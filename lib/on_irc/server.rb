require File.join(File.dirname(__FILE__), '/user')

class IRC
  class Server
    attr_accessor :config, :connection, :handlers, :name, :irc, :current_nick, :request_who
    config_accessor :address, :port, :nick, :ident, :realname, :ssl

    def initialize(irc, name, config)
      @irc = irc
      @name = name
      @config = config
      @handlers = { :identified => {} }
      @connected = false
      @current_nick = config.nick || irc.nick
      @channels = DowncasedHash[]
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

    def send_cmd(cmd, *args)
      # remove nil entries
      args.compact!
      # prepend last arg with : only if it exists. it's really ugly
      args[-1] = ":#{args[-1]}" if args[-1]
      connection.send_data(cmd.to_s.upcase + ' ' + args.join(' ') + "\r\n")
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
        when :'315'
          @channels[event.params[0]][:synced] = true if event.params[0][0] == 35
        when :'352' # who reply
          if name == :ShadowFire #TODO: replace hardcoded server name with IRCd check
            channel, username, hostname, server_address, nick, modes, realname = event.params
            if usr = user[nick]
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
            nick.slice!(0) if [:~, :&, :'@', :%, :+].include? nick[0].to_sym
            unless User[@name].include? nick
              User.new @name, event.params[1], nick
              User[@name, nick].identified_check_count = 0
            else
              User[@name, nick].channels << channel.downcase
            end
          end
        when :'366' # end of names
          request_who event.params[0]
        when :ping
          send_cmd :pong, event.target
        when :join
          if event.sender.nick == current_nick
            @channels[event.channel] = { :synced => false }
          else
            unless User[@name].include? event.sender.nick
              User.new @name, event.channel, event.sender.nick
              User[@name, event.sender.nick].identified_check_count = 0
            else
              User[@name, event.sender.nick].channels << channel.downcase
            end
            EM.add_timer(0.5) { request_who(event.sender.nick) }
          end
        when :part
          User.remove @name, event.channel, event.sender.nick
          User.clear @name, event.channel if event.sender.nick == current_nick
        when :quit
          User.remove @name, event.sender.nick
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
      #puts parsed_line.inspect
      event = Event.new(self, parsed_line[:prefix],
                        parsed_line[:command].downcase.to_sym,
                        parsed_line[:target], parsed_line[:params])
      handle_event(event)
    end

    def unbind
      User.clear @name
      @connected = false
      EM.add_timer(3) do
        connection.reconnect(config.address, config.port)
        connection.post_init
      end
    end
  end
end
