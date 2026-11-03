part of 'main.dart';

bool letter(int c) => c >= 65 && c <= 90 || c >= 97 && c <= 122;
bool digit(int c) => c >= 48 && c <= 57;
int swapped(int c) => letter(c) ? c ^ 32 : c;
Set<int> standard(int c) {
  final lower = c | 32;
  return {
    for (var i = 0; i < 128; i++)
      if ((switch (lower) {
            100 => digit(i),
            119 => letter(i) || digit(i) || i == 95,
            115 => i >= 9 && i <= 13 || i == 32,
            _ => false,
          }) !=
          (c >= 65 && c <= 90))
        i,
  };
}

bool charMatches(int a, int b, String flags) =>
    a == b || flags.contains('i') && letter(a) && swapped(a) == b;
bool classMatches(Set<int> set, bool negated, int c, String flags) =>
    (set.contains(c) ||
        flags.contains('i') && letter(c) && set.contains(swapped(c))) !=
    negated;
bool consumes(Instruction instruction, String text, int q, String flags) {
  if (q >= text.length) return false;
  final c = text.codeUnitAt(q);
  return switch (instruction.op) {
    'CHAR' => charMatches(c, instruction.char, flags),
    'ANY' => flags.contains('s') || c != 10,
    'CLASS' => classMatches(instruction.set, instruction.negated, c, flags),
    _ => false,
  };
}

bool assertion(String kind, String text, int q, String flags) {
  bool word(int i) =>
      i >= 0 &&
      i < text.length &&
      (letter(text.codeUnitAt(i)) ||
          digit(text.codeUnitAt(i)) ||
          text.codeUnitAt(i) == 95);
  return switch (kind) {
    'BOL' => q == 0 || flags.contains('m') && text.codeUnitAt(q - 1) == 10,
    'EOL' =>
      q == text.length || flags.contains('m') && text.codeUnitAt(q) == 10,
    'WORD' => word(q - 1) != word(q),
    'NOTWORD' => word(q - 1) == word(q),
    _ => false,
  };
}
