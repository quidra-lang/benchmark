class BTB
  def initialize(entries)
    @entries = Array.new(entries)
  end

  def lookup(pc)
    entry = @entries[pc.div(4) % @entries.length]
    entry && entry[0] == pc ? entry[1] : nil
  end

  def insert(pc, target)
    @entries[pc.div(4) % @entries.length] = [pc, target]
  end
end

class RAS
  def initialize(depth)
    @depth, @stack = depth, []
  end

  def push(address)
    return if @depth.zero?
    @stack.shift if @stack.length == @depth
    @stack << address
  end

  def pop = @stack.pop
end

class DirectionPredictor
  def initialize(scheme, parameters)
    @scheme, @parameters, @history = scheme, parameters, 0
    case scheme
    when 'ONEBIT', 'TWOBIT', 'GSHARE'
      @table = Array.new(parameters[0], scheme == 'ONEBIT' ? 0 : 1)
    when 'TOURNAMENT'
      local, global_size, _, chooser = parameters
      @local = Array.new(local, 1)
      @global_table = Array.new(global_size, 1)
      @chooser = Array.new(chooser, 1)
    end
  end

  def updated(counter, taken) = (counter + (taken ? 1 : -1)).clamp(0, 3)

  def prediction(pc, target)
    word = pc.div(4)
    case @scheme
    when 'STATIC_NT', 'PERFECT' then false
    when 'BTFN' then target < pc
    when 'ONEBIT' then @table[word % @table.length] == 1
    when 'TWOBIT' then @table[word % @table.length] >= 2
    when 'GSHARE' then @table[(word ^ @history) % @table.length] >= 2
    when 'TOURNAMENT'
      local = @local[word % @local.length] >= 2
      global_prediction = @global_table[(word ^ @history) % @global_table.length] >= 2
      @chooser[word % @chooser.length] >= 2 ? global_prediction : local
    end
  end

  def update(pc, taken)
    return if %w[STATIC_NT BTFN PERFECT].include?(@scheme)
    word = pc.div(4)
    if @scheme == 'TOURNAMENT'
      li, gi, ci = word % @local.length, (word ^ @history) % @global_table.length, word % @chooser.length
      local = @local[li] >= 2
      global_prediction = @global_table[gi] >= 2
      @chooser[ci] = updated(@chooser[ci], global_prediction == taken) if local != global_prediction
      @local[li] = updated(@local[li], taken)
      @global_table[gi] = updated(@global_table[gi], taken)
      @history = (2 * @history + (taken ? 1 : 0)) % (1 << @parameters[2])
    else
      index = (@scheme == 'GSHARE' ? word ^ @history : word) % @table.length
      @table[index] = @scheme == 'ONEBIT' ? (taken ? 1 : 0) : updated(@table[index], taken)
      @history = (2 * @history + (taken ? 1 : 0)) % (1 << @parameters[1]) if @scheme == 'GSHARE'
    end
  end

  def storage_bits
    case @scheme
    when 'STATIC_NT', 'BTFN', 'PERFECT' then 0
    when 'ONEBIT' then @parameters[0]
    when 'TWOBIT' then 2 * @parameters[0]
    when 'GSHARE' then 2 * @parameters[0] + @parameters[1]
    when 'TOURNAMENT'
      local, global_size, history, chooser = @parameters
      2 * (local + global_size + chooser) + history
    end
  end
end
