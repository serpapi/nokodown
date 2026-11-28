# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# CI also tests nokolexbor 0.6.4, the last release for Ruby 2.7 (NOKOLEXBOR_VERSION=0.6.4).
nokolexbor_version = ENV["NOKOLEXBOR_VERSION"].to_s
gem "nokolexbor", nokolexbor_version unless nokolexbor_version.empty?

gem "rake", "~> 13.0"
gem "rspec", "~> 3.12"
