# Comparing extractors on WCXB

These scripts produce the cross-tool table in the main README. Each runner
writes one Markdown file per page to `RUNS/<tool>/<split>/md/<id>.md`, and
`metrics.py` scores every tool from those files the same way.

```sh
bundle exec rake benchmark:corpora            # WCXB into tmp/corpora/wcxb
W=tmp/corpora/wcxb R=tmp/runs

ruby benchmark/compare/run_nokodown.rb $W $R/nokodown
ruby benchmark/compare/run_nokodown.rb $W $R/current-extract current

python3 -m venv tmp/venv && tmp/venv/bin/pip install -r benchmark/compare/requirements.txt
tmp/venv/bin/python benchmark/compare/run_python.py trafilatura $W $R/trafilatura
tmp/venv/bin/python benchmark/compare/run_python.py rs-trafilatura $W $R/rs-trafilatura

(cd benchmark/compare && npm install)
for i in 0 1 2 3; do node benchmark/compare/run_readability.js $W $R/readability $i 4 & done; wait

tmp/venv/bin/python benchmark/compare/metrics.py $W $R tmp/metrics.json \
  nokodown rs-trafilatura trafilatura readability current-extract
```

rs-trafilatura has no macOS wheel; building it needs a Rust toolchain, and on
Python 3.14 also `PYO3_USE_ABI3_FORWARD_COMPATIBILITY=1`.

`current-extract` reproduces the Extract API's current rule (the page's
`<main>`, else its only `<article>`, else `<body>`) using nokodown's converter,
so it isolates the effect of main-content detection.

Besides the benchmark's F1 and snippet rates, `metrics.py` reports what an LLM
pays for: tokens per page (o200k tokenizer), the share of tokens spent on URLs
and on Markdown syntax, boilerplate-looking lines, duplicated lines, leaked raw
HTML, escapes and malformed tables.
