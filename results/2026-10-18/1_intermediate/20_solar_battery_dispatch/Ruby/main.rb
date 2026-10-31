SETTING_RANGES = {
  'CAPACITY' => [1, 100_000], 'INITIAL' => [0, 100],
  'CHARGE' => [1, 20_000], 'DISCHARGE' => [1, 20_000],
  'CEFF' => [1, 100], 'DEFF' => [1, 100],
  'RESERVE' => [0, 100], 'COST' => [0, 100_000],
  'EXPORT' => [0, 100_000], 'FEEDIN' => [0, 10_000],
  'FIXED' => [0, 100_000], 'DEMAND' => [0, 100_000],
  'PVSCALE' => [0, 300]
}.freeze
STRATEGY_RANGES = {
  'TOU' => [1, 100], 'PEAKSHAVE' => [0, 100_000], 'BACKUP' => [0, 100]
}.freeze
FLOW_NAMES = %w[PV>LOAD PV>BATTERY PV>GRID PV>CURTAIL BATTERY>LOAD BATTERY>GRID GRID>LOAD GRID>BATTERY].freeze
TOTAL_FIELDS = %i[load pv charge discharge imported exported curtailed drawn loss shortfall import_cost export_income].freeze
DAY_NAMES = %w[MON TUE WED THU FRI SAT SUN].freeze

class CommandError < StandardError; end

def money(value)
  sign = value.negative? ? '-' : ''
  whole, cents = value.abs.divmod(100)
  "#{sign}#{whole}.#{cents.to_s.rjust(2, '0')}"
end

def percentage(numerator, denominator)
  value = denominator.zero? ? 0 : 10_000 * numerator / denominator
  "#{value / 100}.#{(value % 100).to_s.rjust(2, '0')}"
end

def ceiling(numerator, denominator)
  (numerator + denominator - 1) / denominator
end

def truncate_divide(number, denominator)
  number.negative? ? -(-number / denominator) : number / denominator
end

def table_row(values, widths)
  values.zip(widths).map { |value, width| value.to_s.rjust(width) }.join
end

def bar(width)
  "|#{'#' * width}#{'.' * (20 - width)}|"
end

def tariff_extremes(prices)
  [prices.min_by { |_, value| value }[0], prices.max_by { |_, value| value }[0]]
end

def strategy_text(strategy)
  name, parameter = strategy
  parameter.nil? ? name : "#{name} #{parameter}"
end

def read_strategies(tokens)
  strategies = []
  index = 0
  while index < tokens.length
    name = tokens[index]
    index += 1
    if %w[SELF EXPORTPEAK].include?(name)
      strategies << [name, nil]
      next
    end
    raise CommandError, "unknown strategy #{name}" unless STRATEGY_RANGES.key?(name)
    raise CommandError, "missing parameter for #{name}" if index == tokens.length
    parameter = tokens[index].to_i
    index += 1
    low, high = STRATEGY_RANGES.fetch(name)
    raise CommandError, "invalid parameter for #{name}" unless (low..high).cover?(parameter)
    strategies << [name, parameter]
  end
  strategies
end

def require_count(arguments, expected)
  raise CommandError, 'wrong number of arguments' unless arguments.length == expected
end

def one_strategy(arguments)
  strategies = read_strategies(arguments)
  require_count(strategies, 1)
  strategies.first
end

def checked_range(low, high, step, bounds)
  minimum, maximum = bounds
  if low < minimum || high > maximum || high < low || step < 1 ||
     (high - low) / step + 1 > 20
    raise CommandError, 'invalid range'
  end
  (low..high).step(step)
end

class InputData
  attr_reader :initial_settings, :initial_prices, :day_count, :loads, :base_pv,
              :day_names, :weekend_days, :periods, :commands

  def initialize(lines)
    @lines = lines
    @position = 0
    battery = read_tokens.drop(1).map(&:to_i)
    grid = read_tokens.drop(1).map(&:to_i)
    @initial_settings = SETTING_RANGES.keys.zip(battery + grid + [100]).to_h
    period_count = read_tokens[1].to_i
    @initial_prices = {}
    period_count.times do
      name, price = read_tokens
      @initial_prices[name] = price.to_i
    end
    weekday = read_period_hours(read_tokens.drop(1))
    weekend = read_period_hours(read_tokens.drop(1))
    profile_count = read_tokens[1].to_i
    profiles = {}
    profile_count.times do
      kind, name, *values = read_tokens
      profiles[[kind, name]] = values.map(&:to_i)
    end
    @day_count = read_tokens[1].to_i
    @loads, @base_pv = [], []
    @day_count.times do
      load_name, load_pct, pv_name, pv_pct = read_tokens
      @loads.concat(profiles.fetch(['LOAD', load_name]).map { |value| value * load_pct.to_i / 100 })
      @base_pv.concat(profiles.fetch(['PV', pv_name]).map { |value| value * pv_pct.to_i / 100 })
    end
    holidays = read_tokens.drop(2).map(&:to_i).to_h { |day| [day, true] }
    override_count = read_tokens[1].to_i
    override_count.times do
      day, hour, load, pv = read_tokens.map(&:to_i)
      index = (day - 1) * 24 + hour
      @loads[index] = load
      @base_pv[index] = pv
    end
    @day_names, @weekend_days, @periods = [], [], []
    (1..@day_count).each do |day|
      holiday = holidays.key?(day)
      weekend_day = holiday || (day - 1) % 7 >= 5
      @day_names << (holiday ? 'HOL' : DAY_NAMES[(day - 1) % 7])
      @weekend_days << weekend_day
      @periods.concat(weekend_day ? weekend : weekday)
    end
    @commands = @lines.drop(@position)
  end

  private

  def read_tokens
    tokens = @lines[@position].split(' ')
    @position += 1
    tokens
  end

  def read_period_hours(tokens)
    hours = []
    (0...tokens.length).step(2) do |index|
      start = tokens[index].to_i
      finish = index + 2 < tokens.length ? tokens[index + 2].to_i : 24
      hours.concat([tokens[index + 1]] * (finish - start))
    end
    hours
  end
end

class HourRecord
  attr_reader :index, :day, :hour, :period, :load, :pv, :soc, :flows,
              :charge, :discharge, :imported, :exported, :curtailed, :drawn,
              :shortfall, :loss, :import_cost, :export_income, :net_cost

  def initialize(index, period, load, pv, soc, flows, drawn, shortfall, loss, price, feedin)
    @index, @day, @hour = index, index / 24 + 1, index % 24
    @period, @load, @pv, @soc, @flows = period, load, pv, soc, flows
    @charge = flows[1] + flows[7]
    @discharge = flows[4] + flows[5]
    @imported = flows[6] + flows[7]
    @exported = flows[2] + flows[5]
    @curtailed = flows[3]
    @drawn, @shortfall, @loss = drawn, shortfall, loss
    @import_cost = @imported * price / 100_000
    @export_income = @exported * feedin / 100_000
    @net_cost = @import_cost - @export_income
  end
end

class Totals
  attr_reader :count, :flows, :net_cost, *TOTAL_FIELDS

  def initialize(records)
    @count = records.length
    TOTAL_FIELDS.each do |field|
      instance_variable_set("@#{field}", records.sum { |record| record.public_send(field) })
    end
    @flows = FLOW_NAMES.each_index.map do |index|
      records.sum { |record| record.flows[index] }
    end
    @net_cost = @import_cost - @export_income
  end
end

class SimulationResult
  attr_reader :strategy, :settings, :prices, :start_soc, :reserve, :hours, :days,
              :daily, :by_period, :total, :peak, :demand_charge, :bill, :end_soc,
              :sufficiency

  def initialize(strategy, settings, prices, start_soc, reserve, records)
    @strategy, @settings, @prices = strategy, settings.dup, prices.dup
    @start_soc, @reserve, @hours = start_soc, reserve, records
    @days = records.each_slice(24).to_a
    @daily = @days.map { |day| Totals.new(day) }
    @by_period = prices.to_h do |period, _|
      [period, Totals.new(records.select { |record| record.period == period })]
    end
    @total = Totals.new(records)
    @peak = records.map(&:imported).max
    @demand_charge = @peak * settings['DEMAND'] / 1000
    @bill = @total.net_cost + settings['FIXED'] + @demand_charge
    @end_soc = records.last.soc
    @sufficiency = percentage([0, @total.load - @total.imported].max, @total.load)
  end
end

class Simulator
  def initialize(data, strategy, settings, prices, outage = nil)
    @data, @strategy = data, strategy
    @name, @parameter = strategy
    @settings, @prices, @outage = settings.dup, prices.dup, outage
    @capacity, @ceff, @deff = settings.values_at('CAPACITY', 'CEFF', 'DEFF')
    reserve_pct = @name == 'BACKUP' ? [settings['RESERVE'], @parameter].max : settings['RESERVE']
    @reserve = @capacity * reserve_pct / 100
    @start_soc = @capacity * settings['INITIAL'] / 100
    @soc = @start_soc
    @cheapest, @peak = tariff_extremes(prices)
    @arbitrage = @name == 'EXPORTPEAK' && settings['FEEDIN'] > prices.fetch(@cheapest)
  end

  def discharge_target(deficit, period)
    return period == @peak ? deficit : 0 if @name == 'TOU'
    return [0, deficit - @parameter].max if @name == 'PEAKSHAVE'
    return 0 if @arbitrage && period == @cheapest && period != @peak
    deficit
  end

  def grid_charge(period, pv_charge, grid_load)
    headroom = @settings['CHARGE'] - pv_charge
    target = nil
    if @name == 'TOU' && period == @cheapest && period != @peak
      target = @capacity * @parameter / 100
    elsif @name == 'PEAKSHAVE' && period == @cheapest
      target = @capacity
      headroom = [headroom, [0, @parameter - grid_load].max].min
    elsif @name == 'BACKUP' && period == @cheapest
      target = @reserve
    elsif @arbitrage && period == @cheapest && period != @peak
      target = @capacity
    end
    return 0 if target.nil?
    amount = [headroom, ceiling(100 * [0, target - @soc].max, @ceff)].min
    @soc += amount * @ceff / 100
    amount
  end

  def run_hour(index)
    settings = @settings
    load = @data.loads[index]
    pv = @data.base_pv[index] * settings['PVSCALE'] / 100
    period = @data.periods[index]
    direct = [load, pv].min
    surplus = pv - direct
    deficit = load - direct
    pv_charge = [surplus, settings['CHARGE'], ceiling(100 * (@capacity - @soc), @ceff)].min
    @soc += pv_charge * @ceff / 100
    surplus -= pv_charge
    is_outage = !@outage.nil? && @outage[0] <= index && index <= @outage[1]
    target = is_outage ? deficit : discharge_target(deficit, period)
    lower_bound = is_outage ? 0 : @reserve
    load_drawn = [ceiling(100 * target, @deff), settings['DISCHARGE'],
                  [0, @soc - lower_bound].max].min
    load_discharge = load_drawn * @deff / 100
    @soc -= load_drawn
    deficit -= load_discharge
    export_drawn = 0
    battery_export = 0
    if is_outage
      grid_load, shortfall, pv_export, curtailed, grid_charge = 0, deficit, 0, surplus, 0
    else
      grid_load, shortfall = deficit, 0
      pv_export = [surplus, settings['EXPORT']].min
      curtailed = surplus - pv_export
      grid_charge = grid_charge(period, pv_charge, grid_load)
      if @arbitrage && period == @peak && pv_charge.zero?
        export_drawn = [ceiling(100 * (settings['EXPORT'] - pv_export), @deff),
                        settings['DISCHARGE'] - load_drawn,
                        [0, @soc - @reserve].max].min
        battery_export = export_drawn * @deff / 100
        @soc -= export_drawn
      end
    end
    loss = pv_charge - pv_charge * @ceff / 100 +
           grid_charge - grid_charge * @ceff / 100 +
           load_drawn - load_discharge + export_drawn - battery_export
    flows = [direct, pv_charge, pv_export, curtailed, load_discharge,
             battery_export, grid_load, grid_charge]
    HourRecord.new(index, period, load, pv, @soc, flows, load_drawn + export_drawn,
                   shortfall, loss, @prices.fetch(period), settings['FEEDIN'])
  end

  def run
    records = @data.loads.each_index.map { |index| run_hour(index) }
    SimulationResult.new(@strategy, @settings, @prices, @start_soc, @reserve, records)
  end
end

class DispatchDesk
  HANDLERS = {
    'RUN' => :run, 'SET' => :set_value, 'PRICE' => :price, 'RESET' => :reset,
    'CONFIG' => :config, 'NOBATTERY' => :no_battery, 'COMPARE' => :compare,
    'SIZE' => :size, 'SWEEP' => :sweep, 'OUTAGE' => :outage, 'DIFF' => :diff,
    'HOURLY' => :hourly, 'DAILY' => :daily, 'BILL' => :bill, 'SAVINGS' => :savings,
    'BYPERIOD' => :by_period, 'DAYTYPE' => :day_type, 'PEAKS' => :peaks,
    'PROFILE' => :profile, 'FLOWS' => :flows, 'SELFSUFF' => :self_suff,
    'CYCLES' => :cycles, 'USAGE' => :usage, 'HISTOGRAM' => :histogram,
    'CHART' => :chart
  }.freeze

  def initialize(data)
    @data = data
    @settings = data.initial_settings.dup
    @prices = data.initial_prices.dup
    @current = nil
  end

  def execute(tokens)
    command, *args = tokens
    return ["ERROR unknown command #{command}"] unless HANDLERS.key?(command)
    public_send(HANDLERS.fetch(command), args)
  rescue CommandError => e
    ["ERROR #{e.message}"]
  end

  def require_result
    raise CommandError, 'no run' if @current.nil?
    @current
  end

  def checked_day(text)
    day = text.to_i
    raise CommandError, 'invalid day' unless (1..@data.day_count).cover?(day)
    day
  end

  def result_without_arguments(arguments)
    require_count(arguments, 0)
    require_result
  end

  def result_for_day(arguments)
    require_count(arguments, 1)
    day = checked_day(arguments.first)
    [day, require_result]
  end

  def simulate(strategy, settings = @settings, prices = @prices, outage = nil)
    Simulator.new(@data, strategy, settings, prices, outage).run
  end

  def baseline(settings, prices)
    simulate(['SELF', nil], settings.merge('CAPACITY' => 0), prices)
  end

  def run(arguments)
    strategy = one_strategy(arguments)
    result = simulate(strategy)
    @current = result
    total = result.total
    ["RUN #{strategy_text(strategy)} bill #{money(result.bill)} " \
     "import #{total.imported} export #{total.exported} soc #{result.end_soc}"]
  end

  def set_value(arguments)
    require_count(arguments, 2)
    item, text = arguments
    raise CommandError, "unknown parameter #{item}" unless SETTING_RANGES.key?(item)
    value = text.to_i
    low, high = SETTING_RANGES.fetch(item)
    raise CommandError, "invalid value for #{item}" unless (low..high).cover?(value)
    previous = @settings[item]
    @settings[item] = value
    ["SET #{item} #{previous} -> #{value}"]
  end

  def price(arguments)
    require_count(arguments, 2)
    period, text = arguments
    raise CommandError, "unknown period #{period}" unless @prices.key?(period)
    value = text.to_i
    raise CommandError, "invalid value for #{period}" unless (0..10_000).cover?(value)
    previous = @prices[period]
    @prices[period] = value
    cheapest, peak = tariff_extremes(@prices)
    ["PRICE #{period} #{previous} -> #{value} cheapest #{cheapest} peak #{peak}"]
  end

  def reset(arguments)
    require_count(arguments, 0)
    @settings = @data.initial_settings.dup
    @prices = @data.initial_prices.dup
    ['RESET']
  end

  def config(arguments)
    require_count(arguments, 0)
    names = SETTING_RANGES.keys
    battery = names.first(8).map { |name| "#{name.downcase} #{@settings[name]}" }.join(' ')
    grid = names[8, 4].map { |name| "#{name.downcase} #{@settings[name]}" }.join(' ')
    tariff = @prices.map { |period, value| "#{period} #{value}" }.join(' ')
    cheapest, peak = tariff_extremes(@prices)
    ["BATTERY #{battery}", "GRID #{grid}", "SOLAR pvscale #{@settings['PVSCALE']}",
     "TARIFF #{tariff} cheapest #{cheapest} peak #{peak}"]
  end

  def no_battery(arguments)
    require_count(arguments, 0)
    result = baseline(@settings, @prices)
    total = result.total
    ["NOBATTERY bill #{money(result.bill)} import #{total.imported} " \
     "export #{total.exported} curtailed #{total.curtailed} peak #{result.peak}"]
  end

  def compare(arguments)
    strategies = read_strategies(arguments)
    raise CommandError, 'wrong number of arguments' if strategies.empty?
    reference = baseline(@settings, @prices)
    trials = strategies.map { |strategy| simulate(strategy) }.sort_by(&:bill)
    output = ["COMPARE baseline #{money(reference.bill)}"]
    trials.each_with_index do |result, index|
      output << "#{index + 1}. #{strategy_text(result.strategy)} bill #{money(result.bill)} " \
                "saving #{money(reference.bill - result.bill)} sufficiency #{result.sufficiency}%"
    end
    output
  end

  def size(arguments)
    require_count(arguments, 3)
    capacities = checked_range(*arguments.map(&:to_i), SETTING_RANGES.fetch('CAPACITY'))
    reference = baseline(@settings, @prices)
    output = []
    best = nil
    capacities.each do |capacity|
      settings = @settings.merge('CAPACITY' => capacity)
      result = simulate(['SELF', nil], settings)
      saving = reference.bill - result.bill
      cost = capacity * settings['COST'] / 1000
      payback = 'never'
      if saving.positive?
        tenths = 10 * cost / saving
        payback = "#{tenths / 10}.#{tenths % 10}"
        if best.nil? || cost * best[2] < best[1] * saving
          best = [capacity, cost, saving]
        end
      end
      output << "SIZE #{capacity} bill #{money(result.bill)} saving #{money(saving)} " \
                "cost #{money(cost)} payback #{payback}"
    end
    output << (best.nil? ? 'BEST none' : "BEST #{best[0]}")
    output
  end

  def sweep(arguments)
    raise CommandError, 'wrong number of arguments' if arguments.length < 5
    item = arguments[0]
    raise CommandError, "unknown parameter #{item}" unless SETTING_RANGES.key?(item)
    values = checked_range(*arguments[1, 3].map(&:to_i), SETTING_RANGES.fetch(item))
    strategy = one_strategy(arguments.drop(4))
    output = []
    best = nil
    values.each do |value|
      settings = @settings.merge(item => value)
      result = simulate(strategy, settings)
      reference = baseline(settings, @prices)
      best = [value, result.bill] if best.nil? || result.bill < best[1]
      output << "SWEEP #{item} #{value} bill #{money(result.bill)} " \
                "saving #{money(reference.bill - result.bill)} " \
                "sufficiency #{result.sufficiency}%"
    end
    output << "BEST #{best[0]}"
    output
  end

  def outage(arguments)
    require_count(arguments, 3)
    day = checked_day(arguments[0])
    start, finish = arguments.drop(1).map(&:to_i)
    raise CommandError, 'invalid hours' unless 0 <= start && start <= finish && finish <= 23
    current = require_result
    first = (day - 1) * 24 + start
    last = (day - 1) * 24 + finish
    result = simulate(current.strategy, current.settings, current.prices, [first, last])
    before = first.zero? ? result.start_soc : result.hours[first - 1].soc
    output = ["OUTAGE day #{day} hours #{start}-#{finish} " \
              "strategy #{strategy_text(result.strategy)} soc #{before}",
              'hour   load     pv  disch    soc  short   curt']
    records = result.hours[first..last]
    records.each do |record|
      output << table_row([record.hour, record.load, record.pv, record.discharge,
                           record.soc, record.shortfall, record.curtailed], [4] + [7] * 6)
    end
    total = Totals.new(records)
    served = total.load.zero? ? '100.00' : percentage(total.load - total.shortfall, total.load)
    output << "TOTAL load #{total.load} unserved #{total.shortfall} " \
              "served #{served}% bill #{money(result.bill)}"
    output
  end

  def diff(arguments)
    raise CommandError, 'wrong number of arguments' if arguments.length < 2
    day = checked_day(arguments[0])
    strategy = one_strategy(arguments.drop(1))
    current = require_result
    comparison = simulate(strategy, current.settings, current.prices)
    output = ["DIFF day #{day} #{@data.day_names[day - 1]} " \
              "#{strategy_text(current.strategy)} vs #{strategy_text(strategy)}",
              'hour   imp1   imp2   exp1   exp2   soc1   soc2']
    current.days[day - 1].zip(comparison.days[day - 1]).each do |first, second|
      output << table_row([first.hour, first.imported, second.imported, first.exported,
                           second.exported, first.soc, second.soc], [4] + [7] * 6)
    end
    cost1 = current.daily[day - 1].net_cost
    cost2 = comparison.daily[day - 1].net_cost
    output << "TOTAL cost1 #{money(cost1)} cost2 #{money(cost2)} " \
              "difference #{money(cost2 - cost1)}"
    output
  end

  def hourly(arguments)
    day, result = result_for_day(arguments)
    output = ["HOURLY day #{day} #{@data.day_names[day - 1]} " \
              "strategy #{strategy_text(result.strategy)}",
              'hour   load     pv charge  disch    soc import export   curt']
    widths = [4] + [7] * 8
    result.days[day - 1].each do |record|
      output << table_row([record.hour, record.load, record.pv, record.charge,
                           record.discharge, record.soc, record.imported,
                           record.exported, record.curtailed], widths)
    end
    total = result.daily[day - 1]
    output << table_row(['sum', total.load, total.pv, total.charge,
                         total.discharge, '', total.imported, total.exported,
                         total.curtailed], widths)
    output
  end

  def daily(arguments)
    result = result_without_arguments(arguments)
    output = ["DAILY strategy #{strategy_text(result.strategy)}",
              'day name    load      pv  import  export    curt     soc      cost']
    result.daily.each_with_index do |total, index|
      output << table_row([index + 1, @data.day_names[index], total.load, total.pv,
                           total.imported, total.exported, total.curtailed,
                           result.days[index].last.soc, money(total.net_cost)],
                          [3, 5] + [8] * 6 + [10])
    end
    total = result.total
    output << "TOTAL load #{total.load} pv #{total.pv} import #{total.imported} " \
              "export #{total.exported} curtailed #{total.curtailed} " \
              "cost #{money(total.net_cost)}"
    output
  end

  def bill(arguments)
    result = result_without_arguments(arguments)
    output = ["BILL strategy #{strategy_text(result.strategy)} days #{@data.day_count}"]
    result.by_period.each do |period, total|
      output << "IMPORT #{period} #{total.imported} Wh #{money(total.import_cost)}"
    end
    output.concat([
      "EXPORT #{result.total.exported} Wh #{money(-result.total.export_income)}",
      "FIXED #{money(result.settings['FIXED'])}",
      "DEMAND #{result.peak} Wh #{money(result.demand_charge)}",
      "TOTAL #{money(result.bill)}"
    ])
    output
  end

  def savings(arguments)
    result = result_without_arguments(arguments)
    reference = baseline(result.settings, result.prices)
    rows = result.by_period.map do |period, total|
      [period, reference.by_period[period].import_cost, total.import_cost]
    end
    rows.concat([
      ['EXPORT', -reference.total.export_income, -result.total.export_income],
      ['DEMAND', reference.demand_charge, result.demand_charge],
      ['TOTAL', reference.bill, result.bill]
    ])
    output = ["SAVINGS strategy #{strategy_text(result.strategy)}"]
    rows.each do |name, before, after|
      output << "#{name} #{money(before)} -> #{money(after)} " \
                "saving #{money(before - after)}"
    end
    output
  end

  def by_period(arguments)
    result = result_without_arguments(arguments)
    output = ["BYPERIOD strategy #{strategy_text(result.strategy)}"]
    result.by_period.each do |period, total|
      output << "#{period} hours #{total.count} load #{total.load} pv #{total.pv} " \
                "charge #{total.charge} discharge #{total.discharge} " \
                "import #{total.imported} export #{total.exported}"
    end
    output
  end

  def day_type(arguments)
    result = result_without_arguments(arguments)
    output = ["DAYTYPE strategy #{strategy_text(result.strategy)}"]
    [['WEEKDAY', false], ['WEEKEND', true]].each do |name, weekend|
      days = @data.weekend_days.each_index.select { |index| @data.weekend_days[index] == weekend }
      records = days.flat_map { |day| result.days[day] }
      total = Totals.new(records)
      count = days.length
      output << "#{name} days #{count} load #{total.load / count} " \
                "pv #{total.pv / count} import #{total.imported / count} " \
                "export #{total.exported / count} " \
                "cost #{money(truncate_divide(total.net_cost, count))}"
    end
    output
  end

  def peaks(arguments)
    require_count(arguments, 1)
    count = arguments.first.to_i
    raise CommandError, 'invalid count' if count < 1
    result = require_result
    records = result.hours.select { |record| record.imported.positive? }
    records.sort_by! { |record| [-record.imported, record.index] }
    output = ["PEAKS strategy #{strategy_text(result.strategy)}"]
    records.first(count).each_with_index do |record, index|
      output << "#{index + 1}. day #{record.day} hour #{record.hour} #{record.period} " \
                "import #{record.imported} load #{record.load} soc #{record.soc}"
    end
    output << 'none' if records.empty?
    output
  end

  def profile(arguments)
    result = result_without_arguments(arguments)
    output = ["PROFILE strategy #{strategy_text(result.strategy)} days #{@data.day_count}",
              'hour   load     pv import export    soc']
    24.times do |hour|
      records = result.hours.select { |record| record.hour == hour }
      averages = %i[load pv imported exported soc].map do |field|
        records.sum { |record| record.public_send(field) } / @data.day_count
      end
      output << table_row([hour, *averages], [4] + [7] * 5)
    end
    output
  end

  def flows(arguments)
    result = result_without_arguments(arguments)
    output = ["FLOWS strategy #{strategy_text(result.strategy)}"]
    FLOW_NAMES.zip(result.total.flows).each do |name, amount|
      output << "#{name} #{amount}"
    end
    output << "LOSSES #{result.total.loss}"
    output << "STORED #{result.end_soc - result.start_soc}"
    output
  end

  def self_suff(arguments)
    result = result_without_arguments(arguments)
    flows = result.total.flows
    ["SELFSUFF sufficiency #{result.sufficiency}% " \
     "consumption #{percentage(flows[0] + flows[1], result.total.pv)}%"]
  end

  def cycles(arguments)
    result = result_without_arguments(arguments)
    drawn = result.total.drawn
    capacity = result.settings['CAPACITY']
    common = drawn.gcd(capacity)
    numerator, denominator = drawn / common, capacity / common
    thousandths = 1000 * drawn / capacity
    decimal = "#{thousandths / 1000}.#{(thousandths % 1000).to_s.rjust(3, '0')}"
    ["CYCLES #{numerator}/#{denominator} #{decimal} " \
     "drawn #{drawn} losses #{result.total.loss}"]
  end

  def usage(arguments)
    result = result_without_arguments(arguments)
    hours = result.hours
    charging = hours.count { |record| record.charge.positive? }
    discharging = hours.count { |record| record.drawn.positive? }
    idle = hours.count { |record| record.charge.zero? && record.drawn.zero? }
    full = hours.count { |record| record.soc == result.settings['CAPACITY'] }
    low = 0
    run_length = 0
    longest = 0
    first = nil
    hours.each do |record|
      if record.soc <= result.reserve
        low += 1
        run_length += 1
        if run_length > longest
          longest = run_length
          first = hours[record.index - run_length + 1]
        end
      else
        run_length = 0
      end
    end
    line = "USAGE charging #{charging} discharging #{discharging} idle #{idle} " \
           "full #{full} low #{low} longest #{longest}"
    line += " from day #{first.day} hour #{first.hour}" unless first.nil?
    [line]
  end

  def histogram(arguments)
    result = result_without_arguments(arguments)
    capacity = result.settings['CAPACITY']
    counts = Array.new(10, 0)
    result.hours.each do |record|
      counts[[9, 10 * record.soc / capacity].min] += 1
    end
    output = ["HISTOGRAM strategy #{strategy_text(result.strategy)}"]
    counts.each_with_index do |count, index|
      width = 20 * count / result.hours.length
      output << "#{(10 * index).to_s.rjust(3)}% #{bar(width)} #{count}"
    end
    output
  end

  def chart(arguments)
    day, result = result_for_day(arguments)
    capacity = result.settings['CAPACITY']
    output = ["CHART day #{day} #{@data.day_names[day - 1]} " \
              "strategy #{strategy_text(result.strategy)}"]
    result.days[day - 1].each do |record|
      width = 20 * record.soc / capacity
      output << "#{record.hour.to_s.rjust(2)} #{bar(width)} " \
                "#{percentage(record.soc, capacity)}%"
    end
    output
  end
end

lines = STDIN.each_line.map(&:chomp)
data = InputData.new(lines)
desk = DispatchDesk.new(data)
output = []
data.commands.each do |line|
  tokens = line.split(' ')
  break if tokens.first == 'END'
  output.concat(desk.execute(tokens))
end
puts output unless output.empty?
