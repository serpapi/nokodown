# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

# Public corpora used by the benchmarks, pinned so scores are comparable between
# runs.
CORPORA = {
  "scrapinghub" => ["https://github.com/scrapinghub/article-extraction-benchmark.git", "4a3bc979f76c0df73cb95fe272e2fc1b96f9f010"],
  "mozilla" => ["https://github.com/mozilla/readability.git", "ab4027a8b37669745016869a37a504727992b2ba"],
  "wcxb" => ["https://github.com/Murrough-Foley/web-content-extraction-benchmark.git", "c039d5ee9f5a3a984a0e167e63aacd04e76e78a9"]
}.freeze

CORPORA_DIR = "tmp/corpora"

namespace :benchmark do
  desc "Download the benchmark corpora into #{CORPORA_DIR}"
  task :corpora do
    CORPORA.each do |name, (repository, commit)|
      path = File.join(CORPORA_DIR, name)
      next if File.directory?(path)

      mkdir_p path
      sh "git", "-C", path, "init", "--quiet"
      sh "git", "-C", path, "fetch", "--quiet", "--depth", "1", repository, commit
      sh "git", "-C", path, "checkout", "--quiet", "FETCH_HEAD"
    end
  end

  desc "Score extraction against the Scrapinghub, Mozilla and WCXB corpora"
  task quality: :corpora do
    %w[scrapinghub mozilla].each { |name| ruby "benchmark/quality.rb", name, File.join(CORPORA_DIR, name) }
    %w[dev test].each { |split| ruby "benchmark/wcxb.rb", File.join(CORPORA_DIR, "wcxb"), split }
  end

  desc "Time extraction over the Scrapinghub corpus"
  task speed: :corpora do
    ruby "benchmark/speed.rb", File.join(CORPORA_DIR, "scrapinghub", "html")
  end
end
