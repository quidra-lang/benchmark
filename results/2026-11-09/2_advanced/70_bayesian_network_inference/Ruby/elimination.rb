require 'set'
require_relative 'factors'

module Elimination
  Step = Data.define(:variable, :fill, :scope, :size)
  Plan = Data.define(:steps, :maximum, :total)

  def self.interaction_graph(factors)
    graph = {}
    factors.each do |factor|
      factor.variables.each { |variable| graph[variable] ||= Set.new }
      factor.variables.combination(2) do |left, right|
        graph[left].add(right)
        graph[right].add(left)
      end
    end
    graph
  end

  def self.make_plan(factors, eliminate, method, given_order, sizes)
    graph = interaction_graph(factors)
    remaining, steps = eliminate.dup, []
    ranks = given_order.each_with_index.to_h
    until remaining.empty?
      fills = remaining.to_h do |variable|
        [variable, graph[variable].to_a.sort.combination(2).count { |left, right| !graph[left].include?(right) }]
      end
      variable = remaining.min_by do |item|
        method == 'MINFILL' ? [fills[item], graph[item].length, item] : [ranks[item]]
      end
      neighbors = graph[variable].to_a.sort
      scope = (neighbors + [variable]).sort
      steps << Step.new(variable, fills[variable], scope, Factors.entry_count(scope, sizes))
      neighbors.combination(2) do |left, right|
        graph[left].add(right)
        graph[right].add(left)
      end
      neighbors.each { |neighbor| graph[neighbor].delete(variable) }
      graph.delete(variable)
      remaining.delete(variable)
    end
    Plan.new(steps, steps.map(&:size).max || 0, steps.inject(0) { |total, step| total + step.size })
  end

  def self.execute(initial, plan, sizes, maximize = false)
    factors, products = initial.dup, []
    plan.steps.each do |step|
      selected, factors = factors.partition { |factor| factor.variables.include?(step.variable) }
      product = Factors.multiply(selected, sizes)
      factors << product.eliminate(step.variable, maximize)
      products << [step.variable, product] if maximize
    end
    [Factors.multiply(factors, sizes), products]
  end

  def self.traceback(products, sizes)
    assignment = {}
    products.reverse_each do |variable, product|
      assignment[variable] = (0...sizes[variable]).max_by do |state|
        product.value(assignment.merge(variable => state))
      end
    end
    assignment
  end
end
