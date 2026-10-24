import 'dart:io';
import 'dart:math';

class Invalid implements Exception {}
Never invalid() => throw Invalid();
const systemNames = ['GEOHASH', 'MAIDENHEAD', 'PLUSCODE', 'GARS', 'GEOREF', 'MESH'];
const precisions = [[1, 2, 3, 4, 5, 6, 7, 8, 9], [2, 4, 6, 8], [2, 4, 6, 8, 10, 11], [5, 6, 7], [2, 4, 8, 10, 12], [4, 6, 8, 9, 10, 11]];
const geohash = '0123456789bcdefghjkmnpqrstuvwxyz';
const plusDigits = '23456789CFGHJMPQRVWX';
const l24 = 'ABCDEFGHJKLMNPQRSTUVWXYZ', g25 = 'ABCDEFGHJKLMNOPQRSTUVWXYZ';
const bands = 'CDEFGHJKLMNPQRSTUVWX', mgrsRows = 'ABCDEFGHJKLMNPQRSTUV';
const columns = ['STUVWXYZ', 'ABCDEFGH', 'JKLMNPQR'];
const maidenSets = ['ABCDEFGHIJKLMNOPQR', '0123456789', 'abcdefghijklmnopqrstuvwx', '0123456789'];
int floorDiv(int a, int b) => a ~/ b - (a < 0 && a % b != 0 ? 1 : 0);
int rounded(int a, int b) => floorDiv(2 * a + b, 2 * b);
int number(String text, int minimum, int maximum) {
  if (!RegExp(r'^-?[0-9]{1,9}$').hasMatch(text)) invalid();
  final n = int.parse(text);
  if (n < minimum || n > maximum) invalid();
  return n;
}
int coordinate(String text, bool latitude) {
  if (!RegExp(r'^-?[0-9]{1,3}(\.[0-9]{1,6})?$').hasMatch(text)) invalid();
  final negative = text.startsWith('-'), parts = (negative ? text.substring(1) : text).split('.');
  var n = int.parse(parts[0]) * 1000000 + (parts.length == 1 ? 0 : int.parse(parts[1].padRight(6, '0')));
  if (negative) n = -n;
  if (latitude ? n < -90000000 || n > 90000000 : n < -180000000 || n >= 180000000) invalid();
  return n;
}
String coordText(int n) => '${n < 0 ? '-' : ''}${n.abs() ~/ 1000000}.${(n.abs() % 1000000).toString().padLeft(6, '0')}';
String decimal(int n, int width) => n.toString().padLeft(width, '0');
int index(String set, String c) {
  final i = set.indexOf(c);
  if (i < 0) invalid();
  return i;
}
int digits(String text) {
  if (!RegExp(r'^[0-9]+$').hasMatch(text)) invalid();
  return int.parse(text);
}
int system(String text) {
  final s = systemNames.indexOf(text);
  if (s < 0) invalid();
  return s;
}
int precision(int s, String text) {
  final p = number(text, 1, 12);
  if (!precisions[s].contains(p)) invalid();
  return p;
}
(int, int) grid(int s, int p) {
  return switch (s) {
    0 => (1 << ((5 * p + 1) ~/ 2), 1 << (5 * p ~/ 2)),
    1 => {2: (18, 18), 4: (180, 180), 6: (4320, 4320), 8: (43200, 43200)}[p]!,
    2 => {2: (18, 9), 4: (360, 180), 6: (7200, 3600), 8: (144000, 72000), 10: (2880000, 1440000), 11: (11520000, 7200000)}[p]!,
    3 => {5: (720, 360), 6: (1440, 720), 7: (4320, 2160)}[p]!,
    4 => {2: (24, 12), 4: (360, 180), 8: (21600, 10800), 10: (216000, 108000), 12: (2160000, 1080000)}[p]!,
    _ => (360 * meshScale(p), 270 * meshScale(p)),
  };
}
int meshScale(int p) => {4: 1, 6: 8, 8: 80, 9: 160, 10: 320, 11: 640}[p]!;
List<int> radixDigits(int value, List<int> radices) {
  final result = List.filled(radices.length, 0);
  for (var i = radices.length - 1; i >= 0; i--) {
    result[i] = value % radices[i];
    value ~/= radices[i];
  }
  return result;
}
class Cell {
  final int s, p, x, y, w, h;
  Cell(this.s, this.p, this.x, this.y) : w = grid(s, p).$1, h = grid(s, p).$2;
  Cell ancestor(int q) {
    final g = grid(s, q);
    return Cell(s, q, x * g.$1 ~/ w, y * g.$2 ~/ h);
  }
  String get key => '$p/$x/$y';
}
Cell containing(int s, int p, int lat, int lon) {
  final g = grid(s, p), y = (lat + 90000000) * g.$2 ~/ 180000000;
  return Cell(s, p, (lon + 180000000) * g.$1 ~/ 360000000, min(y, g.$2 - 1));
}
String? encode(Cell c) {
  var x = c.x, y = c.y;
  final p = c.p, result = StringBuffer();
  switch (c.s) {
    case 0:
      var xb = (5 * p + 1) ~/ 2, yb = 5 * p ~/ 2, value = 0;
      for (var i = 0; i < 5 * p; i++) {
        final bit = i % 2 == 0 ? (x >> --xb) & 1 : (y >> --yb) & 1;
        value = 2 * value + bit;
        if (i % 5 == 4) {
          result.write(geohash[value]);
          value = 0;
        }
      }
    case 1:
      final radices = [18, 10, 24, 10].take(p ~/ 2).toList();
      final xs = radixDigits(x, radices), ys = radixDigits(y, radices);
      for (var i = 0; i < xs.length; i++) result.write('${maidenSets[i][xs[i]]}${maidenSets[i][ys[i]]}');
    case 2:
      final last = p == 11 ? 4 * (y % 5) + x % 4 : -1;
      if (p == 11) {
        x ~/= 4;
        y ~/= 5;
      }
      final k = (p == 11 ? 10 : p) ~/ 2;
      final xs = radixDigits(x, [18, ...List.filled(k - 1, 20)]), ys = radixDigits(y, [9, ...List.filled(k - 1, 20)]);
      for (var i = 0; i < k; i++) result.write('${plusDigits[ys[i]]}${plusDigits[xs[i]]}');
      if (last >= 0) result.write(plusDigits[last]);
      final text = result.toString();
      return p < 8 ? '${text.padRight(8, '0')}+' : '${text.substring(0, 8)}+${text.substring(8)}';
    case 3:
      final area = p == 7 ? 1 + x % 3 + 3 * (2 - y % 3) : 0;
      if (p == 7) {
        x ~/= 3;
        y ~/= 3;
      }
      final quadrant = p >= 6 ? 1 + x % 2 + 2 * (1 - y % 2) : 0;
      if (p >= 6) {
        x ~/= 2;
        y ~/= 2;
      }
      result.write('${decimal(x + 1, 3)}${l24[y ~/ 24]}${l24[y % 24]}');
      if (p >= 6) result.write(quadrant);
      if (p == 7) result.write(area);
    case 4:
      final m = (p - 4) ~/ 2, scale = p >= 8 ? 6 * pow(10, m - 1).toInt() : 1;
      final east = x % scale, north = y % scale;
      if (p >= 8) {
        x ~/= scale;
        y ~/= scale;
      }
      final a = p >= 4 ? x ~/ 15 : x, b = p >= 4 ? y ~/ 15 : y;
      result.write('${l24[a]}${l24[b]}');
      if (p >= 4) result.write('${l24[x % 15]}${l24[y % 15]}');
      if (p >= 8) result.write('${decimal(east, m)}${decimal(north, m)}');
    case 5:
      final scale = meshScale(p), u = x - 280 * scale, v = y - 135 * scale;
      if (u < 0 || u >= 80 * scale || v < 0 || v >= 100 * scale) return null;
      final count = precisions[5].indexOf(p) + 1;
      final us = radixDigits(u, [80, 8, 10, 2, 2, 2].take(count).toList());
      final vs = radixDigits(v, [100, 8, 10, 2, 2, 2].take(count).toList());
      result.write('${decimal(vs[0], 2)}${decimal(us[0], 2)}');
      for (var i = 1; i < count; i++) result.write(i <= 2 ? '${vs[i]}${us[i]}' : '${1 + us[i] + 2 * vs[i]}');
  }
  return result.toString();
}
Cell decode(int s, String code) {
  final p = s == 2 ? 0 : code.length;
  if (s != 2 && !precisions[s].contains(p)) invalid();
  var x = 0, y = 0, actual = p;
  switch (s) {
    case 0:
      var bitIndex = 0;
      for (final ch in code.split('')) {
        final value = index(geohash, ch);
        for (var b = 4; b >= 0; b--) {
          if (bitIndex++ % 2 == 0)
            x = 2 * x + ((value >> b) & 1);
          else
            y = 2 * y + ((value >> b) & 1);
        }
      }
    case 1:
      const radices = [18, 10, 24, 10];
      for (var i = 0; i < p ~/ 2; i++) {
        x = x * radices[i] + index(maidenSets[i], code[2 * i]);
        y = y * radices[i] + index(maidenSets[i], code[2 * i + 1]);
      }
    case 2:
      if (code.length < 9 || code[8] != '+' || '+'.allMatches(code).length != 1) invalid();
      final zero = code.substring(0, 8).indexOf('0'), before = zero < 0 ? 8 : zero;
      if (![2, 4, 6, 8].contains(before)) invalid();
      if (zero >= 0 && (code.substring(before, 8) != '0' * (8 - before) || code.length != 9)) invalid();
      if (zero < 0 && ![0, 2, 3].contains(code.length - 9)) invalid();
      final text = code.substring(0, before) + code.substring(9);
      actual = text.length;
      final values = text.split('').map((c) => index(plusDigits, c)).toList();
      if (values[0] > 8 || values[1] > 17) invalid();
      final pairs = (actual == 11 ? 10 : actual) ~/ 2;
      for (var i = 0; i < pairs; i++) {
        y = y * (i == 0 ? 9 : 20) + values[2 * i];
        x = x * (i == 0 ? 18 : 20) + values[2 * i + 1];
      }
      if (actual == 11) {
        x = 4 * x + values.last % 4;
        y = 5 * y + values.last ~/ 4;
      }
    case 3:
      final band = digits(code.substring(0, 3));
      if (band < 1 || band > 720) invalid();
      final a = index(l24, code[3]), b = index(l24, code[4]);
      if (a >= 15) invalid();
      x = band - 1;
      y = a * 24 + b;
      if (p >= 6) {
        final q = index('1234', code[5]);
        x = 2 * x + q % 2;
        y = 2 * y + 1 - q ~/ 2;
      }
      if (p == 7) {
        final q = index('123456789', code[6]);
        x = 3 * x + q % 3;
        y = 3 * y + 2 - q ~/ 3;
      }
    case 4:
      x = index(l24, code[0]);
      y = index(l24, code[1]);
      if (y >= 12) invalid();
      if (p >= 4) {
        final a = index(l24, code[2]), b = index(l24, code[3]);
        if (a >= 15 || b >= 15) invalid();
        x = 15 * x + a;
        y = 15 * y + b;
      }
      if (p >= 8) {
        final m = (p - 4) ~/ 2, scale = 6 * pow(10, (p - 4) ~/ 2 - 1).toInt();
        final a = digits(code.substring(4, 4 + m)), b = digits(code.substring(4 + m));
        if (a >= scale || b >= scale) invalid();
        x = x * scale + a;
        y = y * scale + b;
      }
    case 5:
      digits(code);
      y = int.parse(code.substring(0, 2));
      x = int.parse(code.substring(2, 4));
      if (x > 79) invalid();
      if (p >= 6) {
        final a = digits(code[4]), b = digits(code[5]);
        if (a > 7 || b > 7) invalid();
        y = 8 * y + a;
        x = 8 * x + b;
      }
      if (p >= 8) {
        y = 10 * y + digits(code[6]);
        x = 10 * x + digits(code[7]);
      }
      for (var i = 8; i < p; i++) {
        final q = index('1234', code[i]);
        x = 2 * x + q % 2;
        y = 2 * y + q ~/ 2;
      }
      x += 280 * meshScale(p);
      y += 135 * meshScale(p);
  }
  return Cell(s, actual, x, y);
}

String execute(String line) {
  final a = line.split(' '), op = a[0];
  void arity(int n) { if (a.length != n + 1) invalid(); }
  Cell read(int si, int ci) => decode(system(a[si]), a[ci]);
  if (op == 'ENCODE') {
    arity(4);
    final s = system(a[1]), lat = coordinate(a[2], true), lon = coordinate(a[3], false), p = precision(s, a[4]);
    return encode(containing(s, p, lat, lon)) ?? 'OUT OF AREA';
  }
  if (op == 'SIZE') {
    arity(2);
    final s = system(a[1]), p = precision(s, a[2]), g = grid(s, p);
    return 'w=${coordText(360000000 ~/ g.$1)} h=${coordText(180000000 ~/ g.$2)} cells=${s == 5 ? 8000 * meshScale(p) * meshScale(p) : g.$1 * g.$2}';
  }
  if (['DECODE', 'NEIGHBORS', 'PARENT', 'CHILDREN'].contains(op)) {
    arity(2);
    final c = read(1, 2), sequence = precisions[c.s], position = sequence.indexOf(c.p);
    if (op == 'DECODE') {
      final south = -90000000 + 180000000 * c.y ~/ c.h, west = -180000000 + 360000000 * c.x ~/ c.w;
      final north = -90000000 + 180000000 * (c.y + 1) ~/ c.h, east = -180000000 + 360000000 * (c.x + 1) ~/ c.w;
      final cy = -90000000 + 180000000 * (2 * c.y + 1) ~/ (2 * c.h), cx = -180000000 + 360000000 * (2 * c.x + 1) ~/ (2 * c.w);
      return 'sw=${coordText(south)},${coordText(west)} ne=${coordText(north)},${coordText(east)} c=${coordText(cy)},${coordText(cx)}';
    }
    if (op == 'NEIGHBORS') {
      const offsets = [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)];
      return offsets.map((d) => c.y + d.$2 < 0 || c.y + d.$2 >= c.h ? '-' : encode(Cell(c.s, c.p, (c.x + d.$1) % c.w, c.y + d.$2)) ?? '-').join(' ');
    }
    if (op == 'PARENT') return position == 0 ? 'NONE' : encode(c.ancestor(sequence[position - 1]))!;
    if (position == sequence.length - 1) return 'NONE';
    final q = sequence[position + 1], g = grid(c.s, q), rx = g.$1 ~/ c.w, ry = g.$2 ~/ c.h;
    if (rx * ry > 100) return 'TOO MANY';
    return [for (var j = ry - 1; j >= 0; j--) for (var i = 0; i < rx; i++) encode(Cell(c.s, q, rx * c.x + i, ry * c.y + j)) ?? '-'].join(' ');
  }
  if (['COMMON', 'STEPS', 'PATH'].contains(op)) {
    arity(3);
    final c = read(1, 2), d = decode(c.s, a[3]);
    if (op == 'COMMON') {
      final sequence = precisions[c.s], coarse = min(sequence.indexOf(c.p), sequence.indexOf(d.p));
      for (var i = coarse; i >= 0; i--) {
        final x = c.ancestor(sequence[i]), y = d.ancestor(sequence[i]);
        if (x.key == y.key) return encode(x)!;
      }
      return 'NONE';
    }
    if (c.p != d.p) return 'MISMATCH';
    var dx = (d.x - c.x) % c.w;
    if (2 * dx > c.w) dx -= c.w;
    final dy = d.y - c.y;
    if (op == 'STEPS') return 'dx=$dx dy=$dy';
    final n = max(dx.abs(), dy.abs());
    if (n + 1 > 100) return 'TOO MANY';
    return [for (var i = 0; i <= n; i++) encode(Cell(c.s, c.p, (c.x + (n == 0 ? 0 : rounded(i * dx, n))) % c.w, c.y + (n == 0 ? 0 : rounded(i * dy, n)))) ?? '-'].join(' ');
  }
  if (op == 'COMPACT') {
    if (a.length < 3 || a.length > 102) invalid();
    final s = system(a[1]), cells = <String, Cell>{};
    for (final code in a.skip(2)) {
      final c = decode(s, code);
      cells[c.key] = c;
    }
    for (final c in cells.values.toList()) {
      for (final q in precisions[s].where((q) => q < c.p)) {
        if (cells.containsKey(c.ancestor(q).key)) {
          cells.remove(c.key);
          break;
        }
      }
    }
    var changed = true;
    while (changed) {
      changed = false;
      for (final c in cells.values.toList()) {
        final position = precisions[s].indexOf(c.p);
        if (position == 0) continue;
        final parent = c.ancestor(precisions[s][position - 1]), rx = c.w ~/ parent.w, ry = c.h ~/ parent.h;
        if (rx * ry > cells.length) continue;
        final children = [for (var j = 0; j < ry; j++) for (var i = 0; i < rx; i++) Cell(s, c.p, parent.x * rx + i, parent.y * ry + j)];
        if (children.every((child) => cells.containsKey(child.key))) {
          for (final child in children) cells.remove(child.key);
          cells[parent.key] = parent;
          changed = true;
          break;
        }
      }
    }
    final ordered = cells.values.toList()..sort((c, d) => c.p != d.p ? c.p.compareTo(d.p) : c.y != d.y ? d.y.compareTo(c.y) : c.x.compareTo(d.x));
    return ordered.map((c) => encode(c)!).join(' ');
  }
  if (op == 'CONTAINS') {
    arity(4);
    final c = read(1, 2), d = containing(c.s, c.p, coordinate(a[3], true), coordinate(a[4], false));
    return c.key == d.key ? 'YES' : 'NO';
  }
  if (op == 'COVER') {
    arity(6);
    final s = system(a[1]), p = precision(s, a[2]), lat1 = coordinate(a[3], true), lon1 = coordinate(a[4], false), lat2 = coordinate(a[5], true), lon2 = coordinate(a[6], false);
    if (lat1 > lat2) invalid();
    final c = containing(s, p, lat1, lon1), d = containing(s, p, lat2, lon2);
    var width = d.x - c.x + 1;
    if (lon1 > lon2) width = min(c.w, width + c.w);
    if (width * (d.y - c.y + 1) > 100) return 'TOO MANY';
    return [for (var y = d.y; y >= c.y; y--) for (var i = 0; i < width; i++) encode(Cell(s, p, (c.x + i) % c.w, y)) ?? '-'].join(' ');
  }
  if (op == 'CONVERT') {
    arity(5);
    final c = read(1, 2);
    if (a[3] != 'TO') invalid();
    final s = system(a[4]), p = precision(s, a[5]), g = grid(s, p);
    return encode(Cell(s, p, (2 * c.x + 1) * g.$1 ~/ (2 * c.w), (2 * c.y + 1) * g.$2 ~/ (2 * c.h))) ?? 'OUT OF AREA';
  }
  if (op == 'RELATE') {
    arity(4);
    final c = read(1, 2), d = read(3, 4);
    final x1 = c.x * d.w, x2 = (c.x + 1) * d.w, x3 = d.x * c.w, x4 = (d.x + 1) * c.w;
    final y1 = c.y * d.h, y2 = (c.y + 1) * d.h, y3 = d.y * c.h, y4 = (d.y + 1) * c.h;
    if (x1 == x3 && x2 == x4 && y1 == y3 && y2 == y4) return 'EQUAL';
    if (x1 >= x3 && x2 <= x4 && y1 >= y3 && y2 <= y4) return 'INSIDE';
    if (x3 >= x1 && x4 <= x2 && y3 >= y1 && y4 <= y2) return 'CONTAINS';
    if (x1 < x4 && x3 < x2 && y1 < y4 && y3 < y2) return 'OVERLAP';
    if (y1 <= y4 && y3 <= y2 && (x1 <= x4 && x3 <= x2 || c.x + 1 == c.w && d.x == 0 || d.x + 1 == d.w && c.x == 0)) return 'TOUCH';
    return 'DISJOINT';
  }
  if (op == 'SHORTEN' || op == 'RECOVER') {
    arity(3);
    final lat = coordinate(a[2], true), lon = coordinate(a[3], false);
    if (op == 'SHORTEN') {
      final c = decode(2, a[1]);
      if (c.p < 8) invalid();
      bool nearby(int limit) => (180000000 * (2 * c.y + 1) - (lat + 90000000) * 2 * c.h).abs() < limit * 2 * c.h &&
          (360000000 * (2 * c.x + 1) - (lon + 180000000) * 2 * c.w).abs() < limit * 2 * c.w;
      return nearby(15000) ? a[1].substring(6) : nearby(300000) ? a[1].substring(4) : a[1];
    }
    final short = a[1], at = short.indexOf('+');
    if (![2, 4].contains(at) || '+'.allMatches(short).length != 1 || ![0, 2, 3].contains(short.length - at - 1)) invalid();
    for (final c in short.replaceAll('+', '').split('')) index(plusDigits, c);
    final removed = 8 - at, prefix = encode(containing(2, 10, lat, lon))!.substring(0, removed), c = decode(2, prefix + short);
    var x = c.x, y = c.y;
    final distance = removed == 4 ? 1000000 : 50000, my = distance * c.h ~/ 180000000, mx = distance * c.w ~/ 360000000;
    final cy = 180000000 * (2 * y + 1), cx = 360000000 * (2 * x + 1);
    if ((lat + 90000000 + distance ~/ 2) * 2 * c.h < cy && cy - distance * 2 * c.h >= 0) y -= my;
    else if ((lat + 90000000 - distance ~/ 2) * 2 * c.h > cy && cy + distance * 2 * c.h <= 180000000 * 2 * c.h) y += my;
    if ((lon + 180000000 + distance ~/ 2) * 2 * c.w < cx) x = (x - mx) % c.w;
    else if ((lon + 180000000 - distance ~/ 2) * 2 * c.w > cx) x = (x + mx) % c.w;
    return encode(Cell(2, c.p, x, y))!;
  }
  if (op == 'UTMZONE') {
    arity(2);
    final lat = coordinate(a[1], true), lon = coordinate(a[2], false);
    if (lat < -80000000 || lat >= 84000000) return 'NONE';
    final k = (lat + 80000000) ~/ 8000000, band = bands[min(k, 19)];
    var zone = (lon + 180000000) ~/ 6000000 + 1;
    if (band == 'V' && lon >= 3000000 && lon < 12000000) zone = 32;
    if (band == 'X' && lon >= 0 && lon < 42000000) zone = lon < 9000000 ? 31 : lon < 21000000 ? 33 : lon < 33000000 ? 35 : 37;
    return '$zone$band';
  }
  if (op == 'OSGB' || op == 'MGRS') {
    arity(op == 'OSGB' ? 3 : 5);
    final mgrs = op == 'MGRS', zone = mgrs ? number(a[1], 1, 60) : 0;
    if (mgrs && (a[2].length != 1 || !bands.contains(a[2]))) invalid();
    final e = number(a[mgrs ? 3 : 1], mgrs ? 100000 : 0, mgrs ? 899999 : 699999), n = number(a[mgrs ? 4 : 2], 0, mgrs ? 9999999 : 1299999), d = number(a[mgrs ? 5 : 3], 0, 5);
    final letters = mgrs ? '${columns[zone % 3][e ~/ 100000 - 1]}${mgrsRows[(n ~/ 100000 + (zone % 2 == 0 ? 5 : 0)) % 20]}' : '${g25[5 * (3 - n ~/ 500000) + 2 + e ~/ 500000]}${g25[5 * (4 - n ~/ 100000 % 5) + e ~/ 100000 % 5]}';
    return '${mgrs ? '$zone${a[2]} ' : ''}$letters${d == 0 ? '' : ' ${decimal(e % 100000, 5).substring(0, d)} ${decimal(n % 100000, 5).substring(0, d)}'}';
  }
  if (op == 'UNOSGB' || op == 'UNMGRS') {
    final mgrs = op == 'UNMGRS', base = mgrs ? 2 : 1;
    if (a.length != base + 1 && a.length != base + 3) invalid();
    var e = 0, n = 0, size = 100000;
    if (mgrs) {
      if (!RegExp(r'^[1-9][0-9]?[C-HJ-NP-X]$').hasMatch(a[1])) invalid();
      final zone = int.parse(a[1].substring(0, a[1].length - 1));
      if (zone > 60) invalid();
      if (a[2].length != 2) invalid();
      e = 100000 * (index(columns[zone % 3], a[2][0]) + 1);
      n = 100000 * ((index(mgrsRows, a[2][1]) - (zone % 2 == 0 ? 5 : 0)) % 20);
    } else {
      if (a[1].length != 2) invalid();
      final first = index(g25, a[1][0]), second = index(g25, a[1][1]);
      e = 500000 * (first % 5 - 2) + 100000 * (second % 5);
      n = 500000 * (3 - first ~/ 5) + 100000 * (4 - second ~/ 5);
      if (e < 0 || e >= 700000 || n < 0 || n >= 1300000) invalid();
    }
    if (a.length == base + 3) {
      final east = a[base + 1], north = a[base + 2];
      if (east.isEmpty || east.length > 5 || east.length != north.length) invalid();
      size = pow(10, 5 - east.length).toInt();
      e += digits(east) * size;
      n += digits(north) * size;
    }
    return '${mgrs ? '${a[1]} ' : ''}sw=$e,$n size=$size';
  }
  if (op == 'QUADKEY') {
    arity(3);
    final z = number(a[3], 1, 23), x = number(a[1], 0, (1 << z) - 1), y = number(a[2], 0, (1 << z) - 1);
    return [for (var i = z - 1; i >= 0; i--) '${((x >> i) & 1) + 2 * ((y >> i) & 1)}'].join();
  }
  if (op == 'UNQUADKEY') {
    arity(1);
    final key = a[1];
    if (key.isEmpty || key.length > 23) invalid();
    var x = 0, y = 0;
    for (final c in key.split('')) {
      final v = index('0123', c);
      x = 2 * x + v % 2;
      y = 2 * y + v ~/ 2;
    }
    return 'x=$x y=$y z=${key.length}';
  }
  invalid();
}
void main() {
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      print(execute(line));
    } on Invalid {
      print('INVALID');
    }
  }
}
