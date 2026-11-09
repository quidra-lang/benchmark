# frozen_string_literal: true

require_relative 'minstd'
require_relative 'road'
require_relative 'vehicles'
require_relative 'signals'
require_relative 'stats'

class TrafficSimulation
  Source = Struct.new(:node, :rates, :entry, :queue, :start, :maximum, keyword_init: true)
  Turn = Struct.new(:target, :weight, :vehicles, keyword_init: true)
  Stop = Struct.new(:segment, :cell, :dwell, :buses, keyword_init: true)
  Detector = Struct.new(:name, :segment, :cell, :width, :records, keyword_init: true)
  Diagram = Struct.new(:segment, :lane, :start, :finish, :rows, keyword_init: true)
  Ring = Struct.new(:length, :maximum, :warmup, :measured, :seed, :counts, keyword_init: true)
  Move = Struct.new(:vehicle, :segment, :cell, :old_speed, :speed, :crossing, keyword_init: true)

  def initialize
    @segments = []
    @segment_by_id = {}
    @junctions = []
    @junction_by_node = {}
    @incidents = []
    @stops = []
    @classes = []
    @sources = []
    @sinks = []
    @detectors = []
    @diagrams = []
    @rings = []
    @tracks = {}
    read_network
    read_demand
    read_parameters
    @generator = Minstd.new(@seed)
    @vehicles = []
    @events = []
    @intervals = []
    @route_lists = {}
  end

  def read_network
    File.foreach('input/network.txt') do |line|
      kind, *values = line.split
      case kind
      when 'SEGMENT'
        id, from, to, length, lanes, limit = values
        segment = Road::Segment.new(id, from, to, length.to_i, lanes.to_i, limit.to_i)
        @segments << segment
        @segment_by_id[id] = segment
      when 'JUNCTION'
        junction = Signals::Junction.new(values[0], values[1].to_i, values.drop(2))
        @junctions << junction
        @junction_by_node[junction.node] = junction
      when 'INCIDENT'
        segment = @segment_by_id.fetch(values[0])
        @incidents << Road::Incident.new(segment, *values.drop(1).map(&:to_i))
      when 'STOP'
        segment = @segment_by_id.fetch(values[0])
        stop = Stop.new(segment: segment, cell: values[1].to_i, dwell: values[2].to_i, buses: 0)
        segment.stop = stop
        @stops << stop
      end
    end
    @segments.each { |segment| segment.junction = @junction_by_node[segment.to] }
  end

  def read_demand
    File.foreach('input/demand.txt') do |line|
      kind, *values = line.split
      case kind
      when 'CLASS'
        name, maximum, weight, overtake, stop = values
        @classes << Vehicles::ClassInfo.new(name: name, vmax: maximum.to_i, weight: weight.to_i,
                                             overtake: overtake, stop: stop)
      when 'SOURCE'
        node = values[0]
        rates = values.drop(1).map { |token| token.split(':').map(&:to_i) }
        entry = @segments.find { |segment| segment.from == node }
        @sources << Source.new(node: node, rates: rates, entry: entry, queue: [], start: 0, maximum: 0)
      when 'SINK'
        @sinks << values[0]
      when 'TURN'
        turn = Turn.new(target: @segment_by_id.fetch(values[1]), weight: values[2].to_i, vehicles: 0)
        @segment_by_id.fetch(values[0]).turns << turn
      end
    end
    @class_weights = @classes.map(&:weight)
  end

  def read_parameters
    File.foreach('input/params.txt') do |line|
      kind, *values = line.split
      case kind
      when 'seed' then @seed = values[0].to_i
      when 'steps' then @steps = values[0].to_i
      when 'dawdle' then @dawdle, @stopped_dawdle = values.map(&:to_i)
      when 'interval' then @interval_length = values[0].to_i
      when 'bin' then @bin_width = values[0].to_i
      when 'detector'
        @detectors << Detector.new(name: values[0], segment: @segment_by_id.fetch(values[1]),
                                    cell: values[2].to_i, width: values[3].to_i, records: [])
      when 'diagram'
        @diagrams << Diagram.new(segment: @segment_by_id.fetch(values[0]), lane: values[1].to_i,
                                  start: values[2].to_i, finish: values[3].to_i, rows: [])
      when 'track'
        @track_numbers = values.map(&:to_i)
        @track_numbers.each { |number| @tracks[number] = [] }
      when 'ring'
        length, maximum, warmup, measured, seed = values.first(5).map(&:to_i)
        @rings << Ring.new(length: length, maximum: maximum, warmup: warmup, measured: measured,
                           seed: seed, counts: values.drop(5).map(&:to_i))
      end
    end
  end

  def time(step)
    format('%04d', step)
  end

  def update_incidents(step)
    @incidents.each do |incident|
      kind = incident.update(step)
      next unless kind

      @events << "#{time(step)} #{kind} #{incident.segment.id} lane #{incident.lane} cell #{incident.cell}"
    end
  end

  def start_interval
    @current = {arrivals: 0, insertions: 0, exits: 0, vehicle_steps: 0, speed_sum: 0}
    @intervals << @current
    @detectors.each { |detector| detector.records << {passed: 0, occupied: 0, speed_sum: 0} }
  end

  def arrivals(step)
    @sources.each do |source|
      random = @generator.draw
      rate = source.rates.find { |_value, finish| step <= finish }&.first || 0
      next unless random % 1000 < rate

      kind = @classes[Minstd.select(@class_weights, @generator.draw)]
      vehicle = Vehicles::Vehicle.new(@vehicles.length + 1, kind, source.node, step)
      @vehicles << vehicle
      source.queue << vehicle
      @current[:arrivals] += 1
    end
  end

  def enter_segment(vehicle)
    segment = vehicle.segment
    vehicle.route << segment.id
    segment.counts[:entered] += 1
    vehicle.turn = if segment.junction
                     index = Minstd.select(segment.turns.map(&:weight), @generator.draw)
                     segment.turns[index]
                   end
  end

  def queue_event(source, step, open: false)
    line = "#{time(step)} QUEUE #{source.node} from #{source.start} max #{source.maximum}"
    line += ' open' if open
    @events << line
  end

  def insertions(step)
    @sources.each do |source|
      segment = source.entry
      until source.queue.empty?
        lanes = (1..segment.lanes).select { |lane| segment.cells[lane][0].nil? }
        break if lanes.empty?

        lane = lanes.min_by { |candidate| [-segment.first(candidate), candidate] }
        vehicle = source.queue.shift
        vehicle.place(segment, lane, 0)
        vehicle.insertion = step
        enter_segment(vehicle)
        @current[:insertions] += 1
      end
      if !source.queue.empty? && source.start.zero?
        source.start = step
        source.maximum = 0
      end
      next if source.start.zero?

      source.maximum = [source.maximum, source.queue.length].max
      if source.queue.empty?
        queue_event(source, step)
        source.start = 0
      end
    end
  end

  def desired_lane(vehicle)
    segment, lane, cell = vehicle.segment, vehicle.lane, vehicle.cell
    maximum = vehicle.maximum
    here = segment.free(lane, cell, maximum + 1)
    want = [vehicle.speed + 1, maximum].min
    obstacle = here < maximum + 1 && cell + here + 1 < segment.length &&
               segment.cells[lane][cell + here + 1] == Road::OBSTACLE
    if obstacle
      [lane + 1, lane - 1].each do |candidate|
        next unless candidate.between?(1, segment.lanes)

        if segment.free(candidate, cell, maximum + 1) > here && segment.safe?(candidate, cell)
          return [candidate, :avoidance]
        end
      end
    end
    if vehicle.heading_for_stop?
      return [lane - 1, :return] if lane >= 2 && segment.safe?(lane - 1, cell)

      return [lane, nil]
    end
    if vehicle.kind.overtake == 'Y' && lane < segment.lanes && here < want &&
       segment.free(lane + 1, cell, maximum + 1) > here && segment.safe?(lane + 1, cell)
      return [lane + 1, :overtaking]
    end
    if lane >= 2 && segment.free(lane - 1, cell, maximum + 1) > want && segment.safe?(lane - 1, cell)
      return [lane - 1, :return]
    end
    [lane, nil]
  end

  def change_lanes
    reservations = {}
    changes = []
    @segments.each do |segment|
      next if segment.lanes < 2

      segment.vehicles.each do |vehicle|
        next unless vehicle.dwell.zero?

        lane, kind = desired_lane(vehicle)
        next if lane == vehicle.lane

        key = [segment.id, lane, vehicle.cell]
        next if reservations[key]

        reservations[key] = true
        changes << [vehicle, lane, kind]
      end
    end
    changes.each do |vehicle, lane, kind|
      vehicle.place(vehicle.segment, lane, vehicle.cell)
      vehicle.lane_changes += 1
      vehicle.segment.counts[kind] += 1
    end
  end

  def determine_speed(vehicle, step)
    segment, lane, cell = vehicle.segment, vehicle.lane, vehicle.cell
    accelerated = [vehicle.speed + 1, vehicle.maximum].min
    gap = segment.free(lane, cell, accelerated)
    if gap < accelerated && cell + gap == segment.length - 1
      if segment.junction.nil?
        gap = accelerated
      elsif segment.junction.green?(segment.id, step)
        target = vehicle.turn.target
        target_lane = [lane, target.lanes].min
        gap += target.free(target_lane, -1, accelerated - gap)
      end
    end
    gap = [gap, segment.stop.cell - cell].min if vehicle.heading_for_stop?
    speed = [accelerated, gap].min
    speed = Vehicles.slowdown(speed, vehicle.speed, @dawdle, @stopped_dawdle, @generator)
    if vehicle.dwell > 0
      speed = 0
      vehicle.dwell -= 1
    end
    speed
  end

  def prepare_moves(step)
    @segments.flat_map { |segment| segment.vehicles(reverse: true) }.map do |vehicle|
      Move.new(vehicle: vehicle, segment: vehicle.segment, cell: vehicle.cell, old_speed: vehicle.speed,
               speed: determine_speed(vehicle, step), crossing: false)
    end
  end

  def move_vehicles(moves, step)
    moves.each do |move|
      vehicle, segment = move.vehicle, move.segment
      destination = move.cell + move.speed
      if destination < segment.length
        vehicle.place(segment, vehicle.lane, destination)
      elsif segment.junction.nil?
        vehicle.leave
        vehicle.exit = step
        vehicle.sink = segment.to
        @current[:exits] += 1
      else
        move.crossing = true
      end
    end
  end

  def pass_junctions(moves)
    moves.each do |move|
      next unless move.crossing

      vehicle, segment = move.vehicle, move.segment
      turn = vehicle.turn
      target = turn.target
      lane = [vehicle.lane, target.lanes].min
      wanted = move.cell + move.speed - segment.length
      destination = [wanted, target.first(lane) - 1].min
      segment.counts[:blocked] += 1 if destination < wanted
      if destination >= 0
        vehicle.place(target, lane, destination)
        move.speed = segment.length - move.cell + destination
        segment.counts[:passed] += 1
        turn.vehicles += 1
        enter_segment(vehicle)
      else
        vehicle.place(segment, vehicle.lane, segment.length - 1)
        move.speed = segment.length - 1 - move.cell
      end
    end
  end

  def aggregate_vehicles(moves, step)
    moves.each do |move|
      vehicle = move.vehicle
      vehicle.network_steps += 1
      vehicle.distance += move.speed
      if move.speed.zero?
        vehicle.stopped_steps += 1
        vehicle.stop_count += 1 if move.old_speed > 0
      end
      vehicle.speed = move.speed
      @current[:vehicle_steps] += 1
      @current[:speed_sum] += move.speed
      if vehicle.heading_for_stop? && vehicle.lane == 1 && vehicle.cell == vehicle.segment.stop.cell
        stop = vehicle.segment.stop
        vehicle.completed_stops[vehicle.segment.id] = true
        vehicle.dwell = stop.dwell
        stop.buses += 1
        @events << "#{time(step)} BUS_STOP #{vehicle.number} #{vehicle.segment.id} cell #{stop.cell}"
      end
      if @tracks.key?(vehicle.number)
        position = vehicle.segment ? "#{vehicle.segment.id} #{vehicle.lane} #{vehicle.cell}" : 'EXIT'
        @tracks[vehicle.number] << "#{time(step)} #{position} #{vehicle.speed}"
      end
      @detectors.each do |detector|
        next unless move.segment == detector.segment && move.cell < detector.cell

        if vehicle.segment != detector.segment || vehicle.cell >= detector.cell
          detector.records[-1][:passed] += 1
        end
      end
    end
  end

  def aggregate_state(step)
    @detectors.each do |detector|
      totals = detector.records[-1]
      1.upto(detector.segment.lanes) do |lane|
        detector.cell.upto(detector.cell + detector.width - 1) do |cell|
          vehicle = detector.segment.cells[lane][cell]
          next if vehicle.nil? || vehicle == Road::OBSTACLE

          totals[:occupied] += 1
          totals[:speed_sum] += vehicle.speed
        end
      end
    end
    @segments.each do |segment|
      vehicles = segment.vehicles
      counts = segment.counts
      counts[:vehicle_sum] += vehicles.length
      counts[:speed_sum] += vehicles.sum(&:speed)
      counts[:maximum_vehicles] = [counts[:maximum_vehicles], vehicles.length].max
      next unless segment.junction

      green = segment.junction.green?(segment.id, step)
      counts[:green] += 1 if green
      queue = vehicles.count { |vehicle| vehicle.speed.zero? }
      counts[:queue_sum] += queue
      counts[:maximum_queue] = [counts[:maximum_queue], queue].max
      if step < @steps && queue > 0 && green && !segment.junction.green?(segment.id, step + 1)
        counts[:failures] += 1
      end
    end
    @diagrams.each do |diagram|
      next unless step.between?(diagram.start, diagram.finish)

      segment = diagram.segment
      signal = segment.junction.nil? ? 'E' : segment.junction.green?(segment.id, step) ? 'G' : 'R'
      diagram.rows << "#{time(step)} #{segment.picture(diagram.lane)} #{signal}"
    end
  end

  def simulate
    1.upto(@steps) do |step|
      update_incidents(step)
      start_interval if (step - 1) % @interval_length == 0
      arrivals(step)
      insertions(step)
      change_lanes
      moves = prepare_moves(step)
      move_vehicles(moves, step)
      pass_junctions(moves)
      aggregate_vehicles(moves, step)
      aggregate_state(step)
    end
    @sources.each { |source| queue_event(source, @steps, open: true) unless source.start.zero? }
  end

  def enumerate_routes(segment)
    return @route_lists[segment.id] if @route_lists.key?(segment.id)

    if segment.junction.nil?
      routes = [{segments: [segment.id], expected: Rational(1, 1), sink: segment.to}]
    else
      total = segment.turns.sum(&:weight)
      routes = segment.turns.flat_map do |turn|
        enumerate_routes(turn.target).map do |route|
          {segments: [segment.id] + route[:segments], expected: route[:expected] * Rational(turn.weight, total),
           sink: route[:sink]}
        end
      end
    end
    @route_lists[segment.id] = routes
  end

  def route_summary(prefix, expected, vehicles, total)
    line = "  #{prefix} expected #{Stats.fraction(expected.numerator, expected.denominator)} vehicles #{vehicles.length}"
    line += " share #{Stats.fraction(vehicles.length, total)} mean #{Stats.decimal(vehicles.sum(&:network_steps), vehicles.length, 2)}"
    line
  end

  def travel_lines
    exited = @vehicles.select(&:exit)
    lines = []
    @classes.each do |kind|
      times = exited.select { |vehicle| vehicle.kind == kind }.map(&:network_steps)
      lines.concat(Stats.travel_block("CLASS #{kind.name}", times, @bin_width))
    end
    lines.concat(Stats.travel_block('ALL', exited.map(&:network_steps), @bin_width))
    @sources.each do |source|
      vehicles = exited.select { |vehicle| vehicle.source == source.node }
      routes = enumerate_routes(source.entry)
      lines << "SOURCE #{source.node} exited #{vehicles.length}"
      routes.each do |route|
        selected = vehicles.select { |vehicle| vehicle.route == route[:segments] }
        lines << route_summary("ROUTE #{route[:segments].join(',')}", route[:expected], selected, vehicles.length)
      end
      @sinks.each do |sink|
        matching = routes.select { |route| route[:sink] == sink }
        next if matching.empty?

        expected = matching.sum { |route| route[:expected] }
        selected = vehicles.select { |vehicle| vehicle.sink == sink }
        lines << route_summary("SINK #{sink}", expected, selected, vehicles.length)
      end
    end
    lines
  end

  def class_block(heading, vehicles)
    inserted = vehicles.count(&:insertion)
    exited = vehicles.select(&:exit)
    steps = vehicles.sum(&:network_steps)
    distance = vehicles.sum(&:distance)
    lines = [heading]
    lines << "  generated #{vehicles.length} inserted #{inserted} exited #{exited.length} in_network #{inserted - exited.length} queued #{vehicles.length - inserted}"
    lines << "  vehicle_steps #{steps} distance #{distance} mean_speed #{Stats.fraction(distance, steps)} = #{Stats.decimal(distance, steps, 3)}"
    detail = "  travel #{Stats.decimal(exited.sum(&:network_steps), exited.length, 2)}"
    delay = exited.sum { |vehicle| vehicle.insertion - vehicle.arrival }
    detail += " entry_delay #{Stats.decimal(delay, exited.length, 2)}"
    {stopped: :stopped_steps, stops: :stop_count, lane_changes: :lane_changes}.each do |label, field|
      detail += " #{label} #{Stats.decimal(exited.sum { |vehicle| vehicle.public_send(field) }, exited.length, 2)}"
    end
    lines << detail
    lines
  end

  def class_lines
    lines = []
    @classes.each do |kind|
      heading = "CLASS #{kind.name} vmax #{kind.vmax} weight #{kind.weight} overtake #{kind.overtake} stops #{kind.stop}"
      lines.concat(class_block(heading, @vehicles.select { |vehicle| vehicle.kind == kind }))
    end
    lines.concat(class_block('ALL', @vehicles))
    lines
  end

  def network_lines
    lines = []
    @segments.each do |segment|
      counts = segment.counts
      line = "SEGMENT #{segment.id} #{segment.from} #{segment.to} length #{segment.length} lanes #{segment.lanes} limit #{segment.limit} entered #{counts[:entered]}"
      line += " mean_vehicles #{Stats.decimal(counts[:vehicle_sum], @steps, 3)} density #{Stats.decimal(counts[:vehicle_sum], @steps * segment.length * segment.lanes, 4)}"
      line += " mean_speed #{Stats.decimal(counts[:speed_sum], counts[:vehicle_sum], 2)} max_vehicles #{counts[:maximum_vehicles]}"
      lines << line + " changes #{counts[:overtaking]}/#{counts[:return]}/#{counts[:avoidance]}"
    end
    @junctions.each do |junction|
      lines.concat(junction.lines)
      @segments.select { |segment| segment.junction == junction }.each do |segment|
        counts = segment.counts
        line = "  IN #{segment.id} green #{counts[:green]} passed #{counts[:passed]} blocked #{counts[:blocked]} max_queue #{counts[:maximum_queue]}"
        lines << line + " mean_queue #{Stats.decimal(counts[:queue_sum], @steps, 3)} failures #{counts[:failures]}"
        segment.turns.each do |turn|
          lines << "    TURN #{turn.target.id} weight #{turn.weight} vehicles #{turn.vehicles}"
        end
      end
    end
    @stops.each do |stop|
      lines << "STOP #{stop.segment.id} cell #{stop.cell} dwell #{stop.dwell} buses #{stop.buses}"
    end
    @incidents.each do |incident|
      active = incident.active_start ? "#{incident.active_start}-#{incident.active_end}" : 'none'
      lines << "INCIDENT #{incident.segment.id} lane #{incident.lane} cell #{incident.cell} planned #{incident.start}-#{incident.finish} active #{active}"
    end
    lines
  end

  def diagram_lines
    @diagrams.flat_map do |diagram|
      ["DIAGRAM #{diagram.segment.id} lane #{diagram.lane} steps #{diagram.start}-#{diagram.finish}"] + diagram.rows
    end
  end

  def detector_lines
    lines = ['detector,interval,flow,density,speed']
    @detectors.each do |detector|
      capacity = @interval_length * detector.width * detector.segment.lanes
      detector.records.each_with_index do |record, index|
        lines << [detector.name, index + 1, record[:passed], Stats.decimal(record[:occupied], capacity, 4),
                  Stats.decimal(record[:speed_sum], record[:occupied], 2)].join(',')
      end
    end
    lines
  end

  def timeline_lines
    lines = ['interval,arrived,inserted,exited,in_network,queued,mean_speed']
    road = 0
    queued = 0
    @intervals.each_with_index do |interval, index|
      road += interval[:insertions] - interval[:exits]
      queued += interval[:arrivals] - interval[:insertions]
      lines << [index + 1, interval[:arrivals], interval[:insertions], interval[:exits], road, queued,
                Stats.decimal(interval[:speed_sum], interval[:vehicle_steps], 2)].join(',')
    end
    lines
  end

  def track_lines
    lines = []
    @track_numbers.each do |number|
      vehicle = @vehicles[number - 1]
      unless vehicle
        lines << "VEHICLE #{number} none"
        next
      end
      lines << "VEHICLE #{number} class #{vehicle.kind.name} source #{vehicle.source} arrival #{vehicle.arrival} inserted #{vehicle.insertion || '-'} exited #{vehicle.exit || '-'} sink #{vehicle.sink || '-'}"
      lines << 'ROUTE ' + (vehicle.route.empty? ? '-' : vehicle.route.join(' '))
      lines.concat(@tracks[number])
    end
    lines
  end

  def ring_experiment(ring, count)
    vehicles = Array.new(count) { |index| [(index * ring.length).div(count), 0, 0] }
    generator = Minstd.new(ring.seed)
    total = 0
    1.upto(ring.warmup + ring.measured) do |step|
      ordered = vehicles.sort_by { |vehicle| -vehicle[0] }
      ordered.each_with_index do |vehicle, index|
        gap = (ordered[index - 1][0] - vehicle[0] - 1) % ring.length
        speed = [vehicle[1] + 1, ring.maximum, gap].min
        vehicle[2] = Vehicles.slowdown(speed, vehicle[1], @dawdle, @stopped_dawdle, generator)
      end
      vehicles.each do |vehicle|
        vehicle[0] = (vehicle[0] + vehicle[2]) % ring.length
        vehicle[1] = vehicle[2]
        total += vehicle[2] if step > ring.warmup
      end
    end
    total
  end

  def fundamental_lines
    lines = ['ring,vehicles,density,flow,speed']
    @rings.each_with_index do |ring, index|
      ring.counts.each do |count|
        total = ring_experiment(ring, count)
        lines << [index + 1, count, Stats.decimal(count, ring.length, 4),
                  Stats.decimal(total, ring.length * ring.measured, 4),
                  Stats.decimal(total, count * ring.measured, 3)].join(',')
      end
    end
    lines
  end

  def run
    simulate
    files = {'spacetime.txt' => diagram_lines, 'detectors.csv' => detector_lines,
             'travel_times.txt' => travel_lines, 'class_stats.txt' => class_lines,
             'network_stats.txt' => network_lines, 'timeline.csv' => timeline_lines,
             'tracks.txt' => track_lines, 'fundamental.csv' => fundamental_lines, 'events.txt' => @events}
    Dir.mkdir('output') unless Dir.exist?('output')
    files.each do |name, lines|
      File.binwrite('output/' + name, lines.empty? ? '' : lines.join("\n") + "\n")
    end
  end
end

TrafficSimulation.new.run if $PROGRAM_NAME == __FILE__
