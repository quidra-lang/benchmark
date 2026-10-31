import 'dart:io';
import 'dart:math' as math;

enum Operation { sum, min, max, gcd }

final class CommandError implements Exception {
  final String message;
  const CommandError(this.message);
}

int gcd(int a, int b) => a.gcd(b);
int integerSqrt(int n) {
  var result = 1;
  while ((result + 1) * (result + 1) <= n) result++;
  return result;
}

int log2(int n) {
  var result = 0;
  while ((1 << (result + 1)) <= n) result++;
  return result;
}

int combine(Operation operation, int a, int b) => switch (operation) {
  Operation.sum => a + b,
  Operation.min => math.min(a, b),
  Operation.max => math.max(a, b),
  Operation.gcd => gcd(a, b),
};

typedef ScalarAnswer = ({int value, int visited});
typedef Aggregate = ({int sum, int min, int max});
typedef LazyAnswer = ({Aggregate value, int visited, int pushes});
typedef SparseAnswer = ({int min, int minpos, int max, int maxpos, int level});
typedef Partition = ({List<int> cells, List<int> whole});
typedef SqrtAnswer = ({int sum, Partition partition});

String sumText(ScalarAnswer answer) => 'sum=${answer.value} visited=${answer.visited}';
String aggregateText(Aggregate value) => 'sum=${value.sum} min=${value.min} max=${value.max}';
String lazyText(LazyAnswer answer) => '${aggregateText(answer.value)} visited=${answer.visited} pushes=${answer.pushes}';
String sparseText(SparseAnswer answer) => 'min=${answer.min} minpos=${answer.minpos} max=${answer.max} maxpos=${answer.maxpos} level=${answer.level}';
String partitionText(Partition split) => 'whole=${split.whole.length} cells=${split.cells.length}';
String sqrtText(SqrtAnswer answer) => 'sum=${answer.sum} ${partitionText(answer.partition)}';
Aggregate merge(Aggregate a, Aggregate b) => (sum: a.sum + b.sum, min: math.min(a.min, b.min), max: math.max(a.max, b.max));

final class Interval {
  final int left, right;
  const Interval(this.left, this.right);
  bool get leaf => left == right;
  int get middle => (left + right) ~/ 2;
  int get length => right - left + 1;
  bool covered(int l, int r) => l <= left && right <= r;
}

final class Layout {
  final List<Interval?> ranges;
  final int count;
  int maxNode = 0;
  Layout(int n) : ranges = List.filled(4 * n, null), count = 2 * n - 1 {
    _build(1, 0, n - 1);
  }
  Interval operator [](int node) => ranges[node]!;
  void _build(int node, int left, int right) {
    ranges[node] = Interval(left, right);
    maxNode = math.max(maxNode, node);
    if (left == right) return;
    final middle = (left + right) ~/ 2;
    _build(2 * node, left, middle);
    _build(2 * node + 1, middle + 1, right);
  }
  Iterable<(int, Interval)> get nodes sync* {
    for (var node = 1; node <= maxNode; node++) {
      final range = ranges[node];
      if (range != null) yield (node, range);
    }
  }
}

final class SegmentTree {
  final Operation operation;
  final Layout shape;
  final List<int> values;
  int get root => values[1];
  SegmentTree(List<int> contents, this.operation)
    : shape = Layout(contents.length), values = List.filled(4 * contents.length, 0) {
    _build(1, contents);
  }

  void _build(int node, List<int> contents) {
    final range = shape[node];
    if (range.leaf) {
      values[node] = operation == Operation.gcd ? contents[range.left].abs() : contents[range.left];
    } else {
      _build(2 * node, contents);
      _build(2 * node + 1, contents);
      _pull(node);
    }
  }
  void _pull(int node) => values[node] = combine(operation, values[2 * node], values[2 * node + 1]);

  ScalarAnswer query(int left, int right, [int node = 1]) {
    final range = shape[node];
    if (range.covered(left, right)) return (value: values[node], visited: 1);
    if (right <= range.middle || left > range.middle) {
      final child = query(left, right, right <= range.middle ? 2 * node : 2 * node + 1);
      return (value: child.value, visited: child.visited + 1);
    }
    final a = query(left, right, 2 * node);
    final b = query(left, right, 2 * node + 1);
    return (value: combine(operation, a.value, b.value), visited: a.visited + b.visited + 1);
  }

  int update(int index, int value, [int node = 1]) {
    final range = shape[node];
    if (range.leaf) {
      values[node] = operation == Operation.gcd ? value.abs() : value;
      return 1;
    }
    final visited = update(index, value, index <= range.middle ? 2 * node : 2 * node + 1);
    _pull(node);
    return visited + 1;
  }

  String describe(ScalarAnswer answer) => '${operation.name}=${answer.value} visited=${answer.visited}';
  Iterable<String> dump() sync* {
    yield 'SEG DUMP ${operation.name.toUpperCase()} nodes=${shape.count}';
    for (final (node, range) in shape.nodes) {
      yield 'NODE $node ${range.left} ${range.right} ${values[node]}';
    }
  }
}

final class Work {
  int visited = 0, covered = 0, pushes = 0;
  @override
  String toString() => 'visited=$visited covered=$covered pushes=$pushes';
}

final class LazyTree {
  final Layout shape;
  final List<Aggregate> values;
  final List<int?> assign;
  final List<int> add;
  Aggregate get root => values[1];
  LazyTree(List<int> contents)
    : shape = Layout(contents.length),
      values = List.filled(4 * contents.length, (sum: 0, min: 0, max: 0)),
      assign = List.filled(4 * contents.length, null),
      add = List.filled(4 * contents.length, 0) {
    _build(1, contents);
  }

  void _build(int node, List<int> contents) {
    final range = shape[node];
    if (range.leaf) {
      final value = contents[range.left];
      values[node] = (sum: value, min: value, max: value);
    } else {
      _build(2 * node, contents);
      _build(2 * node + 1, contents);
      _pull(node);
    }
  }
  void _pull(int node) => values[node] = merge(values[2 * node], values[2 * node + 1]);

  void _apply(int node, int value, bool assignment) {
    final range = shape[node];
    final old = values[node];
    values[node] = assignment
      ? (sum: value * range.length, min: value, max: value)
      : (sum: old.sum + value * range.length, min: old.min + value, max: old.max + value);
    if (range.leaf) return;
    if (assignment) {
      assign[node] = value;
      add[node] = 0;
    } else {
      add[node] += value;
    }
  }

  int _push(int node) {
    final assignment = assign[node];
    if (assignment == null && add[node] == 0) return 0;
    for (var child = 2 * node; child <= 2 * node + 1; child++) {
      if (assignment != null) _apply(child, assignment, true);
      if (add[node] != 0) _apply(child, add[node], false);
    }
    assign[node] = null;
    add[node] = 0;
    return 1;
  }

  Work update(int left, int right, int value, bool assignment) {
    final work = Work();
    void visit(int node) {
      work.visited++;
      final range = shape[node];
      if (range.covered(left, right)) {
        work.covered++;
        _apply(node, value, assignment);
        return;
      }
      work.pushes += _push(node);
      if (left <= range.middle) visit(2 * node);
      if (right > range.middle) visit(2 * node + 1);
      _pull(node);
    }
    visit(1);
    return work;
  }

  LazyAnswer query(int left, int right, [int node = 1]) {
    final range = shape[node];
    if (range.covered(left, right)) return (value: values[node], visited: 1, pushes: 0);
    final pushes = _push(node);
    if (right <= range.middle || left > range.middle) {
      final child = query(left, right, right <= range.middle ? 2 * node : 2 * node + 1);
      return (value: child.value, visited: child.visited + 1, pushes: child.pushes + pushes);
    }
    final a = query(left, right, 2 * node);
    final b = query(left, right, 2 * node + 1);
    return (value: merge(a.value, b.value), visited: a.visited + b.visited + 1, pushes: a.pushes + b.pushes + pushes);
  }

  Iterable<String> dump() sync* {
    yield 'LAZY DUMP nodes=${shape.count}';
    for (final (node, range) in shape.nodes) {
      yield 'NODE $node ${range.left} ${range.right} ${aggregateText(values[node])} assign=${assign[node] ?? '-'} add=${add[node]}';
    }
  }
}

final class Fenwick {
  final List<int> tree;
  int get n => tree.length - 1;
  Fenwick(int n) : tree = List.filled(n + 1, 0);
  int add(int position, int value) {
    var visited = 0;
    for (; position <= n; position += position & -position) {
      tree[position] += value;
      visited++;
    }
    return visited;
  }
  ScalarAnswer prefix(int position) {
    var sum = 0, visited = 0;
    for (; position > 0; position -= position & -position) {
      sum += tree[position];
      visited++;
    }
    return (value: sum, visited: visited);
  }
  String dump(String name) => '$name ${tree.skip(1).join(' ')}';
}

final class PointFenwick {
  final List<int> contents;
  final Fenwick bits;
  PointFenwick(List<int> values) : contents = List.of(values), bits = Fenwick(values.length) {
    for (var i = 0; i < values.length; i++) bits.add(i + 1, values[i]);
  }
  int add(int index, int value) {
    contents[index] += value;
    return bits.add(index + 1, value);
  }
  ScalarAnswer query(int left, int right) {
    final a = bits.prefix(right + 1), b = bits.prefix(left);
    return (value: a.value - b.value, visited: a.visited + b.visited);
  }
  ({int? index, int visited}) lower(int rest) {
    var position = 0, visited = 0;
    for (var step = 1 << log2(contents.length); step >= 1; step ~/= 2) {
      if (position + step > contents.length) continue;
      visited++;
      final value = bits.tree[position + step];
      if (value < rest) {
        rest -= value;
        position += step;
      }
    }
    return (index: position == contents.length ? null : position, visited: visited);
  }
}

final class RangeFenwick {
  final Fenwick b1, b2;
  RangeFenwick(List<int> contents) : b1 = Fenwick(contents.length), b2 = Fenwick(contents.length) {
    for (var i = 0; i < contents.length; i++) {
      final difference = contents[i] - (i == 0 ? 0 : contents[i - 1]);
      b1.add(i + 1, difference);
      b2.add(i + 1, i * difference);
    }
  }
  int add(int left, int right, int value) {
    var visited = b1.add(left + 1, value);
    visited += b1.add(right + 2, -value);
    visited += b2.add(left + 1, value * left);
    visited += b2.add(right + 2, -value * (right + 1));
    return visited;
  }
  ScalarAnswer _prefix(int position) {
    final a = b1.prefix(position), b = b2.prefix(position);
    return (value: position * a.value - b.value, visited: a.visited + b.visited);
  }
  ScalarAnswer query(int left, int right) {
    final a = _prefix(right + 1), b = _prefix(left);
    return (value: a.value - b.value, visited: a.visited + b.visited);
  }
}

final class SparseTable {
  final List<int> contents;
  final List<List<int>> minimum = [], maximum = [];
  int get entries => minimum.fold(0, (sum, row) => sum + row.length);
  SparseTable(List<int> values) : contents = List.of(values) {
    minimum.add(List.generate(values.length, (i) => i));
    maximum.add(List.generate(values.length, (i) => i));
    for (var level = 1; (1 << level) <= values.length; level++) {
      final length = values.length - (1 << level) + 1, half = 1 << (level - 1);
      final minima = List<int>.filled(length, 0), maxima = List<int>.filled(length, 0);
      for (var i = 0; i < length; i++) {
        minima[i] = _select(minimum[level - 1][i], minimum[level - 1][i + half], true);
        maxima[i] = _select(maximum[level - 1][i], maximum[level - 1][i + half], false);
      }
      minimum.add(minima);
      maximum.add(maxima);
    }
  }
  int _select(int a, int b, bool isMinimum) => (isMinimum ? contents[a] <= contents[b] : contents[a] >= contents[b]) ? a : b;
  SparseAnswer query(int left, int right) {
    final level = log2(right - left + 1);
    final end = right - (1 << level) + 1;
    final a = _select(minimum[level][left], minimum[level][end], true);
    final z = _select(maximum[level][left], maximum[level][end], false);
    return (min: contents[a], minpos: a, max: contents[z], maxpos: z, level: level);
  }
  Iterable<String> dump() sync* {
    yield 'SPARSE DUMP levels=${minimum.length}';
    for (var level = 0; level < minimum.length; level++) {
      yield 'MIN $level ${minimum[level].join(' ')}';
      yield 'MAX $level ${maximum[level].join(' ')}';
    }
  }
}

final class SqrtBlocks {
  final int blockSize;
  final List<int> raw, tag, sums;
  int get count => tag.length;
  SqrtBlocks(List<int> contents, this.blockSize)
    : raw = List.of(contents),
      tag = List.filled((contents.length + blockSize - 1) ~/ blockSize, 0),
      sums = List.filled((contents.length + blockSize - 1) ~/ blockSize, 0) {
    for (var i = 0; i < raw.length; i++) sums[i ~/ blockSize] += raw[i];
  }
  Partition _partition(int left, int right) {
    final cells = <int>[], whole = <int>[];
    final first = left ~/ blockSize, last = right ~/ blockSize;
    if (first == last) {
      for (var i = left; i <= right; i++) cells.add(i);
    } else {
      for (var i = left; i < (first + 1) * blockSize; i++) cells.add(i);
      for (var i = last * blockSize; i <= right; i++) cells.add(i);
      for (var block = first + 1; block < last; block++) whole.add(block);
    }
    return (cells: cells, whole: whole);
  }
  Partition add(int left, int right, int value) {
    final split = _partition(left, right);
    for (final i in split.cells) {
      raw[i] += value;
      sums[i ~/ blockSize] += value;
    }
    for (final block in split.whole) {
      tag[block] += value;
      sums[block] += value * blockSize;
    }
    return split;
  }
  SqrtAnswer query(int left, int right) {
    final split = _partition(left, right);
    var sum = 0;
    for (final i in split.cells) sum += raw[i] + tag[i ~/ blockSize];
    for (final block in split.whole) sum += sums[block];
    return (sum: sum, partition: split);
  }
  Iterable<String> dump() sync* {
    yield 'SQRT DUMP block=$blockSize blocks=$count';
    for (var block = 0; block < count; block++) {
      final first = block * blockSize, end = math.min((block + 1) * blockSize, raw.length);
      yield 'BLOCK $block $first ${end - 1} add=${tag[block]} sum=${sums[block]} ${raw.sublist(first, end).join(' ')}';
    }
  }
}

final class PersistentNode {
  final int value;
  final PersistentNode? left, right;
  const PersistentNode(this.value, [this.left, this.right]);
}

final class PersistentTree {
  final int n;
  final List<int> values;
  final List<PersistentNode> versions = [], valueRoots = [];
  int positionNodes, valueNodes = 0;
  int get distinct => values.length;
  PersistentTree(List<int> contents)
    : n = contents.length,
      values = contents.toSet().toList()..sort(),
      positionNodes = 2 * contents.length - 1 {
    versions.add(_build(contents, 0, n - 1));
    valueRoots.add(_build(List.filled(values.length, 0), 0, values.length - 1));
    valueNodes = 2 * values.length - 1;
    final ranks = {for (var i = 0; i < values.length; i++) values[i]: i};
    for (final value in contents) {
      final changed = _change(valueRoots.last, 0, values.length - 1, ranks[value]!, 1, true);
      valueRoots.add(changed.node);
      valueNodes += changed.created;
    }
  }
  static PersistentNode _build(List<int> contents, int left, int right) {
    if (left == right) return PersistentNode(contents[left]);
    final middle = (left + right) ~/ 2;
    final a = _build(contents, left, middle);
    final b = _build(contents, middle + 1, right);
    return PersistentNode(a.value + b.value, a, b);
  }
  static ({PersistentNode node, int created}) _change(PersistentNode node, int left, int right, int index, int value, bool increment) {
    if (left == right) return (node: PersistentNode(increment ? node.value + value : value), created: 1);
    final middle = (left + right) ~/ 2;
    var a = node.left!, b = node.right!;
    final changed = index <= middle
      ? _change(a, left, middle, index, value, increment)
      : _change(b, middle + 1, right, index, value, increment);
    if (index <= middle) a = changed.node; else b = changed.node;
    return (node: PersistentNode(a.value + b.value, a, b), created: changed.created + 1);
  }
  int setValue(int version, int index, int value) {
    final changed = _change(versions[version], 0, n - 1, index, value, false);
    versions.add(changed.node);
    positionNodes += changed.created;
    return changed.created;
  }
  static ScalarAnswer _sum(PersistentNode node, int nl, int nr, int left, int right) {
    if (left <= nl && nr <= right) return (value: node.value, visited: 1);
    final middle = (nl + nr) ~/ 2;
    if (right <= middle || left > middle) {
      final child = right <= middle ? _sum(node.left!, nl, middle, left, right) : _sum(node.right!, middle + 1, nr, left, right);
      return (value: child.value, visited: child.visited + 1);
    }
    final a = _sum(node.left!, nl, middle, left, right);
    final b = _sum(node.right!, middle + 1, nr, left, right);
    return (value: a.value + b.value, visited: a.visited + b.visited + 1);
  }
  ScalarAnswer query(int version, int left, int right) => _sum(versions[version], 0, n - 1, left, right);
  ScalarAnswer kth(int left, int right, int k) {
    var u = valueRoots[right + 1], w = valueRoots[left];
    var p = 0, q = values.length - 1, visited = 1;
    while (p < q) {
      final middle = (p + q) ~/ 2;
      final difference = u.left!.value - w.left!.value;
      if (k <= difference) {
        u = u.left!;
        w = w.left!;
        q = middle;
      } else {
        k -= difference;
        u = u.right!;
        w = w.right!;
        p = middle + 1;
      }
      visited++;
    }
    return (value: values[p], visited: visited);
  }
}

final class GridFenwick {
  final int height, width;
  final List<List<int>> tree;
  GridFenwick(this.height, this.width, List<int> contents)
    : tree = List.generate(height + 1, (_) => List.filled(width + 1, 0)) {
    for (var i = 0; i < height; i++) {
      for (var j = 0; j < width; j++) add(i, j, contents[i * width + j]);
    }
  }
  int add(int row, int column, int value) {
    var visited = 0;
    for (var y = row + 1; y <= height; y += y & -y) {
      for (var z = column + 1; z <= width; z += z & -z) {
        tree[y][z] += value;
        visited++;
      }
    }
    return visited;
  }
  ScalarAnswer _prefix(int row, int column) {
    var sum = 0, visited = 0;
    for (var y = row; y > 0; y -= y & -y) {
      for (var z = column; z > 0; z -= z & -z) {
        sum += tree[y][z];
        visited++;
      }
    }
    return (value: sum, visited: visited);
  }
  ScalarAnswer query(int top, int left, int bottom, int right) {
    final a = _prefix(bottom + 1, right + 1), b = _prefix(top, right + 1);
    final c = _prefix(bottom + 1, left), d = _prefix(top, left);
    return (value: a.value - b.value - c.value + d.value, visited: a.visited + b.visited + c.visited + d.visited);
  }
  Iterable<String> dump() sync* {
    yield 'GRID DUMP rows=$height cols=$width';
    for (var row = 1; row <= height; row++) yield 'ROW $row ${tree[row].skip(1).join(' ')}';
  }
}

typedef MoQuery = ({int left, int right, int number});

final class Laboratory {
  List<int> array, original;
  SegmentTree? segment;
  LazyTree? lazy;
  PointFenwick? fenwick;
  RangeFenwick? rangeFenwick;
  SparseTable? sparse;
  SqrtBlocks? sqrt;
  PersistentTree? persistent;
  GridFenwick? grid;
  Laboratory(List<int> values) : array = List.of(values), original = List.of(values);

  int get structureCount => [segment, lazy, fenwick, rangeFenwick, sparse, sqrt, persistent].where((value) => value != null).length;
  T _need<T extends Object>(T? value, String kind) => value ?? (throw CommandError('NOT BUILT $kind'));
  void _checkIndex(int index) {
    if (index < 0 || index >= array.length) throw CommandError('BAD INDEX $index');
  }
  void _checkRange(int left, int right) {
    _checkIndex(left);
    _checkIndex(right);
    if (left > right) throw CommandError('BAD RANGE $left $right');
  }
  void _checkVersion(PersistentTree tree, int version) {
    if (version < 0 || version >= tree.versions.length) throw CommandError('BAD VERSION $version');
  }
  void _checkCell(GridFenwick tree, int row, int column) {
    if (row < 0 || row >= tree.height || column < 0 || column >= tree.width) throw CommandError('BAD CELL $row $column');
  }
  void _changeArray(int left, int right, int value, [bool assignment = false]) {
    for (var i = left; i <= right; i++) array[i] = assignment ? value : array[i] + value;
  }

  List<String> _check(int left, int right) {
    _checkRange(left, right);
    var sum = 0, minimum = array[left], maximum = array[left], divisor = 0;
    for (var i = left; i <= right; i++) {
      sum += array[i];
      minimum = math.min(minimum, array[i]);
      maximum = math.max(maximum, array[i]);
      divisor = gcd(divisor, array[i]);
    }
    final rows = ['CHECK $left $right sum=$sum min=$minimum max=$maximum gcd=$divisor'];
    var ok = 0, diff = 0;
    void report(String kind, bool equal, String text) {
      if (equal) ok++; else diff++;
      rows.add('$kind ${equal ? 'OK' : 'DIFF'} $text');
    }
    final seg = segment;
    if (seg != null) {
      final answer = seg.query(left, right);
      final expected = switch (seg.operation) {
        Operation.sum => sum, Operation.min => minimum, Operation.max => maximum, Operation.gcd => divisor,
      };
      report('SEG', answer.value == expected, seg.describe(answer));
    }
    final lazyTree = lazy;
    if (lazyTree != null) {
      final answer = lazyTree.query(left, right);
      report('LAZY', answer.value == (sum: sum, min: minimum, max: maximum), lazyText(answer));
    }
    final fen = fenwick;
    if (fen != null) {
      final answer = fen.query(left, right);
      report('FEN', answer.value == sum, sumText(answer));
    }
    final rfen = rangeFenwick;
    if (rfen != null) {
      final answer = rfen.query(left, right);
      report('RFEN', answer.value == sum, sumText(answer));
    }
    final sparseTable = sparse;
    if (sparseTable != null) {
      final answer = sparseTable.query(left, right);
      report('SPARSE', answer.min == minimum && answer.max == maximum, sparseText(answer));
    }
    final blocks = sqrt;
    if (blocks != null) {
      final answer = blocks.query(left, right);
      report('SQRT', answer.sum == sum, sqrtText(answer));
    }
    final versions = persistent;
    if (versions != null) {
      final version = versions.versions.length - 1;
      final answer = versions.query(version, left, right);
      report('PERSIST', answer.value == sum, 'version=$version ${sumText(answer)}');
    }
    rows.add('RESULT ok=$ok diff=$diff');
    return rows;
  }

  List<String> _mo(List<String> words) {
    final queries = <MoQuery>[];
    for (var i = 1; i < words.length; i += 2) {
      final left = int.parse(words[i]), right = int.parse(words[i + 1]);
      _checkRange(left, right);
      queries.add((left: left, right: right, number: queries.length + 1));
    }
    final blockSize = integerSqrt(array.length);
    final order = List<MoQuery>.of(queries)..sort((a, b) {
      final blockA = a.left ~/ blockSize, blockB = b.left ~/ blockSize;
      if (blockA != blockB) return blockA.compareTo(blockB);
      if (a.right != b.right) return blockA.isEven ? a.right.compareTo(b.right) : b.right.compareTo(a.right);
      return a.number.compareTo(b.number);
    });
    final frequency = <int, int>{};
    final answers = List<int>.filled(queries.length, 0);
    var leftEdge = 0, rightEdge = -1, moves = 0;
    void add(int i) {
      frequency[array[i]] = (frequency[array[i]] ?? 0) + 1;
      moves++;
    }
    void remove(int i) {
      final count = frequency[array[i]]! - 1;
      if (count == 0) frequency.remove(array[i]); else frequency[array[i]] = count;
      moves++;
    }
    for (final query in order) {
      while (leftEdge > query.left) add(--leftEdge);
      while (rightEdge < query.right) add(++rightEdge);
      while (leftEdge < query.left) remove(leftEdge++);
      while (rightEdge > query.right) remove(rightEdge--);
      answers[query.number - 1] = frequency.length;
    }
    return [
      'MO queries=${queries.length} block=$blockSize moves=$moves',
      'ORDER ${order.map((q) => q.number).join(' ')}',
      for (final query in queries) 'ANSWER ${query.number} ${query.left} ${query.right} distinct=${answers[query.number - 1]}',
    ];
  }

  List<String> execute(String line) {
    final words = line.split(' ');
    int number(int index) => int.parse(words[index]);
    final kind = words[0];
    if (kind == 'ARRAY') {
      final left = number(1), right = number(2);
      _checkRange(left, right);
      return ['ARRAY $left $right ${array.sublist(left, right + 1).join(' ')}'];
    }
    if (kind == 'LOAD') {
      final removed = structureCount;
      original = words.skip(1).map(int.parse).toList();
      array = List.of(original);
      segment = null; lazy = null; fenwick = null; rangeFenwick = null; sparse = null; sqrt = null; persistent = null;
      return ['LOAD n=${array.length} removed=$removed'];
    }
    if (kind == 'RESET') {
      final rebuilt = structureCount;
      array = List.of(original);
      if (segment != null) segment = SegmentTree(array, segment!.operation);
      if (lazy != null) lazy = LazyTree(array);
      if (fenwick != null) fenwick = PointFenwick(array);
      if (rangeFenwick != null) rangeFenwick = RangeFenwick(array);
      if (sparse != null) sparse = SparseTable(array);
      if (sqrt != null) sqrt = SqrtBlocks(array, sqrt!.blockSize);
      if (persistent != null) persistent = PersistentTree(array);
      return ['RESET rebuilt=$rebuilt'];
    }
    if (kind == 'CHECK') return _check(number(1), number(2));
    if (kind == 'MO') return _mo(words);
    final action = words[1];
    switch (kind) {
      case 'SEG':
        if (action == 'BUILD') {
          final matches = Operation.values.where((op) => op.name.toUpperCase() == words[2]);
          if (matches.isEmpty) throw CommandError('BAD OP ${words[2]}');
          final tree = SegmentTree(array, matches.first);
          segment = tree;
          return ['SEG BUILD ${words[2]} nodes=${tree.shape.count} maxnode=${tree.shape.maxNode} root=${tree.root}'];
        }
        final tree = _need(segment, kind);
        if (action == 'DUMP') return tree.dump().toList();
        final left = number(2);
        if (action == 'UPDATE') {
          _checkIndex(left);
          final value = number(3);
          final visited = tree.update(left, value);
          array[left] = value;
          return ['SEG UPDATE $left $value root=${tree.root} visited=$visited'];
        }
        final right = number(3);
        _checkRange(left, right);
        return ['SEG QUERY $left $right ${tree.describe(tree.query(left, right))}'];
      case 'LAZY':
        if (action == 'BUILD') {
          final tree = LazyTree(array);
          lazy = tree;
          return ['LAZY BUILD nodes=${tree.shape.count} ${aggregateText(tree.root)}'];
        }
        final tree = _need(lazy, kind);
        if (action == 'DUMP') return tree.dump().toList();
        final left = number(2), right = number(3);
        _checkRange(left, right);
        if (action == 'QUERY') return ['LAZY QUERY $left $right ${lazyText(tree.query(left, right))}'];
        final value = number(4);
        final assignment = action == 'ASSIGN';
        final work = tree.update(left, right, value, assignment);
        _changeArray(left, right, value, assignment);
        return ['LAZY $action $left $right $value $work'];
      case 'FEN':
        if (action == 'BUILD') {
          final tree = PointFenwick(array);
          fenwick = tree;
          return ['FEN BUILD n=${array.length} total=${tree.bits.prefix(array.length).value}'];
        }
        final tree = _need(fenwick, kind);
        if (action == 'DUMP') return ['FEN DUMP n=${array.length}', tree.bits.dump('T')];
        if (action == 'LOWER') {
          for (var i = 0; i < array.length; i++) {
            if (tree.contents[i] < 0) throw CommandError('NEGATIVE $i');
          }
          final target = number(2);
          final answer = tree.lower(target);
          return ['FEN LOWER $target index=${answer.index ?? 'none'} visited=${answer.visited}'];
        }
        final left = number(2);
        if (action == 'RANGE') {
          final right = number(3);
          _checkRange(left, right);
          return ['FEN RANGE $left $right ${sumText(tree.query(left, right))}'];
        }
        _checkIndex(left);
        if (action == 'PREFIX') return ['FEN PREFIX $left ${sumText(tree.bits.prefix(left + 1))}'];
        final value = number(3);
        final visited = tree.add(left, value);
        array[left] += value;
        return ['FEN ADD $left $value visited=$visited'];
      case 'RFEN':
        if (action == 'BUILD') {
          final tree = RangeFenwick(array);
          rangeFenwick = tree;
          return ['RFEN BUILD n=${array.length} total=${tree.query(0, array.length - 1).value}'];
        }
        final tree = _need(rangeFenwick, kind);
        if (action == 'DUMP') return ['RFEN DUMP n=${array.length}', tree.b1.dump('B1'), tree.b2.dump('B2')];
        final left = number(2), right = number(3);
        _checkRange(left, right);
        if (action == 'SUM') return ['RFEN SUM $left $right ${sumText(tree.query(left, right))}'];
        final value = number(4);
        final visited = tree.add(left, right, value);
        _changeArray(left, right, value);
        return ['RFEN ADD $left $right $value visited=$visited'];
      case 'SPARSE':
        if (action == 'BUILD') {
          final tree = SparseTable(array);
          sparse = tree;
          return ['SPARSE BUILD levels=${tree.minimum.length} entries=${tree.entries}'];
        }
        final tree = _need(sparse, kind);
        if (action == 'DUMP') return tree.dump().toList();
        final left = number(2), right = number(3);
        _checkRange(left, right);
        return ['SPARSE QUERY $left $right ${sparseText(tree.query(left, right))}'];
      case 'SQRT':
        if (action == 'BUILD') {
          final size = words.length == 3 ? number(2) : integerSqrt(array.length);
          if (size > array.length) throw CommandError('BAD BLOCK $size');
          final tree = SqrtBlocks(array, size);
          sqrt = tree;
          return ['SQRT BUILD block=$size blocks=${tree.count}'];
        }
        final tree = _need(sqrt, kind);
        if (action == 'DUMP') return tree.dump().toList();
        final left = number(2), right = number(3);
        _checkRange(left, right);
        if (action == 'SUM') return ['SQRT SUM $left $right ${sqrtText(tree.query(left, right))}'];
        final value = number(4);
        final split = tree.add(left, right, value);
        _changeArray(left, right, value);
        return ['SQRT ADD $left $right $value ${partitionText(split)}'];
      case 'PERSIST':
        if (action == 'BUILD') {
          final tree = PersistentTree(array);
          persistent = tree;
          return ['PERSIST BUILD nodes=${tree.positionNodes} distinct=${tree.distinct} valuenodes=${tree.valueNodes}'];
        }
        final tree = _need(persistent, kind);
        if (action == 'NODES') return ['PERSIST NODES versions=${tree.versions.length} position=${tree.positionNodes} value=${tree.valueNodes}'];
        if (action == 'KTH') {
          final left = number(2), right = number(3), k = number(4);
          _checkRange(left, right);
          if (k < 1 || k > right - left + 1) throw CommandError('BAD K $k');
          final answer = tree.kth(left, right, k);
          return ['PERSIST KTH $left $right $k value=${answer.value} visited=${answer.visited}'];
        }
        final version = number(2);
        _checkVersion(tree, version);
        final index = number(3);
        if (action == 'SET') {
          _checkIndex(index);
          final value = number(4);
          final created = tree.setValue(version, index, value);
          return ['PERSIST SET $version $index $value version=${tree.versions.length - 1} created=$created'];
        }
        final end = number(4);
        _checkRange(index, end);
        return ['PERSIST QUERY $version $index $end ${sumText(tree.query(version, index, end))}'];
      case 'GRID':
        if (action == 'BUILD') {
          final height = number(2), width = number(3), count = words.length - 4;
          if (count != height * width) throw CommandError('BAD COUNT $count ${height * width}');
          final values = words.skip(4).map(int.parse).toList();
          grid = GridFenwick(height, width, values);
          return ['GRID BUILD rows=$height cols=$width total=${values.fold<int>(0, (a, b) => a + b)}'];
        }
        final tree = _need(grid, kind);
        if (action == 'DUMP') return tree.dump().toList();
        final row = number(2), column = number(3);
        _checkCell(tree, row, column);
        if (action == 'ADD') {
          final value = number(4);
          return ['GRID ADD $row $column $value visited=${tree.add(row, column, value)}'];
        }
        final bottom = number(4), right = number(5);
        _checkCell(tree, bottom, right);
        if (row > bottom || column > right) throw CommandError('BAD RECT $row $column $bottom $right');
        return ['GRID SUM $row $column $bottom $right ${sumText(tree.query(row, column, bottom, right))}'];
    }
    throw StateError('Unknown command');
  }
}

void main() {
  int.parse(stdin.readLineSync()!);
  final values = stdin.readLineSync()!.split(' ').map(int.parse).toList();
  final laboratory = Laboratory(values);
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    try {
      for (final row in laboratory.execute(stdin.readLineSync()!)) stdout.writeln(row);
    } on CommandError catch (error) {
      stdout.writeln('ERROR ${error.message}');
    }
  }
}
