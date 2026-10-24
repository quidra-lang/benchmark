FUNCTIONS = %w[sin cos tan exp ln sqrt].freeze
Expr = Data.define(:kind, :value, :items)
def num(p, q = 1) = Expr.new(5, Rational(p, q), [])
def tree(k, a, s = nil) = Expr.new(k, s, a)
ZERO, ONE, MINUS, HALF = num(0), num(1), num(-1), num(1, 2)
def integer?(f) = f.kind == 5 && f.value.denominator == 1
def negative?(f) = f.kind == 3 && f.items[1].kind == 5 && f.items[1].value < 0
def base(f) = f.kind == 3 ? f.items[0] : f
def exponent(f) = f.kind == 3 ? f.items[1] : ONE
def coefficient(f)
  return [f.value, []] if f.kind == 5
  return f.items[0].kind == 5 ? [f.items[0].value, f.items.drop(1)] : [Rational(1), f.items] if f.kind == 2
  [Rational(1), [f]]
end
def order(f)
  return [f.kind, f.value] if [0, 5].include?(f.kind)
  return [4, f.value, order(f.items[0])] if f.kind == 4
  [f.kind, f.items.map { |a| order(a) }]
end
def exponent_compare(a, b)
  return -1 if a.kind == 5 && b.kind != 5
  return 1 if a.kind != 5 && b.kind == 5
  order(a) <=> order(b)
end
def term_compare(a, b)
  x, y = coefficient(a)[1], coefficient(b)[1]
  (x + y).map { |f| base(f) }.uniq.sort_by { |f| order(f) }.each do |f|
    s, t = x.find { |g| base(g) == f }, y.find { |g| base(g) == f }
    c = exponent_compare(t ? exponent(t) : ZERO, s ? exponent(s) : ZERO)
    return c unless c.zero?
  end
  0
end
def product(c, a)
  return num(c) if a.empty?
  return tree(2, [num(c), *a]) unless c == 1
  a.length == 1 ? a[0] : tree(2, a)
end
def add(*operands)
  terms = operands.flat_map do |f|
    if f.kind == 1 then f.items
    elsif f.kind == 2 && f.items.length == 2 && f.items[0].kind == 5 && f.items[1].kind == 1
      f.items[1].items.map { |t| mul(f.items[0], t) }
    else [f] end
  end
  groups = Hash.new(0)
  terms.each { |f| c, m = coefficient(f); groups[m] += c }
  built = groups.filter_map { |m, c| product(c, m) unless c.zero? }.sort { |a, b| term_compare(a, b) }
  built.empty? ? ZERO : built.length == 1 ? built[0] : tree(1, built)
end
def mul(*operands)
  c = Rational(1)
  groups = {}
  operands.flat_map { |f| f.kind == 2 ? f.items : [f] }.each do |f|
    if f.kind == 5 then c *= f.value
    else (groups[base(f)] ||= []) << f end
  end
  return ZERO if c.zero?
  results = groups.map { |b, a| a.length == 1 ? a[0] : power(b, add(*a.map { |f| exponent(f) })) }
  return mul(num(c), *results) if results.any? { |f| [2, 5].include?(f.kind) } || results.map { |f| base(f) }.uniq.length < results.length
  product(c, results.sort_by { |f| order(base(f)) })
end
def root(v, d)
  return 1 if v == 1
  return nil if d > 20
  r = (v**(1.0 / d)).round
  ([0, r - 1].max..r + 1).find { |s| s**d == v }
end
def power(b, x)
  return ONE if x == ZERO
  return b if x == ONE
  if b.kind == 5
    return ONE if b == ONE
    return tree(3, [b, x]) unless x.kind == 5
    if b.value.zero?
      return ZERO if x.value.positive?
      raise 'division by zero'
    end
    return num(b.value**x.value.numerator) if integer?(x)
    if b.value.positive?
      s, t = root(b.value.numerator, x.value.denominator), root(b.value.denominator, x.value.denominator)
      return num(Rational(s, t)**x.value.numerator) if s && t
    end
  elsif integer?(x)
    return power(b.items[0], mul(b.items[1], x)) if b.kind == 3
    return mul(*b.items.map { |f| power(f, x) }) if b.kind == 2
  end
  tree(3, [b, x])
end
def fn(s, a)
  return power(a, HALF) if s == 'sqrt'
  return ZERO if a == ZERO && %w[sin tan].include?(s)
  return ONE if a == ZERO && %w[cos exp].include?(s)
  return ZERO if a == ONE && s == 'ln'
  if %w[sin cos tan].include?(s) && coefficient(a)[0].negative?
    r = fn(s, mul(MINUS, a))
    return s == 'cos' ? r : mul(MINUS, r)
  end
  return a.items[0] if a.kind == 4 && ((s == 'exp' && a.value == 'ln') || (s == 'ln' && a.value == 'exp'))
  tree(4, [a], s)
end
def variables(f) = (f.kind == 0 ? [f.value] : f.items.flat_map { |a| variables(a) }).uniq.sort

def derivative(f, v)
  case f.kind
  when 5 then ZERO
  when 0 then f.value == v ? ONE : ZERO
  when 1 then add(*f.items.map { |a| derivative(a, v) })
  when 2 then add(*f.items.each_index.map { |i| mul(*f.items.each_with_index.map { |a, j| i == j ? derivative(a, v) : a }) })
  when 3
    b, x = f.items
    return mul(x, power(b, add(x, MINUS)), derivative(b, v)) unless variables(x).include?(v)
    return mul(f, fn('ln', b), derivative(x, v)) unless variables(b).include?(v)
    mul(f, add(mul(derivative(x, v), fn('ln', b)), mul(x, derivative(b, v), power(b, MINUS))))
  when 4
    a = f.items[0]
    h = case f.value
        when 'sin' then fn('cos', a)
        when 'cos' then mul(MINUS, fn('sin', a))
        when 'tan' then power(fn('cos', a), num(-2))
        when 'exp' then f
        else power(a, MINUS) end
    mul(h, derivative(a, v))
  end
end
def rebuild(f, a)
  case f.kind
  when 1 then add(*a)
  when 2 then mul(*a)
  when 3 then power(*a)
  else fn(f.value, a[0]) end
end
def substitute(f, values)
  return values.fetch(f.value, f) if f.kind == 0
  return f if f.kind == 5
  rebuild(f, f.items.map { |a| substitute(a, values) })
end
def terms(f) = f.kind == 1 ? f.items : [f]
def distribute(a, b) = add(*terms(a).flat_map { |x| terms(b).map { |y| mul(x, y) } })
def expand(f)
  return f if [0, 5].include?(f.kind)
  a = f.items.map { |g| expand(g) }
  return a.reduce { |x, y| distribute(x, y) } if f.kind == 2
  if f.kind == 3 && a[0].kind == 1 && integer?(a[1]) && a[1].value.positive?
    return (a[1].value.numerator - 1).times.reduce(a[0]) { |r, _| distribute(r, a[0]) }
  end
  rebuild(f, a)
end
def numeric(f)
  return f.value.to_f if f.kind == 5
  return f.items.sum { |a| numeric(a) } if f.kind == 1
  return f.items.reduce(1.0) { |r, a| r * numeric(a) } if f.kind == 2
  if f.kind == 3
    u, z = f.items.map { |a| numeric(a) }
    integral = f.items[1].kind == 5 ? integer?(f.items[1]) : z == z.truncate
    raise 'domain error' if u < 0 && !integral
    return f.items[1] == HALF ? Math.sqrt(u) : u**z
  end
  a = numeric(f.items[0])
  raise 'domain error' if f.value == 'ln' && a <= 0
  Math.public_send(f.value == 'ln' ? :log : f.value, a)
end
def atomic?(f) = [0, 4].include?(f.kind) || (integer?(f) && f.value >= 0) || (f.kind == 3 && f.items[1] == HALF)
def atom(f) = atomic?(f) ? show(f) : "(#{show(f)})"
def show_power(b, x) = x == HALF ? "sqrt(#{show(b)})" : "#{atom(b)}^#{atom(x)}"
def factor(f) = f.kind == 1 ? "(#{show(f)})" : f.kind == 3 ? show_power(*f.items) : show(f)
def quotient(c, a)
  p, q = c.abs.numerator, c.denominator
  top, bottom = p == 1 ? [] : [p.to_s], q == 1 ? [] : [q.to_s]
  a.each do |f|
    if negative?(f)
      r = num(-f.items[1].value)
      bottom << (r == ONE ? factor(f.items[0]) : show_power(f.items[0], r))
    else top << factor(f) end
  end
  text = top.empty? ? '1' : top.join('*')
  text += bottom.length == 1 ? "/#{bottom[0]}" : "/(#{bottom.join('*')})" unless bottom.empty?
  c.negative? ? '-' + text : text
end
def show(f)
  case f.kind
  when 5 then f.value.denominator == 1 ? f.value.numerator.to_s : f.value.to_s
  when 0 then f.value
  when 4 then "#{f.value}(#{show(f.items[0])})"
  when 3 then negative?(f) ? quotient(Rational(1), [f]) : show_power(*f.items)
  when 2 then quotient(*coefficient(f))
  else f.items.map { |a| show(a) }.reduce { |a, b| a + (b.start_with?('-') ? ' - ' + b[1..] : ' + ' + b) } end
end
class Parser
  def initialize(text, names)
    @tokens = []
    text.scan(/[0-9]+|[a-z][a-z0-9]*|[A-Z][A-Z0-9]*|[-+*\/^()]| +|./).each do |t|
      next if t.start_with?(' ')
      raise "invalid character '#{t}'" unless /\A[a-zA-Z0-9+*\/^()-]+\z/.match?(t)
      @tokens << t
    end
    @names, @p = names, 0
  end
  def peek = @tokens[@p]
  def unexpected = raise(peek ? "unexpected '#{peek}'" : 'unexpected end of expression')
  def accept(s)
    return false unless peek == s
    @p += 1
    true
  end
  def expect(s) = accept(s) || unexpected
  def atom
    t = peek
    unexpected unless t
    if accept('(')
      a = expression
      expect(')')
      return a
    end
    unexpected unless /\A[a-zA-Z0-9]/.match?(t)
    @p += 1
    return num(t.to_i) if /\A[0-9]/.match?(t)
    return @names.fetch(t) { raise "undefined name '#{t}'" } if /\A[A-Z]/.match?(t)
    return tree(0, [], t) unless FUNCTIONS.include?(t)
    expect('(')
    a = expression
    expect(')')
    [t, a]
  end
  def unary
    return ['neg', unary] if accept('-')
    a = atom
    accept('^') ? ['^', a, unary] : a
  end
  def term
    a = unary
    while %w[* /].include?(peek)
      op = peek; @p += 1; a = [op, a, unary]
    end
    a
  end
  def expression
    a = term
    while %w[+ -].include?(peek)
      op = peek; @p += 1; a = [op, a, term]
    end
    a
  end
  def evaluate(t)
    return t if t.is_a?(Expr)
    op, *a = t
    a.map! { |x| evaluate(x) }
    case op
    when '+' then add(*a)
    when '-' then add(a[0], mul(MINUS, a[1]))
    when '*' then mul(*a)
    when '/' then mul(a[0], power(a[1], MINUS))
    when '^' then power(*a)
    when 'neg' then mul(MINUS, a[0])
    else fn(op, a[0]) end
  end
  def parse
    t = expression
    unexpected if peek
    evaluate(t)
  end
end
def variable?(s) = /\A[a-z][a-z0-9]*\z/.match?(s) && !FUNCTIONS.include?(s)
def literal(s)
  raise "invalid number '#{s}'" unless /\A-?[0-9]+(?:\/[0-9]+)?\z/.match?(s)
  p, q = s.split('/').map(&:to_i)
  raise 'division by zero' if q == 0
  num(p, q || 1)
end
SIGNATURES = {'SIMPLIFY'=>'e','EXPAND'=>'e','DIFF'=>'ev','DIFFN'=>'evn','GRAD'=>'e','HESSIAN'=>'e','IMPLICIT'=>'evv','SUBST'=>'eve','EVAL'=>'ea','TANGENT'=>'evc','LIMIT'=>'evc','TAYLOR'=>'evcn'}.freeze
def command(line, names)
  c, separator, argument = line.partition(' ')
  if c == 'LET'
    raise 'wrong number of arguments' unless argument.include?('=')
    name, _, text = argument.partition('='); name = name.strip
    raise "invalid name '#{name}'" unless /\A[A-Z][A-Z0-9]*\z/.match?(name)
    f = Parser.new(text.strip, names).parse
    names[name] = f
    return ["#{name} = #{show(f)}"]
  end
  raise "unknown command #{c}" unless SIGNATURES.key?(c)
  fields = separator.empty? ? [] : argument.split(';', -1).map(&:strip)
  sig = SIGNATURES[c]
  raise 'wrong number of arguments' unless c == 'EVAL' ? [1, 2].include?(fields.length) : fields.length == sig.length
  a = fields.each_with_index.map do |s, i|
    case sig[i]
    when 'e' then Parser.new(s, names).parse
    when 'v' then raise("invalid variable '#{s}'") unless variable?(s); s
    when 'n' then raise("invalid order '#{s}'") unless /\A[1-8]\z/.match?(s); s.to_i
    when 'c' then literal(s)
    else s end
  end
  f, v, x, n = a
  case c
  when 'SIMPLIFY' then ["simplified: #{show(f)}"]
  when 'EXPAND' then ["expanded: #{show(expand(f))}"]
  when 'DIFF' then ["d/d#{v} = #{show(derivative(f, v))}"]
  when 'DIFFN' then (1..x).map { |k| f = derivative(f, v); "d^#{k}/d#{v}^#{k} = #{show(f)}" }
  when 'GRAD', 'HESSIAN'
    vs = variables(f)
    return ['no variables'] if vs.empty?
    vs.each_with_index.flat_map do |s, i|
      d = derivative(f, s)
      c == 'GRAD' ? ["d/d#{s} = #{show(d)}"] : vs.drop(i).map { |t| "d2/d#{s}d#{t} = #{show(derivative(d, t))}" }
    end
  when 'IMPLICIT'
    raise 'same variable' if v == x
    ["d#{x}/d#{v} = #{show(mul(MINUS, derivative(f, v), power(derivative(f, x), MINUS)))}"]
  when 'SUBST' then ["substituted: #{show(substitute(f, {v => x}))}"]
  when 'EVAL'
    values = {}
    (v || '').split.each do |word|
      m = /\A([a-z][a-z0-9]*)=(-?[0-9]+(?:\/[0-9]+)?)\z/.match(word)
      raise "invalid assignment '#{word}'" unless m && variable?(m[1])
      q = literal(m[2]); raise "duplicate variable #{m[1]}" if values.key?(m[1]); values[m[1]] = q
    end
    variables(f).each { |s| raise "no value for #{s}" unless values.key?(s) }
    r = substitute(f, values)
    [r.kind == 5 ? "exact: #{show(r)}" : format('approx: %.6f', numeric(r))]
  when 'TANGENT'
    m = substitute(derivative(f, v), {v => x}); y = substitute(f, {v => x}); variable = tree(0, [], v)
    tangent = "tangent: y = #{show(add(mul(m, variable), y, mul(num(-x.value), m)))}"
    return [tangent, "normal: #{v} = #{show(x)}"] if m == ZERO
    k = power(m, MINUS)
    [tangent, "normal: y = #{show(add(mul(MINUS, k, variable), y, mul(x, k)))}"]
  when 'LIMIT'
    top, bottom = [], []
    (f.kind == 2 ? f.items : [f]).each { |t| negative?(t) ? bottom << power(t.items[0], num(-t.items[1].value)) : top << t }
    g, h = mul(*top), mul(*bottom)
    6.times do |k|
      u, b = substitute(g, {v => x}), substitute(h, {v => x})
      return ["limit: #{show(mul(u, power(b, MINUS)))}"] unless b == ZERO
      return ['limit: unbounded'] unless u == ZERO
      g, h = derivative(g, v), derivative(h, v) if k < 5
    end
    ['limit: unknown']
  when 'TAYLOR'
    ds = [f]; n.times { ds << derivative(ds[-1], v) }; factorial = 1
    ps = ds.each_with_index.map do |d, k|
      factorial *= k if k > 0
      mul(mul(substitute(d, {v => x}), num(1, factorial)), power(add(tree(0, [], v), num(-x.value)), num(k)))
    end
    ["taylor: #{show(expand(add(*ps)))}"]
  end
end
names = {}
gets.to_i.times do
  begin
    puts command(gets.chomp, names)
  rescue RuntimeError => e
    puts "error: #{e.message}"
  end
end
