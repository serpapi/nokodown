# frozen_string_literal: true

module Nokodown
  # Class/id/role vocabularies. Matched against Dom.signature, which lowercases
  # and splits camelCase so "adContainer" reads as "ad-container".
  module Patterns
    # Word boundaries where "_" and digits separate words too, unlike \b.
    WORD_START = "(?<![a-z])"
    WORD_END = "(?![a-z])"

    # Site furniture that surrounds the content on any kind of page.
    CHROME = /
      #{WORD_START}(?:nav|navbar|nav-?bar|navigation|nav-?menu|nav-?links|main-?nav|site-?nav|global-?nav|
      menubar|mega-?menu|top-?bar|toolbar|masthead|crumbs|sidenav|side-?nav|pager|
      skip|skip-?link|skip-?links|skip-?to-?content|noprint|no-?print|d-print-none|toc|
      table-?of-?contents|colophon|copyright|left-?rail|right-?rail)#{WORD_END}|
      sidebar|breadcrumb|pagination|
      (?<![\w-])(?:(?:site|global|main|page|app|l|c|o|g)-?)?footer(?:-(?:wrapper|container|inner|main|top|bottom|links|nav|menu))?(?![\w-])
    /x.freeze

    # Fine print. WordPress puts category-* and tag-* terms on the post, and a
    # modifier ("hasDisclaimer") names the block that has one, not the note.
    DISCLAIMER = /#{WORD_START}(?<!category-|tag-|has-)(?:disclaimers?|disclosures)#{WORD_END}/.freeze

    # A member's signature under each forum post: XenForo message-signature,
    # phpBB and SMF signature. A modifier ("has-signature") names the post
    # that has one. API docs name a function's signature the same way, so
    # Boilerplate removes one only when it is named after a post or sits in one.
    SIGNATURE = /#{WORD_START}(?<!has-|with-)signature(?![\w-])/.freeze
    POST = /post|message|comment|repl(?:y|ies)|thread|topic|forum|discussion|answer|question|bbp|msg/.freeze

    # The panel of member details beside each forum post: XenForo
    # message-user, phpBB postprofile, Invision cAuthorPane, vBulletin
    # userinfo. The token must end there, so XenForo's post body,
    # message-userContent, is not one. MemberPanel reduces it to the name.
    MEMBER_PANEL = /#{WORD_START}(?:postprofile|poster-?info|author-?pane|message-user|user-?(?:info|details|extras|stats))(?![\w-])/.freeze

    # Overlays, ads, prompts and widgets that are never part of the content.
    # "ad" may carry a size ("ad300x250") but must not touch other digits:
    # generated hashes such as "elementor-element-38ad5ea" contain it.
    NOISE = /
      cookie|consent|gdpr|#{WORD_START}ccpa#{WORD_END}|onetrust|didomi|cookiebot|usercentrics|
      newsletter|subscribe|#{WORD_START}sign-?up#{WORD_END}|#{WORD_START}opt-?in#{WORD_END}|#{WORD_START}log-?in#{WORD_END}|#{WORD_START}sign-?in#{WORD_END}|
      advert|adsbygoogle|adsense|#{WORD_START}ad-?(?:slot|unit|container|wrapper|wrap|box|banner|block|label|zone|space)s?#{WORD_END}|
      (?<![a-z\d])(?:ad|ads|dfp|gpt-ad)(?:\d+(?:x\d+)?)?(?![a-z\d])|doubleclick|taboola|outbrain|revcontent|zergnet|
      sponsor|#{WORD_START}promoted#{WORD_END}|
      #{WORD_START}(?:share|shares|sharing|share-?bar|share-?buttons?|share-?tools|sharedaddy|addthis|sharethis)#{WORD_END}|
      social|#{WORD_START}follow-?us#{WORD_END}|
      popup|pop-up|#{WORD_START}modal#{WORD_END}|interstitial|offcanvas|off-canvas|flyout|snackbar|tooltip|popover|
      #{WORD_START}toast#{WORD_END}|#{WORD_START}drawer#{WORD_END}|
      editsection|#{WORD_START}feedback#{WORD_END}|was-?this-?helpful|intercom|livechat|chat-?widget|
      #{SIGNATURE.source}|#{DISCLAIMER.source}|
      #{MEMBER_PANEL.source}|
      related|recommend|recirc|read-?next|more-?stories|you-?may-?like|also-?like|
      #{WORD_START}(?:search-?form|search-?box|search-?bar)#{WORD_END}
    /x.freeze

    # Secondary content: noise next to an article, content on a hub page.
    # WordPress puts "tag-<slug>" and "comments-open" on the post itself, so
    # those forms must not match.
    SECONDARY = /
      comment(?!s?[-_]?(?:open|closed|enabled|disabled))|disqus|#{WORD_START}(?:respond|replies|reply)#{WORD_END}|
      popular|trending|most-?read|most-?viewed|author-?bio|about-?the-?author|#{WORD_START}rss#{WORD_END}|
      (?<![\w-])(?:post-|entry-|article-)?tags?(?:-?(?:cloud|list|links))?(?![\w-])
    /x.freeze

    # Customer reviews, ratings and Q&A on a product page, by name or by the
    # class prefixes of review widget vendors. Modifiers ("has-reviews",
    # "reviews-enabled") and WordPress terms ("category-reviews") sit on the
    # wrapper that has reviews, often around the description, so they must
    # not match.
    REVIEWS = /
      #{WORD_START}(?<!has-|no-|with-|category-|tag-)(?:reviews|(?:customer|product|user|individual|pdp|seo|all)-?reviews?|
      review-?(?:lists?|section|container|wrapper|widget|summary|snapshot|stars|histogram|filters?|cards?|items?|content-list)|
      ratings?-?(?:histogram|summary|snapshot|breakdown)|questions?-?(?:and|&|n)?-?answers?|qna|q-?and-?a|
      customer-?questions|ask-?(?:a-)?question)(?!-(?:enabled|disabled))#{WORD_END}|
      yotpo|bazaarvoice|#{WORD_START}bv-|jdgm|judgeme|okendo|#{WORD_START}stamped-|loox|trustpilot|powerreviews|
      #{WORD_START}pr-(?:review|rd|snippet)|reviews-?io|#{WORD_START}junip-|spr-review|rvw-|#{WORD_START}ruk_
    /x.freeze

    # Cheap first pass: most elements match none of the patterns below.
    PAGE_FURNITURE = Regexp.union(CHROME, NOISE)

    # Onigmo tries the branches of an alternation one at a time, so a word
    # list matches faster once branches share their prefixes: "pag|print"
    # becomes "p(?:ag|rint)". A word holding another adds nothing.
    def self.word_hint(words)
      words = words.reject { |word| words.any? { |other| other != word && word.include?(other) } }
      Regexp.new(prefix_tree(words)).freeze
    end

    def self.prefix_tree(words)
      branches = words.group_by { |word| word[0] }.map do |first, group|
        rest = group.map { |word| word[1..] }
        rest.include?("") ? first : first + prefix_tree(rest)
      end
      branches.size == 1 ? branches.first : "(?:#{branches.join("|")})"
    end
    private_class_method :word_hint, :prefix_tree

    # Every name the furniture patterns match holds one of these words, and
    # most class names hold none, so checking them first skips the slow
    # patterns for most names. A new furniture name needs its word here.
    FURNITURE_HINT = word_hint(%w[
      nav menu bar masthead crumb pag skip print toc table colophon copyright rail footer
      cookie consent gdpr ccpa onetrust didomi usercentrics newsletter subscribe sign opt log
      ad dfp doubleclick taboola outbrain revcontent zergnet sponsor promoted shar social follow
      pop modal interstitial canvas flyout tooltip toast drawer editsection feedback helpful
      intercom chat discl postprofile poster author message user related recommend recirc read
      stories like search
    ])

    # The same for SECONDARY.
    SECONDARY_HINT = word_hint(%w[comment disqus respond repl popular trending most author rss tag])

    def self.furniture?(value)
      value.match?(FURNITURE_HINT) && value.match?(PAGE_FURNITURE)
    end

    def self.secondary?(value)
      value.match?(SECONDARY_HINT) && value.match?(SECONDARY)
    end

    # Furniture named after where it sits. A section may be named after the
    # table-of-contents entry or skip link that points to it ("toc-para",
    # "skip-item"), but never after a place on the page.
    PLACE = /sidebar|rail|footer|nav|menu|masthead|breadcrumb|crumbs|pager|pagination|copyright|colophon|toolbar|top-?bar/.freeze

    OVERLAY = /cookie|consent|gdpr|onetrust|didomi|cookiebot|usercentrics|modal|popup|pop-up|popover|dialog|flyout|off-?canvas|interstitial|snackbar|toast|tooltip/.freeze

    MENU = /#{WORD_START}(?:menu|menus|menu-?items?)#{WORD_END}/.freeze

    # Site headers only; "card-header" or "plan-header" hold content.
    HEADER = /(?<![\w-])(?:(?:site|global|main|top|page|app|l|c|o|g)-?)?header(?:-(?:wrapper|container|inner|main|top|bar|nav))?(?![\w-])|masthead/.freeze

    # Collapsed regions that still hold content: accordions, tab panels, FAQs.
    DISCLOSURE = /accordion|collaps|tab-?pane|tab-?panel|tab-?content|faq|answer|expand|disclosure/.freeze

    # Readability's class weighting regexes.
    POSITIVE = /article|body|content|entry|hentry|h-entry|main|page|pagination|post|text|blog|story/.freeze
    NEGATIVE = /
      -ad-|hidden|(?<!\S)hid(?!\S)|banner|combx|comment|com-|contact|footer|gdpr|masthead|
      media|meta|outbrain|promo|related|scroll|share|shoutbox|sidebar|skyscraper|sponsor|shopping|tags|widget
    /x.freeze

    # Class tokens where "hidden" or "scroll" names a CSS value or a widget
    # state, not page furniture: overflow-hidden, scroll-mt-20, quick-add-hidden,
    # field--label-hidden. Elements that are really hidden are gone by the time
    # this is used. Bare "hidden", as in "hidden md:block", is not one: it marks
    # a responsive duplicate.
    UTILITY_CLASS = /
      \A-?(?:overflow|overscroll|scroll|snap)(?:-[\w.\[\]]+)*\z|.-+hidden\z|
      scroll-(?:m[trblxy]?|p[trblxy]?|margin|padding)(?![a-z])
    /x.freeze

    CHROME_ROLES = Set.new(%w[
      banner navigation contentinfo complementary search menu menubar toolbar tablist
      dialog alertdialog tooltip alert status marquee timer
    ]).freeze

    CHROME_ITEMTYPES = %r{schema\.org/(?:WPHeader|WPFooter|WPSideBar|WPAdBlock|SiteNavigationElement)}.freeze

    ARIA_LABEL = /breadcrumb|pagination|share|social|advert|cookie|newsletter|navigation|\bmenu\b|footer|related/i.freeze

    # Labels that mark a block as an ad wherever they stand. Not "Ad", "Ads"
    # or "Advert", which can also be a name: Ad is a Dutch first name.
    AD_LABEL = /
      advertisement|advertising|sponsored(?:\scontent)?|paid\scontent|anzeige|werbung|
      publicit[eé]|publicidad|pubblicit[aà]|реклама|广告
    /xi.freeze

    # Whole-text matches for short blocks and links that carry no content.
    BOILERPLATE_TEXT = /
      \A(?:
        #{AD_LABEL}|advert|ads?|
        skip\sto\s(?:main\s)?(?:content|navigation)|jump\sto\s(?:main\s)?content|
        share(?:\sthis)?(?:\s(?:article|story|post|page))?|share\son\s\w+|tweet(?:\sthis)?|pin\sit|
        email(?:\sthis)?|print(?:\sthis)?(?:\s(?:article|page))?|
        loading|loading(?:\s[\p{L}]+){1,2}(?=\s*(?:…|\.{3}))|back\sto\stop|scroll\sto\stop|copy\slink|link\scopied|copied|
        (?:read|view|see|show|load)\s(?:more|less)|continue\sreading|click\sto\sexpand|
        (?:hide|show|toggle)\scaption|enlarge\sthis\simage|
        (?:image|photo|picture|slide)\s\d+\s(?:of|\/)\s\d+|\d*\s?comments?|
        (?:this\s\w+\srequires|please\senable|you\sneed\sto\senable)\sjavascript.*|
        permalink|link\sto\sthis\s(?:heading|section)|direct\slink\sto\sthis\s(?:heading|section)|
        add\sto\s(?:cart|bag|basket|wish\s?list|favou?rites|compare)|quick\s(?:shop|view|add)|
        (?:choose|select|more|view)\soptions|compare\sproducts?(?:\s\(\d+\))?|filter\s(?:&|and)\ssort|sort\sby
      )[\s.:!…»›→>]*\z
    /xi.freeze

    # Labels that introduce a box of links to other stories.
    RELATED_LABEL = /
      \A(?:read\smore|more|related(?:\s(?:stories|articles|posts|content|coverage|reading))?|see\salso|
      also\sread|don'?t\smiss|recommended|must\sread|more\son\sthis|watch|trending|popular)\b[\s:|]*
    /xi.freeze

    # Short lines that are page furniture inside an article body.
    STRAY_LINE = /
      \A(?:published|updated|posted|last\supdated|first\spublished)\b.{0,80}\d|
      \bfollow\s(?:us|him|her|them|me)\b.{0,60}\b(?:twitter|facebook|instagram|linkedin|threads|bluesky|x)\b
    /xi.freeze

    LINK_NOISE_TEXT = /
      \A(?:(?:read|view|see|show|load)\s(?:the\s)?(?:full\s)?(?:more|less|article|story|post)|continue\sreading|
      permalink|link\sto\sthis\s(?:heading|section)|copy\slink|edit(?:\sthis\s(?:page|section))?|
      ¶|§|\#|🔗)[\s.:!…»›→>]*\z
    /xi.freeze

    COPYRIGHT_TEXT = /\A(?:copyright\s*)?(?:©|\(c\)|&copy;)|all\srights\sreserved/i.freeze

    NOISE_HEADING = /
      \A(?:related(?:\s\w+)?|share(?:\sthis)?(?:\s\w+)?|comments?|leave\sa\s(?:comment|reply)|
      advertisement|newsletter|follow\sus|subscribe(?:\s\w+)?|popular(?:\s\w+)?|trending(?:\s\w+)?|
      recommended(?:\s\w+)?|more\sfrom\s.+|you\smay\salso\slike|you\smight\salso\slike|read\snext|
      read\smore|tags|categories|about\sthe\sauthor|sign\sup.*|most\s(?:read|popular|viewed))[\s:]*\z
    /xi.freeze
  end
end
