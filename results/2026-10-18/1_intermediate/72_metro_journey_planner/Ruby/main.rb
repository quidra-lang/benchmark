require 'set'

Station = Struct.new(:zone, :name, :transfer, :closed)
MetroLine = Struct.new(:id, :first, :last, :headway, :stops, :offsets, :delay, :suspended) do
  def trips
    (last - first) / headway + 1
  end

  def duration
    offsets.last
  end

  def directions
    [[stops, offsets], [stops.reverse, offsets.reverse.map { |c| duration - c }]]
  end

  def next_train(offset, ready)
    q = [0, (ready - first - delay - offset + headway - 1) / headway].max
    q < trips ? q : nil
  end

  def time(q, offset)
    first + delay + q * headway + offset
  end
end

class MetroError < StandardError; end

class Metro
  def initialize
    @stations = {}
    @lines = {}
    @walks = {}
    @closed = Set.new
    @tariff = nil
  end

  def minutes(text)
    hour, minute = text.split(':').map(&:to_i)
    hour * 60 + minute
  end

  def clock(value)
    format('%02d:%02d', value / 60, value % 60)
  end

  def segment(a, b)
    [a, b].sort
  end

  def blocked?(a, b)
    @closed.include?(segment(a, b))
  end

  def station_check(id)
    raise MetroError, "unknown station #{id}" unless @stations.key?(id)
  end

  def line_check(id)
    raise MetroError, "unknown line #{id}" unless @lines.key?(id)
  end

  def open_check(id)
    raise MetroError, "station #{id} is closed" if @stations[id].closed
  end

  def journey_check(origin, destination)
    station_check(origin)
    station_check(destination)
    raise MetroError, 'origin and destination are the same' if origin == destination
    open_check(origin)
    open_check(destination)
  end

  def running_lines
    @lines.keys.sort.map { |id| @lines[id] }.reject(&:suspended)
  end

  def update(labels, destination, time, journey)
    return false if labels.key?(destination) && labels[destination][0] <= time
    labels[destination] = [time, journey]
    true
  end

  def earliest(origin, departure)
    labels = { origin => [departure, []] }
    settled = Set.new
    lines = running_lines
    loop do
      u = (labels.keys - settled.to_a).min_by { |id| [labels[id][0], id] }
      break unless u
      settled << u
      arrival, journey = labels[u]
      ready = arrival + (u == origin ? 0 : @stations[u].transfer)
      lines.each do |line|
        next unless line.stops.include?(u)
        line.directions.each do |stops, offsets|
          i = stops.index(u)
          next if i == stops.length - 1
          q = line.next_train(offsets[i], ready)
          next unless q
          boarding = line.time(q, offsets[i])
          ((i + 1)...stops.length).each do |j|
            break if blocked?(stops[j - 1], stops[j])
            next if @stations[stops[j]].closed
            time = line.time(q, offsets[j])
            leg = [:ride, line.id, stops.last, u, boarding, stops[j], time, j - i]
            update(labels, stops[j], time, journey + [leg])
          end
        end
      end
      @walks[u].keys.sort.each do |v|
        time = arrival + @walks[u][v]
        next if @stations[v].closed || time > 1440
        update(labels, v, time, journey + [[:walk, u, arrival, v, time]])
      end
    end
    labels
  end

  def walk_step(labels, selected, marked)
    snapshot = selected.to_a.sort.to_h { |u| [u, labels[u]] }
    snapshot.each do |u, (arrival, journey)|
      @walks[u].keys.sort.each do |v|
        time = arrival + @walks[u][v]
        next if @stations[v].closed || time > 1440
        marked << v if update(labels, v, time, journey + [[:walk, u, arrival, v, time]])
      end
    end
  end

  def rounds(origin, departure)
    labels = { origin => [departure, []] }
    marked = Set[origin]
    walk_step(labels, Set[origin], marked)
    result = [labels]
    lines = running_lines
    until marked.empty?
      previous = labels
      previous_marked = marked
      labels = previous.dup
      marked = Set.new
      selected = Set.new
      lines.each do |line|
        line.directions.each do |stops, offsets|
          boarded = nil
          b = nil
          boarding = nil
          journey = nil
          stops.each_with_index do |u, j|
            boarded = nil if j.positive? && blocked?(stops[j - 1], u)
            next if @stations[u].closed
            if boarded
              time = line.time(boarded, offsets[j])
              leg = [:ride, line.id, stops.last, stops[b], boarding, u, time, j - b]
              if update(labels, u, time, journey + [leg])
                selected << u
                marked << u
              end
            end
            next if j == stops.length - 1 || !previous_marked.include?(u)
            arrival, candidate_journey = previous[u]
            ready = arrival + (u == origin ? 0 : @stations[u].transfer)
            candidate = line.next_train(offsets[j], ready)
            if candidate && (boarded.nil? || candidate < boarded)
              boarded = candidate
              b = j
              boarding = line.time(candidate, offsets[j])
              journey = candidate_journey
            end
          end
        end
      end
      walk_step(labels, selected, marked)
      result << labels
    end
    result
  end

  def print_journey(heading, departure, label)
    arrival, journey = label
    rides = journey.count { |leg| leg[0] == :ride }
    walks = journey.count { |leg| leg[0] == :walk }
    puts "#{heading} #{clock(departure)} -> #{clock(arrival)} total #{arrival - departure} rides #{rides} walks #{walks}"
    previous_end = departure
    journey.each do |leg|
      case leg[0]
      when :ride
        _, line, toward, from, start, to, finish, count = leg
        puts "RIDE #{line} toward #{toward} #{from} #{clock(start)} -> #{to} #{clock(finish)} wait #{start - previous_end} stops #{count}"
        previous_end = finish
      when :walk
        _, from, start, to, finish = leg
        puts "WALK #{from} #{clock(start)} -> #{to} #{clock(finish)}"
        previous_end = finish
      when :stay
        _, station, start, finish = leg
        puts "STAY #{station} #{clock(start)} -> #{clock(finish)}"
        previous_end = finish
      end
    end
  end

  def print_fare(origin, destination, time_text, fare_class, journey)
    discount_cap, window, prices = @tariff
    half = ->(x) { (x + 19) / 20 * 10 }
    cap = fare_class == 'CHILD' ? half.call(discount_cap) : discount_cap
    tickets = []
    previous_end = nil
    journey.each do |leg|
      next unless leg[0] == :ride
      _, line_id, toward, from, boarding, to, arrival, = leg
      line = @lines[line_id]
      stops = line.directions.find { |sequence, _| sequence.last == toward }[0]
      zones = stops[stops.index(from)..stops.index(to)].map { |id| @stations[id].zone }.uniq.length
      price = prices[[zones, prices.length].min - 1]
      price = half.call(price) if fare_class == 'CHILD'
      discount = previous_end && boarding - previous_end <= window ? [cap, price].min : 0
      tickets << [line_id, from, to, zones, price, discount, price - discount]
      previous_end = arrival
    end
    puts "FARE #{origin} #{destination} #{time_text} #{fare_class} rides #{tickets.length} total #{tickets.sum { |t| t[6] }}"
    tickets.each do |line, from, to, zones, price, discount, pay|
      puts "TICKET #{line} #{from} #{to} zones #{zones} price #{price} discount #{discount} pay #{pay}"
    end
  end

  def search_command(command, args)
    origin, destination = args
    journey_check(origin, destination)
    departure = minutes(args[2]) if args[2]
    if command == 'FARE'
      raise MetroError, "unknown fare class #{args[3]}" unless %w[ADULT CHILD].include?(args[3])
      raise MetroError, 'no tariff' unless @tariff
    elsif command == 'PROFILE' && departure > minutes(args[3])
      raise MetroError, "empty interval #{args[2]} #{args[3]}"
    end
    case command
    when 'ROUTE', 'FARE'
      label = earliest(origin, departure)[destination]
      if label
        if command == 'ROUTE'
          print_journey("ROUTE #{origin} #{destination}", departure, label)
        else
          print_fare(origin, destination, args[2], args[3], label[1])
        end
      else
        puts "#{command} #{args.join(' ')} unreachable"
      end
    when 'FEWEST', 'PARETO'
      all = rounds(origin, departure)
      if command == 'FEWEST'
        k = all.index { |labels| labels.key?(destination) }
        if k
          print_journey("FEWEST #{origin} #{destination} trips #{k}", departure, all[k][destination])
        else
          puts "FEWEST #{args.join(' ')} unreachable"
        end
      else
        options = all.each_index.select do |k|
          all[k].key?(destination) && (k.zero? || !all[k - 1].key?(destination) || all[k][destination][0] < all[k - 1][destination][0])
        end
        puts "PARETO #{args.join(' ')} options #{options.length}"
        options.each { |k| print_journey("OPTION trips #{k}", departure, all[k][destination]) }
      end
    when 'LASTTRAIN', 'ARRIVEBY'
      start = command == 'LASTTRAIN' ? 1439 : departure - 1
      heading = "#{command} #{origin} #{destination}"
      heading += " by #{args[2]}" if command == 'ARRIVEBY'
      start.downto(0) do |time|
        label = earliest(origin, time)[destination]
        next unless label && (command == 'LASTTRAIN' || label[0] <= departure)
        print_journey(heading, time, label)
        return
      end
      puts "#{heading} none"
    when 'PROFILE'
      finish = minutes(args[3])
      arrivals = (departure..finish).to_h { |t| [t, earliest(origin, t)[destination]&.first] }
      selected = (departure..finish).select do |t|
        arrivals[t] && (t == finish || !arrivals[t + 1] || arrivals[t] < arrivals[t + 1])
      end
      puts "PROFILE #{args.join(' ')} count #{selected.length}"
      selected.each { |t| puts "#{clock(t)} -> #{clock(arrivals[t])} total #{arrivals[t] - t}" }
    end
  end

  def execute(line)
    command, *args = line.split(' ')
    a, b = args
    case command
    when 'STATION'
      raise MetroError, "station #{a} already exists" if @stations.key?(a)
      @stations[a] = Station.new(b.to_i, args[2], 0, false)
      @walks[a] = {}
      puts "STATION #{a} zone #{b} #{args[2]}"
    when 'LINE'
      raise MetroError, "line #{a} already exists" if @lines.key?(a)
      stops = args.drop(4).each_slice(2).map(&:first)
      stops.each { |id| station_check(id) }
      seen = Set.new
      stops.each do |id|
        raise MetroError, "station #{id} appears twice on line #{a}" if seen.include?(id)
        seen << id
      end
      first = minutes(b)
      last = minutes(args[2])
      raise MetroError, "line #{a} first departure is after last departure" if first > last
      offsets = [0]
      args.drop(5).each_slice(2) { |duration, _| offsets << offsets.last + duration.to_i }
      raise MetroError, "line #{a} runs past 24:00" if last + offsets.last > 1440
      service = MetroLine.new(a, first, last, args[3].to_i, stops, offsets, 0, false)
      @lines[a] = service
      puts "LINE #{a} stops #{stops.length} time #{service.duration} trips #{service.trips}"
    when 'TRANSFER'
      station_check(a)
      @stations[a].transfer = b.to_i
      puts "TRANSFER #{a} #{b}"
    when 'WALK'
      station_check(a)
      station_check(b)
      raise MetroError, "walk from #{a} to itself" if a == b
      old = @walks[a][b]
      @walks[a][b] = @walks[b][a] = args[2].to_i
      puts "WALK #{args.join(' ')}#{old ? " was #{old}" : ''}"
    when 'TARIFF'
      prices = args.drop(2).map(&:to_i)
      raise MetroError, 'tariff prices must not decrease' if prices.each_cons(2).any? { |x, y| x > y }
      @tariff = [a.to_i, b.to_i, prices]
      puts "TARIFF zones #{prices.length} discount #{a} window #{b}"
    when 'CLOSE', 'OPEN'
      station_check(a)
      if b
        station_check(b)
        key = segment(a, b)
        if command == 'CLOSE'
          affected = @lines.keys.sort.select { |id| @lines[id].stops.each_cons(2).any? { |x, y| segment(x, y) == key } }
          raise MetroError, "no segment #{a}-#{b}" if affected.empty?
          raise MetroError, "segment #{a}-#{b} is already closed" if @closed.include?(key)
          @closed << key
          puts "CLOSE #{a}-#{b} lines #{affected.join(' ')}"
        else
          raise MetroError, "segment #{a}-#{b} is not closed" unless @closed.include?(key)
          @closed.delete(key)
          puts "OPEN #{a}-#{b}"
        end
      else
        current = @stations[a].closed
        if command == 'CLOSE' && current
          raise MetroError, "station #{a} is already closed"
        elsif command == 'OPEN' && !current
          raise MetroError, "station #{a} is not closed"
        end
        @stations[a].closed = command == 'CLOSE'
        puts "#{command} #{a}"
      end
    when 'DELAY'
      line_check(a)
      raise MetroError, "line #{a} runs past 24:00" if @lines[a].last + b.to_i + @lines[a].duration > 1440
      @lines[a].delay = b.to_i
      puts "DELAY #{a} #{b}"
    when 'SUSPEND', 'RESUME'
      line_check(a)
      if command == 'SUSPEND' && @lines[a].suspended
        raise MetroError, "line #{a} is already suspended"
      elsif command == 'RESUME' && !@lines[a].suspended
        raise MetroError, "line #{a} is not suspended"
      end
      @lines[a].suspended = command == 'SUSPEND'
      puts "#{command} #{a}"
    when 'ROUTE', 'FEWEST', 'PARETO', 'FARE', 'LASTTRAIN', 'ARRIVEBY', 'PROFILE'
      search_command(command, args)
    when 'VIA'
      origin, via, destination, time_text = args
      [origin, via, destination].each { |id| station_check(id) }
      raise MetroError, 'origin and destination are the same' if origin == destination
      if via == origin || via == destination
        raise MetroError, "via station #{via} must differ from origin and destination"
      end
      [origin, via, destination].each { |id| open_check(id) }
      departure = minutes(time_text)
      first = earliest(origin, departure)[via]
      if first
        ready = first[0] + @stations[via].transfer
        second = earliest(via, ready)[destination]
      end
      if first && second
        journey = first[1] + [[:stay, via, first[0], ready]] + second[1]
        print_journey("VIA #{origin} #{via} #{destination}", departure, [second[0], journey])
      else
        puts "VIA #{args.join(' ')} unreachable"
      end
    when 'REACH'
      station_check(a)
      open_check(a)
      departure = minutes(b)
      labels = earliest(a, departure)
      selected = labels.keys.select { |id| labels[id][0] <= departure + args[2].to_i }.sort_by { |id| [labels[id][0], id] }
      puts "REACH #{args.join(' ')} count #{selected.length}"
      selected.each do |id|
        arrival, journey = labels[id]
        puts "#{id} #{@stations[id].name} #{clock(arrival)} #{arrival - departure} rides #{journey.count { |leg| leg[0] == :ride }}"
      end
    when 'TIMETABLE'
      station_check(a)
      line_check(b)
      service = @lines[b]
      raise MetroError, "station #{a} is not on line #{b}" unless service.stops.include?(a)
      toward = args[2]
      direction = service.directions.find { |stops, _| stops.last == toward }
      raise MetroError, "#{toward} is not a terminal of line #{b}" unless direction
      raise MetroError, "no departures from #{a} toward #{toward}" if a == toward
      raise MetroError, "line #{b} is suspended" if service.suspended
      open_check(a)
      stops, offsets = direction
      offset = offsets[stops.index(a)]
      times = (0...service.trips).map { |q| service.time(q, offset) }.select { |t| t >= minutes(args[3]) }.take(args[4].to_i)
      puts "TIMETABLE #{a} #{b} toward #{toward} #{args[3]} next #{times.length}#{times.empty? ? '' : " #{times.map { |t| clock(t) }.join(' ')}"}"
    when 'DEPARTURES', 'ARRIVALS'
      station_check(a)
      open_check(a)
      entries = []
      running_lines.each do |service|
        next unless service.stops.include?(a)
        service.directions.each_with_index do |(stops, offsets), direction|
          i = stops.index(a)
          next if command == 'DEPARTURES' ? i == stops.length - 1 : i.zero?
          (0...service.trips).each do |q|
            time = service.time(q, offsets[i])
            entries << [time, service.id, direction, command == 'DEPARTURES' ? stops.last : stops.first] if time >= minutes(b)
          end
        end
      end
      entries = entries.sort.take(args[2].to_i)
      puts "#{command} #{a} #{b} count #{entries.length}"
      entries.each { |time, id, _, terminal| puts "#{clock(time)} #{id} #{command == 'DEPARTURES' ? 'toward' : 'from'} #{terminal}" }
    when 'TRIP'
      line_check(a)
      service = @lines[a]
      direction = service.directions.find { |stops, _| stops.last == b }
      raise MetroError, "#{b} is not a terminal of line #{a}" unless direction
      raise MetroError, "line #{a} is suspended" if service.suspended
      q = service.next_train(0, minutes(args[2]))
      if q
        stops, offsets = direction
        puts "TRIP #{a} toward #{b} #{args[2]} trip #{q + 1} departs #{clock(service.time(q, 0))}"
        stops.each_with_index do |id, i|
          suffix = @stations[id].closed ? ' closed' : ''
          suffix += ' blocked' if i.positive? && blocked?(stops[i - 1], id)
          puts "#{clock(service.time(q, offsets[i]))} #{id}#{suffix}"
        end
      else
        puts "TRIP #{a} toward #{b} #{args[2]} none"
      end
    when 'SHOWLINE'
      line_check(a)
      service = @lines[a]
      puts "SHOWLINE #{a} #{service.suspended ? 'suspended' : 'running'} first #{clock(service.first)} last #{clock(service.last)} headway #{service.headway} delay #{service.delay} trips #{service.trips}"
      service.stops.each_with_index do |id, i|
        suffix = @stations[id].closed ? ' closed' : ''
        suffix += ' blocked' if i.positive? && blocked?(service.stops[i - 1], id)
        puts "#{service.offsets[i]} #{id} zone #{@stations[id].zone}#{suffix}"
      end
    when 'INFO'
      station_check(a)
      station = @stations[a]
      puts "INFO #{a} #{station.name} zone #{station.zone} transfer #{station.transfer} #{station.closed ? 'closed' : 'open'}"
      lines = @lines.keys.sort.select { |id| @lines[id].stops.include?(a) }
      puts "LINES #{lines.empty? ? 'none' : lines.join(' ')}"
      neighbors = @walks[a].keys.sort
      puts "WALKS #{neighbors.empty? ? 'none' : neighbors.map { |v| "#{v} #{@walks[a][v]}" }.join(' ')}"
    when 'STATUS'
      puts "STATUS stations #{@stations.length} lines #{@lines.length} walks #{@walks.values.sum(&:length) / 2}"
      @stations.keys.sort.each { |id| puts "CLOSED #{id}" if @stations[id].closed }
      @closed.to_a.sort.each { |x, y| puts "CLOSED #{x}-#{y}" }
      @lines.keys.sort.each { |id| puts "SUSPENDED #{id}" if @lines[id].suspended }
      @lines.keys.sort.each { |id| puts "DELAYED #{id} #{@lines[id].delay}" unless @lines[id].delay.zero? }
    end
  rescue MetroError => error
    puts "ERROR #{error.message}"
  end
end

metro = Metro.new
count = STDIN.gets.to_i
count.times { metro.execute(STDIN.gets.chomp) }
