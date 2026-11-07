require_relative 'terms'

module Prolog
  class Unifier
    attr_reader :trail
    def initialize = @trail = []
    def undo(height)
      trail.pop.binding = nil while trail.length > height
    end
    def unify(a, b)
      pending = [[a, b]]
      until pending.empty?
        x, y = pending.pop.map { |t| Terms.deref(t) }
        next if x.equal?(y)
        if x.is_a?(Variable)
          x.binding = y
          trail << x
        elsif y.is_a?(Variable)
          y.binding = x
          trail << y
        elsif x.is_a?(Compound) && y.is_a?(Compound) && x.name == y.name && x.args.length == y.args.length
          (x.args.length - 1).downto(0) { |i| pending << [x.args[i], y.args[i]] }
        elsif x.class != y.class || x != y
          return false
        end
      end
      true
    end
    def identical?(a, b)
      pending = [[a, b]]
      until pending.empty?
        x, y = pending.pop.map { |t| Terms.deref(t) }
        next if x.equal?(y)
        return false if x.is_a?(Variable) || y.is_a?(Variable)
        if x.is_a?(Compound) && y.is_a?(Compound) && x.name == y.name && x.args.length == y.args.length
          (x.args.length - 1).downto(0) { |i| pending << [x.args[i], y.args[i]] }
        elsif x.class != y.class || x != y
          return false
        end
      end
      true
    end
  end
end
