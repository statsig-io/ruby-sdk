class URIHelper
  class URIBuilder

    attr_accessor :options

    def initialize(options)
      @options = options
    end

    def build_url(endpoint)
      api = @options.api_url_base
      if endpoint.include?('download_config_specs')
        api = @options.api_url_download_config_specs
      end
      unless api.end_with?('/')
        api += '/'
      end
      "#{api}#{endpoint}"
    end
  end

  def self.initialize(options)
    @uri_builder = URIBuilder.new(options)
  end

  def self.build_url(endpoint)
    @uri_builder.build_url(endpoint)
  end
end
