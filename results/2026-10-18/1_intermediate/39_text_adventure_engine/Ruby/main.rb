# frozen_string_literal: true

require 'set'

DIRECTIONS = %w[north south east west up down].freeze
VERBS = {
  go: %w[go walk run], look: %w[look l], examine: %w[examine x inspect read], take: %w[take get grab],
  drop: %w[drop discard], put: %w[put insert place], inventory: %w[inventory inv i], open: %w[open],
  close: %w[close shut], unlock: %w[unlock], lock: %w[lock], use: %w[use apply], light: %w[light ignite],
  extinguish: %w[extinguish douse snuff], wait: %w[wait z], score: %w[score], save: %w[save],
  restore: %w[restore load], verbose: %w[verbose], brief: %w[brief]
}.flat_map { |verb, aliases| aliases.map { |word| [word, verb] } }.to_h.freeze
NO_ARGUMENTS = %i[look inventory wait score save restore verbose brief].freeze
ACTIONS = %i[go take drop put open close unlock lock use light extinguish wait].freeze
ARTICLES = %w[the a an].freeze

Place = Data.define(:kind, :id)
PLAYER = Place.new(:player, nil)
NOWHERE = Place.new(:nowhere, nil)
ExitLink = Data.define(:destination, :key, :locked)
Trigger = Data.define(:kind, :first, :second)
Condition = Data.define(:flag, :on)
Message = Data.define(:text)
OpenExit = Data.define(:room, :direction, :destination)
MoveItem = Data.define(:item, :place)
SetFlag = Data.define(:flag, :on)
Points = Data.define(:amount)
Rule = Data.define(:trigger, :condition, :effect)
RuleResult = Data.define(:executed, :message)
Treasures = Data.define(:points, :stored, :total)
Room = Struct.new(:name, :dark, :description)
Item = Struct.new(:name, :nouns, :name_words, :details, :weight, :treasure, :light, :capacity, :key, :fixed, keyword_init: true)
class CommandFailure < StandardError; end

class State
  attr_accessor :room, :bonus, :moves, :darkness, :ended
  attr_reader :places, :containers, :fuel, :lit, :exits, :flags, :visited

  def initialize
    @room = nil
    @bonus = @moves = @darkness = 0
    @ended = nil
    @places = {}; @containers = {}; @fuel = {}; @lit = {}; @exits = {}
    @flags = Set.new; @visited = Set.new
  end

  def initialize_copy(source)
    super
    @places = source.places.dup; @containers = source.containers.dup
    @fuel = source.fuel.dup; @lit = source.lit.dup
    @exits = source.exits.transform_values(&:dup)
    @flags = source.flags.dup; @visited = source.visited.dup
  end
end

class Adventure
  attr_reader :state

  def initialize(definitions)
    @rooms = {}; @items = {}; @rules = []
    @state = State.new
    @saved = @pronoun = @previous = nil
    @verbose = false
    @output = []
    definitions.each { |words| define(words) }
    @ids = @items.keys.sort.freeze
    @vocabulary = @items.values.each_with_object(Set.new) { |item, set| set.merge(item.nouns).merge(item.name_words) }.freeze
    @state.visited.add(@state.room)
    @rooms.each_value { |room| room.description.freeze; room.freeze }
    @items.each_value { |item| item.nouns.freeze; item.name_words.freeze; item.details.freeze; item.freeze }
    @rooms.freeze; @items.freeze; @rules.freeze
  end

  def direction(word) = DIRECTIONS.index { |name| word == name || word == name[0] }
  def words(line) = line.downcase.split.reject { |word| ARTICLES.include?(word) }
  def all?(phrase) = phrase == ['all']
  def tail(words, at) = words[at..].join(' ').freeze
  def inside(item) = Place.new(:inside, item)
  def floor = Place.new(:floor, @state.room)
  def say(text) = @output << text
  def failure(message) = raise(CommandFailure, message)

  def set_exit(room, direction, destination, key = nil)
    (@state.exits[room] ||= {})[direction] = ExitLink.new(destination, key, !key.nil?)
  end

  def read_rule(words, at, trigger)
    condition = nil
    if %w[IF UNLESS].include?(words[at])
      condition = Condition.new(words[at + 1], words[at] == 'IF')
      at += 2
    end
    effect = case words[at]
             when 'MESSAGE' then Message.new(tail(words, at + 1))
             when 'OPEN' then OpenExit.new(words[at + 1], direction(words[at + 2]), words[at + 3])
             when 'REMOVE' then MoveItem.new(words[at + 1], NOWHERE)
             when 'ADD' then MoveItem.new(words[at + 1], Place.new(:floor, words[at + 2]))
             when 'SET', 'CLEAR' then SetFlag.new(words[at + 1], words[at] == 'SET')
             when 'POINTS' then Points.new(words[at + 1].to_i(10))
             end
    Rule.new(trigger, condition, effect)
  end

  def define(w)
    id = w[1]
    case w[0]
    when 'ROOM'
      dark = w[2] == 'DARK'
      @rooms[id] = Room.new(tail(w, dark ? 3 : 2), dark, [])
    when 'DESC' then @rooms[id].description << tail(w, 2)
    when 'EXIT' then set_exit(id, direction(w[2]), w[3], w.size > 4 ? w[5] : nil)
    when 'ITEM'
      @state.places[id] = case w[2]
                          when 'PLAYER' then PLAYER
                          when 'NOWHERE' then NOWHERE
                          else Place.new(:floor, w[2])
                          end
      @state.containers[id] = :open; @state.fuel[id] = 0; @state.lit[id] = false
      item = Item.new(name: '', nouns: Set[id], name_words: Set.new, details: [], weight: w[3].to_i(10),
                      treasure: nil, light: false, capacity: nil, key: nil, fixed: false)
      at = 4
      if w[at] == 'TREASURE'
        item.treasure = w[at + 1].to_i(10); at += 2
      end
      if w[at] == 'LIGHT'
        item.light = true; @state.fuel[id] = w[at + 1].to_i(10); at += 2
      end
      if w[at] == 'CONTAINER'
        item.capacity = w[at + 1].to_i(10); at += 2
        if w[at] == 'CLOSED'
          @state.containers[id] = :closed; at += 1
        end
        if w[at] == 'LOCKED'
          item.key = w[at + 1]; @state.containers[id] = :locked; at += 2
        end
      end
      if w[at] == 'FIXED'
        item.fixed = true; at += 1
      end
      item.name = tail(w, at); item.name_words.merge(w[at..])
      @items[id] = item
    when 'INSIDE' then @state.places[id] = inside(w[2])
    when 'ALIAS' then @items[id].nouns.add(w[2])
    when 'DETAIL' then @items[id].details << tail(w, 2)
    when 'RULE' then @rules << read_rule(w, 3, Trigger.new(:use, id, w[2]))
    when 'ENTER' then @rules << read_rule(w, 2, Trigger.new(:enter, id, nil))
    when 'TROPHY' then @trophy = id
    when 'START' then @state.room = id
    when 'MAXWEIGHT' then @max_weight = id.to_i(10)
    end
  end

  def direct(place) = @ids.select { |id| @state.places[id] == place }

  def reachable?(id, root)
    place = @state.places[id]
    while place.kind == :inside
      return false unless @state.containers[place.id] == :open
      place = @state.places[place.id]
    end
    place == root
  end

  def carried?(id) = reachable?(id, PLAYER)
  def room_item?(id) = reachable?(id, floor)
  def lit? = !@rooms[@state.room].dark || @ids.any? { |id| @state.lit[id] && (carried?(id) || room_item?(id)) }
  def total_weight(id) = @items[id].weight + place_weight(inside(id))
  def place_weight(place) = direct(place).sum { |id| total_weight(id) }

  def within?(id, ancestor)
    place = @state.places[id]
    while place.kind == :inside
      return true if place.id == ancestor
      place = @state.places[place.id]
    end
    false
  end

  def stored?(id)
    place = @state.places[id]
    place = @state.places[place.id] while place.kind == :inside
    place == Place.new(:floor, @trophy)
  end

  def treasures
    points = stored = total = 0
    @ids.each do |id|
      next unless @items[id].treasure
      total += 1
      if stored?(id)
        stored += 1; points += @items[id].treasure
      end
    end
    Treasures.new(points, stored, total)
  end

  def score = treasures.points + @state.bonus

  def display_name(id)
    annotations = []
    annotations << @state.containers[id] if @items[id].capacity
    annotations << 'lit' if @state.lit[id]
    @items[id].name + (annotations.empty? ? '' : " (#{annotations.join(', ')})")
  end

  def item_tree(place, depth)
    direct(place).each do |id|
      say('  ' * depth + display_name(id))
      item_tree(inside(id), depth + 1) if @items[id].capacity && @state.containers[id] == :open
    end
  end

  def describe(full)
    unless lit?
      say('It is pitch dark.')
      return
    end
    say(@rooms[@state.room].name)
    @output.concat(@rooms[@state.room].description) if full
    exits = DIRECTIONS.each_index.filter_map do |d|
      exit = @state.exits.fetch(@state.room, {})[d]
      "#{DIRECTIONS[d]}#{exit.locked ? ' (locked)' : ''}" if exit
    end
    say("Exits: #{exits.empty? ? 'none' : exits.join(', ')}")
    unless direct(floor).empty?
      say('You see:'); item_tree(floor, 1)
    end
  end

  def names(ids) = ids.map { |id| @items[id].name }.join(', ')

  def resolve(phrase)
    lit = lit?
    if phrase == ['it']
      failure('I don\'t know what "it" refers to.') unless @pronoun
      failure("You can't see any such thing.") unless carried?(@pronoun) || lit && room_item?(@pronoun)
      return @pronoun
    end
    phrase.each { |word| failure("I don't know the word \"#{word}\".") unless @vocabulary.include?(word) }
    matches = @ids.select do |id|
      (carried?(id) || lit && room_item?(id)) && @items[id].nouns.include?(phrase.last) &&
        phrase[0...-1].all? { |word| @items[id].name_words.include?(word) }
    end
    failure("You can't see any such thing.") if matches.empty?
    failure("Which do you mean: #{names(matches)}?") if matches.size > 1
    @pronoun = matches.first
  end

  def run_rules(trigger)
    executed = 0; message = false
    @rules.each do |rule|
      condition = rule.condition
      next unless rule.trigger == trigger
      next if condition && @state.flags.include?(condition.flag) != condition.on
      executed += 1
      effect = rule.effect
      case effect
      when Message then say(effect.text); message = true
      when OpenExit then set_exit(effect.room, effect.direction, effect.destination)
      when MoveItem then @state.places[effect.item] = effect.place
      when SetFlag
        effect.on ? @state.flags.add(effect.flag) : @state.flags.delete(effect.flag)
      when Points then @state.bonus += effect.amount
      end
    end
    RuleResult.new(executed, message)
  end

  def turn(baseline)
    @state.moves += 1
    nearby = @ids.to_h { |id| [id, carried?(id) || room_item?(id)] }
    @ids.each do |id|
      next unless @state.lit[id]
      @state.fuel[id] -= 1
      next unless @state.fuel[id].zero?
      @state.lit[id] = false
      say("The #{@items[id].name} goes out.") if nearby[id]
    end
    lit = lit?
    if baseline && !lit
      say('It is now pitch dark.')
    elsif !baseline && lit
      describe(true)
    end
    @state.darkness = lit ? 0 : @state.darkness + 1
    say('You hear something moving in the dark.') if @state.darkness == 2
    @state.ended = :dead if @state.darkness == 3
    treasure = treasures
    @state.ended = :won if !@state.ended && treasure.total.positive? && treasure.stored == treasure.total
    return unless @state.ended
    say(@state.ended == :dead ? '*** You have died ***' : '*** You have won ***')
    say("You scored #{treasure.points + @state.bonus} points in #{@state.moves} moves.")
  end

  def require_container(id)
    failure("The #{@items[id].name} is not a container.") unless @items[id].capacity
    failure("The #{@items[id].name} is closed.") unless @state.containers[id] == :open
  end

  def put_item(id, container)
    failure("The #{@items[container].name} is inside the #{@items[id].name}.") if within?(container, id)
    failure("The #{@items[id].name} is already in the #{@items[container].name}.") if @state.places[id] == inside(container)
    weight = place_weight(inside(container)) + (within?(id, container) ? 0 : total_weight(id))
    failure("The #{@items[id].name} doesn't fit in the #{@items[container].name}.") if weight > @items[container].capacity
    @state.places[id] = inside(container)
  end

  def take(target, from)
    failure('It is pitch dark.') unless lit?
    container = nil; source = floor
    unless from.empty?
      container = resolve(from); require_container(container); source = inside(container)
    end
    if all?(target)
      candidates = direct(source).reject { |id| @items[id].fixed }
      failure(container ? "There is nothing in the #{@items[container].name} to take." : 'There is nothing here to take.') if candidates.empty?
      taken = false
      candidates.each do |id|
        if !carried?(id) && place_weight(PLAYER) + total_weight(id) > @max_weight
          say("#{@items[id].name}: You can't carry any more.")
        else
          @state.places[id] = PLAYER; say("#{@items[id].name}: Taken."); taken = true
        end
      end
      return taken
    end
    id = resolve(target)
    failure("The #{@items[id].name} is not in the #{@items[container].name}.") if container && @state.places[id] != source
    failure("You already have the #{@items[id].name}.") if @state.places[id] == PLAYER
    failure("The #{@items[id].name} is fixed in place.") if @items[id].fixed
    failure("You can't carry any more.") if !carried?(id) && place_weight(PLAYER) + total_weight(id) > @max_weight
    @state.places[id] = PLAYER; say('Taken.'); true
  end

  def drop(target)
    if all?(target)
      candidates = direct(PLAYER)
      failure('You are empty-handed.') if candidates.empty?
      candidates.each { |id| @state.places[id] = floor; say("#{@items[id].name}: Dropped.") }
    else
      id = resolve(target)
      failure("You aren't carrying the #{@items[id].name}.") unless carried?(id)
      @state.places[id] = floor; say('Dropped.')
    end
  end

  def put(first, second)
    id = all?(first) ? nil : resolve(first)
    container = resolve(second)
    if id
      failure("You aren't carrying the #{@items[id].name}.") unless carried?(id)
      failure("You can't put the #{@items[id].name} inside itself.") if id == container
    end
    require_container(container)
    if id
      put_item(id, container); say("You put the #{@items[id].name} in the #{@items[container].name}.")
      return true
    end
    candidates = direct(PLAYER).reject { |item| item == container }
    failure("You have nothing to put in the #{@items[container].name}.") if candidates.empty?
    moved = false
    candidates.each do |item|
      message = begin
        put_item(item, container); moved = true; 'Done.'
      rescue CommandFailure => error
        error.message
      end
      say("#{@items[item].name}: #{message}")
    end
    moved
  end

  def key_check(key, phrase)
    if phrase.empty?
      failure("You don't have the right key.") unless carried?(key)
      say("(with the #{@items[key].name})")
    else
      id = resolve(phrase)
      failure("You aren't carrying the #{@items[id].name}.") unless carried?(id)
      failure("The #{@items[id].name} doesn't fit.") unless id == key
    end
  end

  def change_lock(target, key_phrase, locking)
    d = target.size == 1 ? direction(target.first) : nil
    status = locking ? 'already locked' : 'not locked'
    if d
      exit = @state.exits.fetch(@state.room, {})[d]
      failure("There is no exit #{DIRECTIONS[d]}.") unless exit
      failure("The way #{DIRECTIONS[d]} has no lock.") unless exit.key
      failure("The way #{DIRECTIONS[d]} is #{status}.") if exit.locked == locking
      key_check(exit.key, key_phrase)
      @state.exits[@state.room][d] = exit.with(locked: locking)
      opposite = @state.exits.fetch(exit.destination, {})[d ^ 1]
      if opposite && opposite.destination == @state.room && opposite.key == exit.key
        @state.exits[exit.destination][d ^ 1] = opposite.with(locked: locking)
      end
    else
      id = resolve(target)
      failure("The #{@items[id].name} has no lock.") unless @items[id].capacity && @items[id].key
      failure("The #{@items[id].name} is #{status}.") if (@state.containers[id] == :locked) == locking
      failure("You must close the #{@items[id].name} first.") if locking && @state.containers[id] == :open
      key_check(@items[id].key, key_phrase)
      @state.containers[id] = locking ? :locked : :closed
    end
    say(locking ? 'Locked.' : 'Unlocked.')
  end

  def examine(id)
    if @items[id].details.empty?
      say("You see nothing special about the #{@items[id].name}.")
    else
      @output.concat(@items[id].details)
    end
    say("It is #{@state.lit[id] ? 'lit' : 'unlit'} (fuel #{@state.fuel[id]}).") if @items[id].light
    if @items[id].capacity
      case @state.containers[id]
      when :locked then say('It is locked.')
      when :closed then say('It is closed.')
      when :open
        if direct(inside(id)).empty?
          say('It is empty.')
        else
          say('It contains:'); item_tree(inside(id), 1)
        end
      end
    end
    say("It is a treasure worth #{@items[id].treasure} points.") if @items[id].treasure
    say("It weighs #{total_weight(id)}.")
  end

  def execute(verb, first, second, d)
    baseline = lit?; success = true
    case verb
    when :go
      exit = @state.exits.fetch(@state.room, {})[d]
      failure("You can't go that way.") unless exit
      failure("The way #{DIRECTIONS[d]} is locked.") if exit.locked
      @state.room = exit.destination; baseline = lit?
      describe(@verbose || !@state.visited.include?(@state.room)); @state.visited.add(@state.room)
      run_rules(Trigger.new(:enter, @state.room, nil))
    when :look then describe(true)
    when :examine then examine(resolve(first))
    when :take then success = take(first, second)
    when :drop then drop(first)
    when :put then success = put(first, second)
    when :inventory
      if direct(PLAYER).empty?
        say('You are empty-handed.')
      else
        say('You are carrying:'); item_tree(PLAYER, 1); say("Total weight: #{place_weight(PLAYER)}/#{@max_weight}")
      end
    when :open
      id = resolve(first)
      failure("You can't open the #{@items[id].name}.") unless @items[id].capacity
      failure("The #{@items[id].name} is already open.") if @state.containers[id] == :open
      failure("The #{@items[id].name} is locked.") if @state.containers[id] == :locked
      @state.containers[id] = :open
      children = direct(inside(id))
      say(children.empty? ? 'Opened.' : "Opening the #{@items[id].name} reveals #{names(children)}.")
    when :close
      id = resolve(first)
      failure("You can't close the #{@items[id].name}.") unless @items[id].capacity
      failure("The #{@items[id].name} is already closed.") unless @state.containers[id] == :open
      @state.containers[id] = :closed; say('Closed.')
    when :lock, :unlock then change_lock(first, second, verb == :lock)
    when :use
      a = resolve(first); b = resolve(second)
      failure("You aren't carrying the #{@items[a].name}.") unless carried?(a)
      result = run_rules(Trigger.new(:use, a, b))
      failure('Nothing happens.') if result.executed.zero?
      say('Done.') unless result.message
    when :light, :extinguish
      id = resolve(first); lighting = verb == :light
      failure("You can't #{verb} the #{@items[id].name}.") unless @items[id].light
      failure("The #{@items[id].name} is #{lighting ? 'already lit' : 'not lit'}.") if @state.lit[id] == lighting
      failure("The #{@items[id].name} has no fuel.") if lighting && @state.fuel[id].zero?
      @state.lit[id] = lighting; say("The #{@items[id].name} is now #{lighting ? 'lit' : 'out'}.")
    when :wait then say('Time passes.')
    when :score
      treasure = treasures
      say("You have scored #{treasure.points + @state.bonus} points (treasure #{treasure.points}, bonus #{@state.bonus}) in #{@state.moves} moves.")
      say("Treasures stored: #{treasure.stored} of #{treasure.total}.")
    when :save then @saved = @state.dup; say('Game saved.')
    when :restore
      failure('There is no saved game.') unless @saved
      @state = @saved.dup; say('Game restored.'); describe(true)
    when :verbose then @verbose = true; say('Verbose mode.')
    when :brief then @verbose = false; say('Brief mode.')
    end
    turn(baseline) if success && ACTIONS.include?(verb)
  end

  def interpret(input)
    failure('I beg your pardon?') if input.empty?
    direction_word = !direction(input.first).nil?
    verb = direction_word ? :go : VERBS[input.first]
    failure("I don't know the verb \"#{input.first}\".") unless verb
    failure('The game is over.') if @state.ended && verb != :restore
    first = input.drop(direction_word ? 0 : 1); second = []; d = nil
    if verb == :look && !first.empty?
      failure("I don't understand that.") unless first.first == 'at'
      verb = :examine; first = first.drop(1)
    end
    if NO_ARGUMENTS.include?(verb)
      failure("I don't understand that.") unless first.empty?
    else
      failure(verb == :go ? 'Which way do you want to go?' : "What do you want to #{verb}?") if first.empty?
      if verb == :go
        d = direction(first.first) if first.size == 1
        failure("I don't understand that.") unless d
      else
        split = first.index do |word|
          case verb
          when :put then %w[in into].include?(word)
          when :use then %w[on with].include?(word)
          when :lock, :unlock then word == 'with'
          when :take then word == 'from'
          else false
          end
        end
        if split
          failure("I don't understand that.") if split.zero? || split + 1 == first.size
          second = first.drop(split + 1); first = first.take(split)
        elsif verb == :put || verb == :use
          failure("I don't understand that.")
        end
      end
    end
    execute(verb, first, second, d)
  end

  def process(line)
    say("> #{line}")
    input = words(line)
    if %w[again g].include?(input.first)
      failure("I don't understand that.") unless input.size == 1
      failure('There is nothing to repeat.') unless @previous
      input = words(@previous)
    else
      @previous = line.freeze
    end
    interpret(input)
  rescue CommandFailure => error
    say(error.message)
  end

  def flush
    @output.each { |line| puts line }
    @output.clear
  end
end

definitions = []
while (raw = STDIN.gets)
  line = raw.chomp
  break if line == 'BEGIN'
  definitions << line.split(' ').map(&:freeze).freeze
end
game = Adventure.new(definitions)
game.describe(true); game.flush
while (raw = STDIN.gets)
  line = raw.chomp
  break if line == 'QUIT'
  game.process(line); game.flush
end
game.say("Final score: #{game.score} points in #{game.state.moves} moves.")
game.flush
