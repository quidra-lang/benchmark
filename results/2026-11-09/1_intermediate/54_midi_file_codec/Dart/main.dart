import 'dart:io';
import 'dart:collection';

const channelKinds = ['NOTE_OFF', 'NOTE_ON', 'POLY_PRESSURE', 'CONTROL', 'PROGRAM', 'CHANNEL_PRESSURE', 'PITCH_BEND'];
const textKinds = ['TEXT_EVENT', 'COPYRIGHT', 'TRACK_NAME', 'INSTRUMENT_NAME', 'LYRIC', 'MARKER', 'CUE_POINT'];
final majorKeys = 'Cb Gb Db Ab Eb Bb F C G D A E B F# C#'.split(' ');
final minorKeys = 'Ab Eb Bb F C G D A E B F# C# G# D# A#'.split(' ');
const pitches = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const metaKinds = {0: 'SEQUENCE_NUMBER', 32: 'CHANNEL_PREFIX', 47: 'END_OF_TRACK', 81: 'TEMPO', 84: 'SMPTE_OFFSET', 88: 'TIME_SIGNATURE', 89: 'KEY_SIGNATURE', 127: 'SEQUENCER_SPECIFIC'};
class Event {
  int tick;
  final int code;
  List<int> data;
  Event(this.tick, this.code, List<int> data) : data = List.of(data);
  Event copy() => Event(tick, code, data);
  bool channel() => code >= 128 && code < 240;
  int ch() => (code & 15) + 1;
  bool on() => channel() && code >> 4 == 9 && data[1] > 0;
  bool off() => channel() && (code >> 4 == 8 || code >> 4 == 9 && data[1] == 0);
  bool end() => code == 303;
  String kind() {
    if (channel()) return channelKinds[(code >> 4) - 8];
    if (code == 240) return 'SYSEX';
    if (code == 247) return 'SYSEX_ESCAPE';
    final type = code - 256;
    return type >= 1 && type <= 7 ? textKinds[type - 1] : metaKinds[type] ?? 'META';
  }
}
class Song {
  int format;
  final int division;
  List<List<Event>> tracks;
  Song(this.format, this.division, this.tracks);
  Song copy() => Song(format, division, tracks.map((t) => t.map((e) => e.copy()).toList()).toList());
  int count() => tracks.fold(0, (total, track) => total + track.length);
  int length() => tracks.map((t) => t.last.tick).reduce((a, b) => a > b ? a : b);
}
class Located {
  final Event event;
  final int track, order;
  Located(this.event, this.track, this.order);
}
class Note {
  final Located on, off;
  Note(this.on, this.off);
  int start() => on.event.tick;
  int length() => off.event.tick - start();
  int channel() => on.event.ch();
  int pitch() => on.event.data[0];
}
class Pairing {
  final List<Note> notes;
  final List<Located> unmatched;
  Pairing(this.notes, this.unmatched);
}
class Failure implements Exception {
  final String message;
  Failure(this.message);
}
Never fail(String message) => throw Failure(message);
final output = StringBuffer();
void emit(String line) => output.writeln(line);
final SplayTreeMap<String, Song> songs = SplayTreeMap();
bool running = true, zeroOff = false;
String noteName(int n) => '${pitches[n % 12]}${n ~/ 12 - 1}';
int noteNumber(String text) {
  for (int p = 0; p < 128; p++) { if (noteName(p) == text) return p; }
  fail('bad value');
}
String hex(int n, int width) => n.toRadixString(16).toUpperCase().padLeft(width, '0');
String dataHex(List<int> data) => data.map((b) => hex(b, 2)).join();
int value(List<int> data) => data.fold(0, (a, b) => a * 256 + b);
List<int> bytes(int value, int size) => List.generate(size, (i) => (value >> ((size - i - 1) * 8)) & 255);
List<Located> global(Song s) {
  final List<Located> result = [];
  int order = 0;
  for (int t = 0; t < s.tracks.length; t++) {
    for (final e in s.tracks[t]) { result.add(Located(e, t, order++)); }
  }
  result.sort((a, b) {
    int c = a.event.tick.compareTo(b.event.tick);
    if (c == 0) c = a.track.compareTo(b.track);
    return c == 0 ? a.order.compareTo(b.order) : c;
  });
  return result;
}
String description(Song s) => 'format ${s.format} tracks ${s.tracks.length} division ${s.division} events ${s.count()}';
String eventText(Event e, int track) {
  final head = '${e.tick} $track ${e.kind()}';
  final d = e.data, meta = e.code - 256;
  if (e.channel()) {
    final String fields;
    if ((e.code >> 4) <= 10) { fields = '${noteName(d[0])} ${d[1]}'; }
    else if ((e.code >> 4) == 14) { fields = '${d[0] + 128 * d[1] - 8192}'; }
    else { fields = d.join(' '); }
    return '$head ${e.ch()} $fields';
  }
  if (meta >= 1 && meta <= 7) return '$head "${String.fromCharCodes(d)}"';
  if (e.end()) return head;
  if (e.code == 240 || e.code == 247 || meta == 127 || !metaKinds.containsKey(meta)) {
    return '$head${e.kind() == 'META' ? ' ${hex(meta, 2)}' : ''} ${d.length}${d.isEmpty ? '' : ' ${dataHex(d)}'}';
  }
  if (meta == 0 || meta == 81) return '$head ${value(d)}';
  if (meta == 32) return '$head ${d[0] + 1}';
  if (meta == 84) return '$head ${d.join(' ')}';
  if (meta == 88) return '$head ${d[0]}/${1 << d[1]} ${d[2]} ${d[3]}';
  final sf = d[0] >= 128 ? d[0] - 256 : d[0];
  return '$head ${d[1] == 0 ? '${majorKeys[sf + 7]} major' : '${minorKeys[sf + 7]} minor'}';
}
class Parser {
  final List<int> data;
  int position = 0, end, eventStart = 0;
  Parser(this.data) : end = data.length;
  Never error(int offset, String reason) => fail('byte $offset: $reason');
  int read() {
    if (position >= end) error(eventStart, 'truncated event');
    return data[position++];
  }
  int vlq() {
    final start = position;
    int n = 0;
    for (int i = 0; i < 4; i++) {
      final b = read();
      n = n * 128 + (b & 127);
      if (b < 128) return n;
    }
    error(start, 'variable-length value too long');
  }
  int integer(int p, int n) => value(data.sublist(p, p + n));
  int chunk(String id) {
    final p = position;
    if (data.length - p < 8) error(p, 'truncated chunk');
    for (int i = 0; i < 4; i++) { if (data[p + i] != id.codeUnitAt(i)) error(p, 'bad chunk id'); }
    final length = integer(p + 4, 4);
    if (p + 8 + length > data.length) error(p, 'truncated chunk');
    position += 8;
    return length;
  }
  void validateMeta(int type, List<int> d, int p) {
    final length = switch (type) { 0 || 89 => 2, 32 => 1, 47 => 0, 81 => 3, 84 => 5, 88 => 4, _ => -1 };
    if (length >= 0 && d.length != length) error(p, 'bad meta length');
    bool invalid = false;
    if (type == 81) invalid = value(d) == 0;
    if (type == 32) invalid = d[0] > 15;
    if (type == 88) invalid = d[0] == 0 || d[1] > 6;
    if (type == 89) {
      final sf = d[0] >= 128 ? d[0] - 256 : d[0];
      invalid = sf < -7 || sf > 7 || d[1] > 1;
    }
    if (invalid) error(p, 'bad meta data');
  }
  Song parse() {
    if (chunk('MThd') != 6) error(4, 'bad header length');
    final format = integer(8, 2), count = integer(10, 2), division = integer(12, 2);
    if (format > 2) error(8, 'bad format');
    if (count == 0 || format == 0 && count != 1) error(10, 'bad track count');
    if ((division & 32768) != 0) error(12, 'smpte timing not supported');
    if (division == 0) error(12, 'bad division');
    position = 14;
    final List<List<Event>> tracks = [];
    for (int track = 0; track < count; track++) {
      if (position == data.length) error(position, 'missing track');
      final length = chunk('MTrk');
      end = position + length;
      final List<Event> events = [];
      int tick = 0, status = -1;
      while (position < end) {
        if (events.isNotEmpty && events.last.end()) error(position, 'event after end of track');
        eventStart = position;
        tick += vlq();
        final statusPosition = position, b = read();
        if (b < 128) {
          if (status < 0) error(statusPosition, 'data byte without running status');
          position--;
        } else { status = b; }
        int code = status;
        final List<int> payload = [];
        if (status >= 128 && status <= 239) {
          final n = (status >> 4) == 12 || (status >> 4) == 13 ? 1 : 2;
          for (int i = 0; i < n; i++) {
            final p = position, v = read();
            if (v >= 128) error(p, 'bad data byte');
            payload.add(v);
          }
        } else if (status == 240 || status == 247 || status == 255) {
          final meta = status == 255;
          if (meta) code = 256 + read();
          final size = vlq();
          if (position + size > end) error(eventStart, 'truncated event');
          payload.addAll(data.sublist(position, position + size));
          position += size;
          if (meta) validateMeta(code - 256, payload, statusPosition);
          status = -1;
        } else { error(statusPosition, 'unknown status byte'); }
        events.add(Event(tick, code, payload));
      }
      if (events.isEmpty || !events.last.end()) error(end, 'missing end of track');
      tracks.add(events);
      end = data.length;
    }
    if (position < data.length) error(position, 'extra data');
    return Song(format, division, tracks);
  }
}
int bounded(String text, int low, int high) {
  final n = int.tryParse(text);
  if (n == null || n < low || n > high) fail('bad value');
  return n;
}
void fields(List<String> f, int n) { if (f.length != n) fail('bad value'); }
List<int> blob(List<String> f, int start) {
  if (f.length <= start) fail('bad value');
  final length = bounded(f[start], 0, 1000000);
  if (f.length != start + (length == 0 ? 1 : 2)) fail('bad value');
  if (length == 0) return [];
  final text = f[start + 1];
  if (text.length != 2 * length || !RegExp(r'^[0-9A-F]*$').hasMatch(text)) fail('bad value');
  return [for (int i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)];
}
Event parseEvent(String line) {
  final words = line.split(' ');
  final tick = int.parse(words[0]), kind = words[2];
  final prefixLength = words[0].length + words[1].length + kind.length + 2;
  final tail = line.length > prefixLength ? line.substring(prefixLength + 1) : '';
  final List<String> f = tail.isEmpty ? [] : tail.split(' ');
  final channelIndex = channelKinds.indexOf(kind), textIndex = textKinds.indexOf(kind);
  int code;
  List<int> data = [];
  if (channelIndex >= 0) {
    fields(f, channelIndex >= 4 ? 2 : 3);
    final ch = bounded(f[0], 1, 16);
    code = (channelIndex + 8) * 16 + ch - 1;
    if (channelIndex <= 2) { data = [noteNumber(f[1]), bounded(f[2], 0, 127)]; }
    else if (channelIndex == 6) {
      final bend = bounded(f[1], -8192, 8191) + 8192;
      data = [bend % 128, bend ~/ 128];
    } else { data = f.skip(1).map((v) => bounded(v, 0, 127)).toList(); }
  } else if (textIndex >= 0) {
    if (tail.length < 2 || !tail.startsWith('"') || !tail.endsWith('"') || tail.substring(1, tail.length - 1).contains('"')) fail('bad value');
    code = 257 + textIndex;
    data = tail.substring(1, tail.length - 1).codeUnits;
  } else if (kind == 'SYSEX' || kind == 'SYSEX_ESCAPE') {
    code = kind == 'SYSEX' ? 240 : 247;
    data = blob(f, 0);
  } else if (kind == 'META') {
    if (f.length < 2 || !RegExp(r'^[0-9A-F]{2}$').hasMatch(f[0])) fail('bad value');
    final type = int.parse(f[0], radix: 16);
    if (type <= 7 || metaKinds.containsKey(type)) fail('bad value');
    code = 256 + type;
    data = blob(f, 1);
  } else {
    int? meta;
    for (final entry in metaKinds.entries) { if (entry.value == kind) meta = entry.key; }
    if (meta == null) fail('unknown event type');
    code = 256 + meta;
    switch (meta) {
      case 0: {
        fields(f, 1);
        data = bytes(bounded(f[0], 0, 65535), 2);
      }
      case 32: {
        fields(f, 1);
        data = [bounded(f[0], 1, 16) - 1];
      }
      case 47: {
        fields(f, 0);
      }
      case 81: {
        fields(f, 1);
        data = bytes(bounded(f[0], 1, 16777215), 3);
      }
      case 84: {
        fields(f, 5);
        data = f.map((v) => bounded(v, 0, 255)).toList();
      }
      case 88: {
        fields(f, 3);
        final signature = f[0].split('/');
        if (signature.length != 2) fail('bad value');
        final numerator = bounded(signature[0], 1, 255), denominator = bounded(signature[1], 1, 64);
        if ((denominator & (denominator - 1)) != 0) fail('bad value');
        int exponent = 0;
        while ((1 << exponent) < denominator) { exponent++; }
        data = [numerator, exponent, bounded(f[1], 0, 255), bounded(f[2], 0, 255)];
      }
      case 89: {
        fields(f, 2);
        if (f[1] != 'minor' && f[1] != 'major') fail('bad value');
        final minor = f[1] == 'minor', index = (f[1] == 'minor' ? minorKeys : majorKeys).indexOf(f[0]);
        if (index < 0) fail('bad value');
        data = [(index - 7 + 256) % 256, minor ? 1 : 0];
      }
      case 127: {
        data = blob(f, 0);
      }
    }
  }
  return Event(tick, code, data);
}
Song textSong(List<String> lines) {
  final h = lines[0].split(' ');
  late int format, count, division;
  try {
    if (h.length != 4 || h[0] != 'HEADER') fail('bad header');
    format = bounded(h[1], 0, 2);
    count = bounded(h[2], 1, 65535);
    division = bounded(h[3], 1, 32767);
    if (format == 0 && count != 1) fail('bad header');
  } on Failure { fail('line 1: bad header'); }
  final List<List<Event>> tracks = [[]];
  int current = 0;
  for (int i = 1; i < lines.length; i++) {
    try {
      final e = parseEvent(lines[i]), track = int.parse(lines[i].split(' ')[1]);
      if (track >= count) fail('bad track');
      List<Event> events = tracks[current];
      final end = events.isNotEmpty && events.last.end();
      if (track < current) fail('out of order');
      if (track > current && (!end || track > current + 1)) fail('missing end of track');
      if (track == current && end) fail('event after end of track');
      if (track == current + 1) { current++; events = []; tracks.add(events); }
      if (events.isNotEmpty && e.tick < events.last.tick) fail('out of order');
      events.add(e);
    } on Failure catch (error) { fail('line ${i + 1}: ${error.message}'); }
  }
  if (current + 1 < count || tracks[current].isEmpty || !tracks[current].last.end()) fail('line ${lines.length + 1}: missing end of track');
  return Song(format, division, tracks);
}
List<int> vlq(int n) {
  final result = [n & 127];
  n >>= 7;
  while (n > 0) { result.insert(0, (n & 127) | 128); n >>= 7; }
  return result;
}
void encode(Song s) {
  final List<int> result = [];
  void chunk(List<int> target, String id, List<int> data) {
    target.addAll(id.codeUnits);
    target.addAll(bytes(data.length, 4));
    target.addAll(data);
  }
  chunk(result, 'MThd', [...bytes(s.format, 2), ...bytes(s.tracks.length, 2), ...bytes(s.division, 2)]);
  for (final track in s.tracks) {
    final List<int> data = [];
    int last = 0, previous = -1;
    for (final e in track) {
      data.addAll(vlq(e.tick - last));
      last = e.tick;
      if (e.channel()) {
        int code = e.code;
        List<int> payload = e.data;
        if (zeroOff && (code >> 4) == 8) { code += 16; payload = [e.data[0], 0]; }
        if (!running || previous != code) data.add(code);
        data.addAll(payload);
        previous = code;
      } else {
        previous = -1;
        if (e.code < 256) { data.add(e.code); }
        else { data.addAll([255, e.code - 256]); }
        data.addAll(vlq(e.data.length));
        data.addAll(e.data);
      }
    }
    chunk(result, 'MTrk', data);
  }
  for (int i = 0; i < result.length; i += 16) {
    emit('${hex(i, 4)}: ${result.sublist(i, i + 16 < result.length ? i + 16 : result.length).map((b) => hex(b, 2)).join(' ')}');
  }
  emit('${result.length} bytes');
}
Pairing pairing(Song s) {
  final Map<int, Queue<Located>> queues = {};
  final List<Note> notes = [];
  final List<Located> unmatched = [];
  final events = global(s);
  for (final l in events) {
    final e = l.event;
    if (!e.on() && !e.off()) continue;
    final q = queues.putIfAbsent(e.ch() * 128 + e.data[0], () => Queue());
    if (e.on()) { q.addLast(l); }
    else if (q.isEmpty) { unmatched.add(l); }
    else { notes.add(Note(q.removeFirst(), l)); }
  }
  for (final q in queues.values) { unmatched.addAll(q); }
  final Map<Event, int> order = {for (int i = 0; i < events.length; i++) events[i].event: i};
  notes.sort((a, b) {
    int c = a.start().compareTo(b.start());
    if (c == 0) c = a.channel().compareTo(b.channel());
    if (c == 0) c = a.pitch().compareTo(b.pitch());
    return c == 0 ? order[a.on.event]!.compareTo(order[b.on.event]!) : c;
  });
  unmatched.sort((a, b) => order[a.event]!.compareTo(order[b.event]!));
  return Pairing(notes, unmatched);
}
String time(Song s, int tick) {
  int total = 0, last = 0, tempo = 500000;
  for (final l in global(s)) {
    if (l.event.tick <= tick && l.event.code == 337) {
      total += (l.event.tick - last) * tempo;
      last = l.event.tick;
      tempo = value(l.event.data);
    }
  }
  final us = (total + (tick - last) * tempo) ~/ s.division;
  return '${us ~/ 1000}.${(us % 1000).toString().padLeft(3, '0')}';
}
String bar(Song s, int tick) {
  int start = 0, number = 1, numerator = 4, beat = s.division;
  for (final l in global(s)) {
    if (l.event.tick <= tick && l.event.code == 344) {
      final length = numerator * beat;
      number += (l.event.tick - start + length - 1) ~/ length;
      start = l.event.tick;
      numerator = l.event.data[0];
      beat = s.division * 4 ~/ (1 << l.event.data[1]);
    }
  }
  final x = tick - start, length = numerator * beat;
  return '${number + x ~/ length}:${x % length ~/ beat + 1}:${x % beat}';
}
void printNotes(Pairing p) {
  emit('notes ${p.notes.length} unmatched ${p.unmatched.length}');
  for (final n in p.notes) { emit('${n.start()} ${n.length()} ${n.channel()} ${noteName(n.pitch())} ${n.on.event.data[1]}'); }
  for (final l in p.unmatched) { emit('unmatched ${l.event.on() ? 'on' : 'off'} ${l.event.tick} ${l.track} ${l.event.ch()} ${noteName(l.event.data[0])}'); }
}
bool range(int n, int low, int high) => n >= low && n <= high;
int floorDiv(int n, int d) => n >= 0 ? n ~/ d : -((-n + d - 1) ~/ d);
void execute(List<String> w) {
  final c = w[0];
  if (c == 'HEX' || c == 'TEXT') {
    final lines = List.generate(int.parse(w[2]), (_) => stdin.readLineSync()!);
    final s = c == 'TEXT' ? textSong(lines) : Parser(lines.expand((line) => line.split(' ').map((b) => int.parse(b, radix: 16))).toList()).parse();
    songs[w[1]] = s;
    emit('loaded ${w[1]} ${description(s)}');
    return;
  }
  if (!['DECODE', 'ENCODE', 'TIMING', 'NOTES', 'STATS', 'ROLL', 'TRANSPOSE', 'QUANTIZE', 'VELOCITY', 'TEMPO', 'FILTER', 'MERGE', 'SPLIT', 'COPY', 'LIST', 'RUNNING', 'NOTEOFF'].contains(c)) fail('unknown command');
  if (c == 'LIST') {
    if (songs.isEmpty) { emit('no songs'); }
    else { for (final entry in songs.entries) { emit('${entry.key} ${description(entry.value)}'); } }
    return;
  }
  if (c == 'RUNNING' || c == 'NOTEOFF') {
    if (!(c == 'RUNNING' ? ['ON', 'OFF'] : ['ZERO', 'KEEP']).contains(w[1])) fail('bad argument');
    if (c == 'RUNNING') { running = w[1] == 'ON'; }
    else { zeroOff = w[1] == 'ZERO'; }
    emit('${c.toLowerCase()} ${w[1].toLowerCase()}');
    return;
  }
  final s = songs[w[1]];
  if (s == null) fail('no song ${w[1]}');
  int a = 0, b = 0, d = 0;
  if (['TRANSPOSE', 'QUANTIZE', 'VELOCITY', 'TEMPO', 'ROLL'].contains(c)) {
    a = int.parse(w[2]);
    if (w.length > 3) b = int.parse(w[3]);
    if (c == 'ROLL') d = int.parse(w[4]);
    final valid = switch (c) {
      'TRANSPOSE' => range(a, -127, 127) && (w.length == 3 || range(b, 1, 16)),
      'QUANTIZE' => range(a, 1, 1000000) && range(b, 0, 100),
      'VELOCITY' => range(a, 0, 1000) && range(b, -127, 127),
      'TEMPO' => range(a, 1, 1000) && range(b, 1, 1000),
      _ => range(a, 0, 10000000) && range(b, 1, 10000000) && range(d, 1, 10000000) && b > a && (b - a + d - 1) ~/ d <= 64,
    };
    if (!valid) fail('bad argument');
  }
  if (c == 'FILTER' && w.skip(2).any((v) => !range(int.parse(v), 1, 16))) fail('bad argument');
  if ((c == 'TIMING' || c == 'STATS') && s.format == 2) fail('format 2 not supported');
  switch (c) {
    case 'COPY': {
      songs[w[2]] = s.copy();
      emit('copied ${w[1]} to ${w[2]}');
    }
    case 'DECODE': {
      emit('HEADER ${s.format} ${s.tracks.length} ${s.division}');
      for (int t = 0; t < s.tracks.length; t++) { for (final e in s.tracks[t]) { emit(eventText(e, t)); } }
    }
    case 'ENCODE': {
      encode(s);
    }
    case 'TIMING': {
      for (final l in global(s)) { emit('${l.event.tick} ${l.track} ${l.event.kind()} ${time(s, l.event.tick)} ${bar(s, l.event.tick)}'); }
      emit('end ${s.length()} ${time(s, s.length())} ${bar(s, s.length())}');
    }
    case 'NOTES': {
      printNotes(pairing(s));
    }
    case 'TRANSPOSE': {
      int kept = 0;
      final List<String> removed = [];
      for (int t = 0; t < s.tracks.length; t++) {
        final List<Event> track = [];
        for (final e in s.tracks[t]) {
          if (e.channel() && (e.code >> 4) <= 10 && (w.length == 3 || e.ch() == b)) {
            final original = e.data[0], pitch = e.data[0] + a;
            if (!range(pitch, 0, 127)) {
              removed.add('dropped ${e.tick} $t ${e.kind()} ${e.ch()} ${noteName(original)}');
              continue;
            }
            e.data[0] = pitch;
            kept++;
          }
          track.add(e);
        }
        s.tracks[t] = track;
      }
      emit('transposed $kept dropped ${removed.length}');
      for (final line in removed) { emit(line); }
    }
    case 'QUANTIZE': {
      final p = pairing(s);
      final targets = [...p.notes, ...p.unmatched.where((l) => l.event.on()).map((l) => Note(l, l))];
      int moved = 0;
      for (final n in targets) {
        final tick = n.start(), lower = n.start() ~/ a * a;
        final g = tick - lower <= lower + a - tick ? lower : lower + a;
        final delta = floorDiv(2 * (g - tick) * b + 100, 200);
        n.on.event.tick += delta;
        if (!identical(n.off.event, n.on.event)) n.off.event.tick += delta;
        if (delta != 0) moved++;
      }
      for (final track in s.tracks) {
        final end = track.removeLast();
        final Map<Event, int> order = {for (int i = 0; i < track.length; i++) track[i]: i};
        track.sort((a, b) { final c = a.tick.compareTo(b.tick); return c == 0 ? order[a]!.compareTo(order[b]!) : c; });
        for (final e in track) { if (e.tick > end.tick) end.tick = e.tick; }
        track.add(end);
      }
      emit('quantized ${targets.length} moved $moved');
    }
    case 'VELOCITY': {
      int count = 0, clamped = 0;
      for (final l in global(s)) {
        if (l.event.on()) {
          final v = (l.event.data[1] * a + 50) ~/ 100 + b;
          if (!range(v, 1, 127)) clamped++;
          l.event.data[1] = v < 1 ? 1 : v > 127 ? 127 : v;
          count++;
        }
      }
      emit('velocity $count clamped $clamped');
    }
    case 'TEMPO': {
      final edited = s.copy();
      int count = 0;
      bool atZero = false;
      for (final l in global(edited)) {
        if (l.event.code == 337) {
          final v = (2 * value(l.event.data) * b + a) ~/ (2 * a);
          if (!range(v, 1, 16777215)) fail('tempo out of range');
          l.event.data = bytes(v, 3);
          count++;
          if (l.event.tick == 0) atZero = true;
        }
      }
      final inserted = (1000000 * b + a) ~/ (2 * a);
      if (!atZero) {
        if (!range(inserted, 1, 16777215)) fail('tempo out of range');
        edited.tracks[0].insert(0, Event(0, 337, bytes(inserted, 3)));
      }
      songs[w[1]] = edited;
      emit('scaled $count');
      if (!atZero) emit('inserted 0 0 TEMPO $inserted');
    }
    case 'FILTER': {
      final channels = w.skip(2).map(int.parse).toSet(), before = s.count();
      for (final track in s.tracks) { track.removeWhere((e) => e.channel() && !channels.contains(e.ch())); }
      emit('removed ${before - s.count()}');
    }
    case 'MERGE': {
      if (s.format != 1) fail('not format 1');
      final original = s.tracks.length, length = s.length();
      final events = global(s).where((l) => !l.event.end()).map((l) => l.event).toList();
      events.add(Event(length, 303, []));
      s.tracks = [events];
      s.format = 0;
      emit('merged $original tracks events ${s.count()}');
    }
    case 'SPLIT': {
      if (s.format != 0) fail('not format 0');
      final length = s.length();
      final SplayTreeMap<int, List<Event>> groups = SplayTreeMap();
      groups[0] = [];
      for (final e in s.tracks[0]) {
        if (!e.end()) groups.putIfAbsent(e.channel() ? e.ch() : 0, () => []).add(e);
      }
      s.tracks = groups.values.toList();
      for (final track in s.tracks) { track.add(Event(length, 303, [])); }
      s.format = 1;
      emit('split tracks ${s.tracks.length} events ${s.count()}');
    }
    case 'STATS': {
      final p = pairing(s);
      emit(description(s));
      emit('notes ${p.notes.length} unmatched ${p.unmatched.length}');
      for (int ch = 1; ch <= 16; ch++) {
        final notes = p.notes.where((n) => n.channel() == ch).toList();
        if (notes.isNotEmpty) {
          final ps = notes.map((n) => n.pitch()).toList()..sort();
          emit('channel $ch notes ${notes.length} range ${noteName(ps.first)} ${noteName(ps.last)}');
        }
      }
      final ps = p.notes.map((n) => n.pitch()).toList()..sort();
      emit(ps.isEmpty ? 'range none' : 'range ${noteName(ps.first)} ${noteName(ps.last)}');
      emit('length ${s.length()} ticks ${time(s, s.length())} ms');
      final SplayTreeMap<int, int> changes = SplayTreeMap();
      for (final n in p.notes) {
        if (n.length() > 0) {
          changes[n.start()] = (changes[n.start()] ?? 0) + 1;
          final end = n.start() + n.length();
          changes[end] = (changes[end] ?? 0) - 1;
        }
      }
      int active = 0, maximum = 0, first = 0;
      for (final entry in changes.entries) {
        active += entry.value;
        if (active > maximum) { maximum = active; first = entry.key; }
      }
      emit(maximum == 0 ? 'polyphony 0' : 'polyphony $maximum at $first');
    }
    case 'ROLL': {
      final p = pairing(s), columns = (b - a + d - 1) ~/ d;
      bool any = false;
      for (int pitch = 127; pitch >= 0; pitch--) {
        final line = StringBuffer();
        bool visible = false;
        final notes = p.notes.where((n) => n.pitch() == pitch).toList();
        for (int i = 0; i < columns; i++) {
          final tick = a + i * d;
          final mark = notes.any((n) => tick <= n.start() && n.start() < tick + d) ? '#'
              : notes.any((n) => n.start() <= tick && tick < n.start() + n.length()) ? '=' : '.';
          line.write(mark);
          if (mark != '.') visible = true;
        }
        if (visible) { emit('${noteName(pitch).padRight(4)} $line'); any = true; }
      }
      if (!any) emit('empty');
    }
  }
}
void main() {
  final n = int.parse(stdin.readLineSync()!);
  for (int i = 0; i < n; i++) {
    final words = stdin.readLineSync()!.split(' ');
    try { execute(words); }
    on Failure catch (error) { emit('error: ${error.message}'); }
  }
  stdout.write(output);
}
