part of 'main.dart';

const windowNames = ['rectangular', 'hann', 'hamming', 'blackman', 'flattop'];
List<double> window(String name, int q) {
  const coefficients = {
    'rectangular': [1.0],
    'hann': [.5, .5],
    'hamming': [.54, .46],
    'blackman': [.42, .5, .08],
    'flattop': [.21557895, .41663158, .277263158, .083578947, .006947368],
  };
  final c = coefficients[name]!;
  return List.generate(q, (n) {
    var v = 0.0;
    for (var j = 0; j < c.length; j++) {
      v += (j.isEven ? 1 : -1) * c[j] * cos(2 * pi * j * n / q);
    }
    return v;
  });
}

class WindowFigures {
  final double s1, s2, gain, enbw, hz, scalloping;
  WindowFigures(
    this.s1,
    this.s2,
    this.gain,
    this.enbw,
    this.hz,
    this.scalloping,
  );
}

WindowFigures figures(List<double> w, int fs) {
  var s1 = 0.0, s2 = 0.0, z = const Complex(0);
  for (var n = 0; n < w.length; n++) {
    s1 += w[n];
    s2 += w[n] * w[n];
    z = z + rot(pi * n / w.length).scale(w[n]);
  }
  final enbw = w.length * s2 / (s1 * s1);
  return WindowFigures(
    s1,
    s2,
    s1 / w.length,
    enbw,
    enbw * fs / w.length,
    -20 * log10(z.magnitude / s1),
  );
}
