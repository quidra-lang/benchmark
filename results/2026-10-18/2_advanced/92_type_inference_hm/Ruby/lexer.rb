Token = Struct.new(:kind, :spelling, :value, :position) do
  def name? = kind == 'identifier' && spelling != '_'
end

module Lexer
  KEYWORDS = %w[let rec and in fun if then else match with true false mod val].freeze
  SYMBOLS = %w[;; -> :: : || && <= >= <> ; = < > + - * / ^ ( ) [ ] , |].freeze
  ESCAPES = { 'n' => "\n", 't' => "\t", '\\' => '\\', '"' => '"' }.freeze

  def self.tokenize(source, filename)
    tokens = []
    index = 0
    line = column = 1
    while index < source.length
      start = index
      position = [filename, line, column]
      character = source[index]
      kind = value = nil
      if " \n".include?(character)
        index += 1
      elsif source[index, 2] == '(*'
        closing = source.index('*)', index + 2)
        if closing
          index = closing + 2
        else
          kind, value, index = 'invalid', 'unterminated comment', source.length
        end
      elsif character.match?(/[0-9]/)
        index += 1 while index < source.length && source[index].match?(/[0-9]/)
        value = source[start...index].to_i
        kind = 'integer'
        kind, value = 'invalid', 'integer literal too large' if value > 2_147_483_647
      elsif character.match?(/[A-Za-z_]/)
        index += 1
        index += 1 while index < source.length && source[index].match?(/[A-Za-z0-9_']/)
        value = source[start...index]
        kind = KEYWORDS.include?(value) ? value : 'identifier'
      elsif character == "'" && source[index + 1]&.match?(/[a-z]/)
        index += 2
        index += 1 while index < source.length && source[index].match?(/[A-Za-z0-9_]/)
        kind, value = 'type_variable', source[start...index]
      elsif character == '"'
        index += 1
        decoded = +''
        invalid_escape = false
        while index < source.length && !"\"\n".include?(source[index])
          if source[index] == '\\' && source[index + 1] && source[index + 1] != "\n"
            escaped = ESCAPES[source[index + 1]]
            if escaped
              decoded << escaped
            else
              invalid_escape = true
            end
            index += 2
          else
            decoded << source[index]
            index += 1
          end
        end
        if index == source.length || source[index] == "\n"
          kind, value = 'invalid', 'unterminated string'
        else
          index += 1
          kind, value = invalid_escape ? ['invalid', 'invalid escape sequence'] : ['string', decoded]
        end
      else
        symbol = SYMBOLS.include?(source[index, 2]) ? source[index, 2] : character
        index += symbol.length
        kind, value = SYMBOLS.include?(symbol) ? [symbol, symbol] : ['invalid', "illegal character '#{character}'"]
      end
      consumed = source[start...index]
      tokens << Token.new(kind, consumed, value, position) if kind
      if consumed.include?("\n")
        line += consumed.count("\n")
        column = consumed.length - consumed.rindex("\n")
      else
        column += consumed.length
      end
    end
    tokens << Token.new('EOF', '', nil, [filename, source.count("\n") + 1, 1])
  end
end
