part of 'main.dart';

String display(int c) => c >= 33 && c <= 126 && !{92, 93, 94, 45}.contains(c)
    ? String.fromCharCode(c)
    : '\\x${c.toRadixString(16).toUpperCase().padLeft(2, '0')}';
String setNotation(Set<int> set, [bool negated = false]) {
  final out = StringBuffer(negated ? '[^' : '[');
  for (var a = 0; a < 128;) {
    if (!set.contains(a)) {
      a++;
      continue;
    }
    var b = a;
    while (b + 1 < 128 && set.contains(b + 1)) b++;
    out.write(display(a));
    if (b == a + 1) out.write(display(b));
    if (b > a + 1) out.write('-${display(b)}');
    a = b + 1;
  }
  out.write(']');
  return out.toString();
}

String instructionNotation(Instruction instruction) => switch (instruction.op) {
  'CHAR' => 'CHAR ${display(instruction.char)}',
  'CLASS' => 'CLASS ${setNotation(instruction.set, instruction.negated)}',
  'SPLIT' => 'SPLIT ${instruction.x}, ${instruction.y}',
  'JMP' => 'JMP ${instruction.x}',
  'SAVE' || 'BACKREF' => '${instruction.op} ${instruction.number}',
  'ASSERT' => 'ASSERT ${instruction.kind}',
  'LOOK' => 'LOOK ${instruction.kind} ${instruction.x}',
  _ => instruction.op,
};
String quoted(String text) {
  final out = StringBuffer('"');
  for (final c in text.codeUnits) {
    out.write(switch (c) {
      92 => r'\\',
      34 => r'\"',
      10 => r'\n',
      9 => r'\t',
      _ => String.fromCharCode(c),
    });
  }
  out.write('"');
  return out.toString();
}
