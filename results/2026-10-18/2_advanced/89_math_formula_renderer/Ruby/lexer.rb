module Lexer
  Token = Struct.new(:kind, :value, :column)
  GREEK = %w[alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega].freeze
  FUNCTIONS = %w[sin cos tan log ln exp det lim max min].freeze
  LARGE = %w[sum prod int].freeze
  SYMBOL_COMMANDS = GREEK.to_h { |name| ["\\#{name}", [name, 'ordinary']] }
    .merge((FUNCTIONS + LARGE).to_h { |name| ["\\#{name}", [name, 'operator']] })
    .merge('\\cdot' => ['*', 'binary'], '\\times' => ['x', 'binary'],
           '\\pm' => ['+-', 'binary'], '\\mp' => ['-+', 'binary'],
           '\\leq' => ['<=', 'relation'], '\\geq' => ['>=', 'relation'],
           '\\neq' => ['!=', 'relation'], '\\approx' => ['~=', 'relation'],
           '\\to' => ['->', 'relation'], '\\infty' => ['oo', 'ordinary'],
           '\\ldots' => ['...', 'ordinary'], '\\cdots' => ['...', 'ordinary'],
           '\\quad' => ['  ', 'ordinary'], '\\,' => [' ', 'ordinary'],
           '\\{' => ['{', 'open'], '\\}' => ['}', 'close']).freeze
  COMMAND_NAMES = SYMBOL_COMMANDS.keys.map { |name| name[1..] }.select { |name| /\A[A-Za-z]+\z/.match?(name) }.freeze
  ACCENTS = %w[overline hat vec dot tilde overbrace underbrace].freeze
  CONSTRUCTS = %w[frac binom overset underset sqrt left right].freeze
  RAW = %w[text begin end tag label eqref].freeze
  ENVIRONMENTS = %w[matrix pmatrix bmatrix vmatrix cases].freeze
  SYMBOLS = "+-*/=<>:()[],;.!|'".freeze

  class FormulaError < StandardError
    attr_reader :column

    def initialize(column, message)
      @column = column
      super(message)
    end
  end

  def self.letter?(character)
    character && /[A-Za-z]/.match?(character)
  end

  def self.digit?(character)
    character && /[0-9]/.match?(character)
  end

  def self.tokenize(line)
    tokens = []
    position = 0
    while position < line.size
      character = line[position]
      column = position + 1
      if character == ' '
        position += 1
        next
      end
      if letter?(character) || digit?(character)
        first = position
        numeric = digit?(character)
        position += 1
        position += 1 while (numeric ? digit?(line[position]) : letter?(line[position]))
        if numeric && line[position] == '.' && digit?(line[position + 1])
          position += 2
          position += 1 while digit?(line[position])
        end
        tokens << Token.new(numeric ? 'number' : 'identifier', line[first...position], column)
        next
      end
      if SYMBOLS.include?(character) || '{}^_&'.include?(character)
        tokens << Token.new(SYMBOLS.include?(character) ? 'symbol' : character, character, column)
        position += 1
        next
      end
      raise FormulaError.new(column, "invalid character #{character}") unless character == '\\'
      position += 1
      if line[position] && '\\{},'.include?(line[position])
        escaped = line[position]
        tokens << Token.new(escaped == '\\' ? 'newline' : 'command', '\\' + escaped, column)
        position += 1
        next
      end
      first = position
      position += 1 while letter?(line[position])
      name = line[first...position]
      raise FormulaError.new(column, 'invalid command') if name.empty?
      if RAW.include?(name)
        position += 1 while line[position] == ' '
        raise FormulaError.new(position + 1, 'expected {') unless line[position] == '{'
        closing = line.index('}', position + 1)
        raise FormulaError.new(column, 'unterminated argument') unless closing
        value = line[(position + 1)...closing]
        if %w[begin end].include?(name) && !ENVIRONMENTS.include?(value)
          raise FormulaError.new(column, "unknown environment \"#{value}\"")
        end
        tokens << Token.new(name, value, column)
        position = closing + 1
      elsif SYMBOL_COMMANDS.key?('\\' + name)
        tokens << Token.new('command', '\\' + name, column)
      elsif ACCENTS.include?(name)
        tokens << Token.new('accent', name, column)
      elsif CONSTRUCTS.include?(name)
        tokens << Token.new(name, name, column)
      else
        raise FormulaError.new(column, 'unknown command \\' + name)
      end
    end
    tokens << Token.new('eof', '', line.size + 1)
  end
end
