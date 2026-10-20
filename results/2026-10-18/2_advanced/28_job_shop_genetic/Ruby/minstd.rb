module JobShop
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

    def decide(fraction)
      numerator, denominator = fraction
      below(denominator) < numerator
    end

    def shuffle(sequence)
      sequence.length.downto(2) do |length|
        index = below(length)
        sequence[length - 1], sequence[index] = sequence[index], sequence[length - 1]
      end
      sequence
    end
  end
end
