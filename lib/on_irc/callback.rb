class IRC
  class Callback
    def initialize(block)
      @block = block
    end

    def call(irc, event)
      CallbackDSL.run(irc, event, @block)
    end

    class CallbackDSL
      def self.run(irc, event, block)
        callbackdsl = self.new(irc, event)
        block.arity < 1 ? callbackdsl.instance_eval(&block) : block.call(callbackdsl)
      end

      def initialize(irc, event)
        @event = event
        @irc = irc
      end

      # @event accessors
      def sender
        @event.sender
      end

      def command
        @event.command
      end

      def server
        @event.server
      end

      def target
        @event.target
      end

      def channel
        @event.channel
      end

      def params
        @event.params
      end

      # commands
      include Commands

      def send_cmd(cmd, *args)
        @event.server.send_cmd(cmd, *args)
      end

      def respond(*args)
        type = args.first if args.length > 1
        message = args.length > 1 ? args[1] : args.first

        if channel
          reply_cmd = type || @event.server.config.channel_reply_command || :privmsg
          send(reply_cmd, reply_cmd == :notice ? sender.nick : params[0], message)
        else
          send(@event.command == :notice ? :notice : :privmsg, sender.nick, message)
        end
      end
      alias send_reply respond
    end
  end
end

