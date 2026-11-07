part of 'main.dart';

String realString(double value) {
  final s = value.toStringAsFixed(4);
  return s == '-0.0000' ? '0.0000' : s;
}

String textValue(Object value) =>
    value is double ? realString(value) : value.toString();
String fields(List<Object> items) {
  final out = <String>[];
  for (var i = 0; i < items.length; i += 2) {
    out.add('${items[i]}=${textValue(items[i + 1])}');
  }
  return out.join(' ');
}

void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}

void writeCSV(String name, String header, List<List<Object>> rows) =>
    writeLines(name, [header, ...rows.map((r) => r.map(textValue).join(','))]);
List<String> shadeLines(
  List<List<double>> g,
  int fs,
  int f,
  int b,
  double maximum,
) {
  final out = <String>[];
  for (var k = f ~/ 2; k >= 0; k--) {
    final pixels = StringBuffer();
    for (final frame in g) {
      final level = max(0, 9 - (-20 * log10(frame[k] / maximum) / b).floor());
      pixels.write(' .:-=+*#%@'[level]);
    }
    out.add('${realString(k * fs / f).padLeft(9)} |$pixels|');
  }
  return out;
}
