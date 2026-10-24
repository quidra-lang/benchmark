require_relative 'protocol'
require_relative 'masks'
require_relative 'clients'
require_relative 'channels'
require_relative 'modes'

class Server
  HANDLERS = %w[NICK USER PING PONG QUIT JOIN PART TOPIC NAMES WHOIS AWAY INVITE KICK MODE].freeze
  INTEGER_SETTINGS = %w[NICKLEN CHANNELLEN TOPICLEN MAXCHANNELS BUCKET REFILL QUEUE PINGFREQ TIMEOUT].freeze

  def self.read_inputs
    settings = { 'MOTD' => [] }
    File.foreach('input/server.txt', chomp: true) do |line|
      key, _, value = line.partition(' ')
      if key == 'MOTD'
        settings[key] << value
      else
        settings[key] = INTEGER_SETTINGS.include?(key) ? value.to_i : value
      end
    end
    traffic = File.readlines('input/traffic.txt', chomp: true).map do |line|
      time, identifier, body = line.split(' ', 3)
      kind = 'messages'
      if body.start_with?('CONNECT ')
        host = body[8..]
        if host.length.between?(1, 63) && host.each_char.all? { |character| (Protocol::LETTERS + '0123456789.-').include?(character) }
          kind = 'connect'
        end
      elsif body == 'DISCONNECT'
        kind = 'disconnect'
      end
      [time.to_i, identifier, kind, body]
    end
    [settings, traffic]
  end

  def initialize(settings, traffic)
    @settings, @traffic = settings, traffic
    @end_time = traffic.last[0]
    @time = 0
    @clients, @channels = {}, {}
    @sent, @gone = [], []
    @commands, @numerics, @line_counts = Hash.new(0), Hash.new(0), Hash.new(0)
    traffic.each { |_, _, kind, _| @line_counts[kind] += 1 }
    @statistics, @disconnections = Hash.new(0), Hash.new(0)
    @peak_connections = @peak_registered = [0, 0]
  end

  def send_line(client, line)
    @sent << "#{@time} #{client.identifier} #{line}"
    client.sent += 1
  end

  def numeric(client, number, user: nil, channel: nil, x: nil, command: nil,
              character: nil, names: nil, ban: nil, motd: nil)
    server = @settings['NAME']
    content = case number
              when 1 then ":Welcome to the Internet Relay Network #{client.prefix}"
              when 2 then ":Your host is #{server}, running version #{@settings['VERSION']}"
              when 3 then ":This server was created #{@settings['CREATED']}"
              when 4 then "#{server} #{@settings['VERSION']} i biklmnotv"
              when 5
                "CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=#{@settings['NICKLEN']} CHANNELLEN=#{@settings['CHANNELLEN']} TOPICLEN=#{@settings['TOPICLEN']} CHANLIMIT=#:#{@settings['MAXCHANNELS']} CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server"
              when 221 then client.mode
              when 301 then "#{user.nickname} :#{user.away}"
              when 305 then ':You are no longer marked as being away'
              when 306 then ':You have been marked as being away'
              when 311 then "#{user.nickname} #{user.username} #{user.hostname} * :#{user.realname}"
              when 312 then "#{user.nickname} #{server} :#{@settings['DESCRIPTION']}"
              when 317 then "#{user.nickname} #{@time - user.last_speaking} #{user.registration_time} :seconds idle, signon time"
              when 318 then "#{x} :End of /WHOIS list."
              when 319 then "#{user.nickname} :#{joined_channels(user, ' ')}"
              when 324 then "#{channel.name} #{channel.mode_display(!channel.member(client).nil?)}"
              when 329 then "#{channel.name} #{channel.created}"
              when 331 then "#{channel.name} :No topic is set"
              when 332 then "#{channel.name} :#{channel.topic}"
              when 333 then "#{channel.name} #{channel.topic_setter} #{channel.topic_time}"
              when 341 then "#{user.nickname} #{channel.name}"
              when 353 then "= #{channel.name} :#{names}"
              when 366 then "#{x} :End of /NAMES list."
              when 367 then "#{channel.name} #{ban.join(' ')}"
              when 368 then "#{channel.name} :End of channel ban list"
              when 372 then ":- #{motd}"
              when 375 then ":- #{server} Message of the day -"
              when 376 then ':End of /MOTD command.'
              when 401 then "#{x} :No such nick/channel"
              when 403 then "#{x} :No such channel"
              when 404 then "#{channel.name} :Cannot send to channel"
              when 405 then "#{x} :You have joined too many channels"
              when 409 then ':No origin specified'
              when 411 then ":No recipient given (#{command})"
              when 412 then ':No text to send'
              when 421 then "#{command} :Unknown command"
              when 431 then ':No nickname given'
              when 432 then "#{x} :Erroneous nickname"
              when 433 then "#{x} :Nickname is already in use"
              when 441 then "#{user.nickname} #{channel.name} :They aren't on that channel"
              when 442 then "#{channel.name} :You're not on that channel"
              when 443 then "#{user.nickname} #{channel.name} :is already on channel"
              when 451 then ':You have not registered'
              when 461 then "#{command} :Not enough parameters"
              when 462 then ':You may not reregister'
              when 467 then "#{channel.name} :Channel key already set"
              when 471 then "#{channel.name} :Cannot join channel (+l)"
              when 472 then "#{character} :is unknown mode char to me for #{channel.name}"
              when 473 then "#{channel.name} :Cannot join channel (+i)"
              when 474 then "#{channel.name} :Cannot join channel (+b)"
              when 475 then "#{channel.name} :Cannot join channel (+k)"
              when 482 then "#{channel.name} :You're not channel operator"
              when 501 then ':Unknown MODE flag'
              when 502 then ':Cannot change mode for other users'
              end
    @numerics[number] += 1
    send_line(client, ":#{server} #{format('%03d', number)} #{client.addressee} #{content}")
  end

  def broadcast(channel, line, exclude = nil)
    channel.members.each { |member| send_line(member.client, line) unless member.client.equal?(exclude) }
  end

  def send_peers(client, line)
    peers = client.channels.flat_map { |channel| channel.members.map(&:client) }.to_set
    @clients.each_value do |other|
      send_line(other, line) if !other.equal?(client) && peers.include?(other)
    end
  end

  def find_user(nickname)
    folded = Protocol.fold(nickname)
    @clients.each_value.find { |client| client.registered && Protocol.fold(client.nickname) == folded }
  end

  def find_channel(name) = @channels[Protocol.fold(name)]

  def joined_channels(client, separator)
    client.channels.map { |channel| channel.member(client).status + channel.name }.join(separator)
  end

  def remove_member(client, channel)
    channel.remove(client)
    return unless channel.members.empty?
    @channels.delete(Protocol.fold(channel.name))
    @clients.each_value { |other| other.invites.delete(channel) }
  end

  def disconnect(client, reason, kind)
    if kind != 'closed'
      send_line(client, "ERROR :Closing Link: #{client.addressee}[#{client.hostname}] (#{reason})")
      @statistics['errors'] += 1
    end
    send_peers(client, ":#{client.prefix} QUIT :#{reason}") if client.registered
    client.channels.dup.each { |channel| remove_member(client, channel) }
    @statistics['discarded'] += client.queue.length
    client.queue.clear
    @clients.delete(client.identifier)
    client.active = false
    @gone << [@time, client.identifier, client.addressee, reason]
    @disconnections[kind] += 1
  end

  def complete_registration(client)
    return if client.registered || client.nickname.nil? || client.username.nil?
    client.registered = true
    client.registration_time = client.last_speaking = @time
    count = @clients.values.count(&:registered)
    @peak_registered = [count, @time] if count > @peak_registered[0]
    [1, 2, 3, 4, 5, 375].each { |number| numeric(client, number) }
    @settings['MOTD'].each { |line| numeric(client, 372, motd: line) }
    numeric(client, 376)
    send_line(client, ":#{client.nickname} MODE #{client.nickname} :+i") if client.invisible
  end

  def arrival(record)
    _, identifier, kind, body = record
    if kind == 'connect'
      @clients[identifier] = Client.new(identifier, body[8..], @time, @settings['BUCKET'])
      count = @clients.length
      @peak_connections = [count, @time] if count > @peak_connections[0]
      return
    end
    client = @clients[identifier]
    if kind == 'disconnect'
      disconnect(client, 'Remote host closed the connection', 'closed') if client
      return
    end
    unless client
      @statistics['dropped'] += 1
      return
    end
    client.received += 1
    client.last_received = @time
    client.ping_sent = nil
    if client.queue.empty? && client.tokens.positive?
      client.use_token(@time, @settings['BUCKET'], @settings['REFILL'])
      process(client, body)
    elsif client.queue.length >= @settings['QUEUE']
      @statistics['discarded'] += 1
      disconnect(client, 'Excess Flood', 'flood')
    else
      client.queue << body
      @statistics['queued'] += 1
    end
  end

  def run
    position = 0
    (0..@end_time).each do |time|
      @time = time
      @clients.values.each do |client|
        client.refill(time, @settings['BUCKET'], @settings['REFILL'])
        while client.active && !client.queue.empty? && client.tokens.positive?
          client.use_token(time, @settings['BUCKET'], @settings['REFILL'])
          process(client, client.queue.shift)
        end
      end
      while position < @traffic.length && @traffic[position][0] == time
        arrival(@traffic[position])
        position += 1
      end
      @clients.values.each do |client|
        if client.ping_sent
          if time - client.ping_sent >= @settings['TIMEOUT']
            disconnect(client, "Ping timeout: #{time - client.last_received} seconds", 'timeout')
          end
        elsif time - client.last_received >= @settings['PINGFREQ']
          send_line(client, "PING :#{@settings['NAME']}")
          @statistics['pings'] += 1
          client.ping_sent = time
        end
      end
    end
  end

  def process(client, raw)
    @statistics['processed'] += 1
    command, parameters = Protocol.parse(raw)
    if command.empty?
      @statistics['empty'] += 1
      return
    end
    @commands[command] += 1
    if !client.registered && !%w[NICK USER PING PONG QUIT].include?(command)
      numeric(client, 451)
    elsif %w[PRIVMSG NOTICE].include?(command)
      message(client, parameters, command)
    elsif HANDLERS.include?(command)
      public_send(command.downcase, client, parameters)
    else
      numeric(client, 421, command: command)
    end
  end

  def enough_parameters?(client, parameters, count, command)
    return true if parameters.length >= count
    numeric(client, 461, command: command)
    false
  end

  def nick(client, parameters)
    return numeric(client, 431) if parameters.empty? || parameters[0].empty?
    nickname = parameters[0][0, @settings['NICKLEN']]
    return numeric(client, 432, x: nickname) unless Protocol.valid_nickname?(nickname)
    return if nickname == client.nickname
    folded = Protocol.fold(nickname)
    if @clients.values.any? { |other| !other.equal?(client) && other.nickname && Protocol.fold(other.nickname) == folded }
      return numeric(client, 433, x: nickname)
    end
    if client.registered
      line = ":#{client.prefix} NICK :#{nickname}"
      send_line(client, line)
      send_peers(client, line)
    end
    client.nickname = nickname
    complete_registration(client)
  end

  def user(client, parameters)
    return numeric(client, 462) unless client.username.nil?
    return unless enough_parameters?(client, parameters, 4, 'USER')
    client.username, client.realname = parameters[0], parameters[3]
    mode = parameters[1]
    client.invisible = Protocol.digits?(mode) && mode.length <= 3 && (mode.to_i / 8).odd?
    complete_registration(client)
  end

  def ping(client, parameters)
    return numeric(client, 409) if parameters.empty? || parameters[0].empty?
    server = @settings['NAME']
    send_line(client, ":#{server} PONG #{server} :#{parameters[0]}")
  end

  def pong(_client, _parameters); end

  def quit(client, parameters)
    reason = !parameters.empty? && !parameters[0].empty? ? 'Quit: ' + parameters[0] : 'Client Quit'
    disconnect(client, reason, 'quit')
  end

  def names_reply(client, channel)
    names = channel.name_list(client)
    numeric(client, 353, channel: channel, names: names) unless names.empty?
    numeric(client, 366, x: channel.name)
  end

  def join(client, parameters)
    return unless enough_parameters?(client, parameters, 1, 'JOIN')
    if parameters[0] == '0'
      client.channels.dup.each do |channel|
        broadcast(channel, ":#{client.prefix} PART #{channel.name}")
        remove_member(client, channel)
      end
      return
    end
    keys = parameters.length >= 2 ? parameters[1].split(',') : []
    parameters[0].split(',').each_with_index do |name, index|
      unless Protocol.valid_channel?(name, @settings['CHANNELLEN'])
        numeric(client, 403, x: name)
        next
      end
      channel = find_channel(name)
      next if channel && channel.member(client)
      if client.channels.length >= @settings['MAXCHANNELS']
        numeric(client, 405, x: name)
        next
      end
      if channel
        invited = client.invites.include?(channel)
        failure = if channel.banned?(client) && !invited
                    474
                  elsif channel.flags.include?('i') && !invited
                    473
                  elsif !channel.key.empty? && (keys[index] || '') != channel.key
                    475
                  elsif channel.limit.positive? && channel.members.length >= channel.limit
                    471
                  end
        if failure
          numeric(client, failure, channel: channel)
          next
        end
      else
        channel = Channel.new(name, @time)
        @channels[Protocol.fold(name)] = channel
      end
      client.invites.delete(channel)
      channel.add(client, channel.members.empty?)
      broadcast(channel, ":#{client.prefix} JOIN #{channel.name}")
      unless channel.topic.empty?
        numeric(client, 332, channel: channel)
        numeric(client, 333, channel: channel)
      end
      names_reply(client, channel)
    end
  end

  def part(client, parameters)
    return unless enough_parameters?(client, parameters, 1, 'PART')
    suffix = parameters.length >= 2 && !parameters[1].empty? ? ' :' + parameters[1] : ''
    parameters[0].split(',').each do |name|
      channel = find_channel(name)
      if channel.nil?
        numeric(client, 403, x: name)
      elsif channel.member(client).nil?
        numeric(client, 442, channel: channel)
      else
        broadcast(channel, ":#{client.prefix} PART #{channel.name}#{suffix}")
        remove_member(client, channel)
      end
    end
  end

  def message(client, parameters, command)
    replies = command == 'PRIVMSG'
    client.last_speaking = @time if replies
    if parameters.empty? || parameters[0].empty?
      numeric(client, 411, command: command) if replies
      return
    elsif parameters.length < 2 || parameters[1].empty?
      numeric(client, 412) if replies
      return
    end
    text = parameters[1]
    parameters[0].split(',').each do |target|
      if target.start_with?('#')
        channel = find_channel(target)
        if channel.nil?
          numeric(client, 401, x: target) if replies
        elsif !channel.can_speak?(client)
          numeric(client, 404, channel: channel) if replies
        else
          channel.messages += 1
          broadcast(channel, ":#{client.prefix} #{command} #{channel.name} :#{text}", client)
        end
      else
        recipient = find_user(target)
        if recipient.nil?
          numeric(client, 401, x: target) if replies
          next
        end
        send_line(recipient, ":#{client.prefix} #{command} #{recipient.nickname} :#{text}")
        numeric(client, 301, user: recipient) if replies && !recipient.away.empty?
      end
    end
  end

  def topic(client, parameters)
    return unless enough_parameters?(client, parameters, 1, 'TOPIC')
    channel = find_channel(parameters[0])
    return numeric(client, 403, x: parameters[0]) unless channel
    membership = channel.member(client)
    return numeric(client, 442, channel: channel) unless membership
    if parameters.length == 1
      numeric(client, channel.topic.empty? ? 331 : 332, channel: channel)
      numeric(client, 333, channel: channel) unless channel.topic.empty?
      return
    end
    return numeric(client, 482, channel: channel) if channel.flags.include?('t') && !membership.operator
    channel.topic = parameters[1][0, @settings['TOPICLEN']]
    channel.topic_setter, channel.topic_time = client.nickname, @time
    broadcast(channel, ":#{client.prefix} TOPIC #{channel.name} :#{channel.topic}")
  end

  def names(client, parameters)
    return numeric(client, 366, x: '*') if parameters.empty?
    parameters[0].split(',').each do |name|
      channel = find_channel(name)
      channel ? names_reply(client, channel) : numeric(client, 366, x: name)
    end
  end

  def whois(client, parameters)
    return numeric(client, 431) if parameters.empty?
    recipient = find_user(parameters[0])
    unless recipient
      numeric(client, 401, x: parameters[0])
      numeric(client, 318, x: parameters[0])
      return
    end
    numeric(client, 311, user: recipient)
    numeric(client, 319, user: recipient) unless recipient.channels.empty?
    numeric(client, 312, user: recipient)
    numeric(client, 301, user: recipient) unless recipient.away.empty?
    numeric(client, 317, user: recipient)
    numeric(client, 318, x: recipient.nickname)
  end

  def away(client, parameters)
    client.away = parameters[0] || ''
    numeric(client, client.away.empty? ? 305 : 306)
  end

  def invite(client, parameters)
    return unless enough_parameters?(client, parameters, 2, 'INVITE')
    recipient = find_user(parameters[0])
    return numeric(client, 401, x: parameters[0]) unless recipient
    channel = find_channel(parameters[1])
    return numeric(client, 403, x: parameters[1]) unless channel
    membership = channel.member(client)
    return numeric(client, 442, channel: channel) unless membership
    return numeric(client, 443, channel: channel, user: recipient) if channel.member(recipient)
    return numeric(client, 482, channel: channel) if channel.flags.include?('i') && !membership.operator
    recipient.invites << channel unless recipient.invites.include?(channel)
    numeric(client, 341, user: recipient, channel: channel)
    numeric(client, 301, user: recipient) unless recipient.away.empty?
    send_line(recipient, ":#{client.prefix} INVITE #{recipient.nickname} :#{channel.name}")
  end

  def kick(client, parameters)
    return unless enough_parameters?(client, parameters, 2, 'KICK')
    channel = find_channel(parameters[0])
    return numeric(client, 403, x: parameters[0]) unless channel
    membership = channel.member(client)
    return numeric(client, 442, channel: channel) unless membership
    return numeric(client, 482, channel: channel) unless membership.operator
    recipient = find_user(parameters[1])
    return numeric(client, 401, x: parameters[1]) unless recipient
    return numeric(client, 441, user: recipient, channel: channel) unless channel.member(recipient)
    reason = parameters.length >= 3 && !parameters[2].empty? ? parameters[2] : client.nickname
    broadcast(channel, ":#{client.prefix} KICK #{channel.name} #{recipient.nickname} :#{reason}")
    remove_member(recipient, channel)
  end

  def mode(client, parameters)
    return unless enough_parameters?(client, parameters, 1, 'MODE')
    parameters[0].start_with?('#') ? channel_mode(client, parameters) : user_mode(client, parameters)
  end

  def user_mode(client, parameters)
    recipient = find_user(parameters[0])
    return numeric(client, 401, x: parameters[0]) unless recipient
    return numeric(client, 502) unless recipient.equal?(client)
    return numeric(client, 221) if parameters.length == 1
    sign, changes, unknown = '+', [], false
    parameters[1].each_char do |character|
      if '+-'.include?(character)
        sign = character
      elsif character == 'i'
        desired = sign == '+'
        if client.invisible != desired
          client.invisible = desired
          changes << [sign, character, nil]
        end
      else
        unknown = true
      end
    end
    unless changes.empty?
      send_line(client, ":#{client.nickname} MODE #{client.nickname} :#{Modes.change_string(changes)}")
    end
    numeric(client, 501) if unknown
  end

  def channel_mode(client, parameters)
    channel = find_channel(parameters[0])
    return numeric(client, 403, x: parameters[0]) unless channel
    if parameters.length == 1
      numeric(client, 324, channel: channel)
      numeric(client, 329, channel: channel)
      return
    end
    membership = channel.member(client)
    authorized = membership && membership.operator
    bans_sent = denial_sent = false
    changes = []
    Modes.channel_items(parameters[1], parameters[2..]).each do |sign, character, argument|
      if !'biklmnotv'.include?(character)
        numeric(client, 472, character: character, channel: channel)
      elsif character == 'b' && argument.nil?
        if sign == '+' && !bans_sent
          channel.bans.each { |ban| numeric(client, 367, channel: channel, ban: ban) }
          numeric(client, 368, channel: channel)
          bans_sent = true
        end
      elsif argument.nil? && ('ov'.include?(character) || (sign == '+' && 'kl'.include?(character)))
        next
      elsif !authorized
        numeric(client, 482, channel: channel) unless denial_sent
        denial_sent = true
      else
        change = apply_channel_mode(client, channel, sign, character, argument)
        changes << change if change
      end
    end
    broadcast(channel, ":#{client.prefix} MODE #{channel.name} #{Modes.change_string(changes)}") unless changes.empty?
  end

  def apply_channel_mode(client, channel, sign, character, argument)
    adding = sign == '+'
    changed = false
    change_argument = nil
    case character
    when 'o', 'v'
      recipient = find_user(argument)
      unless recipient
        numeric(client, 401, x: argument)
        return nil
      end
      membership = channel.member(recipient)
      unless membership
        numeric(client, 441, user: recipient, channel: channel)
        return nil
      end
      old = character == 'o' ? membership.operator : membership.voice
      if old != adding
        if character == 'o'
          membership.operator = adding
        else
          membership.voice = adding
        end
        changed, change_argument = true, recipient.nickname
      end
    when 'b'
      mask = Masks.normalize(argument)
      found = channel.bans.index { |ban| Protocol.fold(ban[0]) == Protocol.fold(mask) }
      if adding && found.nil?
        channel.bans << [mask, client.nickname, @time]
        changed, change_argument = true, mask
      elsif !adding && found
        change_argument = channel.bans.delete_at(found)[0]
        changed = true
      end
    when 'k'
      if adding
        if channel.key.empty?
          channel.key = argument
          changed, change_argument = true, argument
        else
          numeric(client, 467, channel: channel)
        end
      elsif !channel.key.empty?
        channel.key = ''
        changed, change_argument = true, '*'
      end
    when 'l'
      if adding
        limit = argument.to_i
        if channel.limit != limit
          channel.limit = limit
          changed, change_argument = true, limit.to_s
        end
      elsif channel.limit.positive?
        channel.limit = 0
        changed = true
      end
    else
      if adding && !channel.flags.include?(character)
        channel.flags.add(character)
        changed = true
      elsif !adding && channel.flags.include?(character)
        channel.flags.delete(character)
        changed = true
      end
    end
    changed ? [sign, character, change_argument] : nil
  end

  def channel_report
    lines = []
    @channels.each_value do |channel|
      lines << "CHANNEL #{channel.name} created #{channel.created} members #{channel.members.length} peak #{channel.peak} messages #{channel.messages} modes #{channel.mode_display}"
      lines << (channel.topic.empty? ? 'TOPIC none' : "TOPIC #{channel.topic_setter} #{channel.topic_time} #{channel.topic}")
      channel.bans.each { |ban| lines << 'BAN ' + ban.join(' ') }
      lines << 'MEMBERS ' + channel.members.map(&:display).join(' ')
    end
    members = @channels.values.sum { |channel| channel.members.length }
    bans = @channels.values.sum { |channel| channel.bans.length }
    lines << "TOTAL channels #{@channels.length} members #{members} bans #{bans}"
    lines
  end

  def client_report
    lines = []
    @clients.each_value do |client|
      channels = joined_channels(client, ',')
      invites = client.invites.map(&:name).join(',')
      channels = 'none' if channels.empty?
      invites = 'none' if invites.empty?
      signon = client.registered ? client.registration_time : '-'
      lines << "CLIENT #{client.identifier} #{client.addressee} #{client.username || '*'} #{client.hostname} #{client.mode} connected #{client.connection_time} signon #{signon} received #{client.received} sent #{client.sent} tokens #{client.tokens} queue #{client.queue.length} channels #{channels} invites #{invites}"
      lines << "AWAY #{client.identifier} #{client.away}" unless client.away.empty?
    end
    registered = @clients.values.count(&:registered)
    invisible = @clients.values.count(&:invisible)
    away = @clients.values.count { |client| !client.away.empty? }
    lines << "TOTAL clients #{@clients.length} registered #{registered} invisible #{invisible} away #{away}"
    lines
  end

  def statistics_report
    counts = @statistics
    pending = @clients.values.sum { |client| client.queue.length }
    lines = ["END #{@end_time}",
             "LINES total #{@traffic.length} connect #{@line_counts['connect']} disconnect #{@line_counts['disconnect']} messages #{@line_counts['messages']}",
             "MESSAGES dropped #{counts['dropped']} queued #{counts['queued']} processed #{counts['processed']} discarded #{counts['discarded']} pending #{pending} empty #{counts['empty']}",
             "SENT lines #{@sent.length} numerics #{@numerics.values.sum} pings #{counts['pings']} errors #{counts['errors']}"]
    @commands.keys.sort.each { |command| lines << "COMMAND #{command} #{@commands[command]}" }
    @numerics.keys.sort.each { |number| lines << "NUMERIC #{format('%03d', number)} #{@numerics[number]}" }
    lines << "PEAK connections #{@peak_connections[0]} at #{@peak_connections[1]}"
    lines << "PEAK registered #{@peak_registered[0]} at #{@peak_registered[1]}"
    lines << 'DISCONNECTS ' + %w[quit closed flood timeout].map { |kind| "#{kind} #{@disconnections[kind]}" }.join(' ')
    @gone.each { |record| lines << 'GONE ' + record.join(' ') }
    lines
  end

  def write_outputs
    Dir.mkdir('output') unless Dir.exist?('output')
    { 'sent.txt' => @sent, 'channels.txt' => channel_report,
      'clients.txt' => client_report, 'stats.txt' => statistics_report }.each do |filename, lines|
      File.write(File.join('output', filename), lines.empty? ? '' : lines.join("\n") + "\n")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  server = Server.new(*Server.read_inputs)
  server.run
  server.write_outputs
end
