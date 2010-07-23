class IRC
  class User
    class DowncasedHash < Hash
      def [](key)
        key = key.to_s.downcase.to_sym if key.is_a? Symbol
        key.respond_to?(:downcase) ? super(key.downcase) : super(key)
      end

      def []=(key, value)
        key = key.to_s.downcase.to_sym if key.is_a? Symbol
        key.respond_to?(:downcase) ? super(key.downcase, value) : super(key, value)
      end

      def delete(key)
        key = key.to_s.downcase.to_sym if key.is_a? Symbol
        key.respond_to?(:downcase) ? super(key.downcase) : super(key)
      end

      def include?(key)
        key = key.to_s.downcase.to_sym if key.is_a? Symbol
        key.respond_to?(:downcase) ? super(key.downcase) : super(key)
      end
    end

    class UsersHash < DowncasedHash
      def [](key)
        return super(key) unless key[0] == 35
        values.find_all { |usr| usr.channel && usr.channel.downcase == key.downcase }
      end

      def include?(nick)
        values.include? nick
      end
    end

    @@users = DowncasedHash[]

    class << self # Class methods
      def [](server, channel_or_nick=nil)
        @@users[server] ||= DowncasedHash[]
        return @@users[server][channel_or_nick] if channel_or_nick and channel_or_nick[0] == 35
        return UsersHash[*@@users[server].values.collect {|h| h.to_a}.flatten] unless channel_or_nick
        UsersHash[*@@users[server].values.collect {|h| h.to_a}.flatten][channel_or_nick]
      end

      def remove(server, channel, nickname)
        @@users[server][channel].delete nickname
      end

      def clear(server, channel=nil)
        @@users[server] = DowncasedHash[] unless channel
        @@users[server][channel] = DowncasedHash[] if channel
      end
    end

    attr_accessor :server, :nickname, :channel
    attr_reader :join_time
    
    def initialize(server, channel, nickname)
      @server = server.to_s.downcase.to_sym
      @channel = channel.downcase
      @nickname = nickname
      @join_time = Time.now
      @attributes = {}
      @@users[@server] ||= DowncasedHash[]
      @@users[@server][@channel] ||= UsersHash[]
      @@users[@server][@channel][@nickname] = self
    end

    def ==(other)
      return @nickname.downcase == other.downcase if other.is_a? String
      super
    end

    def to_s
      "#<IRC::User:#@nickname, @server=#@server @channel=#@channel, @attributes=#{@attributes.inspect}>"
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