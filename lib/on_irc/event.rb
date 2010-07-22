class IRC
  class Event
    attr_accessor :server, :sender, :command, :params, :target, :channel

    def initialize(server, prefix, command, target, params)
      @server = server
      @sender = Sender.new(prefix)
      @sender.user = server.user[@sender.nick] if server.users.include? @sender.nick
      @command = command
      @target = target
      @channel = target if target and target[0] == 35
      @params = params
    end


  end
end


module Kernel
 # Like instance_eval but allows parameters to be passed.
  def instance_exec(*args, &block)
    mname = "__instance_exec_#{Thread.current.object_id.abs}_#{object_id.abs}"
    Object.class_eval{ define_method(mname, &block) }
    begin
      ret = send(mname, *args)
    ensure
      Object.class_eval{ undef_method(mname) } rescue nil
    end
    ret
  end
end

