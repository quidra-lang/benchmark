require_relative 'unifier'

class InferenceError < StandardError
  attr_reader :kind, :position, :details
  def initialize(kind, position, **details)
    @kind, @position, @details = kind, position, details
    super()
  end
end
class Inferencer
  include Unifier
  attr_reader :local_bindings
  def initialize = @local_bindings = []
  def check(expected, found, position)
    unify(expected, found)
  rescue UnificationFailure => failure
    raise InferenceError.new('check', position, expected: expected, found: found, failure: failure)
  end
  def operator_types(operator)
    return [INT, INT, INT] if %w[+ - * / mod].include?(operator)
    return [STRING, STRING, STRING] if operator == '^'
    return [BOOL, BOOL, BOOL] if %w[&& ||].include?(operator)
    variable = TypeVariable.new
    return [variable, Type.new('list', variable), Type.new('list', variable)] if operator == '::'
    [variable, variable, BOOL]
  end
  def expression(node, environment)
    children = node.children
    result = case node.kind
             when 'integer' then INT
             when 'boolean' then BOOL
             when 'string' then STRING
             when 'name'
               unless environment.key?(node.value)
                 raise InferenceError.new('unbound', node.position, name: node.value, candidates: environment.keys)
               end
               instantiate(environment[node.value])
             when 'fun'
               argument = TypeVariable.new
               inner = environment.dup
               inner[node.value.spelling] = Scheme.new(argument) unless node.value.spelling == '_'
               Type.new('function', argument, expression(children[0], inner))
             when 'apply'
               function = resolve(expression(children[0], environment))
               if function.is_a?(TypeVariable)
                 argument, value = TypeVariable.new, TypeVariable.new
                 function.binding = Type.new('function', argument, value)
               elsif function.kind == 'function'
                 argument, value = function.children
               else
                 raise InferenceError.new('not_function', children[0].position, found: function)
               end
               check(argument, expression(children[1], environment), children[1].position)
               value
             when 'binary'
               first, second, value = operator_types(node.value.spelling)
               check(first, expression(children[0], environment), children[0].position)
               check(second, expression(children[1], environment), children[1].position)
               value
             when 'negate'
               check(INT, expression(children[0], environment), children[0].position)
               INT
             when 'if'
               check(BOOL, expression(children[0], environment), children[0].position)
               value = expression(children[1], environment)
               check(value, expression(children[2], environment), children[2].position)
               value
             when 'pair'
               Type.new('pair', *children.map { |child| expression(child, environment) })
             when 'list'
               element = TypeVariable.new
               children.each { |child| check(element, expression(child, environment), child.position) }
               Type.new('list', element)
             when 'match'
               matched = expression(children[0], environment)
               value = TypeVariable.new
               node.value.each do |pattern, arm|
                 bindings = {}
                 check(matched, pattern(pattern, bindings), pattern.position)
                 inner = environment.merge(bindings.transform_values { |type| Scheme.new(type) })
                 check(value, expression(arm, inner), arm.position)
               end
               value
             when 'let'
               expression(children[0], group(node.value, environment, local: true))
             end
    node.inferred = result
  end
  def pattern(node, bindings)
    case node.kind
    when 'wildcard' then TypeVariable.new
    when 'name'
      raise InferenceError.new('duplicate_pattern', node.position, name: node.value) if bindings.key?(node.value)
      bindings[node.value] = TypeVariable.new
    when 'integer' then INT
    when 'boolean' then BOOL
    when 'string' then STRING
    when 'pair' then Type.new('pair', *node.children.map { |child| pattern(child, bindings) })
    else
      element = TypeVariable.new
      sequence = Type.new('list', element)
      if node.kind == 'cons'
        check(element, pattern(node.children[0], bindings), node.children[0].position)
        check(sequence, pattern(node.children[1], bindings), node.children[1].position)
      else
        node.children.each { |child| check(element, pattern(child, bindings), child.position) }
      end
      sequence
    end
  end
  def group(group, environment, local: false)
    names = Set.new
    group.bindings.each do |binding|
      raise InferenceError.new('duplicate_let', binding.position, name: binding.name) if names.include?(binding.name)
      names << binding.name
      if group.rec_position && binding.expression.kind != 'fun'
        raise InferenceError.new('recursive_function', binding.position, name: binding.name)
      end
    end
    if group.rec_position
      inferred = group.bindings.map { TypeVariable.new }
      recursive = environment.dup
      group.bindings.zip(inferred) { |binding, type| recursive[binding.name] = Scheme.new(type) }
      group.bindings.zip(inferred) do |binding, expected|
        check(expected, expression(binding.expression, recursive), binding.position)
      end
    else
      inferred = group.bindings.map { |binding| expression(binding.expression, environment) }
    end
    result = environment.dup
    group.bindings.zip(inferred) do |binding, type|
      binding.scheme = generalize(type, environment)
      result[binding.name] = binding.scheme
    end
    @local_bindings.concat(group.bindings) if local
    result
  end
end
