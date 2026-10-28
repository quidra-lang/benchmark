import java.util.*;

final class BlockRecord {
    final Block block;
    final BlockRecord parent;
    final Map<Reference, Coin> utxo;
    final List<Integer> transactionFees;
    final String source;
    final int fees, work;
    BlockRecord(Block block, BlockRecord parent, Map<Reference, Coin> utxo, List<Integer> transactionFees,
                String source) {
        this.block = block;
        this.parent = parent;
        this.utxo = utxo;
        this.transactionFees = transactionFees;
        this.source = source;
        fees = transactionFees.stream().mapToInt(Integer::intValue).sum();
        work = parent == null ? 1 : parent.work + (1 << (4 * block.difficulty));
    }
}

final class Chain {
    static int reward(int height, int initial, int interval) {
        for (int i = 0; i < height / interval; i++)
            initial /= 2;
        return initial;
    }
    static BlockRecord ancestor(BlockRecord record, int height) {
        while (record.block.height > height)
            record
        = record.parent;
        return record;
    }
    static List<BlockRecord> sequence(BlockRecord record) {
        List<BlockRecord> records = new ArrayList<>();
        while (record != null) {
            records.add(record);
            record
            = record.parent;
        }
        Collections.reverse(records);
        return records;
    }
    static BlockRecord fork(BlockRecord first, BlockRecord second) {
        int height = Math.min(first.block.height, second.block.height);
        first = ancestor(first, height);
        second = ancestor(second, height);
        while (first != second) {
            first = first.parent;
            second = second.parent;
        }
        return first;
    }
    static int median(BlockRecord record) {
        List<Integer> times = new ArrayList<>();
        while (record != null && times.size() < 3) {
            times.add(record.block.timestamp);
            record
            = record.parent;
        }
        Collections.sort(times);
        return times.get((times.size() - 1) / 2);
    }
    static int difficulty(BlockRecord parent, int initial, int interval, int target) {
        int height = parent.block.height + 1, difficulty = parent.block.difficulty;
        if (height == 1)
            return initial;
        if (height % interval != 0)
            return difficulty;
        int span = parent.block.timestamp - ancestor(parent, height - interval).block.timestamp,
            expected = target * (interval - 1);
        if (2 * span < expected)
            return Math.min(difficulty + 1, 2);
        return span > 2 * expected ? Math.max(difficulty - 1, 0) : difficulty;
    }
}
