import 'dart:io';
import 'dart:math' as math;
part 'dataset.dart';
part 'grid_index.dart';
part 'dbscan.dart';
part 'optics.dart';
part 'report.dart';

String line(List<Object> parts) => parts.join(' ');
String valueText(int value) => value == infinity ? '-' : '$value';
String optionalRoot(int value) => value == infinity ? '-' : rootText(value);
String optionalIndex(int value) => value < 0 ? '-' : '$value';
String labelChar(int label) => label < 0
    ? '.'
    : label < 52
    ? 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'[label]
    : '#';
String checkText(bool passed) => passed ? 'ok' : 'mismatch';
String conditionText(bool passed) => passed ? 'ok' : 'fail';
int integerRoot(int value) {
  if (value == 0) return 0;
  var low = 0, high = value + 1;
  while (low + 1 < high) {
    final middle = (low + high) ~/ 2;
    if (middle <= value ~/ middle) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return low;
}

int suggestedRadius(int value) {
  var root = integerRoot(value);
  if (root * root < value) root++;
  return math.max(1, root);
}

int pairCount(int n) => n * (n - 1) ~/ 2;
List<String> joinParts(List<List<String>> parts) => [
  for (var i = 0; i < parts.length; i++) ...[if (i > 0) '', ...parts[i]],
];

class Curve {
  late final List<int> order, values;
  int knee = 0, eps = 0, cross = 0;
  Curve(List<Point> points, List<int> distances) {
    order = List.generate(points.length, (i) => i)
      ..sort((a, b) {
        final comparison = distances[b].compareTo(distances[a]);
        return comparison == 0
            ? points[a].id.compareTo(points[b].id)
            : comparison;
      });
    values = order.map((i) => distances[i]).toList();
    for (var rank = 0; rank < values.length; rank++) {
      final value =
          ((values.length - 1) * (values[rank] - values.first) -
                  (values.last - values.first) * rank)
              .abs();
      if (value > cross) {
        cross = value;
        knee = rank;
      }
    }
    eps = suggestedRadius(values[knee]);
  }
}

class GridSummary {
  final int eps;
  final neighborhoods = <List<int>>[], occupancy = <int, int>{};
  late final int cells;
  late final (int, int) busiest;
  late final int busiestCount;
  int candidates = 0, pairs = 0, brutePairs = 0;
  bool consistent = true;
  GridSummary(List<Point> points, this.eps) {
    final grid = GridIndex(points, eps);
    cells = grid.cells.length;
    (busiest, busiestCount) = grid.busiest();
    var total = 0;
    for (var i = 0; i < points.length; i++) {
      final (neighbors, count) = grid.neighborhood(i);
      neighborhoods.add(neighbors);
      candidates += count;
      total += neighbors.length;
    }
    pairs = (total - points.length) ~/ 2;
    final brute = bruteForceCounts(points, eps);
    for (var i = 0; i < brute.length; i++) {
      if (brute[i] != neighborhoods[i].length) consistent = false;
    }
    brutePairs =
        (brute.fold(0, (sum, count) => sum + count) - points.length) ~/ 2;
    for (final cell in grid.cells.values) {
      occupancy[cell.length] = (occupancy[cell.length] ?? 0) + 1;
    }
  }
  List<String> lines() {
    final sizes = occupancy.keys.toList()..sort();
    return [
      'eps $eps cells $cells busiest ${busiest.$1} ${busiest.$2} $busiestCount candidates $candidates pairs $pairs brute_pairs $brutePairs ${checkText(consistent)}',
      '  occupancy ${sizes.map((size) => '$size:${occupancy[size]}').join(' ')}',
    ];
  }
}

class Setting {
  final String name, kind;
  final int radius;
  final List<int> labels;
  final List<bool> core;
  late final List<List<int>> members;
  int noise = 0, coreCount = 0, borderCount = 0;
  Setting(this.name, this.kind, this.radius, this.labels, this.core) {
    final count = labels.reduce(math.max) + 1;
    members = List.generate(count, (_) => <int>[]);
    for (var i = 0; i < labels.length; i++) {
      final label = labels[i];
      if (label < 0) {
        noise++;
      } else {
        members[label].add(i);
        if (core[i]) {
          coreCount++;
        } else {
          borderCount++;
        }
      }
    }
  }
}

(List<int>, List<bool>) extract(
  List<int> order,
  List<int> reach,
  List<int> core,
  int radius,
) {
  final labels = List.filled(order.length, -1),
      isCore = core.map((value) => value <= radius * radius).toList();
  var cluster = -1;
  for (final point in order) {
    if (reach[point] > radius * radius) {
      if (isCore[point]) {
        cluster++;
        labels[point] = cluster;
      }
    } else {
      labels[point] = cluster;
    }
  }
  return (labels, isCore);
}

class DownArea {
  final int start, end;
  int high = 0;
  DownArea(this.start, this.end);
}

class Xi {
  final List<int> reach;
  final int alpha, beta, minPts, minSize;
  late final List<bool> steepUp, steepDown, up, down;
  final areas = <(String, int, int)>[],
      clusters = <(int, int)>[],
      clusterLabels = <int>[],
      parents = <int>[];
  late final List<int> positionLabels;
  Xi(this.reach, Params p)
    : alpha = (p.xiV - p.xiU) * (p.xiV - p.xiU),
      beta = p.xiV * p.xiV,
      minPts = p.minPts,
      minSize = p.xiMinSize {
    final n = reach.length - 1;
    steepUp = List.filled(n, false);
    steepDown = List.filled(n, false);
    up = List.filled(n, false);
    down = List.filled(n, false);
    for (var i = 0; i < n; i++) {
      final a = reach[i],
          b = reach[i + 1],
          defined = reach[i] != infinity || reach[i + 1] != infinity;
      steepUp[i] = defined && xle(a, b);
      steepDown[i] = defined && xle(b, a);
      up[i] = a < b;
      down[i] = a > b;
    }
    scan();
    positionLabels = List.filled(n, -1);
    var next = 0;
    for (final cluster in clusters) {
      final start = cluster.$1, end = cluster.$2;
      final free = positionLabels
          .sublist(start, end + 1)
          .every((label) => label < 0);
      var label = -1;
      if (free) {
        label = next++;
        for (var i = start; i <= end; i++) {
          positionLabels[i] = label;
        }
      }
      clusterLabels.add(label);
    }
    for (var j = 0; j < clusters.length; j++) {
      final cluster = clusters[j], size = clusters[j].$2 - clusters[j].$1 + 1;
      var best = -1, bestSize = 0;
      for (var i = 0; i < clusters.length; i++) {
        final other = clusters[i],
            otherSize = clusters[i].$2 - clusters[i].$1 + 1;
        if (i == j ||
            other.$1 > cluster.$1 ||
            cluster.$2 > other.$2 ||
            otherSize < size ||
            otherSize == size && i < j)
          continue;
        if (best < 0 || otherSize < bestSize) {
          best = i;
          bestSize = otherSize;
        }
      }
      parents.add(best);
    }
  }
  bool xle(int a, int b) => b == infinity
      ? true
      : a == infinity
      ? false
      : beta * a <= alpha * b;
  int regionEnd(int start, List<bool> steep, List<bool> reverse) {
    var end = start, flat = 0;
    for (var i = start; i < steep.length; i++) {
      if (steep[i]) {
        end = i;
        flat = 0;
      } else if (reverse[i]) {
        break;
      } else {
        flat++;
        if (flat > minPts) break;
      }
    }
    return end;
  }

  void scan() {
    var downAreas = <DownArea>[], index = 0, mib = 0;
    for (var start = 0; start < steepUp.length; start++) {
      if (start < index || !(steepUp[start] || steepDown[start])) continue;
      for (var i = index; i <= start; i++) {
        mib = math.max(mib, reach[i]);
      }
      if (mib == infinity) {
        downAreas = [];
      } else {
        downAreas = downAreas
            .where((area) => xle(mib, reach[area.start]))
            .toList();
        for (final area in downAreas) {
          area.high = math.max(area.high, mib);
        }
      }
      if (steepDown[start]) {
        final end = regionEnd(start, steepDown, up);
        areas.add(('down', start, end));
        downAreas.add(DownArea(start, end));
        index = end + 1;
        mib = reach[index];
      } else {
        final end = regionEnd(start, steepUp, down);
        areas.add(('up', start, end));
        index = end + 1;
        mib = reach[index];
        final candidates = <(int, int)>[];
        for (final area in downAreas) {
          var cs = area.start, ce = end;
          if (!xle(area.high, reach[ce + 1])) continue;
          final top = reach[area.start];
          if (xle(reach[ce + 1], top)) {
            while (cs < area.end && reach[cs + 1] > reach[ce + 1]) {
              cs++;
            }
          } else if (xle(top, reach[ce + 1])) {
            while (ce > start && reach[ce - 1] > top) {
              ce--;
            }
          }
          if (ce - cs + 1 >= minSize && cs <= area.end && ce >= start)
            candidates.add((cs, ce));
        }
        clusters.addAll(candidates.reversed);
      }
    }
  }
}

int turn(Point origin, Point a, Point b) =>
    (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x);
List<Point> halfHull(Iterable<Point> points) {
  final hull = <Point>[];
  for (final point in points) {
    while (hull.length >= 2 &&
        turn(hull[hull.length - 2], hull.last, point) <= 0) {
      hull.removeLast();
    }
    hull.add(point);
  }
  return hull;
}

List<Point> convexHull(List<Point> points) {
  final ordered = List<Point>.of(points)
    ..sort((a, b) {
      final compared = a.x.compareTo(b.x);
      return compared == 0 ? a.y.compareTo(b.y) : compared;
    });
  if (ordered.length <= 2) return ordered;
  final lower = halfHull(ordered), upper = halfHull(ordered.reversed);
  return [...lower.take(lower.length - 1), ...upper.take(upper.length - 1)];
}

List<String> clusterLines(List<Point> points, Setting setting, int label) {
  final members = setting.members[label],
      n = setting.members[label].length,
      all = setting.members[label].map((i) => points[i]).toList();
  var sx = 0,
      sy = 0,
      core = 0,
      loX = all.first.x,
      loY = all.first.y,
      hiX = all.first.x,
      hiY = all.first.y;
  for (final i in members) {
    final point = points[i];
    sx += point.x;
    sy += point.y;
    if (setting.core[i]) core++;
    loX = math.min(loX, point.x);
    loY = math.min(loY, point.y);
    hiX = math.max(hiX, point.x);
    hiY = math.max(hiY, point.y);
  }
  var medoid = members.first, best = infinity;
  for (final i in members) {
    final dx = n * points[i].x - sx, dy = n * points[i].y - sy;
    final distance = dx * dx + dy * dy;
    if (distance < best) {
      best = distance;
      medoid = i;
    }
  }
  final area = (hiX - loX + 1) * (hiY - loY + 1), hull = convexHull(all);
  var doubled = 0, diameter = 0;
  for (var i = 0; i < hull.length; i++) {
    final point = hull[i], next = hull[(i + 1) % hull.length];
    doubled += point.x * next.y - next.x * point.y;
    for (final other in hull) {
      diameter = math.max(diameter, squaredDistance(point, other));
    }
  }
  doubled = doubled.abs();
  return [
    'cluster $label ${labelChar(label)} size $n core $core border ${n - core} centroid ${fractionText(sx, n)} ${fractionText(sy, n)} medoid ${points[medoid].id}',
    '  bbox $loX $loY $hiX $hiY area $area density ${fractionText(n, area)}',
    '  hull ${hull.length} hull_area ${doubled ~/ 2}.${doubled.isOdd ? 5 : 0} diameter_sq $diameter diameter ${rootText(diameter)}',
  ];
}

(int, int) adjustedRand(List<int> a, List<int> b) {
  final joint = <(int, int), int>{},
      first = <int, int>{},
      second = <int, int>{};
  for (var i = 0; i < a.length; i++) {
    final pair = (a[i], b[i]);
    joint[pair] = (joint[pair] ?? 0) + 1;
    first[a[i]] = (first[a[i]] ?? 0) + 1;
    second[b[i]] = (second[b[i]] ?? 0) + 1;
  }
  final s = joint.values.fold(0, (total, count) => total + pairCount(count)),
      x = first.values.fold(0, (total, count) => total + pairCount(count)),
      y = second.values.fold(0, (total, count) => total + pairCount(count)),
      z = pairCount(a.length);
  final numerator = 2 * (z * s - x * y), denominator = z * (x + y) - 2 * x * y;
  return denominator == 0 ? (1, 1) : (numerator, denominator);
}

class Analysis {
  final List<Point> points;
  final Params params;
  final curves = <Curve>[],
      grids = <GridSummary>[],
      neighborhoods = <int, List<List<int>>>{},
      settings = <Setting>[],
      mapCells = <(int, int)>[];
  late final Curve curve;
  late final List<int> kdist, core, reach, order, predecessor, positions;
  late final Setting knee, xiSetting;
  late final Xi xi;
  Analysis(this.points, this.params) {
    final rows = <List<int>>[];
    for (var i = 0; i < points.length; i++) {
      final distances = [
        for (var j = 0; j < points.length; j++)
          if (i != j) squaredDistance(points[i], points[j]),
      ]..sort();
      rows.add(distances);
    }
    for (var j = 0; j < 2 * params.minPts; j++) {
      final values = rows.map((row) => row[j]).toList();
      curves.add(Curve(points, values));
      if (j == params.minPts - 2) kdist = values;
    }
    curve = curves[params.minPts - 2];
    final radii = {...params.eps, curve.eps, params.maxEps}.toList()..sort();
    for (final eps in radii) {
      final grid = GridSummary(points, eps);
      grids.add(grid);
      neighborhoods[eps] = grid.neighborhoods;
    }
    for (final eps in params.eps) {
      addDB('db$eps', eps);
    }
    knee = addDB('knee${curve.eps}', curve.eps);
    core = coreDistances(points, neighborhoods[params.maxEps]!, params.minPts);
    (order, reach, predecessor) = opticsOrdering(
      points,
      neighborhoods[params.maxEps]!,
      core,
    );
    for (final eps in params.extract) {
      final (labels, isCore) = extract(order, reach, core, eps);
      settings.add(Setting('op$eps', 'extract', eps, labels, isCore));
    }
    positions = [...order.map((i) => reach[i]), infinity];
    xi = Xi(positions, params);
    final labels = List.filled(points.length, -1),
        isCore = core.map((value) => value != infinity).toList();
    for (var position = 0; position < order.length; position++) {
      labels[order[position]] = xi.positionLabels[position];
    }
    xiSetting = Setting('xi', 'xi', params.maxEps, labels, isCore);
    settings.add(xiSetting);
    final loX = points.map((point) => point.x).reduce(math.min),
        hiX = points.map((point) => point.x).reduce(math.max),
        loY = points.map((point) => point.y).reduce(math.min),
        hiY = points.map((point) => point.y).reduce(math.max);
    for (final point in points) {
      mapCells.add((
        (point.x - loX) * params.mapWidth ~/ (hiX - loX + 1),
        (hiY - point.y) * params.mapHeight ~/ (hiY - loY + 1),
      ));
    }
  }
  Setting addDB(String name, int eps) {
    final (labels, core) = dbscan(neighborhoods[eps]!, params.minPts);
    final setting = Setting(name, 'dbscan', eps, labels, core);
    settings.add(setting);
    return setting;
  }

  List<Setting> dbSettings() =>
      settings.where((setting) => setting.kind == 'dbscan').toList();
  List<String> labelsLines() => [
    'id,${settings.map((setting) => setting.name).join(',')}',
    for (var i = 0; i < points.length; i++)
      '${points[i].id},${settings.map((setting) => setting.labels[i]).join(',')}',
  ];
  List<String> opticsLines() => [
    'order,id,core_sq,reach_sq,reach,predecessor',
    for (var position = 0; position < order.length; position++)
      '${position + 1},${points[order[position]].id},${valueText(core[order[position]])},${valueText(reach[order[position]])},${optionalRoot(reach[order[position]])},${predecessor[order[position]] < 0 ? '-' : points[predecessor[order[position]]].id}',
  ];
  List<String> kdistLines() {
    final lines = [
      'k_distance k ${params.minPts - 1} points ${points.length}',
      'rank id kdist_sq kdist',
    ];
    for (var rank = 0; rank < curve.order.length; rank++) {
      final value = curve.values[rank];
      lines.add(
        '${rank + 1} ${points[curve.order[rank]].id} $value ${rootText(value)}',
      );
    }
    final value = curve.values[curve.knee];
    lines.addAll([
      '',
      'knee rank ${curve.knee + 1} id ${points[curve.order[curve.knee]].id} kdist_sq $value kdist ${rootText(value)} cross ${curve.cross}',
      'suggested_eps ${curve.eps}',
      '',
      'knee_table',
    ]);
    for (var j = 0; j < curves.length; j++) {
      final row = curves[j];
      lines.add(
        'k ${j + 1} rank ${row.knee + 1} id ${points[row.order[row.knee]].id} kdist_sq ${row.values[row.knee]} eps ${row.eps}',
      );
    }
    lines.addAll(['', 'core_check']);
    for (final setting in dbSettings()) {
      final count = kdist
              .where((value) => value <= setting.radius * setting.radius)
              .length,
          gridCore = setting.core.where((value) => value).length;
      lines.add(
        'eps ${setting.radius} core $count non_core ${points.length - count} grid_core $gridCore ${checkText(count == gridCore)}',
      );
    }
    var count = 0, consistent = true;
    for (var i = 0; i < core.length; i++) {
      if (core[i] != infinity) {
        count++;
        if (core[i] != kdist[i]) consistent = false;
      }
    }
    lines.add(
      'optics max_eps ${params.maxEps} core $count ${checkText(consistent)}',
    );
    return lines;
  }

  List<String> settingLines(Setting setting) {
    final lines = [
      'setting ${setting.name} eps ${setting.radius} clusters ${setting.members.length} noise ${setting.noise} core ${setting.coreCount} border ${setting.borderCount}',
    ];
    for (var label = 0; label < setting.members.length; label++) {
      lines.addAll(clusterLines(points, setting, label));
    }
    if (setting.kind != 'dbscan') return lines;
    var linked = true, supported = true, separated = true, isolated = 0;
    final ambiguous = <String>[];
    for (var i = 0; i < points.length; i++) {
      final neighbors = neighborhoods[setting.radius]![i],
          label = setting.labels[i],
          coreLabels = {
            for (final other in neighborhoods[setting.radius]![i])
              if (setting.core[other]) setting.labels[other],
          };
      if (setting.core[i]) {
        if (coreLabels.any((other) => other != label)) linked = false;
      } else if (label >= 0) {
        if (!coreLabels.contains(label)) supported = false;
        final others = coreLabels.where((other) => other != label).toList()
          ..sort();
        if (others.isNotEmpty)
          ambiguous.add(
            '  ${points[i].id} cluster $label also ${others.join(' ')}',
          );
      } else {
        if (coreLabels.isNotEmpty) separated = false;
        if (neighbors.length == 1) isolated++;
      }
    }
    return [
      ...lines,
      'check ${conditionText(linked)} ${conditionText(supported)} ${conditionText(separated)}',
      'isolated $isolated',
      'ambiguous ${ambiguous.length}',
      ...ambiguous,
    ];
  }

  List<String> hierarchyLines() {
    final ordered = dbSettings(),
        positions = {for (var i = 0; i < settings.length; i++) settings[i]: i};
    ordered.sort((a, b) {
      final comparison = a.radius.compareTo(b.radius);
      return comparison == 0
          ? positions[a]!.compareTo(positions[b]!)
          : comparison;
    });
    final lines = ['hierarchy'];
    for (var i = 1; i < ordered.length; i++) {
      final small = ordered[i - 1],
          large = ordered[i],
          sources = List.generate(ordered[i].members.length, (_) => <int>[]);
      lines.add('${small.name} -> ${large.name}');
      for (var cluster = 0; cluster < small.members.length; cluster++) {
        final firstCore = small.members[cluster].firstWhere(
          (point) => small.core[point],
        );
        sources[large.labels[firstCore]].add(cluster);
      }
      for (var label = 0; label < sources.length; label++) {
        lines.add(
          '  $label <- ${sources[label].isEmpty ? '-' : sources[label].join(' ')}',
        );
      }
    }
    return lines;
  }

  List<String> comparisonLines() {
    final lines = ['optics_vs_dbscan'];
    for (final setting in settings.where(
      (setting) => setting.kind == 'extract',
    )) {
      final matches = dbSettings()
          .where((other) => other.radius == setting.radius)
          .toList();
      if (matches.isEmpty) continue;
      final reference = matches.first,
          pairs = <(int, int)>{},
          first = <int>{},
          second = <int>{},
          mapping = <int, int>{};
      var border = 0;
      for (var i = 0; i < points.length; i++) {
        final label = setting.labels[i], other = reference.labels[i];
        if (setting.core[i]) {
          pairs.add((label, other));
          first.add(label);
          second.add(other);
          mapping[label] = other;
        }
        if (label < 0 && other >= 0) border++;
      }
      final same =
          pairs.length == first.length && pairs.length == second.length;
      var moved = '-';
      if (same) {
        var count = 0;
        for (var i = 0; i < points.length; i++) {
          final label = setting.labels[i];
          if (label >= 0 && mapping[label] != reference.labels[i]) count++;
        }
        moved = '$count';
      }
      lines.add(
        '${setting.name} ${reference.name} core_partition ${same ? 'same' : 'different'} border_as_noise $border moved $moved',
      );
    }
    return lines;
  }

  List<String> opticsSummary() {
    final components = <int>[];
    var coreCount = 0;
    for (final index in order) {
      if (reach[index] == infinity) components.add(0);
      components[components.length - 1]++;
      if (core[index] != infinity) coreCount++;
    }
    return [
      'optics max_eps ${params.maxEps} core $coreCount components ${components.length} singletons ${components.where((count) => count == 1).length} largest ${components.reduce(math.max)}',
    ];
  }

  List<String> sweepLines() {
    final lines = [
          'sweep max_eps ${params.maxEps}',
          'eps clusters noise largest',
        ],
        counts = <int>[];
    for (var eps = 1; eps <= params.maxEps; eps++) {
      final (labels, _) = extract(order, reach, core, eps);
      final sizes = <int, int>{};
      var noise = 0, count = 0, largest = 0;
      for (final label in labels) {
        if (label < 0) {
          noise++;
        } else {
          final size = (sizes[label] ?? 0) + 1;
          sizes[label] = size;
          count = math.max(count, label + 1);
          largest = math.max(largest, size);
        }
      }
      counts.add(count);
      lines.add('$eps $count $noise $largest');
    }
    var bestStart = -1, bestEnd = 0, bestLength = 0;
    for (var start = 0; start < counts.length;) {
      var end = start;
      while (end + 1 < counts.length && counts[end + 1] == counts[start]) {
        end++;
      }
      final length = end - start + 1;
      if (counts[start] >= 2 && length > bestLength) {
        bestStart = start;
        bestEnd = end;
        bestLength = length;
      }
      start = end + 1;
    }
    lines.add(
      bestStart < 0
          ? 'stable -'
          : 'stable clusters ${counts[bestStart]} eps ${bestStart + 1} ${bestEnd + 1} length $bestLength',
    );
    return lines;
  }

  List<String> xiLines() {
    final lines = [
      'xi ${params.xiText} min_size ${params.xiMinSize} steep_areas ${xi.areas.length}',
    ];
    for (final area in xi.areas) {
      lines.add('${area.$1} ${area.$2 + 1} ${area.$3 + 1}');
    }
    lines.add('xi_clusters ${xi.clusters.length}');
    for (var j = 0; j < xi.clusters.length; j++) {
      final cluster = xi.clusters[j],
          start = xi.clusters[j].$1,
          end = xi.clusters[j].$2;
      var valley = infinity;
      for (final value in xi.reach.sublist(start + 1, end + 1)) {
        valley = math.min(valley, value);
      }
      lines.add(
        '$j start ${cluster.$1 + 1} end ${cluster.$2 + 1} size ${end - start + 1} label ${optionalIndex(xi.clusterLabels[j])} parent ${optionalIndex(xi.parents[j])} walls ${optionalRoot(xi.reach[start])} ${optionalRoot(xi.reach[end + 1])} valley ${optionalRoot(valley)}',
      );
    }
    return lines;
  }

  List<String> outlierLines() {
    final rows = <(int, int, int)>[];
    for (var i = 0; i < points.length; i++) {
      if (knee.labels[i] >= 0) continue;
      var nearest = -1, best = infinity;
      for (var j = 0; j < points.length; j++) {
        if (knee.core[j]) {
          final distance = squaredDistance(points[i], points[j]);
          if (distance < best) {
            best = distance;
            nearest = j;
          }
        }
      }
      rows.add((best, i, nearest));
    }
    rows.sort((a, b) {
      final comparison = b.$1.compareTo(a.$1);
      return comparison == 0
          ? points[a.$2].id.compareTo(points[b.$2].id)
          : comparison;
    });
    return [
      'outliers ${knee.name} count ${rows.length}',
      for (final row in rows)
        '${points[row.$2].id} nearest_core ${points[row.$3].id} cluster ${knee.labels[row.$3]} dist_sq ${row.$1} dist ${rootText(row.$1)}',
    ];
  }

  List<String> gapLines() {
    final lines = ['gaps ${knee.name}'];
    for (var first = 0; first < knee.members.length; first++) {
      for (var second = first + 1; second < knee.members.length; second++) {
        var best = infinity, p = -1, q = -1;
        for (final i in knee.members[first]) {
          for (final j in knee.members[second]) {
            final distance = squaredDistance(points[i], points[j]);
            if (distance < best) {
              best = distance;
              p = i;
              q = j;
            }
          }
        }
        lines.add(
          '$first $second dist_sq $best dist ${rootText(best)} between ${points[p].id} ${points[q].id}',
        );
      }
    }
    return lines;
  }

  List<String> contingencyLines() {
    final table = List.generate(
      knee.members.length + 1,
      (_) => List.filled(xiSetting.members.length + 1, 0),
    );
    for (var i = 0; i < points.length; i++) {
      table[knee.labels[i] + 1][xiSetting.labels[i] + 1]++;
    }
    final lines = [
      'contingency ${knee.name} xi',
      'columns ${[for (var c = -1; c < xiSetting.members.length; c++) c].join(' ')}',
      for (var r = 0; r < table.length; r++) '${r - 1} ${table[r].join(' ')}',
    ];
    for (var c = 0; c < xiSetting.members.length; c++) {
      var best = 0, shared = -1;
      for (var r = 0; r < knee.members.length; r++) {
        if (table[r + 1][c + 1] > shared) {
          best = r;
          shared = table[r + 1][c + 1];
        }
      }
      final union =
          knee.members[best].length + xiSetting.members[c].length - shared;
      lines.add(
        'match $c $best shared $shared jaccard ${fractionText(shared, union)}',
      );
    }
    return lines;
  }

  List<String> clustersLines() {
    final parts = <List<String>>[
      [
        'points ${points.length} min_pts ${params.minPts}',
        'settings ${settings.map((setting) => setting.name).join(' ')}',
      ],
      ['grid', for (final grid in grids) ...grid.lines()],
      for (final setting in settings) settingLines(setting),
      hierarchyLines(),
      comparisonLines(),
      opticsSummary(),
      sweepLines(),
      xiLines(),
      outlierLines(),
      gapLines(),
      contingencyLines(),
    ];
    final ari = ['ari'];
    for (var i = 0; i < settings.length; i++) {
      for (var j = i + 1; j < settings.length; j++) {
        final (numerator, denominator) = adjustedRand(
          settings[i].labels,
          settings[j].labels,
        );
        ari.add(
          '${settings[i].name} ${settings[j].name} ${ariText(numerator, denominator)}',
        );
      }
    }
    parts.add(ari);
    return joinParts(parts);
  }

  List<String> clusterMap(Setting setting, bool kinds) {
    final cells = List.generate(
      params.mapHeight,
      (_) => List.generate(params.mapWidth, (_) => <int>[]),
    );
    for (var i = 0; i < mapCells.length; i++) {
      final cell = mapCells[i];
      cells[cell.$2][cell.$1].add(i);
    }
    final rows = <String>[];
    for (final row in cells) {
      final characters = <String>[];
      for (final indices in row) {
        var mark = ' ';
        if (indices.isNotEmpty) {
          mark = '.';
          if (kinds) {
            for (final i in indices) {
              if (setting.core[i]) {
                mark = '#';
                break;
              }
              if (setting.labels[i] >= 0) mark = '+';
            }
          } else {
            final labels = {
              for (final i in indices)
                if (setting.labels[i] >= 0) setting.labels[i],
            };
            if (labels.length == 1) {
              mark = labelChar(labels.single);
            } else if (labels.length > 1) {
              mark = '*';
            }
          }
        }
        characters.add(mark);
      }
      rows.add(characters.join());
    }
    return rows;
  }

  List<String> mapsLines() {
    final lines = <String>[];
    for (final setting in settings) {
      lines.add(
        'map ${setting.name} clusters ${setting.members.length} noise ${setting.noise}',
      );
      lines.addAll(framed(clusterMap(setting, false), params.mapWidth));
      final legend = [
        for (var label = 0; label < setting.members.length; label++)
          '${labelChar(label)}=${setting.members[label].length}',
      ];
      lines.addAll(['legend ${legend.isEmpty ? '-' : legend.join(' ')}', '']);
    }
    lines.add('kinds ${knee.name}');
    lines.addAll(framed(clusterMap(knee, true), params.mapWidth));
    lines.add('');
    final heights = <int>[];
    var kneeColumn = 0;
    for (var c = 0; c < params.kdistWidth; c++) {
      final first = c * points.length ~/ params.kdistWidth,
          last = (c + 1) * points.length ~/ params.kdistWidth;
      heights.add(
        integerRoot(
          params.kdistHeight *
              params.kdistHeight *
              curve.values[first] ~/
              curve.values.first,
        ),
      );
      if (first <= curve.knee && curve.knee < last) kneeColumn = c;
    }
    final rows = [
      for (var r = 0; r < params.kdistHeight; r++)
        [
          for (var c = 0; c < params.kdistWidth; c++)
            params.kdistHeight - r <= heights[c]
                ? '#'
                : c == kneeColumn
                ? ':'
                : ' ',
        ].join(),
    ];
    lines.add(
      'kdist_plot k ${params.minPts - 1} max ${rootText(curve.values.first)} knee_column ${kneeColumn + 1}',
    );
    lines.addAll(framed(rows, params.kdistWidth));
    lines.add('');
    final top = positions.where((value) => value != infinity).reduce(math.max),
        columns = settings
            .where(
              (setting) => setting.kind == 'extract' || setting.kind == 'xi',
            )
            .toList();
    lines.add(
      'reachability width ${params.plotWidth} max_reach ${rootText(top)} columns ${columns.map((setting) => setting.name).join(' ')}',
    );
    for (var position = 0; position < order.length; position++) {
      final i = order[position], distance = reach[order[position]];
      final bar = distance == infinity
              ? List.filled(params.plotWidth, '-').join()
              : List.filled(
                  integerRoot(
                    params.plotWidth * params.plotWidth * distance ~/ top,
                  ),
                  '#',
                ).join(),
          labels = columns
              .map((setting) => labelChar(setting.labels[i]))
              .join();
      lines.add(
        '${(position + 1).toString().padLeft(4)} ${points[i].id.toString().padLeft(5)} ${optionalRoot(distance).padLeft(7)} $labels |$bar',
      );
    }
    return lines;
  }
}

void main() {
  final analysis = Analysis(readPoints(), readParams());
  writeLines('labels.csv', analysis.labelsLines());
  writeLines('optics_order.csv', analysis.opticsLines());
  writeLines('kdist.txt', analysis.kdistLines());
  writeLines('clusters.txt', analysis.clustersLines());
  writeLines('maps.txt', analysis.mapsLines());
}
