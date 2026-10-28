part of 'main.dart';

(List<int>, List<bool>) dbscan(List<List<int>> neighborhoods, int minPts) {
  final labels = List.filled(neighborhoods.length, -2),
      core = neighborhoods
          .map((neighbors) => neighbors.length >= minPts)
          .toList();
  var cluster = 0;
  for (var point = 0; point < labels.length; point++) {
    if (labels[point] != -2) continue;
    if (!core[point]) {
      labels[point] = -1;
      continue;
    }
    labels[point] = cluster;
    final queue = List<int>.of(neighborhoods[point]);
    for (var head = 0; head < queue.length; head++) {
      final other = queue[head];
      if (labels[other] == -1) {
        labels[other] = cluster;
      } else if (labels[other] == -2) {
        labels[other] = cluster;
        if (core[other]) queue.addAll(neighborhoods[other]);
      }
    }
    cluster++;
  }
  return (labels, core);
}
