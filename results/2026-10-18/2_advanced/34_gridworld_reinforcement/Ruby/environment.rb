ACTION_LETTERS = %w[N E S W].freeze

class World
  attr_reader :rows, :cols, :kinds, :wind, :terminal_rewards, :states, :terminals,
              :state_index, :terminal_index, :start, :start_state

  def self.read(path)
    lines = File.readlines(path, chomp: true)
    rows = lines[0].split[1].to_i
    cols = lines[1].split[1].to_i
    kinds = lines[2, rows].join
    wind = lines[rows + 2].split[1].chars.map(&:to_i)
    rewards = lines[rows + 3].split.drop(1).map(&:to_i)
    new(rows, cols, kinds, wind, rewards)
  end

  def initialize(rows, cols, kinds, wind, rewards)
    @rows, @cols, @kinds, @wind, @terminal_rewards = rows, cols, kinds, wind, rewards
    @states, @terminals = [], []
    @state_index = Array.new(kinds.length)
    @terminal_index = Array.new(kinds.length)
    kinds.each_char.with_index do |kind, cell|
      if kind == "G" || kind == "P"
        @terminal_index[cell] = @terminals.length
        @terminals << cell
      elsif kind != "#"
        @state_index[cell] = @states.length
        @states << cell
      end
    end
    @start = kinds.index("S")
    @start_state = @state_index[@start]
  end

  def terminal?(cell)
    !@terminal_index[cell].nil?
  end

  def terminal_name(cell)
    @kinds[cell] == "G" ? "goal" : "pit"
  end

  def move(cell, direction)
    target = cell + [-@cols, 1, @cols, -1][direction]
    target = cell if @kinds[target] == "#"
    return target if terminal?(target)

    @wind[cell % @cols].times do
      above = target - @cols
      break if @kinds[above] == "#"

      target = above
      break if terminal?(target)
    end
    target
  end
end

class RandomGenerator
  def initialize(seed)
    @value = seed
  end

  def draw
    @value = (48_271 * @value) % 2_147_483_647
  end
end

class Environment
  attr_reader :world, :slip_total, :moves, :transitions

  def initialize(world, step_reward, slip_total, floor_slip, ice_slip)
    @world, @step_reward, @slip_total = world, step_reward, slip_total
    @floor_slip, @ice_slip = floor_slip, ice_slip
    @moves = world.states.map { |cell| Array.new(4) { |direction| world.move(cell, direction) } }
    @transitions = world.states.each_index.map do |state|
      Array.new(4) do |action|
        slip_outcomes(state, action).filter_map do |direction, numerator|
          [@moves[state][direction], numerator] if numerator.positive?
        end
      end
    end
  end

  def slip(state)
    @world.kinds[@world.states[state]] == "~" ? @ice_slip : @floor_slip
  end

  def slip_outcomes(state, action)
    p = slip(state)
    [[action, @slip_total - 2 * p], [(action + 1) % 4, p], [(action + 3) % 4, p]]
  end

  def reward(cell)
    terminal = @world.terminal_index[cell]
    terminal.nil? ? @step_reward : @world.terminal_rewards[terminal]
  end

  def step(generator, state, action)
    draw = generator.draw % @slip_total
    p = slip(state)
    direction = if draw < @slip_total - 2 * p
                  action
                elsif draw < @slip_total - p
                  (action + 1) % 4
                else
                  (action + 3) % 4
                end
    cell = @moves[state][direction]
    [cell, reward(cell)]
  end
end
