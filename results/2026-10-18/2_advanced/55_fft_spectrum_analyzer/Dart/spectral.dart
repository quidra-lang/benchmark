part of 'main.dart';

double median(List<double> v) {
  final a = List<double>.of(v)..sort();
  final n = a.length;
  return n.isOdd ? a[n ~/ 2] : (a[n ~/ 2 - 1] + a[n ~/ 2]) / 2;
}

bool local(List<double> v, int k) =>
    k > 0 && k + 1 < v.length && v[k] > v[k - 1] && v[k] > v[k + 1];
(double, double) interpolate(List<double> v, int k, bool logarithmic) {
  if (!local(v, k)) return (k.toDouble(), v[k]);
  var a = v[k - 1], b = v[k], c = v[k + 1];
  if (logarithmic) {
    a = log(a);
    b = log(b);
    c = log(c);
  }
  final d = (a - c) / (2 * (a - 2 * b + c));
  var value = b - (a - c) * d / 4;
  if (logarithmic) value = exp(value);
  return (k + d, value);
}

(List<double>, List<Complex>, List<double>) amplitude(
  List<double> x,
  List<double> w,
) {
  final u = List.generate(w.length, (n) => x[n] * w[n]),
      s = sum(w),
      z = transform(realComplex(u, u.length));
  final a = List.generate(
    w.length ~/ 2 + 1,
    (k) => (k == 0 || 2 * k == w.length ? 1 : 2) * z[k].magnitude / s,
  );
  return (u, z, a);
}

(List<List<Complex>>, double) frameTransforms(
  List<double> x,
  List<double> w,
  int hop,
) {
  final out = <List<Complex>>[];
  var error = 0.0;
  for (var start = 0; start + w.length <= x.length; start += hop) {
    final u = List.generate(w.length, (n) => x[start + n] * w[n]),
        z = packed(u),
        full = radix(realComplex(u, u.length));
    for (var k = 0; k < z.length; k++) {
      error = max(error, (z[k] - full[k]).magnitude);
    }
    out.add(z);
  }
  return (out, error);
}

class WelchResult {
  final List<double> psd, coherence;
  final List<Complex> transfer;
  final int segments;
  final double error;
  WelchResult(
    this.psd,
    this.coherence,
    this.transfer,
    this.segments,
    this.error,
  );
}

WelchResult welch(List<double> x, List<double> y, int fs, int l, String name) {
  final w = window(name, l);
  final (a, ea) = frameTransforms(x, w, l ~/ 2);
  final (b, eb) = frameTransforms(y, w, l ~/ 2);
  final ns = a.length,
      psd = List.filled(l ~/ 2 + 1, 0.0),
      coherence = List.filled(l ~/ 2 + 1, 0.0),
      transfer = zeros(l ~/ 2 + 1),
      uw = squares(w);
  for (var k = 0; k < psd.length; k++) {
    var xx = 0.0, yy = 0.0, xy = const Complex(0);
    for (var j = 0; j < ns; j++) {
      final v = a[j][k].magnitude, t = b[j][k].magnitude;
      xx += v * v;
      yy += t * t;
      xy = xy + a[j][k].conjugate * b[j][k];
    }
    final c = k == 0 || k == l ~/ 2 ? 1 : 2;
    psd[k] = c * xx / (ns * fs * uw);
    coherence[k] = xy.magnitude * xy.magnitude / (xx * yy);
    transfer[k] = xy.scale(1 / xx);
  }
  return WelchResult(psd, coherence, transfer, ns, max(ea, eb));
}

List<int> rankedPeaks(List<double> v, int count, [bool Function(int)? accept]) {
  final out = <int>[];
  for (var k = 1; k + 1 < v.length; k++) {
    if (local(v, k) && (accept == null || accept(k))) out.add(k);
  }
  out.sort((a, b) {
    final c = v[b].compareTo(v[a]);
    return c != 0 ? c : a.compareTo(b);
  });
  return out.take(count).toList();
}
