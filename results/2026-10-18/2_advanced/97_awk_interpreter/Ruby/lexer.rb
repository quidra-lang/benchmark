Token = Struct.new(:kind, :text, :value, :line, :column) do
  def position
    "#{line}:#{column}"
  end
end

class AwkSyntaxError < StandardError
  attr_reader :token
  def initialize(token)
    @token = token
    super("status: syntax error at #{token.position}")
  end
end

class Lexer
  KEYWORDS = %w[BEGIN END function if else while for do break continue next exit return delete in getline print printf].freeze
  BUILTINS = %w[length substr index split sprintf toupper tolower close int].freeze
  PAIRS = %w[+= -= *= /= %= ^= == <= >= != ++ -- && || >>].freeze
  SYMBOLS = '+-*/%^!><?:=()[]{},;$'.freeze

  def self.letter?(c)
    c && (('a'..'z').cover?(c) || ('A'..'Z').cover?(c) || c == '_')
  end

  def self.digit?(c)
    c && ('0'..'9').cover?(c)
  end

  def self.name?(s)
    !s.empty? && letter?(s[0]) && s.each_char.all? { |c| letter?(c) || digit?(c) }
  end

  def initialize(source)
    @source, @at, @line, @column = source, 0, 1, 1
  end

  def advance
    char = @source[@at]
    @at += 1
    if char == "\n"
      @line += 1
      @column = 1
    else
      @column += 1
    end
    char
  end

  def tokens
    result = []
    while @at < @source.length
      c = @source[@at]
      token = Token.new(nil, c, nil, @line, @column)
      if c == ' '
        advance
        next
      elsif c == '\\' && @source[@at + 1] == "\n"
        2.times { advance }
        next
      elsif c == '#'
        advance while @at < @source.length && @source[@at] != "\n"
        next
      elsif c == "\n"
        token.kind = :nl
        advance
      elsif self.class.digit?(c)
        first = @at
        advance while self.class.digit?(@source[@at])
        token.kind, token.text = :number, @source[first...@at]
        token.value = token.text.to_i
      elsif self.class.letter?(c)
        first = @at
        advance while self.class.letter?(@source[@at]) || self.class.digit?(@source[@at])
        token.text = @source[first...@at]
        token.kind = if KEYWORDS.include?(token.text) then token.text
                     elsif BUILTINS.include?(token.text) then :builtin
                     elsif @source[@at] == '(' then :funcname
                     else :name
                     end
      elsif c == '"'
        advance
        value = +''
        loop do
          raise AwkSyntaxError.new(token) if @at >= @source.length || @source[@at] == "\n"
          break if @source[@at] == '"'
          if @source[@at] == '\\'
            slash = Token.new(nil, '\\', nil, @line, @column)
            advance
            escaped = { 'n' => "\n", 't' => "\t", '\\' => '\\', '"' => '"', '/' => '/' }[@source[@at]]
            raise AwkSyntaxError.new(slash) unless escaped
            value << escaped
            advance
          else
            value << advance
          end
        end
        advance
        token.kind, token.value = :string, value
      else
        pair = @source[@at, 2]
        if PAIRS.include?(pair)
          token.kind = token.text = pair
          2.times { advance }
        elsif SYMBOLS.include?(c)
          token.kind = c
          advance
        else
          raise AwkSyntaxError.new(token)
        end
      end
      result << token
    end
    result << Token.new(:eof, '', nil, @line, 1)
  end
end
