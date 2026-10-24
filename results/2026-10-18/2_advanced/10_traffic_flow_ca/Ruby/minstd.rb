# frozen_string_literal: true

class Minstd
  def initialize(seed)
    @state = seed
  end

  def draw
    @state = 48_271 * @state % 2_147_483_647
  end

  def self.select(weights, value)
    remainder = value % weights.sum
    weights.each_with_index do |weight, index|
      return index if remainder < weight

      remainder -= weight
    end
  end
end
