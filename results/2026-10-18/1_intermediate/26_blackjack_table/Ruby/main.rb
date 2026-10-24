# frozen_string_literal: true

class CommandError < StandardError; end

def integer(word, minimum, maximum)
  raise CommandError, "bad value #{word}" unless /\A(?:0|[1-9][0-9]{0,9})\z/.match?(word)
  value = word.to_i
  raise CommandError, "bad value #{word}" unless value.between?(minimum, maximum)
  value
end

def choice(word, *choices)
  raise CommandError, "bad value #{word}" unless choices.include?(word)
  word
end

def on(word) = choice(word, 'ON', 'OFF') == 'ON'
def on_off(value) = value ? 'ON' : 'OFF'

Rules = Data.define(:hit_soft17, :penetration, :minimum, :maximum, :six_to_five, :double_after_split,
                    :doubling, :hands, :resplit_aces, :surrender, :charlie, :side_maximum) do
  def self.defaults
    new(hit_soft17: false, penetration: 75, minimum: 10, maximum: 500, six_to_five: false,
        double_after_split: true, doubling: 'ANY', hands: 4, resplit_aces: false,
        surrender: true, charlie: 0, side_maximum: 25)
  end

  def changed(name, word)
    case name
    when 'DEALER' then with(hit_soft17: choice(word, 'S17', 'H17') == 'H17')
    when 'PEN' then with(penetration: integer(word, 50, 90))
    when 'MIN' then with(minimum: integer(word, 1, 10000))
    when 'MAX' then with(maximum: integer(word, 1, 10000))
    when 'BJ' then with(six_to_five: choice(word, '3:2', '6:5') == '6:5')
    when 'DAS' then with(double_after_split: on(word))
    when 'DOUBLE' then with(doubling: choice(word, 'ANY', '9-11', '10-11'))
    when 'HANDS' then with(hands: integer(word, 1, 4))
    when 'RSA' then with(resplit_aces: on(word))
    when 'SURRENDER' then with(surrender: on(word))
    when 'CHARLIE' then with(charlie: choice(word, '0', '5', '6', '7').to_i)
    when 'SIDEMAX' then with(side_maximum: integer(word, 0, 1000))
    else raise CommandError, "unknown rule #{name}"
    end
  end

  def to_s
    format('rules DEALER %s PEN %d MIN %d MAX %d BJ %s DAS %s DOUBLE %s HANDS %d RSA %s SURRENDER %s CHARLIE %d SIDEMAX %d',
           hit_soft17 ? 'H17' : 'S17', penetration, minimum, maximum, six_to_five ? '6:5' : '3:2',
           on_off(double_after_split), doubling, hands, on_off(resplit_aces), on_off(surrender), charlie, side_maximum)
  end
end

Card = Data.define(:code) do
  def rank = code % 13
  def suit = code / 13
  def point = [rank + 1, 10].min
  def black? = suit == 0 || suit == 3
  def hilo
    case point
    when 2..6 then 1
    when 1, 10 then -1
    else 0
    end
  end
  def to_s = "#{'A23456789TJQK'[rank]}#{'CDHS'[suit]}"
end

Total = Data.define(:value, :soft)

class Hand
  attr_reader :cards, :split, :split_aces
  attr_accessor :bet, :finished, :reason

  def initialize(cards = [], bet: 0, split: false, split_aces: false)
    @cards = cards.dup
    @bet, @split, @split_aces = bet, split, split_aces
    @finished = false
    @reason = nil
  end

  def total
    sum = @cards.sum(&:point)
    soft = @cards.any? { |card| card.rank.zero? } && sum + 10 <= 21
    Total.new(sum + (soft ? 10 : 0), soft)
  end

  def blackjack? = !@split && @cards.length == 2 && total.value == 21

  def to_s
    t = total
    status = if blackjack? then 'blackjack'
             elsif t.value > 21 then "bust #{t.value}"
             elsif t.soft then "soft #{t.value}"
             else t.value.to_s
             end
    "#{@cards.join(' ')} (#{status})"
  end

  def outcome(dealer, dealer_natural)
    return blackjack? ? :push : :lose if dealer_natural
    return :blackjack if blackjack?
    return @reason if @reason
    return :win if dealer > 21 || total.value > dealer
    total.value == dealer ? :push : :lose
  end
end

def hand_profit(result, bet, rules)
  case result
  when :blackjack then rules.six_to_five ? bet * 6 / 5 : bet * 3 / 2
  when :win, :charlie then bet
  when :push then 0
  when :surrender then bet / 2 - bet
  else -bet
  end
end

class Statistics
  attr_accessor :rounds, :hands, :wins, :losses, :pushes, :blackjacks, :busts, :surrenders, :doubles, :splits

  def initialize
    @rounds = @hands = @wins = @losses = @pushes = 0
    @blackjacks = @busts = @surrenders = @doubles = @splits = 0
  end

  def record(result)
    @hands += 1
    case result
    when :blackjack, :win, :charlie then @wins += 1
    when :push then @pushes += 1
    else @losses += 1
    end
    @blackjacks += 1 if result == :blackjack
    @busts += 1 if result == :bust
    @surrenders += 1 if result == :surrender
  end

  def to_s
    "rounds #{@rounds} hands #{@hands} wins #{@wins} losses #{@losses} pushes #{@pushes}" \
      " blackjacks #{@blackjacks} busts #{@busts} surrenders #{@surrenders} doubles #{@doubles} splits #{@splits}"
  end
end

class Player
  attr_reader :name, :seat, :hands, :stats
  attr_accessor :bankroll, :bet, :side, :insurance, :net

  def initialize(name, seat, bankroll)
    @name, @seat, @bankroll = name, seat, bankroll
    @bet = @side = @insurance = @net = 0
    @hands = []
    @stats = Statistics.new
  end

  def hand_name(index) = "#{@name}[#{index + 1}]"
end

class Shoe
  attr_reader :decks, :cards, :drawn
  attr_accessor :running

  def initialize(decks, seed)
    @decks, @random = decks, seed
    shuffle
  end

  def shuffle
    @cards = Array.new(52 * @decks) { |i| Card.new(i % 52) }
    (@cards.length - 1).downto(1) do |i|
      @random = @random * 48_271 % 2_147_483_647
      j = @random % (i + 1)
      @cards[i], @cards[j] = @cards[j], @cards[i]
    end
    @drawn = @running = 0
  end

  def cut(penetration) = @cards.length * penetration / 100

  def draw(visible = true)
    card = @cards[@drawn]
    @drawn += 1
    @running += card.hilo if visible
    card
  end
end

Turn = Data.define(:player, :index, :hand) do
  def name = player.hand_name(index)
end

class Table
  COMMANDS = %w[SHOE RULE RULES PLAYER LEAVE REBUY BET SIDE DEAL INSURANCE HIT STAND DOUBLE SPLIT SURRENDER HINT AUTO STATUS COUNT STATS].freeze
  ACTIONS = { 'HIT' => :hit, 'STAND' => :stand, 'DOUBLE' => :double, 'SPLIT' => :split, 'SURRENDER' => :surrender }.freeze
  IDLE_COMMANDS = %w[SHOE RULE PLAYER LEAVE REBUY BET SIDE DEAL].freeze
  NAMED_COMMANDS = %w[LEAVE REBUY BET SIDE INSURANCE AUTO].freeze
  AMOUNT_COMMANDS = %w[REBUY BET SIDE INSURANCE].freeze

  def initialize
    @rules = Rules.defaults
    @seats = Array.new(7)
    @participants = []
    @output = []
    @shoe = nil
    @state = :idle
    @round = @dealer_blackjacks = @dealer_busts = @insurance_turn = 0
    @dealer = Hand.new
    @hole_visible = false
  end

  def execute(words)
    @output = []
    command, first, second = words
    raise CommandError, "unknown command #{command}" unless COMMANDS.include?(command)
    action = ACTIONS[command]
    target = proposed = nil
    amount = seed = 0
    case command
    when 'SHOE'
      amount = integer(first, 1, 8)
      seed = integer(second, 1, 2_147_483_646)
    when 'RULE'
      proposed = @rules.changed(first, second)
    when 'PLAYER'
      raise CommandError, "bad name #{first}" unless /\A[A-Z]{1,8}\z/.match?(first)
      amount = integer(second, 1, 1_000_000)
    else
      if action || NAMED_COMMANDS.include?(command)
        target = find(first)
        raise CommandError, "unknown player #{first}" unless target
        amount = integer(second, command == 'REBUY' ? 1 : 0, 1_000_000) if AMOUNT_COMMANDS.include?(command)
      end
    end
    if IDLE_COMMANDS.include?(command)
      raise CommandError, 'round in progress' unless @state == :idle
    elsif command == 'INSURANCE'
      raise CommandError, 'no insurance' unless @state == :insurance
    elsif action || command == 'AUTO' || command == 'HINT'
      raise CommandError, 'no round' if @state == :idle
      raise CommandError, 'insurance pending' if @state == :insurance
    end
    if action || command == 'AUTO'
      turn = current
      raise CommandError, "waiting for #{turn.name}" unless turn.player.equal?(target)
      if action
        problem = action_error(action, target, turn.hand)
        raise CommandError, problem if problem
        perform(action)
      else
        perform(recommend) while @state == :play && current.player.equal?(target)
      end
      return @output
    end
    case command
    when 'SHOE'
      @shoe = Shoe.new(amount, seed)
      emit('shoe %d decks %d cards cut %d', @shoe.decks, @shoe.cards.length, @shoe.cut(@rules.penetration))
    when 'RULE'
      raise CommandError, 'min above max' if proposed.minimum > proposed.maximum
      @rules = proposed
      emit('rule %s %s', first, second)
    when 'RULES'
      emit('%s', @rules)
    when 'PLAYER'
      raise CommandError, 'player exists' if find(first)
      seat = @seats.index(nil)
      raise CommandError, 'table full' if seat.nil?
      @seats[seat] = Player.new(first, seat, amount)
      emit('%s sits at seat %d with %d', first, seat + 1, amount)
    when 'LEAVE'
      emit('%s leaves with %d net %+d', target.name, target.bankroll, target.net)
      @seats[target.seat] = nil
    when 'REBUY'
      target.bankroll += amount
      emit('%s rebuys %d bankroll %d', target.name, amount, target.bankroll)
    when 'BET'
      unless amount.zero?
        raise CommandError, 'bet out of limits' unless amount.between?(@rules.minimum, @rules.maximum)
        raise CommandError, 'insufficient funds' if amount + target.side > target.bankroll
      end
      target.bet = amount
      if amount.zero?
        target.side = 0
        emit('%s bet cleared', target.name)
      else
        emit('%s bets %d', target.name, amount)
      end
    when 'SIDE'
      unless amount.zero?
        raise CommandError, 'no bet' if target.bet.zero?
        raise CommandError, 'side out of limits' if amount > @rules.side_maximum
        raise CommandError, 'insufficient funds' if target.bet + amount > target.bankroll
      end
      target.side = amount
      if amount.zero? then emit('%s side cleared', target.name)
      else emit('%s side %d', target.name, amount)
      end
    when 'DEAL'
      raise CommandError, 'no shoe' unless @shoe
      raise CommandError, 'no bets' unless @seats.compact.any? { |player| !player.bet.zero? }
      deal
    when 'INSURANCE'
      waiting = @participants[@insurance_turn]
      raise CommandError, "waiting for #{waiting.name}" unless target.equal?(waiting)
      raise CommandError, 'insurance out of limits' if amount > target.bet / 2
      raise CommandError, 'insufficient funds' if amount > target.bankroll
      target.bankroll -= amount
      target.insurance = amount
      if amount.zero? then emit('%s declines insurance', target.name)
      else emit('%s insures %d', target.name, amount)
      end
      @insurance_turn += 1
      peek if @insurance_turn == @participants.length
    when 'HINT'
      emit('hint %s: %s', current.name, recommend)
    when 'STATUS'
      status
    when 'COUNT'
      raise CommandError, 'no shoe' unless @shoe
      remaining = @shoe.cards.length - @shoe.drawn
      scaled = @shoe.running.abs * 5200 / remaining
      emit('count running %d true %s%d.%02d remaining %d', @shoe.running, @shoe.running.negative? ? '-' : '', scaled / 100, scaled % 100, remaining)
    when 'STATS'
      players = @seats.compact
      raise CommandError, 'no players' if players.empty?
      players.each { |player| emit('stats %s %s net %+d', player.name, player.stats, player.net) }
      emit('stats dealer rounds %d blackjacks %d busts %d', @round, @dealer_blackjacks, @dealer_busts)
    end
    @output
  end

  private

  def emit(pattern, *values) = @output << format(pattern, *values)
  def find(name) = @seats.compact.find { |player| player.name == name }

  def current
    @participants.each do |player|
      player.hands.each_with_index do |hand, index|
        return Turn.new(player, index, hand) unless hand.finished
      end
    end
    nil
  end

  def reveal
    unless @hole_visible
      @shoe.running += @dealer.cards[1].hilo
      @hole_visible = true
    end
    emit('dealer: %s', @dealer)
  end

  def finish_check(player, hand)
    value = hand.total.value
    if value > 21
      hand.finished = true
      hand.reason = :bust
    elsif !@rules.charlie.zero? && hand.cards.length == @rules.charlie
      hand.finished = true
      hand.reason = :charlie
    elsif value == 21
      hand.finished = true
    elsif hand.split_aces && hand.cards.length == 2
      hand.finished = !(hand.cards.all? { |card| card.rank.zero? } && @rules.resplit_aces && player.hands.length < @rules.hands)
    end
  end

  def settle(dealer_natural)
    dealer_total = @dealer.total.value
    @participants.each do |player|
      player.hands.each_with_index do |hand, index|
        result = hand.outcome(dealer_total, dealer_natural)
        profit = hand_profit(result, hand.bet, @rules)
        player.bankroll += hand.bet + profit
        player.net += profit
        player.stats.record(result)
        emit('%s %s %+d', player.hand_name(index), result, profit)
      end
      emit('%s bankroll %d', player.name, player.bankroll)
    end
    @seats.compact.each { |player| player.bet = player.side = 0 }
    @state = :idle
  end

  def dealer_turn
    reveal
    needs_draw = @participants.any? { |player| player.hands.any? { |hand| hand.reason.nil? && !hand.blackjack? } }
    drew = false
    if needs_draw
      loop do
        total = @dealer.total
        break unless total.value <= 16 || total.value == 17 && total.soft && @rules.hit_soft17
        @dealer.cards << @shoe.draw
        drew = true
        emit('dealer hits: %s', @dealer)
      end
    end
    @dealer_busts += 1 if drew && @dealer.total.value > 21
    settle(false)
  end

  def advance
    loop do
      turn = current
      unless turn
        dealer_turn
        return
      end
      return unless turn.hand.cards.length == 1
      turn.hand.cards << @shoe.draw
      emit('%s: %s', turn.name, turn.hand)
      finish_check(turn.player, turn.hand)
      return unless turn.hand.finished
    end
  end

  def peek
    natural = @dealer.blackjack?
    emit('dealer peeks: %s', natural ? 'blackjack' : 'no blackjack')
    @participants.each do |player|
      next if player.insurance.zero?
      profit = player.insurance * (natural ? 2 : -1)
      player.bankroll += player.insurance + profit
      player.net += profit
      emit('%s insurance %+d', player.name, profit)
    end
    if natural
      @dealer_blackjacks += 1
      reveal
      settle(true)
    else
      @state = :play
      advance
    end
  end

  def deal
    if @shoe.drawn >= @shoe.cut(@rules.penetration)
      @shoe.shuffle
      emit('shuffle')
    end
    @round += 1
    emit('round %d', @round)
    @participants = @seats.compact.reject { |player| player.bet.zero? }
    @participants.each do |player|
      player.bankroll -= player.bet + player.side
      player.insurance = 0
      player.stats.rounds += 1
      player.hands.replace([Hand.new(bet: player.bet)])
    end
    @dealer = Hand.new
    @hole_visible = false
    @participants.each { |player| player.hands[0].cards << @shoe.draw }
    @dealer.cards << @shoe.draw
    @participants.each do |player|
      hand = player.hands[0]
      hand.cards << @shoe.draw
      hand.finished = hand.blackjack?
    end
    @dealer.cards << @shoe.draw(false)
    @participants.each { |player| emit('%s: %s', player.hand_name(0), player.hands[0]) }
    emit('dealer: %s ??', @dealer.cards[0])
    @participants.each do |player|
      next if player.side.zero?
      first, second = player.hands[0].cards
      result, multiplier = if first.rank != second.rank then [:lose, -1]
                           elsif first.suit == second.suit then [:perfect, 25]
                           elsif first.black? == second.black? then [:colored, 12]
                           else [:mixed, 6]
                           end
      profit = player.side * multiplier
      player.bankroll += player.side + profit
      player.net += profit
      emit('%s side %s %+d', player.name, result, profit)
    end
    case @dealer.cards[0].point
    when 1
      @state = :insurance
      @insurance_turn = 0
      emit('insurance offered')
    when 10 then peek
    else
      @state = :play
      advance
    end
  end

  def action_error(action, player, hand)
    case action
    when :hit
      return 'split aces' if hand.split_aces
    when :double
      return 'split aces' if hand.split_aces
      return 'two cards only' unless hand.cards.length == 2
      total = hand.total
      minimum = @rules.doubling == '10-11' ? 10 : 9
      if @rules.doubling != 'ANY' && (total.soft || !total.value.between?(minimum, 11)) || !@rules.double_after_split && hand.split
        return 'double not allowed'
      end
      return 'insufficient funds' if player.bankroll < hand.bet
    when :split
      return 'two cards only' unless hand.cards.length == 2
      return 'not a pair' unless hand.cards[0].point == hand.cards[1].point
      return 'hand limit' if player.hands.length >= @rules.hands
      return 'insufficient funds' if player.bankroll < hand.bet
    when :surrender
      return 'surrender not allowed' if !@rules.surrender || hand.split
      return 'two cards only' unless hand.cards.length == 2
    end
    nil
  end

  def recommend
    turn = current
    hand = turn.hand
    possible = ->(action) { action_error(action, turn.player, hand).nil? }
    up = @dealer.cards[0].point
    up = 11 if up == 1
    return possible.call(:split) ? :split : :stand if hand.split_aces
    if possible.call(:split)
      pair = hand.cards[0].point
      if pair == 1 || pair == 8 || pair == 9 && ![7, 10, 11].include?(up) ||
         [2, 3, 7].include?(pair) && up <= 7 || pair == 6 && up <= 6 || pair == 4 && [5, 6].include?(up)
        return :split
      end
    end
    total = hand.total
    value = total.value
    symbol = :h
    if total.soft
      if value >= 19
        symbol = :s
      elsif value == 18
        symbol = up.between?(3, 6) ? :ds : [2, 7, 8].include?(up) ? :s : :h
      elsif value == 17 && up.between?(3, 6) || [15, 16].include?(value) && up.between?(4, 6) || [13, 14].include?(value) && up.between?(5, 6)
        symbol = :d
      end
    else
      if value >= 17
        symbol = :s
      elsif value >= 13
        symbol = up <= 6 ? :s : value == 16 && up >= 9 || value == 15 && up == 10 ? :r : :h
      elsif value == 12
        symbol = up.between?(4, 6) ? :s : :h
      elsif value == 11 && up <= 10 || value == 10 && up <= 9 || value == 9 && up.between?(3, 6)
        symbol = :d
      end
    end
    case symbol
    when :s then :stand
    when :d then possible.call(:double) ? :double : :hit
    when :ds then possible.call(:double) ? :double : :stand
    when :r then possible.call(:surrender) ? :surrender : :hit
    else :hit
    end
  end

  def perform(action)
    turn = current
    player, hand, name = turn.player, turn.hand, turn.name
    case action
    when :split
      first, second = hand.cards
      aces = hand.split_aces || first.rank.zero?
      player.bankroll -= hand.bet
      player.stats.splits += 1
      emit('%s splits %s %s', name, first, second)
      replacement = Hand.new([first], bet: hand.bet, split: true, split_aces: aces)
      player.hands[turn.index] = replacement
      player.hands.insert(turn.index + 1, Hand.new([second], bet: hand.bet, split: true, split_aces: aces))
      replacement.cards << @shoe.draw
      emit('%s: %s', name, replacement)
      finish_check(player, replacement)
    when :stand, :surrender
      hand.finished = true
      hand.reason = :surrender if action == :surrender
      emit('%s %s: %s', name, action == :stand ? 'stands' : 'surrenders', hand)
    when :hit, :double
      if action == :double
        player.bankroll -= hand.bet
        hand.bet *= 2
        player.stats.doubles += 1
      end
      hand.cards << @shoe.draw
      emit('%s %s: %s', name, action == :double ? 'doubles' : 'hits', hand)
      finish_check(player, hand)
      hand.finished = true if action == :double
    end
    advance
  end

  def status
    case @state
    when :idle then emit('table idle round %d', @round)
    when :insurance then emit('table insurance round %d next %s', @round, @participants[@insurance_turn].name)
    when :play then emit('table play round %d turn %s', @round, current.name)
    end
    emit('dealer: %s ??', @dealer.cards[0]) unless @state == :idle
    @seats.compact.each do |player|
      emit('seat %d %s bankroll %d bet %d side %d', player.seat + 1, player.name, player.bankroll, player.bet, player.side)
      next if @state == :idle || !@participants.include?(player)
      player.hands.each_with_index { |hand, index| emit('%s: %s bet %d', player.hand_name(index), hand, hand.bet) }
    end
  end
end

table = Table.new
STDIN.gets.to_i.times do
  words = STDIN.gets.split
  begin
    table.execute(words).each { |line| STDOUT.write("#{line}\n") }
  rescue CommandError => error
    STDOUT.write("error: #{error.message}\n")
  end
end
