# nokodown

Any web page to main-content Markdown, at Nokolexbor speed.

Extracts the main content of a web page as clean Markdown, together with the
metadata Readability returns (title, byline, excerpt, site name, publish date,
language). It works on articles and on everything else: home pages, search
results, product and pricing pages, documentation, forums.

Built on [Nokolexbor](https://github.com/serpapi/nokolexbor), for the
`include_markdown` option of SerpApi's Extract API. The name is Nokolexbor's
"noko" plus Markdown's "down".

## Installation

```ruby
gem "nokodown", git: "git@github.com:serpapi/nokodown.git"
```

Ruby 2.7 or newer, nokolexbor 0.6 or newer.

## Usage

```ruby
require "nokodown"

result = Nokodown.extract(html, url: "https://example.com/post")

result.markdown       # "# Post title\n\nFirst paragraph..."
result.title          # "Post title"
result.byline         # "Jane Doe"
result.excerpt        # "A one-line summary."
result.site_name      # "Example"
result.published_time # "2026-09-30T08:00:00Z"
result.lang           # "en"
result.mode           # :article, :page, :full or :none

Nokodown.to_markdown(html, url: "https://example.com/post") # just the Markdown
```

`html` is a string in any encoding. Binary strings are decoded the way a
browser reads them, by their `<meta charset>` or XML declaration, except that
bytes which read as UTF-8 are UTF-8 whatever the page declares, and the
encoding of a page that declares none is told from its bytes. UTF-8 text that
was once misread as Windows-1252 ("cafÃ©") is repaired, and invalid bytes are
dropped. A body that is not a page at all, such as a PDF, an image or an
archive served as HTML, or bytes made largely of control characters, gives
empty Markdown and `mode` `:none`. Elements nested more than 256 levels deep,
as unclosed tags on broken pages leave them, keep only their text.

| Option | Default | |
| --- | --- | --- |
| `url` | `nil` | Page URL. Relative links and images are resolved against it (and `<base>`), and links to the page itself are reduced to their text. |
| `main_content` | `true` | Keep only the main content. `false` converts the whole page, dropping only scripts, styles, hidden elements and form controls. |
| `title` | `true` | Start with the page title as a `#` heading when the content has no `<h1>`, or when its first `<h1>` follows the opening paragraphs and so heads a section, or names a section that the page's URL, which names the title, does not mention. Away from the home page, a heading that only names the site gives way to the page title, and a title that only names the site does not head content that has a heading of its own. When no content is found at all (a page rendered by scripts, a bot wall), `markdown` is empty and only `result.title` has the title. With `false`, an `<h1>` the content holds, such as the article's own headline, still opens it. |
| `images` | `true` | Include images. Emoji images are always kept as their text. |
| `links` | `true` | Keep links. `false` keeps only their text. |

`mode` says how the content was chosen: `:article` when the page was narrowed
to one body of prose, `:page` when the whole main region was kept, `:full`
with `main_content: false`, `:none` for a document without a body.

## What it removes

- Site navigation, headers, footers, sidebars, breadcrumbs, pagination
  (runs of page numbers, by their shape too) and archive calendars of day
  links, tables of contents and links back to the top (by class name, or as
  links to points on the page itself), found through HTML semantics (`nav`,
  page-level `header` and `footer`, ARIA roles, schema.org types) and
  class/id names. Structure
  finds the rest: a site header of menus or notices above the page's title
  however much it holds, a footer by any name that ends a page (not one
  inside `main` or an article, nor the footer of a section, a card or a
  quote), a breadcrumb trail by its shape in any language (a link to the
  home page, then links down the site with separators), a line of links to
  the site's tag or label archives ("Tags: a, b") with at most a short label
  ending in a colon and a category kicker above the title, unless the page
  repeats the line (a card's tags) or is such an archive, and copyright and
  licence lines in the major web languages.
- Once the content is chosen and pruned, so that they cannot sway either, a
  line of links to the site's sign-in, registration, account, cart or feeds
  ("您需要登录后才可以回帖 登录 | 注册", "View Cart (0)", "Subscribe to:
  Posts (Atom)") by where they point, unless a sentence, a heading, the
  page's title, a date, a table or a picture sits with them or they are
  items of a larger menu, and comment, review and contact forms (a visible
  text box, a name or e-mail field and little text) with the title above
  them, and a note under that title, in any language. A form stays when it
  wraps the page (ASP.NET), holds its title or main region, holds an e-mail
  address or a phone number, holds a table of what it asks about (a row of
  headers over a row of text, as an inquiry shows the flat it is about),
  asks how many (an order with a note), or is all an application or
  sign-up page's main region holds, and neither kind goes when it is all
  the content holds, spacer images aside.
- Cookie banners, ads, newsletter and sign-in prompts, share bars and share
  links by where they point, modals, chat widgets, "related", "recommended"
  and "most popular" boxes, legal disclaimers and disclosures (but not a note
  continuing the paragraph before it, or the footnote to a mark just above),
  and, next to an article, its comment thread.
- Blocks of teasers for other pages of the same site whatever their class
  names: a run of cards (a title link with a thumbnail, a date or an
  excerpt) or a titled list of bare links ("Смотрите также"). A block goes
  when:
  - it lists pages like this one (the same path but for its last segment,
    the same query keys, ids for the values that differ) after a line of
    the page's own text;
  - it lists posts named by their titles under the root, as this page is,
    under a heading after a line of text, or after a body of text on a
    page that declares itself an article, a product or a thread;
  - its title calls it related in the major web languages ("You may also
    like", "Похожие товары", "猜你喜欢"), unless it holds most of the page;
  - on a page that declares itself an article, a product or a thread, it is
    a titled box of cards that the page's own text, or its own list,
    outweighs.

  Blocks stay on home pages, in hubs of sections built alike, in forum posts,
  in a section that the page's own table of contents lists, under a title the
  page's address names, when they link below this page, and when the content
  would be left with fewer than 20 words outside headings. Lists of bare links
  also stay on listings, under a letter of an index, among three or more
  headed lists of links (a site map), and when they hold most of the page.
- On forums, the member panel and signature repeated beside every post. The
  member panel leaves one line naming the poster, with the post's date when
  the panel holds it. A quote that repeats a post already in the output is cut
  to its opening sentence, so the reply still shows what it answers.
- On product pages, customer reviews and Q&A widgets, with their review
  summaries and rating histograms. An inline rating badge ("212 reviews" next
  to the price), testimonials and editorial reviews stay.
- Invisible elements (`hidden`, `aria-hidden`, inline `display: none`,
  screen-reader-only and other hiding classes, and elements placed far off
  screen or in a one-pixel strip, where hacked sites hide link spam), keeping
  collapsed accordions, tab panels and FAQ answers. Content that React streams
  into hidden containers at the end of the page is put back where the page
  shows it, unless it is mostly links, as carousels of recommended products
  are.
- Sections rendered twice, such as a desktop and a mobile copy: the mobile
  copy goes and the desktop one stays.
- Repeated text and the labels of controls, in the major web languages:
  copies of the title (an H2 or bold line under the H1, a gallery label on
  every item), labels and tabs over the heading they repeat, lists made of
  the page's own headings, a "Read more", "Leer más" or "Comprar" link
  after a title that links to the same page (judged card by card, so a
  label the page uses once goes too), labels of controls ("Menu",
  "Loading...", "Back to top", "Quantity:", "prev / next"), counters
  without a label (view and comment counts, FAQ and step badges, slide
  numbers, a player's "0:00"), form labels left without their fields, and
  the marks at a slider's ends ("A A", "0 100").
  A read-more link that is the only way to its page, a number a label
  explains or that sits in a row of numbers, and a fact repeated on every
  card ("In stock") stay. A card whose only words are a shop button's
  label ("Add to cart", "В корзину") keeps its linked picture when the
  label goes.
- Tracking pixels, spacers, icons, placeholders and loading spinners
  (`no-image.png`, `img_load.gif`), README badges, click-tracking URL
  parameters (`utm_*`, `gclid`, `fbclid`, ...), permalink anchors, English
  "Read more" and "Continue reading" links wherever they are, code line
  numbers, and repeated responsive copies of the same image.
- Headings left at the end of the content with nothing under them, once
  what they headed is removed, unless one states a figure (a price, a
  score, a year).
- Markdown that costs tokens without meaning: horizontal rules, blank lines
  inside lists, headings inside list items, emphasis around a whole
  paragraph, cell, heading or link (a short bold label stays), separators
  between links and at line ends, lines of only punctuation, icon-font
  glyphs, code-language labels and copy buttons, and escapes that cannot
  change the rendering. A card's repeated links to its own page keep their
  text without the URL (its title keeps the link), and a button such as
  "Read more", a text the page uses once for each of several pages, goes when
  it ends its line (judged across all cards, in any language); texts that
  take turns from card to card ("Sold",
  "Available") are values and stay.
  Lines of one paragraph that each open with a link are a list written
  without its markup, and every item keeps its link, even where several
  link to the same file.
- In the main content, images whose alt text does not say what they show, at
  any size and in any wrapper (a figure keeps its caption): no alt text, a
  file or camera name ("IMG_6175.JPG"), a hash, or a word for "image" or
  "loading" ("photo", "foto", "画像"); icons, logos and avatars, told by their
  file name ("QDLogoBlue.gif"), folder (`/icons/`), class or alt text. An image
  alone in a text-free cell of a data table, such as a tick in a comparison
  table, stays, and so do all images of a page with fewer than 20 words
  besides them. So does the one picture of a photo's own page, linked to its
  full-size file, when the paragraphs hold fewer than 20 words besides
  their links. An image with alt text that is marked decorative
  (`role="presentation"` or `role="none"`) goes unless it sits in a figure, an
  image link or a text-free paragraph or table cell, or declares a width or
  height of 300 pixels or more; and card thumbnails go while the Markdown
  still has a text link to the same page. "Read more" or
  "3 comments" never names the page, and a label without letters ("$40") or
  with only a date ("Oct 1, 2026") names it only for an image without alt
  text. Any other text does, so in `:page` mode a thumbnail beside a
  "Shop now" link goes too; in an `:article`, only one outside a figure whose
  alt is a word or two, or is mostly the link text.
- Later copies of an image that stands alone on its line: always for an
  image whose alt names nothing (none, a file or camera name, "photo"), as in
  a gallery's thumbnail strip, and for one with alt text only when nothing but
  images came since the last copy, as in a logo strip shown twice. A line
  with several copies of one image, such as a row of rating stars, keeps
  them all.
- Markup and server output that leak into the text, outside code: HTML
  escaped into alt text (its text is kept), escaped elements written out
  whole, PHP and Liquid error messages, and template placeholders and
  shortcodes left unrendered. Email addresses hidden from harvesters, by
  Cloudflare or by a decoy inside the address, are shown as readers see
  them.

Every structural rule is guarded: an element that contains the `<main>`
region, or most of the page's text, is never removed because of its class name,
and neither is one named for what it has or allows (`has-sidebar`,
`with-navigation`, `sidebar-enabled`) or for the layout it is laid out in
(`layout-sidebar-left`, `one-right-sidebar`). A `<footer>` or a complementary
pane that holds the page's only `<h1>`, unless that links to the home page,
and a fair share of its text is the content, and so is a block named like
furniture (`dialog-off-canvas-main-canvas`) that also holds prose, unless it
is named as a breadcrumb trail or a menu.
Three kinds of named furniture go however much of a short page they hold: a
site header above the title, a sidebar or footer without prose beside a title
that has text of its own (not a block whose BEM modifier names its layout,
`catalog-grid--sidebar`, one inside a grid column wider than half the row,
or the layout that holds a sidebar beside a column named main, content or
primary with most of its text, `tmpl_two_col_sidebar`), and a cookie banner
that one of its names calls a banner, a bar or a dialog along with the
cookies (`cookie-notice`, `cmplz-cookiebanner`), or a consent manager, or
that is laid over the page, unless it holds the page's `<h1>` or the page is
about cookies. A shop's or a blog's tags (`product_tag-cookies`) name what it
lists, not the block, and a name for the room a page leaves for the banner
(`cookiebot-padding-bottom`) names the wrapper of its content. A grid
column narrower than the title's and beside it ("col-md-4" beside "col-md-8")
goes the same way, whatever its names, when it holds three or more linked
headings and no prose, as the latest posts beside an empty tag archive do,
unless most link below the page's own address, as a show's episodes do.
Prose here is two sentences' worth of lines of 80 characters or
more in any block, not counting link text or what an `<address>` holds:
opening hours and contact details are lines, not prose.

## How it works

1. **Charset**: transcode to UTF-8; Lexbor itself ignores `<meta charset>`.
   The bytes decide when they disagree with the declared charset or when
   there is none.
2. **Metadata**: JSON-LD, Open Graph and other `<meta>` tags, then the
   document, in Readability's order of preference. The title drops the
   site's name, as declared, as its domain spells it or as its logo heading
   shows it, and gives way to an `<h1>` that the page's URL names when the
   title does not.
3. **Preprocessor**: restore lazy-loaded images (`data-src`, `srcset`,
   `<noscript>` copies), drop scripts, invisible elements and form controls,
   and mark the forms that ask for a message, with their titles, while their
   controls are there.
4. **Boilerplate**: remove page chrome and noise widgets across the whole page.
5. **ContentLocator**: score paragraphs with Readability's algorithm. When one
   candidate holds most of the page's prose the content is narrowed to it
   (`:article`); otherwise the whole main region is kept (`:page`), because a
   listing or a product page spreads its content over many small blocks. The
   share required depends on the page type its metadata declares. A row of a
   data table stands for the whole table. When a short stretch that is not a
   list of links (a standfirst, key facts, a price) sits between the page's
   `<h1>` and the article, the article reaches up to the headline, unless that
   `<h1>` links to the home page, does not match the title, or a heading below
   matches the title better (a blog's name, a journal's, a section
   label). On forum
   threads (schema.org types or the forum software's generator tag) replies
   are content even in comment-named containers, and on forums and Q&A pages
   where no single post holds the page, the whole main region is cleaned as an
   article. There, each post's author and date, read from its header before
   boilerplate removal, become one line above the post's body
   (`**JGD** · April 2, 2024`) in place of the header, the panel around the
   name and repeated copies of the date. A post "by" Advertisement is an ad
   slot and goes. **Teasers** then finds the blocks of teasers for other
   pages, which are dropped from the content once it is cleaned.
6. **Pruner**: in articles, Readability's conditional cleaning plus removal of
   bylines, datelines and inline boxes of links to other stories, under a
   label in the major web languages ("Read also", "Lea también", "Читайте
   также", "Baca juga") or none; on other
   pages, removal of leftover link clusters, with the heading over them, and
   of columns of links beside a column of prose in layout tables, unless the
   table declares them the wider column or they hold the page title, and of
   narrow grid columns ("col-md-4", "span4") or side-named cells that are
   mostly links, beside a column of 7/12 or more that holds the title. An
   index page, whose link clusters hold most of its text, keeps them but for
   its menus: lists of links holding one to the page itself, the clusters
   above its title, and the side columns its table declares narrower. Such
   a menu goes from other pages too, but not from a section that the page's
   own table of contents lists, where it is content: the pieces of a set,
   this item among them. In
   both modes, short links and boxes styled as buttons ("Add to cart", "Book
   a demo") are removed, except for disclosure toggles, buttons inside a
   sentence and titles or labels styled as buttons, and so is the line a
   feed adds after a post ("The post … appeared first on …", in any
   language): a few words around a link to the post the page shows, by its
   title, and one to its site's home page. If article cleaning
   keeps less than half of what it was given (unless what it removed from a
   declared article was mostly links), it is undone and light cleaning,
   which treats link clusters and menus as page pruning does, is used
   instead; if it leaves almost nothing, the content is pruned as a page.
   Once cleaning is known to stay, it leaves alone the items of a listing of
   posts or products (alike blocks, each with a linked title, that hold most
   of the text) and a featured post beside them, since it would judge each
   item on its own. A teaser's linked title with its date and author links
   is not a link cluster, however short. Then **MessageForms** and
   **ServiceLinks** remove what is left in the content of the marked forms
   and titles and of the sign-in, cart and feed lines.
7. **Markdown**: headings, emphasis, links, images, nested and ordered lists,
   task lists, block quotes, fenced code with the language from the
   highlighter's classes, GFM tables (rowspans and colspans filled in) for data
   tables while layout tables are unwrapped, and a list of "name: value" lines
   for a two-column table without column names, definition lists, details,
   TeX from MathML, superscript and subscript digits as Unicode (10⁶, H₂O) and
   other scripts as 2^(n-1) and a_n. A `<pre>` whose lines are set with `<br>`
   or `<p>` and read as sentences, as site builders write product
   descriptions, is text, not code. A label and its value, or a number and
   its unit, set in sibling elements share a line ("Type: Condo"), and words,
   numbers and dates that adjacent elements run together are spaced
   ("20.07 2026"). Text is escaped only where it would otherwise change
   meaning.
   A list whose items hold whole sections, as tab panels do (two headings
   of different names, each over text of its own), is written as those
   sections, and its items without a heading as a list. An ordered one
   keeps its numbers on the heading that opens each item, after a product
   photo ("## 4. Acme Drill"), unless every heading has a rank of its own,
   and stays a numbered list if an item opens with anything else.

## Quality

### All kinds of pages: WCXB

[WCXB][wcxb] has 2,008 human-reviewed pages: 1,050 articles and 958 product,
collection, listing, forum, documentation and service (SaaS, pricing) pages,
split into a development set (1,497) and a held-out test set (511). Scores use
its metric: word-level F1 against the reference main content, plus the share
of "must include" snippets found and of boilerplate snippets leaked. All
systems ran on the same pages with links, images and tables on; their Markdown
was converted back to text for scoring, and tokens were counted on the Markdown
an LLM would read (o200k tokenizer). Word F1 is identical to WCXB's
`evaluate.py`. The snippet rates average only the pages that have snippets and
compare text with whitespace collapsed, while `evaluate.py` counts a page
without snippets as 100% and compares raw text, so its rates differ by about a
point.

| System | F1 (dev) | F1 (test) | Boilerplate leaked (test) | Content snippets found (test) | Tokens per page (test) | Tokens on URLs (test) |
| --- | --- | --- | --- | --- | --- | --- |
| nokodown | 0.836 | 0.874 | 8.3% | 83.6% | 2,718 | 21% |
| rs-trafilatura 0.1.1 | 0.838 | 0.873 | 12.7% | 87.7% | 2,664 | 18% |
| Trafilatura 2.3.1 | 0.816 | 0.858 | 8.1% | 81.8% | 2,552 | 17% |
| Readability.js 0.6 + Turndown | 0.770 | 0.830 | 10.0% | 76.5% | 2,899 | 23% |
| Current Extract rule | 0.782 | 0.802 | 43.2% | 90.1% | 4,356 | 35% |

F1 by page type on the test set (257 articles; 28 to 59 pages of each other type):

| System | Article | Product | Collection | Listing | Forum | Documentation | Service |
| --- | --- | --- | --- | --- | --- | --- | --- |
| nokodown | 0.949 | 0.806 | 0.736 | 0.724 | 0.783 | 0.922 | 0.807 |
| rs-trafilatura 0.1.1 | 0.942 | 0.740 | 0.732 | 0.714 | 0.829 | 0.953 | 0.801 |
| Trafilatura 2.3.1 | 0.934 | 0.719 | 0.589 | 0.757 | 0.786 | 0.941 | 0.817 |
| Readability.js 0.6 + Turndown | 0.931 | 0.634 | 0.614 | 0.637 | 0.711 | 0.882 | 0.805 |
| Current Extract rule | 0.874 | 0.666 | 0.647 | 0.727 | 0.679 | 0.906 | 0.727 |

"Current Extract rule" is the Extract API's present `include_markdown`
behaviour (the page's `<main>`, else its only `<article>`, else `<body>`)
reproduced with nokodown's converter. See
[benchmark/compare](benchmark/compare/README.md) to reproduce the table.

```sh
bundle exec ruby benchmark/wcxb.rb tmp/corpora/wcxb test
```

### Articles

Scored with the [Scrapinghub article extraction benchmark][benchmark]'s metric
(precision and recall over 4-token shingles, averaged per page). The Markdown is
converted back to text and the leading title is removed, since both references
leave the headline out of the body.

| Corpus | Pages | F1 | Precision | Recall |
| --- | --- | --- | --- | --- |
| [Scrapinghub][benchmark], human-labelled article bodies | 181 | 0.945 | 0.915 | 0.978 |
| [Mozilla Readability test pages][mozilla], Readability.js output as reference | 130 | 0.941 | 0.953 | 0.929 |

Published results on the same Scrapinghub corpus, for comparison:
Trafilatura 0.958, newspaper4k 0.949, Readability.js 0.947, go-readability
0.934, readability-lxml 0.922, goose3 0.896, jusText 0.804, html2text 0.662.

```sh
bundle exec rake benchmark:quality   # downloads the corpora at pinned commits into tmp/
```

## Speed

Per page over the Scrapinghub corpus (pages of 20 KB to 1.4 MB, median
111 KB), median of 5 runs, on an Apple Silicon laptop with nokolexbor 0.6.4:

| Ruby | Median | p90 | p99 | Max |
| --- | --- | --- | --- | --- |
| 2.7.8 | 6.4 ms | 11.6 ms | 30.3 ms | 59.8 ms |
| 3.4.5 | 7.0 ms | 12.8 ms | 34.4 ms | 63.1 ms |

```sh
bundle exec rake benchmark:speed
ruby benchmark/speed.rb DIRECTORY --per-page   # any folder of .html or .html.gz files
```

## Using it in the Extract API

The Extract API currently fills `text_content.markdown` from the page's
`<main>`, its only `<article>`, or the whole body. With this gem:

```ruby
markdown = Nokodown.to_markdown(html, url: final_url)
```

`main_content: false` gives the whole-page conversion if a request needs it.
Truncation to 50,000 characters stays in the engine, and `include_tags` /
`exclude_tags` can be applied to the HTML before it is passed in.

## Development

```sh
bundle install
bundle exec rspec
NOKOLEXBOR_VERSION=0.6.4 bundle exec rspec   # the version SerpApi runs
```

Specs use RSpec's `should` syntax, like the main SerpApi app.

## License

Apache License 2.0. The scoring and cleaning heuristics are adapted from
[Readability.js][mozilla]; see [NOTICE](NOTICE).

[benchmark]: https://github.com/scrapinghub/article-extraction-benchmark
[mozilla]: https://github.com/mozilla/readability
[wcxb]: https://github.com/Murrough-Foley/web-content-extraction-benchmark
