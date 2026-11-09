require_relative 'waveform_io'
require_relative 'picker'
require_relative 'associator'
require_relative 'locator'
require_relative 'magnitude'

def ordered_sum(values)
  result = 0.0
  values.each { |value| result += value.to_f }
  result
end

def mean(values)
  ordered_sum(values) / values.length.to_f
end

def scaled(value, places)
  integer = (value.abs * (10**places).to_f + 0.5).floor
  value.negative? ? -integer : integer
end

def decimal(value, places)
  integer = scaled(value, places)
  absolute = integer.abs
  factor = 10**places
  "#{integer.negative? ? '-' : ''}#{absolute.div(factor)}.#{(absolute % factor).to_s.rjust(places, '0')}"
end

def time_notation(sample)
  "#{sample.div(100)}.#{(sample % 100).to_s.rjust(2, '0')}"
end

def save(name, lines)
  File.write("output/#{name}", lines.join("\n") + "\n")
end

def station_ordered(picks)
  picks.sort_by { |pick| pick[:station][:order] }
end

def observations(picks, corrections = nil)
  station_ordered(picks).map do |pick|
    correction = corrections ? corrections[pick[:station][:code]] : 0.0
    [pick[:station], pick[:time] - correction]
  end
end

def locate_candidates(candidates, params)
  events = []
  candidates.each do |candidate|
    initial = station_ordered(candidate[:picks])
    first = Locator.run(observations(initial), params)
    candidate[:passes] << [initial, first]
    retained = []
    initial.zip(first[:residuals]).each do |pick, residual|
      if residual.abs > params[:residual_limit]
        candidate[:dropped] << [pick, residual]
      else
        retained << pick
      end
    end
    if !candidate[:dropped].empty? && retained.length < params[:min_stations]
      candidate[:rejected] = true
      initial.each { |pick| pick[:state] = :rejected }
      next
    end
    adopted = first
    unless candidate[:dropped].empty?
      adopted = Locator.run(observations(retained), params)
      candidate[:passes] << [retained, adopted]
    end
    number = events.length + 1
    candidate[:event] = number
    retained.zip(adopted[:residuals]).each do |pick, residual|
      pick.merge!(state: :used, event: number, first_residual: residual)
    end
    candidate[:dropped].each { |pick, _| pick.merge!(state: :dropped, event: number) }
    events << {number: number, used: retained, first: adopted, solution: adopted[:solution]}
  end
  events
end

def station_corrections(events, stations)
  values = stations.to_h { |s| [s[:code], []] }
  events.each do |event|
    event[:used].each { |pick| values[pick[:station][:code]] << pick[:first_residual] }
  end
  stations.to_h do |station|
    residuals = values[station[:code]]
    [station[:code], residuals.empty? ? 0.0 : mean(residuals)]
  end
end

def quality_for(event, params)
  solution = event[:solution]
  velocity = params[:velocity]
  used = event[:used]
  obs = event[:observations]
  ellipse = Locator.error_ellipse(solution, obs, velocity)
  x, y, = solution
  angles = used.map do |pick|
    s = pick[:station]
    phi = Math.atan2(s[:x].to_f - x, s[:y].to_f - y) * 180.0 / Locator::PI
    phi.negative? ? phi + 360.0 : phi
  end.sort
  gaps = angles.each_cons(2).map { |a, b| b - a } + [angles[0] + 360.0 - angles[-1]]
  gap = gaps.max
  dmin = used.map do |pick|
    dx = pick[:station][:x].to_f - x
    dy = pick[:station][:y].to_f - y
    Math.sqrt(dx * dx + dy * dy)
  end.min
  fits = lambda do |bounds|
    gap <= bounds[0] && event[:final][:rms] <= bounds[1] && ellipse[:smaj] <= bounds[2]
  end
  grade = fits.call(params[:quality_a]) ? 'A' : (fits.call(params[:quality_b]) ? 'B' : 'C')
  first = event[:first][:solution]
  dx, dy = x - first[0], y - first[1]
  jackknife = used.each_with_index.map do |pick, index|
    remaining = obs.each_with_index.filter_map { |observation, j| observation unless index == j }
    alternative = Locator.geiger(solution, remaining, velocity)[:solution]
    differences = 3.times.map { |axis| alternative[axis] - solution[axis] }
    jx, jy, jz = differences
    {code: pick[:station][:code], dx: jx, dy: jy, dz: jz, shift: Math.sqrt(jx * jx + jy * jy)}
  end
  maximum = jackknife.first
  jackknife.drop(1).each { |j| maximum = j if j[:shift] > maximum[:shift] }
  ellipse.merge(gap: gap, dmin: dmin, grade: grade, dh: Math.sqrt(dx * dx + dy * dy),
                dz: solution[2] - first[2], jackknife: jackknife, maximum: maximum)
end

def relocate(events, corrections, params)
  events.each do |event|
    obs = observations(event[:used], corrections)
    event[:observations] = obs
    event[:start_rms] = Locator.rms(event[:first][:solution], obs, params[:velocity])
    final = Locator.geiger(event[:first][:solution], obs, params[:velocity])
    event[:final] = final
    event[:solution] = final[:solution]
    event[:used].zip(final[:residuals]).each { |pick, residual| pick[:residual] = residual }
    event[:quality] = quality_for(event, params)
  end
end

def compute_magnitudes(events, stations, params)
  station_residuals = stations.to_h { |s| [s[:code], []] }
  events.each do |event|
    data = event[:used].map do |pick|
      radius = Locator.distance(event[:solution], pick[:station]) / 1000.0
      Magnitude.for_pick(pick, radius, params).merge(pick: pick)
    end
    local = data.filter_map { |item| item[:ml] }
    event[:magnitudes] = data
    event[:ml] = local.empty? ? nil : Magnitude.median(local)
    event[:md] = Magnitude.median(data.map { |item| item[:md] })
    event[:h] = scaled(event[:ml], 2) if event[:ml]
    data.each do |item|
      station_residuals[item[:pick][:station][:code]] << item[:ml] - event[:ml] if item[:ml]
    end
  end
  corrections = station_residuals.transform_values { |values| values.empty? ? 0.0 : mean(values) }
  events.each do |event|
    corrected = event[:magnitudes].filter_map do |item|
      item[:ml] - corrections[item[:pick][:station][:code]] if item[:ml]
    end
    event[:mlc] = corrected.empty? ? nil : Magnitude.median(corrected)
  end
  [corrections, station_residuals]
end

def travel_fit(events)
  points = events.flat_map do |event|
    event[:used].map do |pick|
      [Locator.distance(event[:solution], pick[:station]) / 1000.0, pick[:time] - event[:solution][3]]
    end
  end
  n = points.length.to_f
  sd = ordered_sum(points.map(&:first))
  st = ordered_sum(points.map(&:last))
  sdd = ordered_sum(points.map { |d, _| d * d })
  sdt = ordered_sum(points.map { |d, t| d * t })
  slope = (n * sdt - sd * st) / (n * sdd - sd * sd)
  intercept = (st - slope * sd) / n
  squares = ordered_sum(points.map { |d, t| r = t - intercept - slope * d; r * r })
  {n: points.length, velocity: 1000.0 / slope, intercept: intercept, rms: Math.sqrt(squares / n)}
end

def cluster_events(events, params)
  distance_limit, time_limit = params[:cluster]
  neighbors = Array.new(events.length) { [] }
  events.each_with_index do |first, i|
    (i + 1...events.length).each do |j|
      a, b = first[:solution], events[j][:solution]
      next if (a[3] - b[3]).abs > time_limit
      dx, dy, dz = 3.times.map { |axis| a[axis] - b[axis] }
      next if Math.sqrt(dx * dx + dy * dy + dz * dz) > distance_limit
      neighbors[i] << j
      neighbors[j] << i
    end
  end
  visited = Set.new
  clusters = []
  events.each_index do |first|
    next unless visited.add?(first)
    queue = [first]
    members = []
    until queue.empty?
      index = queue.shift
      members << index
      neighbors[index].each { |other| queue << other if visited.add?(other) }
    end
    members.sort!
    number = clusters.length + 1
    members.each { |i| events[i][:cluster] = number }
    cluster = {number: number, members: members.map { |i| i + 1 }}
    if members.length > 1
      cluster[:center] = 3.times.map { |axis| mean(members.map { |i| events[i][:solution][axis] }) }
      origins = members.map { |i| events[i][:solution][3] }
      cluster[:span] = origins.max - origins.min
    end
    clusters << cluster
  end
  clusters
end

def reassociate(picks, events, corrections, params)
  station_sets = events.to_h do |event|
    [event[:number], event[:used].map { |pick| pick[:station][:code] }.to_set]
  end
  added = []
  picks.each do |pick|
    next unless pick[:state] == :unassociated
    best = nil
    events.each do |event|
      number = event[:number]
      code = pick[:station][:code]
      next if station_sets[number].include?(code)
      residual = pick[:time] - event[:solution][3] - Locator.distance(event[:solution], pick[:station]) / params[:velocity].to_f - corrections[code]
      next if residual.abs > params[:residual_limit]
      best = [number, residual] if best.nil? || residual.abs < best[1].abs
    end
    next unless best
    number, residual = best
    pick.merge!(state: :added, event: number, residual: residual)
    station_sets[number].add(pick[:station][:code])
    added << pick
  end
  added
end

def catalog_statistics(events)
  available = events.select { |event| event[:ml] }
  stats = Magnitude.frequency_statistics(available.map { |event| Magnitude.class_number(event[:h]) })
  xs, ys = available.map { |event| event[:md] }, available.map { |event| event[:ml] }
  xbar, ybar = mean(xs), mean(ys)
  sxx = ordered_sum(xs.map { |x| (x - xbar) * (x - xbar) })
  sxy = ordered_sum(xs.zip(ys).map { |x, y| (x - xbar) * (y - ybar) })
  syy = ordered_sum(ys.map { |y| (y - ybar) * (y - ybar) })
  slope = sxy / sxx
  stats.merge(mlmd: {n: available.length, slope: slope, intercept: ybar - slope * xbar,
                    r: sxy / Math.sqrt(sxx * syy), mean_diff: ybar - xbar})
end

def picks_report(picks)
  lines = ['station,sample,time_s,duration,snr,amplitude,clipped,event,status,residual']
  picks.each do |pick|
    event = %i[used dropped added].include?(pick[:state]) ? pick[:event] : 0
    residual = %i[used added].include?(pick[:state]) ? decimal(pick[:residual], 4) : '-'
    lines << [pick[:station][:code], pick[:sample], time_notation(pick[:sample]), pick[:duration],
              decimal(pick[:ratio], 2), pick[:amplitude], pick[:clipped] ? 'yes' : 'no',
              event, pick[:state], residual].join(',')
  end
  lines
end

def solution_line(label, solution, rms, iteration = nil)
  x, y, z, t0 = solution
  heading = iteration ? "#{label} #{iteration}" : label
  "#{heading} x=#{decimal(x, 1)} y=#{decimal(y, 1)} z=#{decimal(z, 1)} t0=#{decimal(t0, 3)} rms=#{decimal(rms, 4)}"
end

def pass_lines(number, picks, run, velocity)
  grid = run[:grid]
  lines = ["PASS #{number} stations=#{picks.map { |pick| pick[:station][:code] }.join(',')}",
           solution_line('GRID', grid[:solution], grid[:rms]),
           'PROFILE ' + grid[:profile].map { |value| decimal(value, 4) }.join(' ')]
  run[:trace].each { |r| lines << solution_line('ITER', r[:solution], r[:rms], r[:number]) }
  picks.zip(run[:residuals]).each do |pick, residual|
    distance = Locator.distance(run[:solution], pick[:station])
    lines << "RES #{pick[:station][:code]} dist=#{decimal(distance, 1)} tt=#{decimal(distance / velocity.to_f, 4)} obs=#{time_notation(pick[:sample])} res=#{decimal(residual, 4)}"
  end
  lines
end

def event_location_lines(event, velocity, corrections)
  lines = ["EVENT #{event[:number]}", solution_line('START', event[:first][:solution], event[:start_rms])]
  event[:final][:trace].each { |r| lines << solution_line('ITER', r[:solution], r[:rms], r[:number]) }
  event[:used].each do |pick|
    code = pick[:station][:code]
    distance = Locator.distance(event[:solution], pick[:station])
    lines << "RES #{code} dist=#{decimal(distance, 1)} tt=#{decimal(distance / velocity.to_f, 4)} obs=#{time_notation(pick[:sample])} corr=#{decimal(corrections[code], 4)} res=#{decimal(pick[:residual], 4)}"
  end
  q = event[:quality]
  lines += ["ELLIPSE smaj=#{decimal(q[:smaj], 1)} smin=#{decimal(q[:smin], 1)} az=#{decimal(q[:az], 1)} erz=#{decimal(q[:erz], 1)} ert=#{decimal(q[:ert], 4)}",
            "SHIFT dh=#{decimal(q[:dh], 1)} dz=#{decimal(q[:dz], 1)}",
            "GAP #{decimal(q[:gap], 1)} DMIN #{decimal(q[:dmin], 1)} QUALITY #{q[:grade]}"]
  q[:jackknife].each do |j|
    lines << "JACK #{j[:code]} dx=#{decimal(j[:dx], 1)} dy=#{decimal(j[:dy], 1)} dz=#{decimal(j[:dz], 1)} shift=#{decimal(j[:shift], 1)}"
  end
  lines << "JACKKNIFE max=#{decimal(q[:maximum][:shift], 1)} station=#{q[:maximum][:code]}"
  lines
end

def locations_report(picks, candidates, events, stations, corrections, fit, clusters, added, params)
  lines = []
  candidates.each do |candidate|
    lines << "CANDIDATE #{candidate[:number]} picks=#{candidate[:picks].length} first=#{time_notation(candidate[:first][:sample])}"
    initial, first = candidate[:passes][0]
    lines.concat(pass_lines(1, initial, first, params[:velocity]))
    candidate[:dropped].each { |pick, residual| lines << "DROP #{pick[:station][:code]} res=#{decimal(residual, 4)}" }
    if candidate[:rejected]
      lines << "RESULT REJECTED stations=#{candidate[:picks].length - candidate[:dropped].length}"
    else
      if candidate[:passes].length == 2
        retained, second = candidate[:passes][1]
        lines.concat(pass_lines(2, retained, second, params[:velocity]))
      end
      lines << "RESULT EVENT #{candidate[:event]}"
    end
  end
  lines << 'CORRECTIONS'
  stations.each do |s|
    lines << "#{s[:code]} n=#{s[:picks].count { |pick| pick[:state] == :used }} correction=#{decimal(corrections[s[:code]], 4)}"
  end
  events.each { |event| lines.concat(event_location_lines(event, params[:velocity], corrections)) }
  lines << "FIT n=#{fit[:n]} velocity=#{decimal(fit[:velocity], 1)} intercept=#{decimal(fit[:intercept], 4)} rms=#{decimal(fit[:rms], 4)}"
  clusters.each do |cluster|
    next if cluster[:members].length < 2
    x, y, z = cluster[:center]
    lines << "CLUSTER #{cluster[:number]} events=#{cluster[:members].join(',')} x=#{decimal(x, 1)} y=#{decimal(y, 1)} z=#{decimal(z, 1)} span=#{decimal(cluster[:span], 3)}"
  end
  lines << 'ADDED'
  added.each do |pick|
    lines << "#{pick[:station][:code]} sample=#{pick[:sample]} event=#{pick[:event]} res=#{decimal(pick[:residual], 4)}"
  end
  lines << "SUMMARY picks=#{picks.length} candidates=#{candidates.length} events=#{events.length} rejected=#{candidates.count { |c| c[:rejected] }} unassociated=#{picks.count { |pick| pick[:state] == :unassociated }}"
  depths = events.map { |event| event[:solution][2] }
  lines << "DEPTH min=#{decimal(depths.min, 1)} median=#{decimal(Magnitude.median(depths), 1)} max=#{decimal(depths.max, 1)}"
  grades = %w[A B C].map { |grade| "#{grade}=#{events.count { |event| event[:quality][:grade] == grade }}" }
  lines << 'QUALITY ' + grades.join(' ') + " mean_rms=#{decimal(mean(events.map { |event| event[:final][:rms] }), 4)}"
  lines
end

def catalog_report(events)
  lines = ['event,origin_time,x,y,depth,rms,stations,gap,dmin,smaj,smin,azimuth,erz,ml,md,quality,cluster']
  events.each do |event|
    x, y, z, t0 = event[:solution]
    q = event[:quality]
    lines << [event[:number], decimal(t0, 3), decimal(x, 1), decimal(y, 1), decimal(z, 1),
              decimal(event[:final][:rms], 4), event[:used].length, decimal(q[:gap], 1),
              decimal(q[:dmin], 1), decimal(q[:smaj], 1), decimal(q[:smin], 1), decimal(q[:az], 1),
              decimal(q[:erz], 1), event[:ml] ? decimal(event[:ml], 2) : '-', decimal(event[:md], 2),
              q[:grade], event[:cluster]].join(',')
  end
  lines
end

def framed(grid)
  border = '+' + '-' * grid.first.length + '+'
  [border] + grid.map { |row| '|' + row.join + '|' } + [border]
end

def timeline(events, params)
  duration, width, low, high, height = params[:timeline]
  grid = Array.new(height) { Array.new(width, ' ') }
  events.each do |event|
    next unless event[:ml]
    time = scaled(event[:solution][3], 3)
    h = event[:h]
    next unless time >= 0 && time < 1000 * duration && h >= 100 * low
    col = (time * width).div(1000 * duration)
    level = [((h - 100 * low) * height).div(100 * (high - low)), height - 1].min
    (0..level).each do |k|
      row = height - 1 - k
      if k == level
        grid[row][col] = 'o'
      elsif grid[row][col] == ' '
        grid[row][col] = '|'
      end
    end
  end
  ["TIMELINE t=0..#{duration} ML=#{low}..#{high}"] + framed(grid)
end

def magnitudes_report(events, stats, params)
  lines = []
  events.each do |event|
    ml = event[:ml] ? decimal(event[:ml], 2) : '-'
    available = event[:magnitudes].count { |item| item[:ml] }
    lines << "EVENT #{event[:number]} ML=#{ml} n=#{available} MD=#{decimal(event[:md], 2)}"
    event[:magnitudes].each do |item|
      pick = item[:pick]
      prefix = "#{pick[:station][:code]} r=#{decimal(item[:r], 3)} amp=#{pick[:amplitude]} "
      if item[:ml]
        lines << prefix + "ml=#{decimal(item[:ml], 2)} res=#{decimal(item[:ml] - event[:ml], 2)} dur=#{pick[:duration]} md=#{decimal(item[:md], 2)}"
      else
        lines << prefix + "clipped dur=#{pick[:duration]} md=#{decimal(item[:md], 2)}"
      end
    end
  end
  lines << 'CORRECTED'
  events.each { |event| lines << "EVENT #{event[:number]} MLC=#{event[:mlc] ? decimal(event[:mlc], 2) : '-'}" }
  lines << 'FMD'
  frequencies = stats[:frequencies]
  (frequencies.keys.min..frequencies.keys.max).each do |value|
    cumulative = frequencies.select { |key, _| key >= value }.values.sum
    lines << "M=#{Magnitude.class_notation(value)} N=#{frequencies[value]} CUM=#{cumulative}"
  end
  lines += ['MC ' + Magnitude.class_notation(stats[:completeness]),
            "BVALUE #{decimal(stats[:b], 3)} SIGMA #{decimal(stats[:sigma], 3)} N #{stats[:nb]}",
            "AVALUE #{decimal(stats[:a], 3)}"]
  relation = stats[:mlmd]
  lines << "MLMD n=#{relation[:n]} slope=#{decimal(relation[:slope], 3)} intercept=#{decimal(relation[:intercept], 3)} r=#{decimal(relation[:r], 3)} mean_diff=#{decimal(relation[:mean_diff], 3)}"
  lines + timeline(events, params)
end

def stations_report(stations, corrections, magnitude_corrections, magnitude_residuals)
  lines = []
  stations.each do |station|
    code = station[:code]
    picks = station[:picks]
    used = picks.select { |pick| pick[:state] == :used }.sort_by { |pick| pick[:event] }
    if used.empty?
      before = after = '-'
    else
      before = decimal(Math.sqrt(mean(used.map { |pick| pick[:first_residual] * pick[:first_residual] })), 4)
      after = decimal(Math.sqrt(mean(used.map { |pick| pick[:residual] * pick[:residual] })), 4)
    end
    states = %i[used dropped added rejected unassociated].map { |state| "#{state}=#{picks.count { |pick| pick[:state] == state }}" }
    lines += ["STATION #{code} x=#{station[:x]} y=#{station[:y]} elevation=#{station[:elevation]}",
              "SAMPLES start=#{station[:start]} count=#{station[:samples].length} mean=#{station[:mean]} noise=#{decimal(station[:noise], 1)} peak=#{station[:peak]} clipped=#{station[:clipped_samples]}",
              "TRIGGERS total=#{station[:triggers]} short=#{station[:short]} picks=#{picks.length}",
              'PICKS ' + states.join(' '),
              "RESIDUALS n=#{used.length} rms=#{before} correction=#{decimal(corrections[code], 4)} after=#{after}",
              "MAGNITUDES n=#{magnitude_residuals[code].length} correction=#{decimal(magnitude_corrections[code], 2)}"]
  end
  lines
end

def event_symbol(event)
  return '?' unless event[:ml]
  return '.' if event[:h] < 100
  return 'o' if event[:h] < 200
  return 'O' if event[:h] < 300
  '@'
end

def plot_positions(event, params)
  x, y, z = event[:solution].take(3).map { |coordinate| scaled(coordinate, 1) }
  left, right, bottom, top = params[:map_area]
  width, map_height = params[:map_size]
  depth, section_height = params[:section]
  xvalid = 10 * left <= x && x < 10 * right
  yvalid = 10 * bottom <= y && y < 10 * top
  column_x = ((x - 10 * left) * width).div(10 * (right - left))
  column_y = ((y - 10 * bottom) * width).div(10 * (top - bottom))
  row = (z * section_height).div(10 * depth)
  map = if xvalid && yvalid
          [column_x, map_height - 1 - ((y - 10 * bottom) * map_height).div(10 * (top - bottom))]
        end
  {map: map, ew: xvalid && z < 10 * depth ? [column_x, row] : nil,
   ns: yvalid && z < 10 * depth ? [column_y, row] : nil}
end

def station_position(station, params)
  left, right, bottom, top = params[:map_area]
  width, height = params[:map_size]
  x, y = station.values_at(:x, :y)
  return nil unless left <= x && x < right && bottom <= y && y < top
  [((x - left) * width).div(right - left), height - 1 - ((y - bottom) * height).div(top - bottom)]
end

def position_text(position)
  position ? position.join(',') : 'outside'
end

def place(grid, position, symbol)
  return unless position
  ranks = {' ' => -1, '?' => 0, '.' => 1, 'o' => 2, 'O' => 3, '@' => 4, '^' => 5}
  col, row = position
  grid[row][col] = symbol if ranks[symbol] > ranks[grid[row][col]]
end

def maps_report(events, stations, params)
  left, right, bottom, top = params[:map_area]
  width, height = params[:map_size]
  depth, section_height = params[:section]
  grids = {map: Array.new(height) { Array.new(width, ' ') },
           ew: Array.new(section_height) { Array.new(width, ' ') },
           ns: Array.new(section_height) { Array.new(width, ' ') }}
  positions = {}
  events.each do |event|
    points = plot_positions(event, params)
    positions[event[:number]] = points
    %i[map ew ns].each { |key| place(grids[key], points[key], event_symbol(event)) }
  end
  station_points = {}
  stations.each do |station|
    point = station_position(station, params)
    station_points[station[:code]] = point
    place(grids[:map], point, '^')
  end
  lines = ["MAP x=#{left}..#{right} y=#{bottom}..#{top}"] + framed(grids[:map])
  lines += ["SECTION EW x=#{left}..#{right} z=0..#{depth}"] + framed(grids[:ew])
  lines += ["SECTION NS y=#{bottom}..#{top} z=0..#{depth}"] + framed(grids[:ns])
  lines << 'LEGEND ^ station . ML<1 o ML<2 O ML<3 @ ML>=3 ? no ML'
  stations.each { |station| lines << "STATION #{station[:code]} map=#{position_text(station_points[station[:code]])}" }
  events.each do |event|
    points = positions[event[:number]]
    lines << "EVENT #{event[:number]} #{event_symbol(event)} map=#{position_text(points[:map])} ew=#{position_text(points[:ew])} ns=#{position_text(points[:ns])}"
  end
  lines
end

def main
  stations, params = WaveformIO.load
  picks = stations.flat_map { |station| Picker.detect(station, params) }
  picks = picks.each_with_index.sort_by { |(pick, index)| [pick[:sample], pick[:station][:order], index] }.map(&:first)
  candidates = Associator.associate(picks, params[:association_window], params[:min_stations])
  events = locate_candidates(candidates, params)
  corrections = station_corrections(events, stations)
  relocate(events, corrections, params)
  magnitude_corrections, magnitude_residuals = compute_magnitudes(events, stations, params)
  fit = travel_fit(events)
  clusters = cluster_events(events, params)
  added = reassociate(picks, events, corrections, params)
  stats = catalog_statistics(events)
  save('picks.csv', picks_report(picks))
  save('locations.txt', locations_report(picks, candidates, events, stations, corrections, fit, clusters, added, params))
  save('catalog.csv', catalog_report(events))
  save('magnitudes.txt', magnitudes_report(events, stats, params))
  save('stations.txt', stations_report(stations, corrections, magnitude_corrections, magnitude_residuals))
  save('map.txt', maps_report(events, stations, params))
end

main if $PROGRAM_NAME == __FILE__
