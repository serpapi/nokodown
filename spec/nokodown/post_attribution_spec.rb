# frozen_string_literal: true

RSpec.describe Nokodown::PostAttribution do
  def thread(posts, head: '<meta name="generator" content="XenForo">', url: "https://example.com/threads/starter")
    Nokodown.to_markdown(
      "<html><head>#{head}<title>Sourdough starter smells like acetone</title></head><body>" \
      "<nav><a href='/'>Forums</a> <a href='/baking'>Baking</a></nav><main><h1>Sourdough starter smells like acetone</h1>" \
      "<div class='posts'>#{posts.join}</div></main></body></html>",
      url: url
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

  # Each cell reads as a post of its own: the panel holds the name and
  # the date, the main cell the post's line.
  it "writes one line when the member panel's cell and the post's cell both name the poster" do
    user = ->(name) { "<a class='username' href='/members/#{name}'>#{name}</a>" }
    post = lambda do |name, day|
      "<article class='message'><div class='message-inner'><div class='message-cell message-cell--user'>" \
        "<section class='message-user'><h4 class='message-name'>#{user.call(name)}</h4>" \
        "<div class='message-date'><time datetime='2024-05-0#{day}'>May #{day}, 2024</time></div></section></div>" \
        "<div class='message-cell message-cell--main'><header class='message-attribution'>#{user.call(name)} " \
        "<a href='/posts/#{day}'><time datetime='2024-05-0#{day}'>May #{day}, 2024</time></a></header>" \
        "<div class='message-content'><p>#{name == 'wren' ? question : answer}</p></div></div></div></article>"
    end
    markdown = thread([post.call("wren", 3), post.call("basil", 5)])

    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
    markdown.should include("**basil** · May 5, 2024\n\n#{answer}")
    markdown.scan(/\*\*(?:wren|basil)\*\*/).size.should == 2
  end

  # phpBB's prosilver: a list of the poster's details, then the post's
  # subject above the line naming the poster. Three or more lists repeat
  # like cards. The opening post's subject is the thread's title; a
  # localized board says "door", not "by".
  it "writes one line where the post's subject stands between the member panel and the post's line" do
    title = "Sourdough starter smells like acetone"
    %w[by door].each do |by|
      posts = [["wren", 3, title, question], ["basil", 5, "Re: Starter", answer], ["lark", 7, "Re: Starter", answer]]
      posts = posts.map do |name, day, subject, body|
        "<div id='p#{day}' class='post has-profile'><div class='inner'>" \
          "<dl class='postprofile'><dt><a class='username' href='/members/#{name}'>#{name}</a></dt>" \
          "<dd class='profile-posts'><strong>Posts:</strong> <a href='/search?author=#{name}'>41</a></dd>" \
          "<dd class='profile-joined'><strong>Joined:</strong> Fri Oct 14, 2016 12:00 pm</dd></dl>" \
          "<div class='postbody'><h3><a href='#p#{day}'>#{subject}</a></h3>" \
          "<p class='author'>#{by} <strong><a class='username' href='/members/#{name}'>#{name}</a></strong> " \
          "<time datetime='2024-05-0#{day}T08:45:00Z'>May #{day}, 2024</time></p><div class='content'>#{body}</div></div></div></div>"
      end
      [posts.first(2), posts].each do |thread_posts|
        markdown = thread(thread_posts, head: '<meta name="generator" content="phpBB">')

        markdown.should include("**wren** · May 3, 2024\n\n#{question}")
        markdown.should include("### Re: Starter\n\n**basil** · May 5, 2024\n\n#{answer}")
        markdown.scan(/\*\*(?:wren|basil|lark)\*\*/).size.should == thread_posts.size
      end
    end
  end

  # A long profile field ("About me") can outweigh the posts themselves;
  # the panel still gives way to the post's line.
  it "writes one line where a member panel's field outweighs the posts" do
    about = "I maintain the regional test kitchen and the technical archive for fermentation measurements. " * 8
    body = "The starter doubled in volume overnight after its second feeding. I used the original flour and a clean jar."
    posts = [["wren", 3, about], ["basil", 4, nil], ["iris", 5, nil]].map do |name, day, field|
      extra = field ? "<dd class='profile-custom-field profile-about_me'><strong>About me:</strong> #{field}</dd>" : ""
      "<div id='p#{day}' class='post has-profile bg1'><div class='inner'><dl class='postprofile' id='profile#{day}'>" \
        "<dt class='no-profile-rank no-avatar'><strong><span class='username'>#{name}</span></strong></dt>" \
        "<dd class='profile-posts'><strong>Posts:</strong> 6#{day}</dd>" \
        "<dd class='profile-joined'><strong>Joined:</strong> Mon Mar 05, 2018 12:08 am</dd>#{extra}</dl>" \
        "<div class='postbody'><div id='post_content#{day}'><h3><a href='#p#{day}'>Re: Starter</a></h3>" \
        "<p class='author'><span class='responsive-hide'>by <strong><span class='username'>#{name}</span></strong> &raquo; </span>" \
        "<time datetime='2024-05-0#{day}T08:45:00Z'>May #{day}, 2024</time></p><div class='content'>#{name} watched. #{body}</div></div></div></div></div>"
    end
    markdown = thread(posts, head: '<meta name="generator" content="phpBB">')

    markdown.should include("**wren** · May 3, 2024\n\nwren watched. #{body}")
    markdown.should_not include("About me")
    markdown.scan(/\*\*(?:wren|basil|iris)\*\*/).size.should == 3
  end

  # A board without profiles names the poster in no link; the posts count
  # links to a search, and a count or a contact menu names no other member.
  it "writes one line where the member panel names the poster in no link beside a linked post count" do
    contact = lambda do |day|
      "<dd class='profile-contact'><strong>Contact:</strong><a href='#' class='dropdown-trigger' title='Contact'><span class='sr-only'>Contact</span></a>" \
        "<a href='./ucp.php?i=pm&amp;mode=compose&amp;p=#{day}'><span class='contact-icon pm-icon'>Send private message</span></a></dd>"
    end
    # Public URL fields print the address as the link's text: the board's
    # own as its path, a long one cut short, an email as the address.
    field_set = lambda do |pairs|
      lambda do |_day|
        pairs.map do |label, url, text, kind|
          "<dd class='profile-custom-field'><strong>#{label}:</strong> <a class='#{kind || 'postlink'}' href='#{url}'>#{text || url}</a></dd>"
        end.join
      end
    end
    # phpBB brackets each link it makes in comments, which tell its field
    # links from a theme's where its censor has changed them.
    made = ->(field) { ->(day) { field.call(day).gsub("<a ", "<!-- m --><a ").gsub("</a>", "</a><!-- m -->") } }
    fields = field_set.call([["Code forge", "https://forge.example.net/profile/wren"], ["Community", "https://community.example.net/account/wren"]])
    local = field_set.call([["My gallery", "https://example.com/gallery/profile/wren", "gallery/profile/wren"],
                            ["Member journal", "https://example.com/journal/account/wren", "journal/account/wren"]])
    scripts = field_set.call([["My gallery", "https://example.com/ucp.php?i=profile&amp;mode=signature", "ucp.php?i=profile&amp;mode=signature", "postlink-local"],
                              ["Member journal", "https://example.com/ucp.php?i=profile&amp;mode=avatar", "ucp.php?i=profile&amp;mode=avatar", "postlink-local"]])
    long = "https://workshop.example/members/long-community-name/member-resources"
    shortened = field_set.call([["My gallery", "#{long}/profile/ab", "https://workshop.example/members/long-c ... profile/ab"],
                                ["Member journal", "#{long}/account/ab", "https://workshop.example/members/long-c ... account/ab"]])
    # A "www." address gets "http://" in its href only.
    www = "www.workshop.example/members/long-community-name/member-resources"
    shortened_www = field_set.call([["My gallery", "http://#{www}/profile/ab", "www.workshop.example/members/long-commu ... profile/ab"],
                                    ["Member journal", "http://#{www}/account/ab", "www.workshop.example/members/long-commu ... account/ab"]])
    mail = field_set.call([["Workshop", "mailto:account@workshop.example", "account@workshop.example"],
                           ["Society", "mailto:profile@society.example", "profile@society.example"]])
    # Email fields have no class, and a long address is cut in its middle.
    long_mail = "workshop-starter-baking-lab-calibrations-reports-2024"
    mail_shortened = field_set.call([["Workshop", "mailto:#{long_mail}@profile.io", "workshop-starter-baking-lab-calibration ... profile.io", ""],
                                     ["Society", "mailto:#{long_mail}@account.io", "workshop-starter-baking-lab-calibration ... account.io", ""]])
    # A member may be named as an address a field shows.
    own_mail = field_set.call([["Work email", "mailto:wren@example.com", "wren@example.com", ""]])
    # A word the board censors changes the href's middle the text cuts.
    censored = made.call(field_set.call([["My gallery", "http://www.workshop.example/contributors/member/directory/profile/ab", "www.workshop.example/contributors/hellr ... profile/ab"],
                                         ["Member journal", "http://www.workshop.example/contributors/member/directory/account/ab", "www.workshop.example/contributors/hellr ... account/ab"]]))
    # A member may be named as the board's own page a field links to.
    index = field_set.call([["Home page", "https://example.com/index.php", "index.php", "postlink-local"]])
    # A board's own page shows its path: the member's name as well.
    portfolio = field_set.call([["Portfolio", "https://example.com/wren", "wren", "postlink-local"]])
    # The board's own "/profile" and "/account" pages, shown as their path.
    local_words = made.call(field_set.call([["Portfolio", "https://example.com/profile", "profile", "postlink-local"],
                                            ["Journal", "https://example.com/account", "account", "postlink-local"]]))
    # A word the board censors at the cut ("rude" made "profile").
    censored_tail = made.call(field_set.call([["Lab", "mailto:#{long_mail}@xrude.co.uk", "workshop-starter-baking-lab-calibration ... profile.co.uk", ""],
                                              ["Lab", "mailto:#{long_mail}@xmean.co.uk", "workshop-starter-baking-lab-calibration ... account.co.uk", ""]]))
    # A censor's words may have spaces ("profile withheld"), at the cut of
    # an address, or in a board's own page it shows as its path.
    censored_words = made.call(field_set.call([["Lab", "mailto:#{long_mail}@xrude.co.uk", "workshop-starter-baking-lab-calibration ... profile withheld.co.uk", ""],
                                               ["Website", "https://field.example/online/tools/spamfilter/directory/my-profile", "https://field.example/online/tools/link removed ... my-profile"],
                                               ["Portfolio", "https://example.com/account page", "account page", "postlink-local"]]))
    # The censor may shorten the href's hidden middle below phpBB's 55, or
    # replace the whole shown tail, the end of a longer word.
    censored_href = made.call(field_set.call([["Lab", "https://field.example/aaaaaaaaaaaaaaaa/x/my-profile", "https://field.example/aaaaaaaaaaaaaaaa/ ... my-profile"],
                                              ["Lab", "https://field.example/aaaaaaaaaaaaaaaa/public-directory/mirror-spamsource", "https://field.example/aaaaaaaaaaaaaaaa/ ... profile withheld"]]))
    # The censor's word in the href where the text cut a longer one, or
    # in the text's whole tail, a word's end.
    censored_cut = made.call(field_set.call([["Lab", "https://field.example/fermentation/x/ab/my-profile", "https://field.example/fermentation/emba ... my-profile"],
                                             ["Lab", "https://field.example/fermentation/x/ab/my-account", "https://field.example/fermentation/emba ... my-account"]]))
    # A censored host's words with a path whose cut follows a "~".
    censored_tilde = made.call(field_set.call([["Website", "http://archived profile/~wren-fermentation-notebooks-#{"a" * 24}-research-1", "archived profile/~wren-fermentation- ... research-1"],
                                               ["Website", "http://archived profile/~wren-fermentation-notebooks-#{"b" * 24}-research-2", "archived profile/~wren-fermentation- ... research-2"]]))
    censored_word = made.call(field_set.call([["Lab", "https://field.example/labs/experiments/calibrations/xcontraband", "https://field.example/labs/experiments/ ... profile"],
                                             ["Lab", "https://field.example/labs/photographs/catalogue/xrestricted", "https://field.example/labs/photographs/ ... account"]]))
    # prosilver prints a field named "field1" in a plain row as well.
    field1 = made.call(lambda do |_day|
      links = "<a class='postlink-local' href='https://example.com/profile'>profile</a> <a class='postlink-local' href='https://example.com/account'>account</a>"
      "<dd><strong>Portfolio:</strong> #{links}</dd><dd class='profile-custom-field profile-field1'><strong>Portfolio:</strong> #{links}</dd>"
    end)
    # A field named as a date ("time_zone", "birthdate") dates the member.
    dated_fields = lambda do |_day|
      "<dd class='profile-custom-field profile-time_zone'><strong>Time zone:</strong> UTC+03:00</dd>" \
        "<dd class='profile-custom-field profile-birthdate'><strong>Birthday:</strong> 12-05-1987</dd>"
    end
    # Contact fields are named as the board likes; one is the member's own.
    contacts = lambda do |_day|
      "<dd class='profile-contact'><strong>Contact:</strong><div class='dropdown'><div class='dropdown-contents contact-icons'>" \
        "<a href='https://github.com/wrenbakes' title='GitHub profile'><span class='contact-icon'>GitHub profile</span></a>" \
        "<a href='https://social.example/@wrenbakes' title='Mastodon account'><span class='contact-icon'>Mastodon account</span></a>" \
        "<a href='http://facebook.com/facebook/' title='Facebook'><span class='contact-icon'>Facebook</span></a></div></div></dd>"
    end
    # The board's own pages, named as profiles, in the contact menu.
    board_contacts = lambda do |_day|
      "<dd class='profile-contact'><strong>Contact:</strong><div class='dropdown'><div class='dropdown-contents contact-icons'><div>" \
        "<a href='/chat/users/wren' title='Chat profile'><span class='contact-icon chat-icon'>Chat profile</span></a>" \
        "<a href='/directory/members/wren' title='Directory profile'><span class='contact-icon directory-icon'>Directory profile</span></a></div></div></div></dd>"
    end
    # The censor replaces a whole word of the href the text cuts, or the
    # whole shown tail; phpBB's comments say it made the links.
    censored_whole = made.call(field_set.call([["Lab", "https://lab.example/x/batch/calibration/archive/my-profile", "https://lab.example/x/batch/cali ... my-profile"],
                                               ["Lab", "https://lab.example/calibration/fermentation/records/removed", "https://lab.example/calibration/ferment ... no-account"]]))
    # The censor may blank a field's text; the menu's opener is titled
    # "Contact <name>" and goes nowhere.
    blanked = made.call(field_set.call([["Lab", "https://lab.example/records/profile", ""], ["Lab", "https://lab.example/records/account", ""]]))
    trigger = lambda do |_day|
      "<dd class='profile-contact'><strong>Contact:</strong><a href='#' class='dropdown-trigger' title='Contact profile'><span class='sr-only'>Contact profile</span></a></dd>"
    end
    # Without its comments, a field row of phpBB's own ident shows the
    # board's "/profile" and "/account" pages as their path.
    stripped_words = lambda do |day|
      local_words.call(day).gsub(/<!-- m -->/, "").gsub("class='profile-custom-field'", "class='profile-custom-field profile-portfolio'")
    end
    # Or the board two folders down, where the page read is.
    board = "https://example.com/community/fermentation/viewtopic.php?t=25"
    stripped_deep = ->(day) { stripped_words.call(day).gsub("https://example.com/", "https://example.com/community/fermentation/") }
    # A contact field's ident and name may say "time" and hold digits.
    office = lambda do |_day|
      "<dd class='profile-contact'><strong>Contact:</strong><div class='dropdown'><div class='dropdown-contents contact-icons'>" \
        "<a href='https://booking.example/wren' title='Office hours (UTC+3)'><span class='contact-icon office_time-icon'>Office hours (UTC+3)</span></a></div></div></dd>"
    end
    # The censor may turn a board path in a classless row into words.
    censored_page = lambda do |_day|
      "<dd><strong>Portfolio:</strong> <!-- l --><a class='postlink-local' href='https://example.com/profile page'>profile page</a><!-- l --></dd>" \
        "<dd><strong>Journal:</strong> <!-- l --><a class='postlink-local' href='https://example.com/account page'>account page</a><!-- l --></dd>"
    end
    # A theme may number phpBB's field classes.
    numbered = ->(_day) { "<dd class='profile-custom-fieldset profile-field-0'><strong>Portfolio 0:</strong> <!-- l --><a class='postlink-local' href='https://example.com/profile'>profile</a><!-- l --></dd>" }
    # The censor's words keep their spaces in the href: two, or one after
    # the folder's slash that the text strips.
    censored_spaces = lambda do |_day|
      "<dd><strong>Portfolio:</strong> <!-- l --><a class='postlink-local' href='https://example.com/profile  page'>profile  page</a><!-- l --></dd>" \
        "<dd><strong>Journal:</strong> <!-- l --><a class='postlink-local' href='https://example.com/forum/ view account'> view account</a><!-- l --></dd>"
    end
    # A stripped board deep on another port, with the page's default port
    # spelt out, or read through a route below the board.
    on_port = ->(day) { stripped_deep.call(day).gsub("https://example.com/", "https://example.com:8443/") }
    default_port = ->(day) { stripped_deep.call(day).gsub("https://example.com/", "https://example.com:443/") }
    # The censor may change the board's folder in the href, or leave a
    # space after a slash in both; the board's URL may name another host
    # than the page's.
    deep_fields = lambda do |path, other|
      lambda do |_day|
        "<dd class='profile-custom-field profile-portfolio'><strong>Portfolio:</strong> <!-- l --><a class='postlink-local' href='https://#{path}/#{other[0]}'>#{other[0]}</a><!-- l --></dd>" \
          "<dd class='profile-custom-field profile-journal'><strong>Journal:</strong> <!-- l --><a class='postlink-local' href='https://#{path}/#{other[1]}'>#{other[1]}</a><!-- l --></dd>"
      end
    end
    censored_folder = deep_fields.call("example.com/community/culturing", %w[profile account])
    censored_slash = deep_fields.call("example.com/community/fermentation", ["profile/ guide", "account/ settings"])
    other_host = deep_fields.call("example.com/community/fermentation", %w[profile account])
    # The censor can change a word on both sides of a cut address, or a
    # board link's href alone ("fermentation/profile" to "fermentation/portfolio").
    censored_edges = made.call(field_set.call([["Lab", "https://ext.example/xxxxxxxxxxxxxxx/laboratory/fermentation/public.01.pdf", "https://ext.example/xxxxxxxxxxxxxxx/catalog profile ... office account.01.pdf"],
                                               ["Lab", "https://ext.example/xxxxxxxxxxxxxxx/laboratory/fermentation/public.02.pdf", "https://ext.example/xxxxxxxxxxxxxxx/catalog profile ... office account.02.pdf"]]))
    # The censor's words in the host and the path, after the shown start.
    censored_host = made.call(field_set.call([["Project", "https://legacy.example.net/ferments/archive/profile", "https://retiredlaboratoryfermentationar ... ed/profile"],
                                              ["Project", "https://legacy.example.net/calibration/archive/account", "https://retiredlaboratoryfermentationar ... ed/account"]]))
    # The censor's words before a fragment or a query the cut keeps.
    censored_fragment = made.call(field_set.call([["Projects", "https://photo.example.org/galleries/removed/weekly-exhibits/removed#profile", "https://photo.example.org/galleries/cas ... no#profile"],
                                                  ["Projects", "https://photo.example.org/galleries/removed/previous-exhibits/removed#account", "https://photo.example.org/galleries/cas ... no#account"]]))
    censored_query = made.call(field_set.call([["Website", "https://photo.example.org/galleries/archive/fermentation-notebooks/archive?profile", "https://photo.example.org/galleries/ret ... ed?profile"],
                                               ["Project", "https://photo.example.org/galleries/archive/laboratory-logs/archive?account", "https://photo.example.org/galleries/ret ... ed?account"]]))
    # Or rewrite the whole shown tail, or keep a query's "=".
    censored_tail_whole = made.call(field_set.call([["Project", "https://legacy.example.net/ferments/archived", "https://retiredlaboratoryfermentationar ... my-profile"],
                                                    ["Project", "https://legacy.example.net/calibration/archived", "https://retiredlaboratoryfermentationar ... my-account"]]))
    censored_equals = made.call(field_set.call([["Project", "https://legacy.example.net/ferments/index?archive=profile", "https://retiredlaboratoryfermentationar ... ed=profile"],
                                                ["Project", "https://legacy.example.net/calibration/index?archive=account", "https://retiredlaboratoryfermentationar ... ed=account"]]))
    board_href = deep_fields.call("example.com/community/fermentation", %w[portfolio archive]).then do |field|
      ->(day) { field.call(day).sub(">portfolio<", ">profile<").sub(">archive<", ">account<") }
    end
    # A member may be named 404 and have 404 posts, or begin with "@".
    [["", "wren"], [contact, "wren"], ["", "41"], [fields, "wren"], [local, "wren"], [scripts, "wren"], [shortened, "wren"], [shortened_www, "wren"],
     [mail, "wren"], [mail_shortened, "wren"], [own_mail, "wren@example.com"], [censored, "wren"], [contacts, "wren"], [contacts, "Facebook"],
     ["", "@wren"], ["", "@ wren"], [index, "index.php"], [portfolio, "wren"], [local_words, "wren"], [local_words, "profile"],
     [censored_tail, "wren"], [censored_words, "wren"], [dated_fields, "wren"], [censored_href, "wren"], [field1, "wren"], [field1, "profile"], [censored_cut, "wren"], [censored_word, "wren"], [censored_tilde, "wren"],
     [board_contacts, "wren"], [censored_whole, "wren"], [blanked, "wren"], [trigger, "profile"], [stripped_words, "wren"], [office, "wren"],
     [censored_page, "wren"], [stripped_deep, "wren", board], [numbered, "profile"], [censored_spaces, "wren"],
     [on_port, "wren", board.sub("example.com", "example.com:8443")], [default_port, "wren", board],
     [stripped_deep, "wren", "https://example.com/community/fermentation/topic/starter.html"], [censored_folder, "wren", board],
     [censored_slash, "wren", board], [other_host, "wren", board.sub("example.com", "forum.example.com")], [censored_edges, "wren"],
     [board_href, "wren", board], [board_href, "profile", board], [censored_host, "wren", board], [censored_fragment, "wren"], [censored_query, "wren"],
     [censored_tail_whole, "wren", board], [censored_tail_whole, "wren"], [censored_equals, "wren", board], [board_href, "profile"]].each do |extra, first, url|
      # Longer posts, as the fields' links would outweigh short ones.
      more = [fields, local, scripts, shortened, shortened_www, mail, mail_shortened, own_mail, censored, contacts, local_words, censored_tail, censored_words, censored_href, field1, censored_cut, censored_word, censored_tilde,
              board_contacts, censored_whole, blanked, stripped_words, office, censored_page, stripped_deep, numbered, censored_spaces, on_port,
              default_port, censored_folder, censored_slash, other_host, censored_edges, board_href, censored_host, censored_fragment, censored_query,
              censored_tail_whole, censored_equals].include?(extra) ? " I fed it at the same hour each day, kept it in a clean jar on the kitchen counter, and used the same flour throughout." : ""
      posts = [[first, 3, "Starter", question + more], ["basil", 5, "Re: Starter", answer + more]].map do |name, day, subject, body|
        "<div id='p#{day}' class='post has-profile'><div class='inner'>" \
          "<dl class='postprofile'><dt><strong><span class='username'>#{name}</span></strong></dt>" \
          "<dd class='profile-posts'><strong>Posts:</strong> <a href='./search.php?author_id=#{day}&amp;sr=posts'>41</a></dd>" \
          "#{extra.respond_to?(:call) ? extra.call(day) : extra}</dl>" \
          "<div class='postbody'><h3><a href='#p#{day}'>#{subject}</a></h3>" \
          "<p class='author'>by <strong><span class='username'>#{name}</span></strong> " \
          "<time datetime='2024-05-0#{day}T08:45:00Z'>May #{day}, 2024</time></p><div class='content'>#{body}</div></div></div></div>"
      end
      markdown = thread(posts, head: '<meta name="generator" content="phpBB">', url: url || "https://example.com/threads/starter")

      # The post's line drops the "@" a handle is shown with.
      shown = first.sub(/\A@\s*/, "")
      markdown.should include("**#{shown}** · May 3, 2024\n\n#{question}")
      markdown.should include("**basil** · May 5, 2024\n\n#{answer}")
      markdown.scan(/\*\*(?:@\s*)?(?:#{shown}|basil)\*\*/).size.should eq(2), "#{extra.respond_to?(:call) ? extra.call(3) : extra} #{first}"
    end

    # Where the post's date is plain text, the panel's contact stays.
    posts = [["wren", 3, office.call(3), question], ["basil", 5, "", answer]].map do |name, day, extra, body|
      "<div id='p#{day}' class='post has-profile'><div class='inner'><dl class='postprofile'><dt><a class='username' href='./memberlist.php?u=#{day}'>#{name}</a></dt>#{extra}</dl>" \
        "<div class='postbody'><h3><a href='#p#{day}'>Starter</a></h3><p class='author'>by <strong><a class='username' href='./memberlist.php?u=#{day}'>#{name}</a></strong> " \
        "0#{day} May 2024, 12:00</p><div class='content'>#{body}</div></div></div></div>"
    end
    thread(posts, head: '<meta name="generator" content="phpBB">').should include("Office hours (UTC+3)")

    # A panel known only by its id keeps its contact beside a dated post.
    posts = [["wren", 3, office.call(3), question], ["basil", 5, "", answer]].map do |name, day, extra, body|
      "<div id='p#{day}' class='post has-profile'><div class='inner'><dl id='postprofile'><dt><strong><span class='username'>#{name}</span></strong></dt>#{extra}</dl>" \
        "<div class='postbody'><h3><a href='#p#{day}'>Starter</a></h3><p class='author'>by <strong><span class='username'>#{name}</span></strong> " \
        "<time datetime='2024-05-0#{day}T08:45:00Z'>May #{day}, 2024</time></p><div class='content'>#{body}</div></div></div></div>"
    end
    thread(posts, head: '<meta name="generator" content="phpBB">').should include("Office hours (UTC+3)")

    # So does a theme's own panel, a post's second root, beside it.
    markdown = thread([
      "<article class='message'><div class='message-user'><a class='username' href='/members/87'>W. Baker</a>" \
      "<span class='contact-icon office_time-icon'>Office hours 09:00–12:00 UTC</span></div><div class='article-content'>" \
      "<header><a class='username' href='/members/87'>W. Baker</a> <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p><p>#{answer}</p><p>#{question}</p></div></article>",
      post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
    ])
    markdown.should include("Office hours 09:00–12:00 UTC")

    # A theme's dl.postprofile showing the icon in a row of its own, not
    # in prosilver's contact menu.
    markdown = thread([
      "<article class='message'><dl class='message-user postprofile'><dt><a class='username' href='/members/87'>W. Baker</a></dt>" \
      "<dd class='office-hours'><span class='contact-icon office_time-icon'>Office hours 09:00–12:00 UTC</span></dd></dl>" \
      "<header><a class='username' href='/members/87'>W. Baker</a> <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p><p>#{answer}</p></article>",
      post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
    ])
    markdown.should include("Office hours 09:00–12:00 UTC")

    # The same row styled with prosilver's "contact-icons" but shown
    # inline, outside a dropdown.
    markdown = thread([
      "<article class='message'><dl class='message-user postprofile'><dt><a class='username' href='/members/87'>W. Baker</a></dt>" \
      "<dd class='office-hours'><div class='contact-icons'><a href='/schedule'><span class='contact-icon office_time-icon'>Office hours 09:00–12:00 UTC</span></a></div></dd></dl>" \
      "<header><a class='username' href='/members/87'>W. Baker</a> <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p><p>#{answer}</p></article>",
      post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
    ])
    markdown.should include("Office hours 09:00–12:00 UTC")

    # Or with prosilver's two menu classes, but in no dropdown.
    markdown = thread([
      "<article class='message'><dl class='message-user postprofile'><dt><a class='username' href='/members/87'>W. Baker</a></dt>" \
      "<dd class='office-hours'><div class='dropdown-contents contact-icons' role='group'><a href='/schedule'><span class='contact-icon office_time-icon'>Office hours 09:00–12:00 UTC</span></a></div></dd></dl>" \
      "<header><a class='username' href='/members/87'>W. Baker</a> <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p><p>#{answer}</p></article>",
      post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
    ])
    markdown.should include("Office hours 09:00–12:00 UTC")
  end

  # The rest of the panel's column (a rank, a post count) stands between the
  # panel's line and the post's, and may say whose it is.
  it "keeps the member panel's line when its column holds more" do
    ["<p class='userTitle'>Moderator</p>", "<p>Posts: 41</p>"].each do |extra|
      posts = [["wren", 3, question], ["basil", 5, answer]].map do |name, day, body|
        user = "<a class='username' href='/members/#{name}'>#{name}</a>"
        "<article class='message'><div class='message-cell--user'><section class='message-user'>#{user}</section>#{extra}</div>" \
          "<div class='message-main'><header class='message-attribution'>#{user} <time datetime='2024-05-0#{day}T08:45:00Z'>May #{day}, 2024</time></header>" \
          "<div class='message-content'><p>#{body}</p></div></div></article>"
      end
      markdown = thread(posts)

      markdown.should include("**wren**\n\n#{extra.gsub(/<[^>]+>/, '')}\n\n**wren** · May 3, 2024\n\n#{question}")
      markdown.should include("**basil** · May 5, 2024\n\n#{answer}")
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
      "<div class='blockquote'>#{panel}<p>I agree.</p></div>#{head}" => "I agree.",
      "<div class='bbquote'>#{panel}<p>I agree.</p></div>#{head}" => "I agree.",
      "<div class='quotation'>#{panel}<p>I agree.</p></div>#{head}" => "I agree.",
      "<div role='blockquote'>#{panel}<p>I agree.</p></div>#{head}" => "I agree.",
      "<div>#{panel}<p id='quote-435'>I agree.</p></div>#{head}" => "I agree.",
      "<section>#{panel}<div id='blockquote-2'><p>I agree.</p></div></section>#{head}" => "I agree.",
      "#{panel}<p>I agree.</p>#{head}" => "I agree.",
      "#{panel}<span>I agree.</span>#{head}" => "I agree."
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
    kinds = [["message unread", "unread message"], ["message dark", "message light"], ["theme-dark message", "message theme-light"],
             ["unread message", "read message"]]
    kinds.product([["post-435", "post-436"], nil]).each do |(outer, inner), ids|
      outer_id, inner_id = ids&.map { |id| " id='#{id}'" }
      markdown = thread([
        "<article class='#{outer}'#{outer_id}><article class='#{inner}'#{inner_id}><div class='message-user'>#{user}</div>" \
        "<p>I agree.</p></article>#{head}</article>",
        "<article class='#{outer}'><header><a class='username' href='/members/basil'>basil</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
        "<p>#{answer}</p></article>"
      ])

      markdown.should include("**wren**\n\nI agree.\n\n**wren** · May 3, 2024\n\n#{question}")
    end
  end

  # The same name may be another member's, at another URL or where the
  # panel links to two of that name, or come with a fuller date.
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
      ["<a class='username' href='/users#@server/a/'>Wren</a>", "<a class='username' href='/users#@server/a'>wren</a> <time>May 3, 2024</time>"],
      ["<a class='username' href='/members/wren/'>Wren</a>", "<a class='username' href='/members/wren'>wren</a> <time>May 3, 2024</time>"],
      ["<a class='username' href='http://example.com/members/wren'>Wren</a>", "<a class='username' href='/members/wren'>wren</a> <time>May 3, 2024</time>"],
      ["<a class='username' href='/user?icid=72'>Wren</a>", "<a class='username' href='/user?icid=84'>wren</a> <time>May 3, 2024</time>"],
      ["<a href='/members/72'><span class='username'>Wren</span><span class='badge'>Pro</span></a><span>Referred by <a href='/members/84'>Wren</a></span>",
       "<a class='username' href='/members/84'>wren</a> <time>May 3, 2024</time>"],
      ["<a href='/members/72'><span class='username'>Wren</span></a><span>Last visitor:</span><a class='username' href='/members/84'>Wren</a>",
       "<a class='username' href='/members/84'>wren</a> <time>May 3, 2024</time>"],
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
    ["../members/wren", "https://example.com:443/members/wren", "HTTPS://Example.com/members/wren"].each do |link|
      markdown = thread([
        "<article class='message'><div class='message-user'><a class='username' href='#{link}'>wren</a></div>" \
        "<div class='message-main'><header><a class='username' href='/members/wren'>wren</a> <time>May 3, 2024</time></header>" \
        "<p>#{question}</p></div></article>",
        post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
      ])

      markdown.should include("**wren** · May 3, 2024\n\n#{question}")
      markdown.scan("**wren**").size.should == 1
    end

    markdown = thread([
      "<article class='message'><div class='message-user'><a class='username' href='./wren'>wren</a></div>" \
      "<div class='message-main'><header><a class='username' href='https://example.com/people/wren'>wren</a> <time>May 3, 2024</time></header>" \
      "<p>#{question}</p></div></article>",
      post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
    ], head: '<meta name="generator" content="XenForo"><base href="https://example.com/people/">')

    markdown.scan("**wren**").size.should == 1
  end

  # Text before the panel in the post ("Last edited by", in any language)
  # may make its line the name of who did it, not the poster's again; a
  # panel after the post's line names a reply, a quote, an attachment or an
  # editor.
  it "keeps the member panel's line after text in the post, or after the post's line" do
    user = "<a class='username' href='/members/wren'>wren</a>"
    head = "<header>#{user} <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p>"
    panel = "<div class='message-user'>#{user}</div>"
    {
      "#{head}<p>Last edited by</p>#{panel}" => "Last edited by\n\n**wren**\n\n**basil**",
      "<div>Reviewed by</div>#{panel}#{head}" => "Reviewed by\n\n**wren**\n\n**wren** · May 3, 2024",
      "<p>Last edited by —</p>#{panel}#{head}" => "Last edited by —\n\n**wren**\n\n**wren** · May 3, 2024",
      "<p>Última edición de</p>#{panel}#{head}" => "Última edición de\n\n**wren**\n\n**wren** · May 3, 2024",
      "<p>Last edited by <span>(moderator)</span></p>#{panel}#{head}" => "(moderator)\n\n**wren**\n\n**wren** · May 3, 2024",
      "#{head}<p>Laatst bewerkt door</p>#{panel}" => "Laatst bewerkt door\n\n**wren**\n\n**basil**",
      "#{head}<p>最終編集者</p>#{panel}" => "最終編集者\n\n**wren**\n\n**basil**",
      "#{head}<p>I independently reproduced this.</p>#{panel}" => "I independently reproduced this.\n\n**wren**\n\n**basil**",
      "#{head}<blockquote>Mix again tomorrow.</blockquote><div class='citation'>#{panel}</div>" => "> Mix again tomorrow.\n\n**wren**\n\n**basil**",
      "<div class='edit'>Last edited by —</div><div class='message-inner'>#{panel}#{head}</div>" =>
        "Last edited by —\n\n**wren**\n\n**wren** · May 3, 2024",
      "#{panel}<h3>Verified by the above contributor</h3>#{head}" =>
        "**wren**\n\n### Verified by the above contributor\n\n**wren** · May 3, 2024",
      "#{panel}<div role='blockquote'><h3>“Keep the lid loose.”</h3></div>#{head}" =>
        "**wren**\n\n### “Keep the lid loose.”\n\n**wren** · May 3, 2024"
    }.each do |inner, shown|
      markdown = thread([
        "<article class='message'>#{inner}</article>",
        post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
      ])

      markdown.should include(shown)
    end
  end

  # The line a panel leaves with a link (an attachment, a quoted file) is
  # no reason to read their container as a list of links.
  it "keeps a link beside the member panel's line" do
    user = "<a class='username' href='/members/wren'>wren</a>"
    head = "<header>#{user} <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p>"
    {
      "<div class='quote'><div class='message-user'>#{user}</div><a href='/log.pdf'>Log</a></div>#{head}" => "[Log](https://example.com/log.pdf)",
      "#{head}<div class='attachment'><div class='user-info'>#{user}</div><a href='/log.pdf'>Mixing log</a></div>" =>
        "[Mixing log](https://example.com/log.pdf)",
      "#{head}<div class='attachments'><div class='message-user'>#{user}</div><ul><li><a href='/log.pdf'>Mixing log</a></li></ul></div>" =>
        "- [Mixing log](https://example.com/log.pdf)"
    }.each do |inner, shown|
      markdown = thread([
        "<article class='message'>#{inner}</article>",
        post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
      ])

      markdown.should include(shown)
      markdown.should include("**wren** · May 3, 2024\n\n#{question}")
    end
  end

  # Member cards in a post's body are the post's content.
  it "keeps the member cards a post's body lists" do
    cards = [%w[Aster Lab\ safety\ officer], %w[Moss Instrumentation\ engineer], %w[Lark Sample\ custodian]].each_with_index.map do |(name, role), index|
      "<div class='user-info'><a class='username' href='/members/#{87 + index}'>#{name}</a> " \
        "<span>#{role} · <a href='/reports/#{87 + index}.pdf'>Report #{index}</a></span></div>"
    end
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<div class='message-content'><p>The starter doubled in volume overnight.</p><h3>Contributors</h3>#{cards.join}</div></article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave some room in the jar for the next feeding.</p></article></main></body></html>"
    markdown = Nokodown.to_markdown(html)

    3.times { |index| markdown.should include("[Report #{index}](/reports/#{87 + index}.pdf)") }
  end

  # An account box between posts holds a panel of no post: it is judged as
  # any other box, and the posts' files are kept.
  it "keeps a post's files beside an account box between posts" do
    user = "<div class='user-info'><a class='username' href='/u/wren'>Wren</a></div>"
    report = "<div class='files'><div>Attachment</div><a href='/report.pdf'>Laboratory mixing log</a></div>"
    ["", "<div class='attachment'>#{user}<ul><li><a href='/log.pdf'>Mixing log</a></li></ul></div>"].each do |card|
      html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
             "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
             "<p>The starter doubled.</p>#{card}#{report}</article>" \
             "<div class='member-controls'>#{user}<a href='/sign-up'>Register for member features</a> <a href='/pricing'>View the subscription plans</a></div>" \
             "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
             "<p>Leave room in the jar.</p></article></main></body></html>"

      Nokodown.to_markdown(html).should include("[Laboratory mixing log](/report.pdf)")
    end
  end

  # A member panel that names someone else (a source's supplier) is not
  # the poster's: its line counts as kept text, as the panel did.
  it "keeps a post's files beside a member panel that names another member" do
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<div class='sources'><div class='user-info'><a class='username' href='/members/48'>Basil Cunningham</a></div><p>Attached records</p>" \
           "<a href='/schedule.pdf'>Original feeding schedule</a> <a href='/temperature.pdf'>Daily temperature chart</a></div>" \
           "<p>The starter doubled.</p><div class='files'><p>Attachment</p><a href='/report.pdf'>Laboratory mixing log</a></div></article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar before mixing again.</p></article></main></body></html>"

    markdown = Nokodown.to_markdown(html)
    markdown.should include("**Basil Cunningham**")
    markdown.should include("[Laboratory mixing log](/report.pdf)")
    markdown.should include("[Daily temperature chart](/temperature.pdf)")
  end

  # A group kept for the line it holds keeps the groups around it too.
  it "keeps the files in groups around a group kept for its member panel's line" do
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><div id='wrap'><div id='outer'><div id='inner'><div class='user-info'>" \
           "<a class='username' href='/u/contributor'>Basil Alexander Cunningham of West Lancashire</a></div><a href='/schedule.pdf'>PDF</a></div> " \
           "<a href='/notes.pdf'>Log</a></div> <a href='/data.pdf'>CSV</a></div>" \
           "<header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled in volume overnight after its second feeding on the kitchen counter.</p></article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>A second feeding in a clean jar helped mine recover overnight too.</p></article></main></body></html>"

    markdown = Nokodown.to_markdown(html)
    markdown.should include("**Basil Alexander Cunningham of West Lancashire**\n\n[PDF](/schedule.pdf)\n\n[Log](/notes.pdf)\n\n[CSV](/data.pdf)")
  end

  # Held in one order, a group after the panel it holds: put back the other way.
  it "keeps a member panel's line held inside a group held after it" do
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled.</p><div id='group'><div class='supplier' id='credit0'><div class='user-info'><span class='username'>Basil Cunningham</span></div><p></p></div>" \
           "<div class='user-info'><a class='username' href='/members/49'>Aster Marshall</a></div></div>" \
           "<div class='reviewer' id='other'><div class='message-user'><span class='username'>Mira Rivers</span></div><p></p></div></article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article></main></body></html>"

    markdown = Nokodown.to_markdown(html, url: "https://example.com/t")
    markdown.should include("**Basil Cunningham**\n\n**Aster Marshall**\n\n**Mira Rivers**")
  end

  # Whether cleaning left almost nothing is read as before the panels were.
  it "prunes like a page when cleaning keeps little more than the panels' lines" do
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled.</p><div id='group'><div class='contributor' id='credit0'><div class='user-info'><a class='username' href='/members/48'>Basil Cunningham</a></div>" \
           "<div><p>Measurements</p><a href='/raw.pdf'>Mixing log A</a></div></div>" \
           "<div class='user-info'><a class='username' href='/members/49'>Aster Marshall</a></div></div>" \
           "<footer><p>Original laboratory records.</p><a href='/mix.pdf'>Mixing log</a></footer>" \
           "<aside><p>Note A. The mixer was weighed before fermentation and the total was entered in the register. </p></aside>" \
           "<aside><p>Note B. The water was weighed before fermentation and the total was entered in the register. </p></aside></article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article></main></body></html>"

    markdown = Nokodown.to_markdown(html, url: "https://example.com/t")
    markdown.should include("(https://example.com/raw.pdf)", "(https://example.com/mix.pdf)", "Note A.", "Note B.", "**Basil Cunningham**")
  end

  # A container held out for its panels was gone when the share was read.
  it "prunes like a page when what is kept is only a container held for its panels" do
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled.</p><div class='contributors'><div class='contributor'><div class='user-info'><a class='username' href='/members/48'>Basil Cunningham</a></div>" \
           "<div><span>Measurements for both test jars</span> <a href='/raw.pdf'>Mixing log A</a></div></div>" \
           "<div class='user-info'><a class='username' href='/members/49'>Aster Marshall</a></div></div>" \
           "<footer><p>Original laboratory records.</p><a href='/mix.pdf'>Mixing log</a></footer>" \
           "<aside><p>Note A. The starter was weighed at noon and entered into the batch record. We kept a copy.</p></aside>" \
           "<aside><p>Note B. The water was weighed at noon and recorded alongside the flour.</p></aside></article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article></main></body></html>"

    markdown = Nokodown.to_markdown(html, url: "https://example.com/t")
    markdown.should include("(https://example.com/raw.pdf)", "(https://example.com/mix.pdf)", "Note A.", "Note B.")
    markdown.should_not include("nokodown")
  end

  # The lighter pass tells a cluster of links without the panels, too.
  it "keeps a file beside member panels on the lighter pass" do
    credit = lambda do |id, member, name, file|
      "<div class='contributor' id='credit#{id}'><div class='user-info'><a class='username' href='/members/#{member}'>#{name}</a></div>" \
        "<p>Original records</p><a href='/#{file}.pdf'>Mixing log #{file[-1].upcase}</a></div>"
    end
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled.</p><ul id='group'><li>#{credit.call(0, 48, 'Basil Cunningham', 'trial-a')}" \
           "<div class='user-info'><a class='username' href='/members/49'>Aster Marshall</a></div></li></ul>" \
           "#{credit.call(2, 50, 'Lark Bronson', 'trial-b')}#{credit.call(3, 51, 'Cori Meyer', 'trial-c')}</article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article></main></body></html>"

    markdown = Nokodown.to_markdown(html, url: "https://example.com/t")
    markdown.should include("(https://example.com/trial-a.pdf)", "(https://example.com/trial-b.pdf)", "(https://example.com/trial-c.pdf)")
  end

  # Whether the clusters are the content is weighed without the lines too.
  it "keeps a box of files that is most of a post without the lines on the lighter pass" do
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled.</p><div><p>Files</p><a href='/evidence-0.pdf'>Laboratory mixing report</a> " \
           "<a href='/evidence-1.pdf'>Fermentation observation</a> <a href='/evidence-2.pdf'>Temperature register</a> " \
           "<a href='/evidence-3.pdf'>Ingredient weight report</a></div>" \
           "<div class='user-info'><span class='username'>Basil Alexander Cunningham</span></div>" \
           "<aside><p>The weighing procedure was recorded in the laboratory register before the batches were prepared.</p></aside></article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article></main></body></html>"

    markdown = Nokodown.to_markdown(html, url: "https://example.com/t")
    markdown.should include("(https://example.com/evidence-0.pdf)", "(https://example.com/evidence-3.pdf)")
  end

  # A paragraph of links is read without the panels in it, as it was
  # before they were read.
  it "keeps a file in a paragraph beside two member panels" do
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled.</p><section class='attachments'><p><span class='user-info'><a class='username' href='/members/48'>Basil Cunningham</a></span> " \
           "<span class='user-info'><a class='username' href='/members/49'>Aster Marshall</a></span> <a href='/trial-a.pdf'>Mixing log A</a></p></section></article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article></main></body></html>"

    Nokodown.to_markdown(html, url: "https://example.com/t").should include("[Mixing log A](https://example.com/trial-a.pdf)")
  end

  # The same paragraph, when the post is pruned like a page.
  it "keeps a file in a paragraph beside two member panels on a pruned page" do
    files = (0..2).map { |index| "<div class='files'><p>Supporting file</p><a href='/log-#{index}.pdf'>#{'Laboratory mixing results ' * 3}</a></div>" }.join
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled.</p><section class='attachments'><p><span class='user-info'><a class='username' href='/members/48'>Basil Cunningham</a></span> " \
           "<span class='user-info'><a class='username' href='/members/49'>Aster Marshall</a></span> <a href='/trial-a.pdf'>Mixing log A</a></p></section>#{files}</article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article></main></body></html>"

    Nokodown.to_markdown(html).should include("[Mixing log A](/trial-a.pdf)")
  end

  # A box goes only if it is one both with the panel, as before the
  # poster's line, and without it, as after.
  it "keeps a paragraph of files beside an unlinked member panel" do
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled.</p><section class='attachments'><p>Files</p><p><span class='user-info'><span class='username'>Basil Cunningham</span></span> " \
           "<a href='/report.pdf'>Report</a> <a href='/methods.pdf'>Methods</a> <a href='/records.pdf'>Records</a></p></section></article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article></main></body></html>"

    markdown = Nokodown.to_markdown(html, url: "https://example.com/t")
    markdown.should include("Basil Cunningham")
    markdown.should include("[Records](https://example.com/records.pdf)")
  end

  it "keeps two boxes of files when one credits a member" do
    box = lambda do |kind, label, credit|
      links = ["Batch reference report", "Fermentation observation", "Temperature register"].each_with_index.map do |name, index|
        "<a href='/#{kind}-#{index}.pdf'>#{name}</a>"
      end
      "<div class='#{kind}-files'><p>#{label}</p>#{credit}#{links.join(' ')}</div>"
    end
    credit = "<div class='user-info'><span class='username'>Basil Cunningham</span></div>"
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled.</p>#{box.call('first', 'Primary files', credit)}#{box.call('second', 'Follow-up files', '')}</article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article></main></body></html>"

    markdown = Nokodown.to_markdown(html, url: "https://example.com/t")
    markdown.should include("[Temperature register](https://example.com/first-2.pdf)")
    markdown.should include("[Temperature register](https://example.com/second-2.pdf)")
  end

  # A short aside is weighed without the panel in it, as before the line.
  it "keeps a post's footer and notes beside a short aside that credits a member" do
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled.</p><aside><p>The total weight of the bowl and the starter was entered in the kitchen register. " \
           "I took another reading the following morning. Recorded by <span class='user-info'><a class='username' href='/members/48'>" \
           "Basil Alexander Cunningham of West Lancashire</a></span> <a href='/weights.pdf'>Weighing sheet</a></p></aside>" \
           "<footer><p>Full records</p><a href='/oven.pdf'>Baking schedule</a></footer><aside><p>The mixture tripled in volume while it rested " \
           "on the kitchen counter. We wrote down the time and returned the bowl to the bench.</p></aside></article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article></main></body></html>"

    markdown = Nokodown.to_markdown(html, url: "https://example.com/t")
    markdown.should include("[Baking schedule](https://example.com/oven.pdf)")
    markdown.should include("The mixture tripled in volume")
  end

  # What only main's view removes stays, and the fallback reads the post
  # without it, as main did.
  it "keeps a box of files and a post's report and notes that main kept falling back" do
    page = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled.</p><section class='attachments'><p><span class='user-info'><span class='username'>Basil Cunningham</span></span> " \
           "<a href='/record-0.pdf'>Mixing log</a> <a href='/record-1.pdf'>Proofing notes</a> <a href='/record-2.pdf'>Temperature chart</a></p></section>" \
           "<footer><a href='/lab.pdf'>Original laboratory report</a></footer>" \
           "<aside><p>The second trial was conducted before noon on Friday after the original fermentation had slowed.</p></aside>" \
           "<aside><p>Water and flour weighed separately on the laboratory scale before the mixture was recorded.</p></aside></article>" \
           "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article></main></body></html>"
    reduced = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
              "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
              "<p>The starter doubled.</p><p><span class='user-info'><span class='username'>Basil</span></span> " \
              "<a href='/sample-a.pdf'>Sample A</a> <a href='/sample-b.pdf'>Sample B</a></p></article>" \
              "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
              "<p>Leave room in the jar.</p></article></main></body></html>"

    markdown = Nokodown.to_markdown(page, url: "https://example.com/t")
    markdown.should include("[Temperature chart](https://example.com/record-2.pdf)")
    markdown.should include("[Original laboratory report](https://example.com/lab.pdf)")
    markdown.should include("Water and flour weighed separately")
    Nokodown.to_markdown(reduced, url: "https://example.com/t").should include("**Basil**\n\n[Sample A](https://example.com/sample-a.pdf)")
  end

  # An aside goes only where it goes with the credit and without it.
  it "keeps an aside with a member's credit that one reading kept" do
    aside = lambda do |note, body|
      "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
        "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
        "<p>#{body}</p><aside><p>We measured the mixture and logged the results. The reference temperature and humidity are in the notebook. #{note} " \
        "Logged by <span class='user-info'><a class='username' href='/members/48'>Basil Alexander Cunningham of West Lancashire</a></span> " \
        "<a href='/weighing.pdf'>Weighing sheet</a></p></aside></article>" \
        "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
        "<p>Leave room in the jar so the mixture can expand. Clean the rim and write down the temperature.</p></article></main></body></html>"
    end
    short = aside.call("We will check the jar again tomorrow at noon.", "The starter doubled after its second feeding and held steady.")
    long = aside.call("The next check is tomorrow after the second feeding. I left the jar on the counter.",
                      "The starter doubled in volume after the second feeding and then held steady on the counter. I used the same flour " \
                      "and a clean jar for both feedings. I kept the kitchen window closed all night while the mixture rested.")

    [short, long].each do |html|
      Nokodown.to_markdown(html, url: "https://example.com/t").should include("[Weighing sheet](https://example.com/weighing.pdf)")
    end
  end

  # A container holding a spared aside is weighed with it, as it was kept.
  it "keeps the container of an aside with a member's credit" do
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message comment'><header><a class='username' href='/u/Wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>It doubled up.</p><div><aside><p>We checked the temperature and humidity before the second feeding started. " \
           "<span class='user-info'><span class='username'>Basil Cunningham</span> cleaned the instruments and calibrated the temperature probe " \
           "before we started the regular evening measurements.</span></p></aside><p><a href='/reference-control.pdf'>Reference measurements</a></p></div>" \
           "<aside><p>We mixed the second batch overnight and checked both jars in the morning. The plain starter had doubled and the rye starter " \
           "was already close to the lid. <a href='/target0.pdf'>Original laboratory report for batch A</a></p></aside></article>" \
           "<article class='message comment'><header><a class='username' href='/u/Fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>We had the same result using a smaller jar this morning. It is easier to see how much the starter rises when the sides are straight, " \
           "and the rubber band stayed in place overnight. I washed the jar and marked the new level before feeding both samples again.</p></article>" \
           "</main></body></html>"

    markdown = Nokodown.to_markdown(html)
    markdown.should include("Basil Cunningham cleaned the instruments")
    markdown.should include("[Reference measurements](/reference-control.pdf)")
  end

  # Main's reading of the related links had the spared footer gone, as
  # main removed it; base's reading drops it with the box.
  it "keeps a post's note after a credited footer that main removed" do
    html = lambda do |title|
      "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
        "<article class='message'><header><a class='username' href='/u/Wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
        "<p>It doubled up.</p><h3>Read more</h3><section><footer><p>" +
        (1..3).map { |index| "<a href='/chart#{index}.pdf'>Humidity and temperature observations before and after feeding #{index}</a>" }.join(" ") +
        " <span class='user-info'><a class='username' href='/staff/basil'>Basil Cunningham</a> #{title}</span></p></footer>" \
        "<p>We observed a level rise after feeding the starter. <a href='/witness.pdf'>Witness statement</a></p></section></article>" \
        "<article class='message'><header><a class='username' href='/u/Fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
        "<p>Leave it room. We observed a level rise after feeding the starter. </p></article></main></body></html>"
    end

    markdown = Nokodown.to_markdown(html.call("The senior laboratory safety officer and verifier for this session"))
    markdown.should include("[Witness statement](/witness.pdf)")
    # Where both readings drop the footer, it goes; the note stays.
    markdown = Nokodown.to_markdown(html.call("<a href='/qualifications.pdf'>The senior laboratory safety officer and verifier for this session</a>"))
    markdown.should include("[Witness statement](/witness.pdf)")
    markdown.should_not include("chart1.pdf")
  end

  # Base removed the footer as furniture before reading related links; its
  # reading of the section has the footer gone, so the note stays.
  it "keeps a post's note after a footer that only base removed as furniture" do
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><header><a class='username' href='/u/Wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>Initial test.</p><p>Reviewed by <span class='user-info'><a class='username' href='/staff/basil'>Basil Cunningham</a> Records officer</span>.</p>" \
           "<h3>Read more</h3><section><footer><p><a href='/chart0.pdf'>Overnight humidity and temperature readings for the rye culture</a> " \
           "<a href='/chart1.pdf'>Reference calibration from the independent sensor</a> <a href='/chart2.pdf'>Initial and final temperatures in the comparison batch</a></p></footer>" \
           "<p>The reading was confirmed at noon. <a href='/witness.pdf'>Witness statement</a></p></section></article>" \
           "<article class='message'><header><a class='username' href='/u/Fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Please allow room for the next feeding. </p></article></main></body></html>"

    markdown = Nokodown.to_markdown(html)
    markdown.should include("The reading was confirmed at noon. [Witness statement](/witness.pdf)")
    markdown.should include("**Basil Cunningham**")
  end

  # Each container is weighed against the post as it was before.
  it "keeps a post's files that outweigh the rest without the lines" do
    links = (0..3).map { |index| "<a href='/schedule#{index}.pdf'>#{['Rye starter protocol', 'Feeding timetable', 'Fermentation diary', 'Rye starter protocol'][index]} #{index}</a>" }
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
           "<article class='message'><div class='user-info'><a class='username' href='/u/contributor'>Basil Alexander Cunningham of West Lancashire</a></div>" \
           "<header><a class='username' href='/u/Wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled. </p><div class='files'><div>#{links.join(' ')}</div></div></article>" \
           "<article class='message'><header><a class='username' href='/u/Fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article></main></body></html>"

    markdown = Nokodown.to_markdown(html)
    markdown.should include("[Rye starter protocol 0](/schedule0.pdf) [Feeding timetable 1](/schedule1.pdf)")
  end

  # Pruning weighs the post as it did before the poster's panels became
  # lines: a panel that names someone else, however it mentions the
  # poster, or one in a quote, counts as kept.
  it "keeps a post's files whatever the panels beside them say" do
    message = lambda do |inside|
      "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>#{inside}</article>"
    end
    fern = "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
           "<p>Leave room in the jar.</p></article>"
    files = "<div class='files'><p>Attachment</p><a href='/report.pdf'>Laboratory mixing log</a></div>"
    sources = lambda do |name, extra = ""|
      "<div class='sources'><div class='user-info'><a class='username' href='/members/48'>#{name}</a>#{extra}</div><p>Attached records</p>" \
        "<a href='/schedule.pdf'>Original feeding schedule</a> <a href='/temperature.pdf'>Daily temperature chart</a></div>"
    end
    three = "<div class='sources'><div class='user-info'><a class='username' href='/members/48'>Basil Cunningham</a></div>" \
            "<a href='/first.pdf'>First trial data</a> <a href='/water.pdf'>Water measurements</a> <a href='/oven.pdf'>Oven temperature</a></div>"
    quoted = "<section role='blockquote'><div class='member-controls'><div class='user-info'><a class='username' href='/m/cedar'>Wren</a></div>" \
             "<a href='/archive/prior-schedule'>See the past feeding schedule</a> <a href='/archive/temperature'>See the overnight temperature</a></div></section>"
    [
      [message.call("#{sources.call('Basil Cunningham', ' <span>Referred by Wren</span>')}<p>The starter doubled.</p>#{files}"),
       ["[Laboratory mixing log](/report.pdf)", "[Daily temperature chart](/temperature.pdf)"]],
      [message.call("<p>The starter doubled.</p>#{files}#{three}"), ["[Oven temperature](/oven.pdf)"]],
      [message.call("<section class='message-content'><p>The starter doubled.</p>#{files}#{quoted}</section>"),
       ["[Laboratory mixing log](/report.pdf)", "[See the overnight temperature](/archive/temperature)"]],
      ["<div class='row'>#{sources.call('Wren')}#{message.call("<p>The starter doubled.</p>#{files}")}</div>",
       ["[Laboratory mixing log](/report.pdf)"]]
    ].each do |post, links|
      html = "<html><head><meta name='generator' content='XenForo'></head><body><main>#{post}#{fern}</main></body></html>"

      markdown = Nokodown.to_markdown(html)
      links.each { |link| markdown.should include(link) }
    end
  end

  # The panel's line makes the div around it and its links a block, which
  # main kept as a paragraph: it counts as kept text, so the pass that
  # keeps it stands.
  it "keeps the links beside the poster's member panel lower in the post" do
    # The box may name the panel as what describes it.
    ["", " aria-describedby='owner'"].each do |described|
      html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
             "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
             "<p>The starter doubled.</p><div class='files'><p>Attachment</p><a href='/report.pdf'>Laboratory mixing log</a></div>" \
             "<div class='sources'#{described}><div class='user-info' id='owner'><a class='username' href='/u/wren'>Wren</a></div>" \
             "<a href='/first.pdf'>First trial data</a> <a href='/water.pdf'>Water measurements</a> <a href='/oven.pdf'>Oven temperature</a></div></article>" \
             "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
             "<p>Leave room in the jar.</p></article></main></body></html>"

      Nokodown.to_markdown(html).should include("[Oven temperature](/oven.pdf)")
    end
  end

  # Cards after the post's first paragraph are its content, the poster's
  # own among them.
  it "keeps the member cards below a post's first paragraph" do
    %w[Aster Wren].each do |first|
      cards = [[first, "Lab safety officer", "Safety review"], ["Moss", "Instrumentation engineer", "Instrument calibration"],
               ["Lark", "Sample custodian", "Sample manifest"]].each_with_index.map do |(name, role, report), index|
        "<div class='user-info'><a class='username' href='/members/#{87 + index}'>#{name}</a> " \
          "<span>#{role} · <a href='/reports/#{87 + index}.pdf'>#{report}</a></span></div>"
      end
      html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
             "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
             "<p>The starter doubled in volume overnight.</p><h3>Contributors</h3>#{cards.join}</article>" \
             "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
             "<p>Leave some room in the jar for the next feeding.</p></article></main></body></html>"

      markdown = Nokodown.to_markdown(html)
      markdown.should include("Lab safety officer · [Safety review](/reports/87.pdf)")
      markdown.should include("Sample custodian · [Sample manifest](/reports/89.pdf)")
    end

    # A roster in a list beside the opening post, before another post's
    # row with a roster of its own: the post and the card stay.
    roster = lambda do |people|
      "<ul>#{people.map { |name, id, role, kind| "<li><div class='user-info#{kind}'><a class='username' href='/members/#{id}'>#{name}</a> <span>#{role} · <a href='/reports/#{id}.pdf'>Report #{id}</a></span></div></li>" }.join}</ul>"
    end
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main><div class='reply-row'>" \
           "#{roster.call([['Wren', 87, 'Lab safety officer', ' reviewer']])}" \
           "<article class='message'><header><a class='username' href='/members/87'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled. I weighed the jar before and after the second feeding.</p></article>" \
           "<article class='message'><header><span class='username'>Advertisement</span> <time datetime='2024-05-04'>May 4, 2024</time></header><p>Sponsored content.</p></article></div>" \
           "<div class='reply-row'><article class='message'><header><a class='username' href='/u/Fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header><p>Leave room in the jar.</p></article>" \
           "#{roster.call([['Daisy', 187, 'Alternate recorder and steward of the signed instrumentation calibration notes for this laboratory'],
                           ['Clover', 188, 'Senior international instrumentation and engineering representative, fermentation division'],
                           ['Iris', 189, 'Custodian of the laboratory sample and certifications for the regional examination board']])}</div></main></body></html>"
    markdown = Nokodown.to_markdown(html)
    markdown.should include("**Wren** · May 3, 2024\n\nThe starter doubled.")
    markdown.should include("Lab safety officer · [Report 87](/reports/87.pdf)")

    # The content is chosen as base chose it, with the cards there: the
    # second post stays beside the first post's listed card, and the
    # opening post beside a card in sections.
    card = lambda do |name, id, role, kind = ""|
      "<div class='message-user#{kind}'><a class='username' href='/members/#{id}'>#{name}</a> <span>#{role} · <a href='/files/#{id}.pdf'>Report #{id}</a></span></div>"
    end
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main><div class='reply-row'><article class='message'>" \
           "<ul><li>#{card.call('Wren', 87, 'Safety officer for the fermentation project')}</li></ul>" \
           "<header><a class='username' href='/members/87'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled overnight. I marked the height of the mixture before the second feeding and weighed the jar at the same hour the next morning. " \
           "The other jar rose more slowly on the cooler side of the kitchen. I have attached the signed measurements.</p></article></div>" \
           "<div class='reply-row'><div class='contributors'>#{card.call('Fern', 89, 'Lab technician')}</div><article class='message'>" \
           "<header><a class='username' href='/members/89'>Fern</a> <time datetime='2024-05-04'>May 4, 2024</time></header>" \
           "<p>A second reading confirmed the result. The starter in my jar also reached the mark by noon.</p></article></div>" \
           "<footer><div class='contributors'>#{card.call('Morgan', 17, 'Records coordinator')}</div></footer></main></body></html>"
    markdown = Nokodown.to_markdown(html)
    markdown.should include("**Wren** · May 3, 2024\n\nThe starter doubled overnight.")
    markdown.should include("**Fern** · May 4, 2024\n\nA second reading confirmed the result.")

    html = "<html><head><meta name='generator' content='XenForo'></head><body><main><div class='reply-row'>" \
           "<section aria-label='Contributors'><section>#{card.call('Wren', 87, 'Lab safety officer', ' reviewer').sub('message-user', 'user-info')}</section></section>" \
           "<article class='message'><header><a class='username' href='/members/87'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The starter doubled. I weighed the jar before and after the second feeding.</p></article>" \
           "<article class='message'><header><span class='username'>Advertisement</span> <time datetime='2024-05-04'>May 4, 2024</time></header><p>Sponsored content.</p></article></div>" \
           "<div class='reply-row'><article class='message'><header><a class='username' href='/u/Fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header><p>Leave room in the jar.</p></article>" \
           "<section aria-label='Contributors'>#{[['Daisy', 187, 'Alternate recorder and steward of the signed instrumentation calibration notes for this laboratory'],
                                                 ['Clover', 188, 'Senior international instrumentation and engineering representative, fermentation division'],
                                                 ['Iris', 189, 'Custodian of the laboratory sample and certifications for the regional examination board']].map { |person| "<section>#{card.call(*person).sub('message-user', 'user-info')}</section>" }.join}</section></div></main></body></html>"
    markdown = Nokodown.to_markdown(html)
    markdown.should include("**Wren** · May 3, 2024\n\nThe starter doubled.")
    markdown.should include("Lab safety officer · [Report 87](/files/87.pdf)")

    # A card left in place must not narrow the choice to the first row:
    # where the cards reduced would take in the next post, it stays.
    signer = ->(name, id) { "<div class='message-user'><strong class='username'>#{name}</strong> <span>Project steward · <a href='/record/#{id}.pdf'>Signed review #{id}</a></span></div>" }
    html = "<html><head><meta name='generator' content='XenForo'></head><body><main><div class='reply-row'>#{signer.call('Wren', 1)}" \
           "<article class='message'><header><a class='username' href='/u/Wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
           "<p>The electrical current stayed within the specified range throughout this test. We repeated the run the next morning, when an independent " \
           "observer measured the sealed jar and signed the report. The overnight data are in the original log. Gas production had slowed.</p></article></div>" \
           "<div class='reply-row'><article class='message'><header><a class='username' href='/u/Fern'>Fern</a> <time datetime='2024-05-04'>May 4, 2024</time></header>" \
           "<p>Fern measured the pressure. <a href='/fern-lab.pdf'>Pressure report</a>.</p><aside><div class='user-info'><span class='username'>Iris</span>" \
           "<dl><dd class='profile-custom-field profile-time_zone'>Time zone: UTC+03:00 (Arabia Standard Time)</dd></dl></div></aside></article>" \
           "#{signer.call('Fern', 2)}</div>#{signer.call('Morgan', 3)}</main></body></html>"
    markdown = Nokodown.to_markdown(html, url: "https://example.com/threads/starter")
    markdown.should include("**Fern** · May 4, 2024\n\nFern measured the pressure. [Pressure report](https://example.com/fern-lab.pdf).")
    markdown.should include("[Signed review 3](https://example.com/record/3.pdf)")
  end

  # A card whose role names the poster is still another member's.
  # The first of a row of cards alike is a card too, the poster's own as well.
  # A featured card, with a class the others lack, is one of them (in a
  # row long enough for base to take it for cards).
  it "keeps a member card above a post that names the poster in its role" do
    [["Aster", "Wren’s lab safety officer", "", "div"], ["Wren", "Lab safety officer", "", "div"], ["Wren", "Lab safety officer", " featured", "div"],
     ["Wren", "Lab safety officer", "", "section"], ["Wren", "Lab safety officer", "", "li"], ["Wren", "Lab safety officer", "", "slot"],
     ["Wren", "Lab safety officer", "", "badge"], ["Wren", "Lab safety officer", "", "deep"],
     ["Wren", "Lab safety officer", "", "lead-badge"], ["Wren", "Lab safety officer", "", "lead-caption"],
     ["Wren", "Lab safety officer", "", "shell"], ["Wren", "Lab safety officer", "", "badged-levels"],
     ["Wren", "Lab safety officer", "", "linked-levels"], ["Wren", "Lab safety officer", "", "span-levels"],
     ["Wren", "Lab safety officer", "", "caption-levels"], ["Wren", "Lab safety officer", "", "badge-levels"],
     ["Wren", "Lab safety officer", "", "two-part-levels"], ["Wren", "Lab safety officer", "", "break-levels"],
     ["Wren", "Lab safety officer", "", "boxed-levels"], ["Wren", "Lab safety officer", "", "picture-levels"],
     ["Wren", "Lab safety officer", "", "mark-levels"], ["Wren", "Lab safety officer", "", "label-levels"]].each do |first, role, extra, tag|
      cards = [[first, role, "Safety review"], ["Moss", "Instrumentation engineer", "Instrument calibration"],
               ["Lark", "Sample custodian", "Sample manifest"], ["Juniper", "Records custodian", "Batch journal"]].each_with_index.map do |(name, title, report), index|
        name_tag = index.zero? && %w[div section].include?(tag) ? tag : "div"
        card = "<#{name_tag} class='user-info#{extra if index.zero?}'><a class='username' href='/members/#{87 + index}'>#{name}</a> <span>#{title} · <a href='/reports/#{87 + index}.pdf'>#{report}</a></span></#{name_tag}>"
        # Only the featured card may sit in a wrapper of its own.
        next "<section class='contributor-slot'>#{card}</section>" if tag == "slot" && index.zero?
        # The others' items hold a badge beside the card.
        next "<li>#{index.zero? ? '' : '<span>Staff member</span>'}#{card}</li>" if tag == "badge"
        # The featured card's wrapper holds a badge beside it.
        next "<section>#{card}<span>Staff member</span></section>" if tag == "lead-badge" && index.zero?
        # Or a caption longer than a badge.
        next "<section><span>Lead contributor and laboratory archivist</span>#{card}</section>" if tag == "lead-caption" && index.zero?
        # Each card sits three wrappers deep.
        next "<li><section><div class='card-body'>#{card}</div></section></li>" if tag == "deep"
        # The featured card in more wrappers, each around it alone.
        next "<li><div class='card-shell'><div class='card-content'><div class='media-body'>#{card}</div></div></div></li>" if tag == "shell" && index.zero?
        next "<li><div class='media-body'>#{card}</div></li>" if tag == "shell"
        # The others three sections deep, each beside a badge.
        next "<li>#{card}</li>" if tag == "badged-levels" && index.zero?
        next "<li>#{'<section><span>Staff member</span>' * 3}#{card}#{'</section>' * 3}</li>" if tag == "badged-levels"
        # The featured card four sections deep, each beside a linked label.
        next "<li>#{"<section><small><a href='/team'>Staff</a></small>" * 4}#{card}#{'</section>' * 4}</li>" if tag == "linked-levels" && index.zero?
        # Or a label whose link wraps its text, or a caption longer than a name.
        next "<li>#{"<section><small><a href='/team'><span>Staff</span></a></small>" * 4}#{card}#{'</section>' * 4}</li>" if tag == "span-levels" && index.zero?
        # Or a badge that nests its label in spans of its own.
        badge = "<span class='badge-visual'><span class='badge-inner'><span class='badge-label'>Staff</span></span></span>"
        next "<li>#{"<section><small><a href='/team'>#{badge}</a></small>" * 4}#{card}#{'</section>' * 4}</li>" if tag == "badge-levels" && index.zero?
        # Or a label in two parts side by side.
        next "<li>#{"<section><small><a href='/team'><b>Team</b><span>Staff directory</span></a></small>" * 4}#{card}#{'</section>' * 4}</li>" if tag == "two-part-levels" && index.zero?
        # Or a line break between the parts.
        next "<li>#{"<section><small><a href='/team'><b>Team</b><br><span>Staff directory</span></a></small>" * 4}#{card}#{'</section>' * 4}</li>" if tag == "break-levels" && index.zero?
        next "<li>#{"<section><small><a href='/team'><div><b>Team</b><span>Staff directory</span></div></a></small>" * 4}#{card}#{'</section>' * 4}</li>" if tag == "boxed-levels" && index.zero?
        picture = "<picture><source srcset='/icons/team.webp' type='image/webp'><img src='/icons/team.png' alt='Team badge'></picture>"
        next "<li>#{"<section><small><a href='/team'>#{picture}<span>Staff directory</span></a></small>" * 4}#{card}#{'</section>' * 4}</li>" if tag == "picture-levels" && index.zero?
        # Or an editorial mark or a <label> beside the label's text.
        next "<li>#{"<section><small><a href='/team'><del>Former</del><span>Safety staff</span></a></small>" * 4}#{card}#{'</section>' * 4}</li>" if tag == "mark-levels" && index.zero?
        next "<li>#{"<section><small><a href='/team'><label>Team</label><span>Safety staff</span></a></small>" * 4}#{card}#{'</section>' * 4}</li>" if tag == "label-levels" && index.zero?
        next "<li>#{'<section><span>Fermentation team members listed in the laboratory directory</span>' * 4}#{card}#{'</section>' * 4}</li>" if tag == "caption-levels" && index.zero?

        # A badge's picture: the others in items of their own, as a roster lists them.
        %w[li picture-levels mark-levels label-levels].include?(tag) ? "<li>#{card}</li>" : card
      end
      rows = [["Wren", question], ["Fern", answer], ["Moss", answer]].map do |name, body|
        "<article class='message'><header><a class='username' href='/u/#{name}'>#{name}</a> <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{body}</p></article>"
      end
      levels = %w[linked-levels span-levels caption-levels badge-levels two-part-levels break-levels boxed-levels picture-levels mark-levels label-levels]
      listed = (%w[li badge deep shell badged-levels] + levels).include?(tag)
      list = listed ? "<ul>#{cards.join}</ul>" : cards.join
      contributors = "<section class='contributors'><h3>Contributors</h3>#{list}</section>"
      markdown = thread(["<div class='reply-row'>#{contributors}#{rows[0]}</div>", *rows.drop(1).map { |row| "<div class='reply-row'>#{row}</div>" }])

      markdown.should include("**Wren** · May 3, 2024\n\n#{question}")
      markdown.should include("#{'- ' if listed && !levels.include?(tag)}[#{first}](https://example.com/members/87) #{role} · [Safety review](https://example.com/reports/87.pdf)"), tag
    end
  end

  # A quoted panel's box, kept for its line, is no reason to settle for a
  # pass that took a post's files.
  it "keeps a post's files beside a quoted member panel" do
    sources = [
      "<div class='user-info'><a class='username' href='/u/wren'>Wren</a></div>",
      "<div class='user-info'><a class='username' href='/members/48'>Basil Cunningham</a></div><p>Reference</p>"
    ]
    sources.each do |source|
      html = "<html><head><meta name='generator' content='XenForo'></head><body><main>" \
             "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
             "<p>The starter doubled.</p><div class='files'><p>Attachment</p><a href='/report.pdf'>Laboratory mixing log</a></div></article>" \
             "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
             "<p>Leave room in the jar.</p><blockquote><div class='sources'>#{source}" \
             "<a href='/schedule.pdf'>Original feeding schedule</a> <a href='/temperature.pdf'>Daily temperature chart</a></div></blockquote>" \
             "</article></main></body></html>"

      Nokodown.to_markdown(html).should include("[Laboratory mixing log](/report.pdf)")
    end
  end

  # Without the page's URL, ?member=72 and /?member=72 may be two members'.
  # A panel that names the poster in no link, beside a link that names
  # someone ("Referred by"), leaves the profile in doubt.
  it "keeps the member panel's line where the profile is in doubt" do
    [
      ["<a class='username' href='/?member=72'>Wren</a>", "<a class='username' href='?member=72'>Wren</a>", nil],
      ["<a class='username' href='/#wren'>Wren</a>", "<a class='username' href='#wren'>Wren</a>", nil],
      ["<span class='username'>Wren</span><span>Referred by <a href='/members/72'>Wren</a></span>",
       "<a class='username' href='/members/72'>Wren</a>", "https://example.com/threads/starter"]
    ].each do |panel, header, url|
      html = "<html><head><meta name='generator' content='XenForo'><title>Starter</title></head><body><main>" \
             "<article class='message'><header>#{header} <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p>" \
             "<div>Guest contributor</div><div class='user-info'>#{panel}</div></article>" \
             "<article class='message'><header><a class='username' href='/u/fern'>Fern</a> <time datetime='2024-05-05'>May 5, 2024</time></header>" \
             "<p>#{answer}</p></article></main></body></html>"
      markdown = url ? Nokodown.to_markdown(html, url: url) : Nokodown.to_markdown(html)

      markdown.should include("Guest contributor\n\n**Wren**\n\n**Fern** · May 5, 2024")
    end
  end

  # Two names alike are two members where the forum gives them two account
  # ids, or where the panel credits something else in the post
  # ("Uploaded by the member above").
  it "keeps the member panel's line that names another member of the same name" do
    [
      ["<div class='user-info'><span class='username' data-user-id='41'>Wren</span><a href='/members/41'>41</a></div>",
       "<span class='username' data-user-id='90'>Wren</span>"],
      ["<div class='user-info' id='uploader'><span class='username'>Wren</span></div>" \
       "<div class='postbody'><h3 aria-describedby='uploader'><a href='/report.pdf'>Uploaded by the member at left</a></h3></div>",
       "<a class='username' href='/members/wren'>Wren</a>"],
      # The profile link says so; the name's own id beats a referrer's.
      ["<div class='user-info'>Contributed by <span class='username'>Wren</span><a rel='author' href='/members/92'>View profile</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'><span class='username'>Wren</span><a href='/members/41' aria-label='View account 41'>✦</a></div>",
       "<a class='username' href='/members/90'>Wren</a>"],
      ["<div class='user-info'><span class='username'><a href='/members/41'>404</a></span></div>",
       "<a class='username' href='/members/90'>404</a>"],
      ["<div class='user-info'>Contributed by <span class='username' data-user-id='92'>Wren</span> · " \
       "Referred by <a href='/members/72' data-user-id='72'>@Wren</a></div>",
       "<span class='username' data-user-id='72'>Wren</span>"],
      ["<div class='user-info' data-user-id='92'>Contributed by <span class='username'>Wren</span> · " \
       "Referred by <a href='/members/72' data-user-id='72'>@Wren</a></div>",
       "<span class='username' data-user-id='72'>Wren</span>"],
      ["<div class='user-info'>Contributed by <span class='username'>Wren</span><a rel='AUTHOR' href='/members/92'>Biographie</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # The name's own link counts in a contact block; "Profile/Account" is
      # a label, not an address.
      ["<div class='user-info'><span class='contact-panel'><a class='username' href='/members/41'>Wren</a></span></div>",
       "<a class='username' href='/members/90'>Wren</a>"],
      ["<div class='user-info'><span class='username'>Wren</span><a href='/members/41'>Profile/Account</a></div>",
       "<a class='username' href='/members/90'>Wren</a>"],
      ["<div class='user-info'><span class='username'>Wren</span><a href='/teams/blue/Profile/Account'>Profile/Account</a></div>",
       "<a class='username' href='/members/90'>Wren</a>"],
      # rel="author" names the profile even in contact details.
      ["<div class='user-info'>Contributed by <span class='username'>Wren</span><span class='contact-details'><a rel='author' href='/members/92'>View profile</a></span></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Contributed by <span class='username'>Wren</span><a rel='author' href='mailto:wren@workshop.example'>Write</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # A theme's profile button may share phpBB's address-link class.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><a class='postlink' href='/members/92'>View profile</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><a class='postlink' href='/members/92/profile'>profile</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # An email link that says it is the profile, or a co-author's own
      # address beside the poster's other one.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><a class='postlink' href='mailto:wren.senior@example.org'>View profile</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><a itemprop='email' href='mailto:wren.senior@example.com'>Email Wren</a></div>",
       "<a class='username' href='mailto:wren.junior@example.com'>Wren</a>"],
      # A co-author's two addresses, or one in contact details, beside the
      # poster's profile or other address.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><a itemprop='email' href='mailto:wren.senior@example.com'>Email Wren</a>" \
       "<a href='mailto:wren-lab@example.com'>Email laboratory</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><span class='profile-contact'>" \
       "<a itemprop='email' href='mailto:wren.senior@example.com'>Email Wren</a></span></div>",
       "<a class='username' href='mailto:wren.junior@example.com'>Wren</a>"],
      # A board-local button that says it is the profile.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><a class='postlink-local' href='https://example.com/members/92/profile'>profile</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # A label between an address's start and end, or one host's start
      # beside another's.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><a class='postlink' href='https://profiles.example.net/archive/members/92'>https://example.com/ View profile ... members/92</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><a class='postlink' href='https://www.example.com.au/archive/members/92'>www.example.com/ View profile ... members/92</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # A co-author's own address beside one shared with the poster.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><span class='contact-details'><a itemprop='email' href='mailto:wren.senior@example.com'>Email Wren</a>" \
       "<a href='mailto:wren.junior@example.com'>Email laboratory</a></span></div>",
       "<a class='username' href='mailto:wren.junior@example.com'>Wren</a>"],
      # An email link's subject is not the address it shows.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small>Referred by <a href='mailto:Wren@example.org?subject=Wren'>Wren</a></small></div>",
       "<span class='username'>Wren</span>"],
      ["<div class='user-info'>Co-author <span class='username'>wren@example.org</span><small>Referred by " \
       "<a href='mailto:senior-wren@example.org?subject=Starter'>wren@example.org</a></small></div>",
       "<span class='username'>wren@example.org</span>"],
      # A theme's button or referral inside phpBB's field class says what
      # it is; a shortened address shows its own scheme.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-custom-field'>" \
       "<a class='postlink-local' href='https://example.com/members/92/profile'>View profile</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-custom-field'>Referred by " \
       "<a class='postlink' href='/members/92'>Wren</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><a class='postlink' href='https://lab.example/u/members/92/profile'>http://lab.example/u ... profile</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # A mailto's text that ends its address ("art" of "portrait.art") is
      # not the address; a whole host is not the start of a longer one.
      ["<div class='user-info'>Co-author <span class='username'>art</span><small>Referred by " \
       "<a href='mailto:office@portrait.art?subject=Introduction'>art</a></small></div>",
       "<span class='username'>art</span>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><a class='postlink' href='https://www.forum.org.au/people/92/profile'>www.forum.org ... profile</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # In phpBB's field class too: a button the href only ends with, a
      # shortened address of another scheme or host, an email's suffix.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-custom-field'>" \
       "<a class='postlink' href='https://example.com/members/92/viewProfile'>Profile</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-custom-field'>" \
       "<a class='postlink' href='https://lab.example/u/members/92/profile'>http://lab.example/u ... profile</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-custom-field'>" \
       "<a class='postlink' href='https://www.forum.org.au/people/92/profile'>www.forum.org ... profile</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>wren@example.org</span><small class='profile-custom-field'>Referred by " \
       "<a href='mailto:senior-wren@example.org?subject=Starter'>wren@example.org</a></small></div>",
       "<span class='username'>wren@example.org</span>"],
      # phpBB keeps an address's last 10 characters, not the 7 after a
      # 39-character host.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><a class='postlink' href='https://www.international-fermentation-labs.org.au/people/92/profile'>" \
       "www.international-fermentation-labs.org ... profile</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # A "www." address phpBB shows goes to "http://" that, not "https://".
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><a class='postlink' href='https://www.international-fermentation-labs.org.au/people/92/my-profile'>" \
       "www.international-fermentation-labs.org ... my-profile</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # A custom field named "contact" is not the contact block.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-custom-field profile-contact'>Referred by " \
       "<a class='postlink' href='https://example.com/members/SeniorWren'>Wren</a></small></div>",
       "<span class='username'>Wren</span>"],
      # In the field class, a shown start that is not phpBB's cut, and a
      # full URL's one word ("profile"), which only a board's own page shows.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-custom-field'>" \
       "<a class='postlink' href='https://directory.example/lookup/member-calibration-registry/p/92?tab=about'>https://directory.example/people ... View profile /p/92?tab=about</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-custom-field'>" \
       "<a class='postlink' href='https://directory.example/members/92/profile'>profile</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # A field's shown start or end that is not the href's, beyond a word
      # the censor could have changed: another host, path, or file name.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-custom-field'>" \
       "<a class='postlink' href='https://directory.example.org/research/fermentation/contributors/92/wren.html'>https://directory.example.org/research/ ... View profile.html</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-custom-field'>" \
       "<a class='postlink' href='https://www.international-directory.org.uk/directory/membership/92/my-profile'>https://www.international-directory.net ... my-profile</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span>" \
       "<a class='postlink' href='https://directory.example.org/research/fermentation/contributors/92/my-profile'>https://directory.example.org/people ... my-profile</a></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # The board's own profile page among the ways to reach the member.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-contact'>" \
       "<a class='postlink' href='/members/92'>View forum profile</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-contact'>" \
       "<a class='postlink' href='https://example.com/members/92'>View forum profile</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # A field-styled action phpBB did not make, shaped as a censored cut.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-custom-field'>" \
       "<a class='postlink' href='https://members.international-research-institute.org/directory/92/verification'>https://members.example.org/people/92 ... View profile</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-custom-field'>" \
       "<a class='postlink-local' href='https://example.com/members/92/profile'>profile</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # A theme's profile action between two links phpBB made, or with a
      # contact icon outside phpBB's contact menu, or between phpBB's
      # comments ("View forum profile" is no address).
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-actions'>" \
       "<!-- m --><a class='postlink' href='https://lab.example/my-profile'>https://lab.example/my-profile</a><!-- m -->" \
       "<a href='/members/92'>View forum profile</a>" \
       "<!-- m --><a class='postlink' href='https://lab.example/my-account'>https://lab.example/my-account</a><!-- m --></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-contact'>" \
       "<a href='/members/92'><span class='contact-icon'></span>View forum profile</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-contact'>" \
       "<!-- m --><a class='postlink' href='/members/92'>View forum profile</a><!-- m --></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-contact'>" \
       "<a class='postlink' href='https://example.com/members/92' aria-label='View forum profile'><span class='contact-icon'>◉</span></a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # phpBB's comments in a plain <dd>: around addresses beside the
      # theme's "View forum profile", or around that alone; and an
      # icon-only "#member-92" that says it is the profile.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><dl><dd>" \
       "<!-- m --><a class='postlink' href='https://lab.example/one'>https://lab.example/one</a><!-- m -->" \
       "<!-- m --><a class='postlink' href='/members/92'>View forum profile</a><!-- m -->" \
       "<!-- m --><a class='postlink' href='https://lab.example/two'>https://lab.example/two</a><!-- m --></dd></dl></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><dl><dd class='profile-custom-field profile-coauthor'><small><span>" \
       "<!-- m --><a class='postlink' href='/members/92'>View forum profile</a><!-- m --></span></small></dd></dl></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-contact'>" \
       "<a href='#member-92' class='postlink' aria-label='View forum profile'><svg aria-hidden='true' viewBox='0 0 8 8'><circle cx='4' cy='4' r='2'/></svg></a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # A directory link that ends with the member's name ("@Wren.Baker"),
      # or a board's own page phpBB made of it outside a field row.
      ["<div class='user-info'>Co-author <span class='username'>Wren.Baker</span><small>Member directory: " \
       "<a class='postlink' href='https://directory.example/users/92/@Wren.Baker'>Wren.Baker</a></small></div>",
       "<a class='username' href='https://example.com/members/72'>Wren.Baker</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren.Baker</span><small class='profile-actions'>Member directory: " \
       "<span class='profile-custom-field profile-coauthor'><a class='postlink' href='https://directory.example/users/92/@Wren.Baker'>Wren.Baker</a></span></small></div>",
       "<a class='username' href='https://example.com/members/72'>Wren.Baker</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-actions'>Member directory: " \
       "<!-- l --><a class='postlink-local' href='https://example.com/Wren'>Wren</a><!-- l --></small></div>",
       "<a class='username' href='https://example.com/members/72'>Wren</a>"],
      # The same in a theme's own classed <dd>, or a local-classed link to
      # another host's directory.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><dl><dt>Member directory</dt><dd class='coauthor-directory'>Member directory: " \
       "<!-- l --><a class='postlink-local' href='https://example.com/Wren'>Wren</a><!-- l --></dd></dl></div>",
       "<a class='username' href='https://example.com/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>A.J.</span><small class='profile-actions'>Member directory: " \
       "<a class='postlink-local' href='https://directory.example/directory/92/A.J.'>A.J.</a></small></div>",
       "<a class='username' href='https://example.com/members/72'>A.J.</a>"],
      # A theme's control phpBB-style comments bracket, in a <dd> of no
      # class or its own "profile-" class: a label, or a link elsewhere.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><dl><dd><!-- m --><a class='postlink' href='/members/92'>Profile: Wren</a><!-- m --></dd></dl></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><dl><dd class='profile-directory'><!-- m --><a class='postlink' href='/members/92'>Profile</a><!-- m --></dd></dl></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><dl><dd class='profile-coauthor-directory'>Member directory: " \
       "<!-- l --><a class='postlink-local' href='https://example.com/Wren'>Wren</a><!-- l --></dd></dl></div>",
       "<a class='username' href='https://example.com/members/72'>Wren</a>"],
      # A word inside the href's last segment, or a label around a cut.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><dl><dd class='profile-credit-field'>" \
       "<!-- m --><a class='postlink' href='https://example.com/memberlist.php?mode=viewprofile&amp;u=92'>profile</a><!-- m --></dd></dl></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><dl><dd class='profile-custom-field'>" \
       "<!-- m --><a class='postlink' href='/people/Wren.Baker/biography'>Wren</a><!-- m --></dd></dl></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><dl><dd class='profile-coauthor-field'>" \
       "<!-- m --><a class='postlink' href='/members/92'>Profile ... Wren</a><!-- m --></dd></dl></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # A board-style link to another host, or in a theme's own <small>.
      ["<div class='user-info'>Co-author <span class='username'>A.J.</span><dl><dd class='profile-custom-field profile-coauthor'>" \
       "<!-- l --><a class='postlink-local' href='https://directory.example/A.J.'>A.J.</a><!-- l --></dd></dl></div>",
       "<a class='username' href='https://example.com/members/72'>A.J.</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren.Baker</span><small class='member-directory'>Staff directory: " \
       "<a class='postlink-local' href='https://example.com/people/Wren.Baker'>Wren.Baker</a></small></div>",
       "<a class='username' href='/members/72'>Wren.Baker</a>"],
      ["<div class='user-info'>Co-author <span class='username'>gallery/profile/wren</span><small class='profile-custom-field'>" \
       "<a class='postlink' href='https://directory.example/people/92/gallery/profile/wren'>gallery/profile/wren</a></small></div>",
       "<a class='username' href='/members/72'>gallery/profile/wren</a>"],
      # A staff directory on the board's host outside its folder, or on
      # another host, in a field row of a theme's panel.
      ["<div class='user-info'>Co-author <span class='username'>Wren.Baker</span><dl><dd class='profile-custom-field profile-coauthor'>" \
       "<a class='postlink-local' href='https://example.com/staff/Wren.Baker'>Wren.Baker</a></dd></dl></div>",
       "<a class='username' href='/members/72'>Wren.Baker</a>"],
      # Above the page's folder, or in it spelled in other case.
      ["<div class='user-info'>Co-author <span class='username'>Wren.Baker</span><dl><dd class='profile-custom-field profile-coauthor'>" \
       "<a class='postlink-local' href='https://example.com/Wren.Baker'>Wren.Baker</a></dd></dl></div>",
       "<a class='username' href='/members/72'>Wren.Baker</a>"],
      ["<div class='user-info'>Co-author <span class='username'>Wren.Baker</span><dl><dd>" \
       "<a class='postlink-local' href='https://example.com/THREADS/Wren.Baker'>Wren.Baker</a></dd></dl></div>",
       "<a class='username' href='/members/72'>Wren.Baker</a>"],
      ["<div class='user-info'>Co-author <span class='username'>profile/Wren.Baker</span><dl><dd class='profile-custom-field profile-coauthor'>" \
       "<a class='postlink' href='https://people.example.net/staff/profile/Wren.Baker'>profile/Wren.Baker</a></dd></dl></div>",
       "<a class='username' href='/members/72'>profile/Wren.Baker</a>"],
      # The same host outside the page's folder, or no host: a theme's
      # directory, not phpBB's link.
      ["<div class='user-info'>Co-author <span class='username'>team/profile/wren</span><dl><dd class='profile-custom-field profile-directory'>" \
       "<a class='postlink' href='https://example.com/people/team/profile/wren'>team/profile/wren</a></dd></dl></div>",
       "<a class='username' href='/members/72'>team/profile/wren</a>"],
      ["<div class='user-info'>Co-author <span class='username'>profile/Wren.Baker</span><dl><dd class='profile-custom-field profile-coauthor'>" \
       "<a class='postlink' href='/staff/profile/Wren.Baker'>profile/Wren.Baker</a></dd></dl></div>",
       "<a class='username' href='/members/72'>profile/Wren.Baker</a>"],
      # A theme's class that only starts as phpBB's.
      ["<div class='user-info'>Co-author <span class='username'>profile/Wren.Baker</span><dl><dd class='profile-custom-field profile-coauthor'>" \
       "<a class='postlink-profile' href='https://directory.example.net/staff/profile/Wren.Baker'>profile/Wren.Baker</a></dd></dl></div>",
       "<a class='username' href='/members/72'>profile/Wren.Baker</a>"],
      # A theme's panel known by the id "postprofile" (prosilver's is "profile<post>").
      ["<dl id='postprofile' aria-label='Co-author' itemprop='author'><dt>Co-author <span class='username'>Wren.Baker</span></dt><dd class='coauthor-directory'>" \
       "<a class='postlink-local' href='https://directory.example.net/staff/profile/Wren.Baker'>Wren.Baker</a></dd></dl>",
       "<a class='username' href='/members/72'>Wren.Baker</a>"],
      # A menu's trigger that goes to the member.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-contact'>" \
       "<a href='#member-92' class='dropdown-trigger' rel='author'><img src='/i/user.png' alt=''></a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"],
      # A control that goes nowhere but says it is the profile.
      ["<div class='user-info'>Co-author <span class='username'>Wren</span><small class='profile-contact'>" \
       "<a class='postlink' href='#'>View forum profile</a></small></div>",
       "<a class='username' href='/members/72'>Wren</a>"]
    ].each do |panel, header|
      markdown = thread([
        "<article class='message'>#{panel}<header>#{header} <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p></article>",
        post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
      ])

      name = header[/>([^<]+)</, 1]
      markdown.scan(/\*\*#{Regexp.escape(name)}\*\*/).size.should eq(2), panel
      markdown.should include("**#{name}** · May 3, 2024\n\n#{question}")
    end

    # Without the page's URL, a board-style link outside prosilver's panel
    # is a theme's, relative or to another host.
    %w[postlink postlink-local].product(["/staff/profile/Wren.Baker", "https://directory.example.net/staff/profile/Wren.Baker"]).each do |klass, href|
      markdown = thread([
        "<article class='message'><div class='user-info'>Co-author <span class='username'>profile/Wren.Baker</span><dl><dd class='profile-custom-field profile-coauthor'>" \
        "<a class='#{klass}' href='#{href}'>profile/Wren.Baker</a></dd></dl></div>" \
        "<header><a class='username' href='/members/72'>profile/Wren.Baker</a> <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p></article>",
        post("basil", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
      ], url: nil)
      markdown.scan(%r{\*\*profile/Wren\.Baker\*\*}).size.should eq(2), "#{klass} #{href}"
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
  # table's caption, and reads a sparser grid as a layout, dropping what its
  # rows show with no text: a panel's line in a table stays.
  it "keeps the member panel's line in a table" do
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

    user = "<a class='username' href='/members/wren'>wren</a>"
    head = "<header>#{user} <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p>"
    basil = "<header><a class='username' href='/members/basil'>basil</a> <time datetime='2024-05-05'>May 5, 2024</time></header><p>#{answer}</p>"
    caption = "<caption><a href='/archives/friday'>Friday fermentation log</a></caption>"
    {
      "<table>#{caption}<tr><td><div class='desktop message-user'>#{user}</div><div class='mobile message-user'>#{user}</div></td>" \
      "<td>#{head}</td></tr><tr><td></td><td>#{basil}</td></tr></table>" => "[Friday fermentation log](https://example.com/archives/friday)",
      "<table>#{caption}<tr><td><table role='presentation'><tr><td><div class='message-user'>#{user}</div></td></tr></table></td>" \
      "<td>#{head}</td></tr><tr><td></td><td>#{basil}</td></tr></table>" => "[Friday fermentation log](https://example.com/archives/friday)",
      "<table><tr><td><div class='message-user'>#{user}</div></td><td>#{head}</td><td>Starter</td></tr>" \
      "<tr><td><div class='message-user'><a class='username' href='/members/basil'>basil</a></div></td><td>#{basil}</td><td>Starter</td></tr>" \
      "<tr><td>Attachment</td><td><iframe src='https://www.youtube.com/embed/abcd1234567' title='Starter demonstration'></iframe></td><td></td></tr>" \
      "<tr><td>Bake</td><td>Cover the loaf.</td><td></td></tr></table>" => "[Starter demonstration](https://www.youtube.com/watch?v=abcd1234567)"
    }.each do |table, shown|
      markdown = thread([table], head: '<meta name="generator" content="vBulletin">')

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

  # A theme may style a quoted author's date with phpBB's field class.
  it "keeps a quoted author's date in an element of phpBB's field class" do
    ["<small class='profile-custom-field'><time datetime='2024-05-02'>May 2, 2024</time></small>",
     "<span class='post-date profile-custom-field'>May 2, 2024</span>",
     "<span class='profile-custom-field' id='post-date-27'>May 2, 2024</span>",
     "<span class='profile-custom-field profile-post-date'>May 2, 2024</span>",
     "<span class='profile-custom-field profile-post_date' itemprop='datePublished'>May 2, 2024</span>",
     # Or with phpBB's contact icon class, saying it is the date.
     "<span class='contact-icon quoted-date' itemprop='datePublished'>May 2, 2024</span>"].each do |date|
      quote = "<blockquote><div id='user-info' aria-label='Original author'><span class='username'>Basil</span>#{date}</div><p>#{answer}</p></blockquote>"
      markdown = thread([
        "<article class='message'><header><a class='username' href='/u/wren'>Wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header>" \
          "<p>#{question}</p>#{quote}</article>",
        post("fern", "<time datetime='2024-05-05T09:10:00Z'>May 5, 2024</time>", answer)
      ])

      markdown.should include("**Wren** · May 3, 2024")
      markdown.should include("> **Basil** · May 2, 2024")
    end
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

  # A heading quoted in the header stays when the header goes.
  it "keeps a heading quoted in the header when the header goes" do
    markdown = thread([
      "<article class='message'><header><div role='blockquote'><h3><a href='/posts/14'>Original calibration failed</a></h3></div>" \
      "<a class='username' href='/u/wren'>wren</a> <time datetime='2024-05-03'>May 3, 2024</time></header><p>#{question}</p></article>",
      "<article class='message'><header><a class='username' href='/u/basil'>basil</a> <time datetime='2024-05-05'>May 5, 2024</time></header><p>#{answer}</p></article>"
    ])

    markdown.should include("[Original calibration failed](https://example.com/posts/14)")
    markdown.should include("**wren** · May 3, 2024\n\n#{question}")
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
