# frozen_string_literal: true

module Mime
  ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

  def self.strict_base64(text)
    return nil unless (text.length % 4).zero?

    unpadded = text.sub(/=+\z/, '')
    return nil if text.length - unpadded.length >= 3

    result = +''.b
    buffer = 0
    bits = 0
    unpadded.each_char do |character|
      value = ALPHABET.index(character)
      return nil unless value

      buffer = (buffer << 6) | value
      bits += 6
      next if bits < 8

      bits -= 8
      result << ((buffer >> bits) & 255)
      buffer &= (1 << bits) - 1
    end
    result
  end

  def self.base64_body(text)
    decoded = strict_base64(text.delete(" \t\n"))
    return nil unless decoded

    decoded = decoded.gsub("\r\n", "\n")
    return nil unless decoded.each_byte.all? { |byte| byte == 9 || byte == 10 || byte.between?(32, 126) }

    decoded
  end

  def self.quoted_printable(text)
    lines = text.empty? ? [''] : text.split("\n", -1)
    result = +''.b
    error = false
    lines.each_with_index do |original, line_index|
      line = original.sub(/[ \t]+\z/, '')
      soft = line.end_with?('=')
      line = line[0...-1] if soft
      index = 0
      while index < line.length
        if line.getbyte(index) == 61
          pair = line[index + 1, 2]
          value = pair&.match?(/\A[0-9A-Fa-f]{2}\z/) ? pair.to_i(16) : nil
          if value && (value == 9 || value.between?(32, 126))
            result << value
            index += 3
            next
          end
          error = true
        end
        result << line.getbyte(index)
        index += 1
      end
      result << "\n" if !soft && line_index + 1 < lines.length
    end
    [result, error]
  end
end
