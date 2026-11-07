STATIONS = %w[GRILL FRY COLD BAR].freeze
COURSES = %w[DRINK STARTER MAIN DESSERT].freeze
Server = Struct.new(:name, :parties, :sales, :tips)
Table = Struct.new(:number, :seats, :check)
Check = Struct.new(:party, :size, :table, :server, :seated, :lines, :paid, :discount, :closed)
MenuItem = Struct.new(:name, :station, :prep, :price, :course, :stock)
Line = Struct.new(:id, :check, :seat, :item, :quantity, :station, :prep, :price, :course,
                  :state, :reason, :fire, :ready, :started)
class CommandError < StandardError; end

def cents(text)
  text.delete('.').to_i
end

def money(value)
  format('%d.%02d', value / 100, value % 100)
end

def clock(time)
  format('%02d:%02d', (660 + time) / 60, (660 + time) % 60)
end

def rounded(value, rate)
  (value * rate + 50) / 100
end

def amount(line)
  line.reason.nil? ? line.price * line.quantity : 0
end

def active(check)
  check.lines.reject { |line| line.state == 'VOID' }
end

class Restaurant
  attr_reader :output

  def initialize
    @now = 0
    @tables = {}
    @servers = []
    @waiting = []
    @menu = {}
    @lines = []
    @stations = STATIONS.to_h do |name|
      [name, {capacity: name == 'BAR' ? 2 : 1, up: true, queue: [], cooking: [], tickets: [], remakes: 0}]
    end
    @happy_rate = 0
    @happy_end = 0
    @covers = 0
    @parties = 0
    @turns = 0
    @stay = 0
    @sales = COURSES.to_h { |course| [course, 0] }
    @totals = %i[subtotal discount service tax total].to_h { |field| [field, 0] }
    @payments = {'CASH' => 0, 'CARD' => 0}
    @tips = 0
    @comps = 0
    @comp_amount = 0
    @voids = 0
    @served = {}
    @output = []
  end

  def emit(*parts)
    @output << parts.join(' ')
  end

  def table(text)
    raise CommandError, "unknown table #{text}" unless @tables.key?(text.to_i)
    @tables[text.to_i]
  end

  def check(text)
    t = table(text)
    raise CommandError, "table #{text} is free" unless t.check
    t.check
  end

  def unlocked(c)
    raise CommandError, "check for table #{c.table.number} is locked" if c.paid.positive?
  end

  def line(text)
    id = text.to_i
    raise CommandError, "unknown line #{text}" unless (1..@lines.length).cover?(id)
    @lines[id - 1]
  end

  def modifiable(l)
    raise CommandError, "##{l.id} is void" if l.state == 'VOID'
    raise CommandError, "##{l.id} is on a closed check" if l.check.closed
    unlocked(l.check)
  end

  def unserved(c)
    count = active(c).count { |l| l.state != 'SERVED' }
    raise CommandError, "table #{c.table.number} has #{count} unserved items" if count.positive?
  end

  def station(name)
    raise CommandError, "unknown station #{name}" unless @stations.key?(name)
    @stations[name]
  end

  def course(name)
    raise CommandError, "unknown course #{name}" unless COURSES.include?(name)
  end

  def item(name)
    raise CommandError, "unknown item #{name}" unless @menu.key?(name)
    @menu[name]
  end

  def load(server)
    @tables.values.count { |t| t.check && t.check.server.equal?(server) }
  end

  def select_table(size)
    @tables.values.select { |t| t.check.nil? && t.seats >= size }.min_by { |t| [t.seats, t.number] }
  end

  def seat(party, size, table)
    server = @servers.each_with_index.min_by { |s, i| [load(s), i] }[0]
    c = Check.new(party, size, table, server, @now, [], 0, 0, false)
    table.check = c
    server.parties += 1
    @covers += size
    @parties += 1
    c
  end

  def process_waiting
    remaining = []
    @waiting.each do |party, size, joined|
      t = select_table(size)
      if t
        c = seat(party, size, t)
        emit('SEATED', party, size, 'table', t.number, 'server', c.server.name, 'waited', @now - joined)
      else
        remaining << [party, size, joined]
      end
    end
    @waiting = remaining
  end

  def amounts(c)
    subtotal = active(c).sum { |l| amount(l) }
    discount = rounded(subtotal, c.discount)
    after = subtotal - discount
    service = c.size >= 6 ? rounded(after, 18) : 0
    tax = rounded(after, 8)
    total = after + service + tax
    {subtotal: subtotal, discount: discount, service: service, tax: tax, total: total, due: total - c.paid}
  end

  def close(c)
    a = amounts(c)
    @turns += 1
    @stay += @now - c.seated
    active(c).each { |l| @sales[l.course] += amount(l) }
    @totals.each_key { |field| @totals[field] += a[field] }
    c.server.sales += a[:total]
    c.closed = true
    c.table.check = nil
    emit('FREE', 'table', c.table.number, c.party, 'stayed', @now - c.seated)
    process_waiting
  end

  def start(s, time)
    while s[:up] && !s[:queue].empty? && s[:cooking].length < s[:capacity]
      l = s[:queue].shift
      l.state = 'COOKING'
      l.ready = time + l.prep
      l.started = true
      s[:cooking] << l
    end
  end

  def tick(minutes)
    finish = @now + minutes
    emit('TICK', clock(finish))
    loop do
      cooking = @stations.values.flat_map { |s| s[:cooking] }
      break if cooking.empty?
      time = cooking.map(&:ready).min
      break if time > finish
      @stations.each do |name, s|
        finished = s[:cooking].select { |l| l.ready == time }.sort_by(&:id)
        s[:cooking].reject! { |l| l.ready == time }
        finished.each do |l|
          l.state = 'READY'
          s[:tickets] << time - l.fire
          emit('READY', clock(time), name, "##{l.id}", l.item, "x#{l.quantity}", 'table', l.check.table.number, 'seat', l.seat)
        end
      end
      @stations.each_value { |s| start(s, time) }
    end
    @now = finish
  end

  def seats(c)
    active(c).group_by(&:seat).sort.to_h.transform_values { |lines| lines.sum { |l| amount(l) } }
  end

  def allocate(values, rate)
    result = values.to_h { |seat, value| [seat, value * rate / 100] }
    left = rounded(values.values.sum, rate) - result.values.sum
    order = values.keys.sort_by { |seat| [-(values[seat] * rate % 100), seat] }
    order.first(left).each { |seat| result[seat] += 1 }
    result
  end

  def bill(c)
    emit('BILL', 'table', c.table.number, c.party, 'guests', c.size)
    seats(c).each do |seat, subtotal|
      emit('SEAT', seat, money(subtotal))
      active(c).select { |l| l.seat == seat }.each do |l|
        emit("##{l.id}", l.item, "x#{l.quantity}", money(amount(l)), *(l.reason ? ['COMP', l.reason] : []))
      end
    end
    a = amounts(c)
    emit('SUBTOTAL', money(a[:subtotal]))
    emit('DISCOUNT', "#{c.discount}%", money(a[:discount])) unless c.discount.zero?
    emit('SERVICE', money(a[:service])) if c.size >= 6
    emit('TAX', money(a[:tax]))
    emit('TOTAL', money(a[:total]))
    if c.paid.positive?
      emit('PAID', money(c.paid))
      emit('DUE', money(a[:due]))
    end
  end

  def report
    emit('REPORT', clock(@now))
    emit('COVERS', @covers, 'parties', @parties)
    emit('TURNS', @turns, 'avg_stay', @turns.positive? ? @stay / @turns : '-')
    emit('SALES', *COURSES.flat_map { |c| [c, money(@sales[c])] })
    emit('TOTALS', *@totals.flat_map { |field, value| [field, money(value)] })
    emit('PAYMENTS', 'cash', money(@payments['CASH']), 'card', money(@payments['CARD']), 'tips', money(@tips))
    emit('COMPS', @comps, money(@comp_amount), 'VOIDS', @voids)
    @served.select { |_, count| count.positive? }.sort_by { |name, count| [-count, name] }.first(3).each_with_index do |(name, count), i|
      emit('TOP', i + 1, name, count)
    end
    @stations.each do |name, s|
      tickets = s[:tickets]
      emit(name, 'tickets', tickets.length, 'avg', tickets.empty? ? '-' : tickets.sum / tickets.length,
           'max', tickets.empty? ? '-' : tickets.max, 'remakes', s[:remakes])
    end
    @servers.each { |s| emit('SERVER', s.name, 'tables', load(s), 'parties', s.parties, 'sales', money(s.sales), 'tips', money(s.tips)) }
  end

  def command(cmd, a)
    case cmd
    when 'TABLE'
      number = a[0].to_i
      raise CommandError, "table #{a[0]} already exists" if @tables.key?(number)
      @tables[number] = Table.new(number, a[1].to_i, nil)
      emit('TABLE', number, 'seats', a[1].to_i)
      process_waiting
    when 'STAFF'
      raise CommandError, "#{a[0]} is already on duty" if @servers.any? { |s| s.name == a[0] }
      @servers << Server.new(a[0], 0, 0, 0)
      emit('STAFF', a[0])
    when 'SEAT'
      seated = @tables.values.find { |t| t.check && t.check.party == a[0] }
      raise CommandError, "#{a[0]} is already seated at table #{seated.number}" if seated
      raise CommandError, "#{a[0]} is already waiting" if @waiting.any? { |party, _, _| party == a[0] }
      size = a[1].to_i
      raise CommandError, "no table for party of #{size}" unless @tables.values.any? { |t| t.seats >= size }
      raise CommandError, 'no server on duty' if @servers.empty?
      t = select_table(size)
      if t
        c = seat(a[0], size, t)
        emit('SEAT', a[0], size, 'table', t.number, 'server', c.server.name)
      else
        @waiting << [a[0], size, @now]
        emit('WAIT', a[0], size, 'position', @waiting.length)
      end
    when 'CANCEL'
      index = @waiting.index { |party, _, _| party == a[0] }
      raise CommandError, "#{a[0]} is not waiting" unless index
      party, size, joined = @waiting.delete_at(index)
      emit('CANCEL', party, size, 'waited', @now - joined)
    when 'MOVE'
      source = table(a[0])
      destination = table(a[1])
      raise CommandError, "table #{a[0]} is free" unless source.check
      raise CommandError, "table #{a[1]} is occupied" if destination.check
      c = source.check
      raise CommandError, "table #{a[1]} is too small for #{c.party}" if destination.seats < c.size
      source.check = nil
      destination.check = c
      c.table = destination
      emit('MOVE', c.party, 'table', source.number, '->', destination.number)
      process_waiting
    when 'MENU'
      station(a[1])
      course(a[4])
      old = @menu[a[0]]
      @menu[a[0]] = MenuItem.new(a[0], a[1], a[2].to_i, cents(a[3]), a[4], old&.stock)
      emit('MENU', old ? 'UPDATE' : 'ADD', a[0], a[1], a[2].to_i, money(cents(a[3])), a[4])
    when 'STOCK'
      item = item(a[0])
      item.stock = a[1].to_i
      emit('STOCK', item.name, item.stock)
    when 'HAPPY'
      @happy_rate = a[0].to_i
      @happy_end = @now + a[1].to_i
      emit('HAPPY', "#{@happy_rate}%", 'until', clock(@happy_end))
    when 'ITEMS'
      items = @menu.values.sort_by { |i| [COURSES.index(i.course), i.name] }
      emit('ITEMS', items.length)
      items.each { |i| emit(i.course, i.name, i.station, i.prep, money(i.price), i.stock.nil? ? '-' : i.stock) }
    when 'ORDER'
      c = check(a[0])
      unlocked(c)
      seat = a[1].to_i
      raise CommandError, "seat #{seat} out of range for table #{a[0]}" if seat > c.size
      item = item(a[2])
      quantity = a[3].to_i
      raise CommandError, "only #{item.stock} #{item.name} left" if !item.stock.nil? && item.stock < quantity
      happy = item.course == 'DRINK' && @now < @happy_end
      price = item.price - (happy ? rounded(item.price, @happy_rate) : 0)
      l = Line.new(@lines.length + 1, c, seat, item.name, quantity, item.station, item.prep, price,
                   item.course, 'ORDERED', nil, 0, 0, false)
      @lines << l
      c.lines << l
      emit('ORDER', "##{l.id}", 'table', c.table.number, 'seat', seat, item.name, "x#{quantity}", money(amount(l)), *(happy ? ['HAPPY'] : []))
      unless item.stock.nil?
        item.stock -= quantity
        emit('SOLDOUT', item.name) if item.stock.zero?
      end
    when 'FIRE'
      c = check(a[0])
      course(a[1])
      lines = c.lines.select { |l| l.course == a[1] && l.state == 'ORDERED' }
      raise CommandError, "nothing to fire for #{a[1]} at table #{a[0]}" if lines.empty?
      if %w[MAIN DESSERT].include?(a[1])
        %w[STARTER MAIN DESSERT].take_while { |course| course != a[1] }.each do |earlier|
          raise CommandError, "fire #{earlier} first" if c.lines.any? { |l| l.course == earlier && l.state == 'ORDERED' }
        end
      end
      lines.each do |l|
        l.state = 'QUEUED'
        l.fire = @now
        @stations[l.station][:queue] << l
      end
      emit('FIRE', 'table', c.table.number, a[1], *lines.map { |l| "##{l.id}" })
      @stations.each_value { |s| start(s, @now) }
    when 'TICK'
      tick(a[0].to_i)
    when 'SERVE'
      c = check(a[0])
      lines = c.lines.select { |l| l.state == 'READY' }
      raise CommandError, "nothing ready for table #{a[0]}" if lines.empty?
      lines.each do |l|
        l.state = 'SERVED'
        @served[l.item] = @served.fetch(l.item, 0) + l.quantity
      end
      emit('SERVE', 'table', c.table.number, *lines.map { |l| "##{l.id}" })
    when 'RUSH'
      l = line(a[0])
      raise CommandError, "##{l.id} is not queued" unless l.state == 'QUEUED'
      s = @stations[l.station]
      s[:queue].delete(l)
      s[:queue].unshift(l)
      emit('RUSH', "##{l.id}", l.station)
    when 'REMAKE'
      l = line(a[0])
      raise CommandError, "##{l.id} is on a closed check" if l.check.closed
      raise CommandError, "##{l.id} is not ready or served" unless %w[READY SERVED].include?(l.state)
      l.state = 'QUEUED'
      l.fire = @now
      s = @stations[l.station]
      s[:queue].unshift(l)
      s[:remakes] += 1
      emit('REMAKE', "##{l.id}", l.item, l.station)
      start(s, @now)
    when 'VOID'
      l = line(a[0])
      raise CommandError, "##{l.id} is already void" if l.state == 'VOID'
      raise CommandError, "##{l.id} has already started" if l.started
      @stations[l.station][:queue].delete(l) if l.state == 'QUEUED'
      l.state = 'VOID'
      item = @menu[l.item]
      item.stock += l.quantity unless item.stock.nil?
      @voids += 1
      emit('VOID', "##{l.id}", l.item, "x#{l.quantity}")
    when 'STATION'
      s = station(a[0])
      raise CommandError, "station #{a[0]} is already down" if a[1] == 'DOWN' && !s[:up]
      raise CommandError, "station #{a[0]} is not down" if a[1] == 'UP' && s[:up]
      s[:up] = a[1] == 'UP'
      start(s, @now) if s[:up]
      emit('STATION', a[0], a[1])
    when 'COMP', 'TRANSFER'
      l = line(a[0])
      modifiable(l)
      if cmd == 'COMP'
        raise CommandError, "##{l.id} is already comped" unless l.reason.nil?
        value = amount(l)
        emit('COMP', "##{l.id}", l.item, money(value), a[1])
        @comps += 1
        @comp_amount += value
        l.reason = a[1]
      else
        seat = a[1].to_i
        raise CommandError, "seat #{seat} out of range for table #{l.check.table.number}" if seat > l.check.size
        raise CommandError, "##{l.id} is already on seat #{seat}" if seat == l.seat
        emit('TRANSFER', "##{l.id}", 'seat', l.seat, '->', seat)
        l.seat = seat
      end
    when 'DISCOUNT'
      c = check(a[0])
      unlocked(c)
      c.discount = a[1].to_i
      emit('DISCOUNT', 'table', c.table.number, "#{c.discount}%")
    when 'BILL'
      bill(check(a[0]))
    when 'SPLIT'
      c = check(a[0])
      amounts = amounts(c)
      raise CommandError, "nothing to split for table #{a[0]}" if amounts[:due].zero?
      if a[1] == 'EVEN'
        count = a[2].to_i
        raise CommandError, "cannot split table #{a[0]} #{count} ways" if count > c.size
        emit('SPLIT', 'table', c.table.number, 'EVEN', count, 'due', money(amounts[:due]))
        q, r = amounts[:due].divmod(count)
        (1..count).each { |i| emit('PAYER', i, money(q + (i <= r ? 1 : 0))) }
      else
        raise CommandError, "table #{a[0]} has payments" if c.paid.positive?
        values = seats(c)
        discounts = allocate(values, c.discount)
        after = values.to_h { |seat, value| [seat, value - discounts[seat]] }
        services = allocate(after, c.size >= 6 ? 18 : 0)
        taxes = allocate(after, 8)
        emit('SPLIT', 'table', c.table.number, 'BYSEAT', 'total', money(amounts[:total]))
        values.each do |seat, subtotal|
          emit('SEAT', seat, 'subtotal', money(subtotal), 'discount', money(discounts[seat]),
               'service', money(services[seat]), 'tax', money(taxes[seat]),
               'total', money(after[seat] + services[seat] + taxes[seat]))
        end
      end
    when 'PAY'
      c = check(a[0])
      raise CommandError, "unknown method #{a[1]}" unless %w[CASH CARD].include?(a[1])
      unserved(c)
      due = amounts(c)[:due]
      raise CommandError, "nothing to pay for table #{a[0]}" if due.zero?
      value = cents(a[2])
      applied = [value, due].min
      c.paid += applied
      @payments[a[1]] += applied
      if value < due
        emit('PAY', 'table', c.table.number, a[1], money(value), 'remaining', money(due - value))
      else
        emit('PAY', 'table', c.table.number, a[1], money(value), a[1] == 'CASH' ? 'change' : 'tip', money(value - due))
        if a[1] == 'CARD'
          @tips += value - due
          c.server.tips += value - due
        end
        close(c)
      end
    when 'CLOSE'
      c = check(a[0])
      unserved(c)
      due = amounts(c)[:due]
      raise CommandError, "table #{a[0]} still owes #{money(due)}" unless due.zero?
      close(c)
    when 'STATUS'
      c = check(a[0])
      emit('STATUS', 'table', c.table.number, c.party, 'guests', c.size, 'since', clock(c.seated))
      c.lines.each do |l|
        emit("##{l.id}", 'seat', l.seat, l.item, "x#{l.quantity}", l.course, l.state,
             *(l.state == 'COOKING' ? ['until', clock(l.ready)] : []), *(l.reason ? ['COMP', l.reason] : []))
      end
    when 'KITCHEN'
      emit('KITCHEN', clock(@now))
      @stations.each do |name, s|
        cooking = s[:cooking].sort_by { |l| [l.ready, l.id] }.map { |l| "##{l.id}@#{clock(l.ready)}" }
        queue = s[:queue].map { |l| "##{l.id}" }
        emit(name, s[:up] ? 'up' : 'down', 'cooking', cooking.empty? ? '-' : cooking.join(' '), 'queue', queue.empty? ? '-' : queue.join(' '))
      end
    when 'FLOOR'
      tables = @tables.values.sort_by(&:number)
      free = tables.count { |t| t.check.nil? }
      emit('FLOOR', clock(@now), 'free', free, 'seated', tables.length - free, 'waiting', @waiting.length)
      tables.each do |t|
        c = t.check
        if c
          emit('table', t.number, 'seats', t.seats, c.party, 'guests', c.size, 'server', c.server.name,
               'since', clock(c.seated), 'items', active(c).length, 'total', money(amounts(c)[:total]),
               *(c.paid.positive? ? ['paid', money(c.paid)] : []))
        else
          emit('table', t.number, 'seats', t.seats, 'free')
        end
      end
      @waiting.each_with_index { |(party, size, joined), i| emit('WAITING', i + 1, party, size, 'since', clock(joined)) }
    when 'REPORT'
      report
    end
  end

  def execute(line)
    cmd, *args = line.split
    begin
      command(cmd, args)
    rescue CommandError => error
      emit('ERROR', error.message)
    end
  end
end

restaurant = Restaurant.new
STDIN.gets.to_i.times { restaurant.execute(STDIN.gets.chomp) }
STDOUT.write(restaurant.output.join("\n") + "\n")
