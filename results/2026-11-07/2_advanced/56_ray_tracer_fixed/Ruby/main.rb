require 'fileutils'
require_relative 'scene'
require_relative 'intersect'
require_relative 'shading'

class Renderer
  include Intersect
  include Shading
  RAY_KINDS = %w[primary reflection refraction shadow].freeze
  LIGHT_COUNTS = %i[pixels shadow_rays blocked attenuated backfacing outside].freeze
  BLACK = [0, 0, 0].freeze

  def initialize(scene, settings)
    @scene = scene
    @width, @height = settings.fetch('size')
    @contrast, @max_depth, @far, @epsilon, margin = %w[contrast depth far epsilon pad].map { |k| settings.fetch(k)[0] }
    @objects, @lights = scene.objects, scene.lights
    @planes = @objects.select { |obj| obj[:kind] == 'plane' }
    @nodes = []
    bounded = @objects.select do |obj|
      obj[:bounds] = bounds(obj, margin)
      obj[:leaf_depth] = nil
      !obj[:bounds].nil?
    end
    @root = build_bvh(bounded, 0) unless bounded.empty?
    @rays = RAY_KINDS.to_h { |kind| [kind, 0] }
    @misses = RAY_KINDS.first(3).to_h { |kind| [kind, 0] }
    @depth_counts = Array.new(@max_depth + 1, 0)
    @tests = RAY_KINDS.to_h { |kind| [kind, { nodes: 0, objects: 0 }] }
    @object_counts = @objects.map { { primary: 0, secondary: 0, shadow: 0 } }
    @light_counts = @lights.map { LIGHT_COUNTS.to_h { |name| [name, 0] } }
    @total_internal_reflections = @clamped = @supersampled = 0
    @pixels = []
  end

  def union_box(objects)
    [3.times.map { |a| objects.map { |obj| obj[:bounds][0][a] }.min },
     3.times.map { |a| objects.map { |obj| obj[:bounds][1][a] }.max }]
  end

  def surface_cost(objects)
    lo, hi = union_box(objects)
    dx, dy, dz = sub(hi, lo)
    (dx * dy + dy * dz + dz * dx) * objects.length
  end

  def build_bvh(objects, depth)
    node = { bounds: union_box(objects), depth: depth, visits: 0, objects: nil }
    @nodes << node
    if objects.length <= 2
      node[:objects] = objects.sort_by { |obj| obj[:number] }
      objects.each { |obj| obj[:leaf_depth] = depth }
      return node
    end
    best_key = best_groups = nil
    3.times do |axis|
      ordered = objects.sort_by { |obj| [(obj[:bounds][0][axis] + obj[:bounds][1][axis]).div(2), obj[:number]] }
      (1...ordered.length).each do |split|
        left, right = ordered.take(split), ordered.drop(split)
        key = [surface_cost(left) + surface_cost(right), axis, split]
        if best_key.nil? || (key <=> best_key).negative?
          best_key, best_groups = key, [left, right]
        end
      end
    end
    node[:left] = build_bvh(best_groups[0], depth + 1)
    node[:right] = build_bvh(best_groups[1], depth + 1)
    node
  end

  def test_node(node, origin, direction, kind, counted)
    if counted
      @tests[kind][:nodes] += 1
      node[:visits] += 1
    end
    interval = slab(*node[:bounds], origin, direction)
    interval && interval[2] > @epsilon ? interval[0] : nil
  end

  def test_object(obj, origin, direction, kind, counted)
    @tests[kind][:objects] += 1 if counted
    candidate(obj, origin, direction, @epsilon)
  end

  def nearest(origin, direction, kind = 'primary', counted = false)
    best = nil
    consider = lambda do |obj|
      hit = test_object(obj, origin, direction, kind, counted)
      next if hit.nil? || hit[0] > @far
      if best.nil? || ([hit[0], obj[:number]] <=> [best[1][0], best[0][:number]]).negative?
        best = [obj, hit]
      end
    end
    visit = lambda do |node|
      entry = test_node(node, origin, direction, kind, counted)
      next if entry.nil? || entry > @far || (best && entry > best[1][0])
      if node[:objects]
        node[:objects].each(&consider)
      else
        visit.call(node[:left])
        visit.call(node[:right])
      end
    end
    @planes.each(&consider)
    visit.call(@root) if @root
    best
  end

  def occluders(origin, direction, distance, counted = false)
    found = []
    consider = lambda do |obj|
      hit = test_object(obj, origin, direction, 'shadow', counted)
      if hit && hit[0] < distance
        found << obj
        @object_counts[obj[:number] - 1][:shadow] += 1 if counted
      end
    end
    visit = lambda do |node|
      entry = test_node(node, origin, direction, 'shadow', counted)
      next if entry.nil? || entry >= distance
      if node[:objects]
        node[:objects].each(&consider)
      else
        visit.call(node[:left])
        visit.call(node[:right])
      end
    end
    @planes.each(&consider)
    visit.call(@root) if @root
    found.sort_by { |obj| obj[:number] }
  end

  def camera_ray(qx, qy)
    hw, hh = @scene.view
    u = ((qx - 2 * @width) * hw).div(2 * @width)
    v = ((2 * @height - qy) * hh).div(2 * @height)
    [@scene.eye, norm(add(add(@scene.forward, sc(@scene.right, u)), sc(@scene.up, v)))]
  end

  def intersection_info(nearest, origin, direction)
    obj, intersection = nearest
    distance = intersection[0]
    point = add(origin, sc(direction, distance))
    outward = outward_normal(obj, point, direction, intersection)
    front = dot(outward, direction) <= 0
    { object: obj, distance: distance, point: point, normal: front ? outward : neg(outward),
      front: front, base: base_color(obj[:material], point) }
  end

  def light_samples(light, point)
    return [[light[:direction], @far, light[:intensity]]] if light[:kind] == 'sun'
    positions = []
    if light[:kind] == 'area'
      k = light[:divisions]
      k.times do |j|
        k.times do |i|
          position = 3.times.map do |a|
            light[:position][a] + ((2 * i + 1) * light[:u][a]).div(2 * k) +
              ((2 * j + 1) * light[:v][a]).div(2 * k)
          end
          positions << position
        end
      end
    else
      positions << light[:position]
    end
    positions.map do |position|
      relative = sub(position, point)
      [norm(relative), length(relative), light[:intensity].div(light[:samples])]
    end
  end

  def cone_factor(light, direction)
    return S unless light[:kind] == 'spot'
    cosine = -dot(direction, light[:direction])
    return 0 if cosine <= light[:outer]
    return S if cosine >= light[:inner]
    ((cosine - light[:outer]) * S).div(light[:inner] - light[:outer])
  end

  def sample_contribution(light, sample, info, view, pixel)
    direction, distance, intensity = sample
    ndl = dot(info[:normal], direction)
    counters = @light_counts[light[:number] - 1]
    if ndl <= 0
      counters[:backfacing] += 1 if pixel
      return [0, 0, 0]
    end
    factor = cone_factor(light, direction)
    if factor.zero?
      counters[:outside] += 1 if pixel
      return [0, 0, 0]
    end
    if pixel
      @rays['shadow'] += 1
      pixel[:rays] += 1
      counters[:shadow_rays] += 1
    end
    blockers = occluders(info[:point], direction, distance, !pixel.nil?)
    blockers.each { |obj| factor = mul(factor, obj[:material].kt) }
    if factor.zero?
      counters[:blocked] += 1 if pixel
      return [0, 0, 0]
    end
    counters[:attenuated] += 1 if pixel && !blockers.empty?
    diffuse, specular = phong(info[:object][:material], info[:normal], direction, view, ndl, intensity, factor)
    [1, diffuse, specular]
  end

  def local_color(info, direction, pixel)
    info[:lighting] = @lights.map do |light|
      lit = diffuse = specular = 0
      light_samples(light, info[:point]).each do |sample|
        count, dif, spe = sample_contribution(light, sample, info, neg(direction), pixel)
        lit += count
        diffuse += dif
        specular += spe
      end
      [lit, diffuse, specular]
    end
    diffuse = info[:lighting].sum { |item| item[1] }
    specular = info[:lighting].sum { |item| item[2] }
    raw = info[:base].map { |c| (c * (@scene.ambient + diffuse)).div(S) + (255 * specular).div(S) }
    @clamped += raw.count { |c| c > 255 } if pixel
    info[:illumination] = info[:lighting].count { |item| item[0].positive? }
    raw.map { |c| [c, 255].min }
  end

  def apply_fog(color, distance)
    return color unless @scene.fog
    r, g, b, start, finish = @scene.fog
    factor = if distance <= start then 0
             elsif distance >= finish then S
             else ((distance - start) * S).div(finish - start)
             end
    mix([color, S - factor], [[r, g, b], factor])
  end

  def trace(origin, direction, kind = 'primary', depth = 0, pixel = nil, record = nil)
    if pixel
      @rays[kind] += 1
      @depth_counts[depth] += 1
      pixel[:rays] += 1
      pixel[:depth] = [pixel[:depth], depth].max
    end
    record << "ray #{kind} #{depth} origin #{origin.join(' ')} direction #{direction.join(' ')}" if record
    hit = nearest(origin, direction, kind, !pixel.nil?)
    unless hit
      @misses[kind] += 1 if pixel
      color = @scene.background
      record.concat(['miss', "color #{color.join(' ')}"]) if record
      return { color: color, hit: nil }
    end
    info = intersection_info(hit, origin, direction)
    obj = info[:object]
    @object_counts[obj[:number] - 1][kind == 'primary' ? :primary : :secondary] += 1 if pixel
    local = local_color(info, direction, pixel)
    if record
      record << "hit #{obj[:label]} t #{info[:distance]} point #{info[:point].join(' ')} normal #{info[:normal].join(' ')} base #{info[:base].join(' ')}"
      @lights.zip(info[:lighting]).each do |light, (lit, diffuse, specular)|
        record << "light #{light[:number]} lit #{lit} of #{light[:samples]} diffuse #{diffuse} specular #{specular}"
      end
      record << "local #{local.join(' ')}"
    end
    material = obj[:material]
    color = local
    if depth < @max_depth && (material.kr.positive? || material.kt.positive?)
      wr, wt, transmitted, internal = refraction(material, direction, info[:normal], info[:front])
      if internal
        @total_internal_reflections += 1 if pixel
        record << 'total_internal_reflection' if record
      end
      local_weight = S - material.kr - material.kt
      record << "weights #{local_weight} #{wr} #{wt}" if record
      reflected_color = refracted_color = BLACK
      reflected_color = trace(info[:point], reflected(direction, info[:normal]), 'reflection', depth + 1, pixel, record)[:color] if wr.positive?
      refracted_color = trace(info[:point], transmitted, 'refraction', depth + 1, pixel, record)[:color] if wt.positive?
      color = mix([local, local_weight], [reflected_color, wr], [refracted_color, wt])
    end
    color = apply_fog(color, info[:distance])
    record << "color #{color.join(' ')}" if record
    { color: color, hit: info }
  end

  def render
    @height.times do |y|
      @width.times do |x|
        pixel = { x: x, y: y, rays: 0, depth: 0, samples: 1, label: '.' }
        result = trace(*camera_ray(4 * x + 2, 4 * y + 2), 'primary', 0, pixel)
        pixel[:center] = pixel[:color] = result[:color]
        pixel[:hit] = result[:hit]
        if result[:hit]
          pixel[:label] = result[:hit][:object][:label]
          @light_counts.zip(result[:hit][:lighting]).each { |counts, lighting| counts[:pixels] += 1 if lighting[0].positive? }
        end
        @pixels << pixel
      end
    end
    @pixels.each do |pixel|
      x, y = pixel.values_at(:x, :y)
      boundary = [[x, y - 1], [x, y + 1], [x - 1, y], [x + 1, y]].any? do |nx, ny|
        next false unless nx.between?(0, @width - 1) && ny.between?(0, @height - 1)
        other = @pixels[ny * @width + nx]
        other[:label] != pixel[:label] || other[:center].zip(pixel[:center]).map { |a, b| (a - b).abs }.max > @contrast
      end
      next unless boundary
      @supersampled += 1
      pixel[:samples] = 4
      colors = [[1, 1], [3, 1], [1, 3], [3, 3]].map do |dx, dy|
        trace(*camera_ray(4 * x + dx, 4 * y + dy), 'primary', 0, pixel)[:color]
      end
      pixel[:color] = 3.times.map { |a| colors.sum { |color| color[a] }.div(4) }
    end
  end

  def write_lines(path, lines)
    File.write(path, lines.empty? ? '' : lines.join("\n") + "\n")
  end

  def write_netpbm(path, magic, values)
    lines = [magic, "#{@width} #{@height}", '255']
    values.each_slice(@width) { |row| lines << row.flatten.join(' ') }
    write_lines(path, lines)
  end

  def write_map(path, values)
    write_lines(path, values.each_slice(@width).map(&:join))
  end

  def distance_range
    distances = @pixels.filter_map { |pixel| pixel[:hit] && pixel[:hit][:distance] }
    distances.empty? ? nil : distances.minmax
  end

  def mean_color(pixels)
    3.times.map { |a| pixels.sum { |pixel| pixel[:color][a] }.div(pixels.length) }
  end

  def write_images(folder)
    minimum, maximum = distance_range
    max_cost = @pixels.map { |p| p[:rays] }.max
    depth, normals, albedo, lights = [], [], [], []
    @pixels.each do |pixel|
      hit = pixel[:hit]
      if hit
        depth << (minimum == maximum ? 255 : 255 - (235 * (hit[:distance] - minimum)).div(maximum - minimum))
        normals << hit[:normal].map { |a| ((a + S) * 255).div(2 * S).clamp(0, 255) }
        albedo << hit[:base]
        lights << hit[:illumination].to_s
      else
        depth << 0
        normals << BLACK
        albedo << BLACK
        lights << '.'
      end
    end
    { 'image.ppm' => ['P3', @pixels.map { |p| p[:color] }], 'depth.pgm' => ['P2', depth],
      'normal.ppm' => ['P3', normals], 'albedo.ppm' => ['P3', albedo],
      'cost.pgm' => ['P2', @pixels.map { |p| (255 * p[:rays]).div(max_cost) }] }.each do |name, (magic, values)|
      write_netpbm(File.join(folder, name), magic, values)
    end
    write_map(File.join(folder, 'object_map.txt'), @pixels.map { |p| p[:label] })
    write_map(File.join(folder, 'light_map.txt'), lights)
    write_map(File.join(folder, 'ray_depth.txt'), @pixels.map { |p| p[:depth].to_s })
  end

  def statistics
    lines = ["image #{@width} #{@height}", "supersampled #{@supersampled}"]
    lines << "rays #{RAY_KINDS.map { |k| "#{k} #{@rays[k]}" }.join(' ')} total #{@rays.values.sum}"
    lines << "misses #{RAY_KINDS.first(3).map { |k| "#{k} #{@misses[k]}" }.join(' ')}"
    lines << "depth #{@depth_counts.join(' ')}"
    RAY_KINDS.each { |k| lines << "tests #{k} nodes #{@tests[k][:nodes]} objects #{@tests[k][:objects]}" }
    lines << "total_internal_reflection #{@total_internal_reflections}"
    lines << "clamped #{@clamped}"
    distances = distance_range
    lines << "distance #{distances ? distances.join(' ') : 'none'}"
    lines << "max_pixel_rays #{@pixels.map { |p| p[:rays] }.max}"
    lines << "mean #{mean_color(@pixels).join(' ')}"
    histogram = Array.new(8, 0)
    @pixels.each do |pixel|
      r, g, b = pixel[:color]
      histogram[(299 * r + 587 * g + 114 * b).div(1000).div(32)] += 1
    end
    lines << "histogram #{histogram.join(' ')}"
    @nodes.each do |node|
      role = node[:objects] ? "leaf #{node[:objects].map { |obj| obj[:label] }.join}" : 'inner'
      lines << "node #{node[:depth]} #{role} box #{node[:bounds].flatten.join(' ')} visits #{node[:visits]}"
    end
    @objects.zip(@object_counts).each do |obj, counts|
      pixels = @pixels.select { |p| p[:label] == obj[:label] }
      box = color = 'none'
      unless pixels.empty?
        xs, ys = pixels.map { |p| p[:x] }, pixels.map { |p| p[:y] }
        box = [xs.min, ys.min, xs.max, ys.max].join(' ')
        color = mean_color(pixels).join(' ')
      end
      lines << "object #{obj[:label]} #{obj[:kind]} primary #{counts[:primary]} secondary #{counts[:secondary]} shadow #{counts[:shadow]} pixels #{pixels.length} box #{box} color #{color}"
    end
    @lights.zip(@light_counts).each do |light, counts|
      lines << "light #{light[:number]} #{light[:kind]} samples #{light[:samples]} #{LIGHT_COUNTS.map { |k| "#{k} #{counts[k]}" }.join(' ')}"
    end
    lines
  end

  def queries(path)
    lines = []
    File.foreach(path, chomp: true).with_index(1) do |line, number|
      lines << "query #{number} #{line}"
      kind, *args = line.split
      if kind == 'object'
        obj = @objects.find { |o| o[:label] == args[0] }
        suffix = obj[:bounds] ? "#{obj[:bounds].flatten.join(' ')} leaf #{obj[:leaf_depth]}" : 'none leaf none'
        lines << "#{obj[:kind]} material #{obj[:material].name} bounds #{suffix}"
        next
      end
      values = args.map(&:to_i)
      case kind
      when 'pixel'
        x, y = values
        p = @pixels[y * @width + x]
        lines << "label #{p[:label]} distance #{p[:hit] ? p[:hit][:distance] : 'none'} color #{p[:color].join(' ')} samples #{p[:samples]} rays #{p[:rays]}"
      when 'trace'
        x, y = values
        trace(*camera_ray(4 * x + 2, 4 * y + 2), 'primary', 0, nil, lines)
      when 'ray'
        trace(values[0, 3], norm(values[3, 3]), 'primary', 0, nil, lines)
      when 'visible'
        relative = sub(values, @scene.eye)
        direction = norm(relative)
        visibility = occluders(@scene.eye, direction, length(relative) - @epsilon).empty? ? 'yes' : 'no'
        first = nearest(@scene.eye, direction)
        lines << "#{visibility} first #{first ? "#{first[0][:label]} t #{first[1][0]}" : 'none'}"
      when 'shadow'
        @lights.each do |light|
          total_factor = 0
          numbers = {}
          light_samples(light, values).each do |direction, distance, _|
            factor = cone_factor(light, direction)
            occluders(values, direction, distance).each do |obj|
              numbers[obj[:number]] = true
              factor = mul(factor, obj[:material].kt)
            end
            total_factor += factor
          end
          labels = @objects.select { |o| numbers[o[:number]] }.map { |o| o[:label] }.join
          lines << "light #{light[:number]} factor #{total_factor} occluders #{labels.empty? ? 'none' : labels}"
        end
      when 'region'
        x0, y0, x1, y1 = values
        pixels = (y0..y1).flat_map { |y| (x0..x1).map { |x| @pixels[y * @width + x] } }
        lines << "pixels #{pixels.length} mean #{mean_color(pixels).join(' ')}"
        (@objects.map { |obj| obj[:label] } + ['.']).each do |label|
          count = pixels.count { |p| p[:label] == label }
          lines << "label #{label} #{count}" if count.positive?
        end
      end
    end
    lines
  end
end

if $PROGRAM_NAME == __FILE__
  settings = File.readlines('input/render.txt', chomp: true).to_h do |line|
    key, *values = line.split
    [key, values.map(&:to_i)]
  end
  renderer = Renderer.new(Scene.new('input/scene.txt'), settings)
  renderer.render
  FileUtils.mkdir_p('output')
  renderer.write_images('output')
  renderer.write_lines('output/stats.txt', renderer.statistics)
  renderer.write_lines('output/queries.txt', renderer.queries('input/queries.txt'))
end
