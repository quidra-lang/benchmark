part of 'main.dart';

class Signals {
  final List<int> lowpass, bandpass, derivative, squared, integrated;
  Signals(int n)
    : lowpass = List.filled(n, 0),
      bandpass = List.filled(n, 0),
      derivative = List.filled(n, 0),
      squared = List.filled(n, 0),
      integrated = List.filled(n, 0);
}

int at(List<int> values, int index) => index < 0 ? 0 : values[index];
Signals filterECG(List<int> samples) {
  final n = samples.length,
      c = List.filled(samples.length, 0),
      s = List.filled(samples.length, 0),
      f = Signals(samples.length);
  var window = 0;
  for (var i = 0; i < n; i++) {
    c[i] =
        2 * at(c, i - 1) -
        at(c, i - 2) +
        samples[i] -
        2 * at(samples, i - 6) +
        at(samples, i - 12);
    f.lowpass[i] = floorDiv(c[i], 32);
    s[i] = at(s, i - 1) + f.lowpass[i] - at(f.lowpass, i - 32);
    f.bandpass[i] = at(f.lowpass, i - 16) - floorDiv(s[i], 32);
    f.derivative[i] = floorDiv(
      2 * f.bandpass[i] +
          at(f.bandpass, i - 1) -
          at(f.bandpass, i - 3) -
          2 * at(f.bandpass, i - 4),
      8,
    );
    f.squared[i] = f.derivative[i] * f.derivative[i];
    window += f.squared[i];
    if (i >= 30) window -= f.squared[i - 30];
    f.integrated[i] = window ~/ 30;
  }
  return f;
}
