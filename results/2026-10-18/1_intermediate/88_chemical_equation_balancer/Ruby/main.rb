SYMBOLS = %w[
  H
  He
  Li
  Be
  B
  C
  N
  O
  F
  Ne
  Na
  Mg
  Al
  Si
  P
  S
  Cl
  Ar
  K
  Ca
  Sc
  Ti
  V
  Cr
  Mn
  Fe
  Co
  Ni
  Cu
  Zn
  Ga
  Ge
  As
  Se
  Br
  Kr
  Rb
  Sr
  Y
  Zr
  Nb
  Mo
  Tc
  Ru
  Rh
  Pd
  Ag
  Cd
  In
  Sn
  Sb
  Te
  I
  Xe
]
WEIGHTS = SYMBOLS
  .zip(
    [
      1008,
      4003,
      6941,
      9012,
      10811,
      12011,
      14007,
      15999,
      18998,
      20180,
      22990,
      24305,
      26982,
      28086,
      30974,
      32065,
      35453,
      39948,
      39098,
      40078,
      44956,
      47867,
      50942,
      51996,
      54938,
      55845,
      58933,
      58693,
      63546,
      65380,
      69723,
      72630,
      74922,
      78971,
      79904,
      83798,
      85468,
      87620,
      88906,
      91224,
      92906,
      95950,
      98000,
      101070,
      102906,
      106420,
      107868,
      112414,
      114818,
      118710,
      121760,
      127600,
      126904,
      131293
    ]
  )
  .to_h
VALENCE = [%w[H F Cl Br I], %w[O S Se], %w[B N P As], %w[C Si Ge]]
  .each_with_index
  .flat_map { |es, i|
    es.map { |e| [e, i + 1] }
  }
  .to_h
METALS = {"Li" => 1, "Na" => 1, "K" => 1, "Rb" => 1, "Be" => 2, "Mg" => 2, "Ca" => 2, "Sr" => 2, "Al" => 3}
Formula = Data.define(:c, :q) do
  def mass = c.sum { |e, n| n * WEIGHTS.fetch(e) }
end

Species = Data.define(:f, :state, :k, :formula) do
  def name = f + state
  def mass = formula.mass
  def c = formula.c
  def q = formula.q
end

Equation = Data.define(:list, :r) do
  def signs = list.each_index.map { |i| i < r ? 1 : -1 }
end

class ChemError < StandardError
end

class NoCoefficients < StandardError
end

def fail_chem(text) = raise ChemError, text
def dec(n, d) = "#{n / 10 ** d}.#{(n % 10 ** d).to_s.rjust(d, "0")}"
def ent(n) = (n < 0 ? "-" : "") + dec(n.abs, 2)
def signed(n)
  return "0" if n == 0
  r = n.to_r
  (r > 0 ? "+" : "-") + r.numerator.abs.to_s + (r.denominator == 1 ? "" : "/#{r.denominator}")
end

def order(c)
  es = c.keys.sort
  es.include?("C") ? ["C", *(es.include?("H") ? ["H"] : []), *(es - %w[C H])] : es
end

def add(a, b, k = 1)
  b.each { |e, n| a[e] = a.fetch(e, 0) + n * k }
  a
end

def scale(c, k) = c.transform_values { |n| n * k }
def hill(c, q = 0)
  order(c).map { |e| e + (c[e] == 1 ? "" : c[e].to_s) }.join +
    (q == 0 ? "" : "^" + (q.abs == 1 ? "" : q.abs.to_s) + (q > 0 ? "+" : "-"))
end

class FormulaParser
  attr_reader :symbols
  def initialize(text)
    @text = text
    @p = 0
    @symbols = []
  end

  def peek = @text[@p] || ""
  def number
    start = @p
    @p += 1 while peek.match?(/\A[0-9]\z/)
    return 1 if start == @p
    raise ArgumentError if @text[start] == "0"
    @text[start...@p].to_i
  end

  def sequence
    c = {}
    items = 0
    loop do
      ch = peek
      if ch.match?(/\A[A-Z]\z/)
        e = ch
        @p += 1
        if peek.match?(/\A[a-z]\z/)
          e += peek
          @p += 1
        end

        @symbols << e
        item = {e => 1}
      elsif ["(", "["].include?(ch)
        @p += 1
        item = sequence
        raise ArgumentError unless peek == (ch == "(" ? ")" : "]")
        @p += 1
      else
        break
      end

      add(c, item, number)
      items += 1
    end

    raise ArgumentError if items == 0
    c
  end

  def parse
    c = sequence
    while peek == "."
      @p += 1
      k = number
      add(c, sequence, k)
    end

    q = 0
    if peek == "^"
      @p += 1
      k = number
      ch = peek
      raise ArgumentError unless ["+", "-"].include?(ch)
      @p += 1
      q = ch == "+" ? k : -k
    end

    raise ArgumentError unless @p == @text.length
    Formula.new(c, q)
  end
end

def formula(text, word = text)
  p = FormulaParser.new(text)
  begin
    f = p.parse
  rescue ArgumentError
    fail_chem("invalid formula #{word}")
  end

  p.symbols.each { |e| fail_chem("unknown element #{e}") unless WEIGHTS.key?(e) }
  f
end

def species(word, check = false)
  state = %w[(s) (l) (g) (aq)].find { |s| word.end_with?(s) } || ""
  f = state.empty? ? word : word[0...-state.length]
  k = 1
  if check && (m = /\A[0-9]+/.match(f))
    fail_chem("invalid formula #{word}") if f.start_with?("0")
    k = m[0].to_i
    f = f[m[0].length..]
  end

  Species.new(f, state, k, formula(f, word))
end

def equation(a, check = false)
  ops = a.each_index.select(&:odd?).map { |i| a[i] }
  if a.length.even? ||
      ops.count("->") != 1 ||
      ops.any? { |s| !%w[+ ->].include?(s) } ||
      a.each_index.any? { |i| i.even? && %w[+ ->].include?(a[i]) }
    fail_chem("malformed equation")
  end

  Equation.new(a.each_index.select(&:even?).map { |i| species(a[i], check) }, (a.index("->") + 1) / 2)
end

def quantity(s)
  fail_chem("invalid quantity #{s}") unless /\A(0|[1-9][0-9]{0,3})(?:\.([0-9]{1,3}))?\z/.match?(s)
  a, b = s.split(".")
  q = a.to_i * 1000 + (b || "").ljust(3, "0").to_i
  fail_chem("invalid quantity #{s}") if q == 0
  q
end

def enthalpy(s)
  fail_chem("invalid enthalpy #{s}") unless /\A-?(0|[1-9][0-9]{0,4})(?:\.[0-9]{1,2})?\z/.match?(s)
  a, b = s.delete_prefix("-").split(".")
  (s.start_with?("-") ? -1 : 1) * (a.to_i * 100 + (b || "").ljust(2, "0").to_i)
end

def matrix(list, signs)
  all = {}
  list.each { |s| add(all, s.c) }
  labels = order(all) + ["charge"]
  [labels, labels.map { |e| list.each_with_index.map { |s, i| signs[i] * (e == "charge" ? s.q : s.c.fetch(e, 0)) } }]
end

def nullspace(rows, n)
  a = rows.map { |r| r.map(&:to_r) }
  piv = []
  free = []
  n.times do |j|
    r = piv.length
    i = (r...a.length).find { |k| a[k][j] != 0 }
    if i.nil?
      free << j
      next
    end

    a[r], a[i] = a[i], a[r]
    t = a[r][j]
    a[r] = a[r].map { |x| x / t }
    a.each_index do |k|
      next if k == r || a[k][j] == 0
      t = a[k][j]
      a[k] = a[k].each_with_index.map { |x, z| x - t * a[r][z] }
    end

    piv << j
  end

  basis = free.map do |f|
    v = Array.new(n, 0.to_r)
    v[f] = 1.to_r
    piv.each_with_index { |j, i| v[j] = -a[i][f] }
    l = v.map(&:denominator).reduce(1, :lcm)
    b = v.map { |x| (x * l).to_i }
    g = b.reduce(0) { |t, x| t.gcd(x) }
    b.map { |x| x / g }
  end

  [piv.length, basis]
end

def coefficients(list, signs, k = list.length)
  _, basis = nullspace(matrix(list, signs)[1], list.length)
  raise NoCoefficients, "AMBIGUOUS (nullity #{basis.length})" if basis.length >= 2
  raise NoCoefficients, "IMPOSSIBLE" if basis.empty?
  v = basis[0]
  v = v.map { |x| -x } if v[0] < 0
  raise NoCoefficients, "IMPOSSIBLE" if v.take(k).any? { |x| x <= 0 }
  v
end

def term(s, k) = k == 1 ? s : k.to_s + s
def notation(eq, v)
  t = eq.list.each_with_index.map { |s, i| term(s.name, v[i]) }
  t.take(eq.r).join(" + ") + " -> " + t.drop(eq.r).join(" + ")
end

def gas(s, n, d) = s.state == "(g)" ? " #{dec(n * 22414 / d, 3)} L" : ""
def ratios(a)
  es = order(a)
  f = es.min_by { |e| Rational(a[e], WEIGHTS[e]) }
  out = es.map { |e| "#{e} #{dec(1000 * a[e] * WEIGHTS[f] / (WEIGHTS[e] * a[f]), 3)}" }
  (1..12).each do |k|
    c = {}
    ok = true
    es.each do |e|
      n = k * a[e] * WEIGHTS[f]
      d = WEIGHTS[e] * a[f]
      i = (2 * n + d) / (2 * d)
      c[e] = i
      ok = false if 20 * (n - i * d).abs > d
    end

    return out + ["#{hill(c)} (k = #{k})"] if ok
  end

  out + ["no simple ratio"]
end

def group(f, k)
  c = f.split("^")[0]
  return c if k == 1
  depth = 0
  last = nil
  if c.start_with?("[")
    c.chars.each_with_index { |ch, i|
      depth += 1 if ch == "["
      if ch == "]"
        depth -= 1
        if depth == 0
          last = i
          break
        end
      end
    }
  end

  (/\A[A-Z][a-z]?\z/.match?(c) || last == c.length - 1 ? c : "(#{c})") + k.to_s
end

COUNTS = {
  "ELEMENT" => 1,
  "PARSE" => 1,
  "MASS" => 1,
  "PERCENT" => 1,
  "EMPIRICAL" => 1,
  "DBE" => 1,
  "OXSTATE" => 1,
  "MOLES" => 2,
  "GRAMS" => 2,
  "MOLECULAR" => 2,
  "SALT" => 2,
  "HEAT" => 2,
  "COMBUST" => 3,
  "HEATS" => 0,
  "DERIVE" => -2,
  "BALANCE" => -1,
  "MATRIX" => -1,
  "CHECK" => -1,
  "DELTAH" => -1,
  "REDOX" => -3,
  "HALF" => -3,
  "STOICH" => -4,
  "LIMITING" => -4,
  "YIELD" => -4
}

class Chemistry
  def initialize = @heats = {}
  def execute(line)
    cmd, *a = line.split(" ")
    n = a.length
    fail_chem("unknown command #{cmd}") unless COUNTS.key?(cmd)
    e = COUNTS[cmd]
    if (e >= 0 && n != e) || (e == -1 && n < 1) || (e == -2 && (n < 2 || n.odd?)) || (e == -3 && n < 2)
      fail_chem("wrong argument count for #{cmd}")
    end

    case cmd
    when "ELEMENT"
      s = a[0]
      fail_chem("unknown element #{s}") unless WEIGHTS.key?(s)
      return ["#{s} (Z = #{SYMBOLS.index(s) + 1}) #{dec(WEIGHTS[s], 3)} u"]
    when "HEATS"
      return @heats.empty? ? ["no enthalpies"] : @heats.keys.sort.map { |s| "#{s} #{ent(@heats[s])} kJ/mol" }
    when "HEAT"
      species(a[0])
      h = enthalpy(a[1])
      s = "dHf(#{a[0]}) = #{ent(h)} kJ/mol"
      s += " (was #{ent(@heats[a[0]])})" if @heats.key?(a[0])
      @heats[a[0]] = h
      return [s]
    when "DERIVE"
      b = {}
      a.each_slice(2) do |s, w|
        fail_chem("unknown element #{s}") unless WEIGHTS.key?(s)
        fail_chem("duplicate element #{s}") if b.key?(s)
        q = quantity(w)
        fail_chem("invalid percentage #{w}") if q > 100000
        b[s] = q
      end

      t = b.values.sum
      fail_chem("percentages sum to #{dec(t, 3)}") if (t - 100000).abs > 1000
      return ratios(b)
    when "COMBUST"
      s, p, r = a.map { |x| quantity(x) }
      c = p * 12011 / 44009
      h = r * 2016 / 18015
      o = s - c - h
      fail_chem("inconsistent masses") if c == 0 || h == 0 || 100 * o < -s
      b = {"C" => c, "H" => h}
      b["O"] = o if 100 * o > s
      return b.map { |el, m| "mass #{el} #{dec(m, 3)} g" } + ratios(b)
    end

    if %w[PARSE MASS PERCENT EMPIRICAL DBE OXSTATE MOLES GRAMS MOLECULAR SALT].include?(cmd)
      f = formula(a[0])
      c = f.c
      q = f.q
      m = f.mass
      es = order(c)
      case cmd
      when "PARSE"
        return ["#{hill(c, q)} (#{es.map { |el| "#{el} #{c[el]}" }.join(", ")}; charge #{signed(q)})"]
      when "MASS"
        return ["M(#{a[0]}) = #{dec(m, 3)} g/mol"]
      when "PERCENT"
        return es.map { |el| "#{el} #{dec(10000 * c[el] * WEIGHTS[el] / m, 2)}%" }
      when "EMPIRICAL"
        g = c.values.reduce(:gcd)
        return ["#{hill(c.transform_values { |x| x / g })} (n = #{g})"]
      when "DBE"
        fail_chem("charged formula #{a[0]}") unless q == 0
        t = 2
        es.each { |el|
          fail_chem("no valence for #{el}") unless VALENCE.key?(el)
          t += c[el] * (VALENCE[el] - 2)
        }
        return ["DBE = #{t < 0 ? "-" : ""}#{t.abs / 2}.#{t.odd? ? 5 : 0}"]
      when "OXSTATE"
        st = {}
        if es.length == 1
          st[es[0]] = Rational(q, c[es[0]])
        else
          st["F"] = -1 if c.key?("F")
          es.each { |el| st[el] = METALS[el] if METALS.key?(el) }
          st["H"] = es.all? { |el| el == "H" || METALS.key?(el) } ? -1 : 1 if c.key?("H")
          if c.key?("O")
            st["O"] = -2
          elsif !c.key?("F")
            el = %w[Cl Br I].find { |x| c.key?(x) }
            st[el] = -1 if el
          end

          u = es - st.keys
          return ["indeterminate: " + u.join(" ")] if u.length >= 2
          total = st.sum { |el, x| c[el] * x }
          if u.length == 1
            st[u[0]] = Rational(q - total, c[u[0]])
          elsif total != q
            el = st.keys.last
            st[el] = Rational(q - total + c[el] * st[el], c[el])
          end
        end

        return [es.map { |el| "#{el} #{signed(st[el])}" }.join(", ")]
      when "SALT"
        b = formula(a[1])
        fail_chem("not a cation #{a[0]}") if q <= 0
        fail_chem("not an anion #{a[1]}") if b.q >= 0
        a.each { |w| fail_chem("hydrate ion #{w}") if w.include?(".") }
        g = q.gcd(b.q)
        x = -b.q / g
        y = q / g
        z = add(scale(c, x), b.c, y)
        return ["#{group(a[0], x)}#{group(a[1], y)} (#{hill(z)}, #{dec(Formula.new(z, 0).mass, 3)} g/mol)"]
      end

      fail_chem("charged formula #{a[0]}") if cmd == "MOLECULAR" && q != 0
      v = quantity(a[1])
      return ["#{dec(v, 3)} g #{a[0]} = #{dec(v * 1000000 / m, 6)} mol"] if cmd == "MOLES"
      return ["#{dec(v, 3)} mol #{a[0]} = #{dec(v * m / 1000, 3)} g"] if cmd == "GRAMS"
      k = (2 * v + m) / (2 * m)
      return ["no integer multiple (ratio #{dec(1000 * v / m, 3)})"] if k == 0 || 10 * (v - k * m).abs > m
      return ["#{hill(scale(c, k))} (n = #{k}, #{dec(k * m, 3)} g/mol)"]
    end

    if %w[REDOX HALF].include?(cmd)
      fail_chem("invalid medium #{a[0]}") unless %w[acidic basic].include?(a[0])
      eq = equation(a.drop(1))
      eq.list.each { |s| fail_chem("reserved species #{s.name}") if %w[H^+ OH^- H2O].include?(s.f) }
      aux = [species(a[0] == "acidic" ? "H^+" : "OH^-"), species("H2O")]
      aux << Species.new("e^-", "", 1, Formula.new({}, -1)) if cmd == "HALF"
      v = coefficients(eq.list + aux, eq.signs + Array.new(aux.length, 1), eq.list.length)
      left = []
      right = []
      eq.list.each_with_index { |s, i| (i < eq.r ? left : right) << term(s.name, v[i]) }
      aux.each_with_index { |s, i|
        k = v[eq.list.length + i]
        (k > 0 ? left : right) << term(s.name, k.abs) unless k == 0
      }
      out = [left.join(" + ") + " -> " + right.join(" + ")]
      out << (v[-1] > 0 ? "reduction" : v[-1] < 0 ? "oxidation" : "no electron transfer") if cmd == "HALF"
      return out
    end

    words = a
    rest = []
    if %w[STOICH LIMITING YIELD].include?(cmd)
      fail_chem("invalid separator") unless a.count(":") == 1
      i = a.index(":")
      words = a.take(i)
      rest = a.drop(i + 1)
      if (cmd == "STOICH" && rest.length != 2) || (cmd == "YIELD" && rest.length != 4)
        fail_chem("wrong argument count for #{cmd}")
      end
    end

    eq = equation(words, cmd == "CHECK")
    list = eq.list
    r = eq.r
    if cmd == "MATRIX"
      labels, rows = matrix(list, eq.signs)
      rank, basis = nullspace(rows, list.length)
      return ["columns: " + list.map(&:name).join(" ")] +
        rows.each_with_index.map { |row, i| labels[i] + ": " + row.join(" ") } +
        ["rank #{rank}, nullity #{basis.length}"] +
        basis.map { |v| "null: " + v.join(" ") }
    end

    if cmd == "CHECK"
      labels, rows = matrix(list, eq.signs)
      diff = []
      rows.each_with_index do |row, i|
        l = (0...r).sum { |j| row[j] * list[j].k }
        rr = -(r...list.length).sum { |j| row[j] * list[j].k }
        unless l == rr
          diff << "#{labels[i]}: #{labels[i] == "charge" ? signed(l) : l} != #{labels[i] == "charge" ? signed(rr) : rr}"
        end
      end

      return ["not balanced"] + diff unless diff.empty?
      g = list.map(&:k).reduce(:gcd)
      return [g == 1 ? "balanced" : "balanced, not in lowest terms (gcd #{g})"]
    end

    qs = []
    target = product = nil
    case cmd
    when "DELTAH"
      list.each { |s| fail_chem("no enthalpy for #{s.name}") unless @heats.key?(s.name) }
    when "STOICH"
      target = list.index { |s| s.name == rest[0] }
      fail_chem("species #{rest[0]} not in equation") if target.nil?
      qs = [quantity(rest[1])]
    when "LIMITING"
      fail_chem("expected #{r} masses, got #{rest.length}") unless rest.length == r
      qs = rest.map { |s| quantity(s) }
    when "YIELD"
      target = (0...r).find { |i| list[i].name == rest[0] }
      fail_chem("#{rest[0]} is not a reactant") if target.nil?
      product = (r...list.length).find { |i| list[i].name == rest[2] }
      fail_chem("#{rest[2]} is not a product") if product.nil?
      qs = [quantity(rest[1]), quantity(rest[3])]
    end

    v = coefficients(list, eq.signs)
    out = [notation(eq, v)]
    case cmd
    when "BALANCE"
      out
    when "DELTAH"
      h = list.each_index.sum { |i| -eq.signs[i] * v[i] * @heats[list[i].name] }
      out + ["dH = #{ent(h)} kJ (#{h < 0 ? "exothermic" : h > 0 ? "endothermic" : "thermoneutral"})"]
    when "STOICH"
      d = v[target] * list[target].mass
      out +
        list.each_with_index.map { |s, i|
          "#{s.name} #{dec(qs[0] * v[i] * 1000000 / d, 6)} mol #{dec(qs[0] * v[i] * s.mass / d, 3)} g" +
            gas(s, qs[0] * v[i], d)
        }
    when "YIELD"
      t = qs[0] * v[product] * list[product].mass / (v[target] * list[target].mass)
      out +
        [
          "theoretical #{dec(t, 3)} g",
          "actual #{dec(qs[1], 3)} g",
          t == 0 ? "yield undefined" : "yield #{dec(qs[1] * 10000 / t, 2)}%"
        ]
    when "LIMITING"
      l = (0...r).min_by { |i| Rational(qs[i], v[i] * list[i].mass) }
      d = v[l] * list[l].mass
      out += ["limiting #{list[l].name}", "extent #{dec(qs[l] * 1000000 / d, 6)} mol"]
      (r...list.length).each { |i|
        out << "product #{list[i].name} #{dec(qs[l] * v[i] * list[i].mass / d, 3)} g" + gas(list[i], qs[l] * v[i], d)
      }
      (0...r).each { |i|
        out << "remaining #{list[i].name} #{dec((qs[i] * d - qs[l] * v[i] * list[i].mass) / d, 3)} g" unless i == l
      }
      out
    end

  rescue ChemError => e
    ["error: " + e.message]
  rescue NoCoefficients => e
    [e.message]
  end
end

engine = Chemistry.new
STDIN.gets.to_i.times { puts(engine.execute(STDIN.gets.chomp)) }
