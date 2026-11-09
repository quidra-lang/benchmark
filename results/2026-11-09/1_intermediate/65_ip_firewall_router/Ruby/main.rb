class RouterError < StandardError
end

class Router
  DROP_REASONS = %w[down martian rpf invalid acl_in ttl noroute acl_out exhausted].freeze

  def initialize
    @interfaces = {}
    @routes = []
    @static = []
    @forwards = []
    @pat = []
    @connections = []
    @timeouts = { 'TCP' => 300, 'UDP' => 60, 'ICMP' => 30 }
    @clock = @packet_number = @connection_number = 0
    reset_counters
  end

  def error(message)
    raise RouterError, message
  end

  def address(word)
    error("bad address #{word}") unless word.match?(/\A(?:0|[1-9][0-9]{0,2})(?:\.(?:0|[1-9][0-9]{0,2})){3}\z/) && word.split('.').all? { |part| part.to_i <= 255 }
    word.split('.').reduce(0) { |value, part| value * 256 + part.to_i }
  end

  def ip(value)
    [24, 16, 8, 0].map { |shift| (value >> shift) & 255 }.join('.')
  end

  def network(value, length)
    size = 2**(32 - length)
    value / size * size
  end

  def prefix(word, hosts = false)
    pieces = word.split('/', -1)
    begin
      valid = pieces.length == 2 && pieces[1].match?(/\A(?:0|[1-9][0-9]?)\z/) && pieces[1].to_i <= 32
      error('invalid') unless valid
      value = address(pieces[0])
    rescue RouterError
      error("bad prefix #{word}")
    end
    length = pieces[1].to_i
    error("host bits set in #{word}") if !hosts && value != network(value, length)
    [value, length]
  end

  def contains?(prefix, value)
    network(prefix[0], prefix[1]) == network(value, prefix[1])
  end

  def iface(name)
    error("no interface #{name}") unless @interfaces.key?(name)
    @interfaces[name]
  end

  def local(value)
    @interfaces.find { |_name, item| item[:address] == value }&.first
  end

  def route(value)
    @routes.each_with_index.select { |item, _| @interfaces[item[:dev]][:up] && contains?(item[:prefix], value) }
           .min_by { |item, index| [-item[:prefix][1], item[:metric], index] }&.first
  end

  def route_text(item)
    text = "#{item[:type]} #{ip(item[:prefix][0])}/#{item[:prefix][1]}"
    text += " via #{ip(item[:hop])}" if item[:hop]
    text + " dev #{item[:dev]} metric #{item[:metric]}"
  end

  def port_range(word)
    return [0, 65535, true] if word == 'ANY'
    numbers = word.split('-').map(&:to_i)
    low = numbers[0]
    high = numbers.fetch(1, low)
    error("bad port range #{word}") if high > 65535 || low > 65535 || low > high
    [low, high, false]
  end

  def range_text(range)
    return 'any' if range[2]
    range[0] == range[1] ? range[0].to_s : "#{range[0]}-#{range[1]}"
  end

  def acl_prefix(word)
    word == 'ANY' ? [0, 0] : prefix(word)
  end

  def prefix_text(value)
    value[1] == 0 ? 'any' : "#{ip(value[0])}/#{value[1]}"
  end

  def acl(name, direction, protocol, source, sport, destination, dport, established)
    pair = @interfaces[name][:acl][direction]
    return nil if pair[:rules].empty?
    rule = pair[:rules].sort_by { |item| item[:seq] }.find do |item|
      (item[:proto] == 'ANY' || item[:proto] == protocol) && contains?(item[:src], source) && contains?(item[:dst], destination) &&
        (!%w[TCP UDP].include?(item[:proto]) || (sport.between?(item[:sports][0], item[:sports][1]) && dport.between?(item[:dports][0], item[:dports][1]))) &&
        (!item[:established] || established)
    end
    unless rule
      pair[:default] += 1
      return "DROP acl #{name} #{direction} default"
    end
    rule[:hits] += 1
    case rule[:action]
    when 'PERMIT' then nil
    when 'DENY' then "DROP acl #{name} #{direction} #{rule[:seq]}"
    else "REJECT acl #{name} #{direction} #{rule[:seq]} #{protocol == 'TCP' ? 'tcp-reset' : 'icmp-prohibited'}"
    end
  end

  def packet(name, protocol, flags, source, sport, destination, dport, ttl)
    input = @interfaces[name]
    return ['DROP down', 'down'] unless input[:up]
    martian = [source, destination].any? { |value| contains?([0, 8], value) || contains?([127 * 2**24, 8], value) || contains?([224 * 2**24, 3], value) }
    return ['DROP martian', 'martian'] if martian || local(source)
    if input[:rpf] != 'off'
      reverse = route(source)
      return ['DROP rpf', 'rpf'] unless reverse && (input[:rpf] != 'strict' || reverse[:dev] == name)
    end
    tuple = [protocol, source, sport, destination, dport]
    pure_syn = protocol == 'TCP' && flags == 'S'
    connection = nil
    direction = nil
    @connections.each do |item|
      if item[:orig] == tuple || item[:reply] == tuple
        connection = item
        direction = item[:orig] == tuple ? 'orig' : 'reply'
        break
      end
    end
    if connection && connection[:state] == 'CLOSED' && pure_syn
      @connections.delete(connection)
      connection = nil
    end
    return ['DROP invalid', 'invalid'] if protocol == 'TCP' && !connection && !pure_syn
    verdict = acl(name, 'in', protocol, source, sport, destination, dport, !connection.nil?)
    return [verdict, 'acl_in'] if verdict
    translated_destination = destination
    translated_dport = dport
    mapping = nil
    if input[:role] == 'outside'
      static = @static.find { |item| item[:outside] == destination }
      forward = @forwards.find { |item| item[:dev] == name && item[:proto] == protocol && item[:port] == dport } if destination == input[:address]
      if static
        translated_destination = static[:inside]
      elsif forward
        translated_destination = forward[:inside]
        translated_dport = forward[:inport]
      elsif destination == input[:address]
        mapping = @pat.find { |item| item[:dev] == name && item[:proto] == protocol && item[:port] == dport }
        if mapping
          translated_destination = mapping[:inside]
          translated_dport = mapping[:inport]
        end
      end
    end
    local_name = local(translated_destination)
    return ["LOCAL #{local_name}", 'local'] if local_name
    return ['DROP ttl', 'ttl'] if ttl == 1
    selected = route(translated_destination)
    return ['DROP noroute', 'noroute'] unless selected
    output_name = selected[:dev]
    output = @interfaces[output_name]
    verdict = acl(output_name, 'out', protocol, source, sport, translated_destination, translated_dport, !connection.nil?)
    return [verdict, 'acl_out'] if verdict
    translated_source = source
    translated_sport = sport
    if input[:role] == 'inside' && output[:role] == 'outside'
      static = @static.find { |item| item[:inside] == source }
      forward = @forwards.find { |item| item[:dev] == output_name && item[:proto] == protocol && item[:inside] == source && item[:inport] == sport }
      if static
        translated_source = static[:outside]
      elsif forward
        translated_source = output[:address]
        translated_sport = forward[:port]
      elsif output[:pool]
        mapping = @pat.find { |item| item[:dev] == output_name && item[:proto] == protocol && item[:inside] == source && item[:inport] == sport }
        unless mapping
          used = @pat.select { |item| item[:dev] == output_name }.map { |item| item[:port] } + @forwards.select { |item| item[:dev] == output_name }.map { |item| item[:port] }
          port = (20000...(20000 + output[:pool])).find { |candidate| !used.include?(candidate) }
          return ['DROP exhausted', 'exhausted'] unless port
          mapping = { dev: output_name, proto: protocol, inside: source, inport: sport, port: port, last: @clock }
          @pat << mapping
        end
        translated_source = output[:address]
        translated_sport = mapping[:port]
      end
    end
    mapping[:last] = @clock if mapping
    unless connection
      @connection_number += 1
      connection = { number: @connection_number, proto: protocol, orig: tuple,
                     reply: [protocol, translated_destination, translated_dport, translated_source, translated_sport],
                     input: name, output: output_name, state: protocol == 'TCP' ? 'SYN_SENT' : 'UNREPLIED',
                     orig_packets: 0, reply_packets: 0, orig_fin: false, reply_fin: false, last: @clock }
      @connections << connection
      direction = 'new'
    end
    side = direction == 'reply' ? :reply : :orig
    connection[side == :reply ? :reply_packets : :orig_packets] += 1
    connection[:last] = @clock
    if protocol != 'TCP'
      connection[:state] = 'REPLIED' if direction == 'reply'
    elsif flags.include?('R')
      connection[:state] = 'CLOSED'
    else
      if connection[:state] == 'SYN_SENT' && direction == 'reply' && flags.include?('S') && flags.include?('A')
        connection[:state] = 'ESTABLISHED'
      end
      if flags.include?('F') && %w[ESTABLISHED FIN_WAIT].include?(connection[:state])
        connection[side == :reply ? :reply_fin : :orig_fin] = true
        connection[:state] = connection[:orig_fin] && connection[:reply_fin] ? 'CLOSED' : 'FIN_WAIT'
      end
    end
    output[:tx] += 1
    selected[:hits] += 1
    next_hop = selected[:hop] ? "via #{ip(selected[:hop])}" : 'direct'
    text = "FORWARD #{output_name} #{next_hop} ttl=#{ttl - 1}"
    text += " dnat=#{ip(translated_destination)}:#{translated_dport}" if [translated_destination, translated_dport] != [destination, dport]
    text += " snat=#{ip(translated_source)}:#{translated_sport}" if [translated_source, translated_sport] != [source, sport]
    [text + " conn=#{connection[:number]} #{direction}", 'forwarded']
  end

  def reset_counters
    @counts = { 'forwarded' => 0, 'local' => 0, 'errors' => 0 }
    DROP_REASONS.each { |reason| @counts[reason] = 0 }
    @interfaces.each_value do |item|
      item[:rx] = item[:tx] = item[:drop] = 0
      item[:acl].each_value do |pair|
        pair[:default] = 0
        pair[:rules].each { |rule| rule[:hits] = 0 }
      end
    end
    @routes.each { |item| item[:hits] = 0 }
  end

  def show(what)
    names = @interfaces.keys.sort
    case what
    when 'IFACES'
      puts "show ifaces count=#{names.length}"
      names.each do |name|
        item = @interfaces[name]
        text = "#{name} #{ip(item[:address])}/#{item[:length]} #{item[:up] ? 'up' : 'down'} #{item[:role]} rpf=#{item[:rpf]}"
        text += " pat=#{@pat.count { |mapping| mapping[:dev] == name }}/#{item[:pool]}" if item[:pool]
        puts text
      end
    when 'ROUTES'
      puts "show routes count=#{@routes.length}"
      @routes.each_with_index.sort_by { |item, index| [item[:prefix][0], item[:prefix][1], item[:metric], index] }.each do |item, _|
        puts route_text(item) + " hits=#{item[:hits]}" + (@interfaces[item[:dev]][:up] ? '' : ' inactive')
      end
    when 'ACL'
      puts "show acl count=#{@interfaces.values.sum { |item| item[:acl].values.sum { |pair| pair[:rules].length } }}"
      names.each do |name|
        %w[in out].each do |direction|
          pair = @interfaces[name][:acl][direction]
          next if pair[:rules].empty?
          pair[:rules].sort_by { |rule| rule[:seq] }.each do |rule|
            puts "acl #{name} #{direction} #{rule[:seq]} #{rule[:action]} #{rule[:proto]} #{prefix_text(rule[:src])} #{range_text(rule[:sports])} #{prefix_text(rule[:dst])} #{range_text(rule[:dports])}" + (rule[:established] ? ' established' : '') + " hits=#{rule[:hits]}"
          end
          puts "acl #{name} #{direction} default DENY hits=#{pair[:default]}"
        end
      end
    when 'NAT'
      puts "show nat static=#{@static.length} forward=#{@forwards.length} pat=#{@pat.length}"
      @static.sort_by { |item| item[:inside] }.each { |item| puts "static #{ip(item[:inside])} #{ip(item[:outside])}" }
      @forwards.sort_by { |item| [item[:dev], item[:port], item[:proto]] }.each { |item| puts "forward #{item[:dev]} #{item[:proto]} #{item[:port]} #{ip(item[:inside])}:#{item[:inport]}" }
      @pat.sort_by { |item| [item[:dev], item[:port]] }.each { |item| puts "pat #{item[:dev]} #{item[:port]} #{item[:proto]} #{ip(item[:inside])}:#{item[:inport]} idle=#{@clock - item[:last]}" }
    when 'CONNS'
      puts "show conns count=#{@connections.length}"
      @connections.each do |item|
        _, source, sport, destination, dport = item[:orig]
        _, reply_source, reply_sport, reply_destination, reply_dport = item[:reply]
        puts "conn #{item[:number]} #{item[:proto]} #{ip(source)}:#{sport} > #{ip(destination)}:#{dport} reply #{ip(reply_source)}:#{reply_sport} > #{ip(reply_destination)}:#{reply_dport} in=#{item[:input]} out=#{item[:output]} state=#{item[:state]} pkts=#{item[:orig_packets]}/#{item[:reply_packets]} idle=#{@clock - item[:last]}"
      end
    when 'COUNTERS'
      dropped = DROP_REASONS.sum { |reason| @counts[reason] }
      puts "show counters packets=#{@counts['forwarded'] + @counts['local'] + dropped} forwarded=#{@counts['forwarded']} local=#{@counts['local']} dropped=#{dropped} errors=#{@counts['errors']}"
      puts 'drops ' + DROP_REASONS.map { |reason| "#{reason}=#{@counts[reason]}" }.join(' ')
      names.each do |name|
        item = @interfaces[name]
        puts "iface #{name} rx=#{item[:rx]} tx=#{item[:tx]} drop=#{item[:drop]}"
      end
    end
  end

  def command(words)
    kind, *args = words
    name = args[0]
    case kind
    when 'IFACE'
      error("duplicate interface #{name}") if @interfaces.key?(name)
      value, length = prefix(args[1], true)
      error("bad prefix #{args[1]}") unless length.between?(8, 30)
      base = network(value, length)
      error("bad host address #{args[1]}") if value == base || value == base + 2**(32 - length) - 1
      overlap = @interfaces.find { |_key, item| network(value, [length, item[:length]].min) == network(item[:address], [length, item[:length]].min) }
      error("subnet overlaps #{overlap[0]}") if overlap
      @interfaces[name] = { address: value, length: length, up: true, role: 'inside', pool: nil, rpf: 'off', rx: 0, tx: 0, drop: 0,
                            acl: { 'in' => { rules: [], default: 0 }, 'out' => { rules: [], default: 0 } } }
      @routes << { type: 'C', prefix: [base, length], dev: name, hop: nil, metric: 0, hits: 0 }
      puts "ok iface #{name} #{args[1]} network #{ip(base)}/#{length}"
    when 'UP', 'DOWN'
      item = iface(name)
      state = kind == 'UP'
      error("interface #{name} already #{state ? 'up' : 'down'}") if item[:up] == state
      item[:up] = state
      puts "ok #{kind.downcase} #{name}"
    when 'ROUTE'
      destination = prefix(name)
      via = args[1] == 'VIA'
      hop = via ? address(args[2]) : nil
      iface(args[2]) unless via
      metric = args[3].to_i
      error("bad metric #{args[3]}") unless metric.between?(1, 255)
      if via
        error("nexthop #{args[2]} is local") if local(hop)
        output = @interfaces.find { |_key, item| contains?([item[:address], item[:length]], hop) }&.first
        error("nexthop #{args[2]} unreachable") unless output
      else
        output = args[2]
      end
      error("duplicate route #{name}") if @routes.any? { |item| item[:type] == 'S' && item[:prefix] == destination && item[:dev] == output && item[:hop] == hop }
      item = { type: 'S', prefix: destination, dev: output, hop: hop, metric: metric, hits: 0 }
      @routes << item
      puts "ok route #{route_text(item)}"
    when 'NOROUTE'
      destination = prefix(name)
      removed = @routes.count { |item| item[:type] == 'S' && item[:prefix] == destination }
      error("no static route #{name}") if removed == 0
      @routes.reject! { |item| item[:type] == 'S' && item[:prefix] == destination }
      puts "ok noroute #{name} removed=#{removed}"
    when 'LOOKUP'
      selected = route(address(name))
      puts "lookup #{name} #{selected ? route_text(selected) : 'none'}"
    when 'ACL'
      item = iface(name)
      direction = args[1].downcase
      sequence = args[2].to_i
      error("bad sequence #{args[2]}") unless sequence.between?(1, 9999)
      source = acl_prefix(args[5])
      sports = port_range(args[6])
      destination = acl_prefix(args[7])
      dports = port_range(args[8])
      error("ports not allowed for #{args[4]}") if %w[ICMP ANY].include?(args[4]) && (args[6] != 'ANY' || args[8] != 'ANY')
      pair = item[:acl][direction]
      error("duplicate sequence #{args[2]}") if pair[:rules].any? { |rule| rule[:seq] == sequence }
      pair[:rules] << { seq: sequence, action: args[3], proto: args[4], src: source, sports: sports, dst: destination, dports: dports, established: args.length == 10, hits: 0 }
      puts "ok acl #{name} #{direction} #{sequence}"
    when 'NOACL'
      pair = iface(name)[:acl][args[1].downcase]
      rule = pair[:rules].find { |item| item[:seq] == args[2].to_i }
      error("no rule #{args[2]} on #{name} #{args[1].downcase}") unless rule
      pair[:rules].delete(rule)
      puts "ok noacl #{name} #{args[1].downcase} #{args[2]} hits=#{rule[:hits]}"
    when 'NAT'
      case name
      when 'STATIC'
        inside = address(args[1])
        outside = address(args[2])
        [1, 2].each { |index| error("address #{args[index]} is local") if local(index == 1 ? inside : outside) }
        error("duplicate static #{args[1]}") if @static.any? { |item| item[:inside] == inside }
        error("duplicate static #{args[2]}") if @static.any? { |item| item[:outside] == outside }
        @static << { inside: inside, outside: outside }
        puts "ok nat static #{args[1]} #{args[2]}"
      when 'OUTSIDE'
        item = iface(args[1])
        error("interface #{args[1]} already outside") if item[:role] == 'outside'
        item[:role] = 'outside'
        puts "ok nat outside #{args[1]}"
      when 'PAT'
        item = iface(args[1])
        count = args[2].to_i
        error("bad pool size #{args[2]}") unless count.between?(1, 1000)
        error("pat already on #{args[1]}") if item[:pool]
        item[:pool] = count
        item[:role] = 'outside'
        puts "ok nat pat #{args[1]} #{ip(item[:address])} 20000-#{19999 + count}"
      when 'FORWARD'
        item = iface(args[1])
        port = args[3].to_i
        error("bad port #{args[3]}") unless port.between?(1, 65535)
        inside = address(args[4])
        inport = args[5].to_i
        error("bad port #{args[5]}") unless inport.between?(1, 65535)
        error("interface #{args[1]} not outside") unless item[:role] == 'outside'
        error("address #{args[4]} is local") if local(inside)
        error("duplicate forward #{args[1]} #{args[2]} #{args[3]}") if @forwards.any? { |rule| rule[:dev] == args[1] && rule[:proto] == args[2] && rule[:port] == port }
        @forwards << { dev: args[1], proto: args[2], port: port, inside: inside, inport: inport }
        puts "ok nat forward #{args[1]} #{args[2]} #{port} #{args[4]}:#{inport}"
      end
    when 'RPF'
      iface(name)[:rpf] = args[1].downcase
      puts "ok rpf #{name} #{args[1].downcase}"
    when 'TIMEOUT'
      error("bad timeout #{args[1]}") unless args[1].to_i.between?(1, 86400)
      @timeouts[name] = args[1].to_i
      puts "ok timeout #{name} #{args[1]}"
    when 'TICK'
      error("bad tick #{name}") unless name.to_i.between?(1, 86400)
      @clock += name.to_i
      conns = @connections.length
      mappings = @pat.length
      @connections.reject! do |item|
        timeout = item[:proto] == 'TCP' ? { 'SYN_SENT' => 60, 'FIN_WAIT' => 60, 'CLOSED' => 10 }.fetch(item[:state], @timeouts['TCP']) : @timeouts[item[:proto]]
        @clock - item[:last] >= timeout
      end
      @pat.reject! { |item| @clock - item[:last] >= @timeouts[item[:proto]] }
      puts "ok tick time=#{@clock} expired conns=#{conns - @connections.length} nat=#{mappings - @pat.length}"
    when 'PACKET'
      item = iface(name)
      protocol, flags = args[1], args[2]
      error("flags not allowed for #{protocol}") if protocol != 'TCP' && flags != '-'
      error("bad flags #{flags}") if protocol == 'TCP' && flags != '-' && (!flags.match?(/\A[SAFR]+\z/) || flags.chars.uniq.length != flags.length)
      source = address(args[3])
      sport = args[4].to_i
      error("bad port #{args[4]}") unless sport.between?(0, 65535)
      destination = address(args[5])
      dport = args[6].to_i
      error("bad port #{args[6]}") unless dport.between?(0, 65535)
      ttl = args[7].to_i
      error("bad ttl #{args[7]}") unless ttl.between?(1, 255)
      @packet_number += 1
      item[:rx] += 1
      verdict, reason = packet(name, protocol, flags, source, sport, destination, dport, ttl)
      @counts[reason] += 1
      item[:drop] += 1 if DROP_REASONS.include?(reason)
      puts "##{@packet_number} #{protocol} #{flags} #{args[3]}:#{args[4]} > #{args[5]}:#{args[6]} #{verdict}"
    when 'SHOW'
      show(name)
    when 'CLEAR'
      if name == 'COUNTERS'
        reset_counters
        puts 'ok clear counters'
      else
        puts "ok clear conns=#{@connections.length} nat=#{@pat.length}"
        @connections.clear
        @pat.clear
      end
    end
  end

  def run
    count = STDIN.readline.to_i
    count.times do
      begin
        command(STDIN.readline.split)
      rescue RouterError => exception
        @counts['errors'] += 1
        puts "error: #{exception.message}"
      end
    end
  end
end

Router.new.run
