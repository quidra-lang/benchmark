# frozen_string_literal: true

DIRECTIONS = %w[u d l r].freeze
TURNS = { 'ROT90' => 'rlud', 'ROT180' => 'durl', 'ROT270' => 'lrdu',
          'FLIPH' => 'udrl', 'FLIPV' => 'dulr' }.freeze
LEVEL_CHARACTERS = '#-.$*@+'
STEP_CHARACTERS = 'udlrUDLR'
COMMANDS = {
  'IMPORT' => [:text], 'VALID' => [], 'INFO' => [], 'SHOW' => [], 'EXPORT' => [],
  'MOVE' => [:steps], 'PUSH' => %i[number number direction],
  'BRING' => %i[number number number number], 'PATH' => %i[number number],
  'UNDO' => [:number], 'REDO' => [:number], 'RESET' => [], 'STATUS' => [],
  'HISTORY' => [], 'BOXES' => [], 'REACH' => [], 'DEADSQUARES' => [],
  'DEADLOCK' => [], 'BOUND' => [], 'SAVE' => [:name], 'RESTORE' => [:name],
  'CHECK' => [:steps], 'SOLVE' => [:number], 'HINT' => [:number], 'PLAY' => [],
  'TRANSFORM' => [:transform]
}.freeze

class CommandError < StandardError; end
class StepFailure < StandardError; end
Position = Data.define(:player, :boxes)
SearchNode = Data.define(:boxes, :representative, :parent, :push)
SearchResult = Data.define(:outcome, :expanded, :states, :notation)

def decode(text, allowed)
  result = +''
  index = 0
  while index < text.size
    start = index
    index += 1 while index < text.size && text[index].match?(/[0-9]/)
    count = text[start...index]
    return nil if count.size > 2 || count.start_with?('0') || index == text.size
    return nil unless allowed.include?(text[index])

    result << text[index] * (count.empty? ? 1 : count.to_i)
    index += 1
  end
  result
end

def encode(text)
  text.chars.chunk(&:itself).map { |letter, run| "#{run.size > 1 ? run.size : ''}#{letter}" }.join
end

def valid_argument?(kind, text)
  case kind
  when :number then /\A(?:0|[1-9][0-9]{0,5})\z/.match?(text)
  when :steps then !decode(text, STEP_CHARACTERS).nil?
  when :direction then DIRECTIONS.include?(text)
  when :name then /\A[a-z]{1,8}\z/.match?(text)
  when :transform then TURNS.key?(text)
  else true
  end
end

def push_count(letters) = letters.count('UDLR')
def moved_boxes(boxes, source, destination) = boxes.map { |box| box == source ? destination : box }.sort

def turn_letters(letters, kind)
  letters.tr('udlrUDLR', TURNS.fetch(kind) + TURNS.fetch(kind).upcase)
end

class Level
  attr_reader :height, :width, :walls, :goals, :interior, :goal_cells, :offsets, :distances, :dead, :reason

  def initialize(rows)
    @height, @width = rows.size, rows.first.size
    cells = rows.join.chars
    @walls = cells.map { |letter| letter == '#' }
    @goals = cells.map { |letter| '.*+'.include?(letter) }
    @goal_cells = cells.each_index.select { |cell| @goals[cell] }
    players = cells.each_index.select { |cell| '@+'.include?(cells[cell]) }
    boxes = cells.each_index.select { |cell| '$*'.include?(cells[cell]) }
    @offsets = { 'u' => -@width, 'd' => @width, 'l' => -1, 'r' => 1 }
    @interior = Array.new(cells.size, false)
    if players.size == 1
      @interior[players.first] = true
      stack = [players.first]
      until stack.empty?
        row, column = stack.pop.divmod(@width)
        [[row - 1, column], [row + 1, column], [row, column - 1], [row, column + 1]].each do |r, c|
          next unless r.between?(0, @height - 1) && c.between?(0, @width - 1)

          cell = r * @width + c
          next if @walls[cell] || @interior[cell]

          @interior[cell] = true
          stack << cell
        end
      end
    end
    @reason = invalidity(players.size, boxes)
    analyze if @reason.nil?
    @loaded_position = Position.new(players.first, boxes)
  end

  def loaded_position = @loaded_position
  def size = @height * @width
  def cell_text(cell) = "#{cell / @width + 1} #{cell % @width + 1}"
  def cell_at(row, column) = (row - 1) * @width + column - 1
  def contains?(row, column) = row.between?(1, @height) && column.between?(1, @width)
  def boxes_on_goals(boxes) = boxes.count { |box| @goals[box] }
  def solved?(boxes) = boxes.all? { |box| @goals[box] }

  def invalidity(players, boxes)
    return "players #{players}" unless players == 1
    return 'no boxes' if boxes.empty?
    return "boxes #{boxes.size} goals #{@goal_cells.size}" unless boxes.size == @goal_cells.size

    size.times do |cell|
      row, column = cell.divmod(@width)
      if @interior[cell] && (row.zero? || row == @height - 1 || column.zero? || column == @width - 1)
        return "open #{cell_text(cell)}"
      end
    end
    size.times do |cell|
      return "outside #{cell_text(cell)}" if (@goals[cell] || boxes.include?(cell)) && !@interior[cell]
    end
    nil
  end

  def analyze
    @goal_cells = (0...size).select { |cell| @goals[cell] }
    @distances = @goal_cells.map do |goal|
      distance = Array.new(size)
      distance[goal] = 0
      queue = [goal]
      head = 0
      while head < queue.size
        cell = queue[head]
        head += 1
        @offsets.each_value do |offset|
          box = cell - offset
          next unless @interior[box] && @interior[box - offset] && distance[box].nil?

          distance[box] = distance[cell] + 1
          queue << box
        end
      end
      distance
    end
    @dead = (0...size).map { |cell| @interior[cell] && @distances.all? { |distance| distance[cell].nil? } }
  end

  def reachable(player, boxes)
    seen = Array.new(size, false)
    seen[player] = true
    queue = [player]
    head = 0
    while head < queue.size
      cell = queue[head]
      head += 1
      @offsets.each_value do |offset|
        neighbor = cell + offset
        next unless @interior[neighbor] && !seen[neighbor] && !boxes.include?(neighbor)

        seen[neighbor] = true
        queue << neighbor
      end
    end
    seen
  end

  def representative(player, boxes) = reachable(player, boxes).index(true)

  def walk_path(start, target, boxes)
    parents = Array.new(size)
    queue = [start]
    head = 0
    while head < queue.size
      cell = queue[head]
      head += 1
      @offsets.each do |direction, offset|
        neighbor = cell + offset
        next unless @interior[neighbor] && neighbor != start && parents[neighbor].nil? && !boxes.include?(neighbor)

        parents[neighbor] = [cell, direction]
        queue << neighbor
      end
    end
    path = +''
    until target == start
      target, direction = parents[target]
      path << direction
    end
    path.reverse
  end

  def step(position, direction)
    offset = @offsets.fetch(direction)
    target = position.player + offset
    raise StepFailure, 'wall' if @walls[target]
    return [Position.new(target, position.boxes), direction] unless position.boxes.include?(target)

    beyond = target + offset
    raise StepFailure, 'blocked' if @walls[beyond] || position.boxes.include?(beyond)

    [Position.new(target, moved_boxes(position.boxes, target, beyond)), direction.upcase]
  end

  def pushable?(box, direction, boxes, reach)
    offset = @offsets.fetch(direction)
    reach[box - offset] && @interior[box + offset] && !boxes.include?(box + offset)
  end

  def side_blocked?(box, sides, boxes, assumed)
    return true if sides.any? { |side| @walls[side] || assumed.include?(side) }
    return true if sides.all? { |side| @dead[side] }

    sides.any? { |side| boxes.include?(side) && frozen?(side, boxes, assumed + [box]) }
  end

  def frozen?(box, boxes, assumed = [])
    side_blocked?(box, [box - 1, box + 1], boxes, assumed) &&
      side_blocked?(box, [box - @width, box + @width], boxes, assumed)
  end

  def frozen_box?(boxes) = boxes.any? { |box| !@goals[box] && frozen?(box, boxes) }

  def render(position = nil)
    symbols = (0...size).map do |cell|
      if @walls[cell] then '#'
      elsif position.nil?
        @goals[cell] ? '.' : (@dead[cell] ? 'x' : '-')
      elsif cell == position.player then @goals[cell] ? '+' : '@'
      elsif position.boxes.include?(cell) then @goals[cell] ? '*' : '$'
      else @goals[cell] ? '.' : '-'
      end
    end
    symbols.each_slice(@width).map(&:join)
  end

  def map_cell(kind, cell)
    row, column = cell.divmod(@width)
    case kind
    when 'ROT90' then column * @height + @height - 1 - row
    when 'ROT180' then (@height - 1 - row) * @width + @width - 1 - column
    when 'ROT270' then (@width - 1 - column) * @height + row
    when 'FLIPH' then row * @width + @width - 1 - column
    else (@height - 1 - row) * @width + column
    end
  end

  def map_position(kind, position)
    Position.new(map_cell(kind, position.player), position.boxes.map { |box| map_cell(kind, box) }.sort)
  end

  def transformed(kind)
    # Rebuilding the initial drawing preserves its connected interior under any isometry.
    width = %w[ROT90 ROT270].include?(kind) ? @height : @width
    symbols = Array.new(size)
    render(@loaded_position).join.chars.each_with_index { |letter, cell| symbols[map_cell(kind, cell)] = letter }
    Level.new(symbols.each_slice(width).map(&:join))
  end
end

def push_search(level, start, fixed: [], target: nil, pruning: true, limit: nil)
  first = SearchNode.new(start.boxes, level.representative(start.player, start.boxes), nil, nil)
  nodes = [first]
  known = { [first.boxes, first.representative] => true }
  expanded = 0
  while expanded < nodes.size
    return SearchResult.new('limit', expanded, nodes.size, nil) if expanded == limit

    parent = expanded
    node = nodes[expanded]
    expanded += 1
    reach = level.reachable(node.representative, node.boxes)
    node.boxes.each do |box|
      next if fixed.include?(box)

      DIRECTIONS.each do |direction|
        next unless level.pushable?(box, direction, node.boxes, reach)

        destination = box + level.offsets.fetch(direction)
        boxes = moved_boxes(node.boxes, box, destination)
        next if pruning && (level.dead[destination] || level.frozen_box?(boxes))

        representative = level.representative(box, boxes)
        key = [boxes, representative]
        next if known.key?(key)

        known[key] = true
        nodes << SearchNode.new(boxes, representative, parent, [box, direction])
        next unless (target.nil? ? level.solved?(boxes) : destination == target)

        pushes = []
        cursor = nodes.last
        until cursor.parent.nil?
          pushes << cursor.push
          cursor = nodes[cursor.parent]
        end
        position = start
        notation = +''
        pushes.reverse_each do |source, step|
          offset = level.offsets.fetch(step)
          notation << level.walk_path(position.player, source - offset, position.boxes) << step.upcase
          position = Position.new(source, moved_boxes(position.boxes, source, source + offset))
        end
        return SearchResult.new('found', expanded, nodes.size, notation)
      end
    end
  end
  SearchResult.new('no solution', expanded, nodes.size, nil)
end

class Sokoban
  def initialize(rows) = load(rows)

  def load(rows)
    @level = Level.new(rows)
    @initial = @current = @level.loaded_position
    @history = +''
    @redo = +''
    @snapshots = {}
    @solution = nil
  end

  def emit(*parts) = puts(parts.join(' '))
  def cell(arguments, index = 0) = @level.cell_at(arguments[index].to_i, arguments[index + 1].to_i)

  def simulate(directions)
    position = @current
    letters = +''
    directions.each_char do |direction|
      position, letter = @level.step(position, direction)
      letters << letter
    rescue StepFailure => error
      return [position, letters, "step #{letters.size + 1} #{error.message}"]
    end
    [position, letters, nil]
  end

  def take_steps(directions)
    @current, letters, failure = simulate(directions)
    @history << letters
    @redo.clear unless letters.empty?
    [letters, failure]
  end

  def progress(boxes)
    count = @level.boxes_on_goals(boxes)
    "goals #{count}/#{boxes.size}#{count == boxes.size ? ' solved' : ''}"
  end

  def counted(label, letters)
    letters.empty? ? emit(label, 0) : emit(label, letters.size, letters)
  end

  def search_solution(limit)
    return ['already solved', nil] if @level.solved?(@current.boxes)

    result = push_search(@level, @current, limit: limit)
    counts = "expanded #{result.expanded} states #{result.states}"
    return ["#{result.outcome} #{counts}", nil] unless result.outcome == 'found'

    notation = result.notation
    ["solution pushes #{push_count(notation)} moves #{notation.size} #{counts}", notation]
  end

  def execute(words, rows = [])
    name, *arguments = words
    if name == 'LOAD'
      rows.each_with_index do |row, index|
        raise CommandError, "bad row #{index + 1}" unless row.size == arguments[1].to_i && row.chars.all? { |letter| LEVEL_CHARACTERS.include?(letter) }
      end
      load(rows)
      emit('loaded', "#{@level.height}x#{@level.width}")
      return
    end
    raise CommandError, "unknown command #{name}" unless COMMANDS.key?(name)

    kinds = COMMANDS.fetch(name)
    unless arguments.size == kinds.size && kinds.zip(arguments).all? { |kind, argument| valid_argument?(kind, argument) }
      raise CommandError, 'bad arguments'
    end
    unless %w[IMPORT VALID].include?(name)
      raise CommandError, 'invalid level' unless @level.reason.nil?

      ({ 'PATH' => 1, 'PUSH' => 1, 'BRING' => 2 }[name] || 0).times do |index|
        raise CommandError, 'bad value' unless @level.contains?(arguments[index * 2].to_i, arguments[index * 2 + 1].to_i)
      end
      raise CommandError, 'bad value' if %w[UNDO REDO].include?(name) && arguments[0].to_i.zero?
      raise CommandError, 'bad value' if %w[SOLVE HINT].include?(name) && !arguments[0].to_i.between?(1, 100_000)
    end
    process(name, arguments)
  rescue CommandError => error
    emit('error:', error.message)
  end

  def process(name, arguments)
    level = @level
    position = @current
    case name
    when 'IMPORT'
      rows = arguments[0].split('|', -1).map { |part| decode(part, LEVEL_CHARACTERS) }
      if rows.any?(&:nil?) || rows.size > 10 || !rows.first.size.between?(1, 10) || rows.any? { |row| row.size != rows.first.size }
        raise CommandError, 'bad level'
      end
      load(rows)
      emit('loaded', "#{@level.height}x#{@level.width}")
    when 'VALID' then emit(level.reason.nil? ? 'valid' : "invalid #{level.reason}")
    when 'INFO'
      emit('size', "#{level.height}x#{level.width}", 'walls', level.walls.count(true), 'cells', level.interior.count(true), 'boxes', position.boxes.size, 'dead', level.dead.count(true))
    when 'SHOW' then level.render(position).each { |row| emit(row) }
    when 'EXPORT' then emit('level', level.render(position).map { |row| encode(row) }.join('|'))
    when 'MOVE'
      letters, failure = take_steps(decode(arguments[0], STEP_CHARACTERS).downcase)
      emit('moved', letters) unless letters.empty?
      raise CommandError, failure unless failure.nil?
    when 'PUSH'
      box, direction = cell(arguments), arguments[2]
      offset = level.offsets.fetch(direction)
      raise CommandError, 'no box' unless position.boxes.include?(box)
      raise CommandError, 'blocked' unless level.interior[box + offset] && !position.boxes.include?(box + offset)
      raise CommandError, 'unreachable' unless level.reachable(position.player, position.boxes)[box - offset]

      letters, = take_steps(level.walk_path(position.player, box - offset, position.boxes) + direction)
      emit('pushed', letters)
    when 'BRING'
      source, target = cell(arguments), cell(arguments, 2)
      raise CommandError, 'no box' unless position.boxes.include?(source)
      if source == target
        emit('brought', 0)
      else
        result = push_search(level, position, fixed: position.boxes - [source], target: target, pruning: false)
        raise CommandError, 'no route' unless result.outcome == 'found'

        take_steps(result.notation.downcase)
        emit('brought', push_count(result.notation), result.notation)
      end
    when 'PATH'
      target = cell(arguments)
      raise CommandError, 'unreachable' unless level.reachable(position.player, position.boxes)[target]

      letters, = take_steps(level.walk_path(position.player, target, position.boxes))
      counted('path', letters)
    when 'UNDO'
      raise CommandError, 'nothing to undo' if @history.empty?

      count = [arguments[0].to_i, @history.size].min
      count.times do
        letter = @history.slice!(-1)
        direction = letter.downcase
        offset = level.offsets.fetch(direction)
        boxes = position.boxes
        boxes = moved_boxes(boxes, position.player + offset, position.player) if letter != direction
        position = Position.new(position.player - offset, boxes)
        @redo << direction
      end
      @current = position
      emit('undone', count)
    when 'REDO'
      raise CommandError, 'nothing to redo' if @redo.empty?

      count = [arguments[0].to_i, @redo.size].min
      count.times do
        @current, letter = level.step(@current, @redo.slice!(-1))
        @history << letter
      end
      emit('redone', count)
    when 'RESET'
      @current = @initial
      @history.clear
      @redo.clear
      emit('reset')
    when 'STATUS' then emit('moves', @history.size, 'pushes', push_count(@history), progress(position.boxes))
    when 'HISTORY' then counted('history', @history)
    when 'BOXES'
      reach = level.reachable(position.player, position.boxes)
      emit('boxes', position.boxes.size)
      position.boxes.each do |box|
        distance = level.distances.filter_map { |distances| distances[box] }.min
        directions = DIRECTIONS.select { |direction| level.pushable?(box, direction, position.boxes, reach) }.join
        emit('box', level.cell_text(box), distance.nil? ? 'dead' : distance, directions.empty? ? '-' : directions)
      end
    when 'REACH'
      reach = level.reachable(position.player, position.boxes)
      emit('reach', reach.count(true), 'first', level.cell_text(reach.index(true)))
    when 'DEADSQUARES'
      emit('dead', level.dead.count(true))
      level.render.each { |row| emit(row) }
    when 'DEADLOCK'
      box = position.boxes.find { |candidate| level.dead[candidate] }
      if box
        emit('deadlock dead', level.cell_text(box))
      elsif (box = position.boxes.find { |candidate| !level.goals[candidate] && level.frozen?(candidate, position.boxes) })
        emit('deadlock frozen', level.cell_text(box))
      else emit('no deadlock')
      end
    when 'BOUND' then bound
    when 'SAVE'
      @snapshots[arguments[0]] = [position, @history.dup]
      emit('saved', arguments[0], 'moves', @history.size)
    when 'RESTORE'
      snapshot = @snapshots[arguments[0]]
      raise CommandError, "no snapshot #{arguments[0]}" if snapshot.nil?

      @current, history = snapshot
      @history = history.dup
      @redo.clear
      emit('restored', arguments[0], 'moves', @history.size)
    when 'CHECK'
      after, letters, failure = simulate(decode(arguments[0], STEP_CHARACTERS).downcase)
      if failure then emit('check fail', failure)
      else emit('check ok moves', letters.size, 'pushes', push_count(letters), progress(after.boxes))
      end
    when 'SOLVE', 'HINT'
      summary, notation = search_solution(arguments[0].to_i)
      if name == 'SOLVE'
        emit(summary)
        @solution = notation.nil? ? nil : [notation, position]
        emit(notation) unless notation.nil?
      elsif notation.nil? then emit(summary)
      else
        part = notation[/\A[udlr]*[UDLR]/]
        take_steps(part.downcase)
        emit('hint', part)
      end
    when 'PLAY'
      raise CommandError, 'no solution' if @solution.nil? || @solution[1] != position

      notation = @solution[0]
      take_steps(notation.downcase)
      emit('played pushes', push_count(notation), 'moves', notation.size)
    when 'TRANSFORM'
      kind = arguments[0]
      @initial = level.map_position(kind, @initial)
      @current = level.map_position(kind, position)
      @history = turn_letters(@history, kind)
      @redo = turn_letters(@redo, kind)
      @snapshots.transform_values! { |saved, history| [level.map_position(kind, saved), turn_letters(history, kind)] }
      @solution = [turn_letters(@solution[0], kind), level.map_position(kind, @solution[1])] unless @solution.nil?
      @level = level.transformed(kind)
      emit('transformed', "#{@level.height}x#{@level.width}")
    end
  end

  def bound
    boxes = @current.boxes
    best = nil
    (0...boxes.size).to_a.permutation do |order|
      distances = boxes.zip(order).map { |box, goal| @level.distances[goal][box] }
      next if distances.any?(&:nil?)
      next if best && distances.sum >= best[1].sum

      best = [order, distances]
    end
    if best.nil?
      emit('bound none')
      return
    end
    order, distances = best
    emit('bound', distances.sum)
    boxes.each_with_index do |box, index|
      emit('box', @level.cell_text(box), 'goal', @level.cell_text(@level.goal_cells[order[index]]), 'pushes', distances[index])
    end
  end
end

height = STDIN.readline.split.first.to_i
rows = Array.new(height) { STDIN.readline.chomp }
game = Sokoban.new(rows)
STDIN.readline.to_i.times do
  words = STDIN.readline.chomp.split(' ')
  rows = words[0] == 'LOAD' ? Array.new(words[1].to_i) { STDIN.readline.chomp } : []
  game.execute(words, rows)
end
