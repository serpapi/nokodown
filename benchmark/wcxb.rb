# frozen_string_literal: true

# Extraction quality on WCXB, 2,008 human-reviewed pages of seven types
# (article, product, collection, listing, forum, documentation, service):
# https://github.com/Murrough-Foley/web-content-extraction-benchmark
#
# Scoring follows the benchmark's evaluate.py: word-level precision, recall and
# F1 against the reference main content, averaged per page, plus the share of
# "with" snippets found and of "without" (boilerplate) snippets leaked. The
# Markdown is converted back to plain text first, as the reference is plain.
#
#   ruby benchmark/wcxb.rb PATH_TO_CHECKOUT [dev|test] [--dump scores.json]

require "json"
require "zlib"
require_relative "../lib/nokodown"

module Wcxb
  TYPES = %w[article product collection listing forum documentation service].freeze

  module_function

  def words(text)
    text.downcase.scan(/[[:word:]]+/)
  end

  def scores(predicted, reference)
    predicted = words(predicted)
    reference = words(reference)
    return predicted.empty? ? [1.0, 1.0, 1.0] : [0.0, 0.0, 0.0] if reference.empty?
    return [0.0, 0.0, 0.0] if predicted.empty?

    predicted_counts = predicted.tally
    overlap = reference.tally.sum { |word, count| [count, predicted_counts.fetch(word, 0)].min }
    precision = overlap.fdiv(predicted.size)
    recall = overlap.fdiv(reference.size)
    f1 = precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0.0
    [precision, recall, f1]
  end

  def snippet_rate(text, snippets)
    return if snippets.empty?

    haystack = squash(text)
    snippets.count { |snippet| haystack.include?(squash(snippet)) }.fdiv(snippets.size)
  end

  def squash(text)
    text.downcase.gsub(/\s+/, " ").strip
  end

  def plain_text(markdown)
    markdown.gsub(/!\[[^\]]*\]\((?:[^()\s]|\([^)]*\))*\)/, "")
            .gsub(/\[([^\]]*)\]\((?:[^()\s]|\([^)]*\))*\)/, '\1')
            .gsub(/^(?:`{3,}|~{3,}).*$/, "")
            .gsub(/^\|?(?:\s*:?-{3,}:?\s*\|)+\s*$/, "")
            .gsub(/^\s{0,3}#+\s+/, "")
            .gsub(/^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ x]\]\s+)?/, "")
            .gsub(/^\s*>\s?/, "")
            .tr("|", " ")
            .gsub(%r{</?su[pb]>}, "")
            .gsub(/\*\*|__|\*|~~|`/, "")
            .gsub(/\\([\\`*_{}\[\]()#+\-.!|<>~])/, '\1')
  end

  def pages(path, split)
    Dir[File.join(path, split, "ground-truth", "*.json")].sort.map do |file|
      data = JSON.parse(File.read(file))
      id = File.basename(file, ".json")
      type = data.dig("_internal", "page_type", "primary") || "article"
      truth = data["ground_truth"] || {}
      html = Zlib::GzipReader.open(File.join(path, split, "html", "#{id}.html.gz"), &:read)
      { id: id, url: data["url"], type: type == "category" ? "collection" : type, html: html, truth: truth }
    end
  end

  def run(path, split, dump: nil)
    rows = pages(path, split).map { |page| score(page) }
    report("#{split} (#{rows.size} pages)", rows)
    TYPES.each { |type| report("  #{type}", rows.select { |row| row[:type] == type }) }
    File.write(dump, JSON.pretty_generate(rows)) if dump
  end

  def score(page)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    markdown = Nokodown.to_markdown(page[:html], url: page[:url])
    milliseconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
    text = plain_text(markdown)
    precision, recall, f1 = scores(text, page[:truth]["main_content"].to_s)
    { id: page[:id], type: page[:type], precision: precision, recall: recall, f1: f1,
      with: snippet_rate(text, page[:truth]["with"] || []), without: snippet_rate(text, page[:truth]["without"] || []),
      characters: markdown.size, milliseconds: milliseconds }
  end

  def report(label, rows)
    return if rows.empty?

    mean = ->(key) { values = rows.map { |row| row[key] }.compact; values.sum / values.size }
    puts format("%-18s F1=%.3f  precision=%.3f  recall=%.3f  with=%5.1f%%  without=%4.1f%%  %6.0f chars/page  %.1f ms/page",
                label, mean.call(:f1), mean.call(:precision), mean.call(:recall), mean.call(:with) * 100,
                mean.call(:without) * 100, mean.call(:characters), mean.call(:milliseconds))
  end
end

if $PROGRAM_NAME == __FILE__
  path = ARGV.first
  abort "usage: ruby benchmark/wcxb.rb PATH [dev|test] [--dump scores.json]" unless path && File.directory?(path)

  split = %w[dev test].include?(ARGV[1]) ? ARGV[1] : "dev"
  dump = ARGV.include?("--dump") ? ARGV[ARGV.index("--dump") + 1] : nil
  Wcxb.run(path, split, dump: dump)
end
