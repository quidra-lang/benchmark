import 'dart:io';
import 'dart:math';

class Signal {
  final String name, origin;
  final int rate;
  final List<int> samples;
  final List<Signal> ingredients;
  Signal(this.name, this.rate, List<int> samples, [this.origin = 'input', List<Signal> ingredients = const []]) : samples = List.unmodifiable(samples), ingredients = List.unmodifiable(ingredients);
}
int floorDiv(int a, int b) { final q = a ~/ b; return a % b != 0 && (a < 0) != (b < 0) ? q - 1 : q; }
int rdiv(int a, int b) => floorDiv(2 * a + b, 2 * b);
int peak(List<int> samples) { var result = 0; for (final x in samples) { result = max(result, x.abs()); } return result; }
class ClipCounter {
  int count = 0;
  int saturate(int value) { final limited = max(-32768, min(32767, value)); if (limited != value) count++; return limited; }
}
List<Signal> readSignals() {
  final lines = File('input/signals.txt').readAsLinesSync(), signals = <Signal>[]; var index = 0;
  while (index < lines.length) {
    final header = lines[index++].split(' '), samples = <int>[];
    final count = int.parse(header[3]);
    while (samples.length < count) { samples.addAll(lines[index++].split(' ').map(int.parse)); }
    signals.add(Signal(header[1], int.parse(header[2]), samples));
  }
  return signals;
}
List<String> formatSignal(Signal signal) => ['SIGNAL ${signal.name} ${signal.rate} ${signal.samples.length}', for (var start = 0; start < signal.samples.length; start += 16) signal.samples.skip(start).take(16).join(' ')];
List<int> impulse(int count, int position, int amplitude) { final samples = List.filled(count, 0); samples[position] = amplitude; return samples; }
List<int> stepSignal(int count, int position, int amplitude) => List.generate(count, (i) => i >= position ? amplitude : 0);
List<int> noise(int count, int seed) {
  final samples = <int>[]; for (var i = 0; i < count; i++) { seed = 48271 * seed % 2147483647; samples.add(seed % 65536 - 32768); } return samples;
}
