class HeapObject(val number: Int, pointers: Int, data: Int) {
    val size = 1 + pointers + data
    val fields = IntArray(pointers)
    var address = 0;
    var moves = 0;
    var age = 0;
    var count = 0;
    var marked = false
}
class Pair {
    var count = 0;
    var words = 0
    fun add(item: HeapObject) {
        count++;
        words += item.size
    }
    fun add(other: Pair) {
        count += other.count;
        words += other.words
    }
    override fun toString(): String = "$count $words"
}
data class FreeBlock(val address: Int, val length: Int)
class CollectionRecord(val number: Int, val line: Int, val request: Int, val kind: String, blocks: List<FreeBlock>) {
    val live = Pair();
    val freed = Pair();
    val moved = Pair();
    val promoted = Pair()
    val before = intArrayOf(Heap.total(blocks), Heap.largest(blocks))
    var after = IntArray(2);
    var stack = 0;
    var work = 0
    fun finish(blocks: List<FreeBlock>) {
        after = intArrayOf(Heap.total(blocks), Heap.largest(blocks))
    }
}
abstract class Collector(val size: Int) {
    var objects = mutableListOf<HeapObject>()
    val placed = mutableListOf<HeapObject>()
    val records = mutableListOf<CollectionRecord>()
    fun lookup(number: Int): HeapObject = placed[number - 1]
    fun place(item: HeapObject, address: Int) {
        item.address = address;
        objects.add(item);
        placed.add(item)
    }
    open fun inactive(): IntArray = intArrayOf(0, 0)
    abstract fun freeList(): List<FreeBlock>
    abstract fun allocate(item: HeapObject, roots: List<Int>, line: Int): Boolean
}
object Heap {
    fun byAddress(objects: Collection<HeapObject>): List<HeapObject> = objects.sortedBy {
        it.address
    }
    fun freeBlocks(objects: List<HeapObject>, start: Int, end: Int): List<FreeBlock> {
        val blocks = mutableListOf<FreeBlock>();
        var position = start
        for (item in byAddress(objects)) {
            if (item.address < start || item.address >= end) continue;
            if (item.address > position) blocks.add(FreeBlock(position, item.address - position));
            position = item.address + item.size
        }
        if (position < end) blocks.add(FreeBlock(position, end - position))
        return blocks
    }
    fun firstFit(blocks: List<FreeBlock>, size: Int): Int = blocks.firstOrNull {
        it.length >= size
    }
    ?.address ?: -1
    fun total(blocks: List<FreeBlock>): Int = blocks.sumOf {
        it.length
    }
    fun largest(blocks: List<FreeBlock>): Int = blocks.maxOfOrNull {
        it.length
    }
    ?: 0
    fun dec2(numerator: Int, denominator: Int): String {
        val rounded = (200 * numerator + denominator) / (2 * denominator);
        return "${rounded / 100}.${(rounded % 100).toString().padStart(2, '0')}"
    }
    fun percent(part: Int, whole: Int): String = if (whole == 0) "-" else dec2(100 * part, whole)
    fun classes(values: List<Int>): String {
        val labels = listOf("1", "2-3", "4-7", "8-15", "16+");
        val limits = intArrayOf(1, 3, 7, 15);
        val counts = IntArray(5)
        for (value in values) {
            var index = 0;
            while (index < limits.size && value > limits[index]) index++;
            counts[index]++
        }
        return labels.indices.joinToString(" ") {
            "${labels[it]}:${counts[it]}"
        }
    }
    fun map(size: Int, objects: List<HeapObject>, reachable: Set<Int>, inactive: IntArray): String {
        val cells = CharArray(size) {
            '.'
        };
        for (address in inactive[0] until inactive[1]) cells[address] = '-'
        for (item in objects) {
            val live = item.number in reachable;
            val letter = ('A'.code + (item.number - 1) % 26).toChar();
            cells[item.address] = if (live) letter else '#';
            for (address in item.address + 1 until item.address + item.size) cells[address] = if (live) letter.lowercaseChar() else '='
        }
        return cells.concatToString()
    }
}
