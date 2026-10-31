part of 'main.dart';

String fold(String s) => String.fromCharCodes([
  for (final c in s.codeUnits)
    if (c >= 65 && c <= 90)
      c + 32
    else
      switch (c) {
        91 => 123,
        93 => 125,
        92 => 124,
        94 => 126,
        _ => c,
      },
]);
bool digits(String s) =>
    s.isNotEmpty && s.codeUnits.every((c) => c >= 48 && c <= 57);
bool letter(int c) => c >= 65 && c <= 90 || c >= 97 && c <= 122;
bool special(int c) => r'[]\`_^{|}'.codeUnits.contains(c);
bool validNick(String s) =>
    s.isNotEmpty &&
    (letter(s.codeUnitAt(0)) || special(s.codeUnitAt(0))) &&
    s.codeUnits
        .skip(1)
        .every((c) => letter(c) || special(c) || c >= 48 && c <= 57 || c == 45);
bool validChannel(String s, int limit) =>
    s.length >= 2 && s.length <= limit && s[0] == '#' && !s.contains(':');
(String, List<String>) parse(String raw) {
  var i = 0;
  if (raw.startsWith(':')) {
    final k = raw.indexOf(' ');
    if (k < 0) return ('', []);
    i = k;
  }
  while (i < raw.length && raw[i] == ' ') {
    i++;
  }
  var start = i;
  while (i < raw.length && raw[i] != ' ') {
    i++;
  }
  final command = raw.substring(start, i).toUpperCase(), args = <String>[];
  while (i < raw.length) {
    while (i < raw.length && raw[i] == ' ') {
      i++;
    }
    if (i == raw.length) break;
    if (raw[i] == ':') {
      args.add(raw.substring(i + 1));
      break;
    }
    if (args.length == 14) {
      args.add(raw.substring(i));
      break;
    }
    start = i;
    while (i < raw.length && raw[i] != ' ') {
      i++;
    }
    args.add(raw.substring(start, i));
  }
  return (command, args);
}
