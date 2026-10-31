import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

part 'bitio.dart';
part 'lzw.dart';
part 'lz77.dart';
part 'huffman.dart';
part 'arith_coder.dart';

const methods = ['STORE', 'LZW', 'LZ77', 'LZH', 'ARITH'];
const statuses = [
  'ok',
  'repaired',
  'checksum',
  'error',
  'unsupported',
  'truncated',
  'bad_header',
];

class Parameters {
  final int b, k, m;
  Parameters(this.b, this.k, this.m);
}

class NamedFile {
  final String name;
  final List<int> data;
  NamedFile(this.name, this.data);
}

class LZStats {
  final int tokens;
  int literals = 0, matches = 0, matched = 0, longest = 0, farthest = 0;
  LZStats(this.tokens);
}

class LZHStats {
  final String mode;
  final int fixedBits,
      tableBits,
      codeBits,
      halvings,
      litUsed,
      litMax,
      offsetUsed,
      offsetMax;
  final List<int> slots;
  LZHStats(
    this.mode,
    this.fixedBits,
    this.tableBits,
    this.codeBits,
    this.halvings,
    this.litUsed,
    this.litMax,
    this.offsetUsed,
    this.offsetMax,
    this.slots,
  );
}

class Encoding {
  final String name;
  final List<int> data;
  final List<List<int>> payloads;
  final int best;
  final LZWStats lzw;
  final LZStats lz;
  final LZHStats lzh;
  final ArithStats arith;
  Encoding(
    this.name,
    this.data,
    this.payloads,
    this.best,
    this.lzw,
    this.lz,
    this.lzh,
    this.arith,
  );
  List<int> get payload => payloads[best];
}

class Entry {
  final int number, offset;
  String status = '', name = '';
  bool valid = false;
  int method = 0,
      original = 0,
      compressed = 0,
      checksum = 0,
      start = 0,
      end = 0,
      computed = 0;
  List<int> data = [];
  DecodeError? error;
  (int, int, int) repair = (0, 0, 0);
  Entry(this.number, this.offset);
}

class ParsedArchive {
  final int size;
  int b = 0, k = 0, declared = 0, trailing = 0;
  final entries = <Entry>[];
  String error = '';
  bool stopped = false;
  ParsedArchive(this.size);
  List<Entry> get intact =>
      entries.where((e) => e.status == 'ok' || e.status == 'repaired').toList();
}

(Parameters, List<NamedFile>, List<int>) readInputs() {
  final lines = File('input/manifest.txt').readAsLinesSync(),
      values = [
        for (final line in lines.take(3)) int.parse(line.split(' ')[1]),
      ],
      files = <NamedFile>[];
  for (final line in lines.skip(3)) {
    final name = line.split(' ')[1];
    files.add(NamedFile(name, File('input/files/$name').readAsBytesSync()));
  }
  final text = File('input/archive.hex').readAsLinesSync().join(),
      archive = [
        for (var i = 0; i < text.length; i += 2)
          int.parse(text.substring(i, i + 2), radix: 16),
      ];
  return (Parameters(values[0], values[1], values[2]), files, archive);
}

String ratio(int compressed, int original) =>
    original == 0 ? '-' : '${1000 * compressed ~/ original}';
String methodName(int method) => method < 5 ? methods[method] : '#$method';
int adler(List<int> data) {
  var a = 1, b = 0;
  for (final x in data) {
    a = (a + x) % 65521;
    b = (b + a) % 65521;
  }
  return b * 65536 + a;
}

int modPower(int a, int exponent) {
  var v = 1;
  while (exponent > 0) {
    if ((exponent & 1) != 0) v = v * a % 65521;
    a = a * a % 65521;
    exponent >>= 1;
  }
  return v;
}

(List<int>, (int, int, int))? repairOneByte(
  List<int> data,
  int stored,
  int computed,
) {
  final deltaA = (stored % 65536 - computed % 65536) % 65521,
      deltaB = (stored ~/ 65536 - computed ~/ 65536) % 65521;
  var delta = deltaA;
  if (1 <= deltaA && deltaA <= 255) {
  } else if (65266 <= deltaA && deltaA <= 65520) {
    delta -= 65521;
  } else {
    return null;
  }
  final inverse = modPower(delta % 65521, 65519), t = deltaB * inverse % 65521;
  if (t < 1 || t > data.length) return null;
  final position = data.length - t,
      before = data[position],
      after = before + delta;
  if (after < 0 || after > 255) return null;
  final result = [...data];
  result[position] = after;
  if (adler(result) != stored) return null;
  return (result, (position, before, after));
}

List<int> encodeLZ77(List<Token> tokens, int b, int k) {
  final w = BitWriter();
  for (final t in tokens) {
    if (t.length == 0) {
      w.write(0, 1);
      w.write(t.literal, 8);
    } else {
      w.write(1, 1);
      w.write(t.distance - 1, b);
      w.write(t.length - 3, k);
    }
  }
  return w.finish();
}

List<int> decodeLZ77(List<int> payload, int n, int b, int k) {
  final r = BitReader(payload), out = <int>[];
  while (out.length < n) {
    final flag = r.read(1, out.length);
    if (flag == 0) {
      out.add(r.read(8, out.length));
    } else {
      final u = r.read(b, out.length), v = r.read(k, out.length);
      copyMatch(out, u + 1, v + 3, n);
    }
  }
  return out;
}

List<int> fixedLengths(int count) {
  final width = (count - 1).bitLength, shorter = (1 << width) - count;
  return [for (var s = 0; s < count; s++) s < shorter ? width - 1 : width];
}

void writeCodeTable(BitWriter w, List<int> lengths) {
  var s = 0;
  while (s < lengths.length) {
    if (lengths[s] > 0) {
      w.write(lengths[s], 4);
      s++;
    } else {
      var run = 1;
      while (run < 256 && s + run < lengths.length && lengths[s + run] == 0) {
        run++;
      }
      w.write(0, 4);
      w.write(run - 1, 8);
      s += run;
    }
  }
}

List<int> readCodeTable(BitReader r, int count, int position) {
  final lengths = <int>[];
  while (lengths.length < count) {
    final length = r.read(4, position);
    if (length > 0) {
      lengths.add(length);
    } else {
      final run = r.read(8, position) + 1;
      if (lengths.length + run > count)
        throw DecodeError('bad_table', position);
      lengths.addAll(List.filled(run, 0));
    }
  }
  var used = 0, sum = 0, single = 0;
  for (final v in lengths) {
    if (v > 0) {
      used++;
      single = v;
      sum += 1 << (15 - v);
    }
  }
  if ((used == 1 && single != 1) || (used >= 2 && sum != 1 << 15))
    throw DecodeError('bad_table', position);
  return lengths;
}

class HuffmanReader {
  final symbols = <(int, int), int>{};
  int maximum = 0;
  HuffmanReader(List<int> lengths) {
    final codes = canonicalCodes(lengths);
    for (var s = 0; s < lengths.length; s++) {
      final length = lengths[s];
      if (length > 0) {
        symbols[(length, codes[s])] = s;
        maximum = math.max(maximum, length);
      }
    }
  }
  int read(BitReader r, int position) {
    if (symbols.isEmpty) throw DecodeError('bad_code', position);
    var code = 0;
    for (var width = 1; width <= maximum; width++) {
      code = 2 * code + r.read(1, position);
      final symbol = symbols[(width, code)];
      if (symbol != null) return symbol;
    }
    throw DecodeError('bad_code', position);
  }
}

void writeLZHTokens(
  BitWriter w,
  List<Token> tokens,
  List<int> lit,
  List<int> dist,
) {
  final lc = canonicalCodes(lit), dc = canonicalCodes(dist);
  for (final t in tokens) {
    if (t.length == 0) {
      w.write(lc[t.literal], lit[t.literal]);
    } else {
      final symbol = t.length + 253;
      w.write(lc[symbol], lit[symbol]);
      final u = t.distance - 1, slot = u.bitLength;
      w.write(dc[slot], dist[slot]);
      if (slot >= 2) w.write(u - (1 << (slot - 1)), slot - 1);
    }
  }
}

(int, int) lengthStats(List<int> lengths) {
  var used = 0, longest = 0;
  for (final v in lengths) {
    if (v > 0) used++;
    longest = math.max(longest, v);
  }
  return (used, longest);
}

(List<int>, LZHStats) encodeLZH(List<Token> tokens, Parameters p) {
  final litFreq = List.filled(256 + (1 << p.k), 0),
      distFreq = List.filled(p.b + 1, 0);
  for (final t in tokens) {
    if (t.length == 0) {
      litFreq[t.literal]++;
    } else {
      litFreq[t.length + 253]++;
      distFreq[(t.distance - 1).bitLength]++;
    }
  }
  final (lit, lh) = limitedLengths(litFreq, p.m);
  final (dist, dh) = limitedLengths(distFreq, p.m);
  final fixed = BitWriter(), dynamic = BitWriter();
  fixed.write(0, 1);
  writeLZHTokens(
    fixed,
    tokens,
    fixedLengths(lit.length),
    fixedLengths(dist.length),
  );
  dynamic.write(1, 1);
  writeCodeTable(dynamic, lit);
  writeCodeTable(dynamic, dist);
  final tableBits = dynamic.count - 1;
  writeLZHTokens(dynamic, tokens, lit, dist);
  final codeBits = dynamic.count - 1 - tableBits;
  final (lu, lm) = lengthStats(lit);
  final (du, dm) = lengthStats(dist);
  final useFixed = fixed.count - 1 <= tableBits + codeBits;
  return (
    (useFixed ? fixed : dynamic).finish(),
    LZHStats(
      useFixed ? 'fixed' : 'dynamic',
      fixed.count - 1,
      tableBits,
      codeBits,
      lh + dh,
      lu,
      lm,
      du,
      dm,
      distFreq,
    ),
  );
}

List<int> decodeLZH(List<int> payload, int n, int b, int k) {
  final r = BitReader(payload), flag = r.read(1);
  List<int> lit, dist;
  if (flag == 1) {
    lit = readCodeTable(r, 256 + (1 << k), 0);
    dist = readCodeTable(r, b + 1, 0);
  } else {
    lit = fixedLengths(256 + (1 << k));
    dist = fixedLengths(b + 1);
  }
  final lr = HuffmanReader(lit), dr = HuffmanReader(dist), out = <int>[];
  while (out.length < n) {
    final symbol = lr.read(r, out.length);
    if (symbol < 256) {
      out.add(symbol);
    } else {
      final slot = dr.read(r, out.length);
      var u = slot;
      if (slot >= 2) u = (1 << (slot - 1)) + r.read(slot - 1, out.length);
      copyMatch(out, u + 1, symbol - 253, n);
    }
  }
  return out;
}

List<int> decodePayload(int method, List<int> payload, int n, int b, int k) {
  switch (method) {
    case 0:
      if (payload.length < n) throw DecodeError('end_of_data', payload.length);
      return payload.sublist(0, n);
    case 1:
      return decodeLZW(payload, n);
    case 2:
      return decodeLZ77(payload, n, b, k);
    case 3:
      return decodeLZH(payload, n, b, k);
    case 4:
      return decodeArith(payload, n);
    default:
      throw StateError('unsupported method');
  }
}

Encoding encodeFile(String name, List<int> data, Parameters p) {
  final tokens = tokenize(data, p.b, p.k);
  final (zw, zws) = encodeLZW(data);
  final (zh, zhs) = encodeLZH(tokens, p);
  final (arith, arithStats) = encodeArith(data);
  final payloads = [data, zw, encodeLZ77(tokens, p.b, p.k), zh, arith];
  var best = 0;
  for (var k = 1; k < 5; k++) {
    if (payloads[k].length < payloads[best].length) best = k;
  }
  final zs = LZStats(tokens.length);
  for (final t in tokens) {
    if (t.length == 0) {
      zs.literals++;
    } else {
      zs.matches++;
      zs.matched += t.length;
      zs.longest = math.max(zs.longest, t.length);
      zs.farthest = math.max(zs.farthest, t.distance);
    }
  }
  return Encoding(name, data, payloads, best, zws, zs, zhs, arithStats);
}

void appendBig(List<int> data, int value, int width) {
  for (var shift = 8 * (width - 1); shift >= 0; shift -= 8) {
    data.add((value >> shift) & 255);
  }
}

int readBig(List<int> data, int start, int width) {
  var value = 0;
  for (var i = 0; i < width; i++) {
    value = 256 * value + data[start + i];
  }
  return value;
}

List<int> buildArchive(List<Encoding> encodings, Parameters p) {
  final archive = [...('TXAR'.codeUnits), p.b, p.k];
  appendBig(archive, encodings.length, 2);
  for (final e in encodings) {
    final header = [e.name.length, ...e.name.codeUnits, e.best];
    appendBig(header, e.data.length, 4);
    appendBig(header, e.payload.length, 4);
    appendBig(header, adler(e.data), 4);
    header.add(header.fold(0, (a, b) => a + b) % 256);
    archive.addAll(header);
    archive.addAll(e.payload);
  }
  return archive;
}

Entry readEntryHeader(List<int> x, int number, int pos) {
  final m = x[pos],
      name = x.sublist(pos + 1, pos + 1 + m),
      cursor = pos + 1 + m,
      start = pos + 15 + m;
  var valid = 1 <= m && m <= 32;
  for (final b in name) {
    if (!(b >= 97 && b <= 122 ||
        b >= 48 && b <= 57 ||
        b == 46 ||
        b == 95 ||
        b == 45))
      valid = false;
  }
  var check = 0;
  for (var i = pos; i < start - 1; i++) {
    check += x[i];
  }
  valid = valid && check % 256 == x[start - 1];
  return Entry(number, pos)
    ..valid = valid
    ..name = String.fromCharCodes(name)
    ..method = x[cursor]
    ..original = readBig(x, cursor + 1, 4)
    ..compressed = readBig(x, cursor + 5, 4)
    ..checksum = readBig(x, cursor + 9, 4)
    ..start = start
    ..end = start + readBig(x, cursor + 5, 4);
}

void examinePayload(Entry e, List<int> x, int b, int k) {
  try {
    e.data = decodePayload(
      e.method,
      x.sublist(e.start, e.end),
      e.original,
      b,
      k,
    );
  } on DecodeError catch (error) {
    e.status = 'error';
    e.error = error;
    return;
  }
  e.computed = adler(e.data);
  if (e.computed == e.checksum) {
    e.status = 'ok';
    return;
  }
  final repair = repairOneByte(e.data, e.checksum, e.computed);
  if (repair == null) {
    e.status = 'checksum';
  } else {
    e.status = 'repaired';
    e.data = repair.$1;
    e.repair = repair.$2;
  }
}

ParsedArchive parseArchive(List<int> x) {
  final p = ParsedArchive(x.length);
  if (x.length < 8 || String.fromCharCodes(x.take(4)) != 'TXAR') {
    p.error = 'bad_magic';
    return p;
  }
  p.b = x[4];
  p.k = x[5];
  if (p.b < 6 || p.b > 12 || p.k < 2 || p.k > 5) {
    p.error = 'bad_params';
    return p;
  }
  p.declared = readBig(x, 6, 2);
  var pos = 8;
  for (var number = 1; number <= p.declared; number++) {
    if (pos >= x.length || pos + 15 + x[pos] > x.length) {
      p.entries.add(Entry(number, pos)..status = 'truncated');
      p.stopped = true;
      break;
    }
    final e = readEntryHeader(x, number, pos);
    p.entries.add(e);
    if (!e.valid) {
      e.status = 'bad_header';
      pos = e.end;
      if (pos > x.length) {
        p.stopped = true;
        break;
      }
      continue;
    }
    if (e.end > x.length) {
      e.status = 'truncated';
      p.stopped = true;
      break;
    }
    if (e.method >= 5) {
      e.status = 'unsupported';
    } else {
      examinePayload(e, x, p.b, p.k);
    }
    pos = e.end;
  }
  if (!p.stopped) p.trailing = x.length - pos;
  return p;
}

bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

(int, int) verifyArchive(List<int> archive, List<Encoding> encodings) {
  final p = parseArchive(archive);
  var verified = 0;
  for (var i = 0; i < p.entries.length && i < encodings.length; i++) {
    final e = p.entries[i];
    if (e.status == 'ok' && sameBytes(e.data, encodings[i].data)) verified++;
  }
  return (p.entries.length, verified);
}

List<String> sizesReport(
  List<Encoding> encodings,
  Parameters p,
  List<int> archive,
  int examined,
  int verified,
) {
  final lines = [
        'params offset_bits ${p.b} length_bits ${p.k} window ${1 << p.b} lookahead ${(1 << p.k) + 2} max_code_length ${p.m}',
      ],
      totals = List.filled(5, 0),
      chosen = List.filled(5, 0);
  var originalTotal = 0, bestTotal = 0;
  for (final e in encodings) {
    final original = e.data.length;
    originalTotal += original;
    chosen[e.best]++;
    bestTotal += e.payload.length;
    final fields = ['file ${e.name} original $original'];
    for (var k = 0; k < 5; k++) {
      final n = e.payloads[k].length;
      totals[k] += n;
      fields.add('${methods[k]} $n ${ratio(n, original)}');
    }
    fields.add('best ${methods[e.best]}');
    lines.add(fields.join(' '));
  }
  lines.add(
    [
      'total original $originalTotal',
      for (var k = 0; k < 5; k++)
        '${methods[k]} ${totals[k]} ${ratio(totals[k], originalTotal)}',
      'best $bestTotal ${ratio(bestTotal, originalTotal)}',
    ].join(' '),
  );
  lines.addAll([
    'chosen ${[for (var k = 0; k < 5; k++) '${methods[k]} ${chosen[k]}'].join(' ')}',
    'archive bytes ${archive.length} entries ${encodings.length} ratio ${ratio(archive.length, originalTotal)}',
    'verify entries $examined ok $verified',
  ]);
  return lines;
}

List<String> analysisReport(List<Encoding> encodings) {
  final lines = <String>[];
  for (final e in encodings) {
    final zw = e.lzw, z = e.lz, zh = e.lzh, ar = e.arith;
    lines.addAll([
      'lzw ${e.name} codes ${zw.codes} clears ${zw.clears} widths ${zw.widths.join(' ')} longest ${zw.longest}',
      'lz77 ${e.name} tokens ${z.tokens} literals ${z.literals} matches ${z.matches} matched ${z.matched} longest ${z.longest} farthest ${z.farthest}',
      'lzh ${e.name} mode ${zh.mode} fixed_bits ${zh.fixedBits} table_bits ${zh.tableBits} code_bits ${zh.codeBits} halvings ${zh.halvings} litlen_used ${zh.litUsed} litlen_max ${zh.litMax} offset_used ${zh.offsetUsed} offset_max ${zh.offsetMax}',
      'slots ${e.name} ${zh.slots.join(' ')}',
      'arith ${e.name} bits ${ar.bits} contexts ${ar.contexts} rescales ${ar.rescales}',
    ]);
  }
  return lines;
}

String hex8(int x) => x.toRadixString(16).padLeft(8, '0');
List<String> listingReport(ParsedArchive p) {
  if (p.error.isNotEmpty) return ['archive bytes ${p.size} error ${p.error}'];
  final lines = [
        'archive bytes ${p.size} offset_bits ${p.b} length_bits ${p.k} entries ${p.declared}',
      ],
      totals = List.generate(5, (_) => List.filled(3, 0));
  var listed = 0;
  for (final e in p.entries) {
    final prefix = 'entry ${e.number} offset ${e.offset}';
    if (!e.valid) {
      lines.add(
        '$prefix ${e.status == 'bad_header' ? 'bad_header' : 'truncated header'}',
      );
      continue;
    }
    listed++;
    lines.add(
      '$prefix method ${methodName(e.method)} original ${e.original} compressed ${e.compressed} ratio ${ratio(e.compressed, e.original)} adler ${hex8(e.checksum)} name ${e.name}',
    );
    if (e.method < 5) {
      final t = totals[e.method];
      t[0]++;
      t[1] += e.original;
      t[2] += e.compressed;
    }
  }
  for (var k = 0; k < 5; k++) {
    final t = totals[k];
    lines.add(
      'method ${methods[k]} entries ${t[0]} original ${t[1]} compressed ${t[2]} ratio ${ratio(t[2], t[1])}',
    );
  }
  lines.add(
    'end listed $listed of ${p.declared} stop ${p.stopped ? 'truncated' : 'complete'} trailing ${p.trailing}',
  );
  return lines;
}

String entryTestLine(Entry e, int size) {
  final prefix = 'entry ${e.number} offset ${e.offset}';
  if (!e.valid)
    return '$prefix status ${e.status == 'bad_header' ? 'bad_header' : 'truncated header'}';
  var line =
      '$prefix name ${e.name} method ${methodName(e.method)} status ${e.status}';
  switch (e.status) {
    case 'repaired':
      line += ' byte ${e.repair.$1} from ${e.repair.$2} to ${e.repair.$3}';
    case 'checksum':
      line += ' stored ${hex8(e.checksum)} computed ${hex8(e.computed)}';
    case 'error':
      line += ' ${e.error!.kind} at ${e.error!.position}';
    case 'truncated':
      line += ' payload have ${size - e.start} need ${e.compressed}';
  }
  return line;
}

List<String> testReport(
  ParsedArchive p,
  List<Encoding> salvaged,
  List<int> archive,
  int verified,
) {
  final lines = <String>[];
  if (p.error.isNotEmpty) {
    lines.add('archive error ${p.error}');
  } else {
    final counts = {for (final status in statuses) status: 0};
    for (final e in p.entries) {
      lines.add(entryTestLine(e, p.size));
      counts[e.status] = counts[e.status]! + 1;
    }
    lines.add(
      [
        'summary entries ${p.declared} checked ${p.entries.length}',
        for (final status in statuses) '$status ${counts[status]}',
        'missing ${p.declared - p.entries.length} trailing ${p.trailing}',
      ].join(' '),
    );
  }
  final intact = p.intact;
  var total = 0;
  for (var i = 0; i < salvaged.length; i++) {
    final e = salvaged[i], old = intact[i];
    lines.add(
      'salvage ${e.name} method ${methods[e.best]} compressed ${e.payload.length} was ${methodName(old.method)} ${old.compressed}',
    );
    total += e.data.length;
  }
  lines.add(
    'salvaged entries ${salvaged.length} bytes ${archive.length} original $total verified $verified',
  );
  return lines;
}

List<String> textLines(List<int> data) {
  if (data.isEmpty) return [];
  final lines = String.fromCharCodes(data).split('\n');
  lines.removeLast();
  return lines;
}

List<String> extractionReport(List<Entry> entries) {
  final lines = <String>[];
  for (final e in entries) {
    final contents = textLines(e.data);
    var words = 0, longest = 0;
    for (final line in contents) {
      longest = math.max(longest, line.length);
      words += line.split(' ').where((s) => s.isNotEmpty).length;
    }
    lines.add(
      'file ${e.name} bytes ${e.data.length} lines ${contents.length} words $words longest $longest',
    );
    lines.addAll(contents);
  }
  return lines;
}

class Edit {
  final String sign, content;
  final int number;
  Edit(this.sign, this.number, this.content);
}

List<Edit> editList(List<String> old, List<String> fresh) {
  final a = old.length,
      b = fresh.length,
      decisions = List.generate(
        old.length,
        (_) => Uint8List((fresh.length + 7) ~/ 8),
      );
  var below = List.filled(b + 1, 0), current = List.filled(b + 1, 0);
  for (var i = a - 1; i >= 0; i--) {
    final deletions = decisions[i];
    var right = 0;
    for (var j = b - 1; j >= 0; j--) {
      int length;
      if (old[i] == fresh[j]) {
        length = below[j + 1] + 1;
      } else if (below[j] >= right) {
        length = below[j];
        deletions[j ~/ 8] |= 1 << (j % 8);
      } else {
        length = right;
      }
      current[j] = length;
      right = length;
    }
    final previous = below;
    below = current;
    current = previous;
  }
  final edits = <Edit>[];
  var i = 0, j = 0;
  while (i < a || j < b) {
    if (i < a && j < b && old[i] == fresh[j]) {
      i++;
      j++;
    } else if (j == b ||
        (i < a && (decisions[i][j ~/ 8] & (1 << (j % 8))) != 0)) {
      edits.add(Edit('-', i + 1, old[i]));
      i++;
    } else {
      edits.add(Edit('+', j + 1, fresh[j]));
      j++;
    }
  }
  return edits;
}

List<String> comparisonReport(List<Entry> entries, List<NamedFile> files) {
  final manifest = {for (final f in files) f.name: f.data},
      seen = <String>{},
      lines = <String>[];
  for (final e in entries) {
    seen.add(e.name);
    final data = manifest[e.name];
    if (data == null) {
      lines.add('archive_only ${e.name}');
      continue;
    }
    final old = textLines(e.data), fresh = textLines(data);
    var first = 0;
    while (first < math.min(old.length, fresh.length) &&
        old[first] == fresh[first]) {
      first++;
    }
    if (first == old.length && first == fresh.length) {
      lines.add('same ${e.name} lines ${old.length}');
      continue;
    }
    final edits = editList(old, fresh),
        removed = edits.where((e) => e.sign == '-').length;
    lines.add(
      'differs ${e.name} first_line ${first + 1} archive_lines ${old.length} manifest_lines ${fresh.length} removed $removed added ${edits.length - removed}',
    );
    lines.addAll(edits.map((e) => '${e.sign}${e.number}:${e.content}'));
  }
  lines.addAll(
    files.where((f) => !seen.contains(f.name)).map((f) => 'new ${f.name}'),
  );
  return lines;
}

void writeLines(String name, List<String> lines) {
  File(
    'output/$name',
  ).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}

void writeHex(String name, List<int> data) {
  writeLines(name, [
    for (var i = 0; i < data.length; i += 32)
      data
          .sublist(i, math.min(i + 32, data.length))
          .map((x) => x.toRadixString(16).padLeft(2, '0'))
          .join(),
  ]);
}

void main() {
  final (p, files, supplied) = readInputs();
  final encodings = [for (final f in files) encodeFile(f.name, f.data, p)],
      created = buildArchive(encodings, p);
  final (examined, verified) = verifyArchive(created, encodings);
  final parsed = parseArchive(supplied),
      sp = parsed.error.isEmpty ? Parameters(parsed.b, parsed.k, p.m) : p,
      salvaged = [
        for (final e in parsed.intact) encodeFile(e.name, e.data, sp),
      ],
      salvage = buildArchive(salvaged, sp);
  final (_, salvageVerified) = verifyArchive(salvage, salvaged);
  Directory('output').createSync(recursive: true);
  writeLines(
    'sizes.txt',
    sizesReport(encodings, p, created, examined, verified),
  );
  writeLines('analysis.txt', analysisReport(encodings));
  writeHex('archive.hex', created);
  writeLines('listing.txt', listingReport(parsed));
  writeLines(
    'test_report.txt',
    testReport(parsed, salvaged, salvage, salvageVerified),
  );
  writeLines('extracted.txt', extractionReport(parsed.intact));
  writeLines('compare.txt', comparisonReport(parsed.intact, files));
  writeHex('salvaged.hex', salvage);
}
