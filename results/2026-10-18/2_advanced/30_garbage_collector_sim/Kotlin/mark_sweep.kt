object Marking {
    private fun push(record: CollectionRecord, stack: ArrayDeque<HeapObject>, item: HeapObject) {
        item.marked = true;
        stack.addLast(item);
        record.stack = maxOf(record.stack, stack.size)
    }
    fun mark(collector: Collector, roots: List<Int>, record: CollectionRecord) {
        for (item in collector.objects) item.marked = false
        record.work += roots.size;
        val stack = ArrayDeque<HeapObject>()
        for (root in roots) {
            if (root == 0 || collector.lookup(root).marked) continue
            push(record, stack, collector.lookup(root))
            while (stack.isNotEmpty()) {
                val item = stack.removeLast();
                record.live.add(item);
                record.work += 1 + item.fields.size;
                for (child in item.fields) if (child != 0 && !collector.lookup(child).marked) push(record, stack, collector.lookup(child))
            }
        }
    }
    fun sweep(collector: Collector, record: CollectionRecord) {
        record.work += collector.objects.size;
        val survivors = mutableListOf<HeapObject>();
        for (item in collector.objects) if (item.marked) survivors.add(item) else record.freed.add(item);
        collector.objects = survivors
    }
}
open class MarkSweep(size: Int) : Collector(size) {
    override fun freeList(): List<FreeBlock> = Heap.freeBlocks(objects, 0, size)
    override fun allocate(item: HeapObject, roots: List<Int>, line: Int): Boolean {
        var address = Heap.firstFit(freeList(), item.size)
        if (address < 0) {
            collect(roots, line, item.size);
            address = Heap.firstFit(freeList(), item.size);
            if (address < 0) return false
        }
        place(item, address);
        return true
    }
    open fun collect(roots: List<Int>, line: Int, request: Int) {
        val record = CollectionRecord(records.size + 1, line, request, "sweep", freeList());
        Marking.mark(this, roots, record);
        Marking.sweep(this, record);
        record.finish(freeList());
        records.add(record)
    }
}
class MarkCompact(size: Int) : MarkSweep(size) {
    private var top = 0
    override fun freeList(): List<FreeBlock> = if (top < size) listOf(FreeBlock(top, size - top)) else emptyList()
    override fun allocate(item: HeapObject, roots: List<Int>, line: Int): Boolean {
        if (top + item.size > size) {
            collect(roots, line, item.size);
            if (top + item.size > size) return false
        };
        place(item, top);
        top += item.size;
        return true
    }
    override fun collect(roots: List<Int>, line: Int, request: Int) {
        val record = CollectionRecord(records.size + 1, line, request, "compact", freeList());
        Marking.mark(this, roots, record);
        record.work += objects.size + roots.size;
        var destination = 0;
        val survivors = mutableListOf<HeapObject>()
        for (item in Heap.byAddress(objects)) {
            if (!item.marked) {
                record.freed.add(item);
                continue
            };
            record.work += item.fields.size;
            if (item.address != destination) {
                record.moved.add(item);
                record.work += item.size;
                item.address = destination;
                item.moves++
            };
            destination += item.size;
            survivors.add(item)
        }
        objects = survivors;
        top = destination;
        record.finish(freeList());
        records.add(record)
    }
}
