# frozen_string_literal: true

require "uri"

module Nokodown
  # Resolves hrefs against the page URL (and <base>), tolerating the malformed
  # URLs real pages contain, and shortens them to the address they point at:
  # tracking parameters, click redirectors and image resize options cost
  # tokens and tell a reader nothing.
  class UrlResolver
    TRACKING_PARAM = /\A(?:utm_[a-z_]+|fbclid|gclid|gclsrc|dclid|gbraid|wbraid|msclkid|yclid|igshid|mc_cid|mc_eid|_hsenc|_hsmi|mkt_tok|__s|
                       _gl|_ga|srsltid|trk|icid|cmpid|hsCtaTracking|ref_|pd_rd_[a-z]+|pf_rd_[a-z]+)\z/ix.freeze
    # Amazon session, search-rank and affiliate parameters; on other sites
    # these names can matter (Microsoft fwlinks need linkid).
    AMAZON_PARAM = /\A(?:ref|qid|sr|th|smid|psc|crid|dib|dib_tag|spLa|sprefix|linkCode|linkId|ascsubtag|camp|creative)\z/.freeze
    AMAZON = /(?:\A|\.)amazon\.(?:com?\.)?[a-z]{2,3}\z/.freeze
    AMAZON_PRODUCT = %r{\A.*?/(?:dp|gp/product|gp/aw/d)/[A-Z0-9]{10}}.freeze
    # Click redirectors, as host and path, which carry the destination in a
    # url, u, murl or q parameter.
    REDIRECTOR = %r{
      \A(?:www\.)?google\.(?:com?\.)?[a-z]{2,3}/url\z |
      \A(?:www\.)?youtube\.com/redirect\z |
      \Alm?\.facebook\.com/l\.php\z |
      \.safelinks\.protection\.outlook\.com/?\z |
      \Ago\.(?:skimresources|redirectingat)\.com/?\z |
      \Aredirect\.viglink\.com/?\z |
      \Aclick\.linksynergy\.com/ |
      \A(?:www\.)?avantlink\.com/click\.php\z |
      \A[\w-]+\.(?:pxf|sjv)\.io/c/ |
      \A(?:www\.)?(?:anrdoezrs\.net|dpbolvw\.net|jdoqocy\.com|kqzyfj\.com|tkqlhce\.com)/click- |
      \Asteamcommunity\.com/linkfilter/?\z
    }x.freeze
    DESTINATION_PARAM = /\A(?:url|u|murl|q)\z/.freeze
    # Image CDN size, crop and format options; the default rendition shows the
    # same picture. Signed URLs stop working once any parameter changes.
    PRESENTATION_PARAM = /\A(?:w|h|width|height|q|quality|fit|crop|auto|dpr|fm|format|resize|wid|hei|qlt|fmt|resMode|op_usm|ixlib|
                           imwidth|imheight|impolicy)\z/x.freeze
    SIGNATURE_PARAM = /\A(?:s|sig|sign|signature|token|expires|x-amz-[a-z-]+|key-pair-id|policy|hmac|hash|jwt|itok)\z/i.freeze
    # Image proxies: Next.js and Vercel take the original as ?url=, fetch CDNs
    # (Cloudinary, Cloudflare, Substack) append it to their own path.
    NEXT_IMAGE = %r{/_(?:next|vercel)/image/?\z}.freeze
    EMBEDDED_URL = %r{/(https?(?::|%3A)(?:/|%2F){2}.+)\z}i.freeze
    CDN_CGI_IMAGE = %r{\A/cdn-cgi/image/[^/]+(/.+)\z}.freeze
    UNSAFE = %r{[^A-Za-z0-9\-._~:/?#@!$&'()*+,;=%]}.freeze

    def initialize(url, base_href = nil)
      @base = parse(url)
      href = base_href.to_s.strip
      @base = join(@base, href) || @base if !href.empty? && !href.start_with?("javascript:")
    end

    def resolve(href)
      absolute(href) { |uri| clean_link(uri) }
    end

    def resolve_image(src)
      absolute(src) { |uri| clean_image(uri) }
    end

    def same_page?(url)
      return false unless @base

      uri = parse(url)
      return false unless uri

      @page ||= strip_fragment(clean_link(@base))
      uri.fragment && strip_fragment(uri) == @page
    end

    private

    def absolute(href)
      href = href.to_s.strip.delete("\t\n\r")
      return if href.empty?
      return href if href.match?(/\A(?:mailto|tel|data):/i)

      uri = @base ? join(@base, href) : parse(href)
      uri ? yield(uri).to_s : href
    end

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

    def clean_link(uri)
      target = redirect_target(uri)
      return clean_link(target) if target
      return clean_amazon(uri) if uri.host.to_s.match?(AMAZON)

      reject_params(uri) { |key, _| key.match?(TRACKING_PARAM) }
    end

    def redirect_target(uri)
      return unless "#{uri.host}#{uri.path}".match?(REDIRECTOR)

      target = parse(param_value(uri, DESTINATION_PARAM))
      target if target.is_a?(URI::HTTP) && target.host
    end

    # A product page is /dp/ASIN; the rest of the path and every parameter but
    # the affiliate tag record how the visitor got there.
    def clean_amazon(uri)
      product = uri.path[AMAZON_PRODUCT]
      uri = uri.dup
      uri.path = product || uri.path.sub(%r{/ref=.*\z}, "")
      return reject_params(uri) { |key, _| key != "tag" } if product

      reject_params(uri) { |key, _| key.match?(TRACKING_PARAM) || key.match?(AMAZON_PARAM) }
    end

    def clean_image(uri)
      return uri if signed_image?(uri)

      original = proxied_image(uri)
      return clean_image(original) if original

      reject_params(uri) { |key, value| key.match?(PRESENTATION_PARAM) || (key == "v" && value.match?(/\A\d+\z/)) }
    end

    def signed_image?(uri)
      uri.query.to_s.split("&").any? { |pair| pair.split("=", 2).first.to_s.match?(SIGNATURE_PARAM) }
    end

    def proxied_image(uri)
      path = uri.path.to_s
      original = if path.match?(NEXT_IMAGE)
                   param_value(uri, /\Aurl\z/)
                 elsif path.match?(EMBEDDED_URL)
                   URI::DEFAULT_PARSER.unescape(path[EMBEDDED_URL, 1])
                 else
                   path[CDN_CGI_IMAGE, 1]
                 end
      join(uri, original) if original && !original.empty?
    end

    def param_value(uri, key)
      pair = uri.query.to_s.split("&").find { |candidate| candidate.split("=", 2).first.to_s.match?(key) }
      URI.decode_www_form_component(pair.split("=", 2)[1].to_s) if pair
    rescue ArgumentError
      nil
    end

    # The query without the pairs the block picks, or no query when none are left.
    def reject_params(uri)
      return uri unless uri.query

      pairs = uri.query.split("&").reject do |pair|
        key, value = pair.split("=", 2)
        pair.empty? || yield(key, value.to_s)
      end
      uri = uri.dup
      uri.query = pairs.empty? ? nil : pairs.join("&")
      uri
    end

    def strip_fragment(uri)
      uri.to_s.sub(/#.*\z/, "")
    end
  end
end
