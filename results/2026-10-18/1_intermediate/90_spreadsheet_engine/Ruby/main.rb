# Trees are immutable arrays; the sheet and each history entry share them safely.
def num(n) = [:n, n]
def txt(s) = [:s, s]
def err(s) = [:e, s]
def ref(c, r, f = 0) = [:r, c, r, f]
def idx(r) = r[2] * 26 + r[1]
def label(i) = (65 + i % 26).chr + (i / 26 + 1).to_s
def inside(r) = (0...26).cover?(r[1]) && (0...99).cover?(r[2])
def area_pair(a, b)
  c, r, f = a[1..]; d, t, g = b[1..]
  ac, ar, bc, br = f & 1, f & 2, g & 1, g & 2
  if c > d then c, d, ac, bc = d, c, bc, ac end
  if r > t then r, t, ar, br = t, r, br, ar end
  [:g, ref(c, r, ac | ar), ref(d, t, bc | br)]
end
def address(s)
  raise 'bad address' unless /\A[A-Z][1-9][0-9]?\z/.match?(s)
  ref(s.getbyte(0) - 65, s[1..].to_i - 1)
end
def area(s)
  parts = s.split(':', -1); raise 'bad address' if parts.size > 2
  a = address(parts[0]); b = parts.size == 1 ? a : address(parts[1]); area_pair(a, b)
end
def cells(g)
  (g[1][2]..g[2][2]).flat_map { |r| (g[1][1]..g[2][1]).map { |c| r * 26 + c } }
end
def contains(g, r) = (g[1][1]..g[2][1]).cover?(r[1]) && (g[1][2]..g[2][2]).cover?(r[2])
LEVELS = [%w[= <> < <= > >=], ['&'], %w[+ -], %w[* /]].freeze
def prec(op) = LEVELS.index { |xs| xs.include?(op) }
class Parser
  def syntax(p) = raise("syntax error at #{p}")
  def initialize(s)
    @tokens = []; i = 1
    while i < s.size
      p = i + 1; ch = s[i]
      if ch == ' ' then i += 1; next end
      if /[0-9]/.match?(ch)
        word = s[i..][/\A[0-9]+/]; syntax(p) if word.size >= 10
        @tokens << [num(word.to_i), p]; i += word.size
      elsif ch == '"'
        j = s.index('"', i + 1); syntax(p) unless j
        @tokens << [txt(s[i + 1...j]), p]; i = j + 1
      elsif /[A-Za-z$]/.match?(ch)
        word = s[i..][/\A[A-Za-z0-9$]+/].upcase; i += word.size
        if (m = /\A(\$?)([A-Z])(\$?)([1-9][0-9]?)\z/.match(word))
          x = ref(m[2].ord - 65, m[4].to_i - 1, (m[1].empty? ? 0 : 1) | (m[3].empty? ? 0 : 2))
        elsif /\A[A-Z][A-Z0-9]*\z/.match?(word)
          x = [s[i..].lstrip.start_with?('(') ? :c : :w, word]
        else syntax(p)
        end
        @tokens << [x, p]
      else
        op = s[i, 2]; op = ch unless %w[<> <= >=].include?(op)
        syntax(p) unless '+-*/&(),:=<>'.include?(ch)
        @tokens << [[:t, op], p]; i += op.size
      end
    end
    @tokens << [[:end], s.size + 1]; @at = 0
  end
  def take(op)
    if @tokens[@at][0] == [:t, op] then @at += 1; true else false end
  end
  def expect(op)
    syntax(@tokens[@at][1]) unless take(op)
  end
  def expression(level = 0)
    return primary if level == 4
    a = expression(level + 1)
    while @tokens[@at][0][0] == :t && LEVELS[level].include?(@tokens[@at][0][1])
      op = @tokens[@at][0][1]; @at += 1; a = [:b, op, a, expression(level + 1)]
    end
    a
  end
  def primary
    return [:u, primary] if take('-')
    x, p = @tokens[@at]; @at += 1
    case x[0]
    when :n, :s, :w then x
    when :r
      return x unless take(':')
      syntax(@tokens[@at][1]) unless @tokens[@at][0][0] == :r
      y = @tokens[@at][0]; @at += 1; area_pair(x, y)
    when :c
      expect('('); args = []
      unless take(')')
        args << expression; args << expression while take(','); expect(')')
      end
      [:f, x[1], args]
    when :t
      syntax(p) unless x[1] == '('
      a = expression; expect(')'); a
    else syntax(p)
    end
  end
  def parse
    tree = expression; syntax(@tokens[@at][1]) unless @tokens[@at][0][0] == :end; tree
  end
end
def canonical(x)
  case x[0]
  when :n then x[1].to_s
  when :s then '"' + x[1] + '"'
  when :w then x[1]
  when :x then '#REF!'
  when :r then (x[3] & 1 == 0 ? '' : '$') + (65 + x[1]).chr + (x[3] & 2 == 0 ? '' : '$') + (x[2] + 1).to_s
  when :g then canonical(x[1]) + ':' + canonical(x[2])
  when :f then x[1] + '(' + x[2].map { |a| canonical(a) }.join(',') + ')'
  when :u then '-' + (x[1][0] == :b ? '(' + canonical(x[1]) + ')' : canonical(x[1]))
  when :b
    a, b = canonical(x[2]), canonical(x[3])
    a = '(' + a + ')' if x[2][0] == :b && prec(x[2][1]) < prec(x[1])
    b = '(' + b + ')' if x[3][0] == :b && prec(x[3][1]) <= prec(x[1])
    a + x[1] + b
  end
end
def display(x) = x.nil? ? '' : x[1].to_s
def notation(x) = x.nil? ? '(empty)' : x[0] == :'=' ? '=' + canonical(x[1]) : x[0] == :s ? '"' + x[1] + '"' : display(x)
def to_number(x) = x.nil? ? num(0) : %i[s g].include?(x[0]) ? err('#VALUE!') : x
def to_string(x) = x.nil? ? txt('') : x[0] == :n ? txt(x[1].to_s) : x[0] == :g ? err('#VALUE!') : x
def quotient(a, b) = (a < 0) == (b < 0) ? a.abs / b.abs : -(a.abs / b.abs)
def rewrite(x, &f)
  return nil unless x
  case x[0]
  when :r, :g then f.call(x)
  when :f then [:f, x[1], x[2].map { |a| rewrite(a, &f) }]
  when :b then [:b, x[1], rewrite(x[2], &f), rewrite(x[3], &f)]
  when :u, :'=' then [x[0], rewrite(x[1], &f)]
  else x
  end
end
def dependencies(x, out = {})
  return out unless x
  case x[0]
  when :r then out[idx(x)] = true
  when :g then cells(x).each { |i| out[i] = true }
  when :f then x[2].each { |a| dependencies(a, out) }
  when :b then dependencies(x[2], out); dependencies(x[3], out)
  when :u, :'=' then dependencies(x[1], out)
  end
  out
end
class Sheet
  def initialize
    @contents = Array.new(2574); @values = @contents.dup; @deps = Array.new(2574) { {} }; @history = []
  end
  def evaluate(x)
    case x[0]
    when :n, :s, :g then x
    when :r then @values[idx(x)]
    when :w then err('#NAME?')
    when :x then err('#REF!')
    when :u
      a = to_number(evaluate(x[1])); a[0] == :e ? a : num(-a[1])
    when :b
      a, b = evaluate(x[2]), evaluate(x[3]); return a if a&.first == :e; return b if b&.first == :e
      op = x[1]
      if prec(op) == 0
        return err('#VALUE!') if a&.first == :g || b&.first == :g
        blank = a&.first == :s || b&.first == :s ? txt('') : num(0); a ||= blank; b ||= blank
        c = a[0] != b[0] ? (a[0] == :n ? -1 : 1) : a[1] <=> b[1]
        return num((case op when '=' then c == 0 when '<>' then c != 0 when '<' then c < 0 when '<=' then c <= 0 when '>' then c > 0 else c >= 0 end) ? 1 : 0)
      end
      a, b = op == '&' ? [to_string(a), to_string(b)] : [to_number(a), to_number(b)]
      return a if a[0] == :e; return b if b[0] == :e
      case op
      when '&' then txt(a[1] + b[1])
      when '+' then num(a[1] + b[1])
      when '-' then num(a[1] - b[1])
      when '*' then num(a[1] * b[1])
      else b[1] == 0 ? err('#DIV/0!') : num(quotient(a[1], b[1]))
      end
    when :f then call(x[1], x[2])
    end
  end
  def call(name, args)
    if %w[SUM MIN MAX COUNT AVERAGE AND OR CONCAT].include?(name)
      return err('#VALUE!') if args.empty?
      items = args.flat_map { |a| v = evaluate(a); v&.first == :g ? cells(v).map { |i| @values[i] } : [v] }
      ns = items.select { |a| a&.first == :n }.map { |a| a[1] }
      return num(ns.size) if name == 'COUNT'
      error = items.find { |a| a&.first == :e }; return error if error
      case name
      when 'SUM' then num(ns.sum)
      when 'MIN' then num(ns.min || 0)
      when 'MAX' then num(ns.max || 0)
      when 'AVERAGE' then ns.empty? ? err('#DIV/0!') : num(quotient(ns.sum, ns.size))
      when 'AND' then ns.empty? ? err('#VALUE!') : num(ns.all? { |n| n != 0 } ? 1 : 0)
      when 'OR' then ns.empty? ? err('#VALUE!') : num(ns.any? { |n| n != 0 } ? 1 : 0)
      else txt(items.map { |a| to_string(a)[1] }.join)
      end
    elsif name == 'IF'
      return err('#VALUE!') unless [2, 3].include?(args.size)
      c = to_number(evaluate(args[0])); return c if c[0] == :e
      c[1] != 0 ? evaluate(args[1]) : args.size == 3 ? evaluate(args[2]) : num(0)
    elsif %w[ABS NOT LEN].include?(name)
      return err('#VALUE!') unless args.size == 1
      v = evaluate(args[0]); v = name == 'LEN' ? to_string(v) : to_number(v); return v if v[0] == :e
      num(name == 'LEN' ? v[1].size : name == 'ABS' ? v[1].abs : v[1] == 0 ? 1 : 0)
    else err('#NAME?')
    end
  end
  def recalculate
    @deps = @contents.map { |x| x&.first == :'=' ? dependencies(x[1]) : {} }
    @values = @contents.map { |x| x&.first == :'=' ? nil : x }
    indices = {}; low = {}; stack = []; on = {}; cyclic = {}
    visit = lambda do |i|
      indices[i] = low[i] = indices.size; stack << i; on[i] = true
      @deps[i].each_key do |j|
        next unless @contents[j]&.first == :'='
        if !indices.key?(j) then visit.call(j); low[i] = [low[i], low[j]].min
        elsif on[j] then low[i] = [low[i], indices[j]].min end
      end
      if low[i] == indices[i]
        part = []; loop { j = stack.pop; on.delete(j); part << j; break if j == i }
        part.each { |j| cyclic[j] = true } if part.size > 1 || @deps[i].key?(i)
      end
    end
    @contents.each_index { |i| visit.call(i) if @contents[i]&.first == :'=' && !indices.key?(i) }
    done = {}; calculate = lambda do |i|
      return unless @contents[i]&.first == :'=' && !done[i]
      done[i] = true
      if cyclic[i] then @values[i] = err('#CYCLE!'); return end
      @deps[i].each_key { |j| calculate.call(j) }; v = evaluate(@contents[i][1]); @values[i] = v.nil? ? num(0) : v[0] == :g ? err('#VALUE!') : v
    end
    @contents.each_index { |i| calculate.call(i) }
  end
  def replace(next_contents)
    old = @values; @contents = next_contents; recalculate
    old.each_index.count { |i| old[i] != @values[i] }
  end
  def describe(i) = "#{label(i)}: #{notation(@contents[i])} -> #{notation(@values[i])}"
  def execute(line)
    name, rest = line.split(' ', 2)
    case name
    when 'SHOW' then return [describe(idx(address(rest)))]
    when 'LIST'
      out = @contents.each_index.filter_map { |i| describe(i) if @contents[i] }; return out.empty? ? ['(no cells)'] : out
    when 'DEPS'
      i = idx(address(rest)); format = ->(xs) { xs.empty? ? 'none' : xs.sort.map { |j| label(j) }.join(',') }
      return ["#{rest}: precedents=#{format.call(@deps[i].keys)} dependents=#{format.call(@deps.each_index.select { |j| @deps[j].key?(i) })}"]
    when 'PRINT'
      g = area(rest); rs = g[1][2]..g[2][2]; cs = g[1][1]..g[2][1]; rw = (g[2][2] + 1).to_s.size
      ws = cs.map { |c| [1, *rs.map { |r| display(@values[r * 26 + c]).size }].max }
      sep = '+' + '-' * rw + '+' + ws.map { |w| '-' * w + '+' }.join
      out = [sep, '|' + ' ' * rw + '|' + cs.each_with_index.map { |c,j| (65+c).chr.ljust(ws[j]) + '|' }.join, sep]
      rs.each { |r| out << '|' + (r+1).to_s.rjust(rw) + '|' + cs.each_with_index.map { |c,j| v=@values[r*26+c]; (v&.first == :n ? display(v).rjust(ws[j]) : display(v).ljust(ws[j])) + '|' }.join }
      return out << sep
    when 'UNDO'
      raise 'nothing to undo' if @history.empty?
      command, old = @history.pop; return ["UNDO #{command} changed=#{replace(old)}"]
    end
    next_contents = @contents.dup; target = nil
    case name
    when 'SET'
      a, s = rest.split(' ', 2); target = idx(address(a))
      next_contents[target] = if s.start_with?('=') then [:'=', Parser.new(s).parse]
      elsif /\A"[^"]*"\z/.match?(s) then txt(s[1...-1])
      elsif /\A(?:0|-?[1-9][0-9]{0,8})\z/.match?(s) then num(s.to_i)
      else raise 'bad value' end
    when 'CLEAR' then cells(area(rest)).each { |i| next_contents[i] = nil }
    when 'COPY', 'MOVE'
      a,b = rest.split(' '); source = area(a); dest = address(b); dc = dest[1]-source[1][1]; dr = dest[2]-source[1][2]
      shift = ->(r,rel) { ref(r[1]+(rel && r[3]&1 != 0 ? 0 : dc), r[2]+(rel && r[3]&2 != 0 ? 0 : dr), r[3]) }
      destination = area_pair(shift.call(source[1],false),shift.call(source[2],false)); raise 'out of grid' unless inside(destination[1]) && inside(destination[2])
      transform = lambda do |x|
        if x[0] == :r
          if name == 'COPY' then r=shift.call(x,true); inside(r) ? r : [:x]
          else contains(source,x) ? shift.call(x,false) : contains(destination,x) ? [:x] : x end
        elsif name == 'MOVE' && !(contains(source,x[1]) && contains(source,x[2])) then x
        else
          a=shift.call(x[1],name=='COPY'); b=shift.call(x[2],name=='COPY'); inside(a)&&inside(b) ? area_pair(a,b) : [:x]
        end
      end
      next_contents.map! { |x| rewrite(x,&transform) } if name == 'MOVE'
      moving = cells(source).map { |i| [i, name == 'COPY' ? rewrite(@contents[i],&transform) : next_contents[i]] }
      moving.each { |i,_| next_contents[i]=nil } if name == 'MOVE'
      moving.each { |i,x| next_contents[i+dr*26+dc]=x }
    when 'INSERTROW','DELETEROW','INSERTCOL','DELETECOL'
      row=name.end_with?('ROW'); insert=name.start_with?('INSERT'); raise 'bad address' unless (row ? /\A[1-9][0-9]?\z/ : /\A[A-Z]\z/).match?(rest)
      at=row ? rest.to_i-1 : rest.ord-65; limit=row ? 99 : 26; axis=->(x) { x[row ? 2 : 1] }; change=->(x,v) { row ? ref(x[1],v,x[3]) : ref(v,x[2],x[3]) }
      raise "last #{row ? 'row' : 'column'} not empty" if insert && @contents.each_index.any? { |i| @contents[i] && (row ? i/26 : i%26)==limit-1 }
      transform=lambda do |x|
        if x[0]==:r
          v=axis.call(x)
          if !insert && v==at then [:x]
          else n=v+(insert ? (v>=at ? 1 : 0) : (v>at ? -1 : 0)); n>=limit ? [:x] : change.call(x,n) end
        else
          a=axis.call(x[1]); b=axis.call(x[2]); u=a+(insert ? (a>=at ? 1 : 0) : (a>at ? -1 : 0)); v=b+(insert ? (b>=at ? 1 : 0) : (b>=at ? -1 : 0))
          (!insert && a==at && b==at)||v>=limit ? [:x] : area_pair(change.call(x[1],u),change.call(x[2],v))
        end
      end
      next_contents=Array.new(2574)
      @contents.each_index do |i|
        next unless @contents[i]; r=ref(i%26,i/26); v=axis.call(r); next if !insert && v==at
        t=change.call(r,v+(insert ? (v>=at ? 1 : 0) : (v>at ? -1 : 0))); next_contents[idx(t)]=rewrite(@contents[i],&transform)
      end
    else raise 'unknown command'
    end
    @history << [name,@contents]; changed=replace(next_contents)
    [name+(name=='SET' ? " #{label(target)}=#{notation(@values[target])}" : '')+" changed=#{changed}"]
  end
end
n = STDIN.gets.to_i; sheet = Sheet.new
n.times do
  begin
    puts sheet.execute(STDIN.gets.chomp)
  rescue RuntimeError => e
    puts "ERROR #{e.message}"
  end
end
