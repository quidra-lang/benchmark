require 'fileutils'
require_relative 'pgm_io'
require_relative 'costs'
require_relative 'aggregation'
require_relative 'refinement'
require_relative 'evaluation'

module Stereo
  extend self
  include Refinement
  include Evaluation
  METHODS = %w[sad ssd census sgm fusion wta_final sgm_final].freeze
  SELECTION = METHODS.first(4).freeze
  REASONS = { 'textureless' => 50, 'nonunique' => 100, 'outside' => 150, 'mismatch' => 200, 'occluded' => 255 }.freeze
  SOURCES = %w[kept median background interpolated none].freeze

  def lower_median(values)
    values.sort[(values.length - 1) / 2]
  end

  def coordinates(width, height)
    height.times { |y| width.times { |x| yield x, y, y * width + x } }
  end

  def neighbors4(p, width, height)
    y, x = p.divmod(width)
    [[x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]].filter_map do |xx, yy|
      yy * width + xx if xx.between?(0, width - 1) && yy.between?(0, height - 1)
    end
  end

  def select_disparities(volume, strengths, width, height, params)
    minimum, maximum = params.values_at('disparity_min', 'disparity_max')
    candidates = (minimum..maximum).to_a
    right = Array.new(volume.length)
    coordinates(width, height) do |x, _y, p|
      right[p] = candidates.select { |d| x + d < width }.min_by { |d| [volume[p + d][d - minimum], d] }
    end
    image = Array.new(volume.length, 0)
    reasons = image.dup
    margins = image.dup
    differences = Array.new(4, 0)
    bounds = 0
    coordinates(width, height) do |x, _y, p|
      costs = volume[p]
      best = candidates.min_by { |d| [costs[d - minimum], d] }
      first = costs[best - minimum]
      second = candidates.filter_map { |d| costs[d - minimum] if (d - best).abs >= 2 }.min
      bounds += 1 if best == minimum || best == maximum
      consistent = ->(d) { x >= d && (d - right[p - d]).abs <= params['lr_max_diff'] }
      reason = if strengths[p] < params['texture_threshold']
                 50
               elsif 100 * second <= (100 + params['uniqueness']) * first
                 100
               elsif x < best
                 150
               elsif !consistent.call(best)
                 candidates.any?(&consistent) ? 200 : 255
               else
                 image[p] = best
                 margins[p] = second - first
                 0
               end
      reasons[p] = reason
      differences[[(best - right[p - best]).abs, 3].min] += 1 if [0, 200, 255].include?(reason)
    end
    { image: image, reasons: reasons, margins: margins, lr: differences, bounds: bounds }
  end

  def choose_windows(left, right, cl, cr, strengths, width, height, truth, regions, params)
    selected, sweeps = {}, []
    SELECTION.first(3).each do |kind|
      best_key = nil
      params[kind + '_windows'].each do |window|
        volume = Costs.cost_volume(left, right, cl, cr, width, height, kind, window,
                                   params['disparity_min'], params['disparity_max'])
        selection = select_disparities(volume, strengths, width, height, params)
        selection[:window] = window
        score = evaluate(selection[:image], truth, regions['nonocc'])
        sweeps << { kind: kind, window: window, metrics: score, valid: selection[:image].count(&:positive?) }
        key = score.values_at(:bad1, :bad2)
        if best_key.nil? || (key <=> best_key).negative?
          best_key = key
          selected[kind] = selection
        end
      end
    end
    [selected, sweeps]
  end

  def semi_global(left, right, cl, cr, strengths, width, height, truth, regions, params)
    base = Costs.cost_volume(left, right, cl, cr, width, height, params['sgm_cost'], params['sgm_window'],
                             params['disparity_min'], params['disparity_max'])
    progress = []
    selected = nil
    total = Aggregation.cumulative_costs(base, left, width, height, params['sgm_paths'],
                                        params['p1'], params['p2'], params['p2_gamma']) do |costs, number|
      selected = select_disparities(costs, strengths, width, height, params)
      progress << { number: number, metrics: evaluate(selected[:image], truth, regions['nonocc']),
                    valid: selected[:image].count(&:positive?) }
    end
    selected[:window] = params['sgm_window']
    [selected, total, progress]
  end

  def connected_regions(image, width, height, maximum_difference)
    visited = Array.new(image.length, false)
    components = []
    image.each_index do |start|
      next if image[start].zero? || visited[start]
      visited[start] = true
      stack, component = [start], []
      until stack.empty?
        p = stack.pop
        component << p
        neighbors4(p, width, height).each do |q|
          next if image[q].zero? || visited[q] || (image[q] - image[p]).abs > maximum_difference
          visited[q] = true
          stack << q
        end
      end
      components << component
    end
    components
  end

  def ray_values(image, width, height, x, y, directions)
    directions.filter_map do |dx, dy|
      xx, yy = x + dx, y + dy
      found = nil
      while xx.between?(0, width - 1) && yy.between?(0, height - 1)
        value = image[yy * width + xx]
        if value.positive?
          found = value
          break
        end
        xx += dx
        yy += dy
      end
      found
    end
  end

  def postprocess(selection, width, height, params)
    original = selection[:image]
    removed = connected_regions(original, width, height, params['speckle_range']).select { |c| c.length < params['speckle_size'] }
    filtered = original.dup
    removed.each { |part| part.each { |p| filtered[p] = 0 } }
    medians = Array.new(original.length, 0)
    coordinates(width, height) do |x, y, p|
      next if filtered[p].zero?
      values = []
      ([y - 1, 0].max..[y + 1, height - 1].min).each do |yy|
        ([x - 1, 0].max..[x + 1, width - 1].min).each do |xx|
          value = filtered[yy * width + xx]
          values << value if value.positive?
        end
      end
      medians[p] = lower_median(values)
    end
    result = medians.dup
    sources = Array.new(original.length, 'none')
    coordinates(width, height) do |x, y, p|
      if medians[p].positive?
        sources[p] = medians[p] == original[p] ? 'kept' : 'median'
      else
        background = [150, 255].include?(selection[:reasons][p])
        directions = background ? [[-1, 0], [1, 0]] : Aggregation::DIRECTIONS
        values = ray_values(medians, width, height, x, y, directions)
        next if values.empty?
        result[p] = background ? values.min : lower_median(values)
        sources[p] = background ? 'background' : 'interpolated'
      end
    end
    { image: result, sources: sources, speckles: removed.length, speckle_pixels: removed.sum(&:length),
      median_changed: filtered.each_index.count { |p| filtered[p] != medians[p] },
      background: sources.count('background'), interpolated: sources.count('interpolated'), unfilled: sources.count('none') }
  end

  def fuse(selections, minimum_votes)
    votes = Array.new(5, 0)
    result = Array.new(selections['sad'][:image].length, 0)
    result.each_index do |p|
      values = SELECTION.map { |name| selections[name][:image][p] }.select(&:positive?)
      votes[values.length] += 1
      next if values.empty?
      median = lower_median(values)
      result[p] = median if values.count { |v| (v - median).abs <= 1 } >= minimum_votes
    end
    { image: result, votes: votes }
  end

  def extract_objects(image, truth, width, height, params)
    counts = truth.select(&:positive?).tally
    objects, small = [], 0
    connected_regions(image, width, height, params['object_range']).each do |part|
      if part.length < params['object_min_size']
        small += 1
        next
      end
      xs, ys = part.map { |p| p % width }, part.map { |p| p / width }
      values = part.map { |p| image[p] }
      median, total, n = lower_median(values), values.sum, part.length
      box = [xs.min, ys.min, xs.max, ys.max]
      layers = part.map { |p| truth[p] }.select(&:positive?).tally
      layer = layers.keys.min_by { |g| [-layers[g], g] }
      hits = layer ? layers[layer] : 0
      union = layer ? n + counts[layer] - hits : 0
      objects << { pixels: n, box: box, minimum: values.min, maximum: values.max, median: median,
                   mean: two_decimals(total, n), depth: two_decimals(params['focal_length'] * params['baseline'] * n, total),
                   width: two_decimals((box[2] - box[0] + 1) * params['baseline'], median),
                   height: two_decimals((box[3] - box[1] + 1) * params['baseline'], median),
                   truth: layer, hits: hits, union: union, first: part.min }
    end
    objects.sort_by! { |o| [-o[:median], -o[:pixels], o[:first]] }
    detected = objects.select { |o| o[:truth] && 2 * o[:hits] > o[:union] }.map { |o| o[:truth] }.uniq
    [objects, small, counts.keys.sort, detected]
  end

  def object_lines(objects, small, layers, detected)
    lines = ["objects #{objects.length} small #{small} pixels #{objects.sum { |o| o[:pixels] }}"]
    objects.each_with_index do |o, i|
      truth = o[:truth] ? "truth #{o[:truth]} iou #{ratio(o[:hits], o[:union])}" : 'truth - iou -'
      lines << "object #{i + 1} pixels #{o[:pixels]} box #{o[:box].join(' ')} disparity #{o[:minimum]} #{o[:maximum]} median #{o[:median]} mean #{o[:mean]} depth #{o[:depth]} size #{o[:width]} #{o[:height]} #{truth}"
    end
    missed = layers - detected
    lines << "layers #{layers.length} detected #{detected.length} missed #{missed.empty? ? '-' : missed.join(' ')}"
    lines
  end

  def sample_lines(methods, costs, truth, width, params)
    lines = ['x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth']
    focal, baseline = params.values_at('focal_length', 'baseline')
    params['sample_pixels'].each do |x, y|
      p = y * width + x
      values = [x, y] + SELECTION.map { |name| methods[name][:image][p].zero? ? '-' : methods[name][:image][p] }
      d = methods['sgm_final'][:image][p]
      if d.positive?
        refined, depth = subpixel(d, costs[p], params['disparity_min'], params['disparity_max'], focal, baseline)
        values.concat([d, methods['sgm_final'][:sources][p], refined, depth])
      else
        values.concat(['-', 'none', '-', '-'])
      end
      values.concat(truth[p].positive? ? [truth[p], two_decimals(focal * baseline, truth[p])] : ['-', '-'])
      lines << values.join(',')
    end
    lines
  end

  def input_summary(left, right, truth, strengths, width, height, regions, params)
    size = width * height
    delta = regions['nonocc'].map { |p| right[p - truth[p]] - left[p] }
    bias_sum = delta.sum
    bias = two_decimals(bias_sum.abs, delta.length)
    bias = '-' + bias if bias_sum.negative? && bias != '0.00'
    lines = ["image #{width} #{height}", "disparities #{params['disparity_min']} #{params['disparity_max']}"]
    { 'left' => left, 'right' => right }.each do |name, image|
      lines << "#{name} mean #{two_decimals(image.sum, size)} min #{image.min} max #{image.max}"
    end
    lines << "texture mean #{two_decimals(strengths.sum, size)} textureless #{strengths.count { |v| v < params['texture_threshold'] }}"
    lines << "ground_truth known #{regions['all'].length} nonocc #{regions['nonocc'].length} occluded #{regions['occluded'].length} disc #{regions['disc'].length} unknown #{size - regions['all'].length}"
    lines << "photometric pixels #{delta.length} mean_abs #{two_decimals(delta.sum(&:abs), delta.length)} bias #{bias}"
    lines
  end

  def region_line(region, score)
    "region #{region} pixels #{score[:pixels]} valid #{score[:valid]} bad1 #{ratio(score[:bad1], score[:pixels])} bad2 #{ratio(score[:bad2], score[:pixels])} mae #{score[:mae]} exact #{score[:exact]}"
  end

  def method_lines(name, method, truth, width, height, regions, metrics, params)
    image = method[:image]
    values = image.select(&:positive?)
    horizontal = vertical = 0
    coordinates(width, height) do |x, y, p|
      next if image[p].zero?
      horizontal += 1 if x + 1 < width && image[p + 1].positive? && (image[p] - image[p + 1]).abs >= 2
      vertical += 1 if y + 1 < height && image[p + width].positive? && (image[p] - image[p + width]).abs >= 2
    end
    distribution = values.empty? ? 'disparity min - max - median - distinct 0' : "disparity min #{values.min} max #{values.max} median #{lower_median(values)} distinct #{values.uniq.length}"
    lines = ["method #{name} valid #{values.length} invalid #{image.length - values.length}", distribution,
             "jumps horizontal #{horizontal} vertical #{vertical}"]
    if SELECTION.include?(name)
      counts = method[:reasons].tally
      lines << "window #{method[:window]} bounds #{method[:bounds]}"
      lines << 'reasons ' + REASONS.map { |reason, code| "#{reason} #{counts.fetch(code, 0)}" }.join(' ')
      lr = method[:lr]
      lines << "lr 0 #{lr[0]} 1 #{lr[1]} 2 #{lr[2]} 3+ #{lr[3]}"
    elsif name == 'fusion'
      lines << 'votes ' + (0..4).map { |n| "#{n} #{method[:votes][n]}" }.join(' ')
    else
      lines << "postprocess speckles #{method[:speckles]} #{method[:speckle_pixels]} median #{method[:median_changed]} background #{method[:background]} interpolated #{method[:interpolated]} unfilled #{method[:unfilled]}"
      SOURCES.each do |source|
        region = regions['all'].select { |p| method[:sources][p] == source }
        score = evaluate(image, truth, region)
        lines << "source #{source} pixels #{score[:pixels]} bad1 #{ratio(score[:bad1], score[:pixels])}"
      end
    end
    Evaluation::REGION_ORDER.each { |region| lines << region_line(region, metrics[name][region]) }
    focal, baseline = params.values_at('focal_length', 'baseline')
    errors = regions['nonocc'].filter_map do |p|
      (depth_hundredths(image[p], focal, baseline) - depth_hundredths(truth[p], focal, baseline)).abs if image[p].positive?
    end
    lines << if errors.empty?
               'depth_error pixels 0 mean - max -'
             else
               "depth_error pixels #{errors.length} mean #{two_decimals(errors.sum, 100 * errors.length)} max #{two_decimals(errors.max, 100)}"
             end
    counts = Array.new(5, 0)
    invalid = 0
    regions['all'].each do |p|
      if image[p].zero?
        invalid += 1
      else
        counts[[(image[p] - truth[p]).abs, 4].min] += 1
      end
    end
    lines << "errors 0 #{counts[0]} 1 #{counts[1]} 2 #{counts[2]} 3 #{counts[3]} 4+ #{counts[4]} invalid #{invalid}"
    lines
  end

  def evaluation_lines(left, right, truth, strengths, width, height, regions, methods, sweeps, progress, params)
    metrics = METHODS.to_h do |name|
      [name, Evaluation::REGION_ORDER.to_h { |region| [region, evaluate(methods[name][:image], truth, regions[region])] }]
    end
    lines = input_summary(left, right, truth, strengths, width, height, regions, params)
    (sweeps + progress).each do |item|
      score = item[:metrics]
      prefix = item[:kind] ? "sweep #{item[:kind]} window #{item[:window]}" : "paths #{item[:number]}"
      lines << "#{prefix} valid #{item[:valid]} bad1 #{ratio(score[:bad1], score[:pixels])} bad2 #{ratio(score[:bad2], score[:pixels])}"
    end
    METHODS.each { |name| lines.concat(method_lines(name, methods[name], truth, width, height, regions, metrics, params)) }
    Evaluation::REGION_ORDER.each do |region|
      names = METHODS.sort_by do |name|
        score = metrics[name][region]
        valid = score[:valid]
        [score[:bad1], score[:bad2], valid.zero? ? 1 : 0, valid.zero? ? 0 : Rational(score[:error_sum], valid), METHODS.index(name)]
      end
      lines << "ranking #{region} #{names.join(' ')}"
    end
    SELECTION.each do |name|
      reasons = methods[name][:reasons]
      tp = regions['occluded'].count { |p| [150, 255].include?(reasons[p]) }
      fp = regions['nonocc'].count { |p| [150, 255].include?(reasons[p]) }
      fn = regions['occluded'].length - tp
      lines << "occlusion #{name} tp #{tp} fp #{fp} fn #{fn} precision #{ratio(tp, tp + fp)} recall #{ratio(tp, tp + fn)}"
    end
    SELECTION.each do |name|
      method = methods[name]
      pixels = regions['nonocc'].select { |p| method[:image][p].positive? }.sort_by { |p| [-method[:margins][p], p] }
      [25, 50, 75, 100].each do |percent|
        n = (pixels.length * percent + 99) / 100
        bad = pixels.first(n).count { |p| (method[:image][p] - truth[p]).abs > 1 }
        margin = n.zero? ? '-' : method[:margins][pixels[n - 1]]
        lines << "confidence #{name} #{percent} pixels #{n} margin #{margin} bad1 #{ratio(bad, n)}"
      end
    end
    counts = truth.select(&:positive?).tally
    counts.keys.sort.each do |layer|
      region = regions['nonocc'].select { |p| truth[p] == layer }
      bad = METHODS.map { |name| evaluate(methods[name][:image], truth, region)[:bad1] }
      lines << "layer #{layer} pixels #{counts[layer]} nonocc #{region.length} bad1 #{bad.join(' ')}"
    end
    histogram = methods['sgm_final'][:image].tally
    (params['disparity_min']..params['disparity_max']).each { |d| lines << "histogram #{d} #{histogram.fetch(d, 0)}" }
    lines
  end

  def save_text(name, lines)
    File.write(File.join('output', name), lines.join("\n") + "\n")
  end

  def main
    width, height, left = PgmIO.read_pgm('input/left.pgm')
    _, _, right = PgmIO.read_pgm('input/right.pgm')
    _, _, truth = PgmIO.read_pgm('input/ground_truth.pgm')
    params = PgmIO.read_parameters
    regions = truth_regions(truth, width, height)
    strengths = Costs.texture(left, width, height, params['texture_window'])
    cl, cr = Costs.census(left, width, height), Costs.census(right, width, height)
    methods, sweeps = choose_windows(left, right, cl, cr, strengths, width, height, truth, regions, params)
    sgm, costs, progress = semi_global(left, right, cl, cr, strengths, width, height, truth, regions, params)
    methods['sgm'] = sgm
    methods['fusion'] = fuse(methods, params['fusion_min_votes'])
    methods['wta_final'] = postprocess(methods[params['wta_cost']], width, height, params)
    methods['sgm_final'] = postprocess(sgm, width, height, params)
    objects, small, layers, detected = extract_objects(methods['sgm_final'][:image], truth, width, height, params)
    FileUtils.mkdir_p('output')
    PgmIO.write_pgm('output/disparity_wta.pgm', width, height, methods['wta_final'][:image].map { |v| 8 * v })
    PgmIO.write_pgm('output/disparity_sgm.pgm', width, height, methods['sgm_final'][:image].map { |v| 8 * v })
    PgmIO.write_pgm('output/occlusion.pgm', width, height, sgm[:reasons])
    error = truth.each_index.map do |p|
      actual, expected = methods['sgm_final'][:image][p], truth[p]
      expected.zero? ? 0 : (actual.zero? ? 255 : 50 * ([(actual - expected).abs, 3].min + 1))
    end
    PgmIO.write_pgm('output/error_sgm.pgm', width, height, error)
    save_text('depth.csv', sample_lines(methods, costs, truth, width, params))
    save_text('evaluation.txt', evaluation_lines(left, right, truth, strengths, width, height, regions, methods, sweeps, progress, params))
    save_text('objects.txt', object_lines(objects, small, layers, detected))
  end
end

Stereo.main if $PROGRAM_NAME == __FILE__
