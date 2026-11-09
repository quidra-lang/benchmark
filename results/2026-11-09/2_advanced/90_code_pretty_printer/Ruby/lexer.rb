class SourceError < StandardError
  attr_reader :line, :column
  def initialize(line, column, message)
    @line, @column = line, column
    super(message)
  end
end

module Lexer
  TYPES = %w[int float bool string void].freeze
  KEYWORDS = (TYPES + %w[if else while for return break continue true false switch case default]).freeze
  ASSIGNMENT = %w[= += -= *= /= %=].freeze
  TWO = %w[<= >= == != && || += -= *= /= %=].freeze

  def self.scan(lines)
    tokens, comments, sequence = [], [], []
    previous_line = 0
    lines.each_with_index do |line, row|
      pos = 0
      while pos < line.length
        if line[pos] == ' '
          pos += 1
          next
        end
        start = pos
        rest = line[pos..]
        kind = :symbol
        if rest.start_with?('//')
          value, kind, pos = rest.rstrip, :line_comment, line.length
        elsif rest.start_with?('/*')
          stop = line.index('*/', pos + 2)
          raise SourceError.new(row + 1, pos + 1, 'unterminated comment') unless stop
          pos = stop + 2
          value, kind = line[start...pos], :block_comment
        elsif (match = /\A[A-Za-z_][A-Za-z_0-9]*/.match(rest))
          value = match[0]
          pos += value.length
          kind = KEYWORDS.include?(value) ? :keyword : :identifier
        elsif (match = /\A[0-9]+(?:\.[0-9]+)?/.match(rest))
          value, kind = match[0], :number
          pos += value.length
        elsif line[pos] == '"'
          pos += 1
          pos += line[pos] == '\\' ? 2 : 1 while pos < line.length && line[pos] != '"'
          raise SourceError.new(row + 1, start + 1, 'unterminated string') if pos >= line.length
          pos += 1
          value, kind = line[start...pos], :string
        elsif TWO.include?(line[pos, 2])
          value = line[pos, 2]
          pos += 2
        elsif '+-*/%<>=!()[]{},;.?:'.include?(line[pos])
          value = line[pos]
          pos += 1
        else
          raise SourceError.new(row + 1, pos + 1, "unexpected character '#{line[pos]}'")
        end
        entry = {text: value, kind: kind, line: row + 1, column: start + 1,
                 blank: [0, row - previous_line].max, order: sequence.length}
        previous_line = row + 1
        if %i[line_comment block_comment].include?(kind)
          comments << entry
        else
          entry.merge!(index: tokens.length, leading: [], trailing: [])
          tokens << entry
        end
        sequence << entry
      end
    end
    tokens << {text: '', kind: :end, line: lines.length + 1, column: 1,
               blank: 0, index: tokens.length, leading: [], trailing: [], allowed: true}
    [tokens, comments, sequence]
  end
end
