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
gem "nokodown"
```

Ruby 2.7 or newer, nokolexbor 0.6 or a later 0.x release. nokolexbor 0.7 and
later need Ruby 3.1. Bundler picks 0.6.4 on older Rubies, but `gem install`
does not, so install that version first:

```sh
gem install nokolexbor -v 0.6.4
gem install nokodown
```

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

`html` is a string in any encoding. Binary strings are decoded using their
`<meta charset>`, and invalid bytes are dropped.

`Nokodown.extract`, `Nokodown.to_markdown` and `Nokodown::Result` are the
public API. Other classes are internal and can change in any release.

| Option | Default | |
| --- | --- | --- |
| `url` | `nil` | Page URL. Relative links and images are resolved against it (and `<base>`), and links to the page itself are reduced to their text. |
| `main_content` | `true` | Keep only the main content. `false` converts the whole page, dropping only scripts, styles, hidden elements and form controls. |
| `title` | `true` | Start with the page title as a `#` heading when the content has no `<h1>`. When no content is found at all (a page rendered by scripts, a bot wall), `markdown` is empty and only `result.title` has the title. |
| `images` | `true` | Include images. Emoji images are always kept as their text. |
| `links` | `true` | Keep links. `false` keeps only their text. |

`mode` says how the content was chosen: `:article` when the page was narrowed
to one body of prose, `:page` when the whole main region was kept, `:full`
with `main_content: false`, `:none` for a document without a body.

## What it removes

- Site navigation, headers, footers, sidebars, breadcrumbs, pagination and
  tables of contents, found through HTML semantics (`nav`, page-level `header`
  and `footer`, ARIA roles, schema.org types) and class/id names.
- Cookie banners, ads, newsletter and sign-in prompts, share bars, modals,
  chat widgets, "related", "recommended" and "most popular" boxes, and, next
  to an article, its comment thread.
- On product pages, customer reviews and Q&A widgets, with their review
  summaries and rating histograms. An inline rating badge ("212 reviews" next
  to the price), testimonials and editorial reviews stay.
- Invisible elements (`hidden`, `aria-hidden`, inline `display: none`,
  screen-reader-only and other hiding classes), keeping collapsed accordions,
  tab panels and FAQ answers.
- Tracking pixels, spacers, icons, placeholders, README badges, click-tracking
  URL parameters (`utm_*`, `gclid`, `fbclid`, ...), permalink anchors,
  "Read more" links, code line numbers, and repeated responsive copies of the
  same image.
- In the main content, images marked decorative (`role="presentation"` or
  `role="none"`, and outside an `:article` also `alt=""`) unless they sit in a
  figure, an image link or a text-free paragraph or table cell, or declare a
  width or height of 300 pixels or more; and card thumbnails while the
  Markdown still has a text link to the same page. "Read more" or
  "3 comments" never names the page, and a label without letters ("$40") or
  with only a date ("Oct 1, 2026") names it only for an image without alt
  text. Any other text does, so in `:page` mode a thumbnail beside a
  "Shop now" link goes too; in an `:article`, only one outside a figure whose
  alt is a word or two, or is mostly the link text.
- Later copies of an image that stands alone on its line: always for an
  image without alt text, and for one with alt text only when nothing but
  images came since the last copy, as in a logo strip shown twice. A line
  with several copies of one image, such as a row of rating stars, keeps
  them all.

Every structural rule is guarded: an element that contains the `<main>`
region, or most of the page's text, is never removed because of its class name.

## How it works

1. **Charset**: transcode to UTF-8; Lexbor itself ignores `<meta charset>`.
2. **Metadata**: JSON-LD, Open Graph and other `<meta>` tags, then the
   document, in Readability's order of preference.
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
   article.
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
   tables while layout tables are unwrapped, definition lists, details, TeX
   from MathML, superscript and subscript digits as Unicode (10⁶, H₂O) and
   other scripts as 2^(n-1) and a_n. Text is escaped only where it would
   otherwise change meaning.

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
