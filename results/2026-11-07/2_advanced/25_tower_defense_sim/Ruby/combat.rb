module Combat
  def self.squared_distance(first, second)
    dx = first[0] - second[0]
    dy = first[1] - second[1]
    dx * dx + dy * dy
  end

  def self.advance(position, aim, speed)
    dx = aim[0] - position[0]
    dy = aim[1] - position[1]
    squared = dx * dx + dy * dy
    return [aim.dup, true] if squared <= speed * speed

    length = Integer.sqrt(squared)
    step_x = dx >= 0 ? dx * speed / length : -((-dx) * speed / length)
    step_y = dy >= 0 ? dy * speed / length : -((-dy) * speed / length)
    [[position[0] + step_x, position[1] + step_y], false]
  end

  def self.armored_damage(enemy, power)
    [enemy.hp, [1, power - enemy.type.armor].max].min
  end

  class Effect
    attr_reader :strength, :remaining, :source

    def initialize
      @strength = 0
      @remaining = 0
      @source = nil
    end

    def receive(strength, duration, source = nil)
      if strength > @strength
        @strength = strength
        @remaining = duration
        @source = source
      elsif strength == @strength
        @remaining = [@remaining, duration].max
      end
    end

    def advance
      @remaining -= 1
      return unless @remaining.zero?

      @strength = 0
      @source = nil
    end
  end

  class Projectile
    attr_reader :number, :tower, :target, :performance, :position, :aim

    def initialize(number, tower, target)
      @number = number
      @tower = tower
      @target = target
      @performance = tower.performance
      @targets = tower.type.targets
      @position = tower.center
      @aim = target.position
    end

    def fly
      @aim = @target.position if @target.alive
      return true if @performance.shot_speed.zero?

      @position, arrived = Combat.advance(@position, @aim, @performance.shot_speed)
      arrived
    end

    def can_aim?(enemy)
      @targets == 'both' || @targets == enemy.type.movement
    end
  end
end
