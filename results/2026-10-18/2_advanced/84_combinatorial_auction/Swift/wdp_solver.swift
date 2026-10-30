struct Search {
    var welfare = 0
    var chosen: [Int] = []
    var nodes = 0, pruned = 0, leaves = 0
    var improvements: [(Int, Int, [Int])] = []
    var shares: [(Int, Fraction, Int?)] = []
    var bound = Fraction(0)
}
final class Solver {
    let bids: [Bid], reserves: [Int], offered: Int
    var result = Search()
    var incumbent = false
    init(_ bids: [Bid], _ reserves: [Int], _ offered: Int) {
        self.bids = bids;
        self.reserves = reserves;
        self.offered = offered
    }
    func usable(_ decided: Int, _ winners: Int) -> [Bid] {
        bids.filter {
            $0.bundle & decided == 0 && (!$0.xor || winners & (1 << $0.bidder) == 0)
        }
    }
    func bound(_ decided: Int, _ welfare: Int, _ usable: [Bid]) -> (Fraction, [(Int, Fraction, Int?)]) {
        var bound = Fraction(welfare), shares: [(Int, Fraction, Int?)] = []
        for i in reserves.indices where offered & (1 << i) != 0 && decided & (1 << i) == 0 {
            var share = Fraction(reserves[i]), source: Int?
            for bid in usable where bid.bundle & (1 << i) != 0 {
                let fraction = Fraction(bid.amount, bid.bundle.nonzeroBitCount)
                if fraction > share {
                    share = fraction;
                    source = bid.id
                }
            }
            bound = bound + share
            shares.append((i, share, source))
        }
        return (bound, shares)
    }
    func visit(_ decided: Int, _ winners: Int, _ welfare: Int, _ chosen: [Int]) {
        result.nodes += 1
        if decided == offered {
            result.leaves += 1
            let chosen = chosen.sorted()
            if !incumbent || welfare > result.welfare || welfare == result.welfare && chosen.lexicographicallyPrecedes(result.chosen) {
                incumbent = true
                result.welfare = welfare
                result.chosen = chosen
                result.improvements.append((result.nodes, welfare, chosen))
            }
            return
        }
        let usable = self.usable(decided, winners)
        if incumbent && bound(decided, welfare, usable).0 < Fraction(result.welfare) {
            result.pruned += 1;
            return
        }
        let item = reserves.indices.first {
            offered & (1 << $0) != 0 && decided & (1 << $0) == 0
        }!
        for bid in usable where bid.bundle & (1 << item) != 0 {
            visit(decided | bid.bundle, bid.xor ? winners | (1 << bid.bidder) : winners, welfare + bid.amount, chosen + [bid.id])
        }
        visit(decided | (1 << item), winners, welfare + reserves[item], chosen)
    }
    static func solve(_ bids: [Bid], _ reserves: [Int], _ offered: Int) -> Search {
        let solver = Solver(bids, reserves, offered)
        let (bound, shares) = solver.bound(0, 0, solver.usable(0, 0))
        solver.result.bound = bound
        solver.result.shares = shares
        solver.visit(0, 0, 0, [])
        return solver.result
    }
    static func greedyOrder(_ bids: [Bid]) -> [Bid] {
        bids.sorted {
            let a = $0.amount * $0.amount * $1.bundle.nonzeroBitCount, b = $1.amount * $1.amount * $0.bundle.nonzeroBitCount
            return a == b ? $0.id < $1.id : a > b
        }
    }
    static func greedy(_ bids: [Bid]) -> [Bid] {
        var used = 0, owners = 0, selected: [Bid] = []
        for bid in bids where used & bid.bundle == 0 && (!bid.xor || owners & (1 << bid.bidder) == 0) {
            used |= bid.bundle
            if bid.xor {
                owners |= 1 << bid.bidder
            }
            selected.append(bid)
        }
        return selected
    }
}
