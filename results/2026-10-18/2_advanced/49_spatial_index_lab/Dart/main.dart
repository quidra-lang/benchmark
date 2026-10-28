import 'dart:io';
import 'dart:math';

part 'dataset.dart';
part 'kdtree.dart';
part 'quadtree.dart';
part 'rtree.dart';
part 'grid.dart';
part 'report.dart';

const pointStructures = ['kdtree', 'quadtree', 'rtree', 'str', 'grid'];
const rectangleStructures = ['rtree_rect', 'str_rect'];
const rtreeStructures = ['rtree', 'str', 'rtree_rect', 'str_rect'];
const searchCommands = [
  'RANGE',
  'RADIUS',
  'KNN',
  'WINDOWCOUNT',
  'CONTAINS',
  'NEAREST',
  'JOIN',
];
List<String> structuresFor(String command) => command == 'JOIN'
    ? ['rtree', 'str']
    : ['CONTAINS', 'NEAREST'].contains(command)
    ? rectangleStructures
    : pointStructures;

class NodeView {
  final Box region;
  final List<SpatialObject> held;
  final List<NodeView> children;
  final int depth;
  final String mark;
  final KDNode? kd;
  final QuadNode? quad;
  final RNode? r;
  late final int count =
      held.length + children.fold(0, (sum, child) => sum + child.count);
  NodeView(
    this.region,
    this.held,
    this.children, {
    this.depth = 0,
    this.mark = 'root',
    this.kd,
    this.quad,
    this.r,
  });
}

NodeView kdView(KDNode node, Box region, String mark, int depth) {
  final point = node.point, children = <NodeView>[];
  final left = node.axis == 0
      ? Box(region.x1, region.y1, point.box.x1, region.y2)
      : Box(region.x1, region.y1, region.x2, point.box.y1);
  final right = node.axis == 0
      ? Box(point.box.x1, region.y1, region.x2, region.y2)
      : Box(region.x1, point.box.y1, region.x2, region.y2);
  if (node.left != null) {
    children.add(kdView(node.left!, left, 'L', depth + 1));
  }
  if (node.right != null) {
    children.add(kdView(node.right!, right, 'R', depth + 1));
  }
  return NodeView(
    region,
    [point],
    children,
    depth: depth,
    mark: mark,
    kd: node,
  );
}

NodeView quadView(QuadNode node, String mark, int depth) => NodeView(
  Box(node.x, node.y, node.x + node.size - 1, node.y + node.size - 1),
  node.points,
  [
    for (var i = 0; i < node.children.length; i++)
      quadView(node.children[i], childNames[i], depth + 1),
  ],
  depth: depth,
  mark: mark,
  quad: node,
);
NodeView rtreeView(
  RNode node,
  Map<int, SpatialObject> objects,
  int depth,
) => NodeView(
  node.box,
  node.level == 0 ? [for (final e in node.entries) objects[e.id]!] : [],
  node.level == 0
      ? []
      : [for (final e in node.entries) rtreeView(e.child!, objects, depth + 1)],
  depth: depth,
  r: node,
);
NodeView gridView(Grid grid) => NodeView(
  Box(0, 0, grid.world - 1, grid.world - 1),
  [],
  [for (final c in grid.cells) NodeView(c.box, c.points, [], depth: 1)],
);
Iterable<NodeView> preorder(NodeView root) sync* {
  yield root;
  for (final child in root.children) {
    yield* preorder(child);
  }
}

int minimumDistance(int x, int y, Box box) {
  final dx = x < box.x1
          ? box.x1 - x
          : x > box.x2
          ? x - box.x2
          : 0,
      dy = y < box.y1
          ? box.y1 - y
          : y > box.y2
          ? y - box.y2
          : 0;
  return dx * dx + dy * dy;
}

(bool Function(Box), bool Function(SpatialObject)) conditions(
  String command,
  List<int> values,
) {
  if (command == 'RANGE') {
    final box = Box(values[0], values[1], values[2], values[3]);
    return (
      (region) => intersects(region, box),
      (point) => contains(box, point.box),
    );
  }
  if (command == 'RADIUS') {
    final x = values[0], y = values[1], limit = values[2] * values[2];
    return (
      (region) => minimumDistance(x, y, region) <= limit,
      (point) => minimumDistance(x, y, point.box) <= limit,
    );
  }
  final query = Box(values[0], values[1], values[0], values[1]);
  return (
    (region) => contains(region, query),
    (rect) => contains(rect.box, query),
  );
}

class SearchResult {
  final ids = <int>[], pairs = <(int, int)>[];
  int count = 0, nodes = 0, tests = 0;
}

SearchResult conditionSearch(
  NodeView root,
  bool Function(Box) regionCondition,
  bool Function(SpatialObject) objectCondition,
) {
  final result = SearchResult();
  void visit(NodeView v) {
    result.nodes++;
    result.tests += v.held.length;
    for (final o in v.held) {
      if (objectCondition(o)) {
        result.ids.add(o.id);
      }
    }
    for (final child in v.children) {
      if (regionCondition(child.region)) {
        visit(child);
      }
    }
  }

  visit(root);
  result.ids.sort();
  return result;
}

SearchResult windowCount(NodeView root, Box window) {
  final result = SearchResult();
  void count(NodeView v) {
    result.nodes++;
    if (contains(window, v.region)) {
      result.count += v.count;
      return;
    }
    result.tests += v.held.length;
    for (final o in v.held) {
      if (contains(window, o.box)) {
        result.count++;
      }
    }
    for (final child in v.children) {
      if (intersects(child.region, window)) {
        count(child);
      }
    }
  }

  count(root);
  return result;
}

class QueueElement {
  final int distance, kind, tie;
  final NodeView? node;
  final SpatialObject? object;
  QueueElement(this.distance, this.kind, this.tie, {this.node, this.object});
}

bool queueLess(QueueElement a, QueueElement b) =>
    a.distance < b.distance ||
    a.distance == b.distance &&
        (a.kind < b.kind || a.kind == b.kind && a.tie < b.tie);

class PriorityQueue {
  final elements = <QueueElement>[];
  void add(QueueElement element) {
    elements.add(element);
    var i = elements.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (!queueLess(element, elements[parent])) {
        break;
      }
      elements[i] = elements[parent];
      i = parent;
    }
    elements[i] = element;
  }

  QueueElement removeFirst() {
    final result = elements.first, last = elements.removeLast();
    if (elements.isEmpty) {
      return result;
    }
    var i = 0;
    while (i * 2 + 1 < elements.length) {
      var child = i * 2 + 1;
      if (child + 1 < elements.length &&
          queueLess(elements[child + 1], elements[child])) {
        child++;
      }
      if (!queueLess(elements[child], last)) {
        break;
      }
      elements[i] = elements[child];
      i = child;
    }
    elements[i] = last;
    return result;
  }
}

SearchResult bestFirst(NodeView root, int x, int y, int k) {
  final pending = PriorityQueue()
        ..add(
          QueueElement(minimumDistance(x, y, root.region), 0, 0, node: root),
        ),
      result = SearchResult();
  var serial = 1;
  while (pending.elements.isNotEmpty) {
    final e = pending.removeFirst();
    if (e.kind == 1) {
      result.pairs.add((e.object!.id, e.distance));
      if (result.pairs.length == k) {
        break;
      }
      continue;
    }
    final v = e.node!;
    result.nodes++;
    result.tests += v.held.length;
    for (final o in v.held) {
      pending.add(
        QueueElement(minimumDistance(x, y, o.box), 1, o.id, object: o),
      );
    }
    for (final child in v.children) {
      pending.add(
        QueueElement(
          minimumDistance(x, y, child.region),
          0,
          serial++,
          node: child,
        ),
      );
    }
  }
  return result;
}

void sortPairs(List<(int, int)> pairs) {
  pairs.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
}

SearchResult spatialJoin(NodeView pointRoot, NodeView rectRoot) {
  final result = SearchResult();
  void join(NodeView a, NodeView b) {
    result.nodes++;
    if (a.children.isEmpty && b.children.isEmpty) {
      result.tests += a.held.length * b.held.length;
      for (final p in a.held) {
        for (final r in b.held) {
          if (contains(r.box, p.box)) {
            result.pairs.add((r.id, p.id));
          }
        }
      }
      return;
    }
    if (a.children.isEmpty) {
      for (final child in b.children) {
        if (intersects(a.region, child.region)) {
          join(a, child);
        }
      }
    } else if (b.children.isEmpty) {
      for (final child in a.children) {
        if (intersects(child.region, b.region)) {
          join(child, b);
        }
      }
    } else {
      for (final ac in a.children) {
        for (final bc in b.children) {
          if (intersects(ac.region, bc.region)) {
            join(ac, bc);
          }
        }
      }
    }
  }

  join(pointRoot, rectRoot);
  sortPairs(result.pairs);
  return result;
}

SearchResult bruteForce(
  String command,
  List<int> values,
  Map<int, SpatialObject> points,
  Map<int, SpatialObject> rects,
) {
  final result = SearchResult(),
      objects = ['CONTAINS', 'NEAREST'].contains(command) ? rects : points;
  switch (command) {
    case 'RANGE':
    case 'RADIUS':
    case 'CONTAINS':
      final (_, condition) = conditions(command, values);
      result.ids.addAll([
        for (final o in objects.values)
          if (condition(o)) o.id,
      ]);
      result.ids.sort();
    case 'WINDOWCOUNT':
      final box = Box(values[0], values[1], values[2], values[3]);
      result.count = points.values.where((o) => contains(box, o.box)).length;
    case 'KNN':
    case 'NEAREST':
      final pairs =
          [
            for (final o in objects.values)
              (o.id, minimumDistance(values[0], values[1], o.box)),
          ]..sort((a, b) {
            final c = a.$2.compareTo(b.$2);
            return c != 0 ? c : a.$1.compareTo(b.$1);
          });
      result.pairs.addAll(pairs.take(values[2]));
    case 'JOIN':
      for (final rect in rects.values) {
        for (final point in points.values) {
          if (contains(rect.box, point.box)) {
            result.pairs.add((rect.id, point.id));
          }
        }
      }
      sortPairs(result.pairs);
  }
  return result;
}

bool listEqual<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool sameAnswer(SearchResult a, SearchResult b) =>
    a.count == b.count &&
    listEqual(a.ids, b.ids) &&
    listEqual(a.pairs, b.pairs);
String locateKD(KDNode root, SpatialObject point) {
  var node = root, path = '';
  while (node.point.id != point.id) {
    if (keyLess(point, node.point, node.axis)) {
      path += 'L';
      node = node.left!;
    } else {
      path += 'R';
      node = node.right!;
    }
  }
  return path.isEmpty ? '-' : path;
}

String locateQuad(QuadNode root, SpatialObject point) {
  var node = root;
  final path = <String>[];
  while (node.children.isNotEmpty) {
    final index = destination(node, point);
    path.add(childNames[index]);
    node = node.children[index];
  }
  return path.isEmpty ? '-' : path.join('/');
}

String locateRTree(RNode root, SpatialObject point) {
  String? find(RNode node, List<int> path) {
    for (var i = 0; i < node.entries.length; i++) {
      final e = node.entries[i], next = [...path, i + 1];
      if (node.level == 0) {
        if (e.id == point.id) {
          return next.join('/');
        }
      } else if (contains(e.box, point.box)) {
        final answer = find(e.child!, next);
        if (answer != null) {
          return answer;
        }
      }
    }
    return null;
  }

  return find(root, [])!;
}

List<String> dumpTree(NodeView root, String name) {
  final lines = <String>[];
  for (final v in preorder(root)) {
    final prefix = '  ' * (v.depth + 1);
    String line;
    if (name == 'kdtree') {
      final o = v.held.first;
      line =
          '${v.mark} ${'xy'[v.kd!.axis]} ${o.id} ${o.box.x1} ${o.box.y1} box ${boxWords(v.region)}';
    } else if (name == 'quadtree') {
      final q = v.quad!;
      line =
          '${v.mark} ${q.x} ${q.y} ${q.size} ${v.children.isEmpty ? 'leaf ${ids(v.held.map((o) => o.id).toList())}' : 'node count ${v.count}'}';
    } else {
      line = v.r!.level == 0
          ? 'leaf ${boxWords(v.region)} ids ${ids(v.held.map((o) => o.id).toList())}'
          : 'node ${v.r!.level} ${boxWords(v.region)} entries ${v.r!.entries.length}';
    }
    lines.add('$prefix$line');
  }
  return lines;
}

List<String> kdStatistics(NodeView root) {
  final depths = <int, List<int>>{};
  var height = 0, nodes = 0, leaves = 0, one = 0, depthSum = 0;
  for (final v in preorder(root)) {
    final row = depths.putIfAbsent(v.depth, () => [0, 0, 0]);
    row[0]++;
    nodes++;
    if (v.children.isEmpty) {
      row[1]++;
      leaves++;
    } else if (v.children.length == 1) {
      row[2]++;
      one++;
    }
    depthSum += v.depth;
    height = max(height, v.depth + 1);
  }
  var ideal = 0, capacity = 0;
  while (capacity < nodes) {
    capacity = 2 * capacity + 1;
    ideal++;
  }
  return [
    'kdtree height $height ideal $ideal nodes $nodes leaves $leaves one_child $one depth_sum $depthSum avg_depth ${fraction(depthSum, nodes)}',
    for (var t = 0; t < height; t++)
      '  depth $t nodes ${depths[t]![0]} leaves ${depths[t]![1]} one_child ${depths[t]![2]}',
  ];
}

List<String> quadStatistics(NodeView root, int capacity) {
  final depths = <int, List<int>>{};
  var height = 0, internal = 0, leaves = 0, empty = 0, maximum = 0;
  for (final v in preorder(root)) {
    final row = depths.putIfAbsent(v.depth, () => [0, 0, 0]);
    if (v.children.isNotEmpty) {
      row[0]++;
      internal++;
    } else {
      final count = v.held.length;
      row[1]++;
      row[2] += count;
      leaves++;
      if (count == 0) {
        empty++;
      }
      maximum = max(maximum, count);
    }
    height = max(height, v.depth + 1);
  }
  return [
    'quadtree height $height internal $internal leaves $leaves empty $empty max_leaf $maximum fill ${fraction(root.count, leaves * capacity)}',
    for (var t = 0; t < height; t++)
      '  depth $t internal ${depths[t]![0]} leaves ${depths[t]![1]} points ${depths[t]![2]}',
  ];
}

List<String> rtreeStatistics(
  String name,
  NodeView root,
  int maximum,
  int minimum,
) {
  final levels = <int, List<NodeView>>{};
  var nodes = 0, entries = 0;
  for (final v in preorder(root)) {
    levels.putIfAbsent(v.r!.level, () => []).add(v);
    nodes++;
    entries += v.r!.entries.length;
  }
  final height = root.r!.level + 1,
      lines = <String>[
        '$name height $height nodes $nodes leaves ${levels[0]!.length} entries $entries fill ${fraction(entries, nodes * maximum)}',
      ];
  for (var level = height - 1; level >= 0; level--) {
    final group = levels[level]!;
    var count = 0,
        smallest = maximum + 1,
        largest = 0,
        under = 0,
        areaSum = 0,
        overlapSum = 0;
    for (var i = 0; i < group.length; i++) {
      final v = group[i], size = v.r!.entries.length;
      count += size;
      smallest = min(smallest, size);
      largest = max(largest, size);
      if (size < minimum) {
        under++;
      }
      areaSum += area(v.region);
      for (final other in group.skip(i + 1)) {
        overlapSum += overlap(v.region, other.region);
      }
    }
    lines.add(
      '  level $level nodes ${group.length} entries $count min $smallest max $largest under $under area $areaSum overlap $overlapSum',
    );
  }
  return lines;
}

List<String> gridStatistics(NodeView root) {
  final occupancy = <int, int>{};
  var maximum = 0;
  for (final cell in root.children) {
    final size = cell.held.length;
    occupancy[size] = (occupancy[size] ?? 0) + 1;
    maximum = max(maximum, size);
  }
  final sequence = [
    for (var size = 0; size <= maximum; size++)
      if (occupancy.containsKey(size)) '$size:${occupancy[size]}',
  ].join(' ');
  return [
    'grid cells ${root.children.length} used ${root.children.length - (occupancy[0] ?? 0)} max $maximum',
    '  occupancy $sequence',
  ];
}

class VisitTotal {
  int queries = 0, nodes = 0, tests = 0, maximum = 0;
}

List<String> visitsSummary(Map<String, Map<String, VisitTotal>> totals) {
  final lines = <String>['visits'];
  for (final command in searchCommands) {
    final rows = totals[command];
    if (rows == null) {
      continue;
    }
    final structures = structuresFor(command);
    for (final name in structures) {
      final v = rows[name]!;
      lines.add(
        '$command $name queries ${v.queries} nodes ${v.nodes} tests ${v.tests} max_nodes ${v.maximum} mean_nodes ${fraction(v.nodes, v.queries)}',
      );
    }
    final ranking = List<String>.of(structures)
      ..sort((a, b) {
        final x = rows[a]!,
            y = rows[b]!,
            c = x.nodes.compareTo(y.nodes),
            d = x.tests.compareTo(y.tests);
        return c != 0
            ? c
            : d != 0
            ? d
            : structures.indexOf(a).compareTo(structures.indexOf(b));
      });
    lines.add('rank $command ${ranking.join(' ')}');
  }
  return lines;
}

class Laboratory {
  final points = <int, SpatialObject>{}, rectangles = <int, SpatialObject>{};
  final Params params;
  late KDNode kd;
  late final QuadNode quad;
  late final Grid grid;
  final rtrees = <String, RTree>{}, views = <String, NodeView>{};
  final answers = <String>[],
      visits = <String>['query,command,structure,nodes,tests'],
      joinRows = <String>['query,rect,point'],
      structures = <String>[],
      statistics = <String>[];
  final totals = <String, Map<String, VisitTotal>>{};
  int snapshot = 0;
  Laboratory(
    List<SpatialObject> initialPoints,
    List<SpatialObject> rects,
    this.params,
  ) {
    for (final o in initialPoints) {
      points[o.id] = o;
    }
    for (final o in rects) {
      rectangles[o.id] = o;
    }
    kd = buildKD(initialPoints, 0)!;
    quad = buildQuad(initialPoints, params.world, params.bucket);
    grid = Grid(params.world, params.cellSize, initialPoints);
    for (final name in rtreeStructures) {
      rtrees[name] = buildRTree(
        rectangleStructures.contains(name) ? rects : initialPoints,
        params.maximum,
        params.minimum,
        ['str', 'str_rect'].contains(name),
      );
    }
    refresh();
    for (final name in rectangleStructures) {
      views[name] = rtreeView(rtrees[name]!.root, rectangles, 0);
    }
    recordSnapshot(0);
  }
  void refresh() {
    views['kdtree'] = kdView(
      kd,
      Box(0, 0, params.world - 1, params.world - 1),
      'root',
      0,
    );
    views['quadtree'] = quadView(quad, 'root', 0);
    for (final name in ['rtree', 'str']) {
      views[name] = rtreeView(rtrees[name]!.root, points, 0);
    }
    views['grid'] = gridView(grid);
  }

  void recordSnapshot(int query) {
    final header =
        'snapshot $snapshot query $query points ${points.length} rects ${rectangles.length}';
    if (structures.isNotEmpty) {
      structures.add('');
      statistics.add('');
    }
    structures.addAll([
      header,
      'kdtree',
      ...dumpTree(views['kdtree']!, 'kdtree'),
      'quadtree',
      ...dumpTree(views['quadtree']!, 'quadtree'),
    ]);
    statistics.addAll([
      header,
      ...kdStatistics(views['kdtree']!),
      ...quadStatistics(views['quadtree']!, params.bucket),
    ]);
    for (final name in rtreeStructures) {
      structures.addAll([name, ...dumpTree(views[name]!, name)]);
      statistics.addAll(
        rtreeStatistics(name, views[name]!, params.maximum, params.minimum),
      );
    }
    statistics.addAll(gridStatistics(views['grid']!));
  }

  SearchResult searchStructure(String name, String command, List<int> values) {
    final root = views[name]!;
    if (['RANGE', 'RADIUS', 'CONTAINS'].contains(command)) {
      final (region, object) = conditions(command, values);
      return conditionSearch(root, region, object);
    }
    if (command == 'WINDOWCOUNT') {
      return windowCount(root, Box(values[0], values[1], values[2], values[3]));
    }
    if (command == 'JOIN') {
      return spatialJoin(root, views['${name}_rect']!);
    }
    return bestFirst(root, values[0], values[1], values[2]);
  }

  void recordVisit(
    int query,
    String command,
    String name,
    SearchResult result,
  ) {
    visits.add('$query,$command,$name,${result.nodes},${result.tests}');
    final v = totals
        .putIfAbsent(command, () => {})
        .putIfAbsent(name, VisitTotal.new);
    v.queries++;
    v.nodes += result.nodes;
    v.tests += result.tests;
    v.maximum = max(v.maximum, result.nodes);
  }

  void processSearch(int query, String command, List<int> values) {
    final expected = bruteForce(command, values, points, rectangles),
        mismatches = <String>[];
    for (final name in structuresFor(command)) {
      final actual = searchStructure(name, command, values);
      recordVisit(query, command, name, actual);
      if (!sameAnswer(actual, expected)) {
        mismatches.add(name);
      }
    }
    final check = mismatches.isEmpty
        ? 'ok'
        : 'mismatch ${mismatches.join(' ')}';
    String line;
    if (command == 'WINDOWCOUNT') {
      line = '$query $command count ${expected.count} check $check';
    } else if (command == 'JOIN') {
      line = '$query JOIN count ${expected.pairs.length} check $check';
      for (final (r, p) in expected.pairs) {
        joinRows.add('$query,$r,$p');
      }
    } else {
      final nearest = ['KNN', 'NEAREST'].contains(command),
          sequence = nearest ? distances(expected.pairs) : ids(expected.ids),
          count = nearest ? expected.pairs.length : expected.ids.length;
      line = '$query $command count $count ids $sequence check $check';
    }
    answers.add(line);
  }

  void processLocate(int query, int id) {
    final point = points[id];
    if (point == null) {
      answers.add('$query LOCATE $id missing');
      return;
    }
    final (column, row) = grid.position(point);
    answers.add(
      '$query LOCATE $id kdtree ${locateKD(kd, point)} quadtree ${locateQuad(quad, point)} rtree ${locateRTree(rtrees['rtree']!.root, point)} str ${locateRTree(rtrees['str']!.root, point)} grid $column $row',
    );
  }

  void processInsert(int query, SpatialObject point) {
    points[point.id] = point;
    kd = insertKD(kd, point);
    insertQuad(quad, point, params.bucket);
    for (final name in ['rtree', 'str']) {
      rtrees[name]!.insert(Entry(point.box, id: point.id));
    }
    grid.insert(point);
    refresh();
    answers.add('$query INSERT ${point.id} inserted points ${points.length}');
  }

  void processDelete(int query, int id) {
    final point = points[id];
    var status = 'missing';
    if (point != null) {
      kd = deleteKD(kd, point)!;
      deleteQuad(quad, point, params.bucket);
      for (final name in ['rtree', 'str']) {
        rtrees[name]!.delete(point);
      }
      grid.delete(point);
      points.remove(id);
      refresh();
      status = 'deleted';
    }
    answers.add('$query DELETE $id $status points ${points.length}');
  }

  void process(List<Command> commands) {
    for (var i = 0; i < commands.length; i++) {
      final c = commands[i], q = i + 1;
      switch (c.name) {
        case 'LOCATE':
          processLocate(q, c.values[0]);
        case 'INSERT':
          final v = c.values;
          processInsert(q, SpatialObject(v[0], Box(v[1], v[2], v[1], v[2])));
        case 'DELETE':
          processDelete(q, c.values[0]);
        case 'DUMP':
          snapshot++;
          recordSnapshot(q);
          answers.add('$q DUMP snapshot $snapshot');
        default:
          processSearch(q, c.name, c.values);
      }
    }
  }

  void write() {
    final files = {
      'answers.txt': answers,
      'visits.csv': visits,
      'join.csv': joinRows,
      'structures.txt': structures,
      'stats.txt': [...statistics, '', ...visitsSummary(totals)],
    };
    for (final entry in files.entries) {
      writeLines(entry.key, entry.value);
    }
  }
}

void main() {
  final (points, rects, params, commands) = readDataset();
  final lab = Laboratory(points, rects, params);
  lab.process(commands);
  lab.write();
}
