# Sofetch - Turn a URL into metadata about the page

*DISCLAIMER: I have written this for personal use so far, hence it not being on the main RubyGems registry yet. If this situation changes, I will publish it properly.*

A library that fetches Web pages (either directly or via ScrapingBee – if an API key is present) and performs analysis upon the contents, both locally and optionally using LLM models, in order to produce useful metadata.

## Installation

```
gem 'sofetch', git: 'https://github.com/peterc/sofetch'
```

## Usage

```ruby
require 'sofetch'
```

```ruby
# Shortcut method
page = Sofetch[url]
```

```ruby
page = Sofetch::Page.new(url)
page.fetch
```

Then:

```ruby
page.to_hash
page.clean_html
page.llm.generate_summary_from_html
page.llm.generate_summary_from_metadata

page.llm.generate_summary  # combines the two above for a richer take
```

## Development

You can run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

As this is currently for me only, it's unlikely contributions would be useful, but if you do have ideas or things to stay, please create an issue - I'll certainly listen! :-)
