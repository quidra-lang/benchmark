import 'dart:io';

void main() {
  final out = StringBuffer();
  const paragraph =
      'Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week.';
  final words = paragraph.split(' ');
  var start = 0;
  while (start < words.length) {
    var end = start, letters = 0;
    while (end < words.length &&
        letters + words[end].length + (end - start) <= 30) {
      letters += words[end].length;
      end++;
    }
    final n = end - start;
    out.write('|');
    if (end == words.length || n == 1) {
      final line = words.sublist(start, end).join(' ');
      out.write(line.padRight(30));
    } else {
      final spaces = 30 - letters, gaps = n - 1;
      for (var i = 0; i < n; i++) {
        out.write(words[start + i]);
        if (i < gaps) {
          out.write(' ' * (spaces ~/ gaps + (i < spaces % gaps ? 1 : 0)));
        }
      }
    }
    out.writeln('|');
    start = end;
  }
  stdout.write(out);
}
