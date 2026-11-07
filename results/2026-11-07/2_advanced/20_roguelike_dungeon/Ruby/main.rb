# frozen_string_literal: true

require 'set'
require_relative 'minstd'
require_relative 'dungeon_gen'
require_relative 'entities'
require_relative 'combat'
require_relative 'fov'

class Roguelike
  Player = Struct.new(:position, :depth, :hp, :max_hp, :level, :xp, :gold, :food, :poison,
                      :pack, :weapon, :armor, keyword_init: true)
  ITEM_COMMANDS = { 'quaff' => 'potion', 'read' => 'scroll', 'wield' => 'weapon', 'wear' => 'armor', 'eat' => 'food' }.freeze

  def read_input
    @settings = File.readlines('input/config.txt', chomp: true).to_h do |line|
      key, *values = line.split(' ')
      parsed = case key
               when 'start' then values
               when 'hitdie' then Combat.dice(values[0])
               else values.map(&:to_i)
               end
      [key, parsed]
    end
    @monster_types = File.readlines('input/monsters.txt', chomp: true).map { |line| Entities.monster_type(line) }
    @item_types = File.readlines('input/items.txt', chomp: true).map { |line| Entities.item_type(line) }
    @commands = File.readlines('input/commands.txt', chomp: true).flat_map do |line|
      keyword, *arguments = line.split(' ')
      if keyword == 'move'
        Array.new(arguments.length == 2 ? arguments[1].to_i : 1) { [keyword, arguments[0]] }
      elsif keyword == 'wait'
        Array.new(arguments.empty? ? 1 : arguments[0].to_i) { [keyword, nil] }
      else
        [[keyword, arguments[0]]]
      end
    end
    @checkpoints = @settings['checkpoints'].to_set
    @generation = Minstd.new(@settings['seed'][0])
    @game = Minstd.new(@settings['seed'][1])
  end

  def monster_at(level, position)
    level.monsters.find { |monster| monster.position == position }
  end

  def populate_level(depth)
    level = DungeonGen.generate(@settings, depth, @generation)
    bottom = depth == @settings['levels'][0]
    if bottom
      amulet = Entities::ItemType.new(kind: 'amulet', name: 'amulet')
      level.items[level.target] = Entities::Item.new(amulet, 0, nil)
    else
      level.terrain[level.target[1]][level.target[0]] = '>'
    end
    candidates = @monster_types.select { |type| depth.between?(type.min_depth, type.max_depth) }
    count = @settings['monsters'][0] + @settings['monsters'][1] * (depth - 1)
    level.monsters_created = count
    count.times do |index|
      type = candidates[@generation.choose(candidates.map(&:weight))]
      position = nil
      loop do
        room, position = DungeonGen.room_cell(level, @generation)
        break if room != level.arrival_room && level.terrain[position[1]][position[0]] == '.' && !monster_at(level, position)
      end
      hp = @generation.roll(type.hp_dice)
      asleep = @generation.rnd(100) < @settings['sleep'][0]
      level.monsters << Entities::Monster.new(id: index + 1, type: type, position: position,
                                              hp: hp, max_hp: hp, asleep: asleep, energy: 0, was_visible: false)
    end
    candidates = @item_types.select { |type| depth.between?(type.min_depth, type.max_depth) }
    count = @settings['items'][0] + @settings['items'][1] * (depth - 1)
    level.items_placed = count + (bottom ? 1 : 0)
    count.times do
      type = candidates[@generation.choose(candidates.map(&:weight))]
      position = nil
      loop do
        _, position = DungeonGen.room_cell(level, @generation)
        break if level.terrain[position[1]][position[0]] == '.' && !level.items.key?(position)
      end
      amount = type.kind == 'gold' ? @generation.roll(type.dice) : nil
      level.items[position] = Entities::Item.new(type, 0, amount)
    end
    level
  end

  def initialize_player
    by_name = @item_types.to_h { |type| [type.name, type] }
    pack = @settings['start'].map { |name| Entities::Item.new(by_name.fetch(name), 0, nil) }
    hp = @settings['player'][0]
    @player = Player.new(position: @levels[0].arrival.dup, depth: 1, hp: hp, max_hp: hp, level: 1,
                         xp: 0, gold: 0, food: @settings['food'][0], poison: 0, pack: pack,
                         weapon: pack.find { |item| item.type.kind == 'weapon' },
                         armor: pack.find { |item| item.type.kind == 'armor' })
  end

  def current_level
    @levels[@player.depth - 1]
  end

  def hunger
    return 'normal' if @player.food > @settings['food'][2]
    return 'hungry' if @player.food > @settings['food'][3]

    @player.food.positive? ? 'weak' : 'starving'
  end

  def defense
    armor = @player.armor
    armor ? 10 + armor.type.armor + armor.bonus : 10
  end

  def say(message)
    @messages << "#{format('%04d', @turn)} #{message}"
  end

  def fail_command(message)
    say(message)
    false
  end

  def update_view
    level = current_level
    @visible = Fov.visible(level, @player.position, @settings['fov'][0])
    @visible.each do |position|
      x, y = position
      item = level.items[position]
      level.memory[y][x] = item ? item.symbol : level.terrain[y][x]
    end
    level.monsters.each do |monster|
      visible = @visible.include?(monster.position)
      say("You see the #{monster.type.name}.") if visible && !monster.was_visible
      monster.was_visible = visible
    end
  end

  def gain_experience(amount)
    @player.xp += amount
    thresholds = @settings['xp']
    while @player.level <= thresholds.length && @player.xp >= thresholds[@player.level - 1]
      @player.level += 1
      increase = @game.roll(@settings['hitdie'])
      @player.max_hp += increase
      @player.hp += increase
      say("Welcome to level #{@player.level}.")
    end
  end

  def die(cause)
    @result = 'died'
    @cause = cause
    say('You die.')
  end

  def record_attack(statistics, attack)
    statistics[:count] += 1
    unless attack.kind == :miss
      statistics[:hits] += 1
      statistics[:criticals] += 1 if attack.kind == :critical
      statistics[:damage] += attack.damage
    end
  end

  def player_attack(monster)
    monster.asleep = false
    weapon = @player.weapon
    modifier = @player.level + (weapon ? weapon.type.to_hit + weapon.bonus : 0)
    modifier -= 2 if %w[weak starving].include?(hunger)
    dice = weapon ? weapon.type.damage : [1, 2]
    bonus = weapon ? weapon.bonus : 0
    attack = Combat.resolve(@game, modifier, monster.type.defense, dice, bonus)
    record_attack(@player_attacks, attack)
    if attack.kind == :miss
      say("You miss the #{monster.type.name}.")
      return
    end
    hard = attack.kind == :critical ? ' hard' : ''
    say("You hit the #{monster.type.name}#{hard} for #{attack.damage}.")
    monster.hp -= attack.damage
    return if monster.hp.positive?

    say("You kill the #{monster.type.name}.")
    current_level.monsters.delete(monster)
    current_level.killed += 1
    @kills[monster.type.name] += 1
    gain_experience(monster.type.xp)
  end

  def monster_attack(monster)
    type = monster.type
    attack = Combat.resolve(@game, type.to_hit, defense, type.damage, 0)
    record_attack(@monster_attacks, attack)
    if attack.kind == :miss
      say("The #{type.name} misses you.")
      return
    end
    hard = attack.kind == :critical ? ' hard' : ''
    say("The #{type.name} hits you#{hard} for #{attack.damage}.")
    @player.hp -= attack.damage
    if @player.hp <= 0
      die("killed_by #{type.name}")
    elsif type.traits.include?('P')
      @player.poison += 5
      say('You are poisoned.')
    end
  end

  def move_player(direction_name)
    direction = Fov::DIRECTIONS[Fov::NAMES.index(direction_name)]
    destination = [@player.position[0] + direction[0], @player.position[1] + direction[1]]
    level = current_level
    return fail_command('You bump into a wall.') unless Fov.passable?(level, destination)
    return fail_command('You cannot move diagonally through a door.') unless Fov.move?(level, @player.position, direction)

    monster = monster_at(level, destination)
    if monster
      player_attack(monster)
    else
      @player.position = destination
      @counts[:moves] += 1
      item = level.items[destination]
      if item
        say("You see #{item.reference_name} here.")
      elsif level.terrain[destination[1]][destination[0]] == '>'
        say('There is a staircase down here.')
      end
    end
    true
  end

  def pickup
    level = current_level
    item = level.items[@player.position]
    return fail_command('There is nothing here.') if item.nil?

    case item.type.kind
    when 'gold'
      @player.gold += item.amount
      say("You pick up #{item.display_name}.")
    when 'amulet'
      say('You pick up the amulet.')
      say('You win!')
      @result = 'won'
      @cause = 'amulet'
    else
      return fail_command('Your pack is full.') if @player.pack.length >= @settings['pack'][0]

      @player.pack << item
      say("You pick up the #{item.display_name} (#{@player.pack.length}).")
    end
    level.items.delete(@player.position)
    level.picked += 1
    @counts[:picked] += 1
    true
  end

  def quaff(item)
    say("You quaff the #{item.display_name}.")
    case item.type.effect
    when 'heal'
      @player.hp += @game.roll(item.type.dice)
      if @player.hp > @player.max_hp
        @player.max_hp += 1
        @player.hp = @player.max_hp
      end
      @player.poison = 0
      say('You feel better.')
    when 'poison'
      @player.poison += item.type.power
      say('You feel very sick.')
    when 'level'
      say('You feel more experienced.')
      if @player.level <= @settings['xp'].length
        gain_experience(@settings['xp'][@player.level - 1] - @player.xp)
      end
    end
  end

  def read_scroll(item)
    say("You read the #{item.display_name}.")
    level = current_level
    case item.type.effect
    when 'mapping'
      level.terrain.each_with_index do |row, y|
        row.each_with_index do |terrain, x|
          level.memory[y][x] = terrain if terrain != ' ' && level.memory[y][x] == ' '
        end
      end
      say('A map forms in your mind.')
    when 'teleport'
      loop do
        _, position = DungeonGen.room_cell(level, @game)
        next if position == @player.position || monster_at(level, position)

        @player.position = position
        break
      end
      say('You are teleported.')
    when 'enchant_weapon'
      if @player.weapon
        say("Your #{@player.weapon.display_name} glows blue.")
        @player.weapon.bonus += 1
      else
        say('Your hands twitch.')
      end
    when 'enchant_armor'
      if @player.armor
        say("Your #{@player.armor.display_name} glows silver.")
        @player.armor.bonus += 1
      else
        say('Your skin tingles.')
      end
    end
  end

  def inventory_command(keyword, number)
    return fail_command('You do not have that item.') if number > @player.pack.length

    item = @player.pack[number - 1]
    return fail_command("You cannot #{keyword} that.") unless item.type.kind == ITEM_COMMANDS.fetch(keyword)
    return fail_command('You are already wielding that.') if keyword == 'wield' && @player.weapon.equal?(item)
    return fail_command('You are already wearing that.') if keyword == 'wear' && @player.armor.equal?(item)

    case keyword
    when 'quaff'
      @player.pack.delete_at(number - 1)
      @counts[:quaffed] += 1
      quaff(item)
    when 'read'
      @player.pack.delete_at(number - 1)
      @counts[:read] += 1
      read_scroll(item)
    when 'eat'
      @player.pack.delete_at(number - 1)
      @counts[:eaten] += 1
      @player.food = [@player.food + item.type.power, @settings['food'][1]].min
      say("You eat the #{item.display_name}.")
    when 'wield'
      @player.weapon = item
      @counts[:wielded] += 1
      say("You are now wielding the #{item.display_name}.")
    when 'wear'
      @player.armor = item
      @counts[:worn] += 1
      say("You are now wearing the #{item.display_name}.")
    end
    true
  end

  def execute_command(keyword, argument)
    case keyword
    when 'move'
      move_player(argument)
    when 'wait'
      true
    when 'pickup'
      pickup
    when 'descend'
      x, y = @player.position
      return fail_command('There are no stairs here.') unless current_level.terrain[y][x] == '>'

      @player.depth += 1
      @player.position = current_level.arrival.dup
      say("You descend to depth #{@player.depth}.")
      true
    else
      inventory_command(keyword, argument.to_i)
    end
  end

  def can_attack?(monster)
    direction = [@player.position[0] - monster.position[0], @player.position[1] - monster.position[1]]
    direction.map(&:abs).max == 1 && Fov.move?(current_level, monster.position, direction)
  end

  def wander(monster)
    direction = Fov::DIRECTIONS[@game.rnd(8)]
    return unless Fov.move?(current_level, monster.position, direction)

    destination = [monster.position[0] + direction[0], monster.position[1] + direction[1]]
    if destination == @player.position
      monster_attack(monster)
    elsif !monster_at(current_level, destination)
      monster.position = destination
    end
  end

  def chase(monster, distances)
    if can_attack?(monster)
      monster_attack(monster)
      return
    end

    x, y = monster.position
    origin_distance = distances[y][x]
    best = nil
    best_distance = nil
    Fov::DIRECTIONS.each do |direction|
      next unless Fov.move?(current_level, monster.position, direction)

      destination = [x + direction[0], y + direction[1]]
      distance = distances[destination[1]][destination[0]]
      next if distance.nil? || (!origin_distance.nil? && distance >= origin_distance)
      next if destination == @player.position || monster_at(current_level, destination)
      next unless best_distance.nil? || distance < best_distance

      best = destination
      best_distance = distance
    end
    monster.position = best unless best.nil?
  end

  def monster_action(monster, distances)
    visible = @visible.include?(monster.position)
    if monster.asleep
      if visible && @game.rnd(100) < @settings['sleep'][1]
        monster.asleep = false
        say("The #{monster.type.name} wakes up.")
      end
    elsif monster.type.traits.include?('S')
      monster_attack(monster) if can_attack?(monster)
    elsif monster.type.traits.include?('E') && @game.rnd(2).zero?
      wander(monster)
    elsif visible
      chase(monster, distances)
    else
      wander(monster)
    end
  end

  def monster_phase
    distances = Fov.distances(current_level, @player.position)
    current_level.monsters.each do |monster|
      monster.energy += monster.type.speed
      while monster.energy >= 2
        monster.energy -= 2
        monster_action(monster, distances)
        return if @result
      end
    end
  end

  def end_turn
    current_level.monsters.each do |monster|
      monster.hp += 1 if monster.type.traits.include?('R') && monster.hp < monster.max_hp
    end
    if @player.poison.positive?
      @player.hp -= 1
      @counts[:poison_damage] += 1
      if @player.hp <= 0
        die('poison')
        return
      end
      @player.poison -= 1
      say('You feel less sick.') if @player.poison.zero?
    end
    if @player.food.zero?
      @player.hp -= 1
      @counts[:starvation_damage] += 1
      if @player.hp <= 0
        die('starvation')
        return
      end
    else
      previous_hunger = hunger
      @player.food -= 1
      if hunger != previous_hunger
        message = { 'hungry' => 'You are getting hungry.', 'weak' => 'You feel weak from hunger.',
                    'starving' => 'You are starving.' }.fetch(hunger)
        say(message)
      end
    end
    if (@turn % @settings['player'][1]).zero? && @player.poison.zero? && @player.food.positive? && @player.hp < @player.max_hp
      @player.hp += 1
    end
  end

  def exploration(level)
    explored = 0
    non_rock = 0
    level.terrain.each_with_index do |row, y|
      row.each_with_index do |terrain, x|
        next if terrain == ' '

        non_rock += 1
        explored += 1 if level.memory[y][x] != ' '
      end
    end
    [explored, non_rock]
  end

  def frame(level, current)
    width, height = @settings['map']
    border = "+#{'-' * width}+"
    monsters = level.monsters.to_h { |monster| [monster.position, monster.type.symbol] }
    rows = Array.new(height) do |y|
      cells = Array.new(width) do |x|
        position = [x, y]
        if current && @visible.include?(position)
          if position == @player.position
            '@'
          else
            monsters[position] || level.items[position]&.symbol || level.terrain[y][x]
          end
        else
          level.memory[y][x]
        end
      end
      "|#{cells.join}|"
    end
    [border, *rows, border]
  end

  def status_line
    "STATUS hp #{@player.hp}/#{@player.max_hp} level #{@player.level} xp #{@player.xp} " \
      "defense #{defense} gold #{@player.gold} food #{@player.food} #{hunger} poison #{@player.poison}"
  end

  def checkpoint
    @maps << "CHECKPOINT turn #{@turn} depth #{@player.depth}"
    @maps.concat(frame(current_level, true))
    @maps << status_line
  end

  def final_map
    @maps << "FINAL turn #{@counts[:succeeded]} depth #{@player.depth}"
    @levels.first(@player.depth).each do |level|
      explored, non_rock = exploration(level)
      @maps << "LEVEL #{level.depth} explored #{explored}/#{non_rock}"
      @maps.concat(frame(level, level.depth == @player.depth))
    end
    @maps << status_line
  end

  def dec1(numerator, denominator)
    return '-' if denominator.zero?

    rounded = (20 * numerator + denominator) / (2 * denominator)
    "#{rounded / 10}.#{rounded % 10}"
  end

  def attack_line(label, statistics)
    "#{label} #{statistics[:count]} hits #{statistics[:hits]} criticals #{statistics[:criticals]} " \
      "damage #{statistics[:damage]} accuracy #{dec1(100 * statistics[:hits], statistics[:count])}"
  end

  def stats_lines
    lines = [
      "result #{@result}", "cause #{@cause}", "turns #{@counts[:succeeded]}", "depth #{@player.depth}",
      "level #{@player.level}", "xp #{@player.xp}", "hp #{@player.hp}/#{@player.max_hp}",
      "defense #{defense}", "gold #{@player.gold}", "food #{@player.food} #{hunger}", "poison #{@player.poison}",
      "weapon #{@player.weapon&.display_name || '-'}", "armor #{@player.armor&.display_name || '-'}",
      "commands #{@commands.length} executed #{@counts[:succeeded]} failed #{@counts[:failed]} unused #{@counts[:unused]}",
      "moves #{@counts[:moves]}", attack_line('player_attacks', @player_attacks),
      attack_line('monster_attacks', @monster_attacks),
      "poison_damage #{@counts[:poison_damage]} starvation_damage #{@counts[:starvation_damage]}",
      "picked #{@counts[:picked]} quaffed #{@counts[:quaffed]} read #{@counts[:read]} eaten #{@counts[:eaten]} " \
        "wielded #{@counts[:wielded]} worn #{@counts[:worn]}",
      "kills #{@kills.values.sum}"
    ]
    @monster_types.each do |type|
      count = @kills[type.name]
      lines << "KILL #{type.name} #{count}" if count.positive?
    end
    @levels.each do |level|
      explored, non_rock = exploration(level)
      lines << "LEVEL #{level.depth} rooms #{level.rooms.length} explored #{explored}/#{non_rock} " \
               "#{dec1(100 * explored, non_rock)} monsters #{level.killed}/#{level.monsters_created} " \
               "items #{level.picked}/#{level.items_placed}"
    end
    @player.pack.each_with_index do |item, index|
      line = "INVENTORY #{index + 1} #{item.display_name}"
      line += ' (wielded)' if item.equal?(@player.weapon)
      line += ' (worn)' if item.equal?(@player.armor)
      lines << line
    end
    lines
  end

  def play
    @commands.each do |keyword, argument|
      if @result
        @counts[:unused] += 1
        next
      end
      unless execute_command(keyword, argument)
        @counts[:failed] += 1
        next
      end
      @counts[:succeeded] += 1
      next if @result

      update_view
      monster_phase
      next if @result

      end_turn
      next if @result

      checkpoint if @checkpoints.include?(@turn)
      @turn += 1
    end
    unless @result
      @result = 'alive'
      @cause = 'commands_exhausted'
    end
  end

  def write_lines(name, lines)
    File.binwrite("output/#{name}.txt", lines.empty? ? '' : lines.join("\n") + "\n")
  end

  def run
    read_input
    @levels = (1..@settings['levels'][0]).map { |depth| populate_level(depth) }
    initialize_player
    @messages = []
    @maps = []
    @counts = Hash.new(0)
    @kills = Hash.new(0)
    @player_attacks = Hash.new(0)
    @monster_attacks = Hash.new(0)
    @turn = 1
    @result = nil
    update_view
    play
    final_map
    Dir.mkdir('output') unless Dir.exist?('output')
    write_lines('messages', @messages)
    write_lines('maps', @maps)
    write_lines('stats', stats_lines)
  end
end

Roguelike.new.run
