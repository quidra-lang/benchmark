import 'signals.dart';

int energy(List<int> samples) { var sum = 0; for (final x in samples) { sum += x * x; } return sum; }
int integerSqrt(int n) { var low = 0, high = n + 1; while (high - low > 1) { final middle = (low + high) ~/ 2; if (middle <= n ~/ middle) { low = middle; } else { high = middle; } } return low; }
int rms(List<int> samples) => integerSqrt(energy(samples) ~/ samples.length);
int zeroCrossings(List<int> samples) { var count = 0; for (var i = 1; i < samples.length; i++) { if ((samples[i - 1] < 0) != (samples[i] < 0)) count++; } return count; }
int countClipped(List<int> samples) => samples.where((x) => x == -32768 || x == 32767).length;
String crestFraction(List<int> samples) {
  final denominator = energy(samples); if (denominator == 0) return 'none'; final p = peak(samples);
  final numerator = p * p * samples.length;
  final divisor = numerator.gcd(denominator); return '${numerator ~/ divisor}/${denominator ~/ divisor}';
}
int autocorrelation(List<int> samples, int lag) { var sum = 0; for (var n = 0; n < samples.length - lag; n++) { sum += samples[n] * samples[n + lag]; } return sum; }
int? pitchLag(List<int> samples, int low, int high) {
  var bestLag = low, bestValue = autocorrelation(samples, low);
  for (var lag = low + 1; lag <= high; lag++) { final value = autocorrelation(samples, lag); if (value > bestValue) { bestLag = lag; bestValue = value; } } return bestValue > 0 ? bestLag : null;
}
