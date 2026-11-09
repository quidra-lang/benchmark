require 'fileutils'
require_relative 'layout'
require_relative 'interlocking'
require_relative 'signals'
require_relative 'trains'
require_relative 'safety'

class Simulation
  Request = Struct.new(:number, :route, :time, :reason)

  def initialize
    @layout = Layout.new
    @interlocking = Interlocking.new(@layout)
    @routes = @interlocking.routes
    @trains, requests = Trains.read
    @planned_requests = Hash.new { |h, k| h[k] = [] }
    requests.each { |time, train, route| @planned_requests[time] << [train, route] }
    @events = Hash.new { |h, k| h[k] = [] }
    File.foreach('input/events.txt', chomp: true) do |line|
      time, command, *arguments = line.split(' ')
      @events[time.to_i] << [command, arguments]
    end
    settings = File.readlines('input/params.txt', chomp: true).to_h do |line|
      name, *values = line.split(' ')
      [name, values.map(&:to_i)]
    end
    @end = settings['END'].first
    @throw_time = settings['THROW'].first
    @overlap_time = settings['OVERLAP'].first
    @snapshot_times = settings['SNAPSHOTS'].to_set
    @time, @request_count, @dropped = 0, 0, 0
    @queue, @log, @snapshots = [], [], []
    @safety = Safety.new
  end

  def log(content) = @log << "#{@time} #{content}"

  def occupied?(name)
    section = @layout.sections.fetch(name)
    section.failed || !section.occupants.empty?
  end

  def start_throw(point, target)
    point.moving, point.target, point.completion = true, target, @time + @throw_time
    log("MOVE #{point.name} #{target} until #{point.completion}")
  end

  def complete_throws
    @layout.points.each_value do |point|
      next unless point.moving && point.completion == @time

      point.position = point.target
      point.moving, point.completion = false, nil
      point.stats['throws'] += 1
      log("POINT #{point.name} #{point.position}")
    end
  end

  def release_approaches
    @routes.each_value do |route|
      next unless route.state == 'APPROACH' && route.release_time == @time

      @interlocking.release(route)
      log("TIMEOUT #{route.name}")
    end
  end

  def add_request(name, requester)
    @request_count += 1
    @queue << Request.new(@request_count, name, @time, nil)
    @routes.fetch(name).stats['requests'] += 1
    log("REQUEST q#{@request_count} #{name} #{requester}")
  end

  def cancel(name)
    removed = @queue.select { |q| q.route == name }
    unless removed.empty?
      removed.each { |q| log("DROP q#{q.number} #{name}") }
      @dropped += removed.size
      @queue.reject! { |q| q.route == name }
      return
    end
    route = @routes.fetch(name)
    if route.state == 'LOCKED'
      route.stats['cancels'] += 1
      signal = @layout.signals.fetch(route.start)
      if signal.aspect != 'RED' && occupied?(signal.section)
        route.state, route.release_time = 'APPROACH', @time + route.approach_time
        log("CANCEL #{name} approach until #{route.release_time}")
      else
        @interlocking.release(route)
        log("CANCEL #{name} released")
      end
    else
      log("CANCEL #{name} #{route.set? ? 'refused' : 'none'}")
    end
  end

  def individual_throw(name, target)
    point = @layout.points.fetch(name)
    result = if !point.locks.empty?
               'locked'
             elsif point.failed
               'failed'
             elsif point.moving
               'moving'
             elsif occupied?(point.common)
               'occupied'
             elsif point.position == target
               'none'
             else
               'start'
             end
    log("THROW #{name} #{target} #{result}")
    start_throw(point, target) if result == 'start'
  end

  def execute_events
    @events[@time].each do |command, arguments|
      name = arguments.first
      case command
      when 'REQUEST' then add_request(name, 'OPERATOR')
      when 'CANCEL' then cancel(name)
      when 'THROW' then individual_throw(*arguments)
      when 'TCFAIL', 'TCFIX'
        @layout.sections.fetch(name).failed = command == 'TCFAIL'
        log("#{command} #{name}")
      when 'POINTFAIL', 'POINTFIX'
        point = @layout.points.fetch(name)
        point.failed = command == 'POINTFAIL'
        point.completion = nil if point.failed && point.moving
        log("#{command} #{name}")
        start_throw(point, point.target) if !point.failed && point.moving
      end
    end
  end

  def opposite_lock?(names, route)
    names.any? { |name| @routes.fetch(name).direction != route.direction }
  end

  def request_reason(route)
    return 'busy' if route.set?

    route.conflicts.each do |name|
      return "conflict #{name}" if %w[LOCKED APPROACH].include?(@routes[name].state)
    end
    route.sections.each do |name|
      section = @layout.sections.fetch(name)
      return "occupied #{name}" if occupied?(name)
      return "locked #{name}" if section.route_lock || opposite_lock?(section.overlap_locks, route)
    end
    route.overlap.each do |name|
      section = @layout.sections.fetch(name)
      return "occupied #{name}" if occupied?(name)

      locks = section.overlap_locks.to_a
      locks << section.route_lock if section.route_lock
      return "locked #{name}" if opposite_lock?(locks, route)
    end
    route.requirements.each do |name, target|
      point = @layout.points.fetch(name)
      return "point #{name} locked" if point.locks.any? { |_, position| position != target }
      next if (!point.moving && point.position == target) || (point.moving && point.target == target)

      return "point #{name} failed" if point.failed
      return "point #{name} moving" if point.moving
      return "point #{name} occupied" if occupied?(point.common)
    end
    nil
  end

  def judge_requests
    waiting = []
    @queue.each do |request|
      route = @routes.fetch(request.route)
      reason = request_reason(route)
      if reason
        if reason != request.reason
          log("WAIT q#{request.number} #{route.name} #{reason}")
          request.reason = reason
        end
        waiting << request
        next
      end
      @interlocking.lock(route)
      wait = @time - request.time
      log("GRANT q#{request.number} #{route.name} wait #{wait}")
      route.stats['grants'] += 1
      route.stats['wait'] += wait
      route.stats['maxwait'] = [route.stats['maxwait'], wait].max
      route.requirements.each do |name, target|
        point = @layout.points.fetch(name)
        start_throw(point, target) if !point.moving && point.position != target
      end
    end
    @queue = waiting
  end

  def decide_signals
    Signals.aspects(@interlocking) { |name| occupied?(name) }.each do |signal, aspect|
      next if signal.aspect == aspect

      signal.aspect = aspect
      log("SIGNAL #{signal.name} #{aspect}")
    end
  end

  def occupied_parts(train)
    return [] unless train.state == 'RUNNING'

    tail = train.head - train.length
    train.path.filter_map do |name, start|
      finish = start + @layout.sections.fetch(name).length
      [name, start, [tail, start].max, [train.head, finish].min] if start < train.head && finish > tail
    end
  end

  def head_section(train)
    train.path.reverse_each.find { |_, start| start < train.head } || train.path.first
  end

  def enter(train, entered_boundaries)
    return false if train.state == 'EXITED'
    return true if train.state == 'RUNNING'

    boundary = @layout.boundaries.fetch(train.entry)
    return false if @time < train.entry_time || occupied?(boundary.section) || entered_boundaries.include?(train.entry)

    train.state, train.direction = 'RUNNING', boundary.end == 'L' ? 'UP' : 'DOWN'
    train.path, train.head, train.speed = [[boundary.section, 0]], 0, train.entry_speed
    train.entered = @time
    entered_boundaries.add(train.entry)
    log("ENTER #{train.name} #{train.entry}")
    true
  end

  def reverse(train, stop)
    name, start = head_section(train)
    finish = start + @layout.sections.fetch(name).length
    train.path = occupied_parts(train).reverse.map do |section, origin, _, _|
      [section, finish - (origin + @layout.sections.fetch(section).length)]
    end
    train.head = finish - (train.head - train.length)
    train.direction = train.direction == 'UP' ? 'DOWN' : 'UP'
    log("REVERSE #{train.name} #{stop.section}")
  end

  def finish_dwell(train)
    return true unless train.dwelling

    stop = train.next_stop
    return false if @time < stop.arrival + stop.dwell || @time < stop.scheduled_departure

    train.dwelling, train.awaiting_departure = false, stop
    train.stop_index += 1
    reverse(train, stop) if stop.kind == 'TURN'
    true
  end

  def limit_distance(train)
    return nil if train.boundary

    name, start = head_section(train)
    distance = start + @layout.sections.fetch(name).length - train.head
    loop do
      signal = @layout.signals_at[[name, train.direction]]
      return distance if signal && signal.aspect == 'RED'
      return distance if train.next_stop && train.next_stop.section == name

      type, following = @layout.beyond(name, train.direction)
      return nil if type == :boundary
      return distance if [:buffer, :impassable].include?(type)

      distance += @layout.sections.fetch(following).length
      name = following
    end
  end

  def pass_signal(train, signal)
    route = @routes.each_value.find { |r| r.start == signal.name && %w[LOCKED APPROACH].include?(r.state) }
    log("PASS #{train.name} #{signal.name} #{signal.aspect} #{route ? route.name : '-'}")
    signal.stats['passes'] += 1
    train.stats['passes'] += 1
    if route
      route.state = 'USED'
      route.stats['uses'] += 1
    end
    if signal.aspect == 'RED'
      log("SPAD #{train.name} #{signal.name}")
      @safety.check(@time, 'SIGNAL_PASSING', "#{train.name} #{signal.name}")
      train.emergency = true
    else
      @safety.check(@time, 'SIGNAL_PASSING')
    end
  end

  def move(train, remaining)
    name, start = head_section(train)
    while remaining.positive?
      if train.boundary
        train.head += remaining
        break
      end
      finish = start + @layout.sections.fetch(name).length
      if train.head + remaining <= finish
        train.head += remaining
        break
      end
      remaining -= finish - train.head
      train.head = finish
      signal = @layout.signals_at[[name, train.direction]]
      pass_signal(train, signal) if signal
      stop = train.awaiting_departure
      if stop && stop.section == name
        log("DEPART #{train.name} #{name}")
        stop.departure, train.awaiting_departure = @time, nil
      end
      type, following = @layout.beyond(name, train.direction)
      if type == :boundary
        train.boundary, train.boundary_coordinate = following, finish
      else
        name, start = following, finish
        train.path << [name, start]
      end
    end
  end

  def after_movement(train, speed, previous_speed)
    train.speed = speed
    train.stats['distance'] += speed
    train.stats['maxspeed'] = [train.stats['maxspeed'], speed].max
    train.emergency = false if speed.zero?
    name, start = head_section(train)
    stop = train.next_stop
    arrived = stop && speed.zero? && stop.section == name && train.head == start + @layout.sections[name].length
    if arrived
      train.dwelling, stop.arrival = true, @time
      log("ARRIVE #{train.name} #{name}")
    elsif speed.zero?
      train.stats['standing'] += 1
      log("HOLD #{train.name} #{name}") if previous_speed.positive?
    end
    if train.boundary && train.head - train.length >= train.boundary_coordinate
      train.state, train.exited = 'EXITED', @time
      log("EXIT #{train.name} #{train.boundary}")
    end
  end

  def run_trains
    entered_boundaries = Set.new
    @trains.each_value do |train|
      next unless enter(train, entered_boundaries) && finish_dwell(train)

      speed = Trains.select_speed(train, limit_distance(train))
      previous_speed = train.speed
      move(train, speed)
      after_movement(train, speed, previous_speed)
    end
  end

  def recompute_occupancy
    @layout.sections.each_value { |section| section.occupants = [] }
    @trains.each_value do |train|
      occupied_parts(train).each do |name, _, _, _|
        occupants = @layout.sections.fetch(name).occupants
        occupants << train.name unless occupants.include?(train.name)
      end
    end
  end

  def sectional_release
    @routes.each_value do |route|
      next unless route.state == 'USED'

      remaining = route.sections.select { |name| @layout.sections[name].route_lock == route.name }
      remaining.each { |name| route.passed.add(name) if occupied?(name) }
      remaining.each do |name|
        break if !route.passed.include?(name) || occupied?(name)

        @interlocking.unlock_section(route, name)
        log("RELEASE #{route.name} #{name}")
      end
      if route.sections.none? { |name| @layout.sections[name].route_lock == route.name }
        @interlocking.release(route)
        log("DONE #{route.name}")
      elsif !route.overlap.empty? && route.overlap_locked
        route.overlap_counter = occupied?(route.sections.last) ? route.overlap_counter + 1 : 0
        if route.overlap_counter >= @overlap_time
          @interlocking.unlock_overlap(route)
          log("OVERLAP #{route.name}")
        end
      end
    end
  end

  def record_statistics
    @routes.each_value { |r| r.stats['locked'] += 1 if r.set? }
    @layout.points.each_value do |point|
      point.stats['locked'] += 1 unless point.locks.empty?
      point.stats['moving'] += 1 if point.moving
    end
    @layout.sections.each_value do |section|
      section.stats['occupied'] += 1 if occupied?(section.name)
      section.stats['locked'] += 1 if section.route_lock || !section.overlap_locks.empty?
      section.trains.merge(section.occupants)
    end
    @layout.signals.each_value { |signal| signal.stats[signal.aspect] += 1 }
  end

  def diagram
    sections = @layout.sections.values
    symbols = @layout.points.values + @layout.signals.values + @layout.buffers.values
    rows = sections.map(&:row) + symbols.map(&:row) + @layout.labels.map(&:first)
    columns = sections.map(&:last) + symbols.map(&:column) + @layout.labels.map { |_, c, text| c + text.size - 1 }
    grid = Array.new(rows.max + 1) { Array.new(columns.max + 1, ' ') }
    @layout.labels.each do |row, column, text|
      text.chars.each_with_index { |char, offset| grid[row][column + offset] = char }
    end
    sections.each do |section|
      char = if section.failed then '#'
             elsif section.route_lock then '='
             elsif !section.overlap_locks.empty? then '~'
             else '-'
             end
      (section.first..section.last).each { |col| grid[section.row][col] = char }
    end
    @trains.each_value do |train|
      occupied_parts(train).each do |name, start, lo, hi|
        section = @layout.sections.fetch(name)
        length, cells = section.length, section.last - section.first + 1
        left, right = if train.direction == 'UP'
                        [lo - start, hi - start]
                      else
                        [length - (hi - start), length - (lo - start)]
                      end
        cells.times do |j|
          next unless left * cells < (j + 1) * length && right * cells > j * length

          col = section.first + j
          previous = grid[section.row][col]
          grid[section.row][col] = /[a-z*]/.match?(previous) ? '*' : train.symbol
        end
      end
    end
    @layout.buffers.each_value { |b| grid[b.row][b.column] = '|' }
    @layout.points.each_value { |p| grid[p.row][p.column] = p.detected? ? p.position : '?' }
    @layout.signals.each_value { |s| grid[s.row][s.column] = { 'RED' => 'X', 'YELLOW' => 'Y', 'GREEN' => 'G' }.fetch(s.aspect) }
    grid.map { |row| row.join.rstrip }
  end

  def snapshot
    lines = ["SNAPSHOT #{@time}"] + diagram
    @trains.each_value do |train|
      next unless train.state == 'RUNNING'

      sections = occupied_parts(train).map(&:first).join(',')
      lines << "TRAIN #{train.symbol} #{train.name} #{train.direction} #{train.speed} #{sections}".rstrip
    end
    routes = @routes.values.select(&:set?).map { |r| "#{r.name}/#{r.state}" }
    lines << "ROUTES #{routes.empty? ? '-' : routes.join(' ')}"
  end

  def train_rows
    @trains.values.flat_map do |train|
      rows = [[train.name, "enter:#{train.entry}", train.entry_time, train.entered]]
      train.stops.each do |stop|
        rows << [train.name, "arr:#{stop.section}", stop.scheduled_arrival, stop.arrival]
        rows << [train.name, "dep:#{stop.section}", stop.scheduled_departure, stop.departure]
      end
      rows << [train.name, "exit:#{train.exit}", train.scheduled_exit, train.exited]
    end
  end

  def train_report(rows)
    ['train,location,scheduled,actual,delay'] + rows.map do |name, location, scheduled, actual|
      timing = actual.nil? ? '-,-' : "#{actual},#{actual - scheduled}"
      "#{name},#{location},#{scheduled},#{timing}"
    end
  end

  def punctuality(rows)
    on_time, late, missing, total, maximum = 0, 0, 0, 0, 0
    rows.each do |_, _, scheduled, actual|
      if actual.nil?
        missing += 1
      elsif actual <= scheduled
        on_time += 1
      else
        late += 1
        delay = actual - scheduled
        total += delay
        maximum = [maximum, delay].max
      end
    end
    "PUNCTUALITY on_time #{on_time} late #{late} missing #{missing} total_delay #{total} max_delay #{maximum}"
  end

  def summary(rows)
    lines = @routes.values.map do |r|
      "ROUTE #{r.name} #{r.start}-#{r.finish} " + %w[requests grants uses cancels wait maxwait locked].map { |n| "#{n} #{r.stats[n]}" }.join(' ')
    end
    @layout.points.each_value do |p|
      lines << "POINT #{p.name} throws #{p.stats['throws']} locked #{p.stats['locked']} moving #{p.stats['moving']} final #{p.detected? ? p.position : '?'}"
    end
    @layout.sections.each_value do |s|
      lines << "SECTION #{s.name} occupied #{s.stats['occupied']} locked #{s.stats['locked']} trains #{s.trains.size}"
    end
    @layout.signals.each_value do |s|
      lines << "SIGNAL #{s.name} red #{s.stats['RED']} yellow #{s.stats['YELLOW']} green #{s.stats['GREEN']} passes #{s.stats['passes']}"
    end
    @trains.each_value do |train|
      lines << "TRAIN #{train.name} #{train.symbol} #{train.state} " + %w[distance maxspeed standing passes].map { |n| "#{n} #{train.stats[n]}" }.join(' ')
    end
    states = @trains.values.map(&:state).tally
    lines << "TRAINS total #{@trains.size} exited #{states.fetch('EXITED', 0)} running #{states.fetch('RUNNING', 0)} waiting #{states.fetch('WAITING', 0)}"
    lines << punctuality(rows)
    grants = @routes.values.sum { |r| r.stats['grants'] }
    lines << "REQUESTS total #{@request_count} granted #{grants} dropped #{@dropped} pending #{@queue.size}"
  end

  def write_reports
    rows = train_rows
    reports = { 'events.txt' => @log, 'snapshots.txt' => @snapshots,
                'train_log.csv' => train_report(rows), 'safety.txt' => @safety.report,
                'summary.txt' => summary(rows) }
    FileUtils.mkdir_p('output')
    reports.each { |name, lines| File.write("output/#{name}", lines.map { |line| line + "\n" }.join) }
  end

  def run
    (0..@end).each do |time|
      @time = time
      complete_throws
      release_approaches
      @planned_requests[time].each { |train, route| add_request(route, train) }
      execute_events
      judge_requests
      decide_signals
      run_trains
      recompute_occupancy
      sectional_release
      @safety.inspect(time, @layout, @routes)
      record_statistics
      @snapshots.concat(snapshot) if @snapshot_times.include?(time)
    end
    write_reports
  end
end

Simulation.new.run if $PROGRAM_NAME == __FILE__
