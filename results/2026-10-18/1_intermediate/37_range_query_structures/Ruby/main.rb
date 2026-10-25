
KINDS = %i[SEG LAZY FEN RFEN SPARSE SQRT PERSIST GRID].freeze
OPERATIONS = %i[SUM MIN MAX GCD].freeze
class CommandError < StandardError; end

def combine(op, a, b)
  case op
  when :SUM then a + b
  when :MIN then [a, b].min
  when :MAX then [a, b].max
  when :GCD then a.gcd(b)
  end
end

Span = Data.define(:left, :right) do
  def length = right - left + 1
  def middle = (left + right) / 2
  def leaf? = left == right
  def covers?(other) = left <= other.left && other.right <= right
  def left_child = Span.new(left, middle)
  def right_child = Span.new(middle + 1, right)
end
def whole(n) = Span.new(0, n - 1)
Report = Data.define(:text, :values)
Answer = Data.define(:value, :visited) do
  def report = Report.new("sum=#{value} visited=#{visited}", [value])
end
Aggregate = Data.define(:sum, :min, :max) do
  def self.single(value) = new(value, value, value)
  def merge(other) = Aggregate.new(sum + other.sum, [min, other.min].min, [max, other.max].max)
  def add(value, length) = Aggregate.new(sum + value * length, min + value, max + value)
  def to_s = "sum=#{sum} min=#{min} max=#{max}"
end

class Layout
  attr_reader :spans, :max_node, :count
  def initialize(n)
    @spans = Array.new(4 * n)
    @count = 2 * n - 1
    @max_node = 0
    build(1, whole(n))
    @spans.freeze
  end

  def build(node, span)
    @spans[node] = span
    @max_node = [@max_node, node].max
    return if span.leaf?
    build(2 * node, span.left_child)
    build(2 * node + 1, span.right_child)
  end
end

class Segment
  attr_reader :op, :shape, :tree
  def initialize(values, op)
    @op = op
    @shape = Layout.new(values.length)
    @tree = Array.new(4 * values.length, 0)
    build(1, values)
  end

  def leaf_value(value) = @op == :GCD ? value.abs : value
  def build(node, values)
    span = @shape.spans[node]
    if span.leaf?
      @tree[node] = leaf_value(values[span.left])
    else
      build(2 * node, values)
      build(2 * node + 1, values)
      pull(node)
    end
  end
  def pull(node) = @tree[node] = combine(@op, @tree[2 * node], @tree[2 * node + 1])

  def query_at(node, wanted)
    span = @shape.spans[node]
    return Answer.new(@tree[node], 1) if wanted.covers?(span)
    answer = if wanted.right <= span.middle
               query_at(2 * node, wanted)
             elsif wanted.left > span.middle
               query_at(2 * node + 1, wanted)
             else
               left = query_at(2 * node, wanted)
               right = query_at(2 * node + 1, wanted)
               Answer.new(combine(@op, left.value, right.value), left.visited + right.visited)
             end
    answer.with(visited: answer.visited + 1)
  end
  def query(wanted)
    answer = query_at(1, wanted)
    Report.new("#{@op.downcase}=#{answer.value} visited=#{answer.visited}", [answer.value])
  end
  def update(index, value, node = 1)
    span = @shape.spans[node]
    if span.leaf?
      @tree[node] = leaf_value(value)
      return 1
    end
    visited = update(index, value, index <= span.middle ? 2 * node : 2 * node + 1)
    pull(node)
    visited + 1
  end
  def dump
    rows = ["SEG DUMP #{@op} nodes=#{@shape.count}"]
    @shape.spans.each_with_index do |span, node|
      rows << "NODE #{node} #{span.left} #{span.right} #{@tree[node]}" if span
    end
    rows
  end
end

Counts = Struct.new(:visited, :covered, :pushes) do
  def to_s = "visited=#{visited} covered=#{covered} pushes=#{pushes}"
end
LazyNode = Struct.new(:value, :assign, :add)
LazyAnswer = Data.define(:value, :visited, :pushes)
class Lazy
  attr_reader :shape, :nodes
  def initialize(values)
    @shape = Layout.new(values.length)
    @nodes = Array.new(4 * values.length)
    build(1, values)
  end

  def build(node, values)
    span = @shape.spans[node]
    @nodes[node] = LazyNode.new(nil, nil, 0)
    if span.leaf?
      @nodes[node].value = Aggregate.single(values[span.left])
    else
      build(2 * node, values)
      build(2 * node + 1, values)
      pull(node)
    end
  end
  def pull(node) = @nodes[node].value = @nodes[2 * node].value.merge(@nodes[2 * node + 1].value)
  def apply(node, value, assignment)
    span = @shape.spans[node]
    target = @nodes[node]
    target.value = assignment ? Aggregate.new(value * span.length, value, value) : target.value.add(value, span.length)
    return if span.leaf?
    if assignment
      target.assign = value
      target.add = 0
    else
      target.add += value
    end
  end
  def push(node)
    source = @nodes[node]
    return 0 if source.assign.nil? && source.add.zero?
    (2 * node..2 * node + 1).each do |child|
      apply(child, source.assign, true) unless source.assign.nil?
      apply(child, source.add, false) unless source.add.zero?
    end
    source.assign = nil
    source.add = 0
    1
  end
  def update_at(node, wanted, value, assignment, counts)
    counts.visited += 1
    span = @shape.spans[node]
    if wanted.covers?(span)
      counts.covered += 1
      apply(node, value, assignment)
      return
    end
    counts.pushes += push(node)
    update_at(2 * node, wanted, value, assignment, counts) if wanted.left <= span.middle
    update_at(2 * node + 1, wanted, value, assignment, counts) if wanted.right > span.middle
    pull(node)
  end
  def update(wanted, value, assignment)
    counts = Counts.new(0, 0, 0)
    update_at(1, wanted, value, assignment, counts)
    counts
  end
  def query_at(node, wanted)
    span = @shape.spans[node]
    return LazyAnswer.new(@nodes[node].value, 1, 0) if wanted.covers?(span)
    pushes = push(node)
    answer = if wanted.right <= span.middle
               query_at(2 * node, wanted)
             elsif wanted.left > span.middle
               query_at(2 * node + 1, wanted)
             else
               left = query_at(2 * node, wanted)
               right = query_at(2 * node + 1, wanted)
               LazyAnswer.new(left.value.merge(right.value), left.visited + right.visited, left.pushes + right.pushes)
             end
    answer.with(visited: answer.visited + 1, pushes: answer.pushes + pushes)
  end
  def query(wanted)
    answer = query_at(1, wanted)
    value = answer.value
    Report.new("#{value} visited=#{answer.visited} pushes=#{answer.pushes}", [value.sum, value.min, value.max])
  end
  def dump
    rows = ["LAZY DUMP nodes=#{@shape.count}"]
    @shape.spans.each_with_index do |span, node|
      next unless span
      item = @nodes[node]
      rows << "NODE #{node} #{span.left} #{span.right} #{item.value} assign=#{item.assign.nil? ? '-' : item.assign} add=#{item.add}"
    end
    rows
  end
end

class Bit
  attr_reader :tree
  def initialize(n)
    @tree = Array.new(n + 1, 0)
  end
  def add(position, value)
    visited = 0
    while position < @tree.length
      @tree[position] += value
      visited += 1
      position += position & -position
    end
    visited
  end
  def prefix(position)
    sum = visited = 0
    while position.positive?
      sum += @tree[position]
      visited += 1
      position -= position & -position
    end
    Answer.new(sum, visited)
  end
  def query(span)
    a = prefix(span.right + 1)
    b = prefix(span.left)
    Answer.new(a.value - b.value, a.visited + b.visited)
  end
  def lower(rest)
    n = @tree.length - 1
    position = visited = 0
    step = 1 << (n.bit_length - 1)
    while step.positive?
      if position + step <= n
        value = @tree[position + step]
        visited += 1
        if value < rest
          rest -= value
          position += step
        end
      end
      step /= 2
    end
    Answer.new(position < n ? position : nil, visited)
  end
  def dump(name) = "#{name} #{@tree.drop(1).join(' ')}"
end

class Fenwick
  attr_reader :values, :bit
  def initialize(values)
    @values = values.dup
    @bit = Bit.new(values.length)
    values.each_with_index { |value, i| @bit.add(i + 1, value) }
  end
end

class RangeFenwick
  attr_reader :first, :second
  def initialize(values)
    @first = Bit.new(values.length)
    @second = Bit.new(values.length)
    values.each_with_index do |value, i|
      difference = value - (i.zero? ? 0 : values[i - 1])
      @first.add(i + 1, difference)
      @second.add(i + 1, difference * i)
    end
  end
  def add(span, value)
    visited = @first.add(span.left + 1, value)
    visited += @first.add(span.right + 2, -value)
    visited += @second.add(span.left + 1, value * span.left)
    visited += @second.add(span.right + 2, -value * (span.right + 1))
    visited
  end
  def prefix(position)
    a = @first.prefix(position)
    b = @second.prefix(position)
    Answer.new(position * a.value - b.value, a.visited + b.visited)
  end
  def query(span)
    a = prefix(span.right + 1)
    b = prefix(span.left)
    Answer.new(a.value - b.value, a.visited + b.visited)
  end
end

class Sparse
  attr_reader :values, :minimum, :maximum, :entries
  def initialize(values)
    @values = values.dup.freeze
    @minimum = [(0...values.length).to_a.freeze]
    @maximum = [@minimum.first]
    @entries = values.length
    level = 1
    while (1 << level) <= values.length
      length = values.length - (1 << level) + 1
      half = 1 << (level - 1)
      @minimum << Array.new(length) { |i| select(@minimum[level - 1][i], @minimum[level - 1][i + half], true) }.freeze
      @maximum << Array.new(length) { |i| select(@maximum[level - 1][i], @maximum[level - 1][i + half], false) }.freeze
      @entries += length
      level += 1
    end
    @minimum.freeze
    @maximum.freeze
  end
  def select(a, b, minimum)
    (minimum ? @values[a] <= @values[b] : @values[a] >= @values[b]) ? a : b
  end
  def query(span)
    level = span.length.bit_length - 1
    finish = span.right - (1 << level) + 1
    low = select(@minimum[level][span.left], @minimum[level][finish], true)
    high = select(@maximum[level][span.left], @maximum[level][finish], false)
    Report.new("min=#{@values[low]} minpos=#{low} max=#{@values[high]} maxpos=#{high} level=#{level}", [@values[low], @values[high]])
  end
  def dump
    rows = ["SPARSE DUMP levels=#{@minimum.length}"]
    @minimum.each_index do |level|
      rows << "MIN #{level} #{@minimum[level].join(' ')}"
      rows << "MAX #{level} #{@maximum[level].join(' ')}"
    end
    rows
  end
end

Partition = Data.define(:cells, :blocks) do
  def to_s = "whole=#{blocks.length} cells=#{cells.length}"
end
class Sqrt
  attr_reader :block, :raw, :tags, :sums
  def initialize(values, block)
    @block = block
    @raw = values.dup
    @tags = Array.new((values.length + block - 1) / block, 0)
    @sums = Array.new(@tags.length, 0)
    @raw.each_with_index { |value, i| @sums[i / block] += value }
  end
  def split(span)
    first = span.left / @block
    last = span.right / @block
    cells = (span.left..span.right).select { |i| i / @block == first || i / @block == last }
    Partition.new(cells, ((first + 1)...last).to_a)
  end
  def add(span, value)
    part = split(span)
    part.cells.each { |i| @raw[i] += value; @sums[i / @block] += value }
    part.blocks.each { |b| @tags[b] += value; @sums[b] += value * @block }
    part
  end
  def query(span)
    part = split(span)
    sum = part.cells.sum { |i| @raw[i] + @tags[i / @block] }
    part.blocks.each { |b| sum += @sums[b] }
    Report.new("sum=#{sum} #{part}", [sum])
  end
  def dump
    rows = ["SQRT DUMP block=#{@block} blocks=#{@tags.length}"]
    @tags.each_index do |b|
      first = b * @block
      finish = [(b + 1) * @block, @raw.length].min
      rows << "BLOCK #{b} #{first} #{finish - 1} add=#{@tags[b]} sum=#{@sums[b]} #{@raw[first...finish].join(' ')}"
    end
    rows
  end
end

PersistentNode = Data.define(:value, :left, :right)
ChangedNode = Data.define(:node, :created)
def build_node(values, span)
  return PersistentNode.new(values ? values[span.left] : 0, nil, nil) if span.leaf?
  left = build_node(values, span.left_child)
  right = build_node(values, span.right_child)
  PersistentNode.new(left.value + right.value, left, right)
end
def change_node(source, span, index, value, increment)
  return ChangedNode.new(PersistentNode.new(increment ? source.value + value : value, nil, nil), 1) if span.leaf?
  left = source.left
  right = source.right
  if index <= span.middle
    changed = change_node(left, span.left_child, index, value, increment)
    left = changed.node
  else
    changed = change_node(right, span.right_child, index, value, increment)
    right = changed.node
  end
  ChangedNode.new(PersistentNode.new(left.value + right.value, left, right), changed.created + 1)
end
def query_node(node, span, wanted)
  return Answer.new(node.value, 1) if wanted.covers?(span)
  answer = if wanted.right <= span.middle
             query_node(node.left, span.left_child, wanted)
           elsif wanted.left > span.middle
             query_node(node.right, span.right_child, wanted)
           else
             left = query_node(node.left, span.left_child, wanted)
             right = query_node(node.right, span.right_child, wanted)
             Answer.new(left.value + right.value, left.visited + right.visited)
           end
  answer.with(visited: answer.visited + 1)
end
class Persistent
  attr_reader :roots, :values, :position_nodes, :value_nodes
  def initialize(contents)
    @n = contents.length
    @values = contents.uniq.sort.freeze
    @roots = [build_node(contents, whole(@n))]
    @prefixes = [build_node(nil, whole(@values.length))]
    @position_nodes = 2 * @n - 1
    @value_nodes = 2 * @values.length - 1
    ranks = @values.each_with_index.to_h
    contents.each do |value|
      changed = change_node(@prefixes.last, whole(@values.length), ranks.fetch(value), 1, true)
      @prefixes << changed.node
      @value_nodes += changed.created
    end
    @prefixes.freeze
  end
  def set(version, index, value)
    changed = change_node(@roots[version], whole(@n), index, value, false)
    @roots << changed.node
    @position_nodes += changed.created
    changed.created
  end
  def query(version, span) = query_node(@roots[version], whole(@n), span).report
  def kth(wanted, k)
    u = @prefixes[wanted.right + 1]
    w = @prefixes[wanted.left]
    span = whole(@values.length)
    visited = 1
    until span.leaf?
      count = u.left.value - w.left.value
      if k <= count
        u = u.left; w = w.left; span = span.left_child
      else
        k -= count
        u = u.right; w = w.right; span = span.right_child
      end
      visited += 1
    end
    Answer.new(@values[span.left], visited)
  end
end

class Grid
  attr_reader :height, :width, :tree
  def initialize(height, width, values)
    @height = height
    @width = width
    @tree = Array.new(height + 1) { Array.new(width + 1, 0) }
    values.each_with_index { |value, i| add(i / width, i % width, value) }
  end
  def check_cell(row, column)
    raise CommandError, "BAD CELL #{row} #{column}" if row.negative? || row >= @height || column.negative? || column >= @width
  end
  def add(row, column, value)
    visited = 0
    y = row + 1
    while y <= @height
      x = column + 1
      while x <= @width
        @tree[y][x] += value
        visited += 1
        x += x & -x
      end
      y += y & -y
    end
    visited
  end
  def prefix(row, column)
    sum = visited = 0
    y = row
    while y.positive?
      x = column
      while x.positive?
        sum += @tree[y][x]
        visited += 1
        x -= x & -x
      end
      y -= y & -y
    end
    Answer.new(sum, visited)
  end
  def query(row, column, bottom, right)
    a = prefix(bottom + 1, right + 1)
    b = prefix(row, right + 1)
    c = prefix(bottom + 1, column)
    d = prefix(row, column)
    Answer.new(a.value - b.value - c.value + d.value, a.visited + b.visited + c.visited + d.visited)
  end
  def dump
    ["GRID DUMP rows=#{@height} cols=#{@width}"] + (1..@height).map { |row| "ROW #{row} #{@tree[row].drop(1).join(' ')}" }
  end
end

class Laboratory
  def initialize(values)
    @values = values
    @original = values.dup.freeze
    @structures = {}
  end
  def check_index(index)
    raise CommandError, "BAD INDEX #{index}" if index.negative? || index >= @values.length
  end
  def check_range(span)
    check_index(span.left)
    check_index(span.right)
    raise CommandError, "BAD RANGE #{span.left} #{span.right}" if span.left > span.right
  end
  def check_version(version)
    raise CommandError, "BAD VERSION #{version}" if version.negative? || version >= @structures.fetch(:PERSIST).roots.length
  end
  def array_count = @structures.length - (@structures.key?(:GRID) ? 1 : 0)
  def build(kind, op = :SUM, block = 0)
    tree = case kind
           when :SEG then Segment.new(@values, op)
           when :LAZY then Lazy.new(@values)
           when :FEN then Fenwick.new(@values)
           when :RFEN then RangeFenwick.new(@values)
           when :SPARSE then Sparse.new(@values)
           when :SQRT then Sqrt.new(@values, block)
           when :PERSIST then Persistent.new(@values)
           end
    @structures[kind] = tree
    case kind
    when :SEG then "SEG BUILD #{op} nodes=#{tree.shape.count} maxnode=#{tree.shape.max_node} root=#{tree.tree[1]}"
    when :LAZY then "LAZY BUILD nodes=#{tree.shape.count} #{tree.nodes[1].value}"
    when :FEN, :RFEN then "#{kind} BUILD n=#{@values.length} total=#{@values.sum}"
    when :SPARSE then "SPARSE BUILD levels=#{tree.minimum.length} entries=#{tree.entries}"
    when :SQRT then "SQRT BUILD block=#{block} blocks=#{tree.tags.length}"
    when :PERSIST then "PERSIST BUILD nodes=#{tree.position_nodes} distinct=#{tree.values.length} valuenodes=#{tree.value_nodes}"
    end
  end
  def query(kind, span, version = 0)
    tree = @structures.fetch(kind)
    case kind
    when :FEN then tree.bit.query(span).report
    when :RFEN then tree.query(span).report
    when :PERSIST then tree.query(version, span)
    else tree.query(span)
    end
  end
  def dump(kind)
    tree = @structures.fetch(kind)
    case kind
    when :FEN then ["FEN DUMP n=#{@values.length}", tree.bit.dump('T')]
    when :RFEN then ["RFEN DUMP n=#{@values.length}", tree.first.dump('B1'), tree.second.dump('B2')]
    else tree.dump
    end
  end
  def check(span)
    expected = Aggregate.new(0, @values[span.left], @values[span.left])
    common = 0
    @values[span.left..span.right].each { |value| expected = expected.merge(Aggregate.single(value)); common = common.gcd(value) }
    rows = ["CHECK #{span.left} #{span.right} #{expected} gcd=#{common}"]
    ok = diff = 0
    KINDS.each do |kind|
      next if kind == :GRID || !@structures.key?(kind)
      wanted = case kind
               when :SEG then [{ SUM: expected.sum, MIN: expected.min, MAX: expected.max, GCD: common }.fetch(@structures[kind].op)]
               when :LAZY then [expected.sum, expected.min, expected.max]
               when :SPARSE then [expected.min, expected.max]
               else [expected.sum]
               end
      version = kind == :PERSIST ? @structures[kind].roots.length - 1 : 0
      answer = query(kind, span, version)
      equal = answer.values == wanted
      if equal then ok += 1 else diff += 1 end
      prefix = kind == :PERSIST ? "version=#{version} " : ''
      rows << "#{kind} #{equal ? 'OK' : 'DIFF'} #{prefix}#{answer.text}"
    end
    rows << "RESULT ok=#{ok} diff=#{diff}"
  end
  def mo(queries)
    block = Integer.sqrt(@values.length)
    order = queries.each_index.sort_by do |i|
      span = queries[i]
      b = span.left / block
      [b, b.even? ? span.right : -span.right, i]
    end
    frequencies = Hash.new(0)
    answers = Array.new(queries.length)
    left = right = moves = distinct = 0
    add = lambda do |i|
      value = @values[i]
      distinct += 1 if frequencies[value].zero?
      frequencies[value] += 1
    end
    remove = lambda do |i|
      value = @values[i]
      frequencies[value] -= 1
      distinct -= 1 if frequencies[value].zero?
    end
    order.each do |index|
      span = queries[index]
      finish = span.right + 1
      moves += (span.left - left).abs + (finish - right).abs
      while left > span.left; left -= 1; add.call(left); end
      while right < finish; add.call(right); right += 1; end
      while left < span.left; remove.call(left); left += 1; end
      while right > finish; right -= 1; remove.call(right); end
      answers[index] = distinct
    end
    rows = ["MO queries=#{queries.length} block=#{block} moves=#{moves}", "ORDER #{order.map { |i| i + 1 }.join(' ')}"]
    queries.each_with_index { |span, i| rows << "ANSWER #{i + 1} #{span.left} #{span.right} distinct=#{answers[i]}" }
    rows
  end

  def execute(line)
    words = line.split
    case words[0]
    when 'LOAD'
      removed = array_count
      @values = words.drop(1).map(&:to_i)
      @original = @values.dup.freeze
      @structures.select! { |kind, _| kind == :GRID }
      return ["LOAD n=#{@values.length} removed=#{removed}"]
    when 'RESET'
      @values = @original.dup
      op = @structures[:SEG]&.op || :SUM
      block = @structures[:SQRT]&.block || 0
      rebuilt = array_count
      KINDS.each { |kind| build(kind, op, block) if kind != :GRID && @structures.key?(kind) }
      return ["RESET rebuilt=#{rebuilt}"]
    when 'ARRAY', 'CHECK'
      span = Span.new(words[1].to_i, words[2].to_i)
      check_range(span)
      return check(span) if words[0] == 'CHECK'
      return ["ARRAY #{span.left} #{span.right} #{@values[span.left..span.right].join(' ')}"]
    when 'MO'
      queries = words.drop(1).each_slice(2).map do |left, right|
        span = Span.new(left.to_i, right.to_i)
        check_range(span)
        span
      end
      return mo(queries)
    end
    kind = words[0].to_sym
    action = words[1]
    if action == 'BUILD'
      op = :SUM
      block = 0
      if kind == :SEG
        op = words[2].to_sym
        raise CommandError, "BAD OP #{words[2]}" unless OPERATIONS.include?(op)
      end
      if kind == :SQRT
        block = words.length == 3 ? words[2].to_i : Integer.sqrt(@values.length)
        raise CommandError, "BAD BLOCK #{block}" if block > @values.length
      end
      if kind == :GRID
        height = words[2].to_i; width = words[3].to_i; count = words.length - 4
        raise CommandError, "BAD COUNT #{count} #{height * width}" unless count == height * width
        values = words.drop(4).map(&:to_i)
        @structures[kind] = Grid.new(height, width, values)
        return ["GRID BUILD rows=#{height} cols=#{width} total=#{values.sum}"]
      end
      return [build(kind, op, block)]
    end
    tree = @structures[kind]
    raise CommandError, "NOT BUILT #{kind}" unless tree
    return dump(kind) if action == 'DUMP'
    if kind == :GRID
      row = words[2].to_i; column = words[3].to_i
      tree.check_cell(row, column)
      if action == 'ADD'
        value = words[4].to_i
        return ["GRID ADD #{row} #{column} #{value} visited=#{tree.add(row, column, value)}"]
      end
      bottom = words[4].to_i; right = words[5].to_i
      tree.check_cell(bottom, right)
      raise CommandError, "BAD RECT #{row} #{column} #{bottom} #{right}" if row > bottom || column > right
      return ["GRID SUM #{row} #{column} #{bottom} #{right} #{tree.query(row, column, bottom, right).report.text}"]
    end
    if kind == :PERSIST
      return ["PERSIST NODES versions=#{tree.roots.length} position=#{tree.position_nodes} value=#{tree.value_nodes}"] if action == 'NODES'
      if action == 'KTH'
        span = Span.new(words[2].to_i, words[3].to_i)
        check_range(span)
        k = words[4].to_i
        raise CommandError, "BAD K #{k}" if k < 1 || k > span.length
        answer = tree.kth(span, k)
        return ["PERSIST KTH #{span.left} #{span.right} #{k} value=#{answer.value} visited=#{answer.visited}"]
      end
      version = words[2].to_i
      check_version(version)
      index = words[3].to_i
      if action == 'SET'
        check_index(index)
        value = words[4].to_i
        next_version = tree.roots.length
        created = tree.set(version, index, value)
        return ["PERSIST SET #{version} #{index} #{value} version=#{next_version} created=#{created}"]
      end
      span = Span.new(index, words[4].to_i)
      check_range(span)
      return ["PERSIST QUERY #{version} #{span.left} #{span.right} #{tree.query(version, span).text}"]
    end
    if kind == :FEN && action == 'LOWER'
      tree.values.each_with_index { |value, i| raise CommandError, "NEGATIVE #{i}" if value.negative? }
      k = words[2].to_i
      answer = tree.bit.lower(k)
      return ["FEN LOWER #{k} index=#{answer.value || 'none'} visited=#{answer.visited}"]
    end
    if kind == :SEG && action == 'UPDATE'
      index = words[2].to_i
      check_index(index)
      value = words[3].to_i
      visited = tree.update(index, value)
      @values[index] = value
      return ["SEG UPDATE #{index} #{value} root=#{tree.tree[1]} visited=#{visited}"]
    end
    if kind == :FEN && %w[ADD PREFIX].include?(action)
      index = words[2].to_i
      check_index(index)
      return ["FEN PREFIX #{index} #{tree.bit.prefix(index + 1).report.text}"] if action == 'PREFIX'
      value = words[3].to_i
      @values[index] += value
      tree.values[index] += value
      return ["FEN ADD #{index} #{value} visited=#{tree.bit.add(index + 1, value)}"]
    end
    span = Span.new(words[2].to_i, words[3].to_i)
    check_range(span)
    if %w[ADD ASSIGN].include?(action)
      value = words[4].to_i
      assignment = action == 'ASSIGN'
      details = case kind
                when :LAZY then tree.update(span, value, assignment).to_s
                when :RFEN then "visited=#{tree.add(span, value)}"
                when :SQRT then tree.add(span, value).to_s
                end
      (span.left..span.right).each { |i| @values[i] = assignment ? value : @values[i] + value }
      return ["#{kind} #{action} #{span.left} #{span.right} #{value} #{details}"]
    end
    ["#{kind} #{action} #{span.left} #{span.right} #{query(kind, span).text}"]
  end
end

exit unless STDIN.gets
laboratory = Laboratory.new(STDIN.gets.split.map(&:to_i))
commands = STDIN.gets.to_i
commands.times do
  begin
    rows = laboratory.execute(STDIN.gets)
    STDOUT.puts(rows)
  rescue CommandError => error
    STDOUT.puts("ERROR #{error.message}")
  end
  STDOUT.flush
end
