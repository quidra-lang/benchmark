require_relative 'records'
require_relative 'cleaning'
require_relative 'harmonic_fit'
require_relative 'predict'
require_relative 'report'

def total(items)
  result = 0.0
  items.each { |item| result += block_given? ? yield(item) : item }
  result
end

def mean(items, &block)
  total(items, &block) / items.length
end

def choose(items, field, largest = true)
  best = nil
  items.each { |item| best = item if best.nil? || (largest ? item[field] > best[field] : item[field] < best[field]) }
  best
end

def select_constituents(constituents, length, rayleigh)
  selected = []
  statuses = {}
  constituents.each do |item|
    if item[:speed] * length < 360 * rayleigh
      statuses[item[:name]] = 'short'
    else
      conflict = selected.find { |other| (item[:speed] - other[:speed]).abs * length < 360 * rayleigh }
      statuses[item[:name]] = conflict ? "conflict:#{conflict[:name]}" : 'fitted'
      selected << item unless conflict
    end
  end
  {selected: selected, statuses: statuses}
end

def check_station(source, rows, constituents, params)
  numeric = rows.reject { |row| row[:value].nil? }
  first, last = numeric.first[:time], numeric.last[:time]
  by_time = rows.to_h { |row| [row[:time], row] }
  reasons = {}
  (first..last).each do |time|
    reasons[time] = 'absent' unless by_time.key?(time)
    reasons[time] = 'na' if by_time.key?(time) && by_time[time][:value].nil?
  end
  flats = Cleaning.flat_runs(numeric, params[:flat_run])
  flats.each { |run| (run[:start] + 1..run[:end]).each { |time| reasons[time] = 'flat' } }
  candidates = numeric.reject { |row| reasons.key?(row[:time]) }
  selection = select_constituents(constituents, last - first, params[:rayleigh])
  preliminary = HarmonicFit.fit(candidates, selection[:selected])
  squares = 0.0
  candidates.each do |row|
    row[:preliminary] = row[:value] - Predict.level(preliminary, row[:time])
    squares += row[:preliminary] * row[:preliminary]
  end
  tested, spikes = Cleaning.spike_tests(candidates, params[:spike])
  spikes.each { |spike| reasons[spike[:time]] = 'spike' }
  usable = candidates.reject { |row| reasons.key?(row[:time]) }
  counts = {rows: rows.length, numeric: numeric.length, na: 0, absent: 0, flat: 0, spikes: 0, usable: usable.length}
  reasons.each_value { |reason| counts[reason == 'spike' ? :spikes : reason.to_sym] += 1 }
  source.merge(first: first, last: last, length: last - first, selection: selection, candidates: candidates,
               usable: usable, counts: counts, flats: flats, prefit_rms: Math.sqrt(squares / candidates.length),
               tested: tested, spikes: spikes, gaps: Cleaning.gaps(first, last, reasons))
end

def final_fit(station, params)
  model = HarmonicFit.fit(station[:usable], station[:selection][:selected])
  residuals = {}
  squares = max_abs = 0.0
  station[:usable].each do |row|
    row[:fitted] = Predict.level(model, row[:time])
    row[:residual] = row[:value] - row[:fitted]
    residuals[row[:time]] = row[:residual]
    squares += row[:residual] * row[:residual]
    max_abs = [max_abs, row[:residual].abs].max
  end
  dof = station[:usable].length - model[:unknowns]
  variance = squares / dof
  observed_mean = mean(station[:usable]) { |row| row[:value] }
  centered_squares = lag_product = lag_squares = 0.0
  station[:usable].each do |row|
    difference = row[:value] - observed_mean
    centered_squares += difference * difference
    if residuals.key?(row[:time] + 1)
      lag_product += row[:residual] * residuals[row[:time] + 1]
      lag_squares += row[:residual] * row[:residual]
    end
  end
  model[:constituents].each_with_index do |item, index|
    a, b, amplitude = item.values_at(:a, :b, :amplitude)
    ia, ib = 2 * index + 1, 2 * index + 2
    va = variance * model[:inverse][ia][ia]
    vb = variance * model[:inverse][ib][ib]
    cab = variance * model[:inverse][ia][ib]
    item[:amplitude_error] = Math.sqrt(a * a * va + b * b * vb + 2 * a * b * cab) / amplitude
    item[:phase_error] = Math.sqrt(b * b * va + a * a * vb - 2 * a * b * cab) / (amplitude * amplitude) * 180 / HarmonicFit::PI
    ratio = amplitude / item[:amplitude_error]
    item[:snr] = ratio * ratio
    item[:significant] = item[:snr] >= params[:snr_min] ? 'yes' : 'no'
  end
  station[:model] = model
  station[:constants] = model[:constituents].to_h { |item| [item[:name], item] }
  station[:residuals] = residuals
  station[:statistics] = {dof: dof, rms: Math.sqrt(squares / station[:usable].length), max_abs: max_abs,
                          explained: 100 * (1 - squares / centered_squares), lag1: lag_product / lag_squares}
  station[:top] = station[:usable].sort_by { |row| [-row[:residual].abs, row[:time]] }.first(params[:top_residuals])
end

def predictions(station, params)
  station[:predictions] = (0..params[:hours]).map { |i| Predict.level(station[:model], params[:start] + i) }
  extrema = Predict.grid_extrema(station[:model], params[:start], params[:hours], params[:grid])
  station[:raw_extrema] = extrema.length
  while extrema.length >= 2
    pair = (0...extrema.length - 1).min_by { |i| [(extrema[i][:height] - extrema[i + 1][:height]).abs, i] }
    break if (extrema[pair][:height] - extrema[pair + 1][:height]).abs >= params[:min_range]
    extrema.slice!(pair, 2)
  end
  by_day = {}
  extrema.each do |item|
    item[:minute] = (item[:refined_minute] + 0.5).floor
    item[:day] = item[:minute].div(1440)
    item[:label] = item[:kind] == 'high' ? 'LHW' : 'HLW'
    by_day[item[:day]] ||= {highs: [], lows: []}
    by_day[item[:day]][item[:kind] == 'high' ? :highs : :lows] << item
  end
  by_day.each_value do |group|
    highest = choose(group[:highs], :height)
    lowest = choose(group[:lows], :height, false)
    highest[:label] = 'HHW' if highest
    lowest[:label] = 'LLW' if lowest
  end
  station[:daily] = Array.new(params[:hours] / 24) do |offset|
    day = params[:start] / 24 + offset
    group = by_day.fetch(day, {highs: [], lows: []})
    hhw = choose(group[:highs], :height)&.fetch(:height)
    llw = choose(group[:lows], :height, false)&.fetch(:height)
    {day: day, high_count: group[:highs].length, low_count: group[:lows].length, hhw: hhw, llw: llw,
     range: hhw && llw ? hhw - llw : nil}
  end
  station[:extrema] = extrema
  station[:highs] = extrema.select { |item| item[:kind] == 'high' }
  station[:lows] = extrema.select { |item| item[:kind] == 'low' }
end

def validation(station, constituents, params)
  split = station[:first] + station[:length] / 2
  training, test = station[:usable].partition { |row| row[:time] <= split }
  selection = select_constituents(constituents, training.last[:time] - training.first[:time], params[:rayleigh])
  model = HarmonicFit.fit(training, selection[:selected])
  observed_mean = mean(test) { |row| row[:value] }
  squares = in_sample = centered_squares = 0.0
  test.each do |row|
    error = row[:value] - Predict.level(model, row[:time])
    centered = row[:value] - observed_mean
    squares += error * error
    in_sample += row[:residual] * row[:residual]
    centered_squares += centered * centered
  end
  {split: split, train: training.length, test: test.length, constituents: selection[:selected].length,
   rms: Math.sqrt(squares / test.length), in_sample_rms: Math.sqrt(in_sample / test.length), skill: 1 - squares / centered_squares}
end

def residual_events(station, settings)
  events = []
  current = nil
  finish = lambda do
    events << current if current && current[:end] - current[:start] + 1 >= settings[:hours]
    current = nil
  end
  station[:usable].each do |row|
    type = row[:residual] > settings[:threshold] ? 'positive' : row[:residual] < -settings[:threshold] ? 'negative' : nil
    finish.call if current && (type != current[:type] || row[:time] != current[:end] + 1)
    next unless type
    if current.nil?
      current = {type: type, start: row[:time], end: row[:time], peak: row[:residual], peak_time: row[:time]}
    else
      current[:end] = row[:time]
      if type == 'positive' ? row[:residual] > current[:peak] : row[:residual] < current[:peak]
        current[:peak], current[:peak_time] = row[:residual], row[:time]
      end
    end
  end
  finish.call
  events
end

def daily_means(station)
  weights = [0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1]
  usable = station[:usable].to_h { |row| [row[:time], row[:value]] }
  days = []
  (station[:first] / 24..station[:last] / 24).each do |day|
    noon = day * 24 + 12
    next if noon - 19 < station[:first] || noon + 19 > station[:last]
    weighted = 0.0
    filled = 0
    (-19..19).each do |offset|
      time = noon + offset
      value = usable.key?(time) ? usable[time] : Predict.level(station[:model], time)
      weighted += weights[offset.abs] * value
      filled += 1 unless usable.key?(time)
    end
    days << {day: day, level: weighted / 30, filled: filled}
  end
  average = mean(days) { |entry| entry[:level] }
  mean_day = mean(days) { |entry| entry[:day] - days.first[:day] }
  numerator = denominator = 0.0
  days.each do |entry|
    x = entry[:day] - days.first[:day] - mean_day
    numerator += x * (entry[:level] - average)
    denominator += x * x
  end
  {days: days, average: average, slope: 1000 * (numerator / denominator),
   maximum: choose(days, :level), minimum: choose(days, :level, false)}
end

def tidal_characteristics(station, params)
  m2, s2, k1, o1, m4 = station[:constants].values_at('M2', 'S2', 'K1', 'O1', 'M4')
  form = (k1[:amplitude] + o1[:amplitude]) / (m2[:amplitude] + s2[:amplitude])
  type = form < 0.25 ? 'semidiurnal' : form < 1.5 ? 'mixed_semidiurnal' : form < 3 ? 'mixed_diurnal' : 'diurnal'
  mhhw = mean(station[:daily].reject { |day| day[:hhw].nil? }) { |day| day[:hhw] }
  mllw = mean(station[:daily].reject { |day| day[:llw].nil? }) { |day| day[:llw] }
  mhw = mean(station[:highs]) { |item| item[:height] }
  mlw = mean(station[:lows]) { |item| item[:height] }
  amplitude_sum = total(station[:model][:constituents]) { |item| item[:amplitude] }
  complete_days = station[:daily].reject { |day| day[:range].nil? }
  rises, falls = [], []
  station[:extrema].each_cons(2) do |previous, current|
    rises << current[:minute] - previous[:minute] if previous[:kind] == 'low' && current[:kind] == 'high'
    falls << current[:minute] - previous[:minute] if previous[:kind] == 'high' && current[:kind] == 'low'
  end
  phase = 2 * m2[:phase] - m4[:phase]
  phase += 360 while phase < 0
  phase -= 360 while phase >= 360
  {form: form, type: type, spring: 2 * (m2[:amplitude] + s2[:amplitude]), neap: 2 * (m2[:amplitude] - s2[:amplitude]),
   mhhw: mhhw, mllw: mllw, mhw: mhw, mlw: mlw, mtl: (mhw + mlw) / 2, dtl: (mhhw + mllw) / 2,
   mn: mhw - mlw, gt: mhhw - mllw, hat: station[:model][:mean] + amplitude_sum, lat: station[:model][:mean] - amplitude_sum,
   highest: choose(station[:highs], :height), lowest: choose(station[:lows], :height, false),
   widest: choose(complete_days, :range), narrowest: choose(complete_days, :range, false),
   above: 100.0 * station[:predictions].count { |value| value > mhhw } / (params[:hours] + 1),
   below: 100.0 * station[:predictions].count { |value| value < mllw } / (params[:hours] + 1),
   rise: mean(rises), fall: mean(falls), m4_ratio: m4[:amplitude] / m2[:amplitude], relative_phase: phase,
   dominance: phase < 180 ? 'flood' : 'ebb'}
end

def spring_neap(station, params)
  m2, s2 = station[:constants].values_at('M2', 'S2')
  dw, dg = s2[:speed] - m2[:speed], s2[:phase] - m2[:phase]
  bounds = [params[:start], params[:start] + params[:hours]].map { |time| (dw * time - dg) / 180 }
  events = []
  (bounds.min.floor - 1..bounds.max.ceil + 1).each do |q|
    time = (dg + 180 * q) / dw
    events << {type: q.even? ? 'spring' : 'neap', minute: (time * 60 + 0.5).floor} if time >= params[:start] && time <= params[:start] + params[:hours]
  end
  events
end

def real(value, digits)
  Report.real(value, digits)
end

def cleaning_lines(station, params)
  dt = ->(time) { Records.hour_datetime(params[:epoch], time) }
  c = station[:counts]
  lines = ["station=#{station[:code]} name=#{station[:name]}",
           "span start=#{dt.call(station[:first])} end=#{dt.call(station[:last])} hours=#{station[:length] + 1} record_length=#{station[:length]}",
           "counts rows=#{c[:rows]} numeric=#{c[:numeric]} na=#{c[:na]} absent=#{c[:absent]} flat=#{c[:flat]} spikes=#{c[:spikes]} usable=#{c[:usable]}"]
  station[:flats].each { |run| lines << "flat start=#{dt.call(run[:start])} end=#{dt.call(run[:end])} value=#{real(run[:value], 3)} removed=#{run[:end] - run[:start]}" }
  lines << "spike_test window=#{params[:spike][:window]} candidates=#{station[:candidates].length} tested=#{station[:tested]} prefit_rms=#{real(station[:prefit_rms], 4)}"
  station[:spikes].each do |spike|
    lines << "spike time=#{dt.call(spike[:time])} value=#{real(spike[:value], 3)} residual=#{real(spike[:residual], 4)} median=#{real(spike[:median], 4)} mad=#{real(spike[:mad], 4)} limit=#{real(spike[:limit], 4)}"
  end
  station[:gaps].each { |gap| lines << "gap start=#{dt.call(gap[:start])} end=#{dt.call(gap[:end])} hours=#{gap[:end] - gap[:start] + 1} cause=#{gap[:cause]}" }
  lines
end

def constituent_lines(station, constituents)
  constituents.map do |item|
    status = station[:selection][:statuses][item[:name]]
    prefix = "#{station[:code]},#{item[:name]},#{real(item[:speed], 7)},#{status}"
    next prefix + ',,,,,,' unless status == 'fitted'
    fitted = station[:constants][item[:name]]
    prefix + ',' + [[:amplitude, 4], [:phase, 2], [:amplitude_error, 4], [:phase_error, 2], [:snr, 1]].map { |key, digits| real(fitted[key], digits) }.join(',') + ',' + fitted[:significant]
  end
end

def extreme_lines(station, params)
  lines = ["station=#{station[:code]} extremes=#{station[:extrema].length} raw=#{station[:raw_extrema]} removed=#{station[:raw_extrema] - station[:extrema].length}"]
  station[:extrema].each_with_index do |item, i|
    change = i.zero? ? 'none' : real(item[:height] - station[:extrema][i - 1][:height], 3)
    lines << "#{Records.datetime(params[:epoch], item[:minute])} #{item[:label]} #{real(item[:height], 3)} change=#{change}"
  end
  station[:daily].each do |day|
    lines << "day date=#{Records.date(params[:epoch], day[:day])} high_waters=#{day[:high_count]} low_waters=#{day[:low_count]} hhw=#{real(day[:hhw], 3)} llw=#{real(day[:llw], 3)} range=#{real(day[:range], 3)}"
  end
  lines
end

def summary_lines(station, params)
  dt = ->(time) { Records.hour_datetime(params[:epoch], time) }
  minute = ->(time) { Records.datetime(params[:epoch], time) }
  date = ->(day) { Records.date(params[:epoch], day) }
  stats, v, t, daily = station.values_at(:statistics, :validation, :characteristics, :daily_means)
  lines = ["[station #{station[:code]}] #{station[:name]}",
           "record first=#{dt.call(station[:first])} last=#{dt.call(station[:last])} length=#{station[:length]} usable=#{station[:usable].length}",
           "fit constituents=#{station[:model][:constituents].length} unknowns=#{station[:model][:unknowns]} dof=#{stats[:dof]} mean_level=#{real(station[:model][:mean], 4)}",
           "residual rms=#{real(stats[:rms], 4)} max_abs=#{real(stats[:max_abs], 4)} explained_percent=#{real(stats[:explained], 4)} lag1_autocorrelation=#{real(stats[:lag1], 4)}"]
  station[:top].each_with_index do |row, i|
    lines << "top_residual rank=#{i + 1} time=#{dt.call(row[:time])} observed=#{real(row[:value], 3)} fitted=#{real(row[:fitted], 4)} residual=#{real(row[:residual], 4)}"
  end
  lines << "validation split=#{dt.call(v[:split])} train=#{v[:train]} test=#{v[:test]} constituents=#{v[:constituents]} rms=#{real(v[:rms], 4)} in_sample_rms=#{real(v[:in_sample_rms], 4)} skill=#{real(v[:skill], 4)}"
  lines << "form_number=#{real(t[:form], 4)} type=#{t[:type]}"
  lines << "ranges spring=#{real(t[:spring], 3)} neap=#{real(t[:neap], 3)} mn=#{real(t[:mn], 3)} gt=#{real(t[:gt], 3)}"
  lines << "asymmetry rise_minutes=#{real(t[:rise], 1)} fall_minutes=#{real(t[:fall], 1)} m4_m2_ratio=#{real(t[:m4_ratio], 4)} relative_phase=#{real(t[:relative_phase], 2)} dominance=#{t[:dominance]}"
  lines << "datums mhhw=#{real(t[:mhhw], 3)} mhw=#{real(t[:mhw], 3)} mtl=#{real(t[:mtl], 3)} dtl=#{real(t[:dtl], 3)} mlw=#{real(t[:mlw], 3)} mllw=#{real(t[:mllw], 3)}"
  lines << "bounds hat=#{real(t[:hat], 3)} lat=#{real(t[:lat], 3)}"
  lines << "window high_waters=#{station[:highs].length} low_waters=#{station[:lows].length} highest=#{real(t[:highest][:height], 3)} highest_time=#{minute.call(t[:highest][:minute])} lowest=#{real(t[:lowest][:height], 3)} lowest_time=#{minute.call(t[:lowest][:minute])}"
  lines << "daily_range widest=#{real(t[:widest][:range], 3)} widest_date=#{date.call(t[:widest][:day])} narrowest=#{real(t[:narrowest][:range], 3)} narrowest_date=#{date.call(t[:narrowest][:day])}"
  lines << "exceedance above_mhhw=#{real(t[:above], 2)} below_mllw=#{real(t[:below], 2)}"
  station[:spring_neap].each { |event| lines << "#{event[:type]} time=#{minute.call(event[:minute])}" }
  lines << "surges count=#{station[:events].length} threshold=#{real(params[:surge][:threshold], 3)} min_hours=#{params[:surge][:hours]}"
  station[:events].each do |event|
    lines << "surge type=#{event[:type]} start=#{dt.call(event[:start])} end=#{dt.call(event[:end])} hours=#{event[:end] - event[:start] + 1} peak=#{real(event[:peak], 4)} peak_time=#{dt.call(event[:peak_time])}"
  end
  lines << "daily_mean days=#{daily[:days].length} average=#{real(daily[:average], 4)} slope_mm_per_day=#{real(daily[:slope], 3)} max=#{real(daily[:maximum][:level], 4)} max_date=#{date.call(daily[:maximum][:day])} min=#{real(daily[:minimum][:level], 4)} min_date=#{date.call(daily[:minimum][:day])}"
  daily[:days].each { |day| lines << "daily_mean date=#{date.call(day[:day])} level=#{real(day[:level], 4)} filled=#{day[:filled]}" }
  lines
end

def water_lag(waters, reference)
  mean(waters) do |water|
    nearest = reference.min_by { |item| [(item[:minute] - water[:minute]).abs, item[:minute]] }
    water[:minute] - nearest[:minute]
  end
end

def comparison_lines(stations, params)
  reference = stations.find { |station| station[:code] == params[:reference] }
  lines = ["[comparison] reference=#{params[:reference]}"]
  stations.each do |station|
    next if station.equal?(reference)
    tide, other_tide = station[:characteristics], reference[:characteristics]
    lines << "#{station[:code]} tide hw_lag_min=#{real(water_lag(station[:highs], reference[:highs]), 1)} lw_lag_min=#{real(water_lag(station[:lows], reference[:lows]), 1)} range_ratio=#{real(tide[:gt] / other_tide[:gt], 4)} mtl_diff=#{real(tide[:mtl] - other_tide[:mtl], 3)}"
    %w[M2 S2 K1 O1].each do |name|
      own, other = station[:constants][name], reference[:constants][name]
      phase = own[:phase] - other[:phase]
      phase -= 360 if phase > 180
      phase += 360 if phase <= -180
      lines << "#{station[:code]} #{name} amplitude_ratio=#{real(own[:amplitude] / other[:amplitude], 4)} phase_diff=#{real(phase, 2)} time_lag_min=#{real(phase / own[:speed] * 60, 1)}"
    end
  end
  lines
end

def correlation_lines(stations, maximum_lag)
  lines = ["[correlation] max_lag=#{maximum_lag}"]
  stations.each_with_index do |first, i|
    stations.drop(i + 1).each do |second|
      results = (-maximum_lag..maximum_lag).map do |lag|
        pairs = first[:usable].filter_map { |row| [row[:residual], second[:residuals][row[:time] + lag]] if second[:residuals].key?(row[:time] + lag) }
        mx, my = mean(pairs) { |pair| pair[0] }, mean(pairs) { |pair| pair[1] }
        sxy = sxx = syy = 0.0
        pairs.each do |pair|
          x, y = pair[0] - mx, pair[1] - my
          sxy += x * y
          sxx += x * x
          syy += y * y
        end
        {lag: lag, rho: sxy / Math.sqrt(sxx * syy), pairs: pairs.length}
      end
      best = results.min_by { |item| [-item[:rho], item[:lag].abs, item[:lag]] }
      zero = results.find { |item| item[:lag].zero? }[:rho]
      lines << "#{first[:code]}-#{second[:code]} lag0=#{real(zero, 4)} best_lag=#{best[:lag]} best=#{real(best[:rho], 4)} pairs=#{best[:pairs]}"
    end
  end
  lines
end

def plot(stations, params)
  station = stations.find { |item| item[:code] == params[:plot][:code] }
  hours, top, bottom, step = params[:plot].values_at(:hours, :top, :bottom, :step)
  row_count = (top - bottom) / step + 1
  cells = Array.new(row_count) { Array.new(hours, ' ') }
  heights = Array.new(row_count) { |row| top - row * step }
  baseline = ((top - 100 * station[:model][:mean]) / step + 0.5).floor
  cells[baseline].fill('-') if baseline >= 0 && baseline < row_count
  marks = {}
  station[:extrema].each do |item|
    column = (item[:minute] - 60 * params[:start] + 30).div(60)
    marks[column] = item[:kind] == 'high' ? 'H' : 'L' if column >= 0 && column < hours
  end
  hours.times do |column|
    row = ((top - 100 * station[:predictions][column]) / step + 0.5).floor
    if row < 0
      cells[0][column] = '^'
    elsif row >= row_count
      cells[-1][column] = 'v'
    else
      cells[row][column] = marks.fetch(column, '*')
    end
  end
  ["[plot] station=#{station[:code]} start=#{Records.hour_datetime(params[:epoch], params[:start])} hours=#{hours} step_cm=#{step}"] + Report.plot_lines(cells, heights)
end

def main
  params, constituents, observations = Records.read_all
  files = {'cleaning.txt' => [], 'constituents.csv' => ['station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant'],
           'predictions.csv' => ['time,' + params[:stations].map { |station| station[:code] }.join(',')], 'extremes.txt' => [], 'summary.txt' => []}
  stations = params[:stations].map do |source|
    station = check_station(source, observations[source[:code]], constituents, params)
    final_fit(station, params)
    predictions(station, params)
    station[:validation] = validation(station, constituents, params)
    station[:events] = residual_events(station, params[:surge])
    station[:daily_means] = daily_means(station)
    station[:characteristics] = tidal_characteristics(station, params)
    station[:spring_neap] = spring_neap(station, params)
    files['cleaning.txt'].concat(cleaning_lines(station, params))
    files['constituents.csv'].concat(constituent_lines(station, constituents))
    files['extremes.txt'].concat(extreme_lines(station, params))
    files['summary.txt'].concat(summary_lines(station, params))
    station
  end
  (0..params[:hours]).each do |index|
    files['predictions.csv'] << Records.hour_datetime(params[:epoch], params[:start] + index) + ',' + stations.map { |station| real(station[:predictions][index], 3) }.join(',')
  end
  files['summary.txt'].concat(comparison_lines(stations, params))
  files['summary.txt'].concat(correlation_lines(stations, params[:correlation_lag]))
  files['summary.txt'].concat(plot(stations, params))
  Report.write_files(files)
end

main if $PROGRAM_NAME == __FILE__
