# frozen_string_literal: true

require_relative 'pgm_reader'
require_relative 'threshold'
require_relative 'morphology'
require_relative 'labeling'
require_relative 'report'

class ImageRegionAnalysis
  DIRECTIONS = {
    4 => [[1, 0], [0, -1], [-1, 0], [0, 1]],
    8 => [[1, 0], [1, -1], [0, -1], [-1, -1], [-1, 0], [-1, 1], [0, 1], [1, 1]]
  }.freeze
  ORIENTATIONS = %w[none horizontal vertical falling rising].freeze
  SYMBOLS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
  COLUMNS = %w[image label class flags area x0 y0 x1 y1 cx cy mean variance min max contrast
               border perimeter chain straight diagonal turns compactness runs holes hole_area euler
               parent depth var_x var_y cov_xy hu1 orientation anisotropy extent mirror_lr mirror_tb
               hull_area solidity feret2 width2 elongation bays bay_area skeleton endpoints branches
               neighbor distance2 codes].freeze
  DECIMALS = { cx: 3, cy: 3, mean: 2, variance: 2, contrast: 2, compactness: 3,
               var_x: 3, var_y: 3, cov_xy: 3, hu1: 4, anisotropy: 3, extent: 3,
               mirror_lr: 3, mirror_tb: 3, solidity: 3, width2: 3, elongation: 3 }.freeze
  Settings = Struct.new(:connectivity, :threshold, :polarity, :operations, keyword_init: true)
  Condition = Struct.new(:feature, :operator, :value, :words, keyword_init: true)
  Rule = Struct.new(:name, :conditions, keyword_init: true)
  Hole = Struct.new(:number, :owner, :pixels, :box, keyword_init: true)
  Region = Struct.new(:number, :pixels, :values, :skeleton, :kept, :klass, :flags,
                      :neighbor, :distance2, keyword_init: true)

  def initialize
    @images = PGMReader.read
    read_parameters
    read_rules
    @threshold_lines = []
    @label_lines = []
    @region_lines = [COLUMNS.join(',')]
    @summary_lines = []
    @summaries = []
    @filter_dropped = Array.new(@filters.length, 0)
  end

  def rational(word)
    numerator, denominator = word.split('/').map(&:to_i)
    Rational(numerator, denominator || 1)
  end

  def read_parameters
    lines = File.readlines('input/params.txt', chomp: true).map(&:split)
    @otsu_top = lines[0][1].to_i
    @sweep_step = lines[1][1].to_i
    @isotropy = rational(lines[2][1])
    @bay_min = lines[3][1].to_i
    @elements = {}
    @settings = {}
    lines.drop(4).each do |fields|
      if fields[0] == 'element'
        width, height, ox, oy = fields[2, 4].map(&:to_i)
        offsets = []
        fields[6, height].each_with_index do |row, y|
          width.times { |x| offsets << [x - ox, y - oy] if row[x] == '#' }
        end
        @elements[fields[1]] = offsets
      else
        @settings[fields[1]] = Settings.new(connectivity: fields[2].to_i, threshold: fields[3],
                                            polarity: fields[4], operations: fields.drop(5))
      end
    end
  end

  def parse_conditions(words)
    words.each_slice(3).map do |feature, operator, value|
      Condition.new(feature: feature.to_sym, operator: operator,
                    value: feature == 'orientation' ? value : rational(value),
                    words: [feature, operator, value])
    end
  end

  def read_rules
    @filters = []
    @classes = []
    @flags = []
    File.readlines('input/rules.txt', chomp: true).each do |line|
      fields = line.split
      if fields[0] == 'filter'
        @filters << parse_conditions(fields.drop(1)).first
      else
        rule = Rule.new(name: fields[1], conditions: parse_conditions(fields.drop(2)))
        (fields[0] == 'class' ? @classes : @flags) << rule
      end
    end
    @class_names = @classes.map(&:name).uniq + ['other']
  end

  def position(x, y)
    return nil if x < 0 || x >= @width || y < 0 || y >= @height

    y * @width + x
  end

  def edge?(index)
    x, y = index % @width, index.div(@width)
    x.zero? || y.zero? || x == @width - 1 || y == @height - 1
  end

  def box(pixels)
    xs = pixels.map { |index| index % @width }
    ys = pixels.map { |index| index.div(@width) }
    [xs.min, ys.min, xs.max, ys.max]
  end

  def binarize(value)
    @image.pixels.map { |pixel| @setting.polarity == 'bright' ? pixel > value : pixel <= value }
  end

  def fill_holes(mask)
    background = mask.map { |foreground| !foreground }
    result = mask.dup
    Labeling.components(background, @width, @height, 12 - @setting.connectivity).each do |pixels|
      next if pixels.any? { |index| edge?(index) }

      pixels.each { |index| result[index] = true }
    end
    result
  end

  def prepare_binary
    @statistics = Threshold.analyze(@image)
    @method = %w[otsu isodata].include?(@setting.threshold) ? @setting.threshold : 'fixed'
    @threshold = case @method
                 when 'otsu' then @statistics.otsu
                 when 'isodata' then @statistics.isodata
                 else @setting.threshold.to_i
                 end
    @initial = binarize(@threshold)
    @binary = @initial
    @morph_records = []
    @setting.operations.each do |operation|
      if operation == 'fill'
        @binary = fill_holes(@binary)
      else
        kind, element = operation.split(':')
        @binary = Morphology.apply(@binary, kind, @elements.fetch(element), @width, @height)
      end
      @morph_records << [operation, @binary.count(true)]
    end
    @labeling = Labeling.label(@binary, @width, @height, @setting.connectivity)
    @labels = @labeling.labels
    @four = @setting.connectivity == 4 ? @labeling.groups.length : Labeling.components(@binary, @width, @height, 4).length
    @eight = @setting.connectivity == 8 ? @labeling.groups.length : Labeling.components(@binary, @width, @height, 8).length
  end

  def find_containment
    @holes = []
    @hole_map = Array.new(@binary.length, 0)
    background = @binary.map { |foreground| !foreground }
    Labeling.components(background, @width, @height, 12 - @setting.connectivity).each do |pixels|
      next if pixels.any? { |index| edge?(index) }

      number = @holes.length + 1
      owner = @labels[pixels.first - @width]
      @holes << Hole.new(number: number, owner: owner, pixels: pixels, box: box(pixels))
      pixels.each { |index| @hole_map[index] = number }
    end
    count = @labeling.groups.length
    @parents = Array.new(count + 1)
    @depths = Array.new(count + 1, 0)
    @children = Array.new(count + 1) { [] }
    @owned_holes = Array.new(count + 1) { [] }
    @holes.each { |hole| @owned_holes[hole.owner] << hole }
    @labeling.groups.each_with_index do |pixels, index|
      number = index + 1
      above = pixels.first >= @width ? @hole_map[pixels.first - @width] : 0
      parent = above.zero? ? nil : @holes[above - 1].owner
      @parents[number] = parent
      @depths[number] = @depths[parent] + 1 if parent
      @children[parent || 0] << number
    end
    @euler = count - @holes.length
    @bitquad = Labeling.bitquad(@binary, @width, @height, @setting.connectivity)
  end

  def containment_tree(number)
    children = @children[number]
    return number.to_s if children.empty?

    "#{number}(#{children.map { |child| containment_tree(child) }.join(' ')})"
  end

  def intensity_contrast(pixels, sum, area)
    background = {}
    pixels.each do |index|
      x, y = index % @width, index.div(@width)
      DIRECTIONS[8].each do |dx, dy|
        other = position(x + dx, y + dy)
        background[other] = true if other && @labels[other].zero?
      end
    end
    return Rational(0, 1) if background.empty?

    background_sum = background.keys.sum { |index| @image.pixels[index] }
    Rational(sum * background.length - background_sum * area, area * background.length)
  end

  def basic_features(pixels, number)
    area = pixels.length
    x0, y0, x1, y1 = box(pixels)
    coordinates = pixels.map { |index| [index % @width, index.div(@width)] }
    sx = coordinates.sum(&:first)
    sy = coordinates.sum(&:last)
    intensities = pixels.map { |index| @image.pixels[index] }
    sum = intensities.sum
    sum_squares = intensities.sum { |value| value * value }
    m20 = area * coordinates.sum { |x, _y| x * x } - sx * sx
    m02 = area * coordinates.sum { |_x, y| y * y } - sy * sy
    m11 = area * coordinates.sum { |x, y| x * y } - sx * sy
    u = m20 - m02
    v = 2 * m11
    anisotropy = m20 + m02 > 0 ? Rational(u.abs + v.abs, m20 + m02) : Rational(0, 1)
    orientation = if anisotropy <= @isotropy
                    'none'
                  elsif v.abs >= u.abs
                    v > 0 ? 'falling' : 'rising'
                  else
                    u > 0 ? 'horizontal' : 'vertical'
                  end
    left_right = coordinates.count { |x, y| @labels[y * @width + x0 + x1 - x] == number }
    top_bottom = coordinates.count { |x, y| @labels[(y0 + y1 - y) * @width + x] == number }
    border = x0.zero? || y0.zero? || x1 == @width - 1 || y1 == @height - 1
    { area: area, x0: x0, y0: y0, x1: x1, y1: y1, width: x1 - x0 + 1, height: y1 - y0 + 1,
      cx: Rational(sx, area), cy: Rational(sy, area), mean: Rational(sum, area),
      variance: Rational(area * sum_squares - sum * sum, area * area),
      min: intensities.min, max: intensities.max, contrast: intensity_contrast(pixels, sum, area),
      border: border ? 1 : 0, var_x: Rational(m20, area * area), var_y: Rational(m02, area * area),
      cov_xy: Rational(m11, area * area), hu1: Rational(m20 + m02, area**3),
      anisotropy: anisotropy, orientation: orientation,
      extent: Rational(area, (x1 - x0 + 1) * (y1 - y0 + 1)),
      mirror_lr: Rational(left_right, area), mirror_tb: Rational(top_bottom, area),
      holes: @owned_holes[number].length, hole_area: @owned_holes[number].sum { |hole| hole.pixels.length },
      euler: 1 - @owned_holes[number].length, parent: @parents[number], depth: @depths[number] }
  end

  def trace_contour(pixels, number)
    directions = DIRECTIONS[@setting.connectivity]
    count = directions.length
    origin = pixels.first
    current = origin
    previous_direction = count - 1
    first_step = nil
    codes = []
    loop do
      start = if count == 4
                (previous_direction + 3) % 4
              else
                (previous_direction + (previous_direction.even? ? 7 : 6)) % 8
              end
      x, y = current % @width, current.div(@width)
      choice = nil
      count.times do |offset|
        direction = (start + offset) % count
        dx, dy = directions[direction]
        destination = position(x + dx, y + dy)
        next unless destination && @labels[destination] == number

        choice = [direction, destination]
        break
      end
      break unless choice

      previous = current
      previous_direction, current = choice
      codes << previous_direction
      first_step = current if codes.length == 1
      if codes.length >= 2 && current == first_step && previous == origin
        codes.pop
        break
      end
    end
    codes
  end

  def boundary_features(pixels, number)
    perimeter = pixels.count do |index|
      x, y = index % @width, index.div(@width)
      DIRECTIONS[12 - @setting.connectivity].any? do |dx, dy|
        other = position(x + dx, y + dy)
        other.nil? || @labels[other] != number
      end
    end
    codes = trace_contour(pixels, number)
    straight = @setting.connectivity == 4 ? codes.length : codes.count(&:even?)
    diagonal = codes.length - straight
    turns = codes.each_index.count { |index| codes[index] != codes[(index - 1) % codes.length] }
    runs = pixels.count { |index| (index % @width).zero? || @labels[index - 1] != number }
    { perimeter: perimeter, chain: codes.length, straight: straight, diagonal: diagonal, turns: turns,
      compactness: Rational((5 * straight + 7 * diagonal)**2, 25 * pixels.length), runs: runs,
      codes: codes.empty? ? '-' : codes.join }
  end

  def cross(first, second, point)
    (second[0] - first[0]) * (point[1] - first[1]) - (second[1] - first[1]) * (point[0] - first[0])
  end

  def hull_half(points)
    half = []
    points.each do |point|
      half.pop while half.length >= 2 && cross(half[-2], half[-1], point) <= 0
      half << point
    end
    half
  end

  def convex_hull(pixels)
    corners = {}
    pixels.each do |index|
      x, y = index % @width, index.div(@width)
      [[x, y], [x + 1, y], [x, y + 1], [x + 1, y + 1]].each { |point| corners[point] = true }
    end
    points = corners.keys.sort
    hull_half(points)[0...-1] + hull_half(points.reverse)[0...-1]
  end

  def center_inside?(hull, x, y)
    hull.each_index.all? do |index|
      first = hull[index]
      second = hull[(index + 1) % hull.length]
      (second[0] - first[0]) * (2 * y + 1 - 2 * first[1]) -
        (second[1] - first[1]) * (2 * x + 1 - 2 * first[0]) >= 0
    end
  end

  def hull_features(pixels, values)
    hull = convex_hull(pixels)
    doubled_area = hull.each_index.sum do |index|
      first = hull[index]
      second = hull[(index + 1) % hull.length]
      first[0] * second[1] - second[0] * first[1]
    end.abs
    feret = hull.combination(2).map { |first, second| (first[0] - second[0])**2 + (first[1] - second[1])**2 }.max
    width = hull.each_index.map do |index|
      first = hull[index]
      second = hull[(index + 1) % hull.length]
      maximum = hull.map { |point| cross(first, second, point).abs }.max
      length_squared = (second[0] - first[0])**2 + (second[1] - first[1])**2
      Rational(maximum * maximum, length_squared)
    end.min
    concavity = Array.new(@binary.length, false)
    values[:y0].upto(values[:y1]) do |y|
      values[:x0].upto(values[:x1]) do |x|
        index = y * @width + x
        if @labels[index].zero? && @hole_map[index].zero? && center_inside?(hull, x, y)
          concavity[index] = true
        end
      end
    end
    bays = Labeling.components(concavity, @width, @height, 12 - @setting.connectivity)
    { hull_doubled: doubled_area, solidity: Rational(2 * pixels.length, doubled_area),
      feret2: feret, width2: width, elongation: Rational(feret, 1) / width,
      bays: bays.count { |bay| bay.length >= @bay_min }, bay_area: concavity.count(true) }
  end

  def measure_regions
    @regions = @labeling.groups.each_with_index.map do |pixels, index|
      number = index + 1
      values = basic_features(pixels, number)
      values.merge!(boundary_features(pixels, number))
      values.merge!(hull_features(pixels, values))
      skeleton = Morphology.thin(pixels, @width, @height)
      crossings = pixels.filter_map do |pixel|
        Morphology.transitions(Morphology.neighbour_bits(skeleton, pixel, @width, @height)) if skeleton[pixel]
      end
      values[:skeleton] = crossings.length
      values[:endpoints] = crossings.count(1)
      values[:branches] = crossings.count { |count| count >= 3 }
      Region.new(number: number, pixels: pixels, values: values, skeleton: skeleton, kept: false, flags: [])
    end
  end

  def satisfies?(values, condition)
    comparison = values.fetch(condition.feature) <=> condition.value
    case condition.operator
    when '<' then comparison < 0
    when '<=' then comparison <= 0
    when '>' then comparison > 0
    when '>=' then comparison >= 0
    when '=' then comparison.zero?
    when '!=' then !comparison.zero?
    end
  end

  def apply_rules
    @regions.each do |region|
      failed = @filters.each_index.find { |index| !satisfies?(region.values, @filters[index]) }
      unless failed.nil?
        @filter_dropped[failed] += 1
        next
      end
      region.kept = true
      classification = @classes.find do |rule|
        rule.conditions.all? { |condition| satisfies?(region.values, condition) }
      end
      region.klass = classification ? classification.name : 'other'
      region.flags = @flags.filter_map do |rule|
        rule.name if rule.conditions.all? { |condition| satisfies?(region.values, condition) }
      end
    end
    @kept = @regions.select(&:kept)
  end

  def nearest_neighbors
    @kept.each do |region|
      values = region.values
      choices = @kept.reject { |other| other.number == region.number }.map do |other|
        x = values[:x0] + values[:x1] - other.values[:x0] - other.values[:x1]
        y = values[:y0] + values[:y1] - other.values[:y0] - other.values[:y1]
        [x * x + y * y, other.number]
      end
      next if choices.empty?

      distance, number = choices.min
      region.neighbor = number
      region.distance2 = Rational(distance, 4)
    end
  end

  def append_thresholds
    stats = @statistics
    @threshold_lines << "image #{@image.name} size #{@width} #{@height} maxval #{@image.maximum}"
    @threshold_lines << "histogram pixels #{stats.count} min #{stats.minimum} max #{stats.maximum} mean #{Report.decimal(Rational(stats.sum, stats.count), 2)} median #{stats.median} mode #{stats.mode} levels #{stats.levels}"
    @threshold_lines << ['bins', stats.bin_width, *stats.bins].join(' ')
    @threshold_lines << "otsu threshold #{stats.otsu} upper #{stats.upper} candidates #{stats.candidates.length}"
    stats.candidates.first(@otsu_top).each_with_index do |candidate, index|
      below = Rational(candidate.sum_below, candidate.below)
      above = Rational(candidate.sum_above, candidate.above)
      gap = Rational(candidate.sum_above * candidate.below - candidate.sum_below * candidate.above,
                     candidate.below * candidate.above)
      @threshold_lines << "rank #{index + 1} t #{candidate.threshold} below #{candidate.below} above #{candidate.above} mean_below #{Report.decimal(below, 2)} mean_above #{Report.decimal(above, 2)} gap #{Report.decimal(gap, 2)}"
    end
    @threshold_lines << "isodata threshold #{stats.isodata} iterations #{stats.iterations}"
    @threshold_lines << "threshold #{@threshold} #{@method} #{@setting.polarity} foreground #{@initial.count(true)}"
    @morph_records.each { |operation, count| @threshold_lines << "morph #{operation} foreground #{count}" }
    @sweep_step.step(@image.maximum - 1, @sweep_step) do |threshold|
      mask = binarize(threshold)
      regions = Labeling.components(mask, @width, @height, @setting.connectivity).length
      @threshold_lines << "sweep #{threshold} foreground #{mask.count(true)} regions #{regions}"
    end
  end

  def label_character(index)
    number = @labels[index]
    if number.zero?
      @hole_map[index].zero? ? '.' : ':'
    else
      @regions[number - 1].kept ? SYMBOLS[number % 62] : '#'
    end
  end

  def append_map(name)
    @label_lines << "#{name} #{@image.name} #{@width} #{@height}"
    @height.times do |y|
      @label_lines << @width.times.map { |x| yield(y * @width + x) }.join
    end
  end

  def append_maps
    append_map('morphology') do |index|
      if @binary[index]
        @initial[index] ? '#' : '+'
      else
        @initial[index] ? '-' : '.'
      end
    end
    append_map('labels') { |index| label_character(index) }
    append_map('skeleton') do |index|
      number = @labels[index]
      number > 0 && !@regions[number - 1].skeleton[index] ? '+' : label_character(index)
    end
  end

  def append_region_rows
    @kept.each do |region|
      fields = COLUMNS.map do |column|
        feature = column.to_sym
        case column
        when 'image' then @image.name
        when 'label' then region.number
        when 'class' then region.klass
        when 'flags' then region.flags.empty? ? '-' : region.flags.join('+')
        when 'parent' then region.values[:parent] || '-'
        when 'hull_area' then Report.hull_area(region.values[:hull_doubled])
        when 'neighbor' then region.neighbor || '-'
        when 'distance2' then region.distance2 ? Report.decimal(region.distance2, 2) : '-'
        else
          DECIMALS.key?(feature) ? Report.decimal(region.values.fetch(feature), DECIMALS[feature]) : region.values.fetch(feature)
        end
      end
      @region_lines << fields.join(',')
    end
  end

  def mean_intensity(foreground)
    indices = @binary.each_index.select { |index| @binary[index] == foreground }
    return '-' if indices.empty?

    sum = indices.sum { |index| @image.pixels[index] }
    Report.decimal(Rational(sum, indices.length), 2)
  end

  def orientation_line(regions)
    fields = ['orientations']
    ORIENTATIONS.each { |name| fields.concat([name, regions.count { |region| region.values[:orientation] == name }]) }
    fields.join(' ')
  end

  def append_image_summary
    @summary_lines << "image #{@image.name}"
    @summary_lines << "threshold #{@threshold} #{@method} #{@setting.polarity} conn #{@setting.connectivity}"
    @summary_lines << "foreground #{@initial.count(true)} #{@binary.count(true)}"
    @summary_lines << "regions #{@regions.length} provisional #{@labeling.provisional} kept #{@kept.length} dropped #{@regions.length - @kept.length}"
    @summary_lines << "connectivity four #{@four} eight #{@eight}"
    @summary_lines << "holes #{@holes.length} hole_pixels #{@holes.sum { |hole| hole.pixels.length }} euler #{@euler} bitquad #{@bitquad}"
    @holes.each do |hole|
      @summary_lines << "hole #{hole.number} owner #{hole.owner} area #{hole.pixels.length} box #{hole.box.join(' ')}"
    end
    @summary_lines << "depth_max #{@depths.max}"
    @summary_lines << ['tree', *@children[0].map { |number| containment_tree(number) }].join(' ')
    @summary_lines << "intensity foreground #{mean_intensity(true)} background #{mean_intensity(false)}"
    if @kept.empty?
      @summary_lines << 'area total 0 mean - largest - smallest -'
    else
      total = @kept.sum { |region| region.values[:area] }
      largest = @kept.min_by { |region| [-region.values[:area], region.number] }
      smallest = @kept.min_by { |region| [region.values[:area], region.number] }
      @summary_lines << "area total #{total} mean #{Report.decimal(Rational(total, @kept.length), 2)} largest #{largest.number} #{largest.values[:area]} smallest #{smallest.number} #{smallest.values[:area]}"
    end
    classes = ['classes']
    @class_names.each { |name| classes.concat([name, @kept.count { |region| region.klass == name }]) }
    @summary_lines << classes.join(' ')
    @summary_lines << orientation_line(@kept)
    flags = ['flags']
    @flags.each { |rule| flags.concat([rule.name, @kept.count { |region| region.flags.include?(rule.name) }]) }
    @summary_lines << flags.join(' ')
    @summaries << { name: @image.name, regions: @regions.length, holes: @holes.length, euler: @euler, kept: @kept }
  end

  def append_overall_summary
    kept = @summaries.flat_map { |summary| summary[:kept] }
    regions = @summaries.sum { |summary| summary[:regions] }
    @summary_lines << 'overall'
    @summary_lines << "images #{@images.length}"
    @summary_lines << "regions #{regions} kept #{kept.length} dropped #{regions - kept.length}"
    @summary_lines << "holes #{@summaries.sum { |summary| summary[:holes] }} euler #{@summaries.sum { |summary| summary[:euler] }}"
    @filters.each_with_index do |condition, index|
      @summary_lines << "filter #{index + 1} #{condition.words.join(' ')} dropped #{@filter_dropped[index]}"
    end
    @class_names.each do |name|
      members = kept.select { |region| region.klass == name }
      area = members.sum { |region| region.values[:area] }
      mean = members.empty? ? '-' : Report.decimal(Rational(area, members.length), 2)
      @summary_lines << "class #{name} count #{members.length} area #{area} mean #{mean}"
    end
    @flags.each do |rule|
      @summary_lines << "flag #{rule.name} count #{kept.count { |region| region.flags.include?(rule.name) }}"
    end
    @summary_lines << orientation_line(kept)
    largest = nil
    @summaries.each do |summary|
      summary[:kept].each do |region|
        if largest.nil? || region.values[:area] > largest[:region].values[:area]
          largest = { image: summary[:name], region: region }
        end
      end
    end
    @summary_lines << if largest
                        "largest #{largest[:image]} #{largest[:region].number} #{largest[:region].values[:area]}"
                      else
                        'largest -'
                      end
  end

  def process(image)
    @image = image
    @width, @height = image.width, image.height
    @setting = @settings.fetch(image.name)
    prepare_binary
    find_containment
    measure_regions
    apply_rules
    nearest_neighbors
    append_thresholds
    append_maps
    append_region_rows
    append_image_summary
  end

  def run
    @images.each { |image| process(image) }
    append_overall_summary
    Report.write('thresholds.txt', @threshold_lines)
    Report.write('labels.txt', @label_lines)
    Report.write('regions.csv', @region_lines)
    Report.write('summary.txt', @summary_lines)
  end
end

ImageRegionAnalysis.new.run if $PROGRAM_NAME == __FILE__
