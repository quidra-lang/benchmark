require 'set'

class TypeVariable
  attr_accessor :binding
end
Type = Struct.new(:kind, :children) do
  def initialize(kind, *children) = super(kind, children)
end
Scheme = Struct.new(:value, :quantified) do
  def initialize(value, quantified = []) = super(value, quantified.to_set)
end
class UnificationFailure < StandardError
  attr_reader :expected, :found, :infinite, :nested
  def initialize(expected, found, infinite, nested)
    @expected, @found, @infinite, @nested = expected, found, infinite, nested
    super()
  end
end
module Unifier
  INT = Type.new('int')
  BOOL = Type.new('bool')
  STRING = Type.new('string')
  module_function
  def resolve(value)
    if value.is_a?(TypeVariable) && value.binding
      value.binding = resolve(value.binding)
    else
      value
    end
  end
  def occurs?(variable, value)
    value = resolve(value)
    value.is_a?(TypeVariable) ? variable.equal?(value) : value.children.any? { |child| occurs?(variable, child) }
  end
  def unify(expected, found, nested = false)
    expected, found = resolve(expected), resolve(found)
    return if expected.equal?(found)
    if expected.is_a?(TypeVariable)
      raise UnificationFailure.new(expected, found, true, nested) if occurs?(expected, found)
      expected.binding = found
    elsif found.is_a?(TypeVariable)
      raise UnificationFailure.new(expected, found, true, nested) if occurs?(found, expected)
      found.binding = expected
    elsif expected.kind != found.kind
      raise UnificationFailure.new(expected, found, false, nested)
    else
      expected.children.zip(found.children) { |left, right| unify(left, right, true) }
    end
  end
  def free_variables(value)
    value = resolve(value)
    return Set[value] if value.is_a?(TypeVariable)
    value.children.reduce(Set.new) { |set, child| set | free_variables(child) }
  end
  def generalize(value, environment)
    free = environment.values.reduce(Set.new) { |set, scheme| set | (free_variables(scheme.value) - scheme.quantified) }
    Scheme.new(value, free_variables(value) - free)
  end
  def instantiate(scheme)
    replacements = {}
    copy = lambda do |value|
      value = resolve(value)
      if value.is_a?(TypeVariable)
        scheme.quantified.include?(value) ? (replacements[value] ||= TypeVariable.new) : value
      else
        Type.new(value.kind, *value.children.map { |child| copy.call(child) })
      end
    end
    copy.call(scheme.value)
  end
end
