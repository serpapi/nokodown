"""Trafilatura or rs-trafilatura Markdown for every WCXB page: OUT/<split>/md/<id>.md.

    python benchmark/compare/run_python.py trafilatura|rs-trafilatura WCXB_DIR OUT_DIR

Both run with links, images and tables on, so their Markdown is comparable with
nokodown's defaults. A page that makes the extractor raise is written empty and
reported on stderr.
"""
import gzip
import json
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

TOOL, WCXB, OUT = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])


def markdown(html, url):
    if TOOL == "trafilatura":
        import trafilatura

        return trafilatura.extract(html, url=url, output_format="markdown", include_links=True,
                                   include_images=True, include_tables=True) or ""
    import rs_trafilatura

    result = rs_trafilatura.extract(html, url=url, output_markdown=True, include_links=True, include_images=True)
    body = result.content_markdown or ""
    return f"# {result.title}\n\n{body}" if result.title and not body.lstrip().startswith("#") else body


def convert(job):
    split, truth = job
    url = json.loads(truth.read_text()).get("url")
    html = gzip.open(WCXB / split / "html" / f"{truth.stem}.html.gz", "rt", encoding="utf-8", errors="replace").read()
    try:
        return split, truth.stem, markdown(html, url)
    except Exception as error:  # noqa: BLE001 - one bad page must not stop the run
        print(f"{split}/{truth.stem}: {type(error).__name__}: {error}", file=sys.stderr)
        return split, truth.stem, ""


if __name__ == "__main__":
    jobs = [(split, path) for split in ("dev", "test") for path in sorted((WCXB / split / "ground-truth").glob("*.json"))]
    with ProcessPoolExecutor() as pool:
        for split, file_id, text in pool.map(convert, jobs, chunksize=8):
            out = OUT / split / "md"
            out.mkdir(parents=True, exist_ok=True)
            (out / f"{file_id}.md").write_text(text)
