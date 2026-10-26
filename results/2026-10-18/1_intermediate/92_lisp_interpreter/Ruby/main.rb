NIL = Object.new
VOID = Object.new
UNINIT = Object.new
Pair = Struct.new(:car, :cdr)

class Env
  attr_reader :frame, :parent
  def initialize(parent = nil)
    @parent, @frame = parent, {}
  end

  def find(name)
    e = self
    while e
      return e if e.frame.key?(name)
      e = e.parent
    end

    raise "unbound variable: #{name}"
  end

  def get(name)
    v = find(name).frame[name]
    raise "uninitialized variable: #{name}" if v.equal?(UNINIT)
    v
  end
end

class Procedure
  attr_accessor :name
  attr_reader :builtin
  def initialize(name, minimum, rest, params = [], body = [], env = nil, &builtin)
    @name, @minimum, @rest, @params, @body, @env, @builtin = name, minimum, rest, params, body, env, builtin
  end

  def call(args)
    if args.length < @minimum || (!@rest && args.length != @minimum)
      raise(
        "#{@name || "lambda"}: wrong number of arguments (expected #{@rest ? "at least " : ""}#{@minimum}, got #{args.length})"
      )
    end

    return @builtin.call(args) if @builtin
    scope = Env.new(@env)
    @params.zip(args).each { |name, value| scope.frame[name] = value }
    scope.frame[@rest] = make_list(args.drop(@minimum)) if @rest.is_a?(Symbol)
    evaluate_body(@body, scope)
  end
end

def make_list(a, tail = NIL)
  a.reverse_each { |x| tail = Pair.new(x, tail) }
  tail
end

def list_items(v)
  a = []
  while v.is_a?(Pair)
    a << v.car
    v = v.cdr
  end

  v.equal?(NIL) ? a : nil
end

def represent(v, quoted = true)
  return "()" if v.equal?(NIL)
  return "#<void>" if v.equal?(VOID)
  case v
  when true
    "#t"
  when false
    "#f"
  when Integer, Symbol
    v.to_s
  when String
    quoted ? "\"" + v.each_char.map { |c| {"\"" => "\\\"", "\\" => "\\\\", "\n" => "\\n"}.fetch(c, c) }.join + "\"" : v
  when Procedure
    v.name ? "#<procedure #{v.name}>" : "#<procedure>"
  when Pair
    a = []
    while v.is_a?(Pair)
      a << represent(v.car, quoted)
      v = v.cdr
    end

    a += [".", represent(v, quoted)] unless v.equal?(NIL)
    "(" + a.join(" ") + ")"
  end
end

def same(a, b, deep = false)
  return same(a.car, b.car, true) && same(a.cdr, b.cdr, true) if deep && a.is_a?(Pair) && b.is_a?(Pair)
  return a == b if a.class == b.class && [Integer, String, Symbol, TrueClass, FalseClass].include?(a.class)
  a.equal?(b)
end

def parameters(v)
  names = []
  while v.is_a?(Pair)
    return nil unless v.car.is_a?(Symbol)
    names << v.car
    v = v.cdr
  end

  return nil unless v.equal?(NIL) || v.is_a?(Symbol)
  rest = v.equal?(NIL) ? nil : v
  all = rest ? names + [rest] : names
  all.uniq.length == all.length ? [names, rest] : nil
end

def bindings(v, unique)
  a = list_items(v)
  return nil unless a
  a = a.map { |x| list_items(x) }
  return nil unless a.all? { |b| b && b.length == 2 && b[0].is_a?(Symbol) }
  return nil if unique && a.map(&:first).uniq.length != a.length
  a
end

def shape(ok, x)
  raise "bad syntax: #{represent(x)}" unless ok
end

def compound(p, body, env, name = nil)
  Procedure.new(name, p[0].length, p[1], p[0], body, env)
end

def evaluate_body(a, e)
  a.reduce(VOID) { |_, x| evaluate(x, e) }
end

def evaluate(x, e)
  return e.get(x) if x.is_a?(Symbol)
  unless x.is_a?(Pair)
    shape(!x.equal?(NIL), x)
    return x
  end

  a = list_items(x)
  shape(a, x)
  n = a.length
  case a[0]
  when :quote
    shape(n == 2, x)
    return a[1]
  when :if
    shape([3, 4].include?(n), x)
    return evaluate(a[1], e) != false ? evaluate(a[2], e) : n == 4 ? evaluate(a[3], e) : VOID
  when :begin
    return evaluate_body(a.drop(1), e)
  when :lambda
    p = n >= 3 ? parameters(a[1]) : nil
    shape(p, x)
    return compound(p, a.drop(2), e)
  when :define
    if a[1].is_a?(Symbol)
      shape(n == 3, x)
      v = evaluate(a[2], e)
      v.name = a[1] if v.is_a?(Procedure) && !v.builtin && !v.name
      e.frame[a[1]] = v
    else
      t = a[1]
      p = n >= 3 && t.is_a?(Pair) && t.car.is_a?(Symbol) ? parameters(t.cdr) : nil
      shape(p, x)
      e.frame[t.car] = compound(p, a.drop(2), e, t.car)
    end

    return VOID
  when :"set!"
    shape(n == 3 && a[1].is_a?(Symbol), x)
    v = evaluate(a[2], e)
    e.find(a[1]).frame[a[1]] = v
    return VOID
  when :let, :"let*", :letrec
    named = a[0] == :let && a[1].is_a?(Symbol)
    at = named ? 2 : 1
    bs = n >= at + 2 ? bindings(a[at], a[0] != :"let*") : nil
    shape(bs, x)
    scope = Env.new(e)
    if a[0] == :"let*"
      scope = e unless bs.empty?
      bs.each { |name, expr|
        v = evaluate(expr, scope)
        scope = Env.new(scope)
        scope.frame[name] = v
      }
    elsif a[0] == :letrec
      bs.each { |name, _| scope.frame[name] = UNINIT }
      bs.each { |name, expr| scope.frame[name] = evaluate(expr, scope) }
    else
      values = bs.map { |_, expr| evaluate(expr, e) }
      if named
        p = compound([bs.map(&:first), nil], a.drop(3), scope, a[1])
        scope.frame[a[1]] = p
        return p.call(values)
      end

      bs.zip(values).each { |b, v| scope.frame[b[0]] = v }
    end

    return evaluate_body(a.drop(at + 1), scope)
  when :cond
    cs = a.drop(1).map { |c| list_items(c) }
    cs.each_with_index { |c, i| shape(c && !c.empty? && (c[0] != :else || (c.length >= 2 && i == cs.length - 1)), x) }
    cs.each do |c|
      return evaluate_body(c.drop(1), e) if c[0] == :else
      v = evaluate(c[0], e)
      return c.length == 1 ? v : evaluate_body(c.drop(1), e) if v != false
    end

    return VOID
  when :and
    v = true
    a.drop(1).each { |z|
      v = evaluate(z, e)
      break if v == false
    }
    return v
  when :or
    a.drop(1).each { |z|
      v = evaluate(z, e)
      return v if v != false
    }
    return false
  when :when, :unless
    shape(n >= 3, x)
    return (evaluate(a[1], e) != false) == (a[0] == :when) ? evaluate_body(a.drop(2), e) : VOID
  end

  f = evaluate(a[0], e)
  args = a.drop(1).map { |z| evaluate(z, e) }
  raise "not a procedure: #{represent(f)}" unless f.is_a?(Procedure)
  f.call(args)
end

$mid = false

def write_text(s)
  print(s)
  $mid = !s.end_with?("\n") unless s.empty?
end

def write_line(s)
  write_text("\n") if $mid
  write_text(s + "\n")
end

def expect(name, v, kind)
  ok = case kind
  when "integer"
    v.is_a?(Integer)
  when "string"
    v.is_a?(String)
  when "pair"
    v.is_a?(Pair)
  when "procedure"
    v.is_a?(Procedure)
  when "list"
    !list_items(v).nil?
  end

  raise "#{name}: expected #{kind}, got #{represent(v)}" unless ok
  v
end

def global_env
  e = Env.new
  add = -> (name, min, rest, &fn) { e.frame[name.to_sym] = Procedure.new(name.to_sym, min, rest, &fn) }
  %w[+ * - quotient remainder modulo abs min max gcd = < > <= >=].each do |name|
    fixed = %w[quotient remainder modulo].include?(name) ? 2 : name == "abs" ? 1 : nil
    add.call(name, fixed || (%w[+ * gcd].include?(name) ? 0 : 1), fixed.nil?) do |a|
      a.each { |v| expect(name, v, "integer") }
      case name
      when "+"
        a.sum
      when "*"
        a.reduce(1, :*)
      when "-"
        a.length == 1 ? -a[0] : a.drop(1).reduce(a[0], :-)
      when "abs"
        a[0].abs
      when "min"
        a.min
      when "max"
        a.max
      when "gcd"
        a.reduce(0) { |g, v| g.gcd(v) }
      when "quotient", "remainder", "modulo"
        raise "#{name}: division by zero" if a[1] == 0
        q = a[0].abs / a[1].abs
        q = -q if (a[0] < 0) != (a[1] < 0)
        name == "quotient" ? q : name == "modulo" ? a[0] % a[1] : a[0] - a[1] * q
      else
        a.each_cons(2).all? { |u, v| name == "=" ? u == v : u.public_send(name, v) }
      end
    end
  end

  add.call("not", 1, nil) { |a| a[0] == false }
  add.call("eq?", 2, nil) { |a| same(a[0], a[1]) }
  add.call("equal?", 2, nil) { |a| same(a[0], a[1], true) }
  %w[null? pair? list? number? symbol? procedure?].each do |name|
    add.call(name, 1, nil) do |a|
      case name
      when "null?"
        a[0].equal?(NIL)
      when "pair?"
        a[0].is_a?(Pair)
      when "list?"
        !list_items(a[0]).nil?
      when "number?"
        a[0].is_a?(Integer)
      when "symbol?"
        a[0].is_a?(Symbol)
      else
        a[0].is_a?(Procedure)
      end
    end
  end

  add.call("cons", 2, nil) { |a| Pair.new(*a) }
  add.call("list", 0, true) { |a| make_list(a) }
  %w[car cdr cadr].each do |name|
    add.call(name, 1, nil) { |a|
      p = expect(name, a[0], "pair")
      name == "car" ? p.car : name == "cdr" ? p.cdr : expect(name, p.cdr, "pair").car
    }
  end

  %w[length reverse list-ref].each do |name|
    add.call(name, name == "list-ref" ? 2 : 1, nil) do |a|
      ls = list_items(expect(name, a[0], "list"))
      if name == "length"
        ls.length
      elsif name == "reverse"
        make_list(ls.reverse)
      else
        k = expect(name, a[1], "integer")
        raise "list-ref: index out of range: #{k}" unless k >= 0 && k < ls.length
        ls[k]
      end
    end
  end

  add.call("append", 0, true) { |a|
    a.empty? ? NIL : make_list(a[0...-1].flat_map { |v| list_items(expect("append", v, "list")) }, a[-1])
  }
  %w[map filter fold-left apply].each do |name|
    add.call(name, name == "fold-left" ? 3 : 2, name != "filter") do |a|
      f = expect(name, a[0], "procedure")
      if name == "apply"
        f.call(a[1...-1] + list_items(expect(name, a[-1], "list")))
      else
        ls = a.drop(name == "fold-left" ? 2 : 1).map { |v| list_items(expect(name, v, "list")) }
        if name == "filter"
          make_list(ls[0].select { |v| f.call([v]) != false })
        else
          acc = a[1]
          values = []
          ls.map(&:length).min.times do |i|
            args = ls.map { |l| l[i] }
            if name == "map"
              values << f.call(args)
            else
              acc = f.call([acc] + args)
            end
          end

          name == "map" ? make_list(values) : acc
        end
      end
    end
  end

  add.call("string-append", 0, true) { |a| a.map { |v| expect("string-append", v, "string") }.join }
  add.call("number->string", 1, nil) { |a| expect("number->string", a[0], "integer").to_s }
  add.call("display", 1, nil) { |a|
    write_text(represent(a[0], false))
    VOID
  }
  add.call("newline", 0, nil) { |_|
    write_text("\n")
    VOID
  }
  add.call("error", 1, true) { |a|
    raise expect("error", a[0], "string") + a.drop(1).map { |v| " " + represent(v) }.join
  }
  e
end

class Reader
  def initialize(lines)
    @lines, @row, @column = lines, 0, 0
  end

  def skip_line
    @row += 1
    @column = 0
  end

  def at_end?
    while @row < @lines.length
      s = @lines[@row]
      @column += 1 while s[@column] == " "
      return false if @column < s.length && s[@column] != ";"
      skip_line
    end

    true
  end

  def token
    raise "unexpected end of input" if at_end?
    s = @lines[@row]
    c = s[@column]
    @column += 1
    return [c, nil] if "()'".include?(c)
    if c == "\""
      v = ""
      while @column < s.length
        c = s[@column]
        @column += 1
        return ["value", v] if c == "\""
        if c == "\\"
          break if @column == s.length
          c = s[@column]
          @column += 1
          raise "bad escape" unless ["\"", "\\", "n"].include?(c)
          v += c == "n" ? "\n" : c
        else
          v += c
        end
      end

      raise "unterminated string"
    end

    start = @column - 1
    @column += 1 while @column < s.length && !" ()'\";".include?(s[@column])
    a = s[start...@column]
    return [".", nil] if a == "."
    return ["value", a.to_i] if /\A[+-]?[0-9]+\z/.match?(a)
    return ["value", a == "#t"] if %w[#t #f].include?(a)
    raise "bad token: #{a}" if a.start_with?("#")
    ["value", a.to_sym]
  end

  def datum(t = token)
    return t[1] if t[0] == "value"
    return make_list([:quote, datum]) if t[0] == "'"
    raise "unexpected #{t[0]}" unless t[0] == "("
    a = []
    loop do
      t = token
      return make_list(a) if t[0] == ")"
      if t[0] == "." && !a.empty?
        tail = datum
        raise "expected )" unless token[0] == ")"
        return make_list(a, tail)
      end

      a << datum(t)
    end
  end
end

lines = STDIN.each_line.map(&:chomp).take_while { |s| s != "(exit)" }
reader, env = Reader.new(lines), global_env
until reader.at_end?
  begin
    x = reader.datum
  rescue => error
    write_line("Error: read: " + error.message)
    break if error.message == "unexpected end of input"
    reader.skip_line
    next
  end

  begin
    value = evaluate(x, env)
    write_line(represent(value)) unless value.equal?(VOID)
  rescue => error
    write_line("Error: " + error.message)
  end
end

write_text("\n") if $mid
