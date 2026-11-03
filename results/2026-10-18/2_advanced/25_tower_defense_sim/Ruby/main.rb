require 'fileutils'
require_relative 'grid_map'
require_relative 'pathing'
require_relative 'towers'
require_relative 'enemies'
require_relative 'combat'

class TowerDefense
  Wave = Data.define(:reward, :groups)

  def initialize
    @grid = GridMap.new('input/map.txt')
    @exit_position = @grid.center(@grid.exit)
    read_towers
    read_waves
    read_actions
    read_parameters
    @gold = @parameters['gold'][0]
    @starting_lives = @parameters['lives'][0]
    @lives = @starting_lives
    @next_start = @parameters['schedule'][0]
    @towers = []
    @standing = {}
    @enemies = {}
    @projectiles = {}
    @enemy_number = 0
    @projectile_number = 0
    @wave_records = []
    @active = nil
    @field = Pathing::Field.new(@grid, @standing)
    @events = []
    @snapshots = []
    @cell_kills = Array.new(@grid.height) { Array.new(@grid.width, 0) }
    @enemy_stats = @enemy_types.to_h do |name, _type|
      [name, { spawned: 0, killed: 0, leaked: 0, damage: 0 }]
    end
    @income = { bounty: 0, reward: 0, interest: 0, early: 0, refund: 0 }
    @spent = 0
    @spawned = @killed = @leaked = 0
    @action_index = @actions_done = @actions_refused = 0
    @outcome = nil
  end

  def read_towers
    lines = File.readlines('input/towers.txt', chomp: true)
    @tower_types = {}
    cursor = 0
    while cursor < lines.length
      header = lines[cursor]
      count = header.split[-1].to_i
      type = Towers.parse_type(header, lines[cursor + 1, count])
      @tower_types[type.name] = type
      cursor += count + 1
    end
  end

  def read_waves
    @enemy_types = {}
    @waves = []
    File.foreach('input/waves.txt') do |line|
      words = line.split
      case words[0]
      when 'enemy'
        type = Enemies.parse_type(words)
        @enemy_types[type.name] = type
      when 'wave'
        @waves << Wave.new(words[1].to_i, [])
      when 'group'
        @waves[-1].groups << Enemies.parse_group(words)
      end
    end
  end

  def read_actions
    @actions = File.readlines('input/actions.txt', chomp: true).map do |line|
      words = line.split
      [words[0].to_i, words[1], words.drop(2)]
    end
  end

  def read_parameters
    @parameters = File.readlines('input/params.txt', chomp: true).to_h do |line|
      words = line.split
      [words[0], words.drop(1).map(&:to_i)]
    end
  end

  def run
    @tick = 0
    until @outcome
      @tick += 1
      perform_actions
      spawn_phase
      move_enemies
      break if @outcome

      fire_towers
      move_projectiles
      finish_wave
      snapshot(false) if @parameters['snapshots'].include?(@tick)
    end
    snapshot(true)
    write_outputs
  end

  def event(body)
    @events << "#{@tick} #{body}"
  end

  def perform_actions
    while @action_index < @actions.length && @actions[@action_index][0] == @tick
      _time, command, arguments = @actions[@action_index]
      succeeded = case command
                  when 'BUILD' then build(arguments)
                  when 'UPGRADE' then upgrade(arguments[0].to_i)
                  when 'SELL' then sell(arguments[0].to_i)
                  when 'TARGET' then target(arguments[0].to_i, arguments[1])
                  when 'CALL' then call_wave
                  end
      if succeeded
        @actions_done += 1
      else
        @actions_refused += 1
      end
      @action_index += 1
    end
  end

  def build(arguments)
    name, x_text, y_text = arguments
    cell = [x_text.to_i, y_text.to_i]
    type = @tower_types[name]
    ground_enemies = @enemies.values.select(&:ground?)
    reason = if type.nil?
               'type'
             elsif !@grid.inside?(cell)
               'bounds'
             elsif !@grid.buildable?(cell)
               'terrain'
             elsif @standing.key?(cell)
               'tower'
             elsif @gold < type.levels[0].cost
               'gold'
             elsif ground_enemies.any? { |enemy| enemy.current == cell || enemy.next_cell == cell }
               'enemy'
             end
    if reason.nil?
      trial = Pathing::Field.new(@grid, @standing.merge(cell => true))
      blocked = @grid.spawns.values.any? { |spawn| trial.distance(spawn).nil? }
      blocked ||= ground_enemies.any? { |enemy| trial.distance(enemy.next_cell).nil? }
      reason = 'blocked' if blocked
    end
    if reason
      event("BUILD_REFUSED #{name} #{x_text} #{y_text} #{reason}")
      return false
    end

    tower = Towers::Tower.new(@towers.length + 1, type, cell, @tick)
    @towers << tower
    @standing[cell] = tower
    cost = tower.investment
    @gold -= cost
    @spent += cost
    event("BUILD T#{tower.number} #{name} #{cell.join(' ')} cost #{cost} gold #{@gold}")
    update_field
    true
  end

  def standing_tower(number)
    tower = @towers[number - 1]
    tower if tower&.standing?
  end

  def refuse(command, number, reason)
    event("#{command}_REFUSED T#{number} #{reason}")
    false
  end

  def upgrade(number)
    tower = standing_tower(number)
    return refuse('UPGRADE', number, 'notower') unless tower
    return refuse('UPGRADE', number, 'maxlevel') if tower.level == tower.type.levels.length

    cost = tower.type.levels[tower.level].cost
    return refuse('UPGRADE', number, 'gold') if @gold < cost

    @gold -= cost
    @spent += cost
    tower.level += 1
    tower.investment += cost
    event("UPGRADE T#{number} level #{tower.level} cost #{cost} gold #{@gold}")
    true
  end

  def sell(number)
    tower = standing_tower(number)
    return refuse('SELL', number, 'notower') unless tower

    rate = tower.built == @tick ? 100 : @parameters['sell'][0]
    refund = tower.investment * rate / 100
    tower.sold = @tick
    @standing.delete(tower.cell)
    @gold += refund
    @income[:refund] += refund
    event("SELL T#{number} refund #{refund} gold #{@gold}")
    update_field
    true
  end

  def target(number, mode)
    tower = standing_tower(number)
    return refuse('TARGET', number, 'notower') unless tower
    return refuse('TARGET', number, 'mode') unless Towers::MODES.include?(mode)

    tower.mode = mode
    event("TARGET T#{number} #{mode}")
    true
  end

  def call_wave
    if @active
      event('CALL_REFUSED active')
      return false
    end
    bonus = (@next_start - @tick) * @parameters['early'][0]
    @gold += bonus
    @income[:early] += bonus
    @next_start = @tick
    event("CALL #{@wave_records.length + 1} bonus #{bonus} gold #{@gold}")
    true
  end

  def update_field
    before = @field
    @field = Pathing::Field.new(@grid, @standing)
    @grid.spawns.each do |number, cell|
      old_distance = before.distance(cell)
      new_distance = @field.distance(cell)
      event("REPATH #{number} #{old_distance} #{new_distance}") if old_distance != new_distance
    end
  end

  def start_wave
    number = @wave_records.length + 1
    definition = @waves[number - 1]
    @active = {
      number: number, definition: definition, start: @tick, end: nil,
      status: 'active', spawned: 0, peak: 0, kills: 0, leaks: 0,
      lives_lost: 0, bounty: 0, reward: 0, interest: 0, gold: 0, lives: 0,
      groups_spawned: Array.new(definition.groups.length, 0), damage: Hash.new(0)
    }
    @wave_records << @active
    @next_start = nil
    count = definition.groups.sum(&:count)
    event("WAVE_START #{number} enemies #{count}")
  end

  def spawn_phase
    start_wave if @tick == @next_start
    return unless @active

    @active[:definition].groups.each_with_index do |group, index|
      appeared = @active[:groups_spawned][index]
      next if appeared == group.count
      next unless @tick == @active[:start] + group.delay + appeared * group.interval

      @enemy_number += 1
      enemy = Enemies::Enemy.spawn(@enemy_number, @enemy_types[group.type],
                                   group.multiplier, @grid.spawns[group.spawn], @field)
      register_enemy(enemy, group.spawn)
      @active[:groups_spawned][index] += 1
    end
    @active[:peak] = [@active[:peak], @enemies.length].max
  end

  def register_enemy(enemy, origin)
    @enemies[enemy.number] = enemy
    @spawned += 1
    @active[:spawned] += 1
    @enemy_stats[enemy.type.name][:spawned] += 1
    event("SPAWN E#{enemy.number} #{enemy.type.name} #{origin} hp #{enemy.hp}")
  end

  def credit_damage(enemy, tower, damage)
    tower.damage += damage
    @enemy_stats[enemy.type.name][:damage] += damage
    @active[:damage][tower.number] += damage
  end

  def remove_enemy(enemy)
    enemy.alive = false
    @enemies.delete(enemy.number)
  end

  def kill(enemy, tower)
    remove_enemy(enemy)
    x, y = enemy.occupied
    @cell_kills[y][x] += 1
    tower.kills += 1
    @killed += 1
    @active[:kills] += 1
    @enemy_stats[enemy.type.name][:killed] += 1
    bounty = enemy.type.bounty
    @gold += bounty
    @income[:bounty] += bounty
    @active[:bounty] += bounty
    event("KILL E#{enemy.number} #{enemy.type.name} T#{tower.number} bounty #{bounty} gold #{@gold}")
    enemy.type.split_count.times do
      @enemy_number += 1
      child = Enemies::Enemy.split(@enemy_number, @enemy_types[enemy.type.split_into], enemy)
      register_enemy(child, "E#{enemy.number}")
    end
  end

  def move_enemies
    # The snapshot excludes children created by burning during this phase.
    @enemies.values.each do |enemy|
      move_enemy(enemy)
      break if @outcome
    end
  end

  def move_enemy(enemy)
    if enemy.burn.remaining.positive?
      tower = enemy.burn.source
      damage = [enemy.hp, enemy.burn.strength].min
      enemy.hp -= damage
      credit_damage(enemy, tower, damage)
      enemy.burn.advance
      if enemy.hp.zero?
        kill(enemy, tower)
        return
      end
    end

    enemy.hp = [enemy.hp + enemy.type.regen, enemy.maximum_hp].min
    speed = enemy.movement_speed
    if enemy.ground?
      speed /= 2 if @grid.water?(enemy.occupied)
      arrived = move_ground(enemy, speed)
    else
      enemy.air_position, arrived = Combat.advance(enemy.air_position, @exit_position, speed)
    end
    leak(enemy) if arrived
  end

  def move_ground(enemy, speed)
    while speed.positive?
      remaining = 100 - enemy.progress
      if speed < remaining
        enemy.progress += speed
        speed = 0
      else
        speed -= remaining
        enemy.current = enemy.next_cell
        enemy.progress = 0
        return true if enemy.current == @grid.exit

        enemy.next_cell = @field.next_cell(enemy.current)
      end
    end
    false
  end

  def leak(enemy)
    remove_enemy(enemy)
    loss = [@lives, enemy.type.lives].min
    @lives -= loss
    @leaked += 1
    @active[:leaks] += 1
    @active[:lives_lost] += loss
    @enemy_stats[enemy.type.name][:leaked] += 1
    event("LEAK E#{enemy.number} #{enemy.type.name} lives #{@lives}")
    return unless @lives.zero?

    event('DEFEAT')
    @outcome = 'defeat'
    @active[:end] = @tick
    @active[:status] = 'lost'
    @active[:gold] = @gold
    @active[:lives] = @lives
  end

  def fire_towers
    @towers.each do |tower|
      next unless tower.standing? && @tick >= tower.ready

      enemy = tower.select_target(@enemies.values, @field, @exit_position)
      next unless enemy

      @projectile_number += 1
      projectile = Combat::Projectile.new(@projectile_number, tower, enemy)
      @projectiles[projectile.number] = projectile
      tower.shots += 1
      tower.ready = @tick + tower.performance.interval
      event("SHOT T#{tower.number} E#{enemy.number}")
    end
  end

  def move_projectiles
    @projectiles.values.each do |projectile|
      next unless projectile.fly

      @projectiles.delete(projectile.number)
      performance = projectile.performance
      victims = if performance.splash.zero?
                  projectile.target.alive ? [projectile.target] : []
                else
                  @enemies.values.select do |enemy|
                    projectile.can_aim?(enemy) &&
                      Combat.squared_distance(enemy.position, projectile.aim) <= performance.splash**2
                  end
                end
      projectile.tower.fizzles += 1 if victims.empty?
      # The complete list is fixed before any of its victims can split.
      victims.each { |enemy| impact(projectile, enemy) }
    end
  end

  def impact(projectile, enemy)
    tower = projectile.tower
    performance = projectile.performance
    tower.hits += 1
    damage = Combat.armored_damage(enemy, performance.power)
    enemy.hp -= damage
    credit_damage(enemy, tower, damage)
    if enemy.hp.zero?
      kill(enemy, tower)
    else
      enemy.slow.receive(performance.slow_rate, performance.slow_time) if performance.slow_rate.positive?
      if performance.burn_amount.positive?
        enemy.burn.receive(performance.burn_amount, performance.burn_time, tower)
      end
    end
  end

  def finish_wave
    return unless @active && @enemies.empty?
    all_spawned = @active[:definition].groups.each_with_index.all? do |group, index|
      @active[:groups_spawned][index] == group.count
    end
    return unless all_spawned

    wave = @active
    reward = wave[:definition].reward
    @gold += reward
    rate, cap = @parameters['interest']
    interest = [cap, @gold * rate / 100].min
    @gold += interest
    @income[:reward] += reward
    @income[:interest] += interest
    wave[:end] = @tick
    wave[:status] = 'cleared'
    wave[:reward] = reward
    wave[:interest] = interest
    wave[:gold] = @gold
    wave[:lives] = @lives
    @active = nil
    event("WAVE_END #{wave[:number]} reward #{reward} interest #{interest} gold #{@gold}")
    if wave[:number] == @waves.length
      @outcome = 'victory'
      event('VICTORY')
    else
      @next_start = @tick + @parameters['schedule'][1]
    end
  end

  def picture_rows
    picture = @grid.rows.map(&:dup)
    @grid.spawns.each_value do |spawn|
      @field.path(spawn).each do |cell|
        picture[cell[1]][cell[0]] = '+' if ['.', '~'].include?(@grid.terrain(cell))
      end
    end
    @standing.each { |cell, tower| picture[cell[1]][cell[0]] = tower.type.symbol }
    occupied = Hash.new { |hash, cell| hash[cell] = [] }
    @enemies.each_value { |enemy| occupied[enemy.occupied] << enemy }
    occupied.each do |cell, enemies|
      picture[cell[1]][cell[0]] = enemies.length == 1 ? enemies[0].type.symbol : '*'
    end
    picture
  end

  def grid_lines(rows)
    ruler = (0...@grid.width).map { |x| (x % 10).to_s }.join
    ["  #{ruler}"] + rows.each_with_index.map { |row, y| "#{y % 10} #{row}" }
  end

  def snapshot(final)
    next_start = @active.nil? && @outcome.nil? ? @next_start : '-'
    heading = final ? 'FINAL' : 'SNAPSHOT'
    @snapshots << "#{heading} #{@tick} wave #{@wave_records.length} next #{next_start} gold #{@gold} lives #{@lives}"
    @snapshots.concat(grid_lines(picture_rows))
    @grid.spawns.each do |number, cell|
      @snapshots << "PATH #{number} length #{@field.distance(cell)}"
    end
    @towers.each do |tower|
      next unless tower.standing?

      @snapshots << "T#{tower.number} #{tower.type.name} #{tower.cell.join(' ')} level #{tower.level} mode #{tower.mode} ready #{tower.ready}"
    end
    @enemies.each_value do |enemy|
      @snapshots << "E#{enemy.number} #{enemy.type.name} #{enemy.position.join(' ')} hp #{enemy.hp}/#{enemy.maximum_hp} slow #{enemy.slow.strength} #{enemy.slow.remaining} burn #{enemy.burn.strength} #{enemy.burn.remaining}"
    end
    @projectiles.each_value do |projectile|
      @snapshots << "P#{projectile.number} T#{projectile.tower.number} E#{projectile.target.number} #{projectile.position.join(' ')}"
    end
    return unless final

    @snapshots << 'FLOW'
    @snapshots.concat(grid_lines(analysis_picture(:flow)))
    @snapshots << 'COVERAGE'
    @snapshots.concat(grid_lines(analysis_picture(:coverage)))
    @snapshots << 'KILLS'
    @snapshots.concat(grid_lines(analysis_picture(:kills)))
  end

  def digit(value)
    return '.' if value.zero?

    value < 10 ? value.to_s : '*'
  end

  def analysis_picture(kind)
    Array.new(@grid.height) do |y|
      Array.new(@grid.width) do |x|
        cell = [x, y]
        tower = @standing[cell]
        if kind == :kills
          kills = @cell_kills[y][x]
          kills.positive? ? digit(kills) : (@grid.rock?(cell) ? '#' : '.')
        elsif @grid.rock?(cell)
          '#'
        elsif kind == :flow && cell == @grid.exit
          'E'
        elsif tower
          tower.type.symbol
        elsif kind == :flow
          @field.distance(cell).nil? ? '?' : @field.arrow(cell)
        else
          center = @grid.center(cell)
          digit(@standing.values.count { |standing| standing.in_range?(center) })
        end
      end.join
    end
  end

  def wave_lines
    columns = %w[wave start end status spawned peak kills leaks lives_lost bounty reward interest gold lives]
    lines = [(columns + @towers.map { |tower| "T#{tower.number}" }).join(',')]
    @wave_records.each do |wave|
      values = [wave[:number], wave[:start], wave[:end], wave[:status],
                wave[:spawned], wave[:peak], wave[:kills], wave[:leaks],
                wave[:lives_lost], wave[:bounty], wave[:reward], wave[:interest],
                wave[:gold], wave[:lives]]
      @towers.each { |tower| values << wave[:damage][tower.number] }
      lines << values.join(',')
    end
    lines
  end

  def decimal_one(numerator, denominator)
    return '-' if denominator.zero?

    rounded = (20 * numerator + denominator) / (2 * denominator)
    "#{rounded / 10}.#{rounded % 10}"
  end

  def summary_lines
    cleared = @wave_records.count { |wave| wave[:status] == 'cleared' }
    perfect = @wave_records.count { |wave| wave[:status] == 'cleared' && wave[:leaks].zero? }
    damage = @towers.sum(&:damage)
    score = 10 * @killed + 100 * @lives + 50 * perfect + @gold
    lines = [
      "outcome #{@outcome}",
      "ticks #{@tick}",
      "waves #{cleared}/#{@waves.length} perfect #{perfect}",
      "lives #{@lives}/#{@starting_lives}",
      "gold #{@gold}",
      "enemies spawned #{@spawned} killed #{@killed} leaked #{@leaked}",
      "income bounty #{@income[:bounty]} reward #{@income[:reward]} interest #{@income[:interest]} early #{@income[:early]} refund #{@income[:refund]}",
      "spent #{@spent}",
      "damage #{damage}",
      "actions total #{@actions.length} done #{@actions_done} refused #{@actions_refused} unused #{@actions.length - @action_index}",
      "score #{score}"
    ]
    mvp = @towers.min_by { |tower| [-tower.damage, tower.number] }
    lines << (mvp ? "mvp T#{mvp.number} damage #{mvp.damage}" : 'mvp -')
    @enemy_types.each_key do |name|
      counts = @enemy_stats[name]
      lines << "ENEMY #{name} spawned #{counts[:spawned]} killed #{counts[:killed]} leaked #{counts[:leaked]} damage #{counts[:damage]}"
    end
    @towers.each do |tower|
      state = tower.standing? ? 'active' : "sold #{tower.sold}"
      per_shot = decimal_one(tower.damage, tower.shots)
      share = decimal_one(100 * tower.damage, damage)
      lines << "TOWER T#{tower.number} #{tower.type.name} #{tower.cell.join(' ')} level #{tower.level} mode #{tower.mode} #{state} shots #{tower.shots} hits #{tower.hits} fizzles #{tower.fizzles} kills #{tower.kills} damage #{tower.damage} per_shot #{per_shot} share #{share} invested #{tower.investment}"
    end
    lines
  end

  def write_outputs
    FileUtils.mkdir_p('output')
    files = {
      'events.txt' => @events,
      'waves.csv' => wave_lines,
      'snapshots.txt' => @snapshots,
      'summary.txt' => summary_lines
    }
    files.each do |name, lines|
      text = lines.empty? ? '' : lines.join("\n") + "\n"
      File.binwrite(File.join('output', name), text)
    end
  end
end

TowerDefense.new.run
