require_relative 'combat'

module Towers
  MODES = %w[FIRST LAST STRONGEST WEAKEST CLOSEST].freeze
  Level = Data.define(:cost, :range, :power, :interval, :shot_speed, :splash,
                      :slow_rate, :slow_time, :burn_amount, :burn_time)
  Type = Data.define(:name, :symbol, :targets, :levels)

  def self.parse_type(header, lines)
    words = header.split
    levels = lines.map { |line| Level.new(*line.split.drop(1).map(&:to_i)) }
    Type.new(words[1], words[2], words[3], levels)
  end

  class Tower
    attr_reader :number, :type, :cell, :built
    attr_accessor :level, :mode, :ready, :investment, :sold
    attr_accessor :shots, :hits, :fizzles, :kills, :damage

    def initialize(number, type, cell, tick)
      @number = number
      @type = type
      @cell = cell
      @built = tick
      @sold = nil
      @level = 1
      @mode = 'FIRST'
      @ready = tick
      @investment = type.levels[0].cost
      @shots = @hits = @fizzles = @kills = @damage = 0
    end

    def standing?
      @sold.nil?
    end

    def performance
      @type.levels[@level - 1]
    end

    def center
      [100 * @cell[0], 100 * @cell[1]]
    end

    def can_aim?(enemy)
      @type.targets == 'both' || @type.targets == enemy.type.movement
    end

    def in_range?(position)
      Combat.squared_distance(center, position) <= performance.range * performance.range
    end

    def select_target(enemies, field, exit_position)
      candidates = enemies.select { |enemy| can_aim?(enemy) && in_range?(enemy.position) }
      candidates.min_by do |enemy|
        priority = case @mode
                   when 'FIRST' then enemy.remaining(field, exit_position)
                   when 'LAST' then -enemy.remaining(field, exit_position)
                   when 'STRONGEST' then -enemy.hp
                   when 'WEAKEST' then enemy.hp
                   when 'CLOSEST' then Combat.squared_distance(center, enemy.position)
                   end
        [priority, enemy.number]
      end
    end
  end
end
