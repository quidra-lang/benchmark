require_relative 'unify'

module Prolog
  class Predicates
    SIGNATURES = {
      0 => %w[true fail false nl],
      1 => %w[var nonvar atom number integer atomic compound callable is_list write writeq],
      2 => %w[= \= == \== is =:= =\= < > =< >= =.. copy_term atom_length atom_chars length],
      3 => %w[functor arg between findall],
    }.flat_map { |arity, names| names.map { |name| [name, arity] } }.push(['throw', 1]).freeze
    def initialize(unifier, output, writer)
      @unifier, @output, @writer = unifier, output, writer
    end
    def unify(a, b) = @unifier.unify(a, b)
    def error(name, *args) = Terms.raise_error(name, *args)
    def integer(term)
      term = Terms.deref(term)
      error('instantiation_error') if term.is_a?(Variable)
      error('type_error', 'integer', term) unless term.is_a?(Integer)
      term
    end
    def atom(term)
      term = Terms.deref(term)
      error('instantiation_error') if term.is_a?(Variable)
      error('type_error', 'atom', term) unless term.is_a?(String)
      term
    end
    def proper_list(term)
      elements, tail = Terms.elements(term)
      error('instantiation_error') if tail.is_a?(Variable)
      error('type_error', 'list', term) unless tail == '[]'
      elements
    end
    def evaluate(term)
      term = Terms.deref(term)
      return term if term.is_a?(Integer)
      error('instantiation_error') if term.is_a?(Variable)
      name, arity = Terms.indicator(term)
      valid = arity == 1 && %w[- abs].include?(name) || arity == 2 && %w[+ - * // mod rem min max].include?(name)
      error('type_error', 'evaluable', Terms.pi(name, arity)) unless valid
      args = term.args.map { |a| evaluate(a) }
      x, y = args
      error('evaluation_error', 'zero_divisor') if %w[// mod rem].include?(name) && y.zero?
      result = case name
               when '+' then x + y
               when '-' then arity == 1 ? -x : x - y
               when '*' then x * y
               when '//' then x.abs.div(y.abs) * (x.negative? == y.negative? ? 1 : -1)
               when 'mod' then x - y * x.div(y)
               when 'rem' then x - y * (x.abs.div(y.abs) * (x.negative? == y.negative? ? 1 : -1))
               when 'abs' then x.abs
               when 'min' then [x, y].min
               when 'max' then [x, y].max
               end
      error('evaluation_error', 'int_overflow') unless (-2147483648..2147483647).cover?(result)
      result
    end
    def execute(goal)
      name, = Terms.indicator(goal)
      args = goal.is_a?(Compound) ? goal.args : []
      x, y, z = args.map { |a| Terms.deref(a) }
      case name
      when 'true' then true
      when 'fail', 'false' then false
      when '=' then unify(x, y)
      when '\\='
        height = @unifier.trail.length
        result = unify(x, y)
        @unifier.undo(height)
        !result
      when '==' then @unifier.identical?(x, y)
      when '\\==' then !@unifier.identical?(x, y)
      when 'var' then x.is_a?(Variable)
      when 'nonvar' then !x.is_a?(Variable)
      when 'atom' then x.is_a?(String)
      when 'number', 'integer' then x.is_a?(Integer)
      when 'atomic' then x.is_a?(String) || x.is_a?(Integer)
      when 'compound' then x.is_a?(Compound)
      when 'callable' then Terms.callable?(x)
      when 'is_list' then Terms.elements(x).last == '[]'
      when 'is' then unify(x, evaluate(y))
      when '=:=', '=\\=', '<', '>', '=<', '>='
        a, b = evaluate(x), evaluate(y)
        case name
        when '=:=' then a == b
        when '=\\=' then a != b
        when '<' then a < b
        when '>' then a > b
        when '=<' then a <= b
        when '>=' then a >= b
        end
      when 'functor'
        if !x.is_a?(Variable)
          n, a = x.is_a?(Compound) ? [x.name, x.args.length] : [x, 0]
          unify(y, n) && unify(z, a)
        else
          error('instantiation_error') if y.is_a?(Variable) || z.is_a?(Variable)
          error('type_error', 'atomic', y) if y.is_a?(Compound)
          error('type_error', 'integer', z) unless z.is_a?(Integer)
          error('domain_error', 'not_less_than_zero', z) if z.negative?
          error('representation_error', 'max_arity') if z > 255
          return unify(x, y) if z.zero?
          error('type_error', 'atom', y) if y.is_a?(Integer)
          unify(x, Compound.new(y, Array.new(z) { Variable.new }))
        end
      when 'arg'
        error('instantiation_error') if x.is_a?(Variable) || y.is_a?(Variable)
        error('type_error', 'integer', x) unless x.is_a?(Integer)
        error('type_error', 'compound', y) unless y.is_a?(Compound)
        (1..y.args.length).cover?(x) && unify(y.args[x - 1], z)
      when '=..'
        if !x.is_a?(Variable)
          unify(Terms.list(x.is_a?(Compound) ? [x.name, *x.args] : [x]), y)
        else
          elements = proper_list(y)
          error('domain_error', 'non_empty_list', '[]') if elements.empty?
          head = Terms.deref(elements.first)
          error('instantiation_error') if head.is_a?(Variable)
          if elements.length == 1
            error('type_error', 'atomic', head) if head.is_a?(Compound)
            unify(x, head)
          else
            error('type_error', 'atom', head) unless head.is_a?(String)
            error('representation_error', 'max_arity') if elements.length > 256
            unify(x, Compound.new(head, elements.drop(1)))
          end
        end
      when 'copy_term' then unify(Terms.copy(x), y)
      when 'atom_length'
        value = atom(x)
        error('type_error', 'integer', y) unless y.is_a?(Variable) || y.is_a?(Integer)
        unify(value.length, y)
      when 'atom_chars'
        if !x.is_a?(Variable)
          unify(y, Terms.list(atom(x).chars))
        else
          chars = proper_list(y).map do |element|
            element = Terms.deref(element)
            error('instantiation_error') if element.is_a?(Variable)
            error('type_error', 'character', element) unless element.is_a?(String) && element.length == 1
            element
          end
          unify(x, chars.join)
        end
      when 'write', 'writeq'
        @output << @writer.call(x, name == 'writeq')
        true
      when 'nl'
        @output << "\n"
        true
      end
    end
  end
end
