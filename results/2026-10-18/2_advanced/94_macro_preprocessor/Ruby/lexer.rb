require 'set'

# Tokens are immutable values: every altered occurrence is a new token.
Token = Data.define(:kind, :spelling, :line, :space, :hide) do
  def self.make(kind, spelling, line, space, hide = Set.new)
    new(kind, spelling, line, space, hide.freeze)
  end
end
LogicalLine = Data.define(:tokens, :start, :finish)

module Lexer
  PUNCTUATORS = %w[... <<= >>= -> ++ -- << >> <= >= == != && || *= /= %= += -= &= ^= |= ## [ ] ( ) { } . & * + - ~ ! / % < > ^ | ? : ; = , #].freeze
  module_function

  def read_token(text, position = 0, header = false)
    character = text[position]
    if header && character == '<'
      closing = text.index('>', position + 1)
      newline = text.index("\n", position + 1)
      return [:header, text[position..closing], closing + 1] if closing && (!newline || closing < newline)
    end
    tail = text[position..]
    if (identifier = /\A[A-Za-z_][A-Za-z_0-9]*/.match(tail))
      spelling = identifier[0]
      return [:identifier, spelling, position + spelling.length]
    end
    if character&.match?(/[0-9]/) || (character == '.' && text[position + 1]&.match?(/[0-9]/))
      ending = position + 1
      while ending < text.length
        if text[ending].match?(/[eEpP]/) && text[ending + 1]&.match?(/[+-]/)
          ending += 2
        elsif text[ending].match?(/[A-Za-z_0-9.]/)
          ending += 1
        else
          break
        end
      end
      return [:number, text[position...ending], ending]
    end
    if ['"', "'"].include?(character)
      ending = position + 1
      while ending < text.length && text[ending] != "\n"
        if text[ending] == character
          return [character == '"' ? :string : :character, text[position..ending], ending + 1]
        end
        ending += text[ending] == '\\' && text[ending + 1] && text[ending + 1] != "\n" ? 2 : 1
      end
    end
    punctuator = PUNCTUATORS.find { |item| text[position, item.length] == item }
    return [:punctuator, punctuator, position + punctuator.length] if punctuator
    [:other, character, position + 1]
  end

  def splice(text)
    characters, positions = +'', []
    index, line = 0, 1
    while index < text.length
      if text[index, 2] == "\\\n"
        index += 2
        line += 1
        next
      end
      characters << text[index]
      positions << line
      line += 1 if text[index] == "\n"
      index += 1
    end
    [characters, positions]
  end

  def scan(text, positions, start = 1)
    lines, tokens = [], []
    index, spaced = 0, true
    while index < text.length
      case
      when text[index] == ' '
        spaced = true
        index += 1
      when text[index] == "\n"
        ending = positions[index]
        lines << LogicalLine.new(tokens.freeze, start, ending)
        tokens, start, spaced = [], ending + 1, true
        index += 1
      when text[index, 2] == '/*'
        closing = text.index('*/', index + 2)
        index = closing ? closing + 2 : text.length
        spaced = true
      when text[index, 2] == '//'
        index = text.index("\n", index + 2) || text.length
        spaced = true
      else
        header = tokens.map(&:spelling) == ['#', 'include']
        kind, spelling, ending = read_token(text, index, header)
        tokens << Token.make(kind, spelling, positions[index], spaced)
        index, spaced = ending, false
      end
    end
    lines << LogicalLine.new(tokens.freeze, start, positions.last) unless tokens.empty?
    lines.freeze
  end

  def source(text)
    spliced, positions = splice(text)
    scan(spliced, positions)
  end

  def definition(text, line)
    scan(text + "\n", Array.new(text.length + 1, line), line).flat_map(&:tokens)
  end

  def render(tokens)
    tokens.each_with_index.map { |token, i| (i.positive? && token.space ? ' ' : '') + token.spelling }.join
  end

  def single_token(text)
    return nil if text.empty? || text.start_with?('//', '/*')
    kind, _, ending = read_token(text)
    kind if ending == text.length
  end
end
