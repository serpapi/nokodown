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

  it "writes one line where the member panel beside the post names the poster too" do
    posts = [["wren", question], ["basil", answer]].map do |name, body|
      "<article class='message'><div class='message-user'><a class='avatar' href='/members/#{name}'><img src='/avatars/#{name}.jpg' alt='#{name}'></a>" \
        "<h4 class='message-name'><a class='username' href='/members/#{name}'>#{name}</a></h4><h5 class='message-userTitle'>Well-known member</h5></div>" \
        "<div class='message-main'><header class='message-attribution'><a class='username' href='/members/#{name}'>#{name}</a> " \
        "<a href='/posts/1'><time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></a></header>" \
        "<div class='message-content'><div class='bbWrapper'>#{body}</div></div></div></article>"
    end
    markdown = thread(posts)

    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
    markdown.should include("**basil** · May 3, 2024\n\n#{answer}")
    markdown.scan(/\*\*(?:wren|basil)\*\*/).size.should == 2
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
    markdown.scan(/\*\*(?:wren|basil)\*\*/).size.should == 2
    markdown.should_not include("Reaction score")
  end

  # Class names that read as a member panel ("user-info") turn up inside
  # posts too: in a sentence, in code, around a quoted post's author. The
  # body may be one element or the run of elements after the header.
  it "keeps what a post's body holds under a member panel's class" do
    quote = "<blockquote><div class='message-user'><a class='username' href='/members/celia'>celia</a></div>" \
            "<p>Rye flour wakes a sluggish starter faster than anything else I have tried.</p></blockquote>"
    bodies = [
      ["wren", "<p>I keep it beside a bowl of <span class='user-info'>green apples</span> all night.</p>#{quote}<p>#{question}</p>"],
      ["basil", "<p>#{answer}</p><pre><code>feed(<span class='userinfo'>starter</span>)</code></pre>"]
    ]
    [->(body) { "<div class='message-content'><div class='bbWrapper'>#{body}</div></div>" }, ->(body) { body }].each do |wrap|
      posts = bodies.map do |name, body|
        user = "<h4 class='message-name'><a class='username' href='/members/#{name}'>#{name}</a></h4>"
        "<article class='message'><section class='message-user'>#{user}<dl class='pairs'><dt>Joined</dt><dd>Jan 2020</dd></dl></section>" \
          "<div class='message-main'><header class='message-attribution'>#{user}" \
          "<a href='/posts/1'><time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></a></header>#{wrap.call(body)}</div></article>"
      end
      markdown = thread(posts)

      markdown.should include("a bowl of green apples all night")
      markdown.should include("feed(starter)")
      markdown.should include("celia")
      markdown.scan(/\*\*(?:wren|basil)\*\*/).size.should == 2
    end
  end

  # Replies nested in a post, and not attributed themselves, are named only
  # by their own member panels, dated or not.
  it "keeps the member panel of a reply nested in a post" do
    comment = lambda do |name, day, body, replies: "", head: true, panel: ""|
      "<div class='comment'><div class='user-info'><a class='username' href='/u/#{name}'>#{name}</a> Posts: 12#{panel}</div>" \
        "#{"<div class='comment-head'><time datetime='2024-05-0#{day}T08:45:00Z'>May #{day}, 2024</time></div>" if head}" \
        "<div class='comment-body'><p>#{body}</p></div>#{replies}</div>"
    end
    [
      comment.call("basil", 4, answer),
      comment.call("basil", 3, answer),
      comment.call("basil", 4, answer, head: false),
      comment.call("basil", 4, answer, head: false, panel: " <time datetime='2024-05-04T08:45:00Z'>May 4, 2024</time>")
    ].each do |reply|
      markdown = thread([comment.call("wren", 3, question, replies: "<div class='replies'>#{reply}</div>"), comment.call("fern", 5, question.upcase)])

      markdown.should include("**wren** · May 3, 2024\n\n#{question}")
      markdown.should include("**fern** · May 5, 2024")
      markdown.should match(/\*\*basil\*\*.*\n\n(?:May [34], 2024\n\n)?#{Regexp.escape(answer)}/)
      markdown.scan(/\*\*(?:wren|fern)\*\*/).size.should == 2
    end
  end

  # A date of the member's own ("Last post") does not make the panel a
  # post, in the post or in a cell beside it. The panel's line keeps the
  # date, as "Last posted" may date the post too.
  it "writes the post's line when the member panel holds a date of its own" do
    user = ->(name) { "<h4 class='message-name'><a class='username' href='/members/#{name}'>#{name}</a></h4>" }
    main = lambda do |name, body, cell = "message-main"|
      "<div class='#{cell}'><header class='message-attribution'>#{user.call(name)}" \
        "<a href='/posts/1'><time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></a></header>" \
        "<div class='message-content'><div class='bbWrapper'>#{body}</div></div></div>"
    end
    panel = ->(name) { "<section class='message-user'>#{user.call(name)}<div>Last post <time datetime='2024-06-01T10:00:00Z'>Jun 1, 2024</time></div></section>" }
    layouts = [
      ->(name, body) { "<article class='message'>#{main.call(name, body)}<div class='message-cell--user'>#{panel.call(name)}</div></article>" },
      lambda do |name, body|
        "<article class='message'><div class='message-inner'><div class='message-cell message-cell--user'>#{panel.call(name)}</div>" \
          "#{main.call(name, body, 'message-cell message-cell--main')}</div></article>"
      end
    ]
    layouts.each do |layout|
      markdown = thread([layout.call("wren", question), layout.call("basil", answer)])

      markdown.should include("**wren** · May 3, 2024\n\n#{question}")
      markdown.should include("**basil** · May 3, 2024\n\n#{answer}")
      markdown.scan(/\*\*(?:wren|basil)\*\*(?! · Last post)/).size.should == 2
      markdown.scan("Last post Jun 1, 2024").size.should be <= 2
    end
  end

  # The panel's cell may be a plain div, or share the post's class.
  it "writes one line when the member panel stands in a cell of its own" do
    user = ->(name) { "<a class='username' href='/members/#{name}'>#{name}</a>" }
    rest = lambda do |name, day|
      "<div class='message-main'><header class='message-attribution'>#{user.call(name)} " \
        "<time datetime='2024-05-0#{day}T08:45:00Z'>May #{day}, 2024</time></header>" \
        "<div class='message-content'><p>#{name == 'wren' ? question : answer}</p></div></div>"
    end
    layouts = [
      ->(name, day) { "<div id='post-#{day}'><div><section class='message-user'>#{user.call(name)}</section></div>#{rest.call(name, day)}</div>" },
      lambda do |name, day|
        "<article class='message'><div class='message message-cell--user'><section class='message-user'>#{user.call(name)}</section></div>" \
          "#{rest.call(name, day)}</article>"
      end
    ]
    layouts.each do |layout|
      markdown = thread([layout.call("wren", 3), layout.call("basil", 5)])

      markdown.should include("**wren** · May 3, 2024\n\n#{question}")
      markdown.should include("**basil** · May 5, 2024\n\n#{answer}")
      markdown.scan(/\*\*(?:wren|basil)\*\*/).size.should == 2
    end
  end

  # The rest of the panel's column (a rank, a post count) stands between the
  # panel's line and the post's.
  it "writes one line when the member panel's column holds more" do
    ["<p class='userTitle'>Moderator</p>", "<p>Posts: 41</p>"].each do |extra|
      posts = [["wren", 3, question], ["basil", 5, answer]].map do |name, day, body|
        user = "<a class='username' href='/members/#{name}'>#{name}</a>"
        "<article class='message'><div class='message-cell--user'><section class='message-user'>#{user}</section>#{extra}</div>" \
          "<div class='message-main'><header class='message-attribution'>#{user} <time datetime='2024-05-0#{day}T08:45:00Z'>May #{day}, 2024</time></header>" \
          "<div class='message-content'><p>#{body}</p></div></div></article>"
      end
      markdown = thread(posts)

      markdown.should include("**wren** · May 3, 2024\n\n#{question}")
      markdown.should include("**basil** · May 5, 2024\n\n#{answer}")
      markdown.scan(/\*\*(?:wren|basil)\*\*/).size.should == 2
    end
  end

  # Which lines go is settled once the content is pruned: a shorter post
  # reads as more of a link list.
  it "keeps a short post whole that links out" do
    linked = "<div class='message'><div class='message-user'><a class='username' href='/members/SourdoughBaker'>SourdoughBaker</a></div>" \
             "<header><a class='username' href='/members/SourdoughBaker'>SourdoughBaker</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
             "<p>Keep enough room in the jar for a full rise. <a href='/guide'>Feeding instructions</a></p></div>"
    markdown = thread([linked, post("basil", "<time datetime='2024-05-04T09:10:00Z'>May 4, 2024</time>", "<p>#{answer}</p><p>#{question}</p>")])

    markdown.should include("**SourdoughBaker** · May 3, 2024\n\nKeep enough room in the jar for a full rise. [Feeding instructions]")
    markdown.scan("**SourdoughBaker**").size.should == 1
  end

  # A panel after the body, with more after it, names a reply or a quote,
  # however short, and by the poster too.
  it "keeps the member panel's line before a reply or a quote of the poster's" do
    user = "<a class='username' href='/members/wren'>wren</a>"
    head = "<div class='message-main'><header>#{user} <time>May 3, 2024</time></header><p>#{question}</p>"
    [
      "#{head}</div><div class='response'><div class='message-user'>#{user} <time>May 4, 2024 at 08:45 UTC</time></div>" \
        "<div><a href='/mixing-log.pdf'>Log</a></div></div>",
      "#{head}<div class='quote'><div class='message-user'>#{user}</div><span>I agree.</span></div></div>",
      "#{head}<div class='message-user'>#{user}<time>May 2, 2024</time></div><p>That advice worked.</p></div>",
      "#{head}</div><div class='response'><div class='message-user'>#{user}</div><ul><li><input type='checkbox' checked></li></ul></div>"
    ].each do |inner|
      markdown = thread([
        "<article class='message'><div class='message-user'>#{user}</div>#{inner}</article>",
        post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
      ])

      markdown.should include("**wren** · May 3, 2024\n\n#{question}")
      markdown.should match(/#{Regexp.escape(question)}\n\n\*\*wren\*\*( · May [42], 2024( at 08:45 UTC)?)?\n\n(\[Log\]|I agree\.|That advice worked\.|\*\*basil\*\*)/)
    end
  end

  # A quote, or a reply the post holds, before the post's header or after
  # its body is the poster's too, and the panel's line is all that names it:
  # in the quote, in its caption or credit, or under a quote's class.
  it "keeps the member panel's line in a quote or a reply of the poster's" do
    user = "<a class='username' href='/members/wren'>wren</a>"
    head = "<header>#{user} <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p>"
    panel = "<div class='message-user'>#{user}</div>"
    {
      "<div class='quote'><div class='message-user'>#{user}</div><span>I agree.</span></div>#{head}" => "I agree.",
      "<div class='quote'><div class='message-user'>#{user}</div><img src='/starter.png' alt='Starter photo'></div>#{head}" => "![Starter photo]",
      "<article class='message'><div class='message-user'>#{user}</div><p>I agree.</p></article>#{head}" => "I agree.",
      "#{head}<div class='quote'><div class='message-user'>#{user}</div><math alttext='2^{10}=1024'></math></div>" => "$2^{10}=1024$",
      "<figure><figcaption>#{panel}</figcaption><blockquote><p>I agree.</p></blockquote></figure>#{head}" => "> I agree.",
      "<q><span class='message-user'>#{user}</span>Yes.</q>#{head}" => "Yes.",
      "<div><cite>#{panel}</cite><blockquote>I fed mine twice.</blockquote></div>#{head}" => "> I fed mine twice.",
      "<details><summary>Earlier reply</summary>#{panel}<blockquote>I fed mine twice.</blockquote></details>#{head}" => "> I fed mine twice.",
      "<div class='quote-author user-info'>#{user}</div><p>I agree.</p>#{head}" => "I agree.",
      "<div class='blockquote'>#{panel}<p>I agree.</p></div>#{head}" => "I agree."
    }.each do |inner, shown|
      markdown = thread([
        "<article class='message'><div class='message-user'>#{user}</div>#{inner}</article>",
        post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
      ])

      markdown.should include("**wren** · May 3, 2024\n\n#{question}")
      markdown.should include("**wren**\n\n#{shown}")
    end

    markdown = thread([
      "<article class='message'>#{panel}#{head}<figure><blockquote>I fed mine twice.</blockquote>" \
      "<figcaption class='message-user'>#{user}</figcaption></figure></article>",
      post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
    ])

    markdown.should include("> I fed mine twice.\n\n**wren**\n\n**basil**")
  end

  # A reply nested in a post is no post of its own, whatever its classes
  # add to the post's or however they are ordered.
  it "keeps the member panel's line of a reply in a post of its kind" do
    user = "<a class='username' href='/members/wren'>wren</a>"
    head = "<header>#{user} <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p>"
    [["message unread", "unread message"], ["message dark", "message light"]].each do |outer, inner|
      markdown = thread([
        "<article class='#{outer}' id='post-435'><article class='#{inner}' id='post-436'><div class='message-user'>#{user}</div>" \
        "<p>I agree.</p></article>#{head}</article>",
        post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
      ])

      markdown.should include("**wren**\n\nI agree.\n\n**wren** · May 3, 2024\n\n#{question}")
    end
  end

  # The same name may be another member's, or come with a fuller date.
  it "keeps the member panel's line where it says more than the post's" do
    posts = [
      ["<a class='username' href='/members/101'>Wren</a>", "<a class='username' href='/members/202'>wren</a> <time>May 3, 2024</time>"],
      ["<a class='username' href='/members/WREN'>Wren</a>", "<a class='username' href='/members/wren'>wren</a> <time>May 3, 2024</time>"],
      ["<a class='username' href='https://bakers.example.net/members/wren'>Wren</a>",
       "<a class='username' href='https://example.com/members/wren'>wren</a> <time>May 3, 2024</time>"],
      ["<a class='username' href='https://elsewhere.example/members/wren'>Wren</a>", "<a class='username' href='/members/wren'>wren</a> <time>May 3, 2024</time>"],
      ["<a href='/members/72'><span class='username'>Wren</span><span class='badge'>Pro</span></a>",
       "<a class='username' href='/members/84'>wren</a> <time>May 3, 2024</time>"],
      ["<a class='username' href='/members/72'>Wren</a>", "<a href='/members/84'><span class='username'>wren</span></a> <time>May 3, 2024</time>"],
      ["<a class='username' href='/members/72'>Wren</a>",
       "<span itemprop='author'><a href='/members/72'>Team</a><a href='/members/84' itemprop='name'>wren</a></span> <time>May 3, 2024</time>"],
      ["<a class='username' href='/users#/profiles/191'>Wren</a>", "<a class='username' href='/users#/profiles/105'>wren</a> <time>May 3, 2024</time>"],
      ["<a class='username' href='/members/wren'>wren</a><div class='post-time'>May 3, 2024 at 08:45 UTC</div>",
       "<a class='username' href='/members/wren'>wren</a> <time>May 3, 2024</time>"],
      ["<a class='username' href='/members/wren'>wren</a><span class='post-date'>May 3, 2024</span>",
       "<a class='username' href='/members/wren'>wren</a> <time>Yesterday</time>"]
    ]
    posts.each do |panel, header|
      markdown = thread([
        "<article class='message'><div class='message-user'>#{panel}</div><div class='message-main'><header>#{header}</header><p>#{question}</p></div></article>",
        post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
      ])

      markdown.scan(/\*\*wren\*\*/i).size.should == 2
      markdown.should include("#{question}")
    end
  end

  # One profile, however its link is written.
  it "writes one line where the member panel links to the post's profile" do
    ["../members/wren", "https://example.com:443/members/wren/"].each do |link|
      markdown = thread([
        "<article class='message'><div class='message-user'><a class='username' href='#{link}'>wren</a></div>" \
        "<div class='message-main'><header><a class='username' href='/members/wren'>wren</a> <time>May 3, 2024</time></header>" \
        "<p>#{question}</p></div></article>",
        post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
      ])

      markdown.should include("**wren** · May 3, 2024\n\n#{question}")
      markdown.scan("**wren**").size.should == 1
    end
  end

  # A panel in a link renders as the link to the member's profile.
  it "keeps the member panel's line that links to the profile" do
    markdown = thread([
      "<article class='message'><a class='member-card' href='/members/101'><div class='message-user'><span class='username'>wren</span></div></a>" \
      "<header><a class='username' href='/members/wren'>wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p></article>",
      post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
    ])

    markdown.should include("[**wren**](https://example.com/members/101)")
    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
  end

  # The post's line may go where nothing renders it: between a table's
  # rows, or a list's terms.
  it "keeps the member panel's line where the post's line is not shown" do
    layouts = [
      lambda do |name, day, body|
        user = "<a class='username' href='/members/#{name}'>#{name}</a>"
        "<table class='tborder'><tr><td><div class='message-user'>#{user}</div></td></tr>" \
          "<tr><td><header>#{user} <time datetime='2024-05-0#{day}'>May #{day}, 2024</time></header></td></tr><tr><td><p>#{body}</p></td></tr></table>"
      end,
      lambda do |name, day, body|
        user = "<a class='username' href='/members/#{name}'>#{name}</a>"
        "<article class='message'><dl><dd><div class='message-user'>#{user}</div></dd>" \
          "<header>#{user} <time datetime='2024-05-0#{day}'>May #{day}, 2024</time></header><dd><p>#{body}</p></dd></dl></article>"
      end
    ]
    layouts.each do |layout|
      markdown = thread([layout.call("wren", 3, question), layout.call("basil", 5, answer)])

      markdown.should match(/\*\*wren\*\*.*\n\n(- )?#{Regexp.escape(question)}|\*\*wren\*\*; #{Regexp.escape(question)}/)
      markdown.should match(/\*\*basil\*\*.*\n\n(- )?#{Regexp.escape(answer)}|\*\*basil\*\*; #{Regexp.escape(answer)}/)
    end
  end

  # A table drops a cell that shows nothing, and with its column the
  # table's caption: a panel's line keeps the cell where it shows more.
  it "keeps the member panel's cell that shows more than the line" do
    row = lambda do |name, day, body, extra|
      user = "<a class='username' href='/members/#{name}'>#{name}</a>"
      "<tr><td>#{extra}<div class='message-user'>#{user}</div></td>" \
        "<td><header>#{user} <time datetime='2024-05-0#{day}'>May #{day}, 2024</time></header><p>#{body}</p></td></tr>"
    end
    {
      ["<table><caption><a href='/archives/friday'>Friday fermentation log</a></caption>", ""] => "[Friday fermentation log](https://example.com/archives/friday)",
      ["<table role='presentation'>", "<iframe src='https://www.youtube.com/embed/abcd1234567' title='Starter demonstration'></iframe>"] =>
        "[Starter demonstration](https://www.youtube.com/watch?v=abcd1234567)",
      ["<table role='presentation'>", "<math alttext='2^3'></math>"] => "$2^3$"
    }.each do |(open, extra), shown|
      markdown = thread(["#{open}#{row.call('wren', 3, question, extra)}#{row.call('basil', 5, answer, '')}</table>"],
                        head: '<meta name="generator" content="vBulletin">')

      markdown.should include(shown)
      markdown.should include(question)
      markdown.should include(answer)
    end
  end

  # Boilerplate removes a share bar the post's line was to go above.
  it "keeps the poster's name where the post's line has no place" do
    posts = [["wren", 3, question], ["basil", 5, answer]].map do |name, day, body|
      user = "<a class='username' href='/members/#{name}'>#{name}</a>"
      time = "<time datetime='2024-05-0#{day}'>May #{day}, 2024</time>"
      "<article class='message'><div class='message-cell message-cell--user'><div class='message-user'>#{user}</div><div>#{time}</div></div>" \
        "<div class='message-cell message-cell--main'><header>#{user} #{time}</header>" \
        "#{"<div class='share-buttons'>Share this post with other bakers</div>" if name == 'wren'}<p>#{body}</p></div></article>"
    end
    markdown = thread(posts)

    markdown.should match(/\*\*wren\*\*.*\n\n(May 3, 2024\n\n)?#{Regexp.escape(question)}/)
    markdown.should include("**basil** · May 5, 2024\n\n#{answer}")
    markdown.scan("**basil**").size.should == 1
  end

  it "shows a full date where the page shows a relative one" do
    markdown = thread([
      post("wren", "<time datetime='2024-04-02T05:03:15Z'><span>April 2, 2024</span><span>1 yr</span></time>", question),
      post("basil", "<time datetime='2024-04-02T07:41:00Z'>10 hours ago</time>", answer)
    ])

    markdown.should include("**wren** · April 2, 2024\n\n")
    markdown.should include("**basil** · 2024-04-02\n\n")
  end

  it "shows a relative date as the page does when it has no other" do
    markdown = thread([
      post("wren", "<time>Yesterday at 10:40</time>", question),
      post("basil", "<time>Today at 09:30</time>", answer)
    ])

    markdown.should include("**wren** · Yesterday at 10:40\n\n#{question}")
    markdown.should include("**basil** · Today at 09:30\n\n#{answer}")
  end

  it "drops a copy of the date shown above the body" do
    time = "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time>"
    copy = "<div class='meta'><span class='date'>#{time}</span></div>"
    markdown = thread([post("wren", time, copy + question), post("basil", time.sub("08:45", "09:10"), answer)])

    markdown.scan("May 3, 2024").size.should == 2
  end

  it "keeps a date that is the body's text: a reply that is a date, a date after the text, a quoted date" do
    entry = lambda do |name, at, body|
      "<div class='post'><div class='post-head'><a class='username' href='/u/#{name}'>#{name}</a> " \
        "<time datetime='2024-05-03T#{at}:00Z'>May 3, 2024</time></div><div class='post-body'>#{body}</div></div>"
    end
    date = ->(at) { "<span><time datetime='2024-05-03T#{at}:00Z'>May 3, 2024</time></span>" }
    markdown = thread([
      entry.call("wren", "08:45", "<p>#{question}</p><p>#{date.call('08:45')}</p>"),
      entry.call("carol", "09:10", "<p>#{date.call('09:10')}</p>"),
      entry.call("basil", "09:10", "<blockquote><p>Booked for #{date.call('09:10')}</p></blockquote><p>#{answer}</p>")
    ])

    markdown.should include("#{question}\n\nMay 3, 2024")
    markdown.should include("**carol** · May 3, 2024\n\nMay 3, 2024")
    markdown.should include("> Booked for May 3, 2024")
  end

  it "keeps the subject of each post when the header goes" do
    posts = [["wren", "Is it ruined?", question], ["basil", "Feed it twice at room temperature for two days", answer]].map do |name, subject, body|
      "<div class='post'><div class='post-head'><div class='post-info'><h2>#{subject}</h2><a class='username' href='/u/#{name}'>#{name}</a></div>" \
        "<div class='post-date'><time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></div></div><div class='post-body'><p>#{body}</p></div></div>"
    end
    markdown = thread(posts)

    markdown.should include("## Is it ruined?\n\n**wren** · May 3, 2024\n\n#{question}")
    markdown.should include("## Feed it twice at room temperature for two days\n\n**basil** · May 3, 2024\n\n#{answer}")
    markdown.should_not include("/u/")
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

  it "takes a body that has a signature for the body, not for the signature" do
    posts = [["wren", question], ["basil", answer]].map do |name, body|
      "<div class='post'><div class='post-head'><a class='username' href='/u/#{name}'>#{name}</a> " \
        "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></div><div class='post-text has-signature'><p>#{body}</p></div>" \
        "<div class='signature'>Baking rye and spelt loaves since 1998, mostly by hand.</div></div>"
    end
    markdown = thread(posts)

    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
    markdown.should include("**basil** · May 3, 2024\n\n#{answer}")
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

  it "finds the posts among many dated siblings in linear time" do
    posts = Array.new(2_000) do |index|
      "<div class='post-#{index} post'><div class='post-head'><a class='username' href='/u/#{index}'>member#{index}</a> " \
        "<time datetime='2024-05-03T08:45:00Z'>May 3, 2024</time></div><div class='post-body'><p>#{answer}</p></div></div>"
    end
    body = Nokolexbor::HTML("<html><body><div class='posts'>#{posts.join}</div></body></html>").at_css("body")
    Nokodown::Dom.assign_keys(body)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    described_class.new(body).call
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).should < 1
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
