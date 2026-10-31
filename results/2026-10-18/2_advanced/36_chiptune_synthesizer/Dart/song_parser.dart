part of 'main.dart';

const pitchNames = [
  'C-',
  'C#',
  'D-',
  'D#',
  'E-',
  'F-',
  'F#',
  'G-',
  'G#',
  'A-',
  'A#',
  'B-',
];
List<String> readLines(String path) => File(path).readAsLinesSync();
int hexNumber(String text) => int.parse(text, radix: 16);
int noteNumber(String name) =>
    12 * int.parse(name[2]) + pitchNames.indexOf(name.substring(0, 2));
String noteName(int n) => '${pitchNames[n % 12]}${n ~/ 12}';

class Effect {
  final String text, name;
  final int value;
  Effect(this.text)
    : name = text.startsWith('E') ? text.substring(0, 2) : text[0],
      value = hexNumber(text.substring(text.startsWith('E') ? 2 : 1));
  int get high => value ~/ 16;
  int get low => value % 16;
}

class Cell {
  final int? note, instrument, volume;
  final bool keyOff;
  final Effect? effect;
  Cell(String text)
    : note = text.startsWith('...') || text.startsWith('OFF')
          ? null
          : noteNumber(text.substring(0, 3)),
      instrument = text.substring(4, 6) == '..'
          ? null
          : hexNumber(text.substring(4, 6)),
      volume = text[7] == '.' ? null : hexNumber(text[7]),
      keyOff = text.startsWith('OFF'),
      effect = text.substring(9) == '...' ? null : Effect(text.substring(9));
  bool get hasNote => keyOff || note != null;
  bool get isEmpty =>
      !hasNote && instrument == null && volume == null && effect == null;
}

class Instrument {
  final int number;
  final String name;
  String wave = '';
  int mode = 0, attack = 0, decay = 0, sustain = 0, release = 0, sweep = 0;
  final table = <int>[], arpeggio = <int>[];
  (int, int, int)? vibrato;
  Instrument(this.number, this.name);
}

class Pattern {
  final int number;
  final rows = List.generate(
    64,
    (_) => List.generate(4, (_) => Cell('... .. . ...')),
  );
  Pattern(this.number);
}

class Song {
  final String title;
  final int rate, speed, tempo, gain;
  final instruments = <int, Instrument>{},
      patterns = <int, Pattern>{},
      order = <int>[];
  Song(this.title, this.rate, this.speed, this.tempo, this.gain);
  List<Cell> cells(int position, int row) =>
      patterns[order[position]]!.rows[row];
}

Song readSong() {
  final lines = readLines(
    'input/song.txt',
  ).where((line) => line.isNotEmpty && !line.startsWith('#')).toList();
  final s = Song(
    lines[0].substring(6),
    int.parse(lines[1].substring(5)),
    int.parse(lines[2].substring(6)),
    int.parse(lines[3].substring(6)),
    int.parse(lines[4].substring(5)),
  );
  var index = 5;
  while (index < lines.length) {
    final words = lines[index].split(' ');
    if (words[0] == 'ORDER') {
      s.order.addAll(words.skip(1).map(hexNumber));
      index++;
      continue;
    }
    var end = index + 1;
    while (lines[end] != 'END') {
      end++;
    }
    final block = lines.sublist(index + 1, end), number = hexNumber(words[1]);
    if (words[0] == 'INSTRUMENT') {
      final ins = Instrument(number, words[2]);
      for (final line in block) {
        final v = line.split(' ');
        switch (v[0]) {
          case 'WAVE':
            ins.wave = v[1];
            if (ins.wave == 'PULSE') {
              ins.mode = ['12', '25', '50', '75'].indexOf(v[2]);
            } else if (ins.wave == 'NOISE') {
              ins.mode = v[2] == 'SHORT' ? 1 : 0;
            } else if (ins.wave == 'TABLE') {
              ins.table.addAll(v[2].split('').map(hexNumber));
            }
          case 'ENVELOPE':
            ins.attack = int.parse(v[1]);
            ins.decay = int.parse(v[2]);
            ins.sustain = int.parse(v[3]);
            ins.release = int.parse(v[4]);
          case 'VIBRATO':
            ins.vibrato = (int.parse(v[1]), int.parse(v[2]), int.parse(v[3]));
          case 'ARPEGGIO':
            ins.arpeggio.addAll(v.skip(1).map(int.parse));
          case 'SWEEP':
            ins.sweep = int.parse(v[1]);
        }
      }
      s.instruments[number] = ins;
    } else {
      final pattern = Pattern(number);
      for (final line in block) {
        pattern.rows[hexNumber(line.substring(0, 2))] = line
            .substring(3)
            .split(' | ')
            .map(Cell.new)
            .toList();
      }
      s.patterns[number] = pattern;
    }
    index = end + 1;
  }
  return s;
}

class Params {
  int maxSamples = 0,
      loops = 0,
      fade = 0,
      windowStart = 0,
      windowLength = 0,
      windowWidth = 0,
      windowHeight = 0,
      windowScope = 0,
      rollStart = 0,
      rollRows = 0,
      previewNote = 0,
      previewTicks = 0,
      previewRelease = 0;
  List<bool> muted = List.filled(4, false);
  final traces = <(int, int)>{};
}

Params readParams() {
  final p = Params();
  for (final line in readLines('input/params.txt')) {
    if (line.isEmpty) continue;
    final v = line.split(' ');
    switch (v[0]) {
      case 'max_samples':
        p.maxSamples = int.parse(v[1]);
      case 'loops':
        p.loops = int.parse(v[1]);
      case 'fade':
        p.fade = int.parse(v[1]);
      case 'mute':
        p.muted = v.skip(1).map((x) => x == '1').toList();
      case 'window':
        p.windowStart = int.parse(v[1]);
        p.windowLength = int.parse(v[2]);
        p.windowWidth = int.parse(v[3]);
        p.windowHeight = int.parse(v[4]);
        p.windowScope = int.parse(v[5]);
      case 'roll':
        p.rollStart = int.parse(v[1]);
        p.rollRows = int.parse(v[2]);
      case 'preview':
        p.previewNote = noteNumber(v[1]);
        p.previewTicks = int.parse(v[2]);
        p.previewRelease = int.parse(v[3]);
      case 'trace':
        p.traces.add((hexNumber(v[1]), hexNumber(v[2])));
    }
  }
  return p;
}
