module Game
  TILE_ORDER = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ?'

  class Minstd
    def initialize(seed)
      @state = seed
    end

    def next
      @state = 48271 * @state % 2147483647
    end
  end

  module_function

  def shuffle(bag, random)
    (bag.size - 1).downto(1) do |i|
      j = random.next % (i + 1)
      bag[i], bag[j] = bag[j], bag[i]
    end
    bag
  end

  def make_bag(counts, random)
    shuffle(TILE_ORDER.chars.flat_map { |letter| Array.new(counts[letter], letter) }, random)
  end

  def draw(bag, count)
    [count, bag.size].min.times.map { bag.pop }.join
  end

  def exchange(bag, returned, random)
    drawn = draw(bag, returned.size)
    bag.concat(returned.chars.sort)
    shuffle(bag, random)
    drawn
  end

  def points(collection, values)
    collection.each_char.reduce(0) { |score, letter| score + values[letter] }
  end
end
