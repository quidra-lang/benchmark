# frozen_string_literal: true

require 'set'
require_relative 'dates_calendar'
require_relative 'daycount'
require_relative 'schedule'
require_relative 'pricing'
require_relative 'curve'

class PortfolioAnalysis
  TYPES = %w[FIXED ZERO AMORT FRN].freeze
  BUSINESS_RULES = %w[FOLLOWING MODIFIED_FOLLOWING PRECEDING UNADJUSTED].freeze
  BUCKETS = ['0-1Y', '1-3Y', '3-5Y', '5-10Y', '10Y+'].freeze

  def initialize
    @errors = []
    @scenarios = []
    @limits = []
  end

  def round_ratio(numerator, denominator)
    (2 * numerator + denominator) / (2 * denominator)
  end

  def price(text)
    text.delete('.').to_i
  end

  def hundredths(value)
    sign = value.negative? ? '-' : ''
    whole, fraction = value.abs.divmod(100)
    "#{sign}#{whole}.#{fraction.to_s.rjust(2, '0')}"
  end

  def decimal(value, digits)
    factor = { 2 => 100, 4 => 10_000, 6 => 1_000_000 }.fetch(digits)
    rounded = (value.abs * factor.to_f + 0.5).floor
    sign = value.negative? && rounded.positive? ? '-' : ''
    whole, fraction = rounded.divmod(factor)
    "#{sign}#{whole}.#{fraction.to_s.rjust(digits, '0')}"
  end

  def percent(value)
    decimal(value * 100.0, 4)
  end

  def amount(value)
    decimal(value / 100.0, 2)
  end

  def rows(file)
    File.readlines("input/#{file}", chomp: true).drop(1).each_with_index.map do |line, index|
      [index + 2, line.split(',')]
    end
  end

  def error(file, line, key, message)
    @errors << "#{file}:#{line}: #{key}: #{message}"
  end

  def read_parameters
    @parameter_lines = File.readlines('input/params.txt', chomp: true).map { |line| line.split(' ') }
    @valuation = BondDates.parse(@parameter_lines.find { |words| words.first == 'valuation_date' }[1])
    settlement_days = @parameter_lines.find { |words| words.first == 'settlement_days' }[1].to_i
    holidays = File.readlines('input/calendar.txt', chomp: true).map { |text| BondDates.parse(text) }
    @calendar = BondDates::Calendar.new(holidays)
    @settlement = @calendar.shift(@valuation, settlement_days)
    @fixings = rows('fixings.csv').map { |_, fields| [BondDates.parse(fields[0]), fields[1].to_i] }
    @limits = @parameter_lines.select { |words| words.first == 'limit' }.map { |words| words.drop(1) }
  end

  def validate_pillars
    seen = Set.new
    @pillars = []
    rows('curve_quotes.csv').each do |line, fields|
      text, coupon, frequency = fields
      maturity = BondDates.parse(text)
      duplicate = seen.include?(text)
      seen.add(text)
      message = if duplicate
                  'duplicate pillar'
                elsif maturity.nil?
                  'invalid date'
                elsif maturity <= @settlement
                  'pillar not after settlement'
                elsif !CouponSchedule::FREQUENCIES.include?(frequency.to_i)
                  'invalid frequency'
                end
      if message
        error('curve_quotes.csv', line, text, message)
      else
        @pillars << { maturity: maturity, coupon: coupon.to_i, frequency: frequency.to_i }
      end
    end
    @pillars.sort_by! { |pillar| pillar[:maturity] }
    @curve = ZeroCurve.bootstrap(@pillars, @settlement)
  end

  def validate_scenarios
    seen = Set.new
    @parameter_lines.each_with_index do |words, index|
      next unless words.first == 'scenario'

      _, name, *shifts = words
      duplicate = seen.include?(name)
      seen.add(name)
      message = duplicate ? 'duplicate scenario' : shifts.length != @pillars.length ? 'wrong number of shifts' : nil
      if message
        error('params.txt', index + 1, name, message)
      else
        @scenarios << { name: name, shifts: shifts.map { |shift| shift.to_i.to_f * 0.0001 } }
      end
    end
  end

  def parse_options(type, text)
    allowed = %w[EOM LONG] + { 'FIXED' => ['CALL'], 'ZERO' => [], 'AMORT' => ['SINK'],
                              'FRN' => %w[LAG CAP FLOOR] }.fetch(type)
    values = {}
    sinks = []
    calls = []
    (text == '-' ? [] : text.split(';')).each do |item|
      key, _, value = item.partition('=')
      return nil unless allowed.include?(key)
      return nil if values.key?(key) && !%w[SINK CALL].include?(key)

      values[key] = value
      if key == 'SINK'
        date, _, redemption = value.partition(':')
        sinks << [BondDates.parse(date), redemption.to_i]
      elsif key == 'CALL'
        date, _, call_price = value.partition(':')
        calls << [BondDates.parse(date), price(call_price)]
      end
    end
    lag = values['LAG']&.to_i
    cap = values['CAP']&.to_i
    floor = values['FLOOR']&.to_i
    if type == 'FRN'
      return nil if lag.nil? || !lag.between?(1, 5) || (!cap.nil? && cap > 1200)
      return nil if !floor.nil? && floor > (cap || 1200)
    end
    { eom: values.key?('EOM'), long: values.key?('LONG'), lag: lag, cap: cap, floor: floor,
      sinks: sinks, calls: calls }
  end

  def valid_redemptions?(entries, interior)
    previous = nil
    entries.all? do |date, _|
      valid = !date.nil? && interior.include?(date) && (previous.nil? || date > previous)
      previous = date
      valid
    end
  end

  def index_rate(date)
    later = @fixings.bsearch_index { |fixing| fixing[0] > date }
    index = (later || @fixings.length) - 1
    index.negative? ? nil : @fixings[index][1]
  end

  def cashflows(bond)
    opening = bond[:face]
    sinks = bond[:options][:sinks].to_h
    periods = []
    bond[:dates].each_cons(2).with_index(1) do |(first, last), index|
      numerator, denominator = DayCount.fraction(first, last, bond[:daycount])
      rate = bond[:coupon]
      if bond[:type] == 'FRN'
        fixing_date = @calendar.shift(@calendar.adjust(first, bond[:bdc]), -bond[:options][:lag])
        fixing = index_rate(fixing_date)
        return nil if fixing.nil?

        rate += fixing
        rate = [rate, bond[:options][:floor]].max unless bond[:options][:floor].nil?
        rate = [rate, bond[:options][:cap]].min unless bond[:options][:cap].nil?
      end
      principal = last == bond[:maturity] ? opening : sinks.fetch(last, 0)
      coupon = round_ratio(opening * rate * numerator, 10_000 * denominator)
      periods << { number: index, start: first, end: last, payment: @calendar.adjust(last, bond[:bdc]),
                   numerator: numerator, denominator: denominator, rate: rate, opening: opening,
                   coupon: coupon, principal: principal, amount: coupon + principal }
      opening -= principal
    end
    periods
  end

  def validate_bond(fields)
    id, type, issue_text, maturity_text, coupon, frequency, daycount, bdc, face, text = fields
    return [nil, 'unknown type'] unless TYPES.include?(type)

    issue = BondDates.parse(issue_text)
    maturity = BondDates.parse(maturity_text)
    return [nil, 'invalid date'] if issue.nil? || maturity.nil?
    return [nil, 'maturity not after issue'] if maturity <= issue
    return [nil, 'invalid frequency'] unless CouponSchedule::FREQUENCIES.include?(frequency.to_i)
    return [nil, 'unknown day count'] unless DayCount::CONVENTIONS.include?(daycount)
    return [nil, 'unknown business day rule'] unless BUSINESS_RULES.include?(bdc)

    face = face.to_i
    coupon = coupon.to_i
    return [nil, 'invalid face'] unless (face % 100_000).zero? && face <= 10_000_000
    return [nil, 'invalid coupon'] if coupon > 1200 || (type == 'ZERO' && !coupon.zero?)

    options = parse_options(type, text)
    return [nil, 'invalid option'] if options.nil?

    dates = CouponSchedule.build(issue, maturity, frequency.to_i, eom: options[:eom], long: options[:long])
    interior = dates[1...-1].to_set
    sinking_total = options[:sinks].sum { |_, value| value }
    if !valid_redemptions?(options[:sinks], interior) || options[:sinks].any? { |_, value| value.zero? } ||
       (type == 'AMORT' && (sinking_total.zero? || sinking_total >= face))
      return [nil, 'invalid sinking fund']
    end
    if !valid_redemptions?(options[:calls], interior) || options[:calls].any? { |_, value| !value.between?(100_000, 110_000) }
      return [nil, 'invalid call schedule']
    end
    bond = { id: id, type: type, issue: issue, maturity: maturity, coupon: coupon,
             frequency: frequency.to_i, daycount: daycount, bdc: bdc, face: face, options: options, dates: dates }
    bond[:periods] = cashflows(bond)
    bond[:periods].nil? ? [nil, 'missing fixing'] : [bond, nil]
  end

  def validate_bonds
    @bonds = {}
    seen = Set.new
    rows('bonds.csv').each do |line, fields|
      duplicate = seen.include?(fields.first)
      seen.add(fields.first)
      bond, message = duplicate ? [nil, 'duplicate id'] : validate_bond(fields)
      if message
        error('bonds.csv', line, fields.first, message)
      else
        @bonds[bond[:id]] = bond
      end
    end
  end

  def settlement_values(bond, clean_price)
    current = bond[:periods].index { |period| period[:end] > @settlement }
    period = bond[:periods][current]
    outstanding = period[:opening]
    numerator, denominator = DayCount.fraction(period[:start], @settlement, bond[:daycount])
    accrued = period[:rate].to_f * numerator.to_f / (100.0 * denominator.to_f)
    accrued_cents = round_ratio(outstanding * period[:rate] * numerator, 10_000 * denominator)
    clean_cents = round_ratio(outstanding * clean_price, 100_000)
    remaining = bond[:periods].drop(current)
    flows = remaining.select { |flow| flow[:amount].positive? }
    numerator, denominator = DayCount.fraction(@settlement, period[:end], bond[:daycount])
    fraction = bond[:frequency].to_f * numerator.to_f / denominator.to_f
    { bond: bond, clean_price: clean_price, outstanding: outstanding, accrued: accrued,
      accrued_cents: accrued_cents, clean_cents: clean_cents, value: clean_cents + accrued_cents,
      target: clean_price.to_f / 1000.0 + accrued, fraction: fraction, remaining: remaining,
      flows: flows, pairs: flows.map { |flow| [flow[:payment] - @settlement, flow[:amount]] },
      model: YieldPricing.new(remaining.map { |flow| flow[:amount] }, fraction, bond[:frequency], outstanding) }
  end

  def bond_analytics(asset)
    bond = asset[:bond]
    metrics = asset[:model].analytics(asset[:target])
    metrics[:ytw] = metrics[:ytm]
    metrics[:workout] = bond[:maturity]
    bond[:options][:calls].each do |date, call_price|
      next unless date > @settlement

      last = asset[:remaining].index { |period| period[:end] == date }
      periods = asset[:remaining].take(last + 1)
      amounts = periods.map { |period| period[:coupon] }
      amounts[-1] += round_ratio(periods.last[:opening] * call_price, 100_000)
      model = YieldPricing.new(amounts, asset[:fraction], bond[:frequency], asset[:outstanding])
      call_yield = model.yield_to(asset[:target])
      if call_yield < metrics[:ytw]
        metrics[:ytw] = call_yield
        metrics[:workout] = date
      end
    end
    life = asset[:flows].reduce(0.0) do |total, flow|
      total + flow[:principal].to_f * (flow[:payment] - @settlement).to_f
    end
    metrics[:wal] = life / (365.0 * asset[:outstanding].to_f)
    metrics[:next_payment] = asset[:flows].first[:payment]
    metrics[:curve_clean] = @curve.present_value(asset[:pairs]) * 100.0 / asset[:outstanding].to_f - asset[:accrued]
    metrics[:zspread] = @curve.zspread(asset[:pairs], asset[:value])
    asset[:metrics] = metrics
  end

  def validate_prices
    @priced = {}
    seen = Set.new
    rows('prices.csv').each do |line, (id, clean_price)|
      duplicate = seen.include?(id)
      seen.add(id)
      bond = @bonds[id]
      message = if bond.nil?
                  'unknown bond'
                elsif duplicate
                  'duplicate price'
                elsif !(bond[:issue] <= @settlement && @settlement < bond[:maturity])
                  'not outstanding'
                end
      if message.nil?
        asset = settlement_values(bond, price(clean_price))
        unless asset[:model].dirty(0.0) > asset[:target] && asset[:target] > asset[:model].dirty(1.0)
          message = 'yield out of range'
        end
      end
      if message
        error('prices.csv', line, id, message)
      else
        bond_analytics(asset)
        @priced[id] = asset
      end
    end
  end

  def validate_holdings
    @positions = {}
    rows('holdings.csv').each do |line, (name, id, face, book_price)|
      asset = @priced[id]
      message = if !@bonds.key?(id)
                  'unknown bond'
                elsif asset.nil?
                  'no price'
                elsif !(face.to_i % asset[:bond][:face]).zero?
                  'invalid face'
                end
      if message
        error('holdings.csv', line, id, message)
        next
      end
      units = face.to_i / asset[:bond][:face]
      position = (@positions[[name, id]] ||= { portfolio: name, id: id, asset: asset, units: 0, book: 0 })
      position[:units] += units
      position[:book] += round_ratio(units * asset[:outstanding] * price(book_price), 100_000)
    end
    @positions.each_value do |position|
      asset = position[:asset]
      units = position[:units]
      position[:face] = units * asset[:bond][:face]
      position[:outstanding] = units * asset[:outstanding]
      position[:value] = units * asset[:value]
      position[:gain] = units * asset[:clean_cents] - position[:book]
      position[:dv01] = asset[:metrics][:dv01] * units.to_f * asset[:outstanding].to_f / 10_000.0
    end
  end

  def curve_values(positions, shifts)
    curve = @curve.shifted(shifts)
    positions.map do |position|
      asset = position[:asset]
      position[:units].to_f * curve.present_value(asset[:pairs], asset[:metrics][:zspread])
    end
  end

  def portfolio(name, positions)
    totals = %i[face outstanding value book gain].to_h { |key| [key, positions.sum { |position| position[key] }] }
    value = totals[:value].to_f
    risk = %i[ytm modified convexity zspread].to_h do |key|
      weighted = positions.reduce(0.0) { |total, position| total + position[:value].to_f * position[:asset][:metrics][key] }
      [key, weighted / value]
    end
    risk[:dv01] = positions.reduce(0.0) { |total, position| total + position[:dv01] }
    flows = []
    ladder = Hash.new { |hash, year| hash[year] = [0, 0] }
    totals[:income] = 0
    positions.each do |position|
      position[:weight] = position[:value].to_f * 100.0 / value
      position[:asset][:flows].each do |flow|
        units = position[:units]
        day = flow[:payment] - @settlement
        flows << [day, units * flow[:amount]]
        totals[:income] += units * flow[:coupon] if day <= 365
        year = BondDates.parts(flow[:payment])[0]
        ladder[year][0] += units * flow[:coupon]
        ladder[year][1] += units * flow[:principal]
      end
    end
    risk[:yield] = Bisection.solve(0.0, 1.0, value) { |rate| ZeroCurve.new([1], [rate]).present_value(flows) }
    zero = Array.new(@pillars.length, 0.0)
    base_values = curve_values(positions, zero)
    base = base_values.reduce(0.0, :+)
    lower = curve_values(positions, Array.new(@pillars.length, -0.0001)).reduce(0.0, :+)
    upper = curve_values(positions, Array.new(@pillars.length, 0.0001)).reduce(0.0, :+)
    risk[:effective] = (lower - upper) / (2.0 * 0.0001 * base)
    risk[:krd] = @pillars.each_index.map do |index|
      shifts = zero.dup
      shifts[index] = -0.0001
      lower = curve_values(positions, shifts).reduce(0.0, :+)
      shifts[index] = 0.0001
      upper = curve_values(positions, shifts).reduce(0.0, :+)
      (lower - upper) / (2.0 * 0.0001 * base)
    end
    scenarios = [{ name: 'BASE', values: base_values, total: base, pnl: 0.0, changes: positions.map { 0.0 } }]
    @scenarios.each do |scenario|
      values = curve_values(positions, scenario[:shifts])
      total = values.reduce(0.0, :+)
      scenarios << { name: scenario[:name], values: values, total: total, pnl: total - base,
                     changes: values.each_with_index.map { |price, index| price - base_values[index] } }
    end
    { name: name, positions: positions, totals: totals, risk: risk, ladder: ladder, scenarios: scenarios }
  end

  def bucket(position)
    days = position[:asset][:bond][:maturity] - @settlement
    [365, 1095, 1825, 3650].index { |limit| days < limit } || 4
  end

  def group_line(kind, name, positions, total_value)
    value = positions.sum { |position| position[:value] }
    duration = positions.reduce(0.0) { |total, position| total + position[:value].to_f * position[:asset][:metrics][:modified] }
    dv01 = positions.reduce(0.0) { |total, position| total + position[:dv01] }
    "#{kind} #{name} positions #{positions.length} value #{hundredths(value)} weight #{decimal(value.to_f * 100.0 / total_value.to_f, 4)} " \
      "duration #{decimal(duration / total_value.to_f, 4)} dv01 #{decimal(dv01, 2)}"
  end

  def portfolio_lines(portfolio)
    positions = portfolio[:positions]
    totals = portfolio[:totals]
    risk = portfolio[:risk]
    lines = ["portfolio #{portfolio[:name]}"]
    positions.each do |position|
      asset = position[:asset]
      metrics = asset[:metrics]
      lines << "position #{position[:id]} face #{hundredths(position[:face])} outstanding #{hundredths(position[:outstanding])} " \
               "clean #{decimal(asset[:clean_price].to_f / 1000.0, 6)} value #{hundredths(position[:value])} weight #{decimal(position[:weight], 4)} " \
               "book #{hundredths(position[:book])} gain #{hundredths(position[:gain])} ytm #{percent(metrics[:ytm])} " \
               "modified #{decimal(metrics[:modified], 4)} dv01 #{decimal(position[:dv01], 2)}"
    end
    lines << "total positions #{positions.length} " + %i[face outstanding value book gain income].map { |key| "#{key} #{hundredths(totals[key])}" }.join(' ')
    lines << "risk ytm #{percent(risk[:ytm])} yield #{percent(risk[:yield])} modified #{decimal(risk[:modified], 4)} " \
             "convexity #{decimal(risk[:convexity], 4)} zspread #{percent(risk[:zspread])} dv01 #{decimal(risk[:dv01], 2)}"
    lines << "curve effective #{decimal(risk[:effective], 4)} krd #{risk[:krd].map { |value| decimal(value, 4) }.join(' ')}"
    TYPES.each do |type|
      members = positions.select { |position| position[:asset][:bond][:type] == type }
      lines << group_line('type', type, members, totals[:value])
    end
    BUCKETS.each_with_index do |name, index|
      lines << group_line('bucket', name, positions.select { |position| bucket(position) == index }, totals[:value])
    end
    coupon_total = principal_total = 0
    portfolio[:ladder].sort.each do |year, (coupon, principal)|
      lines << "ladder #{year} coupon #{hundredths(coupon)} principal #{hundredths(principal)} total #{hundredths(coupon + principal)}"
      coupon_total += coupon
      principal_total += principal
    end
    lines << "ladder total coupon #{hundredths(coupon_total)} principal #{hundredths(principal_total)} total #{hundredths(coupon_total + principal_total)}"
    unless @scenarios.empty?
      worst = portfolio[:scenarios].drop(1).reduce { |chosen, scenario| scenario[:pnl] < chosen[:pnl] ? scenario : chosen }
      indices = positions.each_index.sort_by { |index| [worst[:changes][index], positions[index][:id]] }.first(3)
      losers = indices.map { |index| "#{positions[index][:id]} #{amount(worst[:changes][index])}" }.join(' ')
      lines << "stress worst #{worst[:name]} pnl #{amount(worst[:pnl])} losers #{losers}"
    end
    lines
  end

  def compliance(portfolio)
    name = portfolio[:name]
    positions = portfolio[:positions]
    risk = portfolio[:risk]
    total = portfolio[:totals][:value]
    breaches = 0
    lines = @limits.map do |kind, *arguments|
      case kind
      when 'position_weight'
        limit = arguments.first.to_i
        position = positions.min_by { |entry| [-entry[:value], entry[:id]] }
        breach = position[:value] * 10_000 > limit * total
        detail = "position_weight #{position[:id]} #{decimal(position[:weight], 4)} limit #{hundredths(limit)}"
      when 'type_weight'
        type, value = arguments
        limit = value.to_i
        weight = positions.select { |position| position[:asset][:bond][:type] == type }.sum { |position| position[:value] }
        breach = weight * 10_000 > limit * total
        detail = "type_weight #{type} #{decimal(weight.to_f * 100.0 / total.to_f, 4)} limit #{hundredths(limit)}"
      when 'max_maturity'
        years = arguments.first.to_i
        count = positions.count { |position| position[:asset][:bond][:maturity] - @settlement > 365 * years }
        breach = count.positive?
        detail = "max_maturity #{years}Y positions #{count}"
      when 'min_yield'
        limit = arguments.first.to_i
        breach = risk[:ytm] * 10_000.0 < limit.to_f
        detail = "min_yield #{percent(risk[:ytm])} limit #{hundredths(limit)}"
      when 'duration'
        lower, upper = arguments.map(&:to_i)
        breach = risk[:modified] < lower.to_f / 100.0 || risk[:modified] > upper.to_f / 100.0
        detail = "duration #{decimal(risk[:modified], 4)} range #{hundredths(lower)} #{hundredths(upper)}"
      when 'dv01'
        limit = arguments.first.to_i
        breach = risk[:dv01] * 100.0 > limit.to_f
        detail = "dv01 #{decimal(risk[:dv01], 2)} limit #{hundredths(limit)}"
      end
      breaches += 1 if breach
      "#{name} #{detail} #{breach ? 'BREACH' : 'PASS'}"
    end
    lines << "#{name} breaches #{breaches}"
  end

  def cashflow_lines
    lines = ['bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal']
    @bonds.sort.each do |id, bond|
      bond[:periods].each do |period|
        next if period[:amount].zero?

        lines << [id, period[:number], BondDates.text(period[:start]), BondDates.text(period[:end]),
                  BondDates.text(period[:payment]), decimal(period[:numerator].to_f / period[:denominator].to_f, 6),
                  period[:rate], period[:opening], period[:coupon], period[:principal]].join(',')
      end
    end
    lines
  end

  def analytic_lines
    lines = ['bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread']
    @priced.sort.each do |id, asset|
      metrics = asset[:metrics]
      lines << [id, decimal(asset[:clean_price].to_f / 1000.0, 6), decimal(asset[:accrued], 6), decimal(asset[:target], 6),
                percent(metrics[:ytm]), percent(metrics[:ytw]), BondDates.text(metrics[:workout]), BondDates.text(metrics[:next_payment]),
                *%i[wal macaulay modified convexity].map { |key| decimal(metrics[key], 4) }, decimal(metrics[:dv01], 6),
                decimal(metrics[:curve_clean], 6), percent(metrics[:zspread])].join(',')
    end
    lines
  end

  def curve_lines
    lines = ["valuation #{BondDates.text(@valuation)} settlement #{BondDates.text(@settlement)}"]
    @pillars.each_with_index do |pillar, index|
      day = @curve.days[index]
      previous = index.zero? ? 0 : @curve.days[index - 1]
      lines << "pillar #{BondDates.text(pillar[:maturity])} days #{day} frequency #{pillar[:frequency]} par #{hundredths(pillar[:coupon])} " \
               "zero #{percent(@curve.rates[index])} df #{decimal(@curve.discount(day), 6)} forward #{percent(@curve.forward(previous, day))}"
    end
    1.upto(@curve.days.last / 365) do |year|
      day = 365 * year
      lines << "grid #{year}Y days #{day} zero #{percent(@curve.zero(day))} df #{decimal(@curve.discount(day), 6)} " \
               "forward #{percent(@curve.forward(day - 365, day))}"
    end
    lines
  end

  def scenario_lines(portfolios)
    lines = ['portfolio,scenario,bond,value,pnl']
    portfolios.each do |portfolio|
      portfolio[:scenarios].each do |scenario|
        portfolio[:positions].each_with_index do |position, index|
          lines << [portfolio[:name], scenario[:name], position[:id], amount(scenario[:values][index]), amount(scenario[:changes][index])].join(',')
        end
        lines << [portfolio[:name], scenario[:name], '*', amount(scenario[:total]), amount(scenario[:pnl])].join(',')
      end
    end
    lines
  end

  def run
    read_parameters
    validate_pillars
    validate_scenarios
    validate_bonds
    validate_prices
    validate_holdings
    portfolios = @positions.values.group_by { |position| position[:portfolio] }.sort.map do |name, positions|
      portfolio(name, positions.sort_by { |position| position[:id] })
    end
    files = { 'errors.txt' => @errors, 'cashflows.csv' => cashflow_lines, 'analytics.csv' => analytic_lines,
              'curve.txt' => curve_lines, 'portfolio.txt' => portfolios.flat_map { |entry| portfolio_lines(entry) },
              'scenarios.csv' => scenario_lines(portfolios), 'compliance.txt' => portfolios.flat_map { |entry| compliance(entry) } }
    Dir.mkdir('output') unless Dir.exist?('output')
    files.each { |name, lines| File.binwrite("output/#{name}", lines.empty? ? '' : lines.join("\n") + "\n") }
  end
end

PortfolioAnalysis.new.run
