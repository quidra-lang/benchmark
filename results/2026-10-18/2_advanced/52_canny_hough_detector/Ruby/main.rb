require 'set'
require 'fileutils'
require_relative 'pgm_io'
require_relative 'filters'
require_relative 'canny'
require_relative 'hough'
require_relative 'corners'

module Detector
  KINDS = %w[equilateral_triangle right_triangle triangle square rectangle parallelogram trapezoid quadrilateral].freeze
  module_function

  def cross(a, b) = a[0] * b[1] - a[1] * b[0]
  def dot(a, b) = a[0] * b[0] + a[1] * b[1]
  def sub(a, b) = [a[0] - b[0], a[1] - b[1]]
  def distance(a, b) = [(a[0] - b[0]).abs, (a[1] - b[1]).abs].max
  def angle(a, b) = [(a - b).abs, 180 - (a - b).abs].min
  def shape_name(s) = s ? "#{s[:type]} #{s[:number]}" : 'none'

  def rounded(n, d)
    n, d = -n, -d if d < 0
    (2 * n + d) / (2 * d)
  end

  def bresenham(start, finish)
    x, y = start
    xx, yy = finish
    dx, dy = (xx - x).abs, -(yy - y).abs
    sx, sy = x < xx ? 1 : -1, y < yy ? 1 : -1
    error = dx + dy
    points = []
    loop do
      points << [x, y]
      break if x == xx && y == yy
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

  def circumference?(circle, point)
    delta = sub(point, circle[:center])
    (circle[:radius] - 1)**2 <= dot(delta, delta) && dot(delta, delta) <= (circle[:radius] + 1)**2
  end

  def select_circles(peaks, outlines, edges, limit)
    peaks.first(limit).each_with_index.map do |(r, x, y, votes), index|
      offsets = outlines[r].sort do |a, b|
        ha = a[1] > 0 || (a[1] == 0 && a[0] > 0) ? 0 : 1
        hb = b[1] > 0 || (b[1] == 0 && b[0] > 0) ? 0 : 1
        ha == hb ? -(cross(a, b) <=> 0) : ha <=> hb
      end
      hits = offsets.map { |dx, dy| edges.include?([x + dx, y + dy]) }
      arcs = hits.each_index.count { |i| hits[i] && !hits[i - 1] }
      gap = run = 0
      (hits + hits).each do |hit|
        run = hit ? 0 : run + 1
        gap = [gap, run].max
      end
      {type: 'circle', number: index + 1, center: [x, y], radius: r, votes: votes,
       outline: offsets, gap: [gap, hits.length].min, arcs: hits.all? ? 1 : arcs}
    end
  end

  def extract_segments(peaks, edges, trig, p)
    lines, segments, used = [], [], Set.new
    peaks.each do |t, r, votes|
      break if lines.length >= p[:hough_max_lines]
      c, s = trig[t]
      points = edges.reject { |q| used.include?(q) || (Hough.rho(q, t, trig, p[:hough_rho_step]) - r).abs > p[:segment_tolerance] }
      points.sort_by! { |x, y| [y * c - x * s, x, y] }
      groups = []
      points.each do |q|
        if groups.empty? || (q[1] * c - q[0] * s) - (groups.last.last[1] * c - groups.last.last[0] * s) > p[:segment_max_gap] * 16384
          groups << []
        end
        groups.last << q
      end
      accepted = groups.select { |g| distance(g.first, g.last) + 1 >= p[:segment_min_length] }
      next if accepted.empty?
      ids = accepted.map do |g|
        number = segments.length + 1
        segments << {number: number, theta: t, start: g.first, end: g.last,
                     length: distance(g.first, g.last) + 1, pixels: g.length}
        used.merge(g)
        number
      end
      lines << {number: lines.length + 1, theta: t, rho: r, votes: votes, segments: ids}
    end
    [lines, segments, used]
  end

  def junctions(segments, p)
    joins = {}
    segments.combination(2) do |a, b|
      next if angle(a[:theta], b[:theta]) < p[:junction_min_angle]
      da, db = sub(a[:end], a[:start]), sub(b[:end], b[:start])
      den = cross(da, db)
      next if den == 0
      lam = cross(sub(b[:start], a[:start]), db)
      point = 2.times.map { |i| rounded(a[:start][i] * den + lam * da[i], den) }
      ends = [a, b].map { |s| distance(s[:start], point) <= distance(s[:end], point) ? :start : :end }
      next if [a, b].each_with_index.any? { |s, i| distance(s[ends[i]], point) > p[:junction_distance] }
      joins[[a[:number], b[:number]]] = {point: point, ends: {a[:number] => ends[0], b[:number] => ends[1]}}
    end
    joins
  end

  def join(a, b, joins) = joins[[a, b].sort]

  def polygons(segments, joins)
    graph = Hash.new { |h, k| h[k] = [] }
    joins.each_key { |a, b| graph[a] << b; graph[b] << a }
    result = []
    [3, 4].each do |k|
      found = []
      graph.keys.sort.each do |first|
        extend_cycle = lambda do |sequence|
          if sequence.length == k
            next unless sequence[1] < sequence[-1] && join(sequence[-1], first, joins)
            vertices = []
            valid = sequence.each_index.all? do |i|
              current = sequence[i]
              entry = join(sequence[i - 1], current, joins)
              exit_join = join(current, sequence[(i + 1) % k], joins)
              vertices << entry[:point]
              entry[:ends][current] != exit_join[:ends][current]
            end
            next unless valid
            turns = k.times.map { |i| cross(sub(vertices[(i + 1) % k], vertices[i]), sub(vertices[(i + 2) % k], vertices[(i + 1) % k])) }
            next unless turns.all?(&:positive?) || turns.all?(&:negative?)
            found << {type: 'polygon', segments: sequence, vertices: vertices}
          else
            graph[sequence.last].sort.each do |candidate|
              extend_cycle.call(sequence + [candidate]) if candidate > first && !sequence.include?(candidate)
            end
          end
        end
        extend_cycle.call([first])
      end
      found.sort_by { |s| s[:segments] }.each { |s| s[:number] = result.length + 1; result << s }
    end
    result
  end

  def polygon_properties(poly, segments, edges, p)
    vertices = poly[:vertices]
    k = vertices.length
    theta = poly[:segments].map { |id| segments[id - 1][:theta] }
    angles, lengths, supports = [], [], []
    sigma = 0
    k.times do |i|
      v, following = vertices[i], vertices[(i + 1) % k]
      phi = angle(theta[i - 1], theta[i])
      angles << (dot(sub(vertices[i - 1], v), sub(following, v)) < 0 ? 180 - phi : phi)
      delta = sub(following, v)
      lengths << dot(delta, delta)
      points = bresenham(v, following)
      supported = points.count { |x, y| (-1..1).any? { |dy| (-1..1).any? { |dx| edges.include?([x + dx, y + dy]) } } }
      supports << 100 * supported / points.length
      sigma += cross(v, following)
    end
    tolerance = p[:angle_tolerance]
    kind = if k == 3
             if angles.all? { |a| (a - 60).abs <= tolerance }
               'equilateral_triangle'
             elsif angles.any? { |a| (a - 90).abs <= tolerance }
               'right_triangle'
             else
               'triangle'
             end
           else
             a = angle(theta[0], theta[2]) <= tolerance
             b = angle(theta[1], theta[3]) <= tolerance
             if !a && !b
               'quadrilateral'
             elsif a != b
               'trapezoid'
             elsif angles.any? { |v| (v - 90).abs > tolerance }
               'parallelogram'
             elsif 100 * (lengths.max - lengths.min) <= p[:square_tolerance] * lengths.max
               'square'
             else
               'rectangle'
             end
           end
    poly.merge!(angles: angles, lengths: lengths, supports: supports, sigma: sigma,
                kind: kind, vertex_corners: Array.new(k))
  end

  def representatives(shape)
    return shape[:vertices] if shape[:type] == 'polygon'
    x, y = shape[:center]
    r = shape[:radius]
    [[x + r, y], [x, y + r], [x - r, y], [x, y - r]]
  end

  def inside?(shape, point)
    if shape[:type] == 'circle'
      d = sub(point, shape[:center])
      return dot(d, d) <= shape[:radius]**2
    end
    vertices = shape[:vertices]
    vertices.each_index.all? do |i|
      z = cross(sub(vertices[(i + 1) % vertices.length], vertices[i]), sub(point, vertices[i]))
      z == 0 || z.positive? == shape[:sigma].positive?
    end
  end

  def measure(shapes, image, margin)
    shapes.each do |shape|
      points = representatives(shape)
      xs, ys = points.transpose
      inner_count = outer_count = inner_sum = outer_sum = 0
      ([0, ys.min - margin].max..[image.length - 1, ys.max + margin].min).each do |y|
        ([0, xs.min - margin].max..[image.first.length - 1, xs.max + margin].min).each do |x|
          if inside?(shape, [x, y])
            inner_count += 1
            inner_sum += image[y][x]
          else
            outer_count += 1
            outer_sum += image[y][x]
          end
        end
      end
      mean = inner_count.zero? ? 0 : inner_sum / inner_count
      shape.merge!(pixel_count: inner_count, mean: mean, contrast: mean - (outer_count.zero? ? 0 : outer_sum / outer_count))
    end
    shapes.each do |child|
      parents = shapes.each_with_index.select do |parent, _|
        parent[:pixel_count] > child[:pixel_count] && representatives(child).all? { |v| inside?(parent, v) }
      end
      child[:enclosing] = parents.min_by { |parent, i| [parent[:pixel_count], i] }&.first
    end
  end

  def match_corners(corners, polygons, segments, maximum)
    corners.each do |corner|
      candidates = polygons.flat_map do |poly|
        poly[:vertices].each_with_index.filter_map do |v, i|
          d = distance(corner[:point], v)
          [d, poly[:number], i + 1] if d <= maximum
        end
      end
      if candidates.any?
        _, poly, vertex = candidates.min
        corner.merge!(match: "polygon #{poly} vertex #{vertex}", match_kind: :vertex)
        next
      end
      ends = segments.flat_map do |s|
        [:start, :end].each_with_index.filter_map do |endpoint, rank|
          d = distance(corner[:point], s[endpoint])
          [d, s[:number], rank, endpoint] if d <= maximum
        end
      end
      if ends.any?
        _, number, _, endpoint = ends.min
        corner.merge!(match: "segment #{number} #{endpoint}", match_kind: :segment)
      else
        corner.merge!(match: 'none', match_kind: :none)
      end
    end
    polygons.each do |poly|
      poly[:vertex_corners] = poly[:vertices].map do |v|
        candidates = corners.filter_map do |c|
          d = distance(v, c[:point])
          [d, c[:number]] if d <= maximum
        end
        candidates.min&.last
      end
    end
  end

  def explanations(shape, edges)
    return edges.select { |q| circumference?(shape, q) }.to_set if shape[:type] == 'circle'
    explained = Set.new
    vertices = shape[:vertices]
    vertices.each_index do |i|
      bresenham(vertices[i], vertices[(i + 1) % vertices.length]).each do |x, y|
        (-1..1).each do |dy|
          (-1..1).each do |dx|
            point = [x + dx, y + dy]
            explained.add(point) if edges.include?(point)
          end
        end
      end
    end
    explained
  end

  def components(groups, shapes, edges, magnitude, direction)
    explained = shapes.map { |s| explanations(s, edges) }
    groups.each_with_index.map do |points, i|
      xs, ys = points.transpose
      counts = Hash.new(0)
      strength = 0
      points.each { |x, y| counts[direction[y][x]] += 1; strength += magnitude[y][x] }
      ends = points.count { |x, y| Canny::NEIGHBORS.count { |dx, dy| edges.include?([x + dx, y + dy]) } == 1 }
      matches = explained.map { |set| points.count { |q| set.include?(q) } }
      best = matches.max || 0
      {number: i + 1, pixels: points.length, box: [xs.min, ys.min, xs.max, ys.max], ends: ends,
       strength: strength / points.length, direction: counts.keys.min_by { |a| [-counts[a], a] },
       shape: best.zero? ? nil : shapes[matches.index(best)], explained: best}
    end
  end

  def write_results(lines, segments, circles, polygons, corners, components)
    listing = ["lines #{lines.length}"]
    lines.each do |line|
      listing << "line #{line[:number]} theta #{line[:theta]} rho #{line[:rho]} votes #{line[:votes]} segments #{line[:segments].length}"
      line[:segments].each do |id|
        s = segments[id - 1]
        listing << "segment #{id} start #{s[:start].join(' ')} end #{s[:end].join(' ')} length #{s[:length]} pixels #{s[:pixels]}"
      end
    end
    PgmIO.write_lines('lines.txt', listing)
    PgmIO.write_lines('circles.txt', ["circles #{circles.length}"] + circles.map do |c|
      "circle #{c[:number]} center #{c[:center].join(' ')} radius #{c[:radius]} votes #{c[:votes]} points #{c[:outline].length} gap #{c[:gap]} arcs #{c[:arcs]} pixels #{c[:pixel_count]} mean #{c[:mean]} contrast #{c[:contrast]} inside #{shape_name(c[:enclosing])}"
    end)
    listing = ["polygons #{polygons.length}"]
    polygons.each do |s|
      area = s[:sigma].abs
      listing << "polygon #{s[:number]} #{s[:kind]} segments #{s[:segments].join(' ')} area #{area / 2}.#{area.even? ? 0 : 5} pixels #{s[:pixel_count]} mean #{s[:mean]} contrast #{s[:contrast]} inside #{shape_name(s[:enclosing])}"
      s[:vertices].each_with_index do |v, i|
        listing << "vertex #{i + 1} #{v.join(' ')} angle #{s[:angles][i]} corner #{s[:vertex_corners][i] || 'none'}"
      end
      s[:segments].each_with_index do |id, i|
        listing << "side #{i + 1} segment #{id} length2 #{s[:lengths][i]} support #{s[:supports][i]}"
      end
    end
    PgmIO.write_lines('polygons.txt', listing)
    PgmIO.write_lines('corners.txt', ["corners #{corners.length}"] + corners.map do |c|
      "corner #{c[:number]} #{c[:point].join(' ')} response #{c[:response]} match #{c[:match]}"
    end)
    PgmIO.write_lines('components.txt', ["components #{components.length}"] + components.map do |c|
      "component #{c[:number]} pixels #{c[:pixels]} box #{c[:box].join(' ')} ends #{c[:ends]} strength #{c[:strength]} direction #{c[:direction]} shape #{shape_name(c[:shape])} explained #{c[:explained]}"
    end)
  end

  def main
    image = PgmIO.read_image('input/image.pgm')
    trig, p = PgmIO.read_trig('input/trig.txt'), PgmIO.read_params('input/params.txt')
    height, width = image.length, image.first.length
    smooth = Filters.smoothing(image, p[:gauss_size], p[:gauss_kernel], p[:gauss_divisor])
    gx, gy, magnitude = Filters.gradient(smooth)
    direction = Canny.directions(gx, gy)
    nonmax = Canny.suppress(magnitude, direction)
    edges, strong, weak = Canny.hysteresis(nonmax, p[:canny_low], p[:canny_high])
    groups = Canny.components(edges)
    cells, outlines = Hough.circle_votes(edges, width, height, p[:circle_min_radius], p[:circle_max_radius])
    circle_candidates, circle_peaks = Hough.circle_peaks(cells, outlines, width, height, p[:circle_min_percent])
    circles = select_circles(circle_peaks, outlines, edges, p[:circle_max_count])
    circle_edge = edges.select { |q| circles.any? { |c| circumference?(c, q) } }.to_set
    line_edge = edges - circle_edge
    votes = Hough.line_votes(line_edge, trig, p[:hough_rho_step])
    peaks = Hough.line_peaks(votes, p[:hough_threshold])
    lines, segments, used = extract_segments(peaks, line_edge, trig, p)
    joins = junctions(segments, p)
    polygons = polygons(segments, joins)
    polygons.each { |s| polygon_properties(s, segments, edges, p) }
    shapes = polygons + circles
    measure(shapes, image, p[:contrast_margin])
    corner_candidates, corners = Corners.detect(gx, gy, p[:harris_window], p[:harris_threshold], p[:harris_max_count])
    match_corners(corners, polygons, segments, p[:corner_match_distance])
    components = components(groups, shapes, edges, magnitude, direction)
    bounds = [[0, 0], [width - 1, 0], [0, height - 1], [width - 1, height - 1]]
    limits = 180.times.flat_map { |t| bounds.map { |q| Hough.rho(q, t, trig, p[:hough_rho_step]) } }
    max_votes = votes.values.max || 0
    vote_image = (limits.min..limits.max).map { |r| 180.times.map { |t| max_votes.zero? ? 0 : 255 * votes[[t, r]] / max_votes } }
    overlay = image.map { |row| row.map { |v| v / p[:overlay_divisor] } }
    mark = lambda { |x, y| overlay[y][x] = 255 if x >= 0 && x < width && y >= 0 && y < height }
    segments.each { |s| bresenham(s[:start], s[:end]).each { |q| mark.call(*q) } }
    circles.each { |c| c[:outline].each { |dx, dy| mark.call(c[:center][0] + dx, c[:center][1] + dy) } }
    corners.each { |c| (-2..2).each { |e| mark.call(c[:point][0] + e, c[:point][1]); mark.call(c[:point][0], c[:point][1] + e) } }
    FileUtils.mkdir_p('output')
    PgmIO.write_image('edges.pgm', height.times.map { |y| width.times.map { |x| edges.include?([x, y]) ? 255 : 0 } })
    PgmIO.write_image('hough.pgm', vote_image)
    PgmIO.write_image('overlay.pgm', overlay)
    write_results(lines, segments, circles, polygons, corners, components)
    report = {image: "#{width} #{height}", gradient_nonzero: magnitude.flatten.count(&:positive?), gradient_max: magnitude.flatten.max,
              nms_kept: nonmax.flatten.count(&:positive?), strong: strong.length, weak: weak.length, edges: edges.length,
              weak_kept: (weak & edges).length, weak_dropped: (weak - edges).length, edge_components: components.length}
    [0, 45, 90, 135].each { |d| report["direction_#{d}"] = edges.count { |x, y| direction[y][x] == d } }
    report.merge!(circle_candidates: circle_candidates, circle_peaks: circle_peaks.length, circles: circles.length,
                  circle_edge_pixels: circle_edge.length, line_edge_pixels: line_edge.length, hough_max_votes: max_votes,
                  hough_peaks: peaks.length, lines: lines.length, segments: segments.length, claimed_pixels: used.length,
                  junctions: joins.length, polygons: polygons.length)
    KINDS.each { |kind| report[kind] = polygons.count { |s| s[:kind] == kind } }
    report.merge!(corner_candidates: corner_candidates, corners: corners.length,
                  corners_on_vertices: corners.count { |c| c[:match_kind] == :vertex },
                  corners_on_segments: corners.count { |c| c[:match_kind] == :segment },
                  corners_unmatched: corners.count { |c| c[:match_kind] == :none },
                  vertices_with_corner: polygons.inject(0) { |n, s| n + s[:vertex_corners].compact.length })
    PgmIO.write_lines('report.txt', report.map { |name, value| "#{name} #{value}" })
  end
end

Detector.main if $PROGRAM_NAME == __FILE__
