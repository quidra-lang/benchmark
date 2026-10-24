Rectangle = Struct.new(:name, :layer, :x1, :y1, :x2, :y2) do
  def box
    [x1, y1, x2, y2]
  end

  def width
    x2 - x1
  end

  def height
    y2 - y1
  end
end

class LayoutError < StandardError; end

class CoverageGrid
  attr_reader :xs, :ys, :cells

  def initialize(rectangles)
    @xs = rectangles.flat_map { |r| [r.x1, r.x2] }.uniq.sort
    @ys = rectangles.flat_map { |r| [r.y1, r.y2] }.uniq.sort
    @cells = Array.new(@ys.length - 1) { Array.new(@xs.length - 1, 0) }
    rectangles.each do |r|
      (@ys.index(r.y1)...@ys.index(r.y2)).each do |j|
        (@xs.index(r.x1)...@xs.index(r.x2)).each { |i| @cells[j][i] += 1 }
      end
    end
  end

  def area(k = 1, window = nil)
    result = 0
    @cells.each_with_index do |row, j|
      row.each_with_index do |count, i|
        next if count < k
        if window
          dx = [[@xs[i + 1], window[2]].min - [@xs[i], window[0]].max, 0].max
          dy = [[@ys[j + 1], window[3]].min - [@ys[j], window[1]].max, 0].max
          result += dx * dy
        else
          result += (@xs[i + 1] - @xs[i]) * (@ys[j + 1] - @ys[j])
        end
      end
    end
    result
  end

  def perimeter
    result = 0
    @cells.each_with_index do |row, j|
      row.each_with_index do |count, i|
        next if count.zero?
        dy = @ys[j + 1] - @ys[j]
        dx = @xs[i + 1] - @xs[i]
        result += dy if i.zero? || row[i - 1].zero?
        result += dy if i + 1 == row.length || row[i + 1].zero?
        result += dx if j.zero? || @cells[j - 1][i].zero?
        result += dx if j + 1 == @cells.length || @cells[j + 1][i].zero?
      end
    end
    result
  end

  def largest_empty
    best = nil
    (0...(@xs.length - 1)).each do |left|
      blocked = Array.new(@ys.length - 1, false)
      (left...(@xs.length - 1)).each do |right|
        blocked.each_index { |j| blocked[j] ||= @cells[j][right].positive? }
        j = 0
        while j < blocked.length
          if blocked[j]
            j += 1
            next
          end
          start = j
          j += 1 while j < blocked.length && !blocked[j]
          width = @xs[right + 1] - @xs[left]
          area = width * (@ys[j] - @ys[start])
          choice = [-area, @xs[left], @ys[start], width, @xs[right + 1], @ys[j]]
          best = choice if best.nil? || (choice <=> best).negative?
        end
      end
    end
    best ? [[best[1], best[2], best[4], best[5]], -best[0]] : nil
  end

  def holes
    visited = {}
    result = []
    @cells.each_index do |j|
      @cells[j].each_index do |i|
        next if @cells[j][i].positive? || visited[[i, j]]
        queue = [[i, j]]
        visited[[i, j]] = true
        head = 0
        area = 0
        boundary = false
        x1 = x2 = @xs[i]
        y1 = y2 = @ys[j]
        anchor = [@ys[j], @xs[i]]
        while head < queue.length
          x, y = queue[head]
          head += 1
          area += (@xs[x + 1] - @xs[x]) * (@ys[y + 1] - @ys[y])
          x1 = [x1, @xs[x]].min
          x2 = [x2, @xs[x + 1]].max
          y1 = [y1, @ys[y]].min
          y2 = [y2, @ys[y + 1]].max
          point = [@ys[y], @xs[x]]
          anchor = point if (point <=> anchor).negative?
          boundary ||= x.zero? || y.zero? || x + 1 == @xs.length - 1 || y + 1 == @ys.length - 1
          [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]].each do |a, b|
            next if a.negative? || b.negative? || a >= @xs.length - 1 || b >= @ys.length - 1 || @cells[b][a].positive? || visited[[a, b]]
            visited[[a, b]] = true
            queue << [a, b]
          end
        end
        result << [anchor, area, [x1, y1, x2, y2]] unless boundary
      end
    end
    result.sort_by(&:first)
  end

  def pieces
    active = {}
    result = []
    @cells.each_with_index do |row, j|
      current = {}
      i = 0
      while i < row.length
        if row[i].zero?
          i += 1
          next
        end
        start = i
        i += 1 while i < row.length && row[i].positive?
        run = [@xs[start], @xs[i]]
        current[run] = active.key?(run) ? active.delete(run) : @ys[j]
      end
      active.each { |(left, right), bottom| result << [left, bottom, right, @ys[j]] }
      active = current
    end
    active.each { |(left, right), bottom| result << [left, bottom, right, @ys.last] }
    result.sort_by { |r| [r[1], r[0]] }
  end
end

class RectangleWorkbench
  def initialize
    @rectangles = {}
    @rules = {}
    @history = []
  end

  def notation(box)
    "(#{box[0]},#{box[1]})-(#{box[2]},#{box[3]})"
  end

  def point(x, y)
    "(#{x},#{y})"
  end

  def percent(area, denominator)
    value = 10_000 * area / denominator
    format('%d.%02d', value / 100, value % 100)
  end

  def sorted
    @rectangles.keys.sort.map { |name| @rectangles[name] }
  end

  def on_layer(layer)
    sorted.select { |r| r.layer == layer }
  end

  def require_layer(layer)
    rectangles = on_layer(layer)
    raise LayoutError, "no rectangles on #{layer}" if rectangles.empty?
    rectangles
  end

  def rectangle(name)
    @rectangles[name] || (raise LayoutError, "unknown rectangle #{name}")
  end

  def bounds(box)
    raise LayoutError, 'out of bounds' if box.any? { |coordinate| coordinate.abs > 10_000 }
  end

  def remember(line)
    @history << [@rectangles.transform_values(&:dup), line]
  end

  def relation(a, b)
    box = [[a.x1, b.x1].max, [a.y1, b.y1].max, [a.x2, b.x2].min, [a.y2, b.y2].min]
    ox = box[2] - box[0]
    oy = box[3] - box[1]
    kind = ox.negative? || oy.negative? ? :separated : ox.zero? && oy.zero? ? :corner : ox.zero? || oy.zero? ? :edge : :overlap
    direction = ox.negative? && oy.negative? ? 'diagonal' : ox.negative? ? 'x' : 'y'
    [kind, box, ox, oy, [0, -ox, -oy].max, direction]
  end

  def contains(a, b)
    a.x1 <= b.x1 && a.y1 <= b.y1 && a.x2 >= b.x2 && a.y2 >= b.y2
  end

  def connected(a, b)
    %i[overlap edge].include?(relation(a, b)[0])
  end

  def nets(rectangles)
    remaining = rectangles.dup
    result = []
    until remaining.empty?
      group = [remaining.shift]
      i = 0
      while i < group.length
        neighbors = remaining.select { |r| connected(group[i], r) }
        group.concat(neighbors)
        remaining -= neighbors
        i += 1
      end
      result << group.sort_by(&:name)
    end
    result
  end

  def spacing(rectangles, minimum)
    rectangles.combination(2).filter_map do |a, b|
      kind, _, _, _, gap, direction = relation(a, b)
      [gap, a.name, b.name, kind == :corner ? 'corner' : direction] if kind == :corner || (kind == :separated && gap < minimum)
    end.sort
  end

  def spacing_lines(violations)
    violations.each { |gap, a, b, direction| puts "#{a} #{b} gap #{gap} #{direction}" }
  end

  def bounding(rectangles)
    [rectangles.map(&:x1).min, rectangles.map(&:y1).min, rectangles.map(&:x2).max, rectangles.map(&:y2).max]
  end

  def execute(line)
    command, *args = line.split(' ')
    case command
    when 'ADD'
      name, layer = args.take(2)
      raise LayoutError, "duplicate rectangle #{name}" if @rectangles.key?(name)
      x1, y1, x2, y2 = args.drop(2).map(&:to_i)
      raise LayoutError, 'invalid rectangle' if x1 >= x2 || y1 >= y2
      bounds([x1, y1, x2, y2])
      remember(line)
      @rectangles[name] = Rectangle.new(name, layer, x1, y1, x2, y2)
      puts "added #{name} #{layer} #{notation([x1, y1, x2, y2])}"
    when 'COPY', 'MOVE', 'RESIZE', 'SPLIT', 'LAYER', 'DELETE'
      name = args[0]
      original = rectangle(name)
      changed = original.dup
      case command
      when 'COPY', 'MOVE'
        new_name = command == 'COPY' ? args[1] : name
        raise LayoutError, "duplicate rectangle #{new_name}" if command == 'COPY' && @rectangles.key?(new_name)
        dx, dy = args.drop(command == 'COPY' ? 2 : 1).map(&:to_i)
        changed.name = new_name
        changed.x1 += dx
        changed.x2 += dx
        changed.y1 += dy
        changed.y2 += dy
        bounds(changed.box)
        message = command == 'COPY' ? "copied #{name} to #{new_name} #{notation(changed.box)}" : "moved #{name} to #{notation(changed.box)}"
      when 'RESIZE'
        width, height = args.drop(1).map(&:to_i)
        raise LayoutError, 'invalid size' if width <= 0 || height <= 0
        changed.x2 = changed.x1 + width
        changed.y2 = changed.y1 + height
        bounds(changed.box)
        message = "resized #{name} to #{notation(changed.box)}"
      when 'SPLIT'
        axis, position, new_name = args.drop(1)
        position = position.to_i
        raise LayoutError, "duplicate rectangle #{new_name}" if @rectangles.key?(new_name)
        valid = axis == 'x' ? original.x1 < position && position < original.x2 : original.y1 < position && position < original.y2
        raise LayoutError, "cut outside #{name}" unless valid
        added = original.dup
        added.name = new_name
        if axis == 'x'
          changed.x2 = added.x1 = position
        else
          changed.y2 = added.y1 = position
        end
        message = "split #{name} at #{axis}=#{position}: #{name} #{notation(changed.box)}, #{new_name} #{notation(added.box)}"
      when 'LAYER'
        raise LayoutError, "already on #{args[1]}" if original.layer == args[1]
        changed.layer = args[1]
        message = "layer #{name} #{original.layer} -> #{changed.layer}"
      when 'DELETE'
        message = "deleted #{name}"
      end
      remember(line)
      if command == 'DELETE'
        @rectangles.delete(name)
      else
        @rectangles[changed.name] = changed
        @rectangles[added.name] = added if command == 'SPLIT'
      end
      puts message
    when 'UNDO'
      raise LayoutError, 'nothing to undo' if @history.empty?
      @rectangles, previous = @history.pop
      puts "undo: #{previous}"
    when 'LIST'
      puts "rectangles: #{@rectangles.length}"
      sorted.each { |r| puts "#{r.name} #{r.layer} #{notation(r.box)} #{r.width}x#{r.height}" }
    when 'INFO'
      a = rectangle(args[0])
      puts "#{a.name} #{a.layer} #{notation(a.box)} #{a.width}x#{a.height} area #{a.width * a.height}"
      others = sorted.reject { |r| r.name == a.name }
      %w[overlaps touches corners encloses enclosed\ by].each_with_index do |label, i|
        matches = others.select do |b|
          i < 3 ? b.layer == a.layer && relation(a, b)[0] == %i[overlap edge corner][i] : i == 3 ? contains(a, b) : contains(b, a)
        end.map(&:name)
        puts "#{label}: #{matches.empty? ? 'none' : matches.join(' ')}"
      end
    when 'LAYERS'
      layers = sorted.map(&:layer).uniq.sort
      puts "layers: #{layers.length}"
      layers.each do |layer|
        rectangles = on_layer(layer)
        puts "#{layer}: #{rectangles.length} rectangles, area #{CoverageGrid.new(rectangles).area}, nets #{nets(rectangles).length}"
      end
    when 'OVERLAPS'
      rectangles = args.empty? ? sorted : require_layer(args[0])
      pairs = rectangles.combination(2).filter_map do |a, b|
        kind, box, ox, oy = relation(a, b)
        [a.layer, a.name, b.name, box, ox * oy] if a.layer == b.layer && kind == :overlap
      end.sort_by { |p| p.take(3) }
      puts "overlaps #{args.empty? ? 'all layers' : args[0]}: #{pairs.length}"
      pairs.each { |layer, a, b, box, area| puts "#{args.empty? ? layer + ' ' : ''}#{a} #{b} #{notation(box)} area #{area}" }
    when 'AREA', 'COVER', 'PERIMETER', 'BBOX', 'DENSITY', 'RENDER', 'EMPTY', 'HOLES', 'MERGE', 'NETS', 'DRC'
      layer = command == 'COVER' ? args[1] : args[0]
      rectangles = require_layer(layer)
      grid = CoverageGrid.new(rectangles)
      box = bounding(rectangles)
      case command
      when 'AREA'
        puts "area #{layer}: #{grid.area}"
      when 'COVER'
        puts "cover #{layer} >= #{args[0]}: #{grid.area(args[0].to_i)}"
      when 'PERIMETER'
        puts "perimeter #{layer}: #{grid.perimeter}"
      when 'BBOX'
        width, height = box[2] - box[0], box[3] - box[1]
        puts "bbox #{layer}: #{notation(box)} #{width}x#{height}, #{rectangles.length} rectangles, density #{percent(grid.area, width * height)}%"
      when 'DENSITY'
        width = args[1].to_i
        columns = (box[2] - box[0] + width - 1) / width
        rows = (box[3] - box[1] + width - 1) / width
        raise LayoutError, 'too many windows' if columns > 20 || rows > 20
        values = Array.new(rows) { |j| Array.new(columns) { |i| grid.area(1, [box[0] + i * width, box[1] + j * width, box[0] + (i + 1) * width, box[1] + (j + 1) * width]) } }
        puts "density #{layer} window #{width}: #{columns}x#{rows}"
        values.reverse_each { |row| puts row.map { |area| 100 * area / (width * width) }.join(' ') }
        minimum = values.flatten.min
        maximum = values.flatten.max
        [['min', minimum], ['max', maximum]].each do |label, value|
          index = values.flatten.index(value)
          puts "#{label} #{percent(value, width * width)}% at #{point(box[0] + index % columns * width, box[1] + index / columns * width)}"
        end
      when 'RENDER'
        x1, y1, x2, y2 = args.drop(1).map(&:to_i)
        raise LayoutError, 'invalid window' if x1 >= x2 || y1 >= y2
        raise LayoutError, 'window too large' if x2 - x1 > 60 || y2 - y1 > 40
        puts "render #{layer} #{notation([x1, y1, x2, y2])}"
        (y1...y2).to_a.reverse_each do |y|
          row = (x1...x2).map do |x|
            count = rectangles.count { |r| r.x1 <= x && x < r.x2 && r.y1 <= y && y < r.y2 }
            count.zero? ? '.' : count >= 10 ? '*' : count.to_s
          end
          puts row.join
        end
      when 'EMPTY'
        empty = grid.largest_empty
        puts "empty #{layer}: #{empty ? notation(empty[0]) + ' area ' + empty[1].to_s : 'none'}"
      when 'HOLES'
        holes = grid.holes
        puts "holes #{layer}: #{holes.length}"
        holes.each_with_index { |(_, area, bounds), i| puts "hole #{i + 1}: area #{area}, bbox #{notation(bounds)}" }
      when 'MERGE'
        pieces = grid.pieces
        puts "merge #{layer}: #{pieces.length} pieces"
        pieces.each { |r| puts notation(r) }
      when 'NETS'
        groups = nets(rectangles)
        puts "nets #{layer}: #{groups.length}"
        groups.each_with_index { |group, i| puts "net #{i + 1}: #{group.map(&:name).join(' ')} area #{CoverageGrid.new(group).area}" }
      when 'DRC'
        violations = spacing(rectangles, args[1].to_i)
        puts "drc #{layer} spacing #{args[1]}: #{violations.length} violations"
        spacing_lines(violations)
      end
    when 'INTERSECT', 'ADJACENT', 'ENCLOSE', 'PATH'
      a, b = rectangle(args[0]), rectangle(args[1])
      raise LayoutError, "same rectangle #{a.name}" if a.name == b.name
      kind, box, ox, oy, gap = relation(a, b)
      prefix = "#{command.downcase} #{a.name} #{b.name}: "
      if command == 'ENCLOSE'
        margins = [b.x1 - a.x1, b.y1 - a.y1, a.x2 - b.x2, a.y2 - b.y2]
        puts prefix + (margins.min >= 0 ? 'yes, ' : 'no, ') + "margins left #{margins[0]} bottom #{margins[1]} right #{margins[2]} top #{margins[3]}" + (margins.min >= 0 ? ", min #{margins.min}" : '')
      elsif command == 'PATH'
        raise LayoutError, 'different layers' if a.layer != b.layer
        queue = [[a.name]]
        seen = { a.name => true }
        path = nil
        until queue.empty?
          route = queue.shift
          if route.last == b.name
            path = route
            break
          end
          on_layer(a.layer).each do |r|
            next if seen[r.name] || !connected(@rectangles[route.last], r)
            seen[r.name] = true
            queue << route + [r.name]
          end
        end
        puts prefix + (path ? path.join(' -> ') + " (#{path.length - 1} steps)" : 'none')
      elsif command == 'INTERSECT'
        result = case kind
                 when :overlap then "#{notation(box)} area #{ox * oy}"
                 when :edge then "segment #{notation(box)} length #{ox + oy}"
                 when :corner then "point #{point(box[0], box[1])}"
                 else "none, gap #{gap}"
                 end
        puts prefix + result
      else
        if kind == :edge
          direction = ox.zero? ? (a.x2 == box[0] ? 'west' : 'east') : (a.y2 == box[1] ? 'south' : 'north')
          result = "#{a.name} is #{direction} of #{b.name}, edge #{notation(box)}, length #{ox + oy}"
        else
          result = kind == :overlap ? 'overlapping' : kind == :corner ? "corner only at #{point(box[0], box[1])}" : 'not adjacent'
        end
        puts prefix + result
      end
    when 'AT'
      x, y = args.map(&:to_i)
      found = sorted.select { |r| r.x1 <= x && x <= r.x2 && r.y1 <= y && y <= r.y2 }.map do |r|
        horizontal = x == r.x1 || x == r.x2
        vertical = y == r.y1 || y == r.y2
        "#{r.name} #{r.layer} #{horizontal && vertical ? 'corner' : horizontal || vertical ? 'edge' : 'inside'}"
      end
      puts "at #{point(x, y)}: #{found.empty? ? 'none' : found.join(', ')}"
    when 'NEAREST'
      a = rectangle(args[0])
      nearest = on_layer(a.layer).reject { |r| r.name == a.name }.map { |r| [relation(a, r)[4], r.name] }.min
      puts "nearest #{a.name}: #{nearest ? nearest[1] + ' gap ' + nearest[0].to_s : 'none'}"
    when 'RULE'
      kind = args[0].downcase
      if kind == 'enclose'
        raise LayoutError, "same layer #{args[1]}" if args[1] == args[2]
        @rules[[kind, args[1], args[2]]] = args[3].to_i
      else
        @rules[[kind, args[1]]] = args[2].to_i
      end
      puts 'rule ' + args.join(' ').sub(args[0], kind)
    when 'CHECK'
      raise LayoutError, 'no rules' if @rules.empty?
      total = 0
      @rules.keys.sort.each do |key|
        kind, layer, outer = key
        value = @rules[key]
        rectangles = on_layer(layer)
        if kind == 'spacing'
          violations = spacing(rectangles, value)
          puts "spacing #{layer} #{value}: #{violations.length} violations"
          spacing_lines(violations)
        elsif kind == 'width'
          violations = rectangles.select { |r| [r.width, r.height].min < value }
          puts "width #{layer} #{value}: #{violations.length} violations"
          violations.each { |r| puts "#{r.name} width #{[r.width, r.height].min}" }
        else
          enclosures = on_layer(outer)
          violations = rectangles.filter_map do |r|
            best = enclosures.map { |u| [r.x1 - u.x1, r.y1 - u.y1, u.x2 - r.x2, u.y2 - r.y2].min }.max
            [r.name, best] if best.nil? || best < value
          end
          puts "enclose #{layer} #{outer} #{value}: #{violations.length} violations"
          violations.each { |name, best| puts "#{name} best margin #{best.nil? ? 'none' : best}" }
        end
        total += violations.length
      end
      puts "check: #{total} violations in #{@rules.length} rules"
    end
  rescue LayoutError => error
    puts "error: #{error.message}"
  end
end

workbench = RectangleWorkbench.new
STDIN.gets.to_i.times { workbench.execute(STDIN.gets.chomp) }
