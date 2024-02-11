module Sofetch
  class ScrapingbeeClient < GenericClient
    ENDPOINT = 'https://app.scrapingbee.com/api/v1/'

    def request(url:, params: {})
      encoded_url = URI.encode_uri_component(url)

      render_js = params.delete(:render_js)
      screenshot = params.delete(:screenshot)

      params = {
          api_key: ENV['SCRAPINGBEE_API_KEY'],
          url: encoded_url,
          return_page_source: true,
          json_response: true,
          render_js: false,
          timeout: HTTP_TIMEOUT * 1000
      }

      raise ArgumentError, 'No ScrapingBee API key' unless params[:api_key]
      
      params.merge!({
        screenshot: true,
        window_width: 1680,
        window_height: 1050
      }) if screenshot

      params[:render_js] = true if render_js

      uri = URI(ENDPOINT + "?" + params.map{ |k,v| "#{k}=#{v}" }.join('&'))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      req = Net::HTTP::Get.new(uri)
      res = http.request(req)
      status_code = res.code.to_i
      body = res.body
      if res.code == '200' && res.body.start_with?('{')
        body = JSON.parse(res.body)
        body = body.slice('headers', 'type', 'cost', 'initial-status-code', 'resolved-url', 'metadata', 'body')
        body = body.transform_keys(&:to_sym)
        return { code: status_code, success: true }.merge(body)
      end
      
      return { code: status_code, success: false, text: body }
    end
  end
end