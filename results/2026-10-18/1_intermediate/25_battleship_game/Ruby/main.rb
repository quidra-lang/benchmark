
class CommandError < StandardError; end

SHIP_NAMES = %w[CARRIER BATTLESHIP CRUISER SUBMARINE DESTROYER].freeze
SHIP_LENGTHS = [5, 4, 3, 3, 2].freeze
SHIP_SYMBOLS = 'CBRSD'
STRATEGIES = %w[HUNT PROB RANDOM].freeze
SETUP_COMMANDS = %w[PLACE REMOVE AUTOPLACE LAYOUT REEF SALVO CHAIN TOUCH].freeze
TURN_COMMANDS = %w[FIRE AI TORPEDO SONAR].freeze
LINE_DIRECTIONS = [[0, 1].freeze, [1, 0].freeze].freeze
STACK_DIRECTIONS = [[0, -1].freeze, [1, 0].freeze, [0, 1].freeze, [-1, 0].freeze].freeze
VIEW_SYMBOLS = { reef: '~', unattacked: '.', miss: 'o', hit: 'x', sunk: '#' }.freeze

def coordinate(cell) = "#{(65 + cell / 10).chr}#{cell % 10 + 1}"
def parse_cell(text) = (text.ord - 65) * 10 + text[1..].to_i - 1
def advance(state) = 48_271 * state % 2_147_483_647
def switch_name(enabled) = enabled ? 'ON' : 'OFF'

def step(cell, dr, dc)
  row, column = cell / 10 + dr, cell % 10 + dc
  row * 10 + column if row.between?(0, 9) && column.between?(0, 9)
end

NEIGHBORS = Array.new(100) do |cell|
  (-1..1).flat_map do |dr|
    (-1..1).filter_map { |dc| step(cell, dr, dc) unless dr.zero? && dc.zero? }
  end.freeze
end.freeze

Ship = Data.define(:cells) do
  def range = "#{coordinate(cells.first)}-#{coordinate(cells.last)}"
end

def position(start, horizontal, length)
  return if (horizontal ? start % 10 : start / 10) + length > 10

  delta = horizontal ? 1 : 10
  Ship.new(Array.new(length) { |i| start + i * delta }.freeze)
end

Shot = Data.define(:kind, :ship) do
  def hit? = kind == :hit || kind == :sunk
  def text = kind == :sunk ? "SUNK #{SHIP_NAMES[ship]}" : kind.to_s.upcase
end

Choice = Data.define(:cell, :info, :random)
MatchResult = Data.define(:winner, :shots, :hits)

Stats = Struct.new(:shots, :hits, :sunk, :turns, :streak, :longest) do
  def initialize = super(0, 0, 0, 0, 0, 0)

  def record(result)
    self.shots += 1
    if result.hit?
      self.hits += 1
      self.streak += 1
      self.longest = [longest, streak].max
    else
      self.streak = 0
    end
    self.sunk += 1 if result.kind == :sunk
  end
end

class Player
  attr_reader :fleet, :board, :attacked, :candidates, :stats
  attr_accessor :random, :controller, :torpedo_used, :sonar_used, :wins

  def initialize(seed)
    @fleet = Array.new(5)
    @board = Array.new(100)
    @attacked = Array.new(100, false)
    @candidates = []
    @stats = Stats.new
    @random = seed
    @controller = 'HUMAN'
    @torpedo_used = @sonar_used = false
    @wins = 0
  end

  def sunk?(index) = fleet[index] && fleet[index].cells.all? { |cell| attacked[cell] }
  def placed = fleet.count { |ship| ship }
  def afloat = fleet.each_index.count { |index| fleet[index] && !sunk?(index) }

  def set_ship(index, ship)
    fleet[index]&.cells&.each { |cell| board[cell] = nil }
    fleet[index] = ship
    ship&.cells&.each { |cell| board[cell] = index }
  end

  def clear_fleet
    fleet.each_index { |index| set_ship(index, nil) }
  end
end

View = Data.define(:cells, :excluded, :remaining) do
  def candidate?(cell)
    cell && cell.between?(0, 99) && cells[cell] == :unattacked && !excluded[cell]
  end

  def scores
    result = Array.new(100, 0)
    remaining.each do |ship|
      100.times do |start|
        [true, false].each do |horizontal|
          placement = position(start, horizontal, SHIP_LENGTHS[ship])
          next unless placement

          possible = placement.cells.all? do |cell|
            !excluded[cell] && (cells[cell] == :unattacked || cells[cell] == :hit)
          end
          next unless possible

          weight = 1 + 10 * placement.cells.count { |cell| cells[cell] == :hit }
          placement.cells.each { |cell| result[cell] += weight }
        end
      end
    end
    result
  end

  def best(scores)
    cells.each_index.select { |cell| cells[cell] == :unattacked }
         .min_by { |cell| [-scores[cell], cell] }
  end
end

class Game
  attr_reader :players, :reefs, :phase, :current, :winner
  attr_accessor :salvo, :chain, :touch

  def initialize(salvo: false, chain: false, touch: false, reefs: Array.new(100, false))
    @players = [Player.new(1), Player.new(2)]
    @reefs = reefs.dup
    @salvo, @chain, @touch = salvo, chain, touch
    @phase = :setup
    @current = 0
    @winner = nil
  end

  def allowance(player) = salvo ? players[player].afloat : 1

  def check_setup
    raise CommandError, 'setup closed' unless phase == :setup
  end

  def check_turn(player)
    raise CommandError, 'game over' if phase == :over
    raise CommandError, 'fleets not ready' if phase == :setup && players.any? { |owner| owner.placed != 5 }
    raise CommandError, 'not your turn' unless player == current
  end

  def placement_problem(player, ship)
    return 'out of bounds' unless ship
    return 'on reef' if ship.cells.any? { |cell| reefs[cell] }

    board = players[player].board
    overlap = ship.cells.filter_map { |cell| board[cell] }.min
    return "overlaps #{SHIP_NAMES[overlap]}" if overlap

    unless touch
      adjacent = ship.cells.flat_map { |cell| NEIGHBORS[cell] }.filter_map { |cell| board[cell] }.min
      return "touches #{SHIP_NAMES[adjacent]}" if adjacent
    end
    nil
  end

  def auto_place(player, seed)
    owner = players[player]
    owner.random = seed
    owner.clear_fleet
    attempts = 0
    SHIP_LENGTHS.each_with_index do |length, index|
      loop do
        attempts += 1
        owner.random = advance(owner.random)
        horizontal = owner.random.even?
        owner.random = advance(owner.random)
        k = owner.random % (10 * (11 - length))
        start = horizontal ? k / (11 - length) * 10 + k % (11 - length) : k
        ship = position(start, horizontal, length)
        next if placement_problem(player, ship)

        owner.set_ship(index, ship)
        break
      end
    end
    attempts
  end

  def layout(player, text)
    grid = text.delete('/')
    fleet = SHIP_NAMES.each_index.map do |index|
      cells = (0...100).select { |cell| grid[cell] == SHIP_SYMBOLS[index] }
      name, length = SHIP_NAMES[index], SHIP_LENGTHS[index]
      raise CommandError, "#{name} has #{cells.length} cells" unless cells.length == length

      horizontal = cells.each_with_index.all? { |cell, i| cell == cells[0] + i && cell / 10 == cells[0] / 10 }
      vertical = cells.each_with_index.all? { |cell, i| cell == cells[0] + 10 * i }
      raise CommandError, "#{name} not straight" unless horizontal || vertical
      raise CommandError, "#{name} on reef" if cells.any? { |cell| reefs[cell] }

      Ship.new(cells.freeze)
    end
    unless touch
      5.times do |first|
        (first + 1...5).each do |second|
          adjacent = fleet[first].cells.any? { |cell| NEIGHBORS[cell].intersect?(fleet[second].cells) }
          raise CommandError, "#{SHIP_NAMES[first]} touches #{SHIP_NAMES[second]}" if adjacent
        end
      end
    end
    players[player].clear_fleet
    fleet.each_with_index { |ship, index| players[player].set_ship(index, ship) }
  end

  def placed_lines(player)
    players[player].fleet.each_with_index.map do |ship, index|
      "PLACED #{player + 1} #{SHIP_NAMES[index]} #{ship.range}"
    end
  end

  def add_reef(cell)
    raise CommandError, "reef exists at #{coordinate(cell)}" if reefs[cell]

    players.each_with_index do |owner, player|
      index = owner.board[cell]
      raise CommandError, "#{coordinate(cell)} occupied by #{player + 1} #{SHIP_NAMES[index]}" if index
    end
    reefs[cell] = true
  end

  def view(player)
    opponent = players[1 - player]
    sunk = SHIP_NAMES.each_index.map { |index| opponent.sunk?(index) }
    cells = Array.new(100) do |cell|
      ship = opponent.board[cell]
      if reefs[cell]
        :reef
      elsif !opponent.attacked[cell]
        :unattacked
      elsif ship.nil?
        :miss
      else
        sunk[ship] ? :sunk : :hit
      end
    end
    excluded = Array.new(100, false)
    unless touch
      100.times do |cell|
        NEIGHBORS[cell].each { |neighbor| excluded[neighbor] = true } if cells[cell] == :sunk
      end
    end
    remaining = SHIP_NAMES.each_index.reject { |index| sunk[index] }
    View.new(cells.freeze, excluded.freeze, remaining.freeze)
  end

  def choose(player, strategy)
    sight = view(player)
    random = players[player].random
    case strategy
    when 'PROB'
      scores = sight.scores
      cell = sight.best(scores)
      return Choice.new(cell, scores[cell], random)
    when 'RANDOM'
      candidates = (0...100).select { |cell| sight.candidate?(cell) }
      random = advance(random)
      return Choice.new(candidates[random % candidates.length], candidates.length, random)
    end

    100.times do |cell|
      next unless sight.cells[cell] == :hit

      LINE_DIRECTIONS.each do |dr, dc|
        front = step(cell, dr, dc)
        next unless front && sight.cells[front] == :hit

        front = step(front, dr, dc) while front && sight.cells[front] == :hit
        back = step(cell, -dr, -dc)
        return Choice.new(front, 'LINE', random) if sight.candidate?(front)
        return Choice.new(back, 'LINE', random) if sight.candidate?(back)
      end
    end
    players[player].candidates.reverse_each do |cell|
      return Choice.new(cell, 'STACK', random) if sight.candidate?(cell)
    end
    shortest = sight.remaining.map { |index| SHIP_LENGTHS[index] }.min
    cell = (0...100).find { |at| sight.candidate?(at) && ((at / 10 + at % 10) % shortest).zero? }
    Choice.new(cell, 'PARITY', random)
  end

  def shoot(player, cell)
    owner, opponent = players[player], players[1 - player]
    if opponent.attacked[cell]
      result = Shot.new(:already, nil)
    else
      opponent.attacked[cell] = true
      index = opponent.board[cell]
      result = if index.nil?
                 Shot.new(:miss, nil)
               elsif opponent.sunk?(index)
                 Shot.new(:sunk, index)
               else
                 Shot.new(:hit, nil)
               end
      if result.kind == :hit
        STACK_DIRECTIONS.each do |dr, dc|
          neighbor = step(cell, dr, dc)
          owner.candidates << neighbor if neighbor
        end
      end
    end
    owner.stats.record(result)
    result
  end

  def finish_turn(player, hit, mode, output)
    players[player].stats.turns += 1
    if players[1 - player].afloat.zero?
      @phase, @winner = :over, player
      players[player].wins += 1
      output << "WINNER #{player + 1}" if mode == :normal
    else
      @current = chain && hit ? player : 1 - player
    end
  end

  def shooting_turn(player, strategy: nil, targets: nil, output: nil, mode: :normal)
    count = allowance(player)
    @phase = :battle
    hit = false
    count.times do |i|
      if strategy
        choice = choose(player, strategy)
        players[player].random = choice.random
        cell = choice.cell
      else
        cell = targets[i]
      end
      result = shoot(player, cell)
      hit ||= result.hit?
      output << "SHOT #{player + 1} #{coordinate(cell)} #{result.text}" if mode == :normal
      if mode == :match && result.kind == :sunk
        output << "SINK #{player + 1} #{SHIP_NAMES[result.ship]} #{players[player].stats.shots}"
      end
      break if players[1 - player].afloat.zero?
    end
    finish_turn(player, hit, mode, output)
  end

  def torpedo(player, row, west, output)
    @phase = :battle
    players[player].torpedo_used = true
    opponent = players[1 - player]
    text, shot = 'MISS', nil
    10.times do |i|
      cell = row * 10 + (west ? i : 9 - i)
      if reefs[cell]
        text = "REEF #{coordinate(cell)}"
        break
      end
      if opponent.board[cell]
        shot = shoot(player, cell)
        text = "#{shot.text} #{coordinate(cell)}"
        break
      end
      opponent.attacked[cell] = true
    end
    players[player].stats.record(Shot.new(:miss, nil)) unless shot
    output << "TORPEDO #{player + 1} #{(65 + row).chr} #{west ? 'W' : 'E'} #{text}"
    finish_turn(player, shot&.hit?, :normal, output)
  end

  def sonar(player, cell, output)
    @phase = :battle
    players[player].sonar_used = true
    opponent = players[1 - player]
    count = [cell, *NEIGHBORS[cell]].count { |at| opponent.board[at] && !opponent.attacked[at] }
    output << "SONAR #{player + 1} #{coordinate(cell)} #{count}"
    finish_turn(player, false, :normal, output)
  end

  def automatic(output)
    while phase == :battle && players[current].controller != 'HUMAN'
      shooting_turn(current, strategy: players[current].controller, output: output)
    end
  end

  def resign(player)
    raise CommandError, 'not in battle' unless phase == :battle

    @phase, @winner = :over, 1 - player
    players[winner].wins += 1
    ["RESIGN #{player + 1}", "WINNER #{winner + 1}"]
  end

  def show(player, radar)
    output = ["#{radar ? 'RADAR' : 'BOARD'} #{player + 1}", '  1 2 3 4 5 6 7 8 9 10']
    sight = view(player) if radar
    owner = players[player]
    10.times do |row|
      symbols = Array.new(10) do |column|
        cell = row * 10 + column
        ship = owner.board[cell]
        if radar
          VIEW_SYMBOLS[sight.cells[cell]]
        elsif reefs[cell]
          '~'
        elsif ship
          owner.attacked[cell] ? SHIP_SYMBOLS[ship].downcase : SHIP_SYMBOLS[ship]
        else
          owner.attacked[cell] ? 'o' : '.'
        end
      end
      output << "#{(65 + row).chr} #{symbols.join(' ')}"
    end
    output
  end

  def density(player)
    sight = view(player)
    scores = sight.scores
    output = ["DENSITY #{player + 1}", ' ' + (1..10).map { |column| column.to_s.rjust(5) }.join]
    10.times do |row|
      values = Array.new(10) do |column|
        cell = row * 10 + column
        value = case sight.cells[cell]
                when :unattacked then scores[cell]
                when :reef then '~'
                else '-'
                end
        value.to_s.rjust(5)
      end
      output << "#{(65 + row).chr}#{values.join}"
    end
    cell = sight.best(scores)
    output << "BEST #{coordinate(cell)} #{scores[cell]}"
  end

  def export_fleet(player)
    players[player].board.each_slice(10).map do |row|
      row.map { |ship| ship ? SHIP_SYMBOLS[ship] : '.' }.join
    end.join('/')
  end

  def fleet_lines(player)
    owner = players[player]
    output = ["FLEET #{player + 1} afloat #{owner.afloat}"]
    owner.fleet.each_with_index do |ship, index|
      name = SHIP_NAMES[index]
      if ship
        hits = ship.cells.count { |cell| owner.attacked[cell] }
        output << "#{name} #{ship.range} #{hits}/#{SHIP_LENGTHS[index]} #{owner.sunk?(index) ? 'SUNK' : 'AFLOAT'}"
      else
        output << "#{name} unplaced"
      end
    end
    output
  end

  def status
    prefix = "STATUS #{phase.to_s.upcase} salvo #{switch_name(salvo)} chain #{switch_name(chain)} touch #{switch_name(touch)} reefs #{reefs.count(true)}"
    suffix = case phase
             when :setup then "placed #{players[0].placed} #{players[1].placed}"
             when :battle then "turn #{current + 1} shots #{allowance(current)} afloat #{players[0].afloat} #{players[1].afloat}"
             else "winner #{winner + 1} afloat #{players[0].afloat} #{players[1].afloat}"
             end
    "#{prefix} #{suffix}"
  end

  def stats_lines
    players.each_with_index.map do |player, index|
      stats = player.stats
      accuracy = stats.shots.zero? ? '-' : "#{stats.hits * 100 / stats.shots}%"
      "STATS #{index + 1} shots #{stats.shots} hits #{stats.hits} sunk #{stats.sunk} turns #{stats.turns} streak #{stats.longest} accuracy #{accuracy} wins #{player.wins}"
    end
  end

  def simulate(first_seed, second_seed, first_strategy, second_strategy, sinks: nil)
    game = Game.new(salvo: salvo, chain: chain, touch: touch, reefs: reefs)
    game.auto_place(0, first_seed)
    game.auto_place(1, second_seed)
    strategies = [first_strategy, second_strategy]
    until game.phase == :over
      game.shooting_turn(game.current, strategy: strategies[game.current], output: sinks, mode: sinks ? :match : :silent)
    end
    MatchResult.new(game.winner, game.players.map { |player| player.stats.shots }.freeze,
                    game.players.map { |player| player.stats.hits }.freeze)
  end
end

class Program
  def initialize = @game = Game.new

  def execute(words)
    command = words[0]
    game = @game
    game.check_setup if SETUP_COMMANDS.include?(command)
    if TURN_COMMANDS.include?(command)
      player = words[1].to_i - 1
      game.check_turn(player)
      output = []
      case command
      when 'FIRE'
        targets = words.drop(2).map { |word| parse_cell(word) }
        allowance = game.allowance(player)
        raise CommandError, "expected #{allowance} shots" unless targets.length == allowance

        targets.each do |cell|
          raise CommandError, "reef at #{coordinate(cell)}" if game.reefs[cell]
        end
        game.shooting_turn(player, targets: targets, output: output)
      when 'AI'
        game.shooting_turn(player, strategy: words[2], output: output)
      when 'TORPEDO'
        raise CommandError, 'torpedo used' if game.players[player].torpedo_used

        game.torpedo(player, words[2].ord - 65, words[3] == 'W', output)
      when 'SONAR'
        raise CommandError, 'sonar used' if game.players[player].sonar_used

        game.sonar(player, parse_cell(words[2]), output)
      end
      game.automatic(output)
      return output
    end

    case command
    when 'NEW'
      wins = game.players.map(&:wins)
      @game = Game.new
      wins.each_with_index { |count, player| @game.players[player].wins = count }
      ['NEW']
    when 'PLACE'
      player, index = words[1].to_i - 1, SHIP_NAMES.index(words[2])
      raise CommandError, "#{words[2]} already placed" if game.players[player].fleet[index]

      ship = position(parse_cell(words[3]), words[4] == 'H', SHIP_LENGTHS[index])
      problem = game.placement_problem(player, ship)
      raise CommandError, problem if problem

      game.players[player].set_ship(index, ship)
      ["PLACED #{player + 1} #{words[2]} #{ship.range}"]
    when 'REMOVE'
      player, index = words[1].to_i - 1, SHIP_NAMES.index(words[2])
      raise CommandError, "#{words[2]} not placed" unless game.players[player].fleet[index]

      game.players[player].set_ship(index, nil)
      ["REMOVED #{player + 1} #{words[2]}"]
    when 'AUTOPLACE'
      player = words[1].to_i - 1
      attempts = game.auto_place(player, words[2].to_i)
      ["AUTOPLACE #{player + 1} attempts #{attempts}", *game.placed_lines(player)]
    when 'LAYOUT'
      player = words[1].to_i - 1
      game.layout(player, words[2])
      ["LAYOUT #{player + 1}", *game.placed_lines(player)]
    when 'REEF'
      cell = parse_cell(words[1])
      game.add_reef(cell)
      ["REEF #{coordinate(cell)}"]
    when 'SALVO', 'CHAIN', 'TOUCH'
      game.public_send("#{command.downcase}=", words[1] == 'ON')
      ["#{command} #{words[1]}"]
    when 'CONTROL'
      player = words[1].to_i - 1
      game.players[player].controller = words[2]
      ["CONTROL #{player + 1} #{words[2]}"]
    when 'SEED'
      player, seed = words[1].to_i - 1, words[2].to_i
      game.players[player].random = seed
      ["SEED #{player + 1} #{seed}"]
    when 'RESIGN'
      game.resign(words[1].to_i - 1)
    when 'HINT'
      raise CommandError, 'game over' if game.phase == :over

      player = words[1].to_i - 1
      choice = game.choose(player, words[2])
      ["HINT #{player + 1} #{words[2]} #{coordinate(choice.cell)} #{choice.info}"]
    when 'DENSITY'
      raise CommandError, 'game over' if game.phase == :over

      game.density(words[1].to_i - 1)
    when 'SHOW', 'RADAR' then game.show(words[1].to_i - 1, command == 'RADAR')
    when 'EXPORT'
      player = words[1].to_i - 1
      ["EXPORT #{player + 1} #{game.export_fleet(player)}"]
    when 'FLEET' then game.fleet_lines(words[1].to_i - 1)
    when 'STATUS' then [game.status]
    when 'STATS' then game.stats_lines
    when 'MATCH', 'SERIES', 'TOURNEY' then simulation(words)
    end
  end

  def simulation(words)
    if words[0] == 'MATCH'
      output = ["MATCH 1 #{words[3]} 2 #{words[4]}"]
      match = @game.simulate(words[1].to_i, words[2].to_i, words[3], words[4], sinks: output)
      output << "RESULT winner #{match.winner + 1} shots #{match.shots.join(' ')} hits #{match.hits.join(' ')}"
      return output
    end

    count, random = words[1].to_i, words[2].to_i
    if words[0] == 'SERIES'
      wins, shots, fastest = [0, 0], [0, 0], [nil, nil]
      count.times do
        random = advance(random)
        first_seed = random
        random = advance(random)
        match = @game.simulate(first_seed, random, words[3], words[4])
        wins[match.winner] += 1
        2.times { |player| shots[player] += match.shots[player] }
        winning_shots = match.shots[match.winner]
        fastest[match.winner] = [fastest[match.winner] || winning_shots, winning_shots].min
      end
      return ["SERIES #{count} wins #{wins.join(' ')} shots #{shots.join(' ')} fastest #{fastest.map { |value| value || '-' }.join(' ')}"]
    end

    wins, shots = [0, 0, 0], [0, 0, 0]
    STRATEGIES.each_index do |first|
      STRATEGIES.each_index do |second|
        next if first == second

        count.times do
          random = advance(random)
          first_seed = random
          random = advance(random)
          match = @game.simulate(first_seed, random, STRATEGIES[first], STRATEGIES[second])
          wins[match.winner.zero? ? first : second] += 1
          shots[first] += match.shots[0]
          shots[second] += match.shots[1]
        end
      end
    end
    ranking = STRATEGIES.each_index.sort_by { |index| [-wins[index], shots[index], STRATEGIES[index]] }
    output = ["TOURNEY #{count}"]
    ranking.each_with_index do |index, rank|
      output << "#{rank + 1} #{STRATEGIES[index]} wins #{wins[index]} shots #{shots[index]}"
    end
    output
  end
end

program = Program.new
$stdin.gets.to_i.times do
  begin
    $stdout.puts program.execute($stdin.gets.split)
  rescue CommandError => error
    $stdout.puts "ERROR #{error.message}"
  end
end
