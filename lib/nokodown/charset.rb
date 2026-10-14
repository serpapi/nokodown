# frozen_string_literal: true

module Nokodown
  # Lexbor reads bytes as UTF-8 and ignores <meta charset>, so HTML is
  # transcoded first. Invalid bytes are dropped: they would make every regex
  # downstream raise.
  module Charset
    META_CHARSET = /<meta[^>]+charset\s*=\s*["']?\s*([\w-]+)/i.freeze

    module_function

    def utf8(html)
      html = html.dup.force_encoding(declared(html) || Encoding::UTF_8) if html.encoding == Encoding::BINARY
      html = html.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "") if html.encoding != Encoding::UTF_8
      html.valid_encoding? ? html : html.scrub("")
    end

    def declared(html)
      charset = html.byteslice(0, 4096)[META_CHARSET, 1]
      return unless charset

      Encoding.find(charset.sub(/\Autf8\z/i, "UTF-8"))
    rescue ArgumentError
      nil
    end
  end
end
