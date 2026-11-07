import java.util.*;

final class Generational extends Collector {
    final int young, half, promotionAge;
    int base, top, target, barriers, remembers;
    Set<HeapObject> remembered = new HashSet<>();
    Generational(int size, int young, int age) {
        super(size);
        this.young = young;
        half = young / 2;
        promotionAge = age;
    }
    boolean young(HeapObject object) {
        return object.address < young;
    }
    List<FreeBlock> oldBlocks() {
        return Heap.freeBlocks(objects, young, size);
    }
    List<FreeBlock> freeList() {
        List<FreeBlock> blocks = new ArrayList<>();
        if (top < base + half)
            blocks.add(new FreeBlock(top, base + half - top));
        blocks.addAll(oldBlocks());
        return blocks;
    }
    int[] inactive() {
        return new int[] {half - base, 2 * half - base};
    }
    boolean allocate(HeapObject object, List<Integer> roots, int line) {
        if (top + object.size <= base + half) {
            place(object, top);
            top += object.size;
            return true;
        }
        for (int stage = 0; stage < 2; stage++) {
            boolean marking = Heap.largest(oldBlocks()) < top - base;
            String kind = stage == 0 ? (marking ? "major" : "minor") : (marking ? "full" : "tenure");
            if (!collect(kind, roots, line, object.size))
                return false;
            if (top + object.size <= base + half) {
                place(object, top);
                top += object.size;
                return true;
            }
        }
        return false;
    }
    void writeBarrier(int number, int value) {
        HeapObject object = lookup(number);
        if (young(object))
            return;
        barriers++;
        if (value != 0 && young(lookup(value)) && remembered.add(object))
            remembers++;
    }
    boolean evacuate(int number, CollectionRecord record, Set<Integer> pending, List<HeapObject> queue) {
        if (number == 0 || !pending.remove(number))
            return true;
        HeapObject object = lookup(number);
        object.age++;
        object.moves++;
        if (record.kind.equals("tenure") || record.kind.equals("full") || object.age >= promotionAge) {
            int address = Heap.firstFit(oldBlocks(), object.size);
            if (address < 0)
                return false;
            object.address = address;
            record.promoted.add(object)
            ;
        } else {
            object.address = target;
            target += object.size;
        }
        record.moved.add(object)
        ;
        if (record.kind.equals("minor") || record.kind.equals("tenure"))
            record.live.add(object)
        ;
        queue.add(object);
        return true;
    }
    boolean fields(HeapObject object, CollectionRecord record, Set<Integer> pending, List<HeapObject> queue) {
        for (int child : object.fields)
            if (!evacuate(child, record, pending, queue))
                return false;
        return true;
    }
    boolean collect(String kind, List<Integer> roots, int line, int request) {
        CollectionRecord record = new CollectionRecord(records.size() + 1, line, request, kind, freeList());
        if (kind.equals("major") || kind.equals("full")) {
            Marking.mark(this, roots, record);
            List<HeapObject> survivors = new ArrayList<>();
            for (HeapObject object : objects) {
                if (young(object))
                    survivors.add(object);
                else {
                    record.work
                    ++;
                    if (object.marked)
                        survivors.add(object);
                    else {
                        record.freed.add(object)
                        ;
                        remembered.remove(object);
                    }
                }
            }
            objects = survivors;
        }
        Set<Integer> pending = new HashSet<>();
        for (HeapObject object : objects)
            if (young(object))
                pending.add(object.number);
        int destination = half - base;
        target = destination;
        List<HeapObject> queue = new ArrayList<>();
        record.work
        += roots.size();
        for (int root : roots)
            if (!evacuate(root, record, pending, queue))
                return false;
        for (HeapObject object : Heap.byAddress(remembered)) {
            record.work
            += 1 + object.fields.length;
            if (!fields(object, record, pending, queue))
                return false;
        }
        for (int i = 0; i < queue.size(); i++) {
            HeapObject object = queue.get(i);
            record.work
            += object.size + object.fields.length;
            if (!fields(object, record, pending, queue))
                return false;
        }
        List<HeapObject> survivors = new ArrayList<>();
        for (HeapObject object : objects) {
            if (pending.contains(object.number))
                record.freed.add(object)
            ;
            else survivors.add(object);
        }
        objects = survivors;
        base = destination;
        top = target;
        remembered.clear();
        for (HeapObject object : objects)
            if (!young(object))
                for (int child : object.fields)
                    if (child != 0 && young(lookup(child))) {
                        remembered.add(object);
                        break;
                    }
        record.finish(freeList())
        ;
        records.add(record);
        return true;
    }
}
