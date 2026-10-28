part of 'main.dart';

extension GenerationCollector on Heap {
  bool isYoung(HeapObject object) => object.address < young;
  List<FreeBlock> oldBlocks() => freeBlocks(objects, young, size);
  void writeBarrier(HeapObject target, HeapObject? value) {
    if (isYoung(target)) return;
    barriers++;
    if (value != null && isYoung(value) && remembered.add(target)) remembers++;
  }

  bool generationCollection(
    String kind,
    List<HeapObject?> roots,
    int line,
    int request,
  ) {
    final record = CollectionRecord(
          records.length + 1,
          line,
          request,
          kind,
          freeList(),
        ),
        marking = kind == 'major' || kind == 'full';
    if (marking) {
      mark(record, roots, objects);
      final survivors = <HeapObject>[];
      for (final object in objects) {
        if (isYoung(object)) {
          survivors.add(object);
        } else {
          record.work++;
          if (object.marked) {
            survivors.add(object);
          } else {
            record.freed.add(object);
            remembered.remove(object);
          }
        }
      }
      objects = survivors;
    }
    final pending = objects.where(isYoung).toSet(),
        destination = young ~/ 2 - base,
        queue = <HeapObject>[];
    var target = destination;
    bool evacuate(HeapObject? object) {
      if (object == null || !pending.remove(object)) return true;
      object.age++;
      object.moves++;
      if (kind == 'tenure' || kind == 'full' || object.age >= promotionAge) {
        final address = firstFit(oldBlocks(), object.size);
        if (address == null) return false;
        object.address = address;
        record.promoted.add(object);
      } else {
        object.address = target;
        target += object.size;
      }
      record.moved.add(object);
      if (!marking) record.live.add(object);
      queue.add(object);
      return true;
    }

    record.work += roots.length;
    for (final root in roots) {
      if (!evacuate(root)) return false;
    }
    for (final object in byAddress(remembered)) {
      record.work += 1 + object.fields.length;
      for (final child in object.fields) {
        if (!evacuate(child)) return false;
      }
    }
    for (var i = 0; i < queue.length; i++) {
      final object = queue[i];
      record.work += object.size + object.fields.length;
      for (final child in object.fields) {
        if (!evacuate(child)) return false;
      }
    }
    final survivors = <HeapObject>[];
    for (final object in objects) {
      if (pending.contains(object)) {
        record.freed.add(object);
      } else {
        survivors.add(object);
      }
    }
    objects = survivors;
    base = destination;
    top = target;
    remembered = objects
        .where(
          (object) =>
              !isYoung(object) &&
              object.fields.any((child) => child != null && isYoung(child)),
        )
        .toSet();
    record.finish(freeList());
    records.add(record);
    return true;
  }

  bool allocateGeneration(
    HeapObject object,
    List<HeapObject?> roots,
    int line,
  ) {
    for (var step = 0; step <= 2; step++) {
      if (top + object.size <= base + young ~/ 2) {
        object.address = top;
        top += object.size;
        objects.add(object);
        return true;
      }
      if (step == 2) return false;
      final marking = largestFree(oldBlocks()) < top - base;
      final kind = step == 0
          ? (marking ? 'major' : 'minor')
          : (marking ? 'full' : 'tenure');
      if (!generationCollection(kind, roots, line, object.size)) return false;
    }
    return false;
  }
}
