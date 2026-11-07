require 'set'
require 'fileutils'
require_relative 'rational'
require_relative 'intersections'
require_relative 'greiner_hormann'
require_relative 'rings'
require_relative 'render'

KINDS = %w[UNION INTERSECTION DIFFERENCE XOR CLIP AREA MOVE ROTATE MIRROR SNAP LOCATE RENDER].freeze
BINARY = KINDS.first(5).freeze
DEFINITIONS = %w[MOVE ROTATE MIRROR SNAP].freeze
WORD_COUNTS = KINDS.zip([3, 3, 3, 3, 3, 2, 5, 6, 5, 3, 4, 8]).to_h.freeze

class Rejected < StandardError; end

class Polygon
  attr_reader :name, :input_rings, :rings

  def initialize(name, input_rings)
    @name, @input_rings = name, input_rings
    outer = Rings.normalize(input_rings.first, true)
    holes = input_rings.drop(1).map { |ring| Rings.normalize(ring, false) }
    @rings = [outer, *holes.sort_by { |ring| RationalGeometry.point_key(ring.first) }]
  end
end

Region = Struct.new(:polygons, :operands)

module GeometryProcessing
  include RationalGeometry

  def digits?(word)
    /\A[0-9]{1,9}\z/.match?(word)
  end

  def integer_word?(word)
    /\A-?[0-9]{1,9}\z/.match?(word)
  end

  def valid_name?(word)
    /\A[a-z0-9_]{1,16}\z/.match?(word)
  end

  def records(filename)
    File.readlines("input/#{filename}", chomp: true, encoding: 'US-ASCII').each_with_index.filter_map do |line, index|
      [index + 1, line] unless line.empty? || line.start_with?('#')
    end
  end

  def parse_rings(content, end_line)
    result, position = [], 0
    while position < content.size
      number, line = content[position]
      words = line.split(' ')
      unless words.size == 2 && %w[OUTER HOLE].include?(words[0]) && digits?(words[1]) && words[1].to_i.positive?
        return [nil, number]
      end
      if (words[0] == 'OUTER' && !result.empty?) || (words[0] == 'HOLE' && result.empty?)
        return [nil, number]
      end
      count = words[1].to_i
      position += 1
      vertices = []
      count.times do
        return [nil, end_line] if position == content.size
        number, line = content[position]
        coordinates = line.split(' ')
        return [nil, number] unless coordinates.size == 2 && coordinates.all? { |word| integer_word?(word) }
        vertices << coordinates.map { |word| word.to_i(10) }
        position += 1
      end
      result << vertices
    end
    result.empty? ? [nil, end_line] : [result, nil]
  end

  def check_ring(ring, number)
    count = ring.size
    return "too_few_vertices ring #{number}" if count < 3
    ring.each do |point|
      unless point.all? { |coordinate| coordinate.between?(0, 1000) }
        return "out_of_range ring #{number} #{point_text(point)}"
      end
    end
    seen = Set.new
    ring.each do |point|
      return "duplicate_vertex ring #{number} #{point_text(point)}" if seen.include?(point)
      seen.add(point)
    end
    ring.each_with_index do |point, index|
      if cross(ring[index - 1], point, ring[(index + 1) % count]).zero?
        return "collinear ring #{number} #{point_text(point)}"
      end
    end
    edges = Rings.edges(ring)
    count.times do |first|
      ((first + 2)...count).each do |second|
        next if first.zero? && second == count - 1
        a, b = edges[first]
        c, d = edges[second]
        if Intersections.touch?(a, b, c, d)
          return "self_intersection ring #{number} #{segment_text(a, b)} #{segment_text(c, d)}"
        end
      end
    end
    nil
  end

  def check_polygon(sequence)
    sequence.each_with_index do |ring, index|
      error = check_ring(ring, index + 1)
      return error if error
    end
    edge_lists = sequence.map { |ring| Rings.edges(ring) }
    sequence.size.times do |first|
      ((first + 1)...sequence.size).each do |second|
        edge_lists[first].each do |a, b|
          edge_lists[second].each do |c, d|
            if Intersections.touch?(a, b, c, d)
              return "rings_touch rings #{first + 1} #{second + 1} #{segment_text(a, b)} #{segment_text(c, d)}"
            end
          end
        end
      end
    end
    sequence.drop(1).each_with_index do |hole, index|
      return "hole_outside ring #{index + 2} #{point_text(hole.first)}" unless Rings.inside?(sequence.first, hole.first)
    end
    (1...sequence.size).each do |first|
      ((first + 1)...sequence.size).each do |second|
        point = if Rings.inside?(sequence[first], sequence[second].first)
                  sequence[second].first
                elsif Rings.inside?(sequence[second], sequence[first].first)
                  sequence[first].first
                end
        return "hole_in_hole rings #{first + 1} #{second + 1} #{point_text(point)}" if point
      end
    end
    nil
  end

  def arguments_valid?(words)
    kind = words.first
    return false unless words.size == WORD_COUNTS[kind]
    return true if BINARY.include?(kind) || kind == 'AREA'
    case kind
    when 'SNAP'
      valid_name?(words[2])
    when 'LOCATE'
      words.drop(2).all? { |word| integer_word?(word) && word.to_i.between?(0, 1000) }
    when 'MOVE'
      valid_name?(words[4]) && words[2, 2].all? { |word| integer_word?(word) && word.to_i.between?(-1000, 1000) }
    when 'ROTATE'
      valid_name?(words[5]) && words[2, 3].all? { |word| integer_word?(word) } &&
        words[2].to_i.between?(0, 1000) && words[3].to_i.between?(0, 1000) && words[4].to_i.between?(1, 3)
    when 'MIRROR'
      valid_name?(words[4]) && %w[x y].include?(words[2]) && integer_word?(words[3]) && words[3].to_i.between?(0, 1000)
    when 'RENDER'
      return false unless words.drop(2).all? { |word| integer_word?(word) }
      x0, y0, width, height, columns, rows = words.drop(2).map(&:to_i)
      x0 >= 0 && y0 >= 0 && width.between?(1, 100) && height.between?(1, 100) &&
        columns.between?(1, 100) && rows.between?(1, 60) &&
        x0 + width * columns <= 1000 && y0 + height * rows <= 1000
    end
  end

  def general_position(first, second)
    first_vertices, second_vertices = first.rings.flatten(1), second.rings.flatten(1)
    second_set = second_vertices.to_set
    first_vertices.each do |point|
      return "shared_vertex #{point_text(point)}" if second_set.include?(point)
    end
    first_edges = first.rings.flat_map { |ring| Rings.edges(ring) }
    second_edges = second.rings.flat_map { |ring| Rings.edges(ring) }
    first_edges.each do |a, b|
      second_edges.each do |c, d|
        return "overlapping_edges #{segment_text(a, b)} #{segment_text(c, d)}" if Intersections.overlap?(a, b, c, d)
      end
    end
    [[first, first_vertices, second, second_edges], [second, second_vertices, first, first_edges]].each do |source, vertices, other, edges|
      vertices.each do |point|
        edges.each do |a, b|
          if Intersections.on_segment?(point, a, b)
            return "vertex_on_edge #{source.name} #{point_text(point)} #{other.name} #{segment_text(a, b)}"
          end
        end
      end
    end
    nil
  end

  def transformed_rings(polygon, words)
    polygon.input_rings.map do |ring|
      ring.map do |x, y|
        case words[0]
        when 'MOVE'
          x, y = x + words[2].to_i, y + words[3].to_i
        when 'ROTATE'
          cx, cy, turns = words[2, 3].map(&:to_i)
          turns.times { x, y = cx - (y - cy), cy + (x - cx) }
        when 'MIRROR'
          if words[2] == 'x'
            x = 2 * words[3].to_i - x
          else
            y = 2 * words[3].to_i - y
          end
        end
        [x, y]
      end
    end
  end

  def rounded_rings(polygon)
    polygon.map { |ring| ring.map { |point| point.map { |value| (Rational(value) + Rational(1, 2)).floor } } }
  end

  def total_area(polygons)
    total = 0.0
    polygons.each { |polygon| polygon.each { |ring| total += Rings.area(ring) } }
    total
  end

  def binary_result(kind, first, second)
    graph = GreinerHormann::Graph.new(first.rings, second.rings)
    intersection = Rings.assemble(graph.traverse(false, false))
    union = Rings.assemble(graph.traverse(true, true))
    polygons = case kind
               when 'UNION' then union
               when 'INTERSECTION', 'CLIP' then intersection
               else
                 difference = Rings.assemble(graph.traverse(true, false))
                 if kind == 'XOR'
                   reverse_graph = GreinerHormann::Graph.new(second.rings, first.rings)
                   difference.concat(Rings.assemble(reverse_graph.traverse(true, false)))
                   difference.sort_by! { |polygon| point_key(polygon.first.first) }
                 end
                 difference
               end
    relation = if !graph.crossings.empty?
                 'overlap'
               elsif graph.n_a == first.rings.size && graph.n_b.zero?
                 'within'
               elsif graph.n_b == second.rings.size && graph.n_a.zero?
                 'contains'
               elsif graph.n_a.zero? && graph.n_b.zero?
                 'disjoint'
               else
                 'overlap'
               end
    [Region.new(polygons, [first, second]), graph, relation, total_area(intersection) / total_area(union)]
  end

  def cyclic_equal?(first, second)
    return false unless first.size == second.size
    second.each_index.any? do |start|
      second[start] == first.first && first.each_index.all? { |index| first[index] == second[(start + index) % second.size] }
    end
  end

  def crosscheck_clip(first, window, polygons)
    clipped = []
    first.rings.each do |ring|
      points = ring.dup
      Rings.edges(window.rings.first).each do |edge_start, edge_end|
        replacement = []
        points.each_with_index do |current, index|
          previous = points[index - 1]
          a, b = cross(edge_start, edge_end, previous), cross(edge_start, edge_end, current)
          replacement << Intersections.clipping_point(previous, current, a, b) if a.positive? != b.positive?
          replacement << current if b.positive?
        end
        points = replacement
      end
      deduplicated = points.each_with_index.filter_map { |point, index| point if point != points[index - 1] }
      clipped << deduplicated if deduplicated.size >= 3
    end
    result_rings = polygons.flatten(1)
    matches = result_rings.size == clipped.size && result_rings.all? { |ring| clipped.any? { |other| cyclic_equal?(ring, other) } }
    [matches ? 'match' : 'mismatch', clipped.size, clipped.sum(&:size)]
  end

  def convex_hull(outer)
    ordered = outer.sort
    chains = [ordered, ordered.reverse].map do |sequence|
      chain = []
      sequence.each do |point|
        chain.pop while chain.size >= 2 && cross(chain[-2], chain[-1], point) <= 0
        chain << point
      end
      chain
    end
    chains[0][0...-1] + chains[1][0...-1]
  end

  def property_lines(polygon, area)
    orientations = polygon.input_rings.map do |ring|
      double_area = Rings.edges(ring).sum { |a, b| a[0] * b[1] - b[0] * a[1] }
      double_area.positive? ? 'ccw' : 'cw'
    end
    reflex = 0
    polygon.rings.each do |ring|
      ring.each_with_index { |point, index| reflex += 1 if cross(ring[index - 1], point, ring[(index + 1) % ring.size]).negative? }
    end
    hull = convex_hull(polygon.rings.first)
    double_area = Rings.edges(hull).sum { |a, b| a[0] * b[1] - b[0] * a[1] }
    hull_area = real(Rational(double_area, 2))
    ["input #{orientations.join(' ')}", "reflex #{reflex}",
     format('hull %d %.3f solidity %.6f', hull.size, hull_area, area / hull_area)]
  end

  def locate(polygons, point)
    polygons.each_with_index do |polygon, index|
      return "boundary outer #{index + 1}" if Rings.boundary?(polygon.first, point)
      polygon.drop(1).each_with_index do |ring, hole|
        return "boundary hole #{index + 1} #{hole + 1}" if Rings.boundary?(ring, point)
      end
    end
    polygons.each_with_index do |polygon, index|
      if Rings.inside?(polygon.first, point) && polygon.drop(1).none? { |ring| Rings.inside?(ring, point) }
        return "inside polygon #{index + 1}"
      end
    end
    'outside'
  end

  def operand_location(polygon, point)
    return 'boundary' if polygon.rings.any? { |ring| Rings.boundary?(ring, point) }
    Rings.interior?(polygon.rings, point) ? 'inside' : 'outside'
  end
end

class Registry
  include GeometryProcessing
  attr_reader :used, :polygons, :invalid, :block_count, :valid_blocks

  def initialize
    @used, @polygons, @invalid = Set.new, {}, []
    @block_count = @valid_blocks = 0
    lines, position = records('polygons.txt'), 0
    while position < lines.size
      start_line, header = lines[position]
      name = header.split(' ')[1]
      position += 1
      content = []
      until lines[position][1] == 'END'
        content << lines[position]
        position += 1
      end
      end_line = lines[position][0]
      position += 1
      @block_count += 1
      if @used.include?(name)
        @invalid << [name, "duplicate_name line #{start_line}"]
        next
      end
      @used.add(name)
      sequence, error_line = parse_rings(content, end_line)
      if error_line
        @invalid << [name, "format line #{error_line}"]
        next
      end
      error = check_polygon(sequence)
      if error
        @invalid << [name, error]
        next
      end
      @polygons[name] = Polygon.new(name, sequence)
      @valid_blocks += 1
    end
  end

  def resolve(name)
    raise Rejected, "unknown_polygon #{name}" unless @used.include?(name)
    raise Rejected, "invalid_polygon #{name}" unless @polygons.key?(name)
    @polygons[name]
  end

  def define(polygon)
    @used.add(polygon.name)
    @polygons[polygon.name] = polygon
  end
end

class ResultValues
  include RationalGeometry
  attr_reader :area, :ring_count, :hole_count, :vertex_count

  def initialize(polygons, first, second = nil)
    @polygon_count, @ring_items, @origins = polygons.size, [], [0, 0, 0]
    @area = @perimeter = 0.0
    first_vertices = first.rings.flatten(1).to_set
    second_vertices = second ? second.rings.flatten(1).to_set : Set.new
    vertices, sx, sy = [], 0.0, 0.0
    polygons.each_with_index do |polygon, polygon_index|
      polygon.each_with_index do |ring, hole_index|
        area = Rings.area(ring)
        @area += area
        @perimeter += Rings.perimeter(ring)
        @ring_items << [polygon_index + 1, hole_index, ring, area]
        vertices.concat(ring)
        Rings.edges(ring).each do |a, b|
          origin = first_vertices.include?(a) ? 0 : second_vertices.include?(a) ? 1 : 2
          @origins[origin] += 1
          x1, y1 = a.map { |value| real(value) }
          x2, y2 = b.map { |value| real(value) }
          c = x1 * y2 - x2 * y1
          sx += (x1 + x2) * c
          sy += (y1 + y2) * c
        end
      end
    end
    @ring_count = @ring_items.size
    @hole_count = @ring_count - @polygon_count
    @vertex_count = vertices.size
    unless vertices.empty?
      @low = [vertices.map(&:first).min, vertices.map(&:last).min]
      @high = [vertices.map(&:first).max, vertices.map(&:last).max]
      @centroid = [sx / (6.0 * @area), sy / (6.0 * @area)]
    end
  end

  def lines
    result = [format('polygons %d rings %d holes %d vertices %d area %.3f', @polygon_count, @ring_count, @hole_count, @vertex_count, @area)]
    @ring_items.each do |polygon, hole, ring, area|
      prefix = hole.zero? ? "outer #{polygon}" : "hole #{polygon} #{hole}"
      result << "#{prefix} #{ring.size} #{format('%.3f', area)} #{ring.map { |point| point_text(point) }.join(' ')}"
    end
    if @low
      result << "bbox #{point_text(@low)} #{point_text(@high)}"
      result << format('centroid (%.3f,%.3f)', *@centroid)
    else
      result.concat(['bbox none', 'centroid none'])
    end
    result << format('perimeter %.3f', @perimeter)
    result << "origins a #{@origins[0]} b #{@origins[1]} crossing #{@origins[2]}"
    result
  end
end

class Processor
  include GeometryProcessing

  def initialize
    @registry = Registry.new
    @operations = records('operations.txt').map(&:last)
    @regions, @results, @drawings, @rejected_operations = {}, [], [], []
    @areas = ['operation,rings,holes,vertices,area']
    @kind_totals, @kind_succeeded = Hash.new(0), Hash.new(0)
    @succeeded = @defined = @crossings = 0
  end

  def resolve_target(word)
    if word.start_with?('@')
      suffix = word[1..]
      raise Rejected, "bad_target #{word}" unless digits?(suffix) && @regions.key?(suffix.to_i)
      @regions[suffix.to_i]
    else
      Region.new([@registry.resolve(word).rings], nil)
    end
  end

  def check_operation(words)
    kind = words.first
    raise Rejected, "unknown_operation #{kind}" unless WORD_COUNTS.key?(kind)
    raise Rejected, 'bad_arguments' unless arguments_valid?(words)
    checked = {}
    if BINARY.include?(kind)
      checked[:a] = @registry.resolve(words[1])
      checked[:b] = @registry.resolve(words[2])
    elsif %w[AREA MOVE ROTATE MIRROR].include?(kind)
      checked[:a] = @registry.resolve(words[1])
    else
      checked[:target] = resolve_target(words[1])
    end
    if DEFINITIONS.include?(kind) && @registry.used.include?(words.last)
      raise Rejected, "duplicate_name #{words.last}"
    end
    if kind == 'SNAP' && checked[:target].polygons.size != 1
      raise Rejected, "not_single #{words[1]}"
    end
    if kind == 'CLIP'
      window = checked[:b].rings
      raise Rejected, "not_convex #{words[2]}" if window.size > 1
      ring = window.first
      if ring.each_with_index.any? { |point, index| cross(ring[index - 1], point, ring[(index + 1) % ring.size]) <= 0 }
        raise Rejected, "not_convex #{words[2]}"
      end
    end
    if BINARY.include?(kind)
      error = general_position(checked[:a], checked[:b])
      raise Rejected, error if error
    end
    if %w[MOVE ROTATE MIRROR].include?(kind)
      sequence = transformed_rings(checked[:a], words)
      unless sequence.all? { |ring| ring.all? { |point| point.all? { |coordinate| coordinate.between?(0, 1000) } } }
        raise Rejected, "out_of_range #{words.last}"
      end
      checked[:defined] = Polygon.new(words.last, sequence)
    elsif kind == 'SNAP'
      sequence = rounded_rings(checked[:target].polygons.first)
      error = check_polygon(sequence)
      raise Rejected, "invalid_result #{error}" if error
      checked[:defined] = Polygon.new(words.last, sequence)
    end
    checked
  end

  def record_region(number, line, words, checked)
    kind = words.first
    @results << "op #{number} #{line}"
    if BINARY.include?(kind)
      first, second = checked.values_at(:a, :b)
      region, graph, relation, iou = binary_result(kind, first, second)
      @results << format('relation %s iou %.6f', relation, iou)
      @results << "crossings #{graph.crossings.size}"
      @crossings += graph.crossings.size
      graph.crossings.each { |crossing| @results << "crossing #{point_text(crossing.point)} #{crossing.first.entering ? 'in' : 'out'}" }
    else
      first = DEFINITIONS.include?(kind) ? checked[:defined] : checked[:a]
      second = nil
      region = Region.new([first.rings], nil)
    end
    @regions[number] = region
    values = ResultValues.new(region.polygons, first, second)
    @results.concat(values.lines)
    @results.concat(property_lines(first, values.area)) unless BINARY.include?(kind)
    if kind == 'CLIP'
      decision, count, vertices = crosscheck_clip(first, second, region.polygons)
      @results << "crosscheck #{decision} rings #{count} vertices #{vertices}"
    end
    identifier = "#{number}:#{words.join(':')}"
    @areas << "#{identifier},#{values.ring_count},#{values.hole_count},#{values.vertex_count},#{format('%.3f', values.area)}"
  end

  def record_location(number, line, words, target)
    point = words.drop(2).map(&:to_i)
    @results << "op #{number} #{line}"
    @results << "location #{locate(target.polygons, point)}"
    if target.operands
      first, second = target.operands
      @results << "operands a #{operand_location(first, point)} b #{operand_location(second, point)}"
    end
  end

  def record_render(number, words, target)
    parameters = words.drop(2).map(&:to_i)
    operands = target.operands&.map(&:rings)
    lines, counts = Render.grid(target.polygons, operands, *parameters)
    columns, rows = parameters.last(2)
    @drawings << "render #{number} #{words[1]} cols #{columns} rows #{rows} result #{counts['#']} a #{counts['a']} b #{counts['b']} both #{counts['+']}"
    @drawings.concat(lines)
  end

  def process
    @operations.each_with_index do |line, index|
      number, words = index + 1, line.split(' ')
      kind = words.first
      @kind_totals[kind] += 1 if KINDS.include?(kind)
      begin
        checked = check_operation(words)
      rescue Rejected => error
        @rejected_operations << [number, error.message]
        next
      end
      @succeeded += 1
      @kind_succeeded[kind] += 1
      if DEFINITIONS.include?(kind)
        @registry.define(checked[:defined])
        @defined += 1
      end
      case kind
      when 'RENDER' then record_render(number, words, checked[:target])
      when 'LOCATE' then record_location(number, line, words, checked[:target])
      else record_region(number, line, words, checked)
      end
    end
    @results << "summary polygons #{@registry.block_count} valid #{@registry.valid_blocks} invalid #{@registry.invalid.size} defined #{@defined}"
    @results << "summary operations #{@operations.size} succeeded #{@succeeded} rejected #{@rejected_operations.size}"
    @results << "summary crossings #{@crossings}"
    KINDS.each { |kind| @results << "kind #{kind} #{@kind_totals[kind]} #{@kind_succeeded[kind]}" }
  end

  def write
    rejections = ["rejections #{@registry.invalid.size + @rejected_operations.size}"]
    @registry.invalid.each { |name, reason| rejections << "polygon #{name} #{reason}" }
    @rejected_operations.each { |number, reason| rejections << "op #{number} #{reason}" }
    FileUtils.mkdir_p('output')
    {'results.txt' => @results, 'areas.csv' => @areas, 'render.txt' => @drawings, 'rejections.txt' => rejections}.each do |filename, lines|
      File.write("output/#{filename}", lines.empty? ? '' : lines.join("\n") + "\n", encoding: 'US-ASCII')
    end
  end
end

if $PROGRAM_NAME == __FILE__
  processor = Processor.new
  processor.process
  processor.write
end
