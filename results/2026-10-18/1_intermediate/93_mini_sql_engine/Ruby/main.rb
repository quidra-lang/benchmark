RESERVED = %w[
  SELECT
  DISTINCT
  FROM
  AS
  JOIN
  INNER
  LEFT
  OUTER
  ON
  WHERE
  GROUP
  BY
  HAVING
  ORDER
  ASC
  DESC
  LIMIT
  OFFSET
  INSERT
  INTO
  VALUES
  UPDATE
  SET
  DELETE
  CREATE
  TABLE
  DROP
  PRIMARY
  KEY
  NOT
  NULL
  INT
  TEXT
  AND
  OR
  IS
  IN
  BETWEEN
  LIKE
  COUNT
  SUM
  MIN
  MAX
  AVG
  EXIT
]
  .freeze
AGGREGATES = %w[COUNT SUM MIN MAX AVG].freeze
COMPARISONS = %w[= <> != < <= > >=].freeze
Token = Struct.new(:kind, :value, :text)
Expr = Struct.new(:kind, :op, :args, :value, :table, :column, :text, :index, :distinct, :negated, keyword_init: true)
Column = Struct.new(:name, :type, :not_null, :primary)
Table = Struct.new(:name, :columns, :key, :rows) do
  def column(name) = columns.index { |c| c.name == name }
end

def statements(source)
  source
    .scan(/'[^']*'|--[^\n]*|[^;'\-]+|-(?!-)|;/)
    .each_with_object([""]) do |part, a|
      a[-1] << part
      a << "" if part == ";"
    end
    .reject { |s| !s.end_with?(";") }
end

def tokenize(text)
  tokens = []
  i = 0
  while i < text.length
    rest = text[i..]
    if (m = /\A[ \n]+|\A--[^\n]*/.match(rest))
      i += m[0].length
      next
    elsif (m = /\A'([^']*)'/.match(rest))
      kind, value = :string, m[1]
    elsif (m = /\A[0-9]+/.match(rest))
      kind, value = :integer, m[0].to_i
    elsif (m = /\A[A-Za-z_][A-Za-z0-9_]*/.match(rest))
      kind = RESERVED.include?(m[0].upcase) ? :keyword : :name
      value = kind == :keyword ? m[0].upcase : m[0]
    elsif (m = /\A(?:<>|!=|<=|>=|\|\||[(),.;*\/%+\-=<>])/.match(rest))
      kind, value = :symbol, m[0]
    else
      raise "unexpected character '#{text[i]}'"
    end

    tokens << Token.new(kind, value, m[0])
    i += m[0].length
  end

  tokens
end

class Parser
  def initialize(tokens)
    @tokens, @i = tokens, 0
  end

  def peek = @tokens[@i]
  def take
    t = peek
    @i += 1
    t
  end

  def at?(*words) = [:keyword, :symbol].include?(peek.kind) && words.include?(peek.value)
  def accept(word)
    return false unless at?(word)
    @i += 1
    true
  end

  def syntax = raise "syntax error at '#{peek.text}'"
  def expect(word)
    syntax unless accept(word)
  end

  def kind(k)
    syntax unless peek.kind == k
    take.value
  end

  def comma
    a = [yield]
    a << yield while accept(",")
    a
  end

  def parens
    expect("(")
    a = comma { yield }
    expect(")")
    a
  end

  def alias_name
    return kind(:name) if accept("AS")
    peek.kind == :name ? take.value : nil
  end

  def clause(word) = accept(word) ? expression : nil
  def table_ref
    name = kind(:name)
    [name, alias_name || name]
  end

  def reference
    name = kind(:name)
    if accept(".")
      col = kind(:name)
      Expr.new(kind: :ref, table: name, column: col, text: "#{name}.#{col}")
    else
      Expr.new(kind: :ref, column: name, text: name)
    end
  end

  def expression = binary(%w[OR], :and_expr)
  def and_expr = binary(%w[AND], :not_expr)
  def not_expr = accept("NOT") ? Expr.new(kind: :unary, op: "NOT", args: [not_expr]) : comparison
  def binary(ops, method)
    e = send(method)
    while at?(*ops)
      op = take.value
      e = Expr.new(kind: :binary, op: op, args: [e, send(method)])
    end

    e
  end

  def comparison
    e = additive
    if at?(*COMPARISONS)
      op = take.value
      return Expr.new(kind: :binary, op: op, args: [e, additive])
    end

    if accept("IS")
      neg = accept("NOT")
      expect("NULL")
      return Expr.new(kind: :isnull, args: [e], negated: neg)
    end

    neg = accept("NOT")
    if accept("IN")
      return Expr.new(kind: :in, args: [e, *parens { expression }], negated: neg)
    elsif accept("BETWEEN")
      low = additive
      expect("AND")
      return Expr.new(kind: :between, args: [e, low, additive], negated: neg)
    elsif accept("LIKE")
      return Expr.new(kind: :like, args: [e, additive], negated: neg)
    end

    syntax if neg
    e
  end

  def additive = binary(%w[+ - ||], :multiplicative)
  def multiplicative = binary(%w[* / %], :unary)
  def unary = accept("-") ? Expr.new(kind: :unary, op: "-", args: [unary]) : primary
  def primary
    return Expr.new(kind: :literal, value: take.value) if [:integer, :string].include?(peek.kind)
    return Expr.new(kind: :literal, value: nil) if accept("NULL")
    return reference if peek.kind == :name
    if at?(*AGGREGATES)
      name = take.value
      expect("(")
      if name == "COUNT" && accept("*")
        args, distinct = [], false
      else
        distinct = accept("DISTINCT")
        args = [expression]
      end

      expect(")")
      return Expr.new(kind: :aggregate, op: name, args: args, distinct: distinct)
    end

    if accept("(")
      e = expression
      expect(")")
      return e
    end

    syntax
  end

  def expr_tokens
    start = @i
    e = expression
    [e, @tokens[start...@i]]
  end

  def select_item
    e, tokens = expr_tokens
    name = alias_name
    heading = name ||
      (e.kind == :ref && tokens[0].kind == :name ? e.column : tokens
        .each_with_index
        .map { |t, i| (i > 0 && t.kind != :symbol && tokens[i - 1].kind != :symbol ? " " : "") + t.text }
        .join)
    {expr: e, alias: name, heading: heading}
  end

  def order_item
    e, tokens = expr_tokens
    desc = accept("DESC")
    accept("ASC") unless desc
    {expr: e, tokens: tokens, desc: desc}
  end

  def select_query
    q = {kind: :select, distinct: accept("DISTINCT")}
    q[:items] = accept("*") ? nil : comma { select_item }
    expect("FROM")
    q[:source] = table_ref
    q[:joins] = []
    while at?("JOIN", "INNER", "LEFT")
      left = accept("LEFT")
      left ? accept("OUTER") : accept("INNER")
      expect("JOIN")
      ref = table_ref
      expect("ON")
      q[:joins] << {table: ref, left: left, condition: expression}
    end

    q[:where] = clause("WHERE")
    q[:group] = []
    if accept("GROUP")
      expect("BY")
      q[:group] = comma { reference }
    end

    q[:having] = clause("HAVING")
    q[:order] = []
    if accept("ORDER")
      expect("BY")
      q[:order] = comma { order_item }
    end

    if accept("LIMIT")
      q[:limit] = kind(:integer)
      q[:offset] = kind(:integer) if accept("OFFSET")
    end

    q
  end

  def statement
    result = nil
    if accept("CREATE")
      expect("TABLE")
      name = kind(:name)
      columns = parens do
        n = kind(:name)
        syntax unless at?("INT", "TEXT")
        type = take.value
        pk = 0
        nn = false
        loop do
          if accept("PRIMARY")
            expect("KEY")
            pk += 1
          elsif accept("NOT")
            expect("NULL")
            nn = true
          else
            break
          end
        end

        Column.new(n, type, nn, pk)
      end

      result = {kind: :create, name: name, columns: columns}
    elsif accept("DROP")
      expect("TABLE")
      result = {kind: :drop, name: kind(:name)}
    elsif accept("INSERT")
      expect("INTO")
      name = kind(:name)
      cols = at?("(") ? parens { kind(:name) } : nil
      expect("VALUES")
      result = {kind: :insert, name: name, columns: cols, tuples: comma { parens { expression } }}
    elsif accept("UPDATE")
      name = kind(:name)
      expect("SET")
      assignments = comma {
        n = kind(:name)
        expect("=")
        [n, expression]
      }
      result = {kind: :update, name: name, assignments: assignments, where: clause("WHERE")}
    elsif accept("DELETE")
      expect("FROM")
      result = {kind: :delete, name: kind(:name), where: clause("WHERE")}
    elsif accept("SELECT")
      result = select_query
    elsif accept("EXIT")
      result = {kind: :exit}
    end

    expect(";")
    result
  end
end

class Scope
  attr_reader :entries, :width
  def initialize
    @entries, @width = [], 0
  end

  def add(name, table)
    raise "duplicate table name #{name}" if @entries.any? { |entry| entry[0] == name }
    @entries << [name, table, @width]
    @width += table.columns.length
  end

  def resolve(ref)
    entries = ref.table ? @entries.select { |entry| entry[0] == ref.table } : @entries
    raise "unknown table #{ref.table}" if ref.table && entries.empty?
    matches = entries.filter_map do |_, table, offset|
      i = table.column(ref.column)
      [offset + i, table.columns[i].type] unless i.nil?
    end

    raise "unknown column #{ref.text}" if matches.empty?
    raise "ambiguous column #{ref.column}" if matches.length > 1
    ref.index = matches[0][0]
    matches[0][1]
  end
end

def compatible(a, b) = a == b || a == "NULL" || b == "NULL"
def require_type(a, b, op)
  raise "type mismatch for #{op}" unless compatible(a, b)
end

def check(e, scope, aggregates = false, grouped = nil, inside = false)
  case e.kind
  when :literal
    e.value.nil? ? "NULL" : e.value.is_a?(Integer) ? "INT" : "TEXT"
  when :ref
    type = scope.resolve(e)
    raise "column #{e.text} is not grouped" if grouped && !inside && !grouped.include?(e.index)
    type
  when :aggregate
    raise "misuse of aggregate #{e.op}" if !aggregates || inside
    return "INT" if e.args.empty?
    type = check(e.args[0], scope, aggregates, grouped, true)
    require_type(type, "INT", e.op) if %w[SUM AVG].include?(e.op)
    %w[MIN MAX].include?(e.op) ? type : "INT"
  else
    types = e.args.map { |arg| check(arg, scope, aggregates, grouped, inside) }
    case e.kind
    when :unary
      require_type(types[0], "INT", e.op)
      "INT"
    when :binary
      if COMPARISONS.include?(e.op)
        require_type(types[0], types[1], e.op)
        "INT"
      else
        type = e.op == "||" ? "TEXT" : "INT"
        types.each { |t| require_type(t, type, e.op) }
        type
      end

    when :isnull
      "INT"
    when :in, :between
      types.drop(1).each { |t| require_type(t, types[0], e.kind == :in ? "IN" : "BETWEEN") }
      "INT"
    when :like
      types.each { |t| require_type(t, "TEXT", "LIKE") }
      "INT"
    end
  end
end

def condition_check(e, scope, clause, aggregates = false, grouped = nil)
  require_type(check(e, scope, aggregates, grouped), "INT", clause) if e
end

def has_aggregate(e) = e.kind == :aggregate || (e.args || []).any? { |a| has_aggregate(a) }
def true_value(v) = !v.nil? && v != 0
def logical_not(v) = v.nil? ? nil : v == 0 ? 1 : 0
def quotient(a, b) = (a < 0) == (b < 0) ? a.abs / b.abs : -(a.abs / b.abs)
def operate(op, a, b)
  return a == 0 || b == 0 ? 0 : a.nil? || b.nil? ? nil : 1 if op == "AND"
  return true_value(a) || true_value(b) ? 1 : a.nil? || b.nil? ? nil : 0 if op == "OR"
  return nil if a.nil? || b.nil?
  case op
  when "+", "||"
    a + b
  when "-"
    a - b
  when "*"
    a * b
  when "/"
    b == 0 ? nil : quotient(a, b)
  when "%"
    b == 0 ? nil : a - b * quotient(a, b)
  when "="
    a == b ? 1 : 0
  when "<>", "!="
    a != b ? 1 : 0
  else
    a.public_send(op, b) ? 1 : 0
  end
end

def like(text, pattern)
  dp = [true] + [false] * text.length
  pattern.each_char do |char|
    if char == "%"
      (1..text.length).each { |i| dp[i] ||= dp[i - 1] }
    else
      text.length.downto(1) { |i| dp[i] = dp[i - 1] && (char == "_" || char == text[i - 1]) }
      dp[0] = false
    end
  end

  dp[-1] ? 1 : 0
end

def evaluate(e, row, group = nil)
  return e.value if e.kind == :literal
  return row[e.index] if e.kind == :ref
  if e.kind == :aggregate
    return group.length if e.args.empty?
    values = group.map { |r| evaluate(e.args[0], r) }.compact
    values = values.uniq if e.distinct
    return values.length if e.op == "COUNT"
    return nil if values.empty?
    return case e.op
    when "SUM"
      values.sum
    when "MIN"
      values.min
    when "MAX"
      values.max
    when "AVG"
      quotient(values.sum, values.length)
    end
  end

  a = e.args.map { |arg| evaluate(arg, row, group) }
  case e.kind
  when :unary
    e.op == "NOT" ? logical_not(a[0]) : a[0].nil? ? nil : -a[0]
  when :binary
    operate(e.op, *a)
  when :isnull
    a[0].nil? != e.negated ? 1 : 0
  else
    result = case e.kind
    when :in
      a[0].nil? ? nil : a.drop(1).include?(a[0]) ? 1 : a.drop(1).include?(nil) ? nil : 0
    when :between
      operate("AND", operate(">=", a[0], a[1]), operate("<=", a[0], a[2]))
    when :like
      a.any?(&:nil?) ? nil : like(*a)
    end

    e.negated ? logical_not(result) : result
  end
end

def satisfies(e, row, group = nil) = e.nil? || true_value(evaluate(e, row, group))
def row_count(n) = "#{n} #{n == 1 ? "row" : "rows"}"
def value_text(v) = v.nil? ? "NULL" : v.to_s

def print_table(items, types, rows)
  headings = items.map { |i| i[:heading] }
  cells = rows.map { |r| r.map { |v| value_text(v) } }
  widths = headings.each_index.map { |i| ([headings[i].length] + cells.map { |r| r[i].length }).max }
  separator = "+" + widths.map { |w| "-" * (w + 2) + "+" }.join
  puts(separator)
  puts("|" + headings.each_index.map { |i| " #{headings[i].ljust(widths[i])} |" }.join)
  puts(separator)
  cells.each { |r|
    puts("|" + r.each_index.map { |i| " #{types[i] == "INT" ? r[i].rjust(widths[i]) : r[i].ljust(widths[i])} |" }.join)
  }
  puts(separator)
  puts("(#{row_count(rows.length)})")
end

class Database
  def initialize = @tables = {}
  def table(name) = @tables.fetch(name) { raise "unknown table #{name}" }
  def indices(t, names)
    result = []
    names.each do |n|
      i = t.column(n)
      raise "unknown column #{n}" if i.nil?
      raise "duplicate column #{n}" if result.include?(i)
      result << i
    end

    result
  end

  def constraints(t, rows, checked)
    checked.each do |i|
      t.columns.each_with_index { |c, j| raise "NULL value in column #{c.name}" if c.not_null && rows[i][j].nil? }
      if t.key && rows.count { |r| r[t.key] == rows[i][t.key] } > 1
        raise "duplicate primary key #{value_text(rows[i][t.key])}"
      end
    end
  end

  def execute(s)
    case s[:kind]
    when :create
      name = s[:name]
      raise "table #{name} already exists" if @tables.key?(name)
      columns = []
      key = nil
      primary = 0
      s[:columns].each do |c|
        raise "duplicate column #{c.name}" if columns.any? { |p| p.name == c.name }
        primary += c.primary
        raise "multiple primary keys" if primary >= 2
        key = columns.length if c.primary > 0
        c.not_null ||= c.primary > 0
        columns << c
      end

      @tables[name] = Table.new(name, columns, key, [])
      puts("Table #{name} created.")
    when :drop
      table(s[:name])
      @tables.delete(s[:name])
      puts("Table #{s[:name]} dropped.")
    when :insert
      t = table(s[:name])
      targets = s[:columns] ? indices(t, s[:columns]) : (0...t.columns.length).to_a
      s[:tuples].each do |tuple|
        raise "expected #{targets.length} values, got #{tuple.length}" if tuple.length != targets.length
        tuple.zip(targets).each { |e, i|
          require_type(check(e, Scope.new), t.columns[i].type, "column #{t.columns[i].name}")
        }
      end

      additions = s[:tuples].map do |tuple|
        row = [nil] * t.columns.length
        tuple.zip(targets).each { |e, i| row[i] = evaluate(e, []) }
        row
      end

      rows = t.rows + additions
      constraints(t, rows, (t.rows.length...rows.length).to_a)
      t.rows = rows
      puts("#{row_count(additions.length)} inserted.")
    when :update, :delete
      t = table(s[:name])
      scope = Scope.new
      scope.add(t.name, t)
      if s[:kind] == :update
        targets = indices(t, s[:assignments].map(&:first))
        s[:assignments].zip(targets).each { |(_, e), i|
          require_type(check(e, scope), t.columns[i].type, "column #{t.columns[i].name}")
        }
        condition_check(s[:where], scope, "WHERE")
        rows = t.rows.dup
        changed = []
        t.rows.each_with_index do |row, i|
          next unless satisfies(s[:where], row)
          replacement = row.dup
          s[:assignments].zip(targets).each { |(_, e), j| replacement[j] = evaluate(e, row) }
          rows[i] = replacement
          changed << i
        end

        constraints(t, rows, changed)
        t.rows = rows
        puts("#{row_count(changed.length)} updated.")
      else
        condition_check(s[:where], scope, "WHERE")
        rows = t.rows.reject { |r| satisfies(s[:where], r) }
        count = t.rows.length - rows.length
        t.rows = rows
        puts("#{row_count(count)} deleted.")
      end

    when :select
      select(s)
    end
  end

  def select(q)
    scope = Scope.new
    scope.add(q[:source][1], table(q[:source][0]))
    q[:joins].each { |j|
      scope.add(j[:table][1], table(j[:table][0]))
      condition_check(j[:condition], scope, "ON")
    }
    condition_check(q[:where], scope, "WHERE")
    q[:group].each { |ref| scope.resolve(ref) }
    items = q[:items] ||
      scope.entries.flat_map { |name, t, _|
        t.columns.map { |c| {expr: Expr.new(kind: :ref, table: name, column: c.name, text: c.name), heading: c.name} }
      }
    aggregate = !q[:group].empty? || q[:having] || (items + q[:order]).any? { |i| has_aggregate(i[:expr]) }
    grouped = aggregate ? q[:group].map(&:index) : nil
    types = items.map { |i| check(i[:expr], scope, true, grouped) }
    condition_check(q[:having], scope, "HAVING", true, grouped)
    keys = q[:order].map do |o|
      ts = o[:tokens]
      if ts.length == 1 && ts[0].kind == :integer
        k = ts[0].value
        raise "ORDER BY position #{k} is out of range" unless k >= 1 && k <= items.length
        items[k - 1][:expr]
      elsif ts.length == 1 && ts[0].kind == :name && (item = items.find { |i| i[:alias] == ts[0].value })
        item[:expr]
      else
        check(o[:expr], scope, true, grouped)
        o[:expr]
      end
    end

    rows = scope.entries[0][1].rows
    q[:joins].zip(scope.entries.drop(1)).each do |join, (_, t, _)|
      rows = rows.flat_map do |left|
        joined = t.rows.filter_map { |right|
          combined = left + right
          combined if satisfies(join[:condition], combined)
        }
        joined.empty? && join[:left] ? [left + [nil] * t.columns.length] : joined
      end
    end

    rows = rows.select { |r| satisfies(q[:where], r) }
    sources = if aggregate
      groups = q[:group].empty? ? [rows] : rows.group_by { |r| grouped.map { |i| r[i] } }.values
      groups.select { |g| satisfies(q[:having], g[0], g) }.map { |g| [g[0], g] }
    else
      rows.map { |r| [r, nil] }
    end

    results = sources.each_with_index.map { |(r, g), i|
      [items.map { |it| evaluate(it[:expr], r, g) }, keys.map { |key| evaluate(key, r, g) }, i]
    }
    results.sort! do |a, b|
      comparison = 0
      keys.each_index do |i|
        x, y = a[1][i], b[1][i]
        comparison = x.nil? ? y.nil? ? 0 : -1 : y.nil? ? 1 : x <=> y
        comparison = -comparison if q[:order][i][:desc]
        break unless comparison == 0
      end

      comparison == 0 ? a[2] <=> b[2] : comparison
    end

    results = results.uniq { |r| r[0] } if q[:distinct]
    results = results.drop(q[:offset] || 0)
    results = results.take(q[:limit]) if q.key?(:limit)
    print_table(items, types, results.map(&:first))
  end
end

database = Database.new
statements(STDIN.read).each do |text|
  begin
    s = Parser.new(tokenize(text)).statement
    break if s && s[:kind] == :exit
    database.execute(s) if s
  rescue RuntimeError => error
    puts("ERROR: #{error.message}")
  end
end
