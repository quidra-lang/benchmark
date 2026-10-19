INTEGER_WORD = /\A(?:0|-?[1-9][0-9]{0,6})\z/
NAME_WORD = /\A[a-z]{1,8}\z/
DIGITS = /\A[0-9]+\z/
SHADES = "@#*+=~-:,."
ADJACENT4 = [[0, -1], [-1, 0], [1, 0], [0, 1]].freeze
ADJACENT8 = (-1..1).flat_map { |dy| (-1..1).map { |dx| [dx, dy] } }
                   .reject { |dx, dy| dx == 0 && dy == 0 }.freeze
KERNELS = {
  "BLUR" => [[1, 1, 1, 1, 1, 1, 1, 1, 1], 9],
  "GAUSS" => [[1, 2, 1, 2, 4, 2, 1, 2, 1], 16],
  "SHARPEN" => [[0, -1, 0, -1, 5, -1, 0, -1, 0], 1]
}.freeze
PATTERNS = {
  "NEW" => "iiii", "OUTPUT" => "", "INVERT" => "", "BRIGHTNESS" => "i",
  "CONTRAST" => "ii", "THRESHOLD" => "i", "LEVELS" => "ii",
  "POSTERIZE" => "i", "MAXVAL" => "i", "FLIPH" => "", "FLIPV" => "",
  "ROTATE" => "i", "CROP" => "iiii", "PAD" => "ii", "SCALE" => "ii",
  "SHIFT" => "iii", "TILE" => "ii", "BLUR" => "", "GAUSS" => "",
  "SHARPEN" => "", "CONVOLVE" => "iiiiiiiiii", "SOBEL" => "",
  "MEDIAN" => "", "ERODE" => "", "DILATE" => "", "OPEN" => "",
  "CLOSE" => "", "GRADIENT" => "", "LINE" => "iiiii", "RECT" => "iiiii",
  "CIRCLE" => "iiii", "FLOOD" => "iii", "HISTOGRAM" => "",
  "EQUALIZE" => "", "LABEL" => "i", "DISTANCE" => "i", "STATS" => "",
  "REGION" => "iiii", "DITHER" => "", "ASCIIART" => "", "STORE" => "n",
  "RECALL" => "n", "DROP" => "n", "BLEND" => "nii", "DIFF" => "n",
  "PASTE" => "nii", "SLOTS" => "", "INFO" => "", "UNDO" => "", "REDO" => ""
}.freeze
IMAGELESS = %w[NEW RECALL DROP SLOTS INFO UNDO REDO].freeze
NEED_SLOT = %w[RECALL DROP BLEND DIFF PASTE].freeze

class CommandError < StandardError; end

def check(condition, reason = "bad value")
  raise CommandError, reason unless condition
end

class Image
  attr_reader :width, :height, :maxval, :pixels

  def initialize(width, height, maxval, pixels)
    @width, @height, @maxval, @pixels = width, height, maxval, pixels
  end

  def get(x, y)
    @pixels[y * @width + x]
  end

  def contains?(x, y)
    x >= 0 && y >= 0 && x < @width && y < @height
  end

  def clamp(value)
    value.clamp(0, @maxval)
  end

  def row(y)
    @pixels[y * @width, @width]
  end

  def with_pixels(pixels)
    Image.new(@width, @height, @maxval, pixels)
  end

  def neighborhood(x, y)
    (-1..1).flat_map do |dy|
      (-1..1).map do |dx|
        get((x + dx).clamp(0, @width - 1), (y + dy).clamp(0, @height - 1))
      end
    end
  end

  def summary
    checksum = @pixels.each_with_index.sum { |p, i| (i + 1) * p }
    "#{@width}x#{@height} maxval #{@maxval} checksum #{checksum}"
  end
end

def load_pgm(lines)
  words = lines.flat_map { |line| line.split("#", 2)[0].split }
  check(!words.empty? && words[0] == "P2", "bad magic")
  header = lambda do |index, limit, error|
    check(index < words.length, "truncated header")
    check(DIGITS.match?(words[index]), "bad number")
    value = words[index].to_i
    check(value.between?(1, limit), error)
    value
  end
  w = header.call(1, 64, "bad size")
  h = header.call(2, 64, "bad size")
  m = header.call(3, 255, "bad maxval")
  values = words.drop(4)
  pixels = Array.new(w * h) do |i|
    x, y = i % w, i / w
    check(i < values.length, "too few pixels (#{values.length} of #{w * h})")
    check(DIGITS.match?(values[i]), "bad pixel at #{x},#{y}")
    value = values[i].to_i
    check(value <= m, "pixel out of range at #{x},#{y}")
    value
  end
  check(values.length <= w * h, "too many pixels (#{values.length} of #{w * h})")
  Image.new(w, h, m, pixels)
end

def transformed(image, width = image.width, height = image.height)
  pixels = Array.new(width * height) do |i|
    yield(i % width, i / width)
  end
  Image.new(width, height, image.maxval, pixels)
end

def rotated(image, angle)
  w, h = image.width, image.height
  case angle
  when 90 then transformed(image, h, w) { |x, y| image.get(y, h - 1 - x) }
  when 180 then transformed(image) { |x, y| image.get(w - 1 - x, h - 1 - y) }
  when 270 then transformed(image, h, w) { |x, y| image.get(w - 1 - y, x) }
  end
end

def cropped(image, x, y, width, height)
  transformed(image, width, height) { |i, j| image.get(x + i, y + j) }
end

def translated(image, width, height, dx, dy, fill)
  transformed(image, width, height) do |x, y|
    image.contains?(x - dx, y - dy) ? image.get(x - dx, y - dy) : fill
  end
end

def scaled(image, width, height, numerator, denominator)
  transformed(image, width, height) do |x, y|
    image.get((2 * x + 1) * denominator / (2 * numerator),
              (2 * y + 1) * denominator / (2 * numerator))
  end
end

def convoluted(image, weights, divisor)
  transformed(image) do |x, y|
    total = image.neighborhood(x, y).zip(weights).sum { |p, weight| p * weight }
    image.clamp(total / divisor)
  end
end

def rank_filtered(image, rank)
  transformed(image) { |x, y| image.neighborhood(x, y).sort[rank] }
end

def sobel(image)
  transformed(image) do |x, y|
    q = image.neighborhood(x, y)
    gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6]
    gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2]
    image.clamp(gx.abs + gy.abs)
  end
end

def line_points(x0, y0, x1, y1)
  dx, dy = (x1 - x0).abs, -(y1 - y0).abs
  sx, sy = x0 < x1 ? 1 : -1, y0 < y1 ? 1 : -1
  error, x, y = dx + dy, x0, y0
  points = []
  loop do
    points << [x, y]
    break if x == x1 && y == y1
    twice = 2 * error
    if twice >= dy
      error += dy
      x += sx
    end
    if twice <= dx
      error += dx
      y += sy
    end
  end
  points
end

def rectangle_points(image, left, top, width, height, fill)
  right, bottom = left + width - 1, top + height - 1
  points = []
  ([top, 0].max..[bottom, image.height - 1].min).each do |y|
    ([left, 0].max..[right, image.width - 1].min).each do |x|
      points << [x, y] if fill || x == left || x == right || y == top || y == bottom
    end
  end
  points
end

def circle_points(cx, cy, radius)
  a, b, error = radius, 0, 1 - radius
  points = []
  while a >= b
    points.concat([
      [cx + a, cy + b], [cx + b, cy + a], [cx - b, cy + a], [cx - a, cy + b],
      [cx - a, cy - b], [cx - b, cy - a], [cx + b, cy - a], [cx + a, cy - b]
    ])
    b += 1
    if error < 0
      error += 2 * b + 1
    else
      a -= 1
      error += 2 * (b - a) + 1
    end
  end
  points
end

def disc_points(image, outline)
  rows = {}
  outline.each do |x, y|
    if rows.key?(y)
      left, right = rows[y]
      rows[y] = [[left, x].min, [right, x].max]
    else
      rows[y] = [x, x]
    end
  end
  rows.flat_map do |y, (left, right)|
    next [] unless y.between?(0, image.height - 1)
    ([left, 0].max..[right, image.width - 1].min).map { |x| [x, y] }
  end
end

def flood_points(image, x, y)
  target = image.get(x, y)
  stack = [[x, y]]
  seen = { y * image.width + x => true }
  points = []
  until stack.empty?
    cx, cy = stack.pop
    points << [cx, cy]
    ADJACENT4.each do |dx, dy|
      nx, ny = cx + dx, cy + dy
      next unless image.contains?(nx, ny) && image.get(nx, ny) == target
      index = ny * image.width + nx
      next if seen[index]
      seen[index] = true
      stack << [nx, ny]
    end
  end
  points
end

def equalized(image)
  counts = Array.new(image.maxval + 1, 0)
  image.pixels.each { |pixel| counts[pixel] += 1 }
  accumulated = 0
  cdf = counts.map { |count| accumulated += count }
  size = image.pixels.length
  minimum = cdf[image.pixels.min]
  return image.with_pixels(image.pixels.dup) if minimum == size
  span = size - minimum
  image.with_pixels(image.pixels.map do |p|
    (2 * (cdf[p] - minimum) * image.maxval + span) / (2 * span)
  end)
end

def components(image, threshold)
  w = image.width
  seen = Array.new(image.pixels.length, false)
  groups = []
  image.pixels.each_index do |start|
    next if seen[start] || image.pixels[start] < threshold
    seen[start] = true
    stack = [[start % w, start / w]]
    group = []
    until stack.empty?
      x, y = stack.pop
      group << [x, y]
      ADJACENT8.each do |dx, dy|
        nx, ny = x + dx, y + dy
        next unless image.contains?(nx, ny)
        index = ny * w + nx
        next if seen[index] || image.pixels[index] < threshold
        seen[index] = true
        stack << [nx, ny]
      end
    end
    groups << group
  end
  groups
end

def component_text(image, threshold, points)
  xs, ys = points.transpose
  perimeter = points.count do |x, y|
    ADJACENT4.any? do |dx, dy|
      !image.contains?(x + dx, y + dy) || image.get(x + dx, y + dy) < threshold
    end
  end
  area = points.length
  "area #{area} perimeter #{perimeter} box #{xs.min} #{ys.min} #{xs.max} #{ys.max} " \
    "center #{xs.sum / area} #{ys.sum / area}"
end

def distance_map(image, threshold)
  w, h = image.width, image.height
  far = [w + h, image.maxval].max
  distances = image.pixels.map { |p| p < threshold ? 0 : far }
  h.times do |y|
    w.times do |x|
      i = y * w + x
      distances[i] = [distances[i], distances[i - 1] + 1].min if x > 0
      distances[i] = [distances[i], distances[i - w] + 1].min if y > 0
    end
  end
  (h - 1).downto(0) do |y|
    (w - 1).downto(0) do |x|
      i = y * w + x
      distances[i] = [distances[i], distances[i + 1] + 1].min if x < w - 1
      distances[i] = [distances[i], distances[i + w] + 1].min if y < h - 1
    end
  end
  image.with_pixels(distances.map { |v| [v, image.maxval].min })
end

def statistics(pixels, maxval)
  sorted = pixels.sort
  counts = Array.new(maxval + 1, 0)
  pixels.each { |p| counts[p] += 1 }
  mode = (0..maxval).max_by { |p| [counts[p], -p] }
  "min #{sorted.first} max #{sorted.last} mean #{pixels.sum / pixels.length} " \
    "median #{sorted[(pixels.length - 1) / 2]} mode #{mode}"
end

def dithered(image)
  errors = image.pixels.dup
  pixels = Array.new(errors.length, 0)
  weights = [[1, 0, 7], [-1, 1, 3], [0, 1, 5], [1, 1, 1]]
  image.height.times do |y|
    image.width.times do |x|
      index = y * image.width + x
      old = errors[index]
      value = 2 * old >= image.maxval ? image.maxval : 0
      pixels[index] = value
      error = old - value
      weights.each do |dx, dy, weight|
        nx, ny = x + dx, y + dy
        errors[ny * image.width + nx] += error * weight / 16 if image.contains?(nx, ny)
      end
    end
  end
  image.with_pixels(pixels)
end

class Editor
  attr_reader :output

  def initialize
    @current = nil
    @undo = []
    @redo = []
    @slots = {}
    @output = []
  end

  def parse(words)
    name, *given = words
    pattern = PATTERNS[name]
    check(!pattern.nil?, "unknown command #{name}")
    fill = %w[RECT CIRCLE].include?(name) &&
           given.length == pattern.length + 1 && given[-1] == "FILL"
    args = fill ? given[0...-1] : given
    check(args.length == pattern.length, "bad arguments")
    numbers = []
    slot = nil
    args.each_with_index do |argument, index|
      if pattern[index] == "i"
        check(INTEGER_WORD.match?(argument), "bad arguments")
        numbers << argument.to_i
      else
        check(NAME_WORD.match?(argument), "bad arguments")
        slot = argument
      end
    end
    [name, numbers, slot, fill]
  end

  def execute(words)
    name, args, slot, fill = parse(words)
    check(!@current.nil?, "no image") unless IMAGELESS.include?(name)
    check(@slots.key?(slot), "no slot #{slot}") if NEED_SLOT.include?(name)
    run(name, args, slot, fill)
  rescue CommandError => e
    @output << "error: #{e.message}"
  end

  def load(lines)
    replace(load_pgm(lines), "loaded")
  rescue CommandError => e
    @output << "error: load: #{e.message}"
  end

  def emit(line)
    @output << line
  end

  def replace(image, label)
    @current = image
    @undo.clear
    @redo.clear
    emit("#{label} #{image.summary}")
  end

  def commit(image, painted = nil)
    @undo << @current
    @redo.clear
    @current = image
    emit("ok #{image.summary}#{painted.nil? ? "" : " painted #{painted}"}")
  end

  def paint(points, value)
    image = @current
    marked = {}
    points.each do |x, y|
      marked[y * image.width + x] = true if image.contains?(x, y)
    end
    pixels = image.pixels.each_with_index.map { |p, i| marked[i] ? value : p }
    commit(image.with_pixels(pixels), marked.length)
  end

  def crop_area(args)
    x, y, w, h = args
    image = @current
    check(x >= 0 && y >= 0 && w >= 1 && h >= 1 &&
          x + w <= image.width && y + h <= image.height)
    args
  end

  def matching_slot(name)
    image, other = @current, @slots.fetch(name)
    check(image.width == other.width && image.height == other.height, "size mismatch")
    check(image.maxval == other.maxval, "maxval mismatch")
    other
  end

  def run(name, a, slot, fill)
    image = @current
    w, h, m = image&.width, image&.height, image&.maxval
    case name
    when "NEW"
      width, height, maxval, v = a
      check(width.between?(1, 64) && height.between?(1, 64) &&
            maxval.between?(1, 255) && v.between?(0, maxval))
      replace(Image.new(width, height, maxval, Array.new(width * height, v)), "created")
    when "OUTPUT"
      emit("P2")
      emit("#{w} #{h}")
      emit(m.to_s)
      h.times { |y| emit(image.row(y).join(" ")) }
    when "INVERT"
      commit(image.with_pixels(image.pixels.map { |p| m - p }))
    when "BRIGHTNESS"
      check(a[0].between?(-255, 255))
      commit(image.with_pixels(image.pixels.map { |p| image.clamp(p + a[0]) }))
    when "CONTRAST"
      num, den = a
      check(num.between?(0, 100) && den.between?(1, 100))
      center = (m + 1) / 2
      commit(image.with_pixels(image.pixels.map do |p|
        image.clamp(center + (p - center) * num / den)
      end))
    when "THRESHOLD"
      check(a[0].between?(0, m))
      commit(image.with_pixels(image.pixels.map { |p| p >= a[0] ? m : 0 }))
    when "LEVELS"
      lo, hi = a
      check(lo >= 0 && lo < hi && hi <= m)
      commit(image.with_pixels(image.pixels.map { |p| image.clamp((p - lo) * m / (hi - lo)) }))
    when "POSTERIZE"
      levels = a[0]
      check(levels.between?(2, m + 1))
      commit(image.with_pixels(image.pixels.map do |p|
        (p * levels / (m + 1)) * m / (levels - 1)
      end))
    when "MAXVAL"
      maximum = a[0]
      check(maximum.between?(1, 255))
      pixels = image.pixels.map { |p| (2 * p * maximum + m) / (2 * m) }
      commit(Image.new(w, h, maximum, pixels))
    when "FLIPH"
      commit(transformed(image) { |x, y| image.get(w - 1 - x, y) })
    when "FLIPV"
      commit(transformed(image) { |x, y| image.get(x, h - 1 - y) })
    when "ROTATE"
      check([90, 180, 270].include?(a[0]))
      commit(rotated(image, a[0]))
    when "CROP"
      commit(cropped(image, *crop_area(a)))
    when "PAD"
      n, v = a
      check(n >= 1 && v.between?(0, m))
      check(w + 2 * n <= 64 && h + 2 * n <= 64, "too large")
      commit(translated(image, w + 2 * n, h + 2 * n, n, n, v))
    when "SCALE"
      num, den = a
      check(num.between?(1, 16) && den.between?(1, 16))
      width, height = w * num / den, h * num / den
      check(width >= 1 && height >= 1, "too small")
      check(width <= 64 && height <= 64, "too large")
      commit(scaled(image, width, height, num, den))
    when "SHIFT"
      dx, dy, v = a
      check(dx.between?(-1000, 1000) && dy.between?(-1000, 1000) && v.between?(0, m))
      commit(translated(image, w, h, dx, dy, v))
    when "TILE"
      nx, ny = a
      check(nx >= 1 && ny >= 1)
      check(w * nx <= 64 && h * ny <= 64, "too large")
      commit(transformed(image, w * nx, h * ny) { |x, y| image.get(x % w, y % h) })
    when "BLUR", "GAUSS", "SHARPEN"
      weights, divisor = KERNELS.fetch(name)
      commit(convoluted(image, weights, divisor))
    when "CONVOLVE"
      weights, divisor = a[0, 9], a[9]
      check(weights.all? { |v| v.between?(-16, 16) } && divisor.between?(1, 256))
      commit(convoluted(image, weights, divisor))
    when "SOBEL"
      commit(sobel(image))
    when "MEDIAN"
      commit(rank_filtered(image, 4))
    when "ERODE"
      commit(rank_filtered(image, 0))
    when "DILATE"
      commit(rank_filtered(image, 8))
    when "OPEN"
      commit(rank_filtered(rank_filtered(image, 0), 8))
    when "CLOSE"
      commit(rank_filtered(rank_filtered(image, 8), 0))
    when "GRADIENT"
      high, low = rank_filtered(image, 8), rank_filtered(image, 0)
      commit(image.with_pixels(high.pixels.zip(low.pixels).map { |a0, b0| a0 - b0 }))
    when "LINE"
      x0, y0, x1, y1, v = a
      check([x0, y0, x1, y1].all? { |i| i.between?(-1000, 1000) } && v.between?(0, m))
      paint(line_points(x0, y0, x1, y1), v)
    when "RECT"
      x, y, width, height, v = a
      check(x.between?(-1000, 1000) && y.between?(-1000, 1000) &&
            width.between?(1, 1000) && height.between?(1, 1000) && v.between?(0, m))
      paint(rectangle_points(image, x, y, width, height, fill), v)
    when "CIRCLE"
      x, y, radius, v = a
      check(x.between?(-1000, 1000) && y.between?(-1000, 1000) &&
            radius.between?(0, 1000) && v.between?(0, m))
      outline = circle_points(x, y, radius)
      paint(fill ? disc_points(image, outline) : outline, v)
    when "FLOOD"
      x, y, v = a
      check(image.contains?(x, y) && v.between?(0, m))
      paint(flood_points(image, x, y), v)
    when "HISTOGRAM"
      lows = Array.new(16)
      highs = Array.new(16)
      counts = Array.new(16, 0)
      (0..m).each do |v|
        bin = v * 16 / (m + 1)
        lows[bin] ||= v
        highs[bin] = v
      end
      image.pixels.each { |p| counts[p * 16 / (m + 1)] += 1 }
      top = counts.max
      lows.each_with_index do |lo, bin|
        next if lo.nil?
        emit("#{lo.to_s.rjust(3)}-#{highs[bin].to_s.rjust(3)} " \
             "#{counts[bin].to_s.rjust(4)} |#{"#" * (counts[bin] * 32 / top)}")
      end
    when "EQUALIZE"
      commit(equalized(image))
    when "LABEL"
      threshold = a[0]
      check(threshold.between?(0, m))
      groups = components(image, threshold)
      emit("labels #{groups.length}")
      groups.each_with_index do |group, index|
        emit("label #{index + 1} #{component_text(image, threshold, group)}")
      end
    when "DISTANCE"
      check(a[0].between?(0, m))
      commit(distance_map(image, a[0]))
    when "STATS"
      emit(statistics(image.pixels, m))
    when "REGION"
      emit(statistics(cropped(image, *crop_area(a)).pixels, m))
    when "DITHER"
      commit(dithered(image))
    when "ASCIIART"
      h.times do |y|
        emit(image.row(y).map { |p| SHADES[p * 10 / (m + 1)] }.join)
      end
    when "STORE"
      @slots[slot] = image
      emit("stored #{slot} #{image.summary}")
    when "RECALL"
      replace(@slots.fetch(slot), "recalled #{slot}")
    when "DROP"
      @slots.delete(slot)
      emit("dropped #{slot}")
    when "BLEND"
      num, den = a
      check(den.between?(1, 100) && num.between?(0, den))
      other = matching_slot(slot)
      commit(image.with_pixels(image.pixels.each_with_index.map do |p, i|
        (p * (den - num) + other.pixels[i] * num) / den
      end))
    when "DIFF"
      other = matching_slot(slot)
      commit(image.with_pixels(image.pixels.each_with_index.map do |p, i|
        (p - other.pixels[i]).abs
      end))
    when "PASTE"
      x, y = a
      check(x.between?(-1000, 1000) && y.between?(-1000, 1000))
      other = @slots.fetch(slot)
      check(other.maxval == m, "maxval mismatch")
      pixels = image.pixels.dup
      painted = 0
      other.height.times do |j|
        other.width.times do |i|
          next unless image.contains?(x + i, y + j)
          pixels[(y + j) * w + x + i] = other.get(i, j)
          painted += 1
        end
      end
      commit(image.with_pixels(pixels), painted)
    when "SLOTS"
      emit("no slots") if @slots.empty?
      @slots.keys.sort.each { |key| emit("#{key} #{@slots[key].summary}") }
    when "INFO"
      emit("image #{image.nil? ? "none" : image.summary} " \
           "undo #{@undo.length} redo #{@redo.length} slots #{@slots.length}")
    when "UNDO"
      check(!@undo.empty?, "nothing to undo")
      @redo << image
      @current = @undo.pop
      emit("undo #{@current.summary}")
    when "REDO"
      check(!@redo.empty?, "nothing to redo")
      @undo << image
      @current = @redo.pop
      emit("redo #{@current.summary}")
    end
  end
end

lines = STDIN.each_line.map(&:chomp)
position = 1
editor = Editor.new
lines[0].to_i.times do
  words = lines[position].split(" ")
  position += 1
  if words[0] == "LOAD"
    count = words[1].to_i
    editor.load(lines[position, count])
    position += count
  else
    editor.execute(words)
  end
end
puts editor.output
