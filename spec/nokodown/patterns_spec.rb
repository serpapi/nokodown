# frozen_string_literal: true

require "spec_helper"

RSpec.describe Nokodown::Patterns do
  # Every string a pattern's branches spell out, for the patterns here:
  # groups, alternation, "?" and "+", with lookarounds left out (they only
  # narrow a match) and \d read as "1".
  def spellings(source)
    @source = source.gsub(/\s+/, "")
    @at = 0
    alternatives
  end

  def alternatives
    found = sequence
    while @source[@at] == "|"
      @at += 1
      found += sequence
    end
    found
  end

  def sequence
    found = [""]
    until @at >= @source.size || "|)".include?(@source[@at])
      atom = self.atom
      atom += [""] if @source[@at] == "?"
      @at += 1 if "?+".include?(@source[@at].to_s)
      found = found.product(atom).map(&:join)
    end
    found
  end

  def atom
    char = @source[@at]
    @at += 1
    case char
    when "\\" then (@at += 1) && [@source[@at - 1] == "d" ? "1" : @source[@at - 1]]
    when "[" then (@at = @source.index("]", @at) + 1) && [@source[@at - 2]]
    when "(" then group
    else [char]
    end
  end

  def group
    lookaround = @source[@at, 3].match?(/\A\?<?[!=]/)
    @at += lookaround ? 3 : 2
    @at += 1 if lookaround && @source[@at - 1] == "<"
    found = alternatives
    @at += 1
    lookaround ? [""] : found
  end

  # Boilerplate and the scorers check a name for these words before running
  # the slow patterns, which only gives the same answer while every name a
  # pattern matches holds one of the words.
  { CHROME: :FURNITURE_HINT, NOISE: :FURNITURE_HINT, SECONDARY: :SECONDARY_HINT }.each do |pattern, hint|
    it "finds a #{hint} word in every name #{pattern} matches" do
      names = spellings(described_class.const_get(pattern).source)

      names.size.should > 10
      names.reject { |name| name.match?(described_class.const_get(pattern)) }.should == []
      names.reject { |name| name.match?(described_class.const_get(hint)) }.should == []
    end
  end

  it "answers furniture? and secondary? as the full patterns do" do
    ["site-footer", "cookie-banner", "ad-slot", "share-bar", "post-body", "article-content", "comments", "tag-cloud", "tag-news"].each do |name|
      described_class.furniture?(name).should == name.match?(described_class::PAGE_FURNITURE)
      described_class.secondary?(name).should == name.match?(described_class::SECONDARY)
    end
  end

  it "weighs hid as a class name of its own only" do
    ["hid", "a hid", "hid b", "a hid b", "a\nhid", "hid\tb"].each { |value| value.should match(described_class::NEGATIVE) }
    ["ahid", "hidx", "a-hid", "hid_b"].each { |value| value.should_not match(described_class::NEGATIVE) }
  end
end
