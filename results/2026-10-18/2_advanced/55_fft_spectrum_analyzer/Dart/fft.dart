part of 'main.dart';

const pi = 3.141592653589793;

class Complex {
  final double re, im;
  const Complex(this.re, [this.im = 0]);
  Complex operator +(Complex z) => Complex(re + z.re, im + z.im);
  Complex operator -(Complex z) => Complex(re - z.re, im - z.im);
  Complex operator *(Complex z) =>
      Complex(re * z.re - im * z.im, re * z.im + im * z.re);
  Complex operator /(Complex z) {
    final den = z.re * z.re + z.im * z.im;
    return Complex(
      (re * z.re + im * z.im) / den,
      (im * z.re - re * z.im) / den,
    );
  }

  Complex scale(double a) => Complex(re * a, im * a);
  Complex get conjugate => Complex(re, -im);
  double get magnitude => sqrt(re * re + im * im);
  double get phase => atan2(im, re);
}

int pow2(int n) {
  var q = 1;
  while (q < n) {
    q *= 2;
  }
  return q;
}

Complex rot(double t) => Complex(cos(t), -sin(t));
List<Complex> zeros(int n) => List.filled(n, const Complex(0));
List<Complex> radix(List<Complex> source, [bool inverse = false]) {
  final a = List<Complex>.of(source), q = a.length;
  for (var n = 1; n < q; n++) {
    var r = 0, v = n;
    for (var bit = q ~/ 2; bit > 0; bit ~/= 2) {
      r = r * 2 + v % 2;
      v ~/= 2;
    }
    if (n < r) {
      final t = a[n];
      a[n] = a[r];
      a[r] = t;
    }
  }
  final w = List.generate(q ~/ 2, (k) {
    final v = rot(2 * pi * k / q);
    return inverse ? v.conjugate : v;
  });
  for (var s = 2; s <= q; s *= 2) {
    for (var b = 0; b < q; b += s) {
      for (var j = 0; j < s ~/ 2; j++) {
        final t = w[j * (q ~/ s)] * a[b + j + s ~/ 2], u = a[b + j];
        a[b + j] = u + t;
        a[b + j + s ~/ 2] = u - t;
      }
    }
  }
  if (inverse) {
    for (var k = 0; k < q; k++) {
      a[k] = a[k].scale(1 / q);
    }
  }
  return a;
}

List<Complex> transform(List<Complex> v, [bool inverse = false]) {
  final m = v.length;
  if (pow2(m) == m) return radix(v, inverse);
  if (inverse)
    return transform(
      v.map((z) => z.conjugate).toList(),
    ).map((z) => z.conjugate.scale(1 / m)).toList();
  final q = pow2(2 * m - 1), w = zeros(m), a = zeros(q), b = zeros(q);
  for (var n = 0; n < m; n++) {
    w[n] = rot(pi * (n * n % (2 * m)) / m);
    a[n] = v[n] * w[n];
    b[n] = w[n].conjugate;
    if (n > 0) b[q - n] = b[n];
  }
  final fa = radix(a), fb = radix(b);
  for (var k = 0; k < q; k++) {
    fa[k] = fa[k] * fb[k];
  }
  final g = radix(fa, true);
  return List.generate(m, (k) => g[k] * w[k]);
}

List<Complex> realComplex(List<double> v, int q) {
  final a = zeros(q);
  for (var i = 0; i < v.length; i++) {
    a[i] = Complex(v[i]);
  }
  return a;
}

List<double> realParts(List<Complex> v) => v.map((z) => z.re).toList();
List<Complex> packed(List<double> v) {
  final q = v.length,
      h = q ~/ 2,
      z = radix(List.generate(h, (j) => Complex(v[2 * j], v[2 * j + 1])));
  return List.generate(h + 1, (k) {
    final a = z[k % h],
        b = z[(h - k) % h].conjugate,
        e = (a + b).scale(.5),
        o = (a - b) / const Complex(0, 2);
    return e + rot(2 * pi * k / q) * o;
  });
}

List<double> convolution(List<double> a, List<double> b) {
  final n = a.length + b.length - 1,
      q = pow2(n),
      x = radix(realComplex(a, q)),
      y = radix(realComplex(b, q));
  for (var k = 0; k < q; k++) {
    x[k] = x[k] * y[k];
  }
  return realParts(radix(x, true)).sublist(0, n);
}

List<Complex> chirpZ(List<double> u, int fs, int z1, int z2, int j) {
  final m = u.length,
      q = pow2(m + j - 1),
      dz = (z2 - z1) / (j - 1),
      a = zeros(q),
      b = zeros(q);
  for (var n = 0; n < m; n++) {
    a[n] = rot(2 * pi * z1 * n / fs) * rot(pi * dz * n * n / fs);
    a[n] = a[n].scale(u[n]);
  }
  for (var k = -(m - 1); k < j; k++) {
    b[k % q] = rot(pi * dz * k * k / fs).conjugate;
  }
  final fa = radix(a), fb = radix(b);
  for (var k = 0; k < q; k++) {
    fa[k] = fa[k] * fb[k];
  }
  final g = radix(fa, true);
  return List.generate(j, (k) => rot(pi * dz * k * k / fs) * g[k]);
}
