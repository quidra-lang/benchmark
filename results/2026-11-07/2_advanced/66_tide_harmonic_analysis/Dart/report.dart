part of 'main.dart';

String format(double x, int d) {
  final s = x.toStringAsFixed(d);
  return s.startsWith('-') && RegExp(r'^0(?:\.0+)?$').hasMatch(s.substring(1))
      ? s.substring(1)
      : s;
}

void writeLines(String path, StringBuffer s) =>
    File(path).writeAsStringSync(s.toString());
List<String> plotLines(List<List<String>> cells, Settings p) {
  final labels = [
    for (var q = 0; q < cells.length; q++) format((p.zt - q * p.zs) / 100, 2),
  ];
  final width = labels.map((s) => s.length).reduce(max);
  return [
    for (var q = 0; q < cells.length; q++)
      '${labels[q].padLeft(width)} |${cells[q].join()}|',
    '${' ' * width} +${[for (var i = 0; i < p.plotWidth; i++) i % 6 == 0 ? '+' : '-'].join()}+',
  ];
}
