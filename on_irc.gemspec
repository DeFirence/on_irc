# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run the gemspec command
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{on_irc}
  s.version = "2.1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Scott Olson"]
  s.date = %q{2010-01-19}
  s.description = %q{An event driven IRC library with an easy to use DSL}
  s.email = %q{scott@scott-olson.org}
  s.extra_rdoc_files = [
    "LICENSE"
  ]
  s.files = [
    "LICENSE",
     "Rakefile",
     "VERSION",
     "lib/on_irc.rb",
     "lib/on_irc/callback.rb",
     "lib/on_irc/commands.rb",
     "lib/on_irc/config.rb",
     "lib/on_irc/config_accessor.rb",
     "lib/on_irc/connection.rb",
     "lib/on_irc/dsl_accessor.rb",
     "lib/on_irc/event.rb",
     "lib/on_irc/parser.rb",
     "lib/on_irc/sender.rb",
     "lib/on_irc/server.rb"
  ]
  s.homepage = %q{http://github.com/tsion/on_irc}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.5}
  s.summary = %q{An event driven IRC library with an easy to use DSL}
  s.test_files = [
    "examples/regex_bot.rb",
     "examples/relay.rb",
     "examples/bot.rb"
  ]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<eventmachine>, [">= 0"])
    else
      s.add_dependency(%q<eventmachine>, [">= 0"])
    end
  else
    s.add_dependency(%q<eventmachine>, [">= 0"])
  end
end

