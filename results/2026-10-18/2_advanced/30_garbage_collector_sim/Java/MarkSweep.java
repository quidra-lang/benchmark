import java.util.*;

final class Marking {
    static void push(CollectionRecord record, Deque<HeapObject> stack, HeapObject object) {
        object.marked = true;
        stack.push(object);
        record.stack
        = Math.max(record.stack, stack.size());
    }
    static void mark(Collector collector, List<Integer> roots, CollectionRecord record) {
        for (HeapObject object : collector.objects)
            object.marked = false;
        record.work
        += roots.size();
        Deque<HeapObject> stack = new ArrayDeque<>();
        for (int root : roots) {
            if (root == 0 || collector.lookup(root).marked)
                continue;
            push(record, stack, collector.lookup(root));
            while (!stack.isEmpty()) {
                HeapObject object = stack.pop();
                record.live.add(object)
                ;
                record.work
                += 1 + object.fields.length;
                for (int child : object.fields)
                    if (child != 0 && !collector.lookup(child).marked)
                        push(record, stack, collector.lookup(child));
            }
        }
    }
    static void sweep(Collector collector, CollectionRecord record) {
        record.work
        += collector.objects.size();
        List<HeapObject> survivors = new ArrayList<>();
        for (HeapObject object : collector.objects) {
            if (object.marked)
                survivors.add(object);
            else
                record.freed.add(object)
            ;
        }
        collector.objects = survivors;
    }
}
class MarkSweep extends Collector {
    MarkSweep(int size) {
        super(size);
    }
    List<FreeBlock> freeList() {
        return Heap.freeBlocks(objects, 0, size);
    }
    boolean allocate(HeapObject object, List<Integer> roots, int line) {
        int address = Heap.firstFit(freeList(), object.size);
        if (address < 0) {
            collect(roots, line, object.size);
            address = Heap.firstFit(freeList(), object.size);
            if (address < 0)
                return false;
        }
        place(object, address);
        return true;
    }
    void collect(List<Integer> roots, int line, int request) {
        CollectionRecord record =
            new CollectionRecord(records.size() + 1, line, request, "sweep", freeList());
        Marking.mark(this, roots, record);
        Marking.sweep(this, record);
        record.finish(freeList())
        ;
        records.add(record);
    }
}
final class MarkCompact extends MarkSweep {
    private int top;
    MarkCompact(int size) {
        super(size);
    }
    List<FreeBlock> freeList() {
        return top < size ? List.of(new FreeBlock(top, size - top)) : List.of();
    }
    boolean allocate(HeapObject object, List<Integer> roots, int line) {
        if (top + object.size > size) {
            collect(roots, line, object.size);
            if (top + object.size > size)
                return false;
        }
        place(object, top);
        top += object.size;
        return true;
    }
    void collect(List<Integer> roots, int line, int request) {
        CollectionRecord record =
            new CollectionRecord(records.size() + 1, line, request, "compact", freeList());
        Marking.mark(this, roots, record);
        record.work
        += objects.size() + roots.size();
        int destination = 0;
        List<HeapObject> survivors = new ArrayList<>();
        for (HeapObject object : Heap.byAddress(objects)) {
            if (!object.marked) {
                record.freed.add(object)
                ;
                continue;
            }
            record.work
            += object.fields.length;
            if (object.address != destination) {
                record.moved.add(object)
                ;
                record.work
                += object.size;
                object.address = destination;
                object.moves++;
            }
            destination += object.size;
            survivors.add(object);
        }
        objects = survivors;
        top = destination;
        record.finish(freeList())
        ;
        records.add(record);
    }
}
