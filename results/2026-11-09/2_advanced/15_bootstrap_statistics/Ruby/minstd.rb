class Minstd
  def initialize(seed)
    @state = seed
  end

  def draw
    @state = (48_271 * @state) % 2_147_483_647
  end

  def below(limit)
    draw % limit
  end

  def shuffle(values)
    (values.length - 1).downto(1) do |index|
      other = below(index + 1)
      values[index], values[other] = values[other], values[index]
    end
    values
  end
end
