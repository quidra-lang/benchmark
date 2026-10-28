part of 'main.dart';

String displayLine(
  List<String> pieces,
  int slack,
  String alignment,
  bool last,
) {
  final shown = pieces.map((p) => p.replaceAll('~', ' ')).toList(),
      text = shown.join(' ');
  if (slack <= 0) return text;
  final gaps = pieces.length - 1;
  if (alignment == 'justify' && !last && gaps > 0) {
    final q = slack ~/ gaps, r = slack % gaps, result = StringBuffer(shown[0]);
    for (var i = 0; i < shown.length - 1; i++) {
      result.write(' ' * (q + 1 + (i < r ? 1 : 0)));
      result.write(shown[i + 1]);
    }
    return result.toString();
  }
  if (alignment == 'right') return '${' ' * slack}$text';
  if (alignment == 'center') return '${' ' * (slack ~/ 2)}$text';
  return text;
}

List<String> formatTable(
  List<List<String>> rows,
  String columns,
  String caption,
  String number,
) {
  final widths = [
        for (var i = 0; i < columns.length; i++)
          rows.map((row) => row[i].length).reduce(math.max),
      ],
      lines = <String>[];
  if (caption.isNotEmpty) lines.add('Table $number. $caption');
  for (var ri = 0; ri < rows.length; ri++) {
    final cells = <String>[];
    for (var i = 0; i < columns.length; i++) {
      final text = rows[ri][i],
          missing = widths[i] - text.length,
          before = columns[i] == 'r'
              ? missing
              : columns[i] == 'c'
              ? missing ~/ 2
              : 0;
      cells.add('${' ' * before}$text${' ' * (missing - before)}');
    }
    lines.add(cells.join(' | ').replaceFirst(RegExp(r' +$'), ''));
    if (ri == 0) lines.add(widths.map((w) => '-' * w).join('-+-'));
  }
  return lines;
}

String runningHead(
  List<String> fields,
  List<String> values,
  int width,
  int serial,
) {
  const names = ['page', 'pages', 'chapter', 'section'];
  final expanded = <String>[];
  for (var field in fields) {
    for (var i = 0; i < names.length; i++) {
      field = field.replaceAll('{${names[i]}}', values[i]);
    }
    expanded.add(field);
  }
  final left = serial.isEven ? expanded[2] : expanded[0],
      center = expanded[1],
      right = serial.isEven ? expanded[0] : expanded[2],
      line = List.filled(width, ' ');
  for (final (start, text) in [
    (0, left),
    ((width - center.length) ~/ 2, center),
    (width - right.length, right),
  ]) {
    for (var i = 0; i < text.length; i++) {
      line[start + i] = text[i];
    }
  }
  return line.join().replaceFirst(RegExp(r' +$'), '');
}

String pagesText(List<Page> pages) {
  final lines = <String>[];
  for (final p in pages) {
    lines.addAll([
      '--- page ${p.serial} ---',
      p.header,
      '',
      ...p.body,
      '',
      p.footer,
    ]);
  }
  return lines.isEmpty ? '' : '${lines.join('\n')}\n';
}
