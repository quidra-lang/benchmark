class Copying(size: Int) : Collector(size) {
    private val half = size / 2
    private var base = 0;
    private var top = 0
    override fun freeList(): List<FreeBlock> = if (top < base + half) listOf(FreeBlock(top, base + half - top)) else emptyList()
    override fun inactive(): IntArray = intArrayOf(half - base, 2 * half - base)
    override fun allocate(item: HeapObject, roots: List<Int>, line: Int): Boolean {
        if (top + item.size > base + half) {
            collect(roots, line, item.size);
            if (top + item.size > base + half) return false
        };
        place(item, top);
        top += item.size;
        return true
    }
    private fun copy(number: Int, record: CollectionRecord, copied: MutableSet<Int>, queue: MutableList<HeapObject>) {
        if (number == 0 || !copied.add(number)) return
        val item = lookup(number);
        item.address = top;
        top += item.size;
        item.moves++;
        record.live.add(item);
        record.moved.add(item);
        queue.add(item)
    }
    private fun collect(roots: List<Int>, line: Int, request: Int) {
        val record = CollectionRecord(records.size + 1, line, request, "copy", freeList());
        base = half - base;
        top = base;
        val copied = mutableSetOf<Int>();
        val queue = mutableListOf<HeapObject>();
        record.work += roots.size
        for (root in roots) copy(root, record, copied, queue)
        var i = 0
        while (i < queue.size) {
            val item = queue[i++];
            record.work += item.size + item.fields.size;
            for (child in item.fields) copy(child, record, copied, queue)
        }
        for (item in objects) if (item.number !in copied) record.freed.add(item)
        objects = queue;
        record.finish(freeList());
        records.add(record)
    }
}
