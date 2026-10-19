# frozen_string_literal: true

class CommandError < StandardError; end

COMMANDS = {
  'NEW' => 4, 'PRESET' => 2, 'LAYOUT' => 2, 'SAFETY' => 1, 'RESTART' => 0,
  'REVEAL' => 2, 'FLAG' => 2, 'UNFLAG' => 2, 'QUESTION' => 2, 'CHORD' => 2,
  'UNDO' => 0, 'SHOW' => 0, 'STATUS' => 0, 'CELL' => 2, 'HISTORY' => 1,
  'REPLAY' => 1, 'HINT' => 0, 'AUTO' => 0, 'ANALYZE' => 0, 'PROB' => 2,
  'FRONTIER' => 0, 'SOLVE' => 0, 'BOARDINFO' => 0, 'STATS' => 0
}.freeze
CELL_COMMANDS = %w[REVEAL FLAG UNFLAG QUESTION CHORD CELL PROB].freeze
UNFINISHED_COMMANDS = %w[REVEAL FLAG UNFLAG QUESTION CHORD UNDO HINT AUTO ANALYZE PROB FRONTIER SOLVE].freeze
UNDO_COMMANDS = %w[REVEAL FLAG UNFLAG QUESTION CHORD AUTO SOLVE].freeze
PRESETS = { 'beginner' => [9, 9, 10].freeze, 'intermediate' => [16, 16, 40].freeze, 'expert' => [30, 16, 99].freeze }.freeze

def number_word(word)
  raise CommandError, 'bad arguments' unless word.length <= 10 && /\A(?:0|[1-9][0-9]*)\z/.match?(word)

  word.to_i
end

def fraction(numerator, denominator)
  divisor = numerator.gcd(denominator)
  "#{numerator / divisor}/#{denominator / divisor}"
end

def bit_count(bits)
  count = 0
  until bits.zero?
    bits &= bits - 1
    count += 1
  end
  count
end

Move = Data.define(:kind, :cell)
Snapshot = Data.define(:command, :revealed, :marks, :moves)
Constraint = Data.define(:cell, :remaining, :unknown)
Restriction = Data.define(:mask, :target)
Reason = Data.define(:kind, :a, :b) do
  def text(game)
    case kind
    when :single then "single #{game.coord(a)}"
    when :subset then "subset #{game.coord(a)} #{game.coord(b)}"
    when :count then 'count'
    end
  end
end

class Deduction
  attr_reader :safe, :mines

  def initialize
    @safe = {}
    @mines = {}
  end

  def empty? = safe.empty? && mines.empty?

  def add(is_safe, cell, reason)
    (is_safe ? safe : mines)[cell] ||= reason
  end
end

AutoResult = Struct.new(:rounds, :flagged, :opened, :guesses) do
  def initialize = super(0, 0, 0, 0)
end

class Game
  attr_reader :width, :height, :mine_count, :seed, :cells, :safe_cells, :neighbors,
              :mine, :numbers, :revealed, :marks, :state, :exploded, :moves, :undo

  def initialize(width, height, mine_count, seed, layout: nil)
    @width, @height, @mine_count, @seed = width, height, mine_count, seed
    @cells = width * height
    @safe_cells = cells - mine_count
    @neighbors = Array.new(cells) do |cell|
      x, y = cell % width, cell / width
      adjacent = []
      (-1..1).each do |dy|
        (-1..1).each do |dx|
          next if dx.zero? && dy.zero?
          next unless (0...width).cover?(x + dx) && (0...height).cover?(y + dy)

          adjacent << (y + dy) * width + x + dx
        end
      end
      adjacent.freeze
    end.freeze
    @mine = Array.new(cells, false)
    @numbers = Array.new(cells, 0)
    @revealed = Array.new(cells, false)
    @marks = Array.new(cells, :none)
    @determined = !layout.nil?
    @state = determined? ? :playing : :ready
    @exploded = nil
    @moves = []
    @undo = []
    if layout
      cells.times { |cell| @mine[cell] = layout[cell / width][cell % width] == '*' }
      number_board
    end
  end

  def initialize_copy(other)
    super
    # Immutable geometry is shared; every mutable board and record is independent.
    @mine = other.mine.dup
    @numbers = other.numbers.dup
    @revealed = other.revealed.dup
    @marks = other.marks.dup
    @moves = other.moves.dup
    @undo = []
  end

  def coord(cell) = "#{cell % width},#{cell / width}"
  def determined? = @determined
  def finished? = state == :won || state == :lost
  def unknown?(cell) = !revealed[cell] && marks[cell] != :flag
  def remaining = mine_count - marks.count(:flag)
  def opened = revealed.count(true)

  def restart
    revealed.fill(false)
    marks.fill(:none)
    moves.clear
    undo.clear
    @exploded = nil
    @state = determined? ? :playing : :ready
  end

  def number_board
    cells.times { |cell| numbers[cell] = neighbors[cell].count { |other| mine[other] } }
  end

  def place_mines(first, safety)
    sx, sy = first % width, first / width
    candidates = (0...cells).select do |cell|
      case safety
      when 'none' then true
      when 'cell' then cell != first
      when 'block' then (cell % width - sx).abs >= 2 || (cell / width - sy).abs >= 2
      end
    end
    random = seed
    mine_count.times do
      random = 48_271 * random % 2_147_483_647
      mine[candidates.delete_at(random % candidates.length)] = true
    end
    number_board
    @determined = true
    @state = :playing
  end

  def reveal(cell, safety)
    place_mines(cell, safety) unless determined?
    if mine[cell]
      @state = :lost
      @exploded = cell
      return 0
    end
    revealed[cell] = true
    marks[cell] = :none
    queue = [cell]
    head = 0
    while head < queue.length
      current = queue[head]
      head += 1
      next unless numbers[current].zero?

      neighbors[current].each do |other|
        next unless unknown?(other)

        revealed[other] = true
        marks[other] = :none
        queue << other
      end
    end
    queue.length
  end

  def chord(cell, safety)
    opened = 0
    neighbors[cell].each do |other|
      opened += reveal(other, safety) if unknown?(other)
      break if state == :lost
    end
    opened
  end

  def check_win
    return unless state == :playing && opened == safe_cells

    @state = :won
    cells.times { |cell| marks[cell] = :flag if mine[cell] }
  end

  def cell_character(cell)
    if state == :lost
      return '!' if cell == exploded
      return marks[cell] == :flag ? 'F' : '*' if mine[cell]
      return 'X' if marks[cell] == :flag
    end
    return numbers[cell].zero? ? '.' : numbers[cell].to_s if revealed[cell]

    { flag: 'F', question: '?', none: '#' }.fetch(marks[cell])
  end

  def show
    height.times { |y| puts Array.new(width) { |x| cell_character(y * width + x) }.join }
  end

  def ending_output
    if state == :lost
      puts "boom #{coord(exploded)}"
      show
    elsif state == :won
      puts "win moves #{moves.length}"
    end
  end

  def constraints
    (0...cells).filter_map do |cell|
      next unless revealed[cell] && numbers[cell].positive?

      flags = neighbors[cell].count { |other| marks[other] == :flag }
      unknown_cells = neighbors[cell].select { |other| unknown?(other) }
      Constraint.new(cell, numbers[cell] - flags, unknown_cells) unless unknown_cells.empty?
    end
  end

  def deduce
    constraints = self.constraints
    result = Deduction.new
    (1..2).each do |rule|
      constraints.each do |constraint|
        target = rule == 1 ? 0 : constraint.unknown.length
        next unless constraint.remaining == target

        reason = Reason.new(:single, constraint.cell, nil)
        constraint.unknown.each { |cell| result.add(rule == 1, cell, reason) }
      end
      return result unless result.empty?
    end
    at = Array.new(cells)
    constraints.each { |constraint| at[constraint.cell] = constraint }
    constraints.each do |a|
      ax, ay = a.cell % width, a.cell / width
      # Nonempty subset pairs share a neighbor, so their centers are within two cells.
      ([0, ay - 2].max..[height - 1, ay + 2].min).each do |y|
        ([0, ax - 2].max..[width - 1, ax + 2].min).each do |x|
          b = at[y * width + x]
          next unless b && a.unknown.length < b.unknown.length && a.unknown.all? { |cell| b.unknown.include?(cell) }

          difference = b.unknown - a.unknown
          remaining = b.remaining - a.remaining
          next unless remaining.zero? || remaining == difference.length

          reason = Reason.new(:subset, a.cell, b.cell)
          difference.each { |cell| result.add(remaining.zero?, cell, reason) }
        end
      end
    end
    return result unless result.empty?

    if state == :playing && self.remaining.zero?
      reason = Reason.new(:count, nil, nil)
      cells.times { |cell| result.add(true, cell, reason) if unknown?(cell) }
    end
    result
  end

  def hint
    result = deduce
    if !result.safe.empty?
      cell = result.safe.keys.min
      puts "hint safe #{coord(cell)} by #{result.safe[cell].text(self)}"
    elsif !result.mines.empty?
      cell = result.mines.keys.min
      puts "hint mine #{coord(cell)} by #{result.mines[cell].text(self)}"
    else
      puts 'hint none'
    end
  end

  def auto_play(safety)
    total = AutoResult.new
    while state == :playing
      result = deduce
      break if result.empty?

      total.rounds += 1
      result.safe.keys.sort.each do |cell|
        next if revealed[cell]

        moves << Move.new(:auto_reveal, cell)
        total.opened += reveal(cell, safety)
        check_win
        return total if finished?
      end
      result.mines.keys.sort.each do |cell|
        next unless unknown?(cell)

        marks[cell] = :flag
        total.flagged += 1
        moves << Move.new(:auto_flag, cell)
      end
    end
    total
  end

  def solve(safety)
    total = AutoResult.new
    until finished?
      step = auto_play(safety)
      total.rounds += step.rounds
      total.flagged += step.flagged
      total.opened += step.opened
      break if finished?

      frontier = Frontier.new(self)
      frontier.components.each_index { |id| frontier.count(id) }
      unknown_count = (0...cells).count { |cell| unknown?(cell) }
      remaining_count = [remaining, 0].max
      choice = nil
      best_numerator, best_denominator = 0, 1
      cells.times do |cell|
        next unless unknown?(cell)

        id = frontier.component_of[cell]
        numerator = id.negative? ? remaining_count : frontier.ways[cell]
        denominator = id.negative? ? unknown_count : frontier.components[id].configs
        next if denominator.zero?

        if choice.nil? || numerator * best_denominator < best_numerator * denominator
          choice = cell
          best_numerator, best_denominator = numerator, denominator
        end
      end
      break if choice.nil?

      total.guesses += 1
      moves << Move.new(:guess, choice)
      total.opened += reveal(choice, safety)
      check_win
    end
    total
  end

  def probability(cell)
    frontier = Frontier.new(self)
    id = frontier.component_of[cell]
    if id.negative?
      puts "prob #{coord(cell)} unconstrained"
      return
    end
    frontier.count(id)
    component = frontier.components[id]
    if component.configs.zero?
      puts "prob #{coord(cell)} inconsistent"
    else
      puts "prob #{coord(cell)} #{fraction(frontier.ways[cell], component.configs)} size #{component.cells.length} configs #{component.configs}"
    end
  end

  def frontier_report
    frontier = Frontier.new(self)
    puts "frontier #{frontier.components.sum { |component| component.cells.length }} components #{frontier.components.length}"
    frontier.components.each_with_index do |component, id|
      frontier.count(id)
      start = "component #{coord(component.cells.first)} size #{component.cells.length}"
      if component.configs.zero?
        puts "#{start} inconsistent"
      else
        puts "#{start} configs #{component.configs} min #{component.minimum} max #{component.maximum}"
      end
    end
  end

  def replay(count, safety)
    copy = dup
    copy.restart
    moves.first(count).each do |move|
      cell = move.cell
      case move.kind
      when :reveal, :auto_reveal, :guess then copy.reveal(cell, safety)
      when :chord then copy.chord(cell, safety)
      when :flag, :auto_flag then copy.marks[cell] = :flag
      when :unflag then copy.marks[cell] = :none
      when :question then copy.marks[cell] = copy.marks[cell] == :question ? :none : :question
      end
      copy.check_win
    end
    puts "replay #{count}/#{moves.length}"
    copy.show
  end

  def board_info
    visited = Array.new(cells, false)
    openings = largest = isolated = 0
    cells.times do |cell|
      next if mine[cell]

      if numbers[cell].positive?
        isolated += 1 if neighbors[cell].none? { |other| !mine[other] && numbers[other].zero? }
      elsif !visited[cell]
        openings += 1
        covered = Array.new(cells, false)
        queue = [cell]
        head = 0
        visited[cell] = covered[cell] = true
        while head < queue.length
          current = queue[head]
          head += 1
          neighbors[current].each do |other|
            covered[other] = true
            next unless !mine[other] && numbers[other].zero? && !visited[other]

            visited[other] = true
            queue << other
          end
        end
        largest = [largest, covered.count(true)].max
      end
    end
    puts "3bv #{openings + isolated} openings #{openings} largest #{largest} mines #{mine_count} safe #{safe_cells}"
  end

  def process(command, cell, value, safety)
    if %w[REVEAL FLAG UNFLAG QUESTION PROB].include?(command)
      raise CommandError, 'already revealed' if revealed[cell]
      raise CommandError, 'flagged' if %w[REVEAL PROB].include?(command) && marks[cell] == :flag
      raise CommandError, 'already flagged' if command == 'FLAG' && marks[cell] == :flag
      raise CommandError, 'not flagged' if command == 'UNFLAG' && marks[cell] != :flag
    end
    case command
    when 'RESTART'
      restart
      puts "restart #{width}x#{height} mines #{mine_count}"
    when 'REVEAL'
      moves << Move.new(:reveal, cell)
      count = reveal(cell, safety)
      unless state == :lost
        puts "revealed #{count}"
        check_win
      end
      ending_output
    when 'FLAG'
      marks[cell] = :flag
      moves << Move.new(:flag, cell)
      puts "flagged #{coord(cell)} left #{remaining}"
    when 'UNFLAG'
      marks[cell] = :none
      moves << Move.new(:unflag, cell)
      puts "unflagged #{coord(cell)} left #{remaining}"
    when 'QUESTION'
      moves << Move.new(:question, cell)
      marks[cell] = marks[cell] == :question ? :none : :question
      puts "#{marks[cell] == :none ? 'unmarked' : 'questioned'} #{coord(cell)} left #{remaining}"
    when 'CHORD'
      raise CommandError, 'not revealed' unless revealed[cell]
      raise CommandError, 'no number' if numbers[cell].zero?

      flags = neighbors[cell].count { |other| marks[other] == :flag }
      raise CommandError, "flags #{flags} of #{numbers[cell]}" if flags != numbers[cell]
      raise CommandError, 'nothing to reveal' if neighbors[cell].none? { |other| unknown?(other) }

      moves << Move.new(:chord, cell)
      count = chord(cell, safety)
      unless state == :lost
        puts "chorded #{count}"
        check_win
      end
      ending_output
    when 'UNDO'
      snapshot = undo.pop
      raise CommandError, 'nothing to undo' unless snapshot

      @revealed, @marks = snapshot.revealed, snapshot.marks
      # All operations append, so restoring the old prefix restores the move record.
      moves.slice!(snapshot.moves, moves.length - snapshot.moves)
      puts "undo #{snapshot.command.downcase} moves #{moves.length}"
    when 'SHOW' then show
    when 'STATUS'
      puts "status #{state} left #{remaining} moves #{moves.length} revealed #{opened}/#{safe_cells}"
    when 'CELL'
      if revealed[cell]
        flags = neighbors[cell].count { |other| marks[other] == :flag }
        unknown_count = neighbors[cell].count { |other| unknown?(other) }
        puts "cell #{coord(cell)} number #{numbers[cell]} flags #{flags} unknown #{unknown_count}"
      else
        open_count = neighbors[cell].count { |other| revealed[other] }
        puts "cell #{coord(cell)} hidden mark #{marks[cell]} open #{open_count}"
      end
    when 'HISTORY'
      puts "history #{moves.length}"
      count = [value, moves.length].min
      (moves.length - count...moves.length).each do |i|
        move = moves[i]
        puts "#{i + 1} #{move.kind.to_s.tr('_', '-')} #{coord(move.cell)}"
      end
    when 'REPLAY'
      raise CommandError, "no move #{value}" if value > moves.length

      replay(value, safety)
    when 'HINT' then hint
    when 'AUTO', 'SOLVE'
      result = command == 'AUTO' ? auto_play(safety) : solve(safety)
      prefix = command == 'AUTO' ? 'auto' : "solve guesses #{result.guesses}"
      puts "#{prefix} rounds #{result.rounds} flagged #{result.flagged} revealed #{result.opened}"
      ending_output
    when 'ANALYZE'
      copy = dup
      result = copy.auto_play(safety)
      case copy.state
      when :lost then puts "analyze boom #{copy.coord(copy.exploded)} rounds #{result.rounds}"
      when :won then puts "analyze clear rounds #{result.rounds}"
      else puts "analyze stuck rounds #{result.rounds} revealed #{copy.opened}/#{copy.safe_cells}"
      end
    when 'PROB' then probability(cell)
    when 'FRONTIER' then frontier_report
    when 'BOARDINFO' then board_info
    end
  end
end

class Component
  attr_reader :cells
  attr_accessor :configs, :minimum, :maximum

  def initialize
    @cells = []
    @configs = @minimum = @maximum = 0
  end
end

class Frontier
  attr_reader :component_of, :components, :ways

  def initialize(game)
    @constraints = game.constraints
    @component_of = Array.new(game.cells, -1)
    @components = []
    @ways = Array.new(game.cells, 0)
    parent = (0...game.cells).to_a
    ids = Array.new(game.cells, -1)
    present = Array.new(game.cells, false)
    @constraints.each do |constraint|
      constraint.unknown.each do |cell|
        present[cell] = true
        left = root(parent, cell)
        right = root(parent, constraint.unknown.first)
        parent[left] = right
      end
    end
    game.cells.times do |cell|
      next unless present[cell]

      representative = root(parent, cell)
      if ids[representative].negative?
        ids[representative] = components.length
        components << Component.new
      end
      id = ids[representative]
      component_of[cell] = id
      components[id].cells << cell
    end
  end

  def count(id)
    component = components[id]
    local = Array.new(component_of.length)
    component.cells.each_with_index { |cell, i| local[cell] = i }
    restrictions = @constraints.filter_map do |constraint|
      next unless component_of[constraint.unknown.first] == id

      mask = constraint.unknown.reduce(0) { |bits, cell| bits | (1 << local[cell]) }
      Restriction.new(mask, constraint.remaining)
    end
    search = ConfigurationSearch.new(component.cells.length, restrictions)
    search.visit(0, 0)
    component.configs = search.configs
    component.minimum = search.minimum
    component.maximum = search.maximum
    component.cells.each_with_index { |cell, i| ways[cell] = search.ways[i] }
  end

  private

  def root(parent, cell)
    while parent[cell] != cell
      parent[cell] = parent[parent[cell]]
      cell = parent[cell]
    end
    cell
  end
end

class ConfigurationSearch
  attr_reader :configs, :minimum, :maximum, :ways

  def initialize(size, restrictions)
    @size, @restrictions = size, restrictions
    @ways = Array.new(size, 0)
    @configs = @maximum = 0
    @minimum = size + 1
  end

  def visit(depth, mines)
    assigned = (1 << depth) - 1
    @restrictions.each do |constraint|
      used = bit_count(constraint.mask & mines)
      left = bit_count(constraint.mask & ~assigned)
      return if used > constraint.target || used + left < constraint.target
    end
    if depth == @size
      count = bit_count(mines)
      @configs += 1
      @minimum = [minimum, count].min
      @maximum = [maximum, count].max
      @size.times { |i| ways[i] += 1 unless (mines & (1 << i)).zero? }
    else
      visit(depth + 1, mines)
      visit(depth + 1, mines | (1 << depth))
    end
  end
end

class Statistics
  def initialize
    @played = @won = @lost = @streak = @best = 0
    @fastest = nil
  end

  def finish(game)
    @played += 1
    if game.state == :won
      @won += 1
      @streak += 1
      @best = [@best, @streak].max
      @fastest = @fastest.nil? ? game.moves.length : [@fastest, game.moves.length].min
    else
      @lost += 1
      @streak = 0
    end
  end

  def show
    rate = @played.zero? ? '-' : "#{@won * 100 / @played}%"
    puts "stats played #{@played} won #{@won} lost #{@lost} rate #{rate} streak #{@streak} best #{@best} fastest #{@fastest || '-'}"
  end
end

class Table
  def initialize
    @game = nil
    @safety = 'block'
    @stats = Statistics.new
  end

  def layout(width, height, rows)
    rows.each_with_index do |row, i|
      raise CommandError, "bad row #{i + 1}" unless row.length == width && /\A[*.]+\z/.match?(row)
    end
    count = rows.sum { |row| row.count('*') }
    raise CommandError, "bad mine count #{count}" if count.zero? || count == width * height

    @game = Game.new(width, height, count, 0, layout: rows)
    puts "layout #{width}x#{height} mines #{count}"
  end

  def execute(words)
    command = words.first
    raise CommandError, "unknown command #{command}" unless COMMANDS.key?(command)
    raise CommandError, 'bad arguments' unless words.length == COMMANDS[command] + 1

    values = []
    if command == 'PRESET'
      preset = PRESETS[words[1]]
      raise CommandError, 'bad arguments' unless preset

      values = [*preset, number_word(words[2])]
    elsif command == 'SAFETY'
      raise CommandError, 'bad arguments' unless %w[block cell none].include?(words[1])
    else
      values = words.drop(1).map { |word| number_word(word) }
    end
    if command == 'NEW' || command == 'PRESET'
      width, height, mines, seed = values
      unless (1..30).cover?(width) && (1..30).cover?(height) && mines >= 1 && mines <= width * height - 9 && (1..2_147_483_646).cover?(seed)
        raise CommandError, 'bad value'
      end
      @game = Game.new(width, height, mines, seed)
      puts "new #{width}x#{height} mines #{mines}"
      return
    end
    raise CommandError, 'bad value' if command == 'HISTORY' && values[0].zero?

    if command == 'SAFETY'
      @safety = words[1]
      puts "safety #{@safety}"
      return
    end
    if command == 'STATS'
      @stats.show
      return
    end
    raise CommandError, 'no game' unless @game

    has_cell = CELL_COMMANDS.include?(command)
    raise CommandError, 'out of range' if has_cell && (values[0] >= @game.width || values[1] >= @game.height)
    raise CommandError, 'game over' if UNFINISHED_COMMANDS.include?(command) && @game.finished?
    raise CommandError, 'not started' if %w[ANALYZE BOARDINFO].include?(command) && !@game.determined?

    snapshot = Snapshot.new(command, @game.revealed.dup, @game.marks.dup, @game.moves.length) if UNDO_COMMANDS.include?(command)
    was_finished = @game.finished?
    cell = has_cell ? values[1] * @game.width + values[0] : 0
    @game.process(command, cell, values[0], @safety)
    @game.undo << snapshot if snapshot && @game.moves.length > snapshot.moves
    @stats.finish(@game) if !was_finished && @game.finished?
  end
end

table = Table.new
$stdin.gets.to_i.times do
  words = $stdin.gets.chomp.split(' ')
  begin
    if words[0] == 'LAYOUT'
      width, height = words.drop(1).map(&:to_i)
      rows = Array.new(height) { $stdin.gets.chomp }
      table.layout(width, height, rows)
    else
      table.execute(words)
    end
  rescue CommandError => error
    puts "error: #{error.message}"
  end
end
