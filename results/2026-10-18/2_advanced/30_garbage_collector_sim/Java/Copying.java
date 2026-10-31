import java.util.*;

final class Copying extends Collector {
    final int half;
    int base, top;
    Copying(int size) {
        super(size);
        half = size / 2;
    }
    List<FreeBlock> freeList() {
        return top < base + half ? List.of(new FreeBlock(top, base + half - top)) : List.of();
    }
    int[] inactive() {
        return new int[] {half - base, 2 * half - base};
    }
    boolean allocate(HeapObject object, List<Integer> roots, int line) {
        if (top + object.size > base + half) {
            collect(roots, line, object.size);
            if (top + object.size > base + half)
                return false;
        }
        place(object, top);
        top += object.size;
        return true;
    }
    void copy(int number, CollectionRecord record, Set<Integer> copied, List<HeapObject> queue) {
        if (number == 0 || !copied.add(number))
            return;
        HeapObject object = lookup(number);
        object.address = top;
        top += object.size;
        object.moves++;
        record.live.add(object)
        ;
        record.moved.add(object)
        ;
        queue.add(object);
    }
    void collect(List<Integer> roots, int line, int request) {
        CollectionRecord record = new CollectionRecord(records.size() + 1, line, request, "copy", freeList());
        base = half - base;
        top = base;
        Set<Integer> copied = new HashSet<>();
        List<HeapObject> queue = new ArrayList<>();
        record.work
        += roots.size();
        for (int root : roots)
            copy(root, record, copied, queue);
        for (int i = 0; i < queue.size(); i++) {
            HeapObject object = queue.get(i);
            record.work
            += object.size + object.fields.length;
            for (int child : object.fields)
                copy(child, record, copied, queue);
        }
        for (HeapObject object : objects)
            if (!copied.contains(object.number))
                record.freed.add(object)
        ;
        objects = queue;
        record.finish(freeList())
        ;
        records.add(record);
    }
}
