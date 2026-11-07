struct Candidate {
    let bundle: Int, value: Int
}
enum Auctions {
    static func candidates(_ bids: [Bid], _ xor: Bool) -> [Candidate] {
        var result: [Candidate] = []
        for mask in 1..<(1 << bids.count) {
            if xor && mask.nonzeroBitCount != 1 {
                continue
            }
            var bundle = 0, value = 0, valid = true
            for (i, bid) in bids.enumerated() where mask & (1 << i) != 0 {
                if bundle & bid.bundle != 0 {
                    valid = false;
                    break
                }
                bundle |= bid.bundle
                value += bid.amount
            }
            if valid {
                result.append(Candidate(bundle: bundle, value: value))
            }
        }
        return result
    }
    static func value(_ candidates: [Candidate], _ bundle: Int) -> Int {
        candidates.filter {
            $0.bundle & bundle == $0.bundle
        }.map(\.value).max() ?? 0
    }
    static func english(_ values: [Int], _ reserve: Int, _ increment: Int) -> (Int?, Int, Int, [Int?]) {
        var price = reserve, steps = 0, drops = Array<Int?>(repeating: nil, count: values.count)
        while true {
            let remaining = values.indices.filter {
                values[$0] >= price
            }
            for i in values.indices where drops[i] == nil && values[i] < price {
                drops[i] = price
            }
            if remaining.count <= 1 {
                return (remaining.first, remaining.isEmpty ? 0 : price, steps, drops)
            }
            let old = price
            price += increment
            steps += 1
            let next = values.indices.filter {
                values[$0] >= price
            }
            for i in values.indices where drops[i] == nil && values[i] < price {
                drops[i] = price
            }
            if next.isEmpty {
                return (remaining[0], old, steps, drops)
            }
            if next.count == 1 {
                return (next[0], price, steps, drops)
            }
        }
    }
    static func dutch(_ bids: [Int], _ reserve: Int, _ start: Int, _ decrement: Int) -> (Int?, Int, Int) {
        var price = start, steps = 0
        while price >= reserve {
            if let winner = bids.indices.filter({
                bids[$0] >= price
            }).min(by: {
                bids[$0] == bids[$1] ? $0 < $1 : bids[$0] > bids[$1]
            }) {
                return (winner, price, steps)
            }
            price -= decrement
            steps += 1
        }
        return (nil, 0, steps)
    }
}
