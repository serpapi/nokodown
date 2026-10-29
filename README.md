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
| `title` | `true` | Start with the page title as a `#` heading when the content has no `<h1>`, or when its first `<h1>` follows the opening paragraphs and so heads a section, or names a section that the page's URL, which names the title, does not mention. Away from the home page, a heading that only names the site gives way to the page title, and a title that only names the site does not head content that has a heading of its own. When no content is found at all (a page rendered by scripts, a bot wall), `markdown` is empty and only `result.title` has the title. |
| `images` | `true` | Include images. Emoji images are always kept as their text. |
| `links` | `true` | Keep links. `false` keeps only their text. |

`mode` says how the content was chosen: `:article` when the page was narrowed
to one body of prose, `:page` when the whole main region was kept, `:full`
with `main_content: false`, `:none` for a document without a body.

## What it removes

- Site navigation, headers, footers, sidebars, breadcrumbs, pagination and
  tables of contents, found through HTML semantics (`nav`, page-level `header`
  and `footer`, ARIA roles, schema.org types) and class/id names. Structure
  finds the rest: a site header of menus or notices above the page's title
  however much it holds, a footer by any name that ends a page (not one
  inside `main` or an article, nor the footer of a section, a card or a
  quote), a breadcrumb trail by its shape in any language (a link to the
  home page, then links down the site with separators), a line of links to
  the site's tag or label archives ("Tags: a, b") with at most a short label
  ending in a colon and a category kicker above the title, unless the page
  repeats the line (a card's tags) or is such an archive, and
  copyright and licence lines in the major web languages.
- Cookie banners, ads, newsletter and sign-in prompts, share bars and share
  links by where they point, modals, chat widgets, "related", "recommended"
  and "most popular" boxes, legal disclaimers and disclosures (but not a note
  continuing the paragraph before it, or the footnote to a mark just above),
  and, next to an article, its comment thread.
- Blocks of teasers for other pages of the same site whatever their class
  names: a run of cards, each a title link with a thumbnail, a date or an
  excerpt, under a title of its own in any language ("Flere Nyheder",
  "Похожие товары"). They go when they list pages like this one (the same
  path but for its last segment, with the same query keys and ids for the
  values that differ) after a line of the page's own text, or, on a page that
  declares itself an article, a product or a thread, when the page's own
  text, or its own list, outweighs them. They stay on home pages, in hubs of
  sections built alike, in forum posts (attachments), when they link to pages
  below this one, and when the content would be left with fewer than 20 words
  outside headings.
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
- Sections rendered twice, such as a desktop and a mobile copy.
- Repeated text and the labels of controls, in the major web languages:
  copies of the title (an H2 or bold line under the H1, a gallery label on
  every item), labels and tabs over the heading they repeat, lists made of
  the page's own headings, a "Read more", "Leer más" or "Comprar" link
  after a title that links to the same page (judged card by card, so a
  label the page uses once goes too), labels of controls ("Menu",
  "Loading...", "Back to top", "Quantity:", "prev / next"), counters
  without a label (view and comment counts, FAQ and step badges, slide
  numbers, a player's "0:00"), and form labels left without their fields.
  A read-more link that is the only way to its page, a number a label
  explains or that sits in a row of numbers, and a fact repeated on every
  card ("In stock") stay.
- Tracking pixels, spacers, icons, placeholders and loading spinners
  (`no-image.png`, `img_load.gif`), README badges, click-tracking URL
  parameters (`utm_*`, `gclid`, `fbclid`, ...), permalink anchors, English
  "Read more" and "Continue reading" links wherever they are, code line numbers, and repeated responsive copies of the same image.
- Markdown that costs tokens without meaning: horizontal rules, blank lines
  inside lists, headings inside list items, emphasis around a whole
  paragraph, cell, heading or link (a short bold label stays), separators
  between links and at line ends, lines of only punctuation, icon-font
  glyphs, code-language labels and copy buttons, and escapes that cannot
  change the rendering. A card's repeated links to its own page keep their
  text without the URL (its title keeps the link), and a button such as
  "Read more", a text the page uses once for each of several pages, goes when
  it ends its line (judged across all cards, in any language); texts that take turns from card to card ("Sold",
  "Available") are values and stay.
- In the main content, images whose alt text does not say what they show, at
  any size and in any wrapper (a figure keeps its caption): no alt text, a
  file or camera name ("IMG_6175.JPG"), a hash, or a word for "image" or
  "loading" ("photo", "foto", "画像"); icons, logos and avatars, told by their
  file name ("QDLogoBlue.gif"), folder (`/icons/`), class or alt text. An image
  alone in a text-free cell of a data table, such as a tick in a comparison
  table, stays, and so do all images of a page with fewer than 20 words
  besides them. An image with alt text that is marked decorative
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
region, or most of the page's text, is never removed because of its class name.

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
   `<noscript>` copies), drop scripts, invisible elements and form controls.
4. **Boilerplate**: remove page chrome and noise widgets across the whole page.
5. **ContentLocator**: score paragraphs with Readability's algorithm. When one
   candidate holds most of the page's prose the content is narrowed to it
   (`:article`); otherwise the whole main region is kept (`:page`), because a
   listing or a product page spreads its content over many small blocks. The
   share required depends on the page type its metadata declares. On forum
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
   bylines, datelines and inline boxes of links to other stories; on other
   pages, removal of leftover link clusters, unless they hold most of the text
   as on an index page. In both modes, short links and boxes styled as
   buttons ("Add to cart", "Book a demo") are removed, except for disclosure
   toggles, buttons inside a sentence and titles or labels styled as buttons.
   If article cleaning removes almost everything, it is undone and light
   cleaning is used instead.
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
