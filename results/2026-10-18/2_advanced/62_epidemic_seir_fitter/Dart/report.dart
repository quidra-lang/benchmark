part of 'main.dart';

String fixed(double v, int k) {
  final s = v.toStringAsFixed(k);
  return s.startsWith('-') && !s.substring(1).contains(RegExp('[1-9]'))
      ? s.substring(1)
      : s;
}

List<String> curvePlot(List<int> observed, List<double> fitted) {
  final t = observed.length,
      maximum = observed.reduce(max),
      w = maximum.toString().length,
      grid = List.generate(20, (_) => List.filled(70, '.')),
      days = List.generate(70, (x) => 1 + x * (t - 1) ~/ 69);
  for (var x = 0; x < 70; x++) {
    final day = days[x],
        oy = min(19, 20 * observed[day - 1] ~/ maximum),
        fy = min(19, (20 * fitted[day - 1] / maximum).floor());
    grid[oy][x] = 'o';
    grid[fy][x] = oy == fy ? '#' : '*';
  }
  final out = ['plot observed o fitted * both # days 1 $t max $maximum'];
  for (var y = 19; y >= 0; y--) {
    out.add('${(maximum * y ~/ 20).toString().padLeft(w)} |${grid[y].join()}');
  }
  final axis = List.filled(70, '-'), labels = List.filled(70, ' ');
  for (var x = 0; x < 70; x += 10) {
    axis[x] = '+';
    final text = days[x].toString();
    for (var j = 0; j < text.length; j++) {
      labels[x + j] = text[j];
    }
  }
  out.addAll([
    '${' ' * (w + 1)}+${axis.join()}',
    '${' ' * (w + 2)}${labels.join()}'.trimRight(),
  ]);
  return out;
}
