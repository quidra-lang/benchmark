import 'dart:io';

void main() {
    final out = StringBuffer();
    final graph = List.generate(9, (_) => < int > []);
    for (final e in [(5, 0), (3, 8), (7, 2), (1, 6), (0, 2), (5, 3), (7, 5), (6, 4), (8, 7)]) {
        graph[e.$1].add(e.$2);
        graph[e.$2].add(e.$1);
    }
    for (final list in graph)
        list.sort();
    var visited = List.filled(9, false);
    final order = <int>[];
    void dfs(int v, List<int> result) {
        visited[v] = true;
        result.add(v);
        for (final u in graph[v]) {
            if (!visited[u])
                dfs(u, result);
        }
    }
    dfs(0, order);
    out.writeln('DFS: ${order.join(' ')}');
    visited = List.filled(9, false);
    final queue = [0], bfs = <int>[];
    visited[0] = true;
    for (var head = 0; head < queue.length; head++) {
        final v = queue[head];
        bfs.add(v);
        for (final u in graph[v]) {
            if (!visited[u]) {
                visited[u] = true;
                queue.add(u);
            }
        }
    }
    out.writeln('BFS: ${bfs.join(' ')}');
    visited = List.filled(9, false);
    final components = <List<int>>[];
    for (var v = 0; v < 9; v++) {
        if (!visited[v]) {
            final component = <int>[];
            dfs(v, component);
            component.sort();
            components.add(component);
        }
    }
    out.writeln('components: ${components.length}');
    for (var i = 0; i < components.length; i++)
        out.writeln('component ${i+1}: ${components[i].join(' ')}');
    stdout.write(out);
}
