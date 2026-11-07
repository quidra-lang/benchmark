import 'dart:math';
import 'signals.dart';

(List<int>, int) firFilter(List<int> samples, int divisor, List<int> taps) {
  final clips = ClipCounter(), output = <int>[];
  for (var n = 0; n < samples.length; n++) { var total = 0; for (var k = 0; k < min(taps.length, n + 1); k++) { total += taps[k] * samples[n - k]; } output.add(clips.saturate(floorDiv(total, divisor))); } return (output, clips.count);
}
(List<int>, int) biquadFilter(List<int> samples, List<List<int>> sections) {
  final clips = ClipCounter(); var current = samples;
  for (final section in sections) {
    final [b0, b1, b2, a1, a2] = section;
    final output = <int>[]; var u1 = 0, u2 = 0, v1 = 0, v2 = 0;
    for (final u in current) { final v = clips.saturate(floorDiv(b0 * u + b1 * u1 + b2 * u2 - a1 * v1 - a2 * v2, 16384)); output.add(v); u2 = u1; u1 = u; v2 = v1; v1 = v; }
    current = output;
  }
  return (current, clips.count);
}
List<int> movingAverage(List<int> samples, int width) {
  final output = <int>[]; var total = 0;
  for (var n = 0; n < samples.length; n++) { total += samples[n]; if (n >= width) total -= samples[n - width]; output.add(rdiv(total, width)); } return output;
}
(List<int>, int) dcBlock(List<int> samples, int num, int den) {
  final clips = ClipCounter(), output = <int>[]; var previousInput = 0, previousOutput = 0;
  for (final x in samples) { previousOutput = clips.saturate(x - previousInput + rdiv(num * previousOutput, den)); previousInput = x; output.add(previousOutput); } return (output, clips.count);
}
