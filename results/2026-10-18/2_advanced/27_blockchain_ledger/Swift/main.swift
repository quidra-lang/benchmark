import Foundation
struct Params {
    let values: [String: [String]]
    init() throws {
        values = Dictionary(uniqueKeysWithValues: try String(contentsOfFile: "input/params.txt", encoding: .utf8).split(separator: "\n").map {
            let p = $0.split(separator: " ").map(String.init); return(p[0], Array(p.dropFirst()))
        })
    }
    func get(_ k: String, _ i: Int = 0) -> Int {
        Int(values[k]![i])!
    }
}
final class Peer {
    var acceptedBlocks = 0,
    rejectedBlocks = 0,
    orphans = 0,
    acceptedTxs = 0,
    rejectedTxs = 0,
    ignored = 0,
    score = 0
}
struct Entry {
    let tx: Transaction;
    let fee: Int;
    let arrival: Int
}
struct Reorganization {
    let time: Int;
    let fork: Int;
    let disconnected: Int;
    let connected: Int;
    let old: String;
    let new: String
}
struct Acceptance {
    let reason: String?;
    let fee: Int;
    let conflicts: [String]
    init(_ reason: String? = nil, _ fee: Int = 0, _ conflicts: [String] = []) {
        self.reason = reason;
        self.fee = fee;
        self.conflicts = conflicts
    }
}
final class Node {
    let p: Params,
    wallets: [Wallet],
    owners: [String: Wallet],
    named: [String: Wallet]
    var now = 0,
    records = [String: BlockRecord](),
    main = [BlockRecord](),
    confirmed = [String: Int](),
    mempool = [Entry](),
    orphans = [(Block, String)](),
    rejected = Set<String>(),
    drops = [String: String](),
    peers = [String: Peer](),
    rejections = [String: Int](),
    reorganizations = [Reorganization](),
    log = [String]()
    var tip: BlockRecord
    init(_ p: Params, _ wallets: [Wallet]) {
        let byName = Dictionary(uniqueKeysWithValues: wallets.map {
            ($0.name, $0)
        })
        self.p = p;
        self.wallets = wallets;
        owners = Dictionary(uniqueKeysWithValues: wallets.map {
            ($0.address, $0)
        });
        named = byName
        let g = p.values["GENESIS"]!, outputs = stride(from: 0, to: g.count, by: 2).map {
            Output(address: byName[g[$0]]!.address, amount: Int(g[$0+1])!)
        }
        let cb = createCoinbase(0, outputs), b = Block(0, String(repeating: "0", count: 32), cb.txid, 0, 0, 0, [cb]);
        var utxo = Utxo();
        apply(&utxo, cb, 0)
        tip = BlockRecord(b, nil, utxo, [], "genesis");
        records[b.hash] = tip;
        refresh()
    }
    func refresh() {
        main = chainTo(tip);
        confirmed = [: ];
        for r in main {
            for tx in r.block.transactions {
                confirmed[tx.txid] = r.block.height
            }
        }
    }
    func writeLog(_ line: String) {
        log.append("\(now) \(line)")
    }
    func tally(_ c: String, _ r: String) {
        rejections[c+" "+r, default: 0] += 1
    }
    var height: Int {
        tip.block.height+1
    }
    func blockReward(_ h: Int) -> Int {
        reward(h, p.get("REWARD"), p.get("REWARD", 1))
    }
    func difficulty(_ r: BlockRecord) -> Int {
        requiredDifficulty(r, p.get("DIFFICULTY"), p.get("RETARGET"), p.get("RETARGET", 1))
    }
    var locked: Set<Reference> {
        Set(mempool.flatMap {
            $0.tx.inputs
        })
    }
    var ranked: [Entry] {
        mempool.sorted {
            let a = $0.fee * $1.tx.size, b = $1.fee * $0.tx.size;
            return a != b ? a>b : $0.tx.txid<$1.tx.txid
        }
    }
    func balance(_ a: String) -> Int {
        tip.utxo.values.filter {
            $0.address == a
        }.reduce(0) {
            $0+$1.amount
        }
    }
    func acceptance(_ tx: Transaction) -> Acceptance {
        if tx.coinbase {
            return Acceptance("coinbase")
        }
        if confirmed[tx.txid] != nil || mempool.contains(where: {
            $0.tx.txid == tx.txid
        }) {
            return Acceptance("duplicate")
        }
        let(reason, fee) = checkTransaction(tx, tip.utxo, [], height, owners, p.get("MATURITY"));
        if let r = reason {
            return Acceptance(r)
        }
        if fee*1000<p.get("MINFEERATE")*tx.size {
            return Acceptance("low-fee")
        }
        let inputs = Set(tx.inputs), conflicts = mempool.filter {
            !inputs.isDisjoint(with: $0.tx.inputs)
        }
        if !conflicts.isEmpty && (fee <= conflicts.reduce(0) {
            $0+$1.fee
        }
        || conflicts.contains(where: {
            fee * $0.tx.size <= $0.fee * tx.size
        })) {
            return Acceptance("conflict")
        }
        return Acceptance(nil, fee, conflicts.map {
            $0.tx.txid
        })
    }
    func drop(_ id: String, _ reason: String) {
        mempool.removeAll {
            $0.tx.txid == id
        };
        drops[id] = reason;
        writeLog("DROP \(short(id)) \(reason)")
    }
    func register(_ tx: Transaction, _ result: Acceptance, _ arrival: Int) {
        for id in result.conflicts {
            drop(id, "replaced")
        };
        mempool.append(Entry(tx: tx, fee: result.fee, arrival: arrival));
        if mempool.count>p.get("MEMPOOL") {
            drop(ranked.last!.tx.txid, "mempool-full")
        }
    }
    func switchTip(_ target: BlockRecord) {
        let old = tip, fork = forkPoint(tip, target), f = fork.block.height, d = old.block.height-f, c = target.block.height-f
        if d>p.get("MAXREORG") {
            writeLog("REFUSE \(target.block.height) \(short(target.block.hash)) work \(target.cumulativeWork) fork \(f) depth \(d)");
            return
        }
        let returned = main.dropFirst(f+1).flatMap {
            Array($0.block.transactions.dropFirst())
        };
        tip = target;
        refresh()
        if d == 0 {
            writeLog("TIP \(target.block.height) \(short(target.block.hash)) work \(target.cumulativeWork)")
        }else {
            writeLog("REORG \(target.block.height) \(short(target.block.hash)) work \(target.cumulativeWork) fork \(f) disconnected \(d) connected \(c)")
            reorganizations.append(Reorganization(time: now, fork: f, disconnected: d, connected: c, old: old.block.hash, new: target.block.hash))
        }
        let previous = mempool;
        mempool = []
        let candidates = returned.map {
            ($0, now, true)
        }
        +previous.map {
            ($0.tx, $0.arrival, false)
        }
        for(tx, arrival, isReturned)in candidates {
            if confirmed[tx.txid] != nil {
                continue
            };
            let a = acceptance(tx);
            if let r = a.reason {
                drop(tx.txid, r)
            }else {
                if isReturned {
                    writeLog("RETURN \(short(tx.txid))")
                };
                register(tx, a, arrival)
            }
        }
    }
    func penalize(_ name: String, _ points: Int) {
        let peer = peers[name]!, before = peer.score;
        peer.score += points;
        if before<p.get("BAN") && peer.score >= p.get("BAN") {
            writeLog("BAN \(name) score \(peer.score)")
        }
    }
    func pay(_ f: [String]) {
        let w = named[f[2]]!, fee = Int(f[3])!;
        var outputs = stride(from: 4, to: f.count, by: 2).map {
            Output(address: named[f[$0]]!.address, amount: Int(f[$0+1])!)
        }
        let total = outputs.reduce(0) {
            $0+$1.amount
        }, need = total+fee, prefix = "PAY \(w.name) fee \(fee) total \(total)", locks = locked
        let coins = tip.utxo.filter {
            $0.value.address == w.address && !locks.contains($0.key) && $0.value.mature(height, p.get("MATURITY"))
        }.sorted {
            a, b in a.value.amount != b.value.amount ? a.value.amount>b.value.amount : a.key<b.key
        }
        var inputs = [Reference](), gathered = 0
        for(r, c)in coins {
            if gathered >= need {
                break
            };
            inputs.append(r);
            gathered += c.amount
        }
        if gathered<need {
            writeLog(prefix+" rejected insufficient-funds");
            tally("pay", "insufficient-funds");
            return
        }
        if gathered>need {
            outputs.append(Output(address: w.address, amount: gathered-need))
        }
        let tx = createTransaction(inputs, outputs, w.secret), a = acceptance(tx)
        if let r = a.reason {
            writeLog("\(prefix) tx \(short(tx.txid)) rejected \(r)");
            tally("pay", r)
        }else {
            writeLog("\(prefix) tx \(short(tx.txid)) accepted inputs \(tx.inputs.count) outputs \(tx.outputs.count) size \(tx.size)");
            register(tx, a, now)
        }
    }
    func bump(_ id: String, _ fee: Int) {
        let prefix = "BUMP \(short(id)) fee \(fee)"
        guard let e = mempool.first(where: {
            $0.tx.txid == id
        })else {
            writeLog(prefix+" rejected unknown");
            tally("bump", "unknown");
            return
        }
        let last = e.tx.outputs.last!, change = last.amount-(fee-e.fee)
        if change<1 || e.tx.inputs.contains(where: {
            tip.utxo[$0]!.address != last.address
        }) {
            writeLog(prefix+" rejected no-change");
            tally("bump", "no-change");
            return
        }
        var outputs = e.tx.outputs;
        outputs[outputs.count-1] = Output(address: last.address, amount: change)
        let tx = createTransaction(e.tx.inputs, outputs, owners[last.address]!.secret), a = acceptance(tx)
        if let r = a.reason {
            writeLog("\(prefix) tx \(short(tx.txid)) rejected \(r)");
            tally("bump", r)
        }else {
            writeLog("\(prefix) tx \(short(tx.txid)) accepted size \(tx.size)");
            register(tx, a, now)
        }
    }
    func receiveTx(_ peer: String, _ tx: Transaction) {
        let a = acceptance(tx);
        if let r = a.reason {
            peers[peer]!.rejectedTxs += 1;
            tally("tx", r);
            writeLog("TX \(peer) \(short(tx.txid)) rejected \(r)");
            if ["coinbase", "bad-output", "bad-sig", "overspend"].contains(r) {
                penalize(peer, p.get("BAN", 2))
            }
        }else {
            peers[peer]!.acceptedTxs += 1;
            writeLog("TX \(peer) \(short(tx.txid)) accepted fee \(a.fee) size \(tx.size)");
            register(tx, a, now)
        }
    }
    func mine(_ name: String) {
        let h = height;
        var selected = [Entry](), size = 0
        for e in ranked {
            if size+e.tx.size <= p.get("MAXBLOCK") {
                selected.append(e);
                size += e.tx.size
            }
        }
        let fees = selected.map(\.fee), cb = createCoinbase(h, [Output(address: named[name]!.address, amount: blockReward(h)+fees.reduce(0, +))])
        let b = mineBlock(h, tip.block.hash, [cb]+selected.map(\.tx), max(now, medianTime(tip)+1), difficulty(tip));
        var utxo = tip.utxo
        for tx in b.transactions {
            apply(&utxo, tx, h)
        }
        let r = BlockRecord(b, tip, utxo, fees, "local");
        records[b.hash] = r
        writeLog("MINE \(name) \(h) \(short(b.hash)) bits \(b.difficulty) nonce \(b.nonce) txs \(b.transactions.count) size \(b.size) fees \(r.fees) work \(r.cumulativeWork)");
        switchTip(r)
    }
    func validate(_ b: Block, _ parent: BlockRecord) -> (String?, Utxo, [Int]) {
        if b.height != parent.block.height+1 {
            return("bad-height", [: ], [])
        }
        if b.difficulty != difficulty(parent) {
            return("bad-difficulty", [: ], [])
        }
        if b.timestamp <= medianTime(parent) {
            return("time-too-old", [: ], [])
        }
        if b.timestamp>now+p.get("DRIFT") {
            return("time-too-new", [: ], [])
        }
        var utxo = parent.utxo, spent = Set<Reference>(), fees = [Int]()
        for(i, tx)in b.transactions.enumerated().dropFirst() {
            let(reason, fee) = checkTransaction(tx, utxo, spent, b.height, owners, p.get("MATURITY"));
            if let reason = reason {
                return("\(reason) tx \(i+1)", [: ], [])
            };
            spent.formUnion(tx.inputs);
            apply(&utxo, tx, b.height);
            fees.append(fee)
        }
        let cb = b.transactions[0]
        if cb.outputs.contains(where: {
            owners[$0.address] == nil || $0.amount == 0
        }) {
            return("bad-output tx 1", [: ], [])
        }
        if cb.total>blockReward(b.height)+fees.reduce(0, +) {
            return("bad-coinbase", [: ], [])
        }
        apply(&utxo, cb, b.height);
        return(nil, utxo, fees)
    }
    func reject(_ kind: String, _ b: Block, _ peer: String, _ reason: String) {
        rejected.insert(b.hash);
        peers[peer]!.rejectedBlocks += 1;
        tally("block", String(reason.split(separator: " ")[0]));
        writeLog("\(kind) \(peer) \(b.height) \(short(b.hash)) rejected \(reason)");
        if reason != "time-too-new" {
            penalize(peer, p.get("BAN", 1))
        }
    }
    func connect(_ kind: String, _ b: Block, _ peer: String) {
        let parent = records[b.previous]!, (reason, utxo, fees) = validate(b, parent);
        if let reason = reason {
            reject(kind, b, peer, reason)
        }else {
            let r = BlockRecord(b, parent, utxo, fees, peer);
            records[b.hash] = r;
            peers[peer]!.acceptedBlocks += 1;
            writeLog("\(kind) \(peer) \(b.height) \(short(b.hash)) accepted work \(r.cumulativeWork)");
            if r.cumulativeWork>tip.cumulativeWork {
                switchTip(r)
            }
        }
    }
    func resolve(_ start: String) {
        var queue = [start], i = 0;
        while i<queue.count {
            let parent = queue[i];
            i += 1;
            let children = orphans.filter {
                $0.0.previous == parent
            };
            for(b, peer)in children {
                orphans.removeAll {
                    $0.0.hash == b.hash
                };
                if rejected.contains(parent) {
                    reject("UNORPHAN", b, peer, "bad-parent")
                }else {
                    connect("UNORPHAN", b, peer)
                };
                queue.append(b.hash)
            }
        }
    }
    func receiveBlock(_ peer: String, _ b: Block) {
        if records[b.hash] != nil || orphans.contains(where: {
            $0.0.hash == b.hash
        }) || rejected.contains(b.hash) {
            writeLog("BLOCK \(peer) \(b.height) \(short(b.hash)) rejected duplicate");
            peers[peer]!.rejectedBlocks += 1;
            tally("block", "duplicate");
            return
        }
        if let reason = b.contextError(p.get("MAXBLOCK")) ?? (rejected.contains(b.previous) ? "bad-parent" : nil) {
            reject("BLOCK", b, peer, reason);
            resolve(b.hash);
            return
        }
        if records[b.previous] == nil {
            orphans.append((b, peer));
            peers[peer]!.orphans += 1;
            writeLog("BLOCK \(peer) \(b.height) \(short(b.hash)) orphan parent \(short(b.previous))");
            if orphans.count>p.get("ORPHANS") {
                let old = orphans.removeFirst();
                writeLog("EVICT \(short(old.0.hash)) orphan-limit")
            };
            return
        }
        connect("BLOCK", b, peer);
        resolve(b.hash)
    }
    func status(_ id: String) {
        let prefix = "STATUS "+short(id);
        if let h = confirmed[id] {
            writeLog("\(prefix) confirmed \(h) confirmations \(height-h)");
            return
        };
        let order = ranked;
        if let i = order.firstIndex(where: {
            $0.tx.txid == id
        }) {
            writeLog("\(prefix) mempool rank \(i+1) of \(order.count)")
        }else if let r = drops[id] {
            writeLog("\(prefix) dropped \(r)")
        }else if records.values.contains(where: {
            $0.block.txids.contains(id)
        }) {
            writeLog(prefix+" stale")
        }else {
            writeLog(prefix+" unknown")
        }
    }
    func printState() {
        let order = ranked;
        writeLog("PRINT height \(tip.block.height) tip \(short(tip.block.hash)) work \(tip.cumulativeWork) bits \(difficulty(tip)) reward \(blockReward(height)) mempool \(order.count) size \(order.reduce(0){$0+$1.tx.size}) orphans \(orphans.count)");
        for(i, e)in order.enumerated() {
            writeLog("MEMPOOL \(i+1) \(short(e.tx.txid)) fee \(e.fee) size \(e.tx.size)")
        };
        for w in wallets {
            writeLog("BALANCE \(w.name) \(balance(w.address))")
        }
    }
    func process(_ f: [String], _ texts: [String]) {
        now = Int(f[0])!;
        for e in mempool {
            if now-e.arrival >= p.get("EXPIRY") {
                drop(e.tx.txid, "expired")
            }
        };
        switch f[1] {
            case "PAY": pay(f);
            case "BUMP": bump(f[2], Int(f[3])!);
            case "MINE": mine(f[2]);
            case "STATUS": status(f[2]);
            case "PRINT": printState();
            default: let peer = f[2], kind = f[1];
            if peers[peer] == nil {
                peers[peer] = Peer()
            };
            if peers[peer]!.score >= p.get("BAN") {
                peers[peer]!.ignored += 1;
                writeLog("IGNORE \(peer) \(kind)")
            }else if kind == "TX" {
                receiveTx(peer, Transaction(f[3]))
            }else {
                receiveBlock(peer, Block.parse(f, texts))
            }
        }
    }
    func miner(_ r: BlockRecord) -> String {
        owners[r.block.transactions[0].outputs[0].address]!.name
    }
    func chainLines() -> [String] {
        var lines = ["TIP \(tip.block.height) \(tip.block.hash) work \(tip.cumulativeWork) stored \(records.count) orphans \(orphans.count)"]
        for r in main {
            let b = r.block, m = b.height == 0 ? "-" : miner(r);
            lines.append("BLOCK \(b.height) \(b.hash) prev \(short(b.previous)) time \(b.timestamp) bits \(b.difficulty) nonce \(b.nonce) txs \(b.transactions.count) size \(b.size) fees \(r.fees) miner \(m) source \(r.source) work \(r.cumulativeWork)")
            for(i, tx)in b.transactions.enumerated() {
                if tx.coinbase {
                    let category = b.height == 0 ? "genesis" : "coinbase";
                    lines.append("TX \(i+1) \(tx.txid) \(category) out \(tx.outputs.count) amount \(tx.total)")
                }else {
                    lines.append("TX \(i+1) \(tx.txid) payment in \(tx.inputs.count) out \(tx.outputs.count) size \(tx.size) fee \(r.transactionFees[i-1])")
                }
            }
        }
        let hashes = Set(main.map {
            $0.block.hash
        }), stale = records.values.filter {
            !hashes.contains($0.block.hash)
        }.sorted {
            a, b in a.block.height != b.block.height ? a.block.height<b.block.height : a.block.hash<b.block.hash
        }
        for r in stale {
            lines.append("STALE \(r.block.height) \(r.block.hash) prev \(short(r.block.previous)) source \(r.source) work \(r.cumulativeWork)")
        }
        for(b, peer)in orphans {
            lines.append("ORPHAN \(b.height) \(b.hash) prev \(short(b.previous)) source \(peer)")
        }
        for r in reorganizations {
            lines.append("REORG \(r.time) fork \(r.fork) disconnected \(r.disconnected) connected \(r.connected) old \(short(r.old)) new \(short(r.new))")
        }
        for w in wallets {
            let own = main.dropFirst().filter {
                miner($0) == w.name
            };
            if !own.isEmpty {
                lines.append("MINER \(w.name) blocks \(own.count) coinbase \(own.reduce(0){$0+$1.block.transactions[0].total}) fees \(own.reduce(0){$0+$1.fees})")
            }
        }
        var i = 1;
        while i<main.count {
            let d = main[i].block.difficulty, start = i;
            while i+1<main.count && main[i+1].block.difficulty == d {
                i += 1
            };
            lines.append("BITS \(d) heights \(start)-\(i) blocks \(i-start+1)");
            i += 1
        }
        for name in peers.keys.sorted() {
            let q = peers[name]!, state = q.score >= p.get("BAN") ? "banned" : "ok";
            lines.append("PEER \(name) blocks \(q.acceptedBlocks) rejected \(q.rejectedBlocks) orphans \(q.orphans) txs \(q.acceptedTxs) rejected \(q.rejectedTxs) ignored \(q.ignored) score \(q.score) \(state)")
        }
        for(i, e)in ranked.enumerated() {
            lines.append("MEMPOOL \(i+1) \(e.tx.txid) fee \(e.fee) size \(e.tx.size) time \(e.arrival)")
        }
        for key in rejections.keys.sorted() {
            lines.append("REJECT \(key) \(rejections[key]!)")
        }
        let genesis = main[0].block.transactions[0].total, rewards = main.dropFirst().reduce(0) {
            $0+blockReward($1.block.height)
        }, fees = main.dropFirst().reduce(0) {
            $0+$1.fees
        }, minted = main.dropFirst().reduce(0) {
            $0+$1.block.transactions[0].total
        }
        lines.append("SUPPLY genesis \(genesis) rewards \(rewards) fees \(fees) burned \(rewards+fees-minted) utxo \(tip.utxo.values.reduce(0){$0+$1.amount})");
        return lines
    }
    func balanceLines() -> [String] {
        let locks = locked;
        var lines = ["wallet,address,balance,immature,locked,incoming,utxos"];
        for w in wallets {
            let coins = tip.utxo.filter {
                $0.value.address == w.address
            }, immature = coins.values.filter {
                !$0.mature(height, p.get("MATURITY"))
            }.reduce(0) {
                $0+$1.amount
            }, amount = coins.filter {
                locks.contains($0.key)
            }.values.reduce(0) {
                $0+$1.amount
            }, incoming = mempool.flatMap {
                $0.tx.outputs
            }.filter {
                $0.address == w.address
            }.reduce(0) {
                $0+$1.amount
            };
            lines.append("\(w.name),\(w.address),\(balance(w.address)),\(immature),\(amount),\(incoming),\(coins.count)")
        };
        return lines
    }
    func utxoLines() -> [String] {
        let locks = locked;
        var lines = [String]();
        for r in tip.utxo.keys.sorted() {
            let c = tip.utxo[r]!, category = c.height == 0 ? "genesis" : c.coinbase ? "coinbase" : "payment", state = !c.mature(height, p.get("MATURITY")) ? "immature" : locks.contains(r) ? "locked" : "free";
            lines.append("\(r.text) \(owners[c.address]!.name) \(c.amount) height \(c.height) \(category) \(state)")
        };
        let root = merkleRoot(lines.map(digest));
        lines.append("TOTAL \(tip.utxo.count) \(tip.utxo.values.reduce(0){$0+$1.amount})");
        lines.append("ROOT \(root)");
        return lines
    }
    func historyLines() -> [String] {
        var txs = [String: Transaction]();
        for r in main {
            for tx in r.block.transactions {
                txs[tx.txid] = tx
            }
        };
        var lines = [String]()
        for w in wallets {
            lines.append("WALLET \(w.name) \(w.address)");
            var count = 0, spentTotal = 0, receivedTotal = 0, balance = 0
            for r in main {
                for tx in r.block.transactions {
                    var spent = 0, received = 0, involved = false;
                    for ref in tx.inputs {
                        let o = txs[ref.txid]!.outputs[ref.index];
                        if o.address == w.address {
                            spent += o.amount;
                            involved = true
                        }
                    };
                    for o in tx.outputs {
                        if o.address == w.address {
                            received += o.amount;
                            involved = true
                        }
                    };
                    if !involved {
                        continue
                    };
                    count += 1;
                    spentTotal += spent;
                    receivedTotal += received;
                    balance += received-spent;
                    let category = !tx.coinbase ? "payment" : r.block.height == 0 ? "genesis" : "coinbase", net = String(format: "%+d", received-spent);
                    lines.append("\(r.block.height) \(short(tx.txid)) \(category) spent \(spent) received \(received) net \(net) balance \(balance)")
                }
            }
            var pending = 0;
            for e in ranked {
                let spent = e.tx.inputs.map {
                    tip.utxo[$0]!
                }.filter {
                    $0.address == w.address
                }.reduce(0) {
                    $0+$1.amount
                }, received = e.tx.outputs.filter {
                    $0.address == w.address
                }.reduce(0) {
                    $0+$1.amount
                };
                if spent != 0 || received != 0 {
                    pending += 1;
                    let net = String(format: "%+d", received-spent);
                    lines.append("pending \(short(e.tx.txid)) spent \(spent) received \(received) net \(net)")
                }
            };
            lines.append("END \(w.name) txs \(count) spent \(spentTotal) received \(receivedTotal) balance \(balance) pending \(pending)")
        };
        return lines
    }
}
func writeLines(_ name: String, _ lines: [String]) throws {
    try (lines.isEmpty ? "" : lines.joined(separator: "\n")+"\n").write(toFile: "output/"+name, atomically: true, encoding: .utf8)
}
let node = Node(try Params(), try readWallets()), events = try String(contentsOfFile: "input/events.txt", encoding: .utf8).split(separator: "\n").map(String.init)
var position = 0
while position<events.count {
    let f = events[position].split(separator: " ").map(String.init), n = f[1] == "BLOCK" ? Int(f[9])! : 0;
    node.process(f, Array(events[(position+1)..<(position+1+n)]));
    position += n+1
}
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
try writeLines("log.txt", node.log)
try writeLines("chain.txt", node.chainLines())
try writeLines("balances.csv", node.balanceLines())
try writeLines("utxo.txt", node.utxoLines())
try writeLines("history.txt", node.historyLines())
