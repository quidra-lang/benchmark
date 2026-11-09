import Foundation
struct Block {
    let height: Int;
    let previous: String;
    let merkle: String;
    let timestamp: Int;
    let difficulty: Int;
    let nonce: Int;
    let transactions: [Transaction];
    let hash: String
    init(_ height: Int, _ previous: String, _ merkle: String, _ timestamp: Int, _ difficulty: Int, _ nonce: Int, _ transactions: [Transaction]) {
        self.height = height;
        self.previous = previous;
        self.merkle = merkle;
        self.timestamp = timestamp;
        self.difficulty = difficulty;
        self.nonce = nonce;
        self.transactions = transactions
        hash = digest("\(height)|\(previous)|\(merkle)|\(timestamp)|\(difficulty)|\(nonce)")
    }
    var size: Int {
        transactions.dropFirst().reduce(0) {
            $0+$1.size
        }
    }
    var txids: [String] {
        transactions.map(\.txid)
    }
    func contextError(_ maxSize: Int) -> String? {
        if !hash.hasPrefix(String(repeating: "0", count: difficulty)) {
            return "bad-pow"
        }
        if merkleRoot(txids) != merkle {
            return "bad-merkle"
        }
        if transactions[0].coinbaseHeight != height || transactions.dropFirst().contains(where: {
            $0.coinbase
        }) {
            return "bad-structure"
        }
        return size>maxSize ? "too-large" : nil
    }
    static func parse(_ f: [String], _ texts: [String]) -> Block {
        Block(Int(f[3])!, f[4], f[5], Int(f[6])!, Int(f[7])!, Int(f[8])!, texts.map(Transaction.init))
    }
}
func mineBlock(_ h: Int, _ previous: String, _ txs: [Transaction], _ timestamp: Int, _ difficulty: Int) -> Block {
    let merkle = merkleRoot(txs.map(\.txid));
    var nonce = 0
    while true {
        let b = Block(h, previous, merkle, timestamp, difficulty, nonce, txs);
        if b.hash.hasPrefix(String(repeating: "0", count: difficulty)) {
            return b
        };
        nonce += 1
    }
}
