require "set"

class Invalid < StandardError
end

class BookingSystem
  CLASSES = %w[F J Y].freeze
  TIERS = %w[PLATINUM GOLD SILVER NONE].freeze

  def initialize
    @models = {}
    @flights = {}
    @bookings = {}
    @tiers = {}
    @used = Set.new
    @defining = nil
    @serial = 0
  end

  def fail_with(message)
    raise Invalid, message
  end

  def tier(name)
    @tiers.fetch(name, "NONE")
  end

  def passengers(flight)
    flight[:bookings].flat_map { |booking| booking[:passengers] }
  end

  def get_flight(name, open = false)
    flight = @flights[name]
    fail_with("unknown flight #{name}") unless flight
    fail_with("flight #{name} is closed") if open && flight[:closed]
    flight
  end

  def get_booking(pnr, open = false)
    booking = @bookings[pnr]
    fail_with("unknown PNR #{pnr}") if !booking || booking[:passengers].empty?
    get_flight(booking[:flight], open)
    booking
  end

  def get_passenger(pnr, name, open = true)
    booking = get_booking(pnr, open)
    person = booking[:passengers].find { |passenger| passenger[:name] == name }
    fail_with("no passenger #{name} in #{pnr}") unless person
    person
  end

  def cabin(flight, name)
    value = flight[:model][:cabins][name]
    fail_with("no cabin #{name} on #{flight[:name]}") unless value
    value
  end

  def booked(flight, cabin)
    passengers(flight).count { |person| person[:type] != "INFANT" && person[:cabin] == cabin }
  end

  def display(person)
    person[:type] == "INFANT" ? "LAP" : person[:seat] || "UNASSIGNED"
  end

  def load_factor(seated, seats)
    value = (seated * 1000).div(seats)
    "#{value.div(10)}.#{value % 10}%"
  end

  def fits?(flight, people, seats, desired = nil, vacated = [])
    ignored = people + vacated
    existing = passengers(flight).select { |person| person[:seat] && !ignored.include?(person) }
    occupied = existing.map { |person| person[:seat] }.to_set
    infants = Set.new
    existing.select { |person| person[:infant] }.each do |person|
      seat = flight[:model][:seats][person[:seat]]
      infants << [seat[:row], seat[:block]]
    end
    people.each_with_index do |person, i|
      seat = flight[:model][:seats][seats[i]]
      return false if !seat || seat[:cabin] != (desired || person[:cabin])
      return false if flight[:blocked].include?(seat[:id]) || occupied.include?(seat[:id])
      if (person[:type] == "CHILD" || person[:infant]) && flight[:model][:exits].include?(seat[:row])
        return false
      end
      key = [seat[:row], seat[:block]]
      return false if person[:infant] && infants.include?(key)
      infants << key if person[:infant]
      occupied << seat[:id]
    end
    true
  end

  def choose(flight, person, desired = person[:cabin])
    candidates = cabin(flight, desired)[:seats].select { |seat| fits?(flight, [person], [seat], desired) }
    candidates.find { |seat| flight[:model][:seats][seat][:kind] == person[:pref] } || candidates[0]
  end

  def reassign(flight)
    output = []
    passengers(flight).each do |person|
      next if person[:type] == "INFANT" || person[:seat]
      seat = choose(flight, person)
      if seat
        person[:seat] = seat
        output << "REASSIGNED #{person[:pnr]} #{person[:name]} #{seat}"
      end
    end
    output
  end

  def assign(flight, people, cabin_name)
    if people.length == 1
      people[0][:seat] = choose(flight, people[0])
      return "SINGLE"
    end
    cabin = cabin(flight, cabin_name)
    k = people.length
    adopt = lambda do |seats|
      next false unless fits?(flight, people, seats)
      people.each_with_index { |person, i| person[:seat] = seats[i] }
      true
    end
    %w[BLOCK ROW].each do |stage|
      (cabin[:start]..cabin[:end]).each do |row|
        blocks = stage == "BLOCK" ? cabin[:blocks] : [cabin[:blocks].join]
        blocks.each do |block|
          (0..block.length - k).each do |start|
            seats = block[start, k].chars.map { |letter| "#{row}#{letter}" }
            return stage if adopt.call(seats)
          end
        end
      end
    end
    (2..k).each do |h|
      width = (k + h - 1).div(h)
      height = (k + width - 1).div(width)
      (cabin[:start]..cabin[:end] - height + 1).each do |row|
        cabin[:blocks].each do |block|
          (0..block.length - width).each do |start|
            seats = Array.new(k) { |j| "#{row + j.div(width)}#{block[start + j % width]}" }
            return "STACK" if adopt.call(seats)
          end
        end
      end
    end
    people.each { |person| person[:seat] = choose(flight, person) }
    "SPLIT"
  end

  def targets(person)
    @bookings[person[:pnr]][:passengers].select do |other|
      other.equal?(person) || other[:name] == person[:infant]
    end
  end

  def remove(flight, removed)
    removed.each do |person|
      next unless person[:type] == "INFANT"
      adult = @bookings[person[:pnr]][:passengers].find { |other| other[:name] == person[:adult] }
      adult[:infant] = nil if adult
    end
    flight[:bookings].each do |booking|
      booking[:passengers] = booking[:passengers].reject { |person| removed.include?(person) }
    end
    flight[:volunteers].reject! { |person| removed.include?(person) }
  end

  def define(name, args)
    if name == "AIRCRAFT"
      @defining = {
        name: args[0], base: args[1].to_i, limit: args[2].to_i,
        cabins: {}, seats: {}, exits: Set.new, blocked: Set.new
      }
      return []
    end
    model = @defining
    case name
    when "CABIN"
      blocks = args.drop(3)
      start = args[1].to_i
      ending = args[2].to_i
      seats = []
      (start..ending).each do |row|
        blocks.each_with_index do |block, block_index|
          block.chars.each_with_index do |letter, i|
            window = (block_index.zero? && i.zero?) || (block_index == blocks.length - 1 && i == block.length - 1)
            kind = window ? "W" : (i.zero? || i == block.length - 1 ? "A" : "M")
            id = "#{row}#{letter}"
            seats << id
            model[:seats][id] = { id: id, row: row, letter: letter, block: block_index, kind: kind, cabin: args[0] }
          end
        end
      end
      model[:cabins][args[0]] = { start: start, end: ending, blocks: blocks, seats: seats }
    when "EXIT"
      model[:exits] = args.map(&:to_i).to_set
    when "BLOCKED"
      model[:blocked] = args.to_set
    when "END"
      @models[model[:name]] = model
      @defining = nil
      counts = CLASSES.select { |item| model[:cabins].key?(item) }.map do |item|
        count = model[:cabins][item][:seats].count { |seat| !model[:blocked].include?(seat) }
        "#{item} #{count}"
      end
      return ["AIRCRAFT #{model[:name]} " + counts.join(" ")]
    end
    []
  end

  def book(args)
    pnr, flight_name, cabin_name = args[0, 3]
    fail_with("duplicate PNR #{pnr}") if @used.include?(pnr)
    flight = get_flight(flight_name, true)
    cabin(flight, cabin_name)
    people = args.drop(3).each_with_index.map do |token, i|
      name, type, pref = token.split(":")
      {
        name: name, type: type, pref: pref, cabin: cabin_name, seat: nil,
        infant: nil, adult: nil, pnr: pnr, order: @serial * 10 + i
      }
    end
    seen = Set.new
    people.each do |person|
      fail_with("duplicate name #{person[:name]} in #{pnr}") if seen.include?(person[:name])
      seen << person[:name]
    end
    existing = passengers(flight).map { |person| person[:name] }.to_set
    people.each do |person|
      fail_with("#{person[:name]} already on #{flight_name}") if existing.include?(person[:name])
    end
    adults = people.select { |person| person[:type] == "ADULT" }
    infants = people.select { |person| person[:type] == "INFANT" }
    fail_with("no adult in #{pnr}") if adults.empty?
    fail_with("too many infants in #{pnr}") if infants.length > adults.length
    seated = people.reject { |person| person[:type] == "INFANT" }
    if booked(flight, cabin_name) + seated.length > flight[:limits][cabin_name]
      fail_with("limit exceeded for #{flight_name} #{cabin_name}")
    end
    infants.each_with_index do |infant, i|
      infant[:adult] = adults[i][:name]
      adults[i][:infant] = infant[:name]
    end
    booking = { pnr: pnr, flight: flight_name, passengers: people, checked: false }
    @serial += 1
    @bookings[pnr] = booking
    flight[:bookings] << booking
    @used << pnr
    method = assign(flight, seated, cabin_name)
    items = people.map { |person| "#{person[:name]}:#{display(person)}" }.join(" ")
    ["BOOKED #{pnr} #{flight_name} #{cabin_name} #{method} #{items}"]
  end

  def close(flight)
    output = []
    flight[:bookings].each do |booking|
      next if booking[:passengers].empty? || booking[:checked]
      output << "NOSHOW #{booking[:pnr]} #{booking[:passengers].length}"
      remove(flight, booking[:passengers].dup)
    end
    output.concat(reassign(flight))
    count = 0
    total = 0
    compensation = { "F" => 500, "J" => 300, "Y" => 150 }
    deny = lambda do |person, voluntary|
      value = compensation[person[:cabin]] * (voluntary ? 1 : 2)
      value = value.div(2) if person[:type] == "CHILD"
      output << "DENIED #{voluntary ? 'VOLUNTARY' : 'INVOLUNTARY'} #{person[:pnr]} #{person[:name]} #{person[:cabin]} #{value}"
      count += 1
      total += value
      remove(flight, targets(person))
    end
    CLASSES.select { |item| flight[:model][:cabins].key?(item) }.each do |item|
      volunteers = flight[:volunteers].select { |person| person[:seat] && person[:cabin] == item }
      volunteers.each do |volunteer|
        candidates = passengers(flight).select do |person|
          person[:type] != "INFANT" && !person[:seat] && person[:cabin] == item
        end
        if candidates.any? { |person| fits?(flight, [person], [volunteer[:seat]], nil, [volunteer]) }
          deny.call(volunteer, true)
          output.concat(reassign(flight))
        end
      end
    end
    unassigned = passengers(flight).select { |person| person[:type] != "INFANT" && !person[:seat] }
    unassigned.each { |person| deny.call(person, false) }
    flight[:closed] = true
    output << "CLOSED #{flight[:name]} denied #{count} compensation #{total}"
    output
  end

  def command(line)
    name, *args = line.split(" ")
    return define(name, args) if %w[AIRCRAFT CABIN EXIT BLOCKED END].include?(name)
    if name == "FLIGHT"
      fail_with("duplicate flight #{args[0]}") if @flights.key?(args[0])
      model = @models[args[1]]
      fail_with("unknown aircraft #{args[1]}") unless model
      limits = {}
      items = []
      CLASSES.select { |item| model[:cabins].key?(item) }.each do |item|
        count = model[:cabins][item][:seats].count { |seat| !model[:blocked].include?(seat) }
        limit = (count * (100 + args[2].to_i)).div(100)
        limits[item] = limit
        items << "#{item} #{count}/#{limit}"
      end
      @flights[args[0]] = {
        name: args[0], model: model, blocked: model[:blocked].dup, limits: limits,
        closed: false, bookings: [], volunteers: []
      }
      return ["FLIGHT #{args[0]} #{model[:name]} " + items.join(" ")]
    end
    return book(args) if name == "BOOK"
    if name == "STATUS"
      @tiers[args[0]] = args[1]
      return ["STATUS " + args.join(" ")]
    end
    if name == "FIND"
      items = []
      @flights.each_value do |flight|
        person = passengers(flight).find { |passenger| passenger[:name] == args[0] }
        if person
          items << "#{flight[:name]} #{person[:pnr]} #{person[:cabin]} #{display(person)} #{flight[:closed] ? 'CLOSED' : 'OPEN'}"
        end
      end
      return ["FIND #{args[0]} #{tier(args[0])} #{items.length}", *items]
    end
    if name == "INFO"
      booking = get_booking(args[0])
      items = booking[:passengers].map { |person| "#{person[:name]} #{person[:type]} #{person[:cabin]} #{display(person)}" }
      return ["INFO #{booking[:pnr]} #{booking[:flight]} #{items.length} #{booking[:checked] ? 'CHECKED' : 'NOT-CHECKED'}", *items]
    end
    if %w[SEAT SWAP CANCEL CHECKIN VOLUNTEER].include?(name)
      booking = get_booking(args[0], true)
      flight = get_flight(booking[:flight])
      if name == "CHECKIN"
        fail_with("#{booking[:pnr]} already checked in") if booking[:checked]
        booking[:checked] = true
        return ["CHECKIN #{booking[:pnr]} #{booking[:passengers].length}"]
      end
      if name == "CANCEL"
        removed = args.length == 1 ? booking[:passengers].dup : targets(get_passenger(args[0], args[1]))
        remaining = booking[:passengers].reject { |person| removed.include?(person) }
        if args.length == 2 && !remaining.empty? && remaining.none? { |person| person[:type] == "ADULT" }
          fail_with("#{booking[:pnr]} would have no adult")
        end
        output = ["CANCELLED #{booking[:pnr]} " + removed.map { |person| person[:name] }.join(" ")]
        remove(flight, removed)
        return output + reassign(flight)
      end
      person = get_passenger(args[0], args[1])
      if name == "SWAP"
        other = get_passenger(args[2], args[3])
        fail_with("cannot swap #{person[:name]} with itself") if person.equal?(other)
        [person, other].each do |passenger|
          fail_with("infant #{passenger[:name]} has no seat") if passenger[:type] == "INFANT"
        end
        if booking[:flight] != @bookings[other[:pnr]][:flight]
          fail_with("#{args[0]} and #{args[2]} are on different flights")
        end
        if person[:cabin] != other[:cabin]
          fail_with("#{person[:name]} and #{other[:name]} are in different cabins")
        end
        [person, other].each { |passenger| fail_with("#{passenger[:name]} has no seat") unless passenger[:seat] }
        unless fits?(flight, [person, other], [other[:seat], person[:seat]])
          fail_with("swap of #{person[:name]} and #{other[:name]} breaks seating rules")
        end
        person[:seat], other[:seat] = other[:seat], person[:seat]
        return ["SWAPPED #{person[:pnr]} #{person[:name]} #{person[:seat]} #{other[:pnr]} #{other[:name]} #{other[:seat]}", *reassign(flight)]
      end
      if name == "VOLUNTEER"
        fail_with("#{person[:name]} cannot volunteer") if person[:type] != "ADULT" || person[:infant]
        fail_with("#{person[:name]} has no seat") unless person[:seat]
        fail_with("#{person[:name]} already volunteered") if flight[:volunteers].include?(person)
        flight[:volunteers] << person
        return ["VOLUNTEER #{person[:pnr]} #{person[:name]} #{person[:seat]}"]
      end
      fail_with("infant #{person[:name]} has no seat") if person[:type] == "INFANT"
      seat = flight[:model][:seats][args[2]]
      fail_with("no seat #{args[2]} in cabin #{person[:cabin]}") if !seat || seat[:cabin] != person[:cabin]
      fail_with("seat #{seat[:id]} is blocked") if flight[:blocked].include?(seat[:id])
      fail_with("seat #{seat[:id]} is occupied") if passengers(flight).any? { |other| other[:seat] == seat[:id] }
      if (person[:type] == "CHILD" || person[:infant]) && flight[:model][:exits].include?(seat[:row])
        fail_with("exit row #{seat[:row]} not allowed for #{person[:name]}")
      end
      fail_with("infant limit reached at #{seat[:id]}") unless fits?(flight, [person], [seat[:id]])
      old = person[:seat]
      person[:seat] = seat[:id]
      return ["MOVED #{person[:pnr]} #{person[:name]} #{old} -> #{seat[:id]}", *reassign(flight)]
    end
    modifying = %w[UPGRADE CLOSE BLOCK UNBLOCK].include?(name)
    flight = get_flight(args[0], modifying)
    return close(flight) if name == "CLOSE"
    if name == "UPGRADE"
      cabins = CLASSES.select { |item| flight[:model][:cabins].key?(item) }
      output = []
      count = 0
      cabins.each_cons(2) do |higher, lower|
        targets = passengers(flight).select do |person|
          person[:cabin] == lower && person[:type] == "ADULT" && !person[:infant] && tier(person[:name]) != "NONE"
        end.sort_by { |person| [TIERS.index(tier(person[:name])), person[:order]] }
        targets.each do |person|
          break if booked(flight, higher) >= flight[:limits][higher]
          seat = choose(flight, person, higher)
          break unless seat
          old = person[:seat] || "UNASSIGNED"
          person[:cabin] = higher
          person[:seat] = seat
          output << "UPGRADED #{person[:pnr]} #{person[:name]} #{lower} #{old} -> #{higher} #{seat}"
          count += 1
        end
      end
      return output + reassign(flight) + ["UPGRADE #{flight[:name]} #{count}"]
    end
    if name == "BLOCK" || name == "UNBLOCK"
      seat = args[1]
      fail_with("no seat #{seat} on #{flight[:name]}") unless flight[:model][:seats].key?(seat)
      blocked = flight[:blocked].include?(seat)
      fail_with("seat #{seat} is blocked") if name == "BLOCK" && blocked
      fail_with("seat #{seat} is not blocked") if name == "UNBLOCK" && !blocked
      output = ["#{name} #{flight[:name]} #{seat}"]
      if name == "BLOCK"
        flight[:blocked] << seat
        person = passengers(flight).find { |passenger| passenger[:seat] == seat }
        if person
          person[:seat] = nil
          person[:seat] = choose(flight, person)
          output << "DISPLACED #{person[:pnr]} #{person[:name]} #{seat} -> #{person[:seat] || 'UNASSIGNED'}"
        end
      else
        flight[:blocked].delete(seat)
      end
      return output + reassign(flight)
    end
    inspect_flight(name, flight, args)
  end

  def inspect_flight(name, flight, args)
    people = passengers(flight)
    seated = people.select { |person| person[:seat] }.sort_by do |person|
      seat = flight[:model][:seats][person[:seat]]
      [seat[:row], seat[:letter]]
    end
    unassigned = people.select { |person| person[:type] != "INFANT" && !person[:seat] }
    cabins = CLASSES.select { |item| flight[:model][:cabins].key?(item) }
    if name == "MAP"
      occupied = seated.map { |person| person[:seat] }.to_set
      output = ["MAP #{flight[:name]}"]
      cabins.each do |item|
        cabin = flight[:model][:cabins][item]
        output.concat(["CABIN #{item}", "   " + cabin[:blocks].join(" ")])
        (cabin[:start]..cabin[:end]).each do |row|
          blocks = cabin[:blocks].map do |block|
            block.chars.map do |letter|
              id = "#{row}#{letter}"
              if flight[:blocked].include?(id)
                "#"
              elsif occupied.include?(id)
                "X"
              elsif flight[:model][:exits].include?(row)
                "E"
              else
                "."
              end
            end.join
          end
          output << row.to_s.rjust(2) + " " + blocks.join(" ")
        end
      end
      return output
    end
    if name == "AVAIL"
      cabin = cabin(flight, args[1])
      occupied = seated.map { |person| person[:seat] }.to_set
      free = cabin[:seats].reject { |seat| flight[:blocked].include?(seat) || occupied.include?(seat) }
                          .map { |seat| flight[:model][:seats][seat] }
      return ["AVAIL #{flight[:name]} #{args[1]} free #{free.length} W #{free.count { |seat| seat[:kind] == 'W' }} " +
              "M #{free.count { |seat| seat[:kind] == 'M' }} A #{free.count { |seat| seat[:kind] == 'A' }} " +
              "EXIT #{free.count { |seat| flight[:model][:exits].include?(seat[:row]) }}"]
    end
    if name == "MANIFEST"
      infants = people.count { |person| person[:type] == "INFANT" }
      output = ["MANIFEST #{flight[:name]} seated #{seated.length} unassigned #{unassigned.length} infants #{infants}"]
      (seated + unassigned).each do |person|
        line = "#{person[:seat] || '---'} #{person[:cabin]} #{person[:pnr]} #{person[:name]} #{person[:type]}"
        line += " +#{person[:infant]}" if person[:infant]
        line += " #{tier(person[:name])}" unless tier(person[:name]) == "NONE"
        line += " CHECKED" if @bookings[person[:pnr]][:checked]
        line += " VOL" if flight[:volunteers].include?(person)
        output << line
      end
      return output
    end
    if name == "LOADFACTOR"
      output = ["LOADFACTOR #{flight[:name]}"]
      total_seated = 0
      total_seats = 0
      cabins.each do |item|
        count = seated.count { |person| person[:cabin] == item }
        seats = flight[:model][:cabins][item][:seats].count { |seat| !flight[:blocked].include?(seat) }
        total_seated += count
        total_seats += seats
        output << "#{item} #{count}/#{seats} #{load_factor(count, seats)} booked #{booked(flight, item)}/#{flight[:limits][item]}"
      end
      output << "ALL #{total_seated}/#{total_seats} #{load_factor(total_seated, total_seats)}"
      return output
    end
    if name == "BALANCE"
      weight = 0
      moment = 0
      seated.each do |person|
        value = (person[:type] == "ADULT" ? 80 : 40) + (person[:infant] ? 10 : 0)
        weight += value
        moment += value * (flight[:model][:seats][person[:seat]][:row] - flight[:model][:base])
      end
      limit = flight[:model][:limit]
      verdict = moment < -limit ? "NOSE-HEAVY" : moment > limit ? "TAIL-HEAVY" : "OK"
      return ["BALANCE #{flight[:name]} weight #{weight} moment #{moment} limit #{limit} #{verdict}"]
    end
    entries = seated.map do |person|
      booking = @bookings[person[:pnr]]
      seat = flight[:model][:seats][person[:seat]]
      if booking[:passengers].any? { |passenger| passenger[:type] == "INFANT" }
        group = "PRE"
        key = [0, seat[:row], seat[:letter]]
      elsif person[:cabin] != "Y"
        group = "CABIN"
        key = [1, seat[:row], seat[:letter]]
      elsif %w[PLATINUM GOLD].include?(tier(person[:name]))
        group = "TIER"
        key = [2, seat[:row], seat[:letter]]
      else
        zone = (seat[:row] - flight[:model][:cabins]["Y"][:start]).div(5) + 1
        group = "ZONE#{zone}"
        key = [3, -zone, %w[W M A].index(seat[:kind]), -seat[:row], seat[:letter]]
      end
      { person: person, group: group, key: key }
    end.sort_by { |entry| entry[:key] }
    output = ["BOARDING #{flight[:name]} #{entries.length}"]
    entries.each_with_index do |entry, i|
      person = entry[:person]
      output << "#{i + 1} #{entry[:group]} #{person[:seat]} #{person[:pnr]} #{person[:name]}"
    end
    output
  end
end

lines = STDIN.read.split("\n")
system = BookingSystem.new
output = []
lines[0].to_i.times do |i|
  begin
    output.concat(system.command(lines[i + 1]))
  rescue Invalid => error
    output << "ERROR " + error.message
  end
end
STDOUT.write(output.join("\n") + "\n") unless output.empty?
