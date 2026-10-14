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

`html` is a string in any encoding. Binary strings are decoded using their
`<meta charset>`, and invalid bytes are dropped.

| Option | Default | |
| --- | --- | --- |
| `url` | `nil` | Page URL. Relative links and images are resolved against it (and `<base>`), and links to the page itself are reduced to their text. |
| `main_content` | `true` | Keep only the main content. `false` converts the whole page, dropping only scripts, styles, hidden elements and form controls. |
| `title` | `true` | Start with the page title as a `#` heading when the content has no `<h1>`. |
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
   share required depends on the page type its metadata declares.
6. **Pruner**: in articles, Readability's conditional cleaning plus removal of
   bylines, datelines and inline boxes of links to other stories; on other
   pages, removal of leftover link clusters. If article cleaning removes almost
   everything, it is undone and light cleaning is used instead.
7. **Markdown**: headings, emphasis, links, images, nested and ordered lists,
   task lists, block quotes, fenced code with the language from the
   highlighter's classes, GFM tables (rowspans and colspans filled in) for data
   tables while layout tables are unwrapped, definition lists, details, TeX
   from MathML, `<sup>`/`<sub>`. Text is escaped only where it would otherwise
   change meaning.

## Quality

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

Both corpora are articles. Non-article pages are covered by the fixtures in
`spec/fixtures` (product, search results, documentation, pricing, forum) and
were spot-checked on 45 live pages of all kinds.

```sh
bundle exec rake benchmark:quality   # downloads both corpora at pinned commits into tmp/
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
