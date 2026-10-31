# frozen_string_literal: true

module Combat
  Attack = Struct.new(:kind, :damage)

  def self.dice(token)
    token.split('d').map(&:to_i)
  end

  def self.resolve(generator, modifier, defense, dice, bonus)
    roll = 1 + generator.rnd(20)
    return Attack.new(:miss, 0) if roll == 1

    if roll == 20
      kind = :critical
      damage = generator.roll(dice) + generator.roll(dice) + bonus
    elsif roll + modifier >= defense
      kind = :hit
      damage = generator.roll(dice) + bonus
    else
      return Attack.new(:miss, 0)
    end
    Attack.new(kind, [damage, 1].max)
  end
end
