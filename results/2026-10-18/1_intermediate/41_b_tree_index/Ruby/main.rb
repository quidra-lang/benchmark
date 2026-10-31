
Entry = Data.define(:key, :value) do
  def initialize(key:, value:)
    super(key: key, value: value.freeze)
  end

  def to_s = "#{key}=#{value}"
end

Search = Data.define(:page, :position, :path)
Changes = Data.define(:writes, :frees)
Scan = Data.define(:entries, :visited)
class CommandError < StandardError; end

class Node
  attr_reader :entries, :children

  def initialize(entries = [], children = [])
    @entries, @children = entries, children
  end

  def initialize_copy(other)
    super
    @entries = other.entries.dup
    @children = other.children.dup
  end

  def leaf? = @children.empty?
  def position(key) = @entries.index { |entry| key <= entry.key } || @entries.length
  def to_s = "[#{@entries.map(&:key).join(' ')}]"
  def same_content?(other) = @entries == other.entries && @children == other.children
end

class Trace
  attr_reader :lines, :cases

  def initialize(enabled)
    @enabled = enabled
    @lines, @cases = [], []
  end

  def emit(template, *args)
    @lines << format(template, *args) if @enabled
  end
end

class Tree
  attr_reader :degree, :pages
  attr_accessor :root, :splits, :merges, :borrows

  def initialize(degree)
    @degree = degree
    @root = @splits = @merges = @borrows = 0
    @pages = { 0 => Node.new }
  end

  def initialize_copy(other)
    super
    @pages = other.pages.transform_values(&:dup)
  end

  def allocate(node)
    page = 0
    page += 1 while @pages.key?(page)
    @pages[page] = node
    page
  end

  def entries
    result = []
    collect(@root, result)
    result
  end

  def collect(page, result)
    node = @pages.fetch(page)
    (0..node.entries.length).each do |j|
      collect(node.children[j], result) unless node.leaf?
      result << node.entries[j] if j < node.entries.length
    end
  end

  def search(key)
    page, path = @root, []
    loop do
      node = @pages.fetch(page)
      path << node.to_s
      position = node.position(key)
      return Search.new(page, position, path) if node.entries[position]&.key == key
      return Search.new(nil, position, path) if node.leaf?
      page = node.children[position]
    end
  end

  def check_node(page, location, depth, low, high, reference)
    node = @pages.fetch(page)
    count = node.entries.length
    minimum = page == @root ? (node.leaf? ? 0 : 1) : @degree - 1
    maximum = 2 * @degree - 1
    details = "at=#{location} node=#{node}"
    return "COUNT #{details} keys=#{count} allowed=#{minimum}..#{maximum}" unless (minimum..maximum).cover?(count)
    node.entries.each_cons(2) do |left, right|
      return "ORDER #{details} #{left.key}>=#{right.key}" if left.key >= right.key
    end
    node.entries.each do |entry|
      if (low && entry.key <= low) || (high && entry.key >= high)
        return "RANGE #{details} key=#{entry.key} low=#{low || '-inf'} high=#{high || '+inf'}"
      end
    end
    if node.leaf?
      if reference[0].nil?
        reference[0] = depth
      elsif depth != reference[0]
        return "DEPTH #{details} depth=#{depth} expected=#{reference[0]}"
      end
    end
    node.children.each_with_index do |child, j|
      lower = j.zero? ? low : node.entries[j - 1].key
      upper = j == count ? high : node.entries[j].key
      problem = check_node(child, "#{location}.#{j}", depth + 1, lower, upper, reference)
      return problem if problem
    end
    nil
  end

  def violation = check_node(@root, 'root', 0, nil, nil, [nil])
  def status = violation ? 'DAMAGED' : 'OK'

  def height
    page, depth = @root, 0
    until @pages.fetch(page).leaf?
      page = @pages.fetch(page).children.first
      depth += 1
    end
    depth
  end

  def self.load(degree, tokens) = Parser.new(degree, tokens).load

  def changes(before)
    writes = @pages.count { |page, node| !before.pages.key?(page) || !node.same_content?(before.pages[page]) }
    frees = before.pages.keys.count { |page| !@pages.key?(page) }
    Changes.new(writes, frees)
  end

  def split_child(parent_page, position, trace)
    parent = @pages.fetch(parent_page)
    child_page = parent.children[position]
    child = @pages.fetch(child_page)
    old = child.to_s
    middle = child.entries[@degree - 1]
    right = Node.new(child.entries.drop(@degree), child.children.drop(@degree))
    right_page = allocate(right)
    child.entries.slice!(@degree - 1, child.entries.length)
    child.children.slice!(@degree, child.children.length) unless child.leaf?
    parent.entries.insert(position, middle)
    parent.children.insert(position + 1, right_page)
    @splits += 1
    trace.emit('STEP split page=%d keys=%s up=%d new=%d', child_page, old, middle.key, right_page)
  end

  def upsert(entry, trace)
    found = search(entry.key)
    unless found.page.nil?
      node = @pages.fetch(found.page)
      old = node.entries[found.position].value
      node.entries[found.position] = entry
      return old
    end
    if @pages.fetch(@root).entries.length == 2 * @degree - 1
      @root = allocate(Node.new([], [@root]))
      trace.emit('STEP grow page=%d', @root)
      split_child(@root, 0, trace)
    end
    page = @root
    until @pages.fetch(page).leaf?
      node = @pages.fetch(page)
      position = node.position(entry.key)
      if @pages.fetch(node.children[position]).entries.length == 2 * @degree - 1
        split_child(page, position, trace)
        position += 1 if entry.key > node.entries[position].key
      end
      page = node.children[position]
    end
    node = @pages.fetch(page)
    node.entries.insert(node.position(entry.key), entry)
    trace.emit('STEP place page=%d keys=%s', page, node)
    nil
  end

  def extreme(page, last)
    loop do
      node = @pages.fetch(page)
      return last ? node.entries.last : node.entries.first if node.leaf?
      page = last ? node.children.last : node.children.first
    end
  end

  def merge(parent_page, position, case_name, trace)
    parent = @pages.fetch(parent_page)
    left_page, right_page = parent.children[position, 2]
    left = @pages.fetch(left_page)
    right = @pages.delete(right_page)
    left.entries << parent.entries.delete_at(position)
    left.entries.concat(right.entries)
    left.children.concat(right.children)
    parent.children.delete_at(position + 1)
    @merges += 1
    trace.emit('STEP %s page=%d merge=%d+%d keys=%s', case_name, parent_page, left_page, right_page, left)
    if parent_page == @root && parent.entries.empty?
      @root = left_page
      @pages.delete(parent_page)
      trace.emit('STEP shrink page=%d', @root)
    end
    left_page
  end

  def remove_at(page, key, trace)
    node = @pages.fetch(page)
    position = node.position(key)
    if node.entries[position]&.key == key
      if node.leaf?
        trace.cases << '1'
        node.entries.delete_at(position)
        trace.emit('STEP 1 page=%d keys=%s', page, node)
        return
      end
      left, right = node.children[position, 2]
      if @pages.fetch(left).entries.length >= @degree
        predecessor = extreme(left, true)
        trace.cases << '2a'
        trace.emit('STEP 2a page=%d pred=%d', page, predecessor.key)
        remove_at(left, predecessor.key, trace)
        node.entries[position] = predecessor
      elsif @pages.fetch(right).entries.length >= @degree
        successor = extreme(right, false)
        trace.cases << '2b'
        trace.emit('STEP 2b page=%d succ=%d', page, successor.key)
        remove_at(right, successor.key, trace)
        node.entries[position] = successor
      else
        trace.cases << '2c'
        child = merge(page, position, '2c', trace)
        remove_at(child, key, trace)
      end
      return
    end
    child_page = node.children[position]
    child = @pages.fetch(child_page)
    if child.entries.length == @degree - 1
      left = position.positive? ? node.children[position - 1] : nil
      right = node.children[position + 1]
      if left && @pages.fetch(left).entries.length >= @degree
        sibling = @pages.fetch(left)
        trace.cases << '3a-left'
        child.entries.unshift(node.entries[position - 1])
        node.entries[position - 1] = sibling.entries.pop
        child.children.unshift(sibling.children.pop) unless sibling.leaf?
        @borrows += 1
        trace.emit('STEP 3a-left page=%d child=%d from=%d keys=%s', page, child_page, left, child)
      elsif right && @pages.fetch(right).entries.length >= @degree
        sibling = @pages.fetch(right)
        trace.cases << '3a-right'
        child.entries << node.entries[position]
        node.entries[position] = sibling.entries.shift
        child.children << sibling.children.shift unless sibling.leaf?
        @borrows += 1
        trace.emit('STEP 3a-right page=%d child=%d from=%d keys=%s', page, child_page, right, child)
      elsif left
        trace.cases << '3b-left'
        child_page = merge(page, position - 1, '3b-left', trace)
      else
        trace.cases << '3b-right'
        child_page = merge(page, position, '3b-right', trace)
      end
    end
    remove_at(child_page, key, trace)
  end

  def remove(key, trace)
    trace.cases.clear
    remove_at(@root, key, trace)
  end

  def scan_node(page, low, high, entries)
    node = @pages.fetch(page)
    visited = 1
    count = node.entries.length
    (0..count).each do |j|
      if !node.leaf? && (j.zero? || node.entries[j - 1].key < high) && (j == count || node.entries[j].key > low)
        visited += scan_node(node.children[j], low, high, entries)
      end
      entries << node.entries[j] if j < count && node.entries[j].key.between?(low, high)
    end
    visited
  end

  def scan(low, high)
    entries = []
    visited = scan_node(@root, low, high, entries)
    Scan.new(entries, visited)
  end

  def dump_node(page, tokens)
    node = @pages.fetch(page)
    tokens << '('
    (0..node.entries.length).each do |j|
      dump_node(node.children[j], tokens) unless node.leaf?
      tokens << node.entries[j].to_s if j < node.entries.length
    end
    tokens << ')'
  end

  def dump
    tokens = []
    dump_node(@root, tokens)
    tokens.join(' ')
  end

  def copy_group(old, built)
    source = built.fetch(old)
    node = Node.new(source.entries.dup)
    page = allocate(node)
    source.children.each { |child| node.children << copy_group(child, built) }
    page
  end

  def compact
    source, children, built = entries, [], []
    old_root = nil
    loop do
      groups = (source.length + 2 * @degree).div(2 * @degree)
      keys = source.length - (groups - 1)
      base, extra = keys.divmod(groups)
      position = child_position = 0
      separators, level = [], []
      groups.times do |j|
        count = base + (j < extra ? 1 : 0)
        node = Node.new(source[position, count], children.empty? ? [] : children[child_position, count + 1])
        position += count
        child_position += count + 1
        level << built.length
        built << node
        if j + 1 < groups
          separators << source[position]
          position += 1
        end
      end
      if groups == 1
        old_root = level.first
        break
      end
      source, children = separators, level
    end
    @pages.clear
    @root = copy_group(old_root, built)
    @splits = @merges = @borrows = 0
  end
end

class Parser
  def initialize(degree, tokens)
    @tree = Tree.new(degree)
    @tree.pages.clear
    @tokens, @position = tokens, 0
  end

  def entry
    token = @tokens[@position]
    split = token&.index('=')
    raise CommandError, "SYNTAX #{@position + 1}" unless split
    @position += 1
    Entry.new(Integer(token[0...split], 10), token[(split + 1)..])
  end

  def read_node
    raise CommandError, "SYNTAX #{@position + 1}" unless @tokens[@position] == '('
    @position += 1
    node = Node.new
    page = @tree.allocate(node)
    internal = @tokens[@position] == '('
    node.children << read_node if internal
    until @tokens[@position] == ')'
      node.entries << entry
      node.children << read_node if internal
    end
    @position += 1
    page
  end

  def load
    @tree.root = read_node
    raise CommandError, "SYNTAX #{@position + 1}" unless @position == @tokens.length
    @tree
  end
end

class Workbench
  NEEDS_VALID = %w[INSERT BULKLOAD DELETE DELRANGE RANGE COUNT MIN MAX FLOOR CEIL RANK SELECT SEEK NEXT PREV HEIGHT COMPACT].freeze

  def initialize
    @index = @saved = nil
    @cursor = :unset
    @trace = false
  end

  def find_entry(entries, last: false, &predicate)
    (last ? entries.reverse_each : entries.each).find(&predicate)
  end

  def process(line)
    words = line.split(' ')
    command = words[0]
    if command == 'TRACE'
      @trace = words[1] == 'ON'
      return ["TRACE #{words[1]}"]
    end
    first = words[1] ? Integer(words[1], 10) : 0
    ranged = %w[DELRANGE RANGE COUNT].include?(command)
    second = ranged ? Integer(words[2], 10) : 0
    if command == 'CREATE' || command == 'LOAD'
      raise CommandError, "BAD DEGREE #{first}" unless (2..5).cover?(first)
      tree = command == 'CREATE' ? Tree.new(first) : Tree.load(first, words.drop(2))
      result = command == 'CREATE' ? "CREATE t=#{first}" : "LOAD t=#{first} nodes=#{tree.pages.length} keys=#{tree.entries.length} #{tree.status}"
      @index, @cursor = tree, :unset
      return [result]
    end
    tree = @index
    raise CommandError, 'NO INDEX' unless tree
    raise CommandError, 'DAMAGED' if NEEDS_VALID.include?(command) && tree.violation
    entries = tree.entries
    raise CommandError, "BAD RANGE #{first} #{second}" if ranged && first > second
    raise CommandError, "BAD POSITION #{first}" if command == 'SELECT' && !first.between?(1, entries.length)
    raise CommandError, 'NO CURSOR' if %w[NEXT PREV].include?(command) && @cursor == :unset
    raise CommandError, 'NO SAVE' if command == 'RESTORE' && @saved.nil?
    output = []
    steps = Trace.new(@trace && %w[INSERT DELETE].include?(command))
    case command
    when 'INSERT'
      before, splits = tree.dup, tree.splits
      old = tree.upsert(Entry.new(first, words[2]), steps)
      writes = tree.changes(before).writes
      output.concat(steps.lines)
      output << if old
                  "INSERT #{first} UPDATED old=#{old} writes=#{writes}"
                else
                  "INSERT #{first} NEW splits=#{tree.splits - splits} height=#{tree.height} writes=#{writes}"
                end
    when 'BULKLOAD'
      before, splits = tree.dup, tree.splits
      added = updated = 0
      words.drop(1).each_slice(2) do |key, value|
        if tree.upsert(Entry.new(Integer(key, 10), value), steps)
          updated += 1
        else
          added += 1
        end
      end
      output << "BULKLOAD pairs=#{(words.length - 1).div(2)} new=#{added} updated=#{updated} splits=#{tree.splits - splits} height=#{tree.height} writes=#{tree.changes(before).writes}"
    when 'DELETE'
      found = tree.search(first)
      if found.page.nil?
        output << "DELETE #{first} NOT FOUND"
      else
        value = tree.pages.fetch(found.page).entries[found.position].value
        before = tree.dup
        tree.remove(first, steps)
        changes = tree.changes(before)
        output.concat(steps.lines)
        output << "DELETE #{first} REMOVED value=#{value} cases=#{steps.cases.join(',')} height=#{tree.height} writes=#{changes.writes} frees=#{changes.frees}"
      end
    when 'DELRANGE'
      before, merges, borrows = tree.dup, tree.merges, tree.borrows
      removed = 0
      entries.each do |entry|
        next unless entry.key.between?(first, second)
        tree.remove(entry.key, steps)
        removed += 1
      end
      changes = tree.changes(before)
      output << "DELRANGE #{first} #{second} removed=#{removed} merges=#{tree.merges - merges} borrows=#{tree.borrows - borrows} height=#{tree.height} writes=#{changes.writes} frees=#{changes.frees}"
    when 'GET'
      found = tree.search(first)
      result = found.page.nil? ? 'NOT FOUND' : "FOUND value=#{tree.pages.fetch(found.page).entries[found.position].value}"
      output << "GET #{first} #{result} path=#{found.path.join(' -> ')}"
    when 'RANGE', 'COUNT'
      result = tree.scan(first, second)
      suffix = command == 'RANGE' ? result.entries.map { |entry| " #{entry}" }.join : ''
      output << "#{command} #{first} #{second} count=#{result.entries.length} visited=#{result.visited}#{suffix}"
    when 'MIN', 'MAX'
      entry = command == 'MIN' ? entries.first : entries.last
      output << "#{command} #{entry || 'EMPTY'}"
    when 'FLOOR', 'CEIL'
      floor = command == 'FLOOR'
      entry = find_entry(entries, last: floor) { |value| floor ? value.key <= first : value.key >= first }
      output << "#{command} #{first} #{entry || 'NONE'}"
    when 'RANK'
      output << "RANK #{first} #{entries.count { |entry| entry.key < first }}"
    when 'SELECT'
      output << "SELECT #{first} #{entries[first - 1]}"
    when 'SEEK'
      entry = find_entry(entries) { |value| value.key >= first }
      @cursor = entry&.key || :end
      output << "SEEK #{first} #{entry || 'END'}"
    when 'NEXT', 'PREV'
      forward = command == 'NEXT'
      entry = case @cursor
              when Integer
                find_entry(entries, last: !forward) { |value| forward ? value.key > @cursor : value.key < @cursor }
              when :begin then forward ? entries.first : nil
              when :end then forward ? nil : entries.last
              end
      boundary = forward ? :end : :begin
      @cursor = entry&.key || boundary
      output << "#{command} #{entry || boundary.to_s.upcase}"
    when 'PRINT'
      level, depth = [tree.root], 0
      until level.empty?
        output << "LEVEL #{depth} #{level.map { |page| tree.pages.fetch(page).to_s }.join(' ')}"
        level = level.flat_map { |page| tree.pages.fetch(page).children }
        depth += 1
      end
    when 'PAGES'
      tree.pages.keys.sort.each do |page|
        node = tree.pages.fetch(page)
        kids = node.leaf? ? '-' : node.children.join(',')
        output << "PAGE #{page} #{node} kids=#{kids}"
      end
    when 'DUMP'
      output << "DUMP #{tree.degree} #{tree.dump}"
    when 'HEIGHT'
      output << "HEIGHT #{tree.height}"
    when 'STATS'
      nodes = tree.pages.length
      leaves = tree.pages.values.count(&:leaf?)
      fill = (100 * entries.length).div((2 * tree.degree - 1) * nodes)
      output << "STATS t=#{tree.degree} nodes=#{nodes} leaves=#{leaves} keys=#{entries.length} fill=#{fill}% splits=#{tree.splits} merges=#{tree.merges} borrows=#{tree.borrows}"
    when 'VERIFY'
      problem = tree.violation
      output << (problem ? "VERIFY FAIL #{problem}" : 'VERIFY OK')
    when 'REBUILD'
      tree = Tree.new(tree.degree)
      entries.each { |entry| tree.upsert(entry, steps) }
      output << "REBUILD entries=#{entries.length} keys=#{tree.entries.length} nodes=#{tree.pages.length} splits=#{tree.splits} height=#{tree.height}"
    when 'COMPACT'
      nodes = tree.pages.length
      tree.compact
      output << "COMPACT nodes=#{nodes}->#{tree.pages.length} height=#{tree.height}"
    when 'SAVE'
      @saved = tree.dup
      output << "SAVE nodes=#{tree.pages.length} keys=#{entries.length} #{tree.status}"
    when 'RESTORE'
      tree = @saved.dup
      output << "RESTORE nodes=#{tree.pages.length} keys=#{tree.entries.length} #{tree.status}"
    end
    @index = tree
    output
  end
end

workbench = Workbench.new
Integer(STDIN.readline, 10).times do
  begin
    STDOUT.puts(workbench.process(STDIN.readline.chomp))
  rescue CommandError => error
    STDOUT.puts("ERROR #{error.message}")
  end
end
