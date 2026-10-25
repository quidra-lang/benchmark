import 'dart:io';
import 'canvas.dart';

void writeText(String name, List<String> lines) => File('output/$name').writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void writePpm(Image image) => writeText('image.ppm', ['P3', '${image.first.length} ${image.length}', '255', for (final row in image) row.map((c) => '${c.$1} ${c.$2} ${c.$3}').join(' ')]);
void writePreview(Image image) {
  final lines = <String>[]; const ramp = '@%#*+=-:,.';
  for (var top = 0; top < image.length; top += 4) { var text = ''; for (var left = 0; left < image.first.length; left += 2) { var total = 0; for (var y = top; y < top + 4; y++) { for (var x = left; x < left + 2; x++) { final c = image[y][x]; total += 299 * c.$1 + 587 * c.$2 + 114 * c.$3; } } text += ramp[(total ~/ 8000) * 10 ~/ 256]; } lines.add(text); } writeText('preview.txt', lines);
}
