PROTOCOLS = %w[SW GBN SR].freeze
KEYS = %w[
  PROTOCOL FRAMES WINDOW SEQBITS TIMEOUT DELAY INTERVAL MAXTICKS DUPACK
  NAK BACKOFF CONGESTION UNSAFE TRACE RANDOM LOSEDATA LOSECTRL
  CORRUPTDATA CORRUPTCTRL DELAYDATA DELAYCTRL SNAPSHOT
].freeze
REQUIRED = %w[PROTOCOL FRAMES WINDOW SEQBITS TIMEOUT DELAY].freeze
LIST_KEYS = %w[LOSEDATA LOSECTRL CORRUPTDATA CORRUPTCTRL DELAYDATA DELAYCTRL SNAPSHOT].freeze
DELAY_KEYS = %w[DELAYDATA DELAYCTRL].freeze
CHOICES = {
  'PROTOCOL' => PROTOCOLS,
  'NAK' => %w[ON OFF],
  'BACKOFF' => %w[ON OFF],
  'CONGESTION' => %w[ON OFF],
  'UNSAFE' => %w[ON OFF],
  'TRACE' => %w[ALL SENDER RECEIVER NONE]
}.freeze
RANGES = {
  'FRAMES' => (1..60), 'WINDOW' => (1..32), 'SEQBITS' => (1..6),
  'TIMEOUT' => (1..50), 'DELAY' => (1..10), 'INTERVAL' => (0..10),
  'MAXTICKS' => (1..2000), 'DUPACK' => (1..10),
  'LOSEDATA' => (1..9999), 'LOSECTRL' => (1..9999),
  'CORRUPTDATA' => (1..9999), 'CORRUPTCTRL' => (1..9999),
  'SNAPSHOT' => (0..2000)
}.freeze
TRACE_SIDES = {
  'ALL' => %w[SENDER RECEIVER], 'SENDER' => %w[SENDER],
  'RECEIVER' => %w[RECEIVER], 'NONE' => []
}.freeze
RANDOM_MULTIPLIER = 48_271
RANDOM_MODULUS = 2_147_483_647

class SettingsError < StandardError; end

def truncated(numerator, denominator, digits)
  scale = 10**digits
  value = numerator * scale / denominator
  "#{value / scale}.#{(value % scale).to_s.rjust(digits, '0')}"
end

def tick_text(tick)
  tick.nil? ? '-' : tick.to_s
end

def option(settings, key, fallback)
  settings.fetch(key, [fallback])[0]
end

def number_set(settings, key)
  settings.fetch(key, []).map(&:to_i).to_h { |n| [n, true] }
end

def delay_map(settings, key)
  settings.fetch(key, []).to_h do |text|
    number, extra = text.split(':', 2).map(&:to_i)
    [number, extra]
  end
end

def valid_value?(key, values)
  return CHOICES[key].include?(values[0]) if CHOICES.key?(key)
  return RANGES[key].cover?(values[0].to_i) if !LIST_KEYS.include?(key) && RANGES.key?(key)
  if key == 'RANDOM'
    seed, loss, corrupt = values.map(&:to_i)
    return (1...RANDOM_MODULUS).cover?(seed) && loss >= 0 && corrupt >= 0 && loss + corrupt <= 100
  end
  if DELAY_KEYS.include?(key)
    pairs = values.map { |value| value.split(':', 2).map(&:to_i) }
    return pairs.all? { |n, extra| (1..9999).cover?(n) && (1..50).cover?(extra) } &&
           pairs.map(&:first).uniq.length == pairs.length
  end
  values.all? { |value| RANGES.fetch(key).cover?(value.to_i) } &&
    values.map(&:to_i).uniq.length == values.length
end

class Config
  attr_reader :protocol, :frames, :window, :seqbits, :timeout, :delay, :interval,
              :limit, :dupack, :nak, :backoff, :congestion, :unsafe, :trace,
              :random, :lose_data, :lose_ctrl, :corrupt_data, :corrupt_ctrl,
              :delay_data, :delay_ctrl, :snapshots

  def initialize(settings)
    @protocol = option(settings, 'PROTOCOL', '')
    @frames = option(settings, 'FRAMES', '0').to_i
    @window = option(settings, 'WINDOW', '0').to_i
    @seqbits = option(settings, 'SEQBITS', '0').to_i
    @timeout = option(settings, 'TIMEOUT', '0').to_i
    @delay = option(settings, 'DELAY', '0').to_i
    @interval = option(settings, 'INTERVAL', '0').to_i
    @limit = option(settings, 'MAXTICKS', '1000').to_i
    @dupack = settings.key?('DUPACK') ? settings['DUPACK'][0].to_i : nil
    @nak = option(settings, 'NAK', 'OFF') == 'ON'
    @backoff = option(settings, 'BACKOFF', 'OFF') == 'ON'
    @congestion = option(settings, 'CONGESTION', 'OFF') == 'ON'
    @unsafe = option(settings, 'UNSAFE', 'OFF') == 'ON'
    @trace = option(settings, 'TRACE', 'ALL')
    @random = settings['RANDOM']&.map(&:to_i)
    @lose_data = number_set(settings, 'LOSEDATA')
    @lose_ctrl = number_set(settings, 'LOSECTRL')
    @corrupt_data = number_set(settings, 'CORRUPTDATA')
    @corrupt_ctrl = number_set(settings, 'CORRUPTCTRL')
    @delay_data = delay_map(settings, 'DELAYDATA')
    @delay_ctrl = delay_map(settings, 'DELAYCTRL')
    @snapshots = number_set(settings, 'SNAPSHOT')
  end

  def window_limit
    case @protocol
    when 'SW' then 1
    when 'GBN' then 2**@seqbits - 1
    else 2**(@seqbits - 1)
    end
  end

  def config_line
    "config: #{@protocol} n=#{@frames} w=#{@window} k=#{@seqbits} T=#{@timeout} d=#{@delay}"
  end

  def options_line
    dupack = @dupack.nil? ? 'off' : @dupack
    random = @random.nil? ? 'off' : @random.join('/')
    "options: interval=#{@interval} limit=#{@limit} dupack=#{dupack} " \
      "nak=#{@nak ? 'on' : 'off'} backoff=#{@backoff ? 'on' : 'off'} " \
      "congestion=#{@congestion ? 'on' : 'off'} unsafe=#{@unsafe ? 'on' : 'off'} " \
      "trace=#{@trace.downcase} random=#{random}"
  end
end

def check_settings(lines)
  settings = {}
  lines.each do |key, values|
    raise SettingsError, "unknown key #{key}" unless KEYS.include?(key)
    raise SettingsError, "duplicate key #{key}" if settings.key?(key)
    count_ok = if key == 'RANDOM'
                 values.length == 3
               elsif LIST_KEYS.include?(key)
                 !values.empty?
               else
                 values.length == 1
               end
    raise SettingsError, "wrong number of values for #{key}" unless count_ok
    settings[key] = values
  end
  REQUIRED.each do |key|
    raise SettingsError, "missing key #{key}" unless settings.key?(key)
  end
  KEYS.each do |key|
    if settings.key?(key) && !valid_value?(key, settings[key])
      raise SettingsError, "bad value for #{key}"
    end
  end
  config = Config.new(settings)
  if config.protocol == 'SR' && !config.dupack.nil?
    raise SettingsError, 'DUPACK not supported for SR'
  end
  if (config.protocol == 'SW' || !config.unsafe) && config.window > config.window_limit
    raise SettingsError, "window #{config.window} exceeds limit #{config.window_limit} for #{config.protocol}"
  end
  both = config.lose_data.keys & config.corrupt_data.keys
  raise SettingsError, "data ##{both.min} both lost and corrupted" unless both.empty?
  both = config.lose_ctrl.keys & config.corrupt_ctrl.keys
  raise SettingsError, "control ##{both.min} both lost and corrupted" unless both.empty?
  config
end

FrameRecord = Struct.new(:transmissions, :first, :delivered, :acked, keyword_init: true) do
  def initialize(**values)
    super(transmissions: 0, first: nil, delivered: nil, acked: nil, **values)
  end
end
Transmission = Struct.new(:number, :kind, :value, :payload, :outcome, :arrival)

class LossGenerator
  def initialize(seed, loss, corruption)
    @state, @loss, @corruption = seed, loss, corruption
  end

  def next_outcome
    @state = RANDOM_MULTIPLIER * @state % RANDOM_MODULUS
    roll = @state % 100
    return 'LOST' if roll < @loss
    return 'CORRUPT' if roll < @loss + @corruption
    'NORMAL'
  end
end

class Channel
  attr_reader :sent, :lost, :corrupted

  def initialize(delay, losses, corruptions, extra_delays)
    @delay, @losses, @corruptions, @extra_delays = delay, losses, corruptions, extra_delays
    @sent = @lost = @corrupted = 0
    @in_transit = []
  end

  def send(kind, value, payload, tick, generator)
    @sent += 1
    outcome = generator.nil? ? 'NORMAL' : generator.next_outcome
    outcome = if @losses.key?(@sent)
                'LOST'
              elsif @corruptions.key?(@sent)
                'CORRUPT'
              else
                outcome
              end
    item = Transmission.new(@sent, kind, value, payload,
                            outcome, tick + @delay + @extra_delays.fetch(@sent, 0))
    @in_transit << item
    item
  end

  def arrivals(tick)
    current, @in_transit = @in_transit.partition { |item| item.arrival == tick }
    current
  end

  def count_damage(item)
    item.outcome == 'LOST' ? @lost += 1 : @corrupted += 1
  end
end

class Simulation
  attr_reader :lines, :completion, :delivered, :data_channel, :config

  def initialize(config)
    @config = config
    @selective = config.protocol == 'SR'
    @modulus = 2**config.seqbits
    @visible = TRACE_SIDES.fetch(config.trace)
    @generator = config.random.nil? ? nil : LossGenerator.new(*config.random)
    @data_channel = Channel.new(config.delay, config.lose_data, config.corrupt_data, config.delay_data)
    @control_channel = Channel.new(config.delay, config.lose_ctrl, config.corrupt_ctrl, config.delay_ctrl)
    @records = Array.new(config.frames) { FrameRecord.new }
    @lines = []
    @tick = @base = @frames_sent = @next_frame = 0
    @timer_length = config.timeout
    @timer = nil
    @duplicates = 0
    @acked = Array.new(config.frames, false)
    @timers = Array.new(config.frames)
    @queue = []
    @cwnd = 1
    @ssthresh = config.window
    @round_acks = 0
    @expected = 0
    @nak_sent = false
    @buffer = {}
    @resent = @naks = @timeouts = @fast_retransmits = 0
    @delivered = @errors = @discarded = @max_buffer = 0
    @completion = nil
  end

  def emit(*parts)
    @lines << ([@tick] + parts).join(' ')
  end

  def trace(side, *parts)
    emit(*parts) if @visible.include?(side)
  end

  def frame_of(value)
    @base + (value - @base) % @modulus
  end

  def effective_window
    @config.congestion ? [@config.window, @cwnd].min : @config.window
  end

  def run
    (0..@config.limit).each do |tick|
      @tick = tick
      @data_channel.arrivals(tick).each do |item|
        item.outcome == 'NORMAL' ? receive_data(item) : report_damage(@data_channel, item, 'RECEIVER')
      end
      @control_channel.arrivals(tick).each do |item|
        item.outcome == 'NORMAL' ? receive_control(item) : report_damage(@control_channel, item, 'SENDER')
      end
      completed = @base == @config.frames
      unless completed
        process_timeouts
        send_data
      end
      snapshot if @config.snapshots.key?(tick)
      if completed
        @completion = tick
        emit('DONE')
        return
      end
    end
    emit('ABORT')
  end

  def report_damage(channel, item, side)
    channel.count_damage(item)
    trace(side, item.outcome, item.kind, "##{item.number}")
  end

  def receive_data(item)
    trace('RECEIVER', 'RECV', "seq=#{item.value}", "##{item.number}")
    if @selective
      selective_receive(item.value, item.payload)
    else
      go_back_n_receive(item.value, item.payload)
    end
  end

  def go_back_n_receive(seq, payload)
    if seq == @expected % @modulus
      deliver(payload)
      send_control('ack', seq)
      return
    end
    discard(seq)
    if @config.nak && !@nak_sent
      send_control('nak', @expected % @modulus)
      @nak_sent = true
    elsif @expected > 0
      send_control('ack', (@expected - 1) % @modulus)
    end
  end

  def selective_receive(seq, payload)
    offset = (seq - @expected) % @modulus
    if offset >= @config.window
      discard(seq)
      send_control('ack', seq) if (@expected - seq) % @modulus <= @config.window
      return
    end
    position = @expected + offset
    if @buffer.key?(position)
      discard(seq)
      send_control('ack', seq)
    elsif offset == 0
      deliver(payload)
      deliver(@buffer.delete(@expected)) while @buffer.key?(@expected)
      send_control('ack', seq)
    else
      @buffer[position] = payload
      @max_buffer = [@max_buffer, @buffer.length].max
      trace('RECEIVER', 'BUFFER', "f=#{position}")
      send_control('ack', seq)
      if @config.nak && !@nak_sent
        send_control('nak', @expected % @modulus)
        @nak_sent = true
      end
    end
  end

  def deliver(payload)
    position = @expected
    if payload == position
      @delivered += 1
      @records[payload].delivered = @tick
      trace('RECEIVER', 'DELIVER', "f=#{position}")
    else
      @errors += 1
      trace('RECEIVER', 'DELIVER', "f=#{position}", "wrong=#{payload}")
    end
    @expected += 1
    @nak_sent = false
  end

  def discard(seq)
    @discarded += 1
    trace('RECEIVER', 'DISCARD', "seq=#{seq}")
  end

  def send_control(kind, value)
    item = @control_channel.send(kind, value, nil, @tick, @generator)
    @naks += 1 if kind == 'nak'
    trace('RECEIVER', kind.upcase, "a=#{value}", "##{item.number}")
  end

  def receive_control(item)
    before = [@cwnd, @ssthresh]
    if item.kind == 'ack'
      @selective ? selective_ack(item) : go_back_n_ack(item)
    else
      @selective ? selective_nak(item) : go_back_n_nak(item)
    end
    report_window(before)
  end

  def control_line(item, accepted)
    parts = ["#{accepted ? 'GOT' : 'OLD'}#{item.kind.upcase}", "a=#{item.value}", "##{item.number}"]
    parts << "base=#{@base}" if accepted
    trace('SENDER', *parts)
  end

  def go_back_n_ack(item)
    frame = frame_of(item.value)
    if frame < @frames_sent
      grow_window(frame - @base + 1)
      move_base(frame + 1)
      @next_frame = @base if @next_frame < @base
      @timer = @base == @next_frame ? nil : @tick + @timer_length
      control_line(item, true)
      return
    end
    control_line(item, false)
    return if @config.dupack.nil? || @base < 1
    if item.value == (@base - 1) % @modulus
      @duplicates += 1
      if @duplicates == @config.dupack
        @fast_retransmits += 1
        trace('SENDER', 'FASTRETX', "f=#{@base}")
        go_back
        halve_window
      end
    end
  end

  def go_back_n_nak(item)
    frame = frame_of(item.value)
    if frame > @frames_sent
      control_line(item, false)
      return
    end
    grow_window(frame - @base)
    move_base(frame)
    go_back
    halve_window
    control_line(item, true)
  end

  def selective_ack(item)
    frame = frame_of(item.value)
    if frame >= @frames_sent || @acked[frame]
      control_line(item, false)
      return
    end
    @acked[frame] = true
    @records[frame].acked = @tick
    @timers[frame] = nil
    @queue.delete(frame)
    grow_window(1)
    previous = @base
    @base += 1 while @base < @frames_sent && @acked[@base]
    @timer_length = @config.timeout if @base > previous
    control_line(item, true)
  end

  def selective_nak(item)
    frame = frame_of(item.value)
    if frame >= @frames_sent || @acked[frame]
      control_line(item, false)
      return
    end
    @timers[frame] = nil
    @queue << frame unless @queue.include?(frame)
    halve_window
    control_line(item, true)
  end

  def move_base(new_base)
    return if new_base <= @base
    (@base...new_base).each { |frame| @records[frame].acked = @tick }
    @base = new_base
    @timer_length = @config.timeout
    @duplicates = 0
  end

  def go_back
    @next_frame = @base
    @timer = nil
    @duplicates = 0
  end

  def grow_window(count)
    return unless @config.congestion
    count.times do
      next if @cwnd >= @config.window
      if @cwnd < @ssthresh
        @cwnd += 1
      else
        @round_acks += 1
        if @round_acks == @cwnd
          @cwnd += 1
          @round_acks = 0
        end
      end
    end
  end

  def halve_window
    return unless @config.congestion
    @ssthresh = [@cwnd / 2, 1].max
    @cwnd = @ssthresh
    @round_acks = 0
  end

  def collapse_window
    return unless @config.congestion
    @ssthresh = [@cwnd / 2, 1].max
    @cwnd = 1
    @round_acks = 0
  end

  def report_window(before)
    trace('SENDER', 'CWND', @cwnd, "ssthresh=#{@ssthresh}") if [@cwnd, @ssthresh] != before
  end

  def process_timeouts
    if @selective
      (@base...@frames_sent).each do |frame|
        next unless @timers[frame] == @tick
        @timers[frame] = nil
        @queue << frame
        time_out(frame)
      end
    elsif @timer == @tick
      time_out(@base)
      go_back
    end
  end

  def time_out(frame)
    before = [@cwnd, @ssthresh]
    @timeouts += 1
    trace('SENDER', 'TIMEOUT', "f=#{frame}")
    @timer_length = [2 * @timer_length, 8 * @config.timeout].min if @config.backoff
    collapse_window
    report_window(before)
  end

  def may_send_new?(frame)
    frame < @config.frames && frame < @base + effective_window &&
      frame * @config.interval <= @tick
  end

  def send_data
    @selective ? selective_send : go_back_n_send
  end

  def go_back_n_send
    frame = @next_frame
    return if frame >= @config.frames || frame >= @base + effective_window
    return if frame >= @frames_sent && frame * @config.interval > @tick
    transmit(frame)
    @frames_sent = [@frames_sent, frame + 1].max
    @next_frame += 1
    @timer = @tick + @timer_length if @timer.nil?
  end

  def selective_send
    if !@queue.empty?
      frame = @queue.shift
    elsif may_send_new?(@frames_sent)
      frame = @frames_sent
      @frames_sent += 1
    else
      return
    end
    transmit(frame)
    @timers[frame] = @tick + @timer_length
  end

  def transmit(frame)
    record = @records[frame]
    seq = frame % @modulus
    item = @data_channel.send('data', seq, frame, @tick, @generator)
    record.transmissions += 1
    if record.transmissions == 1
      record.first = @tick
      label = 'SEND'
    else
      @resent += 1
      label = 'RESEND'
    end
    trace('SENDER', label, "f=#{frame}", "seq=#{seq}", "##{item.number}")
  end

  def sender_mark(frame)
    if @selective
      acknowledged = @acked[frame]
      waiting = @queue.include?(frame)
      sent = frame < @frames_sent
    else
      acknowledged = frame < @base
      waiting = @next_frame <= frame && frame < @frames_sent
      sent = frame < @next_frame
    end
    return 'A' if acknowledged
    return 'R' if waiting
    return 'O' if sent
    return 'W' if frame < @base + effective_window
    '.'
  end

  def receiver_mark(position)
    return 'D' if position < @expected
    if @selective
      return 'B' if @buffer.key?(position)
      return 'W' if position < @expected + @config.window
    elsif position == @expected
      return 'W'
    end
    '.'
  end

  def snapshot
    sender = (0...@config.frames).map { |f| sender_mark(f) }.join
    receiver = (0...@config.frames).map { |f| receiver_mark(f) }.join
    emit('SNAPSHOT', "sender=#{sender}", "receiver=#{receiver}")
  end

  def data_count
    @data_channel.sent
  end

  def goodput_text
    truncated(@delivered, @completion, 2)
  end

  def efficiency_text
    truncated(100 * @delivered, data_count, 1)
  end

  def latency_text
    return '-' if @delivered == 0
    total = @records.sum { |r| r.delivered.nil? ? 0 : r.delivered - r.first }
    truncated(total, @delivered, 2)
  end

  def report
    lines = @records.each_with_index.map do |record, frame|
      "frame #{frame}: seq=#{frame % @modulus} tx=#{record.transmissions} " \
        "first=#{tick_text(record.first)} delivered=#{tick_text(record.delivered)} " \
        "acked=#{tick_text(record.acked)}"
    end
    data, control = @data_channel, @control_channel
    lines << "totals: data=#{data.sent} resent=#{@resent} control=#{control.sent} " \
             "nak=#{@naks} timeouts=#{@timeouts} fastretx=#{@fast_retransmits}"
    lines << "channel: lost_data=#{data.lost} lost_ctrl=#{control.lost} " \
             "corrupt_data=#{data.corrupted} corrupt_ctrl=#{control.corrupted}"
    lines << "receiver: delivered=#{@delivered} errors=#{@errors} " \
             "discarded=#{@discarded} max_buffer=#{@max_buffer}"
    if @completion.nil?
      completion = goodput = '-'
    else
      completion, goodput = @completion.to_s, goodput_text
    end
    utilization = truncated(100 * data.sent, @tick + 1, 1)
    lines << "result: completion=#{completion} goodput=#{goodput} " \
             "efficiency=#{efficiency_text}% utilization=#{utilization}% " \
             "latency=#{latency_text}"
    lines
  end
end

class Scenario
  attr_reader :name, :config, :simulation

  def initialize(name, settings)
    @name, @settings = name, settings
    @config = @simulation = nil
  end

  def completed?
    !@simulation.nil? && !@simulation.completion.nil?
  end

  def status
    @simulation.nil? ? 'invalid' : 'aborted'
  end

  def execute(output)
    output << "== #{@name} =="
    begin
      @config = check_settings(@settings)
    rescue SettingsError => e
      output << "error: #{e.message}"
      return
    end
    output << @config.config_line
    output << @config.options_line
    @simulation = Simulation.new(@config)
    @simulation.run
    output.concat(@simulation.lines)
    output.concat(@simulation.report)
  end
end

def ranking_lines(scenarios)
  lines = ['== ranking ==']
  completed = scenarios.each_with_index.select { |scenario, _| scenario.completed? }
  completed.sort_by! do |scenario, index|
    run = scenario.simulation
    [-Rational(run.delivered, run.completion),
     -Rational(run.delivered, run.data_count), index]
  end
  completed.each_with_index do |(scenario, _), rank|
    run = scenario.simulation
    lines << "#{rank + 1}. #{scenario.name} #{scenario.config.protocol} " \
             "goodput=#{run.goodput_text} efficiency=#{run.efficiency_text}%"
  end
  scenarios.each do |scenario|
    lines << "- #{scenario.name} #{scenario.status}" unless scenario.completed?
  end
  lines
end

def protocol_lines(scenarios)
  lines = ['== protocols ==']
  PROTOCOLS.each do |protocol|
    runs = scenarios.filter_map do |scenario|
      scenario.simulation if scenario.completed? && scenario.config.protocol == protocol
    end
    next if runs.empty?
    delivered = runs.sum(&:delivered)
    ticks = runs.sum(&:completion)
    data = runs.sum(&:data_count)
    lines << "#{protocol}: runs=#{runs.length} goodput=#{truncated(delivered, ticks, 2)} " \
             "efficiency=#{truncated(100 * delivered, data, 1)}%"
  end
  lines
end

def read_scenarios(lines)
  count = lines[0].to_i
  index = 1
  Array.new(count) do
    name = lines[index].split(' ')[1]
    index += 1
    settings = []
    until lines[index] == 'END'
      key, *values = lines[index].split(' ')
      settings << [key, values]
      index += 1
    end
    index += 1
    Scenario.new(name, settings)
  end
end

scenarios = read_scenarios(STDIN.each_line.map(&:chomp))
output = []
scenarios.each { |scenario| scenario.execute(output) }
output.concat(ranking_lines(scenarios))
output.concat(protocol_lines(scenarios))
puts output
