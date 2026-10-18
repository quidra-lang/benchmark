TYPES = %w[MOTORCYCLE CAR ECAR VAN BUS].freeze
KINDS = %w[MOTO COMPACT LARGE EV].freeze
PREF = {
  'MOTORCYCLE' => %w[MOTO COMPACT LARGE],
  'CAR' => %w[COMPACT LARGE],
  'ECAR' => %w[EV COMPACT LARGE],
  'VAN' => %w[LARGE]
}.freeze
FIELDS = %i[entries exits refused stay parking night lost charge total].freeze
Spot = Struct.new(:level, :number, :kind, :code, :closed, :vehicle) do
  def free?
    !closed && vehicle.nil?
  end
end
Vehicle = Struct.new(:plate, :kind, :spots, :entered, :energy, :charge_cost, :validation, :payment) do
  def location
    spots.first.code + (kind == 'BUS' ? "..#{spots.last.number}" : '')
  end

  def order
    [spots.first.level, spots.first.number]
  end
end
Waiting = Struct.new(:plate, :kind, :joined)
class CommandError < StandardError; end

def empty_totals
  FIELDS.to_h { |field| [field, 0] }
end

def empty_types
  TYPES.to_h { |kind| [kind, empty_totals] }
end

def sum_totals(rows)
  FIELDS.to_h { |field| [field, rows.sum { |row| row[field] }] }
end

def date_of(time)
  time / 1440 + 1
end

def stamp(time)
  format('%d-%02d:%02d', date_of(time), time % 1440 / 60, time % 60)
end

def duration(minutes)
  format('%d:%02d', minutes / 60, minutes % 60)
end

class Garage
  attr_reader :output

  def initialize
    @now = 0
    @levels = []
    @spots = []
    @spot_codes = {}
    @vehicles = {}
    @queue = []
    @passes = {}
    @history = {}
    @rates = {
      'MOTORCYCLE' => [100, 800], 'CAR' => [200, 1600],
      'ECAR' => [200, 1600], 'VAN' => [300, 2400], 'BUS' => [600, 4800]
    }
    @fees = {'NIGHT' => 300, 'LOST' => 2000, 'KWH' => 30}
    @totals = empty_types
    @daily = {}
    @peak = 0
    @peak_time = nil
    @output = []
  end

  def emit(*parts)
    @output << parts.join(' ')
  end

  def vehicle(plate)
    raise CommandError, "#{plate} is not parked" unless @vehicles.key?(plate)
    @vehicles[plate]
  end

  def spot(code)
    raise CommandError, "unknown spot #{code}" unless @spot_codes.key?(code)
    @spot_codes[code]
  end

  def unpaid(v)
    raise CommandError, "#{v.plate} has already paid" unless v.payment.nil?
  end

  def pass?(plate, time = @now)
    @passes.key?(plate) && date_of(time) <= @passes[plate]
  end

  def day_totals(day)
    @daily[day] ||= empty_types
  end

  def count(kind, field, day)
    @totals[kind][field] += 1
    day_totals(day)[kind][field] += 1
  end

  def assignment(kind)
    if kind == 'BUS'
      @levels.each do |level|
        level.each_cons(3) do |triple|
          return triple if triple.all? { |s| s.kind == 'LARGE' && s.free? }
        end
      end
    else
      PREF[kind].each do |preferred|
        found = @spots.find { |s| s.kind == preferred && s.free? }
        return [found] if found
      end
    end
    nil
  end

  def park(plate, kind, spots)
    v = Vehicle.new(plate, kind, spots, @now, 0, 0, 0, nil)
    @vehicles[plate] = v
    spots.each { |s| s.vehicle = v }
    count(kind, :entries, date_of(@now))
    if @vehicles.length > @peak
      @peak = @vehicles.length
      @peak_time = @now
    end
    v
  end

  def give_up
    remaining = []
    @queue.each do |w|
      deadline = w.joined + 30
      if deadline <= @now
        emit('GIVEUP', w.plate, w.kind, stamp(deadline))
        count(w.kind, :refused, date_of(deadline))
      else
        remaining << w
      end
    end
    @queue = remaining
  end

  def process_queue
    remaining = []
    @queue.each do |w|
      spots = assignment(w.kind)
      if spots
        v = park(w.plate, w.kind, spots)
        emit('ADMIT', w.plate, w.kind, v.location, 'waited', duration(@now - w.joined))
      else
        remaining << w
      end
    end
    @queue = remaining
  end

  def interval(v, start, finish, grace)
    remaining = finish - start
    return [0, 0] if pass?(v.plate, finish) || remaining <= grace
    rate, cap = @rates[v.kind]
    parking = 0
    first = true
    while remaining.positive?
      minutes = [remaining, 1440].min
      billable = minutes - (first ? grace : 0)
      parking += [((billable + 29) / 30) * rate, cap].min
      remaining -= minutes
      first = false
    end
    [parking, (date_of(finish) - date_of(start)) * @fees['NIGHT']]
  end

  def charges(v, lost = false)
    lost_fee = lost ? @fees['LOST'] : 0
    if v.payment.nil?
      parking, night = interval(v, v.entered, @now, 15 + v.validation)
      due = parking + night + lost_fee + v.charge_cost
    else
      paid_time, paid_parking, paid_night = v.payment
      additional, extra_night = interval(v, paid_time, @now, 15)
      parking = paid_parking + additional
      night = paid_night + extra_night
      due = additional + extra_night
    end
    {
      parking: parking, night: night, lost: lost_fee, charge: v.charge_cost,
      total: parking + night + lost_fee + v.charge_cost, due: due
    }
  end

  def fee_line(label, v, c)
    emit(label, v.plate, v.location, 'stay', duration(@now - v.entered),
         'parking', c[:parking], 'night', c[:night], 'lost', c[:lost],
         'charge', c[:charge], 'total', c[:total], 'due', c[:due])
  end

  def annotation(v)
    parts = []
    parts << 'PASS' if pass?(v.plate)
    parts.push('VAL', v.validation) unless v.validation.zero?
    parts.push('KWH', v.energy) unless v.energy.zero?
    parts << 'PAID' unless v.payment.nil?
    parts.empty? ? '' : ' ' + parts.join(' ')
  end

  def move_vehicle(v, s)
    old = v.location
    v.spots.first.vehicle = nil
    v.spots = [s]
    s.vehicle = v
    emit('MOVE', v.plate, old, '->', s.code)
  end

  def revenue_line(label, t)
    parts = [label, 'exits', t[:exits]]
    %i[parking night lost charge total].each { |f| parts.push(f, t[f]) }
    emit(*parts)
  end

  def daily_line(prefix, t)
    emit(*prefix, 'entries', t[:entries], 'exits', t[:exits],
         'refused', t[:refused], 'revenue', t[:total])
  end

  def stats_line(label, t)
    q = t[:exits].zero? ? 0 : t[:stay] * 10 / t[:exits]
    emit(label, 'entries', t[:entries], 'exits', t[:exits],
         'refused', t[:refused], 'avg_stay', "#{q / 10}.#{q % 10}")
  end

  def command(cmd, a)
    plate = a[0]
    case cmd
    when 'LEVEL'
      counts = a.map(&:to_i)
      index = @levels.length + 1
      level = []
      KINDS.zip(counts).each do |kind, count|
        count.times do
          number = level.length + 1
          s = Spot.new(index, number, kind, "L#{index}-#{number}", false, nil)
          level << s
          @spots << s
          @spot_codes[s.code] = s
        end
      end
      @levels << level
      emit('LEVEL', index, 'spots', level.length, 'MOTO', counts[0],
           'COMPACT', counts[1], 'LARGE', counts[2], 'EV', counts[3])
      process_queue
    when 'CLOSE'
      s = spot(a[0])
      raise CommandError, "spot #{s.code} is already closed" if s.closed
      raise CommandError, "spot #{s.code} is occupied by #{s.vehicle.plate}" if s.vehicle
      s.closed = true
      emit('CLOSE', s.code, s.kind)
    when 'OPEN'
      s = spot(a[0])
      raise CommandError, "spot #{s.code} is not closed" unless s.closed
      s.closed = false
      emit('OPEN', s.code, s.kind)
      process_queue
    when 'RATE'
      kind, rate, cap = a
      raise CommandError, "unknown type #{kind}" unless TYPES.include?(kind)
      rate = rate.to_i
      cap = cap.to_i
      raise CommandError, "cap below rate for #{kind}" if cap < rate
      @rates[kind] = [rate, cap]
      emit('RATE', kind, rate, cap)
    when 'FEE'
      item, amount = a
      raise CommandError, "unknown fee #{item}" unless @fees.key?(item)
      @fees[item] = amount.to_i
      emit('FEE', item, amount.to_i)
    when 'ENTER'
      kind = a[1]
      raise CommandError, "unknown type #{kind}" unless TYPES.include?(kind)
      raise CommandError, "#{plate} is already parked at #{@vehicles[plate].location}" if @vehicles.key?(plate)
      raise CommandError, "#{plate} is already waiting" if @queue.any? { |w| w.plate == plate }
      spots = assignment(kind)
      if spots
        v = park(plate, kind, spots)
        emit('ENTER', plate, kind, v.location)
      elsif @queue.length < 3
        @queue << Waiting.new(plate, kind, @now)
        emit('WAIT', plate, kind, @queue.length)
      else
        emit('FULL', plate, kind)
        count(kind, :refused, date_of(@now))
      end
    when 'LEAVE'
      index = @queue.index { |w| w.plate == plate }
      raise CommandError, "#{plate} is not waiting" unless index
      w = @queue.delete_at(index)
      emit('LEAVE', plate, w.kind)
    when 'EXIT'
      v = vehicle(plate)
      lost = a.length == 2
      unpaid(v) if lost
      c = charges(v, lost)
      fee_line('EXIT', v, c)
      (@history[plate] ||= []) << {
        entered: v.entered, exited: @now, location: v.location,
        kind: v.kind, total: c[:total], lost: lost
      }
      count(v.kind, :exits, date_of(@now))
      daily = day_totals(date_of(@now))[v.kind]
      %i[parking night lost charge total].each do |f|
        @totals[v.kind][f] += c[f]
        daily[f] += c[f]
      end
      @totals[v.kind][:stay] += @now - v.entered
      daily[:stay] += @now - v.entered
      v.spots.each { |s| s.vehicle = nil }
      @vehicles.delete(plate)
      process_queue
    when 'PAY'
      v = vehicle(plate)
      unpaid(v)
      c = charges(v)
      v.payment = [@now, c[:parking], c[:night]]
      emit('PAY', plate, 'parking', c[:parking], 'night', c[:night],
           'charge', c[:charge], 'total', c[:total])
    when 'QUOTE'
      v = vehicle(plate)
      fee_line('QUOTE', v, charges(v))
    when 'CHARGE'
      v = vehicle(plate)
      kwh = a[1].to_i
      raise CommandError, "#{plate} is not an electric car" unless v.kind == 'ECAR'
      raise CommandError, "#{plate} is not at a charger" unless v.spots.first.kind == 'EV'
      unpaid(v)
      raise CommandError, "charge limit exceeded for #{plate}" if v.energy + kwh > 100
      cost = kwh * @fees['KWH']
      v.energy += kwh
      v.charge_cost += cost
      emit('CHARGE', plate, 'kwh', kwh, 'cost', cost,
           'stay_kwh', v.energy, 'stay_cost', v.charge_cost)
    when 'VALIDATE'
      v = vehicle(plate)
      unpaid(v)
      minutes = a[1].to_i
      raise CommandError, "validation limit exceeded for #{plate}" if v.validation + minutes > 180
      v.validation += minutes
      emit('VALIDATE', plate, minutes, 'total', v.validation)
    when 'PASS'
      last = pass?(plate) ? @passes[plate] : date_of(@now) - 1
      @passes[plate] = last + a[1].to_i
      emit('PASS', plate, 'until', @passes[plate])
    when 'UNPASS'
      raise CommandError, "#{plate} has no pass" unless pass?(plate)
      @passes.delete(plate)
      emit('UNPASS', plate)
    when 'MOVE'
      v = vehicle(plate)
      raise CommandError, "bus #{plate} cannot be moved" if v.kind == 'BUS'
      s = spot(a[1])
      raise CommandError, "#{plate} is already at #{s.code}" if s.equal?(v.spots.first)
      raise CommandError, "spot #{s.code} is closed" if s.closed
      raise CommandError, "spot #{s.code} is occupied by #{s.vehicle.plate}" if s.vehicle
      raise CommandError, "#{v.kind} cannot use #{s.kind} spot #{s.code}" unless PREF[v.kind].include?(s.kind)
      move_vehicle(v, s)
      process_queue
    when 'REBALANCE'
      targets = @vehicles.values.reject { |v| v.kind == 'BUS' }.sort_by(&:order)
      moved = 0
      targets.each do |v|
        rank = PREF[v.kind].index(v.spots.first.kind)
        next if rank.zero?
        spots = assignment(v.kind)
        if spots && PREF[v.kind].index(spots.first.kind) < rank
          move_vehicle(v, spots.first)
          moved += 1
        end
      end
      emit('REBALANCE', moved)
      process_queue
    when 'WHERE'
      v = @vehicles[plate]
      position = @queue.index { |w| w.plate == plate }
      if v
        emit('WHERE', plate, v.location, v.kind, stamp(v.entered),
             'stay', duration(@now - v.entered) + annotation(v))
      elsif position
        emit('WHERE', plate, 'waiting', position + 1)
      elsif @history.key?(plate)
        emit('WHERE', plate, 'gone', stamp(@history[plate].last[:exited]))
      else
        raise CommandError, "unknown plate #{plate}"
      end
    when 'LIST', 'OVERSTAY'
      level = a.empty? ? nil : a[0].to_i
      raise CommandError, "unknown level #{level}" if cmd == 'LIST' && level && level > @levels.length
      targets = @vehicles.values.select do |v|
        cmd == 'LIST' ? level.nil? || v.spots.first.level == level : @now - v.entered >= level * 60
      end
      targets.sort_by! { |v| cmd == 'LIST' ? v.order : [v.entered, *v.order] }
      cmd == 'LIST' ? emit('LIST', targets.length) : emit('OVERSTAY', level, targets.length)
      targets.each do |v|
        if cmd == 'LIST'
          emit(v.location, v.plate, v.kind, stamp(v.entered) + annotation(v))
        else
          emit(v.location, v.plate, v.kind, stamp(v.entered), 'stay', duration(@now - v.entered))
        end
      end
    when 'MAP'
      emit('MAP', @levels.length)
      @levels.each_with_index do |level, i|
        symbols = level.map { |s| s.closed ? '#' : s.vehicle ? s.kind[0] : s.kind[0].downcase }.join
        emit("L#{i + 1}", *symbols.scan(/.{1,10}/))
      end
    when 'OCCUPANCY'
      emit('OCCUPANCY', 'vehicles', @vehicles.length, 'waiting', @queue.length)
      all_used = KINDS.to_h { |k| [k, 0] }
      all_available = all_used.dup
      all_closed = 0
      @levels.each_with_index do |level, i|
        used = KINDS.to_h { |k| [k, 0] }
        available = used.dup
        closed = 0
        level.each do |s|
          if s.closed
            closed += 1
          else
            available[s.kind] += 1
          end
          used[s.kind] += 1 if s.vehicle
        end
        parts = ["L#{i + 1}"]
        KINDS.each do |k|
          parts.push(k, "#{used[k]}/#{available[k]}")
          all_used[k] += used[k]
          all_available[k] += available[k]
        end
        emit(*parts, 'closed', closed)
        all_closed += closed
      end
      parts = ['TOTAL']
      KINDS.each { |k| parts.push(k, "#{all_used[k]}/#{all_available[k]}") }
      q = all_available.values.sum.zero? ? 0 : all_used.values.sum * 1000 / all_available.values.sum
      emit(*parts, 'closed', all_closed, 'rate', "#{q / 10}.#{q % 10}%")
    when 'SIGN'
      parts = ['SIGN']
      TYPES.each do |kind|
        count = 0
        if kind == 'BUS'
          @levels.each do |level|
            run = 0
            level.each do |s|
              if s.kind == 'LARGE' && s.free?
                run += 1
              else
                count += run / 3
                run = 0
              end
            end
            count += run / 3
          end
        else
          count = @spots.count { |s| s.free? && PREF[kind].include?(s.kind) }
        end
        parts.push(kind, count.zero? ? 'FULL' : count)
      end
      emit(*parts)
    when 'RATES'
      emit('RATES')
      TYPES.each { |kind| emit(kind, *@rates[kind]) }
      emit('NIGHT', @fees['NIGHT'], 'LOST', @fees['LOST'], 'KWH', @fees['KWH'])
    when 'PASSES'
      plates = @passes.keys.select { |p| pass?(p) }.sort
      emit('PASSES', plates.length)
      plates.each do |p|
        parts = [p, 'until', @passes[p]]
        parts << 'IN' if @vehicles.key?(p)
        emit(*parts)
      end
    when 'HISTORY'
      records = @history[plate]
      raise CommandError, "no history for #{plate}" unless records
      emit('HISTORY', plate, 'visits', records.length, 'paid', records.sum { |r| r[:total] })
      records.each do |r|
        parts = [stamp(r[:entered]), stamp(r[:exited]), r[:location], r[:kind], r[:total]]
        parts << 'LOST' if r[:lost]
        emit(*parts)
      end
    when 'REVENUE'
      emit('REVENUE')
      TYPES.each { |kind| revenue_line(kind, @totals[kind]) }
      revenue_line('TOTAL', sum_totals(@totals.values))
    when 'DAILY'
      day = a[0].to_i
      totals = @daily.fetch(day) { empty_types }
      daily_line(['DAILY', day], sum_totals(totals.values))
      TYPES.each { |kind| daily_line([kind], totals[kind]) }
    when 'STATS'
      emit('STATS', 'parked', @vehicles.length, 'peak', @peak, 'at', @peak_time ? stamp(@peak_time) : '-')
      TYPES.each { |kind| stats_line(kind, @totals[kind]) }
      stats_line('ALL', sum_totals(@totals.values))
    end
  end

  def execute(line)
    day, clock, cmd, *args = line.split
    hour, minute = clock.split(':').map(&:to_i)
    @now = (day.to_i - 1) * 1440 + hour * 60 + minute
    give_up
    begin
      command(cmd, args)
    rescue CommandError => error
      emit('ERROR', error.message)
    end
  end
end

garage = Garage.new
STDIN.gets.to_i.times { garage.execute(STDIN.gets.chomp) }
STDOUT.write(garage.output.join("\n") + "\n")
