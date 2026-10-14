# frozen_string_literal: true

# Content extraction quality against two public corpora:
#
#   scrapinghub  181 news/blog pages with human-labelled article bodies
#                https://github.com/scrapinghub/article-extraction-benchmark
#   mozilla      130 pages with Readability.js output as the reference
#                https://github.com/mozilla/readability (test/test-pages)
#
# Scoring is the Scrapinghub benchmark's: precision and recall over 4-token
# shingles per page, averaged across pages, F1 from the averages.
#
#   ruby benchmark/quality.rb scrapinghub PATH_TO_CHECKOUT
#   ruby benchmark/quality.rb mozilla PATH_TO_CHECKOUT [--worst 10] [--dump scores.json]

require "json"
require "zlib"
require_relative "../lib/readable_markdown"

module Quality
  module_function

  def tokens(text)
    text.to_s.scan(/[[:word:]]+/)
  end

  def shingles(text, size = 4)
    words = tokens(text)
    grams = (0..[words.size - size, 0].max).map { |i| words[i, size] }.reject(&:empty?)
    grams.tally
  end

  def compare(expected, actual)
    expected = shingles(expected)
    actual = shingles(actual)
    tp = fp = fn = 0.0
    (expected.keys | actual.keys).each do |key|
      e = expected.fetch(key, 0)
      a = actual.fetch(key, 0)
      tp += [e, a].min
      fp += [a - e, 0].max
      fn += [e - a, 0].max
    end
    [tp, fp, fn]
  end

  def precision(tp, fp, fn)
    return 1.0 if fp.zero? && fn.zero?
    return 0.0 if tp.zero? && fp.zero?

    tp / (tp + fp)
  end

  def recall(tp, fp, fn)
    return 1.0 if fp.zero? && fn.zero?
    return 0.0 if tp.zero? && fn.zero?

    tp / (tp + fn)
  end

  # Both references leave the headline out of the article body.
  def body(markdown)
    markdown.sub(/\A# .*\n*/, "")
  end

  def plain_text(markdown)
    markdown.gsub(/^(`{3,}|~{3,}).*$/, "")
            .gsub(/!\[([^\]]*)\]\([^)]*\)/, "")
            .gsub(/\[([^\]]*)\]\((?:[^()]|\([^)]*\))*\)/, '\1')
            .gsub(/^\|(?:\s*-+\s*\|)+\s*$/, "")
  end

  def scrapinghub(path)
    truth = JSON.parse(File.read(File.join(path, "ground-truth.json")))
    truth.map do |id, item|
      html = Zlib::GzipReader.open(File.join(path, "html", "#{id}.html.gz"), &:read)
      [id, item["articleBody"], html, item["url"]]
    end
  end

  def mozilla(path)
    Dir[File.join(path, "test", "test-pages", "*")].sort.map do |dir|
      expected = Nokolexbor::HTML(File.read(File.join(dir, "expected.html"))).at_css("body").text
      [File.basename(dir), expected, File.read(File.join(dir, "source.html")), "http://fakehost/test/page.html"]
    end
  end

  def run(corpus, path, worst: 0, dump: nil)
    pages = public_send(corpus, path)
    seconds = 0.0
    scores = pages.map do |id, expected, html, url|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = ReadableMarkdown.extract(html, url: url)
      seconds += Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      tp, fp, fn = compare(expected, plain_text(body(result.markdown)))
      total = tp + fp + fn
      tp, fp, fn = [tp, fp, fn].map { |x| x / total } if total.positive?
      { id: id, tp: tp, fp: fp, fn: fn, mode: result.mode }
    end
    report(corpus, scores, seconds)
    report_worst(scores, worst) if worst.positive?
    File.write(dump, JSON.pretty_generate(scores.map { |s| [s[:id], precision(s[:tp], s[:fp], s[:fn]).round(3), recall(s[:tp], s[:fp], s[:fn]).round(3)] })) if dump
  end

  def report(corpus, scores, seconds)
    precisions = scores.select { |s| s[:tp] + s[:fp] > 0 }.map { |s| precision(s[:tp], s[:fp], s[:fn]) }
    recalls = scores.select { |s| s[:tp] + s[:fn] > 0 }.map { |s| recall(s[:tp], s[:fp], s[:fn]) }
    p_avg = precisions.sum / precisions.size
    r_avg = recalls.sum / recalls.size
    f1 = 2 * p_avg * r_avg / (p_avg + r_avg)
    modes = scores.map { |s| s[:mode] }.tally.map { |mode, count| "#{mode}=#{count}" }.join(" ")
    puts format("%-12s pages=%d  F1=%.3f  precision=%.3f  recall=%.3f  %.1f ms/page  %s",
                corpus, scores.size, f1, p_avg, r_avg, seconds / scores.size * 1000, modes)
  end

  def report_worst(scores, count)
    scores.min_by(count) { |s| s[:tp] }.each do |s|
      puts format("  %-40s p=%.2f r=%.2f %s", s[:id], precision(s[:tp], s[:fp], s[:fn]), recall(s[:tp], s[:fp], s[:fn]), s[:mode])
    end
  end
end

if $PROGRAM_NAME == __FILE__
  corpus, path = ARGV
  abort "usage: ruby benchmark/quality.rb scrapinghub|mozilla PATH [--worst N]" unless %w[scrapinghub mozilla].include?(corpus) && path
  worst = ARGV.include?("--worst") ? ARGV[ARGV.index("--worst") + 1].to_i : 0
  dump = ARGV.include?("--dump") ? ARGV[ARGV.index("--dump") + 1] : nil
  Quality.run(corpus, path, worst: worst, dump: dump)
end
