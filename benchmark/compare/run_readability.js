// Mozilla Readability + Turndown (GFM) for every WCXB page: OUT/<split>/md/<id>.md.
//
//   node benchmark/compare/run_readability.js WCXB_DIR OUT_DIR [SHARD SHARDS]
//
// jsdom is slow on large pages; run several shards in parallel to speed it up.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const { JSDOM, VirtualConsole } = require("jsdom");
const { Readability } = require("@mozilla/readability");
const TurndownService = require("turndown");
const { gfm } = require("turndown-plugin-gfm");

const [wcxb, out, shardArg, shardsArg] = process.argv.slice(2);
const shard = Number(shardArg || 0);
const shards = Number(shardsArg || 1);
const turndown = new TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced", bulletListMarker: "-" });
turndown.use(gfm);
const virtualConsole = new VirtualConsole();

function document(html, url) {
  try {
    return new JSDOM(html, { url, virtualConsole });
  } catch (error) {
    return new JSDOM(html, { virtualConsole }); // some pages carry URLs jsdom rejects
  }
}

for (const split of ["dev", "test"]) {
  const mdDir = path.join(out, split, "md");
  fs.mkdirSync(mdDir, { recursive: true });
  const files = fs.readdirSync(path.join(wcxb, split, "ground-truth")).sort();
  files.forEach((file, index) => {
    if (index % shards !== shard) return;
    const id = file.replace(/\.json$/, "");
    const url = JSON.parse(fs.readFileSync(path.join(wcxb, split, "ground-truth", file))).url;
    const html = zlib.gunzipSync(fs.readFileSync(path.join(wcxb, split, "html", `${id}.html.gz`))).toString("utf8");
    const dom = document(html, url);
    const article = new Readability(dom.window.document).parse();
    const markdown = article && article.content ? (article.title ? `# ${article.title}\n\n` : "") + turndown.turndown(article.content) : "";
    dom.window.close();
    fs.writeFileSync(path.join(mdDir, `${id}.md`), markdown);
  });
}
