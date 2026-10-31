import 'dart:math' as math;

void main() {
  final edges = [
    (0, 1, 7),
    (2, 0, 4),
    (1, 2, 9),
    (1, 3, 14),
    (3, 2, 6),
    (2, 4, 3),
    (4, 3, 5),
    (5, 3, 11),
    (4, 6, 16),
    (6, 5, 8),
    (7, 5, 12),
    (6, 7, 2),
    (7, 4, 10),
  ]..sort((a, b) => a.$3.compareTo(b.$3));
  final parent = List.generate(8, (i) => i);
  int find(int v) {
    while (parent[v] != v) {
      parent[v] = parent[parent[v]];
      v = parent[v];
    }
    return v;
  }

  var accepted = 0, skipped = 0, total = 0;
  for (final e in edges) {
    final a = find(e.$1), b = find(e.$2);
    if (a == b) {
      skipped++;
      continue;
    }
    parent[a] = b;
    accepted++;
    total += e.$3;
    print(
      '${String.fromCharCode(65 + math.min(e.$1, e.$2))}-${String.fromCharCode(65 + math.max(e.$1, e.$2))} ${e.$3}',
    );
    if (accepted == 7) break;
  }
  print('total weight: $total\nskipped: $skipped');
}
