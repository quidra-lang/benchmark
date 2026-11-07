# frozen_string_literal: true

require_relative 'mime'

module Headers
  Token = Data.define(:kind, :text, :spaced)
  ADDRESS_MARKS = %q(!#$%&'*+-/=?^_`{|}~)
  MIME_EXCLUDED = [40, 41, 60, 62, 64, 44, 59, 58, 92, 34, 47, 91, 93, 63, 61].freeze

  def self.trim(text)
    text.gsub(/\A[ \t]+|[ \t]+\z/, '')
  end

  def self.collapse(text)
    trim(text.gsub(/[ \t]+/, ' '))
  end

  def self.fields(lines)
    fields = []
    invalid = []
    current = nil
    lines.each do |number, line|
      if line.start_with?(' ', "\t")
        if current
          current[1] << line
        else
          invalid << number
        end
        next
      end
      colon = line.index(':')
      if colon && colon.positive? && line[0...colon].each_byte.all? { |byte| byte.between?(33, 126) }
        current = [line[0...colon].downcase, line[colon + 1..]]
        fields << current
      else
        current = nil
        invalid << number
      end
    end
    fields.each { |field| field[1] = trim(field[1]) }
    [fields, invalid]
  end

  def self.remove_comments(text)
    result = +''
    depth = 0
    index = 0
    while index < text.length
      character = text[index]
      if depth.zero?
        if character == '('
          depth = 1
          result << ' '
        else
          result << character
        end
      elsif character == '\\'
        index += 1
      elsif character == '('
        depth += 1
      elsif character == ')'
        depth -= 1
      end
      index += 1
    end
    depth.zero? ? result : nil
  end

  def self.word_byte?(byte, variant)
    if variant == :address
      byte.between?(65, 90) || byte.between?(97, 122) || byte.between?(48, 57) ||
        ADDRESS_MARKS.include?(byte.chr)
    else
      byte.between?(33, 126) && !MIME_EXCLUDED.include?(byte)
    end
  end

  def self.tokens(text, variant)
    specials = variant == :address ? '<>:;@,.' : '/;='
    result = []
    index = 0
    spaced = false
    while index < text.length
      byte = text.getbyte(index)
      if byte == 32 || byte == 9
        spaced = true
        index += 1
        next
      end
      if byte == 40
        depth = 1
        index += 1
        while index < text.length && depth.positive?
          case text.getbyte(index)
          when 92 then index += 1
          when 40 then depth += 1
          when 41 then depth -= 1
          end
          index += 1
        end
        return nil unless depth.zero?

        spaced = true
        next
      end
      if byte == 34
        value = +''
        index += 1
        while index < text.length && text.getbyte(index) != 34
          if text.getbyte(index) == 92
            index += 1
            return nil if index == text.length
          end
          value << text[index]
          index += 1
        end
        return nil if index == text.length

        index += 1
        kind = :quoted
      elsif specials.include?(text[index])
        value = text[index]
        kind = value
        index += 1
      elsif word_byte?(byte, variant)
        first = index
        index += 1 while index < text.length && word_byte?(text.getbyte(index), variant)
        value = text[first...index]
        kind = :word
      else
        return nil
      end
      result << Token.new(kind, value, spaced)
      spaced = false
    end
    result
  end

  def self.encoded_word(word)
    return [word, false, false] unless word.length >= 4 && word.start_with?('=?') && word.end_with?('?=')

    pieces = word[2...-2].split('?', -1)
    return [word, false, false] unless pieces.length == 3 && pieces.none?(&:empty?)

    charset, encoding, text = pieces
    return [word, false, true] unless charset.downcase == 'us-ascii' && %w[Q q B b].include?(encoding)

    if encoding.downcase == 'b'
      decoded = Mime.strict_base64(text)
    else
      decoded = +''.b
      index = 0
      while index < text.length
        case text.getbyte(index)
        when 95
          decoded << 32
        when 61
          pair = text[index + 1, 2]
          return [word, false, true] unless pair&.match?(/\A[0-9A-Fa-f]{2}\z/)

          decoded << pair.to_i(16)
          index += 2
        else
          decoded << text.getbyte(index)
        end
        index += 1
      end
    end
    return [word, false, true] unless decoded && decoded.each_byte.all? { |byte| byte.between?(32, 126) }

    [decoded, true, false]
  end

  def self.unstructured(text)
    result = +''
    previous_success = false
    error = false
    text.scan(/[^ \t]+/).each_with_index do |word, index|
      decoded, success, failed = encoded_word(word)
      result << ' ' if index.positive? && !(previous_success && success)
      result << decoded
      previous_success = success
      error ||= failed
    end
    [collapse(result), error]
  end

  def self.parameters(text, subtype:)
    sequence = tokens(text, :mime)
    return nil unless sequence && sequence[0]&.kind == :word

    type = sequence[0].text.downcase
    index = 1
    sub = nil
    if subtype
      return nil unless sequence[index]&.kind == '/' && sequence[index + 1]&.kind == :word

      sub = sequence[index + 1].text.downcase
      index += 2
    end
    parameters = {}
    while index < sequence.length
      return nil unless sequence[index]&.kind == ';' && sequence[index + 1]&.kind == :word &&
                        sequence[index + 2]&.kind == '=' && [:word, :quoted].include?(sequence[index + 3]&.kind)

      name = sequence[index + 1].text.downcase
      parameters[name] = sequence[index + 3].text unless parameters.key?(name)
      index += 4
    end
    [type, sub, parameters]
  end
end
