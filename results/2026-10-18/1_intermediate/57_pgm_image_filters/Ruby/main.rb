require "set"

PATTERNS = {
  "NEW" => "iiii", "OUTPUT" => "", "INVERT" => "", "BRIGHTNESS" => "i",
  "CONTRAST" => "ii", "THRESHOLD" => "i", "LEVELS" => "ii", "POSTERIZE" => "i",
  "MAXVAL" => "i", "FLIPH" => "", "FLIPV" => "", "ROTATE" => "i",
  "CROP" => "iiii", "PAD" => "ii", "SCALE" => "ii", "SHIFT" => "iii",
  "TILE" => "ii", "BLUR" => "", "GAUSS" => "", "SHARPEN" => "",
  "CONVOLVE" => "iiiiiiiiii", "SOBEL" => "", "MEDIAN" => "", "ERODE" => "",
  "DILATE" => "", "OPEN" => "", "CLOSE" => "", "GRADIENT" => "",
  "LINE" => "iiiii", "RECT" => "iiiii", "CIRCLE" => "iiii", "FLOOD" => "iii",
  "HISTOGRAM" => "", "EQUALIZE" => "", "LABEL" => "i", "DISTANCE" => "i",
  "STATS" => "", "REGION" => "iiii", "DITHER" => "", "ASCIIART" => "",
  "STORE" => "n", "RECALL" => "n", "DROP" => "n", "BLEND" => "nii",
  "DIFF" => "n", "PASTE" => "nii", "SLOTS" => "", "INFO" => "",
  "UNDO" => "", "REDO" => ""
}.freeze
IMAGELESS = %w[NEW RECALL DROP SLOTS INFO UNDO REDO].freeze
SLOT_COMMANDS = %w[RECALL DROP BLEND DIFF PASTE].freeze
NEIGHBORS4 = [[0, -1], [-1, 0], [1, 0], [0, 1]].freeze
NEIGHBORS8 = (-1..1).flat_map { |dy| (-1..1).filter_map { |dx| [dx, dy] unless dx.zero? && dy.zero? } }.freeze
SHADES = "@#*+=~-:,.".freeze
KERNELS = {
  "BLUR" => [[1, 1, 1, 1, 1, 1, 1, 1, 1], 9],
  "GAUSS" => [[1, 2, 1, 2, 4, 2, 1, 2, 1], 16],
  "SHARPEN" => [[0, -1, 0, -1, 5, -1, 0, -1, 0], 1]
}.freeze

class CommandError < StandardError
end

def check(condition, reason = "bad value")
  raise CommandError, reason unless condition
end

def within_limit?(*values)
  values.all? { |value| (-1000..1000).cover?(value) }
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

  def row(y)
    @pixels[y * @width, @width]
  end

  def with_pixels(pixels)
    Image.new(@width, @height, @maxval, pixels)
  end

  def mapped
    with_pixels(@pixels.map { |value| yield value })
  end

  def clamp(value)
    [[value, 0].max, @maxval].min
  end

  def neighborhood(x, y)
    (-1..1).flat_map do |dy|
      (-1..1).map do |dx|
        get([[x + dx, 0].max, @width - 1].min,
            [[y + dy, 0].max, @height - 1].min)
      end
    end
  end

  def summary
    checksum = @pixels.each_with_index.sum { |value, index| value * (index + 1) }
    "#{@width}x#{@height} maxval #{@maxval} checksum #{checksum}"
  end
end

def read_pgm(lines)
  words = lines.flat_map { |line| line.split("#", 2).first.split }
  check(!words.empty? && words[0] == "P2", "bad magic")
  parse_header = lambda do |index, maxval, reason|
    check(index < words.length, "truncated header")
    check(/\A[0-9]+\z/.match?(words[index]), "bad number")
    number = words[index].to_i
    check(number.between?(1, maxval), reason)
    number
  end
  width = parse_header.call(1, 64, "bad size")
  height = parse_header.call(2, 64, "bad size")
  maximum = parse_header.call(3, 255, "bad maxval")
  values = words.drop(4)
  count = width * height
  pixels = []
  count.times do |index|
    x, y = index % width, index / width
    check(index < values.length, "too few pixels (#{values.length} of #{count})")
    check(/\A[0-9]+\z/.match?(values[index]), "bad pixel at #{x},#{y}")
    number = values[index].to_i
    check(number <= maximum, "pixel out of range at #{x},#{y}")
    pixels << number
  end
  check(values.length <= count, "too many pixels (#{values.length} of #{count})")
  Image.new(width, height, maximum, pixels)
end

def transformed(image, width, height)
  pixels = (0...height).flat_map do |y|
    (0...width).map { |x| yield x, y }
  end
  Image.new(width, height, image.maxval, pixels)
end

def cropped(image, x, y, width, height)
  transformed(image, width, height) { |i, j| image.get(x + i, y + j) }
end

def translated(image, width, height, dx, dy, fill)
  transformed(image, width, height) do |x, y|
    image.contains?(x - dx, y - dy) ? image.get(x - dx, y - dy) : fill
  end
end

def convolution(image, coefficients, divisor)
  transformed(image, image.width, image.height) do |x, y|
    value = image.neighborhood(x, y).zip(coefficients).sum { |pixel, weight| pixel * weight }
    image.clamp(value.div(divisor))
  end
end

def rank_filtered(image, rank)
  transformed(image, image.width, image.height) do |x, y|
    image.neighborhood(x, y).sort[rank]
  end
end

def sobel(image)
  transformed(image, image.width, image.height) do |x, y|
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
  wanted = image.get(x, y)
  seen = Set[[x, y]]
  stack = [[x, y]]
  points = []
  until stack.empty?
    cx, cy = stack.pop
    points << [cx, cy]
    NEIGHBORS4.each do |dx, dy|
      nx, ny = cx + dx, cy + dy
      next unless image.contains?(nx, ny) && image.get(nx, ny) == wanted
      next unless seen.add?([nx, ny])
      stack << [nx, ny]
    end
  end
  points
end

def equalized(image)
  counts = Array.new(image.maxval + 1, 0)
  image.pixels.each { |pixel| counts[pixel] += 1 }
  cdf = counts.each_with_object([]) { |count, values| values << count + (values.last || 0) }
  n = image.pixels.length
  first = cdf[image.pixels.min]
  return image.with_pixels(image.pixels.dup) if first == n
  image.mapped { |pixel| (2 * (cdf[pixel] - first) * image.maxval + n - first).div(2 * (n - first)) }
end

def components(image, threshold)
  width = image.width
  visited = Array.new(image.pixels.length, false)
  groups = []
  image.pixels.each_index do |start|
    next if visited[start] || image.pixels[start] < threshold
    visited[start] = true
    stack = [[start % width, start / width]]
    group = []
    until stack.empty?
      x, y = stack.pop
      group << [x, y]
      NEIGHBORS8.each do |dx, dy|
        nx, ny = x + dx, y + dy
        next unless image.contains?(nx, ny)
        index = ny * width + nx
        next if visited[index] || image.pixels[index] < threshold
        visited[index] = true
        stack << [nx, ny]
      end
    end
    groups << group
  end
  groups
end

def component_text(image, threshold, group)
  xx, yy = group.transpose
  perimeter = group.count do |x, y|
    NEIGHBORS4.any? do |dx, dy|
      !image.contains?(x + dx, y + dy) || image.get(x + dx, y + dy) < threshold
    end
  end
  "area #{group.length} perimeter #{perimeter} box #{xx.min} #{yy.min} #{xx.max} #{yy.max} " \
    "center #{xx.sum.div(group.length)} #{yy.sum.div(group.length)}"
end

def distance_map(image, threshold)
  if image.pixels.all? { |pixel| pixel >= threshold }
    return image.with_pixels(Array.new(image.pixels.length, image.maxval))
  end
  w, h = image.width, image.height
  far = w + h
  distances = image.pixels.map { |pixel| pixel < threshold ? 0 : far }
  (0...h).each do |y|
    (0...w).each do |x|
      index = y * w + x
      distances[index] = [distances[index], distances[index - 1] + 1].min if x > 0
      distances[index] = [distances[index], distances[index - w] + 1].min if y > 0
    end
  end
  (h - 1).downto(0) do |y|
    (w - 1).downto(0) do |x|
      index = y * w + x
      distances[index] = [distances[index], distances[index + 1] + 1].min if x < w - 1
      distances[index] = [distances[index], distances[index + w] + 1].min if y < h - 1
    end
  end
  image.with_pixels(distances.map { |value| [value, image.maxval].min })
end

def statistics(pixels, maxval)
  values = pixels.sort
  counts = Array.new(maxval + 1, 0)
  pixels.each { |value| counts[value] += 1 }
  "min #{values.first} max #{values.last} mean #{pixels.sum.div(pixels.length)} " \
    "median #{values[(pixels.length - 1) / 2]} mode #{counts.index(counts.max)}"
end

def dithered(image)
  errors = image.pixels.dup
  pixels = Array.new(errors.length, 0)
  neighbors = [[1, 0, 7], [-1, 1, 3], [0, 1, 5], [1, 1, 1]]
  (0...image.height).each do |y|
    (0...image.width).each do |x|
      index = y * image.width + x
      old = errors[index]
      value = 2 * old >= image.maxval ? image.maxval : 0
      pixels[index] = value
      difference = old - value
      neighbors.each do |dx, dy, weight|
        next unless image.contains?(x + dx, y + dy)
        errors[(y + dy) * image.width + x + dx] += (difference * weight).div(16)
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

  def emit(line)
    @output << line
  end

  def load(lines)
    replace(read_pgm(lines), "loaded")
  rescue CommandError => error
    emit("error: load: #{error.message}")
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
    emit("ok #{image.summary}#{painted.nil? ? '' : " painted #{painted}"}")
  end

  def paint(points, value)
    image = @current
    touched = Set.new
    points.each do |x, y|
      touched.add(y * image.width + x) if image.contains?(x, y)
    end
    pixels = image.pixels.each_with_index.map { |pixel, index| touched.include?(index) ? value : pixel }
    commit(image.with_pixels(pixels), touched.length)
  end

  def checked_crop(args)
    x, y, w, h = args
    image = @current
    check(x >= 0 && y >= 0 && w >= 1 && h >= 1)
    check(x + w <= image.width && y + h <= image.height)
    args
  end

  def matching_slot(name)
    other = @slots.fetch(name)
    check(other.width == @current.width && other.height == @current.height, "size mismatch")
    check(other.maxval == @current.maxval, "maxval mismatch")
    other
  end

  def execute(words)
    name = words.first
    check(PATTERNS.key?(name), "unknown command #{name}")
    pattern = PATTERNS[name]
    given = words.drop(1)
    fill = %w[RECT CIRCLE].include?(name) && given.length == pattern.length + 1 && given[-1] == "FILL"
    given = given[0...-1] if fill
    check(given.length == pattern.length, "bad arguments")
    values = []
    slot = nil
    given.each_with_index do |word, index|
      if pattern[index] == "i"
        check(/\A(?:0|-?[1-9][0-9]{0,6})\z/.match?(word), "bad arguments")
        values << word.to_i
      else
        check(/\A[a-z]{1,8}\z/.match?(word), "bad arguments")
        slot = word
      end
    end
    check(!@current.nil?, "no image") unless IMAGELESS.include?(name)
    check(@slots.key?(slot), "no slot #{slot}") if SLOT_COMMANDS.include?(name)
    run(name, values, slot, fill)
  rescue CommandError => error
    emit("error: #{error.message}")
  end

  def run(name, a, slot, fill)
    image = @current
    m = image&.maxval
    case name
    when "NEW"
      w, h, maximum, value = a
      check(w.between?(1, 64) && h.between?(1, 64))
      check(maximum.between?(1, 255) && value.between?(0, maximum))
      replace(Image.new(w, h, maximum, Array.new(w * h, value)), "created")
    when "OUTPUT"
      emit("P2")
      emit("#{image.width} #{image.height}")
      emit(m.to_s)
      image.height.times { |y| emit(image.row(y).join(" ")) }
    when "INVERT"
      commit(image.mapped { |pixel| m - pixel })
    when "BRIGHTNESS"
      check(a[0].between?(-255, 255))
      commit(image.mapped { |pixel| image.clamp(pixel + a[0]) })
    when "CONTRAST"
      num, den = a
      check(num.between?(0, 100) && den.between?(1, 100))
      center = (m + 1) / 2
      commit(image.mapped { |pixel| image.clamp(center + ((pixel - center) * num).div(den)) })
    when "THRESHOLD"
      check(a[0].between?(0, m))
      commit(image.mapped { |pixel| pixel >= a[0] ? m : 0 })
    when "LEVELS"
      low, high = a
      check(low >= 0 && low < high && high <= m)
      commit(image.mapped { |pixel| image.clamp(((pixel - low) * m).div(high - low)) })
    when "POSTERIZE"
      levels = a[0]
      check(levels.between?(2, m + 1))
      commit(image.mapped { |pixel| ((pixel * levels).div(m + 1) * m).div(levels - 1) })
    when "MAXVAL"
      maximum = a[0]
      check(maximum.between?(1, 255))
      pixels = image.pixels.map { |pixel| (2 * pixel * maximum + m).div(2 * m) }
      commit(Image.new(image.width, image.height, maximum, pixels))
    when "FLIPH"
      commit(transformed(image, image.width, image.height) { |x, y| image.get(image.width - 1 - x, y) })
    when "FLIPV"
      commit(transformed(image, image.width, image.height) { |x, y| image.get(x, image.height - 1 - y) })
    when "ROTATE"
      angle = a[0]
      check([90, 180, 270].include?(angle))
      w, h = image.width, image.height
      result = if angle == 180
        transformed(image, w, h) { |x, y| image.get(w - 1 - x, h - 1 - y) }
      elsif angle == 90
        transformed(image, h, w) { |x, y| image.get(y, h - 1 - x) }
      else
        transformed(image, h, w) { |x, y| image.get(w - 1 - y, x) }
      end
      commit(result)
    when "CROP"
      commit(cropped(image, *checked_crop(a)))
    when "PAD"
      border, fill_value = a
      check(border >= 1 && fill_value.between?(0, m))
      w, h = image.width + 2 * border, image.height + 2 * border
      check(w <= 64 && h <= 64, "too large")
      commit(translated(image, w, h, border, border, fill_value))
    when "SCALE"
      num, den = a
      check(num.between?(1, 16) && den.between?(1, 16))
      w, h = image.width * num / den, image.height * num / den
      check(w > 0 && h > 0, "too small")
      check(w <= 64 && h <= 64, "too large")
      commit(transformed(image, w, h) do |x, y|
        image.get(((2 * x + 1) * den).div(2 * num), ((2 * y + 1) * den).div(2 * num))
      end)
    when "SHIFT"
      dx, dy, fill_value = a
      check(within_limit?(dx, dy) && fill_value.between?(0, m))
      commit(translated(image, image.width, image.height, dx, dy, fill_value))
    when "TILE"
      nx, ny = a
      check(nx >= 1 && ny >= 1)
      w, h = image.width * nx, image.height * ny
      check(w <= 64 && h <= 64, "too large")
      commit(transformed(image, w, h) { |x, y| image.get(x % image.width, y % image.height) })
    when "BLUR", "GAUSS", "SHARPEN"
      commit(convolution(image, *KERNELS.fetch(name)))
    when "CONVOLVE"
      check(a.first(9).all? { |v| v.between?(-16, 16) } && a[9].between?(1, 256))
      commit(convolution(image, a.first(9), a[9]))
    when "SOBEL"
      commit(sobel(image))
    when "MEDIAN", "ERODE", "DILATE"
      commit(rank_filtered(image, { "MEDIAN" => 4, "ERODE" => 0, "DILATE" => 8 }.fetch(name)))
    when "OPEN"
      commit(rank_filtered(rank_filtered(image, 0), 8))
    when "CLOSE"
      commit(rank_filtered(rank_filtered(image, 8), 0))
    when "GRADIENT"
      high = rank_filtered(image, 8).pixels
      low = rank_filtered(image, 0).pixels
      commit(image.with_pixels(high.zip(low).map { |a1, b1| a1 - b1 }))
    when "LINE"
      check(within_limit?(*a.first(4)) && a[4].between?(0, m))
      paint(line_points(*a.first(4)), a[4])
    when "RECT"
      x, y, w, h, value = a
      check(within_limit?(x, y) && w.between?(1, 1000) && h.between?(1, 1000) && value.between?(0, m))
      paint(rectangle_points(image, x, y, w, h, fill), value)
    when "CIRCLE"
      cx, cy, radius, value = a
      check(within_limit?(cx, cy) && radius.between?(0, 1000) && value.between?(0, m))
      points = circle_points(cx, cy, radius)
      paint(fill ? disc_points(image, points) : points, value)
    when "FLOOD"
      x, y, value = a
      check(image.contains?(x, y) && value.between?(0, m))
      paint(flood_points(image, x, y), value)
    when "HISTOGRAM"
      lows = Array.new(16)
      highs = Array.new(16, 0)
      counts = Array.new(16, 0)
      (0..m).each do |value|
        index = value * 16 / (m + 1)
        lows[index] ||= value
        highs[index] = value
      end
      image.pixels.each { |value| counts[value * 16 / (m + 1)] += 1 }
      top = counts.max
      16.times do |index|
        next if lows[index].nil?
        emit("#{lows[index].to_s.rjust(3)}-#{highs[index].to_s.rjust(3)} " \
             "#{counts[index].to_s.rjust(4)} |#{'#' * (counts[index] * 32 / top)}")
      end
    when "EQUALIZE"
      commit(equalized(image))
    when "LABEL"
      check(a[0].between?(0, m))
      groups = components(image, a[0])
      emit("labels #{groups.length}")
      groups.each_with_index do |group, index|
        emit("label #{index + 1} #{component_text(image, a[0], group)}")
      end
    when "DISTANCE"
      check(a[0].between?(0, m))
      commit(distance_map(image, a[0]))
    when "STATS"
      emit(statistics(image.pixels, m))
    when "REGION"
      emit(statistics(cropped(image, *checked_crop(a)).pixels, m))
    when "DITHER"
      commit(dithered(image))
    when "ASCIIART"
      image.height.times do |y|
        emit(image.row(y).map { |pixel| SHADES[pixel * 10 / (m + 1)] }.join)
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
      check(num >= 0 && num <= den && den.between?(1, 100))
      other = matching_slot(slot)
      pixels = image.pixels.each_with_index.map do |pixel, index|
        (pixel * (den - num) + other.pixels[index] * num).div(den)
      end
      commit(image.with_pixels(pixels))
    when "DIFF"
      other = matching_slot(slot)
      commit(image.with_pixels(image.pixels.each_with_index.map { |pixel, i| (pixel - other.pixels[i]).abs }))
    when "PASTE"
      x, y = a
      check(within_limit?(x, y))
      other = @slots.fetch(slot)
      check(other.maxval == m, "maxval mismatch")
      pixels = image.pixels.dup
      painted = 0
      other.height.times do |j|
        other.width.times do |i|
          next unless image.contains?(x + i, y + j)
          pixels[(y + j) * image.width + x + i] = other.get(i, j)
          painted += 1
        end
      end
      commit(image.with_pixels(pixels), painted)
    when "SLOTS"
      emit("no slots") if @slots.empty?
      @slots.keys.sort.each { |key| emit("#{key} #{@slots[key].summary}") }
    when "INFO"
      emit("image #{image ? image.summary : 'none'} undo #{@undo.length} redo #{@redo.length} slots #{@slots.length}")
    when "UNDO"
      check(!@undo.empty?, "nothing to undo")
      @redo << @current
      @current = @undo.pop
      emit("undo #{@current.summary}")
    when "REDO"
      check(!@redo.empty?, "nothing to redo")
      @undo << @current
      @current = @redo.pop
      emit("redo #{@current.summary}")
    end
  end
end

count = Integer(STDIN.gets)
editor = Editor.new
count.times do
  words = STDIN.gets.chomp.split(" ")
  if words[0] == "LOAD"
    length = words[1].to_i
    editor.load(Array.new(length) { STDIN.gets.chomp })
  else
    editor.execute(words)
  end
end
STDOUT.write(editor.output.join("\n") + "\n")
