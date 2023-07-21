# typed: true
require 'user_agent_parser'

module UAParser
  class Parser
    def initialize
      @ua_parser = UserAgentParser::Parser.new
    end

    def parse_os(*args)
      @ua_parser.parse_os(*args)
    end

    def parse_ua(*args)
      @ua_parser.parse_ua(*args)
    end

    def parse_device(*args)
      @ua_parser.parse_device(*args)
    end
  end

  def self.initialize
    if !@initialize_bg_thread.nil? && @initialize_bg_thread.alive?
      @initialize_bg_thread.kill.join
    end
    @parser = Parser.new
  end

  def self.initialize_async
    if !@initialize_bg_thread.nil? && @initialize_bg_thread.alive?
      @initialize_bg_thread.kill.join
    end
    @initialize_bg_thread = Thread.new { @parser = Parser.new }
    @initialize_bg_thread
  end

  def self.parse_os(*args)
    if @parser.nil?
      initialize
    end
    @parser.parse_os(*args)
  end

  def self.parse_ua(*args)
    if @parser.nil?
      initialize
    end
    @parser.parse_ua(*args)
  end

  def self.parse_device(*args)
    if @parser.nil?
      initialize
    end
    @parser.parse_device(*args)
  end
end
