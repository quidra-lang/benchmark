import 'hashing.dart';
import 'transactions.dart';

class Block {
  final int height, timestamp, difficulty, nonce;
  final String previous, merkle, hash;
  final List<Transaction> transactions;
  Block(
    this.height,
    this.previous,
    this.merkle,
    this.timestamp,
    this.difficulty,
    this.nonce,
    this.transactions,
  ) : hash = digest(
        headerText(height, previous, merkle, timestamp, difficulty, nonce),
      );
  int get size => transactions.skip(1).fold(0, (total, t) => total + t.size);
  List<String> get txids => transactions.map((t) => t.txid).toList();
}

String headerText(int h, String p, String root, int t, int d, int nonce) =>
    '$h|$p|$root|$t|$d|$nonce';
Block parseBlock(List<String> f, List<String> texts) => Block(
  int.parse(f[3]),
  f[4],
  f[5],
  int.parse(f[6]),
  int.parse(f[7]),
  int.parse(f[8]),
  texts.map(Transaction.new).toList(),
);
Block mineBlock(
  int h,
  String previous,
  List<Transaction> txs,
  int timestamp,
  int difficulty,
) {
  final root = merkleRoot(txs.map((t) => t.txid));
  final prefix = List.filled(difficulty, '0').join();
  for (var nonce = 0; ; nonce++) {
    final block = Block(h, previous, root, timestamp, difficulty, nonce, txs);
    if (block.hash.startsWith(prefix)) return block;
  }
}

String? contextFreeError(Block b, int maxSize) {
  if (!b.hash.startsWith(List.filled(b.difficulty, '0').join()))
    return 'bad-pow';
  if (merkleRoot(b.txids) != b.merkle) return 'bad-merkle';
  if (!b.transactions.first.coinbase ||
      b.transactions.first.coinbaseHeight != b.height ||
      b.transactions.skip(1).any((t) => t.coinbase))
    return 'bad-structure';
  if (b.size > maxSize) return 'too-large';
  return null;
}
