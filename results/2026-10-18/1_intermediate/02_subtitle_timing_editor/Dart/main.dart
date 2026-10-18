import 'dart:io';

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

Never badArguments() => throw CommandError('bad arguments');

int? unsigned(String text, [int limit = 9]) {
  if (text.isEmpty || text.length > limit ||
      text.codeUnits.any((c) => c < 48 || c > 57)) return null;
  return int.parse(text);
}

int? timeValue(String text) {
  if (text.length != 12 || text[2] != ':' || text[5] != ':' ||
      text[8] != ',') return null;
  final h = unsigned(text.substring(0, 2));
  final m = unsigned(text.substring(3, 5));
  final s = unsigned(text.substring(6, 8));
  final ms = unsigned(text.substring(9));
  if (h == null || m == null || s == null || ms == null || m > 59 || s > 59) return null;
  return h * 3600000 + m * 60000 + s * 1000 + ms;
}

int floorDiv(int a, int b) {
  final q = a ~/ b;
  return a % b == 0 || a >= 0 ? q : q - 1;
}

int roundRatio(int a, int b) {
  if (b < 0) { a = -a; b = -b; }
  return floorDiv(2 * a + b, 2 * b);
}

String padded(int n, int width) => n.toString().padLeft(width, '0');
String timeText(int t, [bool vtt = false]) =>
    '${padded(t ~/ 3600000, 2)}:${padded(t ~/ 60000 % 60, 2)}:'
    '${padded(t ~/ 1000 % 60, 2)}${vtt ? '.' : ','}${padded(t % 1000, 3)}';
String assTime(int t) {
  final c = (t + 5) ~/ 10;
  return '${c ~/ 360000}:${padded(c ~/ 6000 % 60, 2)}:'
      '${padded(c ~/ 100 % 60, 2)}.${padded(c % 100, 2)}';
}
String decimal(int v) => '${v ~/ 100}.${padded(v % 100, 2)}';

class Cue {
  int index, start, end;
  List<String> text;
  Cue(this.index, this.start, this.end, this.text);
  Cue copy() => Cue(index, start, end, List.of(text));
  int get duration => end - start;
  int get characters => text.fold(0, (sum, s) => sum + s.length);
  bool get dialogue => text.any((s) => s.startsWith('- '));
}

List<String> words(List<String> lines) =>
    lines.expand((s) => s.split(' ')).where((s) => s.isNotEmpty).toList();
List<String> wrap(List<String> lines, int width) {
  final result = <String>[];
  for (final word in words(lines)) {
    if (result.isNotEmpty && result.last.length + 1 + word.length <= width) {
      result[result.length - 1] += ' $word';
    } else {
      result.add(word);
    }
  }
  return result;
}
bool sameLines(List<String> a, List<String> b) =>
    a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
String normalized(String s) => s.split(' ').where((w) => w.isNotEmpty).join(' ');

const formatTags = ['<i>', '</i>', '<b>', '</b>', '<u>', '</u>'];
const assTags = [r'{\i1}', r'{\i0}', r'{\b1}', r'{\b0}', r'{\u1}', r'{\u0}'];
// kind: 0 format, 1 font, 2 position, 3 ordinary; detail: format index/code.
(int, int, int) markup(String line, int p) {
  for (var i = 0; i < formatTags.length; i++) {
    if (line.startsWith(formatTags[i], p)) return (formatTags[i].length, 0, i);
  }
  if (line.startsWith('</font>', p)) return (7, 1, 0);
  if (line.startsWith('<font', p) && p + 5 < line.length &&
      (line[p + 5] == ' ' || line[p + 5] == '>')) {
    final end = line.indexOf('>', p + 5);
    if (end >= 0) return (end - p + 1, 1, 0);
  }
  if (p + 6 <= line.length && line.startsWith(r'{\an', p) &&
      line.codeUnitAt(p + 4) >= 49 && line.codeUnitAt(p + 4) <= 57 && line[p + 5] == '}') {
    return (6, 2, line.codeUnitAt(p + 4) - 48);
  }
  return (1, 3, 0);
}

class Command {
  final String name;
  final List<Object> args;
  Command(this.name, this.args);
  int number(int i) => args[i] as int;
  String string(int i) => args[i] as String;
  List<String> lines(int i) => args[i] as List<String>;
  (int, int) rate(int i) => args[i] as (int, int);
}

const schemas = <String, List<String>>{
  'LIST': [], 'VALIDATE': [], 'SEARCH': ['string'], 'AT': ['time'],
  'GAPS': ['gap'], 'STATS': [], 'PRINT': [], 'TOVTT': [], 'TOASS': [],
  'FRAMES': ['fps'], 'SHIFT': ['signed'], 'SHIFTFROM': ['position', 'signed'],
  'SCALE': ['scale', 'scale'], 'SYNC': ['position', 'time', 'position', 'time'],
  'SNAP': ['fps'], 'FIXOVERLAP': ['gap'], 'EXTEND': ['minimum'],
  'TIME': ['position', 'time', 'time'], 'SORT': [], 'RENUMBER': [],
  'MERGE': ['gap'], 'SPLIT': ['width'], 'INSERT': ['position', 'time', 'time', 'text'],
  'DELETE': ['position'], 'TEXT': ['position', 'text'], 'BALANCE': [],
  'STRIP': [], 'CLEANHI': [], 'REPLACE': ['replacement'], 'UNDO': [],
};
const modifying = ['SHIFT', 'SHIFTFROM', 'SCALE', 'SYNC', 'SNAP', 'FIXOVERLAP',
  'EXTEND', 'TIME', 'SORT', 'RENUMBER', 'MERGE', 'SPLIT', 'INSERT', 'DELETE',
  'TEXT', 'BALANCE', 'STRIP', 'CLEANHI', 'REPLACE'];

Command parseCommand(String line, int cueCount) {
  final parts = line.split(' '), name = parts.first;
  if (!schemas.containsKey(name)) throw CommandError('unknown command');
  final schema = List<String>.of(schemas[name]!);
  if (name == 'DELETE' && parts.length == 3) schema.add('position');
  final stringLast = schema.isNotEmpty &&
      ['string', 'text', 'replacement'].contains(schema.last);
  if (parts.length < schema.length + 1 ||
      (!stringLast && parts.length != schema.length + 1)) badArguments();
  final raw = parts.skip(1).toList();
  if (stringLast) {
    final joined = raw.skip(schema.length - 1).join(' ');
    raw.removeRange(schema.length - 1, raw.length);
    raw.add(joined);
  }
  final values = <Object>[];
  for (var i = 0; i < schema.length; i++) {
    final type = schema[i], s = raw[i];
    if (type == 'string') { values.add(s); continue; }
    if (type == 'text' || type == 'replacement') {
      final lines = s.split('|');
      if (lines.any((l) => l.isEmpty) || type == 'replacement' && lines.length != 2) badArguments();
      values.add(lines);
      continue;
    }
    if (type == 'fps') {
      final rate = s.split('/');
      if (rate.length > 2) badArguments();
      final a = unsigned(rate[0]), b = rate.length == 1 ? 1 : unsigned(rate[1]);
      if (a == null || b == null || a < 1 || a > 100000 || b < 1 || b > 100000) badArguments();
      values.add((a, b));
      continue;
    }
    int? value;
    if (type == 'time') {
      value = timeValue(s);
    } else if (type == 'signed' && s.startsWith('-')) {
      final magnitude = unsigned(s.substring(1));
      value = magnitude == null ? null : -magnitude;
    } else {
      value = unsigned(s);
    }
    if (value == null) badArguments();
    if (type == 'position' && value < 1 ||
        type == 'gap' && value > 60000 ||
        type == 'minimum' && (value < 1 || value > 60000) ||
        type == 'scale' && (value < 1 || value > 100000) ||
        type == 'width' && (value < 10 || value > 80)) badArguments();
    values.add(value);
  }
  final command = Command(name, values);
  if (name == 'DELETE' && values.length == 2 && command.number(1) < command.number(0)) badArguments();
  for (var i = 0; i < schema.length; i++) {
    if (schema[i] == 'position' && command.number(i) > cueCount + (name == 'INSERT' ? 1 : 0)) {
      throw CommandError('no cue ${command.number(i)}');
    }
  }
  return command;
}

class Editor {
  List<Cue> cues = [];
  final history = <(String, List<Cue>)>[];
  int blocks = 0, bad = 0;
  void load(List<String> block, StringBuffer out) {
    if (block.isEmpty) return;
    blocks++;
    String? problem;
    final index = unsigned(block[0], 6);
    int? start, end;
    if (index == null) {
      problem = 'index';
    } else if (block.length < 2 || block[1].length != 29 || block[1].substring(12, 17) != ' --> ') {
      problem = 'time';
    } else {
      start = timeValue(block[1].substring(0, 12));
      end = timeValue(block[1].substring(17));
      if (start == null || end == null) problem = 'time';
      else if (block.length < 3) problem = 'no text';
    }
    if (problem != null) {
      bad++;
      out.writeln('BAD CUE $blocks: $problem');
    } else {
      cues.add(Cue(index!, start!, end!, block.skip(2).toList()));
    }
  }
  void listCue(StringBuffer out, int i) {
    final c = cues[i];
    out.writeln('${i + 1} ${c.index} ${timeText(c.start)} ${timeText(c.end)} ${c.text.join('|')}');
  }
  String execute(String line) {
    final command = parseCommand(line, cues.length), op = command.name;
    int n(int i) => command.number(i);
    if (op == 'SYNC' && cues[n(0) - 1].start == cues[n(2) - 1].start) {
      throw CommandError('sync points coincide');
    }
    if (op == 'UNDO') {
      if (history.isEmpty) throw CommandError('nothing to undo');
      final entry = history.removeLast();
      cues = entry.$2;
      return 'UNDO command=${entry.$1}\n';
    }
    if (modifying.contains(op)) history.add((op, cues.map((c) => c.copy()).toList()));
    final out = StringBuffer();
    switch (op) {
      case 'LIST':
        for (var i = 0; i < cues.length; i++) listCue(out, i);
      case 'VALIDATE':
        var problems = 0;
        void problem(String s) { out.writeln(s); problems++; }
        for (var i = 0; i < cues.length; i++) {
          final c = cues[i], p = i + 1, d = c.duration;
          if (c.index != p) problem('cue $p: index ${c.index} (expected $p)');
          if (d <= 0) problem('cue $p: end not after start');
          if (i > 0 && c.start < cues[i - 1].end) problem('cue $p: overlaps previous by ${cues[i - 1].end - c.start} ms');
          if (d >= 1 && d < 700) problem('cue $p: too short ($d ms)');
          if (d > 7000) problem('cue $p: too long ($d ms)');
          for (var j = 0; j < c.text.length; j++) {
            if (c.text[j].length > 42) problem('cue $p: line ${j + 1} too long (${c.text[j].length} chars)');
          }
          if (c.text.length >= 3) problem('cue $p: too many lines (${c.text.length})');
          if (d > 0 && c.characters * 1000 > 21 * d) problem('cue $p: too fast (${decimal(c.characters * 100000 ~/ d)} cps)');
        }
        out.writeln('VALIDATE problems=$problems');
      case 'SEARCH':
        var found = 0;
        for (var i = 0; i < cues.length; i++) {
          final matches = cues[i].text.where((s) => s.contains(command.string(0)));
          if (matches.isNotEmpty) {
            out.writeln('${i + 1} ${timeText(cues[i].start)} ${matches.first}');
            found++;
          }
        }
        out.writeln('SEARCH found=$found');
      case 'AT':
        var active = 0;
        for (var i = 0; i < cues.length; i++) {
          if (cues[i].start <= n(0) && n(0) < cues[i].end) { listCue(out, i); active++; }
        }
        out.writeln('AT active=$active');
      case 'GAPS':
        var count = 0;
        for (var i = 0; i + 1 < cues.length; i++) {
          final gap = cues[i + 1].start - cues[i].end;
          if (gap < n(0)) { out.writeln('${i + 1} ${i + 2} $gap'); count++; }
        }
        out.writeln('GAPS count=$count');
      case 'STATS':
        out.writeln('STATS cues=${cues.length}');
        if (cues.isNotEmpty) {
          var total = 0, chars = 0, longest = 0, maximum = -1;
          for (var i = 0; i < cues.length; i++) {
            final d = cues[i].duration < 0 ? 0 : cues[i].duration;
            total += d;
            if (d > 0) chars += cues[i].characters;
            if (d > maximum) { maximum = d; longest = i; }
          }
          out.writeln('duration total=${timeText(total)} mean=${timeText(total ~/ cues.length)}');
          out.writeln('speed ${total == 0 ? '-' : decimal(chars * 100000 ~/ total)}');
          out.writeln('longest cue=${longest + 1} duration=${timeText(maximum)}');
          if (cues.length == 1) out.writeln('gap none');
          else {
            var position = 0, gap = cues[1].start - cues[0].end;
            for (var i = 1; i + 1 < cues.length; i++) {
              final candidate = cues[i + 1].start - cues[i].end;
              if (candidate > gap) { gap = candidate; position = i; }
            }
            out.writeln('gap cue=${position + 1} ms=$gap');
          }
        }
      case 'PRINT':
        for (final c in cues) {
          out.writeln(c.index);
          out.writeln('${timeText(c.start)} --> ${timeText(c.end)}');
          for (final s in c.text) out.writeln(s);
          out.writeln();
        }
      case 'TOVTT':
        out.write('WEBVTT\n\n');
        for (final c in cues) {
          final lines = <String>[];
          var code = 0;
          for (final s in c.text) {
            final converted = StringBuffer();
            for (var p = 0; p < s.length;) {
              final item = markup(s, p);
              if (item.$2 == 2 && code == 0) code = item.$3;
              if (item.$2 == 0) converted.write(s.substring(p, p + item.$1));
              if (item.$2 == 3) converted.write(s[p] == '&' ? '&amp;' : s[p] == '<' ? '&lt;' : s[p] == '>' ? '&gt;' : s[p]);
              p += item.$1;
            }
            final text = converted.toString().trim();
            if (text.isNotEmpty) lines.add(text);
          }
          if (lines.isEmpty) continue;
          var settings = code >= 7 ? ' line:0' : code >= 4 ? ' line:50%' : '';
          if ([1, 4, 7].contains(code)) settings += ' align:start';
          if ([3, 6, 9].contains(code)) settings += ' align:end';
          out.writeln(c.index);
          out.writeln('${timeText(c.start, true)} --> ${timeText(c.end, true)}$settings');
          for (final text in lines) out.writeln(text);
          out.writeln();
        }
      case 'TOASS':
        out.writeln('[Events]');
        out.writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');
        for (final c in cues) {
          final lines = <String>[];
          for (final s in c.text) {
            final converted = StringBuffer();
            for (var p = 0; p < s.length;) {
              final item = markup(s, p);
              if (item.$2 == 0) converted.write(assTags[item.$3]);
              else if (item.$2 != 1) converted.write(s.substring(p, p + item.$1));
              p += item.$1;
            }
            lines.add(converted.toString());
          }
          out.writeln('Dialogue: 0,${assTime(c.start)},${assTime(c.end)},Default,,0,0,0,,${lines.join(r'\N')}');
        }
      case 'FRAMES':
        final rate = command.rate(0);
        for (var i = 0; i < cues.length; i++) out.writeln('${i + 1} ${cues[i].start * rate.$1 ~/ (1000 * rate.$2)} ${cues[i].end * rate.$1 ~/ (1000 * rate.$2)}');
      case 'SHIFT' || 'SHIFTFROM' || 'SCALE' || 'SYNC' || 'SNAP':
        final first = op == 'SHIFTFROM' ? n(0) - 1 : 0;
        var clamped = 0, changed = 0;
        final s1 = op == 'SYNC' ? cues[n(0) - 1].start : 0;
        final s2 = op == 'SYNC' ? cues[n(2) - 1].start : 0;
        for (var i = first; i < cues.length; i++) {
          final c = cues[i], before = [c.start, c.end], after = <int>[];
          var clamp = false;
          for (final t in before) {
            int value;
            if (op == 'SCALE') value = roundRatio(t * n(0), n(1));
            else if (op == 'SYNC') value = roundRatio(n(1) * (s2 - s1) + (t - s1) * (n(3) - n(1)), s2 - s1);
            else if (op == 'SNAP') {
              final rate = command.rate(0);
              final f = roundRatio(t * rate.$1, 1000 * rate.$2);
              value = roundRatio(f * 1000 * rate.$2, rate.$1);
            } else value = t + n(op == 'SHIFT' ? 0 : 1);
            if (value < 0) { value = 0; clamp = true; }
            if (value != t) changed++;
            after.add(value);
          }
          c.start = after[0]; c.end = after[1];
          if (clamp) clamped++;
        }
        if (op == 'SNAP') out.writeln('SNAP changed=$changed');
        else if (op == 'SCALE') out.writeln('SCALE cues=${cues.length}');
        else out.writeln('$op cues=${cues.length - first} clamped=$clamped');
      case 'FIXOVERLAP':
        var fixed = 0, failed = 0;
        for (var i = 0; i + 1 < cues.length; i++) {
          final candidate = cues[i + 1].start - n(0);
          if (cues[i].end > candidate) {
            if (candidate > cues[i].start) { cues[i].end = candidate; fixed++; }
            else { out.writeln('cue ${i + 1}: cannot fix'); failed++; }
          }
        }
        out.writeln('FIXOVERLAP fixed=$fixed failed=$failed');
      case 'EXTEND':
        var extended = 0, short = 0;
        for (var i = 0; i < cues.length; i++) {
          final c = cues[i];
          if (c.duration < n(0)) {
            var candidate = c.start + n(0);
            if (i + 1 < cues.length && cues[i + 1].start < candidate) candidate = cues[i + 1].start;
            if (candidate > c.end) { c.end = candidate; extended++; }
          }
          if (c.duration < n(0)) short++;
        }
        out.writeln('EXTEND extended=$extended short=$short');
      case 'TIME':
        cues[n(0) - 1].start = n(1); cues[n(0) - 1].end = n(2);
        out.writeln('TIME cue=${n(0)}');
      case 'SORT':
        final ordered = [for (var i = 0; i < cues.length; i++) (cues[i], i)];
        ordered.sort((a, b) {
          final start = a.$1.start.compareTo(b.$1.start), end = a.$1.end.compareTo(b.$1.end);
          return start != 0 ? start : end != 0 ? end : a.$2.compareTo(b.$2);
        });
        final moved = [for (var i = 0; i < ordered.length; i++) ordered[i].$2 != i].where((x) => x).length;
        cues = ordered.map((entry) => entry.$1).toList();
        out.writeln('SORT moved=$moved');
      case 'RENUMBER':
        var changed = 0;
        for (var i = 0; i < cues.length; i++) {
          if (cues[i].index != i + 1) { cues[i].index = i + 1; changed++; }
        }
        out.writeln('RENUMBER changed=$changed');
      case 'MERGE':
        final result = <Cue>[];
        var merged = 0;
        for (final b in cues) {
          if (result.isNotEmpty) {
            final a = result.last, combined = wrap([...a.text, ...b.text], 42);
            if (b.start - a.end < n(0) && !a.dialogue && !b.dialogue && combined.length <= 2) {
              if (b.end > a.end) a.end = b.end;
              a.text = combined; merged++; continue;
            }
          }
          result.add(b);
        }
        cues = result;
        out.writeln('MERGE merged=$merged cues=${cues.length}');
      case 'SPLIT':
        final result = <Cue>[];
        var split = 0;
        for (final c in cues) {
          if (c.duration < 1 || c.dialogue) { result.add(c); continue; }
          final lines = wrap(c.text, n(0));
          if (lines.length <= 2) { c.text = lines; result.add(c); continue; }
          split++;
          final parts = [for (var i = 0; i < lines.length; i += 2) lines.sublist(i, i + 2 < lines.length ? i + 2 : lines.length)];
          final counts = parts.map((p) => p.fold(0, (s, line) => s + line.length)).toList();
          final total = counts.fold(0, (s, count) => s + count), duration = c.duration;
          final times = counts.map((count) => duration * count ~/ total).toList();
          final order = [for (var i = 0; i < counts.length; i++) i];
          order.sort((a, b) {
            final cmp = (duration * counts[b] % total).compareTo(duration * counts[a] % total);
            return cmp != 0 ? cmp : a.compareTo(b);
          });
          final remainder = duration - times.fold(0, (s, t) => s + t);
          for (var i = 0; i < remainder; i++) times[order[i]]++;
          var start = c.start;
          for (var i = 0; i < parts.length; i++) {
            result.add(Cue(c.index, start, start + times[i], parts[i]));
            start += times[i];
          }
        }
        cues = result;
        out.writeln('SPLIT split=$split cues=${cues.length}');
      case 'INSERT':
        cues.insert(n(0) - 1, Cue(n(0), n(1), n(2), command.lines(3)));
        out.writeln('INSERT cue=${n(0)} cues=${cues.length}');
      case 'DELETE':
        final end = command.args.length == 2 ? n(1) : n(0);
        cues.removeRange(n(0) - 1, end);
        out.writeln('DELETE removed=${end - n(0) + 1} cues=${cues.length}');
      case 'TEXT':
        cues[n(0) - 1].text = command.lines(1);
        out.writeln('TEXT cue=${n(0)} lines=${command.lines(1).length}');
      case 'BALANCE':
        var changed = 0, skipped = 0, dialogue = 0;
        for (final c in cues) {
          if (c.dialogue) { dialogue++; continue; }
          final ws = words(c.text), text = ws.join(' ');
          List<String>? candidate;
          if (text.length <= 42) candidate = [text];
          else {
            var bestDifference = 1000000, bestFirst = 1000000;
            for (var j = 1; j < ws.length; j++) {
              final left = ws.take(j).join(' '), right = ws.skip(j).join(' ');
              final difference = (left.length - right.length).abs();
              if (left.length <= 42 && right.length <= 42 &&
                  (difference < bestDifference || difference == bestDifference && left.length < bestFirst)) {
                bestDifference = difference; bestFirst = left.length; candidate = [left, right];
              }
            }
          }
          if (candidate == null) skipped++;
          else if (!sameLines(c.text, candidate)) { c.text = candidate; changed++; }
        }
        out.writeln('BALANCE changed=$changed skipped=$skipped dialogue=$dialogue');
      case 'STRIP' || 'CLEANHI':
        var tags = 0, segments = 0, labels = 0, removedLines = 0, removedCues = 0;
        final result = <Cue>[];
        for (final c in cues) {
          final lines = <String>[];
          for (final text in c.text) {
            final converted = StringBuffer();
            for (var p = 0; p < text.length;) {
              if (op == 'STRIP') {
                final item = markup(text, p);
                if (item.$2 == 3) converted.write(text[p]); else tags++;
                p += item.$1;
              } else {
                final close = text[p] == '[' ? ']' : text[p] == '(' ? ')' : '';
                final end = close.isEmpty ? -1 : text.indexOf(close, p + 1);
                if (end >= 0) { segments++; p = end + 1; }
                else { converted.write(text[p]); p++; }
              }
            }
            var line = op == 'STRIP' ? converted.toString().trim() : normalized(converted.toString());
            if (op == 'CLEANHI') {
              final prefix = line.startsWith('- ') ? '- ' : '', body = line.startsWith('- ') ? line.substring(2) : line;
              final colon = body.indexOf(':');
              if (colon > 0 && body.codeUnitAt(0) >= 65 && body.codeUnitAt(0) <= 90 &&
                  body.substring(0, colon).codeUnits.every((c) => c >= 65 && c <= 90 || c >= 48 && c <= 57 || c == 32)) {
                line = normalized(prefix + body.substring(colon + 1)); labels++;
              }
            }
            if (line.isEmpty || op == 'CLEANHI' && line == '-') removedLines++;
            else lines.add(line);
          }
          if (lines.isEmpty) removedCues++;
          else { c.text = lines; result.add(c); }
        }
        cues = result;
        out.writeln(op == 'STRIP' ? 'STRIP tags=$tags removed_lines=$removedLines removed_cues=$removedCues' :
            'CLEANHI segments=$segments labels=$labels removed_lines=$removedLines removed_cues=$removedCues');
      case 'REPLACE':
        final pair = command.lines(0), old = pair[0], replacement = pair[1];
        var count = 0, changedCues = 0;
        for (final c in cues) {
          var changed = false;
          for (var i = 0; i < c.text.length; i++) {
            final text = c.text[i], result = StringBuffer();
            for (var p = 0; p < text.length;) {
              if (text.startsWith(old, p)) {
                result.write(replacement); p += old.length; count++; changed = true;
              } else { result.write(text[p]); p++; }
            }
            c.text[i] = result.toString();
          }
          if (changed) changedCues++;
        }
        out.writeln('REPLACE count=$count cues=$changedCues');
    }
    return out.toString();
  }
}

void main() {
  final editor = Editor(), output = StringBuffer();
  var block = <String>[];
  while (true) {
    final line = stdin.readLineSync()!;
    if (line == '###') { editor.load(block, output); break; }
    if (line.isEmpty) { editor.load(block, output); block = []; }
    else block.add(line);
  }
  output.writeln('LOAD cues=${editor.cues.length} bad=${editor.bad}');
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try { output.write(editor.execute(line)); }
    on CommandError catch (error) { output.writeln('ERROR ${error.message}'); }
  }
  stdout.write(output);
}
