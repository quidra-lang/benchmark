import 'dart:io';

void main() {
  final out = StringBuffer();
  for (final p in [(7, 3), (10, 2), (41, 3)]) {
    final people = List.generate(p.$1, (i) => i + 1);
    var index = 0, survivor = 0;
    out.write('n=${p.$1} k=${p.$2}:');
    while (people.isNotEmpty) {
      index = (index + p.$2 - 1) % people.length;
      survivor = people.removeAt(index);
      out.write(' $survivor');
    }
    out.writeln('\nsurvivor: $survivor');
  }
  stdout.write(out);
}
