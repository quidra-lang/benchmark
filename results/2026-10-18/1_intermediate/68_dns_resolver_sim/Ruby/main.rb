class DnsError < StandardError
end

class Resolver
  TYPES = %w[A NS CNAME SOA PTR MX TXT AAAA].freeze
  KINDS = %w[ANSWER CNAME REFERRAL NODATA NXDOMAIN LAME TIMEOUT].freeze
  def initialize
    @roots = []
    @zones = []
    @current = nil
    @down = []
    @cache = {}
    @settings = { 'MINTTL' => 1, 'MAXTTL' => 86400, 'NEGTTL' => 3600 }
    @clock = @hits = 0
    @queries = {}
    @resolutions = Hash.new(0)
  end
  def error(message)
    raise DnsError, message
  end
  def labels(name)
    name == '.' ? [] : name[0...-1].split('.')
  end
  def name_key(name)
    labels(name).reverse
  end
  def below?(name, ancestor)
    ancestor == '.' || name == ancestor || name.end_with?('.' + ancestor)
  end
  def ancestors(name)
    parts = labels(name)
    (0..parts.length).map { |i| i == parts.length ? '.' : parts[i..].join('.') + '.' }
  end
  def name(word, wildcard = false, origin = nil)
    return origin if origin && word == '@'
    return '.' if word == '.'
    parts = (word.end_with?('.') ? word[0...-1] : word).split('.', -1)
    valid = parts.each_with_index.all? do |part, index|
      (wildcard && index == 0 && part == '*') || (part.length.between?(1, 63) && part.match?(/\A[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\z/))
    end
    error("bad name #{word}") unless valid
    result = parts.map(&:downcase).join('.') + '.'
    result += origin if origin && origin != '.' && !word.end_with?('.')
    result
  end
  def address(word)
    error("bad address #{word}") unless word.match?(/\A(?:0|[1-9][0-9]{0,2})(?:\.(?:0|[1-9][0-9]{0,2})){3}\z/) && word.split('.').all? { |part| part.to_i <= 255 }
    word.split('.').reduce(0) { |n, part| n * 256 + part.to_i }
  end
  def ip(number)
    [24, 16, 8, 0].map { |shift| (number >> shift) & 255 }.join('.')
  end
  def ipv6(word)
    pieces = word.split('::', -1)
    valid = pieces.length <= 2
    sides = pieces.map { |side| side.empty? ? [] : side.split(':', -1) }
    valid &&= sides.flatten.all? { |group| group.match?(/\A[0-9A-Fa-f]{1,4}\z/) }
    count = sides.flatten.length
    valid &&= pieces.length == 1 ? count == 8 : count <= 7
    error("bad address #{word}") unless valid
    groups = sides[0].map { |group| group.to_i(16) }
    groups += [0] * (8 - count) + sides[1].map { |group| group.to_i(16) } if pieces.length == 2
    groups
  end
  def ipv6_text(groups)
    best_start = nil
    best_length = 1
    index = 0
    while index < 8
      if groups[index] == 0
        finish = index
        finish += 1 while finish < 8 && groups[finish] == 0
        if finish - index > best_length
          best_start = index
          best_length = finish - index
        end
        index = finish
      else
        index += 1
      end
    end
    words = groups.map { |group| group.to_s(16) }
    return words.join(':') unless best_start
    words[0...best_start].join(':') + '::' + words[(best_start + best_length)..].join(':')
  end
  def integer?(word)
    word.match?(/\A(?:0|[1-9][0-9]{0,8})\z/)
  end
  def ttl(word)
    if integer?(word)
      seconds = word.to_i
    else
      lower = word.downcase
      error("bad ttl #{word}") unless lower.match?(/\A(?:(?:0|[1-9][0-9]{0,2})[wdhms])+\z/)
      order = 'wdhms'
      previous = -1
      seconds = 0
      lower.scan(/([0-9]+)([wdhms])/).each do |number, unit|
        rank = order.index(unit)
        error("bad ttl #{word}") unless rank > previous
        previous = rank
        seconds += number.to_i * { 'w' => 604800, 'd' => 86400, 'h' => 3600, 'm' => 60, 's' => 1 }[unit]
      end
    end
    error("bad ttl #{word}") unless seconds.between?(1, 604800)
    seconds
  end
  def check_type(type)
    error("bad type #{type}") unless TYPES.include?(type)
    type
  end
  def data_key(record)
    data = record[:data]
    case record[:type]
    when 'A', 'AAAA', 'TXT' then data
    when 'MX' then [data[0], name_key(data[1])]
    when 'SOA' then []
    else name_key(data)
    end
  end
  def sorted(records)
    records.sort_by { |record| data_key(record) }
  end
  def record_text(record, remaining = nil)
    data = record[:data]
    text = case record[:type]
           when 'A' then ip(data)
           when 'AAAA' then ipv6_text(data)
           when 'MX', 'SOA' then data.join(' ')
           else data
           end
    "#{record[:owner]} #{remaining || record[:ttl]} #{record[:type]} #{text}"
  end
  def zone_line(words, number)
    if words[0] == 'ROOT'
      added = []
      words.drop(1).each do |word|
        value = address(word)
        error("duplicate root #{word}") if @roots.include?(value) || added.include?(value)
        added << value
      end
      @roots.concat(added)
    elsif words[0] == 'ZONE'
      @current = nil
      origin = name(words[1])
      server = address(words[2])
      error("duplicate zone #{origin} at #{words[2]}") if @zones.any? { |zone| zone[:origin] == origin && zone[:server] == server }
      @current = { origin: origin, server: server, line: number, records: [] }
      @zones << @current
    else
      error('no current zone') unless @current
      owner = name(words[0], true, @current[:origin])
      error("out of zone #{owner}") unless below?(owner, @current[:origin])
      lifetime = ttl(words[1])
      type = check_type(words[2])
      fields = words.drop(3)
      count = { 'MX' => 2, 'SOA' => 7 }.fetch(type, 1)
      error('wrong field count') unless type == 'TXT' || fields.length == count
      data = case type
             when 'A' then address(fields[0])
             when 'AAAA' then ipv6(fields[0])
             when 'NS', 'CNAME', 'PTR' then name(fields[0], false, @current[:origin])
             when 'MX'
               error("bad preference #{fields[0]}") unless integer?(fields[0]) && fields[0].to_i <= 65535
               [fields[0].to_i, name(fields[1], false, @current[:origin])]
             when 'TXT'
               text = fields.join(' ')
               error("bad text #{text}") unless text.match?(/\A"[^"]*"\z/)
               text
             when 'SOA'
               values = fields[0, 2].map { |field| name(field, false, @current[:origin]) }
               fields[2, 4].each { |field| error("bad number #{field}") unless integer?(field) }
               error("bad minimum #{fields[6]}") unless integer?(fields[6]) && fields[6].to_i.between?(1, 86400)
               values + fields.drop(2).map(&:to_i)
             end
      records = @current[:records]
      error('ns at wildcard') if type == 'NS' && labels(owner)[0] == '*'
      error('soa not at origin') if type == 'SOA' && owner != @current[:origin]
      error('duplicate soa') if type == 'SOA' && records.any? { |record| record[:type] == 'SOA' }
      error('duplicate record') if records.any? { |record| record[:owner] == owner && record[:type] == type && record[:data] == data }
      conflict = records.any? { |record| record[:owner] == owner && (type == 'CNAME' || record[:type] == 'CNAME') }
      error("cname conflict #{owner}") if conflict
      records << { owner: owner, ttl: lifetime, type: type, data: data }
    end
  end
  def response(kind, answer = [], authority = [], additional = [], cut = nil)
    { kind: kind, answer: answer, authority: authority, additional: additional, cut: cut }
  end
  def authoritative(server, queried_name, type, cut)
    return response('TIMEOUT') if @down.include?(server) || @zones.none? { |zone| zone[:server] == server }
    zone = @zones.select { |item| item[:server] == server && below?(queried_name, item[:origin]) }.max_by { |item| labels(item[:origin]).length }
    return response('LAME') unless zone && labels(zone[:origin]).length >= labels(cut).length
    records = zone[:records]
    soa = records.find { |record| record[:type] == 'SOA' }
    delegation = ancestors(queried_name).reverse.find do |ancestor|
      ancestor != zone[:origin] && below?(ancestor, zone[:origin]) && records.any? { |record| record[:owner] == ancestor && record[:type] == 'NS' }
    end
    if delegation
      authority = sorted(records.select { |record| record[:owner] == delegation && record[:type] == 'NS' })
      glue = authority.flat_map { |record| sorted(records.select { |item| item[:owner] == record[:data] && item[:type] == 'A' }) }
      return response('REFERRAL', [], authority, glue, delegation)
    end
    found = records.select { |record| record[:owner] == queried_name }
    if found.empty?
      exists = ->(ancestor) { records.any? { |record| below?(record[:owner], ancestor) } }
      return response('NODATA', [], [soa]) if exists.call(queried_name)
      closest = ancestors(queried_name).drop(1).find { |ancestor| exists.call(ancestor) }
      wildcard = closest == '.' ? '*.' : '*.' + closest
      found = records.select { |record| record[:owner] == wildcard }
      return response('NXDOMAIN', [], [soa]) if found.empty?
    end
    answer = found.select { |record| record[:type] == type }
    kind = 'ANSWER'
    if answer.empty? && type != 'CNAME'
      answer = found.select { |record| record[:type] == 'CNAME' }
      kind = 'CNAME'
    end
    return response('NODATA', [], [soa]) if answer.empty?
    response(kind, sorted(answer).map { |record| record.merge(owner: queried_name) })
  end
  def describe(result)
    case result[:kind]
    when 'REFERRAL' then 'REFERRAL ' + result[:cut]
    when 'CNAME' then 'CNAME ' + result[:answer][0][:data]
    else result[:kind]
    end
  end
  def ask(server, queried_name, type, cut)
    result = authoritative(server, queried_name, type, cut)
    @queries[server] ||= Hash.new(0)
    @queries[server][result[:kind]] += 1
    result
  end
  def trace(depth, text)
    puts '  ' * (depth + 1) + text
  end
  def store(records)
    lifetime = [[records.map { |record| record[:ttl] }.min, @settings['MINTTL']].max, @settings['MAXTTL']].min
    first = records[0]
    @cache[[first[:owner], first[:type]]] = { kind: 'POS', records: sorted(records), expiry: @clock + lifetime }
    records.map { |record| record.merge(ttl: lifetime) }
  end
  def cache_records(entry)
    entry[:records].map { |record| record.merge(ttl: entry[:expiry] - @clock) }
  end
  def query_servers(queried_name, type, cut, nameservers, depth, resolving)
    if nameservers.nil?
      @roots.each do |server|
        result = ask(server, queried_name, type, cut)
        trace(depth, "ASK #{ip(server)} #{queried_name} #{type} -> #{describe(result)}")
        return result unless %w[LAME TIMEOUT].include?(result[:kind])
      end
    else
      nameservers.sort_by { |host| name_key(host) }.each do |host|
        cached = @cache[[host, 'A']]
        if cached && cached[:kind] == 'POS'
          addresses = cached[:records].map { |record| record[:data] }
        elsif resolving.include?([host, 'A'])
          trace(depth, "GLUELESS #{host} -> LOOP")
          addresses = []
        else
          trace(depth, "GLUELESS #{host}")
          status, answer = resolve(host, 'A', depth + 1, resolving)
          addresses = status == 'NOERROR' ? answer.select { |record| record[:type] == 'A' }.map { |record| record[:data] } : []
        end
        addresses.uniq.sort.each do |server|
          result = ask(server, queried_name, type, cut)
          trace(depth, "ASK #{ip(server)} #{queried_name} #{type} -> #{describe(result)}")
          return result unless %w[LAME TIMEOUT].include?(result[:kind])
        end
      end
    end
    nil
  end
  def lookup(queried_name, type, depth, resolving)
    entry = @cache[[queried_name, type]]
    if entry
      result = entry[:kind] == 'POS' ? response('ANSWER', cache_records(entry)) : response(entry[:kind])
    elsif @cache.any? { |(host, _), item| item[:kind] == 'NXDOMAIN' && below?(queried_name, host) }
      result = response('NXDOMAIN')
    elsif type != 'CNAME' && (entry = @cache[[queried_name, 'CNAME']]) && entry[:kind] == 'POS'
      result = response('CNAME', cache_records(entry))
    end
    if result
      @hits += 1
      trace(depth, "CACHE HIT #{queried_name} #{type} -> #{describe(result)}")
      return result
    end
    cut = ancestors(queried_name).find { |ancestor| (entry = @cache[[ancestor, 'NS']]) && entry[:kind] == 'POS' }
    if cut
      @hits += 1
      trace(depth, "CACHE HIT #{queried_name} #{type} -> REFERRAL #{cut}")
      servers = @cache[[cut, 'NS']][:records].map { |record| record[:data] }
    else
      cut = '.'
      servers = nil
    end
    loop do
      result = query_servers(queried_name, type, cut, servers, depth, resolving)
      return response("SERVFAIL no server for #{cut}") unless result
      case result[:kind]
      when 'REFERRAL'
        store(result[:authority])
        result[:additional].group_by { |record| record[:owner] }.each_value { |records| store(records) }
        cut = result[:cut]
        servers = result[:authority].map { |record| record[:data] }
      when 'ANSWER', 'CNAME'
        result[:answer] = store(result[:answer])
        return result
      else
        soa = result[:authority][0]
        lifetime = [soa[:ttl], soa[:data][-1], @settings['NEGTTL']].min
        @cache[[queried_name, type]] = { kind: result[:kind], expiry: @clock + lifetime }
        return result
      end
    end
  end
  def resolve(queried_name, type, depth = 0, resolving = [])
    resolving = resolving + [[queried_name, type]]
    seen = [queried_name]
    chain = []
    current = queried_name
    status = nil
    answer = []
    loop do
      result = lookup(current, type, depth, resolving)
      kind = result[:kind]
      if kind == 'CNAME'
        record = result[:answer][0]
        chain << record
        target = record[:data]
        if seen.include?(target)
          status = 'SERVFAIL cname loop'
          answer = []
          break
        elsif chain.length == 9
          status = 'SERVFAIL cname chain too long'
          answer = []
          break
        end
        seen << target
        current = target
      else
        status = kind == 'ANSWER' ? 'NOERROR' : kind
        answer = status.start_with?('SERVFAIL') ? [] : chain + result[:answer]
        break
      end
    end
    @resolutions[status.start_with?('SERVFAIL') ? 'SERVFAIL' : status] += 1
    [status, answer]
  end
  def print_result(status, answer)
    answer.each { |record| puts 'answer ' + record_text(record) }
    puts "status #{status}"
  end
  def address_resolution(host)
    output = []
    %w[A AAAA].each do |type|
      status, answer = resolve(host, type)
      next unless status == 'NOERROR'
      output.concat(answer.select { |record| record[:type] == type }.map { |record| type == 'A' ? ip(record[:data]) : ipv6_text(record[:data]) })
    end
    output.empty? ? 'no address' : output.join(' ')
  end
  def command(words)
    kind = words[0]
    case kind
    when 'RESOLVE', 'MX'
      queried_name = name(words[1], true)
      type = kind == 'MX' ? 'MX' : check_type(words[2])
      puts "#{kind.downcase} #{queried_name}" + (kind == 'MX' ? '' : " #{type}")
      status, answer = resolve(queried_name, type)
      print_result(status, answer)
      if kind == 'MX' && status == 'NOERROR'
        answer.select { |record| record[:type] == 'MX' }.each do |record|
          preference, host = record[:data]
          puts "exchange #{preference} #{host} -> #{host == '.' ? 'null' : address_resolution(host)}"
        end
      elsif kind == 'MX' && status == 'NODATA'
        cnames = answer.select { |record| record[:type] == 'CNAME' }
        host = cnames.empty? ? queried_name : cnames[-1][:data]
        puts "implicit #{host} -> #{address_resolution(host)}"
      end
    when 'REVERSE'
      if words[1].include?(':')
        groups = ipv6(words[1])
        text = ipv6_text(groups)
        reverse = groups.map { |group| format('%04x', group) }.join.reverse.chars.join('.') + '.ip6.arpa.'
      else
        value = address(words[1])
        text = ip(value)
        reverse = text.split('.').reverse.join('.') + '.in-addr.arpa.'
      end
      puts "reverse #{text} #{reverse}"
      print_result(*resolve(reverse, 'PTR'))
    when 'QUERY', 'DUMP'
      server = address(words[1])
      queried_name = name(words[2], kind == 'QUERY')
      if kind == 'QUERY'
        type = check_type(words[3])
        result = ask(server, queried_name, type, '.')
        puts "query #{ip(server)} #{queried_name} #{type} -> #{describe(result)}"
        %i[answer authority additional].each { |section| result[section].each { |record| puts "#{section} #{record_text(record)}" } }
      else
        zone = @zones.find { |item| item[:server] == server && item[:origin] == queried_name }
        if @down.include?(server) || @zones.none? { |item| item[:server] == server }
          puts "dump #{ip(server)} #{queried_name} -> TIMEOUT"
        elsif !zone
          puts "dump #{ip(server)} #{queried_name} -> REFUSED"
        else
          puts "dump #{ip(server)} #{queried_name} records=#{zone[:records].length}"
          zone[:records].sort_by { |record| [name_key(record[:owner]), TYPES.index(record[:type]), data_key(record)] }.each { |record| puts '  ' + record_text(record) }
        end
      end
    when 'DOWN', 'UP'
      server = address(words[1])
      error("server #{words[1]} already down") if kind == 'DOWN' && @down.include?(server)
      error("server #{words[1]} not down") if kind == 'UP' && !@down.include?(server)
      kind == 'DOWN' ? @down.push(server) : @down.delete(server)
      puts "#{kind.downcase} #{ip(server)}"
    when 'SET'
      key, word = words[1, 2]
      error("bad setting #{key}") unless @settings.key?(key)
      error("bad value #{word}") unless integer?(word) && word.to_i.between?(1, 604800)
      settings = @settings.merge(key => word.to_i)
      error('minttl above maxttl') if settings['MINTTL'] > settings['MAXTTL']
      @settings = settings
      puts "set #{key}=#{word.to_i}"
    when 'TIME'
      word = words[1]
      error("bad time #{word}") unless integer?(word) && word.to_i.between?(1, 1000000)
      @clock += word.to_i
      before = @cache.length
      @cache.delete_if { |_, item| item[:expiry] <= @clock }
      puts "time now=#{@clock} expired=#{before - @cache.length}"
    when 'CACHE', 'FLUSH'
      selected_name = words[1] ? name(words[1]) : nil
      entries = @cache.select { |(host, _), _| selected_name.nil? || below?(host, selected_name) }
      if kind == 'FLUSH'
        entries.each_key { |key| @cache.delete(key) }
        puts "flush removed=#{entries.length}"
      else
        puts "cache entries=#{entries.length}"
        entries.sort_by { |(host, type), _| [name_key(host), TYPES.index(type)] }.each do |(host, type), entry|
          remaining = entry[:expiry] - @clock
          if entry[:kind] == 'POS'
            entry[:records].each { |record| puts '  ' + record_text(record, remaining) }
          else
            puts "  #{host} #{remaining} #{type} #{entry[:kind]}"
          end
        end
      end
    when 'STATS'
      puts "stats queries=#{@queries.values.sum { |counts| counts.values.sum }} hits=#{@hits}"
      @queries.keys.sort.each do |server|
        counts = @queries[server]
        puts "  #{ip(server)} sent=#{counts.values.sum} " + KINDS.map { |response| "#{response.downcase}=#{counts[response]}" }.join(' ')
      end
      puts 'resolutions ' + %w[NOERROR NODATA NXDOMAIN SERVFAIL].map { |status| "#{status.downcase}=#{@resolutions[status]}" }.join(' ')
    end
  end
  def run
    lines = STDIN.each_line.map { |line| line.chomp("\n").delete_suffix("\r") }
    zones = true
    lines.each_with_index do |line, index|
      break if !zones && line == 'END'
      if zones && line == 'END ZONES'
        @zones = @zones.select do |zone|
          valid = zone[:records].any? { |record| record[:type] == 'SOA' }
          if valid
            puts "zone #{zone[:origin]} at #{ip(zone[:server])} records=#{zone[:records].length}"
          else
            puts "error line #{zone[:line]}: zone #{zone[:origin]} at #{ip(zone[:server])} has no soa"
          end
          valid
        end
        puts "loaded roots=#{@roots.length} zones=#{@zones.length} records=#{@zones.sum { |zone| zone[:records].length }}"
        zones = false
        next
      end
      begin
        zones ? zone_line(line.split(' '), index + 1) : command(line.split(' '))
      rescue DnsError => exception
        puts "error line #{index + 1}: #{exception.message}"
      end
    end
  end
end

Resolver.new.run
