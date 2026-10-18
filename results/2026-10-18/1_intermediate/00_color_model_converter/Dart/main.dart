import 'dart:io';
import 'dart:math' as math;

typedef Color = List<int>;
class Invalid implements Exception {}

const names = [
  'black', 'maroon', 'green', 'olive', 'navy', 'purple', 'teal', 'silver',
  'gray', 'red', 'lime', 'yellow', 'blue', 'magenta', 'cyan', 'white',
  'orange', 'pink', 'brown', 'gold', 'coral', 'salmon', 'violet', 'indigo',
];
const builtins = <Color>[
  [0, 0, 0], [128, 0, 0], [0, 128, 0], [128, 128, 0],
  [0, 0, 128], [128, 0, 128], [0, 128, 128], [192, 192, 192],
  [128, 128, 128], [255, 0, 0], [0, 255, 0], [255, 255, 0],
  [0, 0, 255], [255, 0, 255], [0, 255, 255], [255, 255, 255],
  [255, 165, 0], [255, 192, 203], [165, 42, 42], [255, 215, 0],
  [255, 127, 80], [250, 128, 114], [238, 130, 238], [75, 0, 130],
];

// All divisions below have positive denominators. Dart's ~/ truncates, so
// negative floor and the two distinct tie rules are expressed explicitly.
int floorRatio(int n, int d) => n >= 0 ? n ~/ d : -((-n + d - 1) ~/ d);
int rounded(int n, int d) => floorRatio(2 * n + d, 2 * d);
int away(int n, int d) => n < 0 ? -rounded(-n, d) : rounded(n, d);
int clamp(int x) => math.max(0, math.min(255, x));
int percent(int n, int d) => rounded(100 * n, d);
bool equal(Color a, Color b) => a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
int distance(Color a, Color b) {
  var result = 0;
  for (var j = 0; j < 3; j++) {
    final d = a[j] - b[j];
    result += d * d;
  }
  return result;
}

int squareRoot(int n) {
  var lo = 0, hi = n + 1;
  while (lo + 1 < hi) {
    final mid = (lo + hi) ~/ 2;
    if (mid <= n ~/ mid) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

String hexColor(Color c) => '#${c.map((x) => x.toRadixString(16).toUpperCase().padLeft(2, '0')).join()}';
String colorSequence(Iterable<Color> colors) => colors.map(hexColor).join(' ');
int integer(String s, int lo, int hi) {
  if (!RegExp(r'^-?[0-9]{1,9}$').hasMatch(s))
    throw Invalid();
  final value = int.parse(s);
  if (value < lo || value > hi)
    throw Invalid();
  return value;
}
List<int> hsl(Color c) {
  final m = c.reduce(math.max), n = c.reduce(math.min), d = m - n;
  return [hue(c), d == 0 ? 0 : percent(d, 255 - (m + n - 255).abs()), percent(m + n, 510)];
}

int hue(Color c) {
  final r = c[0], g = c[1], b = c[2];
  final m = c.reduce(math.max), n = c.reduce(math.min), d = m - n;
  if (d == 0)
    return 0;
  var numerator = m == r ? 60 * (g - b) : m == g ? 60 * (b - r) + 120 * d : 60 * (r - g) + 240 * d;
  if (numerator < 0)
    numerator += 360 * d;
  return rounded(numerator, d) % 360;
}
// base(h,C) has components C * factor / 60. These integer factors
// let each inverse conversion combine all fractions before its only round.
List<int> baseFactors(int h) {
  final q = h ~/ 60, f = h % 60, x = q.isEven ? f : 60 - f;
  return switch (q) {
    0 => [60, x, 0],
    1 => [x, 60, 0],
    2 => [0, 60, x],
    3 => [0, x, 60],
    4 => [x, 0, 60],
    _ => [60, 0, x],
  };
}
Color fromHsl(int h, int s, int l) {
  final c = (100 - (2 * l - 100).abs()) * s;
  return [for (final f in baseFactors(h)) rounded(255 * (2 * c * f + 60 * (200 * l - c)), 1200000)];
}
Color fromHsv(int h, int s, int v) {
  final c = v * s;
  return [for (final f in baseFactors(h)) rounded(255 * (c * f + 60 * (100 * v - c)), 600000)];
}
Color fromHwb(int h, int w, int k) {
  if (w + k >= 100)
    return List.filled(3, rounded(255 * w, w + k));
  return [for (final f in baseFactors(h)) rounded(255 * (f * (100 - w - k) + 60 * w), 6000)];
}
List<int> hsv(Color c) {
  final m = c.reduce(math.max), n = c.reduce(math.min);
  return [hue(c), m == 0 ? 0 : percent(m - n, m), percent(m, 255)];
}
List<int> hwb(Color c) => [hue(c), percent(c.reduce(math.min), 255), percent(255 - c.reduce(math.max),
  255)];
List<int> cmyk(Color c) {
  final m = c.reduce(math.max);
  return m == 0 ? [0, 0, 0, 100] : [for (final x in c) percent(m - x, m), percent(255 - m, 255)];
}
List<int> ycbcr(Color c) {
  final r = c[0], g = c[1], b = c[2];
  return [clamp(rounded(299 * r + 587 * g + 114 * b, 1000)), clamp(rounded(128000 - 169 * r - 331 * g + 500 * b,
    1000)), clamp(rounded(128000 + 500 * r - 419 * g - 81 * b, 1000))];
}
List<int> yiq(Color c) {
  final r = c[0], g = c[1], b = c[2];
  return [rounded(299 * r + 587 * g + 114 * b, 1000), rounded(596 * r - 274 * g - 322 * b, 1000),
    rounded(211 * r - 523 * g + 312 * b, 1000)];
}

String triple(String label, List<int> v, bool percentages) => '$label(${v[0]},${v[1]}${percentages ? '%' : ''},${v[2]}${percentages ? '%' : ''})';
String model(String op, Color c) => switch (op) {
  'HSL' => triple('hsl', hsl(c), true),
  'HSV' => triple('hsv', hsv(c), true),
  'HWB' => triple('hwb', hwb(c), true),
  'CMYK' => 'cmyk(${cmyk(c).map((v) => '$v%').join(',')})',
  'YCBCR' => triple('ycbcr', ycbcr(c), false),
  _ => triple('yiq', yiq(c), false),
};
Color ansi(int n) {
  if (n < 16)
    return builtins[n];
  if (n >= 232)
    return List.filled(3, 8 + 10 * (n - 232));
  const v = [0, 95, 135, 175, 215, 255];
  final i = n - 16;
  return [v[i ~/ 36], v[(i ~/ 6) % 6], v[i % 6]];
}

int luminance(Color c) => 2126 * c[0] * c[0] + 7152 * c[1] * c[1] + 722 * c[2] * c[2];
(int, String) contrast(Color a, Color b) {
  final y1 = luminance(a), y2 = luminance(b);
  final high = math.max(y1, y2) + 32512500, low = math.min(y1, y2) + 32512500;
  return (rounded(100 * high, low), high >= 7 * low ? 'AAA' : 2 * high >= 9 * low ? 'AA' : 'FAIL');
}

String contrastText(Color a, Color b) {
  final result = contrast(a, b), r = result.$1;
  return '${r ~/ 100}.${(r % 100).toString().padLeft(2, '0')} ${result.$2}';
}
Color rotated(Color c, int d) {
  final v = hsl(c);
  return fromHsl((v[0] + d) % 360, v[1], v[2]);
}
Color gradientColor(Color a, Color b, int i, int denominator) => [for (var j = 0; j < 3; j++) a[j] + away((b[j] - a[j]) * i,
  denominator)];
class Box {
  final List<Color> colors;
  Box(this.colors);
  List<int> ranges() => [for (var j = 0; j < 3; j++) colors.map((c) => c[j]).reduce(math.max) - colors.map((c)
    => c[j]).reduce(math.min)];
  Color mean() => [for (var j = 0; j < 3; j++) rounded(colors.fold(0, (s, c) => s + c[j]), colors.length)];
}
List<Box> palette(int k, List<Color> colors) {
  final boxes = [Box(colors.toList())];
  while (boxes.length < k) {
    var selected = -1, width = -1;
    for (var i = 0; i < boxes.length; i++) {
      if (boxes[i].colors.length < 2)
        continue;
      final w = boxes[i].ranges().reduce(math.max);
      if (w > width) {
        selected = i;
        width = w;
      }
    }
    final box = boxes[selected], ranges = box.ranges();
    var component = 0;
    for (var j = 1; j < 3; j++) {
      if (ranges[j] > ranges[component])
        component = j;
    }
    // Stable insertion sort, including duplicate RGB values and equal channels.
    final sorted = box.colors.toList();
    for (var i = 1; i < sorted.length; i++) {
      final c = sorted[i];
      var j = i;
      while (j > 0 && sorted[j - 1][component] > c[component]) {
        sorted[j] = sorted[j - 1];
        j--;
      }
      sorted[j] = c;
    }
    final middle = sorted.length ~/ 2;
    boxes.replaceRange(selected, selected + 1, [Box(sorted.sublist(0, middle)), Box(sorted.sublist(middle))]);
  }
  return boxes;
}

int blendComponent(String mode, int x, int y) {
  final multiply = x * y ~/ 255, screen = 255 - (255 - x) * (255 - y) ~/ 255;
  return switch (mode) {
    'MULTIPLY' => multiply,
    'SCREEN' => screen,
    'OVERLAY' => x < 128 ? 2 * x * y ~/ 255 : 255 - 2 * (255 - x) * (255 - y) ~/ 255,
    'HARDLIGHT' => y < 128 ? 2 * x * y ~/ 255 : 255 - 2 * (255 - x) * (255 - y) ~/ 255,
    'SOFTLIGHT' => ((255 - x) * multiply + x * screen) ~/ 255,
    'DARKEN' => math.min(x, y),
    'LIGHTEN' => math.max(x, y),
    'DIFFERENCE' => (x - y).abs(),
    'EXCLUSION' => x + y - 2 * x * y ~/ 255,
    'ADD' => math.min(255, x + y),
    'SUBTRACT' => math.max(0, x - y),
    'COLORDODGE' => y == 255 ? 255 : math.min(255, 255 * x ~/ (255 - y)),
    'COLORBURN' => y == 0 ? 0 : math.max(0, 255 - 255 * (255 - x) ~/ y),
    _ => throw Invalid(),
  };
}

class Engine {
  // Dart maps retain insertion order; replacing a value preserves its position.
  final registered = <String, Color>{};
  Color color(String text) {
    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(text)) {
      return [for (var i = 1; i < 7; i += 2) int.parse(text.substring(i, i + 2), radix: 16)];
    }
    if (RegExp(r'^#[0-9a-fA-F]{3}$').hasMatch(text)) {
      return [for (var i = 1; i < 4; i++) 17 * int.parse(text[i], radix: 16)];
    }
    final match = RegExp(r'^rgb\(([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})\)$').firstMatch(text);
    if (match != null) {
      final result = [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
      if (result.every((x) => x <= 255))
        return result;
      throw Invalid();
    }
    final index = names.indexOf(text);
    if (index >= 0)
      return builtins[index];
    final saved = registered[text];
    if (saved != null)
      return saved;
    throw Invalid();
  }

  String execute(String line) {
    final words = line.split(' '), op = words.first, a = words.skip(1).toList();
    void count(int n) {
      if (a.length != n)
        throw Invalid();
    }
    int number(int i, int lo, int hi) => integer(a[i], lo, hi);
    List<Color> allColors(int start) => a.skip(start).map(color).toList();
    if (op == 'DEFINE') {
      count(2);
      if (!RegExp(r'^[a-z]{1,12}$').hasMatch(a[0]) || names.contains(a[0]))
        throw Invalid();
      final value = color(a[1]);
      registered[a[0]] = value;
      return '${a[0]} ${hexColor(value)}';
    }
    if (op == 'UNDEFINE') {
      count(1);
      if (!RegExp(r'^[a-z]{1,12}$').hasMatch(a[0]) || !registered.containsKey(a[0]))
        throw Invalid();
      registered.remove(a[0]);
      return '${a[0]} removed';
    }
    if (op == 'LIST') {
      count(0);
      final keys = registered.keys.toList()..sort();
      return keys.isEmpty ? 'NONE' : keys.map((name) => '$name=${hexColor(registered[name]!)}').join(' ');
    }
    if (['HSL', 'HSV', 'HWB', 'CMYK', 'YCBCR', 'YIQ', 'PARSE'].contains(op)) {
      count(1);
      final c = color(a[0]);
      if (op != 'PARSE')
        return model(op, c);
      var name = '-';
      for (var i = 0; i < names.length; i++) {
        if (equal(c, builtins[i])) {
          name = names[i];
          break;
        }
      }
      if (name == '-') {
        for (final entry in registered.entries) {
          if (equal(c, entry.value)) {
            name = entry.key;
            break;
          }
        }
      }
      return '${hexColor(c)} rgb(${c.join(',')}) ${['HSL', 'HSV', 'HWB', 'CMYK', 'YCBCR', 'YIQ'].map((m) => model(m, c)).join(' ')} $name';
    }
    if (['FROMHSL', 'FROMHSV', 'FROMHWB'].contains(op)) {
      count(3);
      final h = number(0, 0, 359), s = number(1, 0, 100), v = number(2, 0, 100);
      return hexColor(op == 'FROMHSL' ? fromHsl(h, s, v) : op == 'FROMHSV' ? fromHsv(h, s, v) : fromHwb(h,
        s, v));
    }
    if (op == 'FROMCMYK') {
      count(4);
      final c = number(0, 0, 100), m = number(1, 0, 100), y = number(2, 0, 100), k = number(3, 0, 100);
      return hexColor([for (final v in [c, m, y]) rounded(255 * (100 - v) * (100 - k), 10000)]);
    }
    if (op == 'FROMYCBCR' || op == 'FROMYIQ') {
      count(3);
      final y = number(0, 0, 255), u = number(1, op == 'FROMYIQ' ? -255 : 0, 255), v = number(2, op == 'FROMYIQ' ? -255 : 0,
        255);
      final values = op == 'FROMYIQ' ? [1000 * y + 956 * u + 619 * v, 1000 * y - 272 * u - 647 * v,
        1000 * y - 1106 * u + 1703 * v]: [1000 * y + 1402 * (v - 128), 1000 * y - 344 * (u - 128) - 714 * (v - 128),
        1000 * y + 1772 * (u - 128)];
      return hexColor(values.map((x) => clamp(rounded(x, 1000))).toList());
    }
    if (op == 'FROM565') {
      count(1);
      if (!RegExp(r'^0x[0-9a-fA-F]{4}$').hasMatch(a[0]))
        throw Invalid();
      final v = int.parse(a[0].substring(2), radix: 16);
      return hexColor([rounded(255 * (v ~/ 2048), 31), rounded(255 * ((v ~/ 32) % 64), 63), rounded(255 * (v % 32),
        31)]);
    }
    if (op == 'FROMANSI') {
      count(1);
      return hexColor(ansi(number(0, 0, 255)));
    }
    if (op == 'RGB565') {
      count(1);
      final c = color(a[0]), v = 2048 * rounded(31 * c[0], 255) + 32 * rounded(63 * c[1], 255) + rounded(31 * c[2],
        255);
      return '0x${v.toRadixString(16).toUpperCase().padLeft(4, '0')}';
    }
    if (op == 'ANSI') {
      count(1);
      final c = color(a[0]);
      var best = 16;
      for (var i = 17; i <= 255; i++) {
        if (distance(c, ansi(i)) < distance(c, ansi(best)))
          best = i;
      }
      return '$best ${hexColor(ansi(best))} ${distance(c, ansi(best))}';
    }
    if (op == 'WEBSAFE' || op == 'INVERT') {
      count(1);
      final c = color(a[0]);
      return hexColor([for (final x in c) op == 'INVERT' ? 255 - x : 51 * rounded(x, 51)]);
    }
    if (op == 'GRAY') {
      count(2);
      final c = color(a[0]), r = c[0], g = c[1], b = c[2];
      final value = switch (a[1]) {
        'LUMA' => rounded(299 * r + 587 * g + 114 * b, 1000),
        'AVERAGE' => rounded(r + g + b, 3),
        'LIGHTNESS' => rounded(c.reduce(math.max) + c.reduce(math.min), 2),
        'HSP' => squareRoot((299 * r * r + 587 * g * g + 114 * b * b) ~/ 1000),
        _ => throw Invalid(),
      };
      return hexColor(List.filled(3, value));
    }
    if (op == 'MIX' || op == 'MIXHSL') {
      count(3);
      final c1 = color(a[0]), c2 = color(a[1]), p = number(2, 0, 100);
      if (op == 'MIX')
        return hexColor([for (var j = 0; j < 3; j++) rounded(c1[j] * (100 - p) + c2[j] * p, 100)]);
      final v1 = hsl(c1), v2 = hsl(c2);
      var e = (v2[0] - v1[0]) % 360;
      if (e > 180)
        e -= 360;
      return hexColor(fromHsl((v1[0] + away(e * p, 100)) % 360, v1[1] + away((v2[1] - v1[1]) * p, 100),
        v1[2] + away((v2[2] - v1[2]) * p, 100)));
    }
    if (op == 'GRADIENT') {
      count(3);
      final c1 = color(a[0]), c2 = color(a[1]), n = number(2, 2, 16);
      return colorSequence([for (var i = 0; i < n; i++) gradientColor(c1, c2, i, n - 1)]);
    }
    if (['TINTS', 'SHADES', 'TONES'].contains(op)) {
      count(2);
      final c = color(a[0]), n = number(1, 1, 10), target = List.filled(3, op == 'TINTS' ? 255 : op == 'SHADES' ? 0 : 128);
      return colorSequence([for (var i = 1; i <= n; i++) gradientColor(c, target, i, n + 1)]);
    }
    if (op == 'BLEND') {
      count(3);
      final base = color(a[1]), top = color(a[2]), mode = a[0];
      if (['HUE', 'SATURATION', 'COLOR', 'LUMINOSITY'].contains(mode)) {
        final v1 = hsl(base), v2 = hsl(top);
        return hexColor(fromHsl(mode == 'HUE' || mode == 'COLOR' ? v2[0] : v1[0], mode == 'SATURATION' || mode == 'COLOR' ? v2[1] : v1[1],
          mode == 'LUMINOSITY' ? v2[2] : v1[2]));
      }
      return hexColor([for (var j = 0; j < 3; j++) blendComponent(mode, base[j], top[j])]);
    }
    if (op == 'ALPHA') {
      count(4);
      final fg = color(a[0]), p = number(1, 0, 100), bg = color(a[2]), q = number(3, 0, 100), opacity = 100 * p + q * (100 - p);
      final c = opacity == 0 ? [0, 0, 0] : [for (var j = 0; j < 3; j++) rounded(100 * p * fg[j] + q * (100 - p) * bg[j],
        opacity)];
      return '${hexColor(c)} ${rounded(opacity, 100)}%';
    }
    if (op == 'SIMULATE') {
      count(2);
      final c = color(a[0]);
      final coefficients = switch (a[1]) {
        'PROTANOPIA' => [[567, 433, 0], [558, 442, 0], [0, 242, 758]],
        'DEUTERANOPIA' => [[625, 375, 0], [700, 300, 0], [0, 300, 700]],
        'TRITANOPIA' => [[950, 50, 0], [0, 433, 567], [0, 475, 525]],
        'ACHROMATOPSIA' => [[299, 587, 114], [299, 587, 114], [299, 587, 114]],
        _ => throw Invalid(),
      };
      return hexColor([for (final row in coefficients) rounded(row[0] * c[0] + row[1] * c[1] + row[2] * c[2],
        1000)]);
    }
    if (op == 'ROTATE') {
      count(2);
      return hexColor(rotated(color(a[0]), number(1, -720, 720)));
    }
    if (['COMPLEMENT', 'TRIADIC', 'TETRADIC', 'SPLITCOMP'].contains(op)) {
      count(1);
      final c = color(a[0]);
      final offsets = switch (op) {
        'COMPLEMENT' => [180],
        'TRIADIC' => [120, 240],
        'TETRADIC' => [90, 180, 270],
        _ => [150, 210]
      };
      return colorSequence(offsets.map((d) => rotated(c, d)));
    }
    if (op == 'ANALOGOUS') {
      count(3);
      final c = color(a[0]), k = number(1, 1, 6), step = number(2, 1, 60);
      return colorSequence([for (var i = -k; i <= k; i++) if (i != 0) rotated(c, i * step)]);
    }
    if (['LIGHTEN', 'DARKEN', 'SATURATE', 'DESATURATE'].contains(op)) {
      count(2);
      final v = hsl(color(a[0])), p = number(1, 0, 100);
      final j = op == 'LIGHTEN' || op == 'DARKEN' ? 2 : 1;
      v[j] = op == 'LIGHTEN' || op == 'SATURATE' ? math.min(100, v[j] + p) : math.max(0, v[j] - p);
      return hexColor(fromHsl(v[0], v[1], v[2]));
    }
    if (op == 'NEAREST') {
      count(1);
      final c = color(a[0]);
      var bestName = names[0], bestColor = builtins[0], d = distance(c, bestColor);
      for (var i = 1; i < names.length; i++) {
        final next = distance(c, builtins[i]);
        if (next < d) {
          d = next;
          bestName = names[i];
          bestColor = builtins[i];
        }
      }
      for (final entry in registered.entries) {
        final next = distance(c, entry.value);
        if (next < d) {
          d = next;
          bestName = entry.key;
          bestColor = entry.value;
        }
      }
      return '$bestName ${hexColor(bestColor)} $d';
    }
    if (op == 'DISTANCE') {
      count(2);
      final c1 = color(a[0]), c2 = color(a[1]), r = c1[0] - c2[0], g = c1[1] - c2[1], b = c1[2] - c2[2];
      final w = (1024 + c1[0] + c2[0]) * r * r + 2048 * g * g + (1534 - c1[0] - c2[0]) * b * b;
      return '${distance(c1, c2)} ${squareRoot(w ~/ 512)}';
    }
    if (op == 'CONTRAST') {
      count(2);
      return contrastText(color(a[0]), color(a[1]));
    }
    if (op == 'ACCESSIBLE') {
      count(2);
      final fg = color(a[0]), bg = color(a[1]);
      var result = fg;
      if (contrast(fg, bg).$2 == 'FAIL') {
        final v = hsl(fg);
        var found = false;
        for (var t = 1; t <= 100 && !found; t++) {
          for (final l in [v[2] - t, v[2] + t]) {
            if (l < 0 || l > 100)
              continue;
            final candidate = fromHsl(v[0], v[1], l);
            if (contrast(candidate, bg).$2 != 'FAIL') {
              result = candidate;
              found = true;
              break;
            }
          }
        }
      }
      return '${hexColor(result)} ${contrastText(result, bg)}';
    }
    if (op == 'BEST') {
      if (a.length < 2 || a.length > 33)
        throw Invalid();
      final colors = allColors(0), bg = colors[0];
      var best = 1;
      for (var i = 2; i < colors.length; i++) {
        if (contrast(colors[i], bg).$1 > contrast(colors[best], bg).$1)
          best = i;
      }
      return '${hexColor(colors[best])} ${contrastText(colors[best], bg)}';
    }
    if (op == 'DESCRIBE') {
      count(1);
      final v = hsl(color(a[0])), h = v[0], s = v[1], l = v[2];
      if (l <= 5)
        return 'black';
      if (l >= 95)
        return 'white';
      final lightness = l <= 20 ? 'very dark' : l <= 40 ? 'dark' : l <= 60 ? 'medium' : l <= 80 ? 'light' : 'very light';
      if (s < 10)
        return '$lightness gray';
      const hues = ['red', 'orange', 'yellow', 'chartreuse', 'green', 'spring-green', 'cyan', 'azure',
        'blue', 'violet', 'magenta', 'rose'];
      return '$lightness ${s < 40 ? 'muted' : s < 80 ? 'moderate' : 'vivid'} ${hues[((h + 15) % 360) ~/ 30]}';
    }
    if (op == 'PALETTE' || op == 'KMEANS') {
      if (a.length < 2 || a.length > 33)
        throw Invalid();
      final k = number(0, 1, a.length - 1), colors = allColors(1), boxes = palette(k, colors);
      if (op == 'PALETTE')
        return boxes.map((box) => '${hexColor(box.mean())}:${box.colors.length}').join(' ');
      var representatives = boxes.map((box) => box.mean()).toList();
      var counts = List.filled(k, 0), iterations = 0;
      for (var t = 0; t < 20; t++) {
        iterations++;
        counts = List.filled(k, 0);
        final sums = List.generate(k, (_) => List.filled(3, 0));
        for (final c in colors) {
          var best = 0;
          for (var j = 1; j < k; j++) {
            if (distance(c, representatives[j]) < distance(c, representatives[best]))
              best = j;
          }
          counts[best]++;
          for (var j = 0; j < 3; j++)
            sums[best][j] += c[j];
        }
        final next = [for (var j = 0; j < k; j++) counts[j] == 0 ? representatives[j] : [for (var channel = 0; channel < 3; channel++) rounded(sums[j][channel],
          counts[j])]];
        final unchanged = [for (var j = 0; j < k; j++) equal(next[j], representatives[j])].every((x) => x);
        representatives = next;
        if (unchanged)
          break;
      }
      return '$iterations ${[for (var j = 0; j < k; j++) '${hexColor(representatives[j])}:${counts[j]}'].join(' ')}';
    }
    if (op == 'SORT') {
      if (a.isEmpty || a.length > 32)
        throw Invalid();
      final colors = allColors(0);
      int compare(Color a, Color b) {
        final x = hsl(a), y = hsl(b);
        for (var j = 0; j < 3; j++) {
          final c = x[j].compareTo(y[j]);
          if (c != 0)
            return c;
        }
        return 0;
      }
      for (var i = 1; i < colors.length; i++) {
        final c = colors[i];
        var j = i;
        while (j > 0 && compare(colors[j - 1], c) > 0) {
          colors[j] = colors[j - 1];
          j--;
        }
        colors[j] = c;
      }
      return colorSequence(colors);
    }
    if (op == 'DITHER') {
      if (a.isEmpty || a.length > 32)
        throw Invalid();
      final colors = allColors(0), result = <String>[];
      var error = [0, 0, 0];
      for (final c in colors) {
        final corrected = [for (var j = 0; j < 3; j++) clamp(c[j] + error[j])];
        var best = 0;
        for (var j = 1; j < 16; j++) {
          if (distance(corrected, builtins[j]) < distance(corrected, builtins[best]))
            best = j;
        }
        result.add(names[best]);
        error = [for (var j = 0; j < 3; j++) corrected[j] - builtins[best][j]];
      }
      return result.join(' ');
    }
    if (op == 'RANDOM') {
      count(2);
      var state = number(0, 1, 999999999);
      final n = number(1, 1, 16), colors = <Color>[];
      for (var i = 0; i < n; i++) {
        state = state * 48271 % 2147483647;
        final h = state % 360;
        state = state * 48271 % 2147483647;
        final s = 40 + state % 61;
        state = state * 48271 % 2147483647;
        final l = 25 + state % 51;
        colors.add(fromHsl(h, s, l));
      }
      return colorSequence(colors);
    }
    throw Invalid();
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!), engine = Engine(), output = StringBuffer();
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      output.writeln(engine.execute(line));
    } on Invalid {
      output.writeln('INVALID');
    }
  }
  stdout.write(output);
}
