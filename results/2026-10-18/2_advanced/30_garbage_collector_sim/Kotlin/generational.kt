class Generational(size: Int, val young: Int, private val promotionAge: Int) : Collector(size) {
    private val half = young / 2
    private var base = 0;
    private var top = 0;
    private var target = 0
    var barriers = 0;
    var remembers = 0
    val remembered = mutableSetOf<HeapObject>()
    fun young(item: HeapObject): Boolean = item.address < young
    private fun oldBlocks(): List<FreeBlock> = Heap.freeBlocks(objects, young, size)
    override fun freeList(): List<FreeBlock> = (if (top < base + half) listOf(FreeBlock(top, base + half - top)) else emptyList()) + oldBlocks()
    override fun inactive(): IntArray = intArrayOf(half - base, 2 * half - base)
    override fun allocate(item: HeapObject, roots: List<Int>, line: Int): Boolean {
        if (top + item.size <= base + half) {
            place(item, top);
            top += item.size;
            return true
        }
        for (stage in 0..1) {
            val marking = Heap.largest(oldBlocks()) < top - base;
            val kind = if (stage == 0) {
                if (marking) "major" else "minor"
            } else {
                if (marking) "full" else "tenure"
            }
            if (!collect(kind, roots, line, item.size)) return false
            if (top + item.size <= base + half) {
                place(item, top);
                top += item.size;
                return true
            }
        }
        return false
    }
    fun writeBarrier(number: Int, value: Int) {
        val item = lookup(number);
        if (young(item)) return;
        barriers++;
        if (value != 0 && young(lookup(value)) && remembered.add(item)) remembers++
    }
    private fun evacuate(number: Int, record: CollectionRecord, pending: MutableSet<Int>, queue: MutableList<HeapObject>): Boolean {
        if (number == 0 || !pending.remove(number)) return true
        val item = lookup(number);
        item.age++;
        item.moves++
        if (record.kind == "tenure" || record.kind == "full" || item.age >= promotionAge) {
            val address = Heap.firstFit(oldBlocks(), item.size);
            if (address < 0) return false;
            item.address = address;
            record.promoted.add(item)
        }
        else {
            item.address = target;
            target += item.size
        }
        record.moved.add(item);
        if (record.kind == "minor" || record.kind == "tenure") record.live.add(item);
        queue.add(item);
        return true
    }
    private fun fields(item: HeapObject, record: CollectionRecord, pending: MutableSet<Int>, queue: MutableList<HeapObject>): Boolean {
        for (child in item.fields) if (!evacuate(child, record, pending, queue)) return false;
        return true
    }
    private fun collect(kind: String, roots: List<Int>, line: Int, request: Int): Boolean {
        val record = CollectionRecord(records.size + 1, line, request, kind, freeList())
        if (kind == "major" || kind == "full") {
            Marking.mark(this, roots, record);
            val survivors = mutableListOf<HeapObject>()
            for (item in objects) if (young(item)) survivors.add(item) else {
                record.work++;
                if (item.marked) survivors.add(item) else {
                    record.freed.add(item);
                    remembered.remove(item)
                }
            }
            objects = survivors
        }
        val pending = objects.filter {
            young(it)
        }.map {
            it.number
        }.toMutableSet();
        val destination = half - base;
        target = destination;
        val queue = mutableListOf<HeapObject>();
        record.work += roots.size
        for (root in roots) if (!evacuate(root, record, pending, queue)) return false
        for (item in Heap.byAddress(remembered)) {
            record.work += 1 + item.fields.size;
            if (!fields(item, record, pending, queue)) return false
        }
        var i = 0
        while (i < queue.size) {
            val item = queue[i++];
            record.work += item.size + item.fields.size;
            if (!fields(item, record, pending, queue)) return false
        }
        val survivors = mutableListOf<HeapObject>();
        for (item in objects) if (item.number in pending) record.freed.add(item) else survivors.add(item)
        objects = survivors;
        base = destination;
        top = target;
        remembered.clear()
        for (item in objects) if (!young(item) && item.fields.any {
            it != 0 && young(lookup(it))
        }) remembered.add(item)
        record.finish(freeList());
        records.add(record);
        return true
    }
}
