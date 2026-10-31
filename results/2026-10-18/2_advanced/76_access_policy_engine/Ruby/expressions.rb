# Recursive descent follows the expression grammar's eight precedence levels.
module Expressions
  def self.parse(text)
    Parser.new(text).disjunction
  end

  class Parser
    def initialize(text)
      @tokens = text.scan(/"[^"]*"|[0-9]+|[A-Za-z][A-Za-z0-9_.]*|==|!=|<=|>=|[()\[\],+*<>-]/)
      @position = 0
    end

    def peek = @tokens[@position]

    def take
      token = peek
      @position += 1
      token
    end

    def joined(level, operators)
      tree = send(level)
      while operators.include?(peek)
        operator = take
        tree = [operator, tree, send(level)]
      end
      tree
    end

    def disjunction = joined(:conjunction, %w[or])
    def conjunction = joined(:negation, %w[and])
    def sum = joined(:product, %w[+ -])
    def product = joined(:unary, %w[*])

    def negation
      return comparison unless peek == 'not'
      take
      ['not', negation]
    end

    def comparison
      tree = sum
      tree = [take, tree, sum] if %w[== != < <= > >= in].include?(peek)
      tree
    end

    def unary
      return primary unless peek == '-'
      take
      ['-', unary]
    end

    def primary
      token = take
      return ['literal', token.to_i] if token.match?(/\A[0-9]+\z/)
      return ['literal', token[1...-1]] if token.start_with?('"')
      return ['literal', token == 'true'] if %w[true false].include?(token)
      return ['it'] if token == 'it'
      return ['attribute', token] if token.include?('.')
      if token == '('
        tree = disjunction
        take
        return tree
      end
      if token == '['
        items = []
        until peek == ']'
          items << take[1...-1]
          take unless peek == ']'
        end
        take
        return ['literal', items]
      end
      take # opening parenthesis of a function call
      arguments = []
      until peek == ')'
        arguments << disjunction
        take unless peek == ')'
      end
      take
      [token, *arguments]
    end
  end
end
