import 'dart:math' as math;
import 'blocks.dart';
import 'transactions.dart';

class BlockRecord {
  final Block block;
  final BlockRecord? parent;
  final Utxo utxo;
  final List<int> transactionFees;
  final String source;
  final int fees, work;
  BlockRecord(
    this.block,
    this.parent,
    this.utxo,
    this.transactionFees,
    this.source,
  ) : fees = transactionFees.fold(0, (total, fee) => total + fee),
      work = parent == null ? 1 : parent.work + (1 << (4 * block.difficulty));
}

int reward(int height, int initial, int interval) {
  for (var i = 0; i < height ~/ interval; i++) {
    initial ~/= 2;
  }
  return initial;
}

BlockRecord ancestor(BlockRecord r, int height) {
  while (r.block.height > height) {
    r = r.parent!;
  }
  return r;
}

List<BlockRecord> chainTo(BlockRecord r) {
  final records = <BlockRecord>[];
  BlockRecord? current = r;
  while (current != null) {
    records.add(current);
    current = current.parent;
  }
  return records.reversed.toList();
}

BlockRecord forkPoint(BlockRecord a, BlockRecord b) {
  final h = math.min(a.block.height, b.block.height);
  a = ancestor(a, h);
  b = ancestor(b, h);
  while (!identical(a, b)) {
    a = a.parent!;
    b = b.parent!;
  }
  return a;
}

int medianTime(BlockRecord r) {
  final times = <int>[];
  BlockRecord? current = r;
  while (current != null && times.length < 3) {
    times.add(current.block.timestamp);
    current = current.parent;
  }
  times.sort();
  return times[(times.length - 1) ~/ 2];
}

int requiredDifficulty(
  BlockRecord parent,
  int initial,
  int interval,
  int target,
) {
  final height = parent.block.height + 1;
  final difficulty = parent.block.difficulty;
  if (height == 1) return initial;
  if (height % interval != 0) return difficulty;
  final span =
      parent.block.timestamp -
      ancestor(parent, height - interval).block.timestamp;
  final expected = target * (interval - 1);
  if (2 * span < expected) return math.min(difficulty + 1, 2);
  if (span > 2 * expected) return math.max(difficulty - 1, 0);
  return difficulty;
}
