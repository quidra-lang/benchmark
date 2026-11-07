# frozen_string_literal: true

require_relative 'dataset'
require_relative 'variable_charts'
require_relative 'attribute_charts'
require_relative 'run_rules'
require_relative 'capability'
require_relative 'plot'

class ProcessControl
  FAMILIES = {'XBAR_R' => %w[XBAR_R R], 'XBAR_S' => %w[XBAR_S S], 'I_MR' => %w[I MR]}.freeze
  CHARTS = %w[XBAR_R R XBAR_S S I MR CUSUM EWMA MA].freeze
  ATTRIBUTES = %w[p np c u].freeze
  LOCATION = %w[XBAR_R XBAR_S I CUSUM EWMA MA].freeze
  EVENT_TYPES = %w[SHIFT_UP SHIFT_DOWN SPREAD_UP SPREAD_DOWN PATTERN].freeze

  def initialize
    @data = Dataset::Data.new
    @settings = @data.settings
    @samples = @data.samples
    @n = @settings['subgroup_size']
    @m = @settings['phase1_subgroups']
    @subgroups = VariableCharts.statistics(@samples, @n)
    @count = @subgroups.length
    @phase2 = ((@m + 1)..@count).to_a
    @families = {}
    @limits = {}
    @phase1_sequences = {}
    @phase1_checks = {}
    @signals = []
    @monitoring = @phase2.to_h { |number| [number, {}] }
  end

  def calculate_limits(family, points)
    VariableCharts.estimate(family, points, @subgroups, @samples, @n, @data.constants)
  end

  def estimate_families
    FAMILIES.each do |family, charts|
      initial = (1..(family == 'I_MR' ? @m * @n : @m)).to_a
      retained = initial.dup
      passes = []
      status = nil
      estimate = nil
      1.upto(@settings['max_passes']) do |pass|
        estimate = calculate_limits(family, retained)
        outliers = []
        estimate.sequences.each_with_index do |sequence, index|
          sequence.each do |point, value|
            outliers << point if estimate.limits[index].outside?(value)
          end
        end
        outliers = outliers.uniq.sort
        passes << {number: pass, points: retained.length, estimate: estimate, outliers: outliers}
        if outliers.empty?
          status = 'converged'
          break
        elsif pass == @settings['max_passes']
          status = 'stopped'
          break
        end
        retained -= outliers
      end
      @families[family] = {retained: retained, removed: initial - retained, passes: passes,
                           status: status, estimate: estimate}
      charts.each_with_index do |chart, index|
        @limits[chart] = estimate.limits[index]
        @phase1_sequences[chart] = estimate.sequences[index]
      end
    end
    @mu0 = @limits['XBAR_R'].cl
    @sigma = @limits['R'].cl / @data.constants[:d2] / Math.sqrt(@n)
    @kc = @settings['cusum_k'] * @sigma
    @hc = @settings['cusum_h'] * @sigma
    @rho = @settings['ewma_lambda'] / (2 - @settings['ewma_lambda'])
    @ewma_width = @settings['ewma_l'] * @sigma * Math.sqrt(@rho)
    @ma_width = 3 * @sigma / Math.sqrt(@settings['ma_span'])
  end

  def check_phase1
    CHARTS.first(6).each do |chart|
      sequence = @phase1_sequences.fetch(chart)
      signals = RunRules.check(chart, sequence, @limits.fetch(chart), @settings['rules'].fetch(chart))
      @phase1_checks[chart] = {points: sequence.length, signals: signals}
    end
  end

  def phase2_sequence(chart)
    if chart == 'I'
      ((@m * @n + 1)..@samples.length).map { |point| [point, @samples[point - 1]] }
    elsif chart == 'MR'
      ((@m * @n + 1)..@samples.length).map do |point|
        [point, (@samples[point - 1] - @samples[point - 2]).abs]
      end
    else
      field = {'XBAR_R' => :mean, 'R' => :range, 'XBAR_S' => :mean, 'S' => :sd}.fetch(chart)
      @phase2.map { |point| [point, @subgroups[point - 1][field]] }
    end
  end

  def monitor_shewhart
    CHARTS.first(6).each do |chart|
      @signals.concat(RunRules.check(chart, phase2_sequence(chart), @limits.fetch(chart), @settings['rules'].fetch(chart)))
    end
  end

  def add_signal(chart, rule, start, finish, value, direction)
    @signals << RunRules::Signal.new(chart: chart, rule: rule, start: start, finish: finish,
                                     value: value, direction: direction)
  end

  def monitor_cusum
    upper = 0.0
    lower = 0.0
    upper_run = 0
    lower_run = 0
    @phase2.each do |point|
      mean = @subgroups[point - 1].mean
      upper = [0.0, upper + (mean - @mu0 - @kc)].max
      lower = [0.0, lower + (@mu0 - mean - @kc)].max
      upper_run = upper > 0 ? upper_run + 1 : 0
      lower_run = lower > 0 ? lower_run + 1 : 0
      @monitoring[point][:upper] = upper
      @monitoring[point][:lower] = lower
      if upper > @hc
        add_signal('CUSUM', 'UPPER', point - upper_run + 1, point, upper, 'UP')
        upper = 0.0
        upper_run = 0
      end
      if lower > @hc
        add_signal('CUSUM', 'LOWER', point - lower_run + 1, point, lower, 'DOWN')
        lower = 0.0
        lower_run = 0
      end
    end
  end

  def smooth_signal(chart, start, finish, value, lower, upper)
    if value > upper
      add_signal(chart, 'UPPER', start, finish, value, 'UP')
    elsif value < lower
      add_signal(chart, 'LOWER', start, finish, value, 'DOWN')
    end
  end

  def monitor_ewma
    weight = @settings['ewma_lambda']
    q = (1 - weight) * (1 - weight)
    value = @mu0
    factor = 1.0
    @phase2.each do |point|
      value = weight * @subgroups[point - 1].mean + (1 - weight) * value
      factor *= q
      width = @settings['ewma_l'] * @sigma * Math.sqrt(@rho * (1 - factor))
      lower = @mu0 - width
      upper = @mu0 + width
      @monitoring[point][:ewma] = {value: value, width: width, lcl: lower, ucl: upper}
      smooth_signal('EWMA', point, point, value, lower, upper)
    end
  end

  def monitor_moving_average
    @phase2.each do |point|
      start = [@m + 1, point - @settings['ma_span'] + 1].max
      length = point - start + 1
      total = @subgroups[start - 1, length].sum(&:total)
      value = total.to_f / (@n * length).to_f
      width = 3 * @sigma / Math.sqrt(length)
      lower = @mu0 - width
      upper = @mu0 + width
      @monitoring[point][:ma] = {value: value, width: width, lcl: lower, ucl: upper}
      smooth_signal('MA', start, point, value, lower, upper)
    end
  end

  def signal_group(signal)
    %w[I MR].include?(signal.chart) ? (signal.finish - 1) / @n + 1 : signal.finish
  end

  def index_signals
    @signals.sort_by! do |signal|
      rule = signal.rule.is_a?(Integer) ? signal.rule : signal.rule == 'UPPER' ? 9 : 10
      [CHARTS.index(signal.chart), signal.finish, rule]
    end
    @by_chart = CHARTS.to_h { |chart| [chart, []] }
    @signal_counts = Array.new(@count + 1, 0)
    @signals.each do |signal|
      @by_chart[signal.chart] << signal
      @signal_counts[signal_group(signal)] += 1
    end
  end

  def build_events
    numbers = @signals.map { |signal| signal_group(signal) }.uniq.sort
    groups = []
    numbers.each do |number|
      if groups.empty? || number - groups[-1][-1] - 1 > @settings['event_gap']
        groups << [number]
      else
        groups[-1] << number
      end
    end
    @event_numbers = Array.new(@count + 1)
    @events = groups.each_with_index.map do |points, index|
      start = points.first
      finish = points.last
      length = finish - start + 1
      signals = @signals.select { |signal| signal_group(signal).between?(start, finish) }
      counts = Array.new(5, 0)
      signals.each do |signal|
        if signal.direction == 'NONE'
          counts[4] += 1
        else
          category = LOCATION.include?(signal.chart) ? 0 : 2
          category += 1 if signal.direction == 'DOWN'
          counts[category] += 1
        end
      end
      detection = CHARTS.to_h do |chart|
        ends = signals.select { |signal| signal.chart == chart }.map { |signal| signal_group(signal) }
        [chart, ends.min]
      end
      onset = signals.select { |signal| signal.chart == 'CUSUM' }.map(&:start).min || start
      selected = @subgroups[start - 1, length]
      mean = selected.sum(&:total).to_f / (@n * length).to_f
      sd_total = 0.0
      selected.each { |subgroup| sd_total += subgroup.sd }
      spread = (sd_total / length.to_f) / @limits['S'].cl
      outside = @samples[(start - 1) * @n, length * @n].count { |value| outside_spec?(value) }
      (start..finish).each { |number| @event_numbers[number] = index + 1 }
      {number: index + 1, start: start, finish: finish, length: length, signals: signals.length,
       charts: CHARTS.select { |chart| !detection[chart].nil? }, counts: counts, onset: onset,
       shift: (mean - @mu0) / @sigma, spread: spread, outside: outside,
       type: EVENT_TYPES[counts.index(counts.max)], detection: detection}
    end
  end

  def outside_spec?(value)
    value < @settings['lsl'] || value > @settings['usl']
  end

  def sample_numbers(subgroups)
    subgroups.flat_map { |number| (((number - 1) * @n + 1)..(number * @n)).to_a }
  end

  def propose_limits
    quiet = @phase2.reject { |number| @event_numbers[number] }
    @proposed = FAMILIES.to_h do |family, _charts|
      additions = family == 'I_MR' ? sample_numbers(quiet) : quiet
      points = @families[family][:retained] + additions
      [family, {points: points.length, estimate: calculate_limits(family, points)}]
    end
  end

  def estimate_attributes
    @attributes = {}
    standard = VariableCharts::Limits.new(lcl: -3.0, cl: 0.0, ucl: 3.0)
    ATTRIBUTES.each do |chart|
      initial = (1..@data.lots.length).to_a
      retained = initial.dup
      passes = []
      fit = nil
      status = nil
      1.upto(@settings['max_passes']) do |pass|
        lots = retained.map { |number| @data.lots[number - 1] }
        fit = AttributeCharts.fit(chart, lots)
        outliers = lots.select { |lot| AttributeCharts.point(chart, fit, lot).status != 'ok' }.map(&:number)
        passes << {number: pass, lots: retained.length, center: fit.center, outliers: outliers}
        if outliers.empty?
          status = 'converged'
          break
        elsif pass == @settings['max_passes']
          status = 'stopped'
          break
        end
        retained -= outliers
      end
      points = @data.lots.map { |lot| AttributeCharts.point(chart, fit, lot) }
      sequence = points.map { |point| [point.number, point.z] }
      signals = RunRules.check('STD', sequence, standard, @settings['rules']['STD'])
      @attributes[chart] = {passes: passes, retained: retained, removed: initial - retained,
                             status: status, points: points, signals: signals}
    end
  end

  def capability_target(numbers)
    subgroups = numbers.map { |number| @subgroups[number - 1] }
    samples = sample_numbers(numbers).map { |number| [number, @samples[number - 1]] }
    values = Capability.calculate(subgroups, samples, @settings, @data.constants)
    {numbers: numbers, samples: samples, values: values}
  end

  def build_capability
    @capability = {'phase1' => capability_target(@families['XBAR_R'][:retained]),
                   'phase2' => capability_target(@phase2)}
    @rolling = []
    start = @m + 1
    width = @settings['rolling_window']
    while start + width - 1 <= @count
      finish = start + width - 1
      @rolling << {start: start, finish: finish, values: capability_target((start..finish).to_a)[:values]}
      start += @settings['rolling_step']
    end
  end

  def real(value)
    text = format('%.4f', value)
    text == '-0.0000' ? '0.0000' : text
  end

  def number_list(numbers)
    numbers.empty? ? 'none' : numbers.join(' ')
  end

  def limit_text(name, limits)
    "#{name} lcl #{real(limits.lcl)} cl #{real(limits.cl)} ucl #{real(limits.ucl)}"
  end

  def family_limit_text(family, estimate)
    FAMILIES[family].each_with_index.map do |chart, index|
      name = %w[XBAR_R XBAR_S].include?(chart) ? 'XBAR' : chart
      limit_text(name, estimate.limits[index])
    end.join(' ')
  end

  def limits_report
    lines = ["characteristic #{@settings['characteristic']}", "subgroup_size #{@n}",
             "subgroups #{@count}", "samples #{@samples.length}", "phase1_subgroups #{@m}"]
    @families.each do |family, result|
      lines << "family #{family}"
      result[:passes].each do |pass|
        lines << "pass #{pass[:number]} points #{pass[:points]} #{family_limit_text(family, pass[:estimate])} out #{number_list(pass[:outliers])}"
      end
      lines << "result #{result[:status]} passes #{result[:passes].length} retained #{result[:retained].length} removed #{number_list(result[:removed])}"
    end
    @phase1_checks.each do |chart, result|
      result[:signals].each do |signal|
        lines << "phase1_signal #{chart} #{signal.rule} #{signal.start} #{signal.finish} #{real(signal.value)}"
      end
      lines << "phase1_check #{chart} points #{result[:points]} signals #{result[:signals].length}"
    end
    @proposed.each do |family, result|
      lines << "proposed #{family} points #{result[:points]} #{family_limit_text(family, result[:estimate])}"
    end
    lines << "cusum target #{real(@mu0)} sigma #{real(@sigma)} k #{real(@kc)} h #{real(@hc)}"
    lines << "ewma target #{real(@mu0)} sigma #{real(@sigma)} lcl #{real(@mu0 - @ewma_width)} ucl #{real(@mu0 + @ewma_width)}"
    lines << "ma target #{real(@mu0)} sigma #{real(@sigma)} span #{@settings['ma_span']} lcl #{real(@mu0 - @ma_width)} ucl #{real(@mu0 + @ma_width)}"
    CHARTS.each do |chart|
      signals = @by_chart.fetch(chart)
      rules = @settings['rules'][chart] || %w[UPPER LOWER]
      counts = rules.map { |rule| "#{rule}:#{signals.count { |signal| signal.rule == rule }}" }.join(' ')
      points = %w[I MR].include?(chart) ? @samples.length - @m * @n : @phase2.length
      ends = signals.map(&:finish).uniq
      lines << "phase2 #{chart} points #{points} signals #{signals.length} signalled #{ends.length} first #{ends.min || 'none'} by_rule #{counts}"
    end
    lines
  end

  def signals_report
    ['chart,rule,start,end,value,direction'] + @signals.map do |signal|
      [signal.chart, signal.rule, signal.start, signal.finish, real(signal.value), signal.direction].join(',')
    end
  end

  def events_report
    lines = ["events #{@events.length}"]
    @events.each do |event|
      counts = event[:counts]
      line = "event #{event[:number]} start #{event[:start]} end #{event[:finish]} length #{event[:length]}"
      line += " signals #{event[:signals]} charts #{event[:charts].join(',')}"
      line += " location_up #{counts[0]} location_down #{counts[1]} spread_up #{counts[2]} spread_down #{counts[3]} pattern #{counts[4]}"
      line += " onset #{event[:onset]} shift #{real(event[:shift])} spread #{real(event[:spread])} out_of_spec #{event[:outside]} type #{event[:type]}"
      lines << line
      detection = CHARTS.map { |chart| "#{chart}:#{event[:detection][chart] || '-'}" }.join(' ')
      lines << "detection #{event[:number]} #{detection}"
    end
    lines
  end

  def subgroup_phase(number)
    return 'phase2' if number > @m

    @families['XBAR_R'][:removed].include?(number) ? 'excluded' : 'phase1'
  end

  def subgroups_report
    lines = ['subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event']
    @subgroups.each do |subgroup|
      number = subgroup.number
      fields = [number, subgroup_phase(number), real(subgroup.mean), RunRules.zone(subgroup.mean, @limits['XBAR_R']),
                subgroup.range, real(subgroup.sd)]
      if number > @m
        row = @monitoring.fetch(number)
        fields.concat([real(row[:upper]), real(row[:lower]), real(row[:ewma][:value]), real(row[:ma][:value])])
      else
        fields.concat(['-', '-', '-', '-'])
      end
      fields.concat([@signal_counts[number], @event_numbers[number] || '-'])
      lines << fields.join(',')
    end
    lines
  end

  def attribute_report
    lines = []
    @attributes.each do |chart, result|
      lines << "chart #{chart}"
      result[:passes].each do |pass|
        lines << "pass #{pass[:number]} lots #{pass[:lots]} center #{real(pass[:center])} out #{number_list(pass[:outliers])}"
      end
      lines << "result #{result[:status]} passes #{result[:passes].length} retained #{result[:retained].length} removed #{number_list(result[:removed])}"
      result[:points].each do |point|
        value = %w[np c].include?(chart) ? point.value.to_s : real(point.value)
        lines << "lot #{point.number} size #{point.size} value #{value} lcl #{real(point.lcl)} ucl #{real(point.ucl)} z #{real(point.z)} status #{point.status}"
      end
      result[:signals].each do |signal|
        lines << "signal #{signal.rule} #{signal.start} #{signal.finish} #{real(signal.value)}"
      end
      lines << "signals #{result[:signals].length}"
    end
    lines
  end

  def capability_report
    lines = []
    fields = %i[mean sigma_within sigma_sbar sigma_overall cp cpu cpl cpk pp ppu ppl ppk cpm]
    @capability.each do |name, group|
      values = group[:values]
      lines << "group #{name} subgroups #{group[:numbers].length} values #{group[:samples].length}"
      fields.each { |field| lines << "#{field} #{real(values[field])}" }
      %i[cpk_ci ppk_ci].each { |field| lines << "#{field} #{values[field].map { |value| real(value) }.join(' ')}" }
      lines << "below_lsl #{values[:below_lsl]}"
      lines << "above_usl #{values[:above_usl]}"
      lines << "ppm #{real(values[:ppm])}"
      group[:samples].each do |number, value|
        next unless outside_spec?(value)

        side = value < @settings['lsl'] ? 'low' : 'high'
        lines << "out_of_spec sample #{number} subgroup #{(number - 1) / @n + 1} value #{value} side #{side}"
      end
      lines << "verdict #{values[:verdict]}"
      Capability.histogram(group[:samples], @settings).each do |row|
        parts = ['bin', row[:start], row[:finish], row[:count]]
        parts << '#' * row[:bar] if row[:bar].positive?
        parts.concat(row[:marks])
        lines << parts.join(' ')
      end
    end
    @rolling.each do |window|
      values = window[:values]
      line = "rolling #{window[:start]} #{window[:finish]}"
      %i[mean sigma_within sigma_overall cpk ppk].each { |field| line += " #{field} #{real(values[field])}" }
      lines << line + " verdict #{values[:verdict]}"
    end
    lines
  end

  def signalled?(chart, number, rule = nil)
    @by_chart[chart].any? { |signal| signal.finish == number && (rule.nil? || signal.rule == rule) }
  end

  def phase_mark(number, family)
    return '2' if number > @m

    @families[family][:removed].include?(number) ? 'x' : '1'
  end

  def charts_report
    lines = []
    [['XBAR', 'XBAR_R', 'XBAR_R', :mean], ['R', 'R', 'XBAR_R', :range], ['S', 'S', 'XBAR_S', :sd]].each do |name, chart, family, field|
      limits = @limits.fetch(chart)
      lines << 'chart ' + limit_text(name, limits)
      @subgroups.each do |subgroup|
        value = subgroup[field]
        signal = subgroup.number > @m && signalled?(chart, subgroup.number)
        band = Plot.shewhart(value, limits, signal)
        lines << format('%3d %s %s %s', subgroup.number, phase_mark(subgroup.number, family), band, real(value))
      end
    end
    lines << "chart CUSUM h #{real(@hc)}"
    @phase2.each do |number|
      row = @monitoring.fetch(number)
      band = Plot.cusum(row[:upper], row[:lower], @hc, signalled?('CUSUM', number, 'UPPER'), signalled?('CUSUM', number, 'LOWER'))
      lines << format('%3d %s %s %s', number, band, real(row[:upper]), real(row[:lower]))
    end
    [['EWMA', :ewma, @ewma_width], ['MA', :ma, @ma_width]].each do |chart, field, width|
      lines << "chart #{chart} lcl #{real(@mu0 - width)} cl #{real(@mu0)} ucl #{real(@mu0 + width)}"
      @phase2.each do |number|
        row = @monitoring[number][field]
        band = Plot.smooth(row[:value], @mu0, width, row[:width], signalled?(chart, number))
        lines << format('%3d %s %s %s %s', number, band, real(row[:value]), real(row[:lcl]), real(row[:ucl]))
      end
    end
    @attributes.each do |chart, result|
      lines << "chart #{chart.upcase}_STD lcl -3.0000 cl 0.0000 ucl 3.0000"
      result[:points].each do |point|
        lines << format('%3d %s %s', point.number, Plot.standardized(point.z, point.status), real(point.z))
      end
    end
    lines
  end

  def run
    estimate_families
    check_phase1
    monitor_shewhart
    monitor_cusum
    monitor_ewma
    monitor_moving_average
    index_signals
    build_events
    propose_limits
    estimate_attributes
    build_capability
    files = {'limits.txt' => limits_report, 'signals.csv' => signals_report, 'events.txt' => events_report,
             'subgroups.csv' => subgroups_report, 'attribute_charts.txt' => attribute_report,
             'capability.txt' => capability_report, 'charts.txt' => charts_report}
    Dir.mkdir('output') unless Dir.exist?('output')
    files.each { |name, lines| File.binwrite('output/' + name, lines.join("\n") + "\n") }
  end
end

ProcessControl.new.run
