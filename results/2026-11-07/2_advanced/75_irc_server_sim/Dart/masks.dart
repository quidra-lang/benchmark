part of 'main.dart';

bool matchMask(String mask, String text) {
  mask = fold(mask);
  text = fold(text);
  var i = 0, j = 0, star = -1, mark = 0;
  while (j < text.length) {
    if (i < mask.length && (mask[i] == '?' || mask[i] == text[j])) {
      i++;
      j++;
    } else if (i < mask.length && mask[i] == '*') {
      star = i++;
      mark = j;
    } else if (star >= 0) {
      mark++;
      j = mark;
      i = star + 1;
    } else {
      return false;
    }
  }
  while (i < mask.length && mask[i] == '*') {
    i++;
  }
  return i == mask.length;
}

String normalizeMask(String s) {
  final bang = s.contains('!'), at = s.contains('@');
  if (bang && at) return s;
  if (at) return '*!$s';
  if (bang) return '$s@*';
  if (s.contains('.')) return '*!*@$s';
  return '$s!*@*';
}
