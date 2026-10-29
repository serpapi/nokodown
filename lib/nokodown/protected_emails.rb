# frozen_string_literal: true

module Nokodown
  # Email addresses that sites hide from harvesters, shown as a reader sees
  # them. Cloudflare puts "[email protected]" in their place, with the
  # address XOR-encoded in hex for the visitor's browser to decode; other
  # tools put a decoy inside the address that a stylesheet hides.
  module ProtectedEmails
    CLOUDFLARE_LINK = %r{/cdn-cgi/l/email-protection(?:#(\h+))?\z}.freeze
    EMAIL = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/.freeze
    # "info@ <span>ex.com</span> example.com": no address has spaces.
    DECOY = /\A([^\s@]+@)\s+(\S+)\s+([^\s@]+\.[^\s@]+)\z/.freeze

    module_function

    def reveal(root)
      root.css("[data-cfemail]").each { |node| reveal_cloudflare(node) }
      root.css("a[href*='/cdn-cgi/l/email-protection']").each { |link| relink(link) }
      root.xpath(".//text()[contains(., '@')]").map(&:parent).compact.each { |node| drop_decoy(node) }
    end

    def reveal_cloudflare(node)
      email = decode(node["data-cfemail"])
      return unless email

      node.content = email
      node["href"] = "mailto:#{email}" if node.name == "a"
    end

    def relink(link)
      hex = link["href"].to_s.strip[CLOUDFLARE_LINK, 1]
      email = hex ? decode(hex) : Dom.text(link)
      link["href"] = "mailto:#{email}" if email&.match?(EMAIL)
    end

    # The first byte is the key the others are XORed with.
    def decode(hex)
      bytes = [hex.to_s].pack("H*").bytes
      key = bytes.shift
      email = bytes.map { |byte| byte ^ key }.pack("C*").force_encoding(Encoding::UTF_8)
      email if email.valid_encoding? && email.include?("@")
    end

    def drop_decoy(node)
      match = Dom.text(node).match(DECOY)
      return unless match

      decoys = node.element_children.select { |child| Dom.text(child) == match[2] }
      node.content = match[1] + match[3] if decoys.size == 1
    end
  end
end
