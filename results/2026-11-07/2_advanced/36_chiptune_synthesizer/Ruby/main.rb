require_relative 'song_parser'
require_relative 'instruments'
require_relative 'sequencer'
require_relative 'mixer'
require_relative 'report'

module Chiptune
  FMIN = 1000
  LANE_LIMIT = 3375
  EFFECT_ORDER = %w[0 1 2 3 4 5 6 7 A B C D E1 E2 E9 EA EB EC ED EE F P Q R V].freeze
  TONICS = %w[C C# D D# E F F# G G# A A# B].freeze
  MAJOR_WEIGHTS = [64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29].freeze
  MINOR_WEIGHTS = [64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32].freeze

  NoteRecord = Struct.new(:serial, :channel, :position, :row, :instrument, :note,
                          :start, :length, :release, :reason, keyword_init: true)
  PlayedRow = Struct.new(:position, :row, :start, :speed, :tempo, :notes, keyword_init: true)

  class Channel
    include Instruments

    attr_accessor :number, :instrument, :note, :frequency, :target, :portamento, :slide,
                  :detune, :vibrato_speed, :vibrato_depth, :vibrato_position,
                  :tremolo_speed, :tremolo_depth, :tremolo_position, :volume, :mode,
                  :phase, :register, :age, :released, :release_age, :release_level,
                  :envelope, :output_frequency, :output_volume, :amplitude,
                  :increment, :effect, :sounding, :record, :note_ons, :retriggers,
                  :cuts, :active, :audible

    def initialize(number)
      @number = number
      @instrument = @note = @effect = @record = nil
      @frequency = @target = @portamento = @slide = @detune = 0
      @vibrato_speed = @vibrato_depth = @vibrato_position = 0
      @tremolo_speed = @tremolo_depth = @tremolo_position = 0
      @volume = 15
      @mode = @phase = @age = @release_age = @release_level = 0
      @register = 1
      @released = @sounding = false
      @envelope = @output_frequency = @output_volume = @amplitude = @increment = 0
      @note_ons = @retriggers = @cuts = @active = @audible = 0
    end

    def effect_name = @effect&.name
    def effect_value = @effect ? @effect.value : 0

    def key_off
      @release_age = @age
      @release_level = @envelope
      @released = true
    end

    def approach(step)
      @frequency = if @frequency < @target
                     [@frequency + step, @target].min
                   else
                     [@frequency - step, @target].max
                   end
    end

    def volume_slide
      @volume = (@volume + @effect.high - @effect.low).clamp(0, 15)
    end

    def update_output(tick, rate)
      name = effect_name
      semitones = name == '0' ? [0, @effect.high, @effect.low][tick % 3] : 0
      unless @instrument.arpeggio.empty?
        semitones += @instrument.arpeggio[@age % @instrument.arpeggio.length]
      end
      frequency = transpose(@frequency, semitones) + @detune
      if name == '4' || name == '6'
        frequency += oscillation(@vibrato_position, @vibrato_depth, 4)
      end
      if @instrument.vibrato
        delay, speed, depth = @instrument.vibrato
        frequency += oscillation((@age - delay) * speed % 64, depth, 4) if @age >= delay
      end
      @output_frequency = frequency.clamp(FMIN, 50 * rate)
      @envelope = envelope_value(@instrument, @age, @released, @release_age, @release_level)
      @output_volume = if name == '7'
                         (@volume + oscillation(@tremolo_position, @tremolo_depth, 255)).clamp(0, 15)
                       else
                         @volume
                       end
      @amplitude = @envelope * @output_volume
      @increment = @output_frequency * 65536 / (100 * rate)
    end
  end

  class Player
    include Instruments
    include Report
    include SongParser

    def initialize(song, params)
      @song = song
      @params = params
      @fmax = 50 * song.rate
      @channels = (1..SongParser::CHANNELS).map { |number| Channel.new(number) }
      @lanes = Array.new(SongParser::CHANNELS) { [] }
      @samples = []
      @speed = song.speed
      @tempo = song.tempo
      @delay = @position = @row = @ticks = @clipped = 0
      @cells = []
      @records = []
      @warnings = []
      @log = []
      @played = []
      @play_counts = Hash.new(0)
      @first_starts = {}
      @instrument_ticks = Hash.new(0)
      @effect_counts = Hash.new(0)
      @end_reason = 'finished'
      @end_row = @loop_start = nil
    end

    def warn(channel, message)
      @warnings << "warning #{hex2(@position)}:#{hex2(@row)} ch#{channel.number} #{message}"
    end

    def clamp_frequency(frequency) = frequency.clamp(FMIN, @fmax)

    def end_record(channel, reason)
      return unless channel.record

      channel.record.length = @samples.length - channel.record.start
      channel.record.reason = reason
      channel.record = nil
    end

    def note_on(channel, note)
      end_record(channel, 'next')
      channel.frequency = channel.target = note_frequency(note)
      channel.phase = channel.age = channel.vibrato_position = channel.tremolo_position = 0
      channel.released = false
      channel.note = note
      channel.note_ons += 1
      channel.record = NoteRecord.new(serial: @records.length + 1, channel: channel.number,
                                      position: @position, row: @row, instrument: channel.instrument,
                                      note: note, start: @samples.length)
      @records << channel.record
    end

    def apply_cell(channel, cell, portamento)
      if cell.instrument
        instrument = @song.instruments[cell.instrument]
        if instrument
          channel.instrument = instrument
          channel.volume = 15
          channel.mode = instrument.mode
        else
          warn(channel, "undefined instrument #{hex2(cell.instrument)}")
        end
      end
      channel.volume = cell.volume unless cell.volume.nil?
      if cell.note == :off
        if channel.note && !channel.released
          channel.key_off
          channel.record.release = @samples.length - channel.record.start
        else
          warn(channel, 'key off without note')
        end
      elsif cell.note
        if channel.instrument.nil?
          warn(channel, 'note without instrument')
        elsif portamento && channel.note
          channel.target = note_frequency(cell.note)
          channel.note = cell.note
        else
          warn(channel, 'portamento without note') if portamento
          note_on(channel, cell.note)
        end
      end
    end

    def note_slide(channel, effect)
      unless channel.note
        warn(channel, 'slide without note')
        return
      end
      channel.note = if effect.name == 'Q'
                       [channel.note + effect.low, 95].min
                     else
                       [channel.note - effect.low, 12].max
                     end
      channel.target = note_frequency(channel.note)
      channel.slide = 2 * effect.high + 1
    end

    def set_mode(channel, value)
      wave = channel.instrument&.wave
      if (wave == 'PULSE' && value <= 3) || (wave == 'NOISE' && value <= 1)
        channel.mode = value
      else
        warn(channel, "invalid mode #{hex2(value)}")
      end
    end

    def start_effect(channel)
      effect = channel.effect
      value = effect.value
      case effect.name
      when '3' then channel.portamento = value if value.positive?
      when '4'
        channel.vibrato_speed = effect.high if effect.high.positive?
        channel.vibrato_depth = effect.low if effect.low.positive?
      when '7'
        channel.tremolo_speed = effect.high if effect.high.positive?
        channel.tremolo_depth = effect.low if effect.low.positive?
      when 'C' then channel.volume = [value, 15].min
      when 'E1' then channel.frequency = clamp_frequency(channel.frequency + 10 * value)
      when 'E2' then channel.frequency = clamp_frequency(channel.frequency - 10 * value)
      when 'EA' then channel.volume = [channel.volume + value, 15].min
      when 'EB' then channel.volume = [channel.volume - value, 0].max
      when 'EE' then @delay = value
      when 'F'
        if value.between?(1, 31)
          @speed = value
        elsif value >= 32
          @tempo = value
        end
      when 'P' then channel.detune = value - 128
      when 'Q', 'R' then note_slide(channel, effect)
      when 'V' then set_mode(channel, value)
      end
    end

    def tick_effect(channel)
      effect = channel.effect
      case effect.name
      when '1' then channel.frequency = clamp_frequency(channel.frequency + 10 * effect.value)
      when '2' then channel.frequency = clamp_frequency(channel.frequency - 10 * effect.value)
      when '3' then channel.approach(10 * channel.portamento)
      when '5'
        channel.approach(10 * channel.portamento)
        channel.volume_slide
      when '6', 'A' then channel.volume_slide
      when 'Q', 'R' then channel.approach(10 * channel.slide) unless channel.slide.zero?
      end
    end

    def start_row
      @delay = 0
      @channels.zip(@cells).each do |channel, cell|
        channel.effect = cell.effect
        channel.slide = 0
        @effect_counts[cell.effect.name] += 1 if cell.effect
        name = channel.effect_name
        unless name == 'ED' && channel.effect_value >= 1
          apply_cell(channel, cell, name == '3' || name == '5')
        end
        start_effect(channel) if channel.effect
      end
      ticks = @speed * (1 + @delay)
      @channels.each do |channel|
        next unless channel.effect_value >= ticks

        case channel.effect_name
        when 'EC' then warn(channel, 'cut beyond row')
        when 'ED' then warn(channel, 'delay beyond row')
        end
      end
      ticks
    end

    def process_tick(tick)
      @channels.zip(@cells).each do |channel, cell|
        name = channel.effect_name
        value = channel.effect_value
        if channel.note && channel.age >= 1 && !channel.instrument.sweep.zero?
          channel.frequency = clamp_frequency(channel.frequency + 10 * channel.instrument.sweep)
        end
        tick_effect(channel) if tick >= 1 && channel.effect
        apply_cell(channel, cell, false) if name == 'ED' && value >= 1 && tick == value
        if name == 'E9' && value >= 1 && tick >= 1 && tick % value == 0 && channel.note
          channel.phase = channel.age = 0
          channel.released = false
          channel.retriggers += 1
        end
        if name == 'EC' && tick == value && channel.note
          end_record(channel, 'cut')
          channel.note = nil
          channel.cuts += 1
        end
        channel.sounding = !channel.note.nil?
        next unless channel.sounding

        channel.update_output(tick, @song.rate)
        channel.active += 1
        channel.audible += 1 if channel.amplitude.positive?
        @instrument_ticks[channel.instrument.number] += 1
      end
    end

    def advance
      @channels.each do |channel|
        channel.age += 1 if channel.note
        case channel.effect_name
        when '4', '6'
          channel.vibrato_position = (channel.vibrato_position + channel.vibrato_speed) % 64
        when '7'
          channel.tremolo_position = (channel.tremolo_position + channel.tremolo_speed) % 64
        end
      end
      @ticks += 1
    end

    def channel_text(channel)
      effect = channel.effect&.text || '...'
      unless channel.note
        return format('--- -- %7s - %s %s', '-', hex1(channel.volume), effect)
      end

      format('%s %s %7d %s %s %s', note_name(channel.note), hex2(channel.instrument.number),
             channel.output_frequency, hex1(channel.envelope), hex1(channel.output_volume), effect)
    end

    def log_row(start)
      header = format('%02X %02X %02X %7d %2d %3d', @position, @song.order[@position],
                      @row, start, @speed, @tempo)
      @log << ([header] + @channels.map { |channel| channel_text(channel) }).join(' | ')
      @played << PlayedRow.new(position: @position, row: @row, start: start, speed: @speed,
                               tempo: @tempo, notes: @channels.map(&:note))
    end

    def log_tick(tick)
      parts = [format('  tick %3d %7d', tick, @samples.length)]
      @channels.each do |channel|
        parts << if channel.sounding
                   format('%7d %5d %X%X', channel.output_frequency, channel.increment,
                          channel.envelope, channel.output_volume)
                 else
                   format('%7s %5s --', '-', '-')
                 end
      end
      @log << parts.join(' | ')
    end

    def play_row(position, row)
      @position = position
      @row = row
      @cells = @song.cells(position, row)
      start = @samples.length
      @first_starts[[position, row]] ||= start
      ticks = start_row
      tick_samples = Sequencer.samples_per_tick(@song.rate, @tempo)
      traced = @params.traces.key?([position, row])
      ticks.times do |tick|
        process_tick(tick)
        log_row(start) if tick.zero?
        log_tick(tick) if traced
        count = [tick_samples, @params.max_samples - @samples.length].min
        @clipped += Mixer.mix_tick(@channels, count, @song.gain, @params.muted, @samples, @lanes)
        advance
        return false if @samples.length == @params.max_samples
      end
      true
    end

    def play
      position = row = 0
      loop do
        @play_counts[[position, row]] += 1
        unless play_row(position, row)
          @end_reason = 'limit'
          break
        end
        following = Sequencer.next_row(@song, position, row)
        if following.nil?
          @end_reason = 'stop'
          @end_row = [position, row]
          break
        end
        position, row = following
        break if position >= @song.order.length

        if @play_counts[following] >= @params.loops
          @end_reason = 'loop'
          @end_row = following
          @loop_start = @first_starts[following]
          break
        end
      end
      @channels.each { |channel| end_record(channel, 'end') }
      if %w[limit loop].include?(@end_reason) && @params.fade.positive?
        Mixer.fade_out(@samples, @params.fade)
      end
    end

    def end_text
      return @end_reason unless %w[stop loop].include?(@end_reason)

      "#{@end_reason} order=#{hex2(@end_row[0])} row=#{hex2(@end_row[1])}"
    end

    def note_range(notes)
      notes.empty? ? 'none' : "#{note_name(notes.min)}..#{note_name(notes.max)}"
    end

    def hex_list(values)
      values.empty? ? 'none' : values.map { |value| hex2(value) }.join(' ')
    end

    def note_lines
      @records.map do |record|
        segment = @lanes[record.channel - 1][record.start, record.length]
        cycles = segment.each_cons(2).count { |previous, current| previous < 0 && current >= 0 }
        release = record.release.nil? ? '-' : record.release.to_s
        format('%4d ch=%d at=%02X:%02X ins=%02X note=%s start=%d length=%d release=%s end=%s peak=%d cycles=%d',
               record.serial, record.channel, record.position, record.row, record.instrument.number,
               note_name(record.note), record.start, record.length, release, record.reason, peak(segment), cycles)
      end
    end

    def roll_lines
      start, rows = @params.roll
      targets = @played[start, rows] || []
      pitches = targets.flat_map(&:notes).compact.uniq.sort.reverse
      lines = ["ROLL start=#{start} rows=#{targets.length} pitches=#{pitches.length}"]
      pitches.each do |pitch|
        marks = targets.map do |row|
          owners = row.notes.each_index.select { |index| row.notes[index] == pitch }
          owners.empty? ? ' ' : owners.length == 1 ? (owners[0] + 1).to_s : '*'
        end
        lines << "#{note_name(pitch)} |#{marks.join}|"
      end
      ruler = targets.each_index.map { |index| index % 16 == 0 ? '+' : '-' }.join
      lines << "    +#{ruler}+"
    end

    def path_line
      positions = []
      @played.each { |row| positions << row.position if positions.last != row.position }
      'path ' + positions.map { |position| hex2(position) }.join(' ')
    end

    def timing_lines
      previous = nil
      @played.filter_map do |row|
        timing = [row.speed, row.tempo]
        changed = timing != previous
        previous = timing
        if changed
          "timing sample=#{row.start} order=#{hex2(row.position)} row=#{hex2(row.row)} speed=#{row.speed} tempo=#{row.tempo}"
        end
      end
    end

    def channel_lines
      @channels.zip(@lanes).map do |channel, lane|
        "channel #{channel.number} notes=#{channel.note_ons} retriggers=#{channel.retriggers} " \
          "cuts=#{channel.cuts} active=#{channel.active} audible=#{channel.audible} " \
          "peak=#{peak(lane)} rms=#{rms(lane)}"
      end
    end

    def instrument_lines
      @song.instruments.sort.map do |number, instrument|
        records = @records.select { |record| record.instrument.number == number }
        summary = if records.empty?
                    'range=none average=-'
                  else
                    "range=#{note_range(records.map(&:note))} average=#{records.sum(&:length) / records.length}"
                  end
        "instrument #{hex2(number)} #{instrument.name} #{instrument.wave} notes=#{records.length} " \
          "ticks=#{@instrument_ticks[number]} #{summary}"
      end
    end

    def pattern_lines
      @song.patterns.sort.map do |number, pattern|
        rows = pattern.count { |cells| cells.any? { |cell| !cell.empty? } }
        notes = pattern.sum { |cells| cells.count(&:has_note?) }
        "pattern #{hex2(number)} rows=#{rows} notes=#{notes} orders=#{@song.order.count(number)}"
      end
    end

    def order_lines
      reached = Sequencer.reachable_rows(@song)
      @song.order.each_with_index.map do |pattern, position|
        starts = @played.select { |row| row.position == position }.map(&:start)
        dead = (0...SongParser::ROWS).count do |row|
          !reached.key?([position, row]) && @song.cells(position, row).any?(&:has_note?)
        end
        first = starts.empty? ? '-' : starts.first.to_s
        "order #{hex2(position)} pattern=#{hex2(pattern)} rows=#{starts.length} first=#{first} dead=#{dead}"
      end
    end

    def note_count_lines
      @records.group_by(&:note).sort.map do |note, records|
        "note #{note_name(note)} count=#{records.length}"
      end
    end

    def effects_line
      used = EFFECT_ORDER.filter_map do |name|
        "#{name}=#{@effect_counts[name]}" if @effect_counts[name].positive?
      end
      'effects ' + (used.empty? ? 'none' : used.join(' '))
    end

    def unused_lines
      used_instruments = @records.map { |record| record.instrument.number }
      played_positions = @played.map(&:position)
      ["unused_instruments=#{hex_list(@song.instruments.keys.sort - used_instruments)}",
       "unused_patterns=#{hex_list(@song.patterns.keys.sort - @song.order)}",
       "unreached_orders=#{hex_list((0...@song.order.length).to_a - played_positions)}"]
    end

    def pitch_classes
      @records.each_with_object(Array.new(12, 0)) do |record, totals|
        totals[record.note % 12] += record.length unless record.instrument.wave == 'NOISE'
      end
    end

    def estimate_key(totals)
      keys = [MAJOR_WEIGHTS, MINOR_WEIGHTS].each_with_index.flat_map do |weights, mode|
        12.times.map do |tonic|
          score = 12.times.sum { |pitch| weights[(pitch - tonic) % 12] * totals[pitch] }
          ["#{TONICS[tonic]} #{mode.zero? ? 'major' : 'minor'}", score, mode * 12 + tonic]
        end
      end
      keys.sort_by { |_name, score, order| [-score, order] }.first(2)
    end

    def usage_lines
      @channels.map do |channel|
        records = @records.select { |record| record.channel == channel.number }
        parts = ["usage ch#{channel.number} range=#{note_range(records.map(&:note))}"]
        @song.instruments.keys.sort.each do |number|
          parts << "#{hex2(number)}=#{records.count { |record| record.instrument.number == number }}"
        end
        parts.join(' ')
      end
    end

    def stats_lines
      total = @samples.length
      stats = statistics(@samples)
      lines = ["title=#{@song.title}", "rate=#{@song.rate}", "samples=#{total}",
               "duration_ms=#{total * 1000 / @song.rate}", "end=#{end_text}"]
      lines.concat(if @end_reason == 'loop'
                     ["loop_start=#{@loop_start}", "loop_length=#{total - @loop_start}"]
                   else
                     ['loop_start=-', 'loop_length=-']
                   end)
      lines.concat(["rows=#{@played.length}", "ticks=#{@ticks}", "clipped=#{@clipped}"])
      %i[peak min max rms zero_crossings adler32].each { |key| lines << "#{key}=#{stats[key]}" }
      lines << path_line
      lines.concat(timing_lines)
      lines.concat(channel_lines)
      lines.concat(instrument_lines)
      lines.concat(pattern_lines)
      lines.concat(order_lines)
      lines.concat(note_count_lines)
      lines << effects_line
      lines.concat(unused_lines)
      totals = pitch_classes
      lines << 'pitch_classes ' + TONICS.zip(totals).map { |name, value| "#{name}=#{value}" }.join(' ')
      best, runner_up = estimate_key(totals)
      lines << "key=#{best[0]} score=#{best[1]} runner_up=#{runner_up[0]} score=#{runner_up[1]}"
      lines.concat(usage_lines)
      lines.concat(@warnings)
    end

    def plot_row(value, low, high, height)
      (2 * (high - value) * (height - 1) + high - low) / (2 * (high - low))
    end

    def plot_lines(values, low, high, middle, height, width)
      length = values.length
      middle_row = plot_row(middle, low, high, height)
      columns = width.times.map do |column|
        covered = values[column * length / width...(column + 1) * length / width]
        [plot_row(covered.max, low, high, height), plot_row(covered.min, low, high, height)]
      end
      height.times.map do |row|
        label = if row.zero?
                  high.to_s
                elsif row == middle_row
                  middle.to_s
                elsif row == height - 1
                  low.to_s
                else
                  ''
                end
        marks = columns.map do |top, bottom|
          row.between?(top, bottom) ? '#' : row == middle_row ? '-' : ' '
        end
        format('%5s |%s|', label, marks.join)
      end
    end

    def axis_lines(start, length, width)
      ruler = width.times.map { |column| column % 10 == 0 ? '+' : '-' }.join
      labels = '    ms'
      (0...width).step(10) do |column|
        milliseconds = (start + column * length / width) * 1000 / @song.rate
        labels = labels.ljust(7 + column) + milliseconds.to_s
      end
      ["      +#{ruler}+", labels]
    end

    def waveform_lines
      start, length, width, height, scope = @params.window
      axes = axis_lines(start, length, width)
      lines = ["MIX start=#{start} length=#{length} width=#{width} height=#{height}"]
      lines.concat(plot_lines(@samples[start, length], 0, 255, 128, height, width))
      lines.concat(axes)
      @lanes.each_with_index do |lane, index|
        lines << "CHANNEL #{index + 1}"
        lines.concat(plot_lines(lane[start, length], -LANE_LIMIT, LANE_LIMIT, 0, scope, width))
      end
      lines.concat(axes)
    end

    def preview_lines(instrument)
      channel = Channel.new(1)
      channel.instrument = instrument
      channel.mode = instrument.mode
      channel.note = @params.preview_note
      channel.frequency = channel.target = note_frequency(channel.note)
      channel.sounding = true
      tick_samples = Sequencer.samples_per_tick(@song.rate, @song.tempo)
      samples = []
      envelopes = []
      frequencies = []
      @params.preview_ticks.times do |tick|
        channel.age = tick
        channel.key_off if tick == @params.preview_release
        if tick >= 1 && !instrument.sweep.zero?
          channel.frequency = clamp_frequency(channel.frequency + 10 * instrument.sweep)
        end
        channel.update_output(tick, @song.rate)
        envelopes << hex1(channel.envelope)
        frequencies << channel.output_frequency
        Mixer.mix_tick([channel], tick_samples, @song.gain, [false], samples)
      end
      stats = statistics(samples)
      ["instrument #{hex2(instrument.number)} #{instrument.name} wave=#{instrument.wave} " \
       "samples=#{samples.length} peak=#{stats[:peak]} rms=#{stats[:rms]} adler32=#{stats[:adler32]}",
       '  env ' + envelopes.join, '  freq ' + frequencies.join(' ')]
    end

    def write_lines(name, lines)
      File.open(File.join('output', name), 'w:US-ASCII') do |file|
        lines.each { |line| file.puts(line) }
      end
    end

    def run
      play
      previews = @song.instruments.sort.flat_map { |_number, instrument| preview_lines(instrument) }
      Dir.mkdir('output') unless Dir.exist?('output')
      write_lines('samples.txt', hex_lines(@samples))
      write_lines('channel_log.txt', @log)
      write_lines('notes.txt', note_lines)
      write_lines('roll.txt', roll_lines)
      write_lines('stats.txt', stats_lines)
      write_lines('waveform.txt', waveform_lines)
      write_lines('instruments.txt', previews)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  song = Chiptune::SongParser.read_song('input/song.txt')
  params = Chiptune::SongParser.read_params('input/params.txt')
  Chiptune::Player.new(song, params).run
end
