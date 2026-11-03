class CommandError < StandardError
  def initialize(message) = super("ERROR #{message}")
end

Fraction = Data.define(:n, :d) do
  include(Comparable)

  def self.make(n, d = 1)
    n, d = -n, -d if d.negative?
    divisor = n.gcd(d)
    new(n / divisor, d / divisor)
  end

  def +(b) = Fraction.make(n * b.d + b.n * d, d * b.d)
  def -(b) = Fraction.make(n * b.d - b.n * d, d * b.d)
  def *(b) = Fraction.make(n * b.n, d * b.d)
  def /(b) = Fraction.make(n * b.d, d * b.n)
  def -@ = Fraction.new(-n, d)
  def abs = Fraction.new(n.abs, d)
  def <=>(b) = (n * b.d) <=> (b.n * d)
  def power(exponent)
    factor = exponent.negative? ? Fraction.make(d, n) : self
    result = Fraction::ONE
    exponent.abs.times { result *= factor }
    result
  end

  def to_s = d == 1 ? n.to_s : "#{n}/#{d}"
  def decimal
    magnitude = n.abs
    format("%s%d.%06d", n.negative? ? "-" : "", magnitude / d, magnitude % d * 1_000_000 / d)
  end

  def notation(unit) = "#{self} #{unit} (#{decimal})"
end

Fraction::ONE = Fraction.make(1)
def whole(n) = Fraction.make(n)

Dimension = Data.define(:kg, :m, :s, :a, :k, :mol, :cd) do
  def self.make(kg: 0, m: 0, s: 0, a: 0, k: 0, mol: 0, cd: 0) = new(kg, m, s, a, k, mol, cd)
  def exponents = [kg, m, s, a, k, mol, cd]
  def +(b) = Dimension.new(*exponents.zip(b.exponents).map { |x, y| x + y })
  def -(b) = Dimension.new(*exponents.zip(b.exponents).map { |x, y| x - y })
  def scale(factor) = Dimension.new(*exponents.map { |value| value * factor })
  def half = Dimension.new(*exponents.map { |value| value / 2 })
  def even? = exponents.all?(&:even?)
  def match(other)
    raise CommandError, "DIMENSION MISMATCH #{self} vs #{other}" if self != other
  end

  def to_s
    symbols = %w[kg m s A K mol cd]
    terms = exponents.each_with_index.filter_map do |value, i|
      next if value.zero?
      value == 1 ? symbols[i] : "#{symbols[i]}^#{value}"
    end

    terms.empty? ? "1" : terms.join(" ")
  end
end

Dimension::ZERO = Dimension.make
Quantity = Data.define(:value, :dim)

KINDS = {
  "dimensionless" => Dimension::ZERO,
  "length" => Dimension.make(m: 1),
  "mass" => Dimension.make(kg: 1),
  "time" => Dimension.make(s: 1),
  "current" => Dimension.make(a: 1),
  "temperature" => Dimension.make(k: 1),
  "amount" => Dimension.make(mol: 1),
  "luminous_intensity" => Dimension.make(cd: 1),
  "area" => Dimension.make(m: 2),
  "volume" => Dimension.make(m: 3),
  "speed" => Dimension.make(m: 1, s: -1),
  "acceleration" => Dimension.make(m: 1, s: -2),
  "density" => Dimension.make(kg: 1, m: -3),
  "momentum" => Dimension.make(kg: 1, m: 1, s: -1),
  "force" => Dimension.make(kg: 1, m: 1, s: -2),
  "energy" => Dimension.make(kg: 1, m: 2, s: -2),
  "power" => Dimension.make(kg: 1, m: 2, s: -3),
  "pressure" => Dimension.make(kg: 1, m: -1, s: -2),
  "frequency" => Dimension.make(s: -1),
  "charge" => Dimension.make(s: 1, a: 1),
  "voltage" => Dimension.make(kg: 1, m: 2, s: -3, a: -1),
  "resistance" => Dimension.make(kg: 1, m: 2, s: -3, a: -2),
  "conductance" => Dimension.make(kg: -1, m: -2, s: 3, a: 2),
  "capacitance" => Dimension.make(kg: -1, m: -2, s: 4, a: 2),
  "magnetic_flux" => Dimension.make(kg: 1, m: 2, s: -2, a: -1),
  "flux_density" => Dimension.make(kg: 1, s: -2, a: -1),
  "inductance" => Dimension.make(kg: 1, m: 2, s: -2, a: -2),
  "illuminance" => Dimension.make(m: -2, cd: 1),
  "catalytic_activity" => Dimension.make(s: -1, mol: 1)
}.freeze

def kind_name(dim) = KINDS.key(dim) || "-"
def letter?(c) = c && (c.between?(65, 90) || c.between?(97, 122))
def digit?(c) = c && c.between?(48, 57)
def digits?(text) = /\A[0-9]+\z/.match?(text)

def number(text)
  body = text.delete_prefix("-")
  value = if digits?(body)
    whole(Integer(body, 10))
  elsif body.include?(".")
    first, second = body.split(".", 2)
    raise CommandError, "BAD NUMBER #{text}" unless digits?(first) && digits?(second)
    scale = 1
    second.length.times { scale *= 10 }
    Fraction.make(Integer(first, 10) * scale + Integer(second, 10), scale)
  elsif body.include?("/")
    first, second = body.split("/", 2)
    unless digits?(first) && digits?(second) && !Integer(second, 10).zero?
      raise CommandError, "BAD NUMBER #{text}"
    end

    Fraction.make(Integer(first, 10), Integer(second, 10))
  else
    raise CommandError, "BAD NUMBER #{text}"
  end

  text.start_with?("-") ? -value : value
end

def exponent(text)
  value = Integer(text, 10)
  raise CommandError, "BAD EXPONENT #{text}" if value.zero? || !value.between?(-3, 3)
  value
end

def check_name(name, variable)
  unless /\A[A-Za-z]{1,12}\z/.match?(name) && !(variable && %w[abs sqrt min max].include?(name))
    raise CommandError, "BAD NAME #{name}"
  end
end

Token = Data.define(:kind, :text, :position)
UnitName = Data.define(:name)
UnitNumber = Data.define(:text)
UnitPower = Data.define(:child, :exponent)
UnitTerm = Data.define(:op, :node)
UnitProduct = Data.define(:terms)
Literal = Data.define(:number, :unit)
Variable = Data.define(:name)
Power = Data.define(:child, :exponent)
Negative = Data.define(:child)
Binary = Data.define(:op, :left, :right)
Call = Data.define(:name, :args)

class Parser
  def initialize(source, quantity)
    @source, @tokens, @position = source, [], 0
    i = 0
    while i < source.length
      start, c = i, source.getbyte(i)
      kind = if letter?(c)
        i += 1 while letter?(source.getbyte(i))
        :identifier
      elsif digit?(c)
        i += 1 while digit?(source.getbyte(i))
        if quantity && source.getbyte(i) == 46 && digit?(source.getbyte(i + 1))
          i += 1
          i += 1 while digit?(source.getbyte(i))
        end

        :number
      elsif quantity && c == 91 && (finish = source.index("]", i + 1)) && finish > i + 1
        i = finish + 1
        :unit
      else
        i += 1
        (quantity ? "+-*/^()," : "*/^()-").include?(c.chr) ? :symbol : :invalid
      end

      @tokens << Token.new(kind, source[start...i], start)
    end

    @tokens << Token.new(:end, "", source.length)
  end

  def current = @tokens[@position]
  def advance
    token = current
    @position += 1
    token
  end

  def take(text)
    return false unless current.text == text
    @position += 1
    true
  end

  def syntax
    raise CommandError, "SYNTAX #{@source} AT #{current.kind == :end ? "END" : current.position + 1}"
  end

  def expect(text)
    syntax unless take(text)
  end

  def read_exponent
    start = current.position
    take("-")
    syntax unless current.kind == :number && !current.text.include?(".")
    token = advance
    @source[start...(token.position + token.text.length)]
  end

  def unit_term
    atom = if current.kind == :identifier
      UnitName.new(advance.text)
    elsif current.kind == :number && current.text[0] != "0"
      UnitNumber.new(advance.text)
    elsif take("(")
      unit_expression.tap { expect(")") }
    else
      syntax
    end

    take("^") ? UnitPower.new(atom, read_exponent) : atom
  end

  def unit_expression
    terms = [UnitTerm.new("*", unit_term)]
    while %w[* /].include?(current.text)
      op = advance.text
      terms << UnitTerm.new(op, unit_term)
    end

    UnitProduct.new(terms.freeze)
  end

  def complete_unit
    result = unit_expression
    syntax unless current.kind == :end
    result
  end

  def unit_string = advance.text[1...-1]
  def primary
    result = if current.kind == :number
      text = advance.text
      Literal.new(text, current.kind == :unit ? unit_string : nil)
    elsif current.kind == :unit
      Literal.new("1", unit_string)
    elsif current.kind == :identifier
      name = advance.text
      if take("(")
        args = [expression]
        args << expression while take(",")
        expect(")")
        Call.new(name, args.freeze)
      else
        Variable.new(name)
      end
    elsif take("(")
      expression.tap { expect(")") }
    else
      syntax
    end

    take("^") ? Power.new(result, read_exponent) : result
  end

  def unary = take("-") ? Negative.new(unary) : primary
  def product
    result = unary
    while %w[* /].include?(current.text)
      op = advance.text
      result = Binary.new(op, result, unary)
    end

    result
  end

  def expression
    result = product
    while %w[+ -].include?(current.text)
      op = advance.text
      result = Binary.new(op, result, product)
    end

    result
  end

  def complete
    result = expression
    syntax unless current.kind == :end
    result
  end
end

Reduced = Data.define(:coefficient, :names)
def reduce(node)
  case node
  when UnitName
    Reduced.new(Fraction::ONE, {node.name => 1})
  when UnitNumber
    Reduced.new(whole(Integer(node.text, 10)), {})
  when UnitPower
    inner = reduce(node.child)
    k = Integer(node.exponent, 10)
    Reduced.new(inner.coefficient.power(k), inner.names.transform_values { |count| count * k })
  when UnitProduct
    coefficient, names = Fraction::ONE, {}
    node.terms.each do |term|
      right = reduce(term.node)
      coefficient = term.op == "*" ? coefficient * right.coefficient : coefficient / right.coefficient
      right.names.each { |name, count| names[name] = names.fetch(name, 0) + (term.op == "*" ? count : -count) }
    end

    Reduced.new(coefficient, names)
  end
end

def reduced_text(tree)
  result = reduce(tree)
  parts = []
  parts << result.coefficient.to_s if result.coefficient != Fraction::ONE
  result.names.each do |name, count|
    parts << (count == 1 ? name : "#{name}^#{count}") unless count.zero?
  end

  parts.empty? ? "1" : parts.join(" ")
end

Definition = Data.define(:value, :expression)
Unit = Data.define(:symbol, :quantity, :prefix, :definition)
ParsedUnit = Data.define(:tree, :quantity)

class Database
  PREFIXES = [
    ["G", whole(1_000_000_000)],
    ["M", whole(1_000_000)],
    ["k", whole(1000)],
    ["h", whole(100)],
    ["da", whole(10)],
    ["d", Fraction.make(1, 10)],
    ["c", Fraction.make(1, 100)],
    ["m", Fraction.make(1, 1000)],
    ["u", Fraction.make(1, 1_000_000)],
    ["n", Fraction.make(1, 1_000_000_000)]
  ].map(&:freeze).freeze

  def initialize
    @units, @variables = [], {}
    add("m", 1, 1, "length", true)
    add("g", 1, 1000, "mass", true)
    add("s", 1, 1, "time", true)
    add("A", 1, 1, "current", true)
    add("K", 1, 1, "temperature", true)
    add("mol", 1, 1, "amount", true)
    add("cd", 1, 1, "luminous_intensity", true)
    add("N", 1, 1, "force", true)
    add("J", 1, 1, "energy", true)
    add("W", 1, 1, "power", true)
    add("Pa", 1, 1, "pressure", true)
    add("Hz", 1, 1, "frequency", true)
    add("C", 1, 1, "charge", true)
    add("V", 1, 1, "voltage", true)
    add("ohm", 1, 1, "resistance", true)
    add("S", 1, 1, "conductance", true)
    add("F", 1, 1, "capacitance", true)
    add("Wb", 1, 1, "magnetic_flux", true)
    add("T", 1, 1, "flux_density", true)
    add("H", 1, 1, "inductance", true)
    add("lx", 1, 1, "illuminance", true)
    add("kat", 1, 1, "catalytic_activity", true)
    add("L", 1, 1000, "volume", true)
    add("t", 1000, 1, "mass", false)
    add("min", 60, 1, "time", false)
    add("h", 3600, 1, "time", false)
    add("day", 86400, 1, "time", false)
    add("in", 127, 5000, "length", false)
    add("ft", 381, 1250, "length", false)
    add("yd", 1143, 1250, "length", false)
    add("mi", 201168, 125, "length", false)
    add("nmi", 1852, 1, "length", false)
    add("ha", 10000, 1, "area", false)
    add("kn", 463, 900, "speed", false)
    add("bar", 100000, 1, "pressure", true)
    add("atm", 101325, 1, "pressure", false)
    add("Torr", 20265, 152, "pressure", false)
    add("cal", 523, 125, "energy", true)
    add("Wh", 3600, 1, "energy", true)
    add("Ah", 3600, 1, "charge", true)
    add("dC", 1, 1, "temperature", false)
    add("dF", 5, 9, "temperature", false)
  end

  def add(symbol, n, d, kind, prefix)
    @units << Unit.new(symbol.freeze, Quantity.new(Fraction.make(n, d), KINDS.fetch(kind)), prefix, nil)
  end

  def resolve(name)
    exact = @units.find { |entry| entry.symbol == name }
    return exact.quantity if exact
    PREFIXES.each do |prefix, factor|
      next unless name.start_with?(prefix)
      suffix = name[prefix.length..]
      entry = @units.take(42).find { |candidate| candidate.prefix && candidate.symbol == suffix }
      return Quantity.new(factor * entry.quantity.value, entry.quantity.dim) if entry
    end

    nil
  end

  def validate_unit(node)
    case node
    when UnitName
      raise CommandError, "UNKNOWN UNIT #{node.name}" unless resolve(node.name)
    when UnitPower
      validate_unit(node.child)
      exponent(node.exponent)
    when UnitProduct
      node.terms.each { |term| validate_unit(term.node) }
    end
  end

  def unit_value(node)
    case node
    when UnitName
      resolve(node.name)
    when UnitNumber
      Quantity.new(whole(Integer(node.text, 10)), Dimension::ZERO)
    when UnitPower
      value = unit_value(node.child)
      k = Integer(node.exponent, 10)
      Quantity.new(value.value.power(k), value.dim.scale(k))
    when UnitProduct
      result = Quantity.new(Fraction::ONE, Dimension::ZERO)
      node.terms.each do |term|
        right = unit_value(term.node)
        result = if term.op == "*"
          Quantity.new(result.value * right.value, result.dim + right.dim)
        else
          Quantity.new(result.value / right.value, result.dim - right.dim)
        end
      end

      result
    end
  end

  def parse_unit(text)
    tree = Parser.new(text, false).complete_unit
    validate_unit(tree)
    ParsedUnit.new(tree, unit_value(tree))
  end

  def unit(text) = parse_unit(text).quantity
  def quantity(text) = evaluate(Parser.new(text, true).complete)
  def evaluate(expression)
    case expression
    when Literal
      return Quantity.new(number(expression.number), Dimension::ZERO) unless expression.unit
      from = unit(expression.unit)
      Quantity.new(number(expression.number) * from.value, from.dim)
    when Variable
      @variables.fetch(expression.name) { raise CommandError, "UNKNOWN VARIABLE #{expression.name}" }
    when Negative
      value = evaluate(expression.child)
      Quantity.new(-value.value, value.dim)
    when Power
      value = evaluate(expression.child)
      k = exponent(expression.exponent)
      raise CommandError, "DIVISION BY ZERO" if value.value.n.zero? && k.negative?
      Quantity.new(value.value.power(k), value.dim.scale(k))
    when Binary
      a = evaluate(expression.left)
      b = evaluate(expression.right)
      case expression.op
      when "+", "-"
        a.dim.match(b.dim)
        Quantity.new(expression.op == "+" ? a.value + b.value : a.value - b.value, a.dim)
      when "*"
        Quantity.new(a.value * b.value, a.dim + b.dim)
      else
        raise CommandError, "DIVISION BY ZERO" if b.value.n.zero?
        Quantity.new(a.value / b.value, a.dim - b.dim)
      end

    when Call
      arity = case expression.name
      when "abs", "sqrt"
        1
      when "min", "max"
        2
      else
        raise CommandError, "UNKNOWN FUNCTION #{expression.name}"
      end

      raise CommandError, "BAD ARGUMENTS #{expression.name}" unless expression.args.length == arity
      a = evaluate(expression.args[0])
      case expression.name
      when "abs"
        Quantity.new(a.value.abs, a.dim)
      when "sqrt"
        raise CommandError, "NEGATIVE ROOT" if a.value.n.negative?
        raise CommandError, "ODD DIMENSION #{a.dim}" unless a.dim.even?
        n, d = Integer.sqrt(a.value.n), Integer.sqrt(a.value.d)
        raise CommandError, "NOT EXACT" if n * n != a.value.n || d * d != a.value.d
        Quantity.new(Fraction.make(n, d), a.dim.half)
      else
        b = evaluate(expression.args[1])
        a.dim.match(b.dim)
        if expression.name == "min"
          a.value <= b.value ? a : b
        else
          a.value >= b.value ? a : b
        end
      end
    end
  end

  def simplified(dim)
    @units.find { |entry| entry.quantity.value == Fraction::ONE && entry.quantity.dim == dim }&.symbol || dim.to_s
  end

  def notation(value) = value.value.notation(simplified(value.dim))
  def selected(dim) = @units.select { |entry| entry.quantity.dim == dim }.sort_by { |entry|
    [entry.quantity.value, entry.symbol]
  }

  def command(line)
    w = line.split(" ")
    case w[0]
    when "DEFINE"
      check_name(w[1], false)
      value = number(w[3])
      from = unit(w[4])
      raise CommandError, "NAME TAKEN #{w[1]}" if KINDS.key?(w[1]) || resolve(w[1])
      raise CommandError, "NOT POSITIVE #{w[3]}" unless value.n.positive?
      factor = value * from.value
      @units << Unit.new(w[1].freeze, Quantity.new(factor, from.dim), false, Definition.new(value, w[4].freeze))
      ["DEFINE #{w[1]} factor=#{factor} dim=#{from.dim} kind=#{kind_name(from.dim)}"]
    when "UNDEF"
      index = @units.index { |entry| entry.symbol == w[1] }
      raise CommandError, "NOT DEFINED #{w[1]}" unless index
      raise CommandError, "BUILTIN UNIT #{w[1]}" if index < 42
      @units.delete_at(index)
      ["UNDEF #{w[1]}"]
    when "DEFS"
      rows = @units.drop(42).map do |entry|
        "DEF #{entry.symbol} = #{entry.definition.value} #{entry.definition.expression} factor=#{entry.quantity.value} dim=#{entry.quantity.dim}"
      end

      ["DEFS count=#{@units.length - 42}"] + rows
    when "CONVERT", "INVERT"
      value = number(w[1])
      from = unit(w[2])
      to = unit(w[4])
      inverse = w[0] == "INVERT"
      if inverse
        if from.dim == Dimension::ZERO || from.dim + to.dim != Dimension::ZERO
          raise CommandError, "NOT RECIPROCAL #{from.dim} vs #{to.dim}"
        end

        raise CommandError, "DIVISION BY ZERO" if value.n.zero?
      else
        from.dim.match(to.dim)
      end

      result = value * from.value
      result = Fraction::ONE / result if inverse
      result /= to.value
      ["#{w[0]} #{value} #{w[2]} = #{result.notation(w[4])}"]
    when "DIM", "REDUCE", "SIMPLIFY"
      parsed = parse_unit(w[1])
      from = parsed.quantity
      result = case w[0]
      when "DIM"
        "#{from.dim} factor=#{from.value} kind=#{kind_name(from.dim)}"
      when "REDUCE"
        reduced_text(parsed.tree)
      else
        notation(from)
      end

      ["#{w[0]} #{w[1]} = #{result}"]
    when "ADD", "SUB", "MUL", "DIV", "COMPARE"
      a = number(w[1])
      first = unit(w[2])
      b = number(w[3])
      second = unit(w[4])
      target = w.length == 7
      destination = target ? unit(w[6]) : first
      if %w[ADD SUB COMPARE].include?(w[0])
        first.dim.match(second.dim)
        first.dim.match(destination.dim) if target
        left = a * first.value
        right = b * second.value
        if w[0] == "COMPARE"
          relation = ["<", "=", ">"][(left <=> right) + 1]
          ratio = right.n.zero? ? "undefined" : (left / right).to_s
          ["COMPARE #{a} #{w[2]} #{relation} #{b} #{w[4]} ratio=#{ratio}"]
        else
          add = w[0] == "ADD"
          result = (add ? left + right : left - right) / destination.value
          ["#{w[0]} #{a} #{w[2]} #{add ? "+" : "-"} #{b} #{w[4]} = #{result.notation(target ? w[6] : w[2])}"]
        end
      else
        multiply = w[0] == "MUL"
        dim = multiply ? first.dim + second.dim : first.dim - second.dim
        raise CommandError, "DIVISION BY ZERO" if !multiply && b.n.zero?
        dim.match(destination.dim) if target
        raw = multiply ? a * b : a / b
        left = a * first.value
        right = b * second.value
        coherent = multiply ? left * right : left / right
        op = multiply ? "*" : "/"
        prefix = "#{w[0]} #{a} #{w[2]} #{op} #{b} #{w[4]} = "
        if target
          [prefix + (coherent / destination.value).notation(w[6])]
        else
          right_unit = !multiply && (w[4].include?("*") || w[4].include?("/")) ? "(#{w[4]})" : w[4]
          ["#{prefix}#{raw} #{w[2]}#{op}#{right_unit} = #{coherent.notation(simplified(dim))}"]
        end
      end

    when "TEMP"
      value = number(w[1])
      [w[2], w[4]].each do |scale|
        raise CommandError, "UNKNOWN SCALE #{scale}" unless %w[C F K R].include?(scale)
      end

      kelvin = case w[2]
      when "C"
        value + Fraction.make(5463, 20)
      when "F"
        (value + Fraction.make(45967, 100)) * whole(5) / whole(9)
      when "R"
        value * whole(5) / whole(9)
      else
        value
      end

      raise CommandError, "BELOW ABSOLUTE ZERO" if kelvin.n.negative?
      result = case w[4]
      when "C"
        kelvin - Fraction.make(5463, 20)
      when "F"
        kelvin * whole(9) / whole(5) - Fraction.make(45967, 100)
      when "R"
        kelvin * whole(9) / whole(5)
      else
        kelvin
      end

      ["TEMP #{value} #{w[2]} = #{result.notation(w[4])}"]
    when "LIST"
      dim = KINDS[w[1]] || unit(w[1]).dim
      matching = selected(dim)
      rows = matching.map do |entry|
        "UNIT #{entry.symbol} factor=#{entry.quantity.value} origin=#{entry.definition ? "user" : "builtin"} prefix=#{entry.prefix ? "yes" : "no"}"
      end

      ["LIST #{w[1]} dim=#{dim} kind=#{kind_name(dim)} count=#{matching.length}"] + rows
    when "TABLE"
      value = number(w[1])
      from = unit(w[2])
      matching = selected(from.dim)
      rows = matching.map do |entry|
        "ROW #{(value * from.value / entry.quantity.value).notation(entry.symbol)}"
      end

      ["TABLE #{value} #{w[2]} dim=#{from.dim} count=#{matching.length}"] + rows
    when "AUTO"
      value = number(w[1])
      from = unit(w[2])
      reference = @units.take(42).find { |entry| entry.prefix && entry.quantity.dim == from.dim }
      raise CommandError, "NO PREFIXABLE UNIT #{from.dim}" unless reference
      scaled = value * from.value / reference.quantity.value
      magnitude, k = scaled.abs, 0
      unless magnitude.n.zero?
        if magnitude >= Fraction::ONE
          k += 3 while k < 9 && magnitude >= whole(10).power(k + 3)
        else
          k -= 3 while k > -9 && magnitude < whole(10).power(k)
        end
      end

      prefix = ["n", "u", "m", "", "k", "M", "G"][(k + 9) / 3]
      ["AUTO #{value} #{w[2]} = #{(scaled / whole(10).power(k)).notation(prefix + reference.symbol)}"]
    when "SPLIT"
      value = number(w[1])
      from = unit(w[2])
      parts = w[4].split(",")
      destinations = parts.map { |part| unit(part) }
      raise CommandError, "NEGATIVE VALUE" if value.n.negative?
      destinations.each { |entry| from.dim.match(entry.dim) }
      raise CommandError, "UNIT ORDER" if destinations.each_cons(2).any? { |a, b| a.value <= b.value }
      remaining = value * from.value
      pieces = []
      (parts.length - 1).times do |i|
        quotient = remaining / destinations[i].value
        count = quotient.n / quotient.d
        remaining -= whole(count) * destinations[i].value
        pieces << "#{count} #{parts[i]}"
      end

      pieces << (remaining / destinations.last.value).notation(parts.last)
      ["SPLIT #{value} #{w[2]} = #{pieces.join(" ")}"]
    when "LET"
      check_name(w[1], true)
      value = quantity(w[3])
      @variables[w[1]] = value
      ["LET #{w[1]} = #{notation(value)}"]
    when "EVAL"
      value = quantity(w[1])
      result = if w.length == 4
        destination = unit(w[3])
        value.dim.match(destination.dim)
        (value.value / destination.value).notation(w[3])
      else
        notation(value)
      end

      ["EVAL #{w[1]} = #{result}"]
    when "VARS"
      ["VARS count=#{@variables.length}"] +
        @variables.keys.sort.map { |name| "VAR #{name} = #{notation(@variables.fetch(name))}" }
    else
      raise CommandError, "UNKNOWN COMMAND #{w[0]}"
    end
  end
end

database = Database.new
Integer($stdin.gets, 10).times do
  line = $stdin.gets(chomp: true)
  begin
    puts(database.command(line))
  rescue CommandError => error
    puts(error.message)
  end
end
