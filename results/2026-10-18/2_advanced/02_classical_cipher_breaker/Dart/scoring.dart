import 'dart:io';

bool isLetter(String char) {
  final c = char.codeUnitAt(0);
  return c >= 65 && c <= 90 || c >= 97 && c <= 122;
}

int letterValue(String char) {
  final c = char.codeUnitAt(0);
  return c >= 97 ? c - 97 : c - 65;
}

String upperLetter(int value) => String.fromCharCode(65 + value);

String letterString(String text) {
  final result = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (isLetter(c)) result.write(upperLetter(letterValue(c)));
  }
  return result.toString();
}

List<String> groups(String text) {
  final parts = <String>[];
  for (var i = 0; i < text.length; i += 5) {
    parts.add(text.substring(i, i + 5 > text.length ? text.length : i + 5));
  }
  final lines = <String>[];
  for (var i = 0; i < parts.length; i += 10) {
    lines.add(parts.skip(i).take(10).join(' '));
  }
  return lines;
}

int monogram(String text, List<int> weights) {
  var sum = 0;
  for (final c in text.codeUnits) sum += weights[c - 65];
  return sum;
}

int bigram(String text, List<List<int>> weights) {
  var sum = 0;
  for (var i = 1; i < text.length; i++) {
    sum += weights[text.codeUnitAt(i - 1) - 65][text.codeUnitAt(i) - 65];
  }
  return sum;
}

(List<int>, List<List<int>>) readWeights(String path) {
  final lines = File(path).readAsLinesSync();
  final mono = lines[1].split(' ').map(int.parse).toList();
  final bi = List.generate(26, (row) =>
      lines[row + 3].split(' ').map(int.parse).toList());
  return (mono, bi);
}
