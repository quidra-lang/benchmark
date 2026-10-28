import 'dart:io';
import 'dart:math';
part 'bitstream.dart';
part 'reed_solomon.dart';
part 'matrix.dart';
part 'masking.dart';
part 'render.dart';

const levels = ['L', 'M', 'Q', 'H'];

class BlockTable {
  final int e, b1, k1, b2, k2;
  BlockTable(this.e, this.b1, this.k1, this.b2, this.k2);
  int get data => b1 * k1 + b2 * k2;
  List<int> get lengths => [for (var i = 0; i < b1 + b2; i++) i < b1 ? k1 : k2];
  int get total => data + e * (b1 + b2);
}

class Segment {
  final String mode, text;
  Segment(this.mode, this.text);
}

class Group {
  final int value, width;
  final String text;
  Group(this.value, this.width, this.text);
}

class Request {
  final String id, level, mode, version, mask, text;
  Request(this.id, this.level, this.mode, this.version, this.mask, this.text);
}

class Damage {
  final String kind;
  final List<String> args;
  Damage(this.kind, this.args);
}

class Result {
  List<String> lines = [];
  bool ok = false;
  String text = '';
  final List<int> blocks = List.filled(3, 0);
  int corrected = 0;
}

class Prepared {
  final Request request;
  final String mode, level;
  final int version, length;
  int mask = 0, terminator = 0, zeroFill = 0, pads = 0;
  final List<Segment> segments;
  final BlockTable table;
  List<int> data = [], interleaved = [];
  final List<List<int>> blocks = [];
  List<Point> placement = [];
  final Matrix matrix;
  List<List<int>> symbol = [];
  final List<Penalty> penalties = [];
  Prepared(
    this.request,
    this.mode,
    this.level,
    this.version,
    this.length,
    this.segments,
    this.table,
    this.matrix,
  );
}

int number(String s) => int.tryParse(s) ?? 0;
List<String> readLines(String path) => File(path).readAsLinesSync();
int countWidth(String mode, int v) => v == 10
    ? switch (mode) {
        'NUMERIC' => 12,
        'ALPHANUMERIC' => 11,
        _ => 16,
      }
    : switch (mode) {
        'NUMERIC' => 10,
        'ALPHANUMERIC' => 9,
        _ => 8,
      };
int dataWidth(String mode, int n) => switch (mode) {
  'NUMERIC' => 10 * (n ~/ 3) + [0, 4, 7][n % 3],
  'ALPHANUMERIC' => 11 * (n ~/ 2) + 6 * (n % 2),
  _ => 8 * n,
};
int indicator(String mode) => switch (mode) {
  'NUMERIC' => 1,
  'ALPHANUMERIC' => 2,
  _ => 4,
};
bool encodable(String mode, String c) => switch (mode) {
  'NUMERIC' => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57,
  'ALPHANUMERIC' => alphanumeric.contains(c),
  _ => true,
};
bool canEncode(String mode, String text) {
  for (var i = 0; i < text.length; i++) {
    if (!encodable(mode, text[i])) return false;
  }
  return true;
}

(List<Segment>, int) splitSegments(String mode, String text, int v) {
  if (mode != 'MIXED')
    return (
      [Segment(mode, text)],
      4 + countWidth(mode, v) + dataWidth(mode, text.length),
    );
  final n = text.length,
      cost = List.filled(n + 1, 0),
      starts = List.filled(n + 1, 0),
      chosen = List.filled(n + 1, 0),
      bad = List.generate(3, (_) => List.filled(n + 1, 0));
  for (var mu = 0; mu < 3; mu++) {
    for (var i = 0; i < n; i++) {
      bad[mu][i + 1] = bad[mu][i] + (encodable(modes[mu], text[i]) ? 0 : 1);
    }
  }
  for (var i = 1; i <= n; i++) {
    cost[i] = 1 << 30;
    for (var j = 0; j < i; j++) {
      for (var mu = 0; mu < 3; mu++) {
        if (bad[mu][i] != bad[mu][j]) continue;
        final value =
            cost[j] +
            4 +
            countWidth(modes[mu], v) +
            dataWidth(modes[mu], i - j);
        if (value < cost[i]) {
          cost[i] = value;
          starts[i] = j;
          chosen[i] = mu;
        }
      }
    }
  }
  final reversed = <Segment>[];
  var i = n;
  while (i > 0) {
    final j = starts[i];
    reversed.add(Segment(modes[chosen[i]], text.substring(j, i)));
    i = j;
  }
  return (reversed.reversed.toList(), cost[n]);
}

List<Group> groups(Segment segment) {
  final mode = segment.mode,
      text = segment.text,
      out = <Group>[],
      size = mode == 'NUMERIC'
          ? 3
          : mode == 'ALPHANUMERIC'
          ? 2
          : 1;
  for (var start = 0; start < text.length; start += size) {
    final part = text.substring(start, min(start + size, text.length)),
        width = dataWidth(mode, part.length);
    var value = 0;
    switch (mode) {
      case 'NUMERIC':
        value = number(part);
        break;
      case 'ALPHANUMERIC':
        value = alphanumeric.indexOf(part[0]);
        if (part.length == 2)
          value = 45 * value + alphanumeric.indexOf(part[1]);
        break;
      default:
        value = part.codeUnitAt(0);
    }
    out.add(Group(value, width, part));
  }
  return out;
}

(List<int>, int, int, int) padding(List<int> prefix, int capacity) {
  final out = List<int>.of(prefix),
      terminator = min(4, capacity - prefix.length);
  out.addAll(List.filled(terminator, 0));
  final zeroFill = (8 - out.length % 8) % 8;
  out.addAll(List.filled(zeroFill, 0));
  var pads = 0;
  final b = Bits(out);
  while (b.values.length < capacity) {
    b.append(pads % 2 == 0 ? 0xec : 0x11, 8);
    pads++;
  }
  return (b.values, terminator, zeroFill, pads);
}

List<Point> placementOrder(List<int> lengths, int e) {
  final out = <Point>[];
  var maximum = 0;
  for (final k in lengths) {
    maximum = max(maximum, k);
  }
  for (var i = 0; i < maximum; i++) {
    for (var b = 0; b < lengths.length; b++) {
      if (i < lengths[b]) out.add((b, i));
    }
  }
  for (var i = 0; i < e; i++) {
    for (var b = 0; b < lengths.length; b++) {
      out.add((b, lengths[b] + i));
    }
  }
  return out;
}

int hamming(int a) {
  var n = 0;
  while (a != 0) {
    a &= a - 1;
    n++;
  }
  return n;
}

class QR {
  final Map<int, Map<String, BlockTable>> tables = {};
  final Map<int, List<int>> alignment = {};
  final field = Field();
  int quiet = 0, scale = 1;
  final List<Request> requests = [];
  final Map<String, List<Damage>> damage = {};
  final List<String> codes = [],
      codewords = [],
      bitstream = [],
      selfcheck = [],
      scans = [],
      capacity = [];
  final Map<String, int> errorKinds = {},
      modeCounts = {},
      levelCounts = {},
      checkCounts = {};
  final versions = List.filled(11, 0),
      masks = List.filled(8, 0),
      blockCounts = List.filled(3, 0);
  int valid = 0,
      boosted = 0,
      segments = 0,
      dataCount = 0,
      ecCount = 0,
      modules = 0,
      dark = 0,
      checks = 0,
      corrected = 0,
      scanCount = 0,
      scanOK = 0;
  BlockTable tableAt(int v, String level) => tables[v]![level]!;
  (Prepared?, String) prepare(Request r) {
    if (!['L', 'M', 'Q', 'H', 'L+', 'M+', 'Q+', 'H+'].contains(r.level))
      return (null, 'level ${r.level}');
    if (![...modes, 'AUTO', 'MIXED'].contains(r.mode))
      return (null, 'mode ${r.mode}');
    if (r.version != 'AUTO' &&
        (number(r.version) < 1 ||
            number(r.version) > 10 ||
            '${number(r.version)}' != r.version))
      return (null, 'version ${r.version}');
    if (r.mask != 'AUTO' &&
        (r.mask.length != 1 ||
            r.mask.codeUnitAt(0) < 48 ||
            r.mask.codeUnitAt(0) > 55))
      return (null, 'mask ${r.mask}');
    if (r.text.isEmpty) return (null, 'text');
    if (r.mode == 'NUMERIC' || r.mode == 'ALPHANUMERIC') {
      for (var i = 0; i < r.text.length; i++) {
        if (!encodable(r.mode, r.text[i])) return (null, 'charset position $i');
      }
    }
    var mode = r.mode;
    if (mode == 'AUTO') {
      for (final candidate in modes) {
        if (canEncode(candidate, r.text)) {
          mode = candidate;
          break;
        }
      }
    }
    final base = r.level[0];
    final (segments1, bits1) = splitSegments(mode, r.text, 1);
    final (segments10, bits10) = splitSegments(mode, r.text, 10);
    (List<Segment>, int) segmentsAt(int v) =>
        v == 10 ? (segments10, bits10) : (segments1, bits1);
    var version = number(r.version);
    if (r.version == 'AUTO') {
      for (var v = 1; v <= 10; v++) {
        if (segmentsAt(v).$2 <= 8 * tableAt(v, base).data) {
          version = v;
          break;
        }
      }
      if (version == 0)
        return (
          null,
          'capacity bits $bits10 capacity ${8 * tableAt(10, base).data}',
        );
    }
    final (segments, length) = segmentsAt(version);
    if (length > 8 * tableAt(version, base).data)
      return (
        null,
        'capacity bits $length capacity ${8 * tableAt(version, base).data}',
      );
    var level = base;
    if (r.level.length == 2) {
      for (final candidate in levels) {
        if (levels.indexOf(candidate) >= levels.indexOf(base) &&
            length <= 8 * tableAt(version, candidate).data)
          level = candidate;
      }
    }
    final table = tableAt(version, level),
        p = Prepared(
          r,
          mode,
          level,
          version,
          length,
          segments,
          table,
          makeMatrix(version, alignment[version] ?? []),
        ),
        b = Bits();
    for (final seg in segments) {
      b.append(indicator(seg.mode), 4);
      b.append(seg.text.length, countWidth(seg.mode, version));
      for (final group in groups(seg)) {
        b.append(group.value, group.width);
      }
    }
    final (padded, t, z, pads) = padding(b.values, 8 * table.data);
    p.terminator = t;
    p.zeroFill = z;
    p.pads = pads;
    p.data = wordsFromBits(padded);
    var at = 0;
    final lengths = table.lengths;
    for (final k in lengths) {
      final data = p.data.sublist(at, at + k);
      p.blocks.add([...data, ...field.encode(data, table.e)]);
      at += k;
    }
    p.placement = placementOrder(lengths, table.e);
    p.interleaved = [
      for (final position in p.placement) p.blocks[position.$1][position.$2],
    ];
    final stream = bitsFromWords(p.interleaved);
    for (var j = 0; j < p.matrix.order.length; j++) {
      final position = p.matrix.order[j];
      if (j < stream.length)
        p.matrix.values[position.$2][position.$1] = stream[j];
    }
    final (f1, f2) = formatPositions(17 + 4 * version);
    final symbols = <List<List<int>>>[];
    for (var mask = 0; mask < 8; mask++) {
      final symbol = applyMask(p.matrix.values, p.matrix.areas, mask),
          f = formatInformation(level, mask);
      writeInformation(symbol, f1, f);
      writeInformation(symbol, f2, f);
      symbols.add(symbol);
      p.penalties.add(penalty(symbol));
    }
    var mask = number(r.mask);
    if (r.mask == 'AUTO') {
      for (var m = 1; m < 8; m++) {
        if (p.penalties[m].total < p.penalties[mask].total) mask = m;
      }
    }
    p.mask = mask;
    p.symbol = symbols[mask];
    return (p, '');
  }

  Result attempt(List<List<int>> a) {
    final out = Result(), n = a.length, v = (a.length - 17) ~/ 4;
    final (f1, f2) = formatPositions(n);
    final f = readInformation(a, f1), g = readInformation(a, f2);
    var d1 = 16, d2 = 16, level1 = '', level2 = '', mask1 = 0, mask2 = 0;
    for (final level in levels) {
      for (var mask = 0; mask < 8; mask++) {
        final information = formatInformation(level, mask),
            first = hamming(f ^ information),
            second = hamming(g ^ information);
        if (first < d1) {
          d1 = first;
          level1 = level;
          mask1 = mask;
        }
        if (second < d2) {
          d2 = second;
          level2 = level;
          mask2 = mask;
        }
      }
    }
    final distance = d2 < d1 ? d2 : d1,
        level = d2 < d1 ? level2 : level1,
        mask = d2 < d1 ? mask2 : mask1,
        text = 'format ${binary(f, 15)} ${binary(g, 15)} distance $d1 $d2';
    if (distance > 3) {
      out.lines.add('$text unreadable');
      return out;
    }
    out.lines.add('$text level $level mask $mask');
    if (v >= 7) {
      final (p1, p2) = versionPositions(n);
      final g1 = readInformation(a, p1), g2 = readInformation(a, p2);
      var e1 = 19, e2 = 19, v1 = 0, v2 = 0;
      for (var version = 7; version <= 40; version++) {
        final information = versionInformation(version),
            first = hamming(g1 ^ information),
            second = hamming(g2 ^ information);
        if (first < e1) {
          e1 = first;
          v1 = version;
        }
        if (second < e2) {
          e2 = second;
          v2 = version;
        }
      }
      final distance = e2 < e1 ? e2 : e1,
          version = e2 < e1 ? v2 : v1,
          text = 'version ${binary(g1, 18)} ${binary(g2, 18)} distance $e1 $e2';
      if (distance > 3) {
        out.lines.add('$text unreadable');
        return out;
      }
      out.lines.add('$text decoded $version');
      if (version != v) return out;
    }
    final table = tableAt(v, level),
        matrix = makeMatrix(v, alignment[v] ?? []),
        unmasked = applyMask(a, matrix.areas, mask),
        stream = [
          for (final p in matrix.order.take(8 * table.total))
            unmasked[p.$2][p.$1],
        ],
        words = wordsFromBits(stream),
        lengths = table.lengths,
        blocks = [for (final k in lengths) List.filled(k + table.e, 0)],
        order = placementOrder(lengths, table.e);
    for (var j = 0; j < order.length; j++) {
      final p = order[j];
      blocks[p.$1][p.$2] = words[j];
    }
    var failed = false;
    for (var b = 0; b < blocks.length; b++) {
      final correction = field.correct(blocks[b], table.e),
          text = 'block $b syndromes ${hexadecimal(correction.syndromes)}';
      if (!correction.ok) {
        out.lines.add('$text failed');
        out.blocks[2]++;
        failed = true;
      } else if (correction.positions.isEmpty) {
        out.lines.add('$text ok');
        out.blocks[0]++;
        blocks[b] = correction.words;
      } else {
        out.lines.add('$text corrected ${correction.positions.join(' ')}');
        out.blocks[1]++;
        out.corrected += correction.positions.length;
        blocks[b] = correction.words;
      }
    }
    if (failed) return out;
    final data = [
          for (var b = 0; b < blocks.length; b++) ...blocks[b].take(lengths[b]),
        ],
        b = Bits(bitsFromWords(data)),
        decoded = StringBuffer();
    var end = 0;
    while (b.values.length - b.position >= 4) {
      final modeBits = b.read(4);
      if (modeBits == 0) break;
      final mode = switch (modeBits) {
        1 => 'NUMERIC',
        2 => 'ALPHANUMERIC',
        4 => 'BYTE',
        _ => '',
      };
      if (mode.isEmpty) {
        out.lines.add('parse failed indicator ${binary(modeBits, 4)}');
        return out;
      }
      final cw = countWidth(mode, v);
      if (b.values.length - b.position < cw) {
        out.lines.add('parse failed length $mode');
        return out;
      }
      final k = b.read(cw);
      if (b.values.length - b.position < dataWidth(mode, k)) {
        out.lines.add('parse failed length $mode');
        return out;
      }
      final size = mode == 'NUMERIC'
          ? 3
          : mode == 'ALPHANUMERIC'
          ? 2
          : 1;
      for (var j = 0; j < k; j += size) {
        final length = min(size, k - j),
            value = b.read(dataWidth(mode, length));
        var valid = true;
        switch (mode) {
          case 'NUMERIC':
            final limit = [1, 10, 100, 1000][length];
            if (value >= limit) {
              valid = false;
            } else {
              decoded.write('$value'.padLeft(length, '0'));
            }
            break;
          case 'ALPHANUMERIC':
            if (length == 2) {
              if (value >= 2025) {
                valid = false;
              } else {
                decoded.write(alphanumeric[value ~/ 45]);
                decoded.write(alphanumeric[value % 45]);
              }
            } else if (value >= 45) {
              valid = false;
            } else {
              decoded.write(alphanumeric[value]);
            }
            break;
          case 'BYTE':
            if (value < 32 || value > 126) {
              valid = false;
            } else {
              decoded.writeCharCode(value);
            }
            break;
        }
        if (!valid) {
          out.lines.add('parse failed value $mode');
          return out;
        }
      }
      out.lines.add('segment $mode $k');
      end = b.position;
    }
    final (padded, _, _, _) = padding(
      b.values.sublist(0, end),
      b.values.length,
    );
    final equal = List.generate(
      padded.length,
      (i) => padded[i] == b.values[i],
    ).every((v) => v);
    out.lines.add(equal ? 'padding ok' : 'padding bad');
    out.text = decoded.toString();
    out.lines.add('text "${out.text}"');
    out.ok = true;
    return out;
  }

  Result decode(List<List<int>> a) {
    final n = a.length,
        corners = [(n - 7, n - 7), (n - 7, 0), (0, 0), (0, n - 7)];
    var rotation = 0, best = 50;
    for (var k = 0; k < 4; k++) {
      final c = corners[k];
      var score = 0;
      for (var y = 0; y < 7; y++) {
        for (var x = 0; x < 7; x++) {
          final expected = max((x - 3).abs(), (y - 3).abs()) == 2 ? 0 : 1;
          if (a[c.$2 + y][c.$1 + x] == expected) score++;
        }
      }
      if (score < best) {
        best = score;
        rotation = k;
      }
    }
    for (var k = 0; k < rotation; k++) {
      a = rotate(a);
    }
    var result = attempt(a), mirrored = 'no';
    if (!result.ok) {
      final second = attempt(transpose(a));
      if (second.ok) {
        result = second;
        mirrored = 'yes';
      }
    }
    result.lines = [
      'orientation rotations $rotation mirrored $mirrored',
      ...result.lines,
    ];
    return result;
  }

  String check(Result result, String expected) {
    final status = !result.ok
        ? 'failed'
        : result.text == expected
        ? 'ok'
        : 'mismatch';
    checks++;
    checkCounts[status] = (checkCounts[status] ?? 0) + 1;
    for (var i = 0; i < 3; i++) {
      blockCounts[i] += result.blocks[i];
    }
    corrected += result.corrected;
    return status;
  }

  int tolerance(Prepared p, int color) {
    final n = p.symbol.length;
    for (var size = 1; size <= n; size++) {
      final a = (n - size) ~/ 2, damaged = cloneGrid(p.symbol);
      for (var y = a; y < a + size; y++) {
        for (var x = a; x < a + size; x++) {
          damaged[y][x] = color;
        }
      }
      final result = decode(damaged);
      if (!result.ok || result.text != p.request.text) return size - 1;
    }
    return n;
  }

  void emit(Prepared p) {
    final r = p.request, n = p.symbol.length, table = p.table;
    var dark = 0;
    for (final row in p.symbol) {
      for (final v in row) {
        dark += v;
      }
    }
    valid++;
    modeCounts[p.mode] = (modeCounts[p.mode] ?? 0) + 1;
    levelCounts[p.level] = (levelCounts[p.level] ?? 0) + 1;
    versions[p.version]++;
    masks[p.mask]++;
    segments += p.segments.length;
    dataCount += table.data;
    ecCount += table.e * (table.b1 + table.b2);
    modules += n * n;
    this.dark += dark;
    if (p.level != r.level[0]) boosted++;
    codes.add(
      'symbol version ${p.version} level ${p.level} mask ${p.mask} size $n',
    );
    codes.add(
      'segments ${p.segments.length} ${p.segments.map((s) => '${s.mode}:${s.text.length}').join(' ')}',
    );
    final alternatives = [
          for (final mode in modes)
            canEncode(mode, r.text)
                ? '${4 + countWidth(mode, p.version) + dataWidth(mode, r.text.length)}'
                : '-',
        ],
        mixed = splitSegments('MIXED', r.text, p.version).$2;
    codes.add(
      'bits data ${p.length} capacity ${8 * table.data} alternatives NUMERIC ${alternatives[0]} ALPHANUMERIC ${alternatives[1]} BYTE ${alternatives[2]} MIXED $mixed',
    );
    final fits = <String>[],
        length1 = splitSegments(p.mode, r.text, 1).$2,
        length10 = splitSegments(p.mode, r.text, 10).$2;
    for (final level in levels) {
      var fit = '-';
      for (var v = 1; v <= 10; v++) {
        if ((v == 10 ? length10 : length1) <= 8 * tableAt(v, level).data) {
          fit = '$v';
          break;
        }
      }
      fits.add(fit);
    }
    codes.add('fits L ${fits[0]} M ${fits[1]} Q ${fits[2]} H ${fits[3]}');
    codes.add(
      'modules function ${n * n - p.matrix.order.length} data ${p.matrix.order.length} remainder ${p.matrix.order.length - 8 * table.total} dark $dark',
    );
    final versionInfo = p.version >= 7
        ? binary(versionInformation(p.version), 18)
        : 'none';
    codes.add(
      'format ${binary(formatInformation(p.level, p.mask), 15)} version $versionInfo',
    );
    for (var mask = 0; mask < 8; mask++) {
      final a = p.penalties[mask];
      codes.add(
        'penalty $mask n1 ${a.n1} n2 ${a.n2} n3 ${a.n3} n4 ${a.n4} total ${a.total}',
      );
    }
    codes.addAll(symbolLines(p.symbol));
    codewords.add(
      'request ${r.id} version ${p.version} level ${p.level} blocks ${p.blocks.length} data ${table.data} ec_per_block ${table.e} total ${table.total}',
    );
    for (var b = 0; b < p.blocks.length; b++) {
      final block = p.blocks[b], k = block.length - table.e;
      codewords.add('block $b data ${hexadecimal(block.sublist(0, k))}');
      codewords.add('block $b ec ${hexadecimal(block.sublist(k))}');
    }
    codewords.add('interleaved ${hexadecimal(p.interleaved)}');
    bitstream.add(
      'request ${r.id} version ${p.version} bits ${p.length} capacity ${8 * table.data}',
    );
    for (final seg in p.segments) {
      bitstream.add(
        'segment ${seg.mode} indicator ${binary(indicator(seg.mode), 4)} count ${seg.text.length} ${binary(seg.text.length, countWidth(seg.mode, p.version))}',
      );
      for (final g in groups(seg)) {
        bitstream.add(
          'group ${g.value} ${binary(g.value, g.width)} "${g.text}"',
        );
      }
    }
    bitstream.add(
      'terminator ${p.terminator} zero_fill ${p.zeroFill} pad_bytes ${p.pads}',
    );
    final image = pbm(p.symbol, quiet, scale);
    File('output/qr_${r.id}.pbm').writeAsStringSync(image);
    final (array, imageLine) = imageRead(image);
    selfcheck.addAll(['request ${r.id}', imageLine, 'check clean']);
    var result = decode(array);
    selfcheck.addAll(result.lines);
    selfcheck.add('result ${check(result, r.text)}');
    final operations = damage[r.id] ?? <Damage>[];
    if (operations.isNotEmpty) {
      var damaged = cloneGrid(p.symbol);
      for (final operation in operations) {
        final a = operation.args;
        switch (operation.kind) {
          case 'flip':
            final x = number(a[0]), y = number(a[1]);
            damaged[y][x] ^= 1;
            break;
          case 'fill':
            final x = number(a[0]),
                y = number(a[1]),
                w = number(a[2]),
                h = number(a[3]),
                color = a[4] == 'dark' ? 1 : 0;
            for (var row = y; row < y + h; row++) {
              for (var col = x; col < x + w; col++) {
                damaged[row][col] = color;
              }
            }
            break;
        }
      }
      var changed = 0,
          functions = 0,
          formats = 0,
          versions = 0,
          data = 0,
          remainder = 0;
      final index = {
            for (var j = 0; j < p.matrix.order.length; j++)
              p.matrix.order[j]: j,
          },
          damagedWords = [for (final _ in p.blocks) <int>{}];
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          if (damaged[y][x] == p.symbol[y][x]) continue;
          changed++;
          switch (p.matrix.areas[y][x]) {
            case 1:
              functions++;
              break;
            case 2:
              formats++;
              break;
            case 3:
              versions++;
              break;
            case 0:
              final j = index[(x, y)]!;
              if (j >= 8 * table.total) {
                remainder++;
              } else {
                data++;
                final position = p.placement[j ~/ 8];
                damagedWords[position.$1].add(position.$2);
              }
              break;
          }
        }
      }
      selfcheck.addAll([
        'check damaged operations ${operations.length}',
        'damage changed $changed function $functions format $formats version $versions data $data remainder $remainder',
        'errors ${damagedWords.map((w) => w.length).join(' ')} limit ${table.e ~/ 2}',
      ]);
      for (final operation in operations) {
        if (operation.kind == 'rotate') {
          damaged = rotate(damaged);
        } else if (operation.kind == 'mirror') {
          damaged = transpose(damaged);
        }
      }
      result = decode(damaged);
      selfcheck.addAll(result.lines);
      selfcheck.add('result ${check(result, r.text)}');
    }
    final light = tolerance(p, 0), darkTolerance = tolerance(p, 1);
    selfcheck.add('tolerance light $light dark $darkTolerance');
  }

  void capacityTable() {
    for (var v = 1; v <= 10; v++) {
      final m = makeMatrix(v, alignment[v] ?? []),
          n = 17 + 4 * v,
          table = tableAt(v, 'L'),
          coordinates = alignment[v] ?? <int>[];
      capacity.add(
        'version $v size $n data_modules ${m.order.length} codewords ${table.total} remainder ${m.order.length - 8 * table.total} alignment ${coordinates.isEmpty ? 'none' : coordinates.join(' ')}',
      );
      for (final level in levels) {
        final table = tableAt(v, level), maximum = <int>[];
        for (final mode in modes) {
          var k = 0;
          while (4 + countWidth(mode, v) + dataWidth(mode, k + 1) <=
              8 * table.data) {
            k++;
          }
          maximum.add(k);
        }
        capacity.add(
          'level $level blocks ${table.b1 + table.b2} data ${table.data} ec_per_block ${table.e} numeric ${maximum[0]} alphanumeric ${maximum[1]} byte ${maximum[2]}',
        );
      }
    }
  }

  List<String> summary() => [
    'requests ${requests.length} encoded $valid errors ${requests.length - valid}',
    'error_kinds level ${errorKinds['level'] ?? 0} mode ${errorKinds['mode'] ?? 0} version ${errorKinds['version'] ?? 0} mask ${errorKinds['mask'] ?? 0} text ${errorKinds['text'] ?? 0} charset ${errorKinds['charset'] ?? 0} capacity ${errorKinds['capacity'] ?? 0}',
    'modes NUMERIC ${modeCounts['NUMERIC'] ?? 0} ALPHANUMERIC ${modeCounts['ALPHANUMERIC'] ?? 0} BYTE ${modeCounts['BYTE'] ?? 0} MIXED ${modeCounts['MIXED'] ?? 0}',
    'levels L ${levelCounts['L'] ?? 0} M ${levelCounts['M'] ?? 0} Q ${levelCounts['Q'] ?? 0} H ${levelCounts['H'] ?? 0} boosted $boosted',
    'versions ${versions.skip(1).join(' ')}',
    'masks ${masks.join(' ')}',
    'segments $segments data_codewords $dataCount ec_codewords $ecCount',
    'modules $modules dark $dark',
    'checks $checks ok ${checkCounts['ok'] ?? 0} mismatch ${checkCounts['mismatch'] ?? 0} failed ${checkCounts['failed'] ?? 0}',
    'blocks ok ${blockCounts[0]} corrected ${blockCounts[1]} failed ${blockCounts[2]} codewords $corrected',
    'scans $scanCount decoded $scanOK failed ${scanCount - scanOK}',
  ];
}

(List<List<int>>, String) imageRead(String text) {
  final lines = text.trimRight().split('\n'),
      size = lines[1].split(' '),
      w = number(size[0]),
      h = number(size[1]),
      pixels = lines.sublist(2);
  var left = w, right = -1, top = h;
  for (var y = 0; y < pixels.length; y++) {
    for (var x = 0; x < w; x++) {
      if (pixels[y][x] == '1') {
        left = min(left, x);
        right = max(right, x);
        top = min(top, y);
      }
    }
  }
  var run = 0;
  for (var x = left; x < w && pixels[top][x] == '1'; x++) {
    run++;
  }
  final scale = run ~/ 7, n = (right - left + 1) ~/ scale, a = intGrid(n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      a[y][x] = number(pixels[top + scale * y][left + scale * x]);
    }
  }
  var well = true;
  for (var y = 0; y < pixels.length; y++) {
    for (var x = 0; x < w; x++) {
      final expected =
          x >= left && x < left + scale * n && y >= top && y < top + scale * n
          ? a[(y - top) ~/ scale][(x - left) ~/ scale]
          : 0;
      if (number(pixels[y][x]) != expected) well = false;
    }
  }
  return (
    a,
    'image $w $h quiet ${left ~/ scale} scale $scale size $n ${well ? 'ok' : 'bad'}',
  );
}

void main() {
  final q = QR(), params = readLines('input/params.txt');
  q.quiet = number(params[0].split(' ')[1]);
  q.scale = number(params[1].split(' ')[1]);
  for (final line in readLines('input/tables.txt')) {
    final a = line.split(' '), v = number(a[1]);
    if (a[0] == 'block') {
      q.tables.putIfAbsent(v, () => {})[a[2]] = BlockTable(
        number(a[3]),
        number(a[4]),
        number(a[5]),
        number(a[6]),
        number(a[7]),
      );
    } else {
      q.alignment[v] = [for (final s in a.skip(2)) number(s)];
    }
  }
  for (final line in readLines('input/requests.txt')) {
    final at = line.indexOf(':'), a = line.substring(0, at).split(' ');
    q.requests.add(
      Request(a[0], a[1], a[2], a[3], a[4], line.substring(at + 1)),
    );
  }
  for (final line in readLines('input/damage.txt')) {
    final a = line.split(' ');
    q.damage.putIfAbsent(a[0], () => []).add(Damage(a[1], a.sublist(2)));
  }
  Directory('output').createSync(recursive: true);
  for (final r in q.requests) {
    q.codes.add('request ${r.id}');
    final (p, errorText) = q.prepare(r);
    if (errorText.isNotEmpty) {
      q.codes.add('error $errorText');
      final kind = errorText.split(' ')[0];
      q.errorKinds[kind] = (q.errorKinds[kind] ?? 0) + 1;
      continue;
    }
    q.emit(p!);
  }
  final lines = readLines('input/scans.txt');
  var at = 0;
  while (at < lines.length) {
    final name = lines[at++].split(' ')[1],
        n = lines[at].length,
        a = [
          for (var y = 0; y < n; y++)
            [for (var x = 0; x < n; x++) lines[at + y][x] == '#' ? 1 : 0],
        ];
    at += n;
    q.scanCount++;
    final result = q.decode(a);
    q.scans.add('scan $name size $n');
    q.scans.addAll(result.lines);
    if (result.ok) {
      q.scanOK++;
      q.scans.add('result decoded');
    } else {
      q.scans.add('result failed');
    }
  }
  q.capacityTable();
  final reports = {
    'codes.txt': q.codes,
    'codewords.txt': q.codewords,
    'bitstream.txt': q.bitstream,
    'selfcheck.txt': q.selfcheck,
    'scans.txt': q.scans,
    'capacity.txt': q.capacity,
    'summary.txt': q.summary(),
  };
  for (final e in reports.entries) {
    File(
      'output/${e.key}',
    ).writeAsStringSync(e.value.isEmpty ? '' : '${e.value.join('\n')}\n');
  }
}
