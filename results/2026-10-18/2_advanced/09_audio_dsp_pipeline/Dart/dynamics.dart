import 'dart:math';
import 'signals.dart';

List<int> envelope(List<int> samples, int attack, int release) {
  final levels = <int>[]; var level = 0;
  for (final x in samples) { final magnitude = min(x.abs(), 32767); final coefficient = magnitude > level ? attack : release; level += rdiv((magnitude - level) * coefficient, 32768); levels.add(level); } return levels;
}
(List<int>, int) normalizeSignal(List<int> samples, int target) {
  final sourcePeak = peak(samples); return (sourcePeak == 0 ? [...samples] : [for (final x in samples) rdiv(x * target, sourcePeak)], sourcePeak);
}
(List<int>, int) gateSignal(List<int> samples, int threshold, int hold) {
  final output = <int>[]; var muted = 0; int? last;
  for (var i = 0; i < samples.length; i++) { final x = samples[i]; if (x.abs() >= threshold) last = i; if (last != null && i - last <= hold) { output.add(x); } else { output.add(0); muted++; } } return (output, muted);
}
(List<int>, int, int) compressSignal(List<int> samples, int threshold, int ratioNum, int ratioDen, int attack, int release) {
  final levels = envelope(samples, attack, release), output = <int>[]; var gain = 32768, minimum = 32768, reduced = 0;
  for (var n = 0; n < samples.length; n++) {
    final level = levels[n];
    final target = level > threshold ? rdiv((threshold + rdiv((level - threshold) * ratioDen, ratioNum)) * 32768, level) : 32768;
    gain = target < gain ? target : gain + rdiv((target - gain) * release, 32768); minimum = min(minimum, gain); if (gain < 32768) reduced++; output.add(rdiv(samples[n] * gain, 32768));
  }
  return (output, minimum, reduced);
}
