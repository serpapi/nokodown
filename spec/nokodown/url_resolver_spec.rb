# frozen_string_literal: true

RSpec.describe Nokodown::UrlResolver do
  describe "#current_page?" do
    let(:urls) { described_class.new("https://example.com/category/%E3%83%A1/?sort=new") }

    it "matches links to the page whatever their scheme, host prefix, trailing slash or escape case" do
      urls.current_page?("http://www.example.com/category/%e3%83%a1?sort=new").should == true
      urls.current_page?("?sort=new").should == true
    end

    it "does not match other pages or a part of the page" do
      urls.current_page?("/category/%E3%83%A1/?sort=old").should == false
      urls.current_page?("https://example.com:8080/category/%E3%83%A1/?sort=new").should == false
      urls.current_page?("#comments").should == false
      urls.current_page?("javascript:void(0)").should == false
    end

    it "reads a path with a run of thousands of slashes in linear time" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      urls.current_page?("/category#{"/" * 20_000}page").should == false

      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 0.5
    end
  end
end
