part of 'main.dart';

String decimal(int p, int q) {
  final n = (2 * p * 10000 + q) ~/ (2 * q);
  return '${n ~/ 10000}.${(n % 10000).toString().padLeft(4, '0')}';
}

String percent(int p, int q) {
  if (q == 0) return '-';
  final n = (2 * p * 10000 + q) ~/ (2 * q);
  return '${n ~/ 100}.${(n % 100).toString().padLeft(2, '0')}';
}

String fraction(int p, int q) {
  final g = p.gcd(q);
  return '${p ~/ g}/${q ~/ g}';
}

String hex(int n) => n.toRadixString(16).padLeft(8, '0');
String registerText(int r) => r < 0 ? '-' : 'r$r';
void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}

class Span {
  final int first, last, stage;
  final String character;
  Span(this.first, this.last, this.character, this.stage);
}

class DiagramRow {
  final int instruction, pc;
  final String kind, annotation;
  final bool wrong;
  final List<Span> spans;
  DiagramRow(
    this.instruction,
    this.pc,
    this.kind,
    this.wrong,
    this.spans, [
    this.annotation = '',
  ]);
  (String, bool, int, int) render(int start, int end) {
    final cells = List.filled(end - start + 1, '.');
    var visible = false;
    for (final s in spans) {
      for (var c = max(start, s.first); c <= min(end, s.last); c++) {
        cells[c - start] = s.character;
        visible = true;
      }
    }
    final stars = cells.where((c) => c == '*').length,
        flush = cells.where((c) => c == 'x').length,
        left = wrong
            ? '     - ${hex(pc)} FLUSH  '
            : '${(instruction + 1).toString().padLeft(6)} ${hex(pc)} ${kind.padRight(6)} ';
    return ('$left${cells.join()}$annotation', visible, stars, flush);
  }
}

String cycleDigits(int start, int end) =>
    [for (var c = start; c <= end; c++) c % 10].join();
