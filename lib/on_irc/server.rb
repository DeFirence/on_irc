require File.join(File.dirname(__FILE__), '/user')

class IRC
  class Server
    attr_accessor :config, :connection, :handlers, :name, :irc, :current_nick, :request_who, :bans, :supported
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
      puts "#{@name} <- #{cmd.to_s.upcase} #{args.join(' ')}"
    end

    # basic IRC commands
    include Commands

    def on(event, &block)
      @handlers[event.to_s.downcase.to_sym] = Callback.new(block)
    end

    def on_identified_update(nick, &block)
      if block
        puts "[on_identified_update] added handler for nick: #{nick}"
        User[@name, nick].handlers[:identified] = block
        return
      end
      if @handlers[:identified_update] or @irc.handlers[:identified_update]
        event = Event.new(self, "#{nick}!ident@internal", :identified_update, nick, [])
        (@handlers[:identified_update] || @irc.handlers[:identified_update]).call(@irc, event)
      end
      if User[@name, nick].handlers[:identified]
        puts "[on_identified_update] called handler for nick: #{nick}"
        User[@name, nick].handlers.delete(:identified).call(User[@name, nick])
      end
    end

    def request_who(nick_or_channel)
      if nick_or_channel[0] != 35 and not (usr = user[nick_or_channel])
        return puts "[request_who] skipping request for #{nick_or_channel.inspect}"
      end
      send_cmd :who, nick_or_channel
      return if nick_or_channel[0] == 35
      usr.identified_check_count += 1
      usr.who_request_timer = EventMachine::Timer.new(7) do
        puts "[request_who] timed out waiting for reply to who for #{nick_or_channel.inspect}"
        unless usr = user[nick_or_channel]
          puts "[request_who_timeout] skipping handling because #{nick_or_channel.inspect} no longer exists"
          next
        end
        if usr.identified_check_count < 4
          request_who(nick_or_channel)
        else
          on_identified_update(nick_or_channel)
        end
      end
    end

    def handle_event(event)
      case event.command
        when :'001'
          @connected = true
          @connect_time = Time.now
          @irc.handlers[:connected].call(@irc, event) if @irc.handlers[:connected]
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
        when :'315'
          p event if event.params[0].nil? #debug
          @channels[event.params[0]][:synced] = true if event.params[0][0] == 35
        when :'352' # who reply
          if name == :ShadowFire #TODO: replace hardcoded server name with IRCd check
            channel, username, hostname, server_address, nick, modes, realname = event.params
            if usr = user[nick]
              usr.ident      = username
              usr.hostname   = hostname
              usr.identified = modes.include? 'r'
              puts "User[#{nick.inspect}] identified? #{usr.identified?} identified_check_count=#{usr.identified_check_count.inspect} time_since_join=#{usr.time_since_join.inspect}"
              usr.who_request_timer.cancel if usr.who_request_timer
              if usr.identified? or usr.identified_check_count >= 4
                on_identified_update(nick)
              elsif channel and @channels.include?(channel) and not @channels[channel][:synced]
                on_identified_update(nick)
              else
                EM.add_timer(0.5) { request_who(nick) }
              end
            end
          end
        when :'353' # names
          event.params[2].split(" ").each do |nick|
            nick.slice!(0) if [:~, :&, :'@', :%, :+].include? nick[0, 1].to_sym
            unless User[@name].include? nick
              User.new @name, event.params[1], nick
              User[@name, nick].identified_check_count = 0
            else
              User[@name, nick].channels << event.params[1].downcase
            end
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
                case mode.to_sym
                  when :b
                    if added
                      @channels[event.channel][:bans][param] = event.sender.nick
                    else
                      @channels[event.channel][:bans].delete(param)
                    end
                end
              end
            end
          end
        when :ping
          send_cmd :pong, event.target
        when :join
          if event.sender.nick == current_nick
            @channels[event.channel] = { :synced => false, :bans => {} }
            send_cmd(:mode, event.channel, '+b')
          else
            unless User[@name].include? event.sender.nick
              User.new @name, event.channel, event.sender.nick
              User[@name, event.sender.nick].identified_check_count = 0
            else
              User[@name, event.sender.nick].channels << event.channel.downcase
            end
            EM.add_timer(0.5) { request_who(event.sender.nick) }
          end
        when :part
          User.remove @name, event.channel, event.sender.nick
          User.clear @name, event.channel if event.sender.nick == current_nick
        when :quit
          User.remove @name, event.sender.nick
        when :kick
          User.remove @name, event.channel, event.params.first
          User.clear @name, event.channel if event.params.first == current_nick
        when :nick
          if event.sender.nick == current_nick
            current_nick = event.target
          else
            User[@name, event.sender.nick].identified_check_count = 0
            EM.add_timer(0.5) { request_who(event.target) }
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
      reconnect_after_3_seconds = lambda {
        EM.add_timer(3) { reconnect.call }
      }
      reconnect = lambda {
        if handler = @handlers[:pre_reconnect] || @irc.handlers[:pre_reconnect]
          handler.call(@irc, Event.new(self, nil, :pre_reconnect, nil, []))
        end
        connection.reconnect(config.address, config.port) rescue return reconnect_after_3_seconds
        connection.post_init
      }
      reconnect_after_3_seconds
    end
  end
end
