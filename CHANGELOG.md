# Changelog

## Unreleased

- Elements nested more than 64 levels below `<body>` are converted as plain
  text, so deeply nested markup no longer raises `SystemStackError`, also
  inside a thread with its smaller stack.
- Native `<video>` and `<audio>` players become links to the file they play,
  labelled with their title. Muted videos (autoplaying backgrounds) are
  skipped, and a player inside a link is replaced by its thumbnail, if it
  holds one and is not hidden.
- Links without `href` take their target from `data-href`, `data-url` and
  the other attributes scripts keep it in.
- An image's `data-src` (and the other attributes only lazy loaders use) is
  preferred over its `src`, also without a "lazy" class, so the real image
  replaces a placeholder or a low-quality thumbnail. High-resolution
  attributes come first, then the largest size in `data-a-dynamic-image`,
  then the other loaders' attributes and a lazy `srcset`. A value that is
  no image location ("false", a number, a word) never replaces `src`.
  Spacer and placeholder files no longer count as a `src`.
- With `main_content: false`, everything visible is converted, so a
  selection comes out whole: headings without a section, boilerplate lines
  ("Advertisement", "Share"), repeated headings, paragraphs and images,
  quotes, rules, buttons, form text and open dialogs are kept. Only
  scripts, styles, hidden elements, form inputs, closed dialogs and
  punctuation-only lines are dropped.
- Links and images whose `javascript:` or `vbscript:` scheme is disguised
  by tabs, line breaks or leading control characters (`java&#9;script:`),
  or that a `<base>` with such a scheme would produce, are dropped like
  any other script link. A link's URL can no longer end its Markdown
  destination early with a stray `)`, nor its text end the label early
  with a stray `]` or a trailing backslash, and write a link of its own.
  Link text holds no link, autolink or HTML tag of its own either, from
  raw TeX or from a backtick run too long to fence code. Raw TeX, emoji
  alt text and email addresses, whatever they start with, cannot start
  Markdown that reaches past them; code with a backtick run too long to
  fence is written as text; a backslash at the end of a text escapes
  nothing after it; code spans side by side keep their own fences; and
  text side by side cannot join into a link, an image, an autolink or a
  tag.
  Brackets and backticks in a URL are percent-encoded, so a URL read as
  text holds no link either.
- Code inside link text keeps its brackets and backslashes as they are.
- `max_length:` returns exactly the first `max_length` characters of the
  Markdown, and the same `excerpt`, and stops rendering once they are
  known: at most one short render and one whole render. `nil`, the
  default, changes nothing; a negative or non-Integer value raises
  `ArgumentError`.
- A link whose `href` is blank takes its target from `data-href` and the
  like too. A link made only of images keeps its target, as
  `[![alt](src)](href)`.
- An iframe embed is linked only from an http(s) URL on the video host's
  own domain, and one without a title is written as `[Video](url)`.
- A page made only of headings keeps all of them, a one-column table with
  a header cell or a caption stays a table, and the H1 above an article
  body chosen inside `<main>` opens the content.
- A table cell escapes every pipe, so a backslash before a pipe stays.
- Extraction is faster, with the same output: about 40% on Wikipedia's
  Coffee article (364 to 214 ms on Ruby 2.7) and 27% on WCXB (ms per page).

## 0.1.0 (2026-11-02)

First release.

- `Nokodown.extract` returns the main content of a web page as Markdown,
  with Readability-style metadata (title, byline, excerpt, site name,
  published time, language).
- `Nokodown.to_markdown` returns only the Markdown.
- Works on articles and on home, listing, product, documentation, forum and
  service pages.
