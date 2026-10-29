# frozen_string_literal: true

require "json"

module Nokodown
  # Title, byline, excerpt, site name, publish date and language, from JSON-LD,
  # <meta> tags and the document, in Readability's order of preference. Runs
  # before the document is cleaned.
  class Metadata
    ARTICLE_TYPES = /\A(?:Article|AdvertiserContentArticle|NewsArticle|AnalysisNewsArticle|AskPublicNewsArticle|BackgroundNewsArticle|OpinionNewsArticle|ReportageNewsArticle|ReviewNewsArticle|Report|SatiricalArticle|ScholarlyArticle|MedicalScholarlyArticle|SocialMediaPosting|BlogPosting|LiveBlogPosting|DiscussionForumPosting|TechArticle|APIReference)\z/.freeze
    PRODUCT_TYPES = /\A(?:Product|ProductGroup|IndividualProduct|Offer|SoftwareApplication|MobileApplication|Book|Vehicle)\z/.freeze
    MICRODATA_FORUM = "[itemtype*='schema.org/DiscussionForumPosting']:not([itemprop]), " \
                      "[itemtype*='schema.org/DiscussionForumPosting'][itemprop~=mainEntity]"
    FORUM_GENERATOR = /\A\s*(?:Discourse|XenForo|vBulletin|phpBB|Invision|Vanilla|NodeBB|Flarum|MyBB)/i.freeze

    PROPERTY = /\s*(article|dc|dcterm|og|twitter)\s*:\s*(author|creator|description|published_time|title|site_name|type)\s*/i.freeze
    NAME = /\A\s*(?:(dc|dcterm|og|twitter|parsely|weibo:(?:article|webpage))\s*[-.:]\s*)?(author|creator|pub-date|description|title|site_name|application-name)\s*\z/i.freeze

    TITLE_SEPARATORS = '\|\-–—\\\/>»'
    SEPARATOR = /\s[#{TITLE_SEPARATORS}]\s/.freeze
    HIERARCHY_SEPARATOR = %r{\s[\\/>»]\s}.freeze
    SITE_NAME_SEPARATOR = "[#{TITLE_SEPARATORS}:·•]"
    WORD = /[\p{L}\p{N}]+/.freeze
    CLOSING = /\A[?!.)\]"'”’）」』】》]*/.freeze
    HEADING_END = /\G(?:\s[-–—]\s|\s*[|:·•,]|#{SiteName::UNDERSCORE})/.freeze
    HOME_LINK = %r{\A(?:(?:https?:)?//[^/?#]+)?/?(?:index\.[a-z]+|[a-z]{2}(?:[-_][a-z]{2})?/?)?(?:[?#].*)?\z}i.freeze
    LOGO_NAME = /logo|brand|site[-_]?(?:title|name)/i.freeze
    SITE_LOGO_NAME = /logo|site[-_]?(?:title|name)/i.freeze
    SCRIPT_QUERY = /index\.[a-z]+\?/i.freeze
    ENTITY = /&(?:#\d+|#x\h+|[a-z][a-z\d]*);/i.freeze

    TITLE_KEYS = %w[dc:title dcterm:title og:title weibo:article:title weibo:webpage:title title twitter:title parsely-title].freeze
    BYLINE_KEYS = %w[dc:creator dcterm:creator author parsely-author].freeze
    EXCERPT_KEYS = %w[dc:description dcterm:description og:description weibo:article:description weibo:webpage:description description twitter:description].freeze

    def initialize(doc, url = nil)
      @doc = doc
      @url = url
      @url_words = UrlWords.new(url)
    end

    def to_h
      documents = json_ld_documents
      json = json_ld(documents)
      meta = meta_values
      site_name = clean(json[:site_name] || meta["og:site_name"] || meta["application-name"])
      site = SiteName.new(@url, [site_name, meta["application-name"]] + logo_names)
      title = page_title(clean(json[:title] || first_value(meta, TITLE_KEYS)), site_name, site)
      {
        title: title && heading_title(title, site),
        site: site,
        url_words: @url_words,
        byline: clean(json[:byline] || first_value(meta, BYLINE_KEYS) || article_author(meta)) || document_byline,
        excerpt: clean(json[:excerpt] || first_value(meta, EXCERPT_KEYS)),
        site_name: site_name,
        published_time: clean(json[:published_time] || meta["article:published_time"] || meta["parsely-pub-date"] || document_published_time),
        lang: clean(@doc.root&.[]("lang")) || clean(@doc.at_css("meta[http-equiv='content-language'], meta[http-equiv='Content-Language']")&.[]("content")),
        page_type: discussion_type(documents) || json[:type] || og_type(meta)
      }
    end

    private

    def first_value(meta, keys)
      keys.map { |key| meta[key] }.compact.first
    end

    def json_ld_documents
      @doc.css("script[type='application/ld+json']").map { |script| parse_json(script.content) }
    end

    def json_ld(documents)
      items = documents.flat_map { |document| flatten(document) }
      article = items.find { |item| types(item).any? { |type| type.match?(ARTICLE_TYPES) } }
      return article_fields(article).merge(type: :article) if article

      product = items.find { |item| types(item).any? { |type| type.match?(PRODUCT_TYPES) } }
      product ? { title: string(product["name"]), type: :product } : {}
    end

    def parse_json(content)
      JSON.parse(content.sub(/\A\s*<!\[CDATA\[/, "").sub(/\]\]>\s*\z/, ""))
    rescue JSON::ParserError
      nil
    end

    def flatten(node)
      case node
      when Array then node.flat_map { |item| flatten(item) }
      when Hash then [node] + (node["@graph"].is_a?(Array) ? flatten(node["@graph"]) : [])
      else []
      end
    end

    def types(item)
      Array(item["@type"]).grep(String)
    end

    # Threads and Q&A pages, whose replies are content. Takes precedence over
    # the article types, since a thread declares its opening post as a
    # DiscussionForumPosting, often under mainEntity. A posting nested deeper,
    # such as an article's reader comments, does not make the page a thread.
    def discussion_type(documents)
      items = documents.flat_map { |document| flatten(document) }
      declared = (items + items.flat_map { |item| flatten(item["mainEntity"]) }).flat_map { |item| types(item) }
      return :qa if declared.include?("QAPage") || @doc.at_css("[itemtype*='schema.org/QAPage']")

      forum = declared.include?("DiscussionForumPosting") || @doc.at_css(MICRODATA_FORUM)
      :forum if forum || forum_generator?
    end

    def forum_generator?
      @doc.css("meta[name=generator]").any? { |meta| meta["content"].to_s.match?(FORUM_GENERATOR) }
    end

    def article_fields(item)
      {
        title: article_title(string(item["name"]), string(item["headline"])),
        byline: authors(item["author"]),
        excerpt: string(item["description"]),
        site_name: item["publisher"].is_a?(Hash) ? string(item["publisher"]["name"]) : nil,
        published_time: string(item["datePublished"])
      }
    end

    # Some sites put their own name in "name" and the title in "headline":
    # prefer whichever matches the <title>.
    def article_title(name, headline)
      return name || headline unless name && headline && name != headline

      title = document_title.to_s
      Dom.similarity(headline, title) > 0.75 && Dom.similarity(name, title) <= 0.75 ? headline : name
    end

    def authors(value)
      value = [value] if value.is_a?(Hash)
      names = Array(value).map { |author| author.is_a?(Hash) ? string(author["name"]) : string(author) }.compact
      names.reject! { |name| name.match?(%r{\Ahttps?://}) }
      names.empty? ? nil : names.join(", ")
    end

    def string(value)
      value = value.first if value.is_a?(Array)
      value.is_a?(String) && !value.strip.empty? ? value.strip : nil
    end

    def meta_values
      @doc.css("meta").each_with_object({}) do |meta, values|
        content = meta["content"].to_s.strip
        next if content.empty?

        if (property = meta["property"].to_s[PROPERTY])
          values[property.downcase.delete(" \t\n")] = content
        elsif (name = meta["name"].to_s).match?(NAME)
          values[name.downcase.delete(" \t\n").tr(".", ":")] = content
        end
      end
    end

    def article_author(meta)
      author = meta["article:author"]
      author unless author.to_s.match?(%r{\Ahttps?://})
    end

    def og_type(meta)
      type = meta["og:type"].to_s.downcase
      return :article if type.start_with?("article")

      :product if type.include?("product")
    end

    # Readability's <title> heuristics: drop the site name around a separator
    # unless that leaves too few words.
    def document_title
      original = Dom.squish((@doc.at_css("head title") || @doc.at_css("title"))&.content.to_s)
      title = Dom.squish(shortened_title(original))
      keep_original = words(title) <= 4 &&
                      (!original.match?(HIERARCHY_SEPARATOR) || words(title) != words(original.gsub(SEPARATOR, "")) - 1)
      title = original if keep_original
      title.empty? ? nil : title
    end

    def shortened_title(original)
      if original.match?(SEPARATOR)
        without_last_part(original)
      elsif original.include?(": ")
        after_colon(original)
      elsif original.length > 150 || original.length < 15
        h1s = @doc.css("h1")
        h1s.size == 1 ? Dom.text(h1s.first) : original
      else
        original
      end
    end

    def without_last_part(original)
      last_separator = original.enum_for(:scan, SEPARATOR).map { Regexp.last_match.begin(0) }.last
      title = original[0...last_separator]
      words(title) < 3 ? original.sub(/\A[^#{TITLE_SEPARATORS}]*[#{TITLE_SEPARATORS}]/, "") : title
    end

    def after_colon(original)
      return original if @doc.css("h1, h2").any? { |heading| Dom.text(heading) == original }

      title = original[(original.rindex(":") + 1)..]
      return original[(original.index(":") + 1)..] if words(title) < 3
      return original if words(original[0...original.index(":")]) > 5

      title
    end

    def words(string)
      string.split(/\s+/).size
    end

    def strip_site_name(title, site_name)
      return title if title.nil? || site_name.nil? || title.casecmp?(site_name)

      escaped = Regexp.escape(site_name)
      stripped = title.sub(/\s*#{SITE_NAME_SEPARATOR}\s*#{escaped}\s*\z/i, "").sub(/\A\s*#{escaped}\s*#{SITE_NAME_SEPARATOR}\s*/i, "")
      stripped.empty? ? title : stripped
    end

    # A declared title that only names the site gives way to the <title>,
    # which may name the page as well, except on the home page. Site names
    # are dropped before Readability's cut, which keeps the start of
    # "Site » Section » Page".
    def page_title(declared, site_name, site)
      title = site.without(strip_site_name(declared, site_name)) if declared && (site.home? || !site.name?(declared))
      return title if title

      document = document_page_title(site_name, site)
      document && (declared.nil? || !site.name?(document)) ? document : declared
    end

    def document_page_title(site_name, site)
      original = Dom.squish((@doc.at_css("head title") || @doc.at_css("title"))&.content.to_s)
      title = site.without(strip_site_name(original, site_name))
      title == original ? strip_site_name(document_title, site_name) : title
    end

    # Taken for the site's name, a logo needs more than a "brand" class,
    # which font and colour utilities share ("font-family-ua-brand").
    def logo_names
      @doc.css("body h1").select { |h1| logo?(h1, SITE_LOGO_NAME) }.map { |h1| Dom.text(h1) }
    end

    # SEO titles wrap the page's name in sections, site names and keywords
    # ("Using the Fetch API - Web APIs | MDN"); the H1s tell which part it is.
    def heading_title(title, site)
      h1s = @doc.css("body h1")
      title_from_h1(title, h1s, site) || title_without_site_h1(title, h1s) || h1_named_by_url(title, h1s) || title
    end

    # An H1 that the page's URL names, when the title does not, is the
    # page's own name: such a title is stale or the same on every page.
    def h1_named_by_url(title, h1s)
      name = h1s.reject { |h1| logo?(h1) }.map { |h1| Dom.text(h1) }.max_by { |text| @url_words.coverage(text) }
      name if name && @url_words.prefers?(name, title)
    end

    # Cut only at a separator, or before the site's name: an H1 that is just
    # the first words of a longer name ("Trail Running" in "Trail Running
    # Shoes for Women") says less than the title. A logo H1 names the site,
    # not the page.
    def title_from_h1(title, h1s, site)
      matches = title.enum_for(:scan, WORD).map { Regexp.last_match }
      title_words = matches.map { |match| match[0].downcase }
      h1s.each do |h1|
        h1_words = tokens(h1.content)
        next if h1_words.empty? || h1_words.size >= title_words.size || title_words.first(h1_words.size) != h1_words
        next if logo?(h1)

        cut = matches[h1_words.size - 1].end(0)
        closing = title[cut..][CLOSING]
        from = cut + closing.length
        return title[0, cut] + closing if title.match?(HEADING_END, from) || site.ending?(title[from..])
      end
      nil
    end

    # mdBook and similar generators end every page's title with the book's
    # name, which their menu bar shows as an H1. "Site | Page" titles end
    # with the page's H1 too, so the part kept must be a heading of the page,
    # not of the site, and of at least 3 words, as in without_last_part.
    def title_without_site_h1(title, h1s)
      separator = title.enum_for(:scan, SEPARATOR).map { Regexp.last_match }.last
      return if separator.nil?

      page = title[0, separator.begin(0)]
      site_words = tokens(title[separator.end(0)..])
      return if words(page) < 3 || site_words.empty? || h1s.none? { |h1| tokens(h1.content) == site_words }

      page if heading_text?(page)
    end

    # H1s are left out: title_from_h1 has already cut at a page H1 that starts
    # the title, so an H1 that matches here is most often the site's logo.
    def heading_text?(text)
      text_words = tokens(text)
      @doc.css("body h2, body h3").any? do |heading|
        tokens(heading.content) == text_words && !logo?(heading) && !site_chrome?(heading)
      end
    end

    # A <header> or <footer> names the site, unless it is the header of the
    # page's <main> or <article>.
    def site_chrome?(node)
      names = Dom.ancestors_named(node, "header", "footer", "main", "article").map(&:name)
      (names & %w[header footer]).any? && (names & %w[main article]).empty?
    end

    # A logo heading links to the site's root or names itself a logo, brand or
    # site title. A <header> around an H1, or its container's classes, say too
    # little: most such H1s are the page's own title.
    def logo?(heading, names = LOGO_NAME)
      nodes = [heading] + heading.css("[class], [id]").to_a
      return true if nodes.any? { |node| "#{node["class"]} #{node["id"]}".match?(names) }

      heading.css("a[href]").any? { |link| home_link?(link["href"].strip) }
    end

    # An empty href, or one that starts with a fragment or query, links to
    # the page itself, as a permalink does. A query on a script links to any
    # page: wikis link every page as "index.php?Page".
    def home_link?(href)
      !href.empty? && !href.start_with?("#", "?") && href.match?(HOME_LINK) && !href.match?(SCRIPT_QUERY)
    end

    # Split before downcasing, like the title's words, which are scanned first
    # for their offsets: downcasing "İ" adds a combining dot that splits words.
    def tokens(text)
      text.scan(WORD).map(&:downcase)
    end

    def document_byline
      node = @doc.at_css("[itemprop~=author] [itemprop~=name], [rel=author], [itemprop~=author], .byline, .author")
      return unless node

      text = Dom.text(node).sub(/\A(?:by|von|par|por)\s+/i, "")
      text if text.length.between?(1, 100)
    end

    def document_published_time
      node = @doc.at_css("[itemprop~=datePublished][datetime], [itemprop~=datePublished][content], time[pubdate][datetime]")
      node && (node["datetime"] || node["content"])
    end

    def clean(value)
      return if value.nil?

      value = value.to_s
      value = unescape(value) if value.match?(ENTITY)
      value = Dom.squish(value)
      value.empty? ? nil : value
    end

    # JSON-LD strings and twice-escaped attributes keep their entities
    # ("MLS&reg;"). Lexbor decodes every HTML entity in a textarea's text,
    # which it does not parse for tags.
    def unescape(value)
      Nokolexbor::HTML("<textarea>#{value.gsub("<", "&lt;")}</textarea>").at_css("textarea").text
    end
  end
end
