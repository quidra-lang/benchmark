RATE_SETTINGS = %w[STATE SUPP SSRATE MEDRATE ADDMED UIRATE MATCH MATCHMAX GARNCAP].freeze
INITIAL = {
  'STATE' => 500, 'SUPP' => 2200, 'SSRATE' => 620, 'MEDRATE' => 145,
  'ADDMED' => 90, 'UIRATE' => 270, 'MATCH' => 5000, 'MATCHMAX' => 600,
  'GARNCAP' => 2500, 'SSBASE' => 16860000, 'ADDBASE' => 20000000,
  'UIBASE' => 700000, 'RETIRECAP' => 2300000, 'ALLOWANCE' => 15000, 'NIGHT' => 100
}.freeze
FIELDS = %i[R O D N P accrued salary leave deduction sales commission earnings bonus gross
            retirement health federal supplemental state social medicare garnishment net
            employer_social employer_medicare unemployment match employer W Y F J].freeze
WEEKDAYS = %w[Mon Tue Wed Thu Fri Sat Sun].freeze
class CommandError < StandardError; end

def cents(text)
  whole, fraction = text.split('.')
  whole.to_i * 100 + fraction.to_i
end

def money(value)
  format('%d.%02d', value / 100, value % 100)
end

def rate_text(value)
  money(value) + '%'
end

def duration(value)
  format('%d:%02d', value / 60, value % 60)
end

def clock(value)
  format('%02d:%02d', value / 60, value % 60)
end

def weekday(day)
  WEEKDAYS[(day - 1) % 7]
end

def period_of(day)
  (day - 1) / 14 + 1
end

def empty_totals
  FIELDS.to_h { |field| [field, 0] }
end

def sum_stubs(stubs)
  total = empty_totals
  stubs.each do |stub|
    FIELDS.each { |field| total[field] += stub[field] }
  end
  total
end

def progressive(table, amount)
  pairs = table.sort
  numerator = 0
  pairs.each_with_index do |(lower, rate), i|
    break if lower >= amount
    upper = i + 1 < pairs.length ? pairs[i + 1][0] : amount
    numerator += rate * ([amount, upper].min - lower)
  end
  numerator / 10000
end

class Employee
  attr_accessor :id, :department, :kind, :base, :active, :retirement, :health, :allowances,
                :extra, :garnishments, :bonus, :pto_balance, :shifts, :pto, :leave,
                :sales, :stubs, :ytd, :periods

  def initialize(id, department, kind, base)
    @id = id
    @department = department
    @kind = kind
    @base = base
    @active = true
    @retirement = 0
    @health = 0
    @allowances = 0
    @extra = 0
    @garnishments = []
    @bonus = 0
    @pto_balance = 0
    @shifts = {}
    @pto = {}
    @leave = {}
    @sales = {}
    @stubs = {}
    @ytd = empty_totals
    @periods = 0
  end

  def garnishment_balance
    @garnishments.sum { |_, balance| balance }
  end
end

class Payroll
  attr_reader :output

  def initialize
    @settings = INITIAL.dup
    @brackets = {}
    @tiers = {}
    @holidays = {}
    @employees = {}
    @closed = 0
    @output = []
  end

  def emit(indent, *parts)
    @output << ' ' * indent + parts.join(' ')
  end

  def employee(text, active = false, kind = nil)
    e = @employees[text.to_i]
    raise CommandError, "unknown employee #{text}" unless e
    raise CommandError, "terminated employee #{text}" if active && !e.active
    raise CommandError, "not #{kind.downcase} #{text}" if kind && e.kind != kind
    e
  end

  def day_check(text)
    day = text.to_i
    raise CommandError, "invalid day #{text}" unless (1..364).cover?(day)
    period = period_of(day)
    raise CommandError, "period closed #{period}" if period <= @closed
    day
  end

  def period_check(text)
    period = text.to_i
    raise CommandError, "invalid period #{text}" unless (1..26).cover?(period)
    period
  end

  def rate_check(text)
    value = cents(text)
    raise CommandError, "invalid rate #{text}" if value > 10000
    value
  end

  def amount_check(text)
    value = cents(text)
    raise CommandError, 'invalid amount' if value.zero?
    value
  end

  def time_check(text)
    hour, minute = text.split(':').map(&:to_i)
    raise CommandError, "invalid time #{text}" if hour > 23 || minute > 59
    hour * 60 + minute
  end

  def daily(e, day)
    shifts = e.shifts.fetch(day, [])
    worked = shifts.sum { |s, t| t - s }
    night = shifts.sum { |s, t| [0, [t, 360].min - s].max + [0, t - [s, 1320].max].max }
    pto = e.pto.fetch(day, 0)
    return [worked, 0, 0, worked, night, pto] if (day % 7).zero? || @holidays.key?(day)
    [worked, [worked, 480].min, [[worked - 480, 0].max, 240].min, [worked - 720, 0].max, night, pto]
  end

  def weekly(e, week)
    values = Array.new(5, 0)
    (7 * week - 6..7 * week).each do |day|
      daily = daily(e, day)
      5.times { |i| values[i] += daily[i + 1] }
    end
    overtime = [0, values[0] - 2400].max
    values[0] -= overtime
    values[1] += overtime
    [values, overtime]
  end

  def breakdown(e, period)
    a = weekly(e, 2 * period - 1)[0]
    b = weekly(e, 2 * period)[0]
    a.zip(b).map { |x, y| x + y }
  end

  def calculate(e, period)
    s = empty_totals
    c = @settings
    ytd = e.ytd
    if e.kind == 'HOURLY'
      values = breakdown(e, period)
      %i[R O D N P].zip(values).each { |field, value| s[field] = value }
      weighted = 2 * (s[:R] + s[:P]) + 3 * s[:O] + 4 * s[:D]
      s[:earnings] = (weighted * e.base + 2 * s[:N] * c['NIGHT']) / 120
    elsif e.kind == 'SALARIED'
      if e.active
        s[:salary] = e.base / 26
        s[:leave] = e.leave.keys.count { |day| period_of(day) == period && !@holidays.key?(day) }
        s[:deduction] = s[:leave] * (e.base / 260)
        s[:earnings] = s[:salary] - s[:deduction]
      end
    else
      s[:sales] = e.sales.fetch(period, 0)
      s[:commission] = progressive(@tiers, s[:sales])
      s[:earnings] = s[:commission] + (e.active ? e.base : 0)
    end
    s[:bonus] = e.bonus
    gross = s[:earnings] + s[:bonus]
    return nil if gross.zero?
    s[:gross] = gross
    remaining = gross
    deduct = lambda do |field, amount|
      s[field] = [amount, remaining].min
      remaining -= s[field]
    end
    retirement_room = [0, c['RETIRECAP'] - ytd[:retirement]].max
    deduct.call(:retirement, [gross * e.retirement / 10000, retirement_room].min)
    deduct.call(:health, e.health)
    s[:W] = remaining
    base_taxable = [0, s[:earnings] - s[:retirement] - s[:health]].max
    allowance_taxable = [0, base_taxable - e.allowances * c['ALLOWANCE']].max
    deduct.call(:federal, progressive(@brackets, allowance_taxable) + e.extra)
    deduct.call(:supplemental, (s[:W] - base_taxable) * c['SUPP'] / 10000)
    deduct.call(:state, s[:W] * c['STATE'] / 10000)
    s[:F] = gross - s[:health]
    s[:Y] = [s[:F], [0, c['SSBASE'] - ytd[:Y]].max].min
    additional = [0, [s[:F], ytd[:F] + s[:F] - c['ADDBASE']].min].max
    deduct.call(:social, s[:Y] * c['SSRATE'] / 10000)
    deduct.call(:medicare, s[:F] * c['MEDRATE'] / 10000 + additional * c['ADDMED'] / 10000)
    disposable = remaining
    cap = disposable * c['GARNCAP'] / 10000
    balances = []
    garnishment = 0
    e.garnishments.each do |rate, balance|
      taken = [disposable * rate / 10000, balance, cap - garnishment].min
      garnishment += taken
      balances << balance - taken
    end
    s[:garnishment] = garnishment
    s[:garnishment_balance] = balances.sum
    s[:net] = remaining - garnishment
    s[:employer_social] = s[:Y] * c['SSRATE'] / 10000
    s[:employer_medicare] = s[:F] * c['MEDRATE'] / 10000
    s[:J] = [s[:F], [0, c['UIBASE'] - ytd[:J]].max].min
    s[:unemployment] = s[:J] * c['UIRATE'] / 10000
    s[:match] = [s[:retirement], gross * c['MATCHMAX'] / 10000].min * c['MATCH'] / 10000
    s[:employer] = %i[employer_social employer_medicare unemployment match].sum { |field| s[field] }
    s[:accrued] = [960 - e.pto_balance, (s[:R] + s[:O] + s[:D]) / 20].min if e.kind == 'HOURLY'
    s[:pto_balance] = e.pto_balance + s[:accrued]
    [s, balances]
  end

  def hours_parts(values)
    %w[reg ot dbl night pto].zip(values).flat_map { |label, value| [label, duration(value)] }
  end

  def stub_block(e, s, indent)
    if e.kind == 'HOURLY'
      emit(indent, 'hours', *hours_parts(%i[R O D N P].map { |field| s[field] }))
      emit(indent, 'pto', 'accrued', duration(s[:accrued]), 'balance', duration(s[:pto_balance]))
    elsif e.kind == 'SALARIED'
      emit(indent, 'salary', money(s[:salary]), 'leave', s[:leave], 'deduction', money(s[:deduction]))
    else
      emit(indent, 'sales', money(s[:sales]), 'commission', money(s[:commission]))
    end
    %i[earnings bonus gross retirement health federal supplemental state social medicare].each do |field|
      emit(indent, field == :social ? 'social-security' : field, money(s[field]))
    end
    emit(indent, 'garnishment', money(s[:garnishment]), 'balance', money(s[:garnishment_balance]))
    emit(indent, 'net', money(s[:net]))
    emit(indent, 'employer', 'social-security', money(s[:employer_social]), 'medicare', money(s[:employer_medicare]),
         'unemployment', money(s[:unemployment]), 'match', money(s[:match]))
  end

  def print_stub(e, period, s, department)
    emit(2, 'STUB', e.id, department, e.kind, 'period', period)
    stub_block(e, s, 4)
  end

  def show_hours(e, period)
    emit(0, 'HOURS', e.id, 'period', period)
    found = false
    (14 * period - 13..14 * period).each do |day|
      shifts = e.shifts.fetch(day, []).sort
      next if shifts.empty? && !e.pto.key?(day)
      worked, *values = daily(e, day)
      parts = ['day', day, weekday(day)]
      parts << 'holiday' if @holidays.key?(day)
      parts.concat(shifts.map { |s, t| "#{clock(s)}-#{clock(t)}" })
      emit(2, *parts, 'total', duration(worked), *hours_parts(values))
      found = true
    end
    emit(2, '(none)') unless found
    [2 * period - 1, 2 * period].each do |week|
      values, overtime = weekly(e, week)
      emit(2, 'week', week, *hours_parts(values), 'weekly-ot', duration(overtime))
    end
    emit(2, 'total', *hours_parts(breakdown(e, period)))
  end

  def run(period)
    @closed = period
    emit(0, 'RUN', period, 'days', "#{14 * period - 13}-#{14 * period}")
    paid = 0
    skipped = 0
    stubs = []
    @employees.values.sort_by(&:id).each do |e|
      calculated = calculate(e, period)
      if calculated.nil?
        skipped += 1 if e.active
        next
      end
      s, balances = calculated
      print_stub(e, period, s, e.department)
      e.bonus = 0
      e.pto_balance = s[:pto_balance]
      balances.each_with_index { |balance, i| e.garnishments[i][1] = balance }
      FIELDS.each { |field| e.ytd[field] += s[field] }
      e.periods += 1
      e.stubs[period] = [s, e.department]
      stubs << s
      paid += 1
    end
    t = sum_stubs(stubs)
    emit(2, 'TOTAL', 'paid', paid, 'skipped', skipped, 'gross', money(t[:gross]),
         'deductions', money(t[:gross] - t[:net]), 'net', money(t[:net]), 'employer', money(t[:employer]))
  end

  def journal(period)
    stubs = @employees.values.filter_map { |e| e.stubs[period]&.first }
    t = sum_stubs(stubs)
    rows = [
      ['debit', 'wages', t[:gross]],
      ['debit', 'employer-tax', t[:employer_social] + t[:employer_medicare] + t[:unemployment]],
      ['debit', 'retirement-match', t[:match]],
      ['credit', 'retirement', t[:retirement] + t[:match]],
      ['credit', 'health', t[:health]],
      ['credit', 'federal', t[:federal] + t[:supplemental]],
      ['credit', 'state', t[:state]],
      ['credit', 'fica', t[:social] + t[:medicare] + t[:employer_social] + t[:employer_medicare]],
      ['credit', 'unemployment', t[:unemployment]],
      ['credit', 'garnishment', t[:garnishment]],
      ['credit', 'net-pay', t[:net]]
    ]
    emit(0, 'JOURNAL', period, 'stubs', stubs.length)
    rows.each { |side, label, amount| emit(2, side, label, money(amount)) }
    debit = rows.select { |side, _, _| side == 'debit' }.sum(&:last)
    credit = rows.select { |side, _, _| side == 'credit' }.sum(&:last)
    emit(2, 'total', 'debit', money(debit), 'credit', money(credit))
  end

  def report_line(department, stubs)
    t = sum_stubs(stubs)
    taxes = %i[federal supplemental state social medicare].sum { |field| t[field] }
    emit(2, department, 'stubs', stubs.length, 'gross', money(t[:gross]), 'pretax', money(t[:retirement] + t[:health]),
         'taxes', money(taxes), 'garnishment', money(t[:garnishment]), 'net', money(t[:net]), 'employer', money(t[:employer]))
  end

  def command(cmd, a)
    case cmd
    when 'SET'
      name = a[0]
      raise CommandError, "unknown setting #{name}" unless @settings.key?(name)
      value = RATE_SETTINGS.include?(name) ? rate_check(a[1]) : cents(a[1])
      old = @settings[name]
      @settings[name] = value
      emit(0, 'SET', name, RATE_SETTINGS.include?(name) ? rate_text(old) : money(old),
           '->', RATE_SETTINGS.include?(name) ? rate_text(value) : money(value))
    when 'BRACKET', 'TIER'
      rate = rate_check(a[1])
      table = cmd == 'BRACKET' ? @brackets : @tiers
      lower = cents(a[0])
      action = table.key?(lower) ? 'replaced' : 'added'
      table[lower] = rate
      emit(0, cmd, money(lower), rate_text(rate), action)
    when 'EMP'
      id = a[0].to_i
      raise CommandError, "duplicate employee #{a[0]}" if @employees.key?(id)
      base = amount_check(a[3])
      @employees[id] = Employee.new(id, a[1], a[2], base)
      emit(0, 'EMP', id, a[1], a[2], money(base))
    when 'RATE', 'DEPT', 'BENEFIT', 'W4', 'GARNISH', 'TERM', 'BONUS'
      e = employee(a[0], true)
      case cmd
      when 'RATE'
        base = amount_check(a[1])
        old = e.base
        e.base = base
        emit(0, 'RATE', e.id, money(old), '->', money(base))
      when 'DEPT'
        raise CommandError, "same department #{a[1]}" if a[1] == e.department
        old = e.department
        e.department = a[1]
        emit(0, 'DEPT', e.id, old, '->', a[1])
      when 'BENEFIT'
        rate = rate_check(a[1])
        e.retirement = rate
        e.health = cents(a[2])
        emit(0, 'BENEFIT', e.id, 'retirement', rate_text(rate), 'health', money(e.health))
      when 'W4'
        e.allowances = a[1].to_i
        e.extra = cents(a[2])
        emit(0, 'W4', e.id, 'allowances', e.allowances, 'extra', money(e.extra))
      when 'GARNISH'
        rate = rate_check(a[1])
        amount = amount_check(a[2])
        e.garnishments << [rate, amount]
        emit(0, 'GARNISH', e.id, 'order', e.garnishments.length, rate_text(rate), 'balance', money(amount))
      when 'TERM'
        e.active = false
        emit(0, 'TERM', e.id)
      when 'BONUS'
        amount = amount_check(a[1])
        e.bonus += amount
        emit(0, 'BONUS', e.id, money(amount), 'pending', money(e.bonus))
      end
    when 'HOLIDAY'
      day = day_check(a[0])
      raise CommandError, "duplicate holiday #{a[0]}" if @holidays.key?(day)
      @holidays[day] = true
      emit(0, 'HOLIDAY', day, weekday(day))
    when 'TIME', 'UNTIME', 'PTO', 'LEAVE', 'SALES'
      kind = cmd == 'LEAVE' ? 'SALARIED' : cmd == 'SALES' ? 'COMMISSION' : 'HOURLY'
      e = employee(a[0], true, kind)
      day = day_check(a[1])
      case cmd
      when 'TIME'
        start = time_check(a[2])
        finish = time_check(a[3])
        raise CommandError, "invalid shift #{a[2]}-#{a[3]}" if start >= finish
        shifts = e.shifts.fetch(day, []).sort
        shifts.each do |s, t|
          raise CommandError, "overlapping shift #{clock(s)}-#{clock(t)}" if start < t && s < finish
        end
        raise CommandError, "daily limit #{a[0]} #{a[1]}" if shifts.sum { |s, t| t - s } + finish - start > 960
        (e.shifts[day] ||= []) << [start, finish]
        emit(0, 'TIME', e.id, 'day', day, "#{clock(start)}-#{clock(finish)}", duration(finish - start))
      when 'UNTIME'
        start = time_check(a[2])
        shifts = e.shifts.fetch(day, [])
        index = shifts.index { |s, _| s == start }
        raise CommandError, "no shift #{a[0]} #{a[1]} #{a[2]}" unless index
        shift = shifts.delete_at(index)
        emit(0, 'UNTIME', e.id, 'day', day, "#{clock(shift[0])}-#{clock(shift[1])}")
      when 'PTO'
        hour, minute = a[2].split(':').map(&:to_i)
        length = hour * 60 + minute
        raise CommandError, "invalid duration #{a[2]}" if minute > 59 || !(1..480).cover?(length)
        raise CommandError, "duplicate pto #{a[0]} #{a[1]}" if e.pto.key?(day)
        raise CommandError, "insufficient pto #{a[0]} #{duration(e.pto_balance)}" if length > e.pto_balance
        e.pto[day] = length
        e.pto_balance -= length
        emit(0, 'PTO', e.id, 'day', day, duration(length), 'balance', duration(e.pto_balance))
      when 'LEAVE'
        raise CommandError, "not workday #{a[1]}" if [0, 6].include?(day % 7) || @holidays.key?(day)
        raise CommandError, "duplicate leave #{a[0]} #{a[1]}" if e.leave.key?(day)
        e.leave[day] = true
        emit(0, 'LEAVE', e.id, 'day', day, weekday(day))
      when 'SALES'
        amount = amount_check(a[2])
        period = period_of(day)
        e.sales[period] = e.sales.fetch(period, 0) + amount
        emit(0, 'SALES', e.id, 'day', day, money(amount), 'period', period, 'total', money(e.sales[period]))
      end
    when 'HOURS'
      e = employee(a[0], false, 'HOURLY')
      show_hours(e, period_check(a[1]))
    when 'RUN'
      period = a[0].to_i
      raise CommandError, "invalid period #{a[0]}" if period != @closed + 1 || period > 26
      run(period)
    when 'PREVIEW'
      e = employee(a[0])
      period = @closed + 1
      calculated = calculate(e, period)
      emit(0, 'PREVIEW', e.id, 'period', period)
      calculated ? print_stub(e, period, calculated[0], e.department) : emit(2, 'no pay')
    when 'REPRINT'
      e = employee(a[0])
      period = period_check(a[1])
      saved = e.stubs[period]
      raise CommandError, "no stub #{a[0]} #{a[1]}" unless saved
      emit(0, 'REPRINT', e.id, period)
      print_stub(e, period, saved[0], saved[1])
    when 'YTD'
      e = employee(a[0])
      emit(0, 'YTD', e.id, e.department, e.kind, e.active ? 'active' : 'terminated', 'periods', e.periods)
      s = e.ytd.merge(pto_balance: e.pto_balance, garnishment_balance: e.garnishment_balance)
      stub_block(e, s, 2)
      emit(2, 'wages', 'federal', money(s[:W]), 'social-security', money(s[:Y]),
           'medicare', money(s[:F]), 'unemployment', money(s[:J]))
      emit(2, 'retirement-room', money([0, @settings['RETIRECAP'] - s[:retirement]].max), 'pending-bonus', money(e.bonus))
    when 'JOURNAL'
      period = a[0].to_i
      raise CommandError, "no run #{a[0]}" unless (1..@closed).cover?(period)
      journal(period)
    when 'REPORT'
      departments = {}
      all = []
      @employees.each_value do |e|
        e.stubs.each_value do |s, department|
          (departments[department] ||= []) << s
          all << s
        end
      end
      emit(0, 'REPORT', 'period', @closed)
      departments.keys.sort.each { |department| report_line(department, departments[department]) }
      report_line('total', all)
    when 'TOP'
      k = a[0].to_i
      employees = @employees.values.select { |e| e.periods.positive? }.sort_by { |e| [-e.ytd[:gross], e.id] }
      emit(0, 'TOP', k)
      employees.first(k).each_with_index do |e, i|
        emit(2, i + 1, e.id, e.department, 'gross', money(e.ytd[:gross]), 'net', money(e.ytd[:net]))
      end
      emit(2, '(none)') if employees.empty?
    when 'EMPLOYEES'
      emit(0, 'EMPLOYEES')
      @employees.values.sort_by(&:id).each do |e|
        emit(2, e.id, e.department, e.kind, money(e.base), e.active ? 'active' : 'terminated',
             'retirement', rate_text(e.retirement), 'health', money(e.health), 'allowances', e.allowances,
             'extra', money(e.extra), 'bonus', money(e.bonus))
        e.garnishments.each_with_index do |(rate, balance), i|
          emit(4, 'garnish', i + 1, rate_text(rate), 'balance', money(balance))
        end
      end
      emit(2, '(none)') if @employees.empty?
    when 'CONFIG'
      emit(0, 'CONFIG')
      @settings.each { |name, value| emit(2, name, RATE_SETTINGS.include?(name) ? rate_text(value) : money(value)) }
      [['bracket', @brackets], ['tier', @tiers]].each do |label, table|
        table.sort.each { |lower, rate| emit(2, label, money(lower), rate_text(rate)) }
      end
    end
  end

  def execute(line)
    cmd, *args = line.split
    begin
      command(cmd, args)
    rescue CommandError => error
      emit(0, 'ERROR', error.message)
    end
  end
end

payroll = Payroll.new
STDIN.gets.to_i.times { payroll.execute(STDIN.gets.chomp) }
STDOUT.write(payroll.output.join("\n") + "\n")
