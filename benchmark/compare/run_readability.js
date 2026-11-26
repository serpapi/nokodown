// Mozilla Readability + Turndown (GFM) for every WCXB page: OUT/<split>/md/<id>.md.
//
//   node benchmark/compare/run_readability.js WCXB_DIR OUT_DIR [SHARD SHARDS]
//
// jsdom is slow on large pages; run several shards in parallel to speed it up.
// A page that makes Readability or Turndown throw is written empty and
// reported on stderr.
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

function markdown(html, url) {
  const dom = document(html, url);
  try {
    const article = new Readability(dom.window.document).parse();
    if (!article || !article.content) return "";
    return (article.title ? `# ${article.title}\n\n` : "") + turndown.turndown(article.content);
  } finally {
    dom.window.close();
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
    let output = "";
    try {
      output = markdown(html, url);
    } catch (error) {
      // As in run_python.py: one page that breaks the extractor (turndown-plugin-gfm
      // throws on some tables) is written empty instead of stopping the shard.
      console.error(`${split}/${id}: ${error.name}: ${error.message}`);
    }
    fs.writeFileSync(path.join(mdDir, `${id}.md`), output);
  });
}
