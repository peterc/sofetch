# frozen_string_literal: true

require_relative "sofetch/version"
require 'net/http'
require 'net/https'
require 'json'
require 'nokogiri'

module Sofetch
  class Error < StandardError; end

  def self.[](url)
    obj = Page.new(url)
    obj.fetch
    obj
  end

  class Page
    attr_reader :raw_data
    def initialize(url)
      @url = url
      @raw_data = nil
    end

    def fetch(render_js: false)
      2.times do
        response = Sofetch.scrapingbee_request(url: @url, render_js: render_js)
        if response[:success]
          @raw_data = response
          return true
        elsif response["text"] && response["text"].include?("try with render_js")
          render_js = true
          next
        else
          raise Sofetch::Error, "Failed to fetch page: #{response[:text]}"
        end
      end
    end

    def opengraph
      raise Sofetch::Error, "No data available" unless @raw_data
      @raw_data[:metadata]["opengraph"]&.first
    end

    def metas
      html_document.css("meta").map { |meta|
        [meta.attributes["name"]&.value || meta.attributes["property"]&.value, meta.attributes["content"]&.value]
      }.to_h
    end

    def headings
      html_document.css("h1, h2, h3").map(&:text).compact.uniq.map(&:strip).reject(&:empty?).first(10)
    end

    def paragraphs
      html_document.css("p").map(&:text).map(&:strip).reject(&:empty?)
    end

    def html
      raise Sofetch::Error, "No data available" unless @raw_data && raw_data[:body]
      raw_data[:body]
    end

    def resolved_url
      raw_data[:"resolved-url"]
    end

    def published_at
      raise Sofetch::Error, "No data available" unless @raw_data
      published_ats = []
      published_ats << (opengraph["article:published_time"] || opengraph["og:pubdate"] || opengraph["og:article:published_time"]) if opengraph
      published_ats << metas["article:published_time"] if metas
      if resolved_url && resolved_url[/\d{4}\/\d{2}\/\d{2}/]
        published_ats << resolved_url[/\d{4}\/\d{2}\/\d{2}/]
      end
      published_ats.compact.uniq.map(&:strip)      
    end

    def to_llm
      out = []
      out << "URL: #{@url}"
      out << "SITE NAME: #{site_name}" if site_name
      titles.each do |title|
        out << "POSSIBLE TITLE: #{title}"
      end
      descriptions.each do |description|
        out << "POSSIBLE DESCRIPTION: #{description}"
      end
      authors.each do |author|
        out << "POSSIBLE AUTHOR: #{author}"
      end
      published_at.each do |published_at|
        out << "POSSIBLE DATE: #{published_at}"
      end
      headings.each do |heading|
        out << "HEADING: #{heading}"
      end
      paragraphs.first(3).each.with_index do |paragraph, i|
        out << "PARAGRAPH #{i+1}: #{paragraph}"
      end
      out.join("\n")
    end

    def authors
      raise Sofetch::Error, "No data available" unless @raw_data
      authors = []
      authors << opengraph["article:author"] if opengraph
      authors << metas["author"] if metas
      authors.compact.uniq.map(&:strip)
    end

    def html_document
      Nokogiri::HTML(html)
    end

    def titles
      raise Sofetch::Error, "No data available" unless @raw_data
      titles = []
      titles << opengraph["og:title"] if opengraph
      titles << html_document.at_css("title")&.text if html_document
      titles.compact.uniq.map(&:strip)
    end

    def descriptions
      raise Sofetch::Error, "No data available" unless @raw_data
      descriptions = []
      descriptions << opengraph["og:description"] if opengraph
      descriptions << html_document.at_css("meta[name='description']")&.attributes&.dig("content")&.value if html_document
      descriptions.compact.uniq.map(&:strip)
    end

    def site_name
      return opengraph["og:site_name"].to_s.strip if opengraph
      nil
    end

  end

  SCRAPINGBEE_ENDPOINT = 'https://app.scrapingbee.com/api/v1/'
  
  def self.scrapingbee_request(url:, screenshot: false, render_js: false)
      url = url.strip
      raise ArgumentError, 'URL is empty' if url.empty?
      raise ArgumentError, 'URL is not valid' unless url.match?(/\A#{URI::DEFAULT_PARSER.make_regexp}\z/)

      encoded_url = URI.encode_uri_component(url)

      params = {
          api_key: ENV['SCRAPINGBEE_API_KEY'],
          url: encoded_url,
          return_page_source: true,
          json_response: true,
          render_js: false,
          timeout: 15000
      }

      raise ArgumentError, 'No ScrapingBee API key' unless params[:api_key]
      
      params.merge!({
        screenshot: true,
        window_height: 1050,
        window_width: 1680,
      }) if screenshot

      params[:render_js] = true if render_js

      uri = URI(SCRAPINGBEE_ENDPOINT + "?" + params.map{ |k,v| "#{k}=#{v}" }.join('&'))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      req =  Net::HTTP::Get.new(uri)
      res = http.request(req)
      status_code = res.code.to_i
      body = res.body
      if res.code == '200' && res.body.start_with?('{')
        body = JSON.parse(res.body)
        body = body.slice('headers', 'type', 'cost', 'initial-status-code', 'resolved-url', 'metadata', 'body')
        # Convert keys to symbols
        body = body.transform_keys(&:to_sym)
        return { code: status_code, success: true }.merge(body)
      end
      return { code: status_code, success: false, text: body }
  rescue StandardError => e
      return { code: 999, success: false, text: e.message }
  end
end
