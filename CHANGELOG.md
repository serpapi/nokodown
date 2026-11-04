# Changelog

## Unreleased

- Elements nested more than 64 levels below `<body>` are converted as plain
  text, so deeply nested markup no longer raises `SystemStackError`, also
  inside a thread with its smaller stack.
- Native `<video>` and `<audio>` players become links to the file they play,
  labelled with their title. Muted videos (autoplaying backgrounds) and
  players inside a link are skipped.
- Links without `href` take their target from `data-href`, `data-url` and
  the other attributes scripts keep it in.
- An image's `data-src` (and the other attributes only lazy loaders use) is
  preferred over its `src`, also without a "lazy" class, so the real image
  replaces a placeholder or a low-quality thumbnail. Spacer and placeholder
  files no longer count as a `src`.
- With `main_content: false`, headings without a section and boilerplate
  lines ("Advertisement", "Share") are kept, so converting a selection of
  headings no longer gives empty Markdown.

## 0.1.0 (2026-11-02)

First release.

- `Nokodown.extract` returns the main content of a web page as Markdown,
  with Readability-style metadata (title, byline, excerpt, site name,
  published time, language).
- `Nokodown.to_markdown` returns only the Markdown.
- Works on articles and on home, listing, product, documentation, forum and
  service pages.
