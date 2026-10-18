METHODS = %w[NEXTFIT FIRSTFIT BESTFIT WORSTFIT ALMOSTWORST HARMONIC KBOUNDED FFD BFD WFD].freeze
Item = Struct.new(:id, :size)
Bin = Struct.new(:load, :items, :klass)
Rectangle = Struct.new(:id, :w, :h)
Placement = Struct.new(:id, :w, :h, :x, :y, :rotated)
FreeRect = Struct.new(:x, :y, :w, :h)
class CommandError < StandardError; end

def total(items)
  items.sum(&:size)
end

def descending(items)
  items.sort_by { |i| [-i.size, i.id] }
end

def notation(item)
  "#{item.id}:#{item.size}"
end

def letter(id)
  (64 + id).chr
end

def ceil(a, b)
  (a + b - 1) / b
end

def copy_bins(bins)
  bins.map { |b| Bin.new(b.load, b.items.dup, b.klass) }
end

def pack(items, capacity, method, k = 0)
  bins = []
  steps = []
  current = {}
  active = []
  inspections = 0
  closes = 0
  order = %w[FFD BFD WFD].include?(method) ? descending(items) : items
  order.each do |item|
    before = inspections
    destination = nil
    closed = nil
    klass = nil
    if method == 'NEXTFIT'
      unless bins.empty?
        inspections += 1
        destination = bins.length - 1 if bins.last.load + item.size <= capacity
      end
    elsif method == 'HARMONIC'
      klass = [capacity / item.size, k].min
      index = current[klass]
      unless index.nil?
        inspections += 1
        destination = index if bins[index].load + item.size <= capacity
      end
    elsif %w[FIRSTFIT FFD KBOUNDED].include?(method)
      candidates = method == 'KBOUNDED' ? active : bins.each_index.to_a
      candidates.each do |index|
        inspections += 1
        if bins[index].load + item.size <= capacity
          destination = index
          break
        end
      end
    else
      inspections += bins.length
      candidates = bins.each_index.select { |i| bins[i].load + item.size <= capacity }
      largest = %w[BESTFIT BFD].include?(method)
      candidates.sort_by! { |i| [largest ? -bins[i].load : bins[i].load, i] }
      destination = candidates[method == 'ALMOSTWORST' && candidates.length > 1 ? 1 : 0]
    end
    fresh = destination.nil?
    if fresh
      if method == 'KBOUNDED' && active.length == k
        index = active.min_by { |i| [-bins[i].load, i] }
        active.delete(index)
        closed = index + 1
        closes += 1
      end
      destination = bins.length
      bins << Bin.new(0, [], klass)
      current[klass] = destination if method == 'HARMONIC'
      active << destination if method == 'KBOUNDED'
    end
    bins[destination].items << item
    bins[destination].load += item.size
    steps << {item: item, bin: destination + 1, inspected: inspections - before,
              fresh: fresh, closed: closed, klass: klass}
  end
  {bins: bins, steps: steps, inspections: inspections, closes: closes}
end

def bounds(items, capacity)
  thresholds = [0, *items.select { |i| 2 * i.size <= capacity }.map(&:size)].uniq.sort
  rows = thresholds.map do |alpha|
    j1 = items.select { |i| i.size > capacity - alpha }
    j2 = items.select { |i| 2 * i.size > capacity && i.size <= capacity - alpha }
    j3 = items.select { |i| 2 * i.size <= capacity && i.size >= alpha }
    extra = total(j3) - (j2.length * capacity - total(j2))
    [alpha, j1.length, j2.length, j3.length, j1.length + j2.length + (extra.positive? ? ceil(extra, capacity) : 0)]
  end
  [ceil(total(items), capacity), rows.map(&:last).max, rows]
end

class Lab
  attr_reader :output

  def initialize
    @capacity = nil
    @items = []
    @output = []
  end

  def emit(*parts)
    @output << parts.join(' ')
  end

  def bin_line(bin, number, capacity, harmonic = false, over = false)
    parts = ['BIN', number, "load=#{bin.load}/#{capacity}", 'items=' + bin.items.map { |i| notation(i) }.join(' ')]
    parts << "class=#{bin.klass}" if harmonic
    parts << 'OVER' if over
    emit(*parts)
  end

  def header(method, k, result)
    parameter = %w[HARMONIC KBOUNDED].include?(method) ? " k=#{k}" : ''
    method + parameter + " bins=#{result[:bins].length} inspections=#{result[:inspections]}" +
      " waste=#{result[:bins].length * @capacity - total(@items)}" + (method == 'KBOUNDED' ? " closes=#{result[:closes]}" : '')
  end

  def reduce(method, k)
    bins = pack(@items, @capacity, method, k)[:bins]
    before = bins.length
    eliminations = []
    loop do
      succeeded = false
      bins.each_index.sort_by { |i| [bins[i].load, i] }.each do |source|
        loads = bins.map(&:load)
        moves = []
        possible = true
        descending(bins[source].items).each do |item|
          candidates = bins.each_index.select { |i| i != source && loads[i] + item.size <= @capacity }
          destination = candidates.min_by { |i| [-loads[i], i] }
          if destination.nil?
            possible = false
            break
          end
          loads[destination] += item.size
          moves << [item, destination]
        end
        next unless possible
        text = moves.map { |item, destination| "#{notation(item)}->#{destination + 1}" }.join(' ')
        eliminations << "ELIMINATE bin=#{source + 1} load=#{bins[source].load} moves=#{text}"
        moves.each do |item, destination|
          bins[destination].items << item
          bins[destination].load += item.size
        end
        bins.delete_at(source)
        succeeded = true
        break
      end
      break unless succeeded
    end
    emit('REDUCE', method, *(%w[HARMONIC KBOUNDED].include?(method) ? ["k=#{k}"] : []),
         "before=#{before}", "after=#{bins.length}", "eliminated=#{before - bins.length}")
    eliminations.each { |line| emit(line) }
    bins.each_with_index { |b, i| bin_line(b, i + 1, @capacity, method == 'HARMONIC') }
  end

  def exact(limit)
    raise CommandError, 'BAD PARAMETER' if limit.zero?
    raise CommandError, 'TOO MANY ITEMS' if @items.length > 20
    lower = bounds(@items, @capacity)[1]
    best = copy_bins(pack(@items, @capacity, 'FFD')[:bins])
    emit('EXACT', "ffd=#{best.length}", "L2=#{lower}")
    order = descending(@items)
    remaining = Array.new(order.length + 1, 0)
    (order.length - 1).downto(0) { |i| remaining[i] = remaining[i + 1] + order[i].size }
    bins = []
    nodes = 0
    status = best.length == lower ? 'bound' : 'complete'
    stopped = status == 'bound'
    visit = lambda do |index, used|
      if nodes == limit
        status = 'limit'
        stopped = true
        next
      end
      nodes += 1
      free = bins.length * @capacity - used
      extra = remaining[index] - free
      bound = bins.length + (extra.positive? ? ceil(extra, @capacity) : 0)
      next if bound >= best.length
      if index == order.length
        best = copy_bins(bins)
        emit('IMPROVE', "bins=#{best.length}", "nodes=#{nodes}")
        if best.length == lower
          status = 'bound'
          stopped = true
        end
        next
      end
      item = order[index]
      seen = {}
      bins.each do |bin|
        next if seen.key?(bin.load)
        seen[bin.load] = true
        next if bin.load + item.size > @capacity
        bin.load += item.size
        bin.items << item
        visit.call(index + 1, used + item.size)
        bin.items.pop
        bin.load -= item.size
        break if stopped
      end
      next if stopped
      if bins.length + 1 < best.length
        bins << Bin.new(item.size, [item], nil)
        visit.call(index + 1, used + item.size)
        bins.pop
      end
    end
    visit.call(0, 0) unless stopped
    emit('RESULT', "bins=#{best.length}", "nodes=#{nodes}", "status=#{status}")
    best.each_with_index { |b, i| bin_line(b, i + 1, @capacity) }
  end

  def cover
    emit('COVER', "total=#{total(@items)}", "upper=#{total(@items) / @capacity}")
    %w[DNF BIGSMALL].each do |method|
      remaining = method == 'DNF' ? @items.dup : descending(@items)
      bins = []
      until remaining.empty?
        first = remaining.shift
        bin = Bin.new(first.size, [first], nil)
        while bin.load < @capacity && !remaining.empty?
          item = method == 'DNF' ? remaining.shift : remaining.pop
          bin.items << item
          bin.load += item.size
        end
        bins << bin
      end
      covered = bins.select { |b| b.load >= @capacity }
      rest = bins.find { |b| b.load < @capacity }
      emit(method, "covered=#{covered.length}", "rest=#{rest ? rest.load : 0}")
      covered.each_with_index { |b, i| bin_line(b, i + 1, @capacity) }
      emit('REST', 'items=' + rest.items.map { |i| notation(i) }.join(' ')) if rest
    end
  end

  def machines(bins, count)
    count.times do |i|
      bin = bins[i]
      items = bin && !bin.items.empty? ? bin.items.map { |item| notation(item) }.join(' ') : '-'
      emit('MACHINE', i + 1, "load=#{bin ? bin.load : 0}", "items=#{items}")
    end
  end

  def multifit(count)
    raise CommandError, 'BAD PARAMETER' if count.zero?
    size = total(@items)
    largest = @items.map(&:size).max
    lo = [ceil(size, count), largest].max
    hi = [ceil(2 * size, count), largest].max
    emit('MULTIFIT', "m=#{count}", "lower=#{lo}", "upper=#{hi}")
    while lo < hi
      mid = (lo + hi) / 2
      bins = pack(@items, mid, 'FFD')[:bins]
      ok = bins.length <= count
      emit('TRY', "cap=#{mid}", "bins=#{bins.length}", ok ? 'ok' : 'fail')
      if ok
        hi = mid
      else
        lo = mid + 1
      end
    end
    bins = pack(@items, hi, 'FFD')[:bins]
    emit('RESULT', "cap=#{hi}", "makespan=#{bins.map(&:load).max}")
    machines(bins, count)
    lpt = Array.new(count) { Bin.new(0, [], nil) }
    descending(@items).each do |item|
      chosen = lpt.each_index.min_by { |i| [lpt[i].load, i] }
      lpt[chosen].items << item
      lpt[chosen].load += item.size
    end
    emit('LPT', "makespan=#{lpt.map(&:load).max}")
    machines(lpt, count)
  end

  def cutstock(capacity, tokens)
    raise CommandError, 'BAD CAPACITY' if capacity.zero?
    pieces = tokens.map { |t| t.split(':').map(&:to_i) }
    seen = {}
    pieces.each_with_index do |(length, demand), i|
      raise CommandError, "BAD PIECE #{i + 1}" if length.zero? || length > capacity || demand.zero?
      raise CommandError, "DUPLICATE PIECE #{i + 1}" if seen.key?(length)
      seen[length] = true
    end
    pieces.sort_by! { |length, _| -length }
    patterns = []
    enumerate = lambda do |index, rest, prefix|
      maximum = rest / pieces[index][0]
      if index == pieces.length - 1
        patterns << [*prefix, maximum]
      else
        maximum.downto(0) do |count|
          enumerate.call(index + 1, rest - count * pieces[index][0], [*prefix, count])
        end
      end
    end
    enumerate.call(0, capacity, [])
    remaining = pieces.map(&:last)
    used = Array.new(patterns.length, 0)
    while remaining.any?(&:positive?)
      chosen = patterns.each_index.max_by do |p|
        [patterns[p].each_with_index.sum { |a, i| [a, remaining[i]].min }, -p]
      end
      used[chosen] += 1
      pieces.each_index { |i| remaining[i] = [0, remaining[i] - patterns[chosen][i]].max }
    end
    trims = patterns.map { |p| capacity - p.each_with_index.sum { |a, i| a * pieces[i][0] } }
    cut = pieces.each_index.map { |i| patterns.each_with_index.sum { |p, j| p[i] * used[j] } }
    bars = used.sum
    size = pieces.sum { |length, demand| length * demand }
    emit('CUTSTOCK', "L=#{capacity}", "pieces=#{pieces.length}", "patterns=#{patterns.length}")
    patterns.each_with_index do |p, i|
      breakdown = p.each_with_index.filter_map { |a, j| "#{a}x#{pieces[j][0]}" if a.positive? }.join('+')
      emit('PATTERN', i + 1, breakdown, "rest=#{trims[i]}")
    end
    used.each_with_index { |n, i| emit('USE', i + 1, "bars=#{n}") if n.positive? }
    pieces.each_with_index { |(length, demand), i| emit('PIECE', length, "demand=#{demand}", "cut=#{cut[i]}") }
    emit('TOTAL', "bars=#{bars}", "trim=#{used.each_with_index.sum { |n, i| n * trims[i] }}",
         "surplus=#{cut.each_with_index.sum { |n, i| n - pieces[i][1] }}", "waste=#{bars * capacity - size}")
    items = []
    pieces.each { |length, demand| demand.times { items << Item.new(items.length + 1, length) } }
    ffd = pack(items, capacity, 'FIRSTFIT')[:bins].length
    emit('FFD', "bars=#{ffd}", "waste=#{ffd * capacity - size}")
    emit('LOWER', "bars=#{ceil(size, capacity)}")
  end

  def drawing(width, height, placements)
    cells = Array.new(height) { Array.new(width, '.') }
    placements.each do |p|
      (p.y...(p.y + p.h)).each do |y|
        cells[y].fill(letter(p.id), p.x, p.w)
      end
    end
    (height - 1).downto(0) { |y| emit(cells[y].join) }
  end

  def rectangles(tokens)
    tokens.each_with_index.map do |t, i|
      w, h = t.split('x').map(&:to_i)
      Rectangle.new(i + 1, w, h)
    end
  end

  def shelf(width, tokens)
    raise CommandError, 'BAD CAPACITY' if width.zero?
    rectangles = rectangles(tokens)
    rectangles.each do |r|
      raise CommandError, "BAD RECT #{r.id}" if r.w.zero? || r.h.zero? || r.w > width
    end
    order = rectangles.sort_by { |r| [-r.h, -r.w, r.id] }
    area = rectangles.sum { |r| r.w * r.h }
    emit('SHELF', "W=#{width}", "rects=#{rectangles.length}", "area=#{area}")
    %w[NFDH FFDH BFDH].each do |method|
      shelves = []
      order.each do |r|
        candidates = shelves.each_index.select { |i| shelves[i][:used] + r.w <= width }
        candidates.select! { |i| i == shelves.length - 1 } if method == 'NFDH'
        candidates.sort_by! { |i| [-shelves[i][:used], i] } if method == 'BFDH'
        index = candidates.first
        if index.nil?
          index = shelves.length
          last = shelves.last
          shelves << {y: last ? last[:y] + last[:h] : 0, h: r.h, used: 0, placements: []}
        end
        s = shelves[index]
        s[:placements] << Placement.new(r.id, r.w, r.h, s[:used], s[:y], false)
        s[:used] += r.w
      end
      height = shelves.last[:y] + shelves.last[:h]
      emit(method, "height=#{height}", "shelves=#{shelves.length}", "util=#{area * 100 / (width * height)}")
      shelves.each_with_index do |s, i|
        items = s[:placements].map { |p| "#{letter(p.id)}@#{p.x}" }.join(' ')
        emit('LEVEL', i + 1, "y=#{s[:y]}", "h=#{s[:h]}", "used=#{s[:used]}", "items=#{items}")
      end
      drawing(width, height, shelves.flat_map { |s| s[:placements] })
    end
    heights = Array.new(width, 0)
    placements = []
    order.each do |r|
      x = (0..(width - r.w)).min_by { |candidate| [heights[candidate, r.w].max, candidate] }
      y = heights[x, r.w].max
      placements << Placement.new(r.id, r.w, r.h, x, y, false)
      heights.fill(y + r.h, x, r.w)
    end
    height = heights.max
    emit('SKYLINE', "height=#{height}", "util=#{area * 100 / (width * height)}")
    placements.each { |p| emit('PLACE', letter(p.id), "x=#{p.x}", "y=#{p.y}", "w=#{p.w}", "h=#{p.h}") }
    drawing(width, height, placements)
  end

  def guillotine(width, height, mode, rule, tokens)
    raise CommandError, 'BAD CAPACITY' if width.zero? || height.zero?
    rectangles = rectangles(tokens)
    fits = ->(r, f) { (r.w <= f.w && r.h <= f.h) || (mode == 'ROTATE' && r.h <= f.w && r.w <= f.h) }
    rectangles.each do |r|
      raise CommandError, "BAD RECT #{r.id}" if r.w.zero? || r.h.zero? || !fits.call(r, FreeRect.new(0, 0, width, height))
    end
    sheets = []
    rotated_count = 0
    rectangles.sort_by { |r| [-r.w * r.h, r.id] }.each do |r|
      chosen_sheet = nil
      chosen_free = nil
      best_area = nil
      sheets.each_with_index do |sheet, i|
        sheet[:free].each_with_index do |f, j|
          next unless fits.call(r, f)
          if chosen_sheet.nil? || (rule == 'BEST' && f.w * f.h < best_area)
            chosen_sheet = i
            chosen_free = j
            best_area = f.w * f.h
          end
        end
      end
      if chosen_sheet.nil?
        chosen_sheet = sheets.length
        chosen_free = 0
        sheets << {free: [FreeRect.new(0, 0, width, height)], placements: []}
      end
      sheet = sheets[chosen_sheet]
      f = sheet[:free].delete_at(chosen_free)
      rotated = !(r.w <= f.w && r.h <= f.h)
      w, h = rotated ? [r.h, r.w] : [r.w, r.h]
      rotated_count += 1 if rotated
      sheet[:placements] << Placement.new(r.id, w, h, f.x, f.y, rotated)
      rw = f.w - w
      rh = f.h - h
      top = FreeRect.new(f.x, f.y + h, rw <= rh ? f.w : w, rh)
      right = FreeRect.new(f.x + w, f.y, rw, rw <= rh ? h : f.h)
      [top, right].each { |free| sheet[:free] << free if free.w.positive? && free.h.positive? }
    end
    area = rectangles.sum { |r| r.w * r.h }
    emit('GUILLOTINE', "W=#{width}", "H=#{height}", "mode=#{mode}", "rule=#{rule}", "rects=#{rectangles.length}",
         "sheets=#{sheets.length}", "rotated=#{rotated_count}", "util=#{area * 100 / (sheets.length * width * height)}")
    sheets.each_with_index do |sheet, i|
      emit('SHEET', i + 1, "placed=#{sheet[:placements].length}", "area=#{sheet[:placements].sum { |p| p.w * p.h }}")
      sheet[:placements].each do |p|
        emit('PLACE', letter(p.id), "x=#{p.x}", "y=#{p.y}", "w=#{p.w}", "h=#{p.h}", *(p.rotated ? ['rotated'] : []))
      end
      emit('FREE', *(sheet[:free].empty? ? ['none'] : sheet[:free].map { |f| "#{f.x},#{f.y},#{f.w}x#{f.h}" }))
      drawing(width, height, sheet[:placements])
    end
  end

  def command(cmd, a)
    if %w[ITEMS RANDOM].include?(cmd)
      if cmd == 'ITEMS'
        capacity = a[0].to_i
        raise CommandError, 'BAD CAPACITY' if capacity.zero?
        sizes = a.drop(1).map(&:to_i)
        bad = sizes.index { |s| s.zero? || s > capacity }
        raise CommandError, "BAD ITEM #{bad + 1}" if bad
      else
        count = a[0].to_i
        raise CommandError, 'BAD COUNT' if count.zero? || count > 40
        capacity = a[1].to_i
        raise CommandError, 'BAD CAPACITY' if capacity.zero?
        seed = a[2].to_i
        raise CommandError, 'BAD SEED' if seed.zero? || seed >= 2147483647
        sizes = Array.new(count) do
          seed = 48271 * seed % 2147483647
          seed % capacity + 1
        end
      end
      @capacity = capacity
      @items = sizes.each_with_index.map { |size, i| Item.new(i + 1, size) }
      emit(cmd, "count=#{sizes.length}", "capacity=#{capacity}", "total=#{total(@items)}")
      emit('SIZES', *sizes) if cmd == 'RANDOM'
      return
    end
    if cmd == 'CUTSTOCK'
      cutstock(a[0].to_i, a.drop(1))
      return
    end
    if cmd == 'SHELF'
      shelf(a[0].to_i, a.drop(1))
      return
    end
    if cmd == 'GUILLOTINE'
      guillotine(a[0].to_i, a[1].to_i, a[2], a[3], a.drop(4))
      return
    end
    raise CommandError, 'NO ITEMS' if @capacity.nil?
    if METHODS.include?(cmd) || %w[TRACE REDUCE].include?(cmd)
      specification = %w[TRACE REDUCE].include?(cmd)
      method = specification ? a[0] : cmd
      k = (a[specification ? 1 : 0] || '0').to_i
      raise CommandError, 'BAD PARAMETER' if %w[HARMONIC KBOUNDED].include?(method) && k.zero?
      if cmd == 'REDUCE'
        reduce(method, k)
        return
      end
      result = pack(@items, @capacity, method, k)
      emit((cmd == 'TRACE' ? 'TRACE ' : '') + header(method, k, result))
      if cmd == 'TRACE'
        result[:steps].each_with_index do |s, i|
          parts = ['STEP', i + 1, "item=#{notation(s[:item])}", "bin=#{s[:bin]}", "inspected=#{s[:inspected]}"]
          parts << 'new' if s[:fresh]
          parts << "closed=#{s[:closed]}" if s[:closed]
          parts << "class=#{s[:klass]}" if s[:klass]
          emit(*parts)
        end
      else
        result[:bins].each_with_index { |b, i| bin_line(b, i + 1, @capacity, method == 'HARMONIC') }
      end
    elsif cmd == 'BOUNDS'
      l1, l2, rows = bounds(@items, @capacity)
      emit('BOUNDS', "total=#{total(@items)}", "L1=#{l1}", "L2=#{l2}")
      rows.each { |alpha, j1, j2, j3, bound| emit('ALPHA', alpha, "j1=#{j1}", "j2=#{j2}", "j3=#{j3}", "bound=#{bound}") }
    elsif cmd == 'COMPARE'
      k = a[0].to_i
      raise CommandError, 'BAD PARAMETER' if k.zero?
      l1, l2, = bounds(@items, @capacity)
      emit('COMPARE', "k=#{k}", "L1=#{l1}", "L2=#{l2}")
      rows = METHODS.map { |method| [method, pack(@items, @capacity, method, k)] }
      rows.sort_by { |method, r| [r[:bins].length, method] }.each do |method, r|
        emit(method, "bins=#{r[:bins].length}", "gap=#{r[:bins].length - l2}",
             "waste=#{r[:bins].length * @capacity - total(@items)}", "inspections=#{r[:inspections]}")
      end
    elsif cmd == 'EXACT'
      exact(a[0].to_i)
    elsif cmd == 'CHECK'
      labels = a.map(&:to_i)
      raise CommandError, 'BAD ASSIGNMENT' if labels.length != @items.length || labels.any?(&:zero?)
      bins = {}
      @items.each_with_index do |item, i|
        bin = (bins[labels[i]] ||= Bin.new(0, [], nil))
        bin.load += item.size
        bin.items << item
      end
      over = bins.values.count { |b| b.load > @capacity }
      emit('CHECK', "bins=#{bins.length}", "over=#{over}", "L2=#{bounds(@items, @capacity)[1]}", "status=#{over.zero? ? 'valid' : 'invalid'}")
      bins.keys.sort.each { |label| bin_line(bins[label], label, @capacity, false, bins[label].load > @capacity) }
    elsif cmd == 'COVER'
      cover
    elsif cmd == 'MULTIFIT'
      multifit(a[0].to_i)
    end
  end

  def execute(line)
    cmd, *args = line.split
    begin
      command(cmd, args)
    rescue CommandError => error
      emit('ERROR', error.message)
    end
  end
end

lab = Lab.new
STDIN.gets.to_i.times { lab.execute(STDIN.gets.chomp) }
STDOUT.write(lab.output.join("\n") + "\n")
