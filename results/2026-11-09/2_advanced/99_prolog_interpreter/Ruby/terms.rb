module Prolog
  class Variable
    attr_accessor :binding
  end
  Compound = Struct.new(:name, :args)
  class LogicError < StandardError
    attr_reader :term
    def initialize(term)
      @term = term
      super('Prolog error')
    end
  end
  module Terms
    def self.deref(term)
      term = term.binding while term.is_a?(Variable) && term.binding
      term
    end
    def self.compound(name, *args) = Compound.new(name, args)
    def self.callable?(term) = term.is_a?(String) || term.is_a?(Compound)
    def self.indicator(term)
      term = deref(term)
      term.is_a?(String) ? [term, 0] : [term.name, term.args.length]
    end
    def self.pi(name, arity) = compound('/', name, arity)
    def self.list(elements, tail = '[]') = elements.reverse_each.reduce(tail) { |rest, element| compound('.', element, rest) }
    def self.elements(term)
      values = []
      term = deref(term)
      while term.is_a?(Compound) && term.name == '.' && term.args.length == 2
        values << term.args[0]
        term = deref(term.args[1])
      end
      [values, term]
    end
    def self.copy(term, variables = {})
      term = deref(term)
      case term
      when Variable then variables[term] ||= Variable.new
      when Compound then Compound.new(term.name, term.args.map { |a| copy(a, variables) })
      else term
      end
    end
    def self.variables(term, result = [])
      term = deref(term)
      if term.is_a?(Variable)
        result << term
      elsif term.is_a?(Compound)
        term.args.each { |a| variables(a, result) }
      end
      result
    end
    def self.error(name, *args) = args.empty? ? name : compound(name, *args)
    def self.raise_error(name, *args) = raise LogicError.new(error(name, *args))
  end
end
