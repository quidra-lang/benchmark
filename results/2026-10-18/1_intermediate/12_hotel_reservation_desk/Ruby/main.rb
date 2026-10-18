TYPES = %w[SINGLE DOUBLE SUITE].freeze
WEEKDAYS = %w[SAT SUN MON TUE WED THU FRI].freeze
DATES = []
DAYS = {}
(2000..2099).each do |year|
  leap = (year % 4).zero? && (!(year % 100).zero? || (year % 400).zero?)
  lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  (1..12).each do |month|
    (1..lengths[month - 1]).each do |day|
      text = format('%04d-%02d-%02d', year, month, day)
      DAYS[text] = DATES.length
      DATES << text
    end
  end
end
Room = Struct.new(:number, :kind, :base, :clean, :blocks, :occupied)
Night = Struct.new(:day, :room, :rate)
Reservation = Struct.new(:id, :guest, :room, :start, :finish, :nights, :status,
                         :extras, :deposit, :paid, :posting, :fee, :penalty, :bill)
Waiting = Struct.new(:id, :guest, :kind, :start, :finish)
class CommandError < StandardError; end

def date_text(day)
  DATES[day]
end

def date_week(day)
  "#{date_text(day)} #{WEEKDAYS[day % 7]}"
end

def cents(text)
  whole, fraction = text.split('.')
  whole.to_i * 100 + fraction.to_i
end

def money(value)
  format('%d.%02d', value / 100, value % 100)
end

def lodging(x)
  x.nights.sum(&:rate)
end

def extras(x)
  x.extras.sum { |_, amount| amount }
end

class Hotel
  attr_reader :output

  def initialize
    @today = DAYS['2026-01-01']
    @rooms = {}
    @seasons = []
    @reservations = {}
    @queue = []
    @used = {}
    @output = []
  end

  def emit(indent, *parts)
    @output << ' ' * indent + parts.join(' ')
  end

  def date(text)
    raise CommandError, "invalid date #{text}" unless DAYS.key?(text)
    DAYS[text]
  end

  def room(text)
    raise CommandError, "unknown room #{text}" unless @rooms.key?(text.to_i)
    @rooms[text.to_i]
  end

  def reservation(id)
    raise CommandError, "unknown reservation #{id}" unless @reservations.key?(id)
    @reservations[id]
  end

  def status(x, allowed)
    raise CommandError, "invalid status #{x.id} #{x.status}" unless allowed.include?(x.status)
  end

  def type(kind)
    raise CommandError, "invalid type #{kind}" unless TYPES.include?(kind)
  end

  def unused(id)
    raise CommandError, "duplicate reservation #{id}" if @used.key?(id)
  end

  def stay(a, b)
    start = date(a)
    finish = date(b)
    raise CommandError, "past date #{a}" if start < @today
    raise CommandError, "invalid range #{a} #{b}" if finish <= start
    raise CommandError, "too long #{finish - start}" if finish - start > 30
    [start, finish]
  end

  def period(a, b, future = false, limited = true)
    start = date(a)
    finish = date(b)
    raise CommandError, "past date #{a}" if future && start < @today
    raise CommandError, "invalid range #{a} #{b}" if finish < start
    raise CommandError, "too long #{finish - start + 1}" if limited && finish - start + 1 > 31
    [start, finish]
  end

  def sorted_rooms
    @rooms.values.sort_by(&:number)
  end

  def rate(r, day)
    percent = 100
    @seasons.each do |start, finish, p|
      percent = p if start <= day && day <= finish
    end
    r.base * percent / 100
  end

  def price(r, start, finish)
    (start...finish).map { |day| Night.new(day, r.number, rate(r, day)) }
  end

  def free?(r, day, except = nil)
    night = r.occupied[day]
    !r.blocks.key?(day) && (night.nil? || night[0] == except)
  end

  def unavailable(r, start, finish, except = nil)
    (start...finish).find { |day| !free?(r, day, except) }
  end

  def find_room(kind, start, finish, except = nil)
    sorted_rooms.find { |r| r.kind == kind && unavailable(r, start, finish, except).nil? }
  end

  def in_house(number)
    @reservations.values.find { |x| x.status == 'inhouse' && x.room == number }
  end

  def release(x)
    x.nights.each { |n| @rooms[n.room].occupied.delete(n.day) }
  end

  def occupy(x)
    x.nights.each { |n| @rooms[n.room].occupied[n.day] = [x.id, n.rate] }
  end

  def create(id, guest, r, start, finish, indent = 0)
    x = Reservation.new(id, guest, r.number, start, finish, price(r, start, finish),
                        'booked', [], 0, 0, nil, 0, nil, nil)
    @reservations[id] = x
    @used[id] = true
    occupy(x)
    emit(indent, 'BOOK', id, guest, 'room', r.number, r.kind, date_text(start), '->',
         date_text(finish), 'nights', finish - start, 'total', money(lodging(x)))
  end

  def guest_paid(guest)
    @reservations.values.select { |x| x.guest == guest }.sum(&:paid)
  end

  def tier(guest)
    points = guest_paid(guest) / 100
    if points >= 2000
      [points, 'GOLD', 10]
    elsif points >= 500
      [points, 'SILVER', 5]
    else
      [points, 'BRONZE', 0]
    end
  end

  def bill(x)
    l = lodging(x)
    discount = l * tier(x.guest)[2] / 100
    penalty = x.penalty ? x.penalty.rate : 0
    e = extras(x)
    subtotal = l - discount + penalty + e
    tax = subtotal / 10
    {lodging: l, discount: discount, penalty: penalty, extras: e, tax: tax, total: subtotal + tax}
  end

  def deposit_text(x, amount)
    if amount >= x.deposit
      "deposit #{money(x.deposit)} due #{money(amount - x.deposit)}"
    else
      "deposit #{money(x.deposit)} refund #{money(x.deposit - amount)}"
    end
  end

  def checkout(x, day, indent = 0)
    if day < x.finish
      x.penalty = x.nights.find { |n| n.day == day }
      x.nights.select { |n| n.day >= day }.each { |n| @rooms[n.room].occupied.delete(n.day) }
      x.nights = x.nights.select { |n| n.day < day }
      x.finish = day
    end
    b = bill(x)
    x.bill = b
    x.paid = b[:total]
    x.status = 'checkedout'
    x.posting = day
    @rooms[x.room].clean = false
    emit(indent, 'CHECKOUT', x.id, 'nights', x.nights.length, 'lodging', money(b[:lodging]),
         'discount', money(b[:discount]), 'penalty', money(b[:penalty]), 'extras', money(b[:extras]),
         'tax', money(b[:tax]), 'total', money(b[:total]), deposit_text(x, b[:total]))
  end

  def process_queue
    remaining = []
    @queue.each do |w|
      if w.start < @today
        emit(2, 'WAITLIST', w.id, 'expired')
      else
        r = find_room(w.kind, w.start, w.finish)
        if r
          create(w.id, w.guest, r, w.start, w.finish, 2)
        else
          remaining << w
        end
      end
    end
    @queue = remaining
  end

  def metrics(day)
    available = 0
    occupied = 0
    revenue = 0
    @rooms.each_value do |r|
      available += 1 unless r.blocks.key?(day)
      night = r.occupied[day]
      if night
        occupied += 1
        revenue += night[1]
      end
    end
    [available, occupied, revenue]
  end

  def metrics_text(values)
    available, occupied, revenue = values
    occupancy = available.positive? ? "#{occupied * 100 / available}%" : 'n/a'
    adr = occupied.positive? ? money(revenue / occupied) : 'n/a'
    revpar = available.positive? ? money(revenue / available) : 'n/a'
    "sold #{occupied}/#{available} rate #{occupancy} revenue #{money(revenue)} adr #{adr} revpar #{revpar}"
  end

  def occupancy_text(rooms, day)
    blocked = rooms.count { |r| r.blocks.key?(day) }
    occupied = rooms.count { |r| r.occupied.key?(day) }
    available = rooms.length - blocked
    occupancy = available.positive? ? "#{occupied * 100 / available}%" : 'n/a'
    "rooms #{rooms.length} blocked #{blocked} occupied #{occupied} rate #{occupancy}"
  end

  def invoice(x)
    emit(0, 'INVOICE', x.id, x.guest, 'room', x.room, @rooms[x.room].kind, x.status)
    if %w[cancelled noshow].include?(x.status)
      emit(2, x.status == 'cancelled' ? 'cancellation' : 'noshow', 'fee', money(x.fee))
      emit(2, 'total', money(x.fee))
      emit(2, deposit_text(x, x.fee))
      return
    end
    x.nights.each { |n| emit(2, date_week(n.day), 'room', n.room, money(n.rate)) }
    b = x.status == 'checkedout' ? x.bill : bill(x)
    emit(2, 'lodging', money(b[:lodging]))
    emit(2, 'discount', money(b[:discount]))
    emit(2, 'penalty', date_week(x.penalty.day), money(b[:penalty])) if x.penalty
    x.extras.each { |item, amount| emit(2, 'extra', item, money(amount)) }
    emit(2, 'tax', money(b[:tax]))
    emit(2, 'total', money(b[:total]))
    emit(2, deposit_text(x, b[:total]))
  end

  def command(cmd, a)
    case cmd
    when 'ROOM'
      number = a[0].to_i
      raise CommandError, "duplicate room #{a[0]}" if @rooms.key?(number)
      type(a[1])
      base = cents(a[2])
      @rooms[number] = Room.new(number, a[1], base, true, {}, {})
      emit(0, 'ROOM', number, a[1], money(base))
    when 'RATE'
      r = room(a[0])
      old = r.base
      r.base = cents(a[1])
      emit(0, 'RATE', r.number, money(old), '->', money(r.base))
    when 'SEASON'
      start, finish = period(a[0], a[1], false, false)
      @seasons << [start, finish, a[2].to_i]
      emit(0, 'SEASON', @seasons.length, a[0], '->', a[1], a[2] + '%')
    when 'BLOCK', 'UNBLOCK'
      r = room(a[0])
      start, finish = period(a[1], a[2], true)
      if cmd == 'BLOCK'
        (start..finish).each do |day|
          raise CommandError, "room unavailable #{r.number} #{date_text(day)}" if r.occupied.key?(day)
        end
      end
      count = 0
      (start..finish).each do |day|
        if cmd == 'BLOCK'
          count += 1 unless r.blocks.key?(day)
          r.blocks[day] = true
        elsif r.blocks.delete(day)
          count += 1
        end
      end
      emit(0, cmd, r.number, a[1], '->', a[2], cmd == 'BLOCK' ? 'added' : 'removed', count)
    when 'CLEAN'
      r = room(a[0])
      raise CommandError, "already clean #{r.number}" if r.clean
      r.clean = true
      emit(0, 'CLEAN', r.number)
    when 'TODAY'
      day = date(a[0])
      raise CommandError, "past date #{a[0]}" if day < @today
      emit(0, 'TODAY', date_week(day))
      checkouts = @reservations.values.select { |x| x.status == 'inhouse' && x.finish < day }
      checkouts.sort_by { |x| [x.finish, x.id] }.each { |x| checkout(x, x.finish, 2) }
      noshows = @reservations.values.select { |x| x.status == 'booked' && x.start < day }
      noshows.sort_by { |x| [x.start, x.id] }.each do |x|
        x.fee = x.nights.first.rate
        x.paid = x.fee
        x.status = 'noshow'
        x.posting = x.start
        release(x)
        emit(2, 'NOSHOW', x.id, x.guest, 'fee', money(x.fee), deposit_text(x, x.fee))
      end
      @today = day
    when 'BOOK', 'BOOKROOM', 'WAITLIST'
      unused(a[0])
      specific = nil
      if cmd == 'BOOKROOM'
        specific = room(a[2])
      else
        type(a[2])
      end
      start, finish = stay(a[3], a[4])
      r = specific || find_room(a[2], start, finish)
      if specific
        day = unavailable(specific, start, finish)
        raise CommandError, "room unavailable #{specific.number} #{date_text(day)}" unless day.nil?
      end
      if r
        create(a[0], a[1], r, start, finish)
      elsif cmd == 'WAITLIST'
        @queue << Waiting.new(a[0], a[1], a[2], start, finish)
        @used[a[0]] = true
        emit(0, 'WAITLIST', a[0], 'queued', 'position', @queue.length)
      else
        raise CommandError, "no availability #{a[2]} #{a[3]} #{a[4]}"
      end
    when 'MODIFY'
      x = reservation(a[0])
      status(x, ['booked'])
      start, finish = stay(a[1], a[2])
      old = @rooms[x.room]
      kept = unavailable(old, start, finish, x.id).nil?
      r = kept ? old : find_room(old.kind, start, finish, x.id)
      raise CommandError, "no availability #{old.kind} #{a[1]} #{a[2]}" unless r
      release(x)
      x.room = r.number
      x.start = start
      x.finish = finish
      x.nights = price(r, start, finish)
      occupy(x)
      emit(0, 'MODIFY', x.id, 'room', r.number, kept ? 'kept' : 'reassigned',
           a[1], '->', a[2], 'nights', finish - start, 'total', money(lodging(x)))
    when 'CANCEL'
      i = @queue.index { |w| w.id == a[0] }
      if i
        @queue.delete_at(i)
        emit(0, 'CANCEL', a[0], 'waitlist', 'removed')
      else
        x = reservation(a[0])
        status(x, ['booked'])
        days = x.start - @today
        x.fee = days >= 7 ? 0 : days >= 1 ? x.nights.first.rate / 2 : x.nights.first.rate
        x.paid = x.fee
        x.status = 'cancelled'
        x.posting = @today
        release(x)
        emit(0, 'CANCEL', x.id, 'days', days, 'fee', money(x.fee), deposit_text(x, x.fee))
      end
    when 'CHECKIN'
      x = reservation(a[0])
      status(x, ['booked'])
      raise CommandError, "not arrival date #{x.id} #{date_text(x.start)}" if x.start != @today
      occupant = in_house(x.room)
      raise CommandError, "room occupied #{x.room} #{occupant.id}" if occupant
      raise CommandError, "room dirty #{x.room}" unless @rooms[x.room].clean
      x.status = 'inhouse'
      emit(0, 'CHECKIN', x.id, x.guest, 'room', x.room, 'until', date_text(x.finish))
    when 'MOVE'
      x = reservation(a[0])
      status(x, ['inhouse'])
      r = room(a[1])
      raise CommandError, "same room #{r.number}" if r.number == x.room
      remaining = x.nights.select { |n| n.day >= @today }
      raise CommandError, "no remaining nights #{x.id}" if remaining.empty?
      remaining.each do |n|
        raise CommandError, "room unavailable #{r.number} #{date_text(n.day)}" unless free?(r, n.day, x.id)
      end
      occupant = in_house(r.number)
      raise CommandError, "room occupied #{r.number} #{occupant.id}" if occupant
      raise CommandError, "room dirty #{r.number}" unless r.clean
      old = x.room
      remaining.each do |n|
        @rooms[n.room].occupied.delete(n.day)
        n.room = r.number
        r.occupied[n.day] = [x.id, n.rate]
      end
      emit(0, 'MOVE', x.id, old, '->', r.number, 'nights', remaining.length)
      @rooms[old].clean = false
      x.room = r.number
    when 'EXTEND'
      x = reservation(a[0])
      status(x, ['inhouse'])
      finish = date(a[1])
      raise CommandError, "invalid range #{date_text(x.finish)} #{a[1]}" if finish <= x.finish
      raise CommandError, "too long #{finish - x.start}" if finish - x.start > 30
      r = @rooms[x.room]
      blocked = unavailable(r, x.finish, finish, x.id)
      raise CommandError, "room unavailable #{r.number} #{date_text(blocked)}" unless blocked.nil?
      x.nights.concat(price(r, x.finish, finish))
      x.finish = finish
      occupy(x)
      emit(0, 'EXTEND', x.id, 'until', a[1], 'nights', x.nights.length, 'total', money(lodging(x)))
    when 'CHARGE', 'PAY'
      x = reservation(a[0])
      status(x, cmd == 'CHARGE' ? ['inhouse'] : %w[booked inhouse])
      amount = cents(a[1])
      raise CommandError, 'invalid amount' if amount.zero?
      if cmd == 'CHARGE'
        x.extras << [a[2], amount]
        emit(0, 'CHARGE', x.id, a[2], money(amount), 'extras', money(extras(x)))
      else
        x.deposit += amount
        emit(0, 'PAY', x.id, money(amount), 'deposit', money(x.deposit))
      end
    when 'CHECKOUT'
      x = reservation(a[0])
      status(x, ['inhouse'])
      checkout(x, @today)
    when 'INVOICE'
      invoice(reservation(a[0]))
    when 'AVAIL'
      type(a[0])
      start, finish = period(a[1], a[2])
      emit(0, 'AVAIL', a[0], a[1], '->', a[2])
      (start..finish).each do |day|
        rooms = sorted_rooms.select { |r| r.kind == a[0] && free?(r, day) }
        emit(2, date_week(day), 'free', rooms.length, *rooms.map(&:number))
      end
    when 'OCCUPANCY'
      day = date(a[0])
      emit(0, 'OCCUPANCY', date_week(day), occupancy_text(@rooms.values, day))
      TYPES.each do |kind|
        rooms = @rooms.values.select { |r| r.kind == kind }
        emit(2, kind, occupancy_text(rooms, day)) unless rooms.empty?
      end
    when 'STATS'
      start, finish = period(a[0], a[1])
      emit(0, 'STATS', a[0], '->', a[1])
      total = [0, 0, 0]
      (start..finish).each do |day|
        values = metrics(day)
        emit(2, date_week(day), metrics_text(values))
        3.times { |i| total[i] += values[i] }
      end
      emit(2, 'total', metrics_text(total))
    when 'ROOMS'
      emit(0, 'ROOMS', date_week(@today), 'rooms', @rooms.length)
      sorted_rooms.each do |r|
        occupant = in_house(r.number)
        situation = occupant ? "occupied #{occupant.id}" : r.blocks.key?(@today) ? 'blocked' : 'vacant'
        following = @reservations.values.select { |x| x.status == 'booked' && x.room == r.number }.min_by { |x| [x.start, x.id] }
        parts = [r.number, r.kind, 'base', money(r.base), 'tonight', money(rate(r, @today)), r.clean ? 'clean' : 'dirty', situation]
        parts.push('next', following.id, date_text(following.start)) if following
        emit(2, *parts)
      end
    when 'LIST'
      targets = @reservations.values.select { |x| x.status == a[0] }.sort_by { |x| [x.start, x.id] }
      emit(0, 'LIST', a[0], targets.length)
      targets.each { |x| emit(2, x.id, x.guest, 'room', x.room, date_text(x.start), '->', date_text(x.finish)) }
    when 'QUEUE'
      emit(0, 'QUEUE', @queue.length)
      @queue.each_with_index do |w, i|
        emit(2, i + 1, w.id, w.guest, w.kind, date_text(w.start), '->', date_text(w.finish))
      end
    when 'SCHEDULE'
      day = date(a[0])
      arrivals = @reservations.values.select { |x| x.start == day && x.status != 'cancelled' }.sort_by(&:id)
      departures = @reservations.values.select { |x| x.finish == day && %w[booked inhouse checkedout].include?(x.status) }.sort_by(&:id)
      emit(0, 'SCHEDULE', date_week(day), 'arrivals', arrivals.length, 'departures', departures.length)
      arrivals.each { |x| emit(2, 'arrival', x.id, x.guest, 'room', x.room, x.status) }
      departures.each { |x| emit(2, 'departure', x.id, x.guest, 'room', x.room, x.status) }
    when 'GUEST'
      targets = @reservations.values.select { |x| x.guest == a[0] }
      raise CommandError, "unknown guest #{a[0]}" if targets.empty?
      emit(0, 'GUEST', a[0])
      targets.each do |x|
        pending = %w[booked inhouse].include?(x.status)
        emit(2, x.id, 'room', x.room, @rooms[x.room].kind, date_text(x.start), '->',
             date_text(x.finish), x.status, pending ? 'deposit' : 'paid', money(pending ? x.deposit : x.paid))
      end
      points, name, = tier(a[0])
      emit(2, 'total', 'paid', money(guest_paid(a[0])), 'points', points, 'tier', name)
    when 'REVENUE'
      start, finish = period(a[0], a[1], false, false)
      targets = @reservations.values.select { |x| x.posting && start <= x.posting && x.posting <= finish }
      totals = %i[lodging discount penalty extras tax cancellation noshow].to_h { |key| [key, 0] }
      checkouts = 0
      cancellations = 0
      noshows = 0
      targets.each do |x|
        if x.status == 'checkedout'
          checkouts += 1
          %i[lodging discount penalty extras tax].each { |key| totals[key] += x.bill[key] }
        elsif x.status == 'cancelled'
          cancellations += 1
          totals[:cancellation] += x.fee
        elsif x.status == 'noshow'
          noshows += 1
          totals[:noshow] += x.fee
        end
      end
      emit(0, 'REVENUE', a[0], '->', a[1])
      totals.each { |key, value| emit(2, key, money(value)) }
      total = totals[:lodging] - totals[:discount] + totals[:penalty] + totals[:extras] + totals[:tax] + totals[:cancellation] + totals[:noshow]
      emit(2, 'total', money(total))
      emit(2, 'checkouts', checkouts, 'cancellations', cancellations, 'noshows', noshows)
    end
  end

  def execute(line)
    cmd, *args = line.split
    begin
      command(cmd, args)
    rescue CommandError => error
      emit(0, 'ERROR', error.message)
    end
    process_queue
  end
end

hotel = Hotel.new
STDIN.gets.to_i.times { hotel.execute(STDIN.gets.chomp) }
STDOUT.write(hotel.output.join("\n") + "\n")
