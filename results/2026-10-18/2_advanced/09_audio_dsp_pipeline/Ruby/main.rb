require_relative 'signals'
require_relative 'effects'
require_relative 'filters'
require_relative 'dynamics'
require_relative 'analysis'

class AudioPipeline
  class CommandError < StandardError; end

  SYNTAX = {
    'SET' => %w[var value op operand],
    'IMPULSE' => %w[dst rate count pos amp], 'STEP' => %w[dst rate count pos amp],
    'NOISE' => %w[dst rate count seed], 'GAIN' => %w[dst src num den],
    'MIX' => %w[dst den], 'DELAY' => %w[dst src samples],
    'ECHO' => %w[dst src delay num den tail], 'RESAMPLE' => %w[dst src new_rate],
    'FADE' => %w[dst src in out], 'TRIM' => %w[dst src start count],
    'CONCAT' => %w[dst], 'FIR' => %w[dst src divisor], 'BIQUAD' => %w[dst src],
    'MOVAVG' => %w[dst src width], 'DCBLOCK' => %w[dst src num den],
    'NORMALIZE' => %w[dst src target], 'GATE' => %w[dst src threshold hold],
    'ENVELOPE' => %w[dst src attack release],
    'COMPRESS' => %w[dst src threshold ratio_num ratio_den attack release],
    'ANALYZE' => %w[src min_hz max_hz], 'COMPARE' => %w[src src],
    'EXPECT' => %w[src metric op value], 'SEGMENTS' => %w[src threshold gap min_length],
    'ONSETS' => %w[src attack release threshold min_gap],
    'PITCHTRACK' => %w[src frame hop min_hz max_hz threshold],
    'EXCERPT' => %w[src start count], 'PLOT' => %w[src start count columns half attack release],
    'METER' => %w[src block], 'HISTOGRAM' => %w[src bins], 'TRACE' => %w[src], 'SAVE' => %w[src]
  }.freeze
  GENERATING = %w[IMPULSE STEP NOISE GAIN MIX DELAY ECHO RESAMPLE FADE TRIM CONCAT
                  FIR BIQUAD MOVAVG DCBLOCK NORMALIZE GATE ENVELOPE COMPRESS].freeze
  METRICS = %w[samples peak rms sum zero_crossings clipped].freeze
  SET_OPERATORS = %w[+ - * /].freeze
  EXPECT_OPERATORS = %w[eq ne lt le gt ge].freeze

  def initialize
    @signals = {}
    @variables = {}
    @log = []
    @analysis = ['signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz']
    @excerpts = []
    @waveforms = []
    @saved = []
    @steps = 0
    @errors = 0
    @passed = 0
    @failed = 0
    Signals.read.each do |signal|
      @signals[signal.name] = signal
      @log << "load #{signal.name} rate=#{signal.rate} samples=#{signal.length} peak=#{Signals.peak(signal.samples)}"
    end
  end

  def argument_names(command, count)
    names = SYNTAX.fetch(command)
    case command
    when 'SET'
      [2, 4].include?(count) ? names.first(count) : nil
    when 'MIX'
      names + %w[src weight] * ((count - 2).div(2)) if count.between?(4, 18) && count.even?
    when 'CONCAT'
      names + ['src'] * (count - 1) if count.between?(3, 9)
    when 'FIR'
      names + ['tap'] * (count - 3) if count.between?(4, 67)
    when 'BIQUAD'
      names + %w[b0 b1 b2 a1 a2] * ((count - 2).div(5)) if count.between?(7, 22) && (count - 2) % 5 == 0
    else
      names if names.length == count
    end
  end

  def argument_range(command, name, values)
    source = values['src']
    length = source&.length
    rate = source&.rate
    case name
    when 'rate', 'new_rate' then [1000, 48_000]
    when 'count'
      if %w[TRIM PLOT].include?(command)
        [1, length - values['start']]
      elsif command == 'EXCERPT'
        [1, 1000]
      else
        [1, 20_000]
      end
    when 'pos' then [0, values['count'] - 1]
    when 'amp', 'tap' then [-32_768, 32_767]
    when 'seed' then [1, 2_147_483_646]
    when 'value' then command == 'EXPECT' ? [-1_000_000_000, 1_000_000_000] : [-10_000_000, 10_000_000]
    when 'operand' then [-10_000_000, 10_000_000]
    when 'num' then command == 'DCBLOCK' ? [0, 65_535] : [-65_536, 65_536]
    when 'den' then [command == 'DCBLOCK' ? values['num'] + 1 : 1, 65_536]
    when 'weight', 'b0', 'b1', 'b2', 'a1', 'a2' then [-65_536, 65_536]
    when 'samples', 'tail', 'hold' then [0, 20_000]
    when 'delay', 'gap', 'min_length', 'min_gap', 'block' then [1, 20_000]
    when 'in', 'out' then [0, length]
    when 'start' then [0, length - 1]
    when 'divisor' then [1, 1_000_000]
    when 'width' then [1, 1000]
    when 'target' then [1, 32_767]
    when 'threshold'
      if %w[GATE SEGMENTS].include?(command)
        [1, 32_768]
      elsif command == 'PITCHTRACK'
        [0, 32_767]
      else
        [1, 32_767]
      end
    when 'attack', 'release' then [1, 32_768]
    when 'ratio_num' then [1, 100]
    when 'ratio_den' then [1, values['ratio_num']]
    when 'min_hz' then [1, rate.div(2) - 1]
    when 'max_hz' then [values['min_hz'] + 1, rate.div(2)]
    when 'frame' then [16, length]
    when 'hop' then [1, values['frame']]
    when 'columns' then [8, [120, values['count']].min]
    when 'half' then [2, 20]
    when 'bins' then [2, 64]
    end
  end

  def integer_argument(token)
    if token.start_with?('$')
      name = token[1..]
      raise CommandError, "undefined variable #{token}" unless @variables.key?(name)

      @variables[name]
    else
      valid = token.match?(/\A-?(?:0|[1-9][0-9]{0,9})\z/) && token != '-0'
      raise CommandError, "bad integer #{token}" unless valid

      token.to_i
    end
  end

  def validate(command, tokens)
    raise CommandError, "unknown command #{command}" unless SYNTAX.key?(command)

    names = argument_names(command, tokens.length)
    raise CommandError, 'wrong number of arguments' unless names

    values = {}
    arguments = names.zip(tokens).map do |name, token|
      value = case name
              when 'dst', 'var'
                raise CommandError, "bad name #{token}" unless token.match?(/\A[a-z][a-z0-9_]{0,15}\z/)

                token
              when 'src'
                raise CommandError, "unknown signal #{token}" unless @signals.key?(token)

                @signals[token]
              when 'metric'
                raise CommandError, "unknown metric #{token}" unless METRICS.include?(token)

                token
              when 'op'
                operators = command == 'SET' ? SET_OPERATORS : EXPECT_OPERATORS
                raise CommandError, "unknown operator #{token}" unless operators.include?(token)

                token
              else
                integer = integer_argument(token)
                lower, upper = argument_range(command, name, values)
                raise CommandError, "#{name} out of range" unless integer.between?(lower, upper)

                integer
              end
      values[name] = value unless values.key?(name)
      value
    end
    check_conditions(command, arguments, values)
    [arguments, values]
  end

  def check_conditions(command, arguments, values)
    source = values['src']
    sources = arguments.grep(Signals::Signal)
    if command == 'SET'
      result = values['value']
      if arguments.length == 4
        operand = values['operand']
        raise CommandError, 'division by zero' if values['op'] == '/' && operand.zero?

        result = case values['op']
                 when '+' then result + operand
                 when '-' then result - operand
                 when '*' then result * operand
                 when '/' then result.div(operand)
                 end
        raise CommandError, 'value out of range' if result.abs > 10_000_000
      end
      values['result'] = result
    elsif %w[MIX CONCAT COMPARE].include?(command)
      raise CommandError, 'rate mismatch' unless sources.all? { |signal| signal.rate == sources[0].rate }
      raise CommandError, 'result too long' if command == 'CONCAT' && sources.sum(&:length) > 20_000
    elsif command == 'DELAY'
      raise CommandError, 'result too long' if source.length + values['samples'] > 20_000
    elsif command == 'ECHO'
      raise CommandError, 'unstable feedback' if values['num'].abs >= values['den']
      raise CommandError, 'result too long' if source.length + values['tail'] > 20_000
    elsif command == 'RESAMPLE'
      length = ((source.length - 1) * values['new_rate']).div(source.rate) + 1
      raise CommandError, 'result too long' if length > 20_000
    elsif %w[ANALYZE PITCHTRACK].include?(command)
      low = (source.rate + values['max_hz'] - 1).div(values['max_hz'])
      high = source.rate.div(values['min_hz'])
      raise CommandError, 'empty lag range' if low > high

      limit = command == 'ANALYZE' ? source.length : values['frame']
      raise CommandError, (command == 'ANALYZE' ? 'signal too short' : 'frame too short') if high >= limit

      values['low'] = low
      values['high'] = high
    end
  end

  def generate(command, arguments, values, line)
    source = values['src']
    input = source&.samples
    rate = source ? source.rate : values['rate']
    extras = {}
    case command
    when 'IMPULSE' then samples = Signals.impulse(values['count'], values['pos'], values['amp'])
    when 'STEP' then samples = Signals.step(values['count'], values['pos'], values['amp'])
    when 'NOISE' then samples = Signals.noise(values['count'], values['seed'])
    when 'GAIN' then samples, extras = Effects.gain(input, values['num'], values['den'])
    when 'MIX'
      pairs = arguments.drop(2).each_slice(2).to_a
      sources = pairs.map(&:first)
      rate = sources[0].rate
      samples, extras = Effects.mix(sources, pairs.map(&:last), values['den'])
    when 'DELAY' then samples = Effects.delay(input, values['samples'])
    when 'ECHO' then samples, extras = Effects.echo(input, values['delay'], values['num'], values['den'], values['tail'])
    when 'RESAMPLE'
      rate = values['new_rate']
      samples = Effects.resample(input, source.rate, rate)
    when 'FADE' then samples = Effects.fade(input, values['in'], values['out'])
    when 'TRIM' then samples = input[values['start'], values['count']]
    when 'CONCAT' then samples = arguments.drop(1).flat_map(&:samples)
    when 'FIR' then samples, extras = Filters.fir(input, values['divisor'], arguments.drop(3))
    when 'BIQUAD' then samples, extras = Filters.biquad(input, arguments.drop(2))
    when 'MOVAVG' then samples = Filters.moving_average(input, values['width'])
    when 'DCBLOCK' then samples, extras = Filters.dc_block(input, values['num'], values['den'])
    when 'NORMALIZE' then samples, extras = Dynamics.normalize(input, values['target'])
    when 'GATE' then samples, extras = Dynamics.gate(input, values['threshold'], values['hold'])
    when 'ENVELOPE' then samples = Dynamics.envelope(input, values['attack'], values['release'])
    when 'COMPRESS'
      samples, extras = Dynamics.compress(input, values['threshold'], values['ratio_num'], values['ratio_den'],
                                          values['attack'], values['release'])
    end
    name = values['dst']
    signal = Signals.create(name, rate, samples, "line #{line} #{command}", arguments.grep(Signals::Signal))
    @signals[name] = signal
    detail = "#{name} rate=#{rate} samples=#{samples.length} peak=#{Signals.peak(samples)} sum=#{samples.sum}"
    extras.each { |key, value| detail += " #{key}=#{value}" }
    detail
  end

  def metric(signal, name)
    samples = signal.samples
    case name
    when 'samples' then signal.length
    when 'peak' then Signals.peak(samples)
    when 'rms' then Analysis.rms(samples)
    when 'sum' then samples.sum
    when 'zero_crossings' then Analysis.zero_crossings(samples)
    when 'clipped' then Analysis.clipped(samples)
    end
  end

  def frequency(rate, lag)
    lag ? Signals.two_decimals(Signals.rdiv(100 * rate, lag)) : 'none'
  end

  def analyze(source, values)
    samples = source.samples
    lag = Analysis.pitch_lag(samples, values['low'], values['high'])
    @analysis << [source.name, Signals.peak(samples), Analysis.rms(samples), Analysis.zero_crossings(samples),
                  Analysis.clipped(samples), Analysis.crest(samples), lag || 'none', frequency(source.rate, lag)].join(',')
    "#{source.name} lags=#{values['low']}-#{values['high']}"
  end

  def compare(first, second)
    count = [first.length, second.length].max
    differing = 0
    maximum = 0
    earliest = nil
    energy = 0
    count.times do |index|
      difference = (first.samples[index] || 0) - (second.samples[index] || 0)
      unless difference.zero?
        differing += 1
        earliest ||= index
      end
      maximum = [maximum, difference.abs].max
      energy += difference * difference
    end
    "#{first.name} #{second.name} differing=#{differing} max_diff=#{maximum} first=#{earliest || 'none'} error_energy=#{energy}"
  end

  def expect(source, values)
    actual = metric(source, values['metric'])
    expected = values['value']
    passed = case values['op']
             when 'eq' then actual == expected
             when 'ne' then actual != expected
             when 'lt' then actual < expected
             when 'le' then actual <= expected
             when 'gt' then actual > expected
             when 'ge' then actual >= expected
             end
    if passed
      @passed += 1
    else
      @failed += 1
    end
    "#{source.name} #{values['metric']}=#{actual} #{values['op']} #{expected} #{passed ? 'pass' : 'fail'}"
  end

  def segments(source, values)
    groups = []
    source.samples.each_with_index do |sample, index|
      next if sample.abs < values['threshold']

      if groups.empty? || index - groups[-1][1] > values['gap']
        groups << [index, index]
      else
        groups[-1][1] = index
      end
    end
    groups.select! { |start, finish| finish - start + 1 >= values['min_length'] }
    lines = groups.each_with_index.map do |(start, finish), index|
      samples = source.samples[start..finish]
      "  segment #{index + 1} start=#{start} end=#{finish} start_ms=#{(start * 1000).div(source.rate)} end_ms=#{(finish * 1000).div(source.rate)} peak=#{Signals.peak(samples)} rms=#{Analysis.rms(samples)} crossings=#{Analysis.zero_crossings(samples)}"
    end
    ["#{source.name} segments=#{groups.length}", lines]
  end

  def onsets(source, values)
    envelope = Dynamics.envelope(source.samples, values['attack'], values['release'])
    points = []
    envelope.each_index do |index|
      next unless envelope[index] >= values['threshold'] && (index.zero? || envelope[index - 1] < values['threshold'])
      next unless points.empty? || index - points[-1] >= values['min_gap']

      points << index
    end
    tempo = 'none'
    if points.length >= 2
      intervals = points.each_cons(2).map { |left, right| right - left }.sort
      median = intervals[(points.length - 2).div(2)]
      tempo = Signals.two_decimals(Signals.rdiv(6000 * source.rate, median))
    end
    lines = points.each_with_index.map do |point, index|
      interval = index.zero? ? 'none' : point - points[index - 1]
      "  onset #{index + 1} sample=#{point} ms=#{(point * 1000).div(source.rate)} interval=#{interval}"
    end
    ["#{source.name} onsets=#{points.length} tempo=#{tempo}", lines]
  end

  def excerpt(source, values)
    start = values['start']
    count = [values['count'], source.length - start].min
    @excerpts << "EXCERPT #{source.name} rate=#{source.rate} samples=#{source.length} start=#{start} count=#{count}"
    source.samples[start, count].each_slice(8).with_index do |samples, index|
      @excerpts << (start + index * 8).to_s.rjust(5) + ':' + samples.map { |value| ' ' + value.to_s.rjust(6) }.join
    end
    "#{source.name} start=#{start} count=#{count}"
  end

  def waveform(source, values)
    start, count, columns, half = values.values_at('start', 'count', 'columns', 'half')
    attack, release = values.values_at('attack', 'release')
    samples = source.samples[start, count]
    envelope = Dynamics.envelope(source.samples, attack, release)[start, count]
    rows = 2 * half + 1
    scale = [1, Signals.peak(samples)].max
    row_number = ->(value) { Signals.rdiv((scale - value) * (rows - 1), 2 * scale) }
    cells = Array.new(rows) { Array.new(columns, ' ') }
    columns.times do |column|
      first = (column * count).div(columns)
      last = ((column + 1) * count).div(columns)
      section = samples[first...last]
      top = row_number.call(section.max)
      bottom = row_number.call(section.min)
      level = [scale, envelope[first...last].max].min
      upper_envelope = row_number.call(level)
      lower_envelope = row_number.call(-level)
      rows.times do |row|
        cells[row][column] = if row == upper_envelope || row == lower_envelope
                              '*'
                            elsif row.between?(top, bottom)
                              '#'
                            elsif row == half
                              '-'
                            else
                              ' '
                            end
      end
    end
    @waveforms << "PLOT #{source.name} rate=#{source.rate} start=#{start} count=#{count} columns=#{columns} rows=#{rows} scale=#{scale} attack=#{attack} release=#{release}"
    rows.times do |row|
      label = row.zero? ? scale.to_s : row == half ? '0' : row == rows - 1 ? (-scale).to_s : ''
      @waveforms << label.rjust(6) + ' |' + cells[row].join + '|'
    end
    @waveforms << '       +' + Array.new(columns) { |column| column % 10 == 0 ? '+' : '-' }.join + '+'
    time = '    ms'
    (0...columns).step(10) do |column|
      label = ((start + (column * count).div(columns)) * 1000).div(source.rate).to_s
      position = 8 + column
      time = time.ljust(position)
      time[position, label.length] = label
    end
    @waveforms << time
    "#{source.name} start=#{start} count=#{count} columns=#{columns} rows=#{rows}"
  end

  def meter(source, block)
    count = (source.length + block - 1).div(block)
    @waveforms << "METER #{source.name} rate=#{source.rate} samples=#{source.length} block=#{block} blocks=#{count}"
    source.samples.each_slice(block).with_index do |samples, index|
      peak = Signals.peak(samples)
      rms = Analysis.rms(samples)
      peak_width = Signals.rdiv(peak * 40, 32_768)
      rms_width = Signals.rdiv(rms * 40, 32_768)
      bar = '#' * rms_width + '-' * (peak_width - rms_width) + ' ' * (40 - peak_width)
      time = (index * block * 1000).div(source.rate)
      @waveforms << time.to_s.rjust(6) + " |#{bar}| peak=#{peak} rms=#{rms} clipped=#{Analysis.clipped(samples)}"
    end
    "#{source.name} block=#{block}"
  end

  def histogram(source, bins)
    counts = Array.new(bins, 0)
    source.samples.each { |value| counts[((value + 32_768) * bins).div(65_536)] += 1 }
    maximum = counts.max
    @waveforms << "HISTOGRAM #{source.name} rate=#{source.rate} samples=#{source.length} bins=#{bins} max=#{maximum}"
    bins.times do |bin|
      lower = (bin * 65_536 + bins - 1).div(bins) - 32_768
      upper = ((bin + 1) * 65_536 + bins - 1).div(bins) - 32_769
      bar = '#' * Signals.rdiv(counts[bin] * 50, maximum)
      @waveforms << lower.to_s.rjust(6) + ' ' + upper.to_s.rjust(6) + ' ' + counts[bin].to_s.rjust(5) + ' |' + bar
    end
    "#{source.name} bins=#{bins}"
  end

  def pitch_track(source, values)
    frame, hop, threshold = values.values_at('frame', 'hop', 'threshold')
    low, high = values.values_at('low', 'high')
    count = (source.length - frame).div(hop) + 1
    frames = Array.new(count) do |index|
      samples = source.samples[index * hop, frame]
      level = Analysis.rms(samples)
      lag = level >= threshold ? Analysis.pitch_lag(samples, low, high) : nil
      [level, lag]
    end
    voiced = frames.count { |_level, lag| lag }
    @waveforms << "PITCHTRACK #{source.name} rate=#{source.rate} frame=#{frame} hop=#{hop} lags=#{low}-#{high} threshold=#{threshold} frames=#{count} voiced=#{voiced}"
    frames.each_with_index do |(level, lag), index|
      scale = ' ' * 41
      if lag
        position = high > low ? Signals.rdiv((high - lag) * 40, high - low) : 0
        scale[position] = 'o'
        detail = " lag=#{lag} hz=#{frequency(source.rate, lag)} rms=#{level}"
      else
        detail = " unvoiced rms=#{level}"
      end
      time = (index * hop * 1000).div(source.rate)
      @waveforms << time.to_s.rjust(6) + ' |' + scale + '|' + detail
    end
    "#{source.name} frames=#{count} voiced=#{voiced}"
  end

  def trace(source)
    lines = []
    stack = [[source, 1]]
    until stack.empty?
      signal, depth = stack.pop
      lines << ' ' * (2 * depth) + "#{signal.name} <- #{signal.origin}"
      signal.ingredients.reverse_each { |ingredient| stack << [ingredient, depth + 1] }
    end
    lines
  end

  def execute(command, arguments, values, line)
    return [generate(command, arguments, values, line), []] if GENERATING.include?(command)

    source = values['src']
    case command
    when 'SET'
      @variables[values['var']] = values['result']
      ["#{values['var']}=#{values['result']}", []]
    when 'ANALYZE' then [analyze(source, values), []]
    when 'COMPARE' then [compare(*arguments), []]
    when 'EXPECT' then [expect(source, values), []]
    when 'SEGMENTS' then segments(source, values)
    when 'ONSETS' then onsets(source, values)
    when 'EXCERPT' then [excerpt(source, values), []]
    when 'PLOT' then [waveform(source, values), []]
    when 'METER' then [meter(source, values['block']), []]
    when 'HISTOGRAM' then [histogram(source, values['bins']), []]
    when 'PITCHTRACK' then [pitch_track(source, values), []]
    when 'TRACE' then [source.name, trace(source)]
    when 'SAVE'
      @saved.concat(Signals.output(source))
      ["#{source.name} samples=#{source.length}", []]
    end
  end

  def run
    File.readlines('input/pipeline.txt', chomp: true).each_with_index do |text, index|
      next if text.empty? || text.start_with?('#')

      command, *tokens = text.split(' ')
      begin
        arguments, values = validate(command, tokens)
        details, extra = execute(command, arguments, values, index + 1)
        @steps += 1
        @log << "line #{index + 1}: #{command} #{details}"
        @log.concat(extra)
      rescue CommandError => error
        @errors += 1
        @log << "line #{index + 1}: error: #{error.message}"
      end
    end
    @signals.keys.sort.each do |name|
      signal = @signals[name]
      @log << "signal #{name} rate=#{signal.rate} samples=#{signal.length} peak=#{Signals.peak(signal.samples)} rms=#{Analysis.rms(signal.samples)}"
    end
    @log << "summary steps=#{@steps} errors=#{@errors} signals=#{@signals.length} passed=#{@passed} failed=#{@failed}"
    files = { 'log.txt' => @log, 'analysis.csv' => @analysis, 'excerpts.txt' => @excerpts,
              'waveforms.txt' => @waveforms, 'signals_out.txt' => @saved }
    Dir.mkdir('output') unless Dir.exist?('output')
    files.each do |name, lines|
      File.binwrite(File.join('output', name), lines.empty? ? '' : lines.join("\n") + "\n")
    end
  end
end

AudioPipeline.new.run if $PROGRAM_NAME == __FILE__
