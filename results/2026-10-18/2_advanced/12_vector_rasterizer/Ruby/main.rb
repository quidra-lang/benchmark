# frozen_string_literal: true

require 'set'
require_relative 'canvas'
require_relative 'primitives'
require_relative 'fill'
require_relative 'clipping'
require_relative 'ppm_writer'

class VectorRasterizer
  Node = Struct.new(:keyword, :arguments, :line, :body)
  PEN_COMMANDS = %w[LINE RECT CIRCLE ELLIPSE POLYLINE POLYGON PATH].freeze
  BRUSH_COMMANDS = %w[FILLRECT FILLCIRCLE FILLELLIPSE FILLPOLYGON FILLPATH FLOOD TEXT].freeze
  STATE_COMMANDS = %w[TRANSLATE SCALE ROTATE SAVE RESTORE CLIP NOCLIP USE].freeze
  COMMANDS = (PEN_COMMANDS + BRUSH_COMMANDS + STATE_COMMANDS + ['ERASE']).freeze
  ERRORS = %w[unknown_command bad_arguments unknown_style unknown_symbol unknown_glyph bad_value stack_empty].freeze
  PATH_ARITIES = { 'M' => 2, 'L' => 2, 'H' => 1, 'V' => 1, 'Q' => 4, 'C' => 6, 'Z' => 0 }.freeze

  def read_styles
    @colors = {}
    @pens = {}
    @brushes = {}
    File.readlines('input/styles.txt', chomp: true).each do |line|
      next if line.empty? || line.start_with?('#')

      kind, name, *values = line.split(' ')
      case kind
      when 'color'
        @colors[name] = values.map(&:to_i)
      when 'pen'
        @pens[name] = { width: values[0].to_i, color: values[1], on: values[2].to_i, off: values[3].to_i }
      when 'brush'
        @brushes[name] = { colors: [values[0]], rule: values[1] }
      when 'gradient'
        @brushes[name] = { colors: values.take(2), axis: values[2], rule: values[3] }
      end
    end
  end

  def read_font
    lines = File.readlines('input/font.txt', chomp: true)
    _, width, height = lines.first.split(' ')
    @glyph_width = width.to_i
    @glyph_height = height.to_i
    @glyphs = {}
    index = 1
    while index < lines.length
      character = lines[index].split(' ')[1]
      dots = []
      @glyph_height.times do |y|
        lines[index + y + 1].each_char.with_index { |dot, x| dots << [x, y] if dot == '#' }
      end
      @glyphs[character] = dots
      index += @glyph_height + 1
    end
  end

  def read_scene
    @layers = []
    @symbols = {}
    parents = []
    block = nil
    body = nil
    File.readlines('input/scene.txt', chomp: true).each_with_index do |line, index|
      text = line.strip
      next if text.empty? || text.start_with?('#')

      keyword, *arguments = text.split(' ')
      case keyword
      when 'CANVAS'
        @width, @height = arguments.take(2).map(&:to_i)
        @background = arguments[2]
        @screen = [0, 0, @width - 1, @height - 1]
      when 'LAYER', 'SYMBOL'
        block = { name: arguments[0], body: [], end_line: nil }
        body = block[:body]
        if keyword == 'LAYER'
          @layers << Canvas::Layer.new(number: @layers.length + 1, name: arguments[0],
                                       opacity: arguments[1].to_i, mode: arguments[2], body: body,
                                       pixels: Array.new(@width * @height), commands: 0, errors: 0)
        else
          @symbols[arguments[0]] = block
        end
      when 'END'
        block[:end_line] = index + 1
      when 'REPEAT'
        repetition = Node.new(keyword, arguments, index + 1, [])
        body << repetition
        parents << body
        body = repetition.body
      when 'ENDREPEAT'
        body = parents.pop
      else
        body << Node.new(keyword, arguments, index + 1, nil)
      end
    end
  end

  def transform(point)
    x, y = point
    a, b, c, d, e, f = @matrix
    [a * x + b * y + e, c * x + d * y + f]
  end

  def device_rectangle(values)
    first = transform(values.take(2))
    last = transform(values.drop(2))
    [[first[0], last[0]].min, [first[1], last[1]].min, [first[0], last[0]].max, [first[1], last[1]].max]
  end

  def translate(dx, dy)
    a, b, c, d = @matrix
    @matrix[4] += a * dx + b * dy
    @matrix[5] += c * dx + d * dy
  end

  def snapshot
    [@matrix.dup, @clip.dup, @stack.map { |matrix, clip| [matrix.dup, clip.dup] }]
  end

  def restore_snapshot(saved)
    @matrix = saved[0].dup
    @clip = saved[1].dup
    @stack = saved[2].map { |matrix, clip| [matrix.dup, clip.dup] }
  end

  def integer?(word)
    /\A-?[0-9]+\z/.match?(word)
  end

  def integer_tail?(arguments, count, start = 0)
    arguments.length == count && arguments.drop(start).all? { |word| integer?(word) }
  end

  def parse_path(words)
    return nil if words.empty?

    commands = []
    index = 0
    needs_move = true
    while index < words.length
      kind = words[index]
      upper = kind.upcase
      return nil unless kind.length == 1 && PATH_ARITIES.key?(upper)
      return nil if needs_move && upper != 'M'

      arity = PATH_ARITIES.fetch(upper)
      values = words[(index + 1), arity]
      return nil unless values.length == arity && values.all? { |word| integer?(word) }

      commands << [kind, values.map(&:to_i)]
      needs_move = upper == 'Z'
      index += arity + 1
    end
    commands
  end

  def valid_form?(node)
    args = node.arguments
    case node.keyword
    when 'LINE', 'RECT', 'FILLRECT', 'ELLIPSE', 'FILLELLIPSE'
      integer_tail?(args, 5, 1)
    when 'CIRCLE', 'FILLCIRCLE'
      integer_tail?(args, 4, 1)
    when 'POLYLINE', 'POLYGON', 'FILLPOLYGON'
      args.length >= 2 && args.drop(1).all? { |word| integer?(word) } && args.length == 2 + 2 * args[1].to_i
    when 'PATH', 'FILLPATH'
      args.length >= 2 && integer?(args[1]) && !parse_path(args.drop(2)).nil?
    when 'FLOOD', 'USE'
      integer_tail?(args, 3, 1)
    when 'TEXT'
      args.length == 5 && integer?(args[1]) && integer?(args[2])
    when 'ERASE', 'CLIP'
      integer_tail?(args, 4)
    when 'TRANSLATE', 'SCALE'
      integer_tail?(args, 2)
    when 'ROTATE'
      integer_tail?(args, 1)
    when 'SAVE', 'RESTORE', 'NOCLIP'
      args.empty?
    end
  end

  def bad_value?(node)
    args = node.arguments
    case node.keyword
    when 'CIRCLE', 'FILLCIRCLE'
      args[3].to_i < 1
    when 'ELLIPSE', 'FILLELLIPSE'
      args[3].to_i < 1 || args[4].to_i < 1
    when 'POLYLINE', 'POLYGON', 'FILLPOLYGON'
      args[1].to_i < (node.keyword == 'POLYLINE' ? 2 : 3)
    when 'PATH', 'FILLPATH'
      !args[1].to_i.between?(1, 32)
    when 'FLOOD'
      !Clipping.inside?(transform(args.drop(1).map(&:to_i)), @clip)
    when 'TEXT'
      !%w[left center right].include?(args[3])
    when 'SCALE'
      args.any? { |word| word.to_i.zero? }
    when 'CLIP'
      Clipping.empty?(Clipping.intersection(device_rectangle(args.map(&:to_i)), @clip))
    else
      false
    end
  end

  def error_for(node)
    keyword = node.keyword
    name = node.arguments.first
    return 'unknown_command' unless COMMANDS.include?(keyword)
    return 'bad_arguments' unless valid_form?(node)
    return 'unknown_style' if PEN_COMMANDS.include?(keyword) && !@pens.key?(name)
    return 'unknown_style' if BRUSH_COMMANDS.include?(keyword) && !@brushes.key?(name)
    if keyword == 'USE' && (!@symbols.key?(name) || @symbols[name][:end_line] > node.line)
      return 'unknown_symbol'
    end
    if keyword == 'TEXT' && node.arguments[4].each_char.any? { |character| character != '_' && !@glyphs.key?(character) }
      return 'unknown_glyph'
    end
    return 'bad_value' if bad_value?(node)
    return 'stack_empty' if keyword == 'RESTORE' && @stack.empty?

    nil
  end

  def execute_state(node)
    values = node.arguments.map(&:to_i)
    case node.keyword
    when 'TRANSLATE'
      translate(*values)
    when 'SCALE'
      @matrix[0] *= values[0]
      @matrix[2] *= values[0]
      @matrix[1] *= values[1]
      @matrix[3] *= values[1]
    when 'ROTATE'
      (values[0] % 4).times do
        a, b, c, d = @matrix
        @matrix[0, 4] = [b, -a, d, -c]
      end
    when 'SAVE'
      @stack << [@matrix.dup, @clip.dup]
    when 'RESTORE'
      @matrix, @clip = @stack.pop
    when 'CLIP'
      @clip = Clipping.intersection(device_rectangle(values), @clip)
    when 'NOCLIP'
      @clip = @screen.dup
    when 'USE'
      name = node.arguments[0]
      @symbol_uses[name] += 1
      saved = snapshot
      translate(values[1], values[2])
      execute_block(@symbols.fetch(name)[:body])
      restore_snapshot(saved)
    end
  end

  def subpaths(commands, segments)
    paths = []
    current = [0, 0]
    start = [0, 0]
    commands.each do |kind, values|
      upper = kind.upcase
      if upper == 'Z'
        paths.last[:closed] = true
        current = start.dup
        next
      end
      relative = kind != upper
      points = case upper
               when 'H'
                 [[relative ? current[0] + values[0] : values[0], current[1]]]
               when 'V'
                 [[current[0], relative ? current[1] + values[0] : values[0]]]
               else
                 values.each_slice(2).map { |x, y| relative ? [current[0] + x, current[1] + y] : [x, y] }
               end
      devices = points.map { |point| transform(point) }
      if upper == 'M'
        paths << { points: devices, closed: false }
        start = points.last.dup
      elsif upper == 'Q' || upper == 'C'
        controls = [paths.last[:points].last] + devices
        paths.last[:points].concat(Primitives.bezier(controls, segments).drop(1))
      else
        paths.last[:points].concat(devices)
      end
      current = points.last.dup
    end
    paths
  end

  def path_segments(paths)
    paths.flat_map do |path|
      points = path[:points]
      segments = points.each_cons(2).to_a
      segments << [points.last, points.first] if path[:closed]
      segments
    end
  end

  def add_square(coverage, point, width)
    Primitives.square(point, width) { |pixel| coverage.add(pixel) if Clipping.inside?(pixel, @clip) }
  end

  def pen_coverage(segments, pen)
    coverage = Set.new
    position = 0
    segments.each do |first, last|
      clipped = Clipping.segment(first, last, @clip)
      next if clipped.nil?

      Primitives.line(*clipped) do |point|
        if pen[:off].zero? || position % (pen[:on] + pen[:off]) < pen[:on]
          add_square(coverage, point, pen[:width])
        end
        position += 1
      end
    end
    coverage
  end

  def rectangle_pixels(rectangle)
    rectangle = Clipping.intersection(rectangle, @clip)
    coverage = Set.new
    rectangle[1].upto(rectangle[3]) do |y|
      rectangle[0].upto(rectangle[2]) { |x| coverage.add([x, y]) }
    end
    coverage
  end

  def text_coverage(arguments)
    _, x, y, alignment, text = arguments
    x = x.to_i
    y = y.to_i
    extent = text.length * (@glyph_width + 1) - 1
    x -= extent / 2 if alignment == 'center'
    x -= extent - 1 if alignment == 'right'
    coverage = Set.new
    text.each_char.with_index do |character, index|
      next if character == '_'

      origin = x + index * (@glyph_width + 1)
      @glyphs.fetch(character).each do |dx, dy|
        rectangle = device_rectangle([origin + dx, y + dy, origin + dx + 1, y + dy + 1])
        rectangle[2] -= 1
        rectangle[3] -= 1
        coverage.merge(rectangle_pixels(rectangle))
      end
    end
    coverage
  end

  def drawing_coverage(node)
    keyword = node.keyword
    name = node.arguments.first
    values = node.arguments.drop(1).map(&:to_i)
    pen = @pens[name]
    brush = @brushes[name]
    case keyword
    when 'LINE'
      pen_coverage([[transform(values.take(2)), transform(values.drop(2))]], pen)
    when 'RECT', 'FILLRECT'
      rectangle = device_rectangle(values)
      return rectangle_pixels(rectangle) if keyword == 'FILLRECT'

      x0, y0, x1, y1 = rectangle
      points = [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
      pen_coverage(path_segments([{ points: points, closed: true }]), pen)
    when 'POLYLINE', 'POLYGON', 'FILLPOLYGON'
      points = values.drop(1).each_slice(2).map { |point| transform(point) }
      if keyword == 'FILLPOLYGON'
        Fill.polygons([Clipping.polygon(points, @clip)], brush[:rule], @clip)
      else
        pen_coverage(path_segments([{ points: points, closed: keyword == 'POLYGON' }]), pen)
      end
    when 'CIRCLE', 'FILLCIRCLE', 'ELLIPSE', 'FILLELLIPSE'
      center = transform(values.take(2))
      circle = keyword.end_with?('CIRCLE')
      rx = values[2]
      ry = circle ? rx : values[3]
      a, b, c, d = @matrix
      rx, ry = a.abs * rx + b.abs * ry, c.abs * rx + d.abs * ry
      points = circle && rx == ry ? Primitives.circle(rx) : Primitives.ellipse(rx, ry)
      return Fill.shape(points, center, @clip) if BRUSH_COMMANDS.include?(keyword)

      coverage = Set.new
      points.each { |dx, dy| add_square(coverage, [center[0] + dx, center[1] + dy], pen[:width]) }
      coverage
    when 'PATH', 'FILLPATH'
      paths = subpaths(parse_path(node.arguments.drop(2)), values[0])
      if keyword == 'PATH'
        pen_coverage(path_segments(paths), pen)
      else
        sequences = paths.map { |path| Clipping.polygon(path[:points], @clip) }
        Fill.polygons(sequences, brush[:rule], @clip)
      end
    when 'FLOOD'
      Fill.flood(@layer, transform(values), @clip, @width)
    when 'TEXT'
      text_coverage(node.arguments)
    when 'ERASE'
      pixels = rectangle_pixels(device_rectangle(node.arguments.map(&:to_i)))
      pixels.select { |x, y| @layer.pixels[y * @width + x] }.to_set
    end
  end

  def bounds(pixels)
    return nil if pixels.empty?

    xs = pixels.map(&:first)
    ys = pixels.map(&:last)
    [xs.min, ys.min, xs.max, ys.max]
  end

  def box_text(box)
    box ? box.join(' ') : 'none'
  end

  def brush_color(brush, point, box)
    first = @colors.fetch(brush[:colors][0])
    return first if brush[:colors].length == 1

    axis = brush[:axis] == 'x' ? 0 : 1
    distance = point[axis] - box[axis]
    length = box[axis + 2] - box[axis]
    return first if length.zero?

    last = @colors.fetch(brush[:colors][1])
    4.times.map { |component| first[component] + Canvas.round((last[component] - first[component]) * distance, length) }
  end

  def paint(node, coverage, box)
    name = node.arguments.first
    if node.keyword == 'ERASE'
      coverage.each { |x, y| @layer.pixels[y * @width + x] = nil }
      return
    end
    pen = PEN_COMMANDS.include?(node.keyword)
    (pen ? @used_pens : @used_brushes).add(name)
    coverage.each do |point|
      color = pen ? @colors.fetch(@pens.fetch(name)[:color]) : brush_color(@brushes.fetch(name), point, box)
      @layer.pixels[point[1] * @width + point[0]] = Canvas::Pixel.new(color, node.line)
    end
  end

  def execute_command(node)
    keyword = node.keyword
    statistics = @keywords[keyword]
    statistics[0] += 1
    @layer.commands += 1
    prefix = "cmd #{@log.length + 1} line #{node.line} #{keyword}"
    error = error_for(node)
    if error
      @error_counts[error] += 1
      @layer.errors += 1
      statistics[1] += 1
      @counts[:errors] += 1
      @log << "#{prefix} error #{error}"
    elsif STATE_COMMANDS.include?(keyword)
      @counts[:state] += 1
      @log << "#{prefix} ok"
      execute_state(node)
    else
      coverage = drawing_coverage(node)
      box = bounds(coverage)
      paint(node, coverage, box)
      statistics[2] += coverage.length
      @counts[:drawing] += 1
      @counts[keyword == 'ERASE' ? :erased : :painted] += coverage.length
      @log << "#{prefix} pixels #{coverage.length} box #{box_text(box)}"
    end
  end

  def execute_block(body)
    body.each do |node|
      if node.keyword == 'REPEAT'
        count, dx, dy = node.arguments.map(&:to_i)
        saved = snapshot
        count.times do |index|
          restore_snapshot(saved)
          translate(index * dx, index * dy)
          execute_block(node.body)
        end
        restore_snapshot(saved)
      else
        execute_command(node)
      end
    end
  end

  def layer_lines
    visible = Array.new(@layers.length, 0)
    opaque = Array.new(@width * @height, false)
    @layers.reverse_each do |layer|
      layer.pixels.each_index do |index|
        alpha = Canvas.alpha(layer, index)
        visible[layer.number - 1] += 1 if alpha.positive? && !opaque[index]
        opaque[index] = true if alpha == 255
      end
    end
    lines = ["layers #{@layers.length}"]
    @layers.each do |layer|
      pixels = layer.pixels.each_index.filter_map { |index| [index % @width, index / @width] if layer.pixels[index] }
      colors = layer.pixels.compact.map(&:color).tally
      lines << "layer #{layer.number} #{layer.name} opacity #{layer.opacity} mode #{layer.mode} commands #{layer.commands} errors #{layer.errors} pixels #{pixels.length} box #{box_text(bounds(pixels))} visible #{visible[layer.number - 1]} colors #{colors.length}"
      colors.sort_by { |color, count| [-count, color] }.take(5).each do |color, count|
        lines << "color #{color.join(' ')} pixels #{count}"
      end
    end
    lines
  end

  def summary_lines(image)
    lines = ["canvas #{@width} #{@height}", "background #{@colors.fetch(@background).take(3).join(' ')}",
             "layers #{@layers.length}", "symbols #{@symbols.length}", "commands #{@log.length}",
             "drawing #{@counts[:drawing]}", "state #{@counts[:state]}", "errors #{@counts[:errors]}"]
    ERRORS.each { |error| lines << "error #{error} #{@error_counts[error]}" }
    colors = image.tally
    lines.concat(["painted #{@counts[:painted]}", "erased #{@counts[:erased]}", "colors #{colors.length}"])
    colors.sort_by { |color, count| [-count, color] }.take(8).each_with_index do |(color, count), index|
      lines << "top #{index + 1} #{color.join(' ')} pixels #{count}"
    end
    @symbols.keys.sort.each { |name| lines << "symbol #{name} uses #{@symbol_uses[name]}" }
    @keywords.keys.sort.each do |keyword|
      executions, errors, pixels = @keywords[keyword]
      lines << "keyword #{keyword} executed #{executions} errors #{errors} pixels #{pixels}"
    end
    used_colors = Set.new([@background])
    @used_pens.each { |name| used_colors.add(@pens.fetch(name)[:color]) }
    @used_brushes.each { |name| used_colors.merge(@brushes.fetch(name)[:colors]) }
    used_symbols = @symbol_uses.select { |_, count| count.positive? }.keys.to_set
    unused = []
    [['color', @colors, used_colors], ['pen', @pens, @used_pens],
     ['brush', @brushes, @used_brushes], ['symbol', @symbols, used_symbols]].each do |kind, definitions, used|
      definitions.keys.sort.each { |name| unused << "unused #{kind} #{name}" unless used.include?(name) }
    end
    lines + ["unused #{unused.length}"] + unused
  end

  def probe_lines(image)
    @probes.each_with_index.map do |(kind, values), index|
      if kind == 'point'
        x, y = values
        pixel = y * @width + x
        stack = @layers.filter_map do |layer|
          "#{layer.number}:#{layer.pixels[pixel].line}" if Canvas.alpha(layer, pixel).positive?
        end
        "point #{index + 1} #{x} #{y} rgb #{image[pixel].join(' ')} layers #{stack.length} stack #{stack.empty? ? 'none' : stack.join(' ')}"
      else
        x0, y0, x1, y1 = values
        pixels = (y0..y1).flat_map { |y| (x0..x1).map { |x| y * @width + x } }
        count = pixels.length
        means = 3.times.map { |channel| pixels.sum { |pixel| image[pixel][channel] } / count }
        colors = pixels.map { |pixel| image[pixel] }.uniq.length
        cover = @layers.map { |layer| pixels.count { |pixel| Canvas.alpha(layer, pixel).positive? } }
        "area #{index + 1} #{values.join(' ')} pixels #{count} mean #{means.join(' ')} colors #{colors} cover #{cover.join(' ')}"
      end
    end
  end

  def write_lines(name, lines)
    File.binwrite("output/#{name}", lines.empty? ? '' : lines.join("\n") + "\n")
  end

  def run
    read_styles
    read_font
    read_scene
    @probes = File.readlines('input/probes.txt', chomp: true).drop(1).map do |line|
      kind, *values = line.split(' ')
      [kind, values.map(&:to_i)]
    end
    @log = []
    @counts = Hash.new(0)
    @error_counts = Hash.new(0)
    @symbol_uses = Hash.new(0)
    @keywords = Hash.new { |hash, key| hash[key] = [0, 0, 0] }
    @used_pens = Set.new
    @used_brushes = Set.new
    @layers.each do |layer|
      @layer = layer
      @matrix = [1, 0, 0, 1, 0, 0]
      @clip = @screen.dup
      @stack = []
      execute_block(layer.body)
    end
    image = Canvas.composite(@layers, @width, @height, @colors.fetch(@background))
    Dir.mkdir('output') unless Dir.exist?('output')
    PPMWriter.write(image, @width, @height)
    write_lines('commands.txt', @log)
    write_lines('layers.txt', layer_lines)
    write_lines('summary.txt', summary_lines(image))
    write_lines('probes.txt', probe_lines(image))
  end
end

VectorRasterizer.new.run
