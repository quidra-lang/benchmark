import 'dart:io';
import 'dart:math' as math;

final class CommandError implements Exception {
  final String message;
  const CommandError(this.message);
  @override
  String toString() => 'ERROR $message';
}

const letters = 'CDEFGAB';
const naturals = [0, 2, 4, 5, 7, 9, 11];
const accidentals = ['bb', 'b', '', '#', 'x'];
int floorDiv(int value, int divisor) => (value - value % divisor) ~/ divisor;

final class Pitch {
  final int letter;
  final int alteration;
  const Pitch(this.letter, this.alteration);
  int get natural => naturals[letter];
  int get pitchClass => (natural + alteration) % 12;
  @override
  bool operator ==(Object other) => other is Pitch && letter == other.letter && alteration == other.alteration;
  @override
  int get hashCode => Object.hash(letter, alteration);
  @override
  String toString() => '${letters[letter]}${accidentals[alteration + 2]}';
}

final class Note {
  final Pitch pitch;
  final int octave;
  const Note(this.pitch, this.octave);
  int get midi => 12 * (octave + 1) + pitch.natural + pitch.alteration;
  int get position => 7 * octave + pitch.letter;
  bool get valid => octave >= -1 && octave <= 9 && midi >= 0 && midi <= 127;
  @override
  String toString() => '$pitch$octave';
}

final class Interval {
  final String quality;
  final int number;
  const Interval(this.quality, this.number);
  int get letterDistance => number - 1;
  bool get perfectType => const {0, 3, 4}.contains(letterDistance % 7);
  int get semitones {
    final difference = switch (quality) {
      'dd' => perfectType ? -2 : -3,
      'd' => perfectType ? -1 : -2,
      'm' => -1,
      'A' => 1,
      'AA' => 2,
      _ => 0,
    };
    return 12 * (letterDistance ~/ 7) + naturals[letterDistance % 7] + difference;
  }
  Interval get simple {
    var n = number;
    while (n > 8) {
      n -= 7;
    }
    return Interval(quality, n);
  }
  String get consonance => switch (simple.toString()) {
    'P1' || 'P5' || 'P8' => 'perfect',
    'm3' || 'M3' || 'm6' || 'M6' => 'imperfect',
    _ => 'dissonant',
  };
  @override
  String toString() => '$quality$number';
}

final class Quality {
  final String name;
  final List<Interval> intervals;
  final String suffix;
  final String numeral;
  const Quality(this.name, this.intervals, this.suffix, this.numeral);
  bool get lower => numeral.startsWith('i');
  String get numeralSuffix => numeral.substring(1);
}
final class Mode {
  final String name;
  final String scale;
  final int offset;
  const Mode(this.name, this.scale, this.offset);
}
final class Key {
  final Pitch tonic;
  final Mode mode;
  const Key(this.tonic, this.mode);
  int get fifths => const [0, 2, 4, -1, 1, 3, 5][tonic.letter] + 7 * tonic.alteration + mode.offset;
  @override
  String toString() => '$tonic ${mode.name}';
}
final class Numeral {
  final int degree;
  final int alteration;
  final Quality quality;
  const Numeral(this.degree, this.alteration, this.quality);
}
final class Chord {
  final Pitch root;
  final Quality quality;
  const Chord(this.root, this.quality);
  @override
  String toString() => '$root${quality.suffix}';
}
final class Motion {
  final Interval interval;
  final bool down;
  final int semitones;
  const Motion(this.interval, this.down, this.semitones);
}
final class Degree {
  final int index;
  final String prefix;
  const Degree(this.index, this.prefix);
  @override
  String toString() => '$prefix${index + 1}';
}

List<Interval> intervals(String text) => text.split(' ').map(parseInterval).toList();
final scales = <String, List<Interval>>{
  'major': intervals('P1 M2 M3 P4 P5 M6 M7'),
  'natural_minor': intervals('P1 M2 m3 P4 P5 m6 m7'),
  'harmonic_minor': intervals('P1 M2 m3 P4 P5 m6 M7'),
  'melodic_minor': intervals('P1 M2 m3 P4 P5 M6 M7'),
  'ionian': intervals('P1 M2 M3 P4 P5 M6 M7'),
  'dorian': intervals('P1 M2 m3 P4 P5 M6 m7'),
  'phrygian': intervals('P1 m2 m3 P4 P5 m6 m7'),
  'lydian': intervals('P1 M2 M3 A4 P5 M6 M7'),
  'mixolydian': intervals('P1 M2 M3 P4 P5 M6 m7'),
  'aeolian': intervals('P1 M2 m3 P4 P5 m6 m7'),
  'locrian': intervals('P1 m2 m3 P4 d5 m6 m7'),
  'major_pentatonic': intervals('P1 M2 M3 P5 M6'),
  'minor_pentatonic': intervals('P1 m3 P4 P5 m7'),
  'blues': intervals('P1 m3 P4 A4 P5 m7'),
  'whole_tone': intervals('P1 M2 M3 A4 A5 A6'),
};
final qualities = <Quality>[
  Quality('maj', intervals('P1 M3 P5'), '', 'I'),
  Quality('min', intervals('P1 m3 P5'), 'm', 'i'),
  Quality('dim', intervals('P1 m3 d5'), 'dim', 'io'),
  Quality('aug', intervals('P1 M3 A5'), 'aug', 'I+'),
  Quality('sus2', intervals('P1 M2 P5'), 'sus2', 'Isus2'),
  Quality('sus4', intervals('P1 P4 P5'), 'sus4', 'Isus4'),
  Quality('6', intervals('P1 M3 P5 M6'), '6', 'I6'),
  Quality('m6', intervals('P1 m3 P5 M6'), 'm6', 'i6'),
  Quality('7', intervals('P1 M3 P5 m7'), '7', 'I7'),
  Quality('maj7', intervals('P1 M3 P5 M7'), 'maj7', 'Imaj7'),
  Quality('m7', intervals('P1 m3 P5 m7'), 'm7', 'i7'),
  Quality('mMaj7', intervals('P1 m3 P5 M7'), 'mMaj7', 'imaj7'),
  Quality('m7b5', intervals('P1 m3 d5 m7'), 'm7b5', 'ih7'),
  Quality('dim7', intervals('P1 m3 d5 d7'), 'dim7', 'io7'),
  Quality('9', intervals('P1 M3 P5 m7 M9'), '9', 'I9'),
  Quality('add9', intervals('P1 M3 P5 M9'), 'add9', 'Iadd9'),
];
const modes = [
  Mode('major', 'major', 0), Mode('minor', 'natural_minor', -3), Mode('ionian', 'ionian', 0),
  Mode('dorian', 'dorian', -2), Mode('phrygian', 'phrygian', -4), Mode('lydian', 'lydian', 1),
  Mode('mixolydian', 'mixolydian', -1), Mode('aeolian', 'aeolian', -3), Mode('locrian', 'locrian', -5),
];
const sharpNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const flatNames = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
const romans = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'];
const lowerRomans = ['i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii'];

int alteration(String? text) => switch (text) {'bb' => -2, 'b' => -1, '#' => 1, 'x' => 2, _ => 0};
Pitch parsePitch(String text) {
  final match = RegExp(r'^([A-G])(bb|b|#|x)?$').firstMatch(text);
  if (match == null) throw CommandError('BAD PITCH $text');
  return Pitch(letters.indexOf(match[1]!), alteration(match[2]));
}
Note parseNote(String text) {
  final match = RegExp(r'^([A-G])(bb|b|#|x)?(-1|[0-9])$').firstMatch(text);
  if (match == null) throw CommandError('BAD NOTE $text');
  final note = Note(Pitch(letters.indexOf(match[1]!), alteration(match[2])), int.parse(match[3]!));
  if (!note.valid) throw CommandError('BAD NOTE $text');
  return note;
}
int parseNumber(String text) {
  final value = int.tryParse(text);
  if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(text) || value == null || value > 127) {
    throw CommandError('BAD NUMBER $text');
  }
  return value;
}
int parseFrequency(String text, bool tuning) {
  final match = RegExp(r'^([0-9]{1,5})(?:\.([0-9]{1,2}))?$').firstMatch(text);
  if (match == null) throw CommandError('BAD FREQUENCY $text');
  var cents = int.parse(match[1]!) * 100;
  final tail = match[2];
  if (tail != null) cents += int.parse(tail.padRight(2, '0'));
  if (tuning ? cents < 40000 || cents > 48000 : cents == 0) throw CommandError('BAD FREQUENCY $text');
  return cents;
}
Interval parseInterval(String text) {
  final match = RegExp(r'^(AA|dd|P|M|m|A|d)([1-9][0-9]?)$').firstMatch(text);
  if (match == null) throw CommandError('BAD INTERVAL $text');
  final interval = Interval(match[1]!, int.parse(match[2]!));
  if ((interval.perfectType ? const {'M', 'm'}.contains(interval.quality) : interval.quality == 'P') ||
      interval.number == 1 && const {'d', 'dd'}.contains(interval.quality)) {
    throw CommandError('BAD INTERVAL $text');
  }
  return interval;
}
Quality parseQuality(String text) {
  for (final quality in qualities) {
    if (quality.name == text) return quality;
  }
  throw CommandError('BAD QUALITY $text');
}
Mode parseMode(String text) {
  for (final mode in modes) {
    if (mode.name == text) return mode;
  }
  throw CommandError('BAD MODE $text');
}
Key parseKey(String tonic, String mode) {
  final pitch = parsePitch(tonic);
  final parsedMode = parseMode(mode);
  final key = Key(pitch, parsedMode);
  if (key.fifths < -7 || key.fifths > 7) throw const CommandError('THEORETICAL KEY');
  return key;
}
List<Interval> parseScale(String text) => scales[text] ?? (throw CommandError('BAD SCALE $text'));
int parseInversion(String text, Quality quality) {
  if (!RegExp(r'^[0-9]$').hasMatch(text) || int.parse(text) >= quality.intervals.length) {
    throw CommandError('BAD INVERSION $text');
  }
  return int.parse(text);
}
Numeral parseNumeral(String text) {
  final start = text.startsWith('b') || text.startsWith('#') ? 1 : 0;
  final change = start == 0 ? 0 : text[0] == 'b' ? -1 : 1;
  var end = start;
  while (end < text.length && 'IViv'.contains(text[end])) {
    end++;
  }
  final roman = text.substring(start, end);
  final suffix = text.substring(end);
  var degree = romans.indexOf(roman);
  var lower = false;
  if (degree < 0) {
    degree = lowerRomans.indexOf(roman);
    lower = true;
  }
  if (degree >= 0) {
    for (final quality in qualities) {
      if (quality.lower == lower && quality.numeralSuffix == suffix) return Numeral(degree, change, quality);
    }
  }
  throw CommandError('BAD NUMERAL $text');
}
Chord parseSymbol(String text) {
  final match = RegExp(r'^([A-G])(bb|b|#|x)?(.*)$').firstMatch(text);
  if (match != null) {
    for (final quality in qualities) {
      if (quality.suffix == match[3]) return Chord(Pitch(letters.indexOf(match[1]!), alteration(match[2])), quality);
    }
  }
  throw CommandError('BAD SYMBOL $text');
}

Pitch raisePitch(Pitch root, Interval interval) {
  final letter = (root.letter + interval.letterDistance) % 7;
  final change = root.natural + root.alteration + interval.semitones - naturals[letter] -
      12 * floorDiv(root.letter + interval.letterDistance, 7);
  if (change < -2 || change > 2) throw const CommandError('CANNOT SPELL');
  return Pitch(letter, change);
}
List<Pitch> build(Pitch root, List<Interval> pattern) => pattern.map((interval) => raisePitch(root, interval)).toList();
List<Pitch> keyScale(Key key) => build(key.tonic, scales[key.mode.scale]!);
Note fromMidi(Pitch pitch, int midi) => Note(pitch, (midi - pitch.natural - pitch.alteration) ~/ 12 - 1);
Note standardNote(int midi, [bool flat = false]) => Note(parsePitch((flat ? flatNames : sharpNames)[midi % 12]), midi ~/ 12 - 1);
Pitch fifthsPitch(int fifths) => Pitch(letters.indexOf('FCGDAEB'[(fifths + 1) % 7]), floorDiv(fifths + 1, 7));
Key keyAt(int fifths, Mode mode) => Key(fifthsPitch(fifths - mode.offset), mode);
Degree label(Key key, Pitch pitch) {
  final index = (pitch.letter - key.tonic.letter) % 7;
  final change = pitch.alteration - keyScale(key)[index].alteration;
  return Degree(index, (change < 0 ? 'b' : '#') * change.abs());
}
String romanNotation(int degree, Quality quality) => (quality.lower ? lowerRomans : romans)[degree] + quality.numeralSuffix;
Motion between(Note first, Note second) {
  var distance = second.position - first.position;
  var semitones = second.midi - first.midi;
  final down = distance < 0 || distance == 0 && semitones < 0;
  if (down) {
    distance = -distance;
    semitones = -semitones;
  }
  final difference = semitones - (12 * (distance ~/ 7) + naturals[distance % 7]);
  final perfect = const {0, 3, 4}.contains(distance % 7);
  final quality = perfect
      ? const {-2: 'dd', -1: 'd', 0: 'P', 1: 'A', 2: 'AA'}[difference]
      : const {-3: 'dd', -2: 'd', -1: 'm', 0: 'M', 1: 'A', 2: 'AA'}[difference];
  if (quality == null) throw const CommandError('UNNAMEABLE INTERVAL');
  return Motion(Interval(quality, distance + 1), down, semitones);
}
int pitchMask(Iterable<Pitch> pitches) {
  var mask = 0;
  for (final pitch in pitches) {
    mask |= 1 << pitch.pitchClass;
  }
  return mask;
}
int chordMask(Note root, Quality quality) {
  var mask = 0;
  for (final interval in quality.intervals) {
    mask |= 1 << ((root.midi + interval.semitones) % 12);
  }
  return mask;
}
String cadence(List<Numeral> numerals) {
  if (numerals.length < 2) return 'none';
  final a = numerals[numerals.length - 2], b = numerals.last;
  if (a.alteration == 0 && b.alteration == 0) {
    if (a.degree == 4 && b.degree == 0) return 'authentic';
    if (a.degree == 3 && b.degree == 0) return 'plagal';
    if (a.degree == 4 && b.degree == 5) return 'deceptive';
  }
  return b.alteration == 0 && b.degree == 4 ? 'half' : 'none';
}
String frequency(int cents) => '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
String signed(int value, [bool positiveZero = false]) => value > 0 || value == 0 && positiveZero ? '+$value' : '$value';

const arities = <String, (int, int)>{
  'MIDI': (1, 1), 'NOTE': (1, 1), 'FREQ': (1, 1), 'TUNING': (1, 1), 'PITCH': (1, 1),
  'INTERVAL': (2, 2), 'INVERT': (1, 1), 'TRANSPOSE': (3, 3), 'SCALE': (2, 2),
  'CHORD': (2, 3), 'VOICE': (2, 3), 'IDENTIFY': (2, 15), 'MELODY': (2, 15),
  'ENHARMONIC': (1, 1), 'KEYSIG': (2, 2), 'RELATIVE': (2, 2), 'CIRCLE': (1, 1),
  'DIATONIC': (2, 2), 'PROGRESSION': (3, 15), 'ANALYZE': (3, 15), 'FINDKEY': (1, 15),
  'DEGREE': (3, 3), 'SPELL': (3, 3), 'KEYDIST': (4, 4),
};

final class Calculator {
  int tuning = 44000;
  String execute(String line) {
    final w = line.split(' ');
    final command = w[0];
    final arity = arities[command];
    if (arity == null) throw CommandError('UNKNOWN COMMAND $command');
    if (w.length - 1 < arity.$1 || w.length - 1 > arity.$2) throw const CommandError('ARGUMENT COUNT');
    switch (command) {
      case 'MIDI':
        return 'MIDI ${w[1]} ${parseNote(w[1]).midi}';
      case 'NOTE':
        final number = parseNumber(w[1]);
        return 'NOTE $number ${standardNote(number)} ${standardNote(number, true)}';
      case 'FREQ':
        final note = parseNote(w[1]);
        final value = (tuning / 100) * math.pow(2, (note.midi - 69) / 12);
        return 'FREQ ${w[1]} ${frequency((value * 100 + 0.5).floor())}';
      case 'TUNING':
        final value = parseFrequency(w[1], true);
        tuning = value;
        return 'TUNING ${frequency(value)}';
      case 'PITCH':
        final value = parseFrequency(w[1], false);
        final x = 69 + 12 * math.log(value / tuning) / math.ln2;
        final number = (x + 0.5).floor();
        if (number < 0 || number > 127) throw const CommandError('OUT OF RANGE');
        final cents = (100 * (x - number) + 0.5).floor();
        return 'PITCH ${frequency(value)} ${standardNote(number)} ${signed(cents, true)}';
      case 'INTERVAL':
        final a = parseNote(w[1]);
        final b = parseNote(w[2]);
        final motion = between(a, b);
        return 'INTERVAL ${w[1]} ${w[2]} ${motion.interval} ${motion.down ? 'down' : 'up'} '
            'semitones=${motion.semitones} simple=${motion.interval.simple} class=${motion.interval.consonance}';
      case 'INVERT':
        final interval = parseInterval(w[1]);
        final simple = interval.simple;
        final quality = const {'P': 'P', 'M': 'm', 'm': 'M', 'A': 'd', 'd': 'A', 'AA': 'dd', 'dd': 'AA'}[simple.quality]!;
        final inverted = Interval(quality, 9 - simple.number);
        if (inverted.number == 1 && const {'d', 'dd'}.contains(quality)) throw const CommandError('CANNOT INVERT');
        return 'INVERT ${w[1]} $simple $inverted';
      case 'TRANSPOSE':
        final note = parseNote(w[1]);
        final interval = parseInterval(w[2]);
        if (w[3] != 'UP' && w[3] != 'DOWN') throw CommandError('BAD DIRECTION ${w[3]}');
        final sign = w[3] == 'UP' ? 1 : -1;
        final position = note.position + sign * interval.letterDistance;
        final midi = note.midi + sign * interval.semitones;
        final letter = position % 7, octave = floorDiv(position, 7);
        final change = midi - (12 * (octave + 1) + naturals[letter]);
        if (change < -2 || change > 2) throw const CommandError('CANNOT SPELL');
        final result = Note(Pitch(letter, change), octave);
        if (!result.valid) throw const CommandError('OUT OF RANGE');
        return 'TRANSPOSE ${w[1]} ${w[2]} ${w[3]} $result';
      case 'SCALE':
        final root = parsePitch(w[1]);
        final pattern = parseScale(w[2]);
        final notes = build(root, pattern);
        final steps = List.generate(pattern.length, (i) => (i + 1 == pattern.length ? 12 : pattern[i + 1].semitones) - pattern[i].semitones);
        return 'SCALE ${w[1]} ${w[2]} ${notes.join(' ')} steps=${steps.join(',')}';
      case 'CHORD':
      case 'VOICE':
        final input = command == 'VOICE' ? parseNote(w[1]) : null;
        final root = input?.pitch ?? parsePitch(w[1]);
        final quality = parseQuality(w[2]);
        final inversion = w.length == 4 ? parseInversion(w[3], quality) : 0;
        final tones = build(root, quality.intervals);
        final reordered = [...tones.skip(inversion), ...tones.take(inversion)];
        final symbol = '${Chord(root, quality)}${inversion == 0 ? '' : '/${reordered.first}'}';
        if (command == 'CHORD') return 'CHORD $symbol ${reordered.join(' ')}';
        final notes = <Note>[];
        var previous = input!.midi;
        for (var i = 0; i < reordered.length; i++) {
          var midi = previous;
          if (i != 0 || inversion != 0) {
            midi += (reordered[i].pitchClass - previous) % 12;
            if (midi == previous) midi += 12;
          }
          final made = fromMidi(reordered[i], midi);
          if (!made.valid) throw const CommandError('OUT OF RANGE');
          notes.add(made);
          previous = midi;
        }
        return 'VOICE $symbol ${notes.join(' ')} midi=${notes.map((n) => n.midi).join(',')}';
      case 'IDENTIFY':
        final notes = w.skip(1).map(parseNote).toList();
        final ordered = List.generate(notes.length, (i) => (i, notes[i]));
        ordered.sort((a, b) {
          final comparison = a.$2.midi.compareTo(b.$2.midi);
          return comparison != 0 ? comparison : a.$1.compareTo(b.$1);
        });
        final seen = <int>{};
        final candidates = ordered.map((entry) => entry.$2).where((note) => seen.add(note.pitch.pitchClass)).toList();
        final mask = pitchMask(notes.map((note) => note.pitch));
        final bass = candidates.first;
        for (final root in candidates) {
          for (final quality in qualities) {
            if (chordMask(root, quality) != mask) continue;
            final inversion = quality.intervals.indexWhere((interval) => (root.midi + interval.semitones) % 12 == bass.pitch.pitchClass);
            final symbol = '${Chord(root.pitch, quality)}${inversion == 0 ? '' : '/${bass.pitch}'}';
            return 'IDENTIFY $symbol root=${root.pitch} quality=${quality.name} inversion=$inversion';
          }
        }
        return 'IDENTIFY UNKNOWN';
      case 'MELODY':
        final notes = w.skip(1).map(parseNote).toList();
        var low = notes.first, high = notes.first;
        for (final note in notes) {
          if (note.midi < low.midi) low = note;
          if (note.midi > high.midi) high = note;
        }
        final range = between(low, high).interval;
        final steps = <String>[];
        var leaps = 0;
        for (var i = 1; i < notes.length; i++) {
          final motion = between(notes[i - 1], notes[i]);
          steps.add('${motion.down ? '-' : '+'}${motion.interval}');
          if ((notes[i].midi - notes[i - 1].midi).abs() >= 3) leaps++;
        }
        return 'MELODY n=${notes.length} low=$low high=$high range=$range leaps=$leaps steps=${steps.join(',')}';
      case 'ENHARMONIC':
        final input = parseNote(w[1]);
        final notes = <Note>[];
        for (var letter = 0; letter < 7; letter++) {
          for (var change = -2; change <= 2; change++) {
            final pitch = Pitch(letter, change);
            if (pitch.pitchClass != input.pitch.pitchClass) continue;
            final note = fromMidi(pitch, input.midi);
            if (note.valid) notes.add(note);
          }
        }
        notes.sort((a, b) => a.position.compareTo(b.position));
        return 'ENHARMONIC ${w[1]} ${notes.join(' ')}';
      case 'KEYSIG':
      case 'RELATIVE':
      case 'DIATONIC':
      case 'PROGRESSION':
      case 'ANALYZE':
      case 'DEGREE':
        final key = parseKey(w[1], w[2]);
        if (command == 'KEYSIG') {
          final fifths = key.fifths;
          if (fifths == 0) return 'KEYSIG $key none';
          final names = (fifths > 0 ? 'F# C# G# D# A# E# B#' : 'Bb Eb Ab Db Gb Cb Fb').split(' ');
          return 'KEYSIG $key ${fifths > 0 ? 'sharps' : 'flats'}=${fifths.abs()} ${names.take(fifths.abs()).join(' ')}';
        }
        if (command == 'RELATIVE') return 'RELATIVE $key major=${keyAt(key.fifths, modes[0]).tonic} minor=${keyAt(key.fifths, modes[1]).tonic}';
        if (command == 'DEGREE') {
          final pitch = parsePitch(w[3]);
          return 'DEGREE $key ${w[3]} ${label(key, pitch)}';
        }
        if (command == 'ANALYZE') {
          final chords = w.skip(3).map(parseSymbol).toList();
          final results = chords.map((chord) {
            final degree = label(key, chord.root);
            return degree.prefix + romanNotation(degree.index, chord.quality);
          });
          return 'ANALYZE $key ${results.join(' ')}';
        }
        if (command == 'PROGRESSION') {
          final numerals = w.skip(3).map(parseNumeral).toList();
          final scale = keyScale(key);
          final lines = ['PROGRESSION $key ${numerals.length}'];
          for (var i = 0; i < numerals.length; i++) {
            final numeral = numerals[i];
            final degree = scale[numeral.degree];
            final root = Pitch(degree.letter, degree.alteration + numeral.alteration);
            final tones = build(root, numeral.quality.intervals);
            lines.add('${w[i + 3]} ${Chord(root, numeral.quality)} ${tones.join(' ')}');
          }
          lines.add('CADENCE ${cadence(numerals)}');
          return lines.join('\n');
        }
        final scale = keyScale(key);
        final triads = <String>[], sevenths = <String>[];
        for (var i = 0; i < 7; i++) {
          final third = (scale[(i + 2) % 7].pitchClass - scale[i].pitchClass) % 12;
          final fifth = (scale[(i + 4) % 7].pitchClass - scale[i].pitchClass) % 12;
          final seventh = (scale[(i + 6) % 7].pitchClass - scale[i].pitchClass) % 12;
          final triad = parseQuality(third == 4 ? 'maj' : fifth == 7 ? 'min' : 'dim');
          final tetrad = parseQuality(third == 4 ? seventh == 11 ? 'maj7' : '7' : fifth == 7 ? 'm7' : 'm7b5');
          triads.add('${romanNotation(i, triad)}=${Chord(scale[i], triad)}');
          sevenths.add('${romanNotation(i, tetrad)}=${Chord(scale[i], tetrad)}');
        }
        return 'DIATONIC $key\nTRIADS ${triads.join(' ')}\nSEVENTHS ${sevenths.join(' ')}';
      case 'CIRCLE':
        final mode = parseMode(w[1]);
        return 'CIRCLE ${w[1]} ${List.generate(15, (i) => keyAt(i - 7, mode).tonic).join(' ')}';
      case 'FINDKEY':
        final pitches = w.skip(1).map(parsePitch).toList();
        final keys = <Key>[];
        for (var fifths = -7; fifths <= 7; fifths++) {
          for (var m = 0; m < 2; m++) {
            final key = keyAt(fifths, modes[m]);
            final scale = keyScale(key);
            if (pitches.every(scale.contains)) keys.add(key);
          }
        }
        return 'FINDKEY ${keys.length}${keys.isEmpty ? '' : ' ${keys.join(', ')}'}';
      case 'SPELL':
        final midi = parseNumber(w[1]);
        final key = parseKey(w[2], w[3]);
        var pitch = standardNote(midi, key.fifths < 0).pitch;
        for (final candidate in keyScale(key)) {
          if (candidate.pitchClass == midi % 12) {
            pitch = candidate;
            break;
          }
        }
        final note = fromMidi(pitch, midi);
        if (!note.valid) throw const CommandError('OUT OF RANGE');
        return 'SPELL $midi $key $note ${label(key, pitch)}';
      case 'KEYDIST':
        final a = parseKey(w[1], w[2]);
        final b = parseKey(w[3], w[4]);
        var difference = (b.fifths - a.fifths) % 12;
        if (difference > 6) difference -= 12;
        final first = pitchMask(keyScale(a)), second = pitchMask(keyScale(b));
        var common = 0;
        for (var i = 0; i < 12; i++) {
          if ((first & second & (1 << i)) != 0) common++;
        }
        final sameTonic = a.tonic.pitchClass == b.tonic.pitchClass;
        final relation = first == second ? sameTonic ? 'same' : 'relative' : sameTonic ? 'parallel' : difference.abs() == 1 ? 'close' : 'distant';
        return 'KEYDIST $a $b fifths=${signed(difference)} common=$common relation=$relation';
      default:
        throw StateError('Unknown checked command');
    }
  }
}

void main() {
  final calculator = Calculator();
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      stdout.writeln(calculator.execute(line));
    } on CommandError catch (error) {
      stdout.writeln(error);
    }
  }
}
