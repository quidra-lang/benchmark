# frozen_string_literal: true

PATTERNS = {
  'NEW' => 'iiii', 'OUTPUT' => '', 'INVERT' => '', 'BRIGHTNESS' => 'i',
  'CONTRAST' => 'ii', 'THRESHOLD' => 'i', 'LEVELS' => 'ii',
  'POSTERIZE' => 'i', 'MAXVAL' => 'i', 'FLIPH' => '', 'FLIPV' => '',
  'ROTATE' => 'i', 'CROP' => 'iiii', 'PAD' => 'ii', 'SCALE' => 'ii',
  'SHIFT' => 'iii', 'TILE' => 'ii', 'BLUR' => '', 'GAUSS' => '',
  'SHARPEN' => '', 'CONVOLVE' => 'iiiiiiiiii', 'SOBEL' => '',
  'MEDIAN' => '', 'ERODE' => '', 'DILATE' => '', 'OPEN' => '',
  'CLOSE' => '', 'GRADIENT' => '', 'LINE' => 'iiiii',
  'RECT' => 'iiiii', 'CIRCLE' => 'iiii', 'FLOOD' => 'iii',
  'HISTOGRAM' => '', 'EQUALIZE' => '', 'LABEL' => 'i',
  'DISTANCE' => 'i', 'STATS' => '', 'REGION' => 'iiii',
  'DITHER' => '', 'ASCIIART' => '', 'STORE' => 'n',
  'RECALL' => 'n', 'DROP' => 'n', 'BLEND' => 'nii',
  'DIFF' => 'n', 'PASTE' => 'nii', 'SLOTS' => '',
  'INFO' => '', 'UNDO' => '', 'REDO' => ''
}.freeze

IMAGELESS = %w[NEW RECALL DROP SLOTS INFO UNDO REDO].freeze
NEED_SLOT = %w[RECALL DROP BLEND DIFF PASTE].freeze
SHADES = '@#*+=~-:,.'.freeze
NEIGHBORS4 = [[0, -1], [-1, 0], [1, 0], [0, 1]].freeze
NEIGHBORS8 = (-1..1).flat_map { |dy| (-1..1).map { |dx| [dx, dy] } }
                 .reject { |dx, dy| dx.zero? && dy.zero? }.freeze
KERNELS = {
  'BLUR' => [[1, 1, 1, 1, 1, 1, 1, 1, 1], 9],
  'GAUSS' => [[1, 2, 1, 2, 4, 2, 1, 2, 1], 16],
  'SHARPEN' => [[0, -1, 0, -1, 5, -1, 0, -1, 0], 1]
}.freeze

class CommandError < StandardError; end

def check(condition, reason = 'bad value')
  raise CommandError, reason unless condition
end

def clamp(value, low, high)
  [[value, low].max, high].min
end

class Image
  attr_reader :width, :height, :maxval, :pixels

  def initialize(width, height, maxval, pixels)
    @width = width
    @height = height
    @maxval = maxval
    @pixels = pixels
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

  def limit(value)
    clamp(value, 0, @maxval)
  end

  def neighborhood(x, y)
    (-1..1).flat_map do |dy|
      (-1..1).map do |dx|
        get(clamp(x + dx, 0, @width - 1), clamp(y + dy, 0, @height - 1))
      end
    end
  end

  def summary
    checksum = @pixels.each_with_index.sum { |p, i| (i + 1) * p }
    "#{@width}x#{@height} maxval #{@maxval} checksum #{checksum}"
  end
end

def read_pgm(lines)
  words = lines.flat_map { |line| line.split('#', 2).first.split }
  check(!words.empty? && words[0] == 'P2', 'bad magic')
  header = lambda do |i, limit, error|
    check(i < words.size, 'truncated header')
    check(/\A[0-9]+\z/.match?(words[i]), 'bad number')
    number = words[i].to_i
    check((1..limit).cover?(number), error)
    number
  end
  width = header.call(1, 64, 'bad size')
  height = header.call(2, 64, 'bad size')
  maxval = header.call(3, 255, 'bad maxval')
  values = words.drop(4)
  pixels = []
  (width * height).times do |i|
    x = i % width
    y = i / width
    check(i < values.size, "too few pixels (#{values.size} of #{width * height})")
    check(/\A[0-9]+\z/.match?(values[i]), "bad pixel at #{x},#{y}")
    pixel = values[i].to_i
    check(pixel <= maxval, "pixel out of range at #{x},#{y}")
    pixels << pixel
  end
  check(values.size == width * height, "too many pixels (#{values.size} of #{width * height})")
  Image.new(width, height, maxval, pixels)
end

def transform(image, width = image.width, height = image.height)
  pixels = Array.new(width * height) do |i|
    yield(i % width, i / width)
  end
  Image.new(width, height, image.maxval, pixels)
end

def convolution(image, kernel, divisor)
  transform(image) do |x, y|
    q = image.neighborhood(x, y)
    image.limit(kernel.each_with_index.sum { |coefficient, i| coefficient * q[i] } / divisor)
  end
end

def rank_filter(image, rank)
  transform(image) { |x, y| image.neighborhood(x, y).sort[rank] }
end

def sobel(image)
  transform(image) do |x, y|
    q = image.neighborhood(x, y)
    gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6]
    gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2]
    image.limit(gx.abs + gy.abs)
  end
end

def line_points(x0, y0, x1, y1)
  dx = (x1 - x0).abs
  dy = -(y1 - y0).abs
  sx = x0 < x1 ? 1 : -1
  sy = y0 < y1 ? 1 : -1
  error = dx + dy
  points = []
  loop do
    points << [x0, y0]
    break if x0 == x1 && y0 == y1

    twice = 2 * error
    if twice >= dy
      error += dy
      x0 += sx
    end
    if twice <= dx
      error += dx
      y0 += sy
    end
  end
  points
end

def rectangle_points(image, x, y, width, height, fill)
  right = x + width - 1
  bottom = y + height - 1
  points = []
  ([y, 0].max..[bottom, image.height - 1].min).each do |j|
    ([x, 0].max..[right, image.width - 1].min).each do |i|
      points << [i, j] if fill || i == x || i == right || j == y || j == bottom
    end
  end
  points
end

def circle_points(cx, cy, radius)
  a = radius
  b = 0
  error = 1 - radius
  points = []
  while a >= b
    points.concat([
      [cx + a, cy + b], [cx + b, cy + a],
      [cx - b, cy + a], [cx - a, cy + b],
      [cx - a, cy - b], [cx - b, cy - a],
      [cx + b, cy - a], [cx + a, cy - b]
    ])
    b += 1
    if error.negative?
      error += 2 * b + 1
    else
      a -= 1
      error += 2 * (b - a) + 1
    end
  end
  points
end

def filled_circle(image, outline)
  rows = {}
  outline.each do |x, y|
    if rows.key?(y)
      rows[y][0] = [rows[y][0], x].min
      rows[y][1] = [rows[y][1], x].max
    else
      rows[y] = [x, x]
    end
  end
  rows.flat_map do |y, (lo, hi)|
    next [] unless (0...image.height).cover?(y)

    ([lo, 0].max..[hi, image.width - 1].min).map { |x| [x, y] }
  end
end

def flood_points(image, x, y)
  value = image.get(x, y)
  stack = [[x, y]]
  visited = { y * image.width + x => true }
  points = []
  until stack.empty?
    cx, cy = stack.pop
    points << [cx, cy]
    NEIGHBORS4.each do |dx, dy|
      nx = cx + dx
      ny = cy + dy
      next unless image.contains?(nx, ny) && image.get(nx, ny) == value

      index = ny * image.width + nx
      next if visited[index]

      visited[index] = true
      stack << [nx, ny]
    end
  end
  points
end

def equalize(image)
  counts = Array.new(image.maxval + 1, 0)
  image.pixels.each { |p| counts[p] += 1 }
  accumulated = 0
  cdf = counts.map { |n| accumulated += n }
  minimum = cdf[image.pixels.min]
  size = image.pixels.size
  return image.with_pixels(image.pixels.dup) if minimum == size

  span = size - minimum
  image.with_pixels(image.pixels.map do |p|
    (2 * (cdf[p] - minimum) * image.maxval + span) / (2 * span)
  end)
end

def components(image, threshold)
  visited = Array.new(image.pixels.size, false)
  groups = []
  image.pixels.each_index do |index|
    next if visited[index] || image.pixels[index] < threshold

    visited[index] = true
    group = []
    stack = [[index % image.width, index / image.width]]
    until stack.empty?
      x, y = stack.pop
      group << [x, y]
      NEIGHBORS8.each do |dx, dy|
        nx = x + dx
        ny = y + dy
        next unless image.contains?(nx, ny)

        ni = ny * image.width + nx
        next if visited[ni] || image.pixels[ni] < threshold

        visited[ni] = true
        stack << [nx, ny]
      end
    end
    groups << group
  end
  groups
end

def component_text(image, threshold, group)
  xs, ys = group.transpose
  perimeter = group.count do |x, y|
    NEIGHBORS4.any? do |dx, dy|
      !image.contains?(x + dx, y + dy) || image.get(x + dx, y + dy) < threshold
    end
  end
  "area #{group.size} perimeter #{perimeter} box #{xs.min} #{ys.min} #{xs.max} #{ys.max} " \
    "center #{xs.sum / group.size} #{ys.sum / group.size}"
end

def distance_map(image, threshold)
  return image.with_pixels(Array.new(image.pixels.size, image.maxval)) unless image.pixels.any? { |p| p < threshold }

  width = image.width
  height = image.height
  far = width + height
  distances = image.pixels.map { |p| p < threshold ? 0 : far }
  height.times do |y|
    width.times do |x|
      i = y * width + x
      distances[i] = [distances[i], distances[i - 1] + 1].min if x > 0
      distances[i] = [distances[i], distances[i - width] + 1].min if y > 0
    end
  end
  (height - 1).downto(0) do |y|
    (width - 1).downto(0) do |x|
      i = y * width + x
      distances[i] = [distances[i], distances[i + 1] + 1].min if x < width - 1
      distances[i] = [distances[i], distances[i + width] + 1].min if y < height - 1
    end
  end
  image.with_pixels(distances.map { |n| [n, image.maxval].min })
end

def statistics(pixels, maxval)
  sorted = pixels.sort
  count = Array.new(maxval + 1, 0)
  pixels.each { |p| count[p] += 1 }
  mode = (0..maxval).max_by { |p| [count[p], -p] }
  "min #{sorted.first} max #{sorted.last} mean #{pixels.sum / pixels.size} " \
    "median #{sorted[(pixels.size - 1) / 2]} mode #{mode}"
end

def dither(image)
  errors = image.pixels.dup
  pixels = Array.new(errors.size, 0)
  diffusion = [[1, 0, 7], [-1, 1, 3], [0, 1, 5], [1, 1, 1]]
  image.height.times do |y|
    image.width.times do |x|
      index = y * image.width + x
      old = errors[index]
      new_pixel = 2 * old >= image.maxval ? image.maxval : 0
      pixels[index] = new_pixel
      error = old - new_pixel
      diffusion.each do |dx, dy, weight|
        nx = x + dx
        ny = y + dy
        errors[ny * image.width + nx] += error * weight / 16 if image.contains?(nx, ny)
      end
    end
  end
  image.with_pixels(pixels)
end

class ImageEditor
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

  def parse(words)
    name = words.first
    check(PATTERNS.key?(name), "unknown command #{name}")
    pattern = PATTERNS[name]
    words = words.drop(1)
    fill = %w[RECT CIRCLE].include?(name) &&
           words.size == pattern.size + 1 && words.last == 'FILL'
    words = words[0...-1] if fill
    check(words.size == pattern.size, 'bad arguments')
    values = []
    slot = nil
    pattern.chars.zip(words).each do |kind, word|
      if kind == 'i'
        check(/\A(?:0|-?[1-9][0-9]{0,6})\z/.match?(word), 'bad arguments')
        values << word.to_i
      else
        check(/\A[a-z]{1,8}\z/.match?(word), 'bad arguments')
        slot = word
      end
    end
    [name, values, slot, fill]
  end

  def execute(words)
    name, values, slot, fill = parse(words)
    check(!@current.nil?, 'no image') unless IMAGELESS.include?(name)
    check(@slots.key?(slot), "no slot #{slot}") if NEED_SLOT.include?(name)
    run(name, values, slot, fill)
  rescue CommandError => e
    emit("error: #{e.message}")
  end

  def load(lines)
    replace(read_pgm(lines), 'loaded')
  rescue CommandError => e
    emit("error: load: #{e.message}")
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
    marked = {}
    points.each do |x, y|
      marked[y * image.width + x] = true if image.contains?(x, y)
    end
    commit(image.with_pixels(image.pixels.each_with_index.map do |p, i|
      marked[i] ? value : p
    end), marked.size)
  end

  def crop_area(args)
    x, y, w, h = args
    check(x >= 0 && y >= 0 && w >= 1 && h >= 1)
    check(x + w <= @current.width && y + h <= @current.height)
    args
  end

  def matching_slot(name)
    other = @slots[name]
    check(other.width == @current.width && other.height == @current.height, 'size mismatch')
    check(other.maxval == @current.maxval, 'maxval mismatch')
    other
  end

  def run(name, a, slot, fill)
    image = @current
    w = image&.width
    h = image&.height
    m = image&.maxval
    case name
    when 'NEW'
      width, height, maxval, value = a
      check((1..64).cover?(width) && (1..64).cover?(height))
      check((1..255).cover?(maxval) && (0..maxval).cover?(value))
      replace(Image.new(width, height, maxval, Array.new(width * height, value)), 'created')
    when 'OUTPUT'
      emit('P2')
      emit("#{w} #{h}")
      emit(m.to_s)
      h.times { |y| emit(image.row(y).join(' ')) }
    when 'INVERT'
      commit(image.with_pixels(image.pixels.map { |p| m - p }))
    when 'BRIGHTNESS'
      check((-255..255).cover?(a[0]))
      commit(image.with_pixels(image.pixels.map { |p| image.limit(p + a[0]) }))
    when 'CONTRAST'
      num, den = a
      check((0..100).cover?(num) && (1..100).cover?(den))
      center = (m + 1) / 2
      commit(image.with_pixels(image.pixels.map do |p|
        image.limit(center + (p - center) * num / den)
      end))
    when 'THRESHOLD'
      check((0..m).cover?(a[0]))
      commit(image.with_pixels(image.pixels.map { |p| p >= a[0] ? m : 0 }))
    when 'LEVELS'
      lo, hi = a
      check(0 <= lo && lo < hi && hi <= m)
      commit(image.with_pixels(image.pixels.map { |p| image.limit((p - lo) * m / (hi - lo)) }))
    when 'POSTERIZE'
      levels = a[0]
      check((2..m + 1).cover?(levels))
      commit(image.with_pixels(image.pixels.map do |p|
        q = p * levels / (m + 1)
        q * m / (levels - 1)
      end))
    when 'MAXVAL'
      new_max = a[0]
      check((1..255).cover?(new_max))
      pixels = image.pixels.map { |p| (2 * p * new_max + m) / (2 * m) }
      commit(Image.new(w, h, new_max, pixels))
    when 'FLIPH'
      commit(transform(image) { |x, y| image.get(w - x - 1, y) })
    when 'FLIPV'
      commit(transform(image) { |x, y| image.get(x, h - y - 1) })
    when 'ROTATE'
      angle = a[0]
      check([90, 180, 270].include?(angle))
      result = case angle
               when 90 then transform(image, h, w) { |x, y| image.get(y, h - 1 - x) }
               when 180 then transform(image) { |x, y| image.get(w - 1 - x, h - 1 - y) }
               when 270 then transform(image, h, w) { |x, y| image.get(w - 1 - y, x) }
               end
      commit(result)
    when 'CROP'
      x, y, width, height = crop_area(a)
      commit(transform(image, width, height) { |i, j| image.get(x + i, y + j) })
    when 'PAD'
      n, value = a
      check(n >= 1 && (0..m).cover?(value))
      check(w + 2 * n <= 64 && h + 2 * n <= 64, 'too large')
      commit(transform(image, w + 2 * n, h + 2 * n) do |x, y|
        image.contains?(x - n, y - n) ? image.get(x - n, y - n) : value
      end)
    when 'SCALE'
      num, den = a
      check((1..16).cover?(num) && (1..16).cover?(den))
      width = w * num / den
      height = h * num / den
      check(width >= 1 && height >= 1, 'too small')
      check(width <= 64 && height <= 64, 'too large')
      commit(transform(image, width, height) do |x, y|
        image.get((2 * x + 1) * den / (2 * num), (2 * y + 1) * den / (2 * num))
      end)
    when 'SHIFT'
      dx, dy, value = a
      check((-1000..1000).cover?(dx) && (-1000..1000).cover?(dy) && (0..m).cover?(value))
      commit(transform(image) do |x, y|
        image.contains?(x - dx, y - dy) ? image.get(x - dx, y - dy) : value
      end)
    when 'TILE'
      nx, ny = a
      check(nx >= 1 && ny >= 1)
      check(w * nx <= 64 && h * ny <= 64, 'too large')
      commit(transform(image, w * nx, h * ny) { |x, y| image.get(x % w, y % h) })
    when 'BLUR', 'GAUSS', 'SHARPEN'
      kernel, divisor = KERNELS.fetch(name)
      commit(convolution(image, kernel, divisor))
    when 'CONVOLVE'
      check(a.first(9).all? { |n| (-16..16).cover?(n) } && (1..256).cover?(a[9]))
      commit(convolution(image, a.first(9), a[9]))
    when 'SOBEL'
      commit(sobel(image))
    when 'MEDIAN'
      commit(rank_filter(image, 4))
    when 'ERODE'
      commit(rank_filter(image, 0))
    when 'DILATE'
      commit(rank_filter(image, 8))
    when 'OPEN'
      commit(rank_filter(rank_filter(image, 0), 8))
    when 'CLOSE'
      commit(rank_filter(rank_filter(image, 8), 0))
    when 'GRADIENT'
      minimum = rank_filter(image, 0).pixels
      maximum = rank_filter(image, 8).pixels
      commit(image.with_pixels(maximum.zip(minimum).map { |hi, lo| hi - lo }))
    when 'LINE'
      x0, y0, x1, y1, value = a
      check(a.first(4).all? { |v| (-1000..1000).cover?(v) } && (0..m).cover?(value))
      paint(line_points(x0, y0, x1, y1), value)
    when 'RECT'
      x, y, width, height, value = a
      check((-1000..1000).cover?(x) && (-1000..1000).cover?(y))
      check((1..1000).cover?(width) && (1..1000).cover?(height) && (0..m).cover?(value))
      paint(rectangle_points(image, x, y, width, height, fill), value)
    when 'CIRCLE'
      cx, cy, radius, value = a
      check((-1000..1000).cover?(cx) && (-1000..1000).cover?(cy))
      check((0..1000).cover?(radius) && (0..m).cover?(value))
      points = circle_points(cx, cy, radius)
      paint(fill ? filled_circle(image, points) : points, value)
    when 'FLOOD'
      x, y, value = a
      check(image.contains?(x, y) && (0..m).cover?(value))
      paint(flood_points(image, x, y), value)
    when 'HISTOGRAM'
      lower = Array.new(16)
      upper = Array.new(16)
      counts = Array.new(16, 0)
      (0..m).each do |value|
        bin = value * 16 / (m + 1)
        lower[bin] ||= value
        upper[bin] = value
      end
      image.pixels.each { |p| counts[p * 16 / (m + 1)] += 1 }
      top = counts.max
      16.times do |bin|
        next if lower[bin].nil?

        emit(format('%3d-%3d %4d |%s', lower[bin], upper[bin], counts[bin],
                    '#' * (counts[bin] * 32 / top)))
      end
    when 'EQUALIZE'
      commit(equalize(image))
    when 'LABEL'
      check((0..m).cover?(a[0]))
      groups = components(image, a[0])
      emit("labels #{groups.size}")
      groups.each_with_index do |group, i|
        emit("label #{i + 1} #{component_text(image, a[0], group)}")
      end
    when 'DISTANCE'
      check((0..m).cover?(a[0]))
      commit(distance_map(image, a[0]))
    when 'STATS'
      emit(statistics(image.pixels, m))
    when 'REGION'
      x, y, width, height = crop_area(a)
      pixels = transform(image, width, height) { |i, j| image.get(x + i, y + j) }.pixels
      emit(statistics(pixels, m))
    when 'DITHER'
      commit(dither(image))
    when 'ASCIIART'
      h.times do |y|
        emit(image.row(y).map { |p| SHADES[p * 10 / (m + 1)] }.join)
      end
    when 'STORE'
      @slots[slot] = image
      emit("stored #{slot} #{image.summary}")
    when 'RECALL'
      replace(@slots.fetch(slot), "recalled #{slot}")
    when 'DROP'
      @slots.delete(slot)
      emit("dropped #{slot}")
    when 'BLEND'
      num, den = a
      check(num >= 0 && den >= 1 && den <= 100 && num <= den)
      other = matching_slot(slot)
      pixels = image.pixels.zip(other.pixels).map do |p, q|
        (p * (den - num) + q * num) / den
      end
      commit(image.with_pixels(pixels))
    when 'DIFF'
      other = matching_slot(slot)
      commit(image.with_pixels(image.pixels.zip(other.pixels).map { |p, q| (p - q).abs }))
    when 'PASTE'
      x, y = a
      check((-1000..1000).cover?(x) && (-1000..1000).cover?(y))
      other = @slots.fetch(slot)
      check(other.maxval == m, 'maxval mismatch')
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
    when 'SLOTS'
      emit('no slots') if @slots.empty?
      @slots.sort.each { |key, value| emit("#{key} #{value.summary}") }
    when 'INFO'
      emit("image #{image ? image.summary : 'none'} undo #{@undo.size} " \
           "redo #{@redo.size} slots #{@slots.size}")
    when 'UNDO'
      check(!@undo.empty?, 'nothing to undo')
      @redo << image
      @current = @undo.pop
      emit("undo #{@current.summary}")
    when 'REDO'
      check(!@redo.empty?, 'nothing to redo')
      @undo << image
      @current = @redo.pop
      emit("redo #{@current.summary}")
    end
  end
end

lines = STDIN.each_line.map(&:chomp)
commands = lines.shift.to_i
editor = ImageEditor.new
commands.times do
  words = lines.shift.split(' ')
  if words.first == 'LOAD'
    count = words[1].to_i
    editor.load(lines.shift(count))
  else
    editor.execute(words)
  end
end
puts editor.output
