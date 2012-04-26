require File.join(File.dirname(__FILE__), '/user')

class IRC
  class Server
    attr_accessor :config, :connection, :handlers, :name, :irc, :current_nick, :request_who, :bans, :supported, :channels, :ircd
    config_accessor :address, :port, :nick, :ident, :realname, :ssl

    def initialize(irc, name, config)
      @irc = irc
      @name = name
      @config = config
      @handlers = { :identified => {} }
      @connected = false
      @current_nick = config.nick || irc.nick
      @channels = DowncasedHash[]
      @supported = {}
      @who_requests = 0
      @reconnect = true
    end

    def connected?
      @connected
    end

    def channel
      @config.channel
    end

    def user
      User[@name]
    end

    def users(channel=nil)
      User[@name, channel]
    end

    def bans(channel)
      @channels[channel][:bans]
    end

    def send_cmd(cmd, *args)
      # remove nil entries
      args.compact!
      # prepend last arg with : only if it exists. it's really ugly
      args[-1] = ":#{args[-1]}" if args[-1]
      connection.send_data(cmd.to_s.upcase + ' ' + args.join(' ') + "\r\n")
      puts "#{@name} <- #{cmd.to_s.upcase} #{args.join(' ')}".send(Object.const_defined?(:Colorize) ? :light_blue : :to_s) #TODO: move out of irc lib
    end

    # basic IRC commands
    include Commands

    def on(event, &block)
      @handlers[event.to_s.downcase.to_sym] = Callback.new(block)
    end

    def on_identified_update(nick, &block)
      if block
        puts "[on_identified_update] added handler for nick: #{nick}"
        user[nick].handlers[:identified] = block
        return
      end
      @who_requests -= 1
      if @handlers[:identified_update] or @irc.handlers[:identified_update]
        event = Event.new(self, "#{nick}!ident@internal", :identified_update, nick, [])
        (@handlers[:identified_update] || @irc.handlers[:identified_update]).call(@irc, event)
      end
      if user[nick].handlers[:identified]
        puts "[on_identified_update] called handler for nick: #{nick}"
        user[nick].handlers.delete(:identified).call(user[nick])
      end
    end

    def request_who(nick_or_channel)
      if nick_or_channel[0, 1] != '#' and not (usr = user[nick_or_channel])
        return puts "[request_who] skipping request for #{nick_or_channel.inspect}"
      end
      if usr
        if usr.who_request_timer
          usr.who_request_timer.cancel                            #TODO: when too many who_requests are queued (possible netsplit rejoin)
          usr.who_request_timer = nil                             #      stop individual requests and make a channel who request while
        end                                                       #      preserving individual user callbacks
        if @who_requests >= 8
          puts "[request_who] too many requests in progress, delaying who for #{nick_or_channel.inspect} by 5 seconds"
          return usr.who_request_timer = EventMachine::Timer.new(5) { request_who(nick_or_channel) }
        end
      end
      send_cmd :who, nick_or_channel, '%uhna' # extwho support
      @who_requests += 1
      return if nick_or_channel[0, 1] == '#'
      usr.identified_check_count += 1 if ircd =~ /Unreal/
      usr.who_request_timer = EventMachine::Timer.new(7) do
        puts "[request_who] timed out waiting for reply to who for #{nick_or_channel.inspect}"
        unless usr = user[nick_or_channel]
          @who_requests -= 1
          puts "[request_who_timeout] skipping handling because #{nick_or_channel.inspect} no longer exists"
          next
        end
        @who_requests -= 1
        next unless ircd =~ /Unreal/
        if usr.identified_check_count < 4
          request_who(nick_or_channel)
        else
          on_identified_update(nick_or_channel)
          usr.identified_check_count = 1
        end
      end
    end

    def request_whois(nick)
      unless usr = user[nick]
        return puts "[request_whois] skipping request for #{nick.inspect}"
      end

      if usr.whois_request_timer
        usr.whois_request_timer.cancel
        usr.whois_request_timer = nil
      end
      if @who_requests >= 8
        puts "[request_whois] too many requests in progress, delaying whois for #{nick.inspect} by 5 seconds"
        return usr.whois_request_timer = EventMachine::Timer.new(5) { request_whois(nick) }
      end

      send_cmd :whois, nick
      @who_requests += 1

      usr.identified_check_count += 1 if ircd =~ /ircd-seven/
      usr.whois_request_timer = EventMachine::Timer.new(7) do
        puts "[request_whois] timed out waiting for reply to whois for #{nick.inspect}"
        unless usr = user[nick]
          @who_requests -= 1
          puts "[request_whois_timeout] skipping handling because #{nick.inspect} no longer exists"
          next
        end
        @who_requests -= 1
        next unless ircd =~ /ircd-seven/
        if usr.identified_check_count < 4
          request_whois(nick)
        else
          on_identified_update(nick)
        end
      end
    end

    def handle_event(event)
      case event.command
        when :'001'
          @connected = true
          @connect_time = Time.now
          @irc.handlers[:connected].call(@irc, event) if @irc.handlers[:connected]
        when :'004'
          @ircd = event.params[1]
        when :'005' # supported modes
          @supported[:chanmodes] ||= {}
          event.params[0..-2].collect {|p| s = p.split('='); [s[0], s[1] || true]}.each do |param, value|
            case param.downcase.to_sym
              when :cmds
                @supported[:commands] = value.split(',')
              when :chanmodes
                @supported[:chanmodes].merge! Hash[[:address, :param, :set_param, :no_param].zip(value.split(','))]
              when :prefix
                if value =~ /([^()]+)\)(.+)/
                  @supported[:prefixes] = Hash[*$2.chars.to_a.zip($1.chars.to_a).flatten]
                  @supported[:chanmodes][:prefix] = $1
                end
              else
                @supported[param.downcase.to_sym] = Float(value) rescue value
            end
          end
        when :'311' # start of whois
          return unless usr = user[event.params[0]]
          if ircd =~ /ircd-seven/
            usr.identified_as = nil
            usr.identified = false
          end
        when :'315' # end of who
          return unless nick = event.params[0]
          #if usr = user[nick]
          #  usr.identified = modes.include? 'r' if ircd =~ /Unreal/
          #  @who_requests -= 1 if usr.who_request_timer
          #  usr.who_request_timer.cancel if usr.who_request_timer
          #  usr.who_request_timer = nil
          #  return unless ircd =~ /Unreal/
          #  puts "[end_of_who] #{nick.inspect}: identified? #{usr.identified?} identified_check_count=#{usr.identified_check_count.inspect} time_since_join=#{usr.time_since_join.inspect}"
          #  if usr.identified? or usr.identified_check_count >= 4
          #    on_identified_update(nick)
          #  elsif channel and @channels.include?(channel) and not @channels[channel][:synced]
          #    on_identified_update(nick)
          #  else
          #    EM.add_timer(0.5) { request_who(nick) }
          #  end
          #end
          #puts ":315 @channels=#{@channels.inspect}"          @channels[event.params[0]][:synced] = true if event.params[0][0] == 35
        when :'318' # end of whois
          if usr = user[event.params[0]]
            puts "[#{event.params[0].inspect}] identified? #{usr.identified?} identified_check_count=#{usr.identified_check_count.inspect} time_since_join=#{usr.time_since_join.inspect}"
            @who_requests -= 1 if usr.whois_request_timer
            usr.whois_request_timer.cancel if usr.whois_request_timer
            usr.whois_request_timer = nil
            if ircd =~ /ircd-seven/
              if usr.identified? or usr.identified_check_count >= 4
                on_identified_update(event.params[0])
              else
                EM.add_timer(0.5) { request_whois(event.params[0]) }
              end
            end
          end
        when :'330' # whois account
          return unless usr = user[event.params[0]]
          if ircd =~ /ircd-seven/
            usr.identified_as = event.params[1]
            usr.identified = true
          end
        when :'352' # who reply
          channel, username, hostname, server_address, nick, modes, realname = event.params
          if usr = user[nick]
            usr.ident      = username
            usr.hostname   = hostname
            usr.identified = modes.include? 'r'# if ircd =~ /Unreal/
            @who_requests -= 1 if usr.who_request_timer
            usr.who_request_timer.cancel if usr.who_request_timer
            usr.who_request_timer = nil
            #return unless ircd =~ /Unreal/
            puts "[who_reply] #{nick.inspect}: identified? #{usr.identified?} identified_check_count=#{usr.identified_check_count.inspect} time_since_join=#{usr.time_since_join.inspect}"
            if usr.identified? or usr.identified_check_count >= 4
              on_identified_update(nick)
            elsif channel and @channels.include?(channel) and not @channels[channel][:synced]
              on_identified_update(nick)
            else
              EM.add_timer(0.5) { request_who(nick) }
            end
          end
        when :'353' # names
          event.params[2].split(" ").each do |nick|
            mode_prefix = nick.slice!(0) if @supported[:prefixes].include? nick[0, 1]
            unless user.include? nick
              User.new @name, event.params[1], nick
              user[nick].identified_check_count = 0
            else
              user[nick].channels << event.params[1].downcase
            end

            unless channel = @channels[event.params[1]]
              next warn "[on_irc] Channel does not exist: #{event.params[1].inspect}"
            end

            unless user_modes = channel[:user_modes]
              next warn "[on_irc] Channel is missing user modes: #{channel.inspect}"
            end

            user_modes = (user_modes[nick] = [])
            user_modes << @supported[:prefixes][mode_prefix] if mode_prefix
          end
        when :'354' # extwho
          username, hostname, nick, account = event.params
          if usr = user[nick]
            usr.ident        = username
            usr.hostname     = hostname
            usr.identifed_as = account
          end
        when :'366' # end of names
          request_who event.params[0]
        when :'367' # channel ban list entry
          @channels[event.params[0]][:bans][event.params[1]] = event.params[2]
        when :'433' # nickname in use
          @current_nick += '_'
          send_cmd :nick, @current_nick
        when :mode
          if event.channel
            params = event.params.dup
            direction, added = nil, nil
            params.shift.chars.each do |mode|
              if '+-'.include? mode
                added = mode == '+'
              else
                param_modes = @supported[:chanmodes].values_at(:address, :param, :prefix).join
                param_modes << @supported[:chanmodes][:set_param] if direction == 0
                param = param_modes.include?(mode) ? params.shift : nil
                case mode
                  when 'b'
                    if added
                      @channels[event.channel][:bans][param] = event.sender.nick
                    else
                      @channels[event.channel][:bans].delete(param)
                    end
                  when *@supported[:chanmodes][:prefix].split(//)
                    unless channel = @channels[event.channel]
                      next warn "[on_irc] Channel does not exist: #{event.channel}"
                    end
                    next warn "[on_irc] Channel has no user modes: #{event.channel}" unless channel[:user_modes]
                    if added
                      (channel[:user_modes][param] ||= []) << mode
                    else
                      if channel[:user_modes][param]
                        @channels[event.channel][:user_modes][param].delete(mode)
                      end
                    end
                end
              end
            end
          end
        when :ping
          send_cmd :pong, event.target
        when :join
          if event.sender.nick == current_nick
            @channels[event.channel] = { :synced => false, :bans => {}, :user_modes => DowncasedHash.new }
            puts ":join @channels=#{@channels.inspect}"
            send_cmd :mode, event.channel, '+b'
          else
            unless User[@name].include? event.sender.nick
              User.new @name, event.channel, event.sender.nick
              User[@name, event.sender.nick].identified_check_count = 0
            else
              User[@name, event.sender.nick].channels << event.channel.downcase
            end
            #EM.add_timer(0.5) { request_who(event.sender.nick) }
          end
        when :part
          User.remove @name, event.channel, event.sender.nick
          User.clear @name, event.channel if event.sender.nick == current_nick
          @channels[event.channel][:user_modes].delete(nick)
        when :quit
          User[@name, event.sender.nick].channels.each do |channel|
            @channels[channel][:user_modes].delete(event.sender.nick)
          end
          User.remove @name, event.sender.nick
        when :kick
          @channels[event.channel][:user_modes].delete(event.params[0])
          User.remove @name, event.channel, event.params[0]
          User.clear @name, event.channel if event.params[0] == current_nick
        when :nick
          if event.sender.nick == current_nick
            current_nick = event.target
          else
            User[@name, event.sender.nick].channels.each do |channel|
              @channels[channel][:user_modes][event.target] = @channels[channel][:user_modes].delete(event.sender.nick)
            end
            User[@name, event.sender.nick].identified_check_count = 0
            EM.add_timer(0.5) do
              request_who(event.target)
              request_whois(event.target) if ircd =~ /ircd-seven/
            end
          end
          User[@name, event.sender.nick].nickname = event.target
      end

      if @handlers[:all]
        @handlers[:all].call(@irc, event)
      elsif @irc.handlers[:all]
        @irc.handlers[:all].call(@irc, event)
      end

      if @handlers[event.command]
        @handlers[event.command].call(@irc, event)
      elsif @irc.handlers[event.command]
        @irc.handlers[event.command].call(@irc, event)
      end
    end

    def disconnect(message=nil)
      send_cmd(:quit, message) if message && connected?
      @reconnect = false
      connection.close_connection(true)
    end

    # Eventmachine callbacks
    def receive_line(line)
      parsed_line = Parser.parse(line)
      event = Event.new(self, parsed_line[:prefix],
                        parsed_line[:command].downcase.to_sym,
                        parsed_line[:target], parsed_line[:params])
      handle_event(event)
    end

    def unbind
      User.clear @name
      @connected = false
      @supported = {}
      @channels = DowncasedHash[]
      reconnect = lambda {
        next unless @reconnect
        if handler = @handlers[:pre_reconnect] || @irc.handlers[:pre_reconnect]
          handler.call(@irc, Event.new(self, nil, :pre_reconnect, nil, []))
        end
        connection.reconnect(config.address, config.port) rescue return EM.add_timer(3) { reconnect.call }
        connection.post_init
      }
      EM.add_timer(3) { reconnect.call } if @reconnect
    end
  end
end
