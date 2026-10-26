import 'dart:math' as math;

List<List<int>> strongComponents(List<List<int>> adjacency) {
  final count = adjacency.length, order = List.filled(adjacency.length, -1);
  final low = List.filled(count, 0), onStack = List.filled(count, false), stack = <int>[];
  final components = <List<int>>[];
  var counter = 0;
  for (var root = 0; root < count; root++) {
    if (order[root] >= 0) continue;
    order[root] = low[root] = counter++;
    stack.add(root);
    onStack[root] = true;
    final work = <(int, int)>[(root, 0)];
    while (work.isNotEmpty) {
      final (node, position) = work.last;
      if (position < adjacency[node].length) {
        work[work.length - 1] = (node, position + 1);
        final child = adjacency[node][position];
        if (order[child] < 0) {
          order[child] = low[child] = counter++;
          stack.add(child);
          onStack[child] = true;
          work.add((child, 0));
        } else if (onStack[child]) {
          low[node] = math.min(low[node], order[child]);
        }
        continue;
      }
      work.removeLast();
      if (work.isNotEmpty) {
        final parent = work.last.$1;
        low[parent] = math.min(low[parent], low[node]);
      }
      if (low[node] == order[node]) {
        final component = <int>[];
        while (true) {
          final member = stack.removeLast();
          onStack[member] = false;
          component.add(member);
          if (member == node) break;
        }
        components.add(component);
      }
    }
  }
  return components;
}

List<bool> reachable(List<List<int>> adjacency, List<int> starts) {
  final seen = List.filled(adjacency.length, false), stack = <int>[];
  for (final start in starts) {
    if (!seen[start]) {
      seen[start] = true;
      stack.add(start);
    }
  }
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    for (final next in adjacency[node]) {
      if (!seen[next]) {
        seen[next] = true;
        stack.add(next);
      }
    }
  }
  return seen;
}
List<int> bfsDistances(List<List<int>> adjacency, List<int> sources) {
  final distance = List.filled(adjacency.length, -1), queue = <int>[];
  for (final source in sources) {
    if (distance[source] < 0) {
      distance[source] = 0;
      queue.add(source);
    }
  }
  for (var head = 0; head < queue.length; head++) {
    final node = queue[head];
    for (final next in adjacency[node]) {
      if (distance[next] < 0) {
        distance[next] = distance[node] + 1;
        queue.add(next);
      }
    }
  }
  return distance;
}
List<int> weakComponents(List<List<int>> neighbors) {
  final labels = List.filled(neighbors.length, -1);
  var count = 0;
  for (var start = 0; start < neighbors.length; start++) {
    if (labels[start] >= 0) continue;
    labels[start] = count;
    final stack = [start];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      for (final next in neighbors[node]) {
        if (labels[next] < 0) {
          labels[next] = count;
          stack.add(next);
        }
      }
    }
    count++;
  }
  return labels;
}
