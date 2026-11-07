import 'dart:io';
import 'dart:math' as math;

enum Mode {
  chain('CHAIN'), linear('LINEAR'), quadratic('QUADRATIC'),
  doubleHash('DOUBLE'), robinHood('ROBINHOOD'), cuckoo('CUCKOO');

  const Mode(this.label);
  final String label;
  int get parts => this == cuckoo ? 2 : 1;
  bool get usesTombstones => this == linear || this == quadratic || this == doubleHash;
}

final class CommandError implements Exception {
  const CommandError(this.message);
  final String message;
  @override
  String toString() => 'ERROR $message';
}

final class Item {
  const Item(this.key, this.value);
  final String key;
  final int value;
  @override
  String toString() => '$key=$value';
}

final class Slot {
  const Slot([this.item, this.deleted = false]);
  final Item? item;
  final bool deleted;
  bool get empty => item == null && !deleted;
  String get content => item?.key ?? (deleted ? 'D' : '-');
}

final class Counters {
  int probes = 0, rehashes = 0, inserts = 0, updates = 0;
  int hits = 0, misses = 0, deletes = 0, absent = 0;
}

final class SearchResult {
  Item? item;
  int position = -1, chainIndex = -1, probes = 0;
  int? available;
  final path = <String>[];
}

final class Placement {
  bool success = false, reused = false;
  int position = -1, shifted = 0, kicks = 0;
  Item? homeless;
  final moves = <String>[];
}

final class Mutation {
  const Mutation(this.changed, this.lines, this.rehashes);
  final bool changed;
  final List<String> lines, rehashes;
}

typedef Removal = ({int shifted, List<String> moves});
typedef Cost = ({String key, int probes, int position});
typedef Metrics = ({int longest, String average});

Mode parseMode(String text) {
  for (final mode in Mode.values) {
    if (mode.label == text) return mode;
  }
  throw CommandError('BAD MODE $text');
}

int hash(String key, int base, int modulus) {
  var value = 0;
  for (final character in key.codeUnits) {
    value = (value * base + character) % modulus;
  }
  return value;
}

int prime(int value) {
  for (var candidate = math.max(value, 2); ; candidate++) {
    var valid = true;
    for (var divisor = 2; divisor * divisor <= candidate; divisor++) {
      if (candidate % divisor == 0) { valid = false; break; }
    }
    if (valid) return candidate;
  }
}

String ratio(int numerator, int denominator) {
  final value = denominator == 0 ? 0 : 100 * numerator ~/ denominator;
  return '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
}

String gauge(int value) => value >= 10 ? '+' : value.toString();

Iterable<String> generate(int count, int length, int seed) sync* {
  for (var i = 0; i < count; i++) {
    final key = <int>[];
    for (var j = 0; j < length; j++) {
      seed = 48271 * seed % 2147483647;
      key.add(97 + seed % 26);
    }
    yield String.fromCharCodes(key);
  }
}

List<String> histogram(Iterable<int> values) {
  final counts = <int, int>{};
  for (final value in values) { counts[value] = (counts[value] ?? 0) + 1; }
  final keys = counts.keys.toList()..sort();
  return [for (final key in keys)
    '$key ${counts[key]} ${''.padRight(math.min(counts[key]!, 50), '#')}${counts[key]! > 50 ? '+' : ''}'];
}

void checkCapacity(int capacity) {
  if (capacity < 2 || capacity > 10000) throw const CommandError('BAD CAPACITY');
}

void checkGeneration(int count, int length, int seed) {
  if (count < 1 || count > 500 || length < 1 || length > 10 || seed < 1 || seed > 2147483646) {
    throw const CommandError('BAD ARGUMENT');
  }
}

final class HashTable {
  HashTable(this.mode, this.capacity) {
    buckets = mode == Mode.chain ? List.generate(capacity, (_) => <Item>[]) : [];
    slots = mode == Mode.chain ? [] : List.filled(slotCount, const Slot());
  }

  Mode mode;
  int capacity;
  int size = 0, tombstones = 0;
  final counters = Counters();
  late List<List<Item>> buckets;
  late List<Slot> slots;
  int get slotCount => capacity * mode.parts;

  String position(int index) => mode == Mode.cuckoo ? 'T${index ~/ capacity + 1}.${index % capacity}' : '$index';
  int distance(String key, int index) => (index - hash(key, 31, capacity)) % capacity;

  List<Item> items() => mode == Mode.chain
      ? buckets.expand((bucket) => bucket).toList()
      : [for (final slot in slots) if (slot.item case final item?) item];

  SearchResult search(String key, {bool trace = false}) {
    final result = SearchResult();
    final first = hash(key, 31, capacity);
    void examine(int index, String content) {
      result.probes++;
      if (trace) result.path.add('${position(index)}:$content');
    }
    void found(Item item, int index, [int chainIndex = -1]) {
      result.item = item;
      result.position = index;
      result.chainIndex = chainIndex;
    }
    if (mode == Mode.chain) {
      for (var i = 0; i < buckets[first].length; i++) {
        final item = buckets[first][i];
        examine(first, item.key);
        if (item.key == key) { found(item, first, i); break; }
      }
      return result;
    }
    if (mode == Mode.cuckoo) {
      for (final index in [first, capacity + hash(key, 37, capacity)]) {
        final slot = slots[index];
        examine(index, slot.content);
        final item = slot.item;
        if (item != null && item.key == key) { found(item, index); break; }
      }
      return result;
    }
    final step = mode == Mode.doubleHash ? 1 + hash(key, 37, capacity - 1) : 1;
    for (var i = 0; i < capacity; i++) {
      final offset = mode == Mode.quadratic ? i * i : i * step;
      final index = (first + offset) % capacity;
      final slot = slots[index];
      examine(index, slot.content);
      if (slot.empty) { result.available ??= index; break; }
      if (slot.deleted) { result.available ??= index; continue; }
      final item = slot.item!;
      if (item.key == key) { found(item, index); break; }
      if (mode == Mode.robinHood && distance(item.key, index) < i) break;
    }
    return result;
  }

  Placement place(Item item, {SearchResult? initial, bool trace = false}) {
    final result = Placement();
    if (mode == Mode.chain) {
      result.position = hash(item.key, 31, capacity);
      buckets[result.position].add(item);
      result.success = true;
      return result;
    }
    if (mode.usesTombstones) {
      final found = initial ?? search(item.key);
      final index = found.available;
      if (index == null) { result.homeless = item; return result; }
      result.position = index;
      result.reused = slots[index].deleted;
      slots[index] = Slot(item);
      if (result.reused) tombstones--;
      result.success = true;
      return result;
    }
    var current = item;
    if (mode == Mode.robinHood) {
      var index = hash(item.key, 31, capacity), dist = 0;
      int? from;
      while (true) {
        final resident = slots[index].item;
        if (resident == null) {
          slots[index] = Slot(current);
          if (trace && from != null) result.moves.add('SHIFT ${current.key} $from -> $index');
          if (result.position < 0) result.position = index;
          result.success = true;
          return result;
        }
        final residentDistance = distance(resident.key, index);
        if (residentDistance < dist) {
          slots[index] = Slot(current);
          if (trace && from != null) result.moves.add('SHIFT ${current.key} $from -> $index');
          if (result.position < 0) result.position = index;
          current = resident;
          from = index;
          dist = residentDistance;
          result.shifted++;
        }
        index = (index + 1) % capacity;
        dist++;
      }
    }
    var part = 0;
    while (true) {
      final index = part * capacity + hash(current.key, part == 0 ? 31 : 37, capacity);
      final resident = slots[index].item;
      if (resident == null) {
        slots[index] = Slot(current);
        result.success = true;
        result.position = search(item.key).position;
        return result;
      }
      if (result.kicks == capacity) { result.homeless = current; return result; }
      slots[index] = Slot(current);
      result.kicks++;
      if (trace) result.moves.add('KICK ${resident.key} ${position(index)}');
      current = resident;
      part = 1 - part;
    }
  }

  Removal remove(SearchResult found, {bool trace = false}) {
    var shifted = 0;
    final moves = <String>[];
    if (mode == Mode.chain) { buckets[found.position].removeAt(found.chainIndex); }
    else if (mode.usesTombstones) { slots[found.position] = const Slot(null, true); tombstones++; }
    else {
      slots[found.position] = const Slot();
      if (mode == Mode.robinHood) {
        var next = (found.position + 1) % capacity;
        while (true) {
          final item = slots[next].item;
          if (item == null || distance(item.key, next) == 0) break;
          final destination = (next - 1) % capacity;
          slots[destination] = Slot(item);
          slots[next] = const Slot();
          if (trace) moves.add('SHIFT ${item.key} $next -> $destination');
          shifted++;
          next = (next + 1) % capacity;
        }
      }
    }
    size--;
    return (shifted: shifted, moves: moves);
  }

  static HashTable? rebuild(List<Item> items, Mode mode, int capacity) {
    final table = HashTable(mode, capacity);
    for (final item in items) {
      if (!table.place(item).success) return null;
      table.size++;
    }
    return table;
  }

  void adopt(HashTable replacement) {
    mode = replacement.mode;
    capacity = replacement.capacity;
    size = replacement.size;
    tombstones = replacement.tombstones;
    buckets = replacement.buckets;
    slots = replacement.slots;
  }

  String automatic(String reason, int target, [Item? pending]) {
    final listed = items();
    if (pending != null) listed.add(pending);
    final old = capacity;
    while (true) {
      final replacement = rebuild(listed, mode, target);
      if (replacement != null) {
        adopt(replacement);
        counters.rehashes++;
        return 'REHASH $reason $old -> $capacity';
      }
      target = prime(2 * target);
    }
  }

  List<String> loadCheck(int maxLoad) {
    final threshold = maxLoad * slotCount;
    if (100 * (size + tombstones) <= threshold) return [];
    final grow = 200 * size > threshold;
    return [automatic(grow ? 'load' : 'tomb', grow ? prime(2 * capacity) : capacity)];
  }

  List<String> shrinkCheck(int minLoad, int maxLoad) {
    final target = prime(capacity ~/ 2);
    if (100 * size >= minLoad * slotCount || target >= capacity || 100 * size > maxLoad * target * mode.parts) return [];
    final replacement = rebuild(items(), mode, target);
    if (replacement == null) return [];
    final old = capacity;
    adopt(replacement);
    counters.rehashes++;
    return ['REHASH shrink $old -> $target'];
  }

  Mutation put(String key, int value, int maxLoad, {String command = 'PUT', bool trace = false}) {
    final found = search(key, trace: trace);
    final path = trace ? ['PATH ${found.path.isEmpty ? 'none' : found.path.join(' ')}'] : <String>[];
    counters.probes += found.probes;
    final old = found.item;
    if (old != null) {
      final item = Item(key, command == 'ADD' ? old.value + value : value);
      if (mode == Mode.chain) { buckets[found.position][found.chainIndex] = item; }
      else { slots[found.position] = Slot(item); }
      counters.updates++;
      final row = '$command $item UPDATED old=${old.value} at=${position(found.position)} probes=${found.probes}';
      return Mutation(false, [row, ...path], []);
    }
    final item = Item(key, value);
    final placed = place(item, initial: found, trace: trace);
    size++;
    counters.inserts++;
    var row = '$command $item NEW';
    if (placed.success) {
      row += ' at=${position(placed.position)} probes=${found.probes}';
      if (placed.reused) row += ' reused';
      if (mode == Mode.robinHood) row += ' shifted=${placed.shifted}';
      if (mode == Mode.cuckoo) row += ' kicks=${placed.kicks}';
    } else {
      row += ' probes=${found.probes}' + (mode == Mode.cuckoo ? ' kicks=${placed.kicks} failed' : ' full');
    }
    final rehashes = <String>[];
    if (!placed.success) {
      rehashes.add(automatic(mode == Mode.cuckoo ? 'kicks' : 'full', prime(2 * capacity), placed.homeless));
    }
    rehashes.addAll(loadCheck(maxLoad));
    return Mutation(true, [row, ...path, ...placed.moves, ...rehashes], rehashes);
  }

  List<String> get(String key, {bool trace = false}) {
    final found = search(key, trace: trace);
    counters.probes += found.probes;
    final item = found.item;
    String row;
    if (item != null) {
      counters.hits++;
      row = 'GET $item at=${position(found.position)} probes=${found.probes}';
    } else {
      counters.misses++;
      row = 'GET $key NOT FOUND probes=${found.probes}';
    }
    return [row, if (trace) 'PATH ${found.path.isEmpty ? 'none' : found.path.join(' ')}'];
  }

  Mutation delete(String key, int minLoad, int maxLoad, {bool trace = false}) {
    final found = search(key, trace: trace);
    final path = trace ? ['PATH ${found.path.isEmpty ? 'none' : found.path.join(' ')}'] : <String>[];
    counters.probes += found.probes;
    if (found.item == null) {
      counters.absent++;
      return Mutation(false, ['DEL $key NOT FOUND probes=${found.probes}', ...path], []);
    }
    final removed = remove(found, trace: trace);
    counters.deletes++;
    var row = 'DEL $key OK at=${position(found.position)} probes=${found.probes}';
    if (mode == Mode.robinHood) row += ' shifted=${removed.shifted}';
    final rehashes = shrinkCheck(minLoad, maxLoad);
    return Mutation(true, [row, ...path, ...removed.moves, ...rehashes], rehashes);
  }

  List<Cost> costs() {
    final records = <Cost>[];
    if (mode == Mode.chain) {
      for (var index = 0; index < capacity; index++) {
        for (var i = 0; i < buckets[index].length; i++) {
          records.add((key: buckets[index][i].key, probes: i + 1, position: index));
        }
      }
    } else {
      for (var index = 0; index < slots.length; index++) {
        final item = slots[index].item;
        if (item == null) continue;
        final cost = mode == Mode.cuckoo ? index ~/ capacity + 1
            : mode == Mode.linear || mode == Mode.robinHood ? distance(item.key, index) + 1
            : search(item.key).probes;
        records.add((key: item.key, probes: cost, position: index));
      }
    }
    return records;
  }

  Metrics metrics() {
    var total = 0, longest = 0;
    for (final cost in costs()) {
      total += cost.probes;
      longest = math.max(longest, cost.probes);
    }
    return (longest: longest, average: ratio(total, size));
  }

  List<String> dump() {
    final rows = ['DUMP ${mode.label} cap=$capacity size=$size tomb=$tombstones'];
    if (mode == Mode.chain) {
      for (var index = 0; index < capacity; index++) {
        rows.add('$index ${buckets[index].isEmpty ? '-' : buckets[index].join(' ')}');
      }
    } else {
      for (var index = 0; index < slots.length; index++) {
        final slot = slots[index];
        final item = slot.item;
        final label = mode == Mode.cuckoo ? 'T${index ~/ capacity + 1} ${index % capacity}' : '$index';
        var value = item?.toString() ?? slot.content;
        if (mode == Mode.robinHood && item != null) value += ' d=${distance(item.key, index)}';
        rows.add('$label $value');
      }
    }
    return rows;
  }

  List<String> map() {
    final rows = ['MAP ${mode.label} cap=$capacity'];
    final costBySlot = List.filled(slotCount, 0);
    if (mode != Mode.chain) {
      for (final cost in costs()) { costBySlot[cost.position] = cost.probes; }
    }
    for (var part = 0; part < mode.parts; part++) {
      final characters = <String>[];
      for (var index = 0; index < capacity; index++) {
        if (mode == Mode.chain) {
          characters.add(buckets[index].isEmpty ? '.' : gauge(buckets[index].length));
        } else {
          final flat = part * capacity + index;
          final slot = slots[flat];
          characters.add(slot.empty ? '.' : slot.deleted ? 'D'
              : mode == Mode.cuckoo ? '#' : gauge(costBySlot[flat] - 1));
        }
      }
      for (var index = 0; index < capacity; index += 40) {
        final prefix = mode == Mode.cuckoo ? 'T${part + 1} ' : '';
        rows.add('$prefix${index.toString().padLeft(5, '0')} ${characters.sublist(index, math.min(index + 40, capacity)).join()}');
      }
    }
    return rows;
  }

  List<String> statistics() {
    final values = metrics();
    final count = counters;
    return ['STATS ${mode.label} size=$size cap=$capacity slots=$slotCount tomb=$tombstones '
        'load=${ratio(100 * size, slotCount)}% longest=${values.longest} avg=${values.average} '
        'probes=${count.probes} rehashes=${count.rehashes}',
      'OPS inserts=${count.inserts} updates=${count.updates} hits=${count.hits} misses=${count.misses} '
        'deletes=${count.deletes} absent=${count.absent}'];
  }

  List<String> scan(int cursor, int limit) {
    final keys = <String>[];
    var next = cursor;
    while (next < slotCount && keys.length < limit) {
      if (mode == Mode.chain) { keys.addAll(buckets[next].map((item) => item.key)); }
      else if (slots[next].item case final item?) { keys.add(item.key); }
      next++;
    }
    if (next == slotCount) next = 0;
    return [['SCAN next=$next', ...keys].join(' ')];
  }

  List<int> runs(int start, int count) {
    var empty = -1;
    for (var i = 0; i < count; i++) {
      if (slots[start + i].empty) { empty = i; break; }
    }
    if (empty < 0) return [count];
    final lengths = <int>[];
    var length = 0;
    for (var offset = 1; offset <= count; offset++) {
      if (!slots[start + (empty + offset) % count].empty) { length++; }
      else if (length > 0) { lengths.add(length); length = 0; }
    }
    return lengths;
  }

  List<String> clusters() {
    final lengths = mode == Mode.chain
        ? [for (final bucket in buckets) if (bucket.isNotEmpty) bucket.length]
        : [for (var part = 0; part < mode.parts; part++) ...runs(part * capacity, capacity)];
    final longest = lengths.fold(0, (value, length) => math.max(value, length));
    return ['CLUSTERS runs=${lengths.length} longest=$longest', ...histogram(lengths)];
  }

  List<String> distribution() {
    final values = costs().map((cost) => cost.probes).toList();
    final longest = values.fold(0, (value, cost) => math.max(value, cost));
    return ['DIST keys=$size longest=$longest', ...histogram(values)];
  }
}

final class Simulator {
  HashTable? table;
  int maxLoad = 75, minLoad = 0;
  bool tracing = false;
  static const commands = {'CREATE', 'MAXLOAD', 'MINLOAD', 'TRACE', 'HASH', 'PUT', 'ADD',
    'GET', 'DEL', 'PROBE', 'GEN', 'GENDEL', 'RESIZE', 'CONVERT', 'CLEAR', 'DUMP', 'MAP',
    'STATS', 'KEYS', 'TOP', 'SCAN', 'CLUSTERS', 'DIST', 'COMPARE', 'BENCH'};

  List<String> compare(int capacity) {
    final listed = table!.items()..sort((a, b) => a.key.compareTo(b.key));
    final rows = ['COMPARE keys=${listed.length} cap=$capacity'];
    for (final mode in Mode.values) {
      final trial = HashTable(mode, capacity);
      for (final item in listed) { trial.put(item.key, item.value, maxLoad); }
      final values = trial.metrics();
      rows.add('${mode.label} cap=${trial.capacity} longest=${values.longest} avg=${values.average} '
          'probes=${trial.counters.probes} rehashes=${trial.counters.rehashes}');
    }
    return rows;
  }

  List<String> bench(int capacity, int count, int length, int seed) {
    final keys = generate(2 * count, length, seed).toList();
    final rows = ['BENCH cap=$capacity count=$count len=$length seed=$seed'];
    for (final mode in Mode.values) {
      final trial = HashTable(mode, capacity);
      for (var i = 0; i < count; i++) { trial.put(keys[i], i + 1, maxLoad); }
      var misses = 0, probes = 0;
      for (var i = count; i < 2 * count; i++) {
        final found = trial.search(keys[i]);
        if (found.item == null) { misses++; probes += found.probes; }
      }
      rows.add('${mode.label} cap=${trial.capacity} keys=${trial.size} hit=${trial.metrics().average} '
          'misses=$misses miss=${ratio(probes, misses)} rehashes=${trial.counters.rehashes}');
    }
    return rows;
  }

  List<String> execute(String line) {
    final words = line.split(' ');
    final command = words[0];
    if (!commands.contains(command)) throw CommandError('UNKNOWN COMMAND $command');
    switch (command) {
      case 'CREATE':
        final mode = parseMode(words[1]);
        final capacity = int.parse(words[2]);
        checkCapacity(capacity);
        final replacement = HashTable(mode, prime(capacity));
        table = replacement;
        return ['CREATE ${mode.label} cap=${replacement.capacity}'];
      case 'MAXLOAD':
      case 'MINLOAD':
        final value = int.parse(words[1]);
        final maximum = command == 'MAXLOAD';
        if (maximum ? value < 10 || value > 95 : value < 0 || value > 40) throw const CommandError('BAD LOAD');
        if (maximum) { maxLoad = value; } else { minLoad = value; }
        return ['$command $value'];
      case 'TRACE':
        if (words[1] != 'ON' && words[1] != 'OFF') throw const CommandError('BAD ARGUMENT');
        tracing = words[1] == 'ON';
        return ['TRACE ${words[1]}'];
      case 'HASH':
        final key = words[1];
        final capacity = int.parse(words[2]);
        checkCapacity(capacity);
        return ['HASH $key m=$capacity h31=${hash(key, 31, capacity)} h37=${hash(key, 37, capacity)} '
            'step=${1 + hash(key, 37, capacity - 1)}'];
      case 'BENCH':
        final capacity = int.parse(words[1]);
        checkCapacity(capacity);
        final count = int.parse(words[2]), length = int.parse(words[3]), seed = int.parse(words[4]);
        checkGeneration(count, length, seed);
        return bench(prime(capacity), count, length, seed);
    }
    final current = table;
    if (current == null) throw const CommandError('NO TABLE');
    switch (command) {
      case 'PUT':
      case 'ADD': return current.put(words[1], int.parse(words[2]), maxLoad, command: command, trace: tracing).lines;
      case 'GET': return current.get(words[1], trace: tracing);
      case 'DEL': return current.delete(words[1], minLoad, maxLoad, trace: tracing).lines;
      case 'PROBE':
        final found = current.search(words[1], trace: true);
        return [['PROBE ${words[1]}', ...found.path, '${found.item == null ? 'MISS' : 'FOUND'} probes=${found.probes}'].join(' ')];
      case 'GEN':
      case 'GENDEL':
        final count = int.parse(words[1]), length = int.parse(words[2]), seed = int.parse(words[3]);
        checkGeneration(count, length, seed);
        final rows = <String>[];
        var changed = 0, index = 0;
        for (final key in generate(count, length, seed)) {
          index++;
          final result = command == 'GEN' ? current.put(key, index, maxLoad) : current.delete(key, minLoad, maxLoad);
          if (result.changed) changed++;
          rows.addAll(result.rehashes);
        }
        rows.add(command == 'GEN' ? 'GEN $count new=$changed updated=${count - changed}'
            : 'GENDEL $count deleted=$changed missing=${count - changed}');
        return rows;
      case 'RESIZE':
      case 'CONVERT':
        var mode = current.mode;
        var capacity = current.capacity;
        if (command == 'RESIZE') { capacity = int.parse(words[1]); checkCapacity(capacity); capacity = prime(capacity); }
        else { mode = parseMode(words[1]); }
        if (100 * current.size > maxLoad * capacity * mode.parts) throw const CommandError('TOO SMALL');
        final replacement = HashTable.rebuild(current.items(), mode, capacity);
        if (replacement == null) throw const CommandError('REBUILD FAILED');
        final row = command == 'RESIZE' ? 'RESIZE ${current.capacity} -> $capacity'
            : 'CONVERT ${current.mode.label} -> ${mode.label} cap=$capacity';
        current.adopt(replacement);
        return [row];
      case 'CLEAR':
        final size = current.size;
        current.adopt(HashTable(current.mode, current.capacity));
        return ['CLEAR $size'];
      case 'DUMP': return current.dump();
      case 'MAP': return current.map();
      case 'STATS': return current.statistics();
      case 'KEYS':
        final keys = current.items().map((item) => item.key).toList()..sort();
        return [['KEYS ${current.size}', ...keys].join(' ')];
      case 'TOP':
        final limit = int.parse(words[1]);
        if (limit < 1 || limit > 100) throw const CommandError('BAD ARGUMENT');
        final records = current.costs()..sort((a, b) {
          final order = b.probes.compareTo(a.probes);
          return order != 0 ? order : a.key.compareTo(b.key);
        });
        final selected = records.take(limit).toList();
        return ['TOP ${selected.length}', for (final cost in selected)
          '${cost.key} cost=${cost.probes} at=${current.position(cost.position)}'];
      case 'SCAN':
        final cursor = int.parse(words[1]), limit = int.parse(words[2]);
        if (limit < 1 || limit > 100) throw const CommandError('BAD ARGUMENT');
        if (cursor >= current.slotCount) throw const CommandError('BAD CURSOR');
        return current.scan(cursor, limit);
      case 'CLUSTERS': return current.clusters();
      case 'DIST': return current.distribution();
      case 'COMPARE':
        final capacity = int.parse(words[1]);
        checkCapacity(capacity);
        return compare(prime(capacity));
      default: throw StateError('Unhandled command $command');
    }
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final simulator = Simulator();
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try { stdout.writeln(simulator.execute(line).join('\n')); }
    on CommandError catch (error) { stdout.writeln(error); }
  }
}
