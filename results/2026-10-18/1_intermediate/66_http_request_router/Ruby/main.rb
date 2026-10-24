class ConfigurationError < StandardError
end

class UrlError < StandardError
end

class HttpRouter
  VALID_NAME = /\A[a-z][a-z0-9_]{0,19}\z/
  ROLE = /\A[a-z]{1,16}\z/
  MEDIA = /\A[a-z0-9.+-]+\/[a-z0-9.+-]+\z/
  SEGMENT = /\A[A-Za-z0-9._~-]+\z/
  REASONS = { 200 => 'OK', 204 => 'No Content', 301 => 'Moved Permanently', 302 => 'Found', 304 => 'Not Modified',
              307 => 'Temporary Redirect', 308 => 'Permanent Redirect', 400 => 'Bad Request', 401 => 'Unauthorized',
              403 => 'Forbidden', 404 => 'Not Found', 405 => 'Method Not Allowed', 406 => 'Not Acceptable',
              412 => 'Precondition Failed', 429 => 'Too Many Requests', 501 => 'Not Implemented' }.freeze
  HEADERS = %w[Location Allow Retry-After WWW-Authenticate Access-Control-Allow-Origin Access-Control-Allow-Methods Vary ETag Content-Type Content-Length].freeze

  def initialize
    @routes = []
    @tokens = {}
    @redirects = []
    @origins = []
    @limit = nil
    @errors = 0
    @clients = {}
    @statuses = Hash.new(0)
    @requests = @url_ok = @url_error = 0
  end

  def segment?(text)
    SEGMENT.match?(text) && !%w[. ..].include?(text)
  end

  def canonical?(text)
    text == '/' || (text.start_with?('/') && text[1..].split('/', -1).all? { |part| segment?(part) })
  end

  def pattern(text)
    return [] if text == '/'
    return nil unless text.start_with?('/')
    parts = text[1..].split('/', -1)
    names = []
    pieces = []
    parts.each_with_index do |part, index|
      if segment?(part)
        pieces << [:literal, part]
      else
        match = /\A\{(\*?)([a-z][a-z0-9_]{0,19})(?::(int|slug))?\}\z/.match(part)
        return nil unless match
        star, name, type = match.captures
        return nil if names.include?(name) || (star == '*' && (type || index != parts.length - 1))
        names << name
        pieces << [star == '*' ? :wildcard : (type ? type.to_sym : :parameter), name]
      end
    end
    pieces
  end

  def config_error(message)
    raise ConfigurationError, message
  end

  def configure(line, number)
    command, *args = line.split(' ')
    counts = { 'ROUTE' => [3, 5], 'TOKEN' => [2], 'REDIRECT' => [3], 'ORIGIN' => [1], 'LIMIT' => [2] }
    config_error("unknown command #{command}") unless counts.key?(command) || command == 'TYPES'
    correct_count = command == 'TYPES' ? args.length >= 2 : counts[command].include?(args.length)
    config_error('wrong number of arguments') unless correct_count
    case command
    when 'ROUTE'
      name, methods, path = args
      config_error("bad route name #{name}") unless VALID_NAME.match?(name)
      config_error("duplicate route #{name}") if @routes.any? { |route| route[:name] == name }
      method_list = methods.split(',', -1)
      config_error("bad methods #{methods}") unless method_list.all? { |method| %w[GET POST PUT PATCH DELETE].include?(method) } && method_list.uniq.length == method_list.length
      pieces = pattern(path)
      config_error("bad pattern #{path}") unless pieces
      config_error("unknown option #{args[3]}") if args.length == 5 && args[3] != 'ROLE'
      config_error("bad role #{args[4]}") if args.length == 5 && !ROLE.match?(args[4])
      @routes << { name: name, methods: method_list, pattern: path, pieces: pieces, role: args.length == 5 ? args[4] : 'none', types: nil, hits: 0, number: @routes.length }
    when 'TOKEN'
      token, role = args
      config_error("bad token #{token}") unless token.match?(/\A[A-Za-z0-9._-]{1,32}\z/)
      config_error("duplicate token #{token}") if @tokens.key?(token)
      config_error("bad role #{role}") unless ROLE.match?(role)
      @tokens[token] = role
    when 'REDIRECT'
      from, to, code = args
      [from, to].each do |path|
        base = path.end_with?('/*') ? path[0...-2] : path
        config_error("bad path #{path}") unless canonical?(base) && (!path.end_with?('/*') || base != '/')
      end
      config_error('wildcard mismatch') unless from.end_with?('/*') == to.end_with?('/*')
      config_error("bad redirect code #{code}") unless %w[301 302 307 308].include?(code)
      config_error("duplicate redirect #{from}") if @redirects.any? { |rule| rule[:from] == from }
      star = from.end_with?('/*')
      @redirects << { from: from, base: star ? from[0...-2] : from, to: star ? to[0...-2] : to, wildcard: star, code: code.to_i }
    when 'ORIGIN'
      origin = args[0]
      config_error("bad origin #{origin}") unless origin.match?(/\Ahttps?:\/\/[a-z0-9.:-]+\z/)
      config_error("duplicate origin #{origin}") if @origins.include?(origin)
      @origins << origin
    when 'LIMIT'
      valid = args.all? { |word| word.match?(/\A[1-9][0-9]*\z/) } && args[0].to_i.between?(1, 100) && args[1].to_i.between?(1, 3600)
      config_error('bad limit') unless valid
      config_error('duplicate limit') if @limit
      @limit = args.map(&:to_i)
    when 'TYPES'
      name, *types = args
      route = @routes.find { |item| item[:name] == name }
      config_error("unknown route #{name}") unless route
      config_error("duplicate types #{name}") if route[:types]
      seen = []
      types.each do |type|
        config_error("bad media type #{type}") unless MEDIA.match?(type)
        config_error("duplicate media type #{type}") if seen.include?(type)
        seen << type
      end
      route[:types] = types
    end
  rescue ConfigurationError => error
    @errors += 1
    puts "CONFIG ERROR #{number}: #{error.message}"
  end

  def priority(route)
    pieces = route[:pieces]
    [-pieces.count { |kind, _| kind == :literal }, -pieces.count { |kind, _| [:int, :slug].include?(kind) }, pieces.any? { |kind, _| kind == :wildcard } ? 1 : 0, route[:number]]
  end

  def decode(text)
    text.gsub(/%([0-9A-Fa-f]{2})/) { Regexp.last_match(1).to_i(16).chr }
  end

  def encode(text)
    text.each_char.map { |char| char.match?(/[A-Za-z0-9._~-]/) ? char : format('%%%02X', char.ord) }.join
  end

  def normalize(path)
    path = path.gsub(/%([0-9A-Fa-f]{2})/) do
      char = Regexp.last_match(1).to_i(16).chr
      char.match?(/[A-Za-z0-9._~-]/) ? char : format('%%%02X', char.ord)
    end
    parts = []
    path[1..].split('/', -1).each do |part|
      if part == '..'
        parts.pop
      elsif part != '' && part != '.'
        parts << part
      end
    end
    '/' + parts.join('/')
  end

  def match_route(route, segments)
    pieces = route[:pieces]
    wildcard = !pieces.empty? && pieces[-1][0] == :wildcard
    count = pieces.length - (wildcard ? 1 : 0)
    length_fits = wildcard ? segments.length >= count : segments.length == count
    return nil unless length_fits
    parameters = {}
    pieces.each_with_index do |(kind, name), index|
      text = segments[index]
      case kind
      when :literal
        return nil unless text == name
      when :parameter
        parameters[name] = decode(text)
      when :int
        return nil unless text.match?(/\A[0-9]{1,9}\z/)
        parameters[name] = text.to_i.to_s
      when :slug
        return nil unless text.match?(/\A[a-z0-9-]+\z/)
        parameters[name] = text
      when :wildcard
        parameters[name] = segments[count..].map { |part| decode(part) }.join('/')
      end
    end
    parameters
  end

  def selected_type(types, accept)
    return types[0] if accept.nil?
    elements = []
    accept.split(',', -1).each do |element|
      range, *parameters = element.split(';', -1).map { |part| part.strip }
      range = range.downcase
      next unless range == '*/*' || range.match?(/\A[a-z0-9.+-]+\/\*\z/) || MEDIA.match?(range)
      q = nil
      parameters.each do |parameter|
        next unless parameter.include?('=')
        name, value = parameter.split('=', 2).map { |part| part.strip }
        if name.downcase == 'q'
          q = value
          break
        end
      end
      next if q && !q.match?(/\A(?:0(?:\.[0-9]{0,3})?|1(?:\.0{0,3})?)\z/)
      weight = q ? (q.to_f * 1000).round : 1000
      specificity = range == '*/*' ? 1 : (range.end_with?('/*') ? 2 : 3)
      elements << [range, specificity, weight]
    end
    best = nil
    best_weight = 0
    types.each do |type|
      specificity = 0
      weight = 0
      elements.each do |range, rank, candidate|
        fits = range == '*/*' || range == type || (rank == 2 && range.split('/')[0] == type.split('/')[0])
        if fits && rank > specificity
          specificity = rank
          weight = candidate
        end
      end
      if weight > best_weight
        best_weight = weight
        best = type
      end
    end
    best
  end

  def json_string(text)
    '"' + text.gsub(/[\\"]/) { |char| '\\' + char } + '"'
  end

  def html(text)
    text.gsub(/[&<>"]/) { |char| { '&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;' }[char] }
  end

  def body_for(route, parameters, query, headers, type)
    params = parameters.sort
    queries = query.nil? ? [] : query.split('&', -1).reject(&:empty?).map do |part|
      name, value = part.split('=', 2)
      [decode(name.tr('+', ' ')), decode((value || '').tr('+', ' '))]
    end
    cookies = {}
    if headers.key?('cookie')
      headers['cookie'].split(';', -1).each do |part|
        part = part.strip
        next unless part.include?('=')
        name, value = part.split('=', 2)
        cookies[name] = value if name != '' && !cookies.key?(name)
      end
    end
    cookie_pairs = cookies.sort
    if type == 'application/json'
      pairs = ->(list) { list.map { |name, value| json_string(name) + ':' + json_string(value) }.join(',') }
      query_json = queries.map { |name, value| '[' + json_string(name) + ',' + json_string(value) + ']' }.join(',')
      '{"route":' + json_string(route[:name]) + ',"params":{' + pairs.call(params) + '},"query":[' + query_json + '],"cookies":{' + pairs.call(cookie_pairs) + '}}'
    elsif type == 'text/html'
      output = '<dl><dt>route</dt><dd>' + html(route[:name]) + '</dd>'
      [['param', params], ['query', queries], ['cookie', cookie_pairs]].each do |label, pairs|
        pairs.each { |name, value| output += '<dt>' + label + ' ' + html(name) + '</dt><dd>' + html(value) + '</dd>' }
      end
      output + '</dl>'
    else
      pairs = ->(list) { list.empty? ? '-' : list.map { |name, value| encode(name) + '=' + encode(value) }.join('&') }
      "route=#{route[:name]} params=#{pairs.call(params)} query=#{pairs.call(queries)} cookies=#{pairs.call(cookie_pairs)}"
    end
  end

  def etag(body)
    a = 1
    b = 0
    body.each_byte do |char|
      a = (a + char) % 65521
      b = (b + a) % 65521
    end
    format('"%04x%04x"', b, a)
  end

  def response(status, body = '', headers = {}, type = nil)
    { status: status, body: body, headers: headers, type: type }
  end

  def handle(method, target, headers)
    return response(501, "not implemented: #{method}") unless %w[GET HEAD POST PUT PATCH DELETE OPTIONS].include?(method)
    return response(400, 'bad request: missing host') if !headers.key?('host') || headers['host'].empty?
    effective = method
    if headers.key?('x-http-method-override')
      override = headers['x-http-method-override']
      return response(400, 'bad request: method override') unless method == 'POST' && %w[PUT PATCH DELETE].include?(override)
      effective = override
    end
    client = headers['x-client']
    if client && !client.empty?
      time = headers['x-time'].to_i
      record = @clients[client] ||= { allowed: 0, limited: 0, level: @limit ? @limit[0] * @limit[1] : 0, last: time }
      if @limit
        capacity, period = @limit
        record[:level] = [capacity * period, record[:level] + (time - record[:last]) * capacity].min
        record[:last] = time
        if record[:level] < period
          record[:limited] += 1
          wait = (period - record[:level] + capacity - 1) / capacity
          return response(429, "too many requests: client #{client}", { 'Retry-After' => wait.to_s })
        end
        record[:level] -= period
      end
      record[:allowed] += 1
    end
    path, query = target.split('?', 2)
    suffix = target.include?('?') ? '?' + (query || '') : ''
    normalized = normalize(path)
    return response(308, "redirect to #{normalized}#{suffix}", { 'Location' => normalized + suffix }) if normalized != path
    @redirects.each do |rule|
      if path == rule[:base] || (rule[:wildcard] && path.start_with?(rule[:base] + '/'))
        destination = rule[:to] + path[rule[:base].length..] + suffix
        return response(rule[:code], "redirect to #{destination}", { 'Location' => destination })
      end
    end
    segments = path == '/' ? [] : path[1..].split('/', -1)
    matches = @ordered.filter_map do |route|
      params = match_route(route, segments)
      params ? [route, params] : nil
    end
    return response(404, "not found: #{path}") if matches.empty?
    allowed = matches.flat_map { |route, _| route[:methods] }.uniq + ['OPTIONS']
    allowed << 'HEAD' if allowed.include?('GET')
    allow = allowed.uniq.sort.join(', ')
    return response(204, '', { 'Allow' => allow }) if effective == 'OPTIONS'
    lookup = effective == 'HEAD' ? 'GET' : effective
    selected = matches.find { |route, _| route[:methods].include?(lookup) }
    return response(405, "method not allowed: #{effective}", { 'Allow' => allow }) unless selected
    route, params = selected
    route[:hits] += 1
    if route[:role] != 'none'
      return response(401, 'unauthorized: missing token', { 'WWW-Authenticate' => 'Bearer realm="api"' }) unless headers.key?('authorization')
      scheme, _, token = headers['authorization'].partition(' ')
      unless scheme.downcase == 'bearer' && @tokens.key?(token)
        return response(401, 'unauthorized: invalid token', { 'WWW-Authenticate' => 'Bearer realm="api", error="invalid_token"' })
      end
      return response(403, "forbidden: requires role #{route[:role]}") unless [route[:role], 'admin'].include?(@tokens[token])
    end
    extra = route[:types].length >= 2 ? { 'Vary' => 'Accept' } : {}
    type = selected_type(route[:types], headers['accept'])
    return response(406, 'not acceptable: ' + route[:types].join(', '), extra) unless type
    body = body_for(route, params, query, headers, type)
    tag = etag(body)
    if headers.key?('if-none-match')
      found = headers['if-none-match'].split(',', -1).any? do |part|
        part = part.strip.delete_prefix('W/')
        part == '*' || part == tag
      end
      if found
        return lookup == 'GET' ? response(304, '', extra.merge('ETag' => tag)) : response(412, "precondition failed: #{tag}", extra)
      end
    end
    response(200, body, extra.merge('ETag' => tag), type)
  end

  def request(line, header_lines)
    @requests += 1
    head = false
    cors = false
    headers = {}
    match = /\A([A-Z]{1,16}) (\/[^ #]*) HTTP\/1\.1\z/.match(line)
    if !match
      result = response(400, 'bad request: request line')
    else
      method, target = match.captures
      head = method == 'HEAD'
      valid_escapes = true
      position = 0
      while position < target.length
        if target[position] == '%'
          hex = target[position + 1, 2]
          unless hex && hex.match?(/\A[0-9A-Fa-f]{2}\z/) && hex.to_i(16).between?(32, 126)
            valid_escapes = false
            break
          end
          position += 3
        else
          position += 1
        end
      end
      if !valid_escapes
        result = response(400, 'bad request: percent escape')
      else
        result = nil
        header_lines.each_with_index do |text, index|
          name, value = text.split(':', 2)
          if !value || !name.match?(/\A[A-Za-z0-9-]+\z/)
            result = response(400, "bad request: header line #{index + 1}")
            break
          end
          name = name.downcase
          if headers.key?(name)
            result = response(400, "bad request: duplicate header #{name}")
            break
          end
          headers[name] = value.strip
        end
        unless result
          cors = true
          result = handle(method, target, headers)
        end
      end
    end
    if cors && headers.key?('origin') && @origins.include?(headers['origin'])
      result[:headers]['Access-Control-Allow-Origin'] = headers['origin']
      if result[:status] == 204 && headers.key?('access-control-request-method')
        result[:headers]['Access-Control-Allow-Methods'] = result[:headers]['Allow']
      end
    end
    status = result[:status]
    @statuses[status] += 1
    unless [204, 304].include?(status)
      result[:headers]['Content-Type'] = status == 200 ? result[:type] : 'text/plain'
      result[:headers]['Content-Length'] = result[:body].length.to_s
    end
    puts "REQUEST #{@requests}"
    puts "HTTP/1.1 #{status} #{REASONS[status]}"
    HEADERS.each { |name| puts "#{name}: #{result[:headers][name]}" if result[:headers].key?(name) }
    puts result[:body] unless head || [204, 304].include?(status)
  end

  def urlfor(line)
    _, name, *arguments = line.split(' ')
    route = @routes.find { |item| item[:name] == name }
    raise UrlError, "unknown route #{name}" unless route
    parameter_names = route[:pieces].reject { |kind, _| kind == :literal }.map(&:last)
    values = {}
    queries = []
    arguments.each do |argument|
      key, value = argument.split('=', 2)
      raise UrlError, "bad argument #{argument}" if value.nil? || key.empty?
      if parameter_names.include?(key)
        raise UrlError, "duplicate parameter #{key}" if values.key?(key)
        values[key] = value
      else
        queries << [key, value]
      end
    end
    route[:pieces].each do |kind, key|
      next if kind == :literal
      raise UrlError, "missing parameter #{key}" if kind != :wildcard && !values.key?(key)
      text = values.fetch(key, '')
      valid = case kind
              when :parameter then text != '' && !%w[. ..].include?(text)
              when :int then text.match?(/\A[0-9]{1,9}\z/)
              when :slug then text.match?(/\A[a-z0-9-]+\z/)
              else text == '' || text.split('/', -1).all? { |part| part != '' && !%w[. ..].include?(part) }
              end
      raise UrlError, "bad value for #{key}" unless valid
    end
    parts = route[:pieces].flat_map do |kind, key|
      if kind == :literal
        [key]
      elsif kind == :wildcard
        text = values.fetch(key, '')
        text.empty? ? [] : text.split('/', -1).map { |part| encode(part) }
      else
        [encode(values[key])]
      end
    end
    url = '/' + parts.join('/')
    url += '?' + queries.map { |key, value| encode(key) + '=' + encode(value) }.join('&') unless queries.empty?
    @url_ok += 1
    puts "URLFOR #{name} #{url}"
  rescue UrlError => error
    @url_error += 1
    puts "URLFOR ERROR #{error.message}"
  end

  def run
    input = STDIN.each_line.map { |line| line.chomp("\n").delete_suffix("\r") }
    position = 0
    while input[position] != 'REQUESTS'
      configure(input[position], position + 1)
      position += 1
    end
    position += 1
    puts "CONFIG routes=#{@routes.length} tokens=#{@tokens.length} redirects=#{@redirects.length} origins=#{@origins.length} limit=#{@limit ? @limit.join('/') : 'none'} errors=#{@errors}"
    @routes.each { |route| route[:types] ||= ['application/json'] }
    @ordered = @routes.sort_by { |route| priority(route) }
    @ordered.each_with_index do |route, index|
      methods = route[:methods] + (route[:methods].include?('GET') ? ['HEAD'] : [])
      puts "TABLE #{index + 1} #{route[:name]} #{methods.sort.join(',')} #{route[:pattern]} role=#{route[:role] == 'none' ? '-' : route[:role]} types=#{route[:types].join(',')}"
    end
    while input[position] != 'END'
      line = input[position]
      position += 1
      if line.start_with?('URLFOR ')
        urlfor(line)
      else
        headers = []
        while input[position] != ''
          headers << input[position]
          position += 1
        end
        position += 1
        request(line, headers)
      end
    end
    puts "SUMMARY requests=#{@requests} urlfor_ok=#{@url_ok} urlfor_error=#{@url_error}"
    @statuses.keys.sort.each { |status| puts "STATUS #{status} #{@statuses[status]}" }
    @routes.each { |route| puts "ROUTE #{route[:name]} #{route[:hits]}" }
    @clients.keys.sort.each { |client| puts "CLIENT #{client} allowed=#{@clients[client][:allowed]} limited=#{@clients[client][:limited]}" }
  end
end

HttpRouter.new.run
