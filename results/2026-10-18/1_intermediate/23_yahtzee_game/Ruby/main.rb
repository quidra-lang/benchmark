CATEGORIES = %w[
  ONES TWOS THREES FOURS FIVES SIXES THREEKIND FOURKIND FULLHOUSE
  SMALL LARGE YAHTZEE CHANCE
].freeze
UPPER = CATEGORIES.first(6).freeze
LOWER = CATEGORIES.drop(6).freeze
FACES = (1..6).to_a.freeze
STRATEGIES = %w[KIND STRAIGHT HIGH UPPER].freeze
JOKERS = %w[FORCED FREE OFF].freeze
JOKER_POINTS = { 'FULLHOUSE' => 25, 'SMALL' => 30, 'LARGE' => 40 }.freeze
MODULUS = 2_147_483_647
MULTIPLIER = 48_271
PATTERNS = (0...32).map { |i| i.to_s(2).rjust(5, '0').chars.map { |c| c == '1' } }.freeze
FACTORIALS = [1, 1, 2, 6, 24, 120].freeze

class CommandError < StandardError; end

def require_value(condition, message)
  raise CommandError, message unless condition
end

def integer_word(text, minimum, maximum)
  require_value(/\A-?(?:0|[1-9][0-9]*)\z/.match?(text) && text != '-0', "bad value #{text}")
  value = text.to_i
  require_value(value.between?(minimum, maximum), "bad value #{text}")
  value
end

def player_name(text)
  require_value(/\A[A-Z]{1,8}\z/.match?(text), "bad name #{text}")
  text
end

def hold_pattern(text)
  require_value(/\A[01]{5}\z/.match?(text), "bad pattern #{text}")
  text.chars.map { |mark| mark == '1' }
end

def category_name(text)
  require_value(CATEGORIES.include?(text), "bad category #{text}")
  text
end

def strategy_name(text)
  require_value(STRATEGIES.include?(text), "bad strategy #{text}")
  text
end

def face_text(faces)
  faces.empty? ? '-' : faces.join(' ')
end

def pattern_text(holds)
  holds.map { |v| v ? '1' : '0' }.join
end

def held_faces(faces, holds)
  faces.each_with_index.filter_map { |face, i| face if holds[i] }
end

def fraction_text(numerator, denominator)
  divisor = numerator.gcd(denominator)
  numerator /= divisor
  denominator /= divisor
  denominator == 1 ? numerator.to_s : "#{numerator}/#{denominator}"
end

def average_text(total, count)
  cents = count.zero? ? 0 : 100 * total / count
  "#{cents / 100}.#{(cents % 100).to_s.rjust(2, '0')}"
end

def yahtzee?(faces)
  faces.all? { |face| face == faces[0] }
end

def normal_score(category, faces)
  upper = UPPER.index(category)
  return (upper + 1) * faces.count(upper + 1) unless upper.nil?
  counts = FACES.map { |face| faces.count(face) }
  total = faces.sum
  case category
  when 'THREEKIND' then counts.max >= 3 ? total : 0
  when 'FOURKIND' then counts.max >= 4 ? total : 0
  when 'FULLHOUSE' then counts.include?(3) && counts.include?(2) ? 25 : 0
  when 'SMALL' then (1..3).any? { |start| (start...start + 4).all? { |v| faces.include?(v) } } ? 30 : 0
  when 'LARGE' then (1..2).any? { |start| (start...start + 5).all? { |v| faces.include?(v) } } ? 40 : 0
  when 'YAHTZEE' then yahtzee?(faces) ? 50 : 0
  else total
  end
end

def best_candidate(candidates)
  candidates.max_by { |_, score| score }
end

def most_frequent_face(faces)
  FACES.max_by { |face| [faces.count(face), face] }
end

def bot_holds(strategy, faces)
  return faces.map { |face| face >= 5 } if strategy == 'HIGH'
  if strategy == 'STRAIGHT'
    best_start = 0
    best_length = 0
    FACES.each do |start|
      length = 0
      length += 1 while faces.include?(start + length)
      if length.positive? && length >= best_length
        best_start, best_length = start, length
      end
    end
    if best_length >= 3
      holds = Array.new(5, false)
      (best_start...best_start + best_length).each { |v| holds[faces.index(v)] = true }
      return holds
    end
  end
  target = most_frequent_face(faces)
  faces.map { |face| face == target }
end

REROLLS = (0..5).map do |count|
  FACES.repeated_combination(count).map do |rolled|
    weight = FACTORIALS[count]
    FACES.each { |face| weight /= FACTORIALS[rolled.count(face)] }
    [rolled, weight]
  end
end.freeze

class DiceRoller
  attr_accessor :loaded
  attr_reader :counts
  def initialize(seed)
    @state = seed
    @loaded = []
    @counts = Array.new(6, 0)
  end

  def roll_die
    face = if @loaded.empty?
      @state = MULTIPLIER * @state % MODULUS
      @state % 6 + 1
    else
      @loaded.shift
    end
    @counts[face - 1] += 1
    face
  end
end

class Player
  attr_accessor :strategy, :yahtzee_bonus
  attr_reader :name, :boxes
  def initialize(name, strategy = 'KIND')
    @name, @strategy = name, strategy
    @boxes = CATEGORIES.to_h { |category| [category, nil] }
    @yahtzee_bonus = 0
  end

  def open_categories
    CATEGORIES.select { |category| @boxes[category].nil? }
  end

  def used_count
    13 - open_categories.length
  end

  def round
    used_count + 1
  end

  def upper_subtotal
    UPPER.sum { |category| @boxes[category] || 0 }
  end

  def upper_bonus
    upper_subtotal >= 63 ? 35 : 0
  end

  def total
    @boxes.values.compact.sum + upper_bonus + @yahtzee_bonus
  end
end

class Turn
  attr_accessor :seat, :rolls, :faces, :holds
  def initialize(seat, rolls = 0, faces = [], holds = Array.new(5, false))
    @seat, @rolls = seat, rolls
    @faces, @holds = faces.dup, holds.dup
  end

  def duplicate
    Turn.new(@seat, @rolls, @faces, @holds)
  end
end

ScoreEntry = Struct.new(:player, :category, :points, :bonus, :joker, :turn)

class Game
  attr_accessor :turn
  attr_reader :players, :rules, :roller, :entries, :redo_list
  def initialize(players, rules, roller)
    @players, @rules, @roller = players, rules, roller
    @turn = Turn.new(0)
    @entries, @redo_list = [], []
  end

  def finished?
    @turn.nil?
  end

  def current_player
    @players[@turn.seat]
  end

  def ranking
    @players.each_with_index.sort_by { |player, i| [-player.total, i] }.map(&:first)
  end

  def roll
    if @turn.rolls.zero?
      @turn.faces = Array.new(5) { @roller.roll_die }
    else
      5.times { |i| @turn.faces[i] = @roller.roll_die unless @turn.holds[i] }
    end
    @turn.rolls += 1
    @redo_list.clear
    "#{current_player.name} roll #{@turn.rolls}: #{face_text(@turn.faces)}"
  end

  def set_holds(holds)
    @turn.holds = holds.dup
    @redo_list.clear
    "#{current_player.name} holds #{pattern_text(holds)}: #{face_text(held_faces(@turn.faces, holds))}"
  end

  def joker_situation?(player, faces)
    @rules[:joker] != 'OFF' && yahtzee?(faces) && !player.boxes['YAHTZEE'].nil?
  end

  def allowed_categories(player, faces, joker)
    open = player.open_categories
    return open unless joker && @rules[:joker] == 'FORCED'
    upper = UPPER[faces[0] - 1]
    return [upper] if player.boxes[upper].nil?
    lower = open.select { |category| LOWER.include?(category) }
    lower.empty? ? open : lower
  end

  def points_to_enter(faces, category, joker)
    joker && JOKER_POINTS.key?(category) ? JOKER_POINTS.fetch(category) : normal_score(category, faces)
  end

  def candidates(player, faces)
    joker = joker_situation?(player, faces)
    allowed = allowed_categories(player, faces, joker)
    player.open_categories.map do |category|
      [category, allowed.include?(category) ? points_to_enter(faces, category, joker) : 0]
    end
  end

  def best(player, faces)
    best_candidate(candidates(player, faces))
  end

  def prepare_entry(category)
    player, faces = current_player, @turn.faces
    require_value(player.boxes[category].nil?, "#{category} already used")
    joker = joker_situation?(player, faces)
    unless allowed_categories(player, faces, joker).include?(category)
      upper = UPPER[faces[0] - 1]
      raise CommandError, player.boxes[upper].nil? ? "joker requires #{upper}" : 'joker requires lower box'
    end
    points = points_to_enter(faces, category, joker)
    bonus = yahtzee?(faces) && player.boxes['YAHTZEE'] == 50 ? 100 : 0
    ScoreEntry.new(player, category, points, bonus, joker, @turn.duplicate)
  end

  def score_line(entry, verb)
    player = entry.player
    parts = [player.name, verb, entry.points, 'in', entry.category]
    parts << 'joker' if entry.joker
    parts.concat(['ybonus', entry.bonus]) if entry.bonus.positive?
    subtotal = player.upper_subtotal + (UPPER.include?(entry.category) ? entry.points : 0)
    gain = player.upper_bonus.zero? && subtotal >= 63 ? 35 : 0
    parts.concat(['ubonus', gain]) if gain.positive?
    parts.concat(['total', player.total + entry.points + entry.bonus + gain])
    parts.join(' ')
  end

  def enter(entry)
    entry.player.boxes[entry.category] = entry.points
    entry.player.yahtzee_bonus += entry.bonus
    @entries << entry
  end

  def score(category)
    entry = prepare_entry(category)
    line = score_line(entry, 'scores')
    enter(entry)
    @redo_list.clear
    if @players.all? { |player| player.used_count == 13 }
      @turn = nil
      return [line, 'game over']
    end
    @turn = Turn.new((@turn.seat + 1) % @players.length)
    [line, "turn #{current_player.round} #{current_player.name}"]
  end

  def undo
    entry = @entries.pop
    entry.player.boxes[entry.category] = nil
    entry.player.yahtzee_bonus -= entry.bonus
    @redo_list << [@turn, entry]
    @turn = entry.turn.duplicate
    entry
  end

  def redo
    turn, entry = @redo_list.pop
    enter(entry)
    @turn = turn
    entry
  end

  def bot_category
    player, faces = current_player, @turn.faces
    if player.strategy == 'UPPER'
      face = most_frequent_face(faces)
      category = UPPER[face - 1]
      allowed = allowed_categories(player, faces, joker_situation?(player, faces))
      return category if faces.count(face) >= 3 && allowed.include?(category)
    end
    best(player, faces)[0]
  end

  def bot_turn
    lines = []
    lines << roll if @turn.rolls.zero?
    while @turn.rolls < @rules[:rolls]
      holds = bot_holds(current_player.strategy, @turn.faces)
      break if holds.all?
      lines << set_holds(holds)
      lines << roll
    end
    lines.concat(score(bot_category))
  end
end

class Advisor
  def initialize(game, player)
    @game, @player = game, player
    @values, @expectations = {}, {}
  end

  def value(hand, level)
    key = [level, hand.join]
    return @values.fetch(key) if @values.key?(key)
    score = if level.zero?
      @game.best(@player, hand)[1]
    else
      PATTERNS.map { |holds| expectation(held_faces(hand, holds).sort, level) }.max
    end
    @values[key] = score
  end

  def expectation(held, level)
    key = [level, held.join]
    return @expectations.fetch(key) if @expectations.key?(key)
    total = REROLLS[5 - held.length].sum do |rolled, weight|
      weight * value((held + rolled).sort, level - 1)
    end
    @expectations[key] = total * 6**held.length
  end

  def best_hold(faces, levels)
    best_holds, best_value = nil, -1
    PATTERNS.each do |holds|
      value = expectation(held_faces(faces, holds).sort, levels)
      best_holds, best_value = holds, value if value > best_value
    end
    [best_holds, best_value]
  end
end

class PlayerRecord
  attr_reader :games, :wins, :best, :total
  def initialize
    @games, @wins, @best, @total = 0, 0, 0, 0
  end

  def add(total, won)
    @games += 1
    @wins += 1 if won
    @best = [@best, total].max
    @total += total
  end
end

class SeatSummary
  attr_reader :strategy, :wins, :total, :best, :bonus, :yahtzee
  def initialize(strategy)
    @strategy = strategy
    @wins, @total, @best, @bonus, @yahtzee = 0, 0, 0, 0, 0
  end

  def add(player, won)
    score = player.total
    @wins += 1 if won
    @total += score
    @best = [@best, score].max
    @bonus += 1 if player.upper_bonus == 35
    @yahtzee += 1 if player.boxes['YAHTZEE'] == 50
  end
end

class YahtzeeTable
  attr_reader :output
  def initialize
    @rules = { rolls: 3, joker: 'FORCED' }
    @game = nil
    @records = {}
    @output = []
  end

  def emit(line)
    @output << line
  end

  def require_no_game
    require_value(@game.nil?, 'game in progress')
  end

  def require_game
    require_value(!@game.nil?, 'no game')
    @game
  end

  def require_turn
    game = require_game
    require_value(!game.finished?, 'game over')
    game
  end

  def require_rolled
    game = require_turn
    require_value(game.turn.rolls > 0, 'not rolled')
    game
  end

  def require_rolls_left
    game = require_rolled
    require_value(game.turn.rolls < @rules[:rolls], 'no rolls left')
    game
  end

  def set_rule(args)
    rule, value = args
    case rule
    when 'ROLLS'
      rolls = integer_word(value, 1, 4)
      require_no_game
      @rules[:rolls] = rolls
    when 'JOKER'
      require_value(JOKERS.include?(value), "bad value #{value}")
      require_no_game
      @rules[:joker] = value
    else raise CommandError, "unknown rule #{rule}"
    end
    emit("rule #{rule} #{value}")
  end

  def start_game(args)
    seed = integer_word(args[0], 1, MODULUS - 1)
    names = args.drop(1).map { |name| player_name(name) }
    require_value(names.length <= 6, 'too many players')
    require_no_game
    names.each_with_index do |name, index|
      require_value(!names.first(index).include?(name), "duplicate name #{name}")
    end
    @game = Game.new(names.map { |name| Player.new(name) }, @rules, DiceRoller.new(seed))
    emit("game seed #{seed} players #{names.join(' ')}")
    emit("turn 1 #{names[0]}")
  end

  def set_bot(args)
    name, strategy = player_name(args[0]), strategy_name(args[1])
    game = require_game
    player = game.players.find { |candidate| candidate.name == name }
    require_value(!player.nil?, "no player #{name}")
    player.strategy = strategy
    emit("bot #{name} #{strategy}")
  end

  def load(args)
    faces = args.map { |text| integer_word(text, 1, 6) }
    roller = require_game.roller
    roller.loaded.concat(faces)
    emit("loaded #{roller.loaded.length}")
  end

  def roll
    game = require_turn
    require_value(game.turn.rolls < @rules[:rolls], 'no rolls left')
    require_value(!game.turn.holds.all?, 'all dice held')
    emit(game.roll)
  end

  def hold(args)
    holds = hold_pattern(args[0])
    emit(require_rolls_left.set_holds(holds))
  end

  def keep(args)
    faces = args.map { |text| integer_word(text, 1, 6) }
    game = require_rolls_left
    holds = Array.new(5, false)
    faces.each do |face|
      index = game.turn.faces.each_index.find { |i| !holds[i] && game.turn.faces[i] == face }
      require_value(!index.nil?, "not showing #{face}")
      holds[index] = true
    end
    emit(game.set_holds(holds))
  end

  def score(args)
    category = category_name(args[0])
    @output.concat(require_rolled.score(category))
  end

  def what_if(args)
    category = category_name(args[0])
    game = require_rolled
    emit(game.score_line(game.prepare_entry(category), 'would score'))
  end

  def undo
    game = require_game
    require_value(!game.entries.empty?, 'nothing to undo')
    entry = game.undo
    emit("undo #{entry.player.name} #{entry.category} #{entry.points}")
  end

  def redo
    game = require_game
    require_value(!game.redo_list.empty?, 'nothing to redo')
    entry = game.redo
    emit("redo #{entry.player.name} #{entry.category} #{entry.points}")
  end

  def suggest
    game = require_rolled
    candidates = game.candidates(game.current_player, game.turn.faces)
    best = best_candidate(candidates)
    emit("suggest #{candidates.flatten.join(' ')} best #{best.join(' ')}")
  end

  def odds(args)
    holds = hold_pattern(args[0])
    game = require_rolls_left
    player = game.current_player
    held = held_faces(game.turn.faces, holds)
    open = player.open_categories
    expected = open.to_h { |c| [c, 0] }
    chances = open.to_h { |c| [c, 0] }
    best_total = 0
    REROLLS[5 - held.length].each do |rolled, weight|
      candidates = game.candidates(player, held + rolled)
      candidates.each do |category, score|
        expected[category] += weight * score
        chances[category] += weight if score.positive?
      end
      best_total += weight * best_candidate(candidates)[1]
    end
    outcomes = 6**(5 - held.length)
    emit("odds #{pattern_text(holds)} outcomes #{outcomes}")
    open.each do |category|
      emit("#{category} expect #{fraction_text(expected[category], outcomes)} " \
           "chance #{fraction_text(chances[category], outcomes)}")
    end
    emit("best expect #{fraction_text(best_total, outcomes)}")
  end

  def advise
    game = require_rolls_left
    levels = @rules[:rolls] - game.turn.rolls
    holds, value = Advisor.new(game, game.current_player).best_hold(game.turn.faces, levels)
    emit("advise #{pattern_text(holds)}: #{face_text(held_faces(game.turn.faces, holds))} " \
         "expect #{fraction_text(value, 7776**levels)}")
  end

  def auto(args)
    count = integer_word(args[0], 1, 100)
    game = require_turn
    count.times do
      @output.concat(game.bot_turn)
      break if game.finished?
    end
  end

  def status
    game = require_game
    if game.finished?
      emit('status game over')
    else
      turn, player = game.turn, game.current_player
      emit("status round #{player.round} player #{player.name} rolls #{turn.rolls} " \
           "dice #{face_text(turn.faces)} holds #{pattern_text(turn.holds)}")
    end
  end

  def card
    players = require_game.players
    widths = players.map { |player| [4, player.name.length].max }
    rows = [['CATEGORY', players.map(&:name)]]
    CATEGORIES.each do |category|
      rows << [category, players.map { |player| player.boxes[category]&.to_s || '-' }]
    end
    rows << ['UPPER', players.map { |player| player.upper_subtotal.to_s }]
    rows << ['BONUS', players.map { |player| player.upper_bonus.to_s }]
    rows << ['YBONUS', players.map { |player| player.yahtzee_bonus.to_s }]
    rows << ['TOTAL', players.map { |player| player.total.to_s }]
    rows.each do |heading, cells|
      emit(heading.ljust(9) + cells.each_with_index.map { |cell, i| ' ' + cell.rjust(widths[i]) }.join)
    end
  end

  def bonus
    require_game.players.each do |player|
      subtotal = player.upper_subtotal
      maximum = subtotal + UPPER.each_with_index.sum { |category, i| player.boxes[category].nil? ? 5 * (i + 1) : 0 }
      state = subtotal >= 63 ? 'made' : maximum < 63 ? 'lost' : 'open'
      emit("bonus #{player.name} upper #{subtotal} need #{[63 - subtotal, 0].max} max #{maximum} #{state}")
    end
  end

  def stats
    game = require_game
    game.players.each do |player|
      entries = game.entries.select { |entry| entry.player.equal?(player) }
      rolls = entries.sum { |entry| entry.turn.rolls }
      zeros = entries.count { |entry| entry.points.zero? }
      yahtzees = entries.count { |entry| yahtzee?(entry.turn.faces) }
      average = average_text(entries.sum(&:points), entries.length)
      emit("stats #{player.name} turns #{entries.length} rolls #{rolls} zeros #{zeros} " \
           "yahtzees #{yahtzees} average #{average}")
    end
  end

  def log
    game = require_game
    emit('no scores') if game.entries.empty?
    game.entries.each_with_index do |entry, index|
      parts = ['log', index + 1, entry.player.name, face_text(entry.turn.faces), entry.category, entry.points]
      parts << 'joker' if entry.joker
      parts.concat(['ybonus', entry.bonus]) if entry.bonus.positive?
      emit(parts.join(' '))
    end
  end

  def faces
    counts = require_game.roller.counts
    total = counts.sum
    chi2 = total.zero? ? '0' : fraction_text(6 * counts.sum { |c| c * c } - total * total, total)
    emit("faces #{counts.join(' ')} total #{total} chi2 #{chi2}")
  end

  def standings
    ranking = require_game.ranking
    leader = ranking.first.total
    ranking.each_with_index do |player, index|
      emit("standing #{index + 1} #{player.name} #{player.total} behind #{leader - player.total}")
    end
  end

  def end_game
    game = require_game
    finished = game.finished?
    emit(finished ? 'end final' : 'end abandoned')
    game.ranking.each_with_index do |player, index|
      emit("rank #{index + 1} #{player.name} #{player.total}")
      (@records[player.name] ||= PlayerRecord.new).add(player.total, index.zero?) if finished
    end
    @game = nil
  end

  def show_records
    if @records.empty?
      emit('no records')
      return
    end
    @records.sort_by { |name, record| [-record.wins, -record.best, name] }.each do |name, record|
      emit("record #{name} games #{record.games} wins #{record.wins} best #{record.best} " \
           "average #{average_text(record.total, record.games)}")
    end
  end

  def simulate(args)
    seed = integer_word(args[0], 1, MODULUS - 1)
    count = integer_word(args[1], 1, 50)
    strategies = args.drop(2).map { |strategy| strategy_name(strategy) }
    require_value(strategies.length <= 6, 'too many players')
    roller = DiceRoller.new(seed)
    summaries = strategies.map { |strategy| SeatSummary.new(strategy) }
    count.times do
      players = strategies.each_with_index.map { |strategy, index| Player.new((index + 1).to_s, strategy) }
      game = Game.new(players, @rules, roller)
      game.bot_turn until game.finished?
      winner = game.ranking.first
      players.zip(summaries).each { |player, summary| summary.add(player, player.equal?(winner)) }
    end
    emit("sim seed #{seed} games #{count} players #{strategies.length}")
    summaries.each_with_index do |summary, index|
      emit("seat #{index + 1} #{summary.strategy} wins #{summary.wins} " \
           "average #{average_text(summary.total, count)} best #{summary.best} " \
           "bonus #{summary.bonus} yahtzee #{summary.yahtzee}")
    end
  end

  HANDLERS = {
    'RULE' => :set_rule, 'GAME' => :start_game, 'BOT' => :set_bot, 'LOAD' => :load,
    'ROLL' => :roll, 'HOLD' => :hold, 'KEEP' => :keep, 'SCORE' => :score,
    'WHATIF' => :what_if, 'UNDO' => :undo, 'REDO' => :redo, 'SUGGEST' => :suggest,
    'ODDS' => :odds, 'ADVISE' => :advise, 'AUTO' => :auto, 'STATUS' => :status,
    'CARD' => :card, 'BONUS' => :bonus, 'STATS' => :stats, 'LOG' => :log,
    'FACES' => :faces, 'STANDINGS' => :standings, 'END' => :end_game,
    'RECORDS' => :show_records, 'SIM' => :simulate
  }.freeze

  ARGUMENT_HANDLERS = %i[
    set_rule start_game set_bot load hold keep score what_if odds auto simulate
  ].freeze

  def execute(line)
    command, *args = line.split
    handler = HANDLERS[command]
    require_value(!handler.nil?, "unknown command #{command}")
    if ARGUMENT_HANDLERS.include?(handler)
      send(handler, args)
    else
      send(handler)
    end
  rescue CommandError => error
    emit("error: #{error.message}")
  end
end

input = STDIN.each_line
commands = input.next.to_i
table = YahtzeeTable.new
commands.times { table.execute(input.next.chomp) }
puts table.output
