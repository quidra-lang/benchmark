require 'set'
require_relative 'flight_plans'
require_relative 'trajectory'
require_relative 'conflict'
require_relative 'resolution'
require_relative 'report'

module AirTraffic
  extend self
  include Report

  def ordered_total(values)
    values.reduce(0.0) { |total, value| total + value }
  end

  def sample_times(params)
    (params[:sample_start]...params[:sample_end]).step(60).to_a
  end

  def blockers(code, revised, partner, paths, unresolved, start, params)
    paths.keys.sort.flat_map do |other|
      next [] if other == code
      a, b = [code, other].sort
      next [] if unresolved.include?([a, b])
      conflicts = Conflict.pair(a, a == code ? revised : paths[a], b, b == code ? revised : paths[b], params[:dh], params[:dv])
      conflicts.select { |item| other == partner || item[:start] < start + params[:lookahead] }
    end.min_by { |item| [item[:start], *item[:pair]] }
  end

  def resolve(initial, types, params)
    plans = initial.transform_values { |plan| FlightPlans.clone_plan(plan) }
    paths = plans.transform_values { |plan| Trajectory.build(plan, types) }
    unresolved, resolved = Set.new, Set.new
    rounds, failures = [], []
    loop do
      target = Conflict.all(paths, params[:dh], params[:dv]).find { |item| !unresolved.include?(item[:pair]) }
      break unless target
      first, second = Resolution.priority(*target[:pair].map { |code| plans[code] })
      record = {number: rounds.size + 1, target: target, trials: [], accepted: nil}
      [[first, second], [second, first]].each do |code, partner|
        break if record[:accepted]
        Resolution.manoeuvres(params[:max_delay]).each do |name, amount|
          proposed = Resolution.propose(plans[code], name, amount, types, params)
          trial = {aircraft: code, name: name}
          if !proposed
            trial[:status] = 'infeasible'
          else
            revised = Trajectory.build(proposed, types)
            blocker = blockers(code, revised, partner, paths, unresolved, target[:start], params)
            if blocker
              trial.merge!(status: 'blocked', blocker: blocker)
            else
              trial[:status] = 'accepted'
              proposed[:history] << name
              plans[code], paths[code] = proposed, revised
              record[:accepted] = trial
            end
          end
          record[:trials] << trial
          break if record[:accepted]
        end
      end
      if record[:accepted]
        resolved.add(target[:pair])
      else
        unresolved.add(target[:pair])
        failures << target
      end
      rounds << record
    end
    [plans, paths, rounds, resolved, failures]
  end

  def track(segment)
    vx, vy = segment[:velocity]
    angle = Math.atan2(vx, vy) * 180.0 / 3.141592653589793
    angle < 0 ? angle + 360.0 : angle
  end

  def contains?(sector, point)
    x, y, z = point
    sector[:x1] / 10.0 <= x && x < sector[:x2] / 10.0 &&
      sector[:y1] / 10.0 <= y && y < sector[:y2] / 10.0 &&
      sector[:lower] * 100 <= z && z < sector[:upper] * 100
  end

  def classify(conflicts, sectors, final_pairs, resolved, dh)
    conflicts.each do |item|
      piece = item[:closest]
      a, b = piece.values_at(:a, :b)
      pa, pb = Trajectory.position(a, piece[:tc]), Trajectory.position(b, piece[:tc])
      ta, tb = track(a), track(b)
      angle = (ta - tb).abs
      angle = 360.0 - angle if angle > 180
      ax, ay = a[:velocity]
      bx, by = b[:velocity]
      dot, cross = ax * bx + ay * by, ax * by - ay * bx
      geometry = dot * dot > cross * cross ? (dot < 0 ? 'head_on' : 'trailing') : 'crossing'
      distance = piece[:distance]
      severity = 10.0 * distance < 4.0 * dh ? 'HIGH' : (10.0 * distance < 7.0 * dh ? 'MEDIUM' : 'LOW')
      midpoint = 3.times.map { |i| (pa[i] + pb[i]) / 2.0 }
      sector = sectors.find { |value| contains?(value, midpoint) }
      outcome = final_pairs.include?(item[:pair]) ? 'remaining' : (resolved.include?(item[:pair]) ? 'resolved' : 'indirect')
      item.merge!(level_a: pa[2] / 100.0, level_b: pb[2] / 100.0, track_a: ta, track_b: tb,
                  angle: angle, geometry: geometry, severity: severity, sector: sector ? sector[:name] : '-', outcome: outcome)
    end
  end

  def active(conflicts, time)
    conflicts.select { |item| item[:start] <= time && time < item[:end] }
  end

  def involvement(conflicts)
    result = Hash.new { |hash, key| hash[key] = [] }
    conflicts.each do |item|
      a, b = item[:pair]
      result[a] << [item, b]
      result[b] << [item, a]
    end
    result
  end

  def trajectory_lines(paths)
    rows = ['callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end']
    paths.sort.each do |code, path|
      path[:segments].each do |part|
        x, y, z = part[:start]
        ex, ey, ez = part[:end]
        rows << [code, part[:number], part[:leg], part[:phase], decimal(part[:ts]), decimal(part[:te]),
                 decimal(x), decimal(y), (z / 100).to_i, decimal(ex), decimal(ey), (ez / 100).to_i].join(',')
      end
    end
    rows
  end

  def conflict_lines(label, conflicts, paths, params)
    rows = ["CONFLICTS plan=#{label} count=#{conflicts.size}"]
    conflicts.each_with_index do |item, index|
      piece = item[:closest]
      a, b = piece.values_at(:a, :b)
      rows << "CONFLICT #{index + 1} #{item[:name]} start=#{decimal(item[:start])} end=#{decimal(item[:end])} duration=#{decimal(item[:end] - item[:start])} outcome=#{item[:outcome]}"
      rows << "  CPA t=#{decimal(piece[:tc])} dist=#{decimal(piece[:distance])} vert=#{decimal(piece[:vertical], 1)} levels=#{decimal(item[:level_a], 2)}/#{decimal(item[:level_b], 2)} tracks=#{decimal(item[:track_a], 1)}/#{decimal(item[:track_b], 1)} angle=#{decimal(item[:angle], 1)}"
      rows << "  TYPE geometry=#{item[:geometry]} phases=#{a[:phase]}/#{b[:phase]} segments=#{a[:number]}/#{b[:number]} sector=#{item[:sector]} severity=#{item[:severity]}"
      item[:pieces].each { |part| rows << "  PIECE #{part[:a][:number]}/#{part[:b][:number]} #{decimal(part[:lo])} #{decimal(part[:hi])}" }
    end
    geometry = conflicts.map { |item| item[:geometry] }.tally
    severity = conflicts.map { |item| item[:severity] }.tally
    closest = conflicts.map { |item| item[:closest][:distance] }.min
    rows << 'SUMMARY ' + named(count: conflicts.size, total: decimal(ordered_total(conflicts.map { |item| item[:end] - item[:start] })),
                              min_dist: closest ? decimal(closest) : '-', head_on: geometry.fetch('head_on', 0),
                              crossing: geometry.fetch('crossing', 0), trailing: geometry.fetch('trailing', 0),
                              high: severity.fetch('HIGH', 0), medium: severity.fetch('MEDIUM', 0), low: severity.fetch('LOW', 0))
    flights = involvement(conflicts)
    flights.sort.each do |code, items|
      rows << "FLIGHT #{code} " + named(conflicts: items.size, first: decimal(items.map { |item, _| item[:start] }.min), partners: items.map(&:last).uniq.sort.join(','))
    end
    rows << "TIMELINE from=#{params[:sample_start]} to=#{params[:sample_end]} step=60"
    flights.sort.each do |code, items|
      timeline = sample_times(params).map do |time|
        if !Trajectory.active_segment(paths[code], time)
          '.'
        elsif items.any? { |item, _| item[:start] <= time && time < item[:end] }
          'X'
        else
          '-'
        end
      end.join
      rows << "#{code} #{timeline}"
    end
    rows
  end

  def resolution_lines(initial, final, before_paths, after_paths, before, after, rounds, failures)
    rows = []
    rounds.each do |record|
      target = record[:target]
      rows << "ROUND #{record[:number]} #{target[:name]} start=#{decimal(target[:start])} end=#{decimal(target[:end])} dist=#{decimal(target[:closest][:distance])}"
      record[:trials].each do |trial|
        line = "  TRY #{trial[:aircraft]} #{trial[:name]} #{trial[:status]}"
        blocker = trial[:blocker]
        line += " #{blocker[:name]} start=#{decimal(blocker[:start])}" if blocker
        rows << line
      end
      accepted = record[:accepted]
      rows << (accepted ? "  RESULT resolved #{accepted[:aircraft]} #{accepted[:name]}" : '  RESULT unresolved')
    end
    old_counts, new_counts = involvement(before), involvement(after)
    extra_total = 0.0
    final.sort.each do |code, plan|
      old_time, new_time = before_paths[code][:arrival], after_paths[code][:arrival]
      extra = new_time - old_time
      extra_total += extra
      rows << "FLIGHT #{code} departure=#{plan[:departure] + plan[:delay]} delay=#{plan[:delay]} level=#{signed(plan[:offset])} speed=#{initial[code][:speed]}->#{plan[:speed]} arrival=#{decimal(old_time)}->#{decimal(new_time)} extra=#{decimal(extra)} length=#{decimal(after_paths[code][:length])} conflicts=#{old_counts[code].size}->#{new_counts[code].size} manoeuvres=#{history(plan)}"
    end
    failures.each { |item| rows << "UNRESOLVED #{item[:name]} start=#{decimal(item[:start])} dist=#{decimal(item[:closest][:distance])}" }
    trials = rounds.flat_map { |record| record[:trials] }
    accepted = rounds.filter_map { |record| record[:accepted] }
    rows << 'TOTAL ' + named(rounds: rounds.size, resolved: accepted.size, unresolved: failures.size,
                            level: accepted.count { |trial| trial[:name].start_with?('level_') },
                            speed: accepted.count { |trial| trial[:name] == 'speed_down' },
                            delay: accepted.count { |trial| trial[:name].start_with?('delay_') },
                            total_delay: final.values.reduce(0) { |total, plan| total + plan[:delay] }, total_extra: decimal(extra_total),
                            trials: trials.size, infeasible: trials.count { |trial| trial[:status] == 'infeasible' }, blocked: trials.count { |trial| trial[:status] == 'blocked' })
    rows
  end

  def inside_interval(segment, sector)
    limits = [[sector[:x1] / 10.0, sector[:x2] / 10.0], [sector[:y1] / 10.0, sector[:y2] / 10.0],
              [(sector[:lower] * 100).to_f, (sector[:upper] * 100).to_f]]
    lo, hi = segment.values_at(:ts, :te)
    limits.each_with_index do |(low, high), axis|
      p, v = segment[:start][axis], segment[:velocity][axis]
      if v == 0
        return unless low <= p && p < high
      else
        r1, r2 = (low - p) / v, (high - p) / v
        lo = [lo, segment[:ts] + [r1, r2].min].max
        hi = [hi, segment[:ts] + [r1, r2].max].min
      end
    end
    [lo, hi] if hi - lo > 1e-6
  end

  def transits(paths, sectors)
    paths.sort.flat_map do |code, path|
      entries = sectors.flat_map do |sector|
        combined = []
        path[:segments].each do |segment|
          interval = inside_interval(segment, sector)
          next unless interval
          lo, hi = interval
          if !combined.empty? && lo - combined.last[1] <= 1e-6
            combined.last[1] = hi
          else
            combined << [lo, hi]
          end
        end
        combined.map { |lo, hi| {callsign: code, sector: sector[:name], index: sector[:index], entry: lo, exit: hi, from: '-', to: '-'} }
      end.sort_by { |entry| [entry[:entry], entry[:index]] }
      entries.each_cons(2) do |earlier, later|
        if (later[:entry] - earlier[:exit]).abs <= 1e-6
          earlier[:to], later[:from] = later[:sector], earlier[:sector]
        end
      end
      entries
    end
  end

  def transit_lines(entries)
    ['callsign,sector,entry,exit,duration,from,to'] + entries.map do |item|
      [item[:callsign], item[:sector], decimal(item[:entry]), decimal(item[:exit]), decimal(item[:exit] - item[:entry]), item[:from], item[:to]].join(',')
    end
  end

  def occupancy(paths, sectors, times)
    result = sectors.to_h { |sector| [sector[:name], Array.new(times.size, 0)] }
    times.each_with_index do |time, index|
      paths.sort.each do |_, path|
        observed = Trajectory.observe(path, time)
        next unless observed
        sectors.each { |sector| result[sector[:name]][index] += 1 if contains?(sector, observed[0]) }
      end
    end
    result
  end

  def periods(sectors, times, before_load, after_load, before_entries, after_entries)
    sectors.flat_map do |sector|
      name, capacity = sector.values_at(:name, :capacity)
      times.each_slice(5).with_index(1).map do |samples, number|
        start, finish = samples.first, samples.first + 300
        old = before_load[name][(number - 1) * 5, 5]
        current = after_load[name][(number - 1) * 5, 5]
        entries = [before_entries, after_entries].map { |list| list.count { |item| item[:sector] == name && start <= item[:entry] && item[:entry] < finish } }
        {sector: name, period: number, start: start, end: finish, entries_initial: entries[0], entries_final: entries[1],
         peak_initial: old.max, peak_final: current.max, mean_final: current.reduce(0, :+) / 5.0,
         capacity: capacity, status: current.max > capacity ? 'OVER' : (old.max > capacity ? 'RELIEVED' : 'OK')}
      end
    end
  end

  def load_lines(periods)
    keys = %i[sector period start end entries_initial entries_final peak_initial peak_final mean_final capacity status]
    [keys.join(',')] + periods.map { |item| keys.map { |key| key == :mean_final ? decimal(item[key], 1) : item[key] }.join(',') }
  end

  def level_usage(paths)
    result = {}
    paths.sort.each do |code, path|
      path[:segments].each do |part|
        next unless part[:phase] == 'LVL'
        level = (part[:start][2] / 100).to_i
        value = (result[level] ||= {flights: Set.new, time: 0.0})
        value[:flights].add(code)
        value[:time] += part[:te] - part[:ts]
      end
    end
    result
  end

  def sector_lines(sectors, before_load, after_load, before_entries, after_entries, before, after, before_paths, after_paths)
    rows = []
    sectors.each do |sector|
      name, capacity = sector.values_at(:name, :capacity)
      rows << "SECTOR #{name} x=#{sector[:x1]}..#{sector[:x2]} y=#{sector[:y1]}..#{sector[:y2]} fl=#{sector[:lower]}..#{sector[:upper]} capacity=#{capacity}"
      [['INITIAL', before_entries, before_load, before], ['FINAL', after_entries, after_load, after]].each do |label, entries, loads, conflicts|
        matching = entries.select { |entry| entry[:sector] == name }
        dwell = ordered_total(matching.map { |entry| entry[:exit] - entry[:entry] })
        rows << label + ' ' + named(entries: matching.size, time: decimal(dwell), mean: matching.empty? ? '-' : decimal(dwell / matching.size.to_f),
                                    peak: loads[name].max, over: loads[name].each_slice(5).count { |values| values.max > capacity }, conflicts: conflicts.count { |item| item[:sector] == name })
      end
      height = [capacity + 1, after_load[name].max].max
      rows.concat(chart(height.downto(1).map { |level| after_load[name].map { |value| value >= level ? '#' : (level == capacity ? '-' : '.') }.join }))
    end
    old_levels, new_levels = level_usage(before_paths), level_usage(after_paths)
    rows << 'LEVELS'
    (old_levels.keys | new_levels.keys).sort.reverse.each do |level|
      old = old_levels.fetch(level, {flights: [], time: 0.0})
      current = new_levels.fetch(level, {flights: [], time: 0.0})
      rows << "LEVEL #{level} flights=#{old[:flights].size}->#{current[:flights].size} time=#{decimal(old[:time])}->#{decimal(current[:time])}"
    end
    handoffs = after_entries.reject { |entry| entry[:to] == '-' }.map { |entry| [entry[:sector], entry[:to]] }.tally
    order = sectors.to_h { |sector| [sector[:name], sector[:index]] }
    rows << "HANDOFFS plan=final count=#{handoffs.values.reduce(0, :+)}"
    handoffs.sort_by { |(source, target), _| [order[source], order[target]] }.each { |(source, target), count| rows << "HANDOFF #{source} #{target} #{count}" }
    rows
  end

  def alerts(paths, conflicts, params)
    observations = Hash.new { |hash, key| hash[key] = [] }
    sample_times(params).each do |time|
      flying = paths.sort.filter_map { |code, path| value = Trajectory.observe(path, time); [code, value] if value }.to_h
      flying.keys.combination(2).each do |a, b|
        pa, sa = flying[a]
        pb, sb = flying[b]
        relative = 3.times.map { |i| pa[i] - pb[i] }
        velocity = 3.times.map { |i| sa[:velocity][i] - sb[:velocity][i] }
        loss = Conflict.loss(relative, velocity, 0.0, params[:alert].to_f, params[:dh], params[:dv])
        observations[[a, b]] << {time: time, predicted: time + loss[:lo], distance: loss[:distance]} if loss
      end
    end
    results = observations.flat_map do |pair, events|
      groups = []
      events.each do |event|
        if !groups.empty? && event[:time] - groups.last.last[:time] == 60
          groups.last << event
        else
          groups << [event]
        end
      end
      groups.map { |group| {pair: pair, first: group.first[:time], last: group.last[:time], samples: group.size,
                            predicted: group.first[:predicted], min_dist: group.map { |event| event[:distance] }.min} }
    end.sort_by { |alert| [alert[:first], *alert[:pair]] }
    detected = Set.new
    results.each do |alert|
      matches = conflicts.each_index.select do |i|
        item = conflicts[i]
        item[:pair] == alert[:pair] && item[:start] < alert[:last] + params[:alert] && item[:end] > alert[:first]
      end
      alert[:lead] = matches.empty? ? nil : conflicts[matches.first][:start] - alert[:first]
      detected.merge(matches)
    end
    [results, conflicts.each_with_index.filter_map { |item, i| item unless detected.include?(i) }]
  end

  def alert_lines(label, paths, conflicts, params)
    results, missed = alerts(paths, conflicts, params)
    rows = ["ALERTS plan=#{label} horizon=#{params[:alert]} count=#{results.size}"]
    leads = []
    results.each_with_index do |alert, index|
      if alert[:lead]
        leads << alert[:lead]
        status = "status=true lead=#{decimal(alert[:lead])}"
      else
        status = 'status=false lead=-'
      end
      rows << "ALERT #{index + 1} #{alert[:pair].join('-')} first=#{alert[:first]} last=#{alert[:last]} samples=#{alert[:samples]} predicted=#{decimal(alert[:predicted])} min_dist=#{decimal(alert[:min_dist])} #{status}"
    end
    missed.each { |item| rows << "MISSED #{item[:name]} start=#{decimal(item[:start])} end=#{decimal(item[:end])}" }
    rows << 'SUMMARY ' + named(alerts: results.size, true: leads.size, false: results.size - leads.size, missed: missed.size,
                              mean_lead: leads.empty? ? '-' : decimal(ordered_total(leads) / leads.size.to_f))
    rows
  end

  def cell(point, params)
    x, y = point
    x0, y0, x1, y1, width, height = params[:radar]
    col = ((10.0 * x - x0) * width.to_f / (x1 - x0).to_f).floor
    row = ((10.0 * y - y0) * height.to_f / (y1 - y0).to_f).floor
    [col, height - 1 - row] if col >= 0 && col < width && row >= 0 && row < height
  end

  def radar_lines(label, paths, conflicts, time, params)
    width, height = params[:radar].last(2)
    grid = Array.new(height) { Array.new(width, '.') }
    observed = paths.sort.filter_map { |code, path| value = Trajectory.observe(path, time); [code, value] if value }.to_h
    current = active(conflicts, time)
    involved = current.flat_map { |item| item[:pair] }.to_set
    cells = Hash.new { |hash, key| hash[key] = [] }
    observed.each do |code, (point, _)|
      where = cell(point, params)
      cells[where] << code if where
    end
    cells.each do |(col, row), names|
      grid[row][col] = names.size > 1 ? names.size.to_s : (involved.include?(names.first) ? names.first[0].downcase : names.first[0])
    end
    observed.each_key do |code|
      predicted = Trajectory.observe(paths[code], time + params[:leader])
      next unless predicted
      where = cell(predicted[0], params)
      next unless where
      col, row = where
      grid[row][col] = '*' if grid[row][col] == '.'
    end
    rows = ["RADAR plan=#{label} t=#{time} aircraft=#{observed.size} conflicts=#{current.size}", *chart(grid.map(&:join))]
    observed.each do |code, (point, part)|
      x, y, z = point
      where = cell(point, params)
      rows << "#{code} x=#{decimal(x)} y=#{decimal(y)} fl=#{decimal(z / 100.0, 2)} track=#{decimal(track(part), 1)} phase=#{part[:phase]} cell=#{where ? where.join(',') : 'outside'}"
    end
    current.each do |item|
      pa, pb = item[:pair].map { |code| observed[code][0] }
      dx, dy = pa[0] - pb[0], pa[1] - pb[1]
      rows << "CONFLICT #{item[:name]} dist=#{decimal(Math.sqrt(dx * dx + dy * dy))} vert=#{decimal((pa[2] - pb[2]).abs, 1)}"
    end
    rows
  end

  def density_lines(label, paths, params)
    width, height = params[:radar].last(2)
    grid = Array.new(height) { Array.new(width, 0) }
    sample_times(params).each do |time|
      paths.sort.each do |_, path|
        observed = Trajectory.observe(path, time)
        next unless observed
        where = cell(observed[0], params)
        grid[where[1]][where[0]] += 1 if where
      end
    end
    ["DENSITY plan=#{label} from=#{params[:sample_start]} to=#{params[:sample_end]} step=60 max=#{grid.map(&:max).max}",
     *chart(grid.map { |row| row.map { |value| value == 0 ? '.' : (value < 10 ? value.to_s : '#') }.join })]
  end

  def history(plan)
    plan[:history].empty? ? '-' : plan[:history].join(',')
  end

  def strip_lines(plans, before_paths, after_paths, entries)
    plans.sort.flat_map do |code, plan|
      rows = ["STRIP #{code} type=#{plan[:type]} waypoints=#{plan[:waypoints].size} length=#{decimal(after_paths[code][:length])} manoeuvres=#{history(plan)}"]
      plan[:waypoints].each_with_index do |point, index|
        old_time, old_level = before_paths[code][:waypoint_times][index]
        new_time, new_level = after_paths[code][:waypoint_times][index]
        rows << "WPT #{index} at=#{point[:x]}:#{point[:y]} eta=#{decimal(old_time)}->#{decimal(new_time)} fl=#{old_level}->#{new_level}"
      end
      sequence = entries.select { |entry| entry[:callsign] == code }.map { |entry| "#{entry[:sector]}@#{decimal(entry[:entry])}" }
      rows << "SECTORS #{sequence.empty? ? '-' : sequence.join(',')}"
      rows
    end
  end

  def main
    initial, types, sectors, params = FlightPlans.load_all
    old_paths = initial.transform_values { |plan| Trajectory.build(plan, types) }
    before = Conflict.all(old_paths, params[:dh], params[:dv])
    final, new_paths, rounds, resolved, failures = resolve(initial, types, params)
    after = Conflict.all(new_paths, params[:dh], params[:dv])
    pairs = after.map { |item| item[:pair] }.to_set
    classify(before, sectors, pairs, resolved, params[:dh])
    classify(after, sectors, pairs, resolved, params[:dh])
    old_entries, new_entries = transits(old_paths, sectors), transits(new_paths, sectors)
    times = sample_times(params)
    old_load, new_load = occupancy(old_paths, sectors, times), occupancy(new_paths, sectors, times)
    period_rows = periods(sectors, times, old_load, new_load, old_entries, new_entries)
    write_lines('trajectories.csv', trajectory_lines(new_paths))
    write_lines('conflicts.txt', conflict_lines('initial', before, old_paths, params) + conflict_lines('final', after, new_paths, params))
    write_lines('resolutions.txt', resolution_lines(initial, final, old_paths, new_paths, before, after, rounds, failures))
    write_lines('sector_transits.csv', transit_lines(new_entries))
    write_lines('sector_load.csv', load_lines(period_rows))
    write_lines('sector_report.txt', sector_lines(sectors, old_load, new_load, old_entries, new_entries, before, after, old_paths, new_paths))
    write_lines('alerts.txt', alert_lines('initial', old_paths, before, params) + alert_lines('final', new_paths, after, params))
    radar = params[:snapshots].flat_map { |time| radar_lines('initial', old_paths, before, time, params) + radar_lines('final', new_paths, after, time, params) }
    radar.concat(density_lines('initial', old_paths, params)).concat(density_lines('final', new_paths, params))
    write_lines('radar.txt', radar)
    write_lines('strips.txt', strip_lines(final, old_paths, new_paths, new_entries))
  end
end

AirTraffic.main if $PROGRAM_NAME == __FILE__
