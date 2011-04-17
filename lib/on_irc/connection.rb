class IRC
  class Connection < EventMachine::Connection
    include EventMachine::Protocols::LineText2

    def initialize(server)
      @server = server
    end

    ## EventMachine callbacks
    def post_init
      send_data("USER #{@server.ident || @server.irc.ident} * * :#{@server.realname || @server.irc.realname}\r\n")
      send_data("NICK #{@server.nick || @server.irc.nick}\r\n")
      reset_check_connection_timer
    rescue => e
      p e
    end

    def receive_line(line)
      reset_check_connection_timer
      @server.receive_line(RUBY_VERSION < "1.9" ? line : line.force_encoding('utf-8'))
    end

    def unbind
      @check_connection_timer.cancel if @check_connection_timer
      @server.unbind
    end

    private
    def check_connection
      puts "Sending PING to server to verify connection..."
      @server.send_cmd :ping, @server.address
      @check_connection_timer = EM::Timer.new(30, method(:timeout))
    end

    def timeout
      puts "Timed out waiting for server, reconnecting..."
      @server.send_cmd :quit, "Ping timeout"
      close_connection_after_writing
    end

    def reset_check_connection_timer
      @check_connection_timer.cancel if @check_connection_timer
      @check_connection_timer = EM::Timer.new(100, method(:check_connection))
    end
  end
end

