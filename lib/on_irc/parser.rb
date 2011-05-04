begin
  require 'iconv'
rescue
end

class IRC
  module Parser  
    def self.parse(line)      
      prefix = ''
      command = ''
      params = []
      if const_defined? :Iconv
        ic = ::Iconv.new('UTF-8//IGNORE', 'UTF-8')
        line = ic.iconv(line + ' ')[0..-2]
      end
      msg = StringScanner.new(line)
      
      if msg.peek(1) == ':'
        msg.pos += 1
        prefix = msg.scan /\S+/
        msg.skip /\s+/
      end
      
      command = msg.scan /\S+/
      
      until msg.eos?
        msg.skip /\s+/
        
        if msg.peek(1) == ':'
          msg.pos += 1
          params << msg.rest
          msg.terminate
        else
          params << msg.scan(/\S+/)
        end
      end

      target = params[0]
      params.slice! 0
      
      {:prefix => prefix, :command => command, :target => target, :params => params}
    end
  end
end

