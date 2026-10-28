class BlockRecord(val block: Block, val parent: BlockRecord?, val utxo: Map<Reference, Coin>, val transactionFees: List<Int>, val source: String) {
    val fees = transactionFees.sum()
    val work: Int = if (parent == null) 1 else parent.work + (1 shl (4 * block.difficulty))
}
object Chain {
    fun reward(height: Int, initial: Int, interval: Int): Int {
        var amount = initial;
        repeat(height / interval) {
            amount /= 2
        };
        return amount
    }
    fun ancestor(record: BlockRecord, height: Int): BlockRecord {
        var current = record;
        while (current.block.height > height) current = current.parent!!;
        return current
    }
    fun sequence(record: BlockRecord): List<BlockRecord> {
        val records = mutableListOf<BlockRecord>()
        var current: BlockRecord? = record
        while (current != null) {
            records.add(current);
            current = current.parent
        }
        return records.reversed()
    }
    fun fork(first: BlockRecord, second: BlockRecord): BlockRecord {
        val height = minOf(first.block.height, second.block.height)
        var a = ancestor(first, height)
        var b = ancestor(second, height)
        while (a !== b) {
            a = a.parent!!;
            b = b.parent!!
        }
        return a
    }
    fun median(record: BlockRecord): Int {
        val times = mutableListOf<Int>()
        var current: BlockRecord? = record
        while (current != null && times.size < 3) {
            times.add(current.block.timestamp);
            current = current.parent
        }
        times.sort()
        return times[(times.size - 1) / 2]
    }
    fun difficulty(parent: BlockRecord, initial: Int, interval: Int, target: Int): Int {
        val height = parent.block.height + 1
        val difficulty = parent.block.difficulty
        if (height == 1) return initial
        if (height % interval != 0) return difficulty
        val span = parent.block.timestamp - ancestor(parent, height - interval).block.timestamp
        val expected = target * (interval - 1)
        if (2 * span < expected) return minOf(difficulty + 1, 2)
        return if (span > 2 * expected) maxOf(difficulty - 1, 0) else difficulty
    }
}
