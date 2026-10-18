"""Score every tool's Markdown on WCXB.

Usage: metrics.py WCXB_DIR RUNS_DIR OUT_JSON [tool ...]

Per page: the official WCXB word precision/recall/F1 and with/without snippet
rates (on the Markdown converted to plain text), plus Markdown-specific cost
and noise measures that matter when the output is fed to an LLM.
"""
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import tiktoken

ENCODING = tiktoken.get_encoding("o200k_base")
WCXB, RUNS, OUT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
TOOLS = sys.argv[4:] or sorted(p.name for p in RUNS.iterdir() if p.is_dir())

IMAGE = re.compile(r"!\[([^\]]*)\]\((?:[^()\s]|\([^)]*\))*(?:\s+\"[^\"]*\")?\)")
LINK = re.compile(r"\[([^\]]*)\]\((?:[^()\s]|\([^)]*\))*(?:\s+\"[^\"]*\")?\)")
URL_TARGET = re.compile(r"\]\(((?:[^()\s]|\([^)]*\))*)(?:\s+\"[^\"]*\")?\)")
BARE_URL = re.compile(r"https?://\S+")
RAW_HTML = re.compile(r"</?(?!sup\b|sub\b|br\b)[a-z][a-z0-9-]*(?:\s[^<>]*)?>", re.I)
BOILERPLATE = re.compile(
    r"cookie|privacy policy|terms (?:of|and) (?:use|service)|all rights reserved|©|sign in|log in|"
    r"subscribe|newsletter|share (?:on|this)|follow us|skip to|add to (?:cart|bag|basket)|"
    r"you may also like|related (?:articles|posts|products|stories)|advertisement|accept all",
    re.I,
)


def tokenize(text):
    return re.findall(r"\w+", text.lower()) if text else []


def to_text(markdown):
    text = IMAGE.sub("", markdown)
    text = LINK.sub(lambda m: m.group(1), text)
    text = re.sub(r"^(?:`{3,}|~{3,}).*$", "", text, flags=re.M)
    text = re.sub(r"^\|?(?:\s*:?-{3,}:?\s*\|)+\s*:?-*:?\s*$", "", text, flags=re.M)
    text = re.sub(r"^\s{0,3}#{1,6}\s+", "", text, flags=re.M)
    text = re.sub(r"^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ x]\]\s+)?", "", text, flags=re.M)
    text = re.sub(r"^\s*>\s?", "", text, flags=re.M)
    text = text.replace("|", " ")
    text = re.sub(r"</?su[pb]>", "", text)
    text = re.sub(r"(\*\*|__|\*|~~|`)", "", text)
    text = re.sub(r"\\([\\`*_{}\[\]()#+\-.!|<>~])", r"\1", text)
    return text


def norm(text):
    return re.sub(r"\s+", " ", text.lower()).strip()


def word_scores(predicted, reference):
    pred, ref = tokenize(predicted), tokenize(reference)
    if not ref:
        return (1.0, 1.0, 1.0) if not pred else (0.0, 0.0, 0.0)
    if not pred:
        return (0.0, 0.0, 0.0)
    overlap = sum((Counter(pred) & Counter(ref)).values())
    p, r = overlap / len(pred), overlap / len(ref)
    return p, r, (2 * p * r / (p + r) if p + r else 0.0)


def snippet_rate(text, snippets):
    if not snippets:
        return None
    haystack = norm(text)
    return sum(1 for s in snippets if norm(s) in haystack) / len(snippets)


def tokens(text):
    return len(ENCODING.encode(text, disallowed_special=()))


def table_breaks(markdown):
    broken = 0
    for block in re.split(r"\n\s*\n", markdown):
        rows = [l for l in block.splitlines() if l.strip().startswith("|")]
        if len(rows) >= 2 and len({l.strip().strip("|").count("|") for l in rows}) > 1:
            broken += 1
    return broken


def page_metrics(markdown, gt):
    text = to_text(markdown)
    p, r, f1 = word_scores(text, gt["main_content"])
    total = tokens(markdown)
    url_chars = "".join(URL_TARGET.findall(markdown)) + "".join(BARE_URL.findall(LINK.sub("", IMAGE.sub("", markdown))))
    lines = [l.strip() for l in markdown.splitlines() if l.strip()]
    content_lines = [l for l in lines if re.search(r"\w", l)]
    duplicate_lines = sum(c - 1 for c in Counter(content_lines).values() if c > 1)
    return {
        "precision": p, "recall": r, "f1": f1,
        "with": snippet_rate(text, gt["with"]),
        "without": snippet_rate(text, gt["without"]),
        "empty": not text.strip(),
        "tokens": total,
        "gt_tokens": tokens(gt["main_content"]),
        "url_tokens": tokens(url_chars) if url_chars else 0,
        "syntax_tokens": max(total - tokens(text), 0),
        "boilerplate_lines": sum(1 for l in lines if len(l) < 200 and BOILERPLATE.search(l)),
        "duplicate_lines": duplicate_lines,
        "lines": len(content_lines),
        "raw_html": len(RAW_HTML.findall(markdown)),
        "escapes": len(re.findall(r"\\[\\`*_{}\[\]()#+\-.!|<>~]", markdown)),
        "broken_tables": table_breaks(markdown),
        "images": len(IMAGE.findall(markdown)),
        "links": len(LINK.findall(IMAGE.sub("", markdown))),
    }


def load_gt(split):
    gt = {}
    for path in sorted((WCXB / split / "ground-truth").glob("*.json")):
        data = json.loads(path.read_text())
        internal = data.get("_internal") or {}
        page_type = (internal.get("page_type") or {}).get("primary", "article")
        g = data.get("ground_truth") or {}
        gt[path.stem] = {
            "main_content": g.get("main_content") or "",
            "with": g.get("with") or [],
            "without": g.get("without") or [],
            "page_type": "collection" if page_type == "category" else page_type,
            "url": data.get("url"),
        }
    return gt


def summarize(rows):
    n = len(rows)
    mean = lambda key: sum(r[key] for r in rows) / n
    with_rows = [r["with"] for r in rows if r["with"] is not None]
    without_rows = [r["without"] for r in rows if r["without"] is not None]
    total_tokens = sum(r["tokens"] for r in rows)
    return {
        "pages": n,
        "f1": mean("f1"), "precision": mean("precision"), "recall": mean("recall"),
        "with": sum(with_rows) / len(with_rows) if with_rows else None,
        "without": sum(without_rows) / len(without_rows) if without_rows else None,
        "empty_pages": sum(r["empty"] for r in rows),
        "tokens_per_page": total_tokens / n,
        "tokens_vs_ground_truth": total_tokens / max(sum(r["gt_tokens"] for r in rows), 1),
        "url_token_share": sum(r["url_tokens"] for r in rows) / max(total_tokens, 1),
        "syntax_token_share": sum(r["syntax_tokens"] for r in rows) / max(total_tokens, 1),
        "boilerplate_lines_per_page": mean("boilerplate_lines"),
        "duplicate_line_share": sum(r["duplicate_lines"] for r in rows) / max(sum(r["lines"] for r in rows), 1),
        "raw_html_per_page": mean("raw_html"),
        "escapes_per_1k_tokens": 1000 * sum(r["escapes"] for r in rows) / max(total_tokens, 1),
        "pages_with_broken_tables": sum(1 for r in rows if r["broken_tables"]),
    }


def main():
    report = {"tools": TOOLS, "splits": {}, "pages": {}}
    for split in ("dev", "test"):
        gt = load_gt(split)
        report["splits"][split] = {}
        for tool in TOOLS:
            md_dir = RUNS / tool / split / "md"
            rows, by_type = [], defaultdict(list)
            for file_id, g in gt.items():
                path = md_dir / f"{file_id}.md"
                markdown = path.read_text(errors="replace") if path.exists() else ""
                m = page_metrics(markdown, g)
                m["page_type"] = g["page_type"]
                rows.append(m)
                by_type[g["page_type"]].append(m)
                report["pages"].setdefault(f"{split}/{file_id}", {"page_type": g["page_type"], "url": g["url"]})[tool] = {
                    k: (round(v, 4) if isinstance(v, float) else v) for k, v in m.items() if k != "page_type"}
            report["splits"][split][tool] = {"overall": summarize(rows), "by_type": {t: summarize(v) for t, v in sorted(by_type.items())}}
    OUT.write_text(json.dumps(report))
    for split in ("dev", "test"):
        print(f"\n{split}")
        print(f"{'tool':<18}{'F1':>7}{'P':>7}{'R':>7}{'with':>7}{'w/out':>7}{'empty':>6}{'tok/pg':>8}{'tok/GT':>7}{'url%':>6}{'boiler':>7}{'dup%':>6}{'html':>6}")
        for tool in TOOLS:
            s = report["splits"][split][tool]["overall"]
            print(f"{tool:<18}{s['f1']:>7.3f}{s['precision']:>7.3f}{s['recall']:>7.3f}{s['with']:>7.1%}{s['without']:>7.1%}{s['empty_pages']:>6}"
                  f"{s['tokens_per_page']:>8.0f}{s['tokens_vs_ground_truth']:>7.2f}{s['url_token_share']:>6.1%}{s['boilerplate_lines_per_page']:>7.2f}"
                  f"{s['duplicate_line_share']:>6.1%}{s['raw_html_per_page']:>6.2f}")
        types = sorted(report["splits"][split][TOOLS[0]]["by_type"])
        print(f"\n{split} F1 by page type")
        print(f"{'tool':<18}" + "".join(f"{t[:10]:>11}" for t in types))
        for tool in TOOLS:
            by_type = report["splits"][split][tool]["by_type"]
            print(f"{tool:<18}" + "".join(f"{by_type[t]['f1']:>11.3f}" for t in types))


if __name__ == "__main__":
    main()
