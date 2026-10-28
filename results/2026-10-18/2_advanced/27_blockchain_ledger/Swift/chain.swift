import Foundation
final class BlockRecord {
    let block: Block;
    let parent: BlockRecord?;
    let utxo: Utxo;
    let transactionFees: [Int];
    let fees: Int;
    let source: String;
    let cumulativeWork: Int
    init(_ block: Block, _ parent: BlockRecord?, _ utxo: Utxo, _ fees: [Int], _ source: String) {
        self.block = block;
        self.parent = parent;
        self.utxo = utxo;
        transactionFees = fees;
        self.fees = fees.reduce(0, +);
        self.source = source;
        cumulativeWork = parent.map {
            $0.cumulativeWork+(0..<block.difficulty).reduce(1) {
                a, _ in a*16
            }
        } ?? 1
    }
}
func reward(_ height: Int, _ initial: Int, _ interval: Int) -> Int {
    var a = initial;
    for _ in 0..<(height/interval) {
        a /= 2
    };
    return a
}
func ancestor(_ record: BlockRecord, _ height: Int) -> BlockRecord {
    var r = record;
    while r.block.height>height {
        r = r.parent!
    };
    return r
}
func chainTo(_ record: BlockRecord) -> [BlockRecord] {
    var out = [BlockRecord]();
    var next: BlockRecord? = record;
    while let r = next {
        out.append(r);
        next = r.parent
    };
    return Array(out.reversed())
}
func forkPoint(_ first: BlockRecord, _ second: BlockRecord) -> BlockRecord {
    let h = min(first.block.height, second.block.height);
    var a = ancestor(first, h), b = ancestor(second, h);
    while a != = b {
        a = a.parent!;
        b = b.parent!
    };
    return a
}
func medianTime(_ record: BlockRecord) -> Int {
    var times = [Int]();
    var next: BlockRecord? = record;
    while let r = next {
        times.append(r.block.timestamp);
        if times.count == 3 {
            break
        };
        next = r.parent
    };
    times.sort();
    return times[(times.count-1)/2]
}
func requiredDifficulty(_ p: BlockRecord, _ initial: Int, _ interval: Int, _ target: Int) -> Int {
    let h = p.block.height+1, d = p.block.difficulty
    if h == 1 {
        return initial
    };
    if h%interval != 0 {
        return d
    }
    let span = p.block.timestamp-ancestor(p, h-interval).block.timestamp, expected = target*(interval-1)
    if 2*span<expected {
        return min(d+1, 2)
    };
    if span>2*expected {
        return max(d-1, 0)
    };
    return d
}
