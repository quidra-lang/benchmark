import Foundation
struct Reference: Hashable, Comparable {
    let txid: String;
    let index: Int
    static func <(a: Self, b: Self) -> Bool {
        a.txid != b.txid ? a.txid<b.txid : a.index<b.index
    }
    var text: String {
        "\(txid):\(index)"
    }
}
struct Coin {
    let address: String;
    let amount: Int;
    let height: Int;
    let coinbase: Bool
    func mature(_ h: Int, _ maturity: Int) -> Bool {
        !coinbase || height == 0 || h >= height+maturity
    }
}
typealias Utxo = [Reference: Coin]
struct Output {
    let address: String;
    let amount: Int;
    var text: String {
        "\(address):\(amount)"
    }
}
struct Transaction {
    let text: String;
    let txid: String;
    let inputs: [Reference];
    let outputs: [Output];
    let signatures: [String];
    let coinbaseHeight: Int?
    var size: Int {
        text.utf8.count
    }
    var coinbase: Bool {
        coinbaseHeight != nil
    }
    var body: String {
        String(text.components(separatedBy: ";sig=")[0])
    }
    var total: Int {
        outputs.reduce(0) {
            $0+$1.amount
        }
    }
    init(_ text: String) {
        self.text = text;
        txid = digest(text)
        let parts = text.components(separatedBy: ";")
        outputs = parts[1].dropFirst(4).split(separator: ",").map {
            let p = $0.split(separator: ":");
            return Output(address: String(p[0]), amount: Int(p[1])!)
        }
        coinbaseHeight = parts[0].hasPrefix("cb=") ? Int(parts[0].dropFirst(3))! : nil
        inputs = coinbaseHeight != nil ? [] : parts[0].dropFirst(3).split(separator: ",").map {
            let p = $0.split(separator: ":");
            return Reference(txid: String(p[0]), index: Int(p[1])!)
        }
        signatures = coinbaseHeight != nil ? [] : parts[2].dropFirst(4).split(separator: ",").map(String.init)
    }
}
func createTransaction(_ inputs: [Reference], _ outputs: [Output], _ secret: String) -> Transaction {
    let body = "in="+inputs.map(\.text).joined(separator: ",")+";out="+outputs.map(\.text).joined(separator: ",")
    return Transaction(body+";sig="+inputs.indices.map {
        sign(secret, $0, body)
    }.joined(separator: ","))
}
func createCoinbase(_ h: Int, _ outputs: [Output]) -> Transaction {
    Transaction("cb=\(h);out="+outputs.map(\.text).joined(separator: ","))
}
func checkTransaction(_ tx: Transaction, _ utxo: Utxo, _ spent: Set<Reference>, _ h: Int, _ owners: [String: Wallet], _ maturity: Int) -> (String?, Int) {
    if tx.outputs.contains(where: {
        owners[$0.address] == nil || $0.amount == 0
    }) {
        return ("bad-output", 0)
    }
    var seen = Set<Reference>(), total = 0
    for (i, r) in tx.inputs.enumerated() {
        if spent.contains(r) || seen.contains(r) {
            return ("double-spend", 0)
        }
        guard let c = utxo[r] else {
            return ("missing-input", 0)
        }
        if !c.mature(h, maturity) {
            return ("immature", 0)
        }
        if tx.signatures[i] != sign(owners[c.address]!.secret, i, tx.body) {
            return ("bad-sig", 0)
        }
        seen.insert(r);
        total += c.amount
    }
    return total<tx.total ? ("overspend", 0) : (nil, total-tx.total)
}
func apply(_ utxo: inout Utxo, _ tx: Transaction, _ h: Int) {
    for r in tx.inputs {
        utxo.removeValue(forKey: r)
    }
    for (i, o) in tx.outputs.enumerated() {
        utxo[Reference(txid: tx.txid, index: i)] = Coin(address: o.address, amount: o.amount, height: h, coinbase: tx.coinbase)
    }
}
