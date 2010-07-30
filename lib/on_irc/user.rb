class IRC
  class DowncasedHash < Hash
    def [](key)
      key = key.to_s.downcase.to_sym if key.is_a? Symbol
      key.respond_to?(:downcase) ? super(key.downcase) : super
    end

    def []=(key, value)
      key = key.to_s.downcase.to_sym if key.is_a? Symbol
      key.respond_to?(:downcase) ? super(key.downcase, value) : super
    end

    def delete(key)
      key = key.to_s.downcase.to_sym if key.is_a? Symbol
      key.respond_to?(:downcase) ? super(key.downcase) : super
    end

    def include?(key)
      key = key.to_s.downcase.to_sym if key.is_a? Symbol
      key.respond_to?(:downcase) ? super(key.downcase) : super
    end
  end
  
  class User
    @@users = DowncasedHash[]

    class << self # Class methods
      def [](server, channel_or_nick=nil)
        @@users[server] ||= DowncasedHash[]
        return @@users[server] unless channel_or_nick
        return @@users[server][channel_or_nick] unless channel_or_nick[0] == 35
        @@users[server].reject {|nick, usr| !usr.channels.include? channel_or_nick.downcase }
      end

      def remove(server, channel_or_nick, nickname=nil)
        if nickname and @@users[server][nickname].channels.count > 1
          puts "[IRC::User] Removing #{channel_or_nick.inspect} from #{nickname.inspect}..."
          return @@users[server][nickname].channels.delete(channel_or_nick.downcase)
        end
        nickname = channel_or_nick[0] == 35 ? nickname : channel_or_nick
        puts "[IRC::User] Removing #{nickname.inspect}..."
        @@users[server].delete(nickname.downcase)
      end

      def clear(server, channel=nil)
        puts "[IRC::User] Clearing #{(channel.inspect << "on ") if channel}#{server.inspect}"
        return @@users[server] = DowncasedHash[] unless channel
        channel.downcase!
        @@users[server].delete_if do |nick, usr|
          usr.channels.count == 1 and usr.channels.include? channel
        end
        @@users[server].each do |nick, usr|
          usr.channels.delete(channel) if usr.channels.include? channel
        end
      end
    end

    attr_accessor :server, :channels, :handlers
    attr_reader :join_time, :nickname, :time_since_join
    
    def initialize(server, channel, nickname)
      @server = server.to_s.downcase.to_sym
      @channels = [channel.downcase]
      @nickname = nickname
      @join_time = Time.now
      @attributes = {}
      @handlers = {}
      @@users[@server] ||= DowncasedHash[]
      @@users[@server][@nickname] = self
      puts "[IRC::User] Added #{nickname.inspect} to #{channel.inspect} on #{@server.inspect}."
    end

    def nickname=(nick)
      @@users[@server][nick] = @@users[@server].delete @nickname
      @nickname = nick
    end

    def ==(other)
      other.is_a? String ? @nickname.downcase == other.downcase : super
    end

    def time_since_join
      Time.now - @join_time
    end

    def to_s
      "#<IRC::User:#@nickname, @server=#@server @channel=#@channels, @attributes=#{@attributes.inspect}>"
    end

    def method_missing(method, *args)
      method = method.to_s[0, method.to_s.length-1].to_sym if method.to_s[-1, 1] == "?"
      if method.to_s[-1, 1] == "="
        method = method.to_s[0, method.to_s.length-1].to_sym
        @attributes[method] = args.length > 1 ? args : args.first
      else
        @attributes[method]
      end
    end
  end
end