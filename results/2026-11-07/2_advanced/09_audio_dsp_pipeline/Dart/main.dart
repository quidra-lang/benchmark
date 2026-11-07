import 'dart:io';
import 'dart:math';
import 'signals.dart';
import 'effects.dart';
import 'filters.dart';
import 'dynamics.dart';
import 'analysis.dart';

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
  @override
  String toString() => message;
}
class ArgumentSpec {
  final String name;
  final Object? low, high;
  ArgumentSpec(this.name, [this.low, this.high]);
}
class CommandSpec {
  final List<ArgumentSpec> fixed, repeated;
  final int minimum, maximum;
  CommandSpec(this.fixed, [this.repeated = const [], this.minimum = 0, this.maximum = 0]);
  bool accepts(int count) {
    final extra = count - fixed.length, size = repeated.length;
    return size == 0 ? extra == 0 : extra >= minimum * size && extra <= maximum * size && extra % size == 0;
  }
  ArgumentSpec argument(int index) => index < fixed.length ? fixed[index] : repeated[(index - fixed.length) % repeated.length];
}
class Arguments {
  final List<Object> values;
  final List<Signal> sources;
  Arguments(this.values, this.sources);
  int n(int index) => values[index] as int;
  String text(int index) => values[index] as String;
  Signal signal(int index) => values[index] as Signal;
  int get length => values.length;
}
ArgumentSpec arg(String name, [Object? low, Object? high]) => ArgumentSpec(name, low, high);
Map<String, CommandSpec> commandTable() {
  final dst = arg('dst'), src = arg('src'), rate = arg('rate', 1000, 48000), count = arg('count', 1, 20000);
  final num = arg('num', -65536, 65536), den = arg('den', 1, 65536), attack = arg('attack', 1, 32768), release = arg('release', 1, 32768);
  final minHz = arg('min_hz', 1, 'rate div 2 - 1'), maxHz = arg('max_hz', 'min_hz + 1', 'rate div 2'), start = arg('start', 0, 'L - 1');
  final test = [dst, rate, count, arg('pos', 0, 'count - 1'), arg('amp', -32768, 32767)];
  final section = [for (final name in ['b0', 'b1', 'b2', 'a1', 'a2']) arg(name, -65536, 65536)];
  return {
    'SET': CommandSpec([arg('var'), arg('value', -10000000, 10000000)], [arg('op'), arg('operand', -10000000, 10000000)], 0, 1),
    'IMPULSE': CommandSpec(test), 'STEP': CommandSpec(test), 'NOISE': CommandSpec([dst, rate, count, arg('seed', 1, 2147483646)]),
    'GAIN': CommandSpec([dst, src, num, den]), 'MIX': CommandSpec([dst, den], [src, arg('weight', -65536, 65536)], 1, 8),
    'DELAY': CommandSpec([dst, src, arg('samples', 0, 20000)]), 'ECHO': CommandSpec([dst, src, arg('delay', 1, 20000), num, den, arg('tail', 0, 20000)]),
    'RESAMPLE': CommandSpec([dst, src, arg('new_rate', 1000, 48000)]), 'FADE': CommandSpec([dst, src, arg('in', 0, 'L'), arg('out', 0, 'L')]),
    'TRIM': CommandSpec([dst, src, start, arg('count', 1, 'L - start')]), 'CONCAT': CommandSpec([dst], [src], 2, 8),
    'FIR': CommandSpec([dst, src, arg('divisor', 1, 1000000)], [arg('tap', -32768, 32767)], 1, 64), 'BIQUAD': CommandSpec([dst, src], section, 1, 4),
    'MOVAVG': CommandSpec([dst, src, arg('width', 1, 1000)]), 'DCBLOCK': CommandSpec([dst, src, arg('num', 0, 65535), arg('den', 'num + 1', 65536)]),
    'NORMALIZE': CommandSpec([dst, src, arg('target', 1, 32767)]), 'GATE': CommandSpec([dst, src, arg('threshold', 1, 32768), arg('hold', 0, 20000)]),
    'ENVELOPE': CommandSpec([dst, src, attack, release]), 'COMPRESS': CommandSpec([dst, src, arg('threshold', 1, 32767), arg('ratio_num', 1, 100), arg('ratio_den', 1, 'ratio_num'), attack, release]),
    'ANALYZE': CommandSpec([src, minHz, maxHz]), 'COMPARE': CommandSpec([src, src]),
    'EXPECT': CommandSpec([src, arg('metric'), arg('op'), arg('value', -1000000000, 1000000000)]),
    'SEGMENTS': CommandSpec([src, arg('threshold', 1, 32768), arg('gap', 1, 20000), arg('min_length', 1, 20000)]),
    'ONSETS': CommandSpec([src, attack, release, arg('threshold', 1, 32767), arg('min_gap', 1, 20000)]),
    'PITCHTRACK': CommandSpec([src, arg('frame', 16, 'L'), arg('hop', 1, 'frame'), minHz, maxHz, arg('threshold', 0, 32767)]),
    'EXCERPT': CommandSpec([src, start, arg('count', 1, 1000)]),
    'PLOT': CommandSpec([src, start, arg('count', 1, 'L - start'), arg('columns', 8, 'min(120, count)'), arg('half', 2, 20), attack, release]),
    'METER': CommandSpec([src, arg('block', 1, 20000)]), 'HISTOGRAM': CommandSpec([src, arg('bins', 2, 64)]), 'TRACE': CommandSpec([src]), 'SAVE': CommandSpec([src]),
  };
}
int resolveBound(Object bound, Map<String, int> known, Signal? source) {
  if (bound is int) return bound;
  return switch (bound) {
    'count - 1' => known['count']! - 1, 'min(120, count)' => min(120, known['count']!), 'min_hz + 1' => known['min_hz']! + 1, 'num + 1' => known['num']! + 1,
    'L' => source!.samples.length, 'L - 1' => source!.samples.length - 1, 'L - start' => source!.samples.length - known['start']!,
    'rate div 2' => source!.rate ~/ 2, 'rate div 2 - 1' => source!.rate ~/ 2 - 1, _ => known[bound]!,
  };
}
void sameRate(List<Signal> sources) { for (final source in sources) { if (source.rate != sources.first.rate) throw CommandError('rate mismatch'); } }
int milliseconds(int index, int rate) => index * 1000 ~/ rate;
String twoDecimals(int value) => '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
String frequencyText(int rate, int lag) => twoDecimals(rdiv(100 * rate, lag));
(int, int) lagRange(int rate, int minHz, int maxHz) => ((rate + maxHz - 1) ~/ maxHz, rate ~/ minHz);
int sumSamples(List<int> samples) { var sum = 0; for (final sample in samples) { sum += sample; } return sum; }
int metricValue(List<int> samples, String metric) => switch (metric) { 'samples' => samples.length, 'peak' => peak(samples), 'rms' => rms(samples), 'sum' => sumSamples(samples), 'zero_crossings' => zeroCrossings(samples), _ => countClipped(samples) };

List<String> waveformPlot(Signal source, int start, int count, int columns, int half, int attack, int release) {
  final window = source.samples.sublist(start, start + count), levels = envelope(source.samples, attack, release).sublist(start, start + count);
  final rows = 2 * half + 1, scale = max(1, peak(window)); final grid = List.generate(rows, (_) => List.filled(columns, ' '));
  int rowOf(int value) => rdiv((scale - value) * (rows - 1), 2 * scale);
  for (var c = 0; c < columns; c++) {
    final first = c * count ~/ columns, last = (c + 1) * count ~/ columns; final part = window.sublist(first, last);
    final top = rowOf(part.reduce(max)), bottom = rowOf(part.reduce(min)), level = min(scale, levels.sublist(first, last).reduce(max));
    final upper = rowOf(level), lower = rowOf(-level);
    for (var r = 0; r < rows; r++) { grid[r][c] = r == upper || r == lower ? '*' : top <= r && r <= bottom ? '#' : r == half ? '-' : ' '; }
  }
  final lines = ['PLOT ${source.name} rate=${source.rate} start=$start count=$count columns=$columns rows=$rows scale=$scale attack=$attack release=$release'];
  for (var r = 0; r < rows; r++) { final label = r == 0 ? '$scale' : r == half ? '0' : r == rows - 1 ? '${-scale}' : ''; lines.add('${label.padLeft(6)} |${grid[r].join()}|'); }
  final axis = [for (var c = 0; c < columns; c++) c % 10 == 0 ? '+' : '-'].join(); lines.add('       +$axis+');
  var time = '    ms'; for (var c = 0; c < columns; c += 10) { time = time.padRight(8 + c) + milliseconds(start + c * count ~/ columns, source.rate).toString(); } lines.add(time); return lines;
}
List<String> meterPlot(Signal source, int block) {
  final length = source.samples.length, blocks = (source.samples.length + block - 1) ~/ block;
  final lines = ['METER ${source.name} rate=${source.rate} samples=$length block=$block blocks=$blocks'];
  for (var b = 0; b < blocks; b++) {
    final part = source.samples.sublist(b * block, min((b + 1) * block, length));
    final p = peak(part), q = rms(part);
    final np = rdiv(p * 40, 32768), nq = rdiv(q * 40, 32768);
    final bar = [for (var j = 0; j < 40; j++) j < nq ? '#' : j < np ? '-' : ' '].join();
    lines.add('${milliseconds(b * block, source.rate).toString().padLeft(6)} |$bar| peak=$p rms=$q clipped=${countClipped(part)}');
  }
  return lines;
}
List<String> histogramPlot(Signal source, int bins) {
  final counts = List.filled(bins, 0); for (final x in source.samples) { counts[(x + 32768) * bins ~/ 65536]++; }
  final edges = [for (var b = 0; b <= bins; b++) (b * 65536 + bins - 1) ~/ bins - 32768], largest = counts.reduce(max);
  return ['HISTOGRAM ${source.name} rate=${source.rate} samples=${source.samples.length} bins=$bins max=$largest', for (var b = 0; b < bins; b++) '${edges[b].toString().padLeft(6)} ${(edges[b + 1] - 1).toString().padLeft(6)} ${counts[b].toString().padLeft(5)} |${List.filled(rdiv(counts[b] * 50, largest), '#').join()}'];
}
String pitchRow(int rate, int start, int level, int? lag, int low, int high) {
  final prefix = '${milliseconds(start, rate).toString().padLeft(6)} |'; if (lag == null) return '$prefix${' ' * 41}| unvoiced rms=$level';
  final position = high > low ? rdiv((high - lag) * 40, high - low) : 0;
  return '$prefix${' ' * position}o${' ' * (40 - position)}| lag=$lag hz=${frequencyText(rate, lag)} rms=$level';
}
void traceLines(Signal signal, int depth, List<String> lines) { lines.add('${'  ' * depth}${signal.name} <- ${signal.origin}'); for (final ingredient in signal.ingredients) { traceLines(ingredient, depth + 1, lines); } }

class Pipeline {
  final signals = <String, Signal>{}, variables = <String, int>{}, commands = commandTable();
  final log = <String>[], analysis = ['signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz'], excerpts = <String>[], waveforms = <String>[], saved = <String>[];
  int steps = 0, errors = 0, passed = 0, failed = 0;
  Pipeline() {
    for (final signal in readSignals()) { signals[signal.name] = signal; log.add('load ${signal.name} rate=${signal.rate} samples=${signal.samples.length} peak=${peak(signal.samples)}'); }
  }
  int integerValue(String token) {
    if (token.startsWith(r'$')) { final name = token.substring(1); if (!variables.containsKey(name)) throw CommandError('undefined variable $token'); return variables[name]!; }
    if (!RegExp(r'^-?(0|[1-9][0-9]{0,9})$').hasMatch(token) || token == '-0') throw CommandError('bad integer $token'); return int.parse(token);
  }
  Arguments parse(String name, CommandSpec command, List<String> tokens) {
    final values = <Object>[], sources = <Signal>[], known = <String, int>{};
    for (var j = 0; j < tokens.length; j++) {
      final token = tokens[j], argument = command.argument(j);
      final kind = argument.name; late Object value;
      if (kind == 'dst' || kind == 'var') { if (!RegExp(r'^[a-z][a-z0-9_]{0,15}$').hasMatch(token)) throw CommandError('bad name $token'); value = token; }
      else if (kind == 'src') { if (!signals.containsKey(token)) throw CommandError('unknown signal $token'); value = signals[token]!; sources.add(signals[token]!); }
      else if (kind == 'metric') { if (!['samples', 'peak', 'rms', 'sum', 'zero_crossings', 'clipped'].contains(token)) throw CommandError('unknown metric $token'); value = token; }
      else if (kind == 'op') { if (!(name == 'SET' ? ['+', '-', '*', '/'] : ['eq', 'ne', 'lt', 'le', 'gt', 'ge']).contains(token)) throw CommandError('unknown operator $token'); value = token; }
      else {
        final number = integerValue(token), source = sources.isEmpty ? null : sources.first;
        final low = resolveBound(argument.low!, known, source), high = resolveBound(argument.high!, known, source);
        if (number < low || number > high) throw CommandError('$kind out of range'); known[kind] = number; value = number;
      }
      values.add(value);
    }
    return Arguments(values, sources);
  }
  String generate(int number, String command, Arguments v) {
    final sources = v.sources, x = v.sources.isEmpty ? <int>[] : v.sources.first.samples;
    var rate = sources.isEmpty ? v.n(1) : sources.first.rate; var samples = <int>[], extras = <String>[];
    void clipped((List<int>, int) result) { samples = result.$1; extras = ['clipped=${result.$2}']; }
    switch (command) {
      case 'IMPULSE': samples = impulse(v.n(2), v.n(3), v.n(4)); break;
      case 'STEP': samples = stepSignal(v.n(2), v.n(3), v.n(4)); break;
      case 'NOISE': samples = noise(v.n(2), v.n(3)); break;
      case 'GAIN': clipped(signalGain(x, v.n(2), v.n(3))); break;
      case 'MIX': sameRate(sources); clipped(signalMix([for (final source in sources) source.samples], [for (var j = 3; j < v.length; j += 2) v.n(j)], v.n(1))); break;
      case 'DELAY': if (x.length + v.n(2) > 20000) throw CommandError('result too long'); samples = signalDelay(x, v.n(2)); break;
      case 'ECHO': if (v.n(3).abs() >= v.n(4)) throw CommandError('unstable feedback'); if (x.length + v.n(5) > 20000) throw CommandError('result too long'); clipped(signalEcho(x, v.n(2), v.n(3), v.n(4), v.n(5))); break;
      case 'RESAMPLE': if (resampledLength(x.length, rate, v.n(2)) > 20000) throw CommandError('result too long'); samples = signalResample(x, rate, v.n(2)); rate = v.n(2); break;
      case 'FADE': samples = signalFade(x, v.n(2), v.n(3)); break;
      case 'TRIM': samples = x.sublist(v.n(2), v.n(2) + v.n(3)); break;
      case 'CONCAT': sameRate(sources); if (sources.fold<int>(0, (sum, source) => sum + source.samples.length) > 20000) throw CommandError('result too long'); samples = [for (final source in sources) ...source.samples]; break;
      case 'FIR': clipped(firFilter(x, v.n(2), [for (var j = 3; j < v.length; j++) v.n(j)])); break;
      case 'BIQUAD': {
        final sections = [for (var j = 2; j < v.length; j += 5) [for (var k = 0; k < 5; k++) v.n(j + k)]];
        final result = biquadFilter(x, sections); samples = result.$1; extras = ['sections=${sections.length}', 'clipped=${result.$2}']; break;
      }
      case 'MOVAVG': samples = movingAverage(x, v.n(2)); break;
      case 'DCBLOCK': clipped(dcBlock(x, v.n(2), v.n(3))); break;
      case 'NORMALIZE': { final result = normalizeSignal(x, v.n(2)); samples = result.$1; extras = ['source_peak=${result.$2}']; break; }
      case 'GATE': { final result = gateSignal(x, v.n(2), v.n(3)); samples = result.$1; extras = ['muted=${result.$2}']; break; }
      case 'ENVELOPE': samples = envelope(x, v.n(2), v.n(3)); break;
      case 'COMPRESS': { final result = compressSignal(x, v.n(2), v.n(3), v.n(4), v.n(5), v.n(6)); samples = result.$1; extras = ['min_gain=${result.$2}', 'reduced=${result.$3}']; break; }
    }
    final dst = v.text(0); signals[dst] = Signal(dst, rate, samples, 'line $number $command', sources);
    return '$dst rate=$rate samples=${samples.length} peak=${peak(samples)} sum=${sumSamples(samples)}${extras.isEmpty ? '' : ' ${extras.join(' ')}'}';
  }
  List<String> execute(int number, String name, List<String> tokens) {
    final command = commands[name]; if (command == null) throw CommandError('unknown command $name');
    if (!command.accepts(tokens.length)) throw CommandError('wrong number of arguments'); final v = parse(name, command, tokens);
    if (const {'IMPULSE', 'STEP', 'NOISE', 'GAIN', 'MIX', 'DELAY', 'ECHO', 'RESAMPLE', 'FADE', 'TRIM', 'CONCAT', 'FIR', 'BIQUAD', 'MOVAVG', 'DCBLOCK', 'NORMALIZE', 'GATE', 'ENVELOPE', 'COMPRESS'}.contains(name)) return [generate(number, name, v)];
    if (name == 'SET') {
      var result = v.n(1);
      if (v.length == 4) {
        if (v.text(2) == '/' && v.n(3) == 0) throw CommandError('division by zero');
        result = switch (v.text(2)) { '+' => result + v.n(3), '-' => result - v.n(3), '*' => result * v.n(3), _ => floorDiv(result, v.n(3)) };
        if (result.abs() > 10000000) throw CommandError('value out of range');
      }
      variables[v.text(0)] = result; return ['${v.text(0)}=$result'];
    }
    final source = v.signal(0), x = v.signal(0).samples, length = v.signal(0).samples.length, rate = v.signal(0).rate;
    switch (name) {
      case 'ANALYZE': {
        final (low, high) = lagRange(rate, v.n(1), v.n(2)); if (low > high) throw CommandError('empty lag range'); if (high >= length) throw CommandError('signal too short');
        final lag = pitchLag(x, low, high);
        analysis.add([source.name, peak(x), rms(x), zeroCrossings(x), countClipped(x), crestFraction(x), lag ?? 'none', lag == null ? 'none' : frequencyText(rate, lag)].join(','));
        return ['${source.name} lags=$low-$high'];
      }
      case 'COMPARE': {
        sameRate(v.sources); final b = v.signal(1).samples; var differing = 0, maximum = 0, energy = 0; int? first;
        for (var i = 0; i < max(length, b.length); i++) { final difference = (i < length ? x[i] : 0) - (i < b.length ? b[i] : 0); if (difference != 0) { differing++; first ??= i; } maximum = max(maximum, difference.abs()); energy += difference * difference; }
        return ['${source.name} ${v.signal(1).name} differing=$differing max_diff=$maximum first=${first ?? 'none'} error_energy=$energy'];
      }
      case 'EXPECT': {
        final measured = metricValue(x, v.text(1));
        final pass = switch (v.text(2)) { 'eq' => measured == v.n(3), 'ne' => measured != v.n(3), 'lt' => measured < v.n(3), 'le' => measured <= v.n(3), 'gt' => measured > v.n(3), _ => measured >= v.n(3) };
        if (pass) { passed++; } else { failed++; }
        return ['${source.name} ${v.text(1)}=$measured ${v.text(2)} ${v.n(3)} ${pass ? 'pass' : 'fail'}'];
      }
      case 'SEGMENTS': {
        final found = <(int, int)>[];
        for (var i = 0; i < length; i++) {
          if (x[i].abs() < v.n(1)) continue;
          if (found.isNotEmpty && i - found.last.$2 <= v.n(2)) { found[found.length - 1] = (found.last.$1, i); } else { found.add((i, i)); }
        }
        final reported = found.where((pair) => pair.$2 - pair.$1 + 1 >= v.n(3)).toList();
        final lines = ['${source.name} segments=${reported.length}'];
        for (var j = 0; j < reported.length; j++) {
          final (start, end) = reported[j]; final part = x.sublist(start, end + 1);
          lines.add('  segment ${j + 1} start=$start end=$end start_ms=${milliseconds(start, rate)} end_ms=${milliseconds(end, rate)} peak=${peak(part)} rms=${rms(part)} crossings=${zeroCrossings(part)}');
        }
        return lines;
      }
      case 'ONSETS': {
        final levels = envelope(x, v.n(1), v.n(2)), onsets = <int>[];
        for (var n = 0; n < length; n++) { if (levels[n] >= v.n(3) && (n == 0 || levels[n - 1] < v.n(3)) && (onsets.isEmpty || n - onsets.last >= v.n(4))) onsets.add(n); }
        final intervals = [for (var j = 1; j < onsets.length; j++) onsets[j] - onsets[j - 1]]; var tempo = 'none';
        if (intervals.isNotEmpty) { final ordered = [...intervals]..sort(); tempo = twoDecimals(rdiv(6000 * rate, ordered[(onsets.length - 2) ~/ 2])); }
        return ['${source.name} onsets=${onsets.length} tempo=$tempo', for (var j = 0; j < onsets.length; j++) '  onset ${j + 1} sample=${onsets[j]} ms=${milliseconds(onsets[j], rate)} interval=${j == 0 ? 'none' : intervals[j - 1]}'];
      }
      case 'PITCHTRACK': {
        final (low, high) = lagRange(rate, v.n(3), v.n(4)); if (low > high) throw CommandError('empty lag range'); if (high >= v.n(1)) throw CommandError('frame too short');
        final count = (length - v.n(1)) ~/ v.n(2) + 1, rows = <String>[]; var voiced = 0;
        for (var t = 0; t < count; t++) {
          final part = x.sublist(t * v.n(2), t * v.n(2) + v.n(1)); final level = rms(part);
          final lag = level < v.n(5) ? null : pitchLag(part, low, high);
          if (lag != null) voiced++; rows.add(pitchRow(rate, t * v.n(2), level, lag, low, high));
        }
        waveforms.add('PITCHTRACK ${source.name} rate=$rate frame=${v.n(1)} hop=${v.n(2)} lags=$low-$high threshold=${v.n(5)} frames=$count voiced=$voiced'); waveforms.addAll(rows);
        return ['${source.name} frames=$count voiced=$voiced'];
      }
      case 'EXCERPT': {
        final start = v.n(1), count = min(v.n(2), length - v.n(1)); excerpts.add('EXCERPT ${source.name} rate=$rate samples=$length start=$start count=$count');
        for (var offset = 0; offset < count; offset += 8) { final part = x.sublist(start + offset, start + min(offset + 8, count)); excerpts.add('${(start + offset).toString().padLeft(5)}:${part.map((sample) => ' ${sample.toString().padLeft(6)}').join()}'); }
        return ['${source.name} start=$start count=$count'];
      }
      case 'PLOT': waveforms.addAll(waveformPlot(source, v.n(1), v.n(2), v.n(3), v.n(4), v.n(5), v.n(6))); return ['${source.name} start=${v.n(1)} count=${v.n(2)} columns=${v.n(3)} rows=${2 * v.n(4) + 1}'];
      case 'METER': waveforms.addAll(meterPlot(source, v.n(1))); return ['${source.name} block=${v.n(1)}'];
      case 'HISTOGRAM': waveforms.addAll(histogramPlot(source, v.n(1))); return ['${source.name} bins=${v.n(1)}'];
      case 'TRACE': { final lines = [source.name]; traceLines(source, 1, lines); return lines; }
      case 'SAVE': saved.addAll(formatSignal(source)); return ['${source.name} samples=$length'];
      default: throw StateError(name);
    }
  }
  void run() {
    final lines = File('input/pipeline.txt').readAsLinesSync();
    for (var j = 0; j < lines.length; j++) {
      final line = lines[j]; if (line.isEmpty || line.startsWith('#')) continue; final parts = line.split(' '), number = j + 1;
      final name = parts.first;
      try { final output = execute(number, name, parts.sublist(1)); log.add('line $number: $name ${output.first}'); log.addAll(output.skip(1)); steps++; }
      on CommandError catch (error) { log.add('line $number: error: ${error.message}'); errors++; }
    }
    final names = signals.keys.toList()..sort(); for (final name in names) { final signal = signals[name]!; log.add('signal $name rate=${signal.rate} samples=${signal.samples.length} peak=${peak(signal.samples)} rms=${rms(signal.samples)}'); }
    log.add('summary steps=$steps errors=$errors signals=${signals.length} passed=$passed failed=$failed'); Directory('output').createSync(recursive: true);
    final outputs = {'log.txt': log, 'analysis.csv': analysis, 'excerpts.txt': excerpts, 'waveforms.txt': waveforms, 'signals_out.txt': saved};
    for (final entry in outputs.entries) { File('output/${entry.key}').writeAsStringSync(entry.value.isEmpty ? '' : '${entry.value.join('\n')}\n'); }
  }
}

void main() => Pipeline().run();
