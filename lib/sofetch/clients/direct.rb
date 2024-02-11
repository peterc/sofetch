require 'http'

module Sofetch
  class DirectClient < GenericClient
    HTTP_CLIENT = HTTP.follow(max_hops: 3).timeout(HTTP_TIMEOUT)

    def request(url:, params: {})
      res = HTTP_CLIENT.get(url)
      body = res.body.to_s
      resp = { code: res.code.to_i, success: res.code == 200, body: body }
      resp[:headers] = res.headers.to_h
      return resp
    end
  end
end
