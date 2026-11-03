import 'dart:math';
import 'signals.dart';

(List<int>, int) signalGain(List<int> samples, int num, int den) {
  final clips = ClipCounter(), output = <int>[]; for (final x in samples) { output.add(clips.saturate(rdiv(x * num, den))); } return (output, clips.count);
}
(List<int>, int) signalMix(List<List<int>> tracks, List<int> weights, int den) {
  var length = 0; for (final track in tracks) { length = max(length, track.length); } final clips = ClipCounter(), output = <int>[];
  for (var i = 0; i < length; i++) { var total = 0; for (var k = 0; k < tracks.length; k++) { if (i < tracks[k].length) total += weights[k] * tracks[k][i]; } output.add(clips.saturate(rdiv(total, den))); }
  return (output, clips.count);
}
List<int> signalDelay(List<int> samples, int count) => [...List.filled(count, 0), ...samples];
(List<int>, int) signalEcho(List<int> samples, int delay, int num, int den, int tail) {
  final output = [...samples, ...List.filled(tail, 0)], clips = ClipCounter();
  for (var i = delay; i < output.length; i++) { output[i] = clips.saturate(output[i] + rdiv(num * output[i - delay], den)); } return (output, clips.count);
}
int resampledLength(int length, int oldRate, int newRate) => (length - 1) * newRate ~/ oldRate + 1;
List<int> signalResample(List<int> samples, int oldRate, int newRate) {
  final output = <int>[];
  for (var j = 0; j < resampledLength(samples.length, oldRate, newRate); j++) {
    final p = j * oldRate ~/ newRate, q = j * oldRate % newRate; var value = samples[p];
    if (q > 0) value += rdiv((samples[p + 1] - value) * q, newRate); output.add(value);
  }
  return output;
}
List<int> signalFade(List<int> samples, int fadeIn, int fadeOut) {
  final output = [...samples], length = samples.length;
  for (var i = 0; i < fadeIn; i++) { output[i] = rdiv(output[i] * i, fadeIn); }
  for (var i = length - fadeOut; i < length; i++) { output[i] = rdiv(output[i] * (length - 1 - i), fadeOut); } return output;
}
