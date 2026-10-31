part of 'main.dart';

extension CopyCollector on Heap {
  void copyCollection(List<HeapObject?> roots, int line, int request) {
    final record = CollectionRecord(
      records.length + 1,
      line,
      request,
      'copy',
      freeList(),
    );
    base = size ~/ 2 - base;
    top = base;
    final copied = <HeapObject>{}, queue = <HeapObject>[];
    void copyObject(HeapObject? object) {
      if (object == null || !copied.add(object)) return;
      object.address = top;
      top += object.size;
      object.moves++;
      record.live.add(object);
      record.moved.add(object);
      queue.add(object);
    }

    record.work += roots.length;
    for (final root in roots) {
      copyObject(root);
    }
    for (var i = 0; i < queue.length; i++) {
      final object = queue[i];
      record.work += object.size + object.fields.length;
      for (final child in object.fields) {
        copyObject(child);
      }
    }
    for (final object in objects) {
      if (!copied.contains(object)) record.freed.add(object);
    }
    objects = queue;
    record.finish(freeList());
    records.add(record);
  }

  bool allocateCopy(HeapObject object, List<HeapObject?> roots, int line) {
    if (top + object.size > base + size ~/ 2)
      copyCollection(roots, line, object.size);
    if (top + object.size > base + size ~/ 2) return false;
    object.address = top;
    top += object.size;
    objects.add(object);
    return true;
  }
}
