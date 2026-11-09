Stop = Struct.new(:x, :y, :demand, :service, :open, :close)
class RouteError < StandardError; end

class RouteWorkbench
  def initialize
    @depot = nil
    @departure = 480
    @stops = {}
    @tour = nil
    @routes = nil
    @capacity = nil
  end

  def ids
    @stops.keys.sort
  end

  def name(id)
    id.zero? ? 'D' : id.to_s
  end

  def point(id)
    id.zero? ? @depot : [@stops[id].x, @stops[id].y]
  end

  def distance(a, b)
    x, y = point(a)
    u, v = point(b)
    (x - u).abs + (y - v).abs
  end

  def length(route)
    ([0] + route + [0]).each_cons(2).sum { |a, b| distance(a, b) }
  end

  def load(route)
    route.sum { |id| @stops[id].demand }
  end

  def notation(route)
    (['D'] + route.map(&:to_s) + ['D']).join('-')
  end

  def plan_length(routes = @routes)
    routes.sum { |route| length(route) }
  end

  def normalize
    @routes.reject!(&:empty?)
    @routes.map! { |route| route.first > route.last ? route.reverse : route }
    @routes.sort_by!(&:min)
  end

  def route_lines
    @routes.each_with_index { |route, i| puts "route #{i + 1}: #{notation(route)} load #{load(route)} length #{length(route)}" }
  end

  def clock(time)
    format('%02d:%02d', time / 60, time % 60)
  end

  def minutes(text)
    hour, minute = text.split(':').map(&:to_i)
    hour * 60 + minute
  end

  def require_data
    raise RouteError, 'no depot' unless @depot
    raise RouteError, 'no stops' if @stops.empty?
  end

  def require_tour
    raise RouteError, 'no tour' unless @tour
  end

  def require_plan
    raise RouteError, 'no plan' unless @routes
  end

  def check_capacity(capacity)
    id = ids.find { |n| @stops[n].demand > capacity }
    raise RouteError, "stop #{id} demand #{@stops[id].demand} exceeds capacity #{capacity}" if id
  end

  def simulate(route, print_lines = false)
    time = @departure
    previous = 0
    waiting = 0
    service = 0
    violations = 0
    lateness = 0
    route.each do |id|
      stop = @stops[id]
      arrival = time + distance(previous, id)
      wait = stop.open ? [0, stop.open - arrival].max : 0
      late = stop.close ? [0, arrival - stop.close].max : 0
      begin_time = arrival + wait
      time = begin_time + stop.service
      waiting += wait
      service += stop.service
      violations += 1 if late.positive?
      lateness += late
      puts "#{id} arrive #{clock(arrival)} wait #{wait} begin #{clock(begin_time)} leave #{clock(time)} #{late.positive? ? "late #{late}" : 'ok'}" if print_lines
      previous = id
    end
    time += distance(previous, 0)
    puts "return #{clock(time)}, travel #{length(route)}, wait #{waiting}, service #{service}, violations #{violations}, lateness #{lateness}" if print_lines
    [time, violations, lateness]
  end

  def exact
    stops = ids
    full = (1 << stops.length) - 1
    memo = {}
    solve = lambda do |mask, previous|
      return distance(previous, 0) if mask == full
      memo[[mask, previous]] ||= stops.each_index.reject { |i| mask[i] == 1 }.map do |i|
        distance(previous, stops[i]) + solve.call(mask | (1 << i), stops[i])
      end.min
    end
    route = []
    mask = 0
    previous = 0
    until mask == full
      best = solve.call(mask, previous)
      i = stops.each_index.find { |j| mask[j].zero? && distance(previous, stops[j]) + solve.call(mask | (1 << j), stops[j]) == best }
      route << stops[i]
      mask |= 1 << i
      previous = stops[i]
    end
    route
  end

  def tour_move(route, method)
    old = length(route)
    n = route.length
    if method == 'OROPT'
      (1..3).each do |size|
        next if size > n
        (0..(n - size)).each do |i|
          segment = route[i, size]
          remaining = route.take(i) + route.drop(i + size)
          (0..remaining.length).each do |j|
            next if j == i
            candidate = remaining.take(j) + segment + remaining.drop(j)
            gain = old - length(candidate)
            if gain.positive?
              after = j.zero? ? 'D' : remaining[j - 1]
              return [candidate, "move #{segment.join('-')} after #{after} gain #{gain}"]
            end
          end
        end
      end
    else
      (0...n).each do |i|
        ((i + 1)...n).each do |j|
          candidate = route.dup
          if method == 'TWOOPT'
            candidate[i..j] = candidate[i..j].reverse
          else
            candidate[i], candidate[j] = candidate[j], candidate[i]
          end
          gain = old - length(candidate)
          next unless gain.positive?
          message = method == 'TWOOPT' ? "reverse #{route[i]}..#{route[j]} gain #{gain}" : "swap #{route[i]} and #{route[j]} gain #{gain}"
          return [candidate, message]
        end
      end
    end
    nil
  end

  def improve_tour(route, method, output = true)
    count = 0
    loop do
      move = tour_move(route, method)
      break unless move
      route, message = move
      puts message if output
      count += 1
    end
    [route, count]
  end

  def plan_move(method)
    before = plan_length
    @routes.each_index do |r|
      a = @routes[r]
      if method == 'RELOCATE'
        a.each_with_index do |c, p|
          @routes.each_index do |t|
            next if r == t || load(@routes[t]) + @stops[c].demand > @capacity
            (0..@routes[t].length).each do |j|
              candidate = @routes.map(&:dup)
              candidate[r].delete_at(p)
              candidate[t].insert(j, c)
              gain = before - plan_length(candidate)
              next unless gain.positive?
              after = j.zero? ? 'D' : @routes[t][j - 1]
              return [candidate, "relocate #{c} from route #{r + 1} to route #{t + 1} after #{after} gain #{gain}"]
            end
          end
        end
      else
        ((r + 1)...@routes.length).each do |t|
          b = @routes[t]
          if method == 'EXCHANGE'
            a.each_with_index do |c, p|
              b.each_with_index do |e, j|
                next if load(a) - @stops[c].demand + @stops[e].demand > @capacity || load(b) - @stops[e].demand + @stops[c].demand > @capacity
                candidate = @routes.map(&:dup)
                candidate[r][p], candidate[t][j] = e, c
                gain = before - plan_length(candidate)
                return [candidate, "exchange #{c} (route #{r + 1}) with #{e} (route #{t + 1}) gain #{gain}"] if gain.positive?
              end
            end
          else
            (0..a.length).each do |i|
              (0..b.length).each do |j|
                left = a.take(i) + b.drop(j)
                right = b.take(j) + a.drop(i)
                next if load(left) > @capacity || load(right) > @capacity
                candidate = @routes.map(&:dup)
                candidate[r] = left
                candidate[t] = right
                gain = before - plan_length(candidate)
                next unless gain.positive?
                x = i.zero? ? 'D' : a[i - 1]
                y = j.zero? ? 'D' : b[j - 1]
                return [candidate, "cross route #{r + 1} after #{x} with route #{t + 1} after #{y} gain #{gain}"]
              end
            end
          end
        end
      end
    end
    nil
  end

  def bounds
    tree = [0]
    remaining = ids
    edges = []
    mst = 0
    until remaining.empty?
      weight, c, order = remaining.flat_map { |id| tree.each_index.map { |i| [distance(tree[i], id), id, i] } }.min
      edges << "#{name(tree[order])}-#{c}"
      mst += weight
      tree << c
      remaining.delete(c)
    end
    puts "mst: #{edges.join(' ')} (length #{mst})"
    if ids.length == 1
      one_tree = 2 * distance(0, ids.first)
    else
      tree = [ids.first]
      remaining = ids.drop(1)
      cost = 0
      until remaining.empty?
        weight, c = remaining.flat_map { |id| tree.map { |p| [distance(p, id), id] } }.min
        cost += weight
        tree << c
        remaining.delete(c)
      end
      one_tree = cost + ids.map { |id| distance(0, id) }.sort.take(2).sum
    end
    best = [mst, one_tree].max
    puts "bound: mst #{mst}, one-tree #{one_tree}, best #{best}"
    if @tour
      value = length(@tour)
      u = best.positive? ? (2000 * (value - best) + best) / (2 * best) : 0
      puts "gap: tour #{value}, #{u / 10}.#{u % 10}%"
    else
      puts 'gap: no tour'
    end
  end

  def create_plan(command, args)
    capacity = args[0].to_i
    command == 'SPLIT' ? require_tour : require_data
    check_capacity(capacity)
    if command == 'VRP' && args[1]
      limit = args[1].to_i
      id = ids.find { |c| 2 * distance(0, c) > limit }
      raise RouteError, "stop #{id} too far for limit #{limit}" if id
    end
    merges = 0
    if command == 'VRP'
      routes = ids.map { |id| [id] }
      savings = ids.combination(2).map { |i, j| [distance(0, i) + distance(0, j) - distance(i, j), i, j] }.select { |s, _, _| s.positive? }.sort_by { |s, i, j| [-s, i, j] }
      savings.each do |_, i, j|
        r = routes.index { |route| route.include?(i) }
        t = routes.index { |route| route.include?(j) }
        a = routes[r]
        b = routes[t]
        next if r == t || ![a.first, a.last].include?(i) || ![b.first, b.last].include?(j) || load(a) + load(b) > capacity
        joined = (a.first == i ? a.reverse : a) + (b.last == j ? b.reverse : b)
        next if limit && length(joined) > limit
        routes[r] = joined
        routes.delete_at(t)
        merges += 1
      end
    elsif command == 'SPLIT'
      values = [0]
      parents = []
      (1..@tour.length).each do |j|
        options = (0...j).select { |i| load(@tour[i...j]) <= capacity }.map { |i| [values[i] + length(@tour[i...j]), i] }
        values[j], parents[j] = options.min
      end
      routes = []
      j = @tour.length
      while j.positive?
        routes << @tour[parents[j]...j]
        j = parents[j]
      end
    else
      sweep = ids.sort do |a, b|
        ax, ay = point(a).zip(@depot).map { |x, d| x - d }
        bx, by = point(b).zip(@depot).map { |x, d| x - d }
        az = ax.zero? && ay.zero?
        bz = bx.zero? && by.zero?
        if az || bz
          az == bz ? a <=> b : az ? -1 : 1
        else
          ah = ay.positive? || (ay.zero? && ax.positive?) ? 0 : 1
          bh = by.positive? || (by.zero? && bx.positive?) ? 0 : 1
          cross = ax * by - ay * bx
          ah != bh ? ah <=> bh : (cross.zero? ? [distance(0, a), a] <=> [distance(0, b), b] : -cross <=> 0)
        end
      end
      routes = [[]]
      sweep.each do |id|
        routes << [] if load(routes.last) + @stops[id].demand > capacity
        routes.last << id
      end
    end
    @capacity = capacity
    @routes = routes
    normalize
    extra = command == 'VRP' ? " merges #{merges}," : ''
    puts "#{command.downcase}: capacity #{capacity},#{extra} routes #{@routes.length}, length #{plan_length}"
    route_lines
  end

  def execute(line)
    command, *args = line.split(' ')
    case command
    when 'DEPOT'
      @depot = args.map(&:to_i)
      puts "depot at (#{@depot.join(',')})"
    when 'START'
      @departure = minutes(args[0])
      puts "start #{clock(@departure)}"
    when 'STOP'
      id, x, y, demand, service = args.take(5).map(&:to_i)
      raise RouteError, "stop #{id} already exists" if @stops.key?(id)
      opening = args[5] ? minutes(args[5]) : nil
      closing = args[6] ? minutes(args[6]) : nil
      raise RouteError, 'invalid window' if opening && opening > closing
      @stops[id] = Stop.new(x, y, demand, service, opening, closing)
      @tour = @routes = nil
      puts "stop #{id} added"
    when 'REMOVE'
      id = args[0].to_i
      raise RouteError, "unknown stop #{id}" unless @stops.key?(id)
      @stops.delete(id)
      if @stops.empty?
        @tour = @routes = nil
      else
        @tour.delete(id) if @tour
        if @routes
          @routes.each { |route| route.delete(id) }
          normalize
        end
      end
      puts "stop #{id} removed"
    when 'LIST'
      puts(@depot ? "depot (#{@depot.join(',')})" : 'depot none')
      puts "start #{clock(@departure)}", "stops #{@stops.length}"
      ids.each do |id|
        s = @stops[id]
        puts "#{id} at (#{s.x},#{s.y}) demand #{s.demand} service #{s.service} window #{s.open ? clock(s.open) + '-' + clock(s.close) : 'none'}"
      end
    when 'MATRIX'
      raise RouteError, 'no depot' unless @depot
      locations = [0] + ids
      cells = [[''] + locations.map { |id| name(id) }] + locations.map { |a| [name(a)] + locations.map { |b| distance(a, b).to_s } }
      width = cells.flatten.map(&:length).max
      cells.each { |row| puts row.map { |s| s.rjust(width) }.join(' ') }
    when 'ORDER', 'NEAREST', 'INSERTION', 'EXACT'
      require_data
      if command == 'ORDER'
        route = args.map(&:to_i)
        route.each { |id| raise RouteError, "unknown stop #{id}" unless @stops.key?(id) }
        seen = []
        route.each do |id|
          raise RouteError, "duplicate stop #{id}" if seen.include?(id)
          seen << id
        end
        raise RouteError, "order has #{route.length} stops, expected #{@stops.length}" unless route.length == @stops.length
      elsif command == 'EXACT'
        raise RouteError, "too many stops for exact (#{@stops.length})" if @stops.length > 10
        route = exact
      else
        route = []
        until route.length == @stops.length
          remaining = ids - route
          if command == 'NEAREST'
            route << remaining.min_by { |id| [distance(route.last || 0, id), id] }
          else
            _, id, j = remaining.flat_map do |c|
              (0..route.length).map { |i| [length(route.take(i) + [c] + route.drop(i)) - length(route), c, i] }
            end.min
            route.insert(j, id)
          end
        end
      end
      @tour = route
      puts "#{command.downcase}: #{notation(route)} length #{length(route)}"
    when 'TOUR'
      require_tour
      puts "tour: #{notation(@tour)} length #{length(@tour)}"
    when 'TWOOPT', 'OROPT', 'SWAP'
      require_tour
      before = length(@tour)
      @tour, count = improve_tour(@tour, command)
      puts "#{command.downcase}: moves #{count}, length #{before} -> #{length(@tour)}"
    when 'TIMECHECK'
      if args.empty?
        require_tour
        puts "timecheck tour depart #{clock(@departure)}"
        simulate(@tour, true)
      else
        require_plan
        r = args[0].to_i
        raise RouteError, "no route #{r}" if r > @routes.length
        puts "timecheck route #{r} depart #{clock(@departure)}"
        simulate(@routes[r - 1], true)
      end
    when 'BOUND'
      require_data
      bounds
    when 'VRP', 'SPLIT', 'SWEEP'
      create_plan(command, args)
    when 'ROUTES'
      require_plan
      puts "plan: capacity #{@capacity}, routes #{@routes.length}, length #{plan_length}"
      route_lines
    when 'RELOCATE', 'EXCHANGE', 'CROSS'
      require_plan
      before = plan_length
      old_count = @routes.length
      count = 0
      loop do
        move = plan_move(command)
        break unless move
        @routes, message = move
        puts message
        normalize
        count += 1
      end
      extra = command == 'EXCHANGE' ? '' : " routes #{old_count} -> #{@routes.length},"
      puts "#{command.downcase}: moves #{count},#{extra} length #{before} -> #{plan_length}"
    when 'ROUTEOPT'
      require_plan
      before = plan_length
      @routes.each_index do |r|
        old = length(@routes[r])
        @routes[r], count = improve_tour(@routes[r], 'TWOOPT', false)
        puts "route #{r + 1}: moves #{count}, length #{old} -> #{length(@routes[r])}"
      end
      normalize
      puts "routeopt: length #{before} -> #{plan_length}"
    when 'REPORT'
      puts "report: stops #{@stops.length}, demand #{@stops.values.sum(&:demand)}, service #{@stops.values.sum(&:service)}, windows #{@stops.values.count { |s| s.open }}"
      if @tour
        time, violations, late = simulate(@tour)
        puts "tour: length #{length(@tour)}, return #{clock(time)}, violations #{violations}, lateness #{late}"
      else
        puts 'tour: none'
      end
      if @routes
        runs = @routes.map { |route| simulate(route) }
        denominator = @routes.length * @capacity
        u = (2000 * @routes.sum { |r| load(r) } + denominator) / (2 * denominator)
        puts "plan: capacity #{@capacity}, routes #{@routes.length}, length #{plan_length}, utilization #{u / 10}.#{u % 10}%, return #{clock(runs.map(&:first).max)}, violations #{runs.sum { |r| r[1] }}, lateness #{runs.sum { |r| r[2] }}"
      else
        puts 'plan: none'
      end
    end
  rescue RouteError => error
    puts "error: #{error.message}"
  end
end

workbench = RouteWorkbench.new
count = STDIN.gets.to_i
count.times { workbench.execute(STDIN.gets.chomp) }
