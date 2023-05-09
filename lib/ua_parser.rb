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
end