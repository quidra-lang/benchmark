part of 'main.dart';

typedef Pair = (String, String);

class Trace {
  final List<String> activities;
  final int weight;
  Trace(this.activities, this.weight);
}

int count(Map<Pair, int> d, String a, String b) => d[(a, b)] ?? 0;
Map<Pair, int> follows(List<Trace> log) {
  final d = <Pair, int>{};
  for (final v in log) {
    for (var i = 1; i < v.activities.length; i++) {
      final p = (v.activities[i - 1], v.activities[i]);
      d[p] = (d[p] ?? 0) + v.weight;
    }
  }
  return d;
}

String relation(Map<Pair, int> d, String a, String b) {
  final ab = count(d, a, b) > 0, ba = count(d, b, a) > 0;
  return ab && ba
      ? '||'
      : ab
      ? '->'
      : ba
      ? '<-'
      : '#';
}

void table(StringBuffer s, int n, int width, String Function(int, int) value) {
  s.write('    ');
  for (var j = 1; j <= n; j++) {
    s.write(j.toString().padLeft(width));
  }
  s.writeln();
  for (var i = 0; i < n; i++) {
    s.write((i + 1).toString().padLeft(4));
    for (var j = 0; j < n; j++) {
      s.write(value(i, j).padLeft(width));
    }
    s.writeln();
  }
}

void footprint(
  StringBuffer s,
  List<String> names,
  String Function(String, String) rel,
) {
  for (var i = 0; i < names.length; i++) {
    s.writeln('ACTIVITY ${i + 1} ${names[i]}');
  }
  table(s, names.length, 4, (i, j) => rel(names[i], names[j]));
}
