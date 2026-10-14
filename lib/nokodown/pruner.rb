# frozen_string_literal: true

module Nokodown
  # Final cleanup inside the selected content.
  class Pruner
    CLUSTER_CONTAINERS = "ul, ol, menu, dl, div, section, p, td, li, span, table, header, footer"
    TEXT_BLOCKS = "p, div, span, li, h1, h2, h3, h4, h5, h6, small, section, aside, figcaption, b, strong, em, i"
    BYLINE = /byline|author|dateline|writtenby|p-author/.freeze
    SHARE = /(?<![a-z])(?:share|sharedaddy)(?![a-z])/.freeze

    def initialize(nodes, mode)
      @nodes = nodes
      @mode = mode
    end

    def call
      @nodes.each do |root|
        @mode == :article ? prune_article(root) : remove_link_clusters(root)
        remove_boilerplate_text(root)
      end
    end

    private

    def prune_article(root)
      content_length = Dom.text(root).length
      remove_secondary(root, content_length)
      remove_bylines(root)
      remove_article_furniture(root, content_length)
      remove_related_links(root)
      remove_stray_lines(root)
      clean_conditionally(root, content_length)
      root.css("h1, h2").each { |heading| heading.remove if Scorer.class_weight(heading).negative? }
    end

    # Boxes of links to other stories placed inside the body: "READ MORE:
    # <link>", a "More:" label over a list of headlines, a paragraph of links.
    def remove_related_links(root)
      root.css("p, li, h2, h3, h4, h5, h6, strong, b").each do |node|
        text = Dom.text(node)
        if related_label?(text)
          remove_with_link_box(node)
        elsif related_box?(node, text)
          node.remove
        end
      end
    end

    # "More:" or "DON'T MISS" on its own.
    def related_label?(text)
      text.length <= 30 && text.match?(Patterns::RELATED_LABEL) && text.sub(Patterns::RELATED_LABEL, "").empty?
    end

    # The label may sit in a wrapper of its own (Wikipedia's div.mw-heading),
    # so the box of links follows the wrapper.
    def remove_with_link_box(label)
      text = Dom.text(label)
      holder = label
      holder = holder.parent while holder.next_element.nil? && holder.parent&.element? && Dom.text(holder.parent) == text
      following = holder.next_element
      following.remove if following && link_density(following) >= 0.6
      holder.remove
    end

    # "READ MORE: <headline>", or a paragraph made of several headlines.
    def related_box?(node, text)
      return link_density(node) >= 0.5 if text.match?(Patterns::RELATED_LABEL)

      node.name == "p" && node.css("a[href]").size >= 2 && link_density(node) >= 0.8
    end

    # Datelines and "follow us" lines.
    def remove_stray_lines(root)
      root.css("p, div, span, li, small, time").each do |node|
        next if Dom.ancestors_named(node, "table").any?

        text = Dom.text(node)
        node.remove if text.length <= 120 && text.match?(Patterns::STRAY_LINE)
      end
    end

    def link_density(node)
      text_length = Dom.text(node).length
      return 0.0 if text_length.zero?

      node.css("a[href]").sum { |link| Dom.text(link).length }.fdiv(text_length)
    end

    # Readability drops footers, asides and share widgets inside the article;
    # asides holding real prose (side notes) stay.
    def remove_article_furniture(root, content_length)
      root.css("footer").each { |node| node.remove if Dom.text(node).length <= content_length * 0.5 }
      root.css("aside").each do |node|
        node.remove if Dom.text(node).length < 200 || ContainerCheck.new(node, content_length, Set.new).remove?
      end
      root.css("[class], [id]").each do |node|
        node.remove if Dom.signature(node).match?(SHARE) && Dom.text(node).length < 500
      end
    end

    # Innermost containers first, so an outer one is judged on what is left.
    def clean_conditionally(root, content_length)
      paragraph_keys = Dom.paragraph_keys(root)
      ["form, fieldset", "table", "ul", "div"].each do |selector|
        root.css(selector).reverse_each do |node|
          next if paragraph_keys.include?(Dom.key(node))

          node.remove if ContainerCheck.new(node, content_length, paragraph_keys).remove?
        end
      end
    end

    def remove_secondary(root, total)
      root.element_children.each do |node|
        if Dom.signature(node).match?(Patterns::SECONDARY) && Dom.text(node).length <= total * 0.5
          node.remove
        else
          remove_secondary(node, total)
        end
      end
    end

    # The author line is returned as metadata, like Readability does. Many of
    # them mean a thread or a list of posts, where the authors are content.
    def remove_bylines(root)
      bylines = root.css("*").select do |node|
        byline = node["rel"] == "author" || node["itemprop"].to_s.include?("author") || Dom.signature(node).match?(BYLINE)
        byline && Dom.text(node).length.between?(1, 99)
      end
      bylines.each(&:remove) if bylines.size <= 2
    end

    # Navigation that survived as unlabeled markup: several links, almost no
    # other text, and no link long enough to be a headline.
    def remove_link_clusters(root)
      root.css(CLUSTER_CONTAINERS).reverse_each do |node|
        next if in_data_table?(node)

        node.remove if link_cluster?(node)
      end
    end

    def link_cluster?(node)
      links = node.css("a[href]")
      return false if links.size < 3

      text_length = Dom.text(node).length
      lengths = links.map { |link| Dom.text(link).length }
      text_length.positive? && lengths.max < 30 && lengths.sum.fdiv(text_length) >= 0.7
    end

    def in_data_table?(node)
      tables = node.name == "table" ? [node] : []
      (tables + Dom.ancestors_named(node, "table")).any? { |table| Tables.data_table?(table) }
    end

    def remove_boilerplate_text(root)
      root.css(TEXT_BLOCKS).each do |node|
        text = Dom.text(node)
        next if text.empty? || text.length > 200

        boilerplate = text.length <= 80 && text.match?(Patterns::BOILERPLATE_TEXT)
        copyright = text.match?(Patterns::COPYRIGHT_TEXT) && node.at_css("img").nil?
        node.remove if boilerplate || copyright
      end
    end
  end
end
