# frozen_string_literal: true

# Extraction time per page over a directory of .html or .html.gz files.
# Each page is extracted once to warm up, then timed over several runs; the
# median run counts.
#
#   ruby benchmark/speed.rb DIRECTORY [--runs 5] [--per-page]

require "zlib"
require_relative "../lib/readable_markdown"

module Speed
  module_function

  def run(directory, runs:, per_page:)
    files = Dir[File.join(directory, "**", "*.{html,html.gz}")].sort
    abort "no .html or .html.gz files under #{directory}" if files.empty?

    timings = files.map do |path|
      html = read(path)
      ReadableMarkdown.extract(html)
      ms = median(Array.new(runs) { time { ReadableMarkdown.extract(html) } })
      puts format("%8.1f ms  %6d KB  %s", ms, html.bytesize / 1024, path.delete_prefix("#{directory}/")) if per_page
      ms
    end
    report(timings)
  end

  def read(path)
    path.end_with?(".gz") ? Zlib::GzipReader.open(path, &:read) : File.binread(path)
  end

  def time
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
  end

  def median(values)
    values.sort[values.size / 2]
  end

  def report(timings)
    sorted = timings.sort
    puts format("pages=%d  median=%.1f ms  p90=%.1f ms  p99=%.1f ms  max=%.1f ms  (ruby %s, nokolexbor %s)",
                sorted.size, median(sorted), percentile(sorted, 0.9), percentile(sorted, 0.99), sorted.last,
                RUBY_VERSION, Nokolexbor::VERSION)
  end

  def percentile(sorted, fraction)
    sorted[(fraction * (sorted.size - 1)).round]
  end
end

if $PROGRAM_NAME == __FILE__
  directory = ARGV.first
  abort "usage: ruby benchmark/speed.rb DIRECTORY [--runs N] [--per-page]" unless directory && File.directory?(directory)

  runs = ARGV.include?("--runs") ? ARGV[ARGV.index("--runs") + 1].to_i : 5
  Speed.run(directory.chomp("/"), runs: runs, per_page: ARGV.include?("--per-page"))
end
