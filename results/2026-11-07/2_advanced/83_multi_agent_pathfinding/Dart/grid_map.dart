part of 'main.dart';

class Agent {
  final int start, goal;
  Agent(this.start, this.goal);
}

class Grid {
  final int width, height;
  final List<String> rows;
  final List<Agent> agents = [];
  final List<List<int>> distances = [];
  Grid(this.width, this.height, this.rows);
  bool free(int c) =>
      c >= 0 && c < width * height && rows[c ~/ width][c % width] == '.';
  List<int> destinations(int c) {
    final out = [c], x = c % width, y = c ~/ width;
    for (final (dx, dy) in [(0, -1), (1, 0), (0, 1), (-1, 0)]) {
      final nx = x + dx, ny = y + dy;
      if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
        final v = ny * width + nx;
        if (free(v)) out.add(v);
      }
    }
    return out;
  }

  List<int> distanceTable(int goal) {
    final d = List.filled(width * height, -1), queue = [goal];
    d[goal] = 0;
    for (var h = 0; h < queue.length; h++) {
      final c = queue[h];
      for (final v in destinations(c).skip(1)) {
        if (d[v] < 0) {
          d[v] = d[c] + 1;
          queue.add(v);
        }
      }
    }
    return d;
  }
}

List<String> lines(String path) => File(path).readAsLinesSync();
Grid readGrid() {
  final a = lines('input/map.txt'),
      size = a[0].split(' ').map(int.parse).toList(),
      g = Grid(size[0], size[1], a.sublist(1));
  for (final line in lines('input/agents.csv').skip(1)) {
    final v = line.split(',').map(int.parse).toList();
    g.agents.add(Agent(v[2] * g.width + v[1], v[4] * g.width + v[3]));
  }
  for (final a in g.agents) {
    g.distances.add(g.distanceTable(a.goal));
  }
  return g;
}
