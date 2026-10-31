Token = Struct.new(:kind, :spelling, :position)
class CompileError < StandardError
  attr_reader :kind, :position
  def initialize(kind, position, message)
    @kind, @position = kind, position
    super(message)
  end
end
module Lexer
  KEYWORDS = %w[int bool void true false if else while for break continue return print read].freeze
  DOUBLE = %w[<= >= == != && ||].freeze
  SINGLE = '+-*/%<>=!(){}[],;'
  def self.tokenize(lines)
    source = lines.map { |_, line| line + "\n" }.join
    index, row, column = 0, lines.first[0], 1
    tokens = []
    while index < source.length
      start = index
      position = [row, column]
      character = source[index]
      kind = nil
      if " \n".include?(character)
        index += 1
      elsif source[index, 2] == '//'
        index = source.index("\n", index)
      elsif source[index, 2] == '/*'
        closing = source.index('*/', index + 2)
        raise CompileError.new('lexical', position, 'unterminated comment') unless closing
        index = closing + 2
      elsif character.match?(/[A-Za-z_]/)
        index += 1
        index += 1 while index < source.length && source[index].match?(/[A-Za-z0-9_]/)
        kind = KEYWORDS.include?(source[start...index]) ? 'keyword' : 'identifier'
      elsif character.match?(/[0-9]/)
        index += 1 while index < source.length && source[index].match?(/[0-9]/)
        if source[start...index].to_i > 2_147_483_647
          raise CompileError.new('lexical', position, 'integer literal too large')
        end
        kind = 'integer'
      elsif DOUBLE.include?(source[index, 2])
        index += 2
        kind = 'symbol'
      elsif SINGLE.include?(character)
        index += 1
        kind = 'symbol'
      else
        raise CompileError.new('lexical', position, "unexpected character '#{character}'")
      end
      consumed = source[start...index]
      tokens << Token.new(kind, consumed, position) if kind
      if consumed.include?("\n")
        row += consumed.count("\n")
        column = consumed.length - consumed.rindex("\n")
      else
        column += consumed.length
      end
    end
    tokens << Token.new('end', '', [lines.last[0], lines.last[1].length + 1])
  end
end
