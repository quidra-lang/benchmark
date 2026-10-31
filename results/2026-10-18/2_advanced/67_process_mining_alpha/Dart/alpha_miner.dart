part of 'main.dart';

typedef Masks = (int, int);
Map<Pair, int> triangles(List<Trace> log) {
  final t = <Pair, int>{};
  for (final v in log) {
    final a = v.activities;
    for (var i = 0; i + 2 < a.length; i++) {
      if (a[i] == a[i + 2] && a[i] != a[i + 1]) {
        final p = (a[i], a[i + 1]);
        t[p] = (t[p] ?? 0) + v.weight;
      }
    }
  }
  return t;
}

String alphaRelation(Map<Pair, int> d, Map<Pair, int> tri, String a, String b) {
  final ab = count(d, a, b) > 0,
      ba = count(d, b, a) > 0,
      loop = a != b && count(tri, a, b) > 0 && count(tri, b, a) > 0;
  if (ab && (!ba || loop)) return '->';
  if (ba && (!ab || loop)) return '<-';
  return ab && ba ? '||' : '#';
}

bool candidate(
  Masks m,
  List<String> names,
  String Function(String, String) rel,
) {
  final (left, right) = m;
  if (left == 0 || right == 0) return false;
  for (var i = 0; i < names.length; i++) {
    final a = names[i];
    if (((left >> i) & 1) != 0) {
      for (var j = 0; j < names.length; j++) {
        final b = names[j];
        if (((left >> j) & 1) != 0 && rel(a, b) != '#') return false;
        if (((right >> j) & 1) != 0 && rel(a, b) != '->') return false;
      }
    }
    if (((right >> i) & 1) != 0) {
      for (var j = 0; j < names.length; j++) {
        if (((right >> j) & 1) != 0 && rel(a, names[j]) != '#') return false;
      }
    }
  }
  return true;
}

List<String> maskMembers(int mask, List<String> names) => [
  for (var i = 0; i < names.length; i++)
    if (((mask >> i) & 1) != 0) names[i],
];
int compareSequence(List<String> a, List<String> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    final d = a[i].compareTo(b[i]);
    if (d != 0) return d;
  }
  return a.length.compareTo(b.length);
}

int compareMasks(Masks a, Masks b, List<String> names) {
  final d = compareSequence(maskMembers(a.$1, names), maskMembers(b.$1, names));
  return d != 0
      ? d
      : compareSequence(maskMembers(a.$2, names), maskMembers(b.$2, names));
}
