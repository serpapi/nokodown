# frozen_string_literal: true

require "uri"

module Nokodown
  # Resolves hrefs against the page URL (and <base>), tolerating the malformed
  # URLs real pages contain, and drops click-tracking query parameters.
  class UrlResolver
    TRACKING_PARAM = /\A(?:utm_[a-z_]+|fbclid|gclid|gclsrc|dclid|gbraid|wbraid|msclkid|yclid|igshid|mc_cid|mc_eid|_hsenc|_hsmi|mkt_tok|__s)\z/i.freeze
    UNSAFE = %r{[^A-Za-z0-9\-._~:/?#@!$&'()*+,;=%]}.freeze

    def initialize(url, base_href = nil)
      @base = parse(url)
      href = base_href.to_s.strip
      @base = join(@base, href) || @base if !href.empty? && !href.start_with?("javascript:")
    end

    def resolve(href)
      href = href.to_s.strip.delete("\t\n\r")
      return if href.empty?
      return href if href.match?(/\A(?:mailto|tel|data):/i)

      uri = @base ? join(@base, href) : parse(href)
      return href unless uri

      strip_tracking(uri).to_s
    end

    def same_page?(url)
      return false unless @base

      uri = parse(url)
      return false unless uri

      uri.fragment && strip_fragment(uri) == strip_fragment(@base)
    end

    private

    def parse(url)
      return if url.nil? || url.to_s.strip.empty?

      URI.parse(encode(url.to_s.strip))
    rescue URI::Error, ArgumentError
      nil
    end

    def join(base, href)
      return parse(href) unless base

      base.merge(encode(href))
    rescue URI::Error, ArgumentError
      nil
    end

    def encode(string)
      string.gsub(UNSAFE) { |char| char.bytes.map { |byte| format("%%%02X", byte) }.join }
    end

    def strip_tracking(uri)
      return uri unless uri.query && uri.query.match?(/(?:\A|&)(?:utm_|fbclid|gclid|gclsrc|dclid|gbraid|wbraid|msclkid|yclid|igshid|mc_|_hs|mkt_tok|__s)/i)

      params = uri.query.split("&").reject { |pair| pair.split("=", 2).first.to_s.match?(TRACKING_PARAM) }
      uri = uri.dup
      uri.query = params.empty? ? nil : params.join("&")
      uri
    end

    def strip_fragment(uri)
      uri.to_s.sub(/#.*\z/, "")
    end
  end
end
