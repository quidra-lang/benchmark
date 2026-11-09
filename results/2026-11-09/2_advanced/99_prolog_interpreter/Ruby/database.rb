require_relative 'terms'

module Prolog
  Clause = Struct.new(:head, :body, :file, :line, keyword_init: true)
  class Database
    attr_reader :predicates
    def initialize = @predicates = {}
    def add(key, clause) = (predicates[key] ||= []) << clause
    def candidates(goal)
      key = Terms.indicator(goal)
      clauses = predicates.fetch(key)
      return clauses if key[1].zero?
      x = Terms.deref(goal.args[0])
      clauses.select do |clause|
        y = Terms.deref(clause.head.args[0])
        if x.is_a?(Variable) || y.is_a?(Variable)
          true
        elsif x.is_a?(Compound) && y.is_a?(Compound)
          x.name == y.name && x.args.length == y.args.length
        else
          x.class == y.class && x == y
        end
      end
    end
    def copy_clause(clause)
      map = {}
      [Terms.copy(clause.head, map), clause.body && Terms.copy(clause.body, map)]
    end
  end
end
