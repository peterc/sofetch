require 'http'

module Sofetch
  class DirectClient < GenericClient
    HTTP_CLIENT = HTTP.headers(:user_agent => "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:102.0) Sofetch/0.1.1").follow(max_hops: 3).timeout(HTTP_TIMEOUT)

    def request(url:, params: {})
      res = HTTP_CLIENT.get(url)
      body = res.body.to_s
      resp = { code: res.code.to_i, success: res.code == 200, body: body }
      resp[:headers] = res.headers.to_h
      resp[:"resolved-url"] = res.uri.to_s
      return resp
    end
  end
end
