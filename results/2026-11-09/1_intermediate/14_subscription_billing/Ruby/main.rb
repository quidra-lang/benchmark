LENGTH = {'WEEKLY' => 7, 'MONTHLY' => 30, 'YEARLY' => 360}.freeze
Plan = Struct.new(:name, :price, :cycle, :length, :trial, :setup, :per_seat, :mode, :tiers)
Customer = Struct.new(:name, :region, :method, :balance, :log)
Coupon = Struct.new(:name, :kind, :value, :applications, :maximum, :redeemed)
Subscription = Struct.new(:id, :customer, :plan, :seats, :state, :start, :finish, :trial_end,
                          :pause_start, :pending, :cancel_end, :cancel_on, :canceled_on,
                          :coupon, :left, :usage)
class CommandError < StandardError; end

def cents(text)
  text.delete('.').to_i
end

def money(value)
  (value.negative? ? '-' : '') + format('%d.%02d', value.abs / 100, value.abs % 100)
end

def percent(value)
  money(value) + '%'
end

def fee(plan, seats)
  plan.price * (plan.per_seat ? seats : 1)
end

def period(s)
  "#{s.start}-#{s.finish}"
end

class Billing
  attr_reader :output

  def initialize
    @day = 1
    @plans = {}
    @taxes = {}
    @customers = {}
    @coupons = {}
    @subs = []
    @invoices = []
    @events = []
    @output = []
  end

  def emit(indent, *parts)
    @output << ' ' * indent + parts.join(' ')
  end

  def plan(name)
    raise CommandError, "unknown plan #{name}" unless @plans.key?(name)
    @plans[name]
  end

  def customer(name)
    raise CommandError, "unknown customer #{name}" unless @customers.key?(name)
    @customers[name]
  end

  def coupon(name)
    c = @coupons[name]
    raise CommandError, "unknown coupon #{name}" unless c
    raise CommandError, "coupon exhausted #{name}" if c.maximum && c.redeemed == c.maximum
    c
  end

  def sub(text)
    id = text.to_i
    raise CommandError, "unknown sub #{text}" unless (1..@subs.length).cover?(id)
    @subs[id - 1]
  end

  def invoice(text)
    id = text.to_i
    raise CommandError, "unknown invoice #{text}" unless (1..@invoices.length).cover?(id)
    @invoices[id - 1]
  end

  def state(s, allowed)
    raise CommandError, "invalid state #{s.id} #{s.state}" unless allowed.include?(s.state)
  end

  def balance(c, description, change)
    return if change.zero?
    c.balance += change
    c.log << [@day, description, change, c.balance]
  end

  def sub_invoices(s)
    @invoices.select { |i| i[:sub].equal?(s) }
  end

  def change_state(s, target)
    from = s.state
    emit(2, 'day', @day, 'sub', s.id, from, '->', target)
    @events << [@day, s.id, from, target]
    sub_invoices(s).each { |i| i[:retries] = [] } if from == 'PAST_DUE'
    s.state = target
  end

  def usage_item(s, close = false)
    return [] if s.plan.mode.nil? || s.usage.zero?
    p = s.plan
    units = s.usage
    charge = 0
    lower = 0
    p.tiers.each_with_index do |(limit, unit, flat), k|
      last = k == p.tiers.length - 1
      if p.mode == 'VOLUME'
        if last || limit.nil? || limit >= units
          charge = units * unit + flat
          break
        end
      elsif lower < units
        upper = last || limit.nil? ? units : [units, limit].min
        charge += (upper - lower) * unit + flat
      end
      lower = limit unless limit.nil?
    end
    s.usage = 0 if close
    [["usage #{p.name} #{units} units", charge]]
  end

  def charge_item(p, seats, start)
    ["charge #{p.name} seats #{seats} #{start}-#{start + p.length}", fee(p, seats)]
  end

  def opening(s, start)
    items = [charge_item(s.plan, s.seats, start)]
    items << ["setup #{s.plan.name}", s.plan.setup] if s.plan.setup.positive?
    items
  end

  def quote(s, items)
    subtotal = items.sum(&:last)
    discount = 0
    if s.coupon && (s.left.nil? || s.left.positive?) && subtotal.positive?
      discount = s.coupon.kind == 'PERCENT' ? subtotal * s.coupon.value / 10000 : [s.coupon.value, subtotal].min
    end
    tax = (subtotal - discount) * @taxes.fetch(s.customer.region, 0) / 10000
    total = subtotal - discount + tax
    credit = [s.customer.balance, total].min
    {subtotal: subtotal, discount: discount, tax: tax, total: total, credit: credit, due: total - credit}
  end

  def issue(s, kind, items)
    q = quote(s, items)
    if s.coupon && (s.left.nil? || s.left.positive?) && q[:subtotal].positive? && !s.left.nil?
      s.left -= 1
    end
    i = q.merge(id: @invoices.length + 1, sub: s, day: @day, kind: kind, items: items,
                paid: 0, refunded: 0, outstanding: q[:due], attempts: 0, retries: [])
    @invoices << i
    balance(s.customer, "applied invoice #{i[:id]}", -q[:credit])
    result = 'PAID'
    if q[:due].positive?
      if s.state == 'UNPAID'
        result = 'OPEN'
      else
        i[:attempts] = 1
        if s.customer.method == 'OK'
          i[:paid] = q[:due]
          i[:outstanding] = 0
        else
          result = 'FAILED'
        end
      end
    end
    emit(2, 'day', @day, 'invoice', i[:id], 'sub', s.id, kind,
         'total', money(q[:total]), 'credit', money(q[:credit]), 'due', money(q[:due]), result)
    if result == 'FAILED'
      change_state(s, 'PAST_DUE') if s.state == 'ACTIVE'
      i[:retries] = [@day + 3, @day + 5, @day + 7] if s.state == 'PAST_DUE'
    end
  end

  def complete(i)
    i[:retries] = []
    s = i[:sub]
    if %w[PAST_DUE UNPAID].include?(s.state) && sub_invoices(s).all? { |i| i[:outstanding].zero? }
      s.cancel_on = nil
      change_state(s, 'ACTIVE')
    end
  end

  def cancel(s)
    change_state(s, 'CANCELED')
    s.canceled_on = @day
    s.pending = nil
    s.cancel_end = false
    s.cancel_on = nil
    items = usage_item(s, true)
    issue(s, 'final', items) unless items.empty?
  end

  def advance(target)
    while @day < target
      @day += 1
      @subs.each do |s|
        next if %w[PAUSED CANCELED].include?(s.state)
        sub_invoices(s).each do |i|
          next if i[:retries].first != @day
          i[:retries].shift
          i[:attempts] += 1
          if s.customer.method == 'OK'
            i[:paid] += i[:outstanding]
            i[:outstanding] = 0
            emit(2, 'day', @day, 'retry', i[:attempts] - 1, 'invoice', i[:id], 'PAID')
            complete(i)
          else
            emit(2, 'day', @day, 'retry', i[:attempts] - 1, 'invoice', i[:id], 'FAILED')
            if i[:retries].empty?
              change_state(s, 'UNPAID')
              s.cancel_on = @day + 14
            end
          end
        end
        cancel(s) if s.state == 'UNPAID' && s.cancel_on == @day
        if s.state == 'TRIALING' && s.trial_end == @day
          if s.cancel_end
            cancel(s)
          else
            change_state(s, 'ACTIVE')
            s.start = @day
            s.finish = @day + s.plan.length
            issue(s, 'first', opening(s, @day))
          end
        end
        if %w[ACTIVE PAST_DUE UNPAID].include?(s.state) && s.finish == @day
          if s.cancel_end
            cancel(s)
          else
            items = usage_item(s, true)
            if s.pending
              p, seats = s.pending
              emit(2, 'day', @day, 'sub', s.id, s.plan.name, 'seats', s.seats, '->', p.name, 'seats', seats)
              s.plan = p
              s.seats = seats
              s.pending = nil
            end
            s.start = @day
            s.finish = @day + s.plan.length
            items << charge_item(s.plan, s.seats, @day)
            issue(s, 'renewal', items)
          end
        end
      end
    end
  end

  def totals(q)
    emit(2, 'subtotal', money(q[:subtotal]), 'discount', money(q[:discount]), 'tax', money(q[:tax]), 'total', money(q[:total]))
  end

  def show_sub(s)
    emit(0, 'SUB', s.id, s.customer.name, s.plan.name, 'seats', s.seats, s.state)
    emit(2, 'trial', 'until', s.trial_end) if s.state == 'TRIALING'
    emit(2, 'period', period(s)) if %w[ACTIVE PAST_DUE UNPAID PAUSED].include?(s.state)
    emit(2, 'paused', 'since', s.pause_start) if s.state == 'PAUSED'
    emit(2, 'pending', s.pending[0].name, 'seats', s.pending[1]) if s.pending
    emit(2, 'cancel', 'at', 'end') if s.cancel_end
    emit(2, 'cancel', 'on', s.cancel_on) if s.cancel_on
    emit(2, 'canceled', 'on', s.canceled_on) if s.state == 'CANCELED'
    if s.coupon && (s.left.nil? || s.left.positive?)
      emit(2, 'coupon', s.coupon.name, *(s.left.nil? ? ['forever'] : ['left', s.left]))
    end
    emit(2, 'usage', s.usage) if s.plan.mode && s.state != 'CANCELED'
    open = sub_invoices(s).select { |i| i[:outstanding].positive? }
    emit(2, 'open', *open.map { |i| i[:id] }) unless open.empty?
  end

  def preview(s)
    state(s, %w[TRIALING ACTIVE PAST_DUE UNPAID])
    day = s.state == 'TRIALING' ? s.trial_end : s.finish
    if s.cancel_end
      kind = 'final'
      items = s.state == 'TRIALING' ? [] : usage_item(s)
    elsif s.state == 'TRIALING'
      kind = 'first'
      items = opening(s, day)
    else
      kind = 'renewal'
      items = usage_item(s)
      p, seats = s.pending || [s.plan, s.seats]
      items << charge_item(p, seats, day)
    end
    emit(0, 'PREVIEW', 'sub', s.id, 'day', day, kind)
    items.each { |description, amount| emit(2, description, money(amount)) }
    if items.empty?
      emit(2, '(none)')
    else
      q = quote(s, items)
      totals(q)
      emit(2, 'credit', money(q[:credit]), 'due', money(q[:due]))
    end
  end

  def aging_line(label, row)
    emit(2, label, '0-30', money(row[0]), '31-60', money(row[1]), '61+', money(row[2]), 'sum', money(row.sum))
  end

  def command(cmd, a)
    case cmd
    when 'PLAN'
      raise CommandError, "duplicate plan #{a[0]}" if @plans.key?(a[0])
      p = Plan.new(a[0], cents(a[1]), a[2], LENGTH[a[2]], 0, 0, false, nil, [])
      i = 3
      while i < a.length
        case a[i]
        when 'TRIAL'
          i += 1
          p.trial = a[i].to_i
        when 'SETUP'
          i += 1
          p.setup = cents(a[i])
        when 'PERSEAT'
          p.per_seat = true
        else
          p.mode = a[i]
        end
        i += 1
      end
      @plans[p.name] = p
      parts = ['PLAN', p.name, p.cycle, money(p.price)]
      parts.push('trial', p.trial) if p.trial.positive?
      parts.push('setup', money(p.setup)) if p.setup.positive?
      parts << 'perseat' if p.per_seat
      parts << p.mode.downcase if p.mode
      emit(0, *parts)
    when 'TIER'
      p = plan(a[0])
      raise CommandError, "not metered #{a[0]}" if p.mode.nil?
      limit = a[1] == 'INF' ? nil : a[1].to_i
      last = p.tiers.last
      raise CommandError, "tier order #{a[0]}" if last && (last[0].nil? || (!limit.nil? && limit <= last[0]))
      p.tiers << [limit, cents(a[2]), cents(a[3])]
      emit(0, 'TIER', p.name, p.tiers.length, 'upto', a[1], 'unit', money(cents(a[2])), 'flat', money(cents(a[3])))
    when 'TAX'
      @taxes[a[0]] = a[1].to_i
      emit(0, 'TAX', a[0], percent(a[1].to_i))
    when 'CUSTOMER'
      raise CommandError, "duplicate customer #{a[0]}" if @customers.key?(a[0])
      @customers[a[0]] = Customer.new(a[0], a[1], 'OK', 0, [])
      emit(0, 'CUSTOMER', a[0], 'region', a[1])
    when 'COUPON'
      raise CommandError, "duplicate coupon #{a[0]}" if @coupons.key?(a[0])
      applications = a[3] == 'FOREVER' ? nil : a[3] == 'ONCE' ? 1 : a[4].to_i
      max_index = a.index('MAX')
      maximum = max_index ? a[max_index + 1].to_i : nil
      value = a[1] == 'PERCENT' ? a[2].to_i : cents(a[2])
      @coupons[a[0]] = Coupon.new(a[0], a[1], value, applications, maximum, 0)
      parts = ['COUPON', a[0], a[1].downcase, a[1] == 'PERCENT' ? percent(value) : money(value), a[3].downcase]
      parts << applications if a[3] == 'REPEATING'
      parts.push('max', maximum) if maximum
      emit(0, *parts)
    when 'PAYMETHOD'
      c = customer(a[0])
      c.method = a[1]
      emit(0, 'PAYMETHOD', c.name, c.method)
    when 'CREDIT'
      c = customer(a[0])
      amount = cents(a[1])
      raise CommandError, 'invalid amount' if amount.zero?
      balance(c, 'grant', amount)
      emit(0, 'CREDIT', c.name, 'amount', money(amount), 'balance', money(c.balance))
    when 'DAY'
      day = a[0].to_i
      raise CommandError, "invalid day #{a[0]}" if day <= @day
      emit(0, 'DAY', day)
      advance(day)
    when 'SUBSCRIBE'
      c = customer(a[0])
      p = plan(a[1])
      seat_index = a.index('SEATS')
      raise CommandError, "not per-seat #{p.name}" if seat_index && !p.per_seat
      seats = seat_index ? a[seat_index + 1].to_i : 1
      raise CommandError, 'invalid seats' if seats.zero?
      coupon_index = a.index('COUPON')
      discount = coupon_index ? coupon(a[coupon_index + 1]) : nil
      discount.redeemed += 1 if discount
      s = Subscription.new(@subs.length + 1, c, p, seats, 'NONE', 0, 0, nil,
                           nil, nil, false, nil, nil, discount, discount&.applications, 0)
      @subs << s
      emit(0, 'SUBSCRIBE', 'sub', s.id, c.name, p.name, 'seats', seats, *(discount ? ['coupon', discount.name] : []))
      if p.trial.positive?
        s.trial_end = @day + p.trial
        change_state(s, 'TRIALING')
      else
        change_state(s, 'ACTIVE')
        s.start = @day
        s.finish = @day + p.length
        issue(s, 'first', opening(s, @day))
      end
    when 'CHANGE'
      s = sub(a[0])
      state(s, %w[ACTIVE TRIALING])
      p = s.plan
      seats = s.seats
      if a[1] == 'PLAN'
        p = plan(a[2])
        seats = 1 unless p.per_seat
      else
        raise CommandError, "not per-seat #{p.name}" unless p.per_seat
        seats = a[2].to_i
        raise CommandError, 'invalid seats' if seats.zero?
      end
      raise CommandError, "no change #{s.id}" if p.equal?(s.plan) && seats == s.seats
      s.pending = nil
      old = s.plan
      old_seats = s.seats
      old_fee = fee(old, old_seats)
      new_fee = fee(p, seats)
      head = ['CHANGE', 'sub', s.id, old.name, 'seats', old_seats, '->', p.name, 'seats', seats]
      if s.state == 'TRIALING'
        s.plan = p
        s.seats = seats
        emit(0, *head, 'now')
      elsif new_fee * old.length > old_fee * p.length
        emit(0, *head, 'now')
        days = s.finish - @day
        items = usage_item(s, true)
        items << ["unused #{old.name} seats #{old_seats} #{days} days", -(old_fee * days / old.length)]
        items << ["remaining #{p.name} seats #{seats} #{days} days", new_fee * days / p.length]
        s.plan = p
        s.seats = seats
        issue(s, 'upgrade', items)
      else
        s.pending = [p, seats]
        emit(0, *head, 'at', s.finish)
      end
    when 'PAUSE'
      s = sub(a[0])
      state(s, ['ACTIVE'])
      emit(0, 'PAUSE', 'sub', s.id)
      s.pause_start = @day
      change_state(s, 'PAUSED')
    when 'RESUME'
      s = sub(a[0])
      state(s, ['PAUSED'])
      shift = @day - s.pause_start
      s.finish += shift
      emit(0, 'RESUME', 'sub', s.id, 'shift', shift, 'period', period(s))
      s.pause_start = nil
      change_state(s, 'ACTIVE')
    when 'CANCEL'
      s = sub(a[0])
      if a[1] == 'NOW'
        state(s, %w[TRIALING ACTIVE PAST_DUE UNPAID PAUSED])
        remaining = s.state == 'ACTIVE' ? s.finish - @day : s.state == 'PAUSED' ? s.finish - s.pause_start : 0
        refund = fee(s.plan, s.seats) * remaining / s.plan.length
        balance(s.customer, "cancel sub #{s.id}", refund)
        emit(0, 'CANCEL', 'sub', s.id, 'now', 'credit', money(refund))
        cancel(s)
      else
        state(s, %w[ACTIVE TRIALING])
        raise CommandError, "already canceling #{s.id}" if s.cancel_end
        s.cancel_end = true
        emit(0, 'CANCEL', 'sub', s.id, 'end', s.state == 'TRIALING' ? s.trial_end : s.finish)
      end
    when 'USAGE'
      s = sub(a[0])
      state(s, %w[ACTIVE PAST_DUE])
      raise CommandError, "not metered #{s.plan.name}" unless s.plan.mode
      units = a[1].to_i
      raise CommandError, 'invalid units' if units.zero?
      s.usage += units
      emit(0, 'USAGE', 'sub', s.id, 'units', units, 'total', s.usage)
    when 'APPLY'
      s = sub(a[0])
      state(s, %w[TRIALING ACTIVE PAST_DUE UNPAID PAUSED])
      discount = coupon(a[1])
      discount.redeemed += 1
      s.coupon = discount
      s.left = discount.applications
      emit(0, 'APPLY', 'sub', s.id, 'coupon', discount.name)
    when 'PAY'
      i = invoice(a[0])
      raise CommandError, "already paid #{a[0]}" if i[:outstanding].zero?
      emit(0, 'PAY', 'invoice', i[:id], 'amount', money(i[:outstanding]))
      i[:paid] += i[:outstanding]
      i[:outstanding] = 0
      complete(i)
    when 'REFUND'
      i = invoice(a[0])
      amount = cents(a[1])
      raise CommandError, 'invalid amount' if amount.zero?
      raise CommandError, "refund exceeds #{a[0]} #{money(i[:total] - i[:refunded])}" if amount > i[:total] - i[:refunded]
      applied = [amount, i[:outstanding]].min
      i[:refunded] += amount
      i[:outstanding] -= applied
      balance(i[:sub].customer, "refund invoice #{i[:id]}", amount - applied)
      emit(0, 'REFUND', 'invoice', i[:id], 'amount', money(amount), 'applied', money(applied), 'balance', money(i[:sub].customer.balance))
      complete(i) if applied.positive? && i[:outstanding].zero?
    when 'INVOICE'
      i = invoice(a[0])
      emit(0, 'INVOICE', i[:id], 'sub', i[:sub].id, i[:sub].customer.name, 'day', i[:day], i[:kind], i[:outstanding].positive? ? 'OPEN' : 'PAID')
      i[:items].each { |description, amount| emit(2, description, money(amount)) }
      totals(i)
      emit(2, 'credit', money(i[:credit]), 'due', money(i[:due]), 'paid', money(i[:paid]),
           'refunded', money(i[:refunded]), 'outstanding', money(i[:outstanding]))
    when 'SUB'
      show_sub(sub(a[0]))
    when 'PREVIEW'
      preview(sub(a[0]))
    when 'STATEMENT', 'LEDGER'
      c = customer(a[0])
      if cmd == 'LEDGER'
        emit(0, 'LEDGER', c.name, 'balance', money(c.balance))
        c.log.each do |day, description, change, after|
          emit(2, 'day', day, description, (change.positive? ? '+' : '') + money(change), 'balance', money(after))
        end
        emit(2, '(none)') if c.log.empty?
      else
        emit(0, 'STATEMENT', c.name, 'region', c.region, 'tax', percent(@taxes.fetch(c.region, 0)), 'method', c.method, 'balance', money(c.balance))
        @subs.select { |s| s.customer.equal?(c) }.each { |s| emit(2, 'sub', s.id, s.plan.name, s.state) }
        invoices = @invoices.select { |i| i[:sub].customer.equal?(c) }
        invoices.each do |i|
          emit(2, 'invoice', i[:id], 'day', i[:day], 'sub', i[:sub].id, i[:kind], 'total', money(i[:total]), 'outstanding', money(i[:outstanding]))
        end
        emit(2, 'outstanding', money(invoices.sum { |i| i[:outstanding] }))
      end
    when 'MRR'
      active = @subs.select { |s| %w[ACTIVE PAST_DUE].include?(s.state) }
      rows = active.group_by { |s| s.plan.name }.transform_values do |subs|
        monthly = subs.sum do |s|
          amount = fee(s.plan, s.seats)
          s.plan.cycle == 'MONTHLY' ? amount : s.plan.cycle == 'YEARLY' ? amount / 12 : amount * 30 / 7
        end
        [subs.length, monthly]
      end
      emit(0, 'MRR')
      rows.keys.sort.each { |name| emit(2, name, 'subs', rows[name][0], 'mrr', money(rows[name][1])) }
      emit(2, 'total', 'subs', rows.values.sum(&:first), 'mrr', money(rows.values.sum(&:last)))
    when 'AGING'
      rows = {}
      total = [0, 0, 0]
      @invoices.each do |i|
        next if i[:outstanding].zero?
        row = (rows[i[:sub].customer.name] ||= [0, 0, 0])
        age = @day - i[:day]
        bucket = age <= 30 ? 0 : age <= 60 ? 1 : 2
        row[bucket] += i[:outstanding]
        total[bucket] += i[:outstanding]
      end
      emit(0, 'AGING', 'day', @day)
      rows.keys.sort.each { |name| aging_line(name, rows[name]) }
      aging_line('total', total)
    when 'DUNNING'
      emit(0, 'DUNNING')
      invoices = @invoices.reject { |i| i[:retries].empty? }
      invoices.each do |i|
        emit(2, 'invoice', i[:id], 'sub', i[:sub].id, i[:sub].customer.name,
             'outstanding', money(i[:outstanding]), 'attempts', i[:attempts], 'next', i[:retries].first)
      end
      emit(2, '(none)') if invoices.empty?
    when 'REVENUE'
      total = ->(field) { money(@invoices.sum { |i| i[field] }) }
      emit(0, 'REVENUE')
      emit(2, 'invoices', @invoices.length, 'subtotal', total.call(:subtotal), 'discount', total.call(:discount),
           'tax', total.call(:tax), 'total', total.call(:total))
      emit(2, 'credit', total.call(:credit), 'paid', total.call(:paid), 'refunded', total.call(:refunded),
           'outstanding', total.call(:outstanding), 'balances', money(@customers.values.sum(&:balance)))
    when 'EVENTS'
      s = a.empty? ? nil : sub(a[0])
      emit(0, 'EVENTS', *(s ? ['sub', s.id] : []))
      events = @events.select { |_, id, _, _| s.nil? || id == s.id }
      events.each { |day, id, from, to| emit(2, 'day', day, 'sub', id, from, '->', to) }
      emit(2, '(none)') if events.empty?
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

billing = Billing.new
STDIN.gets.to_i.times { billing.execute(STDIN.gets.chomp) }
STDOUT.write(billing.output.join("\n") + "\n")
