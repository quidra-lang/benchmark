part of 'main.dart';

typedef Volume = List<List<int>>;
int reference(Image img, int x, int y) =>
    img.pixels[y.clamp(0, img.h - 1).toInt() * img.w +
        x.clamp(0, img.w - 1).toInt()];
List<int> boxSum(List<int> values, int w, int h, int window) {
  final radius = window ~/ 2,
      pw = w + 2 * radius,
      ph = h + 2 * radius,
      stride = pw + 1,
      prefix = List.filled((pw + 1) * (ph + 1), 0);
  for (var y = 0; y < ph; y++) {
    for (var x = 0; x < pw; x++) {
      final v =
          values[(y - radius).clamp(0, h - 1).toInt() * w +
              (x - radius).clamp(0, w - 1).toInt()];
      prefix[(y + 1) * stride + x + 1] =
          v +
          prefix[y * stride + x + 1] +
          prefix[(y + 1) * stride + x] -
          prefix[y * stride + x];
    }
  }
  final out = List.filled(w * h, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out[y * w + x] =
          prefix[(y + window) * stride + x + window] -
          prefix[y * stride + x + window] -
          prefix[(y + window) * stride + x] +
          prefix[y * stride + x];
    }
  }
  return out;
}

List<int> census(Image img) {
  final out = List.filled(img.pixels.length, 0);
  for (var y = 0; y < img.h; y++) {
    for (var x = 0; x < img.w; x++) {
      var v = 0;
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          if (dx == 0 && dy == 0) continue;
          v <<= 1;
          if (reference(img, x + dx, y + dy) < img.pixels[y * img.w + x])
            v |= 1;
        }
      }
      out[y * img.w + x] = v;
    }
  }
  return out;
}

List<int> texture(Image img, int window) {
  final g = List.filled(img.pixels.length, 0);
  for (var y = 0; y < img.h; y++) {
    for (var x = 0; x < img.w; x++) {
      g[y * img.w + x] = (reference(img, x + 1, y) - reference(img, x - 1, y))
          .abs();
    }
  }
  return boxSum(g, img.w, img.h, window);
}

int popcount(int value) {
  var count = 0;
  while (value != 0) {
    value &= value - 1;
    count++;
  }
  return count;
}

Volume costVolume(
  Image left,
  Image right,
  List<int> cl,
  List<int> cr,
  String kind,
  int window,
  Params p,
) {
  final out = List.generate(
    left.pixels.length,
    (_) => List.filled(p.max - p.min + 1, 0),
  );
  for (var d = p.min; d <= p.max; d++) {
    final pixel = List.filled(left.pixels.length, 0);
    for (var y = 0; y < left.h; y++) {
      for (var x = 0; x < left.w; x++) {
        final i = y * left.w + x,
            j = y * left.w + max(x - d, 0),
            diff = left.pixels[i] - right.pixels[j];
        pixel[i] = switch (kind) {
          'sad' => diff.abs(),
          'ssd' => diff * diff,
          _ => popcount(cl[i] ^ cr[j]),
        };
      }
    }
    final sums = boxSum(pixel, left.w, left.h, window);
    for (var i = 0; i < sums.length; i++) {
      out[i][d - p.min] = sums[i];
    }
  }
  return out;
}
