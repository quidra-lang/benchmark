require 'set'

MODES = %w[FIRST NEXT BEST WORST SEGFIT BUDDY].freeze
COUNTERS = %w[allocs frees reallocs moves failures collected].freeze
UNIT = 8
HEADER = 8
MIN_BLOCK = 16
MIN_BUDDY_BLOCK = 32
MAX_HEAP = 65_536
UNINITIALIZED = -1
RANDOM_MULTIPLIER = 48_271
RANDOM_MODULUS = 2_147_483_647

class CommandError < StandardError; end

def power_of_two?(value)
  value.positive? && (value & (value - 1)).zero?
end

def size_class(size)
  size.bit_length - 1
end

def fragmentation_percent(free, largest)
  free.positive? ? (free - largest) * 100 / free : 0
end

class Block
  attr_accessor :start, :size, :used, :owner, :requested, :contents, :stamp

  def initialize(start, size)
    @start, @size = start, size
    @used, @owner, @requested, @contents, @stamp = false, nil, 0, [], 0
  end

  def finish = @start + @size
  def payload = @start + HEADER
  def area = "#{@start}+#{@size}"

  def map_units
    rest = @size / UNIT - 1
    return 'F' + '.' * rest unless @used
    'H' + rest.times.map { |i| UNIT * i < @requested ? '#' : '-' }.join
  end
end

class Heap
  attr_accessor :mode, :size, :rover, :blocks

  def initialize(mode, size)
    @mode, @size, @rover, @registrations = mode, size, 0, 0
    @blocks = [register(Block.new(0, size))]
  end

  def register(block)
    @registrations += 1
    block.stamp = @registrations
    block
  end

  def buddy? = @mode == 'BUDDY'

  def required_length(request)
    length = ((request + UNIT - 1) / UNIT) * UNIT + HEADER
    return length unless buddy?
    power = MIN_BUDDY_BLOCK
    power *= 2 while power < length
    power
  end

  def locate(address)
    @blocks.index { |block| block.finish > address }
  end

  def used_blocks = @blocks.select(&:used)
  def free_blocks = @blocks.reject(&:used)
  def used_total = used_blocks.sum(&:size)

  def fragmentation
    sizes = free_blocks.map(&:size)
    fragmentation_percent(sizes.sum, sizes.max || 0)
  end

  def placement(block, alignment)
    place = ((block.start + HEADER + alignment - 1) / alignment) * alignment - HEADER
    place += alignment if place > block.start && place - block.start < MIN_BLOCK
    place
  end

  def rank(index, rover_index)
    block = @blocks[index]
    case @mode
    when 'NEXT' then [(index - rover_index) % @blocks.size, 0]
    when 'BEST', 'BUDDY' then [block.size, block.start]
    when 'WORST' then [-block.size, block.start]
    when 'SEGFIT' then [size_class(block.size), -block.stamp]
    else [block.start, 0]
    end
  end

  def choose(length, alignment)
    rover_index = locate(@rover)
    options = @blocks.each_with_index.filter_map do |block, index|
      next if block.used
      place = placement(block, alignment)
      [rank(index, rover_index), index, place] if place + length <= block.finish
    end
    options.min
  end

  def allocate(length, alignment)
    choice = choose(length, alignment)
    return nil unless choice
    _, index, place = choice
    block = buddy? ? halve(index, length) : carve(index, place, length)
    block.used = true
    @rover = block.finish == @size ? 0 : block.finish if @mode == 'NEXT'
    block
  end

  def carve(index, place, length)
    original = @blocks[index]
    parts = []
    parts << register(Block.new(original.start, place - original.start)) if place > original.start
    block = Block.new(place, original.finish - place)
    parts << block
    if block.size - length >= MIN_BLOCK
      parts << register(Block.new(place + length, block.size - length))
      block.size = length
    end
    @blocks[index, 1] = parts
    block
  end

  def halve(index, length)
    block = @blocks[index]
    while block.size > length
      block.size /= 2
      @blocks.insert(index + 1, register(Block.new(block.finish, block.size)))
    end
    block
  end

  def merge_next(index)
    @blocks[index].size += @blocks.delete_at(index + 1).size
  end

  def buddy_index(index)
    block = @blocks[index]
    (block.start % (2 * block.size)).zero? ? index + 1 : index - 1
  end

  def coalesce(index)
    merges = 0
    if buddy?
      while @blocks[index].size < @size
        partner = buddy_index(index)
        other = @blocks[partner]
        break if other.used || other.size != @blocks[index].size
        index = [index, partner].min
        merge_next(index)
        merges += 1
      end
    else
      if index + 1 < @blocks.size && !@blocks[index + 1].used
        merge_next(index)
        merges += 1
      end
      if index.positive? && !@blocks[index - 1].used
        index -= 1
        merge_next(index)
        merges += 1
      end
    end
    [register(@blocks[index]), merges]
  end

  def release(block)
    block.used, block.owner, block.requested, block.contents = false, nil, 0, []
    coalesce(@blocks.index(block))
  end

  def shrink(index, length)
    block = @blocks[index]
    if buddy?
      return 'kept' if length == block.size
      halve(index, length)
      return 'shrunk'
    end
    return 'kept' if block.size - length < MIN_BLOCK
    @blocks.insert(index + 1, Block.new(block.start + length, block.size - length))
    block.size = length
    coalesce(index + 1)
    'shrunk'
  end

  def grow_into_next(index, length)
    block = @blocks[index]
    return nil if index + 1 >= @blocks.size || @blocks[index + 1].used
    total = block.size + @blocks[index + 1].size
    return nil if total < length
    @blocks.delete_at(index + 1)
    if total - length >= MIN_BLOCK
      block.size = length
      @blocks.insert(index + 1, register(Block.new(block.finish, total - length)))
    else
      block.size = total
    end
    'grown'
  end

  def grow_buddy(index, length)
    block = @blocks[index]
    size, last = block.size, index
    while size < length
      last += 1
      return nil if block.start % (2 * size) != 0 || last >= @blocks.size
      partner = @blocks[last]
      return nil if partner.used || partner.size != size
      size *= 2
    end
    @blocks.slice!(index + 1, last - index)
    block.size = length
    'grown'
  end

  def resize(block, length)
    index = @blocks.index(block)
    return shrink(index, length) if length <= block.size
    buddy? ? grow_buddy(index, length) : grow_into_next(index, length)
  end

  def extend(amount)
    @blocks << Block.new(@size, amount)
    @size += amount
    coalesce(@blocks.size - 1)[0]
  end

  def trim
    released = 0
    if buddy?
      while !@blocks[-1].used && 2 * @blocks[-1].size == @size
        released += @blocks.pop.size
        @size /= 2
      end
    elsif @blocks.size >= 2 && !@blocks[-1].used
      last = @blocks.pop
      released = last.size
      @size = last.start
    end
    @rover = 0 if @rover >= @size
    released
  end

  def compact
    moved = []
    address = 0
    packed = used_blocks
    packed.each do |block|
      if block.start != address
        moved << [block, block.payload]
        block.start = address
      end
      address += block.size
    end
    packed << register(Block.new(address, @size - address)) if address < @size
    @blocks = packed
    @rover = 0
    [moved, address]
  end
end

def experiment(mode, size, seed, operations, maximum_request)
  heap = Heap.new(mode, size)
  state, live, used, peak, successes, failures = seed, [], 0, 0, 0, 0
  operations.times do
    state = RANDOM_MULTIPLIER * state % RANDOM_MODULUS
    allocating = live.empty? || state % 3 != 0
    state = RANDOM_MULTIPLIER * state % RANDOM_MODULUS
    if allocating
      block = heap.allocate(heap.required_length(1 + state % maximum_request), UNIT)
      if block
        successes += 1
        live << block
        used += block.size
      else
        failures += 1
      end
    else
      block = live.delete_at(state % live.length)
      used -= block.size
      heap.release(block)
    end
    peak = [peak, used].max
  end
  "BENCH #{mode} ok=#{successes} fail=#{failures} peak=#{peak} used=#{used} " \
    "frag=#{heap.fragmentation} blocks=#{heap.blocks.length}"
end

class Allocator
  METHODS = {
    'HEAP' => :create_heap, 'MALLOC' => :malloc, 'CALLOC' => :calloc,
    'MEMALIGN' => :memalign, 'REALLOC' => :realloc, 'FREE' => :free,
    'FILL' => :fill, 'COPY' => :copy, 'READ' => :read,
    'ROOT' => :root, 'UNROOT' => :unroot, 'LINK' => :link, 'UNLINK' => :unlink,
    'GC' => :collect, 'SBRK' => :sbrk, 'TRIM' => :trim, 'COMPACT' => :compact,
    'WHO' => :who, 'DUMP' => :dump, 'MAP' => :show_map, 'FREELIST' => :freelist,
    'TREE' => :tree, 'STATS' => :stats, 'LEAKS' => :leaks,
    'HISTORY' => :history, 'BENCH' => :bench
  }.freeze

  attr_reader :output

  def initialize
    @output = []
    reset(nil)
  end

  def reset(heap)
    @heap = heap
    @allocations, @freed, @roots, @references, @histories = {}, Set.new, Set.new, {}, {}
    @counters = COUNTERS.to_h { |name| [name, 0] }
    @peak = 0
  end

  def emit(*parts)
    @output << parts.join(' ')
  end

  def record(name, line)
    emit(line)
    (@histories[name] ||= []) << line
  end

  def out_of_memory(name)
    @counters['failures'] += 1
    CommandError.new("OUT OF MEMORY #{name}")
  end

  def require_live(name)
    return @allocations.fetch(name) if @allocations.key?(name)
    raise CommandError, "USE AFTER FREE #{name}" if @freed.include?(name)
    raise CommandError, "UNKNOWN ID #{name}"
  end

  def require_range(name, offset, length)
    block = require_live(name)
    raise CommandError, "OUT OF BOUNDS #{name}" if offset + length > block.requested
    block
  end

  def require_free_list
    raise CommandError, 'UNSUPPORTED IN BUDDY MODE' if @heap.buddy?
  end

  def reachable
    found = @roots.dup
    pending = @roots.to_a
    until pending.empty?
      name = pending.pop
      (@references[name] || []).each do |target|
        next if found.include?(target)
        found.add(target)
        pending << target
      end
    end
    found
  end

  def create_heap(args)
    size, mode = args[0].to_i, args[1]
    if size % UNIT != 0 || size < 32 || size > MAX_HEAP ||
       (mode == 'BUDDY' && !power_of_two?(size))
      raise CommandError, 'BAD HEAP SIZE'
    end
    reset(Heap.new(mode, size))
    emit("HEAP size=#{size} mode=#{mode}")
  end

  def allocate_id(word, name, request, alignment, fill)
    raise CommandError, 'BAD SIZE' if request.zero?
    raise CommandError, "DUPLICATE ID #{name}" if @allocations.key?(name)
    block = @heap.allocate(@heap.required_length(request), alignment)
    raise out_of_memory(name) unless block
    block.owner, block.requested, block.contents = name, request, Array.new(request, fill)
    @allocations[name] = block
    @freed.delete(name)
    @counters['allocs'] += 1
    record(name, "#{word} #{name} addr=#{block.payload} block=#{block.size}")
  end

  def malloc(args)
    allocate_id('MALLOC', args[0], args[1].to_i, UNIT, UNINITIALIZED)
  end

  def calloc(args)
    allocate_id('CALLOC', args[0], args[1].to_i * args[2].to_i, UNIT, 0)
  end

  def memalign(args)
    name, alignment, request = args[0], args[1].to_i, args[2].to_i
    require_free_list
    unless power_of_two?(alignment) && alignment.between?(UNIT, 4096)
      raise CommandError, 'BAD ALIGNMENT'
    end
    allocate_id('MEMALIGN', name, request, alignment, UNINITIALIZED)
  end

  def release_id(name)
    block = @allocations.delete(name)
    size = block.size
    @freed.add(name)
    @roots.delete(name)
    @references.delete(name)
    @references.each_value { |targets| targets.delete(name) }
    result, merges = @heap.release(block)
    "block=#{size} merges=#{merges} free=#{result.area}"
  end

  def free_id(name)
    raise CommandError, "DOUBLE FREE #{name}" if @freed.include?(name)
    raise CommandError, "UNKNOWN ID #{name}" unless @allocations.key?(name)
    details = release_id(name)
    @counters['frees'] += 1
    record(name, "FREE #{name} #{details}")
  end

  def free(args)
    free_id(args[0])
  end

  def realloc(args)
    name, request = args[0], args[1].to_i
    return free_id(name) if request.zero?
    raise CommandError, "USE AFTER FREE #{name}" if @freed.include?(name)
    return allocate_id('MALLOC', name, request, UNIT, UNINITIALIZED) unless @allocations.key?(name)
    block = @allocations.fetch(name)
    length = @heap.required_length(request)
    contents = block.contents.first(request)
    contents += Array.new(request - contents.length, UNINITIALIZED)
    previous = block.payload
    kind = @heap.resize(block, length)
    unless kind
      moved = @heap.allocate(length, UNIT)
      raise out_of_memory(name) unless moved
      moved.owner = name
      @allocations[name] = moved
      @heap.release(block)
      @counters['moves'] += 1
      block = moved
      kind = "moved from=#{previous}"
    end
    block.requested, block.contents = request, contents
    @counters['reallocs'] += 1
    record(name, "REALLOC #{name} addr=#{block.payload} block=#{block.size} #{kind}")
  end

  def fill(args)
    name = args[0]
    offset, length, value = args.drop(1).map(&:to_i)
    block = require_range(name, offset, length)
    block.contents[offset, length] = Array.new(length, value)
    emit("FILL #{name} #{offset}+#{length} = #{value}")
  end

  def copy(args)
    target_name, source_name = args[0], args[2]
    target_offset, source_offset, length = args[1].to_i, args[3].to_i, args[4].to_i
    target = require_range(target_name, target_offset, length)
    source = require_range(source_name, source_offset, length)
    target.contents[target_offset, length] = source.contents[source_offset, length].dup
    emit("COPY #{target_name} #{target_offset}+#{length} from #{source_name} #{source_offset}")
  end

  def read(args)
    name, offset, length = args[0], args[1].to_i, args[2].to_i
    block = require_range(name, offset, length)
    values = block.contents[offset, length].map { |value| value == UNINITIALIZED ? '?' : value.to_s }
    emit("READ #{name} #{offset}+#{length} = #{values.join(' ')}")
  end

  def root(args)
    name = args[0]
    require_live(name)
    @roots.add(name)
    emit('ROOT', name)
  end

  def unroot(args)
    name = args[0]
    require_live(name)
    raise CommandError, "NOT ROOT #{name}" unless @roots.include?(name)
    @roots.delete(name)
    emit('UNROOT', name)
  end

  def link(args)
    source, target = args
    require_live(source)
    require_live(target)
    (@references[source] ||= Set.new).add(target)
    emit('LINK', source, target)
  end

  def unlink(args)
    source, target = args
    require_live(source)
    require_live(target)
    unless (@references[source] || Set.new).include?(target)
      raise CommandError, "NO LINK #{source} #{target}"
    end
    @references[source].delete(target)
    emit('UNLINK', source, target)
  end

  def collect(_args)
    found = reachable
    garbage = @allocations.reject { |name, _| found.include?(name) }.values.sort_by(&:start)
    emit("GC collected=#{garbage.length} bytes=#{garbage.sum(&:size)}")
    garbage.each do |block|
      name = block.owner
      record(name, "COLLECT #{name} #{release_id(name)}")
    end
    @counters['collected'] += garbage.length
  end

  def sbrk(args)
    amount = args[0].to_i
    valid = if @heap.buddy?
      amount == @heap.size && 2 * @heap.size <= MAX_HEAP
    else
      amount % UNIT == 0 && amount >= MIN_BLOCK && @heap.size + amount <= MAX_HEAP
    end
    raise CommandError, 'BAD SBRK SIZE' unless valid
    block = @heap.extend(amount)
    emit("SBRK heap=#{@heap.size} free=#{block.area}")
  end

  def trim(_args)
    released = @heap.trim
    emit("TRIM heap=#{@heap.size} released=#{released}")
  end

  def compact(_args)
    require_free_list
    moved, used = @heap.compact
    @counters['moves'] += moved.length
    free = used < @heap.size ? "#{used}+#{@heap.size - used}" : 'none'
    emit("COMPACT moved=#{moved.length} free=#{free}")
    moved.each do |block, original|
      record(block.owner, "MOVE #{block.owner} #{original} -> #{block.payload}")
    end
  end

  def who(args)
    address = args[0].to_i
    return emit('WHO', address, 'outside') if address >= @heap.size
    block = @heap.blocks[@heap.locate(address)]
    return emit('WHO', address, 'free', block.area) unless block.used
    return emit('WHO', address, 'header', block.owner) if address < block.payload
    offset = address - block.payload
    emit('WHO', address, offset < block.requested ? 'data' : 'slack', "#{block.owner}+#{offset}")
  end

  def dump(_args)
    text = "DUMP mode=#{@heap.mode} heap=#{@heap.size} blocks=#{@heap.blocks.length}"
    text += " rover=#{@heap.rover}" if @heap.mode == 'NEXT'
    emit(text)
    @heap.blocks.each do |block|
      emit(block.start, block.size, 'USED', block.owner, "req=#{block.requested}") if block.used
      emit(block.start, block.size, 'FREE') unless block.used
    end
  end

  def show_map(_args)
    emit("MAP heap=#{@heap.size}")
    units = @heap.blocks.map(&:map_units).join
    (0...units.length).step(64) do |first|
      emit((first * UNIT).to_s.rjust(5, '0'), units[first, 64])
    end
  end

  def freelist(_args)
    free = @heap.free_blocks
    free.sort_by! { |block| -block.stamp } if @heap.mode == 'SEGFIT'
    emit("FREELIST count=#{free.length}")
    free.map { |block| size_class(block.size) }.uniq.sort.each do |power|
      matching = free.select { |block| size_class(block.size) == power }.map(&:area)
      emit("#{2**power}-#{2**(power + 1) - 1}:", *matching)
    end
  end

  def tree_node(leaves, start, size, depth)
    label = ' ' * (2 * depth) + "#{start}+#{size}"
    block = leaves[start]
    if block && block.size == size
      block.used ? emit(label, 'USED', block.owner) : emit(label, 'FREE')
      return
    end
    emit(label, 'split')
    half = size / 2
    tree_node(leaves, start, half, depth + 1)
    tree_node(leaves, start + half, half, depth + 1)
  end

  def tree(_args)
    raise CommandError, 'REQUIRES BUDDY MODE' unless @heap.buddy?
    emit("TREE heap=#{@heap.size}")
    leaves = @heap.blocks.to_h { |block| [block.start, block] }
    tree_node(leaves, 0, @heap.size, 0)
  end

  def stats(_args)
    used, free = @heap.used_blocks, @heap.free_blocks
    free_total = free.sum(&:size)
    largest = free.map(&:size).max || 0
    emit("STATS used=#{used.sum(&:size)} used_blocks=#{used.length}",
         "free=#{free_total} free_blocks=#{free.length} largest=#{largest}",
         "frag=#{fragmentation_percent(free_total, largest)}",
         "requested=#{used.sum(&:requested)} peak=#{@peak}")
    emit('OPS', *COUNTERS.map { |name| "#{name}=#{@counters[name]}" })
  end

  def leaks(_args)
    found = reachable
    names = @allocations.keys.sort
    requested = names.sum { |name| @allocations[name].requested }
    lost = names.count { |name| !found.include?(name) }
    emit("LEAKS count=#{names.length} requested=#{requested} lost=#{lost}")
    names.each do |name|
      block = @allocations.fetch(name)
      emit("LEAK #{name} addr=#{block.payload} block=#{block.size}",
           "req=#{block.requested} #{found.include?(name) ? 'reachable' : 'lost'}")
    end
  end

  def history(args)
    name = args[0]
    lines = @histories.fetch(name, [])
    emit("HISTORY #{name} events=#{lines.length}")
    @output.concat(lines)
  end

  def bench(args)
    size, seed, operations, max_request = args.map(&:to_i)
    unless power_of_two?(size) && size.between?(32, MAX_HEAP)
      raise CommandError, 'BAD HEAP SIZE'
    end
    emit("BENCH heap=#{size} seed=#{seed} ops=#{operations} maxreq=#{max_request}")
    MODES.each { |mode| emit(experiment(mode, size, seed, operations, max_request)) }
  end

  def execute(line)
    name, *arguments = line.split
    begin
      if @heap.nil? && name != 'HEAP' && name != 'BENCH'
        raise CommandError, 'NO HEAP'
      end
      send(METHODS.fetch(name), arguments)
    rescue CommandError => e
      emit('ERROR', e.message)
    ensure
      @peak = [@peak, @heap.used_total].max if @heap
    end
  end
end

allocator = Allocator.new
n = STDIN.gets.to_i
n.times { allocator.execute(STDIN.gets.chomp) }
puts allocator.output
