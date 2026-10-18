import 'dart:io';

void main() {
    final out = StringBuffer();
    void topological(List<String> names, List<(int, int)> edges, bool cycle) {
        final indegree = List.filled(names.length, 0), taken = List.filled(names.length, false);
        for (final e in edges)
            indegree[e.$2]++;
        final order = <String>[];
        while (true) {
            int ? best;
            for (var i = 0; i < names.length; i++) {
                if (!taken[i] && indegree[i] == 0 && (best == null || names[i].compareTo(names[best]) < 0))
                    best = i;
            }
            if (best == null)
                break;
            taken[best] = true;
            order.add(names[best]);
            for (final e in edges) {
                if (e.$1 == best)
                    indegree[e.$2]--;
            }
        }
        out.writeln('order: ${order.join(' -> ')}');
        if (cycle) {
            final remaining = [for (var i = 0; i < names.length; i++) if (!taken[i]) names[i]]..sort();
            out.writeln('cycle: ${remaining.join(' ')}');
        }
    }
    topological(['physics', 'algebra', 'graphics', 'programming', 'statistics', 'calculus', 'databases',
        'algorithms'], [(5, 0), (1, 5), (3, 7), (1, 4), (7, 6), (4, 6), (5, 2), (7, 2), (0, 2)], false);
    topological(['music', 'ecology', 'art', 'geology', 'biology', 'chemistry'], [(0, 2), (2, 1),
        (4, 5), (5, 1), (1, 3), (3, 5)], true);
    stdout.write(out);
}
