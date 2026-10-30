part of 'main.dart';

String agentName(int i) => String.fromCharCode(65 + i);
String cell(Grid g, int c) => '${c % g.width},${c ~/ g.width}';
String conflictText(Grid g, Conflict c) => c.edge
    ? 'edge t ${c.time} ${agentName(c.a)} ${agentName(c.b)} from ${cell(g, c.u)} to ${cell(g, c.v)}'
    : 'vertex t ${c.time} ${agentName(c.a)} ${agentName(c.b)} at ${cell(g, c.v)}';
String action(Grid g, int u, int v) => u == v
    ? '.'
    : v == u - g.width
    ? 'N'
    : v == u + 1
    ? 'E'
    : v == u + g.width
    ? 'S'
    : 'W';
String actions(Grid g, List<int> path) => [
  for (var t = 1; t < path.length; t++) action(g, path[t - 1], path[t]),
].join();
int gcd(int a, int b) {
  while (b != 0) {
    final r = a % b;
    a = b;
    b = r;
  }
  return a;
}

String fraction(int a, int b) {
  final d = gcd(a, b);
  return '${a ~/ d}/${b ~/ d}';
}

void writeLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
int compareInts(List<int> a, List<int> b) {
  for (var i = 0; i < min(a.length, b.length); i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}
