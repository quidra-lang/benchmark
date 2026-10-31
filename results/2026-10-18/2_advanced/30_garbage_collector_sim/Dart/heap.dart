part of 'main.dart';

class HeapObject {
  final int number, size;
  final List<HeapObject?> fields;
  int address = 0, moves = 0, age = 0, count = 0;
  bool marked = false;
  HeapObject(this.number, int pointers, int data)
    : size = 1 + pointers + data,
      fields = List.filled(pointers, null);
}

class Pair {
  int count = 0, words = 0;
  void add(HeapObject object) {
    count++;
    words += object.size;
  }

  void addPair(Pair pair) {
    count += pair.count;
    words += pair.words;
  }

  @override
  String toString() => '$count $words';
}

typedef FreeBlock = (int, int);

class CollectionRecord {
  final int number, line, request;
  final String kind;
  final live = Pair(), freed = Pair(), moved = Pair(), promoted = Pair();
  int stack = 0, work = 0;
  final (int, int) before;
  (int, int) after = (0, 0);
  CollectionRecord(
    this.number,
    this.line,
    this.request,
    this.kind,
    List<FreeBlock> blocks,
  ) : before = (totalFree(blocks), largestFree(blocks));
  void finish(List<FreeBlock> blocks) {
    after = (totalFree(blocks), largestFree(blocks));
  }
}

List<HeapObject> byAddress(Iterable<HeapObject> objects) =>
    objects.toList()..sort((a, b) => a.address.compareTo(b.address));
List<FreeBlock> freeBlocks(List<HeapObject> objects, int start, int end) {
  final blocks = <FreeBlock>[];
  var position = start;
  for (final object in byAddress(objects)) {
    if (object.address < start || object.address >= end) continue;
    if (object.address > position)
      blocks.add((position, object.address - position));
    position = object.address + object.size;
  }
  if (position < end) blocks.add((position, end - position));
  return blocks;
}

int? firstFit(List<FreeBlock> blocks, int size) {
  for (final block in blocks) {
    if (block.$2 >= size) return block.$1;
  }
  return null;
}

int totalFree(List<FreeBlock> blocks) =>
    blocks.fold(0, (total, b) => total + b.$2);
int largestFree(List<FreeBlock> blocks) =>
    blocks.fold(0, (largest, b) => math.max(largest, b.$2));
String dec2(int a, int b) {
  final q = (200 * a + b) ~/ (2 * b);
  return '${q ~/ 100}.${(q % 100).toString().padLeft(2, '0')}';
}

String pct(int a, int b) => b == 0 ? '-' : dec2(100 * a, b);
String classTable(Iterable<int> values) {
  final counts = List.filled(5, 0),
      limits = [1, 3, 7, 15],
      labels = ['1', '2-3', '4-7', '8-15', '16+'];
  for (final value in values) {
    var index = 4;
    for (var i = 0; i < limits.length; i++) {
      if (value <= limits[i]) {
        index = i;
        break;
      }
    }
    counts[index]++;
  }
  return [
    for (var i = 0; i < counts.length; i++) '${labels[i]}:${counts[i]}',
  ].join(' ');
}

String heapMap(
  int size,
  List<HeapObject> objects,
  Set<int> reachable,
  (int, int) inactive,
) {
  final cells = List.filled(size, '.');
  for (var address = inactive.$1; address < inactive.$2; address++) {
    cells[address] = '-';
  }
  for (final object in objects) {
    final letter = String.fromCharCode(65 + (object.number - 1) % 26),
        live = reachable.contains(object.number);
    cells[object.address] = live ? letter : '#';
    for (var a = object.address + 1; a < object.address + object.size; a++) {
      cells[a] = live ? letter.toLowerCase() : '=';
    }
  }
  return cells.join();
}

int usedWords(Iterable<HeapObject> objects) =>
    objects.fold(0, (total, object) => total + object.size);

class Heap {
  final int size, young, promotionAge;
  final String type;
  final List<int> deaths;
  var objects = <HeapObject>[];
  final records = <CollectionRecord>[];
  var remembered = <HeapObject>{};
  int base = 0,
      top = 0,
      barriers = 0,
      remembers = 0,
      increments = 0,
      decrements = 0;
  final released = <HeapObject>[], reports = <List<String>>[];
  Heap(this.size, this.type, this.young, this.promotionAge, this.deaths);
  List<FreeBlock> freeList() {
    if (type == 'MARK_COMPACT') return top < size ? [(top, size - top)] : [];
    if (type == 'COPYING' || type == 'GENERATIONAL') {
      final half = type == 'COPYING' ? size ~/ 2 : young ~/ 2;
      return [
        if (top < base + half) (top, base + half - top),
        if (type == 'GENERATIONAL') ...oldBlocks(),
      ];
    }
    return freeBlocks(objects, 0, size);
  }

  (int, int) inactive() {
    final half = type == 'COPYING'
        ? size ~/ 2
        : type == 'GENERATIONAL'
        ? young ~/ 2
        : 0;
    return half == 0 ? (0, 0) : (half - base, 2 * half - base);
  }
}
