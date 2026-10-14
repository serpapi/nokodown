# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# CI pins the version SerpApi runs in production (NOKOLEXBOR_VERSION=0.6.4).
nokolexbor_version = ENV["NOKOLEXBOR_VERSION"].to_s
gem "nokolexbor", nokolexbor_version unless nokolexbor_version.empty?

gem "rake", "~> 13.0"
gem "rspec", "~> 3.12"
