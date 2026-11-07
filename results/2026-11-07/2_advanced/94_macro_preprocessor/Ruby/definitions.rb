module Definitions
  BUILTINS = %w[__LINE__ __FILE__ __COUNTER__].freeze
  VARIADIC = '__VA_ARGS__'
  VARIADIC_ERROR = '"__VA_ARGS__" can only appear in the expansion of a variadic macro'
  class Error < StandardError; end

  class Macro
    attr_reader :name, :parameters, :variadic, :replacement, :position, :main_file
    attr_accessor :expanded, :tested

    def initialize(name, parameters, variadic, replacement, position, main_file)
      @name, @parameters, @variadic = name, parameters, variadic
      @replacement, @position, @main_file = replacement, position, main_file
      @expanded = @tested = 0
    end

    def signature
      return name unless parameters
      names = parameters.dup
      names[-1] = '...' if variadic
      "#{name}(#{names.join(', ')})"
    end

    def identical?(other)
      parameters == other.parameters && variadic == other.variadic &&
        replacement.map { |t| [t.spelling, t.space] } == other.replacement.map { |t| [t.spelling, t.space] }
    end
  end

  module_function

  def check_name(tokens, directive)
    return "no macro name given in ##{directive} directive" if tokens.empty?
    return 'macro names must be identifiers' unless tokens[0].kind == :identifier
    name = tokens[0].spelling
    return '"defined" cannot be used as a macro name' if name == 'defined'
    if BUILTINS.include?(name)
      operation = directive == 'define' ? 'redefine' : 'undefine'
      return "cannot #{operation} builtin macro \"#{name}\""
    end
    nil
  end

  def parse(tokens, position, main_file)
    error = check_name(tokens, 'define')
    raise Error, error if error
    name = tokens[0].spelling
    raise Error, VARIADIC_ERROR if name == VARIADIC
    parameters, variadic, index = nil, false, 1
    if tokens[1]&.spelling == '(' && !tokens[1].space
      parameters, index = [], 2
      raise Error, "missing ')' in macro parameter list" unless tokens[index]
      if tokens[index].spelling == ')'
        index += 1
      else
        loop do
          token = tokens[index]
          raise Error, "missing ')' in macro parameter list" unless token
          if token.spelling == '...'
            parameters << VARIADIC
            variadic = true
          elsif token.kind == :identifier
            raise Error, VARIADIC_ERROR if token.spelling == VARIADIC
            raise Error, "duplicate macro parameter \"#{token.spelling}\"" if parameters.include?(token.spelling)
            parameters << token.spelling
          else
            raise Error, "expected parameter name, found \"#{token.spelling}\""
          end
          index += 1
          raise Error, "missing ')' in macro parameter list" unless tokens[index]
          following = tokens[index].spelling
          index += 1
          break if following == ')'
          raise Error, "expected ')' after \"...\", found \"#{following}\"" if variadic
          raise Error, "expected ',' or ')', found \"#{following}\"" unless following == ','
        end
      end
    end
    replacement = tokens[index..].dup
    unless replacement.empty?
      replacement[0] = replacement[0].with(space: false)
      if [replacement.first.spelling, replacement.last.spelling].include?('##')
        raise Error, "'##' cannot appear at either end of a macro expansion"
      end
    end
    replacement.each_with_index do |token, i|
      raise Error, VARIADIC_ERROR if token.kind == :identifier && token.spelling == VARIADIC && !variadic
      if token.spelling == '#' && parameters
        following = replacement[i + 1]
        unless following&.kind == :identifier && parameters.include?(following.spelling)
          raise Error, "'#' is not followed by a macro parameter"
        end
      end
    end
    Macro.new(name, parameters, variadic, replacement, position, main_file)
  end
end
