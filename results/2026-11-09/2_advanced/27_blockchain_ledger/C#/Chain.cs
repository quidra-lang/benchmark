using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed class BlockRecord {
    public readonly Block block;
    public readonly BlockRecord parent;
    public readonly Dictionary<Reference, Coin> utxo;
    public readonly List<int> transactionFees;
    public readonly string source;
    public readonly int fees, work;
    public BlockRecord(Block block, BlockRecord parent, Dictionary<Reference, Coin> utxo,
                       List<int> transactionFees, string source) {
        this.block = block;
        this.parent = parent;
        this.utxo = utxo;
        this.transactionFees = transactionFees;
        this.source = source;
        fees = transactionFees.Sum();
        work = parent == null ? 1 : parent.work + (1 << (4 * block.difficulty));
    }
}

static class Chain {
    public static int Reward(int height, int initial, int interval) {
        for (int i = 0; i < height / interval; i++)
            initial /= 2;
        return initial;
    }
    public static BlockRecord Ancestor(BlockRecord record, int height) {
        while (record.block.height > height)
            record = record.parent;
        return record;
    }
    public static List<BlockRecord> Sequence(BlockRecord record) {
        List<BlockRecord> records = new();
        while (record != null) {
            records.Add(record);
            record = record.parent;
        }
        records.Reverse();
        return records;
    }
    public static BlockRecord Fork(BlockRecord first, BlockRecord second) {
        int height = Math.Min(first.block.height, second.block.height);
        first = Ancestor(first, height);
        second = Ancestor(second, height);
        while (first != second) {
            first = first.parent;
            second = second.parent;
        }
        return first;
    }
    public static int Median(BlockRecord record) {
        List<int> times = new();
        while (record != null && times.Count < 3) {
            times.Add(record.block.timestamp);
            record = record.parent;
        }
        times.Sort();
        return times[(times.Count - 1) / 2];
    }
    public static int Difficulty(BlockRecord parent, int initial, int interval, int target) {
        int height = parent.block.height + 1, difficulty = parent.block.difficulty;
        if (height == 1)
            return initial;
        if (height % interval != 0)
            return difficulty;
        int span = parent.block.timestamp - Ancestor(parent, height - interval).block.timestamp,
            expected = target * (interval - 1);
        if (2 * span < expected)
            return Math.Min(difficulty + 1, 2);
        return span > 2 * expected ? Math.Max(difficulty - 1, 0) : difficulty;
    }
}
