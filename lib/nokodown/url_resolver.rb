# frozen_string_literal: true

require "uri"

module Nokodown
  # Resolves hrefs against the page URL (and <base>), tolerating the malformed
  # URLs real pages contain, and shortens them to the address they point at:
  # tracking parameters, click redirectors and image resize options cost
  # tokens and tell a reader nothing.
  class UrlResolver
    # From Ruby 3.4 URI::DEFAULT_PARSER is the RFC 3986 parser, whose unescape is obsolete.
    URI_PARSER = defined?(URI::RFC2396_PARSER) ? URI::RFC2396_PARSER : URI::DEFAULT_PARSER
    TRACKING_PARAM = /\A(?:utm_[a-z_]+|fbclid|gclid|gclsrc|dclid|gbraid|wbraid|msclkid|yclid|igshid|mc_cid|mc_eid|_hsenc|_hsmi|mkt_tok|__s|
                       _gl|_ga|srsltid|trk|icid|cmpid|hsCtaTracking|ref_|pd_rd_[a-z]+|pf_rd_[a-z]+)\z/ix.freeze
    # Amazon session, search-rank and affiliate parameters; on other sites
    # these names can matter (Microsoft fwlinks need linkid).
    AMAZON_PARAM = /\A(?:ref|qid|sr|th|smid|psc|crid|dib|dib_tag|spLa|sprefix|linkCode|linkId|ascsubtag|camp|creative)\z/.freeze
    AMAZON = /\A(?:www\.|smile\.)?amazon\.(?:com?\.)?[a-z]{2,3}\z/i.freeze
    AMAZON_PRODUCT = %r{\A.*?/(?:dp|gp/product|gp/aw/d)/[A-Z0-9]{10}(?![A-Za-z0-9])}.freeze
    # Bestseller links put the session id after the ref segment.
    AMAZON_REF = %r{/ref=[^/]*(?:/\d{3}-\d{7}-\d{7})?\z}.freeze
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
    }xi.freeze
    DESTINATION_PARAM = /\A(?:url|u|murl|q)\z/.freeze
    MAX_REDIRECTS = 3
    # Image CDN size, crop and format options; the default rendition shows the
    # same picture.
    PRESENTATION_PARAM = /\A(?:fit|crop|auto|dpr|fm|fmt|resize|resMode|op_usm|ixlib|impolicy)\z/.freeze
    # Only a number is a size: Google and Bing thumbnails name the image in q.
    SIZE_PARAM = /\A(?:w|h|width|height|q|quality|wid|hei|qlt|imwidth|imheight)\z/.freeze
    NUMBER = /\A\d+(?:[.,]\d+)?\z/.freeze
    EXTENSION = /\.[A-Za-z][A-Za-z0-9]{1,4}\z/.freeze
    # Signed URLs stop working once any parameter changes.
    SIGNATURE_PARAM = /\A(?:s|sig|sign|signature|token|__token__|hdnts|expires|x-amz-[a-z-]+|x-goog-[a-z-]+|key-pair-id|
                        policy|hmac|hash|jwt|itok)\z/ix.freeze
    NEXT_IMAGE = %r{/_(?:next|vercel)/image/?\z}.freeze
    # Cloudinary (on any domain), Forem, Cloudflare and ShortPixel append the
    # original to their path. Screenshot services and web archives do too, but
    # they do not serve the image at that URL.
    FETCH_PROXY = %r{
      \A[^/]*(?:/[\w-]+)?/image/fetch/ |
      \A[^/]*/(?:dynamic|cdn-cgi)/image/ |
      \Asp-ao\.shortpixel\.ai/client/
    }ix.freeze
    EMBEDDED_URL = %r{/(https?(?::|%3A)(?:/|%2F){2}.+)\z}i.freeze
    CDN_CGI_IMAGE = %r{\A/cdn-cgi/image/[^/]+(/.+)\z}.freeze
    PRIVATE_BUCKET = /\Abucketeer-/i.freeze
    WEB_URL = %r{\Ahttps?://}i.freeze
    UNSAFE = %r{[^A-Za-z0-9\-._~:/?#@!$&'()*+,;=%]}.freeze
    # Schemes that run code or open a document built from the URL itself.
    SCRIPT_SCHEME = /\A(?:javascript|vbscript|data):/i.freeze
    # A browser ignores spaces and control characters around a URL, and tabs
    # and line breaks anywhere in it ("java&#9;script:" is "javascript:").
    OUTER_CONTROLS = /\A[\x00-\x20]+|[\x00-\x20]+\z/.freeze

    # The URL a browser would read from an attribute value.
    def self.normalize(href)
      href.to_s.gsub(OUTER_CONTROLS, "").delete("\t\n\r")
    end

    def self.script?(url)
      url.match?(SCRIPT_SCHEME)
    end

    def initialize(url, base_href = nil)
      @base = parse(url)
      href = UrlResolver.normalize(base_href)
      base = join(@base, href) unless href.empty? || UrlResolver.script?(href)
      @base = base if base && !UrlResolver.script?(base.to_s)
      # A page links to the same places many times, and content selection
      # and rendering both resolve every link.
      @links = {}
      @images = {}
      @same_page = {}
    end

    def resolve(href)
      @links.fetch(href) { @links[href.dup.freeze] = absolute(href) { |uri| clean_link(uri) }.freeze }
    end

    def resolve_image(src)
      @images.fetch(src) { @images[src.dup.freeze] = absolute(src) { |uri| clean_image(uri) }.freeze }
    end

    def same_page?(url)
      @same_page.fetch(url) { @same_page[url.dup.freeze] = page_anchor?(url) }
    end

    private

    def page_anchor?(url)
      return false unless @base

      uri = parse(url)
      return false unless uri

      @page ||= strip_fragment(clean_link(@base))
      !uri.fragment.nil? && strip_fragment(uri) == @page
    end

    # Nothing that runs a script, before or after resolving: a <base> could
    # lend its scheme to a relative path.
    def absolute(href)
      href = UrlResolver.normalize(href)
      return if href.empty? || UrlResolver.script?(href)
      return href if href.match?(/\A(?:mailto|tel):/i)

      uri = @base ? join(@base, href) : parse(href)
      url = uri ? yield(uri).to_s : href
      url unless UrlResolver.script?(url)
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

    def clean_link(uri, redirects = 0)
      target = redirect_target(uri) if redirects < MAX_REDIRECTS
      return clean_link(target, redirects + 1) if target
      return clean_amazon(uri) if uri.host.to_s.match?(AMAZON)

      strip_tracking(uri)
    end

    def strip_tracking(uri)
      reject_params(uri) { |key, _| key.match?(TRACKING_PARAM) }
    end

    def redirect_target(uri)
      return unless "#{uri.host}#{uri.path}".match?(REDIRECTOR)

      param_values(uri, DESTINATION_PARAM).map { |value| parse(value) }.find { |target| web?(target) }
    end

    def web?(uri)
      uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
    end

    def clean_amazon(uri)
      product = uri.path[AMAZON_PRODUCT]
      uri = uri.dup
      uri.path = product || uri.path.sub(AMAZON_REF, "")
      return reject_params(uri) { |key, _| key != "tag" } if product

      reject_params(uri) { |key, _| key.match?(TRACKING_PARAM) || key.match?(AMAZON_PARAM) }
    end

    def clean_image(uri)
      return uri if signed_image?(uri)

      embedded = embedded_image(uri)
      return original_image(uri, embedded) if embedded

      proxy?(uri) ? strip_tracking(uri) : strip_presentation(uri)
    end

    def proxy?(uri)
      uri.query.to_s.split("&").any? { |pair| decode(param(pair).last).to_s.match?(WEB_URL) }
    end

    # A proxy needs its options, so it stays whole when its original is unusable
    # or is the proxy itself. The original is not unwrapped in turn, because
    # proxies can point at each other.
    def original_image(proxy, embedded)
      original = join(proxy, embedded) unless embedded.empty?
      return strip_tracking(proxy) unless web?(original) && !same_resource?(original, proxy) && !original.host.match?(PRIVATE_BUCKET)

      signed_image?(original) ? original : strip_presentation(original)
    end

    def same_resource?(uri, other)
      uri.host == other.host && uri.path == other.path
    end

    def strip_presentation(uri)
      extension = uri.path.to_s.match?(EXTENSION)
      reject_params(uri) { |key, value| key.match?(TRACKING_PARAM) || presentation?(key, value, extension) }
    end

    # Twitter media has no file extension and is a 404 without its format.
    def presentation?(key, value, extension)
      return value.match?(NUMBER) if key.match?(SIZE_PARAM)
      return extension if key == "format"

      key.match?(PRESENTATION_PARAM) || (key == "v" && value.match?(/\A\d+\z/))
    end

    def signed_image?(uri)
      uri.query.to_s.split("&").any? { |pair| param(pair).first.match?(SIGNATURE_PARAM) }
    end

    def embedded_image(uri)
      path = uri.path.to_s
      return param_values(uri, /\Aurl\z/).first.to_s if path.match?(NEXT_IMAGE)
      return fetched_image(uri) if "#{uri.host}#{path}".match?(FETCH_PROXY) && path.match?(EMBEDDED_URL)

      original = path[CDN_CGI_IMAGE, 1]
      original && uri.query ? "#{original}?#{uri.query}" : original
    end

    # An encoded original ends where the proxy's query starts. A plain one was
    # split in two by the parser, so that query is the original's own.
    def fetched_image(uri)
      embedded = uri.path[EMBEDDED_URL, 1]
      return unescape(embedded).to_s if embedded.match?(/\Ahttps?%3A/i)

      uri.query ? "#{embedded}?#{uri.query}" : embedded
    end

    def param_values(uri, key)
      params = uri.query.to_s.split("&").map { |pair| param(pair) }
      params.select { |name, _| name.match?(key) }.map { |_, value| decode(value) }.compact
    end

    def param(pair)
      key, value = pair.split("=", 2)
      [key.to_s, value.to_s]
    end

    def decode(value)
      decoded = URI.decode_www_form_component(value)
      decoded if decoded.valid_encoding?
    rescue ArgumentError
      nil
    end

    def unescape(value)
      decoded = URI_PARSER.unescape(value)
      decoded if decoded.valid_encoding?
    end

    def reject_params(uri)
      return uri unless uri.query

      pairs = uri.query.split("&")
      kept = pairs.reject { |pair| yield(*param(pair)) }
      return uri if kept.size == pairs.size

      kept -= [""]
      uri = uri.dup
      uri.query = kept.empty? ? nil : kept.join("&")
      uri
    end

    def strip_fragment(uri)
      uri.to_s.sub(/#.*\z/, "")
    end
  end
end
