require 'openai'

module Sofetch
  class LLM
    GPT_MODEL = "gpt-3.5-turbo-0125"
    BETTER_GPT_MODEL = "gpt-4-0125-preview"
    MAX_BYTES_OF_HTML = 32768

    def initialize(page)
      raise ArgumentError, 'Expecting a Sofetch::Page object' unless page.is_a?(Sofetch::Page)

      @page = page

      # If we can't create an OpenAI client, there's no need for this whole class
      begin
        @gpt = OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'), request_timeout: 30)
      rescue
        raise ArgumentError, 'No OpenAI API key'
      end
    end

    def generate_summary_from_metadata(force: false)
      @summary_from_metadata = nil if force
      system_prompt = %{
        Return a JSON object that summarizes the page based upon the
        provided context and metadata. Use these keys in the JSON object:
        - site_name (i.e. the broad name of the site, if any)
        - type (e.g. article, website, error)
        - title (a string, in Title Case, ideally)
        - description
        - author (this can be a string or an array for multiple authors)
        - published_at (in ISO 8601 format)
        - tags (an array of lowercase single word tags, kebab_case is ok)
        Do not include any keys that have no value or an empty string value.
      }.strip
      @summary_from_metadata ||= gpt_call_json(system: system_prompt, prompt: make_page_overview) 
    end

    def generate_summary_from_html(force: false)
      @summary_from_html = nil if force
      system_prompt = %{
        Return a JSON object that best summarizes the page based upon the
        provided HTML. Use these keys in the JSON object:
        - site_name (i.e. the broad name of the site, if any)
        - type (e.g. article, website, error)
        - title (a string, in Title Case, ideally)
        - description
        - author (this can be a string or an array for multiple authors)
        - published_at (in ISO 8601 format)
        - tags (an array of lowercase single word tags, kebab_case is ok)
        Do not include any keys that have no value or an empty string value.
      }.strip
      @summary_from_html ||= gpt_call_json(system: system_prompt, prompt: @page.clean_html[0, MAX_BYTES_OF_HTML]) 
    end

    def generate_summary(force: false)
      @summary = nil if force
      system_prompt = %{
        Return a JSON object that best summarizes the page based upon the
        two provided JSON fragments which are attempted summaries by two
        other people. Use these keys in your JSON object:
        - site_name (i.e. the broad name of the site, if any)
        - type (e.g. article, website, error)
        - title (a string, in Title Case, ideally)
        - description
        - author (this can be a string or an array for multiple authors)
        - published_at (in ISO 8601 format)
        - tags (an array of lowercase single word tags, kebab_case is ok)
        Do not include any keys that have no value or an empty string value.
      }.strip
      @summary ||= gpt_call_json(
        system: system_prompt,
        prompt: generate_summary_from_metadata.to_json + "\n\n" + generate_summary_from_html.to_json,
        model: BETTER_GPT_MODEL
      )
    end

    def generate_quick_summary(force: false)
      @quick_summary = nil if force
      system_prompt = %{
        Return a JSON object that best summarizes the page based upon the
        two provided JSON fragments which are attempted summaries by two
        other people. Use these keys in your JSON object:
        - site_name (i.e. the broad name of the site, if any)
        - type (e.g. article, website, error)
        - title (a string, in Title Case, ideally)
        - description
        - author (this can be a string or an array for multiple authors)
        - published_at (in ISO 8601 format)
        - tags (an array of lowercase single word tags, kebab_case is ok)
        Do not include any keys that have no value or an empty string value.
      }.strip
      @summary ||= gpt_call_json(
        system: system_prompt,
        prompt: make_page_overview + "\n\nHTML: " + @page.clean_html[0, (MAX_BYTES_OF_HTML/2)]
      )
    end

    def make_page_overview
      out = []
      out << "URL: #{@page.url}"
      out << "SITE NAME: #{@page.site_name}" if @page.site_name
      out << "CONTENT TYPE: #{@page.type}" if @page.type
      @page.titles.each do |title|
        out << "POSSIBLE TITLE: #{title}"
      end
      @page.descriptions.each do |description|
        out << "POSSIBLE DESCRIPTION: #{description}"
      end
      @page.authors.each do |author|
        out << "POSSIBLE AUTHOR: #{author}"
      end
      @page.published_at.each do |published_at|
        out << "POSSIBLE DATE: #{published_at}"
      end
      @page.headings.each do |heading|
        out << "HEADING: #{heading}"
      end
      @page.paragraphs.first(3).each.with_index do |paragraph, i|
        out << "PARAGRAPH #{i+1}: #{paragraph}"
      end
      out.join("\n")
    end

    private

    def gpt_call(prompt:, system: nil, model: GPT_MODEL, json: false)
      retries = 3
      messages = []
      messages << { role: "system", content: system } if system
      messages << { role: "user", content: prompt }
      parameters = { model: model, messages: messages }
      parameters[:response_format] = { type: "json_object" } if json

      begin
        response = @gpt.chat(parameters: parameters)
      rescue Net::ReadTimeout
        retries -= 1
        retry if retries > 0
        return nil
      end
      
      response.dig("choices", 0, "message", "content")
    end
    
    def gpt_call_json(prompt:, system: nil, model: GPT_MODEL)
      res = gpt_call(prompt: prompt, system: system, model: model, json: true)
      if res
        return JSON.parse(res)
      else
        return {}
      end
    end
  end
end