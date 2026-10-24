# frozen_string_literal: true

module IniLexer
  LITERAL_DOLLAR = "\x01"
  ESCAPES = { '\\' => '\\', '"' => '"', 'n' => "\n", 't' => "\t", '$' => LITERAL_DOLLAR }.freeze
  LogicalLine = Struct.new(:number, :parts, :error)

  def self.read(text)
    physical = text.split("\n", -1)
    physical.pop
    result = []
    line_index = 0
    while line_index < physical.length
      number = line_index + 1
      parts = [[false, +'']]
      quoted = false
      error = nil
      line = physical[line_index]
      index = 0
      while index < line.length
        character = line[index]
        if character == '\\' && index == line.length - 1
          line_index += 1
          line = physical[line_index].sub(/\A */, '')
          index = 0
          next
        end
        if quoted
          if character == '"'
            quoted = false
            parts << [false, +'']
          elsif character == '\\'
            escaped = line[index + 1]
            if ESCAPES.key?(escaped)
              parts.last[1] << ESCAPES[escaped]
            else
              error ||= ['E_ESCAPE', "invalid escape sequence \\#{escaped}"]
            end
            index += 2
            next
          else
            parts.last[1] << character
          end
        elsif character == '"'
          quoted = true
          parts << [true, +'']
        elsif character == ';' || character == '#'
          break
        else
          parts.last[1] << character
        end
        index += 1
      end
      error ||= ['E_UNTERMINATED', 'unterminated string'] if quoted
      result << LogicalLine.new(number, parts, error)
      line_index += 1
    end
    result
  end
end
