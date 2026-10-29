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
      #{WORD_START}signature(?![\w-])|#{DISCLAIMER.source}|
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
      -ad-|hidden|^hid$|\shid$|\shid\s|^hid\s|banner|combx|comment|com-|contact|footer|gdpr|masthead|
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

    # Controls that reveal the rest of a text or lead to more about it, in
    # the major web languages.
    MORE_TEXT = /
      (?:read|view|see|show|load)\s(?:more|less)|continue\sreading|learn\smore|find\sout\smore|
      leer\sm[aá]s|seguir\sleyendo|(?:ver|mostrar|cargar)\sm[aá]s|
      leia\smais|ler\smais|continu(?:e|ar)\slendo|(?:ver|mostrar|carregar)\smais|
      lire\s(?:la\ssuite|plus)|voir\s(?:plus|la\ssuite)|(?:afficher|charger)\splus|
      weiterlesen|mehr\s(?:lesen|anzeigen|laden)|
      leggi\s(?:tutto|di\spi[uù]|altro)|continua\sa\sleggere|(?:mostra|vedi)\s(?:di\s)?pi[uù]|
      lees\s(?:meer|verder)|meer\s(?:lezen|weergeven|laden)|(?:toon|bekijk)\smeer|
      читать\s(?:далее|дальше|полностью)|подробнее|показать\s(?:ещё|еще|больше)|загрузить\s(?:ещё|еще)|
      читати\sдалі|детальніше|докладніше|показати\sбільше|
      (?:prze)?czytaj\s(?:więcej|dalej)|(?:zobacz|pokaż)\swięcej|
      devam[ıi]n[ıi]\soku(?:yun)?|daha\sfazla\sg[öo]ster|
      続きを読む|もっと見る|もっと読む|詳細を見る|詳しく見る|さらに表示|記事を読む|
      阅读更多|閱讀更多|查看更多|加载更多|載入更多|查看详情|查看詳情|阅读全文|閱讀全文|显示更多|顯示更多|
      더\s?보기|자세히\s?보기|더\s읽기|계속\s읽기|
      اقرأ\sالمزيد|قراءة\sالمزيد|عرض\sالمزيد|تابع\sالقراءة|
      xem\sth[êe]m|đọc\s(?:tiếp|thêm)|xem\schi\sti[ếe]t|
      baca\s(?:selengkapnya|lebih\slanjut)|lihat\s(?:selengkapnya|lebih\sbanyak)|muat\slebih\sbanyak|
      č[ií]st\s(?:v[ií]ce|d[áa]le|cel[ée])|zobrazit\sv[ií]ce|
      l[äæ]s\smere?|les\smer|visa\smer|vis\smer|tov[áa]bb|
      קרא(?:ו)?\sעוד|อ่านต่อ|อ่านเพิ่มเติม|और\sपढ़ें|
      saber\sm[aá]s|saiba\smais|en\ssavoir\splus|(?:\+|plus)\sde\sd[ée]tails|
      mehr\serfahren|erfahren\ssie\smehr|scopri\sdi\spi[uù]|meer\sinformatie|узнать\sбольше|
      dowiedz\ssię\swięcej|daha\sfazla\sbilgi|了解更多|もっと知る|자세히\s알아보기|اعرف\sالمزيد|tìm\shiểu\sthêm|
      pelajari\slebih\slanjut
    /xi.freeze

    # Shop controls in the major web languages besides English.
    SHOP_CONTROL_TEXT = /
      buy\snow|in\sden\swarenkorb|(?:zum\s)?warenkorb\shinzufügen|jetzt\skaufen|ajouter\sau\spanier|acheter\smaintenant|
      a[ñn]adir\sal\scarrito|agregar\sal\scarrito|comprar\sahora|adicionar\sao\scarrinho|comprar\sagora|
      aggiungi\sal\scarrello|acquista\sora|in\s(?:de\s)?winkelwagen|toevoegen\saan\swinkelwagen|nu\skopen|
      (?:добавить\s)?в\sкорзину|купить\sв\s(?:один|1)\sклик|купить\sсейчас|dodaj\sdo\skoszyka|kup\steraz|
      sepete\sekle|hemen\sal|カートに入れる|カートに追加|今すぐ購入|加入购物车|加入購物車|立即购买|立即購買|
      장바구니\s?담기|바로\s?구매|أضف\sإلى\sالسلة|اشتر\sالآن|thêm\svào\sgiỏ(?:\shàng)?|mua\sngay|
      (?:masukkan|tambah(?:kan)?\ske)\skeranjang|beli\ssekarang|
      vista\sr[áa]pida|aper[çc]u\srapide|schnellansicht|visualizzazione\srapida|snel\sbekijken|быстрый\sпросмотр|
      szybki\spodgl[ąa]d|h[ıi]zl[ıi]\sbak[ıi][şs]|クイックビュー|快速查看|빠른\s?보기|عرض\sسريع|xem\snhanh|lihat\scepat|
      choix\sdes\soptions|s[ée]lectionner\sles\soptions|seleccionar\sopciones|selecione\sas\sop[çc][õo]es|
      seleziona\s(?:le\s)?opzioni|opties\sselecteren|optionen\sausw[äa]hlen|выбрать\sопции
    /xi.freeze

    # Slideshow and pager controls, alone or as a pair ("prev / next").
    PREV_NEXT = /
      prev(?:ious)?|next|back|anterior|siguiente|pr[óo]ximo|seguinte|pr[ée]c[ée]dent|suivant|zur[üu]ck|weiter|
      vorherige|n[äa]chste|precedente|successiv[oa]|avanti|indietro|vorige|volgende|назад|вперёд|вперед|
      предыдущая|следующая|poprzedni[a]?|następn[ya]|wstecz|dalej|önceki|sonraki|geri|ileri|前へ|次へ|戻る|
      上一页|下一页|上一張|下一張|上一张|下一张|返回|이전|다음|السابق|التالي|trước|tiếp|sebelumnya|selanjutnya|berikutnya|kembali
    /xi.freeze

    # A paragraph that is only the label of a control. Bare words such as
    # "More", "Menu" or "Close" are content inside a sentence or as a
    # heading, so this is matched against whole paragraphs only. A label
    # that links to its page stays when it is the only way there:
    # RepeatedLinks takes it when a title links to the same page.
    UI_LABEL = /
      \A[\s+«»‹›<>←.…(]*(?:
        #{MORE_TEXT}|#{SHOP_CONTROL_TEXT}|(?:#{PREV_NEXT})(?:\s*[\/|·•]?\s*(?:#{PREV_NEXT}))?|
        more|más|mehr|meer|più|więcej|ещё|еще|більше|v[ií]ce|devam[ıi]|selengkapnya|更多|もっと|المزيد|
        loading|cargando|carregando|chargement(?:\sen\scours)?|wird\sgeladen|caricamento|ładowanie|wczytywanie|
        загрузка|завантаження|yükleniyor|読み込み中|加载中|載入中|正在加载|로딩\s?중|불러오는\s중|جار[يی]?\sالتحميل|
        đang\stải|memuat|
        (?:back|go|return|scroll)\sto\s(?:the\s)?top|to\stop|top\sof\s(?:the\s)?page|bottom\sof\s(?:the\s)?page|page\stop|
        (?:zurück\s)?nach\soben|haut\sde\spage|retour\sen\shaut|volver\sarriba|ir\sarriba|voltar\sao\stopo|
        torna\s(?:su|in\salto)|(?:terug\s)?naar\sboven|наверх|вверх|do\sgóry|na\sgórę|yukarı\sçık|başa\sdön|
        トップへ戻る|ページトップ|ページの先頭へ|ページ上部へ|返回顶部|回到顶部|返回頂部|맨\s위로|العودة\sللأعلى|
        (?:lên|về)\sđầu\strang|kembali\ske\satas|
        skip\sto\s(?:main\s)?(?:content|navigation|menu)|go\sto\s(?:main\s)?(?:content|menu)|
        (?:direkt\s)?zum\s(?:haupt)?inhalt(?:\sspringen)?|(?:aller|passer)\sau\scontenu(?:\sprincipal)?|
        (?:ir|saltar)\sal\scontenido(?:\sprincipal)?|(?:pular|ir)\spara\so\sconte[úu]do|(?:vai|salta)\sal\scontenuto|
        (?:ga\s|direct\s)?naar\sde\sinhoud|перейти\sк\s(?:основному\s)?содержимому|przejdź\sdo\s(?:treści|zawartości)|
        (?:ana\s)?içeriğe\sgeç|コンテンツへスキップ|本文へスキップ|本文へ移動|跳至内容|跳到主要内容|跳转到内容|
        본문\s?바로가기|تخطي\sإلى\sالمحتوى|chuyển\sđến\snội\sdung|(?:langsung|lewati)\ske\skonten|
        menu|menü|меню|菜单|選單|メニュー|메뉴|القائمة|
        close|schlie(?:ß|ss)en|fermer|cerrar|fechar|chiudi|sluiten|закрыть|zamknij|kapat|閉じる|关闭|關閉|닫기|إغلاق|
        search|suche|rechercher|buscar|pesquisar|ricerca|zoeken|поиск|szukaj|検索|搜索|搜尋|검색|tìm\skiếm|
        filters?|filtern|filtres?|filtros?|filtri|фильтры?|filtry|filtrele|絞り込み|筛选|필터|bộ\slọc|
        (?:sort\sby|ordenar\spor|trier\spar|sortieren\snach|ordina\sper|sorteer\sop|сортировать\sпо|sortuj\swedług|sırala)|
        quantity|qty|количество|cantidad|quantidade|quantité|menge|anzahl|quantità|aantal|ilość|adet|miktar|
        数量|수량|الكمية|số\slượng|
        купить|kaufen|acheter|comprar|acquista|kopen|購入|购买|구매|شراء
      )[\s.:：!…«»‹›<>→➔)\]]*\z
    /xi.freeze

    # What a view, read, download or like counter counts, in the major web
    # languages.
    COUNTED = /
      views?|reads?|hits|visits|downloads?|likes?|favou?rites?|clicks|comments?|
      visitas|vistas|visualizaciones|lecturas|descargas|comentarios|visualizações|leituras|curtidas|comentários|
      vues|lectures|téléchargements|commentaires|aufrufe|zugriffe|kommentare|visualizzazioni|letture|visite|commenti|
      weergaven|keer\sbekeken|reacties|просмотр(?:ов|а|ы)?|прочтени[йя]|скачивани[йя]|комментари(?:ев|я|й)|переглядів|
      wyświetle(?:ń|nia)|odsłon|komentarz[ey]?|görüntülenme|(?:okunma|okuyan|[iİ]ndirme|görüntülenme)\ssayısı|okunma|yorum|
      閲覧数?|回閲覧|コメント|浏览(?:量|次数)?|次浏览|阅读量?|次阅读|點擊|点击(?:量|数)?|瀏覽|閱讀|评论|評論|조회수?|댓글|
      عدد\s(?:القراءات|المشاهدات|الزيارات)|مشاهدات?|تعليقات|lượt\s(?:xem|tải)|bình\sluận|(?:kali\s)?dilihat|komentar
    /xi.freeze

    # A counter on its own ("2362 views", "Views: 1,915", "点击：571"), or
    # the line a comment or review widget shows when there are none.
    COUNTER_TEXT = /
      \A[\s|(]*(?:
        (?:(?:[\d.,\s]*\d[kmкм]?\s?(?:#{COUNTED})|(?:#{COUNTED})\s?[:：(]?\s?[\d.,\s]*\d[kmкм]?\)?)[\s|·•,]*)+|
        0(?:[.,]0)?\s?(?:out\sof|of|von|de|sur|su|из|na|\/)\s?5|
        comments\s(?:are\s)?(?:closed|off)|both\scomments\sand\strackbacks\sare\s(?:currently\s)?closed|
        no\scomments(?:\syet)?|(?:there\sare\s)?no\sreviews\syet|no\sratings?\syet|be\sthe\sfirst\sto\s(?:review|comment).*|
        no\shay\s(?:comentarios|valoraciones\saún|reseñas)|sin\scomentarios|los\scomentarios\sestán\scerrados|
        sem\scomentários|nenhum\scomentário|(?:os\s)?comentários\s(?:estão\s)?encerrados|ainda\snão\shá\savaliações|
        aucun\s(?:commentaire|avis)|les\scommentaires\ssont\sfermés|il\sn'y\sa\spas\sencore\sd'avis|
        keine\skommentare|kommentare\ssind\sgeschlossen|(?:es\sgibt\s)?noch\skeine\sbewertungen|
        nessun\s(?:commento|recensione)|i\scommenti\ssono\schiusi|non\sci\ssono\sancora\srecensioni|
        geen\sreacties|reacties\szijn\sgesloten|(?:er\szijn\s)?nog\sgeen\s(?:beoordelingen|reviews)|
        (?:комментариев|отзывов)\s(?:пока\s)?нет|нет\s(?:комментариев|отзывов)|комментарии\sзакрыты|пока\sнет\sотзывов|
        brak\s(?:komentarzy|opinii)|komentarze\ssą\s(?:wyłączone|zamknięte)|
        yorum\syok|henüz\syorum\syapılmamış|yorumlar\skapalı|
        コメントは(?:まだ)?ありません|レビューはまだありません|暂无(?:评论|评价)|暫無(?:評論|評價)|还没有评论|
        (?:등록된\s)?댓글이\s없습니다|리뷰가\s없습니다|لا\sتوجد\s(?:تعليقات|مراجعات)|التعليقات\sمغلقة|
        chưa\scó\s(?:bình\sluận|đánh\sgiá)(?:\snào)?|belum\sada\s(?:komentar|ulasan)|nincs\shozzászólás
      )[\s.!)]*\z
    /xi.freeze

    # Whole-text matches for short blocks and links that carry no content.
    BOILERPLATE_TEXT = /
      \A(?:
        #{AD_LABEL}|advert|ads?|
        skip\sto\s(?:main\s)?(?:content|navigation)|jump\sto\s(?:main\s)?content|
        share(?:\sthis)?(?:\s(?:article|story|post|page))?|share\son\s\w+|tweet(?:\sthis)?|pin\sit|
        email(?:\sthis)?|print(?:\sthis)?(?:\s(?:article|page))?|
        loading|loading(?:\s[\p{L}]+){1,2}(?=\s*(?:…|\.{3}))|back\sto\stop|scroll\sto\stop|copy\slink|link\scopied|copied|
        (?:read|view|see|show|load)\s(?:more|less)|continue\sreading|#{SHOP_CONTROL_TEXT}|click\sto\sexpand|
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
