part of 'main.dart';

void mark(
  CollectionRecord record,
  List<HeapObject?> roots,
  List<HeapObject> objects,
) {
  for (final object in objects) {
    object.marked = false;
  }
  record.work += roots.length;
  final stack = <HeapObject>[];
  void push(HeapObject object) {
    object.marked = true;
    stack.add(object);
    record.stack = math.max(record.stack, stack.length);
  }

  for (final root in roots) {
    if (root == null || root.marked) continue;
    push(root);
    while (stack.isNotEmpty) {
      final object = stack.removeLast();
      record.live.add(object);
      record.work += 1 + object.fields.length;
      for (final child in object.fields) {
        if (child != null && !child.marked) push(child);
      }
    }
  }
}

List<HeapObject> sweep(CollectionRecord record, List<HeapObject> objects) {
  record.work += objects.length;
  final survivors = <HeapObject>[];
  for (final object in objects) {
    if (object.marked) {
      survivors.add(object);
    } else {
      record.freed.add(object);
    }
  }
  return survivors;
}

extension MarkCollectors on Heap {
  void sweepCollection(List<HeapObject?> roots, int line, int request) {
    final record = CollectionRecord(
      records.length + 1,
      line,
      request,
      type == 'MARK_COMPACT' ? 'compact' : 'sweep',
      freeList(),
    );
    mark(record, roots, objects);
    if (type == 'MARK_COMPACT') {
      record.work += objects.length + roots.length;
      var destination = 0;
      final survivors = <HeapObject>[];
      for (final object in byAddress(objects)) {
        if (!object.marked) {
          record.freed.add(object);
          continue;
        }
        record.work += object.fields.length;
        if (object.address != destination) {
          record.moved.add(object);
          record.work += object.size;
          object.address = destination;
          object.moves++;
        }
        destination += object.size;
        survivors.add(object);
      }
      top = destination;
      objects = survivors;
    } else {
      objects = sweep(record, objects);
    }
    record.finish(freeList());
    records.add(record);
  }

  bool allocateMark(HeapObject object, List<HeapObject?> roots, int line) {
    if (type == 'MARK_COMPACT') {
      if (top + object.size > size) sweepCollection(roots, line, object.size);
      if (top + object.size > size) return false;
      object.address = top;
      top += object.size;
    } else {
      var address = firstFit(freeList(), object.size);
      if (address == null) {
        if (type == 'REFCOUNT') {
          backup(roots, line, object.size);
        } else {
          sweepCollection(roots, line, object.size);
        }
        address = firstFit(freeList(), object.size);
      }
      if (address == null) return false;
      object.address = address;
    }
    objects.add(object);
    return true;
  }
}
