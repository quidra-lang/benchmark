part of 'main.dart';

class Corner {
  int number = 0;
  final Point point;
  final int response;
  String match = 'none';
  Corner(this.point, this.response);
}

(List<Corner>, int) harris(Image gx, Image gy, Params p) {
  final width = gx.first.length,
      height = gx.length,
      response = newImage(width, height),
      half = p.integer('harris_window') ~/ 2;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var xx = 0, yy = 0, xy = 0;
      for (var j = -half; j <= half; j++) {
        for (var i = -half; i <= half; i++) {
          final a = reference(gx, x + i, y + j),
              b = reference(gy, x + i, y + j);
          xx += a * a;
          yy += b * b;
          xy += a * b;
        }
      }
      final trace = xx + yy;
      response[y][x] = xx * yy - xy * xy - trace * trace ~/ 25;
    }
  }
  final candidates = <Corner>[];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = response[y][x];
      if (value < p.integer('harris_threshold')) {
        continue;
      }
      var peak = true;
      for (final q in neighbors((x, y), width, height)) {
        final other = response[q.$2][q.$1];
        if (other > value ||
            other == value && (q.$2 < y || q.$2 == y && q.$1 < x)) {
          peak = false;
          break;
        }
      }
      if (peak) {
        candidates.add(Corner((x, y), value));
      }
    }
  }
  candidates.sort((a, b) {
    final r = b.response.compareTo(a.response),
        y = a.point.$2.compareTo(b.point.$2);
    return r != 0
        ? r
        : y != 0
        ? y
        : a.point.$1.compareTo(b.point.$1);
  });
  final selected = candidates.take(p.integer('harris_max_count')).toList();
  for (var i = 0; i < selected.length; i++) {
    selected[i].number = i + 1;
  }
  return (selected, candidates.length);
}
