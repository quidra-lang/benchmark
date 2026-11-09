import 'dart:math' as math;
import 'graph_io.dart';

double norm(List<double> values, List<int> nodes) {
  var squares = 0.0;
  for (final node in nodes) {
    squares += values[node] * values[node];
  }
  return math.sqrt(squares);
}
(List<double>, List<double>) hits(int count, List<int> nodes, List<Link> links, int iterations) {
  final sources = List.generate(count, (_) => <int>[]), targets = List.generate(count, (_) => <int>[]);
  final ordered = links.toList()..sort((first, second) {
    final compared = first.$1.compareTo(second.$1);
    return compared != 0 ? compared : first.$2.compareTo(second.$2);
  });
  for (final (source, target) in ordered) {
    sources[target].add(source);
    targets[source].add(target);
  }
  final authority = List.filled(count, 0.0), hub = List.filled(count, 0.0);
  for (final node in nodes) {
    authority[node] = 1;
    hub[node] = 1;
  }
  for (var step = 0; step < iterations; step++) {
    final incoming = List.filled(count, 0.0), outgoing = List.filled(count, 0.0);
    for (final node in nodes) {
      for (final source in sources[node]) {
        incoming[node] += hub[source];
      }
    }
    for (final node in nodes) {
      for (final target in targets[node]) {
        outgoing[node] += incoming[target];
      }
    }
    final authorityNorm = norm(incoming, nodes), hubNorm = norm(outgoing, nodes);
    for (final node in nodes) {
      authority[node] = incoming[node] / authorityNorm;
      hub[node] = outgoing[node] / hubNorm;
    }
  }
  return (authority, hub);
}
