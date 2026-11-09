import 'dart:io';
import 'dart:math' as math;
part 'song_parser.dart';
part 'instruments.dart';
part 'sequencer.dart';
part 'mixer.dart';
part 'report.dart';

const effectOrder = [
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  'A',
  'B',
  'C',
  'D',
  'E1',
  'E2',
  'E9',
  'EA',
  'EB',
  'EC',
  'ED',
  'EE',
  'F',
  'P',
  'Q',
  'R',
  'V',
];
const tonicNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];
const majorWeights = [64, 22, 35, 23, 44, 41, 25, 52, 24, 37, 23, 29],
    minorWeights = [64, 27, 35, 54, 27, 35, 25, 48, 40, 27, 34, 32];
String hex2(int value) => value.toRadixString(16).toUpperCase().padLeft(2, '0');
String hex1(int value) => value.toRadixString(16).toUpperCase();
String hexList(List<int> values) =>
    values.isEmpty ? 'none' : values.map(hex2).join(' ');
String noteRange(List<int> notes) => notes.isEmpty
    ? 'none'
    : '${noteName(notes.reduce(math.min))}..${noteName(notes.reduce(math.max))}';
List<int> instrumentNumbers(Song song) =>
    song.instruments.keys.toList()..sort();
List<int> patternNumbers(Song song) => song.patterns.keys.toList()..sort();

class NoteRecord {
  final int serial, channel, position, row, note, start;
  final Instrument instrument;
  int length = 0;
  int? release;
  String reason = '';
  NoteRecord(
    this.serial,
    this.channel,
    this.position,
    this.row,
    this.instrument,
    this.note,
    this.start,
  );
}

class PlayedRow {
  final int position, row, start, speed, tempo;
  final List<int?> notes;
  PlayedRow(
    this.position,
    this.row,
    this.start,
    this.speed,
    this.tempo,
    this.notes,
  );
}

class Channel {
  final int number;
  Instrument? instrument;
  int? note;
  int frequency = 0,
      target = 0,
      portamento = 0,
      slide = 0,
      detune = 0,
      vibratoSpeed = 0,
      vibratoDepth = 0,
      vibratoPosition = 0,
      tremoloSpeed = 0,
      tremoloDepth = 0,
      tremoloPosition = 0,
      volume = 15,
      mode = 0,
      phase = 0,
      register = 1,
      age = 0,
      releaseAge = 0,
      releaseLevel = 0,
      envelope = 0,
      outputFrequency = 0,
      outputVolume = 0,
      amplitude = 0,
      increment = 0;
  bool released = false, sounding = false;
  Effect? effect;
  NoteRecord? record;
  int noteOns = 0, retriggers = 0, cuts = 0, active = 0, audible = 0;
  Channel(this.number);
  String? get effectName => effect?.name;
  int get effectValue => effect?.value ?? 0;
  void keyOff() {
    releaseAge = age;
    releaseLevel = envelope;
    released = true;
  }

  void approach(int step) {
    frequency = frequency < target
        ? math.min(frequency + step, target)
        : math.max(frequency - step, target);
  }

  void volumeSlide() {
    volume = clamp(volume + effect!.high - effect!.low, 0, 15);
  }

  void updateOutput(int tick, int rate) {
    final ins = instrument!, name = effectName;
    var semitones = name == '0' ? [0, effect!.high, effect!.low][tick % 3] : 0;
    if (ins.arpeggio.isNotEmpty)
      semitones += ins.arpeggio[age % ins.arpeggio.length];
    var output = transpose(frequency, semitones) + detune;
    if (name == '4' || name == '6')
      output += oscillation(vibratoPosition, vibratoDepth, 4);
    final vib = ins.vibrato;
    if (vib != null && age >= vib.$1)
      output += oscillation((age - vib.$1) * vib.$2 % 64, vib.$3, 4);
    outputFrequency = clamp(output, 1000, 50 * rate);
    envelope = envelopeValue(ins, age, released, releaseAge, releaseLevel);
    outputVolume = name == '7'
        ? clamp(volume + oscillation(tremoloPosition, tremoloDepth, 255), 0, 15)
        : volume;
    amplitude = envelope * outputVolume;
    increment = outputFrequency * 65536 ~/ (100 * rate);
  }
}

class Player {
  final Song song;
  final Params params;
  final channels = List.generate(4, (i) => Channel(i + 1)),
      lanes = List.generate(4, (_) => <int>[]),
      samples = <int>[];
  late int speed, tempo;
  int delay = 0, position = 0, row = 0, ticks = 0, clipped = 0;
  List<Cell> cells = [];
  final records = <NoteRecord>[],
      warnings = <String>[],
      log = <String>[],
      played = <PlayedRow>[];
  final playCounts = <(int, int), int>{},
      firstStarts = <(int, int), int>{},
      instrumentTicks = <int, int>{},
      effectCounts = <String, int>{};
  String endReason = 'finished';
  (int, int)? endRow;
  int? loopStart;
  Player(this.song, this.params) {
    speed = song.speed;
    tempo = song.tempo;
  }
  void warn(Channel c, String message) {
    warnings.add(
      'warning ${hex2(position)}:${hex2(row)} ch${c.number} $message',
    );
  }

  int clampFrequency(int frequency) => clamp(frequency, 1000, 50 * song.rate);
  void endRecord(Channel c, String reason) {
    final record = c.record!;
    record.length = samples.length - record.start;
    record.reason = reason;
    c.record = null;
  }

  void noteOn(Channel c, int note) {
    if (c.record != null) endRecord(c, 'next');
    c.frequency = noteFrequency(note);
    c.target = c.frequency;
    c.phase = 0;
    c.age = 0;
    c.vibratoPosition = 0;
    c.tremoloPosition = 0;
    c.released = false;
    c.note = note;
    c.noteOns++;
    final record = NoteRecord(
      records.length + 1,
      c.number,
      position,
      row,
      c.instrument!,
      note,
      samples.length,
    );
    c.record = record;
    records.add(record);
  }

  void applyCell(Channel c, Cell cell, bool portamento) {
    if (cell.instrument != null) {
      final ins = song.instruments[cell.instrument];
      if (ins == null) {
        warn(c, 'undefined instrument ${hex2(cell.instrument!)}');
      } else {
        c.instrument = ins;
        c.volume = 15;
        c.mode = ins.mode;
      }
    }
    if (cell.volume != null) c.volume = cell.volume!;
    if (cell.keyOff) {
      if (c.note != null && !c.released) {
        c.keyOff();
        c.record!.release = samples.length - c.record!.start;
      } else {
        warn(c, 'key off without note');
      }
    } else if (cell.note != null) {
      if (c.instrument == null) {
        warn(c, 'note without instrument');
      } else if (portamento && c.note != null) {
        c.target = noteFrequency(cell.note!);
        c.note = cell.note;
      } else {
        if (portamento) warn(c, 'portamento without note');
        noteOn(c, cell.note!);
      }
    }
  }

  void noteSlide(Channel c, Effect e) {
    if (c.note == null) {
      warn(c, 'slide without note');
      return;
    }
    c.note = e.name == 'Q'
        ? math.min(c.note! + e.low, 95)
        : math.max(c.note! - e.low, 12);
    c.target = noteFrequency(c.note!);
    c.slide = 2 * e.high + 1;
  }

  void startEffect(Channel c) {
    final e = c.effect!, value = c.effect!.value;
    switch (e.name) {
      case '3':
        if (value > 0) c.portamento = value;
      case '4':
        if (e.high > 0) c.vibratoSpeed = e.high;
        if (e.low > 0) c.vibratoDepth = e.low;
      case '7':
        if (e.high > 0) c.tremoloSpeed = e.high;
        if (e.low > 0) c.tremoloDepth = e.low;
      case 'C':
        c.volume = math.min(value, 15);
      case 'E1':
        c.frequency = clampFrequency(c.frequency + 10 * value);
      case 'E2':
        c.frequency = clampFrequency(c.frequency - 10 * value);
      case 'EA':
        c.volume = math.min(c.volume + value, 15);
      case 'EB':
        c.volume = math.max(c.volume - value, 0);
      case 'EE':
        delay = value;
      case 'F':
        if (value >= 1 && value <= 31) {
          speed = value;
        } else if (value >= 32) {
          tempo = value;
        }
      case 'P':
        c.detune = value - 128;
      case 'Q' || 'R':
        noteSlide(c, e);
      case 'V':
        final ins = c.instrument;
        if (ins != null &&
            (ins.wave == 'PULSE' && value <= 3 ||
                ins.wave == 'NOISE' && value <= 1)) {
          c.mode = value;
        } else {
          warn(c, 'invalid mode ${hex2(value)}');
        }
    }
  }

  void tickEffect(Channel c) {
    final e = c.effect!;
    switch (e.name) {
      case '1':
        c.frequency = clampFrequency(c.frequency + 10 * e.value);
      case '2':
        c.frequency = clampFrequency(c.frequency - 10 * e.value);
      case '3':
        c.approach(10 * c.portamento);
      case '5':
        c.approach(10 * c.portamento);
        c.volumeSlide();
      case '6' || 'A':
        c.volumeSlide();
      case 'Q' || 'R':
        if (c.slide != 0) c.approach(10 * c.slide);
    }
  }

  void startRow() {
    delay = 0;
    for (var i = 0; i < channels.length; i++) {
      final c = channels[i], cell = cells[i];
      c.effect = cell.effect;
      c.slide = 0;
      final name = c.effectName;
      if (name != null) effectCounts[name] = (effectCounts[name] ?? 0) + 1;
      if (!(name == 'ED' && c.effectValue >= 1))
        applyCell(c, cell, name == '3' || name == '5');
      if (c.effect != null) startEffect(c);
    }
  }

  void processTick(int tick) {
    for (var i = 0; i < channels.length; i++) {
      final c = channels[i],
          name = channels[i].effectName,
          value = channels[i].effectValue;
      if (c.note != null && c.age >= 1 && c.instrument!.sweep != 0)
        c.frequency = clampFrequency(c.frequency + 10 * c.instrument!.sweep);
      if (tick >= 1 && c.effect != null) tickEffect(c);
      if (name == 'ED' && value >= 1 && tick == value)
        applyCell(c, cells[i], false);
      if (name == 'E9' &&
          value >= 1 &&
          tick >= 1 &&
          tick % value == 0 &&
          c.note != null) {
        c.phase = 0;
        c.age = 0;
        c.released = false;
        c.retriggers++;
      }
      if (name == 'EC' && tick == value && c.note != null) {
        endRecord(c, 'cut');
        c.note = null;
        c.cuts++;
      }
      c.sounding = c.note != null;
      if (c.sounding) {
        c.updateOutput(tick, song.rate);
        c.active++;
        if (c.amplitude > 0) c.audible++;
        final number = c.instrument!.number;
        instrumentTicks[number] = (instrumentTicks[number] ?? 0) + 1;
      }
    }
  }

  void advance() {
    for (final c in channels) {
      final name = c.effectName;
      if (c.note != null) c.age++;
      if (name == '4' || name == '6') {
        c.vibratoPosition = (c.vibratoPosition + c.vibratoSpeed) % 64;
      } else if (name == '7') {
        c.tremoloPosition = (c.tremoloPosition + c.tremoloSpeed) % 64;
      }
    }
    ticks++;
  }

  String channelText(Channel c) {
    final effect = c.effect?.text ?? '...';
    if (c.note == null)
      return '--- -- ${'-'.padLeft(7)} - ${hex1(c.volume)} $effect';
    return '${noteName(c.note!)} ${hex2(c.instrument!.number)} ${c.outputFrequency.toString().padLeft(7)} ${hex1(c.envelope)} ${hex1(c.outputVolume)} $effect';
  }

  void logRow(int start) {
    log.add(
      [
        '${hex2(position)} ${hex2(song.order[position])} ${hex2(row)} ${start.toString().padLeft(7)} ${speed.toString().padLeft(2)} ${tempo.toString().padLeft(3)}',
        ...channels.map(channelText),
      ].join(' | '),
    );
    played.add(
      PlayedRow(
        position,
        row,
        start,
        speed,
        tempo,
        channels.map((c) => c.note).toList(),
      ),
    );
  }

  void logTick(int tick) {
    log.add(
      [
        '  tick ${tick.toString().padLeft(3)} ${samples.length.toString().padLeft(7)}',
        for (final c in channels)
          c.sounding
              ? '${c.outputFrequency.toString().padLeft(7)} ${c.increment.toString().padLeft(5)} ${hex1(c.envelope)}${hex1(c.outputVolume)}'
              : '${'-'.padLeft(7)} ${'-'.padLeft(5)} --',
      ].join(' | '),
    );
  }

  bool playRow(int p, int r) {
    position = p;
    row = r;
    cells = song.cells(p, r);
    final start = samples.length, key = (p, r);
    firstStarts.putIfAbsent(key, () => start);
    startRow();
    final ticks = speed * (1 + delay);
    for (final c in channels) {
      if (c.effectName == 'EC' && c.effectValue >= ticks) {
        warn(c, 'cut beyond row');
      } else if (c.effectName == 'ED' && c.effectValue >= ticks) {
        warn(c, 'delay beyond row');
      }
    }
    final spt = samplesPerTick(song.rate, tempo);
    for (var tick = 0; tick < ticks; tick++) {
      processTick(tick);
      if (tick == 0) logRow(start);
      if (params.traces.contains(key)) logTick(tick);
      final count = math.min(spt, params.maxSamples - samples.length);
      clipped += mixTick(
        channels,
        count,
        song.gain,
        params.muted,
        samples,
        lanes,
      );
      advance();
      if (samples.length == params.maxSamples) return false;
    }
    return true;
  }

  void play() {
    var position = 0, row = 0;
    while (true) {
      final key = (position, row);
      playCounts[key] = (playCounts[key] ?? 0) + 1;
      if (!playRow(position, row)) {
        endReason = 'limit';
        break;
      }
      final next = nextRow(song, position, row);
      if (next == null) {
        endReason = 'stop';
        endRow = key;
        break;
      }
      position = next.$1;
      row = next.$2;
      if (position >= song.order.length) {
        endReason = 'finished';
        break;
      }
      if ((playCounts[next] ?? 0) >= params.loops) {
        endReason = 'loop';
        endRow = next;
        loopStart = firstStarts[next]!;
        break;
      }
    }
    for (final c in channels) {
      if (c.record != null) endRecord(c, 'end');
    }
    if ((endReason == 'limit' || endReason == 'loop') && params.fade > 0)
      fadeOut(samples, params.fade);
  }

  String get endText => endReason == 'stop' || endReason == 'loop'
      ? '$endReason order=${hex2(endRow!.$1)} row=${hex2(endRow!.$2)}'
      : endReason;
}

List<String> noteLines(Player p) {
  final lines = <String>[];
  for (final r in p.records) {
    final segment = p.lanes[r.channel - 1].sublist(r.start, r.start + r.length);
    var cycles = 0;
    for (var i = 1; i < segment.length; i++) {
      if (segment[i - 1] < 0 && segment[i] >= 0) cycles++;
    }
    lines.add(
      '${r.serial.toString().padLeft(4)} ch=${r.channel} at=${hex2(r.position)}:${hex2(r.row)} ins=${hex2(r.instrument.number)} note=${noteName(r.note)} start=${r.start} length=${r.length} release=${r.release ?? '-'} end=${r.reason} peak=${peak(segment, 0)} cycles=$cycles',
    );
  }
  return lines;
}

List<String> rollLines(List<PlayedRow> played, int start, int rows) {
  final targets = played.sublist(
    math.min(start, played.length),
    math.min(start + rows, played.length),
  );
  final pitches = {
    for (final row in targets)
      for (final note in row.notes)
        if (note != null) note,
  }.toList()..sort((a, b) => b.compareTo(a));
  final lines = [
    'ROLL start=$start rows=${targets.length} pitches=${pitches.length}',
  ];
  for (final pitch in pitches) {
    final marks = <String>[];
    for (final row in targets) {
      final owners = [
        for (var i = 0; i < row.notes.length; i++)
          if (row.notes[i] == pitch) i + 1,
      ];
      marks.add(
        owners.isEmpty
            ? ' '
            : owners.length == 1
            ? '${owners.first}'
            : '*',
      );
    }
    lines.add('${noteName(pitch)} |${marks.join()}|');
  }
  lines.add(
    '    +${[for (var i = 0; i < targets.length; i++) i % 16 == 0 ? '+' : '-'].join()}+',
  );
  return lines;
}

List<String> statsLines(Player p) {
  final song = p.song, samples = p.samples, n = p.samples.length;
  final lines = [
    'title=${song.title}',
    'rate=${song.rate}',
    'samples=$n',
    'duration_ms=${n * 1000 ~/ song.rate}',
    'end=${p.endText}',
  ];
  lines.addAll(
    p.endReason == 'loop'
        ? ['loop_start=${p.loopStart}', 'loop_length=${n - p.loopStart!}']
        : ['loop_start=-', 'loop_length=-'],
  );
  lines.addAll([
    'rows=${p.played.length}',
    'ticks=${p.ticks}',
    'clipped=${p.clipped}',
    'peak=${peak(samples, 128)}',
    'min=${samples.reduce(math.min)}',
    'max=${samples.reduce(math.max)}',
    'rms=${rootMeanSquare(samples, 128)}',
    'zero_crossings=${zeroCrossings(samples)}',
    'adler32=${adler32Text(samples)}',
  ]);
  final path = <String>[];
  int? previous;
  for (final row in p.played) {
    if (previous != row.position) {
      path.add(hex2(row.position));
      previous = row.position;
    }
  }
  lines.add('path ${path.join(' ')}');
  (int, int)? timing;
  for (final row in p.played) {
    final pair = (row.speed, row.tempo);
    if (timing != pair)
      lines.add(
        'timing sample=${row.start} order=${hex2(row.position)} row=${hex2(row.row)} speed=${row.speed} tempo=${row.tempo}',
      );
    timing = pair;
  }
  for (var i = 0; i < p.channels.length; i++) {
    final c = p.channels[i], lane = p.lanes[i];
    lines.add(
      'channel ${c.number} notes=${c.noteOns} retriggers=${c.retriggers} cuts=${c.cuts} active=${c.active} audible=${c.audible} peak=${peak(lane, 0)} rms=${rootMeanSquare(lane, 0)}',
    );
  }
  final numbers = instrumentNumbers(song);
  for (final number in numbers) {
    final ins = song.instruments[number]!,
        records = p.records
            .where((r) => identical(r.instrument, song.instruments[number]))
            .toList();
    var total = 0;
    for (final r in records) {
      total += r.length;
    }
    lines.add(
      'instrument ${hex2(number)} ${ins.name} ${ins.wave} notes=${records.length} ticks=${p.instrumentTicks[number] ?? 0} range=${noteRange(records.map((r) => r.note).toList())} average=${records.isEmpty ? '-' : total ~/ records.length}',
    );
  }
  for (final number in patternNumbers(song)) {
    final pattern = song.patterns[number]!;
    var rows = 0, notes = 0;
    for (final cells in pattern.rows) {
      if (cells.any((c) => !c.isEmpty)) rows++;
      for (final cell in cells) {
        if (cell.hasNote) notes++;
      }
    }
    lines.add(
      'pattern ${hex2(number)} rows=$rows notes=$notes orders=${song.order.where((n) => n == number).length}',
    );
  }
  final reached = reachableRows(song);
  for (var position = 0; position < song.order.length; position++) {
    final rows = p.played.where((row) => row.position == position).toList();
    var dead = 0;
    for (var row = 0; row < 64; row++) {
      if (!reached.contains((position, row)) &&
          song.cells(position, row).any((c) => c.hasNote))
        dead++;
    }
    lines.add(
      'order ${hex2(position)} pattern=${hex2(song.order[position])} rows=${rows.length} first=${rows.isEmpty ? '-' : rows.first.start} dead=$dead',
    );
  }
  final noteCounts = <int, int>{};
  for (final r in p.records) {
    noteCounts[r.note] = (noteCounts[r.note] ?? 0) + 1;
  }
  final notes = noteCounts.keys.toList()..sort();
  for (final note in notes) {
    lines.add('note ${noteName(note)} count=${noteCounts[note]}');
  }
  final effects = [
    for (final name in effectOrder)
      if ((p.effectCounts[name] ?? 0) > 0) '$name=${p.effectCounts[name]}',
  ];
  lines.add('effects ${effects.isEmpty ? 'none' : effects.join(' ')}');
  lines.addAll([
    'unused_instruments=${hexList(numbers.where((number) => !p.records.any((r) => r.instrument.number == number)).toList())}',
    'unused_patterns=${hexList(patternNumbers(song).where((number) => !song.order.contains(number)).toList())}',
    'unreached_orders=${hexList([for (var position = 0; position < song.order.length; position++)
      if (!p.played.any((row) => row.position == position)) position])}',
  ]);
  final totals = List.filled(12, 0);
  for (final r in p.records) {
    if (r.instrument.wave != 'NOISE') totals[r.note % 12] += r.length;
  }
  lines.add(
    'pitch_classes ${[for (var i = 0; i < 12; i++) '${tonicNames[i]}=${totals[i]}'].join(' ')}',
  );
  final keys = <(String, int)>[];
  for (var mode = 0; mode < 2; mode++) {
    final weights = mode == 0 ? majorWeights : minorWeights;
    for (var tonic = 0; tonic < 12; tonic++) {
      var score = 0;
      for (var pitch = 0; pitch < 12; pitch++) {
        score += weights[(pitch - tonic) % 12] * totals[pitch];
      }
      keys.add((
        '${tonicNames[tonic]} ${mode == 0 ? 'major' : 'minor'}',
        score,
      ));
    }
  }
  final indexed = List.generate(24, (i) => i)
    ..sort((a, b) {
      final cmp = keys[b].$2.compareTo(keys[a].$2);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  final best = keys[indexed[0]], runnerUp = keys[indexed[1]];
  lines.add(
    'key=${best.$1} score=${best.$2} runner_up=${runnerUp.$1} score=${runnerUp.$2}',
  );
  for (final c in p.channels) {
    final records = p.records.where((r) => r.channel == c.number).toList();
    lines.add(
      'usage ch${c.number} range=${noteRange(records.map((r) => r.note).toList())} ${[for (final number in numbers) '${hex2(number)}=${records.where((r) => r.instrument.number == number).length}'].join(' ')}',
    );
  }
  return [...lines, ...p.warnings];
}

int plotRow(int value, int low, int high, int height) =>
    (2 * (high - value) * (height - 1) + (high - low)) ~/ (2 * (high - low));
List<String> plotLines(
  List<int> values,
  int low,
  int high,
  int middle,
  int height,
  int width,
) {
  final length = values.length,
      middleRow = plotRow(middle, low, high, height),
      columns = <(int, int)>[];
  for (var c = 0; c < width; c++) {
    final covered = values.sublist(
      c * length ~/ width,
      (c + 1) * length ~/ width,
    );
    columns.add((
      plotRow(covered.reduce(math.max), low, high, height),
      plotRow(covered.reduce(math.min), low, high, height),
    ));
  }
  final lines = <String>[];
  for (var row = 0; row < height; row++) {
    final label = row == 0
        ? '$high'
        : row == middleRow
        ? '$middle'
        : row == height - 1
        ? '$low'
        : '';
    lines.add(
      '${label.padLeft(5)} |${columns.map((column) => column.$1 <= row && row <= column.$2
          ? '#'
          : row == middleRow
          ? '-'
          : ' ').join()}|',
    );
  }
  return lines;
}

List<String> axisLines(int start, int length, int width, int rate) {
  final ruler = [
    for (var c = 0; c < width; c++) c % 10 == 0 ? '+' : '-',
  ].join();
  var labels = '    ms';
  for (var c = 0; c < width; c += 10) {
    final milliseconds = (start + c * length ~/ width) * 1000 ~/ rate;
    labels = '${labels.padRight(7 + c)}$milliseconds';
  }
  return ['      +$ruler+', labels];
}

List<String> waveformLines(Player p) {
  final s = p.params,
      start = p.params.windowStart,
      length = p.params.windowLength,
      width = p.params.windowWidth,
      axes = axisLines(
        p.params.windowStart,
        p.params.windowLength,
        p.params.windowWidth,
        p.song.rate,
      );
  return [
    'MIX start=$start length=$length width=$width height=${s.windowHeight}',
    ...plotLines(
      p.samples.sublist(start, start + length),
      0,
      255,
      128,
      s.windowHeight,
      width,
    ),
    ...axes,
    for (var i = 0; i < 4; i++) ...[
      'CHANNEL ${i + 1}',
      ...plotLines(
        p.lanes[i].sublist(start, start + length),
        -3375,
        3375,
        0,
        s.windowScope,
        width,
      ),
    ],
    ...axes,
  ];
}

List<String> previewLines(Song song, Params params, Instrument ins) {
  final c = Channel(1);
  c.instrument = ins;
  c.mode = ins.mode;
  c.note = params.previewNote;
  c.frequency = noteFrequency(params.previewNote);
  c.target = c.frequency;
  c.sounding = true;
  final spt = samplesPerTick(song.rate, song.tempo),
      samples = <int>[],
      lanes = [<int>[]],
      envelopes = <String>[],
      frequencies = <String>[];
  for (var tick = 0; tick < params.previewTicks; tick++) {
    c.age = tick;
    if (tick == params.previewRelease) c.keyOff();
    if (tick >= 1 && ins.sweep != 0)
      c.frequency = clamp(c.frequency + 10 * ins.sweep, 1000, 50 * song.rate);
    c.updateOutput(tick, song.rate);
    envelopes.add(hex1(c.envelope));
    frequencies.add('${c.outputFrequency}');
    mixTick([c], spt, song.gain, [false], samples, lanes);
  }
  return [
    'instrument ${hex2(ins.number)} ${ins.name} wave=${ins.wave} samples=${samples.length} peak=${peak(samples, 128)} rms=${rootMeanSquare(samples, 128)} adler32=${adler32Text(samples)}',
    '  env ${envelopes.join()}',
    '  freq ${frequencies.join(' ')}',
  ];
}

void writeLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void main() {
  final song = readSong(), params = readParams(), player = Player(song, params);
  player.play();
  final previews = <String>[];
  for (final number in instrumentNumbers(song)) {
    previews.addAll(previewLines(song, params, song.instruments[number]!));
  }
  Directory('output').createSync(recursive: true);
  writeLines('samples.txt', hexLines(player.samples));
  writeLines('channel_log.txt', player.log);
  writeLines('notes.txt', noteLines(player));
  writeLines(
    'roll.txt',
    rollLines(player.played, params.rollStart, params.rollRows),
  );
  writeLines('stats.txt', statsLines(player));
  writeLines('waveform.txt', waveformLines(player));
  writeLines('instruments.txt', previews);
}
