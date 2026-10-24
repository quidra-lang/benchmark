# frozen_string_literal: true

class Minstd
  def initialize(seed)
    @state = seed
  end

  def draw
    @state = (48_271 * @state) % 2_147_483_647
  end

  def rnd(limit)
    draw % limit
  end

  def roll(dice)
    dice[0].times.sum { 1 + rnd(dice[1]) }
  end

  def choose(weights)
    target = rnd(weights.sum)
    cumulative = 0
    weights.each_with_index do |weight, index|
      cumulative += weight
      return index if target < cumulative
    end
  end
end
