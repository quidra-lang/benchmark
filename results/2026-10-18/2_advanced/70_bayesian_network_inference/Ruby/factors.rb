require_relative 'learning'

module Factors
  def self.entry_count(variables, sizes)
    variables.inject(1) { |product, variable| product * sizes[variable] }
  end

  def self.assignments(variables, sizes)
    return enum_for(__method__, variables, sizes) unless block_given?

    states = Array.new(variables.length, 0)
    loop do
      yield variables.zip(states).to_h
      index = variables.length - 1
      while index >= 0
        states[index] += 1
        break if states[index] < sizes[variables[index]]

        states[index] = 0
        index -= 1
      end
      break if index.negative?
    end
  end

  class Factor
    attr_reader :variables, :values

    def initialize(variables, values, sizes)
      @variables, @values, @sizes = variables, values, sizes
    end

    def value(assignment)
      @values[Learning.parent_row(@variables, assignment, @sizes)]
    end

    def reduced(evidence)
      variables = @variables.reject { |variable| evidence.key?(variable) }
      values = Factors.assignments(variables, @sizes).map { |assignment| value(assignment.merge(evidence)) }
      Factor.new(variables, values, @sizes)
    end

    def multiplied(other)
      variables = (@variables | other.variables).sort
      values = Factors.assignments(variables, @sizes).map { |assignment| value(assignment) * other.value(assignment) }
      Factor.new(variables, values, @sizes)
    end

    def eliminate(variable, maximize = false)
      variables = @variables - [variable]
      values = Factors.assignments(variables, @sizes).map do |assignment|
        candidates = Array.new(@sizes[variable]) { |state| value(assignment.merge(variable => state)) }
        maximize ? candidates.max : Learning.total(candidates)
      end
      Factor.new(variables, values, @sizes)
    end
  end

  def self.cpt_factor(variable, parents, cpt, sizes)
    variables = ([variable] + parents).sort
    values = assignments(variables, sizes).map do |assignment|
      cpt[Learning.parent_row(parents, assignment, sizes)][assignment[variable]]
    end
    Factor.new(variables, values, sizes)
  end

  def self.multiply(factors, sizes)
    return Factor.new([], [1.0], sizes) if factors.empty?

    factors.drop(1).inject(factors.first) { |product, factor| product.multiplied(factor) }
  end
end
