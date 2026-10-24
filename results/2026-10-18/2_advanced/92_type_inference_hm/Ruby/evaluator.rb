Closure = Struct.new(:parameter, :body, :environment)
Builtin = Struct.new(:behavior)
PairValue = Struct.new(:first, :second) do
  def to_a = [first, second]
end
class RuntimeFailure < StandardError
  attr_reader :position
  def initialize(position, message)
    @position = position
    super(message)
  end
end
class Evaluator
  attr_reader :calls
  def initialize = @calls = 0
  def checked_integer(value, position)
    raise RuntimeFailure.new(position, 'integer overflow') unless (-2_147_483_648..2_147_483_647).cover?(value)
    value
  end
  def compare(first, second, position)
    raise RuntimeFailure.new(position, 'functional value compared') if first.is_a?(Closure) || first.is_a?(Builtin)
    if first.is_a?(Array) || first.is_a?(PairValue)
      left, right = first.to_a, second.to_a
      [left.length, right.length].min.times do |index|
        order = compare(left[index], right[index], position)
        return order unless order.zero?
      end
      left.length <=> right.length
    elsif first == true || first == false
      (first ? 1 : 0) <=> (second ? 1 : 0)
    else
      first <=> second
    end
  end
  def binary(operator, first, second, position)
    case operator
    when '+' then checked_integer(first + second, position)
    when '-' then checked_integer(first - second, position)
    when '*' then checked_integer(first * second, position)
    when '/', 'mod'
      raise RuntimeFailure.new(position, 'division by zero') if second.zero?
      quotient = first.abs / second.abs
      quotient = -quotient if first.negative? != second.negative?
      operator == '/' ? checked_integer(quotient, position) : first - second * quotient
    when '^' then first + second
    when '::' then [first] + second
    else
      order = compare(first, second, position)
      case operator
      when '=' then order.zero?
      when '<>' then !order.zero?
      when '<' then order.negative?
      when '>' then order.positive?
      when '<=' then order <= 0
      when '>=' then order >= 0
      end
    end
  end
  def match_pattern(pattern, value, bindings)
    case pattern.kind
    when 'wildcard' then true
    when 'name'
      bindings[pattern.value] = value
      true
    when 'integer', 'boolean', 'string' then pattern.value == value
    when 'cons'
      !value.empty? && match_pattern(pattern.children[0], value[0], bindings) &&
        match_pattern(pattern.children[1], value.drop(1), bindings)
    else
      values = value.to_a
      return false unless values.length == pattern.children.length
      pattern.children.zip(values).all? { |child, item| match_pattern(child, item, bindings) }
    end
  end
  def expression(node, environment)
    children = node.children
    case node.kind
    when 'integer', 'boolean', 'string' then node.value
    when 'name' then environment.fetch(node.value)
    when 'fun' then Closure.new(node.value.spelling, children[0], environment.dup)
    when 'apply'
      function = expression(children[0], environment)
      argument = expression(children[1], environment)
      @calls += 1
      return function.behavior.call(argument, node.position) if function.is_a?(Builtin)
      inner = function.environment.dup
      inner[function.parameter] = argument unless function.parameter == '_'
      expression(function.body, inner)
    when 'binary'
      first = expression(children[0], environment)
      operator = node.value.spelling
      return first && expression(children[1], environment) if operator == '&&'
      return first || expression(children[1], environment) if operator == '||'
      binary(operator, first, expression(children[1], environment), node.value.position)
    when 'negate' then checked_integer(-expression(children[0], environment), node.value.position)
    when 'if' then expression(children[expression(children[0], environment) ? 1 : 2], environment)
    when 'pair' then PairValue.new(*children.map { |child| expression(child, environment) })
    when 'list' then children.map { |child| expression(child, environment) }
    when 'let' then expression(children[0], group(node.value, environment))
    when 'match'
      value = expression(children[0], environment)
      node.value.each do |pattern, arm|
        bindings = {}
        return expression(arm, environment.merge(bindings)) if match_pattern(pattern, value, bindings)
      end
      raise RuntimeFailure.new(node.position, 'match failure')
    end
  end
  def group(group, environment)
    result = environment.dup
    if group.rec_position
      group.bindings.each do |binding|
        node = binding.expression
        result[binding.name] = Closure.new(node.value.spelling, node.children[0], result)
      end
    else
      values = group.bindings.map { |binding| expression(binding.expression, environment) }
      group.bindings.zip(values) { |binding, value| result[binding.name] = value }
    end
    result
  end
end
