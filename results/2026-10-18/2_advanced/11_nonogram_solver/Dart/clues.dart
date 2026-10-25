import 'line_solver.dart';

bool isClueLine(String text) => text.isNotEmpty && RegExp(r'^[0-9 ]+$').hasMatch(text);
List<int>? parseClue(String text) {
  if (text == '0') return []; final clue = <int>[];
  for (final token in text.split(' ')) { if (!RegExp(r'^[1-9][0-9]?$').hasMatch(token)) return null; clue.add(int.parse(token)); } return clue;
}
List<int> runClue(List<int> cells) {
  final clue = <int>[]; var run = 0;
  for (final state in cells) { if (state == cellFilled) { run++; } else if (run > 0) { clue.add(run); run = 0; } } if (run > 0) clue.add(run); return clue;
}
String spaced(List<int> clue) => clue.isEmpty ? '0' : clue.join(' ');
String commaClue(List<int> clue) => clue.isEmpty ? '0' : clue.join(',');
int clueSpan(List<int> clue) => clue.fold(0, (sum, length) => sum + length) + clue.length - 1;
bool fitsClue(List<int> clue, int length) => clueSpan(clue) <= length;
