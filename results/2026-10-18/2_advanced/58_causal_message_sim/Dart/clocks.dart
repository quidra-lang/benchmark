part of 'main.dart';

void tick(ProcessState p, Event? sent) {
  if (sent == null) {
    p.l++;
  } else {
    p.l = max(p.l, sent.l) + 1;
    for (var i = 0; i < sent.v.length; i++) {
      p.v[i] = max(p.v[i], sent.v[i]);
    }
  }
  p.v[p.index]++;
}

bool lessEqual(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] > b[i]) return false;
  }
  return true;
}

String relation(List<int> a, List<int> b) {
  var less = false, greater = false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] < b[i]) less = true;
    if (a[i] > b[i]) greater = true;
  }
  return less && !greater
      ? '->'
      : greater && !less
      ? '<-'
      : '||';
}

bool deliverable(MessageCopy c, List<int> b) {
  final s = c.message.stamp, src = c.source;
  for (var k = 0; k < s.length; k++) {
    if (k == src) {
      if (s[k] != b[k] + 1) return false;
    } else if (s[k] > b[k]) {
      return false;
    }
  }
  return true;
}

List<int> missing(MessageCopy c, List<int> b) => [
  for (var k = 0; k < c.message.stamp.length; k++)
    if (c.message.stamp[k] > b[k] + (k == c.source ? 1 : 0)) k,
];
String vectorText(List<int> v) => v.join(',');
