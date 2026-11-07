import 'dart:io';
import 'dart:math' as math;

class Problem implements Exception {
  final String message;
  Problem(String message) : message = 'error: $message';
}

Never fail(String message) => throw Problem(message);

class Geometry {
  int x1, y1, x2, y2;
  Geometry(this.x1, this.y1, this.x2, this.y2);
}

class Rectangle extends Geometry {
  final String name, layer;
  Rectangle(this.name, this.layer, int x1, int y1, int x2, int y2)
      : super(x1, y1, x2, y2);
  Rectangle copy({String? name, String? layer, int? x1, int? y1, int? x2, int? y2}) =>
      Rectangle(name ?? this.name, layer ?? this.layer, x1 ?? this.x1,
          y1 ?? this.y1, x2 ?? this.x2, y2 ?? this.y2);
}

class Rule {
  final String kind, layer, outer;
  final int value;
  Rule(this.kind, this.layer, this.outer, this.value);
}

class UndoEntry {
  final Map<String, Rectangle> rectangles;
  final String line;
  UndoEntry(this.rectangles, this.line);
}

class Relation {
  final Geometry common;
  final int ox, oy, gap;
  final String kind, direction;
  Relation(this.common, this.ox, this.oy, this.kind, this.gap, this.direction);
}

class Hole {
  final Geometry box;
  final int area, x, y;
  Hole(this.box, this.area, this.x, this.y);
}

class Violation {
  final String a, b, direction;
  final int gap;
  Violation(this.a, this.b, this.gap, this.direction);
  String line() => '$a $b gap $gap $direction';
}

typedef Point = (int, int);
Map<String, Rectangle> rectangles = {};
final rules = <String, Rule>{};
final history = <UndoEntry>[];
final output = <String>[];

List<Rectangle> ordered() => rectangles.values.toList()
  ..sort((a, b) => a.name.compareTo(b.name));
Rectangle rectangle(String name) => rectangles[name] ?? (fail('unknown rectangle $name'));
List<Rectangle> onLayer(String layer, [bool required = true]) {
  final result = ordered().where((rect) => rect.layer == layer).toList();
  if (required && result.isEmpty) fail('no rectangles on $layer');
  return result;
}

String notation(Geometry rect) => '(${rect.x1},${rect.y1})-(${rect.x2},${rect.y2})';
String point(int x, int y) => '($x,$y)';
int area(Geometry rect) => (rect.x2 - rect.x1) * (rect.y2 - rect.y1);
Geometry bounds(List<Geometry> rects) => Geometry(
    rects.map((rect) => rect.x1).reduce(math.min),
    rects.map((rect) => rect.y1).reduce(math.min),
    rects.map((rect) => rect.x2).reduce(math.max),
    rects.map((rect) => rect.y2).reduce(math.max));
void checkBounds(Geometry rect) {
  if ([rect.x1, rect.y1, rect.x2, rect.y2].any((value) => value.abs() > 10000)) {
    fail('out of bounds');
  }
}
List<int> margins(Geometry outer, Geometry inner) =>
    [inner.x1 - outer.x1, inner.y1 - outer.y1, outer.x2 - inner.x2, outer.y2 - inner.y2];
bool contains(Geometry outer, Geometry inner) => margins(outer, inner).every((value) => value >= 0);
Relation relation(Geometry a, Geometry b) {
  final common = Geometry(math.max(a.x1, b.x1), math.max(a.y1, b.y1),
      math.min(a.x2, b.x2), math.min(a.y2, b.y2));
  final ox = common.x2 - common.x1, oy = common.y2 - common.y1;
  final kind = ox < 0 || oy < 0 ? 'separated'
      : ox == 0 && oy == 0 ? 'corner' : ox == 0 || oy == 0 ? 'edge' : 'overlap';
  return Relation(common, ox, oy, kind, math.max(0, math.max(-ox, -oy)),
      ox < 0 && oy < 0 ? 'diagonal' : ox < 0 ? 'x' : 'y');
}
bool connected(Geometry a, Geometry b) {
  final kind = relation(a, b).kind;
  return kind == 'overlap' || kind == 'edge';
}
(Rectangle, Rectangle) pair(String a, String b) {
  final first = rectangle(a), second = rectangle(b);
  if (a == b) fail('same rectangle $a');
  return (first, second);
}
String decimal(int numerator, int denominator) {
  final value = 100 * numerator ~/ denominator;
  return '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
}

class Coverage {
  late final List<int> x, y;
  late final int nx, ny;
  late final List<List<int>> counts, prefix;
  Coverage(List<Geometry> rects) {
    x = {for (final rect in rects) ...[rect.x1, rect.x2]}.toList()..sort();
    y = {for (final rect in rects) ...[rect.y1, rect.y2]}.toList()..sort();
    nx = x.length - 1;
    ny = y.length - 1;
    final xi = {for (int i = 0; i < x.length; i++) x[i]: i};
    final yi = {for (int j = 0; j < y.length; j++) y[j]: j};
    final diff = List.generate(y.length, (_) => List.filled(x.length, 0));
    for (final rect in rects) {
      final a = xi[rect.x1]!, b = xi[rect.x2]!, c = yi[rect.y1]!, d = yi[rect.y2]!;
      diff[c][a]++;
      diff[c][b]--;
      diff[d][a]--;
      diff[d][b]++;
    }
    for (int j = 0; j < y.length; j++) {
      for (int i = 0; i < x.length; i++) {
        diff[j][i] += (j > 0 ? diff[j - 1][i] : 0) + (i > 0 ? diff[j][i - 1] : 0)
            - (i > 0 && j > 0 ? diff[j - 1][i - 1] : 0);
      }
    }
    counts = [for (int j = 0; j < ny; j++) diff[j].sublist(0, nx)];
    prefix = List.generate(ny + 1, (_) => List.filled(nx + 1, 0));
    for (int j = 0; j < ny; j++) {
      for (int i = 0; i < nx; i++) {
        prefix[j + 1][i + 1] = prefix[j][i + 1] + prefix[j + 1][i] - prefix[j][i]
            + (counts[j][i] > 0 ? (x[i + 1] - x[i]) * (y[j + 1] - y[j]) : 0);
      }
    }
  }
  bool covered(int i, int j) => i >= 0 && i < nx && j >= 0 && j < ny && counts[j][i] > 0;
  int coveredArea([int threshold = 1]) {
    int total = 0;
    for (int j = 0; j < ny; j++) {
      for (int i = 0; i < nx; i++) {
        if (counts[j][i] >= threshold) total += (x[i + 1] - x[i]) * (y[j + 1] - y[j]);
      }
    }
    return total;
  }
  int perimeter() {
    int total = 0;
    for (int j = 0; j < ny; j++) {
      for (int i = 0; i < nx; i++) {
        if (!covered(i, j)) continue;
        if (!covered(i - 1, j)) total += y[j + 1] - y[j];
        if (!covered(i + 1, j)) total += y[j + 1] - y[j];
        if (!covered(i, j - 1)) total += x[i + 1] - x[i];
        if (!covered(i, j + 1)) total += x[i + 1] - x[i];
      }
    }
    return total;
  }
  int coordinate(List<int> values, int point) {
    int low = 0, high = values.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (values[middle] <= point) { low = middle + 1; } else { high = middle; }
    }
    return low - 1;
  }
  int integral(int px, int py) {
    px = math.max(x.first, math.min(px, x.last));
    py = math.max(y.first, math.min(py, y.last));
    final i = coordinate(x, px), j = coordinate(y, py);
    final dx = px - x[i], dy = py - y[j];
    int value = prefix[j][i];
    if (dx > 0) value += (prefix[j][i + 1] - prefix[j][i]) ~/ (x[i + 1] - x[i]) * dx;
    if (dy > 0) value += (prefix[j + 1][i] - prefix[j][i]) ~/ (y[j + 1] - y[j]) * dy;
    if (dx > 0 && dy > 0 && covered(i, j)) value += dx * dy;
    return value;
  }
  int window(Geometry rect) => integral(rect.x2, rect.y2) - integral(rect.x1, rect.y2)
      - integral(rect.x2, rect.y1) + integral(rect.x1, rect.y1);
  Geometry? empty() {
    Geometry? best;
    int bestArea = 0;
    for (int left = 0; left < nx; left++) {
      final blocked = List.filled(ny, false);
      for (int right = left + 1; right <= nx; right++) {
        for (int j = 0; j < ny; j++) { blocked[j] = blocked[j] || covered(right - 1, j); }
        for (int bottom = 0; bottom < ny;) {
          if (blocked[bottom]) { bottom++; continue; }
          int top = bottom + 1;
          while (top < ny && !blocked[top]) { top++; }
          final candidate = Geometry(x[left], y[bottom], x[right], y[top]);
          final size = area(candidate);
          if (size > bestArea || size == bestArea && (best == null || candidate.x1 < best.x1
              || candidate.x1 == best.x1 && (candidate.y1 < best.y1
              || candidate.y1 == best.y1 && candidate.x2 - candidate.x1 < best.x2 - best.x1))) {
            best = candidate;
            bestArea = size;
          }
          bottom = top;
        }
      }
    }
    return best;
  }
  List<Hole> holes() {
    final visited = List.generate(ny, (_) => List.filled(nx, false));
    final result = <Hole>[];
    for (int j = 0; j < ny; j++) {
      for (int i = 0; i < nx; i++) {
        if (visited[j][i] || covered(i, j)) continue;
        final queue = <Point>[(i, j)], cells = <Geometry>[];
        bool boundary = false;
        int total = 0;
        visited[j][i] = true;
        for (int at = 0; at < queue.length; at++) {
          final (cx, cy) = queue[at];
          cells.add(Geometry(x[cx], y[cy], x[cx + 1], y[cy + 1]));
          total += area(cells.last);
          if (cx == 0 || cy == 0 || cx + 1 == nx || cy + 1 == ny) boundary = true;
          for (final (a, b) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]) {
            if (a >= 0 && a < nx && b >= 0 && b < ny && !visited[b][a] && !covered(a, b)) {
              visited[b][a] = true;
              queue.add((a, b));
            }
          }
        }
        if (!boundary) result.add(Hole(bounds(cells), total, x[i], y[j]));
      }
    }
    return result..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
  }
  List<Geometry> pieces() {
    var active = <String, Geometry>{};
    final result = <Geometry>[];
    for (int j = 0; j < ny; j++) {
      final next = <String, Geometry>{};
      for (int i = 0; i < nx;) {
        if (!covered(i, j)) { i++; continue; }
        final left = i;
        while (i < nx && covered(i, j)) { i++; }
        final key = '${x[left]}:${x[i]}';
        final rect = active[key] ?? Geometry(x[left], y[j], x[i], y[j]);
        rect.y2 = y[j + 1];
        next[key] = rect;
      }
      for (final entry in active.entries) { if (!next.containsKey(entry.key)) result.add(entry.value); }
      active = next;
    }
    result.addAll(active.values);
    return result..sort((a, b) => a.y1 != b.y1 ? a.y1.compareTo(b.y1) : a.x1.compareTo(b.x1));
  }
}

List<List<Rectangle>> nets(List<Rectangle> rects) {
  final seen = <String>{}, result = <List<Rectangle>>[];
  for (final first in rects) {
    if (seen.contains(first.name)) continue;
    final queue = [first];
    seen.add(first.name);
    for (int i = 0; i < queue.length; i++) {
      for (final next in rects) {
        if (!seen.contains(next.name) && connected(queue[i], next)) {
          seen.add(next.name);
          queue.add(next);
        }
      }
    }
    result.add(queue..sort((a, b) => a.name.compareTo(b.name)));
  }
  return result;
}
List<Violation> violations(List<Rectangle> rects, int spacing) {
  final result = <Violation>[];
  for (int i = 0; i < rects.length; i++) {
    for (int j = i + 1; j < rects.length; j++) {
      final rel = relation(rects[i], rects[j]);
      if (rel.kind == 'corner' || rel.kind == 'separated' && rel.gap < spacing) {
        result.add(Violation(rects[i].name, rects[j].name, rel.gap,
            rel.kind == 'corner' ? 'corner' : rel.direction));
      }
    }
  }
  return result..sort((a, b) => a.gap != b.gap ? a.gap.compareTo(b.gap)
      : a.a != b.a ? a.a.compareTo(b.a) : a.b.compareTo(b.b));
}

void execute(String line) {
  final words = line.split(' '), command = words[0], args = words.sublist(1);
  final a = args.isEmpty ? '' : args[0], b = args.length < 2 ? '' : args[1];
  if (['ADD', 'COPY', 'MOVE', 'RESIZE', 'SPLIT', 'LAYER', 'DELETE'].contains(command)) {
    final before = Map<String, Rectangle>.of(rectangles);
    if (command == 'ADD') {
      if (rectangles.containsKey(a)) fail('duplicate rectangle $a');
      final values = args.sublist(2).map(int.parse).toList();
      final rect = Rectangle(a, b, values[0], values[1], values[2], values[3]);
      if (rect.x1 >= rect.x2 || rect.y1 >= rect.y2) fail('invalid rectangle');
      checkBounds(rect);
      rectangles[a] = rect;
      output.add('added $a $b ${notation(rect)}');
    } else {
      final old = rectangle(a);
      if (command == 'COPY' || command == 'MOVE') {
        if (command == 'COPY' && rectangles.containsKey(b)) fail('duplicate rectangle $b');
        final offset = command == 'COPY' ? 2 : 1;
        final dx = int.parse(args[offset]), dy = int.parse(args[offset + 1]);
        final rect = old.copy(name: command == 'COPY' ? b : a,
            x1: old.x1 + dx, y1: old.y1 + dy, x2: old.x2 + dx, y2: old.y2 + dy);
        checkBounds(rect);
        rectangles[rect.name] = rect;
        output.add(command == 'COPY' ? 'copied $a to $b ${notation(rect)}' : 'moved $a to ${notation(rect)}');
      } else if (command == 'RESIZE') {
        final w = int.parse(b), h = int.parse(args[2]);
        if (w <= 0 || h <= 0) fail('invalid size');
        final rect = old.copy(x2: old.x1 + w, y2: old.y1 + h);
        checkBounds(rect);
        rectangles[a] = rect;
        output.add('resized $a to ${notation(rect)}');
      } else if (command == 'SPLIT') {
        final position = int.parse(args[2]), name = args[3];
        if (rectangles.containsKey(name)) fail('duplicate rectangle $name');
        if (b == 'x' ? position <= old.x1 || position >= old.x2 : position <= old.y1 || position >= old.y2) {
          fail('cut outside $a');
        }
        final first = b == 'x' ? old.copy(x2: position) : old.copy(y2: position);
        final second = b == 'x' ? old.copy(name: name, x1: position) : old.copy(name: name, y1: position);
        rectangles[a] = first;
        rectangles[name] = second;
        output.add('split $a at $b=$position: $a ${notation(first)}, $name ${notation(second)}');
      } else if (command == 'LAYER') {
        if (old.layer == b) fail('already on $b');
        rectangles[a] = old.copy(layer: b);
        output.add('layer $a ${old.layer} -> $b');
      } else {
        rectangles.remove(a);
        output.add('deleted $a');
      }
    }
    history.add(UndoEntry(before, line));
    return;
  }
  if (command == 'UNDO') {
    if (history.isEmpty) fail('nothing to undo');
    final previous = history.removeLast();
    rectangles = previous.rectangles;
    output.add('undo: ${previous.line}');
    return;
  }
  if (command == 'LIST') {
    output.add('rectangles: ${rectangles.length}');
    for (final rect in ordered()) { output.add('${rect.name} ${rect.layer} ${notation(rect)} ${rect.x2 - rect.x1}x${rect.y2 - rect.y1}'); }
    return;
  }
  if (command == 'INFO') {
    final rect = rectangle(a), others = ordered().where((other) => other.name != a).toList();
    final same = others.where((other) => other.layer == rect.layer).toList();
    output.add('$a ${rect.layer} ${notation(rect)} ${rect.x2 - rect.x1}x${rect.y2 - rect.y1} area ${area(rect)}');
    final groups = <(String, Iterable<Rectangle>)>[
      ('overlaps', same.where((other) => relation(rect, other).kind == 'overlap')),
      ('touches', same.where((other) => relation(rect, other).kind == 'edge')),
      ('corners', same.where((other) => relation(rect, other).kind == 'corner')),
      ('encloses', others.where((other) => contains(rect, other))),
      ('enclosed by', others.where((other) => contains(other, rect)))
    ];
    for (final (label, list) in groups) {
      final names = list.map((other) => other.name).join(' ');
      output.add('$label: ${names.isEmpty ? 'none' : names}');
    }
    return;
  }
  if (command == 'LAYERS') {
    final layers = ordered().map((rect) => rect.layer).toSet().toList()..sort();
    output.add('layers: ${layers.length}');
    for (final layer in layers) {
      final rects = onLayer(layer);
      output.add('$layer: ${rects.length} rectangles, area ${Coverage(rects).coveredArea()}, nets ${nets(rects).length}');
    }
    return;
  }
  if (command == 'OVERLAPS') {
    final layers = args.isEmpty ? (ordered().map((rect) => rect.layer).toSet().toList()..sort()) : [a];
    final found = <String>[];
    if (args.isNotEmpty) onLayer(a);
    for (final layer in layers) {
      final rects = onLayer(layer);
      for (int i = 0; i < rects.length; i++) {
        for (int j = i + 1; j < rects.length; j++) {
          final rel = relation(rects[i], rects[j]);
          if (rel.kind == 'overlap') found.add('${args.isEmpty ? '$layer ' : ''}${rects[i].name} ${rects[j].name} ${notation(rel.common)} area ${area(rel.common)}');
        }
      }
    }
    output.add('overlaps ${args.isEmpty ? 'all layers' : a}: ${found.length}');
    output.addAll(found);
    return;
  }
  if (['INTERSECT', 'ADJACENT', 'ENCLOSE', 'PATH'].contains(command)) {
    final (first, second) = pair(a, b);
    final rel = relation(first, second), heading = '${command.toLowerCase()} $a $b: ';
    if (command == 'INTERSECT') {
      output.add(heading + (rel.kind == 'overlap' ? '${notation(rel.common)} area ${area(rel.common)}'
          : rel.kind == 'edge' ? 'segment ${notation(rel.common)} length ${rel.ox + rel.oy}'
          : rel.kind == 'corner' ? 'point ${point(rel.common.x1, rel.common.y1)}' : 'none, gap ${rel.gap}'));
    } else if (command == 'ADJACENT') {
      final direction = rel.ox == 0 ? (first.x2 == rel.common.x1 ? 'west' : 'east')
          : first.y2 == rel.common.y1 ? 'south' : 'north';
      output.add(heading + (rel.kind == 'overlap' ? 'overlapping'
          : rel.kind == 'edge' ? '$a is $direction of $b, edge ${notation(rel.common)}, length ${rel.ox + rel.oy}'
          : rel.kind == 'corner' ? 'corner only at ${point(rel.common.x1, rel.common.y1)}' : 'not adjacent'));
    } else if (command == 'ENCLOSE') {
      final values = margins(first, second), yes = values.every((value) => value >= 0);
      output.add('$heading${yes ? 'yes' : 'no'}, margins left ${values[0]} bottom ${values[1]} right ${values[2]} top ${values[3]}${yes ? ', min ${values.reduce(math.min)}' : ''}');
    } else {
      if (first.layer != second.layer) fail('different layers');
      final rects = onLayer(first.layer), queue = [first];
      final parents = <String, String?>{a: null};
      for (int i = 0; i < queue.length; i++) {
        for (final next in rects) {
          if (!parents.containsKey(next.name) && connected(queue[i], next)) {
            parents[next.name] = queue[i].name;
            queue.add(next);
          }
        }
      }
      if (!parents.containsKey(b)) { output.add('${heading}none'); }
      else {
        final path = <String>[];
        for (String? name = b; name != null; name = parents[name]) { path.add(name); }
        output.add('$heading${path.reversed.join(' -> ')} (${path.length - 1} steps)');
      }
    }
    return;
  }
  if (command == 'AT') {
    final x = int.parse(a), y = int.parse(b), list = <String>[];
    for (final rect in ordered()) {
      if (!(rect.x1 <= x && x <= rect.x2 && rect.y1 <= y && y <= rect.y2)) continue;
      final horizontal = x == rect.x1 || x == rect.x2, vertical = y == rect.y1 || y == rect.y2;
      list.add('${rect.name} ${rect.layer} ${horizontal && vertical ? 'corner' : horizontal || vertical ? 'edge' : 'inside'}');
    }
    output.add('at ${point(x, y)}: ${list.isEmpty ? 'none' : list.join(', ')}');
    return;
  }
  if (command == 'NEAREST') {
    final rect = rectangle(a);
    final others = onLayer(rect.layer).where((other) => other.name != a).toList();
    others.sort((x, y) {
      final order = relation(rect, x).gap.compareTo(relation(rect, y).gap);
      return order != 0 ? order : x.name.compareTo(y.name);
    });
    output.add('nearest $a: ${others.isEmpty ? 'none' : '${others.first.name} gap ${relation(rect, others.first).gap}'}');
    return;
  }
  if (command == 'RULE') {
    final kind = a.toLowerCase();
    if (kind == 'enclose' && b == args[2]) fail('same layer $b');
    final rule = Rule(kind, b, kind == 'enclose' ? args[2] : '', int.parse(args[kind == 'enclose' ? 3 : 2]));
    rules['$kind ${rule.layer} ${rule.outer}'] = rule;
    output.add('rule $kind ${rule.layer}${kind == 'enclose' ? ' ${rule.outer}' : ''} ${rule.value}');
    return;
  }
  if (command == 'CHECK') {
    if (rules.isEmpty) fail('no rules');
    int total = 0;
    final all = rules.values.toList()..sort((a, b) => a.kind != b.kind ? a.kind.compareTo(b.kind)
        : a.layer != b.layer ? a.layer.compareTo(b.layer) : a.outer.compareTo(b.outer));
    for (final rule in all) {
      final rects = onLayer(rule.layer, false), found = <String>[];
      if (rule.kind == 'spacing') { found.addAll(violations(rects, rule.value).map((item) => item.line())); }
      else if (rule.kind == 'width') {
        for (final rect in rects) {
          final width = math.min(rect.x2 - rect.x1, rect.y2 - rect.y1);
          if (width < rule.value) found.add('${rect.name} width $width');
        }
      } else {
        final outers = onLayer(rule.outer, false);
        for (final rect in rects) {
          final best = outers.isEmpty ? null : outers.map((outer) => margins(outer, rect).reduce(math.min)).reduce(math.max);
          if (best == null || best < rule.value) found.add('${rect.name} best margin ${best ?? 'none'}');
        }
      }
      output.add('${rule.kind} ${rule.layer}${rule.kind == 'enclose' ? ' ${rule.outer}' : ''} ${rule.value}: ${found.length} violations');
      output.addAll(found);
      total += found.length;
    }
    output.add('check: $total violations in ${rules.length} rules');
    return;
  }
  final layer = command == 'COVER' ? b : a, rects = onLayer(command == 'COVER' ? b : a);
  final grid = Coverage(rects), box = bounds(rects);
  if (command == 'AREA') { output.add('area $layer: ${grid.coveredArea()}'); }
  else if (command == 'COVER') { output.add('cover $layer >= $a: ${grid.coveredArea(int.parse(a))}'); }
  else if (command == 'PERIMETER') { output.add('perimeter $layer: ${grid.perimeter()}'); }
  else if (command == 'NETS') {
    final groups = nets(rects);
    output.add('nets $layer: ${groups.length}');
    for (int i = 0; i < groups.length; i++) {
      final group = groups[i];
      output.add('net ${i + 1}: ${group.map((rect) => rect.name).join(' ')} area ${Coverage(group).coveredArea()}');
    }
  } else if (command == 'DRC') {
    final items = violations(rects, int.parse(b));
    output.add('drc $layer spacing $b: ${items.length} violations');
    output.addAll(items.map((item) => item.line()));
  } else if (command == 'BBOX') {
    output.add('bbox $layer: ${notation(box)} ${box.x2 - box.x1}x${box.y2 - box.y1}, ${rects.length} rectangles, density ${decimal(100 * grid.coveredArea(), area(box))}%');
  } else if (command == 'DENSITY') {
    final w = int.parse(b);
    final columns = (box.x2 - box.x1 + w - 1) ~/ w;
    final rows = (box.y2 - box.y1 + w - 1) ~/ w;
    if (columns > 20 || rows > 20) fail('too many windows');
    final values = List.generate(rows, (j) => List.generate(columns, (i) => grid.window(
        Geometry(box.x1 + i * w, box.y1 + j * w, box.x1 + (i + 1) * w, box.y1 + (j + 1) * w))));
    output.add('density $layer window $w: ${columns}x$rows');
    for (int j = rows - 1; j >= 0; j--) { output.add(values[j].map((value) => 100 * value ~/ (w * w)).join(' ')); }
    Point minimum = (0, 0), maximum = (0, 0);
    for (int j = 0; j < rows; j++) {
      for (int i = 0; i < columns; i++) {
        if (values[j][i] < values[minimum.$2][minimum.$1]) minimum = (i, j);
        if (values[j][i] > values[maximum.$2][maximum.$1]) maximum = (i, j);
      }
    }
    for (final (label, at) in [('min', minimum), ('max', maximum)]) {
      output.add('$label ${decimal(100 * values[at.$2][at.$1], w * w)}% at ${point(box.x1 + at.$1 * w, box.y1 + at.$2 * w)}');
    }
  } else if (command == 'RENDER') {
    final values = args.sublist(1).map(int.parse).toList();
    final window = Geometry(values[0], values[1], values[2], values[3]);
    if (window.x1 >= window.x2 || window.y1 >= window.y2) fail('invalid window');
    if (window.x2 - window.x1 > 60 || window.y2 - window.y1 > 40) fail('window too large');
    output.add('render $layer ${notation(window)}');
    for (int y = window.y2 - 1; y >= window.y1; y--) {
      final row = StringBuffer();
      for (int x = window.x1; x < window.x2; x++) {
        final count = rects.where((rect) => rect.x1 <= x && x < rect.x2 && rect.y1 <= y && y < rect.y2).length;
        row.write(count == 0 ? '.' : count >= 10 ? '*' : '$count');
      }
      output.add(row.toString());
    }
  } else if (command == 'EMPTY') {
    final empty = grid.empty();
    output.add('empty $layer: ${empty == null ? 'none' : '${notation(empty)} area ${area(empty)}'}');
  } else if (command == 'HOLES') {
    final holes = grid.holes();
    output.add('holes $layer: ${holes.length}');
    for (int i = 0; i < holes.length; i++) { output.add('hole ${i + 1}: area ${holes[i].area}, bbox ${notation(holes[i].box)}'); }
  } else if (command == 'MERGE') {
    final pieces = grid.pieces();
    output.add('merge $layer: ${pieces.length} pieces');
    output.addAll(pieces.map(notation));
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  for (int i = 0; i < count; i++) {
    try { execute(stdin.readLineSync()!); }
    on Problem catch (error) { output.add(error.message); }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
