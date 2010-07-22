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

    @@users = DowncasedHash[]

    class << self # Class methods
      def [](server, channel=nil, nickname=nil)
        @@users[server] ||= DowncasedHash[]
        return DowncasedHash[*@@users[server].values.collect {|h| h.to_a}.flatten] unless channel
        return @@users[server][channel].values unless nickname
        @@users[server][channel][nickname]
      end

      def remove(server, channel, nickname)
        @@users[server][channel].delete nickname
      end

      def clear(server, channel=nil)
        @@users[server] = DowncasedHash[] unless channel
        @@users[server][channel] = DowncasedHash[] if channel
      end
    end

    attr_accessor :server, :nickname
    attr_reader :join_time
    
    def initialize(server, channel, nickname)
      @server = server.to_s.downcase.to_sym
      @channel = channel.downcase
      @nickname = nickname
      @join_time = Time.now
      @attributes = {}
      @@users[@server] ||= DowncasedHash[]
      @@users[@server][@channel] ||= DowncasedHash[]
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