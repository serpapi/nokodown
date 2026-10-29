# frozen_string_literal: true

module Nokodown
  # Lexbor reads bytes as UTF-8 and ignores <meta charset>, so HTML is
  # transcoded first. Bytes without the HTTP headers that came with them
  # often misstate or omit their charset, so the bytes themselves decide
  # when they disagree with the <meta>. Invalid bytes left over are dropped:
  # they would make every regex downstream raise.
  module Charset
    META_CHARSET = /<meta[^>]+charset\s*=\s*["']?\s*([\w.:-]+)/i.freeze
    XML_ENCODING = /\A\s*<\?xml[^>]+encoding\s*=\s*["']([\w.:-]+)/.freeze
    HEAD_END = %r{</head\s*>|<body[\s>]}i.freeze
    PRESCAN = 32_768
    SAMPLE = 262_144
    HIGH_RUN_BEFORE_LETTER = /[\x80-\xFF]+(?=([A-Za-z])?)/n.freeze
    LEAD_BYTE = /\A[\xC2-\xF4]/n.freeze
    HIGH_BYTE = /[\x80-\xFF]/n.freeze
    DOUBLE_BYTE_RUN = /[\x80-\xFF](?:[\x40-\x7E]?[\x80-\xFF])*/n.freeze
    SINGLE_BYTE_PROBE = "\x81\xA1\xC1\xE1\xF1".b.freeze
    UTF8_BOM = "\xEF\xBB\xBF".b.freeze
    BOM_OR_REPLACEMENT = /\xEF(?:\xBB\xBF|\xBF\xBD)/n.freeze
    UTF16_BOMS = { "\xFF\xFE".b => Encoding::UTF_16LE, "\xFE\xFF".b => Encoding::UTF_16BE }.freeze
    # A PDF, an image, a font, an archive, a program or a media file served
    # as a page.
    BINARY_SIGNATURE = /
      \A\s{0,16}(?:%PDF-|%!PS-Adobe)|
      \A(?:\x89PNG\r\n\x1A\n|GIF8[79]a|\xFF\xD8\xFF|PK\x03\x04|\x1F\x8B\x08|BZh[1-9]1AY&SY|\xFD7zXZ\x00|7z\xBC\xAF\x27\x1C|
      Rar!\x1A\x07|\x7FELF|\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1|RIFF.{4}(?:WEBP|WAVE|AVI\x20)|OggS\x00|wOF[F2]|\x00\x00\x00.ftyp)
    /mnx.freeze
    # ESC is left out: ISO-2022-JP text shifts with it.
    CONTROL_BYTES = "\x00-\x08\x0E-\x1A\x1C-\x1F"
    BINARY_SAMPLE = 4096
    BINARY_SHARE = 0.03

    # Browsers read these labels as the superset encoding, as the WHATWG
    # Encoding Standard says: pages declared Latin-1 use Windows-1252 quotes,
    # GB2312 pages use GBK characters, and a <meta> that names UTF-16 is
    # itself proof that the bytes are not UTF-16.
    LABELS = {
      Encoding::Windows_1252 => /\A(?:iso[-_]?8859-1|latin-?1|l1|(?:us-)?ascii|cp819|ibm819|iso-ir-100|x-cp1252)\z/i,
      Encoding::Windows_1254 => /\A(?:iso[-_]?8859-9|latin-?5|l5|iso-ir-148)\z/i,
      Encoding::Windows_874 => /\A(?:tis-620|iso[-_]?8859-11|dos-874)\z/i,
      Encoding::GB18030 => /\A(?:gb[-_]?2312(?:-80)?|(?:x-)?gbk|cp936|ms936|windows-936|chinese|csgb2312|iso-ir-58|euc-cn)\z/i,
      Encoding::Windows_31J => /\A(?:shift[-_]jis|s-?jis|x-sjis|ms932|ms_kanji|csshiftjis)\z/i,
      Encoding::CP949 => /\A(?:euc-kr|ks_c_5601-198[79]|ksc_?5601|korean|windows-949|cseuckr|iso-ir-149)\z/i,
      Encoding::Big5_HKSCS => /\A(?:big5|cn-big5|x-x-big5|csbig5)\z/i,
      Encoding::EUCJP_MS => /\A(?:x-)?euc-jp\z/i,
      Encoding::UTF_8 => /\A(?:utf-?8|unicode-1-1-utf-8|utf-(?:16|32)(?:le|be)?|unicode(?:fffe)?|ucs-2|csunicode)\z/i
    }.freeze

    # Each multibyte encoding reads text in another as errors or as the
    # wrong script, so the first that reads the page as its own script wins.
    # Japanese goes first because CP949 reads Shift_JIS as Hangul, and Korean
    # before Chinese because GB18030 reads EUC-KR as Han. The two Cyrillic
    # encodings swap case and letters, so the common letters tell them apart.
    CJK = /[\p{Han}\u00B7\u2010-\u2027\u3000-\u303F\uFF00-\uFFEF]/.freeze
    COMMON_CYRILLIC = /[оеаинтсрвлОЕАИНТСРВЛ]/.freeze
    CANDIDATES = [
      [Encoding::Windows_31J, /\p{Hiragana}/, 0.03],
      [Encoding::EUCJP_MS, /\p{Hiragana}/, 0.03],
      [Encoding::CP949, /\p{Hangul}/, 0.9],
      [Encoding::GB18030, CJK, 0.8],
      [Encoding::Big5_HKSCS, CJK, 0.8],
      [Encoding::Windows_1251, COMMON_CYRILLIC, 0.4],
      [Encoding::KOI8_R, COMMON_CYRILLIC, 0.4]
    ].freeze
    MAX_ERRORS = 0.02
    MIN_CHARACTERS = 10
    WESTERN_SHARE = 0.5
    UTF8_SHARE = 0.5
    DECLARED_UTF8_SHARE = 0.9

    # UTF-8 read as Latin-1 or Windows-1252 and saved as UTF-8 again
    # ("cafÃ©") maps back one character to one byte: a continuation byte
    # reads as a C1 control, a Windows-1252 sign, or itself where
    # Windows-1252 leaves it undefined. Only the lead bytes of common scripts
    # (Â to Å, Æ, Î Ï, Ð Ñ, × to Û, à to ð) count, since a letter such as ß
    # or É before a no-break space also reads back as UTF-8, and each must
    # be followed by as many continuations as it leads: "í”" in Vietnamese
    # or "áš" in Slovak is two letters.
    SINGLE_BYTES = (0x80..0xFF).each_with_object({}) do |byte, bytes|
      bytes[byte.chr(Encoding::UTF_8)] = byte.chr
      char = byte.chr.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8, undef: :replace, replace: "")
      bytes[char] = byte.chr unless char.empty?
    end.freeze
    CONTINUATION = '(?:[\xC2\xC5\xC6\xCB][\x80-\xBF]|\xE2[\x80-\x84][\x80-\xBF]|[\x81\x8D\x8F\x90\x9D])'
    DOUBLE_ENCODED_TAIL = "(?:[\\x82-\\x86\\x8E-\\x91\\x97-\\x9B]#{CONTINUATION}|" \
                          "[\\xA0-\\xAF]#{CONTINUATION}{2}|\\xB0#{CONTINUATION}{3})"
    DOUBLE_ENCODED_CHAR = "\\xC3#{DOUBLE_ENCODED_TAIL}"
    DOUBLE_ENCODED_RUN = /\A(?:#{DOUBLE_ENCODED_CHAR})+\z/n.freeze
    # The look-behind comes after the lead byte, which the search can then
    # skip to.
    DOUBLE_ENCODED = /\xC3(?<![\x80-\xFF]\xC3)#{DOUBLE_ENCODED_TAIL}(?:#{DOUBLE_ENCODED_CHAR})*(?![\x80-\xFF])/n.freeze
    C1_CONTROL = /[\u0080-\u009F]/.freeze
    ONLY_C1_CONTROLS = /\A[\u0080-\u009F]+\z/.freeze
    SINGLE_CHARACTER = /\A[\u00A0-\u017F\u0370-\u04FF\u0600-\u06FF\u2000-\u214F\uFEFF]\z/.freeze
    # What UTF-8 a Western page holds: accented letters, Greek, Cyrillic,
    # punctuation, signs, emoji, and byte order marks and replacement
    # characters to be dropped. A letter and a sign of Windows-1252 that read
    # as UTF-8 by chance mostly make another script ("ß“" an NKo letter,
    # "é\u00A0»" a Han one).
    WESTERN = /\A[\u00A0-\u024F\u0370-\u04FF\u1E00-\u1EFF\u2000-\u27BF\uFEFF\uFFFD\u{1F000}-\u{1FAFF}]+\z/.freeze

    module_function

    # Pages hold next to no control bytes. UTF-16 without a byte order mark
    # holds a NUL beside each ASCII character, all on even or all on odd
    # bytes.
    def binary?(html)
      bytes = html.b
      return true if bytes.byteslice(0, BINARY_SAMPLE).match?(BINARY_SIGNATURE)

      bytes.count(CONTROL_BYTES) > bytes.bytesize * BINARY_SHARE && !utf16?(bytes.byteslice(0, BINARY_SAMPLE))
    end

    def utf16?(sample)
      even = (0...sample.bytesize).step(2).count { |index| sample.getbyte(index).zero? }
      odd = sample.count("\x00") - even
      [even, odd].max > sample.bytesize * 0.4 && [even, odd].min < sample.bytesize * 0.05
    end

    def utf8(html)
      html = decode(html.b) if html.encoding == Encoding::BINARY
      html = transcoded(html) if html.encoding != Encoding::UTF_8
      html = html.scrub("") unless html.valid_encoding?
      html.b.match?(BOM_OR_REPLACEMENT) ? html.delete("\uFEFF\uFFFD") : html
    end

    def transcoded(html)
      html.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "")
    rescue Encoding::ConverterNotFoundError
      html.force_encoding(Encoding::UTF_8)
    end

    # Bytes that read as UTF-8 are UTF-8 whatever the <meta> says: the
    # server's Content-Type, which wins over it, must have said so. ASCII
    # reads the same in any encoding but the 7-bit ones (ISO-2022-JP).
    def decode(bytes)
      UTF16_BOMS.each { |bom, encoding| return bytes.byteslice(2..).force_encoding(encoding) if bytes.start_with?(bom) }
      utf8 = bytes.delete_prefix(UTF8_BOM).force_encoding(Encoding::UTF_8)
      declared = declared(bytes)
      return redecoded_runs(utf8) if utf8.valid_encoding? && (!utf8.ascii_only? || declared.nil? || declared.ascii_compatible?)

      declared = nil if declared == Encoding::UTF_8
      return with_strays(bytes, declared) if reads_as_utf8?(bytes, declared ? DECLARED_UTF8_SHARE : UTF8_SHARE)

      encoding = declared || detected(bytes)
      return bytes.force_encoding(encoding) unless encoding.nil? || encoding == Encoding::Windows_1252

      mixed(bytes, Encoding::Windows_1252, whole: !encoding.nil?, western: !encoding.nil?)
    end

    # UTF-8 with bytes of another encoding here and there: the declared one
    # when each of its bytes is a character, Windows-1252 otherwise.
    def with_strays(bytes, declared)
      legacy = declared if declared && single_byte?(declared)
      mixed(bytes, legacy || Encoding::Windows_1252, whole: !legacy.nil?)
    end

    def single_byte?(encoding)
      probe = SINGLE_BYTE_PROBE.dup.force_encoding(encoding)
      !encoding.dummy? && probe.valid_encoding? && probe.length == probe.bytesize
    end

    def declared(html)
      head = html.byteslice(0, PRESCAN).b.split(HEAD_END, 2).first.to_s
      label = head[META_CHARSET, 1] || head.delete_prefix(UTF8_BOM)[XML_ENCODING, 1]
      return unless label

      LABELS.find { |_, labels| label.match?(labels) }&.first || Encoding.find(label)
    rescue ArgumentError
      nil
    end

    # Western text has its accented letters one at a time ("café") or two
    # inside a word ("Anotações"), which a double-byte encoding would read
    # as Han. Other scripts write whole words in high bytes, which
    # double-byte encodings interleave with ASCII trail bytes. Two at the
    # end of a word ("lisää") are Western when no script fits.
    def detected(bytes)
      runs = []
      bytes.scan(DOUBLE_BYTE_RUN) { runs << Regexp.last_match.offset(0) }
      return if runs.empty?
      return Encoding::Windows_1252 if runs.count { |from, to| western_run?(bytes, from, to) } > runs.size * WESTERN_SHARE

      sample = bytes.byteslice(0, SAMPLE)
      found = CANDIDATES.find { |encoding, script, share| reads_as?(sample, encoding, script, share) }&.first
      found || (Encoding::Windows_1252 if runs.count { |from, to| to - from <= 2 } > runs.size * WESTERN_SHARE)
    end

    def western_run?(bytes, from, to)
      to - from == 1 || (to - from == 2 && from.positive? && letter?(bytes.getbyte(from - 1)) && letter?(bytes.getbyte(to)))
    end

    def letter?(byte)
      !byte.nil? && (byte | 0x20).between?(0x61, 0x7A)
    end

    # Text in a legacy encoding reads as UTF-8 here and there by chance, so
    # a page that declares one must read almost entirely as UTF-8. The text
    # from the first high byte on tells, as it does for detection.
    def reads_as_utf8?(bytes, share)
      start = bytes.index(HIGH_BYTE)
      return false unless start

      sample = bytes.byteslice(start, SAMPLE)
      high = sample.bytesize - sample.count("\x00-\x7F")
      sample.force_encoding(Encoding::UTF_8).scrub("").bytesize - sample.bytesize + high >= high * share
    end

    def reads_as?(sample, encoding, script, share)
      text = sample.dup.force_encoding(encoding).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      chars = text.count("^\x00-\x7F").to_f
      chars >= MIN_CHARACTERS && text.count("\uFFFD") <= chars * MAX_ERRORS && text.scan(script).size >= chars * share
    end

    # UTF-8 with runs of a legacy encoding: when the page is known to be
    # Western or to use a single-byte encoding, every run that is not UTF-8
    # is in it. Otherwise only a lone byte is, and a lone lead byte only
    # inside a word: before anything else it is what is left of a character
    # cut off ("przekaza\xC4...").
    def mixed(bytes, legacy, whole: false, western: false)
      bytes.delete_prefix(UTF8_BOM).gsub(HIGH_RUN_BEFORE_LETTER) do |run|
        mixed_run(run, (whole || stray?(run, Regexp.last_match(1))) && legacy, western)
      end.force_encoding(Encoding::UTF_8)
    end

    # Valid UTF-8 only changes where it was decoded twice over, which most
    # pages never were.
    def redecoded_runs(utf8)
      bytes = utf8.b
      return utf8 if utf8.ascii_only? || !bytes.match?(DOUBLE_ENCODED)

      bytes.gsub(DOUBLE_ENCODED) { |run| redecoded(run) || run }.force_encoding(Encoding::UTF_8)
    end

    def stray?(run, letter)
      run.bytesize == 1 && (letter || !run.match?(LEAD_BYTE))
    end

    def mixed_run(run, legacy, western)
      redecoded = redecoded(run)
      return redecoded if redecoded

      utf8 = run.dup.force_encoding(Encoding::UTF_8)
      return run if utf8.valid_encoding? && (!western || utf8.match?(WESTERN))
      return utf8.scrub("").b unless legacy

      run.force_encoding(legacy).encode(Encoding::UTF_8, undef: :replace, replace: "").b
    end

    # A run decoded twice over is undone until it no longer reads back. One
    # character alone only counts in alphabets and punctuation: "é »" reads
    # back as one Han character, "×–" as a Hebrew letter. A run that reads
    # back as control characters only ("ÂŽ") was garbage before it was
    # misread.
    def redecoded(run)
      return unless run.match?(DOUBLE_ENCODED_RUN)

      chars = run.dup.force_encoding(Encoding::UTF_8).each_char
      bytes = chars.map { |char| char.valid_encoding? ? SINGLE_BYTES[char] : char.b }
      return if bytes.include?(nil)

      text = bytes.join.force_encoding(Encoding::UTF_8)
      return unless text.valid_encoding?
      return "".b if text.match?(ONLY_C1_CONTROLS)
      return if text.match?(C1_CONTROL) || (text.length == 1 && !text.match?(SINGLE_CHARACTER))

      redecoded(text.b) || text.b
    end
  end
end
