class Cache
  attr_reader :entries, :replacement, :fills, :evictions

  def initialize(sets, ways, replacement)
    @sets, @ways, @replacement = sets, ways, replacement
    @entries = Array.new(sets) { Array.new(ways) }
    @times = Array.new(sets) { Array.new(ways, 0) }
    @bits = Array.new(sets) { Array.new(ways, 0) }
    @fills, @evictions = Array.new(sets, 0), Array.new(sets, 0)
    @clock = 0
  end

  def locate(block)
    row = block % @sets
    way = @entries[row].index { |item| item && item[:block] == block }
    way && [row, way]
  end

  def state(block)
    position = locate(block)
    position ? @entries[position[0]][position[1]][:state] : 'I'
  end

  def change(block, state)
    position = locate(block)
    @entries[position[0]][position[1]][:state] = state if position
  end

  def remove(block)
    position = locate(block)
    return unless position
    row, way = position
    old = @entries[row][way]
    @entries[row][way] = nil
    old
  end

  def touch_way(row, way, fill = false)
    if @replacement == 'LRU' || (@replacement == 'FIFO' && fill)
      @clock += 1
      @times[row][way] = @clock
    elsif @replacement == 'PLRU'
      low, high, node = 0, @ways, 1
      while high - low > 1
        middle = (low + high) / 2
        if way < middle
          @bits[row][node] = 1
          high, node = middle, node * 2
        else
          @bits[row][node] = 0
          low, node = middle, node * 2 + 1
        end
      end
    end
  end

  def touch(block)
    position = locate(block)
    touch_way(*position) if position
  end

  def victim(row)
    return (0...@ways).min_by { |way| [@times[row][way], way] } unless @replacement == 'PLRU'
    low, high, node = 0, @ways, 1
    while high - low > 1
      middle = (low + high) / 2
      if @bits[row][node].zero?
        high, node = middle, node * 2
      else
        low, node = middle, node * 2 + 1
      end
    end
    low
  end

  def fill(block, state)
    row = block % @sets
    way = @entries[row].index(nil) || victim(row)
    old = @entries[row][way]
    @evictions[row] += 1 if old
    @entries[row][way] = { block: block, state: state }
    @fills[row] += 1
    touch_way(row, way, true)
    old
  end

  def order(row)
    return @ways == 1 ? '-' : @bits[row][1...@ways].join if @replacement == 'PLRU'
    active = (0...@ways).select { |way| @entries[row][way] }
    active.empty? ? '-' : active.sort_by { |way| [-@times[row][way], way] }.join(' ')
  end

  def lines
    @entries.flatten.compact
  end
end
