# frozen_string_literal: true

DATA_COMMANDS = %w[FILE PATCH EDIT].freeze
FORMATS_WITH_ARGUMENT = %w[IFDEF UNIFIED CONTEXT SIDE].freeze
OFFSETS = [0, 1, -1, 2, -2, 3, -3].freeze
GRAPH_WIDTH = 20
NUMBER_PAIR = /\A([0-9]{1,4})(?:,([0-9]{1,4}))?\z/
MARKER_PREFIXES = { '<<<<<<<' => 'start', '|||||||' => 'base', '>>>>>>>' => 'end' }.freeze
SEPARATOR = '======='

class CommandError < StandardError; end

def range_r(start, count)
  if count >= 2
    "#{start + 1},#{start + count}"
  elsif count == 1
    (start + 1).to_s
  else
    start.to_s
  end
end

def range_u(start, count)
  if count >= 2
    "#{start + 1},#{count}"
  elsif count == 1
    (start + 1).to_s
  else
    "#{start},0"
  end
end

def range_m(start, count)
  "#{start + 1},#{count}"
end

def comparison_key(line, options)
  line = line.downcase if options.include?('ICASE')
  line = line.delete(' ') if options.include?('IWHITE')
  line = line.squeeze(' ') if options.include?('ISPACE')
  line
end

def matched_pairs(first, second)
  rows = first.size
  columns = second.size
  table = Array.new(rows + 1) { Array.new(columns + 1, 0) }
  (1..rows).each do |row|
    (1..columns).each do |column|
      table[row][column] = if first[row - 1] == second[column - 1]
                             table[row - 1][column - 1] + 1
                           else
                             [table[row - 1][column], table[row][column - 1]].max
                           end
    end
  end
  pairs = [[rows + 1, columns + 1]]
  i = rows
  j = columns
  while i >= 1 && j >= 1
    if first[i - 1] == second[j - 1]
      pairs << [i, j]
      i -= 1
      j -= 1
    elsif table[i - 1][j] >= table[i][j - 1]
      i -= 1
    else
      j -= 1
    end
  end
  pairs << [0, 0]
  pairs.reverse
end

ChangeBlock = Data.define(:p, :q, :x, :y) do
  def letter
    return 'c' if x >= 1 && y >= 1

    y.zero? ? 'd' : 'a'
  end
end

def change_blocks(first, second)
  matched_pairs(first, second).each_cons(2).filter_map do |(i, j), (next_i, next_j)|
    ChangeBlock.new(i, j, next_i - i - 1, next_j - j - 1) if next_i - i > 1 || next_j - j > 1
  end
end

def walk(blocks, old_start, new_start, old_end)
  steps = []
  old_index = old_start
  new_index = new_start
  blocks.each do |block|
    while old_index < block.p
      steps << [old_index, new_index, nil]
      old_index += 1
      new_index += 1
    end
    steps << [old_index, new_index, block]
    old_index = block.p + block.x
    new_index = block.q + block.y
  end
  while old_index < old_end
    steps << [old_index, new_index, nil]
    old_index += 1
    new_index += 1
  end
  steps
end

def side_row(left, symbol, right, width)
  "#{left[0, width].ljust(width)} #{symbol} #{right[0, width]}".rstrip
end

def stat_graph(inserted, deleted)
  total = inserted + deleted
  if total <= GRAPH_WIDTH
    plus = inserted
    minus = deleted
  else
    plus = GRAPH_WIDTH * inserted / total
    minus = GRAPH_WIDTH * deleted / total
    plus = 1 if inserted >= 1 && plus.zero?
    minus = 1 if deleted >= 1 && minus.zero?
  end
  ('+' * plus) + ('-' * minus)
end

class Hunk
  attr_reader :blocks, :old_start, :old_count, :new_start, :new_count

  def initialize(blocks, context, old_total)
    first = blocks.first
    last = blocks.last
    before = [context, first.p].min
    after = [context, old_total - last.p - last.x].min
    @blocks = blocks
    @old_start = first.p - before
    @old_count = last.p + last.x + after - @old_start
    @new_start = first.q - before
    @new_count = last.q + last.y + after - @new_start
  end

  def steps
    walk(@blocks, @old_start, @new_start, @old_start + @old_count)
  end
end

class LineDiff
  attr_reader :blocks

  def initialize(old, new, options = [])
    @old = old
    @new = new
    old_keys = old.map { |line| comparison_key(line, options) }
    new_keys = new.map { |line| comparison_key(line, options) }
    @blocks = change_blocks(old_keys, new_keys)
  end

  def deleted(block) = @old[block.p, block.x]

  def inserted(block) = @new[block.q, block.y]

  def hunks(context)
    groups = @blocks.slice_when do |previous, block|
      block.p - (previous.p + previous.x) > 2 * context
    end
    groups.map { |group| Hunk.new(group, context, @old.size) }
  end

  def normal
    lines = []
    @blocks.each do |block|
      letter = block.letter
      lines << (range_r(block.p, block.x) + letter + range_r(block.q, block.y))
      lines.concat(deleted(block).map { |line| "< #{line}" })
      lines << '---' if letter == 'c'
      lines.concat(inserted(block).map { |line| "> #{line}" })
    end
    lines
  end

  def ed
    lines = []
    @blocks.reverse_each do |block|
      letter = block.letter
      lines << (range_r(block.p, block.x) + letter)
      lines.push(*inserted(block), '.') unless letter == 'd'
    end
    lines
  end

  def rcs
    lines = []
    @blocks.each do |block|
      lines << "d#{block.p + 1} #{block.x}" if block.x >= 1
      lines.push("a#{block.p + block.x} #{block.y}", *inserted(block)) if block.y >= 1
    end
    lines
  end

  def ifdef(macro)
    lines = []
    walk(@blocks, 0, 0, @old.size).each do |old_index, _, block|
      if block.nil?
        lines << @old[old_index]
      elsif block.x >= 1 && block.y >= 1
        lines.push("#ifndef #{macro}", *deleted(block), "#else /* #{macro} */", *inserted(block),
                   "#endif /* #{macro} */")
      elsif block.y.zero?
        lines.push("#ifndef #{macro}", *deleted(block), "#endif /* ! #{macro} */")
      else
        lines.push("#ifdef #{macro}", *inserted(block), "#endif /* #{macro} */")
      end
    end
    lines
  end

  def unified(context, old_name, new_name)
    lines = ["--- #{old_name}", "+++ #{new_name}"]
    hunks(context).each do |hunk|
      old_range = range_u(hunk.old_start, hunk.old_count)
      new_range = range_u(hunk.new_start, hunk.new_count)
      lines << "@@ -#{old_range} +#{new_range} @@"
      hunk.steps.each do |old_index, _, block|
        if block.nil?
          lines << " #{@old[old_index]}"
        else
          lines.concat(deleted(block).map { |line| "-#{line}" })
          lines.concat(inserted(block).map { |line| "+#{line}" })
        end
      end
    end
    lines
  end

  def context(context, old_name, new_name)
    lines = ["*** #{old_name}", "--- #{new_name}"]
    hunks(context).each do |hunk|
      lines << ('*' * 15)
      lines << "*** #{range_r(hunk.old_start, hunk.old_count)} ****"
      if hunk.blocks.any? { |block| block.x >= 1 }
        hunk.steps.each do |old_index, _, block|
          if block.nil?
            lines << "  #{@old[old_index]}"
          else
            marker = block.y >= 1 ? '! ' : '- '
            lines.concat(deleted(block).map { |line| marker + line })
          end
        end
      end
      lines << "--- #{range_r(hunk.new_start, hunk.new_count)} ----"
      next unless hunk.blocks.any? { |block| block.y >= 1 }

      hunk.steps.each do |_, new_index, block|
        if block.nil?
          lines << "  #{@new[new_index]}"
        else
          marker = block.x >= 1 ? '! ' : '+ '
          lines.concat(inserted(block).map { |line| marker + line })
        end
      end
    end
    lines
  end

  def side_by_side(width)
    lines = []
    walk(@blocks, 0, 0, @old.size).each do |old_index, new_index, block|
      if block.nil?
        lines << side_row(@old[old_index], ' ', @new[new_index], width)
        next
      end
      [block.x, block.y].max.times do |row|
        left, symbol, right = if row < block.x && row < block.y
                                [@old[block.p + row], '|', @new[block.q + row]]
                              elsif row < block.x
                                [@old[block.p + row], '<', '']
                              else
                                ['', '>', @new[block.q + row]]
                              end
        lines << side_row(left, symbol, right, width)
      end
    end
    lines
  end
end

TokenTotals = Struct.new(:deleted, :inserted, :common)

def split_tokens(line, by_word)
  by_word ? line.split : line.chars
end

def deletion(tokens, separator)
  "[-#{tokens.join(separator)}-]"
end

def insertion(tokens, separator)
  "{+#{tokens.join(separator)}+}"
end

def compare_tokens(old_tokens, new_tokens, separator, totals)
  parts = []
  blocks = change_blocks(old_tokens, new_tokens)
  walk(blocks, 0, 0, old_tokens.size).each do |old_index, _, block|
    if block.nil?
      parts << old_tokens[old_index]
      totals.common += 1
      next
    end
    parts << deletion(old_tokens[block.p, block.x], separator) if block.x >= 1
    parts << insertion(new_tokens[block.q, block.y], separator) if block.y >= 1
    totals.deleted += block.x
    totals.inserted += block.y
  end
  parts.join(separator)
end

class PatchHunk
  attr_reader :line_number, :old_count, :new_count, :body

  def initialize(line_number, old_start, old_count, new_start, new_count)
    @line_number = line_number
    @old_start = old_start
    @old_count = old_count
    @new_start = new_start
    @new_count = new_count
    @body = []
  end

  def sequences(reverse)
    old_kinds = reverse ? [' ', '+'] : [' ', '-']
    new_kinds = reverse ? [' ', '-'] : [' ', '+']
    old = @body.filter_map { |kind, text| text if old_kinds.include?(kind) }
    new = @body.filter_map { |kind, text| text if new_kinds.include?(kind) }
    [old, new]
  end

  def start(reverse) = reverse ? @new_start : @old_start

  def leading_context = @body.take_while { |kind, _| kind == ' ' }.size

  def trailing_context = @body.reverse.take_while { |kind, _| kind == ' ' }.size
end

HunkMatch = Data.define(:fuzz, :delta, :position, :lines) do
  def report(number)
    text = "Hunk ##{number} succeeded at #{position + 1}"
    text += " with fuzz #{fuzz}" if fuzz >= 1
    if delta.abs == 1
      text += " (offset #{delta} line)"
    elsif delta != 0
      text += " (offset #{delta} lines)"
    end
    text
  end
end

def parse_range(text, sign)
  return nil unless text.start_with?(sign)

  match = NUMBER_PAIR.match(text[1..])
  return nil if match.nil?

  start = match[1].to_i
  count = match[2].nil? ? 1 : match[2].to_i
  return nil if start.zero? && count != 0

  [start, count]
end

def parse_hunk_header(line, line_number)
  parts = line.split(/ /, -1)
  if parts.size == 4 && parts[0] == '@@' && parts[3] == '@@'
    old_range = parse_range(parts[1], '-')
    new_range = parse_range(parts[2], '+')
  end
  raise CommandError, "PATCH ERROR line #{line_number}: bad hunk header" unless old_range && new_range

  PatchHunk.new(line_number, *old_range, *new_range)
end

def parse_patch(patch_lines)
  index = patch_lines.index { |line| line.start_with?('@@') }
  raise CommandError, 'PATCH ERROR no hunks' if index.nil?

  hunks = []
  while index < patch_lines.size
    hunk = parse_hunk_header(patch_lines[index], index + 1)
    index += 1
    old_seen = 0
    new_seen = 0
    while old_seen < hunk.old_count || new_seen < hunk.new_count
      if index == patch_lines.size
        raise CommandError, "PATCH ERROR line #{hunk.line_number}: truncated hunk"
      end

      line = patch_lines[index]
      kind = line[0]
      in_old = [' ', '-'].include?(kind)
      in_new = [' ', '+'].include?(kind)
      if line.size < 2 || !(in_old || in_new) ||
         (in_old && old_seen == hunk.old_count) || (in_new && new_seen == hunk.new_count)
        raise CommandError, "PATCH ERROR line #{index + 1}: bad hunk line"
      end

      hunk.body << [kind, line[1..]]
      old_seen += 1 if in_old
      new_seen += 1 if in_new
      index += 1
    end
    if hunk.body.all? { |kind, _| kind == ' ' }
      raise CommandError, "PATCH ERROR line #{hunk.line_number}: no changes"
    end

    hunks << hunk
  end
  hunks
end

def search_hunk(hunk, lines, adjustment, reverse, max_fuzz)
  old, new = hunk.sequences(reverse)
  start = hunk.start(reverse)
  expected = old.empty? ? start + adjustment : start - 1 + adjustment
  leading = hunk.leading_context
  trailing = hunk.trailing_context
  (0..max_fuzz).each do |fuzz|
    head = [fuzz, leading].min
    tail = [fuzz, trailing].min
    old_part = old[head...(old.size - tail)]
    new_part = new[head...(new.size - tail)]
    OFFSETS.each do |delta|
      position = expected + head + delta
      finish = position + old_part.size
      next if position.negative? || finish > lines.size

      if lines[position...finish] == old_part
        return HunkMatch.new(fuzz, delta, position, lines[0...position] + new_part + lines[finish..])
      end
    end
  end
  nil
end

def parse_edit_command(line)
  instruction = line[-1]
  address = line[0...-1]
  match = NUMBER_PAIR.match(address)
  return nil unless %w[a c d].include?(instruction) && match
  return nil if instruction == 'a' && match[2]

  first = match[1].to_i
  last = match[2].nil? ? first : match[2].to_i
  [instruction, first, last]
end

def run_edit_script(lines, script)
  lines = lines.dup
  executed = 0
  index = 0
  while index < script.size
    line_number = index + 1
    instruction, first, last = parse_edit_command(script[index])
    raise CommandError, "EDIT ERROR line #{line_number}: bad command" if instruction.nil?

    valid = if instruction == 'a'
              first <= lines.size
            else
              first >= 1 && first <= last && last <= lines.size
            end
    raise CommandError, "EDIT ERROR line #{line_number}: bad range" unless valid

    index += 1
    text = []
    if %w[a c].include?(instruction)
      finish = (index...script.size).find { |position| script[position] == '.' }
      raise CommandError, "EDIT ERROR line #{line_number}: missing terminator" if finish.nil?

      text = script[index...finish]
      index = finish + 1
    end
    case instruction
    when 'a'
      lines[first, 0] = text
    when 'c'
      lines[(first - 1)...last] = text
    else
      lines.slice!((first - 1)...last)
    end
    executed += 1
  end
  [lines, executed]
end

Chunk = Data.define(:kind, :base_start, :ours_start, :theirs_start, :base, :ours, :theirs) do
  def location
    "base #{range_m(base_start, base.size)} a #{range_m(ours_start, ours.size)} " \
      "b #{range_m(theirs_start, theirs.size)}"
  end
end

def chunk_kind(base, ours, theirs)
  return 'b' if ours == base
  return 'a' if theirs == base
  return 'both' if ours == theirs

  'conflict'
end

def match_table(first, second)
  matches = Array.new(first.size + 2, 0)
  matched_pairs(first, second)[1...-1].each { |i, j| matches[i] = j }
  matches
end

def three_way_chunks(base, ours, theirs)
  ours_match = match_table(base, ours)
  theirs_match = match_table(base, theirs)
  chunks = []
  x = y = z = 0
  while x < base.size || y < ours.size || z < theirs.size
    if x < base.size && ours_match[x + 1] == y + 1 && theirs_match[x + 1] == z + 1
      chunks << Chunk.new('stable', x, y, z, [base[x]], [ours[y]], [theirs[z]])
      x += 1
      y += 1
      z += 1
      next
    end
    anchor = ((x + 1)..base.size).find do |line|
      ours_match[line] != 0 && theirs_match[line] != 0
    end
    if anchor
      next_x, next_y, next_z = anchor - 1, ours_match[anchor] - 1, theirs_match[anchor] - 1
    else
      next_x, next_y, next_z = base.size, ours.size, theirs.size
    end
    base_part = base[x...next_x]
    ours_part = ours[y...next_y]
    theirs_part = theirs[z...next_z]
    kind = chunk_kind(base_part, ours_part, theirs_part)
    chunks << Chunk.new(kind, x, y, z, base_part, ours_part, theirs_part)
    x, y, z = next_x, next_y, next_z
  end
  chunks
end

def kind_counts(chunks)
  counts = Hash.new(0)
  chunks.each { |chunk| counts[chunk.kind] += 1 }
  "a=#{counts['a']} b=#{counts['b']} both=#{counts['both']} conflicts=#{counts['conflict']}"
end

def common_prefix_length(first, second)
  length = 0
  length += 1 while length < first.size && length < second.size && first[length] == second[length]
  length
end

def common_suffix_length(first, second, limit)
  length = 0
  length += 1 while length < limit && first[-1 - length] == second[-1 - length]
  length
end

def conflict_lines(chunk, mode, base_name, ours_name, theirs_name)
  return chunk.ours if mode == 'OURS'
  return chunk.theirs if mode == 'THEIRS'
  if mode == 'DIFF3'
    return ["<<<<<<< #{ours_name}", *chunk.ours, "||||||| #{base_name}", *chunk.base,
            SEPARATOR, *chunk.theirs, ">>>>>>> #{theirs_name}"]
  end

  ours = chunk.ours
  theirs = chunk.theirs
  head = common_prefix_length(ours, theirs)
  tail = common_suffix_length(ours, theirs, [ours.size, theirs.size].min - head)
  ours_middle = ours[head...(ours.size - tail)]
  theirs_middle = theirs[head...(theirs.size - tail)]
  middle = if mode == 'UNION'
             ours_middle + theirs_middle
           else
             ["<<<<<<< #{ours_name}", *ours_middle, SEPARATOR, *theirs_middle,
              ">>>>>>> #{theirs_name}"]
           end
  ours[0...head] + middle + ours[(ours.size - tail)..]
end

def marker_kind(line)
  return 'separator' if line == SEPARATOR

  kind = MARKER_PREFIXES[line[0, 7]]
  kind if kind && (line.size == 7 || line[7] == ' ')
end

def next_marker(lines, index)
  index += 1
  index += 1 while index < lines.size && marker_kind(lines[index]).nil?
  index
end

ConflictRegion = Data.define(:start_line, :end_line, :ours, :base, :theirs) do
  def part(side)
    case side
    when 'OURS' then ours
    when 'THEIRS' then theirs
    when 'BASE' then base
    else ours + theirs
    end
  end
end

def region_at(lines, start)
  return nil unless marker_kind(lines[start]) == 'start'

  middle = next_marker(lines, start)
  base_marker = nil
  if middle < lines.size && marker_kind(lines[middle]) == 'base'
    base_marker = middle
    middle = next_marker(lines, middle)
  end
  return nil if middle == lines.size || marker_kind(lines[middle]) != 'separator'

  finish = next_marker(lines, middle)
  return nil if finish == lines.size || marker_kind(lines[finish]) != 'end'

  if base_marker.nil?
    ours = lines[(start + 1)...middle]
    base = nil
  else
    ours = lines[(start + 1)...base_marker]
    base = lines[(base_marker + 1)...middle]
  end
  ConflictRegion.new(start + 1, finish + 1, ours, base, lines[(middle + 1)...finish])
end

def conflict_regions(lines)
  regions = []
  index = 0
  while index < lines.size
    region = region_at(lines, index)
    if region.nil?
      index += 1
    else
      regions << region
      index = region.end_line
    end
  end
  regions
end

class Workspace
  HANDLERS = {
    'FILE' => :load_file,
    'COPY' => :copy,
    'PRINT' => :print_file,
    'FILES' => :list_files,
    'DIFF' => :diff,
    'WORDDIFF' => :word_diff,
    'CHARDIFF' => :char_diff,
    'STAT' => :stat,
    'PATCH' => :patch,
    'EDIT' => :edit,
    'DIFF3' => :diff3,
    'MERGE' => :merge,
    'CONFLICTS' => :conflicts,
    'RESOLVE' => :resolve,
    'UNDO' => :undo
  }.freeze

  attr_reader :output

  def initialize
    @files = {}
    @history = {}
    @output = []
  end

  def execute(words, data)
    command, *arguments = words
    if DATA_COMMANDS.include?(command)
      send(HANDLERS.fetch(command), arguments, data)
    else
      send(HANDLERS.fetch(command), arguments)
    end
  rescue CommandError => e
    emit(e.message)
  end

  private

  def emit(line)
    @output << line
  end

  def require_files(*names)
    missing = names.find { |name| !@files.key?(name) }
    raise CommandError, "ERROR no such file #{missing}" if missing
  end

  def save(name, lines)
    (@history[name] ||= []) << @files[name]
    @files[name] = lines.dup
  end

  def load_file(arguments, data)
    name = arguments.first
    save(name, data)
    emit("FILE #{name} lines=#{data.size}")
  end

  def copy(arguments)
    source, target = arguments
    require_files(source)
    lines = @files[source]
    save(target, lines)
    emit("COPY #{source} #{target} lines=#{lines.size}")
  end

  def print_file(arguments)
    name = arguments.first
    require_files(name)
    lines = @files[name]
    emit("PRINT #{name} lines=#{lines.size}")
    lines.each.with_index(1) { |line, number| emit(format('%3d| %s', number, line)) }
  end

  def list_files(_arguments)
    emit("FILES count=#{@files.size}")
    @files.sort.each do |name, lines|
      emit("#{name} lines=#{lines.size} undo=#{@history[name].size}")
    end
  end

  def undo(arguments)
    name = arguments.first
    states = @history.fetch(name, [])
    raise CommandError, "ERROR nothing to undo #{name}" if states.empty?

    state = states.pop
    if state.nil?
      @files.delete(name)
      emit("UNDO #{name} removed")
    else
      @files[name] = state
      emit("UNDO #{name} lines=#{state.size}")
    end
  end

  def diff(arguments)
    old_name, new_name, form, *options = arguments
    require_files(old_name, new_name)
    parameter = options.shift if FORMATS_WITH_ARGUMENT.include?(form)
    diff = LineDiff.new(@files[old_name], @files[new_name], options)
    if diff.blocks.empty?
      emit("Files #{old_name} and #{new_name} are identical")
      return
    end
    lines = case form
            when 'BRIEF' then ["Files #{old_name} and #{new_name} differ"]
            when 'NORMAL' then diff.normal
            when 'ED' then diff.ed
            when 'RCS' then diff.rcs
            when 'IFDEF' then diff.ifdef(parameter)
            when 'UNIFIED' then diff.unified(parameter.to_i, old_name, new_name)
            when 'CONTEXT' then diff.context(parameter.to_i, old_name, new_name)
            else diff.side_by_side(parameter.to_i)
            end
    @output.concat(lines)
  end

  def token_diff(arguments, by_word)
    old_name, new_name = arguments
    require_files(old_name, new_name)
    old = @files[old_name]
    new = @files[new_name]
    diff = LineDiff.new(old, new)
    if diff.blocks.empty?
      emit("Files #{old_name} and #{new_name} are identical")
      return
    end
    separator = by_word ? ' ' : ''
    totals = TokenTotals.new(0, 0, 0)
    diff.blocks.each do |block|
      [block.x, block.y].max.times do |row|
        old_number = block.p + row + 1
        new_number = block.q + row + 1
        if row < block.x && row < block.y
          old_tokens = split_tokens(old[old_number - 1], by_word)
          new_tokens = split_tokens(new[new_number - 1], by_word)
          text = compare_tokens(old_tokens, new_tokens, separator, totals)
          emit("a#{old_number} b#{new_number}: #{text}")
        elsif row < block.x
          old_tokens = split_tokens(old[old_number - 1], by_word)
          totals.deleted += old_tokens.size
          emit("a#{old_number}: #{deletion(old_tokens, separator)}")
        else
          new_tokens = split_tokens(new[new_number - 1], by_word)
          totals.inserted += new_tokens.size
          emit("b#{new_number}: #{insertion(new_tokens, separator)}")
        end
      end
    end
    label = by_word ? 'WORDS' : 'CHARS'
    emit("#{label} deleted=#{totals.deleted} inserted=#{totals.inserted} common=#{totals.common}")
  end

  def word_diff(arguments)
    token_diff(arguments, true)
  end

  def char_diff(arguments)
    token_diff(arguments, false)
  end

  def stat(arguments)
    old_name, new_name, *options = arguments
    require_files(old_name, new_name)
    old = @files[old_name]
    new = @files[new_name]
    diff = LineDiff.new(old, new, options)
    deleted = diff.blocks.sum(&:x)
    inserted = diff.blocks.sum(&:y)
    total = deleted + inserted
    unchanged = old.size - deleted
    summary = "#{old_name} -> #{new_name} | #{total}"
    summary += " #{stat_graph(inserted, deleted)}" if total.positive?
    emit(summary)
    line_total = old.size + new.size
    similarity = line_total.positive? ? 200 * unchanged / line_total : 100
    emit("changes=#{diff.blocks.size} insertions=#{inserted} deletions=#{deleted} " \
         "unchanged=#{unchanged} similarity=#{similarity}%")
  end

  def patch(arguments, data)
    name, _count, *options = arguments
    require_files(name)
    reverse = options.include?('REVERSE')
    dry_run = options.include?('DRYRUN')
    fuzz_index = options.index('FUZZ')
    max_fuzz = fuzz_index.nil? ? 0 : options[fuzz_index + 1].to_i
    hunks = parse_patch(data)
    emit("#{dry_run ? 'checking' : 'patching'} file #{name}")
    lines = @files[name]
    first = hunks.first
    if search_hunk(first, lines, 0, reverse, max_fuzz).nil? &&
       search_hunk(first, lines, 0, !reverse, max_fuzz)
      emit('Reversed (or previously applied) patch detected! Skipping patch.')
      emit("RESULT applied=0 failed=0 ignored=#{hunks.size} lines=#{lines.size}")
      return
    end
    adjustment = 0
    applied = 0
    failed = 0
    hunks.each.with_index(1) do |hunk, number|
      match = search_hunk(hunk, lines, adjustment, reverse, max_fuzz)
      if match.nil?
        failed += 1
        emit("Hunk ##{number} FAILED at #{hunk.start(reverse)}")
        next
      end
      old, new = hunk.sequences(reverse)
      lines = match.lines
      adjustment += match.delta + new.size - old.size
      applied += 1
      emit(match.report(number))
    end
    emit("RESULT applied=#{applied} failed=#{failed} ignored=0 lines=#{lines.size}")
    save(name, lines) if !dry_run && applied >= 1
  end

  def edit(arguments, data)
    name = arguments.first
    require_files(name)
    lines, executed = run_edit_script(@files[name], data)
    emit("EDIT #{name} commands=#{executed} lines=#{lines.size}")
    save(name, lines)
  end

  def three_way(base_name, ours_name, theirs_name)
    require_files(base_name, ours_name, theirs_name)
    three_way_chunks(@files[base_name], @files[ours_name], @files[theirs_name])
  end

  def diff3(arguments)
    chunks = three_way(*arguments)
    changes = chunks.reject { |chunk| chunk.kind == 'stable' }
    changes.each do |chunk|
      emit("==== #{chunk.kind} #{chunk.location}")
      @output.concat(chunk.base.map { |line| "O #{line}" })
      @output.concat(chunk.ours.map { |line| "A #{line}" }) unless chunk.kind == 'b'
      @output.concat(chunk.theirs.map { |line| "B #{line}" }) if %w[b conflict].include?(chunk.kind)
    end
    emit("DIFF3 chunks=#{changes.size} #{kind_counts(chunks)}")
  end

  def merge(arguments)
    base_name, ours_name, theirs_name, target, mode = arguments
    mode ||= 'MARKERS'
    chunks = three_way(base_name, ours_name, theirs_name)
    result = []
    conflicts = []
    chunks.each do |chunk|
      case chunk.kind
      when 'b'
        result.concat(chunk.theirs)
      when 'conflict'
        result.concat(conflict_lines(chunk, mode, base_name, ours_name, theirs_name))
        conflicts << chunk
      else
        result.concat(chunk.ours)
      end
    end
    emit("MERGE #{target} lines=#{result.size} #{kind_counts(chunks)}")
    conflicts.each.with_index(1) { |chunk, number| emit("CONFLICT #{number} #{chunk.location}") }
    save(target, result)
  end

  def conflicts(arguments)
    name = arguments.first
    require_files(name)
    regions = conflict_regions(@files[name])
    emit("CONFLICTS #{name} count=#{regions.size}")
    regions.each.with_index(1) do |region, number|
      base = region.base.nil? ? 'none' : region.base.size
      emit("#{number}: lines #{region.start_line}-#{region.end_line} ours=#{region.ours.size} " \
           "base=#{base} theirs=#{region.theirs.size}")
    end
  end

  def resolve(arguments)
    name, number_text, side = arguments
    require_files(name)
    number = number_text.to_i
    lines = @files[name]
    regions = conflict_regions(lines)
    raise CommandError, "ERROR no conflict #{number} in #{name}" if regions.size < number

    region = regions[number - 1]
    if side == 'BASE' && region.base.nil?
      raise CommandError, "ERROR no base section in conflict #{number}"
    end

    content = lines[0...(region.start_line - 1)] + region.part(side) + lines[region.end_line..]
    remaining = conflict_regions(content).size
    emit("RESOLVE #{name} #{number} #{side} lines=#{content.size} remaining=#{remaining}")
    save(name, content)
  end
end

def main
  lines = $stdin.readlines(chomp: true)
  workspace = Workspace.new
  position = 1
  lines[0].to_i.times do
    words = lines[position].split
    position += 1
    data = []
    if DATA_COMMANDS.include?(words[0])
      count = words[2].to_i
      data = lines[position, count]
      position += count
    end
    workspace.execute(words, data)
  end
  puts workspace.output
end

main
