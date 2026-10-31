class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);
  @override
  bool operator ==(Object other) => other is Point && x == other.x && y == other.y;
  @override
  int get hashCode => Object.hash(x, y);
}

typedef Mask = List<List<bool>>;
const neighborhood = [Point(0, -1), Point(1, -1), Point(1, 0), Point(1, 1), Point(0, 1), Point(-1, 1), Point(-1, 0), Point(-1, -1)];

Mask newMask(int width, int height) => List.generate(height, (_) => List.filled(width, false));
bool occupied(Mask mask, int x, int y) => y >= 0 && y < mask.length && x >= 0 && x < mask.first.length && mask[y][x];

Mask erode(Mask mask, List<Point> offsets) => List.generate(mask.length, (y) => List.generate(mask.first.length, (x) =>
    offsets.every((offset) => occupied(mask, x + offset.x, y + offset.y))));
Mask dilate(Mask mask, List<Point> offsets) => List.generate(mask.length, (y) => List.generate(mask.first.length, (x) =>
    offsets.any((offset) => occupied(mask, x - offset.x, y - offset.y))));
Mask opening(Mask mask, List<Point> offsets) => dilate(erode(mask, offsets), offsets);
Mask closing(Mask mask, List<Point> offsets) => erode(dilate(mask, offsets), offsets);

List<bool> neighborBits(Set<Point> pixels, Point point) => [for (final offset in neighborhood) pixels.contains(Point(point.x + offset.x, point.y + offset.y))];

int transitions(List<bool> bits) {
  var count = 0;
  for (var i = 0; i < 8; i++) {
    if (!bits[i] && bits[(i + 1) % 8]) {
      count++;
    }
  }
  return count;
}

int crossingNumber(Set<Point> pixels, Point point) => transitions(neighborBits(pixels, point));

bool removable(List<bool> bits, bool first) {
  final count = bits.where((bit) => bit).length;
  if (count < 2 || count > 6 || transitions(bits) != 1) {
    return false;
  }
  final p2 = bits[0], p4 = bits[2], p6 = bits[4], p8 = bits[6];
  return first ? !(p2 && p4 && p6) && !(p4 && p6 && p8) : !(p2 && p4 && p8) && !(p2 && p6 && p8);
}

bool thinningStep(Set<Point> pixels, bool first) {
  final removed = pixels.where((point) => removable(neighborBits(pixels, point), first)).toList();
  pixels.removeAll(removed);
  return removed.isNotEmpty;
}

Set<Point> thin(List<Point> pixels) {
  final skeleton = pixels.toSet();
  while (true) {
    final first = thinningStep(skeleton, true);
    final second = thinningStep(skeleton, false);
    if (!first && !second) {
      return skeleton;
    }
  }
}
