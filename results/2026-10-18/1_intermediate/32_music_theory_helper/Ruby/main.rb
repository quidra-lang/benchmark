
LETTERS = 'CDEFGAB'
NATURALS = [0, 2, 4, 5, 7, 9, 11].freeze
FIFTHS = [0, 2, 4, -1, 1, 3, 5].freeze
ACCIDENTALS = ['bb', 'b', '', '#', 'x'].freeze
SHARPS = %w[C C# D D# E F F# G G# A A# B].freeze
FLATS = %w[C Db D Eb E F Gb G Ab A Bb B].freeze
ROMANS = %w[I II III IV V VI VII].freeze
PERFECT_DELTAS = { dd: -2, d: -1, P: 0, A: 1, AA: 2 }.freeze
MAJOR_DELTAS = { dd: -3, d: -2, m: -1, M: 0, A: 1, AA: 2 }.freeze
INVERSE_QUALITIES = { P: :P, M: :m, m: :M, A: :d, d: :A, AA: :dd, dd: :AA }.freeze

class CommandError < StandardError
  def initialize(message) = super("ERROR #{message}")
end

def canonical_integer(text, low, high)
  return unless /\A(?:0|[1-9][0-9]*)\z/.match?(text)
  value = text.to_i
  value if value.between?(low, high)
end

def parse_number(text)
  canonical_integer(text, 0, 127) || raise(CommandError, "BAD NUMBER #{text}")
end

def parse_frequency(text, tuning)
  parts = /\A([0-9]{1,5})(?:\.([0-9]{1,2}))?\z/.match(text)
  raise CommandError, "BAD FREQUENCY #{text}" unless parts
  value = parts[1].to_i * 100
  value += parts[2].to_i * (parts[2].length == 1 ? 10 : 1) if parts[2]
  if value.zero? || (tuning && !value.between?(40_000, 48_000))
    raise CommandError, "BAD FREQUENCY #{text}"
  end
  value
end

def frequency_text(cents) = format('%d.%02d', cents / 100, cents % 100)

Pitch = Data.define(:letter, :alteration) do
  def pitch_class = (NATURALS[letter] + alteration) % 12
  def to_s = LETTERS[letter] + ACCIDENTALS[alteration + 2]

  def self.prefix(text)
    match = /\A([A-G])(bb|b|#|x)?/.match(text)
    return unless match
    [new(LETTERS.index(match[1]), ACCIDENTALS.index(match[2] || '') - 2), match[0].length]
  end

  def self.parse(text)
    prefix = self.prefix(text)
    raise CommandError, "BAD PITCH #{text}" unless prefix && prefix[1] == text.length
    prefix[0]
  end

  def self.at_fifths(fifths)
    new(LETTERS.index('FCGDAEB'[(fifths + 1) % 7]), (fifths + 1).div(7))
  end

  def raise_by(interval)
    target = letter + interval.distance
    change = NATURALS[letter] + alteration + interval.semitones - NATURALS[target % 7] - 12 * target.div(7)
    raise CommandError, 'CANNOT SPELL' unless change.between?(-2, 2)
    Pitch.new(target % 7, change)
  end
end

Note = Data.define(:pitch, :octave) do
  def midi = 12 * (octave + 1) + NATURALS[pitch.letter] + pitch.alteration
  def position = 7 * octave + pitch.letter
  def valid? = octave.between?(-1, 9) && midi.between?(0, 127)
  def to_s = "#{pitch}#{octave}"

  def self.parse(text)
    prefix = Pitch.prefix(text)
    raise CommandError, "BAD NOTE #{text}" unless prefix
    rest = text[prefix[1]..]
    raise CommandError, "BAD NOTE #{text}" unless /\A(?:-1|[0-9])\z/.match?(rest)
    note = new(prefix[0], rest.to_i)
    raise CommandError, "BAD NOTE #{text}" unless note.valid?
    note
  end

  def self.from_pitch(pitch, midi)
    new(pitch, (midi - NATURALS[pitch.letter] - pitch.alteration).div(12) - 1)
  end

  def self.spelling(midi, flat = false)
    new(Pitch.parse((flat ? FLATS : SHARPS)[midi % 12]), midi.div(12) - 1)
  end
end

Interval = Data.define(:quality, :number) do
  def distance = number - 1
  def perfect_type? = [0, 3, 4].include?(distance % 7)
  def forbidden? = number == 1 && %i[d dd].include?(quality)
  def semitones = 12 * distance.div(7) + NATURALS[distance % 7] + (perfect_type? ? PERFECT_DELTAS : MAJOR_DELTAS).fetch(quality)
  def to_s = "#{quality}#{number}"

  def simple
    n = number
    n -= 7 while n > 8
    Interval.new(quality, n)
  end

  def consonance
    small = simple
    return 'perfect' if quality == :P && [1, 5, 8].include?(small.number)
    return 'imperfect' if %i[M m].include?(quality) && [3, 6].include?(small.number)
    'dissonant'
  end

  def self.parse(text)
    parts = /\A(P|M|m|A|d|AA|dd)([1-9][0-9]?)\z/.match(text)
    raise CommandError, "BAD INTERVAL #{text}" unless parts
    interval = new(parts[1].to_sym, parts[2].to_i)
    deltas = interval.perfect_type? ? PERFECT_DELTAS : MAJOR_DELTAS
    raise CommandError, "BAD INTERVAL #{text}" if !deltas.key?(interval.quality) || interval.forbidden?
    interval
  end

  def self.between(first, second)
    distance = second.position - first.position
    semitones = second.midi - first.midi
    down = distance.negative? || (distance.zero? && semitones.negative?)
    distance, semitones = -distance, -semitones if down
    difference = semitones - 12 * distance.div(7) - NATURALS[distance % 7]
    quality = ([0, 3, 4].include?(distance % 7) ? PERFECT_DELTAS : MAJOR_DELTAS).key(difference)
    raise CommandError, 'UNNAMEABLE INTERVAL' unless quality
    Motion.new(new(quality, distance + 1), down, semitones)
  end
end
Motion = Data.define(:interval, :down, :semitones)

def intervals(text) = text.split.map { |word| Interval.parse(word) }.freeze

SCALES = {
  'major' => 'P1 M2 M3 P4 P5 M6 M7',
  'natural_minor' => 'P1 M2 m3 P4 P5 m6 m7',
  'harmonic_minor' => 'P1 M2 m3 P4 P5 m6 M7',
  'melodic_minor' => 'P1 M2 m3 P4 P5 M6 M7',
  'ionian' => 'P1 M2 M3 P4 P5 M6 M7',
  'dorian' => 'P1 M2 m3 P4 P5 M6 m7',
  'phrygian' => 'P1 m2 m3 P4 P5 m6 m7',
  'lydian' => 'P1 M2 M3 A4 P5 M6 M7',
  'mixolydian' => 'P1 M2 M3 P4 P5 M6 m7',
  'aeolian' => 'P1 M2 m3 P4 P5 m6 m7',
  'locrian' => 'P1 m2 m3 P4 d5 m6 m7',
  'major_pentatonic' => 'P1 M2 M3 P5 M6',
  'minor_pentatonic' => 'P1 m3 P4 P5 m7',
  'blues' => 'P1 m3 P4 A4 P5 m7',
  'whole_tone' => 'P1 M2 M3 A4 A5 A6'
}.transform_values { |text| intervals(text) }.freeze

ChordType = Data.define(:name, :suffix, :numeral_suffix, :lower, :intervals) do
  def symbol(root, bass = nil) = "#{root}#{suffix}#{bass ? "/#{bass}" : ''}"
  def roman(degree) = (lower ? ROMANS[degree].downcase : ROMANS[degree]) + numeral_suffix
end
CHORDS = [
  ['maj', '', '', false, 'P1 M3 P5'],
  ['min', 'm', '', true, 'P1 m3 P5'],
  ['dim', 'dim', 'o', true, 'P1 m3 d5'],
  ['aug', 'aug', '+', false, 'P1 M3 A5'],
  ['sus2', 'sus2', 'sus2', false, 'P1 M2 P5'],
  ['sus4', 'sus4', 'sus4', false, 'P1 P4 P5'],
  ['6', '6', '6', false, 'P1 M3 P5 M6'],
  ['m6', 'm6', '6', true, 'P1 m3 P5 M6'],
  ['7', '7', '7', false, 'P1 M3 P5 m7'],
  ['maj7', 'maj7', 'maj7', false, 'P1 M3 P5 M7'],
  ['m7', 'm7', '7', true, 'P1 m3 P5 m7'],
  ['mMaj7', 'mMaj7', 'maj7', true, 'P1 m3 P5 M7'],
  ['m7b5', 'm7b5', 'h7', true, 'P1 m3 d5 m7'],
  ['dim7', 'dim7', 'o7', true, 'P1 m3 d5 d7'],
  ['9', '9', '9', false, 'P1 M3 P5 m7 M9'],
  ['add9', 'add9', 'add9', false, 'P1 M3 P5 M9']
].map { |name, suffix, numeral_suffix, lower, text| ChordType.new(name, suffix, numeral_suffix, lower, intervals(text)) }.freeze

Mode = Data.define(:name, :scale, :offset)
MODES = [
  Mode.new('major', 'major', 0), Mode.new('minor', 'natural_minor', -3),
  Mode.new('ionian', 'ionian', 0), Mode.new('dorian', 'dorian', -2),
  Mode.new('phrygian', 'phrygian', -4), Mode.new('lydian', 'lydian', 1),
  Mode.new('mixolydian', 'mixolydian', -1), Mode.new('aeolian', 'aeolian', -3),
  Mode.new('locrian', 'locrian', -5)
].freeze

def parse_quality(text) = CHORDS.find { |chord| chord.name == text } || raise(CommandError, "BAD QUALITY #{text}")
def parse_mode(text) = MODES.find { |mode| mode.name == text } || raise(CommandError, "BAD MODE #{text}")
def build_pitches(root, pattern) = pattern.map { |interval| root.raise_by(interval) }.freeze

Key = Data.define(:tonic, :mode, :fifths, :scale) do
  def self.make(tonic, mode)
    fifths = FIFTHS[tonic.letter] + 7 * tonic.alteration + mode.offset
    raise CommandError, 'THEORETICAL KEY' unless fifths.between?(-7, 7)
    new(tonic, mode, fifths, build_pitches(tonic, SCALES.fetch(mode.scale)))
  end

  def self.parse(words, start = 0)
    tonic = Pitch.parse(words[start])
    mode = parse_mode(words[start + 1])
    make(tonic, mode)
  end

  def degree(pitch) = (pitch.letter - tonic.letter) % 7
  def prefix(pitch)
    difference = pitch.alteration - scale[degree(pitch)].alteration
    (difference.negative? ? 'b' : '#') * difference.abs
  end
  def label(pitch) = "#{prefix(pitch)}#{degree(pitch) + 1}"
  def pitch_set = scale.reduce(0) { |mask, pitch| mask | (1 << pitch.pitch_class) }
  def to_s = "#{tonic} #{mode.name}"
end

Numeral = Data.define(:alteration, :degree, :quality)
ChordSymbol = Data.define(:root, :quality)
def parse_numeral(text)
  start = ['b', '#'].include?(text[0]) ? 1 : 0
  alteration = start.zero? ? 0 : (text[0] == 'b' ? -1 : 1)
  ending = start
  ending += 1 while ending < text.length && 'IViv'.include?(text[ending])
  part = text[start...ending]
  suffix = text[ending..]
  ROMANS.each_with_index do |roman, degree|
    CHORDS.each do |quality|
      expected = quality.lower ? roman.downcase : roman
      return Numeral.new(alteration, degree, quality) if part == expected && suffix == quality.numeral_suffix
    end
  end
  raise CommandError, "BAD NUMERAL #{text}"
end

def parse_symbol(text)
  prefix = Pitch.prefix(text)
  if prefix
    quality = CHORDS.find { |chord| chord.suffix == text[prefix[1]..] }
    return ChordSymbol.new(prefix[0], quality) if quality
  end
  raise CommandError, "BAD SYMBOL #{text}"
end

def chord_command(command, args)
  input = Note.parse(args[0]) if command == 'VOICE'
  root = input ? input.pitch : Pitch.parse(args[0])
  quality = parse_quality(args[1])
  inversion = args.length == 3 ? canonical_integer(args[2], 0, quality.intervals.length - 1) : 0
  raise CommandError, "BAD INVERSION #{args[2]}" unless inversion
  ordered = build_pitches(root, quality.intervals).rotate(inversion)
  name = quality.symbol(root, inversion.zero? ? nil : ordered.first)
  return "CHORD #{name} #{ordered.join(' ')}" unless input
  value = input.midi
  notes = ordered.each_with_index.map do |pitch, i|
    unless i.zero? && inversion.zero?
      difference = (pitch.pitch_class - value) % 12
      value += difference.zero? ? 12 : difference
    end
    note = Note.from_pitch(pitch, value)
    raise CommandError, 'OUT OF RANGE' unless note.valid?
    note
  end
  "VOICE #{name} #{notes.join(' ')} midi=#{notes.map(&:midi).join(',')}"
end

def identify(notes)
  candidates = notes.each_with_index.sort_by { |note, i| [note.midi, i] }.map(&:first).uniq { |note| note.pitch.pitch_class }
  bass = candidates.first.pitch
  mask = candidates.reduce(0) { |set, note| set | (1 << note.pitch.pitch_class) }
  candidates.each do |root|
    CHORDS.each do |quality|
      set = quality.intervals.reduce(0) { |bits, interval| bits | (1 << ((root.midi + interval.semitones) % 12)) }
      next unless set == mask
      inversion = quality.intervals.index { |interval| (root.midi + interval.semitones) % 12 == bass.pitch_class }
      name = quality.symbol(root.pitch, inversion.zero? ? nil : bass)
      return "IDENTIFY #{name} root=#{root.pitch} quality=#{quality.name} inversion=#{inversion}"
    end
  end
  'IDENTIFY UNKNOWN'
end

def melody(notes)
  low = high = notes.first
  notes.each do |note|
    low = note if note.midi < low.midi
    high = note if note.midi > high.midi
  end
  range = Interval.between(low, high).interval
  leaps = 0
  steps = notes.each_cons(2).map do |first, second|
    motion = Interval.between(first, second)
    leaps += 1 if (second.midi - first.midi).abs >= 3
    "#{motion.down ? '-' : '+'}#{motion.interval}"
  end
  "MELODY n=#{notes.length} low=#{low} high=#{high} range=#{range} leaps=#{leaps} steps=#{steps.join(',')}"
end

def cadence(numerals)
  return 'none' if numerals.length < 2
  x, y = numerals.last(2)
  if x.alteration.zero? && y.alteration.zero?
    return 'authentic' if x.degree == 4 && y.degree.zero?
    return 'plagal' if x.degree == 3 && y.degree.zero?
    return 'deceptive' if x.degree == 4 && y.degree == 5
  end
  y.alteration.zero? && y.degree == 4 ? 'half' : 'none'
end

def diatonic(key)
  rows = ["DIATONIC #{key}"]
  [3, 4].each do |size|
    items = key.scale.each_with_index.map do |root, i|
      third = (key.scale[(i + 2) % 7].pitch_class - root.pitch_class) % 12
      fifth = (key.scale[(i + 4) % 7].pitch_class - root.pitch_class) % 12
      index = if size == 3
                third == 4 ? 0 : (fifth == 7 ? 1 : 2)
              else
                seventh = (key.scale[(i + 6) % 7].pitch_class - root.pitch_class) % 12
                third == 4 ? (seventh == 11 ? 9 : 8) : (fifth == 7 ? 10 : 12)
              end
      quality = CHORDS[index]
      "#{quality.roman(i)}=#{quality.symbol(root)}"
    end
    rows << (size == 3 ? 'TRIADS ' : 'SEVENTHS ') + items.join(' ')
  end
  rows.join("\n")
end

def key_command(command, args)
  key = Key.parse(args)
  case command
  when 'KEYSIG'
    p = key.fifths
    return "KEYSIG #{key} none" if p.zero?
    names = p.positive? ? %w[F# C# G# D# A# E# B#] : %w[Bb Eb Ab Db Gb Cb Fb]
    "KEYSIG #{key} #{p.positive? ? 'sharps' : 'flats'}=#{p.abs} #{names.take(p.abs).join(' ')}"
  when 'RELATIVE'
    "RELATIVE #{key} major=#{Pitch.at_fifths(key.fifths)} minor=#{Pitch.at_fifths(key.fifths + 3)}"
  when 'DEGREE'
    pitch = Pitch.parse(args[2])
    "DEGREE #{key} #{args[2]} #{key.label(pitch)}"
  when 'KEYDIST'
    other = Key.parse(args, 2)
    distance = (other.fifths - key.fifths) % 12
    distance -= 12 if distance > 6
    same_tonic = key.tonic.pitch_class == other.tonic.pitch_class
    relation = if key.pitch_set == other.pitch_set
                 same_tonic ? 'same' : 'relative'
               elsif same_tonic
                 'parallel'
               else
                 distance.abs == 1 ? 'close' : 'distant'
               end
    common = (key.pitch_set & other.pitch_set).digits(2).sum
    "KEYDIST #{key} #{other} fifths=#{distance.positive? ? '+' : ''}#{distance} common=#{common} relation=#{relation}"
  when 'DIATONIC'
    diatonic(key)
  when 'ANALYZE'
    symbols = args.drop(2).map { |word| parse_symbol(word) }
    items = symbols.map { |chord| key.prefix(chord.root) + chord.quality.roman(key.degree(chord.root)) }
    "ANALYZE #{key} #{items.join(' ')}"
  when 'PROGRESSION'
    numerals = args.drop(2).map { |word| parse_numeral(word) }
    rows = ["PROGRESSION #{key} #{numerals.length}"]
    numerals.each_with_index do |numeral, i|
      degree = key.scale[numeral.degree]
      root = Pitch.new(degree.letter, degree.alteration + numeral.alteration)
      pitches = build_pitches(root, numeral.quality.intervals)
      rows << "#{args[i + 2]} #{numeral.quality.symbol(root)} #{pitches.join(' ')}"
    end
    rows << "CADENCE #{cadence(numerals)}"
    rows.join("\n")
  end
end

ARITIES = {
  'MIDI' => 1..1, 'NOTE' => 1..1, 'FREQ' => 1..1, 'TUNING' => 1..1, 'PITCH' => 1..1,
  'INTERVAL' => 2..2, 'INVERT' => 1..1, 'TRANSPOSE' => 3..3, 'SCALE' => 2..2,
  'CHORD' => 2..3, 'VOICE' => 2..3, 'IDENTIFY' => 2..15, 'MELODY' => 2..15,
  'ENHARMONIC' => 1..1, 'KEYSIG' => 2..2, 'RELATIVE' => 2..2, 'CIRCLE' => 1..1,
  'DIATONIC' => 2..2, 'PROGRESSION' => 3..15, 'ANALYZE' => 3..15, 'FINDKEY' => 1..15,
  'DEGREE' => 3..3, 'SPELL' => 3..3, 'KEYDIST' => 4..4
}.freeze

class Calculator
  def initialize
    @tuning = 44_000
  end

  def execute(line)
    command, *args = line.split(' ')
    arity = ARITIES[command] || raise(CommandError, "UNKNOWN COMMAND #{command}")
    raise CommandError, 'ARGUMENT COUNT' unless arity.cover?(args.length)
    case command
    when 'MIDI', 'FREQ', 'ENHARMONIC'
      note = Note.parse(args[0])
      value = note.midi
      return "MIDI #{args[0]} #{value}" if command == 'MIDI'
      if command == 'FREQ'
        cents = (@tuning * 2.0**((value - 69) / 12.0) + 0.5).floor
        return "FREQ #{args[0]} #{frequency_text(cents)}"
      end
      equivalents = []
      (-1..9).each do |octave|
        (0..6).each do |letter|
          alteration = value - 12 * (octave + 1) - NATURALS[letter]
          equivalents << Note.new(Pitch.new(letter, alteration), octave) if alteration.between?(-2, 2)
        end
      end
      "ENHARMONIC #{args[0]} #{equivalents.join(' ')}"
    when 'NOTE'
      value = parse_number(args[0])
      "NOTE #{value} #{Note.spelling(value)} #{Note.spelling(value, true)}"
    when 'TUNING', 'PITCH'
      value = parse_frequency(args[0], command == 'TUNING')
      if command == 'TUNING'
        @tuning = value
        return "TUNING #{frequency_text(value)}"
      end
      x = 69 + 12 * Math.log2(value.fdiv(@tuning))
      nearest = (x + 0.5).floor
      raise CommandError, 'OUT OF RANGE' unless nearest.between?(0, 127)
      cents = (100 * (x - nearest) + 0.5).floor
      "PITCH #{frequency_text(value)} #{Note.spelling(nearest)} #{cents >= 0 ? '+' : ''}#{cents}"
    when 'INTERVAL'
      first = Note.parse(args[0])
      second = Note.parse(args[1])
      motion = Interval.between(first, second)
      "INTERVAL #{args[0]} #{args[1]} #{motion.interval} #{motion.down ? 'down' : 'up'} semitones=#{motion.semitones} simple=#{motion.interval.simple} class=#{motion.interval.consonance}"
    when 'INVERT'
      simple = Interval.parse(args[0]).simple
      inverse = Interval.new(INVERSE_QUALITIES.fetch(simple.quality), 9 - simple.number)
      raise CommandError, 'CANNOT INVERT' if inverse.forbidden?
      "INVERT #{args[0]} #{simple} #{inverse}"
    when 'TRANSPOSE'
      note = Note.parse(args[0])
      interval = Interval.parse(args[1])
      direction = args[2]
      raise CommandError, "BAD DIRECTION #{direction}" unless %w[UP DOWN].include?(direction)
      sign = direction == 'UP' ? 1 : -1
      position = note.position + sign * interval.distance
      value = note.midi + sign * interval.semitones
      letter, octave = position % 7, position.div(7)
      alteration = value - 12 * (octave + 1) - NATURALS[letter]
      raise CommandError, 'CANNOT SPELL' unless alteration.between?(-2, 2)
      result = Note.new(Pitch.new(letter, alteration), octave)
      raise CommandError, 'OUT OF RANGE' unless result.valid?
      "TRANSPOSE #{args[0]} #{args[1]} #{direction} #{result}"
    when 'SCALE'
      root = Pitch.parse(args[0])
      pattern = SCALES[args[1]] || raise(CommandError, "BAD SCALE #{args[1]}")
      pitches = build_pitches(root, pattern)
      steps = pattern.each_with_index.map { |interval, i| (pattern[i + 1]&.semitones || 12) - interval.semitones }
      "SCALE #{args[0]} #{args[1]} #{pitches.join(' ')} steps=#{steps.join(',')}"
    when 'CHORD', 'VOICE'
      chord_command(command, args)
    when 'IDENTIFY'
      identify(args.map { |word| Note.parse(word) })
    when 'MELODY'
      melody(args.map { |word| Note.parse(word) })
    when 'CIRCLE'
      mode = parse_mode(args[0])
      pitches = (-7..7).map { |p| Pitch.at_fifths(p - mode.offset) }
      "CIRCLE #{args[0]} #{pitches.join(' ')}"
    when 'FINDKEY'
      pitches = args.map { |word| Pitch.parse(word) }
      keys = []
      (-7..7).each do |p|
        MODES.first(2).each do |mode|
          key = Key.make(Pitch.at_fifths(p - mode.offset), mode)
          keys << key if pitches.all? { |pitch| key.scale.include?(pitch) }
        end
      end
      "FINDKEY #{keys.length}#{keys.empty? ? '' : ' ' + keys.join(', ')}"
    when 'SPELL'
      value = parse_number(args[0])
      key = Key.parse(args, 1)
      pitch = key.scale.find { |candidate| candidate.pitch_class == value % 12 } || Note.spelling(value, key.fifths.negative?).pitch
      note = Note.from_pitch(pitch, value)
      raise CommandError, 'OUT OF RANGE' unless note.valid?
      "SPELL #{value} #{key} #{note} #{key.label(pitch)}"
    else
      key_command(command, args)
    end
  end
end

calculator = Calculator.new
STDIN.gets.to_i.times do
  begin
    puts calculator.execute(STDIN.gets.chomp)
  rescue CommandError => error
    puts error.message
  end
end
