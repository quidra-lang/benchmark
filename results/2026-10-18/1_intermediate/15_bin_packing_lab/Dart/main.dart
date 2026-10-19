import 'dart:io';
import 'dart:math' as math;

const methods = [
  'NEXTFIT', 'FIRSTFIT', 'BESTFIT', 'WORSTFIT', 'ALMOSTWORST',
  'HARMONIC', 'KBOUNDED', 'FFD', 'BFD', 'WFD'
];
const parameterized = {'HARMONIC', 'KBOUNDED'};

class CommandError implements Exception {
  final String reason;
  CommandError(this.reason);
}

int ceilDiv(int n, int d) => (n + d - 1) ~/ d;

class Item {
  final int id, size;
  const Item(this.id, this.size);
  @override
  String toString() => '$id:$size';
}

List<Item> descending(Iterable<Item> items) => items.toList()..sort((a, b) {
  final c = b.size.compareTo(a.size);
  return c != 0 ? c : a.id.compareTo(b.id);
});

class Bin {
  final int? category;
  final List<Item> items = [];
  int load = 0;
  Bin([this.category]);
  void put(Item item) {
    items.add(item);
    load += item.size;
  }
  Bin copy() {
    final result = Bin(category);
    result.items.addAll(items);
    result.load = load;
    return result;
  }
}

class Step {
  final Item item;
  final int bin, inspected;
  final bool opened;
  final int? closed, category;
  Step(this.item, this.bin, this.inspected, this.opened, this.closed, this.category);
}

class Packing {
  final String method;
  final int parameter;
  final List<Bin> bins = [];
  final List<Step> steps = [];
  int inspections = 0, closes = 0;
  Packing(this.method, this.parameter);
  String get name => parameterized.contains(method) ? '$method k=$parameter' : method;
  String header(int capacity, int total) {
    var line = '$name bins=${bins.length} inspections=$inspections '
        'waste=${bins.length * capacity - total}';
    if (method == 'KBOUNDED') line += ' closes=$closes';
    return line;
  }
}

Packing pack(List<Item> items, int capacity, String method, [int k = 0]) {
  final result = Packing(method, k);
  final order = {'FFD', 'BFD', 'WFD'}.contains(method) ? descending(items) : items;
  final active = <int>[];
  final current = <int, int>{};
  for (final item in order) {
    final before = result.inspections;
    int? chosen, closed, category;
    if (method == 'NEXTFIT') {
      if (result.bins.isNotEmpty) {
        result.inspections++;
        final last = result.bins.length - 1;
        if (result.bins[last].load + item.size <= capacity) chosen = last;
      }
    } else if ({'FIRSTFIT', 'FFD', 'KBOUNDED'}.contains(method)) {
      final candidates = method == 'KBOUNDED'
          ? active : List.generate(result.bins.length, (i) => i);
      for (final index in candidates) {
        result.inspections++;
        if (result.bins[index].load + item.size <= capacity) {
          chosen = index;
          break;
        }
      }
    } else if (method == 'HARMONIC') {
      category = math.min(capacity ~/ item.size, k);
      final index = current[category];
      if (index != null) {
        result.inspections++;
        if (result.bins[index].load + item.size <= capacity) chosen = index;
      }
    } else {
      result.inspections += result.bins.length;
      final fitting = <int>[];
      for (var index = 0; index < result.bins.length; index++) {
        if (result.bins[index].load + item.size <= capacity) fitting.add(index);
      }
      fitting.sort((a, b) {
        final compare = result.bins[a].load.compareTo(result.bins[b].load);
        if (method == 'BESTFIT' || method == 'BFD') {
          return compare != 0 ? -compare : a.compareTo(b);
        }
        return compare != 0 ? compare : a.compareTo(b);
      });
      if (fitting.isNotEmpty) {
        chosen = method == 'ALMOSTWORST' && fitting.length >= 2
            ? fitting[1] : fitting[0];
      }
    }
    final opened = chosen == null;
    if (opened) {
      if (method == 'KBOUNDED' && active.length == k) {
        closed = active[0];
        for (final index in active.skip(1)) {
          if (result.bins[index].load > result.bins[closed].load ||
              (result.bins[index].load == result.bins[closed].load && index < closed)) {
            closed = index;
          }
        }
        active.remove(closed);
        result.closes++;
      }
      chosen = result.bins.length;
      result.bins.add(Bin(category));
      if (method == 'KBOUNDED') active.add(chosen);
      if (method == 'HARMONIC') current[category!] = chosen;
    }
    result.bins[chosen!].put(item);
    result.steps.add(Step(item, chosen, result.inspections - before, opened, closed, category));
  }
  return result;
}

class BoundRow {
  final int alpha, j1, j2, j3, bound;
  BoundRow(this.alpha, this.j1, this.j2, this.j3, this.bound);
}

class Bounds {
  final int first, second;
  final List<BoundRow> rows;
  Bounds(this.first, this.second, this.rows);
}

Bounds bounds(List<Item> items, int capacity) {
  final total = items.fold<int>(0, (sum, item) => sum + item.size);
  final thresholds = <int>{0};
  for (final item in items) {
    if (2 * item.size <= capacity) thresholds.add(item.size);
  }
  final rows = <BoundRow>[];
  var best = 0;
  for (final alpha in thresholds.toList()..sort()) {
    var j1 = 0, j2 = 0, j3 = 0, secondSum = 0, thirdSum = 0;
    for (final item in items) {
      final size = item.size;
      if (size > capacity - alpha) {
        j1++;
      } else if (2 * size > capacity) {
        j2++;
        secondSum += size;
      }
      if (2 * size <= capacity && size >= alpha) {
        j3++;
        thirdSum += size;
      }
    }
    final excess = thirdSum - (j2 * capacity - secondSum);
    final bound = j1 + j2 + (excess > 0 ? ceilDiv(excess, capacity) : 0);
    best = math.max(best, bound);
    rows.add(BoundRow(alpha, j1, j2, j3, bound));
  }
  return Bounds(ceilDiv(total, capacity), best, rows);
}

class ExactSearch {
  final List<Item> items;
  final int capacity, limit, lower;
  final List<int> remaining;
  final List<Bin> live = [];
  final void Function(String) emit;
  late List<Bin> best;
  int nodes = 0;
  String? status;
  ExactSearch(List<Item> source, this.capacity, this.limit, this.lower,
      List<Bin> incumbent, this.emit)
      : items = descending(source), remaining = List.filled(source.length + 1, 0) {
    best = incumbent.map((bin) => bin.copy()).toList();
    for (var i = items.length - 1; i >= 0; --i) {
      remaining[i] = remaining[i + 1] + items[i].size;
    }
  }
  void visit(int index) {
    if (status != null) return;
    if (nodes == limit) {
      status = 'limit';
      return;
    }
    nodes++;
    final count = live.length;
    final free = count * capacity - (remaining[0] - remaining[index]);
    final excess = remaining[index] - free;
    final minimum = count + (excess > 0 ? ceilDiv(excess, capacity) : 0);
    if (minimum >= best.length) return;
    if (index == items.length) {
      best = live.map((bin) => bin.copy()).toList();
      emit('IMPROVE bins=$count nodes=$nodes');
      if (count == lower) status = 'bound';
      return;
    }
    final item = items[index];
    final seen = <int>{};
    for (final bin in live) {
      final old = bin.load;
      if (!seen.add(old) || old + item.size > capacity) continue;
      bin.put(item);
      visit(index + 1);
      bin.items.removeLast();
      bin.load = old;
      if (status != null) return;
    }
    if (count + 1 < best.length) {
      live.add(Bin()..put(item));
      visit(index + 1);
      live.removeLast();
    }
  }
}

class Rectangle {
  final int id, width, height;
  const Rectangle(this.id, this.width, this.height);
  int get area => width * height;
  String get letter => String.fromCharCode(64 + id);
}

class Placement {
  final Rectangle rectangle;
  final int x, y, width, height;
  final bool rotated;
  Placement(this.rectangle, this.x, this.y, this.width, this.height,
      [this.rotated = false]);
}

class Shelf {
  final int bottom, height;
  int used = 0;
  final List<(Rectangle, int)> items = [];
  Shelf(this.bottom, this.height);
}

class FreeRect {
  final int x, y, width, height;
  FreeRect(this.x, this.y, this.width, this.height);
  int get area => width * height;
  @override
  String toString() => '$x,$y,${width}x$height';
}

class Sheet {
  final List<FreeRect> free;
  final List<Placement> placements = [];
  int area = 0;
  Sheet(int w, int h) : free = [FreeRect(0, 0, w, h)];
}

class PackingLab {
  int? capacity;
  List<Item>? items;
  final List<String> output = [];
  void emit(String line) => output.add(line);
  int get total => items!.fold<int>(0, (sum, item) => sum + item.size);

  void binLine(int number, Bin bin, int cap, {bool classes = false, bool over = false}) {
    var line = 'BIN $number load=${bin.load}/$cap items=${bin.items.join(' ')}';
    if (classes) line += ' class=${bin.category}';
    if (over) line += ' OVER';
    emit(line);
  }
  void binLines(List<Bin> bins, {bool classes = false}) {
    for (var i = 0; i < bins.length; i++) {
      binLine(i + 1, bins[i], capacity!, classes: classes);
    }
  }
  Packing method(String name, List<String> args) {
    final k = parameterized.contains(name) ? int.parse(args[0]) : 0;
    if (parameterized.contains(name) && k == 0) throw CommandError('BAD PARAMETER');
    return pack(items!, capacity!, name, k);
  }

  void cmdItems(List<String> args) {
    final cap = int.parse(args[0]);
    if (cap == 0) throw CommandError('BAD CAPACITY');
    final result = <Item>[];
    for (var i = 1; i < args.length; i++) {
      final size = int.parse(args[i]);
      if (size == 0 || size > cap) throw CommandError('BAD ITEM $i');
      result.add(Item(i, size));
    }
    capacity = cap;
    items = result;
    emit('ITEMS count=${result.length} capacity=$cap total=$total');
  }

  void cmdRandom(List<String> args) {
    final count = int.parse(args[0]), cap = int.parse(args[1]);
    var value = int.parse(args[2]);
    if (count == 0 || count > 40) throw CommandError('BAD COUNT');
    if (cap == 0) throw CommandError('BAD CAPACITY');
    if (value == 0 || value >= 2147483647) throw CommandError('BAD SEED');
    final result = <Item>[];
    for (var i = 1; i <= count; i++) {
      value = 48271 * value % 2147483647;
      result.add(Item(i, value % cap + 1));
    }
    capacity = cap;
    items = result;
    emit('RANDOM count=$count capacity=$cap total=$total');
    emit('SIZES ${result.map((item) => item.size).join(' ')}');
  }

  void cmdMethod(String name, List<String> args) {
    final result = method(name, args);
    emit(result.header(capacity!, total));
    binLines(result.bins, classes: name == 'HARMONIC');
  }

  void cmdTrace(List<String> args) {
    final name = args.first;
    final result = method(name, args.sublist(1));
    emit('TRACE ${result.header(capacity!, total)}');
    for (var i = 0; i < result.steps.length; i++) {
      final step = result.steps[i];
      var line = 'STEP ${i + 1} item=${step.item} '
          'bin=${step.bin + 1} inspected=${step.inspected}';
      if (step.opened) line += ' new';
      if (step.closed != null) line += ' closed=${step.closed! + 1}';
      if (step.category != null) line += ' class=${step.category}';
      emit(line);
    }
  }

  void cmdReduce(List<String> args) {
    final name = args.first;
    final params = args.sublist(1);
    final bins = method(name, params).bins;
    final before = bins.length;
    final events = <String>[];
    while (true) {
      var eliminated = false;
      final order = List.generate(bins.length, (i) => i)..sort((a, b) {
        final byLoad = bins[a].load.compareTo(bins[b].load);
        return byLoad != 0 ? byLoad : a.compareTo(b);
      });
      for (final source in order) {
        final loads = bins.map((bin) => bin.load).toList();
        final moves = <(Item, int)>[];
        var valid = true;
        for (final item in descending(bins[source].items)) {
          int? chosen;
          for (var i = 0; i < bins.length; i++) {
            if (i == source || loads[i] + item.size > capacity!) continue;
            if (chosen == null || loads[i] > loads[chosen] ||
                (loads[i] == loads[chosen] && i < chosen)) {
              chosen = i;
            }
          }
          if (chosen == null) {
            valid = false;
            break;
          }
          loads[chosen] += item.size;
          moves.add((item, chosen));
        }
        if (!valid) continue;
        final text = moves.map((m) => '${m.$1}->${m.$2 + 1}').join(' ');
        events.add('ELIMINATE bin=${source + 1} load=${bins[source].load} moves=$text');
        for (final (item, destination) in moves) {
          bins[destination].put(item);
        }
        bins.removeAt(source);
        eliminated = true;
        break;
      }
      if (!eliminated) break;
    }
    final suffix = parameterized.contains(name) ? ' k=${int.parse(params[0])}' : '';
    emit('REDUCE $name$suffix before=$before after=${bins.length} '
        'eliminated=${before - bins.length}');
    for (final event in events) emit(event);
    binLines(bins, classes: name == 'HARMONIC');
  }

  void cmdBounds() {
    final result = bounds(items!, capacity!);
    emit('BOUNDS total=$total L1=${result.first} L2=${result.second}');
    for (final row in result.rows) {
      emit('ALPHA ${row.alpha} j1=${row.j1} j2=${row.j2} '
          'j3=${row.j3} bound=${row.bound}');
    }
  }

  void cmdCompare(List<String> args) {
    final k = int.parse(args[0]);
    if (k == 0) throw CommandError('BAD PARAMETER');
    final lower = bounds(items!, capacity!);
    final results = methods.map((name) => pack(items!, capacity!, name, k)).toList()
      ..sort((a, b) {
        final c = a.bins.length.compareTo(b.bins.length);
        return c != 0 ? c : a.method.compareTo(b.method);
      });
    emit('COMPARE k=$k L1=${lower.first} L2=${lower.second}');
    for (final result in results) {
      final count = result.bins.length;
      emit('${result.method} bins=$count gap=${count - lower.second} '
          'waste=${count * capacity! - total} inspections=${result.inspections}');
    }
  }

  void cmdExact(List<String> args) {
    final limit = int.parse(args[0]);
    if (limit == 0) throw CommandError('BAD PARAMETER');
    if (items!.length >= 21) throw CommandError('TOO MANY ITEMS');
    final incumbent = pack(items!, capacity!, 'FFD').bins;
    final lower = bounds(items!, capacity!).second;
    emit('EXACT ffd=${incumbent.length} L2=$lower');
    final search = ExactSearch(items!, capacity!, limit, lower, incumbent, emit);
    if (incumbent.length == lower) {
      search.status = 'bound';
    } else {
      search.visit(0);
    }
    emit('RESULT bins=${search.best.length} nodes=${search.nodes} '
        'status=${search.status ?? 'complete'}');
    binLines(search.best);
  }

  void cmdCheck(List<String> args) {
    final labels = args.map(int.parse).toList();
    if (labels.length != items!.length || labels.contains(0)) {
      throw CommandError('BAD ASSIGNMENT');
    }
    final bins = <int, Bin>{};
    for (var i = 0; i < items!.length; i++) {
      bins.putIfAbsent(labels[i], () => Bin()).put(items![i]);
    }
    final overfull = bins.values.where((bin) => bin.load > capacity!).length;
    final lower = bounds(items!, capacity!).second;
    emit('CHECK bins=${bins.length} over=$overfull L2=$lower '
        'status=${overfull == 0 ? 'valid' : 'invalid'}');
    final sorted = bins.keys.toList()..sort();
    for (final label in sorted) {
      final bin = bins[label]!;
      binLine(label, bin, capacity!, over: bin.load > capacity!);
    }
  }

  void coverLines(String name, List<Bin> bins) {
    final covered = bins.where((bin) => bin.load >= capacity!).toList();
    Bin? rest;
    for (final bin in bins) {
      if (bin.load < capacity!) { rest = bin; break; }
    }
    emit('$name covered=${covered.length} rest=${rest?.load ?? 0}');
    binLines(covered);
    if (rest != null) emit('REST items=${rest.items.join(' ')}');
  }

  void cmdCover() {
    emit('COVER total=$total upper=${total ~/ capacity!}');
    final sequential = <Bin>[];
    for (final item in items!) {
      if (sequential.isEmpty || sequential.last.load >= capacity!) {
        sequential.add(Bin());
      }
      sequential.last.put(item);
    }
    coverLines('DNF', sequential);
    final available = descending(items!);
    final paired = <Bin>[];
    while (available.isNotEmpty) {
      final bin = Bin()..put(available.removeAt(0));
      while (bin.load < capacity! && available.isNotEmpty) {
        bin.put(available.removeLast());
      }
      paired.add(bin);
    }
    coverLines('BIGSMALL', paired);
  }

  void machineLines(List<Bin> machines) {
    for (var i = 0; i < machines.length; i++) {
      final bin = machines[i];
      emit('MACHINE ${i + 1} load=${bin.load} '
          'items=${bin.items.isEmpty ? '-' : bin.items.join(' ')}');
    }
  }

  void cmdMultifit(List<String> args) {
    final count = int.parse(args[0]);
    if (count == 0) throw CommandError('BAD PARAMETER');
    final largest = items!.fold<int>(0, (m, item) => math.max(m, item.size));
    var lo = math.max(ceilDiv(total, count), largest);
    var hi = math.max(ceilDiv(2 * total, count), largest);
    emit('MULTIFIT m=$count lower=$lo upper=$hi');
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      final used = pack(items!, mid, 'FFD').bins.length;
      final fits = used <= count;
      emit('TRY cap=$mid bins=$used ${fits ? 'ok' : 'fail'}');
      if (fits) { hi = mid; } else { lo = mid + 1; }
    }
    final machines = pack(items!, hi, 'FFD').bins;
    while (machines.length < count) machines.add(Bin());
    final makespan = machines.fold<int>(0, (m, bin) => math.max(m, bin.load));
    emit('RESULT cap=$hi makespan=$makespan');
    machineLines(machines);
    final lpt = List.generate(count, (_) => Bin());
    for (final item in descending(items!)) {
      var chosen = 0;
      for (var i = 1; i < count; i++) {
        if (lpt[i].load < lpt[chosen].load) chosen = i;
      }
      lpt[chosen].put(item);
    }
    emit('LPT makespan=${lpt.fold<int>(0, (m, bin) => math.max(m, bin.load))}');
    machineLines(lpt);
  }

  List<(List<int>, int)> maximalPatterns(int cap, List<(int, int)> pieces) {
    final patterns = <(List<int>, int)>[];
    void enumerate(int index, int remaining, List<int> prefix) {
      final size = pieces[index].$1;
      final maxCount = remaining ~/ size;
      if (index == pieces.length - 1) {
        patterns.add(([...prefix, maxCount], remaining - maxCount * size));
        return;
      }
      for (var count = maxCount; count >= 0; count--) {
        enumerate(index + 1, remaining - count * size, [...prefix, count]);
      }
    }
    enumerate(0, cap, []);
    return patterns;
  }

  void cmdCutstock(List<String> args) {
    final cap = int.parse(args[0]);
    if (cap == 0) throw CommandError('BAD CAPACITY');
    final pieces = <(int, int)>[];
    final seen = <int>{};
    for (var i = 1; i < args.length; i++) {
      final values = args[i].split(':').map(int.parse).toList();
      final size = values[0], demand = values[1];
      if (size == 0 || size > cap || demand == 0) {
        throw CommandError('BAD PIECE $i');
      }
      if (!seen.add(size)) throw CommandError('DUPLICATE PIECE $i');
      pieces.add((size, demand));
    }
    pieces.sort((a, b) => b.$1.compareTo(a.$1));
    final patterns = maximalPatterns(cap, pieces);
    final remaining = pieces.map((p) => p.$2).toList();
    final uses = List.filled(patterns.length, 0);
    while (remaining.any((n) => n > 0)) {
      var bestIndex = 0, bestUseful = -1;
      for (var i = 0; i < patterns.length; i++) {
        var useful = 0;
        for (var j = 0; j < pieces.length; j++) {
          useful += math.min(patterns[i].$1[j], remaining[j]);
        }
        if (useful > bestUseful) {
          bestUseful = useful;
          bestIndex = i;
        }
      }
      uses[bestIndex]++;
      for (var j = 0; j < remaining.length; j++) {
        remaining[j] = math.max(0, remaining[j] - patterns[bestIndex].$1[j]);
      }
    }
    final cut = List.filled(pieces.length, 0);
    for (var i = 0; i < patterns.length; i++) {
      for (var j = 0; j < pieces.length; j++) {
        cut[j] += uses[i] * patterns[i].$1[j];
      }
    }
    var quantity = 0, bars = 0, trim = 0, surplus = 0;
    for (final piece in pieces) quantity += piece.$1 * piece.$2;
    for (var i = 0; i < patterns.length; i++) {
      bars += uses[i];
      trim += uses[i] * patterns[i].$2;
    }
    for (var i = 0; i < pieces.length; i++) surplus += cut[i] - pieces[i].$2;
    emit('CUTSTOCK L=$cap pieces=${pieces.length} patterns=${patterns.length}');
    for (var i = 0; i < patterns.length; i++) {
      final breakdown = <String>[];
      for (var j = 0; j < pieces.length; j++) {
        final count = patterns[i].$1[j];
        if (count != 0) breakdown.add('${count}x${pieces[j].$1}');
      }
      emit('PATTERN ${i + 1} ${breakdown.join('+')} rest=${patterns[i].$2}');
    }
    for (var i = 0; i < uses.length; i++) {
      if (uses[i] > 0) emit('USE ${i + 1} bars=${uses[i]}');
    }
    for (var i = 0; i < pieces.length; i++) {
      emit('PIECE ${pieces[i].$1} demand=${pieces[i].$2} cut=${cut[i]}');
    }
    emit('TOTAL bars=$bars trim=$trim surplus=$surplus waste=${bars * cap - quantity}');
    final comparison = <Item>[];
    for (final piece in pieces) {
      for (var j = 0; j < piece.$2; j++) {
        comparison.add(Item(comparison.length + 1, piece.$1));
      }
    }
    final number = pack(comparison, cap, 'FIRSTFIT').bins.length;
    emit('FFD bars=$number waste=${number * cap - quantity}');
    emit('LOWER bars=${ceilDiv(quantity, cap)}');
  }

  List<Rectangle> rectangles(List<String> specs) {
    final result = <Rectangle>[];
    for (var i = 0; i < specs.length; i++) {
      final dim = specs[i].split('x').map(int.parse).toList();
      result.add(Rectangle(i + 1, dim[0], dim[1]));
    }
    return result;
  }

  void drawing(int width, int height, List<Placement> placements) {
    final cells = List.generate(height, (_) => List.filled(width, '.'));
    for (final place in placements) {
      for (var y = place.y; y < place.y + place.height; y++) {
        for (var x = place.x; x < place.x + place.width; x++) {
          cells[y][x] = place.rectangle.letter;
        }
      }
    }
    for (var y = height - 1; y >= 0; y--) emit(cells[y].join());
  }

  void shelfMethod(String name, int width, List<Rectangle> rects, int area) {
    final shelves = <Shelf>[];
    final placements = <Placement>[];
    for (final rect in rects) {
      int? chosen;
      if (name == 'NFDH') {
        if (shelves.isNotEmpty && shelves.last.used + rect.width <= width) {
          chosen = shelves.length - 1;
        }
      } else {
        for (var i = 0; i < shelves.length; i++) {
          if (shelves[i].used + rect.width > width) continue;
          if (chosen == null || (name == 'BFDH' &&
              shelves[i].used > shelves[chosen].used)) chosen = i;
        }
      }
      if (chosen == null) {
        final bottom = shelves.isEmpty ? 0 : shelves.last.bottom + shelves.last.height;
        chosen = shelves.length;
        shelves.add(Shelf(bottom, rect.height));
      }
      final shelf = shelves[chosen];
      shelf.items.add((rect, shelf.used));
      placements.add(Placement(rect, shelf.used, shelf.bottom, rect.width, rect.height));
      shelf.used += rect.width;
    }
    final height = shelves.last.bottom + shelves.last.height;
    emit('$name height=$height shelves=${shelves.length} '
        'util=${area * 100 ~/ (width * height)}');
    for (var i = 0; i < shelves.length; i++) {
      final shelf = shelves[i];
      emit('LEVEL ${i + 1} y=${shelf.bottom} h=${shelf.height} '
          'used=${shelf.used} items=${shelf.items.map((p) => '${p.$1.letter}@${p.$2}').join(' ')}');
    }
    drawing(width, height, placements);
  }

  void cmdShelf(List<String> args) {
    final width = int.parse(args[0]);
    if (width == 0) throw CommandError('BAD CAPACITY');
    final rects = rectangles(args.sublist(1));
    for (final rect in rects) {
      if (rect.width == 0 || rect.height == 0 || rect.width > width) {
        throw CommandError('BAD RECT ${rect.id}');
      }
    }
    rects.sort((a, b) {
      final byHeight = b.height.compareTo(a.height);
      if (byHeight != 0) return byHeight;
      final byWidth = b.width.compareTo(a.width);
      return byWidth != 0 ? byWidth : a.id.compareTo(b.id);
    });
    final area = rects.fold<int>(0, (sum, rect) => sum + rect.area);
    emit('SHELF W=$width rects=${rects.length} area=$area');
    for (final name in ['NFDH', 'FFDH', 'BFDH']) {
      shelfMethod(name, width, rects, area);
    }
    final heights = List.filled(width, 0);
    final placements = <Placement>[];
    for (final rect in rects) {
      var chosenX = 0, chosenY = 1 << 60;
      for (var x = 0; x + rect.width <= width; x++) {
        var y = 0;
        for (var column = x; column < x + rect.width; column++) {
          y = math.max(y, heights[column]);
        }
        if (y < chosenY) { chosenX = x; chosenY = y; }
      }
      for (var column = chosenX; column < chosenX + rect.width; column++) {
        heights[column] = chosenY + rect.height;
      }
      placements.add(Placement(rect, chosenX, chosenY, rect.width, rect.height));
    }
    final height = heights.reduce(math.max);
    emit('SKYLINE height=$height util=${area * 100 ~/ (width * height)}');
    for (final place in placements) {
      emit('PLACE ${place.rectangle.letter} x=${place.x} y=${place.y} '
          'w=${place.width} h=${place.height}');
    }
    drawing(width, height, placements);
  }

  (int, int)? freeRectangle(List<Sheet> sheets, int w, int h, bool rotate, String rule) {
    (int, int)? chosen;
    int? bestArea;
    for (var s = 0; s < sheets.length; s++) {
      for (var f = 0; f < sheets[s].free.length; f++) {
        final free = sheets[s].free[f];
        if (!(w <= free.width && h <= free.height) &&
            !(rotate && h <= free.width && w <= free.height)) continue;
        if (rule == 'FIRST') return (s, f);
        if (bestArea == null || free.area < bestArea) {
          bestArea = free.area;
          chosen = (s, f);
        }
      }
    }
    return chosen;
  }

  void cmdGuillotine(List<String> args) {
    final width = int.parse(args[0]), height = int.parse(args[1]);
    final mode = args[2], rule = args[3];
    if (width == 0 || height == 0) throw CommandError('BAD CAPACITY');
    final rects = rectangles(args.sublist(4));
    final rotate = mode == 'ROTATE';
    for (final rect in rects) {
      final fits = rect.width <= width && rect.height <= height;
      final rotated = rotate && rect.height <= width && rect.width <= height;
      if (rect.width == 0 || rect.height == 0 || (!fits && !rotated)) {
        throw CommandError('BAD RECT ${rect.id}');
      }
    }
    rects.sort((a, b) {
      final byArea = b.area.compareTo(a.area);
      return byArea != 0 ? byArea : a.id.compareTo(b.id);
    });
    final sheets = <Sheet>[];
    var rotatedCount = 0;
    for (final rect in rects) {
      var chosen = freeRectangle(sheets, rect.width, rect.height, rotate, rule);
      if (chosen == null) {
        sheets.add(Sheet(width, height));
        chosen = (sheets.length - 1, 0);
      }
      final sheet = sheets[chosen.$1];
      final free = sheet.free.removeAt(chosen.$2);
      final rotated = rect.width > free.width || rect.height > free.height;
      final pw = rotated ? rect.height : rect.width;
      final ph = rotated ? rect.width : rect.height;
      if (rotated) rotatedCount++;
      sheet.placements.add(Placement(rect, free.x, free.y, pw, ph, rotated));
      sheet.area += rect.area;
      final rw = free.width - pw;
      final rh = free.height - ph;
      final top = rw <= rh
          ? FreeRect(free.x, free.y + ph, free.width, rh)
          : FreeRect(free.x, free.y + ph, pw, rh);
      final right = rw <= rh
          ? FreeRect(free.x + pw, free.y, rw, ph)
          : FreeRect(free.x + pw, free.y, rw, free.height);
      if (top.width > 0 && top.height > 0) sheet.free.add(top);
      if (right.width > 0 && right.height > 0) sheet.free.add(right);
    }
    final area = sheets.fold<int>(0, (sum, sheet) => sum + sheet.area);
    emit('GUILLOTINE W=$width H=$height mode=$mode rule=$rule '
        'rects=${rects.length} sheets=${sheets.length} '
        'rotated=$rotatedCount util=${area * 100 ~/ (sheets.length * width * height)}');
    for (var i = 0; i < sheets.length; i++) {
      final sheet = sheets[i];
      emit('SHEET ${i + 1} placed=${sheet.placements.length} area=${sheet.area}');
      for (final place in sheet.placements) {
        var line = 'PLACE ${place.rectangle.letter} x=${place.x} y=${place.y} '
            'w=${place.width} h=${place.height}';
        if (place.rotated) line += ' rotated';
        emit(line);
      }
      emit('FREE ${sheet.free.isEmpty ? 'none' : sheet.free.join(' ')}');
      drawing(width, height, sheet.placements);
    }
  }

  void execute(String line) {
    final tokens = line.split(' ');
    final command = tokens.first;
    final args = tokens.sublist(1);
    try {
      if (!{'ITEMS', 'RANDOM', 'CUTSTOCK', 'SHELF', 'GUILLOTINE'}.contains(command)
          && items == null) throw CommandError('NO ITEMS');
      if (methods.contains(command)) {
        cmdMethod(command, args);
      } else if (command == 'ITEMS') {
        cmdItems(args);
      } else if (command == 'RANDOM') {
        cmdRandom(args);
      } else if (command == 'TRACE') {
        cmdTrace(args);
      } else if (command == 'REDUCE') {
        cmdReduce(args);
      } else if (command == 'BOUNDS') {
        cmdBounds();
      } else if (command == 'COMPARE') {
        cmdCompare(args);
      } else if (command == 'EXACT') {
        cmdExact(args);
      } else if (command == 'CHECK') {
        cmdCheck(args);
      } else if (command == 'COVER') {
        cmdCover();
      } else if (command == 'MULTIFIT') {
        cmdMultifit(args);
      } else if (command == 'CUTSTOCK') {
        cmdCutstock(args);
      } else if (command == 'SHELF') {
        cmdShelf(args);
      } else if (command == 'GUILLOTINE') {
        cmdGuillotine(args);
      }
    } on CommandError catch (error) {
      emit('ERROR ${error.reason}');
    }
  }
  String result() => output.isEmpty ? '' : '${output.join('\n')}\n';
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final lab = PackingLab();
  for (var i = 0; i < count; i++) {
    lab.execute(stdin.readLineSync()!);
  }
  stdout.write(lab.result());
}
