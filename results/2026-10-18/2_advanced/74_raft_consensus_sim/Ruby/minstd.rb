class Minstd
  attr_reader :draws

  def initialize(seed)
    @state = seed
    @draws = 0
  end

  def draw
    @draws += 1
    @state = 48_271 * @state % 2_147_483_647
  end

  def between(low, high)
    low + draw % (high - low + 1)
  end
end
