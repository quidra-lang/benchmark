require_relative 'combat'

module Enemies
  Type = Data.define(:name, :symbol, :movement, :hp, :armor, :speed, :bounty,
                     :lives, :regen, :split_into, :split_count)
  Group = Data.define(:type, :spawn, :count, :delay, :interval, :multiplier)

  def self.parse_type(words)
    Type.new(words[1], words[2], words[3], *words[4, 6].map(&:to_i),
             words[10], words[11].to_i)
  end

  def self.parse_group(words)
    Group.new(words[1], *words.drop(2).map(&:to_i))
  end

  class Enemy
    attr_reader :number, :type, :multiplier, :maximum_hp, :slow, :burn
    attr_accessor :hp, :current, :next_cell, :progress, :air_position, :alive

    def initialize(number, type, multiplier)
      @number = number
      @type = type
      @multiplier = multiplier
      @maximum_hp = type.hp * multiplier / 100
      @hp = @maximum_hp
      @slow = Combat::Effect.new
      @burn = Combat::Effect.new
      @alive = true
    end

    def self.spawn(number, type, multiplier, cell, field)
      enemy = new(number, type, multiplier)
      if enemy.ground?
        enemy.current = cell.dup
        enemy.next_cell = field.next_cell(cell)
        enemy.progress = 0
      else
        enemy.air_position = [100 * cell[0], 100 * cell[1]]
      end
      enemy
    end

    def self.split(number, type, parent)
      enemy = new(number, type, parent.multiplier)
      if enemy.ground?
        enemy.current = parent.current.dup
        enemy.next_cell = parent.next_cell.dup
        enemy.progress = parent.progress
      else
        enemy.air_position = parent.air_position.dup
      end
      enemy
    end

    def ground?
      @type.movement == 'ground'
    end

    def position
      return @air_position unless ground?

      [100 * @current[0] + (@next_cell[0] - @current[0]) * @progress,
       100 * @current[1] + (@next_cell[1] - @current[1]) * @progress]
    end

    def occupied
      return @progress < 50 ? @current : @next_cell if ground?

      [(@air_position[0] + 50) / 100, (@air_position[1] + 50) / 100]
    end

    def remaining(field, exit_position)
      return 100 * field.distance(@next_cell) + 100 - @progress if ground?

      Integer.sqrt(Combat.squared_distance(@air_position, exit_position))
    end

    def movement_speed
      speed = @type.speed
      if @slow.remaining.positive?
        speed = speed * (100 - @slow.strength) / 100
        @slow.advance
      end
      speed
    end
  end
end
