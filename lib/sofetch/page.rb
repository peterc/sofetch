require 'json'
require 'nokogiri'

module Sofetch
  class Page
    attr_reader :raw_data, :url
    def initialize(url)
      @url = url
      @raw_data = nil
    end

    def llm
      @llm ||= Sofetch::LLM.new(self)
    end

    def fetch(render_js: false)
      2.times do
        response = Sofetch::GenericClient.new.request(url: @url, params: { render_js: render_js })
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

    def to_hash
      @hash ||= {
        url: @url,
        site_name: site_name,
        titles: titles,
        descriptions: descriptions,
        authors: authors,
        type: type,
        opengraph: opengraph,
        metas: metas,
        headings: headings,
        paragraphs: paragraphs,
        resolved_url: resolved_url,
        feeds: feeds,
        published_at: published_at,
        html: html
      }
    end

    def opengraph
      raise Sofetch::Error, "No data available" unless @raw_data
      @opengraph ||= @raw_data[:metadata]["opengraph"]&.first
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
      html_document.css("p").map(&:text).map(&:strip).reject(&:empty?).first(10)
    end

    def html
      raise Sofetch::Error, "No data available" unless @raw_data && raw_data[:body]
      raw_data[:body]
    end

    def resolved_url
      raw_data[:"resolved-url"]
    end

    def feeds
      raise Sofetch::Error, "No data available" unless @raw_data
      feeds = []
      feeds << html_document.at_css("link[type='application/rss+xml']")&.attributes&.dig("href")&.value
      feeds << html_document.at_css("link[type='application/atom+xml']")&.attributes&.dig("href")&.value
      feeds << html_document.css("a").map { |a| a.attributes["href"]&.value }.compact.find { |href| href&.match?(/rss|feed/) }
      # If any of the feeds are relative, make them absolute
      feeds.map! { |feed| URI.join(resolved_url, feed).to_s if feed }
      feeds.compact.uniq.map(&:strip)
    end

    def published_at
      raise Sofetch::Error, "No data available" unless @raw_data
      published_ats = []
      published_ats << (opengraph["article:published_time"] || opengraph["og:pubdate"] || opengraph["og:article:published_time"]) if opengraph
      published_ats << metas["article:published_time"] if metas
      if resolved_url && resolved_url[/\d{4}\/\d{2}\/\d{2}/]
        published_ats << resolved_url[/\d{4}\/\d{2}\/\d{2}/]
      end
      published_ats << html_document.at_css("[class*='date'], [id*='date'], time[datetime]")&.text
      published_ats << html_document.at_css("time[itemprop='datePublished']")&.attributes&.dig("datetime")&.value
      published_ats.compact.uniq.map(&:strip)      
    end

    def authors
      raise Sofetch::Error, "No data available" unless @raw_data
      authors = []
      authors << opengraph["article:author"] if opengraph
      authors << metas["author"] if metas
      authors << html_document.at_css(".p-author")&.text
      authors << html_document.at_css("meta[name='citation_author']")&.attributes&.dig("content")&.value
      authors += html_document.css("a[rel='author']").map(&:text)
      authors.compact.uniq.map(&:strip)
    end

    def html_document
      @html_document ||= Nokogiri::HTML(html)
    end

    def clean_html_document
      html_document.css("script, style").remove
      # Remove all elements that have a hidden attribute
      html_document.css("[hidden]").remove
      # Remove all elements with style attributes that contain display: none
      html_document.css("[style*='display: none']").remove
      # Remove all comments
      html_document.xpath("//comment()").remove
      # Remove all DIV, LI, SPAN and P elements that are empty
      html_document.css("div, li, span, p").each do |el|
        el.remove if el.text.strip.empty?
      end

      # Remove all these elements which tend to not have content
      html_document.css("style, link, script, aside, button, svg, label, nav, textarea, noscript, iframe, form, input, img, image, select, option, picture, figure, figcaption, menu").remove

      # Remove the <footer> element if its content is >1K in size
      html_document.css("footer").each do |el|
        el.remove if el.text.size > 1000
      end

      # Remove elements with these IDs ['header', 'footer', 'site-header', 'site-footer', 'cookie-banner', 'outdated']
      html_document.css("#header, #footer, #site-header, #site-footer, #cookie-banner, #outdated").remove

      # Remove elements with these classes ['message-bar', 'tag', 'adwrap', 'sidebar']
      html_document.css(".message-bar, .tag, .adwrap, .sidebar").remove

      # To reduce size, clear all element class attributes that are
      # longer than 20 characters in all
      html_document.css("*").each do |el|
        el.remove_attribute("class") if el.attributes["class"]&.value&.size.to_i > 20
        el.remove_attribute("data")
      end

      # Remove all elements that have classes or IDs containing certain words that imply they are not content
      partial_class_names = ['related', 'cookie', 'consent', 'sticky', 'share', 'sr-only']
      partial_class_names.each do |partial_class_name|
        html_document.css("*[class*='#{partial_class_name}']").remove
      end

      # Remove head tags
      html_document.css("head").remove

      # Remove all span tags but keep the content
      html_document.css("span").each do |el|
        el.replace(el.text)
      end

      # Remove all block elements that are almost entirely made up of <a> elements
      html_document.css("div, article, aside, p").each do |el|
        next if el.text.size < 100
        a_count = el.css("a").size
        if a_count > 4 && a_count > el.text.size / 10
          el.remove
        end
      end

      # Remove all 'text' elements that are just whitespace
      html_document.xpath("//text()").each do |el|
        el.remove if el.text.strip.empty?
      end

      # Remove all attributes that are not href, rel, src, alt, title, class, id, name, type
      html_document.css("*").each do |el|
        el.attributes.each do |name, attr|
          el.remove_attribute(name) unless %w(href rel src alt title class id name type).include?(name)
        end
      end

      # Remove any doctypes
      html_document.xpath("//comment()").each do |el|
        el.remove if el.text.strip.start_with?("<!DOCTYPE")
      end
      
      # Remove all elements that contain no other elements and have no text
      html_document.css("*").each do |el|
        next if el.text.gsub(/[^A-Za-z0-9]/, '').size > 4
        next if el.children.size > 0
        el.remove
      end

      html_document
    end

    def clean_html
      d = clean_html_document.to_html
      d.gsub!(/\s+/, " ")
      d.gsub!(/\n+/, "\n")
      d.gsub!(/>\s+</, "><")
      d.gsub!("<!DOCTYPE html>", "")
      d
    end

    def type
      return metas["og:type"] if metas
      return opengraph["og:type"] if opengraph
      nil
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
      descriptions << metas["og:description"] if metas
      descriptions << html_document.at_css("meta[name='description']")&.attributes&.dig("content")&.value if html_document
      descriptions.compact.uniq.map(&:strip)
    end

    def site_name
      if opengraph
        name = opengraph["og:site_name"].to_s.strip
        return name unless name.empty?
      end

      if metas
        name = metas["og:site_name"].to_s.strip
        return name unless name.empty?
      end

      nil
    end
  end
end