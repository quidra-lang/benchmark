require_relative 'dataset'
require_relative 'grid_index'
require_relative 'dbscan'
require_relative 'optics'
require_relative 'report'

module Density
  Setting = Struct.new(:name, :radius, :labels, :core, :kind, :groups, keyword_init: true) do
    def count
      groups.length
    end

    def noise
      labels.count(-1)
    end
  end

  class Program
    def distance(first, second)
      GridIndex.distance(@points[first], @points[second])
    end

    def suggested_radius(value)
      lower = 1
      upper = 1
      upper *= 2 while upper * upper < value
      while lower < upper
        middle = (lower + upper) / 2
        if middle * middle >= value
          upper = middle
        else
          lower = middle + 1
        end
      end
      lower
    end

    def k_distances
      nearest = @points.each_index.map do |point|
        @points.each_index.filter_map { |other| distance(point, other) unless point == other }.sort.first(2 * @minimum)
      end
      @curves = Array.new(2 * @minimum + 1)
      (1..2 * @minimum).each do |neighbour|
        values = nearest.map { |distances| distances[neighbour - 1] }
        order = @points.each_index.sort_by { |point| [-values[point], @points[point].id] }
        top = values[order.first]
        bottom = values[order.last]
        crosses = order.each_with_index.map do |point, rank|
          ((@count - 1) * (values[point] - top) - (bottom - top) * rank).abs
        end
        knee = order.each_index.min_by { |rank| [-crosses[rank], rank] }
        @curves[neighbour] = { values: values, order: order, rank: knee + 1,
                               point: order[knee], value: values[order[knee]], cross: crosses[knee],
                               eps: suggested_radius(values[order[knee]]) }
      end
      @k = @minimum - 1
      @curve = @curves[@k]
      @kd = @curve[:values]
    end

    def setting(name, radius, labels, core, kind)
      groups = Array.new(labels.max + 1) { [] }
      labels.each_with_index { |label, point| groups[label] << point if label >= 0 }
      Setting.new(name: name, radius: radius, labels: labels, core: core, kind: kind, groups: groups)
    end

    def extract(radius)
      threshold = radius * radius
      labels = Array.new(@count, -1)
      cluster = -1
      core = @optics[:core].map { |value| !value.nil? && value <= threshold }
      @optics[:order].each do |point|
        reach = @optics[:reach][point]
        if reach.nil? || reach > threshold
          if core[point]
            cluster += 1
            labels[point] = cluster
          end
        else
          labels[point] = cluster
        end
      end
      [labels, core]
    end

    def greater(first, second)
      return false if second.nil?
      return true if first.nil?

      first > second
    end

    def maximum(first, second)
      first.nil? || second.nil? ? nil : [first, second].max
    end

    def xle(first, second)
      return true if second.nil?
      return false if first.nil?

      @beta * first <= @alpha * second
    end

    def extend_region(start, steep, opposite)
      finish = start
      quiet = 0
      (start..@count).each do |position|
        if steep[position]
          finish = position
          quiet = 0
        elsif opposite[position]
          break
        else
          quiet += 1
          break if quiet > @minimum
        end
      end
      finish
    end

    def xi_clusters
      numerator, denominator = @params['XI']
      @alpha = (denominator - numerator) * (denominator - numerator)
      @beta = denominator * denominator
      reach = [nil] + @optics[:order].map { |point| @optics[:reach][point] } + [nil]
      steep_up = Array.new(@count + 1, false)
      steep_down = Array.new(@count + 1, false)
      up = Array.new(@count + 1, false)
      down = Array.new(@count + 1, false)
      (1..@count).each do |position|
        first = reach[position]
        second = reach[position + 1]
        next if first.nil? && second.nil?

        steep_up[position] = xle(first, second)
        steep_down[position] = xle(second, first)
        up[position] = greater(second, first)
        down[position] = greater(first, second)
      end
      down_areas = []
      areas = []
      clusters = []
      index = 1
      mib = 0
      (1..@count).each do |position|
        next if position < index || (!steep_down[position] && !steep_up[position])

        (index..position).each { |current| mib = maximum(mib, reach[current]) }
        if mib.nil?
          down_areas.clear
        else
          down_areas.select! { |area| xle(mib, reach[area[:start]]) }
          down_areas.each { |area| area[:height] = maximum(area[:height], mib) }
        end
        if steep_down[position]
          finish = extend_region(position, steep_down, up)
          areas << ['down', position, finish]
          down_areas << { start: position, finish: finish, height: 0 }
          index = finish + 1
          mib = reach[index]
        else
          finish = extend_region(position, steep_up, down)
          areas << ['up', position, finish]
          index = finish + 1
          mib = reach[index]
          candidates = []
          down_areas.each do |area|
            left = area[:start]
            right = finish
            next unless xle(area[:height], reach[right + 1])

            wall = reach[area[:start]]
            if xle(reach[right + 1], wall)
              left += 1 while left < area[:finish] && greater(reach[left + 1], reach[right + 1])
            elsif xle(wall, reach[right + 1])
              right -= 1 while right > position && greater(reach[right - 1], wall)
            end
            if right - left + 1 >= @params['XI_MIN_SIZE'] && left <= area[:finish] && right >= position
              candidates << { start: left, finish: right, size: right - left + 1 }
            end
          end
          clusters.concat(candidates.reverse)
        end
      end
      position_labels = Array.new(@count + 1)
      next_label = 0
      clusters.each do |cluster|
        interval = cluster[:start]..cluster[:finish]
        if interval.all? { |position| position_labels[position].nil? }
          interval.each { |position| position_labels[position] = next_label }
          cluster[:label] = next_label
          next_label += 1
        end
        cluster[:left] = reach[cluster[:start]]
        cluster[:right] = reach[cluster[:finish] + 1]
        cluster[:valley] = reach[(cluster[:start] + 1)..cluster[:finish]].compact.min
      end
      clusters.each_with_index do |cluster, number|
        parents = clusters.each_index.select do |other|
          candidate = clusters[other]
          other != number && candidate[:start] <= cluster[:start] && candidate[:finish] >= cluster[:finish] &&
            (candidate[:size] > cluster[:size] || (candidate[:size] == cluster[:size] && other > number))
        end
        cluster[:parent] = parents.min_by { |other| [clusters[other][:size], other] }
      end
      labels = Array.new(@count, -1)
      @optics[:order].each_with_index { |point, position| labels[point] = position_labels[position + 1] || -1 }
      { labels: labels, clusters: clusters, areas: areas }
    end

    def build_settings
      radii = (@params['EPS'] + [@curve[:eps], @params['OPTICS_MAX_EPS']]).uniq.sort
      @grids = radii.to_h { |radius| [radius, GridIndex.new(@points, radius)] }
      @db_settings = @params['EPS'].map do |radius|
        labels, core = DBSCAN.cluster(@grids[radius].neighbours, @minimum)
        setting("db#{radius}", radius, labels, core, :dbscan)
      end
      labels, core = DBSCAN.cluster(@grids[@curve[:eps]].neighbours, @minimum)
      @knee = setting("knee#{@curve[:eps]}", @curve[:eps], labels, core, :dbscan)
      @db_settings << @knee
      @optics = OPTICS.run(@points, @grids[@params['OPTICS_MAX_EPS']], @minimum)
      @extractions = @params['EXTRACT_EPS'].map do |radius|
        labels, core = extract(radius)
        setting("op#{radius}", radius, labels, core, :extraction)
      end
      @xi = xi_clusters
      xi_core = @optics[:core].map { |value| !value.nil? }
      @xi_setting = setting('xi', @params['OPTICS_MAX_EPS'], @xi[:labels], xi_core, :xi)
      @settings = @db_settings + @extractions + [@xi_setting]
    end

    def turn(origin, first, second)
      o = @points[origin]
      a = @points[first]
      b = @points[second]
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    end

    def convex_hull(members)
      sorted = members.sort_by { |point| [@points[point].x, @points[point].y] }
      return sorted if sorted.length <= 2

      chains = [sorted, sorted.reverse].map do |sequence|
        chain = []
        sequence.each do |point|
          chain.pop while chain.length >= 2 && turn(chain[-2], chain[-1], point) <= 0
          chain << point
        end
        chain.take(chain.length - 1)
      end
      chains.flatten(1)
    end

    def cluster_lines(current, label, members)
      size = members.length
      sx = members.sum { |point| @points[point].x }
      sy = members.sum { |point| @points[point].y }
      core = members.count { |point| current.core[point] }
      medoid = members.min_by do |point|
        dx = size * @points[point].x - sx
        dy = size * @points[point].y - sy
        [dx * dx + dy * dy, @points[point].id]
      end
      xs = members.map { |point| @points[point].x }
      ys = members.map { |point| @points[point].y }
      bbox = [xs.min, ys.min, xs.max, ys.max]
      area = (bbox[2] - bbox[0] + 1) * (bbox[3] - bbox[1] + 1)
      vertices = convex_hull(members)
      twice_area = vertices.each_index.sum do |index|
        first = @points[vertices[index]]
        second = @points[vertices[(index + 1) % vertices.length]]
        first.x * second.y - second.x * first.y
      end.abs
      diameter = vertices.combination(2).reduce(0) { |largest, (first, second)| [largest, distance(first, second)].max }
      [
        "cluster #{label} #{character(label)} size #{size} core #{core} border #{size - core} centroid #{Report.fraction(sx, size)} #{Report.fraction(sy, size)} medoid #{@points[medoid].id}",
        "  bbox #{bbox.join(' ')} area #{area} density #{Report.fraction(size, area)}",
        "  hull #{vertices.length} hull_area #{twice_area / 2}.#{twice_area.even? ? '0' : '5'} diameter_sq #{diameter} diameter #{Report.root(diameter)}"
      ]
    end

    def check_lines(current)
      neighbours = @grids[current.radius].neighbours
      checks = [true, true, true]
      isolated = 0
      ambiguous = []
      @points.each_index do |point|
        labels = neighbours[point].filter_map { |other| current.labels[other] if current.core[other] }.uniq
        if current.core[point]
          checks[0] = false unless labels.all? { |label| label == current.labels[point] }
        elsif current.labels[point] >= 0
          checks[1] = false unless labels.include?(current.labels[point])
          others = labels.reject { |label| label == current.labels[point] }.sort
          ambiguous << [point, others] unless others.empty?
        else
          checks[2] = false unless labels.empty?
          isolated += 1 if neighbours[point].length == 1
        end
      end
      lines = ["check #{checks.map { |passed| passed ? 'ok' : 'fail' }.join(' ')}",
               "isolated #{isolated}", "ambiguous #{ambiguous.length}"]
      ambiguous.each do |point, others|
        lines << "  #{@points[point].id} cluster #{current.labels[point]} also #{others.join(' ')}"
      end
      lines
    end

    def setting_lines(current)
      clustered_core = @points.each_index.count { |point| current.labels[point] >= 0 && current.core[point] }
      lines = ["setting #{current.name} eps #{current.radius} clusters #{current.count} noise #{current.noise} core #{clustered_core} border #{@count - current.noise - clustered_core}"]
      current.groups.each_with_index { |members, label| lines.concat(cluster_lines(current, label, members)) }
      lines.concat(check_lines(current)) if current.kind == :dbscan
      lines
    end

    def hierarchy_lines
      lines = ['hierarchy']
      ordered = @db_settings.each_with_index.sort_by { |current, index| [current.radius, index] }.map(&:first)
      ordered.each_cons(2) do |first, second|
        origins = Array.new(second.count) { [] }
        first.groups.each_with_index do |members, label|
          representative = members.find { |point| first.core[point] }
          origins[second.labels[representative]] << label
        end
        lines << "#{first.name} -> #{second.name}"
        origins.each_with_index do |members, label|
          lines << "  #{label} <- #{members.empty? ? '-' : members.join(' ')}"
        end
      end
      lines
    end

    def comparison_lines
      lines = ['optics_vs_dbscan']
      @extractions.each do |first|
        second = @db_settings.find { |candidate| candidate.radius == first.radius }
        next if second.nil?

        pairs = @points.each_index.filter_map do |point|
          [first.labels[point], second.labels[point]] if first.core[point]
        end.uniq
        left_counts = pairs.map(&:first).tally
        right_counts = pairs.map(&:last).tally
        same = left_counts.keys.sort == (0...first.count).to_a &&
               right_counts.keys.sort == (0...second.count).to_a &&
               left_counts.values.all? { |count| count == 1 } && right_counts.values.all? { |count| count == 1 }
        noise = @points.each_index.count { |point| first.labels[point] == -1 && second.labels[point] >= 0 }
        moved = '-'
        if same
          correspondence = pairs.to_h
          moved = @points.each_index.count do |point|
            first.labels[point] >= 0 && correspondence[first.labels[point]] != second.labels[point]
          end
        end
        lines << "#{first.name} #{second.name} core_partition #{same ? 'same' : 'different'} border_as_noise #{noise} moved #{moved}"
      end
      lines
    end

    def optics_summary
      components = []
      @optics[:order].each do |point|
        components << 0 if @optics[:reach][point].nil?
        components[-1] += 1
      end
      ["optics max_eps #{@params['OPTICS_MAX_EPS']} core #{@optics[:core].count { |value| !value.nil? }} components #{components.length} singletons #{components.count(1)} largest #{components.max}"]
    end

    def sweep_lines
      lines = ["sweep max_eps #{@params['OPTICS_MAX_EPS']}", 'eps clusters noise largest']
      ranges = []
      (1..@params['OPTICS_MAX_EPS']).each do |radius|
        labels, = extract(radius)
        sizes = labels.reject(&:negative?).tally.values
        clusters = sizes.length
        lines << "#{radius} #{clusters} #{labels.count(-1)} #{sizes.max || 0}"
        if !ranges.empty? && ranges.last[:clusters] == clusters
          ranges.last[:finish] = radius
        else
          ranges << { start: radius, finish: radius, clusters: clusters }
        end
      end
      stable = ranges.select { |range| range[:clusters] >= 2 }.min_by do |range|
        [-(range[:finish] - range[:start] + 1), range[:start]]
      end
      lines << if stable
                 "stable clusters #{stable[:clusters]} eps #{stable[:start]} #{stable[:finish]} length #{stable[:finish] - stable[:start] + 1}"
               else
                 'stable -'
               end
      lines
    end

    def xi_lines
      lines = ["xi #{@params['XI'].join('/')} min_size #{@params['XI_MIN_SIZE']} steep_areas #{@xi[:areas].length}"]
      @xi[:areas].each { |area| lines << area.join(' ') }
      lines << "xi_clusters #{@xi[:clusters].length}"
      @xi[:clusters].each_with_index do |cluster, number|
        lines << "#{number} start #{cluster[:start]} end #{cluster[:finish]} size #{cluster[:size]} label #{cluster[:label] || '-'} parent #{cluster[:parent] || '-'} walls #{Report.root(cluster[:left])} #{Report.root(cluster[:right])} valley #{Report.root(cluster[:valley])}"
      end
      lines
    end

    def outlier_lines
      core = @points.each_index.select { |point| @knee.core[point] }
      outliers = @points.each_index.filter_map do |point|
        next unless @knee.labels[point] == -1

        nearest = core.min_by { |other| [distance(point, other), @points[other].id] }
        [point, nearest, distance(point, nearest)]
      end.sort_by { |point, _, squared| [-squared, @points[point].id] }
      lines = ["outliers #{@knee.name} count #{outliers.length}"]
      outliers.each do |point, nearest, squared|
        lines << "#{@points[point].id} nearest_core #{@points[nearest].id} cluster #{@knee.labels[nearest]} dist_sq #{squared} dist #{Report.root(squared)}"
      end
      lines
    end

    def gap_lines
      lines = ["gaps #{@knee.name}"]
      @knee.groups.each_index.to_a.combination(2) do |first_label, second_label|
        best = nil
        @knee.groups[first_label].each do |first|
          @knee.groups[second_label].each do |second|
            candidate = [distance(first, second), first, second]
            best = candidate if best.nil? || (candidate <=> best).negative?
          end
        end
        squared, first, second = best
        lines << "#{first_label} #{second_label} dist_sq #{squared} dist #{Report.root(squared)} between #{@points[first].id} #{@points[second].id}"
      end
      lines
    end

    def contingency_lines
      table = Array.new(@knee.count + 1) { Array.new(@xi_setting.count + 1, 0) }
      @points.each_index { |point| table[@knee.labels[point] + 1][@xi_setting.labels[point] + 1] += 1 }
      columns = (-1...@xi_setting.count).to_a
      lines = ["contingency #{@knee.name} xi", "columns #{columns.join(' ')}"]
      (-1...@knee.count).each { |row| lines << "#{row} #{table[row + 1].join(' ')}" }
      @xi_setting.groups.each_with_index do |members, column|
        row = @knee.groups.each_index.min_by { |candidate| [-table[candidate + 1][column + 1], candidate] }
        shared = table[row + 1][column + 1]
        union = @knee.groups[row].length + members.length - shared
        lines << "match #{column} #{row} shared #{shared} jaccard #{Report.fraction(shared, union)}"
      end
      lines
    end

    def pairs_sum(counts)
      counts.sum { |count| count * (count - 1) / 2 }
    end

    def ari_lines
      lines = ['ari']
      @settings.combination(2) do |first, second|
        shared = pairs_sum(first.labels.zip(second.labels).tally.values)
        a = pairs_sum(first.labels.tally.values)
        b = pairs_sum(second.labels.tally.values)
        total = @count * (@count - 1) / 2
        numerator = 2 * (total * shared - a * b)
        denominator = total * (a + b) - 2 * a * b
        if denominator.zero?
          numerator = denominator = 1
        else
          divisor = numerator.abs.gcd(denominator)
          numerator /= divisor
          denominator /= divisor
        end
        lines << "#{first.name} #{second.name} #{Report.fraction(numerator, denominator)} #{Report.ari(numerator, denominator)}"
      end
      lines
    end

    def character(label)
      return '.' if label == -1
      return (65 + label).chr if label < 26
      return (97 + label - 26).chr if label < 52

      '#'
    end

    def grid_lines
      lines = ['grid']
      @grids.each do |radius, grid|
        counts = grid.neighbours.map(&:length)
        pairs = (counts.sum - @count) / 2
        brute_pairs = (grid.brute_counts.sum - @count) / 2
        check = counts == grid.brute_counts ? 'ok' : 'mismatch'
        occupancy = grid.cells.values.map(&:length).tally.sort.map { |size, cells| "#{size}:#{cells}" }
        lines << "eps #{radius} cells #{grid.cells.length} busiest #{grid.busiest.join(' ')} candidates #{grid.candidates.sum} pairs #{pairs} brute_pairs #{brute_pairs} #{check}"
        lines << "  occupancy #{occupancy.join(' ')}"
      end
      lines
    end

    def clusters_lines
      sections = [["points #{@count} min_pts #{@minimum}", "settings #{@settings.map(&:name).join(' ')}"], grid_lines]
      sections.concat(@settings.map { |current| setting_lines(current) })
      sections.concat([hierarchy_lines, comparison_lines, optics_summary, sweep_lines, xi_lines,
                       outlier_lines, gap_lines, contingency_lines, ari_lines])
      sections.each_with_index.flat_map { |lines, index| index.zero? ? lines : [''] + lines }
    end

    def labels_lines
      lines = [['id', *@settings.map(&:name)].join(',')]
      @points.each_with_index do |point, index|
        lines << [point.id, *@settings.map { |current| current.labels[index] }].join(',')
      end
      lines
    end

    def ordering_lines
      lines = ['order,id,core_sq,reach_sq,reach,predecessor']
      @optics[:order].each_with_index do |point, position|
        core = @optics[:core][point]
        reach = @optics[:reach][point]
        predecessor = @optics[:predecessor][point]
        lines << [position + 1, @points[point].id, core || '-', reach || '-', Report.root(reach),
                  predecessor.nil? ? '-' : @points[predecessor].id].join(',')
      end
      lines
    end

    def kdist_lines
      lines = ["k_distance k #{@k} points #{@count}", 'rank id kdist_sq kdist']
      @curve[:order].each_with_index do |point, rank|
        lines << "#{rank + 1} #{@points[point].id} #{@kd[point]} #{Report.root(@kd[point])}"
      end
      lines << ''
      lines << "knee rank #{@curve[:rank]} id #{@points[@curve[:point]].id} kdist_sq #{@curve[:value]} kdist #{Report.root(@curve[:value])} cross #{@curve[:cross]}"
      lines.concat(["suggested_eps #{@curve[:eps]}", '', 'knee_table'])
      (1..2 * @minimum).each do |neighbour|
        curve = @curves[neighbour]
        lines << "k #{neighbour} rank #{curve[:rank]} id #{@points[curve[:point]].id} kdist_sq #{curve[:value]} eps #{curve[:eps]}"
      end
      lines.concat(['', 'core_check'])
      @db_settings.each do |current|
        core = @kd.count { |value| value <= current.radius * current.radius }
        grid_core = current.core.count(true)
        lines << "eps #{current.radius} core #{core} non_core #{@count - core} grid_core #{grid_core} #{core == grid_core ? 'ok' : 'mismatch'}"
      end
      core = @optics[:core].count { |value| !value.nil? }
      consistent = @optics[:core].each_with_index.all? { |value, point| value.nil? || value == @kd[point] }
      lines << "optics max_eps #{@params['OPTICS_MAX_EPS']} core #{core} #{consistent ? 'ok' : 'mismatch'}"
      lines
    end

    def map_cells
      width, height = @params['MAP_SIZE']
      xs = @points.map(&:x)
      ys = @points.map(&:y)
      xmin, xmax = xs.minmax
      ymin, ymax = ys.minmax
      cells = Array.new(height) { Array.new(width) { [] } }
      @points.each_with_index do |point, index|
        column = (point.x - xmin) * width / (xmax - xmin + 1)
        row = (ymax - point.y) * height / (ymax - ymin + 1)
        cells[row][column] << index
      end
      cells
    end

    def cluster_map(cells, current)
      cells.map do |row|
        row.map do |members|
          if members.empty?
            ' '
          else
            labels = members.map { |point| current.labels[point] }.reject(&:negative?).uniq
            labels.empty? ? '.' : (labels.length == 1 ? character(labels.first) : '*')
          end
        end.join
      end
    end

    def kind_map(cells)
      cells.map do |row|
        row.map do |members|
          if members.empty?
            ' '
          elsif members.any? { |point| @knee.core[point] }
            '#'
          elsif members.any? { |point| @knee.labels[point] >= 0 }
            '+'
          else
            '.'
          end
        end.join
      end
    end

    def scaled_height(value, top, height)
      lower = 0
      upper = height + 1
      while upper - lower > 1
        middle = (lower + upper) / 2
        if middle * middle * top <= height * height * value
          lower = middle
        else
          upper = middle
        end
      end
      lower
    end

    def kdist_plot
      width, height = @params['KDIST_PLOT']
      top = @kd[@curve[:order].first]
      heights = (0...width).map do |column|
        point = @curve[:order][column * @count / width]
        scaled_height(@kd[point], top, height)
      end
      knee_column = (0...width).find do |column|
        column * @count / width < @curve[:rank] && @curve[:rank] <= (column + 1) * @count / width
      end
      rows = (0...height).map do |row|
        (0...width).map do |column|
          if height - row <= heights[column]
            '#'
          else
            column == knee_column ? ':' : ' '
          end
        end.join
      end
      ["kdist_plot k #{@k} max #{Report.root(top)} knee_column #{knee_column + 1}", *Report.frame(rows)]
    end

    def reachability_lines
      width = @params['PLOT_WIDTH']
      top = @optics[:reach].compact.max
      settings = @extractions + [@xi_setting]
      lines = ["reachability width #{width} max_reach #{Report.root(top)} columns #{settings.map(&:name).join(' ')}"]
      @optics[:order].each_with_index do |point, position|
        reach = @optics[:reach][point]
        bar = reach.nil? ? '-' * width : '#' * scaled_height(reach, top, width)
        labels = settings.map { |current| character(current.labels[point]) }.join
        lines << format('%4d %5d %7s %s |%s', position + 1, @points[point].id, Report.root(reach), labels, bar)
      end
      lines
    end

    def maps_lines
      cells = map_cells
      lines = []
      @settings.each do |current|
        lines << "map #{current.name} clusters #{current.count} noise #{current.noise}"
        lines.concat(Report.frame(cluster_map(cells, current)))
        legend = current.groups.each_with_index.map { |members, label| "#{character(label)}=#{members.length}" }
        lines << "legend #{legend.empty? ? '-' : legend.join(' ')}"
        lines << ''
      end
      lines << "kinds #{@knee.name}"
      lines.concat(Report.frame(kind_map(cells)))
      lines << ''
      lines.concat(kdist_plot)
      lines << ''
      lines.concat(reachability_lines)
      lines
    end

    def run
      @points, @params = Dataset.read
      @count = @points.length
      @minimum = @params['MIN_PTS']
      k_distances
      build_settings
      Dir.mkdir('output') unless Dir.exist?('output')
      Report.write('labels.csv', labels_lines)
      Report.write('optics_order.csv', ordering_lines)
      Report.write('kdist.txt', kdist_lines)
      Report.write('clusters.txt', clusters_lines)
      Report.write('maps.txt', maps_lines)
    end
  end
end

Density::Program.new.run
