part of 'main.dart';

class Similarity {
  final double value;
  final int common;
  Similarity(this.value, this.common);
}

class Neighbor {
  final int index;
  final double similarity;
  Neighbor(this.index, this.similarity);
}

List<Neighbor> largestNeighbors(List<Neighbor> candidates, int size) {
  candidates.sort((a, b) {
    final result = b.similarity.compareTo(a.similarity);
    return result != 0 ? result : a.index.compareTo(b.index);
  });
  return candidates.take(size).toList();
}

class Neighborhood {
  final int shrinkage;
  late final List<List<Similarity?>> users, items;
  late final List<List<int>> counts, differences;
  Neighborhood(Ratings d, this.shrinkage) {
    final uCount = d.users.length, iCount = d.items.length;
    users = List.generate(
      uCount,
      (_) => List<Similarity?>.filled(uCount, null),
    );
    items = List.generate(
      iCount,
      (_) => List<Similarity?>.filled(iCount, null),
    );
    counts = List.generate(iCount, (_) => List.filled(iCount, 0));
    differences = List.generate(iCount, (_) => List.filled(iCount, 0));
    for (var u = 0; u < uCount; u++) {
      for (var v = u + 1; v < uCount; v++) {
        var count = 0, sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
        for (final r in d.byUser[u]) {
          final y = d.values[v][r.other];
          if (y != 0) {
            final x = r.value;
            count++;
            sx += x;
            sy += y;
            sxx += x * x;
            syy += y * y;
            sxy += x * y;
          }
        }
        if (count < 2) continue;
        final num = count * sxy - sx * sy,
            dx = count * sxx - sx * sx,
            dy = count * syy - sy * sy;
        if (dx == 0 || dy == 0) continue;
        final a = (num * count) * (num * count),
            b = dx * dy * (count + shrinkage) * (count + shrinkage),
            sign = num > 0
                ? 1
                : num < 0
                ? -1
                : 0,
            s = Similarity(sign * math.sqrt(a / b), count);
        users[u][v] = users[v][u] = s;
      }
    }
    for (var i = 0; i < iCount; i++) {
      for (var j = i + 1; j < iCount; j++) {
        final common = <int>[];
        var difference = 0;
        for (final r in d.byItem[i]) {
          final u = r.other, y = d.values[r.other][j];
          if (y != 0) {
            common.add(u);
            difference += r.value - y;
          }
        }
        final count = common.length;
        if (count == 0) continue;
        counts[i][j] = counts[j][i] = count;
        differences[i][j] = difference;
        differences[j][i] = -difference;
        if (count < 2) continue;
        var num = 0.0, left = 0.0, right = 0.0;
        for (final u in common) {
          final x = d.values[u][i] - d.userMeans[u],
              y = d.values[u][j] - d.userMeans[u];
          num += x * y;
          left += x * x;
          right += y * y;
        }
        if (left == 0 || right == 0) continue;
        final value =
                num / math.sqrt(left * right) * count / (count + shrinkage),
            s = Similarity(value, count);
        items[i][j] = items[j][i] = s;
      }
    }
  }
  double deviation(int target, int source) =>
      differences[target][source] / (counts[target][source] + shrinkage);
}
