struct Coalition {
    let mask: Int, members: [Int], welfare: Int, chosen: [Int]
}
struct Blocking {
    let index: Int, payoff: Int, deficit: Int, minimal: Bool
}
enum Payments {
    static func critical(_ bid: Bid, _ order: [Bid], _ reserve: Int) -> (Int, Int?) {
        let selected = Solver.greedy(order.filter {
            $0.id != bid.id
        })
        guard let rival = selected.first(where: {
            bid.bundle & $0.bundle != 0 || bid.xor && bid.bidder == $0.bidder
        }) else {
            return (reserve, nil)
        }
        func before(_ amount: Int) -> Bool {
            let a = amount * amount * rival.bundle.nonzeroBitCount, b = rival.amount * rival.amount * bid.bundle.nonzeroBitCount
            return a > b || a == b && bid.id < rival.id
        }
        var low = 1, high = 1
        while !before(high) {
            high *= 2
        }
        while low < high {
            let middle = (low + high) / 2
            if before(middle) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return (max(reserve, low), rival.id)
    }
    static func vcg(_ bidder: Int, _ bids: [Bid], _ reserves: [Int], _ offered: Int, _ welfare: Int, _ value: Int) -> (Int, Int, [Int]) {
        let result = Solver.solve(bids.filter {
            $0.bidder != bidder
        }, reserves, offered)
        return (result.welfare - (welfare - value), result.welfare, result.chosen)
    }
    static func coalitions(_ n: Int, _ bids: [Bid], _ reserves: [Int], _ offered: Int) -> [Coalition] {
        let sets = (0..<(1 << n)).map {
            mask in (0..<n).filter {
                mask & (1 << $0) != 0
            }
        }.sorted {
            $0.count == $1.count ? $0.lexicographicallyPrecedes($1) : $0.count < $1.count
        }
        return sets.map {
            members in
            let mask = members.reduce(0) {
                $0 | (1 << $1)
            }
            let result = Solver.solve(bids.filter {
                mask & (1 << $0.bidder) != 0
            }, reserves, offered)
            return Coalition(mask: mask, members: members, welfare: result.welfare, chosen: result.chosen)
        }
    }
    static func blocking(_ coalitions: [Coalition], _ seller: Int, _ utilities: [Int]) -> [Blocking] {
        var result: [Blocking] = []
        for (index, coalition) in coalitions.enumerated() {
            let payoff = seller + coalition.members.reduce(0) {
                $0 + utilities[$1]
            }
            if coalition.welfare > payoff {
                let minimal = !result.contains {
                    coalitions[$0.index].mask & coalition.mask == coalitions[$0.index].mask
                }
                result.append(Blocking(index: index, payoff: payoff, deficit: coalition.welfare - payoff, minimal: minimal))
            }
        }
        return result
    }
    static func gspPrice(_ rank: Int, _ ranking: [Int], _ bids: [Int]) -> Int {
        rank + 1 < ranking.count ? bids[ranking[rank + 1]] : 0
    }
    static func adVCG(_ rank: Int, _ ranking: [Int], _ values: [Int], _ ctr: [Fraction]) -> Fraction {
        var payment = Fraction(0)
        for t in (rank + 1)..<min(ranking.count, ctr.count + 1) {
            let next = t < ctr.count ? ctr[t] : Fraction(0)
            payment = payment + Fraction(values[ranking[t]]) * (ctr[t - 1] - next)
        }
        return payment
    }
}
