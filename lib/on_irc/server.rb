require File.join(File.dirname(__FILE__), '/user')

class IRC
  class Server
    attr_accessor :config, :connection, :handlers, :name, :irc, :current_nick
    config_accessor :address, :port, :nick, :ident, :realname, :ssl

    def initialize(irc, name, config)
      @irc = irc
      @name = name
      @config = config
      @handlers = {}
      @connected = false
      @current_nick = config.nick || irc.nick
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

    def handle_event(event)
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

      case event.command
        when :'001'
          @connected = true
          @irc.handlers[:connected].call(@irc, event) if @irc.handlers[:connected]
        when :ping
          send_cmd :pong, event.target
        when :'353'
          event.params[2].split(" ").each do |nick|
            nick.slice!(0) if [:~, :&, :'@', :%, :+].include? nick[0].to_sym
            User.new @name, event.params[1], nick unless nick == current_nick
          end
        when :join
          User.new @name, event.channel, event.sender.nick
        when :part, :quit
          User.remove @name, event.channel, event.sender.nick
          User.clear @name, event.channel if event.sender.nick == current_nick
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
