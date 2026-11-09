require 'fileutils'
require_relative 'kalman'
require_relative 'association'
require_relative 'imm'
require_relative 'evaluation'

FILTERS = %w[cv ca abg imm rts].freeze

def read_inputs
  measurements, times, truth, params = {}, {}, {}, {}
  File.readlines('input/measurements.csv', chomp: true).drop(1).each do |line|
    scan, time, x, y = line.split(',')
    scan = scan.to_i
    times[scan] = time.to_f
    (measurements[scan] ||= []) << [x.to_f, y.to_f]
  end
  File.readlines('input/truth.csv', chomp: true).drop(1).each do |line|
    target, scan, x, y = line.split(',')
    (truth[target.to_i] ||= {})[scan.to_i] = [x.to_f, y.to_f]
  end
  File.foreach('input/params.txt') do |line|
    name, *values = line.split
    params[name] = if name == 'MODEL'
                     values[0]
                   elsif %w[CONFIRM DELETE PLOT_SIZE].include?(name)
                     values.map(&:to_i)
                   else
                     values.map(&:to_f)
                   end
  end
  [measurements, times, truth, params]
end

class Track
  attr_accessor :number, :birth, :last_hit, :confirmed, :deleted, :status, :hits,
                :consecutive_misses, :observations, :nis, :kalman, :target, :primary_matches,
                :span, :estimates, :model_logs, :covariances, :high, :nis_values, :longest_gap,
                :path, :common, :mean_distance

  def initialize(number, scan, measurement, kalman)
    @number, @birth, @last_hit, @kalman = number, scan, scan, kalman
    @status, @hits, @consecutive_misses = 'tentative', 1, 0
    @observations, @nis, @primary_matches = { scan => measurement }, {}, {}
  end
end

class Analysis
  include Evaluation

  def initialize(measurements, times, truth, params)
    @measurements, @times, @truth, @params = measurements, times, truth, params
    @scans, @targets = measurements.keys.max, truth.keys.sort
    @primary = params['MODEL'].downcase
    @tracks, @track_rows, @log = [], ['track,scan,x,y,vx,vy,status'], []
    @conflict_measurements = @conflict_tracks = @greedy_differences = 0
  end

  def parameter(name)
    @params[name][0]
  end

  def make_kalman(model, measurement)
    Kalman.new(model, parameter("Q_#{model}"), parameter('SIGMA'), parameter('INIT_VELOCITY_VARIANCE'),
               parameter('INIT_ACCELERATION_VARIANCE'), measurement)
  end

  def listed(keyword, items)
    "#{keyword} #{items.empty? ? 'none' : items.join(' ')}"
  end

  def optional(value)
    value.nil? ? '-' : value.to_s
  end

  def groups(items)
    result = []
    items.each do |scan, label|
      if !result.empty? && result[-1][1] + 1 == scan && result[-1][2] == label
        result[-1][1] = scan
      else
        result << [scan, scan, label]
      end
    end
    result
  end

  def path_length(positions)
    Mat.total((1...positions.length).map { |i| distance(positions[i - 1], positions[i]) })
  end

  def rmse(errors)
    Math.sqrt(Mat.total(errors) / errors.length)
  end

  def filter_scores(values)
    best = FILTERS.min_by { |name| real(values[name]).to_f }
    FILTERS.map { |name| "#{name} #{real(values[name])}" }.join(' ') + " best #{best}"
  end

  def framed(rows)
    border = '+' + '-' * rows[0].length + '+'
    [border, *rows.map { |row| '|' + row.join + '|' }, border]
  end

  def track_all_scans
    required_hits, window = @params['CONFIRM']
    1.upto(@scans) do |scan|
      live = @tracks.reject { |t| t.status == 'deleted' }
      measurements = @measurements[scan]
      live.each { |t| t.kalman.predict(@times[scan] - @times[scan - 1]) } if scan > 1
      usable, innovations = {}, {}
      row_gates, column_gates = Array.new(live.length, 0), Array.new(measurements.length, 0)
      live.each_with_index do |track, row|
        measurements.each_with_index do |measurement, column|
          innovation = track.kalman.innovation(measurement)
          next unless innovation[3] <= parameter('GATE')
          usable[[row, column]] = innovation[3]
          innovations[[row, column]] = innovation
          row_gates[row] += 1
          column_gates[column] += 1
        end
      end
      assigned = Association.optimal_assignment(live.length, measurements.length, usable)
      greedy, used_rows, used_columns = [], {}, {}
      usable.keys.sort_by { |row, column| [usable[[row, column]], live[row].number, column] }.each do |row, column|
        next if used_rows[row] || used_columns[column]
        greedy << [row, column]
        used_rows[row] = used_columns[column] = true
      end
      greedy.sort!
      @greedy_differences += 1 if assigned != greedy
      matches = assigned.to_h
      missed, confirmed, deleted = [], [], []
      live.each_with_index do |track, row|
        if matches.key?(row)
          column = matches[row]
          measurement = measurements[column]
          track.kalman.update(measurement, innovations[[row, column]])
          track.observations[scan] = measurement
          track.nis[scan] = usable[[row, column]]
          track.last_hit = scan
          track.hits += 1
          track.consecutive_misses = 0
        else
          track.observations[scan] = nil
          track.consecutive_misses += 1
          missed << track.number
        end
        if track.status == 'confirmed'
          if track.consecutive_misses >= parameter('DELETE')
            track.status, track.deleted = 'deleted', scan
            deleted << track.number
          end
        elsif track.hits >= required_hits
          track.status, track.confirmed = 'confirmed', scan
          confirmed << track.number
        elsif scan - track.birth + 1 >= window
          track.status, track.deleted = 'deleted', scan
          deleted << track.number
        end
      end
      used_columns = assigned.map(&:last)
      new_tracks = []
      measurements.each_with_index do |measurement, column|
        next if used_columns.include?(column)
        track = Track.new(@tracks.length + 1, scan, measurement, make_kalman(@params['MODEL'], measurement))
        @tracks << track
        new_tracks << [track, column]
      end
      conflicts_m, conflicts_t = column_gates.count { |n| n >= 2 }, row_gates.count { |n| n >= 2 }
      @conflict_measurements += conflicts_m
      @conflict_tracks += conflicts_t
      @log.concat([
        "scan #{scan} tracks #{live.length} measurements #{measurements.length}",
        listed('gate', usable.keys.sort.map { |row, column| "#{live[row].number}:#{column + 1}=#{real(usable[[row, column]])}" }),
        listed('assign', assigned.map { |row, column| "#{live[row].number}:#{column + 1}" }),
        listed('greedy', greedy.map { |row, column| "#{live[row].number}:#{column + 1}" }),
        listed('missed', missed), listed('new', new_tracks.map { |track, column| "#{track.number}:#{column + 1}" }),
        listed('confirmed', confirmed), listed('deleted', deleted),
        "status tentative #{@tracks.count { |t| t.status == 'tentative' }} confirmed #{@tracks.count { |t| t.status == 'confirmed' }}",
        "conflicts measurements #{conflicts_m} tracks #{conflicts_t}"
      ])
      (live + new_tracks.map(&:first)).each do |track|
        @track_rows << [track.number, scan, *track.kalman.x.take(4).map { |x| real(x) }, track.status].join(',')
      end
    end
    @evaluated = @tracks.select { |t| t.confirmed }
  end

  def abg_estimates(track)
    alpha, beta, gamma = @params['ABG']
    state = track.observations[track.birth] + Array.new(4, 0.0)
    estimates = {}
    track.span.each do |scan|
      if scan > track.birth
        t = @times[scan] - @times[scan - 1]
        measurement = track.observations[scan]
        2.times do |axis|
          p, v, w = state[axis], state[axis + 2], state[axis + 4]
          p = p + t * v + t * t * w / 2.0
          v = v + t * w
          if measurement
            r = measurement[axis] - p
            p = p + alpha * r
            v = v + beta * r / t
            w = w + 2.0 * gamma * r / (t * t)
          end
          state[axis], state[axis + 2], state[axis + 4] = p, v, w
        end
      end
      estimates[scan] = state.take(4)
    end
    estimates
  end

  def compare_filters
    @evaluated.each do |track|
      track.span = (track.birth..track.last_hit).to_a
      track.estimates = FILTERS.to_h { |name| [name, {}] }
      track.model_logs = {}
      histories = {}
      %w[cv ca].each do |name|
        kalman = make_kalman(name.upcase, track.observations[track.birth])
        history, likelihood = [], 0.0
        track.span.each do |scan|
          if scan > track.birth
            kalman.predict(@times[scan] - @times[scan - 1])
            measurement = track.observations[scan]
            likelihood += kalman.update(measurement)[1] if measurement
          end
          track.estimates[name][scan] = kalman.x.take(4)
          history << kalman.snapshot
        end
        histories[name] = history
        track.model_logs[name] = likelihood
      end
      track.estimates['abg'] = abg_estimates(track)
      history = histories[@primary]
      track.covariances = track.span.each_with_index.to_h { |scan, i| [scan, history[i][:p]] }
      smoothed = Kalman.smooth(history)
      track.estimates['rts'] = track.span.each_with_index.to_h { |scan, i| [scan, smoothed[i].take(4)] }
      imm = IMM.new(@params['IMM_Q'], @params['IMM_TRANSITION'], @params['IMM_INITIAL'], parameter('SIGMA'),
                    parameter('INIT_VELOCITY_VARIANCE'), track.observations[track.birth])
      track.high = {}
      track.span.each do |scan|
        imm.step(@times[scan] - @times[scan - 1], track.observations[scan]) if scan > track.birth
        track.estimates['imm'][scan] = imm.estimate
        track.high[scan] = imm.probabilities[1]
      end
      track.nis_values = track.span.filter_map { |scan| track.nis[scan] }
      gap = longest = 0
      track.span.each do |scan|
        gap = track.observations[scan] ? 0 : gap + 1
        longest = [longest, gap].max
      end
      track.longest_gap = longest
      track.path = path_length(track.span.map { |scan| track.estimates['rts'][scan] })
    end
  end

  def evaluate_scans
    @labels = FILTERS.to_h { |name| [name, @targets.to_h { |target| [target, {}] }] }
    @ospa = FILTERS.to_h { |name| [name, []] }
    @scan_sizes = []
    threshold, cutoff = parameter('MATCH_DISTANCE'), parameter('OSPA_CUTOFF')
    1.upto(@scans) do |scan|
      tracks = @evaluated.select { |track| track.birth <= scan && scan <= track.last_hit }
      targets = @targets.select { |target| @truth[target].key?(scan) }
      @scan_sizes << [targets.length, tracks.length]
      true_positions = targets.map { |target| @truth[target][scan] }
      FILTERS.each do |name|
        estimates = tracks.map { |track| track.estimates[name][scan] }
        usable = {}
        estimates.each_with_index do |estimate, row|
          true_positions.each_with_index do |point, column|
            value = distance(estimate, point)
            usable[[row, column]] = value if value <= threshold
          end
        end
        Association.optimal_assignment(tracks.length, targets.length, usable).each do |row, column|
          track, target = tracks[row], targets[column]
          @labels[name][target][scan] = track.number
          track.primary_matches[scan] = target if name == @primary
        end
        @ospa[name] << ospa(estimates, true_positions, cutoff)
      end
    end
    @continuities = FILTERS.to_h do |name|
      values = @targets.to_h do |target|
        labels = @truth[target].keys.sort.map { |scan| @labels[name][target][scan] }
        [target, continuity(labels)]
      end
      [name, values]
    end
  end

  def match_tracks
    cutoff = parameter('OSPA_CUTOFF')
    usable, details = {}, {}
    @evaluated.each_with_index do |track, row|
      @targets.each_with_index do |target, column|
        positions = @truth[target]
        common = track.span.select { |scan| positions.key?(scan) }
        next if common.empty?
        distances = common.to_h { |scan| [scan, distance(track.estimates[@primary][scan], positions[scan])] }
        next unless distances.values.any? { |value| value < cutoff }
        union = (track.span | positions.keys).sort
        cost = Mat.total(union.map { |scan| distances.key?(scan) ? [cutoff, distances[scan]].min : cutoff }) / union.length
        usable[[row, column]], details[[row, column]] = cost, common
      end
    end
    @matched_tracks = {}
    Association.optimal_assignment(@evaluated.length, @targets.length, usable).each do |row, column|
      track, target = @evaluated[row], @targets[column]
      track.target, track.common, track.mean_distance = target, details[[row, column]], usable[[row, column]]
      @matched_tracks[target] = track
    end
  end

  def evaluate_errors
    @results = {}
    overall_position = FILTERS.to_h { |name| [name, []] }
    overall_velocity = FILTERS.to_h { |name| [name, []] }
    @targets.each do |target|
      track = @matched_tracks[target]
      next unless track
      positions = @truth[target]
      velocities = {}
      track.common.each do |scan|
        next unless positions.key?(scan - 1) && positions.key?(scan + 1)
        interval = @times[scan + 1] - @times[scan - 1]
        velocities[scan] = 2.times.map { |axis| (positions[scan + 1][axis] - positions[scan - 1][axis]) / interval }
      end
      position_rmse, velocity_rmse = {}, {}
      FILTERS.each do |name|
        position_errors = track.common.map { |scan| squared_distance(track.estimates[name][scan], positions[scan]) }
        velocity_errors = velocities.keys.sort.map { |scan| squared_distance(track.estimates[name][scan][2, 2], velocities[scan]) }
        position_rmse[name], velocity_rmse[name] = rmse(position_errors), rmse(velocity_errors)
        overall_position[name].concat(position_errors)
        overall_velocity[name].concat(velocity_errors)
      end
      nees = track.common.map do |scan|
        estimate = track.estimates[@primary][scan]
        error = 2.times.map { |axis| estimate[axis] - positions[scan][axis] }
        covariance = track.covariances[scan].take(2).map { |row| row.take(2) }
        Mat.quadratic2(error, Mat.inverse(covariance))
      end
      @results[target] = { track: track, position: position_rmse, velocity: velocity_rmse,
                           velocity_count: velocities.length, nees: nees }
    end
    @overall_position = FILTERS.to_h { |name| [name, rmse(overall_position[name])] }
    @overall_velocity = FILTERS.to_h { |name| [name, rmse(overall_velocity[name])] }
  end

  def summary_section
    ['summary', "scans #{@scans}", "measurements #{@measurements.values.reduce(0) { |n, values| n + values.length }}",
     "targets #{@targets.length}", "tracks_created #{@tracks.length}", "tracks_confirmed #{@evaluated.length}",
     "false_tracks #{@evaluated.count { |t| t.primary_matches.empty? }}", "missed_targets #{@targets.length - @matched_tracks.length}",
     "measurements_used #{@evaluated.reduce(0) { |n, t| n + t.hits }}", "conflict_measurements #{@conflict_measurements}",
     "conflict_tracks #{@conflict_tracks}", "greedy_differences #{@greedy_differences}"]
  end

  def targets_section
    lines = ['targets']
    @targets.each do |target|
      scans = @truth[target].keys.sort
      length = path_length(scans.map { |scan| @truth[target][scan] })
      speed = length / (@times[scans[-1]] - @times[scans[0]])
      lines << "target #{target} first #{scans[0]} last #{scans[-1]} scans #{scans.length} path #{real(length)} mean_speed #{real(speed)}"
    end
    lines
  end

  def tracks_section
    bound = parameter('CONSISTENCY_BOUND')
    lines = ['tracks']
    @evaluated.each do |track|
      count = track.nis_values.length
      mean = Mat.total(track.nis_values) / count
      inside = track.nis_values.count { |x| x <= bound }
      lines << "track #{track.number} birth #{track.birth} confirmed #{track.confirmed} end #{track.last_hit} deleted #{optional(track.deleted)} hits #{track.hits} misses #{track.span.length - track.hits} longest_gap #{track.longest_gap} path #{real(track.path)} nis #{real(mean)} nis_inside #{inside}/#{count}"
    end
    lines
  end

  def matching_section
    lines = ['matching']
    @evaluated.each do |track|
      line = "track #{track.number} target #{optional(track.target)}"
      line += " common #{track.common.length} mean_distance #{real(track.mean_distance)}" if track.target
      segments = groups(track.primary_matches.sort).map { |first, last, target| "#{first}-#{last}:#{target}" }
      lines << line + " matched_scans #{track.primary_matches.length} " + listed('segments', segments)
    end
    lines
  end

  def rmse_section
    lines = ['rmse']
    @targets.each do |target|
      result = @results[target]
      unless result
        lines << "target #{target} track -"
        next
      end
      track = result[:track]
      lines << "target #{target} track #{track.number} common #{track.common.length} #{filter_scores(result[:position])}"
      lines << "target #{target} velocity #{result[:velocity_count]} #{filter_scores(result[:velocity])}"
    end
    lines + ["overall position #{filter_scores(@overall_position)}", "overall velocity #{filter_scores(@overall_velocity)}"]
  end

  def consistency_section
    lines = ['consistency']
    bound = parameter('CONSISTENCY_BOUND')
    @targets.each do |target|
      result = @results[target]
      unless result
        lines << "target #{target} track -"
        next
      end
      values = result[:nees]
      inside = values.count { |x| x <= bound }
      lines << "target #{target} track #{result[:track].number} nees #{real(Mat.total(values) / values.length)} inside #{inside}/#{values.length}"
    end
    values = @evaluated.flat_map(&:nis_values)
    edges = @params['NIS_EDGES']
    observed = Array.new(edges.length + 1, 0)
    values.each { |value| observed[edges.count { |edge| value >= edge }] += 1 }
    lower = 0.0
    expected = [*edges, nil].map do |upper|
      probability = upper.nil? ? 0.0 : Math.exp(-upper / 2.0)
      count = values.length * (Math.exp(-lower / 2.0) - probability)
      lower = upper
      count
    end
    lines << "nis_histogram total #{values.length} observed #{observed.join(' ')} expected #{expected.map { |x| real(x) }.join(' ')}"
    lines
  end

  def models_section
    lines = ['models']
    @evaluated.each do |track|
      cv, ca = track.model_logs.values_at('cv', 'ca')
      lines << "track #{track.number} updates #{track.nis_values.length} cv #{real(cv)} ca #{real(ca)} better #{cv >= ca ? 'cv' : 'ca'}"
    end
    lines
  end

  def ospa_section
    lines = ["ospa cutoff #{real(parameter('OSPA_CUTOFF'))} order 2", 'scan targets tracks cv ca abg imm rts']
    @scan_sizes.each_with_index do |(targets, tracks), i|
      lines << "#{i + 1} #{targets} #{tracks} #{FILTERS.map { |name| real(@ospa[name][i]) }.join(' ')}"
    end
    lines << "mean #{FILTERS.map { |name| real(Mat.total(@ospa[name]) / @scans) }.join(' ')}"
    lines
  end

  def continuity_section
    lines = ['continuity']
    FILTERS.each do |name|
      values = @continuities[name]
      totals = %i[covered breaks swaps].map do |key|
        "#{key} #{@targets.reduce(0) { |sum, target| sum + values[target][key] }}"
      end
      lines << "#{name} #{totals.join(' ')}"
      @targets.each do |target|
        result = values[target]
        lines << "  target #{target} scans #{@truth[target].length} covered #{result[:covered]} breaks #{result[:breaks]} swaps #{result[:swaps]} delay #{optional(result[:delay])}"
      end
    end
    lines
  end

  def imm_section
    lines = ['imm']
    @evaluated.each do |track|
      mean = Mat.total(track.span.map { |scan| track.high[scan] }) / track.span.length
      maximum_scan = track.span.first
      track.span.each { |scan| maximum_scan = scan if track.high[scan] > track.high[maximum_scan] }
      high_scans = track.span.select { |scan| track.high[scan] > 0.5 }
      segments = groups(high_scans.map { |scan| [scan, true] }).map { |first, last, _| "#{first}-#{last}" }
      lines << "track #{track.number} mean_high #{real(mean)} max_high #{real(track.high[maximum_scan])} at #{maximum_scan} high_scans #{high_scans.length} #{listed('segments', segments)}"
    end
    lines
  end

  def evaluation_lines
    sections = [summary_section, targets_section, tracks_section, matching_section, rmse_section,
                consistency_section, models_section, ospa_section, continuity_section, imm_section]
    sections.each_with_index.flat_map { |section, i| i == 0 ? section : ['', *section] }
  end

  def plot_cell(point)
    xmin, xmax = @params['PLOT_X']
    ymin, ymax = @params['PLOT_Y']
    width, height = @params['PLOT_SIZE']
    dx, dy = (xmax - xmin) / width, (ymax - ymin) / height
    column, row = ((point[0] - xmin) / dx).floor, ((ymax - point[1]) / dy).floor
    [row, column] if column >= 0 && column < width && row >= 0 && row < height
  end

  def plot_lines
    width, height = @params['PLOT_SIZE']
    xmin, xmax = @params['PLOT_X']
    ymin, ymax = @params['PLOT_Y']
    characters = @evaluated.each_with_index.to_h do |track, i|
      [track.number, i < 26 ? ('A'.ord + i).chr : ('a'.ord + i - 26).chr]
    end
    trajectory = Array.new(height) { Array.new(width, ' ') }
    @targets.each do |target|
      @truth[target].keys.sort.each do |scan|
        cell = plot_cell(@truth[target][scan])
        trajectory[cell[0]][cell[1]] = '.' if cell
      end
    end
    @evaluated.each do |track|
      track.span.each do |scan|
        cell = plot_cell(track.estimates['rts'][scan])
        trajectory[cell[0]][cell[1]] = characters[track.number] if cell
      end
    end
    lines = ["tracks x #{real(xmin)} #{real(xmax)} y #{real(ymin)} #{real(ymax)} size #{width} #{height}", *framed(trajectory)]
    @evaluated.each { |track| lines << "#{characters[track.number]} track #{track.number} target #{optional(track.target)}" }
    counts = Array.new(height) { Array.new(width, 0) }
    1.upto(@scans) do |scan|
      @measurements[scan].each do |measurement|
        cell = plot_cell(measurement)
        counts[cell[0]][cell[1]] += 1 if cell
      end
    end
    density = counts.map { |row| row.map { |n| n == 0 ? ' ' : n < 10 ? n.to_s : '#' } }
    lines.concat(['', 'measurements', *framed(density), '', 'timeline'])
    @targets.each do |target|
      labels = @labels[@primary][target]
      timeline = (1..@scans).map do |scan|
        if !@truth[target].key?(scan)
          ' '
        elsif !labels.key?(scan)
          '.'
        else
          characters[labels[scan]]
        end
      end
      lines << "#{target} |#{timeline.join}|"
    end
    cutoff = parameter('OSPA_CUTOFF')
    heights = @ospa[@primary].map { |value| (10 * value / cutoff).floor }
    bars = 10.times.map { |row| heights.map { |value| value >= 10 - row ? '#' : ' ' } }
    lines.concat(['', "ospa #{@primary}", *framed(bars)])
    lines
  end

  def write
    FileUtils.mkdir_p('output')
    smoothed = ['track,scan,x,y,vx,vy']
    @evaluated.each do |track|
      track.span.each do |scan|
        smoothed << [track.number, scan, *track.estimates['rts'][scan].map { |x| real(x) }].join(',')
      end
    end
    { 'tracks.csv' => @track_rows, 'smoothed.csv' => smoothed, 'association_log.txt' => @log,
      'evaluation.txt' => evaluation_lines, 'track_plot.txt' => plot_lines }.each do |name, lines|
      File.write("output/#{name}", lines.join("\n") + "\n")
    end
  end

  def run
    track_all_scans
    compare_filters
    evaluate_scans
    match_tracks
    evaluate_errors
    write
  end
end

Analysis.new(*read_inputs).run if $PROGRAM_NAME == __FILE__
