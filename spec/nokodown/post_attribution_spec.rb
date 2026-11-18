# frozen_string_literal: true

RSpec.describe Nokodown::PostAttribution do
  def thread(posts, head: '<meta name="generator" content="XenForo">')
    Nokodown.to_markdown(
      "<html><head>#{head}<title>Sourdough starter smells like acetone</title></head><body>" \
      "<nav><a href='/'>Forums</a> <a href='/baking'>Baking</a></nav><main><h1>Sourdough starter smells like acetone</h1>" \
      "<div class='posts'>#{posts.join}</div></main></body></html>",
      url: "https://example.com/threads/starter"
    )
  end

  # A panel with the author's name, rank and post count beside the post,
  # whose date sits above its body.
  def post(name, time, body)
    "<article class='message'>" \
      "<section class='message-panel'><a class='avatar' href='/members/#{name}'><img src='/avatars/#{name}.jpg' alt='#{name}'></a>" \
      "<a class='username' href='/members/#{name}'>#{name}</a> " \
      "<span class='rank'>Well-known member</span> <span class='count'>Messages: 1,204</span></section>" \
      "<div class='message-main'><header class='message-attribution'><a href='/posts/1'>#{time}</a> <a href='/posts/1'>#1</a></header>" \
      "<div class='message-content'><div class='bbWrapper'>#{body}</div></div>" \
      "<footer class='message-footer'><a href='/like'>Like</a> <a href='/reply'>Reply</a> <a href='/report'>Report this post</a></footer>" \
      "</div></article>"
  end

  let(:question) { "My starter smells like nail polish remover after two days in the fridge. Is it ruined, or just hungry?" }
  let(:answer) { "Just hungry. The acetone smell means the yeast ran out of food, so feed it twice at room temperature." }

  it "writes each post's author and date as one line before its body" do
    markdown = thread([
      post("wren", "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time>", question),
      post("basil", "<time datetime='2024-05-03T09:10:00Z'>May 3, 2024</time>", answer)
    ])

    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
    markdown.should include("**basil** · May 3, 2024\n\n#{answer}")
  end

  it "drops the header and the author panel the line replaces" do
    markdown = thread([
      post("wren", "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time>", question),
      post("basil", "<time datetime='2024-05-03T09:10:00Z'>May 3, 2024</time>", answer)
    ])

    ["#1", "/members/", "Well-known member", "Messages", "avatars"].each { |noise| markdown.should_not include(noise) }
  end

  # XenForo prints the name twice: in the member panel beside the post and in
  # the header with the date.
  it "writes one line for a post whose member panel sits apart from its header" do
    posts = [["wren", question], ["basil", answer]].map do |name, body|
      user = "<h4 class='message-name'><a class='username' href='/members/#{name}'>#{name}</a></h4>"
      "<article class='message'>" \
        "<section class='message-user'><a class='avatar' href='/members/#{name}'><img src='/avatars/#{name}.jpg' alt='#{name}'></a>" \
        "#{user}<dl class='pairs'><dt>Joined</dt><dd>Jan 2020</dd></dl></section>" \
        "<div class='message-main'><header class='message-attribution'>#{user}" \
        "<a href='/posts/1'><time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></a></header>" \
        "<div class='message-content'><div class='bbWrapper'>#{body}</div></div></div></article>"
    end
    markdown = thread(posts)

    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
    markdown.should include("**basil** · May 3, 2024\n\n#{answer}")
    markdown.scan("**wren**").size.should == 1
    markdown.scan("**basil**").size.should == 1
    markdown.should_not include("Joined")
  end

  # Some XenForo themes repeat the post's date under the name in the member
  # panel, so the panel's cell reads as a post inside the post.
  it "writes the lines when the member panel repeats the post's date" do
    time = "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time>"
    posts = [["wren", question], ["basil", answer]].map do |name, body|
      "<article class='message'><div class='message-cell message-cell--user'><section class='message-user'>" \
        "<div class='message-userDetails'><h4 class='message-name'><a class='username' href='/members/#{name}'>#{name}</a></h4>" \
        "<div class='message-date'>#{time}</div></div>" \
        "<div class='message-userExtras'>Messages 1,204 Reaction score 3,310</div></section></div>" \
        "<div class='message-cell message-cell--main'><header class='message-attribution'><a href='/posts/1'>#{time}</a></header>" \
        "<div class='message-content'><div class='bbWrapper'>#{body}</div></div></div></article>"
    end
    markdown = thread(posts)

    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
    markdown.should include("**basil** · May 3, 2024\n\n#{answer}")
    markdown.should_not include("Reaction score")
  end

  it "shows a full date where the page shows a relative one" do
    markdown = thread([
      post("wren", "<time datetime='2024-04-02T05:03:15Z'><span>April 2, 2024</span><span>1 yr</span></time>", question),
      post("basil", "<time datetime='2024-04-02T07:41:00Z'>10 hours ago</time>", answer)
    ])

    markdown.should include("**wren** · April 2, 2024\n\n")
    markdown.should include("**basil** · 2024-04-02\n\n")
  end

  it "drops a copy of the date shown above the body" do
    time = "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time>"
    copy = "<div class='meta'><span class='date'>#{time}</span></div>"
    markdown = thread([post("wren", time, copy + question), post("basil", time.sub("08:45", "09:10"), answer)])

    markdown.scan("May 3, 2024").size.should == 2
  end

  it "writes a line for an opening post outside the list of replies" do
    entry = lambda do |kind, name, body|
      "<article class='#{kind}'><header>Posted by <span class='author'><a href='/u/#{name}'>#{name}</a></span> " \
        "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></header><div class='content'><p>#{body}</p></div></article>"
    end
    replies = [entry.call("reply", "basil", answer), entry.call("reply", "sage", "Feed it twice a day for three days and it will smell sweet.")]
    markdown = thread([entry.call("topic", "wren", question), "<section class='replies'>#{replies.join}</section>"])

    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
    markdown.should include("**basil** · May 3, 2024\n\n#{answer}")
  end

  it "keeps the line when the header is removed as an aside" do
    posts = [["wren", question], ["basil", answer]].map do |name, body|
      "<article class='entry'><aside class='entry-header'><h3><a class='username' href='/u/#{name}'>#{name}</a></h3> " \
        "<span>Members</span> <time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></aside>" \
        "<div class='entry-content'><p>#{body}</p></div></article>"
    end
    markdown = thread(posts)

    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
    markdown.should include("**basil** · May 3, 2024\n\n#{answer}")
  end

  it "takes the post's author, not the author of a post it quotes" do
    quote = "<blockquote><a class='username' href='/members/wren'>wren</a> said: " \
            "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time> Is it ruined?</blockquote>"
    markdown = thread([
      post("wren", "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time>", question),
      post("basil", "<time datetime='2024-05-03T09:10:00Z'>May 3, 2024</time>", quote + answer)
    ])

    markdown.should include("**basil** · May 3, 2024\n\n> [wren](https://example.com/members/wren) said:")
  end

  it "keeps a one-word reply after the line, not the footer" do
    markdown = thread([
      post("wren", "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time>", question),
      post("basil", "<time datetime='2024-05-03T09:10:00Z'>May 3, 2024</time>", "Agreed.")
    ])

    markdown.should include("**basil** · May 3, 2024\n\nAgreed.")
  end

  it "keeps a short reply without a body class after the line, not its signature" do
    posts = [["wren", question], ["basil", "Agreed."]].map do |name, body|
      "<div class='post'><div class='post-head'><a class='username' href='/u/#{name}'>#{name}</a> " \
        "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></div><div>#{body}</div>" \
        "<div class='signature'>Baking rye and spelt loaves since 1998, mostly by hand.</div></div>"
    end
    markdown = thread(posts)

    markdown.should include("**basil** · May 3, 2024\n\nAgreed.")
  end

  it "dates a post by its own date, not the member's join date" do
    posts = [["wren", question], ["basil", answer]].map do |name, body|
      "<div class='post'><div class='post-user'><a class='username' href='/u/#{name}'>#{name}</a> " \
        "<span>Joined <time datetime='2016-01-04'>Jan 4, 2016</time></span></div>" \
        "<div class='post-main'><div class='post-date'><time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></div>" \
        "<div class='post-text'>#{body}</div></div></div>"
    end
    markdown = thread(posts)

    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
    markdown.should include("**basil** · May 3, 2024\n\n#{answer}")
  end

  it "reads a date wrapped in another one from the inner date" do
    time = "<time class='date' title='Reply: 1'><time datetime='2024-07-03T15:30:35Z'>07/03/24 03:30 PM</time></time>"
    markdown = thread([post("wren", time, question), post("basil", time.sub("15:30", "16:10"), answer)])

    markdown.should include("**wren** · 2024-07-03\n\n#{question}")
  end

  it "drops an ad slot posted by an ad label, with no line for it" do
    time = "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time>"
    ad = "<p>Shop this season's best sourdough starter kits at our partner store.</p>"
    markdown = thread([post("wren", time, question), post("Advertisement", time, ad), post("basil", time, answer)])

    markdown.should include("**basil** · May 3, 2024\n\n#{answer}")
    markdown.should_not include("starter kits")
    markdown.should_not match(/^\s*· /)
  end

  it "keeps the posts of a member named Ad" do
    time = "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time>"
    markdown = thread([post("wren", time, question), post("Ad", time, answer)])

    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
    markdown.should include(answer)
  end

  it "writes no line for a name the cleanup would remove" do
    time = "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time>"
    markdown = thread([post("wren", time, question), post("Loading", time, answer)])

    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
    markdown.should_not match(/^\s*· /)
  end

  it "leaves answers signed below their body alone" do
    answers = [question, answer].map.with_index do |body, index|
      "<div class='answer'><div class='post-text'><p>#{body}</p></div>" \
        "<div class='signature'>answered <time datetime='2024-05-0#{index + 3}T08:45:00Z'>May #{index + 3}, 2024</time> " \
        "<a class='username' href='/users/#{index}'>user#{index}</a></div></div>"
    end
    markdown = thread(answers, head: '<script type="application/ld+json">{"@type": "QAPage"}</script>')

    markdown.should include(question)
    markdown.should_not include("**user")
  end

  it "leaves articles alone" do
    html = "<html><head><title>Harbor bridge reopens</title></head><body><article><h1>Harbor bridge reopens</h1>" \
           "<div class='byline'><a class='author' href='/staff/mara'>Mara Lindqvist</a> " \
           "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></div><p>#{question}</p><p>#{answer}</p></article></body></html>"

    Nokodown.to_markdown(html).should_not include("**Mara Lindqvist**")
  end
end
