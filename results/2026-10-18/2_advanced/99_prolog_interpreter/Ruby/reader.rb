require_relative 'terms'

module Prolog
  SYMBOLS = '+-*/\\^<>=~:.?@#&$'.freeze
  INFIX = { ':-' => [1200, :xfx], ';' => [1100, :xfy], '->' => [1050, :xfy], ',' => [1000, :xfy] }
  %w[= \= == \== is =:= =\= < > =< >= =..].each { |s| INFIX[s] = [700, :xfx] }
  %w[+ -].each { |s| INFIX[s] = [500, :yfx] }
  %w[* / // mod rem].each { |s| INFIX[s] = [400, :yfx] }
  INFIX.freeze
  PREFIX = { '\\+' => 900, '-' => 200 }.freeze
  Token = Struct.new(:kind, :value, :spelling, :line, :column, :space, keyword_init: true)
  class ReadError < StandardError
    attr_reader :token, :index
    def initialize(token, index, message)
      @token, @index = token, index
      super(message)
    end
  end
  class Reader
    attr_reader :tokens, :index, :variables, :occurrences
    def initialize(text, start_column = 1)
      @tokens, @index = [], 0
      lex(text, start_column)
    end
    def lex(text, column)
      i, line, whitespace = 0, 1, true
      while i < text.length
        c = text[i]
        if c == ' ' || c == "\n"
          if c == "\n"
            line += 1
            column = 1
          else
            column += 1
          end
          i += 1
          whitespace = true
          next
        elsif c == '%'
          while i < text.length && text[i] != "\n"
            i += 1
            column += 1
          end
          whitespace = true
          next
        end
        start, col, kind, value = i, column, nil, nil
        if c.match?(/[0-9]/)
          i += 1 while i < text.length && text[i].match?(/[0-9]/)
          value = text[start...i].to_i
          kind = value > 2147483647 ? :invalid : :int
          value = 'integer too large' if kind == :invalid
        elsif c.match?(/[A-Za-z_]/)
          i += 1 while i < text.length && text[i].match?(/[A-Za-z0-9_]/)
          kind = c.match?(/[a-z]/) ? :name : :var
          value = text[start...i]
        elsif SYMBOLS.include?(c)
          i += 1 while i < text.length && SYMBOLS.include?(text[i])
          value = text[start...i]
          kind = value == '.' && (i == text.length || [" ", "\n", '%'].include?(text[i])) ? :end : :name
        elsif c == '!' || c == ';'
          kind, value = :name, c
          i += 1
        elsif ',|()[]'.include?(c)
          kind, value = :punct, c
          i += 1
        elsif c == "'"
          i += 1
          value, incorrect, closed = +'', false, false
          while i < text.length && text[i] != "\n"
            if text[i] == "'"
              if text[i + 1] == "'"
                value << "'"
                i += 2
              else
                i += 1
                closed = true
                break
              end
            elsif text[i] == '\\'
              if i + 1 == text.length || text[i + 1] == "\n"
                i += 1
              else
                escapes = { 'n' => "\n", 't' => "\t", '\\' => '\\', "'" => "'" }
                v = escapes[text[i + 1]]
                if v
                  value << v
                else
                  incorrect = true
                end
                i += 2
              end
            else
              value << text[i]
              i += 1
            end
          end
          kind = closed && !incorrect ? :quoted : :invalid
          value = closed ? 'undefined escape sequence' : 'unterminated quoted atom' if kind == :invalid
        else
          kind, value = :invalid, "illegal character '#{c}'"
          i += 1
        end
        tokens << Token.new(kind: kind, value: value, spelling: text[start...i], line: line, column: col, space: whitespace)
        column += i - start
        whitespace = false
      end
      tokens << Token.new(kind: :eof, value: nil, spelling: '', line: line, column: column, space: whitespace)
    end
    def peek = tokens[index]
    def take
      token = peek
      @index += 1 unless token.kind == :eof
      token
    end
    def fail_at(token, message = nil)
      message ||= case token.kind
                  when :invalid then token.value
                  when :eof then 'unexpected end of file'
                  when :end then 'unexpected end of clause'
                  else token.kind == :name && INFIX.key?(token.value) ? 'operator priority clash' : "unexpected \"#{token.spelling}\""
                  end
      raise ReadError.new(token, tokens.index { |t| t.equal?(token) }, message)
    end
    def expect(value)
      token = take
      fail_at(token) unless token.kind == :punct && token.value == value
    end
    def clause(query: false)
      @variables, @occurrences = {}, Hash.new(0)
      term, = read_term(1200)
      last = take
      fail_at(last) unless last.kind == :end
      fail_at(peek) if query && peek.kind != :eof
      term
    end
    def recover(error)
      @index = error.index
      @index += 1 while peek.kind != :end && peek.kind != :eof
      take if peek.kind == :end
    end
    def infix_token?(token) = (token.kind == :name || token.kind == :punct && token.value == ',') && INFIX.key?(token.value)
    def can_start?(token)
      return true if %i[int var quoted].include?(token.kind)
      return true if token.kind == :punct && ['(', '['].include?(token.value)
      token.kind == :name && (!INFIX.key?(token.value) || PREFIX.key?(token.value))
    end
    def read_term(limit)
      term, priority = primary(limit)
      while infix_token?(peek)
        p, type = INFIX[peek.value]
        left = type == :yfx ? p : p - 1
        break unless p <= limit && priority <= left
        op = take.value
        right, = read_term(type == :xfy ? p : p - 1)
        term, priority = Terms.compound(op, term, right), p
      end
      [term, priority]
    end
    def primary(limit)
      token = take
      case token.kind
      when :int then [token.value, 0]
      when :var
        name = token.value
        occurrences[name] += 1
        variable = name == '_' ? Variable.new : (variables[name] ||= Variable.new)
        [variable, 0]
      when :punct
        if token.value == '('
          term, = read_term(1200)
          expect(')')
          [term, 0]
        elsif token.value == '['
          if peek.kind == :punct && peek.value == ']'
            take
            return ['[]', 0]
          end
          elements = [read_term(999).first]
          while peek.kind == :punct && peek.value == ','
            take
            elements << read_term(999).first
          end
          tail = '[]'
          if peek.kind == :punct && peek.value == '|'
            take
            tail = read_term(999).first
          end
          expect(']')
          [Terms.list(elements, tail), 0]
        else
          fail_at(token)
        end
      when :name, :quoted
        name = token.value
        if peek.kind == :punct && peek.value == '(' && !peek.space
          take
          args = [read_term(999).first]
          while peek.kind == :punct && peek.value == ','
            take
            args << read_term(999).first
          end
          expect(')')
          [Compound.new(name, args), 0]
        elsif token.kind == :name && name == '-' && peek.kind == :int && !peek.space
          [-take.value, 0]
        elsif token.kind == :name && PREFIX.key?(name) && can_start?(peek)
          p = PREFIX[name]
          fail_at(token, 'operator priority clash') if p > limit
          [Terms.compound(name, read_term(p).first), p]
        else
          [name, 0]
        end
      else
        fail_at(token)
      end
    end
  end
end
