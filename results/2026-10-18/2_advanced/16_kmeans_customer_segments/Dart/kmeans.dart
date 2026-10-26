double squaredDistance(List<double> first, List<double> second) {
  var total = 0.0;
  for (var index = 0; index < first.length; index++) {
    final difference = first[index] - second[index];
    total += difference * difference;
  }
  return total;
}

(List<int>, List<double>) assign(List<List<double>> points, List<List<double>> centers) {
  final labels = <int>[], errors = <double>[];
  for (final point in points) {
    var best = 0, bestDistance = squaredDistance(point, centers.first);
    for (var index = 1; index < centers.length; index++) {
      final distance = squaredDistance(point, centers[index]);
      if (distance < bestDistance) {
        best = index;
        bestDistance = distance;
      }
    }
    labels.add(best);
    errors.add(bestDistance);
  }
  return (labels, errors);
}

List<double> meanPoint(List<List<double>> points) {
  final totals = List.filled(points.first.length, 0.0);
  for (final point in points) {
    for (var feature = 0; feature < point.length; feature++) {
      totals[feature] += point[feature];
    }
  }
  return totals.map((value) => value / points.length).toList();
}

List<int> clusterSizes(List<int> labels, int k) {
  final sizes = List.filled(k, 0);
  for (final label in labels) {
    sizes[label]++;
  }
  return sizes;
}
List<double> clusterCenter(List<List<double>> points, List<int> labels, int cluster) =>
    meanPoint([for (var index = 0; index < points.length; index++) if (labels[index] == cluster) points[index]]);
List<List<double>> clusterCenters(List<List<double>> points, List<int> labels, int k) =>
    [for (var cluster = 0; cluster < k; cluster++) clusterCenter(points, labels, cluster)];

int refill(List<int> labels, List<double> errors, int k) {
  final sizes = clusterSizes(labels, k);
  var reseeds = 0;
  for (var cluster = 0; cluster < k; cluster++) {
    if (sizes[cluster] > 0) continue;
    var chosen = -1;
    for (var index = 0; index < labels.length; index++) {
      if (sizes[labels[index]] >= 2 && (chosen < 0 || errors[index] > errors[chosen])) chosen = index;
    }
    sizes[labels[chosen]]--;
    sizes[cluster]++;
    labels[chosen] = cluster;
    errors[chosen] = 0;
    reseeds++;
  }
  return reseeds;
}

class LloydResult {
  final List<int> labels;
  final List<List<double>> centers;
  final int iterations, reseeds;
  final bool converged;
  LloydResult(this.labels, this.centers, this.iterations, this.converged, this.reseeds);
}

LloydResult lloyd(List<List<double>> points, List<List<double>> initial, int limit) {
  final k = initial.length;
  var (labels, errors) = assign(points, initial);
  var iterations = 0, reseeds = 0, converged = false;
  while (iterations < limit && !converged) {
    reseeds += refill(labels, errors, k);
    final centers = clusterCenters(points, labels, k);
    iterations++;
    final (next, nextErrors) = assign(points, centers);
    converged = List.generate(labels.length, (index) => labels[index] == next[index]).every((value) => value);
    labels = next;
    errors = nextErrors;
  }
  reseeds += refill(labels, errors, k);
  return LloydResult(labels, clusterCenters(points, labels, k), iterations, converged, reseeds);
}

double sse(List<List<double>> points, List<int> labels, List<List<double>> centers) {
  var total = 0.0;
  for (var index = 0; index < points.length; index++) {
    total += squaredDistance(points[index], centers[labels[index]]);
  }
  return total;
}
