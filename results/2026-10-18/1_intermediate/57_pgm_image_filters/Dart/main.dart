import 'dart:io';
import 'dart:math' as math;

typedef Point = (int, int);

const adjacent4 = <Point>[(0, -1), (-1, 0), (1, 0), (0, 1)];
const adjacent8 = <Point>[
  (-1, -1), (0, -1), (1, -1), (-1, 0),
  (1, 0), (-1, 1), (0, 1), (1, 1)
];
const shades = '@#*+=~-:,.';
const patterns = <String, String>{
  'NEW': 'iiii', 'OUTPUT': '', 'INVERT': '', 'BRIGHTNESS': 'i',
  'CONTRAST': 'ii', 'THRESHOLD': 'i', 'LEVELS': 'ii', 'POSTERIZE': 'i',
  'MAXVAL': 'i', 'FLIPH': '', 'FLIPV': '', 'ROTATE': 'i',
  'CROP': 'iiii', 'PAD': 'ii', 'SCALE': 'ii', 'SHIFT': 'iii',
  'TILE': 'ii', 'BLUR': '', 'GAUSS': '', 'SHARPEN': '',
  'CONVOLVE': 'iiiiiiiiii', 'SOBEL': '', 'MEDIAN': '', 'ERODE': '',
  'DILATE': '', 'OPEN': '', 'CLOSE': '', 'GRADIENT': '',
  'LINE': 'iiiii', 'RECT': 'iiiii', 'CIRCLE': 'iiii', 'FLOOD': 'iii',
  'HISTOGRAM': '', 'EQUALIZE': '', 'LABEL': 'i', 'DISTANCE': 'i',
  'STATS': '', 'REGION': 'iiii', 'DITHER': '', 'ASCIIART': '',
  'STORE': 'n', 'RECALL': 'n', 'DROP': 'n', 'BLEND': 'nii',
  'DIFF': 'n', 'PASTE': 'nii', 'SLOTS': '', 'INFO': '',
  'UNDO': '', 'REDO': ''
};
const imageless = {'NEW', 'RECALL', 'DROP', 'SLOTS', 'INFO', 'UNDO', 'REDO'};
const needsSlot = {'RECALL', 'DROP', 'BLEND', 'DIFF', 'PASTE'};
const kernels = <String, (List<int>, int)>{
  'BLUR': ([1, 1, 1, 1, 1, 1, 1, 1, 1], 9),
  'GAUSS': ([1, 2, 1, 2, 4, 2, 1, 2, 1], 16),
  'SHARPEN': ([0, -1, 0, -1, 5, -1, 0, -1, 0], 1)
};

class CommandError implements Exception {
  final String reason;
  CommandError(this.reason);
}

void check(bool condition, [String reason = 'bad value']) {
  if (!condition) throw CommandError(reason);
}

int clamp(int value, int low, int high) => math.min(math.max(value, low), high);
int floorDiv(int x, int n) => x >= 0 ? x ~/ n : -((-x + n - 1) ~/ n);
bool withinLimit(Iterable<int> values) => values.every((v) => v >= -1000 && v <= 1000);
int sum(Iterable<int> values) => values.fold(0, (total, value) => total + value);

class Image {
  final int width, height, maxval;
  final List<int> pixels;
  Image(this.width, this.height, this.maxval, this.pixels);

  int get(int x, int y) => pixels[y * width + x];
  bool contains(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;
  int clampPixel(int value) => clamp(value, 0, maxval);
  Image withPixels(List<int> values) => Image(width, height, maxval, values);
  Image mapPixels(int Function(int) change) => withPixels(pixels.map(change).toList());
  List<int> row(int y) => pixels.sublist(y * width, (y + 1) * width);

  List<int> neighborhood(int x, int y) {
    final values = <int>[];
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        values.add(get(clamp(x + dx, 0, width - 1), clamp(y + dy, 0, height - 1)));
      }
    }
    return values;
  }

  String summary() {
    var checksum = 0;
    for (var i = 0; i < pixels.length; i++) checksum += (i + 1) * pixels[i];
    return '${width}x$height maxval $maxval checksum $checksum';
  }
}

Image loadPgm(List<String> lines) {
  final words = <String>[];
  for (final line in lines) {
    final content = line.split('#').first.trim();
    if (content.isNotEmpty) words.addAll(content.split(RegExp(r' +')));
  }
  check(words.isNotEmpty && words.first == 'P2', 'bad magic');

  int header(int index, int limit, String reason) {
    check(index < words.length, 'truncated header');
    check(RegExp(r'^[0-9]+$').hasMatch(words[index]), 'bad number');
    final number = int.parse(words[index]);
    check(number >= 1 && number <= limit, reason);
    return number;
  }

  final width = header(1, 64, 'bad size');
  final height = header(2, 64, 'bad size');
  final maxval = header(3, 255, 'bad maxval');
  final count = words.length - 4;
  final pixels = <int>[];
  for (var i = 0; i < width * height; i++) {
    final x = i % width, y = i ~/ width;
    check(i < count, 'too few pixels ($count of ${width * height})');
    check(RegExp(r'^[0-9]+$').hasMatch(words[i + 4]), 'bad pixel at $x,$y');
    final value = int.parse(words[i + 4]);
    check(value <= maxval, 'pixel out of range at $x,$y');
    pixels.add(value);
  }
  check(count <= width * height, 'too many pixels ($count of ${width * height})');
  return Image(width, height, maxval, pixels);
}

Image transformed(Image image, int width, int height, int Function(int x, int y) value) {
  final pixels = <int>[];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) pixels.add(value(x, y));
  }
  return Image(width, height, image.maxval, pixels);
}

Image cropped(Image image, int left, int top, int width, int height) =>
    transformed(image, width, height, (x, y) => image.get(left + x, top + y));

Image translated(Image image, int width, int height, int dx, int dy, int fill) =>
    transformed(image, width, height, (x, y) =>
        image.contains(x - dx, y - dy) ? image.get(x - dx, y - dy) : fill);

Image convolution(Image image, List<int> weights, int divisor) =>
    transformed(image, image.width, image.height, (x, y) {
      final q = image.neighborhood(x, y);
      var value = 0;
      for (var i = 0; i < 9; i++) value += q[i] * weights[i];
      return image.clampPixel(floorDiv(value, divisor));
    });

Image rankFiltered(Image image, int rank) =>
    transformed(image, image.width, image.height, (x, y) {
      final q = image.neighborhood(x, y)..sort();
      return q[rank];
    });

Image sobel(Image image) =>
    transformed(image, image.width, image.height, (x, y) {
      final q = image.neighborhood(x, y);
      final gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6];
      final gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2];
      return image.clampPixel(gx.abs() + gy.abs());
    });

List<Point> linePoints(int x0, int y0, int x1, int y1) {
  final dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
  final sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
  var error = dx + dy, x = x0, y = y0;
  final points = <Point>[];
  while (true) {
    points.add((x, y));
    if (x == x1 && y == y1) return points;
    final twice = 2 * error;
    if (twice >= dy) { error += dy; x += sx; }
    if (twice <= dx) { error += dx; y += sy; }
  }
}

List<Point> rectanglePoints(Image image, int left, int top, int width, int height, bool fill) {
  final right = left + width - 1, bottom = top + height - 1;
  final points = <Point>[];
  for (var y = math.max(0, top); y <= math.min(bottom, image.height - 1); y++) {
    for (var x = math.max(0, left); x <= math.min(right, image.width - 1); x++) {
      if (fill || x == left || x == right || y == top || y == bottom) points.add((x, y));
    }
  }
  return points;
}

List<Point> circlePoints(int cx, int cy, int radius) {
  var a = radius, b = 0, error = 1 - radius;
  final points = <Point>[];
  while (a >= b) {
    points.addAll([
      (cx + a, cy + b), (cx + b, cy + a), (cx - b, cy + a), (cx - a, cy + b),
      (cx - a, cy - b), (cx - b, cy - a), (cx + b, cy - a), (cx + a, cy - b)
    ]);
    b++;
    if (error < 0) { error += 2 * b + 1; }
    else { a--; error += 2 * (b - a) + 1; }
  }
  return points;
}

List<Point> discPoints(Image image, List<Point> outline) {
  final rows = <int, (int, int)>{};
  for (final point in outline) {
    final x = point.$1, y = point.$2;
    final previous = rows[y];
    rows[y] = previous == null
        ? (x, x) : (math.min(previous.$1, x), math.max(previous.$2, x));
  }
  final points = <Point>[];
  for (final entry in rows.entries) {
    final y = entry.key;
    if (y < 0 || y >= image.height) continue;
    for (var x = math.max(0, entry.value.$1); x <= math.min(image.width - 1, entry.value.$2); x++) {
      points.add((x, y));
    }
  }
  return points;
}

List<Point> floodPoints(Image image, int x, int y) {
  final wanted = image.get(x, y);
  final stack = <Point>[(x, y)];
  final visited = <int>{y * image.width + x};
  final points = <Point>[];
  while (stack.isNotEmpty) {
    final point = stack.removeLast();
    final cx = point.$1, cy = point.$2;
    points.add(point);
    for (final delta in adjacent4) {
      final nx = cx + delta.$1, ny = cy + delta.$2;
      if (!image.contains(nx, ny) || image.get(nx, ny) != wanted) continue;
      final index = ny * image.width + nx;
      if (visited.add(index)) stack.add((nx, ny));
    }
  }
  return points;
}

Image equalized(Image image) {
  final counts = List<int>.filled(image.maxval + 1, 0);
  for (final pixel in image.pixels) counts[pixel]++;
  final cdf = <int>[];
  var running = 0;
  for (final count in counts) {
    running += count;
    cdf.add(running);
  }
  final size = image.pixels.length;
  final first = cdf[image.pixels.reduce(math.min)];
  if (first == size) return image.withPixels(List<int>.of(image.pixels));
  final span = size - first;
  return image.mapPixels((pixel) =>
      (2 * (cdf[pixel] - first) * image.maxval + span) ~/ (2 * span));
}

List<List<Point>> components(Image image, int threshold) {
  final visited = <int>{};
  final groups = <List<Point>>[];
  for (var start = 0; start < image.pixels.length; start++) {
    if (visited.contains(start) || image.pixels[start] < threshold) continue;
    visited.add(start);
    final stack = <Point>[(start % image.width, start ~/ image.width)];
    final group = <Point>[];
    while (stack.isNotEmpty) {
      final point = stack.removeLast();
      group.add(point);
      for (final delta in adjacent8) {
        final x = point.$1 + delta.$1, y = point.$2 + delta.$2;
        if (!image.contains(x, y)) continue;
        final index = y * image.width + x;
        if (image.pixels[index] >= threshold && visited.add(index)) stack.add((x, y));
      }
    }
    groups.add(group);
  }
  return groups;
}

String componentText(Image image, int threshold, List<Point> group) {
  var minX = image.width, minY = image.height, maxX = -1, maxY = -1;
  var sumX = 0, sumY = 0, perimeter = 0;
  for (final point in group) {
    final x = point.$1, y = point.$2;
    minX = math.min(minX, x);
    minY = math.min(minY, y);
    maxX = math.max(maxX, x);
    maxY = math.max(maxY, y);
    sumX += x;
    sumY += y;
    if (adjacent4.any((delta) {
      final nx = x + delta.$1, ny = y + delta.$2;
      return !image.contains(nx, ny) || image.get(nx, ny) < threshold;
    })) perimeter++;
  }
  final area = group.length;
  return 'area $area perimeter $perimeter box $minX $minY $maxX $maxY '
      'center ${sumX ~/ area} ${sumY ~/ area}';
}

Image distanceMap(Image image, int threshold) {
  if (image.pixels.every((pixel) => pixel >= threshold)) {
    return image.withPixels(List<int>.filled(image.pixels.length, image.maxval));
  }
  final w = image.width, h = image.height;
  final distances = image.pixels.map((pixel) => pixel < threshold ? 0 : w + h).toList();
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final index = y * w + x;
      if (x > 0) distances[index] = math.min(distances[index], distances[index - 1] + 1);
      if (y > 0) distances[index] = math.min(distances[index], distances[index - w] + 1);
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final index = y * w + x;
      if (x < w - 1) distances[index] = math.min(distances[index], distances[index + 1] + 1);
      if (y < h - 1) distances[index] = math.min(distances[index], distances[index + w] + 1);
    }
  }
  return image.withPixels(distances.map((value) => math.min(value, image.maxval)).toList());
}

String statistics(List<int> values, int maxval) {
  final sorted = List<int>.of(values)..sort();
  final counts = List<int>.filled(maxval + 1, 0);
  for (final value in values) counts[value]++;
  var mode = 0;
  for (var value = 1; value <= maxval; value++) {
    if (counts[value] > counts[mode]) mode = value;
  }
  return 'min ${sorted.first} max ${sorted.last} mean ${sum(values) ~/ values.length} '
      'median ${sorted[(values.length - 1) ~/ 2]} mode $mode';
}

Image dithered(Image image) {
  final working = List<int>.of(image.pixels);
  final pixels = List<int>.filled(working.length, 0);
  const neighbors = <(int, int, int)>[(1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1)];
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final index = y * image.width + x;
      final old = working[index];
      final value = 2 * old >= image.maxval ? image.maxval : 0;
      pixels[index] = value;
      final error = old - value;
      for (final delta in neighbors) {
        final nx = x + delta.$1, ny = y + delta.$2;
        if (image.contains(nx, ny)) {
          working[ny * image.width + nx] += floorDiv(error * delta.$3, 16);
        }
      }
    }
  }
  return image.withPixels(pixels);
}

class Command {
  final String name, slot;
  final List<int> numbers;
  final bool fill;
  Command(this.name, this.numbers, this.slot, this.fill);
}

class Editor {
  Image? current;
  final undo = <Image>[], redo = <Image>[];
  final slots = <String, Image>{};
  final output = <String>[];

  void emit(String line) => output.add(line);

  Command parseCommand(List<String> words) {
    final name = words.first;
    check(patterns.containsKey(name), 'unknown command $name');
    final pattern = patterns[name]!;
    final given = words.sublist(1);
    final fill = (name == 'RECT' || name == 'CIRCLE') &&
        given.length == pattern.length + 1 && given.last == 'FILL';
    if (fill) given.removeLast();
    check(given.length == pattern.length, 'bad arguments');
    final numbers = <int>[];
    var slot = '';
    for (var i = 0; i < given.length; i++) {
      if (pattern[i] == 'i') {
        check(RegExp(r'^(?:0|-?[1-9][0-9]{0,6})$').hasMatch(given[i]), 'bad arguments');
        numbers.add(int.parse(given[i]));
      } else {
        check(RegExp(r'^[a-z]{1,8}$').hasMatch(given[i]), 'bad arguments');
        slot = given[i];
      }
    }
    return Command(name, numbers, slot, fill);
  }

  void execute(List<String> words) {
    try {
      final command = parseCommand(words);
      if (!imageless.contains(command.name)) check(current != null, 'no image');
      if (needsSlot.contains(command.name)) {
        check(slots.containsKey(command.slot), 'no slot ${command.slot}');
      }
      run(command);
    } on CommandError catch (error) {
      emit('error: ${error.reason}');
    }
  }

  void load(List<String> lines) {
    try {
      replace(loadPgm(lines), 'loaded');
    } on CommandError catch (error) {
      emit('error: load: ${error.reason}');
    }
  }

  void replace(Image image, String label) {
    current = image;
    undo.clear();
    redo.clear();
    emit('$label ${image.summary()}');
  }

  void commit(Image image, [int? painted]) {
    undo.add(current!);
    redo.clear();
    current = image;
    emit('ok ${image.summary()}${painted == null ? '' : ' painted $painted'}');
  }

  void paint(List<Point> points, int value) {
    final image = current!;
    final painted = <int>{};
    for (final point in points) {
      if (image.contains(point.$1, point.$2)) {
        painted.add(point.$2 * image.width + point.$1);
      }
    }
    final pixels = <int>[];
    for (var i = 0; i < image.pixels.length; i++) {
      pixels.add(painted.contains(i) ? value : image.pixels[i]);
    }
    commit(image.withPixels(pixels), painted.length);
  }

  List<int> checkedCrop(List<int> a) {
    final image = current!;
    check(a[0] >= 0 && a[1] >= 0 && a[2] >= 1 && a[3] >= 1);
    check(a[0] + a[2] <= image.width && a[1] + a[3] <= image.height);
    return a;
  }

  Image matchingSlot(String name) {
    final other = slots[name]!, image = current!;
    check(other.width == image.width && other.height == image.height, 'size mismatch');
    check(other.maxval == image.maxval, 'maxval mismatch');
    return other;
  }

  void run(Command cmd) {
    final name = cmd.name, a = cmd.numbers, slot = cmd.slot;
    switch (name) {
      case 'NEW':
        check(a[0] >= 1 && a[0] <= 64 && a[1] >= 1 && a[1] <= 64);
        check(a[2] >= 1 && a[2] <= 255 && a[3] >= 0 && a[3] <= a[2]);
        replace(Image(a[0], a[1], a[2], List<int>.filled(a[0] * a[1], a[3])), 'created');
        return;
      case 'RECALL':
        replace(slots[slot]!, 'recalled $slot');
        return;
      case 'DROP':
        slots.remove(slot);
        emit('dropped $slot');
        return;
      case 'SLOTS':
        if (slots.isEmpty) emit('no slots');
        final names = slots.keys.toList()..sort();
        for (final key in names) emit('$key ${slots[key]!.summary()}');
        return;
      case 'INFO':
        emit('image ${current == null ? 'none' : current!.summary()} '
            'undo ${undo.length} redo ${redo.length} slots ${slots.length}');
        return;
      case 'UNDO':
        check(undo.isNotEmpty, 'nothing to undo');
        redo.add(current!);
        current = undo.removeLast();
        emit('undo ${current!.summary()}');
        return;
      case 'REDO':
        check(redo.isNotEmpty, 'nothing to redo');
        undo.add(current!);
        current = redo.removeLast();
        emit('redo ${current!.summary()}');
        return;
    }
    runWithImage(current!, cmd);
  }

  void runWithImage(Image image, Command cmd) {
    final name = cmd.name, a = cmd.numbers, slot = cmd.slot, fill = cmd.fill;
    final w = image.width, h = image.height, m = image.maxval;
    switch (name) {
      case 'OUTPUT':
        emit('P2');
        emit('$w $h');
        emit('$m');
        for (var y = 0; y < h; y++) emit(image.row(y).join(' '));
        break;
      case 'INVERT':
        commit(image.mapPixels((p) => m - p));
        break;
      case 'BRIGHTNESS':
        check(a[0] >= -255 && a[0] <= 255);
        commit(image.mapPixels((p) => image.clampPixel(p + a[0])));
        break;
      case 'CONTRAST':
        check(a[0] >= 0 && a[0] <= 100 && a[1] >= 1 && a[1] <= 100);
        final center = (m + 1) ~/ 2;
        commit(image.mapPixels((p) =>
            image.clampPixel(center + floorDiv((p - center) * a[0], a[1]))));
        break;
      case 'THRESHOLD':
        check(a[0] >= 0 && a[0] <= m);
        commit(image.mapPixels((p) => p >= a[0] ? m : 0));
        break;
      case 'LEVELS':
        check(a[0] >= 0 && a[0] < a[1] && a[1] <= m);
        commit(image.mapPixels((p) =>
            image.clampPixel(floorDiv((p - a[0]) * m, a[1] - a[0]))));
        break;
      case 'POSTERIZE':
        check(a[0] >= 2 && a[0] <= m + 1);
        commit(image.mapPixels((p) => (p * a[0] ~/ (m + 1) * m) ~/ (a[0] - 1)));
        break;
      case 'MAXVAL':
        check(a[0] >= 1 && a[0] <= 255);
        commit(Image(w, h, a[0],
            image.pixels.map((p) => (2 * p * a[0] + m) ~/ (2 * m)).toList()));
        break;
      case 'FLIPH':
        commit(transformed(image, w, h, (x, y) => image.get(w - 1 - x, y)));
        break;
      case 'FLIPV':
        commit(transformed(image, w, h, (x, y) => image.get(x, h - 1 - y)));
        break;
      case 'ROTATE':
        check(a[0] == 90 || a[0] == 180 || a[0] == 270);
        if (a[0] == 180) {
          commit(transformed(image, w, h, (x, y) => image.get(w - 1 - x, h - 1 - y)));
        } else if (a[0] == 90) {
          commit(transformed(image, h, w, (x, y) => image.get(y, h - 1 - x)));
        } else {
          commit(transformed(image, h, w, (x, y) => image.get(w - 1 - y, x)));
        }
        break;
      case 'CROP':
        checkedCrop(a);
        commit(cropped(image, a[0], a[1], a[2], a[3]));
        break;
      case 'PAD':
        check(a[0] >= 1 && a[1] >= 0 && a[1] <= m);
        check(w + 2 * a[0] <= 64 && h + 2 * a[0] <= 64, 'too large');
        commit(translated(image, w + 2 * a[0], h + 2 * a[0], a[0], a[0], a[1]));
        break;
      case 'SCALE':
        check(a[0] >= 1 && a[0] <= 16 && a[1] >= 1 && a[1] <= 16);
        final width = w * a[0] ~/ a[1], height = h * a[0] ~/ a[1];
        check(width > 0 && height > 0, 'too small');
        check(width <= 64 && height <= 64, 'too large');
        commit(transformed(image, width, height, (x, y) => image.get(
            (2 * x + 1) * a[1] ~/ (2 * a[0]), (2 * y + 1) * a[1] ~/ (2 * a[0]))));
        break;
      case 'SHIFT':
        check(withinLimit(a.take(2)) && a[2] >= 0 && a[2] <= m);
        commit(translated(image, w, h, a[0], a[1], a[2]));
        break;
      case 'TILE':
        check(a[0] >= 1 && a[1] >= 1);
        check(w * a[0] <= 64 && h * a[1] <= 64, 'too large');
        commit(transformed(image, w * a[0], h * a[1], (x, y) => image.get(x % w, y % h)));
        break;
      case 'BLUR':
      case 'GAUSS':
      case 'SHARPEN':
        final (weights, divisor) = kernels[name]!;
        commit(convolution(image, weights, divisor));
        break;
      case 'CONVOLVE':
        check(a.take(9).every((v) => v >= -16 && v <= 16) && a[9] >= 1 && a[9] <= 256);
        commit(convolution(image, a.take(9).toList(), a[9]));
        break;
      case 'SOBEL':
        commit(sobel(image));
        break;
      case 'MEDIAN':
        commit(rankFiltered(image, 4));
        break;
      case 'ERODE':
        commit(rankFiltered(image, 0));
        break;
      case 'DILATE':
        commit(rankFiltered(image, 8));
        break;
      case 'OPEN':
        commit(rankFiltered(rankFiltered(image, 0), 8));
        break;
      case 'CLOSE':
        commit(rankFiltered(rankFiltered(image, 8), 0));
        break;
      case 'GRADIENT':
        final high = rankFiltered(image, 8).pixels, low = rankFiltered(image, 0).pixels;
        commit(image.withPixels(List<int>.generate(high.length, (i) => high[i] - low[i])));
        break;
      case 'LINE':
        check(withinLimit(a.take(4)) && a[4] >= 0 && a[4] <= m);
        paint(linePoints(a[0], a[1], a[2], a[3]), a[4]);
        break;
      case 'RECT':
        check(withinLimit(a.take(2)) && a[2] >= 1 && a[2] <= 1000 &&
            a[3] >= 1 && a[3] <= 1000 && a[4] >= 0 && a[4] <= m);
        paint(rectanglePoints(image, a[0], a[1], a[2], a[3], fill), a[4]);
        break;
      case 'CIRCLE':
        check(withinLimit(a.take(2)) && a[2] >= 0 && a[2] <= 1000 &&
            a[3] >= 0 && a[3] <= m);
        final outline = circlePoints(a[0], a[1], a[2]);
        paint(fill ? discPoints(image, outline) : outline, a[3]);
        break;
      case 'FLOOD':
        check(image.contains(a[0], a[1]) && a[2] >= 0 && a[2] <= m);
        paint(floodPoints(image, a[0], a[1]), a[2]);
        break;
      case 'HISTOGRAM':
        final lows = List<int?>.filled(16, null);
        final highs = List<int>.filled(16, 0), counts = List<int>.filled(16, 0);
        for (var value = 0; value <= m; value++) {
          final bin = value * 16 ~/ (m + 1);
          lows[bin] ??= value;
          highs[bin] = value;
        }
        for (final pixel in image.pixels) counts[pixel * 16 ~/ (m + 1)]++;
        final top = counts.reduce(math.max);
        for (var bin = 0; bin < 16; bin++) {
          if (lows[bin] == null) continue;
          emit('${lows[bin].toString().padLeft(3)}-${highs[bin].toString().padLeft(3)} '
              '${counts[bin].toString().padLeft(4)} |'
              '${List.filled(counts[bin] * 32 ~/ top, '#').join()}');
        }
        break;
      case 'EQUALIZE':
        commit(equalized(image));
        break;
      case 'LABEL':
        check(a[0] >= 0 && a[0] <= m);
        final groups = components(image, a[0]);
        emit('labels ${groups.length}');
        for (var i = 0; i < groups.length; i++) {
          emit('label ${i + 1} ${componentText(image, a[0], groups[i])}');
        }
        break;
      case 'DISTANCE':
        check(a[0] >= 0 && a[0] <= m);
        commit(distanceMap(image, a[0]));
        break;
      case 'STATS':
        emit(statistics(image.pixels, m));
        break;
      case 'REGION':
        checkedCrop(a);
        emit(statistics(cropped(image, a[0], a[1], a[2], a[3]).pixels, m));
        break;
      case 'DITHER':
        commit(dithered(image));
        break;
      case 'ASCIIART':
        for (var y = 0; y < h; y++) {
          emit(image.row(y).map((p) => shades[p * 10 ~/ (m + 1)]).join());
        }
        break;
      case 'STORE':
        slots[slot] = image;
        emit('stored $slot ${image.summary()}');
        break;
      case 'BLEND':
        check(a[0] >= 0 && a[0] <= a[1] && a[1] >= 1 && a[1] <= 100);
        final other = matchingSlot(slot);
        commit(image.withPixels(List<int>.generate(image.pixels.length, (i) =>
            (image.pixels[i] * (a[1] - a[0]) + other.pixels[i] * a[0]) ~/ a[1])));
        break;
      case 'DIFF':
        final other = matchingSlot(slot);
        commit(image.withPixels(List<int>.generate(image.pixels.length, (i) =>
            (image.pixels[i] - other.pixels[i]).abs())));
        break;
      case 'PASTE':
        check(withinLimit(a));
        final other = slots[slot]!;
        check(other.maxval == m, 'maxval mismatch');
        final pixels = List<int>.of(image.pixels);
        var painted = 0;
        for (var y = 0; y < other.height; y++) {
          for (var x = 0; x < other.width; x++) {
            if (image.contains(a[0] + x, a[1] + y)) {
              pixels[(a[1] + y) * w + a[0] + x] = other.get(x, y);
              painted++;
            }
          }
        }
        commit(image.withPixels(pixels), painted);
        break;
    }
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final editor = Editor();
  for (var i = 0; i < count; i++) {
    final words = stdin.readLineSync()!.split(' ');
    if (words[0] == 'LOAD') {
      final length = int.parse(words[1]);
      editor.load(List<String>.generate(length, (_) => stdin.readLineSync()!));
    } else {
      editor.execute(words);
    }
  }
  for (final line in editor.output) stdout.writeln(line);
}
