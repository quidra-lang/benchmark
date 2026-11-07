class Edge {
  final String first, second;
  final int shared;

  Edge(this.first, this.second, this.shared);
}

class ConflictGraph {
  final List<String> vertices;
  final shared = <String, Map<String, int>>{};

  ConflictGraph(Iterable<String> ids, Iterable<List<String>> studentCourses)
      : vertices = (ids.toList()..sort()) {
    for (final id in vertices) {
      shared[id] = {};
    }
    for (final courses in studentCourses) {
      for (var index = 0; index < courses.length; index++) {
        for (final second in courses.skip(index + 1)) {
          final first = courses[index];
          shared[first]![second] = (shared[first]![second] ?? 0) + 1;
          shared[second]![first] = (shared[second]![first] ?? 0) + 1;
        }
      }
    }
  }

  Map<String, int> neighbours(String id) => shared[id] ?? const {};

  int degree(String id) => neighbours(id).length;

  int sharedTotal(String id) => neighbours(id).values.fold(0, (total, count) => total + count);

  List<Edge> edges() {
    final result = <Edge>[];
    for (final first in vertices) {
      final seconds = shared[first]!.keys.toList()..sort();
      for (final second in seconds) {
        if (first.compareTo(second) < 0) result.add(Edge(first, second, shared[first]![second]!));
      }
    }
    return result;
  }

  List<List<String>> components() {
    final seen = <String>{}, components = <List<String>>[];
    for (final vertex in vertices) {
      if (!seen.add(vertex)) continue;
      final component = [vertex];
      for (var index = 0; index < component.length; index++) {
        for (final neighbour in shared[component[index]]!.keys) {
          if (seen.add(neighbour)) component.add(neighbour);
        }
      }
      component.sort();
      components.add(component);
    }
    return components..sort((a, b) {
      final order = b.length.compareTo(a.length);
      return order != 0 ? order : a.first.compareTo(b.first);
    });
  }

  List<String> greedyClique(Iterable<String> ids) {
    var candidates = ids.toList();
    final clique = <String>[];
    while (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        final order = degree(b).compareTo(degree(a));
        return order != 0 ? order : a.compareTo(b);
      });
      final chosen = candidates.first;
      clique.add(chosen);
      candidates = candidates.where((id) => shared[chosen]!.containsKey(id)).toList();
    }
    return clique;
  }

  List<String> kempeChain(Map<String, int> assignment, String start, int first, int second) {
    final chain = [start], seen = {start};
    for (var index = 0; index < chain.length; index++) {
      for (final neighbour in neighbours(chain[index]).keys) {
        final slot = assignment[neighbour];
        if ((slot == first || slot == second) && seen.add(neighbour)) chain.add(neighbour);
      }
    }
    return chain..sort();
  }
}

bool reachable(Map<String, List<String>> arrows, String source, String target) {
  final stack = [source], seen = {source};
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (node == target) return true;
    for (final successor in arrows[node] ?? <String>[]) {
      if (seen.add(successor)) stack.add(successor);
    }
  }
  return false;
}
