# frozen_string_literal: true

require_relative "sofetch/version"
require_relative "sofetch/llm"
require_relative "sofetch/page"

require_relative "sofetch/clients/generic"
require_relative "sofetch/clients/direct"
require_relative "sofetch/clients/scrapingbee"

module Sofetch
  class Error < StandardError; end

  # Shortcut method to create a new Page object and fetch it
  def self.[](url)
    obj = Page.new(url)
    obj.fetch
    obj
  end
end
