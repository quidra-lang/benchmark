part of 'main.dart';

class Regions {
  final List<bool> known, nonocc, occluded, disc;
  final layers = <int>[], layerCounts = <int, int>{};
  Regions(int n)
    : known = List.filled(n, false),
      nonocc = List.filled(n, false),
      occluded = List.filled(n, false),
      disc = List.filled(n, false);
}

class Metrics {
  int pixels = 0, valid = 0, bad1 = 0, bad2 = 0, exact = 0, error = 0;
}

Regions truthRegions(Image gt) {
  final out = Regions(gt.pixels.length);
  for (var y = 0; y < gt.h; y++) {
    final nearest = <int, int>{};
    for (var x = 0; x < gt.w; x++) {
      final g = gt.pixels[y * gt.w + x];
      if (g > 0) nearest[x - g] = max(nearest[x - g] ?? 0, g);
    }
    for (var x = 0; x < gt.w; x++) {
      final index = y * gt.w + x, g = gt.pixels[index];
      if (g == 0) continue;
      out.known[index] = true;
      out.layerCounts[g] = (out.layerCounts[g] ?? 0) + 1;
      if (x - g < 0 || (nearest[x - g] ?? 0) > g) {
        out.occluded[index] = true;
      } else {
        out.nonocc[index] = true;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx, yy = y + dy;
            if ((dx == 0 && dy == 0) ||
                xx < 0 ||
                xx >= gt.w ||
                yy < 0 ||
                yy >= gt.h)
              continue;
            final other = gt.pixels[yy * gt.w + xx];
            if (other > 0 && (other - g).abs() >= 2) out.disc[index] = true;
          }
        }
      }
    }
  }
  out.layers.addAll(out.layerCounts.keys);
  out.layers.sort();
  return out;
}

Metrics evaluate(List<int> disparity, List<int> truth, List<bool> mask) {
  final out = Metrics();
  for (var i = 0; i < mask.length; i++) {
    if (!mask[i]) continue;
    out.pixels++;
    if (disparity[i] == 0) {
      out.bad1++;
      out.bad2++;
      continue;
    }
    out.valid++;
    final error = (disparity[i] - truth[i]).abs();
    out.error += error;
    if (error == 0) out.exact++;
    if (error > 1) out.bad1++;
    if (error > 2) out.bad2++;
  }
  return out;
}

String ratio(int a, int b) {
  if (b == 0) return '0/1 0.00';
  final g = a.gcd(b);
  return '${a ~/ g}/${b ~/ g} ${decimal2(100 * a, b)}';
}
