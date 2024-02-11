require 'net/http'
require 'net/https'

module Sofetch
  class GenericClient
    HTTP_TIMEOUT = 10  # seconds

    def request(url:, params: {}, client_class: nil)
      url = url.strip
      raise ArgumentError, 'URL is empty' if url.empty?
      raise ArgumentError, 'URL is not valid' unless url.match?(/\A#{URI::DEFAULT_PARSER.make_regexp}\z/)
      
      unless client_class
        client_class = DirectClient
        client_class = ScrapingbeeClient if ENV['SCRAPINGBEE_API_KEY']
      end

      resp = client_class.new.request(url: url, params: params)
      resp[:client_class] = client_class.to_s
      return resp
    rescue StandardError => e
      return { code: 999, success: false, text: e.message, client_class: client_class.to_s}  
    end
  end
end
