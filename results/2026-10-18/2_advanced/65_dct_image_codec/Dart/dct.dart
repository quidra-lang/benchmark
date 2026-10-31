part of 'main.dart';

List<int> zigzag() {
  final z = <int>[];
  for (var s = 0; s <= 14; s++) {
    if (s.isOdd) {
      for (var u = 0; u < 8; u++) {
        final v = s - u;
        if (v >= 0 && v < 8) z.add(8 * u + v);
      }
    } else {
      for (var u = 7; u >= 0; u--) {
        final v = s - u;
        if (v >= 0 && v < 8) z.add(8 * u + v);
      }
    }
  }
  return z;
}

int rounded(int a, int s) => floor(a + (1 << (s - 1)), 1 << s);
List<int> transform(List<int> a, List<int> c) {
  final e = List.filled(64, 0), f = List.filled(64, 0);
  for (var u = 0; u < 8; u++) {
    for (var x = 0; x < 8; x++) {
      var sum = 0;
      for (var y = 0; y < 8; y++) {
        sum += c[u * 8 + y] * (a[y * 8 + x] - 128);
      }
      e[u * 8 + x] = rounded(sum, 11);
    }
  }
  for (var u = 0; u < 8; u++) {
    for (var v = 0; v < 8; v++) {
      var sum = 0;
      for (var x = 0; x < 8; x++) {
        sum += e[u * 8 + x] * c[v * 8 + x];
      }
      f[u * 8 + v] = rounded(sum, 15);
    }
  }
  return f;
}

List<int> inverse(List<int> d, List<int> c) {
  final s = List.filled(64, 0), g = List.filled(64, 0);
  for (var y = 0; y < 8; y++) {
    for (var v = 0; v < 8; v++) {
      var sum = 0;
      for (var u = 0; u < 8; u++) {
        sum += c[u * 8 + y] * d[u * 8 + v];
      }
      s[y * 8 + v] = rounded(sum, 11);
    }
  }
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      var sum = 0;
      for (var v = 0; v < 8; v++) {
        sum += s[y * 8 + v] * c[v * 8 + x];
      }
      g[y * 8 + x] = clamp(rounded(sum, 15) + 128);
    }
  }
  return g;
}

List<List<int>> quantTables(List<List<int>> base, int q) {
  final sc = q < 50 ? 5000 ~/ q : 200 - 2 * q;
  return [
    for (final a in base)
      [for (final v in a) ((v * sc + 50) ~/ 100).clamp(1, 255).toInt()],
  ];
}

List<int> quantize(List<int> f, List<int> q) => [
  for (final i in zigzag())
    (f[i] < 0 ? -1 : 1) * ((f[i].abs() + q[i] ~/ 2) ~/ q[i]),
];
List<int> reconstruct(List<int> z, List<int> q, List<int> c) {
  final d = List.filled(64, 0), zz = zigzag();
  for (var k = 0; k < 64; k++) {
    final i = zz[k];
    d[i] = z[k] * q[i];
  }
  return inverse(d, c);
}

List<int> ordered(List<int> a) => [for (final i in zigzag()) a[i]];
