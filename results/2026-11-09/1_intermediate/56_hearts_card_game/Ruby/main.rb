SEATS = 'NESW'
SUITS = 'CDSH'
RANKS = '23456789TJQKA'
STRATEGIES = %w[BASIC LOW HIGH SMART MOON]
DIRECTIONS = {'L' => 'LEFT', 'R' => 'RIGHT', 'A' => 'ACROSS', 'H' => 'HOLD'}
DEFAULT_RULES = {'TARGET' => 100, 'LIMIT' => 100, 'MOON' => 'ADD', 'JACK' => 'OFF',
                 'QSBREAK' => 'OFF', 'BLOOD' => 'OFF', 'PASS' => 'LRAH'}
QS, KS, AS, JD = 36, 37, 38, 22
class CommandError < StandardError; end

def fail_command(message)
  raise CommandError, message
end

def card_text(card)
  RANKS[card % 13] + SUITS[card / 13]
end

def cards_text(cards)
  cards.empty? ? '-' : cards.sort.map { |card| card_text(card) }.join(' ')
end

def seat_value(word)
  fail_command("bad seat #{word}") unless word.size == 1 && SEATS.include?(word)
  SEATS.index(word)
end

def card_value(word)
  unless word.size == 2 && RANKS.include?(word[0]) && SUITS.include?(word[1])
    fail_command("bad card #{word}")
  end
  SUITS.index(word[1]) * 13 + RANKS.index(word[0])
end

def bounded(word, low, high)
  value = word.to_i
  fail_command("bad value #{word}") unless value.between?(low, high)
  value
end

def lowest(cards)
  cards.min_by { |card| [card % 13, card / 13] }
end

def highest(cards)
  cards.min_by { |card| [-(card % 13), card / 13] }
end

def penalty?(card)
  card == QS || card / 13 == 3
end

def pairs(label, values)
  label + ' ' + values.each_with_index.map { |value, seat| "#{SEATS[seat]} #{value}" }.join(' ')
end

def duplicate_cards(cards)
  seen = []
  cards.each do |card|
    fail_command("duplicate card #{card_text(card)}") if seen.include?(card)
    seen << card
  end
end

class Generator
  def initialize(seed)
    @state = seed
  end

  def shuffle(deck)
    (deck.size - 1).downto(1) do |i|
      @state = 48271 * @state % 2147483647
      j = @state % (i + 1)
      deck[i], deck[j] = deck[j], deck[i]
    end
  end
end

class Game
  attr_accessor :bots
  attr_reader :state, :number, :scores, :stats, :stacked, :history, :log, :record,
              :hands, :passes, :taken, :tricks, :current, :undo

  def initialize(rules, bots, generator)
    @rules, @bots, @generator = rules, bots, generator
    @state = 'between'
    @number = 0
    @scores = Array.new(4, 0)
    @stats = Array.new(4) { Array.new(4, 0) }
    @stacked = {}
    @history, @log, @record = [], [], []
  end

  def point(card)
    return 13 if card == QS
    return 1 if card / 13 == 3
    card == JD && @rules['JACK'] == 'ON' ? -10 : 0
  end

  def write(level, line)
    @log << [level, line]
    @record << line if level > 0
  end

  def deal
    @number += 1
    cycle = @rules['PASS']
    @pass_code = cycle[(@number - 1) % cycle.size]
    @hands = Array.new(4) { |seat| (@stacked[seat] || []).dup }
    deck = (0...52).to_a - @hands.flatten
    @generator.shuffle(deck)
    free = (0...4).reject { |seat| @stacked.key?(seat) }
    deck.each_with_index { |card, i| @hands[free[i % free.size]] << card }
    @stacked.clear
    @passes = {}
    @taken = Array.new(4) { [] }
    @tricks, @current, @undo = [], [], []
    @trick_counts = Array.new(4, 0)
    @broken = false
    @record = []
    write(1, "hand #{@number} pass #{DIRECTIONS[@pass_code]}")
    4.times { |seat| write(2, "#{SEATS[seat]}: #{cards_text(@hands[seat])}") }
    if @pass_code == 'H'
      begin_play
    else
      @state = 'passing'
    end
  end

  def begin_play
    @state = 'playing'
    @leader = (0...4).find { |seat| @hands[seat].include?(0) }
    write(2, "lead #{SEATS[@leader]}")
  end

  def pass_cards(seat, cards)
    @hands[seat] -= cards
    @passes[seat] = cards.dup
    write(2, "#{SEATS[seat]} passes #{cards_text(cards)}")
    return unless @passes.size == 4
    offset = {'L' => 1, 'R' => 3, 'A' => 2}[@pass_code]
    @passes.each { |source, passed| @hands[(source + offset) % 4].concat(passed) }
    begin_play
  end

  def actor
    (@leader + @current.size) % 4
  end

  def legal
    hand = @hands[actor]
    if @current.empty?
      return [0] if @tricks.empty?
      safe = hand.reject { |card| card / 13 == 3 }
      return !@broken && !safe.empty? ? safe : hand.dup
    end
    suit = @current[0][1] / 13
    followers = hand.select { |card| card / 13 == suit }
    return followers unless followers.empty?
    if @tricks.empty? && @rules['BLOOD'] == 'OFF'
      safe = hand.reject { |card| penalty?(card) }
      return safe unless safe.empty?
    end
    hand.dup
  end

  def choose_pass(seat)
    hand = @hands[seat]
    low = hand.sort_by { |card| [card % 13, card / 13] }
    high = hand.sort_by { |card| [-(card % 13), card / 13] }
    hearts = high.select { |card| card / 13 == 3 }
    special = [QS, KS, AS].select { |card| hand.include?(card) }
    order = case @bots[seat]
            when 'LOW' then high
            when 'HIGH' then low
            when 'MOON'
              low.reject { |card| card / 13 == 3 } + low.select { |card| card / 13 == 3 }
            when 'SMART'
              protected = hand.include?(QS) && hand.count { |card| card / 13 == 2 } >= 5
              list = protected ? [] : special.dup
              suits = [0, 1].select { |suit| hand.any? { |card| card / 13 == suit } }
              unless suits.empty?
                suit = suits.min_by { |s| [hand.count { |card| card / 13 == s }, s] }
                list += high.select { |card| card / 13 == suit }
              end
              list + hearts + high
            else special + hearts + high
            end
    order.uniq.first(3)
  end

  def queen_played?
    @taken.any? { |cards| cards.include?(QS) } || @current.any? { |_, card| card == QS }
  end

  def choose_play
    seat = actor
    hand = @hands[seat]
    choices = legal
    strategy = @bots[seat]
    return lowest(choices) if strategy == 'LOW'
    return highest(choices) if strategy == 'HIGH'
    if strategy == 'MOON' && (0...4).any? { |other| other != seat && @taken[other].any? { |card| penalty?(card) } }
      strategy = 'BASIC'
    end
    if @current.empty?
      if strategy == 'SMART' && !queen_played? && !hand.include?(QS)
        small = choices.select { |card| card / 13 == 2 && card % 13 < 10 }
        return lowest(small) unless small.empty?
      end
      suits = choices.map { |card| card / 13 }.uniq
      suit = suits.min_by do |s|
        count = choices.count { |card| card / 13 == s }
        [strategy == 'MOON' ? -count : count, s]
      end
      suited = choices.select { |card| card / 13 == suit }
      return strategy == 'MOON' ? highest(suited) : lowest(suited)
    end
    led = @current[0][1] / 13
    if hand.any? { |card| card / 13 == led }
      winning = @current.select { |_, card| card / 13 == led }.map { |_, card| card % 13 }.max
      lower = choices.select { |card| card % 13 < winning }
      if strategy == 'MOON'
        high = highest(choices)
        return high % 13 > winning ? high : lowest(choices)
      end
      return highest(lower) unless lower.empty?
      if strategy == 'SMART' && @current.size == 3
        safe = choices - [QS]
        return safe.empty? ? QS : highest(safe)
      end
      return lowest(choices)
    end
    if strategy == 'MOON'
      safe = choices.reject { |card| penalty?(card) }
      return lowest(safe.empty? ? choices : safe)
    end
    return QS if choices.include?(QS)
    if strategy == 'SMART' && !queen_played?
      return AS if choices.include?(AS)
      return KS if choices.include?(KS)
    end
    hearts = choices.select { |card| card / 13 == 3 }
    highest(hearts.empty? ? choices : hearts)
  end

  def winner(plays)
    led = plays[0][1] / 13
    plays.select { |_, card| card / 13 == led }.max_by { |_, card| card % 13 }[0]
  end

  def trick_line(plays, number)
    sequence = plays.map { |seat, card| "#{SEATS[seat]} #{card_text(card)}" }.join(' ')
    "trick #{number}: #{sequence} -> #{SEATS[winner(plays)]} #{plays.sum { |_, card| point(card) }}"
  end

  def play(card)
    seat = actor
    fields = [@hands, @taken, @tricks, @trick_counts, @current, @leader, @broken, @record]
    @undo << [Marshal.load(Marshal.dump(fields)), @log.size, seat, card]
    @hands[seat].delete(card)
    @current << [seat, card]
    @broken = true if card / 13 == 3 || card == QS && @rules['QSBREAK'] == 'ON'
    return unless @current.size == 4
    won = winner(@current)
    @taken[won].concat(@current.map(&:last))
    @trick_counts[won] += 1
    @tricks << @current
    write(2, trick_line(@current, @tricks.size))
    @current = []
    @leader = won
    finish_hand if @tricks.size == 13
  end

  def undo_card
    fields, length, seat, card = @undo.pop
    @hands, @taken, @tricks, @trick_counts, @current, @leader, @broken, @record = fields
    @log.slice!(length..-1)
    [seat, card]
  end

  def claim(seat)
    remaining = @hands.flatten
    count = 13 - @tricks.size
    @taken[seat].concat(remaining)
    @trick_counts[seat] += count
    @hands = Array.new(4) { [] }
    write(2, "claim #{SEATS[seat]} tricks #{count} points #{remaining.sum { |card| point(card) }}")
    finish_hand
  end

  def ranking
    (0...4).sort_by { |seat| [@scores[seat], seat] }
  end

  def stats_lines
    @stats.each_with_index.map do |s, seat|
      "stats #{SEATS[seat]} tricks #{s[0]} hearts #{s[1]} queens #{s[2]} moons #{s[3]}"
    end
  end

  def finish_hand
    points = @taken.map { |cards| cards.sum { |card| point(card) } }
    shooter = (0...4).find { |seat| @taken[seat].count { |card| penalty?(card) } == 14 }
    unless shooter.nil?
      points[shooter] -= 26
      method = @rules['MOON']
      if method == 'AUTO'
        add = (0...4).map { |seat| @scores[seat] + points[seat] + (seat == shooter ? 0 : 26) }
        ended = @number >= @rules['LIMIT'] || add.max >= @rules['TARGET']
        first = (0...4).min_by { |seat| [add[seat], seat] }
        method = ended && first != shooter ? 'SUB' : 'ADD'
      end
      if method == 'SUB'
        points[shooter] -= 26
      else
        4.times { |seat| points[seat] += 26 if seat != shooter }
      end
      write(1, "moon #{SEATS[shooter]} #{method}")
    end
    4.times do |seat|
      @scores[seat] += points[seat]
      @stats[seat][0] += @trick_counts[seat]
      @stats[seat][1] += @taken[seat].count { |card| card / 13 == 3 }
      @stats[seat][2] += 1 if @taken[seat].include?(QS)
      @stats[seat][3] += 1 if shooter == seat
    end
    write(1, pairs('points', points))
    write(1, pairs('scores', @scores))
    @history << {number: @number, direction: DIRECTIONS[@pass_code], points: points,
                 shooter: shooter, record: @record.dup}
    ended = @number >= @rules['LIMIT'] || @scores.max >= @rules['TARGET']
    @state = ended ? 'none' : 'between'
    return unless ended
    write(0, "game over hands #{@number}")
    ranking.each_with_index { |seat, i| write(0, "rank #{i + 1} #{SEATS[seat]} #{@scores[seat]}") }
    stats_lines.each { |line| write(0, line) }
  end

  def auto_pass
    4.times { |seat| pass_cards(seat, choose_pass(seat)) unless @passes.key?(seat) }
  end

  def auto_hand
    auto_pass if @state == 'passing'
    play(choose_play) while @state == 'playing'
  end

  def auto_game
    auto_hand if %w[passing playing].include?(@state)
    until @state == 'none'
      deal
      auto_hand
    end
  end
end

class Table
  def initialize
    @rules = DEFAULT_RULES.dup
    @bots = Array.new(4, 'BASIC')
    @game = nil
  end

  def active?
    @game && @game.state != 'none'
  end

  def require_state(kind)
    case kind
    when 'game' then fail_command('no game') unless active?
    when 'between'
      require_state('game')
      fail_command('hand in progress') unless @game.state == 'between'
    when 'hand'
      fail_command('no hand') unless active? && %w[passing playing].include?(@game.state)
    else
      fail_command("not #{kind}") unless active? && @game.state == kind
    end
  end

  def rule_value(name, word)
    fail_command("unknown rule #{name}") unless @rules.key?(name)
    if %w[TARGET LIMIT].include?(name)
      fail_command("bad value #{word}") unless word.match?(/\A-?\d+\z/)
      return bounded(word, 1, name == 'TARGET' ? 1000 : 100)
    end
    good = if name == 'PASS'
             word.match?(/\A[LRAH]{1,8}\z/)
           elsif name == 'MOON'
             %w[ADD SUB AUTO].include?(word)
           else
             %w[ON OFF].include?(word)
           end
    fail_command("bad value #{word}") unless good
    word
  end

  def simulate(command, seed, count)
    generator = Generator.new(seed)
    if command == 'GAME'
      game = Game.new(@rules, @bots, generator)
      game.auto_game
      return ["game seed #{seed}"] + game.log.select { |level, _| level <= count }.map(&:last)
    end
    rounds = command == 'ROTATE' ? 4 : 1
    places = Array.new(4) { Array.new(4, 0) }
    totals = Array.new(4, 0)
    stats = Array.new(4) { Array.new(4, 0) }
    hands = 0
    rounds.times do |rotation|
      strategies = Array.new(4)
      4.times { |seat| strategies[(seat + rotation) % 4] = @bots[seat] }
      count.times do
        game = Game.new(@rules, strategies, generator)
        game.auto_game
        hands += game.number
        ranking = game.ranking
        4.times do |original|
          actual = (original + rotation) % 4
          places[original][ranking.index(actual)] += 1
          totals[original] += game.scores[actual]
          4.times { |i| stats[original][i] += game.stats[actual][i] }
        end
      end
    end
    games = rounds * count
    output = ["#{command.downcase} seed #{seed} games #{games} hands #{hands}"]
    4.times do |seat|
      cents = 100 * totals[seat] / games
      average = "#{cents < 0 ? '-' : ''}#{cents.abs / 100}.#{format('%02d', cents.abs % 100)}"
      name = SEATS[seat] + (command == 'ROTATE' ? " #{@bots[seat]}" : '')
      s = stats[seat]
      output << "#{name} places #{places[seat].join(' ')} total #{totals[seat]} average #{average} tricks #{s[0]} hearts #{s[1]} queens #{s[2]} moons #{s[3]}"
    end
    output
  end

  def command(words)
    command, *args = words
    known = %w[RULE BOT SETTINGS GAME MATCH ROTATE NEW ABANDON STACK DEAL SHOW PASS PLAY AUTO UNDO CLAIM LEGAL PREVIEW SCORE TAKEN TRICKS VOIDS UNSEEN STATS HISTORY REPLAY]
    fail_command("unknown command #{command}") unless known.include?(command)
    case command
    when 'RULE'
      value = rule_value(args[0], args[1])
      fail_command('game in progress') if active?
      @rules[args[0]] = value
      return ["rule #{args.join(' ')}"]
    when 'BOT'
      seat = seat_value(args[0])
      fail_command("bad value #{args[1]}") unless STRATEGIES.include?(args[1])
      @bots[seat] = args[1]
      return ["bot #{args.join(' ')}"]
    when 'SETTINGS'
      return ['rules ' + @rules.map { |name, value| "#{name} #{value}" }.join(' '), pairs('bots', @bots)]
    when 'GAME', 'MATCH', 'ROTATE'
      seed = bounded(args[0], 1, 2147483646)
      low, high = {'GAME' => [0, 2], 'MATCH' => [1, 50], 'ROTATE' => [1, 10]}[command]
      return simulate(command, seed, bounded(args[1], low, high))
    when 'NEW'
      seed = bounded(args[0], 1, 2147483646)
      fail_command('game in progress') if active?
      @game = Game.new(@rules, @bots, Generator.new(seed))
      return ["new game seed #{seed}"]
    when 'ABANDON'
      require_state('game')
      @game = nil
      return ['game abandoned']
    end
    seat = seat_value(args[0]) if %w[STACK PASS PLAY CLAIM].include?(command)
    cards = %w[STACK PASS PLAY].include?(command) ? args.drop(1).map { |word| card_value(word) } : []
    fail_command('need 13 cards') if command == 'STACK' && cards.size != 13
    if command == 'AUTO' && !%w[PASS CARD TRICK HAND GAME].include?(args[0])
      fail_command("bad value #{args[0]}")
    end
    kind = case command
           when 'STACK', 'DEAL' then 'between'
           when 'SHOW' then 'hand'
           when 'PASS' then 'passing'
           when 'SCORE', 'STATS', 'HISTORY', 'REPLAY' then 'game'
           when 'AUTO'
             {'PASS' => 'passing', 'CARD' => 'playing', 'TRICK' => 'playing', 'HAND' => 'hand', 'GAME' => 'game'}[args[0]]
           else 'playing'
           end
    require_state(kind)
    game = @game
    before = game.log.size
    prefix = []
    case command
    when 'STACK'
      duplicate_cards(cards)
      cards.each do |card|
        owner = (0...4).find { |other| other != seat && (game.stacked[other] || []).include?(card) }
        fail_command("#{card_text(card)} stacked for #{SEATS[owner]}") unless owner.nil?
      end
      game.stacked[seat] = cards.dup
      return ["stacked #{SEATS[seat]}"]
    when 'DEAL' then game.deal
    when 'SHOW'
      return (0...4).map { |s| "#{SEATS[s]}: #{cards_text(game.hands[s])}" }
    when 'PASS'
      fail_command("#{SEATS[seat]} already passed") if game.passes.key?(seat)
      duplicate_cards(cards)
      cards.each { |card| fail_command("#{SEATS[seat]} does not hold #{card_text(card)}") unless game.hands[seat].include?(card) }
      game.pass_cards(seat, cards)
    when 'PLAY'
      card = cards[0]
      fail_command("waiting for #{SEATS[game.actor]}") if seat != game.actor
      fail_command("#{SEATS[seat]} does not hold #{card_text(card)}") unless game.hands[seat].include?(card)
      unless game.legal.include?(card)
        fail_command(game.tricks.empty? ? 'must lead 2C' : 'hearts not broken') if game.current.empty?
        led = game.current[0][1] / 13
        fail_command("must follow #{SUITS[led]}") if game.hands[seat].any? { |held| held / 13 == led }
        fail_command('no points on first trick')
      end
      prefix << "#{SEATS[seat]} plays #{card_text(card)}"
      game.play(card)
    when 'AUTO'
      case args[0]
      when 'PASS' then game.auto_pass
      when 'CARD'
        card = game.choose_play
        prefix << "#{SEATS[game.actor]} plays #{card_text(card)}"
        game.play(card)
      when 'TRICK'
        count = game.tricks.size
        game.play(game.choose_play) while game.state == 'playing' && game.tricks.size == count
      when 'HAND' then game.auto_hand
      when 'GAME' then game.auto_game
      end
    when 'UNDO'
      fail_command('nothing to undo') if game.undo.empty?
      s, card = game.undo_card
      return ["undo #{SEATS[s]} #{card_text(card)}"]
    when 'CLAIM'
      fail_command("waiting for #{SEATS[game.actor]}") if seat != game.actor
      fail_command('trick in progress') unless game.current.empty?
      game.hands[seat].each do |card|
        (0...4).each do |other|
          next if other == seat
          if game.hands[other].any? { |held| held / 13 == card / 13 && held % 13 > card % 13 }
            fail_command('claim rejected')
          end
        end
      end
      game.claim(seat)
    when 'LEGAL'
      return ["legal #{SEATS[game.actor]}: #{cards_text(game.legal)} bot #{card_text(game.choose_play)}"]
    when 'PREVIEW'
      return game.legal.sort.map do |card|
        copy = Marshal.load(Marshal.dump(game))
        count = copy.tricks.size
        copy.play(card)
        copy.play(copy.choose_play) while copy.state == 'playing' && copy.tricks.size == count
        trick = copy.tricks.last
        "preview #{card_text(card)} -> #{SEATS[copy.winner(trick)]} #{trick.sum { |_, played| copy.point(played) }}"
      end
    when 'SCORE'
      output = [pairs('scores', game.scores)]
      output << pairs('taken', game.taken.map { |held| held.sum { |card| game.point(card) } }) if game.state == 'playing'
      return output
    when 'TAKEN'
      return (0...4).map { |s| "#{SEATS[s]}: #{cards_text(game.taken[s].select { |card| game.point(card) != 0 })}" }
    when 'TRICKS'
      output = game.tricks.each_with_index.map { |trick, i| game.trick_line(trick, i + 1) }
      output << 'current: ' + game.current.map { |s, card| "#{SEATS[s]} #{card_text(card)}" }.join(' ') unless game.current.empty?
      return output.empty? ? ['no tricks'] : output
    when 'VOIDS'
      voids = Array.new(4) { [] }
      (game.tricks + (game.current.empty? ? [] : [game.current])).each do |trick|
        led = trick[0][1] / 13
        trick.each { |s, card| voids[s] << led if card / 13 != led }
      end
      return [pairs('voids', voids.map { |missing| missing.empty? ? '-' : missing.uniq.sort.map { |s| SUITS[s] }.join })]
    when 'UNSEEN'
      played = game.taken.flatten + game.current.map(&:last)
      return ["unseen #{SEATS[game.actor]}: #{cards_text((0...52).to_a - game.hands[game.actor] - played)}"]
    when 'STATS' then return game.stats_lines
    when 'HISTORY'
      output = game.history.map do |hand|
        line = "hand #{hand[:number]} pass #{hand[:direction]} " + pairs('points', hand[:points])
        line += " moon #{SEATS[hand[:shooter]]}" unless hand[:shooter].nil?
        line
      end
      return output.empty? ? ['no hands'] : output
    when 'REPLAY'
      hand = args[0].to_i
      fail_command("bad value #{args[0]}") unless hand.between?(1, game.history.size)
      return game.history[hand - 1][:record].dup
    end
    prefix + game.log.drop(before).map(&:last)
  end
end

table = Table.new
count = STDIN.gets.to_i
count.times do
  begin
    puts table.command(STDIN.gets.chomp.split(' '))
  rescue CommandError => error
    puts "error: #{error.message}"
  end
end
