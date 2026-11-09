module Chiptune
  module SongParser
    PITCHES = %w[C- C# D- D# E- F- F# G- G# A- A# B-].freeze
    ROWS = 64
    CHANNELS = 4

    Effect = Struct.new(:text, :name, :value) do
      def high = value / 16
      def low = value % 16
    end

    Cell = Struct.new(:note, :instrument, :volume, :effect) do
      def has_note? = !note.nil?
      def empty? = note.nil? && instrument.nil? && volume.nil? && effect.nil?
    end

    Instrument = Struct.new(:number, :name, :wave, :mode, :table, :envelope,
                            :vibrato, :arpeggio, :sweep, keyword_init: true)
    Song = Struct.new(:title, :rate, :speed, :tempo, :gain, :instruments,
                      :patterns, :order, keyword_init: true) do
      def cells(position, row) = patterns[order[position]][row]
    end
    Params = Struct.new(:max_samples, :loops, :fade, :muted, :window, :roll,
                        :preview_note, :preview_ticks, :preview_release, :traces,
                        keyword_init: true)

    module_function

    def note_number(name)
      12 * name[2].to_i + PITCHES.index(name[0, 2])
    end

    def note_name(number)
      PITCHES[number % 12] + (number / 12).to_s
    end

    def parse_effect(text)
      return if text == '...'

      extended = text.start_with?('E')
      Effect.new(text, extended ? text[0, 2] : text[0],
                 (extended ? text[2] : text[1, 2]).to_i(16))
    end

    def parse_cell(text)
      note, instrument, volume, effect = text.split
      note = case note
             when '...' then nil
             when 'OFF' then :off
             else note_number(note)
             end
      Cell.new(note, instrument == '..' ? nil : instrument.to_i(16),
               volume == '.' ? nil : volume.to_i(16), parse_effect(effect))
    end

    def parse_instrument(words, lines)
      instrument = Instrument.new(number: words[1].to_i(16), name: words[2],
                                  mode: 0, table: [], arpeggio: [], sweep: 0)
      lines.each do |line|
        key, *values = line.split
        case key
        when 'WAVE'
          instrument.wave = values[0]
          case instrument.wave
          when 'PULSE' then instrument.mode = %w[12 25 50 75].index(values[1])
          when 'NOISE' then instrument.mode = values[1] == 'SHORT' ? 1 : 0
          when 'TABLE' then instrument.table = values[1].chars.map { |digit| digit.to_i(16) }
          end
        when 'ENVELOPE' then instrument.envelope = values.map(&:to_i)
        when 'VIBRATO' then instrument.vibrato = values.map(&:to_i)
        when 'ARPEGGIO' then instrument.arpeggio = values.map(&:to_i)
        when 'SWEEP' then instrument.sweep = values[0].to_i
        end
      end
      instrument
    end

    def parse_pattern(lines)
      rows = Array.new(ROWS) { Array.new(CHANNELS) { parse_cell('... .. . ...') } }
      lines.each do |line|
        rows[line[0, 2].to_i(16)] = line[3..].split(' | ').map { |text| parse_cell(text) }
      end
      rows
    end

    def read_song(path)
      lines = File.readlines(path, chomp: true).reject { |line| line.empty? || line.start_with?('#') }
      song = Song.new(title: lines[0][6..], rate: lines[1].split[1].to_i,
                      speed: lines[2].split[1].to_i, tempo: lines[3].split[1].to_i,
                      gain: lines[4].split[1].to_i, instruments: {}, patterns: {}, order: [])
      index = 5
      while index < lines.length
        words = lines[index].split
        if words[0] == 'ORDER'
          song.order = words.drop(1).map { |word| word.to_i(16) }
          index += 1
          next
        end
        ending = index + 1
        ending += 1 until lines[ending] == 'END'
        block = lines[(index + 1)...ending]
        if words[0] == 'INSTRUMENT'
          instrument = parse_instrument(words, block)
          song.instruments[instrument.number] = instrument
        else
          song.patterns[words[1].to_i(16)] = parse_pattern(block)
        end
        index = ending + 1
      end
      song
    end

    def read_params(path)
      params = Params.new(traces: {})
      File.foreach(path) do |line|
        key, *values = line.split
        case key
        when 'max_samples' then params.max_samples = values[0].to_i
        when 'loops' then params.loops = values[0].to_i
        when 'fade' then params.fade = values[0].to_i
        when 'mute' then params.muted = values.map { |value| value == '1' }
        when 'window' then params.window = values.map(&:to_i)
        when 'roll' then params.roll = values.map(&:to_i)
        when 'preview'
          params.preview_note = note_number(values[0])
          params.preview_ticks = values[1].to_i
          params.preview_release = values[2].to_i
        when 'trace' then params.traces[values.map { |value| value.to_i(16) }] = true
        end
      end
      params
    end
  end
end
