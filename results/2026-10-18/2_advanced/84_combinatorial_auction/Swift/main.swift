import Foundation
typealias F = Fraction
struct Bidder {
    let name: String, xor: Bool;
    var bids: [Bid] = []
}
struct Validated {
    let offered: Int
    var bidders: [Bidder] = [], valid: [Bid] = [], eligible: [Bid] = []
    var rejects: [(Int, String, String)] = []
    var total = 0
}
func reserve(_ mask: Int, _ input: Input) -> Int {
    input.reserves.indices.filter {
        mask & (1 << $0) != 0
    }.reduce(0) {
        $0 + input.reserves[$1]
    }
}
func validateBid(_ text: String, _ id: Int, _ owner: Int, _ xor: Bool, _ offered: Int, _ earlier: [Bid], _ input: Input) -> (Bid?, String?) {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    if parts.count != 2 {
        return (nil, "malformed bid")
    }
    let names = parts[0].split(separator: "+", omittingEmptySubsequences: false).map(String.init), value = parts[1]
    if names.contains(where: {
        $0.isEmpty || !$0.utf8.allSatisfy {
            (97...122).contains($0)
        }
    }) || value.isEmpty || value.count > 5 || !value.utf8.allSatisfy({
        (48...57).contains($0)
    }) || value.count > 1 && value.first == "0" {
        return (nil, "malformed bid")
    }
    var mask = 0
    for name in names {
        guard let i = input.names.firstIndex(of: name) else {
            return (nil, "unknown item \(name)")
        }
        if offered & (1 << i) == 0 {
            return (nil, "item not offered \(name)")
        }
        if mask & (1 << i) != 0 {
            return (nil, "duplicate item \(name)")
        }
        mask |= 1 << i
    }
    if names.count > input.params.bundle {
        return (nil, "bundle too large")
    }
    let amount = Int(value)!
    if amount == 0 {
        return (nil, "zero value")
    }
    if let bid = earlier.first(where: {
        $0.bundle == mask
    }) {
        return (nil, "duplicate bundle \(bid.id)")
    }
    if earlier.count >= input.params.bids {
        return (nil, "too many bids")
    }
    return (Bid(id: id, bidder: owner, bundle: mask, amount: amount, xor: xor), nil)
}
func validate(_ auction: Auction, _ input: Input) -> Validated {
    let offered = auction.offered.reduce(0) {
        $0 | (1 << input.names.firstIndex(of: $1)!)
    }
    var result = Validated(offered: offered), seen: Set<String> = []
    for line in auction.lines {
        let error: String?
        if !seen.insert(line.name).inserted {
            error = "duplicate bidder"
        }
        else if line.language != "XOR" && line.language != "OR" {
            error = "bad language \(line.language)"
        }
        else {
            error = nil
        }
        let owner = result.bidders.count
        var bidder = Bidder(name: line.name, xor: line.language == "XOR")
        for text in line.bids {
            result.total += 1
            let (bid, message) = error.map {
                (nil as Bid?, $0 as String?)
            } ?? validateBid(text, result.total, owner, bidder.xor, offered, bidder.bids, input)
            if let bid {
                if bid.amount >= reserve(bid.bundle, input) {
                    result.eligible.append(bid)
                }
                result.valid.append(bid)
                bidder.bids.append(bid)
            } else {
                result.rejects.append((result.total, line.name, message!))
            }
        }
        if error == nil {
            result.bidders.append(bidder)
        }
    }
    return result
}
struct Allocation {
    var accepted = 0, retained = 0, unsold = 0
    var values: [Int]
}
func allocation(_ ids: [Int], _ v: Validated, _ input: Input) -> Allocation {
    var result = Allocation(values: Array(repeating: 0, count: v.bidders.count)), used = 0
    for id in ids {
        let bid = v.valid.first {
            $0.id == id
        }!
        result.accepted += bid.amount
        used |= bid.bundle
        result.values[bid.bidder] += bid.amount
    }
    result.unsold = v.offered & ~used
    result.retained = reserve(result.unsold, input)
    return result
}
func unsold(_ mask: Int, _ input: Input) -> String {
    Report.bundle(mask, input.names).replacingOccurrences(of: "+", with: " ")
}
func coalitionName(_ members: [Int], _ v: Validated) -> String {
    members.isEmpty ? "-" : members.map {
        v.bidders[$0].name
    }.joined(separator: "+")
}
struct Ascending {
    var lines: [String] = [], payments: [Int], utilities: [Int]
    var revenue = 0, welfare = 0, retained = 0, rounds = 0
    var capped = false
    var exposed = 0, exposure = 0
}
func ascending(_ name: String, _ v: Validated, _ input: Input, _ optimum: Int) -> Ascending {
    let p = input.params, n = v.bidders.count
    let candidates = v.bidders.map {
        Auctions.candidates($0.bids, $0.xor)
    }
    var eligibility = candidates.map {
        $0.map {
            $0.bundle.nonzeroBitCount
        }.max() ?? 0
    }
    var prices = input.reserves, holders = Array<Int?>(repeating: nil, count: input.names.count)
    var bids = Array(repeating: 0, count: prices.count), roundsBid = bids, last = bids
    var result = Ascending(payments: Array(repeating: 0, count: n), utilities: Array(repeating: 0, count: n))
    result.lines.append("AUCTION \(name) increment \(p.increment)")
    var random = p.seed
    for round in 1...p.cap {
        result.rounds = round
        var new = Array(repeating: 0, count: n), activity = new
        for k in 0..<n {
            let held = holders.indices.filter {
                holders[$0] == k
            }.reduce(0) {
                $0 | (1 << $1)
            }
            var best: Candidate?, surplus = 0
            for candidate in candidates[k] where (candidate.bundle | held).nonzeroBitCount <= eligibility[k] {
                let asking = prices.indices.filter {
                    candidate.bundle & (1 << $0) != 0
                }.reduce(0) {
                    total, i in
                    total + prices[i] + (holders[i] != nil && holders[i] != k ? p.increment : 0)
                }
                if candidate.value - asking > surplus {
                    surplus = candidate.value - asking;
                    best = candidate
                }
            }
            if let best {
                new[k] = best.bundle & ~held;
                activity[k] = (best.bundle | held).nonzeroBitCount
            }
            else {
                activity[k] = held.nonzeroBitCount
            }
        }
        let demand = new.reduce(0) {
            $0 + $1.nonzeroBitCount
        }
        if demand == 0 {
            result.lines.append("ROUND \(round) none")
        }
        else {
            let requests = (0..<n).filter {
                new[$0] != 0
            }.map {
                "\(v.bidders[$0].name):\(Report.bundle(new[$0], input.names))"
            }.joined(separator: " ")
            result.lines.append("ROUND \(round) demand \(demand) \(requests)")
            for i in prices.indices where v.offered & (1 << i) != 0 {
                let applicants = (0..<n).filter {
                    new[$0] & (1 << i) != 0
                }
                if applicants.isEmpty {
                    continue
                }
                bids[i] += applicants.count
                roundsBid[i] += 1
                last[i] = round
                var q = 0
                if applicants.count > 1 {
                    random = 48271 * random % 2147483647;
                    q = random % applicants.count
                }
                if holders[i] != nil {
                    prices[i] += p.increment
                }
                holders[i] = applicants[q]
            }
            let standing = prices.indices.filter {
                v.offered & (1 << $0) != 0
            }.map {
                i in
                "\(input.names[i])=\(prices[i])@\(holders[i].map { v.bidders[$0].name } ?? "-")"
            }.joined(separator: " ")
            result.lines.append("STANDING \(standing)")
        }
        var edited: [String] = []
        for k in 0..<n where activity[k] < eligibility[k] {
            eligibility[k] = activity[k];
            edited.append("\(v.bidders[k].name)=\(eligibility[k])")
        }
        if !edited.isEmpty {
            result.lines.append("ELIGIBILITY " + edited.joined(separator: " "))
        }
        if demand == 0 {
            break
        }
        if round == p.cap {
            result.capped = true
        }
    }
    result.lines.append("END rounds \(result.rounds) \(result.capped ? "cap" : "quiet")")
    for i in prices.indices where v.offered & (1 << i) != 0 {
        if let k = holders[i] {
            result.lines.append("ITEM \(input.names[i]) price \(prices[i]) holder \(v.bidders[k].name) bids \(bids[i]) rounds \(roundsBid[i]) last \(last[i])")
        }
        else {
            result.retained += input.reserves[i];
            result.lines.append("ITEM \(input.names[i]) unsold reserve \(input.reserves[i])")
        }
    }
    result.welfare = result.retained
    for k in 0..<n {
        let won = prices.indices.filter {
            holders[$0] == k
        }.reduce(0) {
            $0 | (1 << $1)
        }
        result.payments[k] = prices.indices.filter {
            won & (1 << $0) != 0
        }.reduce(0) {
            $0 + prices[$1]
        }
        let value = Auctions.value(candidates[k], won)
        result.welfare += value
        result.utilities[k] = value - result.payments[k]
        if result.utilities[k] < 0 {
            result.exposed += 1;
            result.exposure -= result.utilities[k]
        }
        let exposed = result.utilities[k] < 0 ? " exposed" : ""
        result.lines.append("BIDDER \(v.bidders[k].name) won \(Report.bundle(won, input.names)) paid \(result.payments[k]) value \(value) utility \(result.utilities[k]) eligibility \(eligibility[k])\(exposed)")
    }
    result.revenue = result.payments.reduce(0, +)
    result.lines.append("TOTAL revenue \(result.revenue) welfare \(result.welfare) efficiency \(F(result.welfare, optimum)) exposure \(result.exposure) exposed \(result.exposed)")
    return result
}
final class Output {
    var wdp: [String] = [], vcg: [String] = [], core: [String] = [], ascending: [String] = [], single: [String] = []
    var summary = ["mechanism,revenue,welfare,efficiency"]
    var totals = Array(repeating: 0, count: 6), revenues = Array(repeating: 0, count: 5)
    var coreCounts = Array(repeating: 0, count: 6), saaCounts = Array(repeating: 0, count: 4), singleCounts = Array(repeating: 0, count: 6)
}
func runAuction(_ auction: Auction, _ input: Input, _ out: Output) {
    let v = validate(auction, input), optimum = Solver.solve(v.eligible, input.reserves, v.offered)
    let optimalAllocation = allocation(optimum.chosen, v, input)
    let a = optimalAllocation.accepted, r = optimalAllocation.retained, values = optimalAllocation.values
    let order = Solver.greedyOrder(v.eligible), greedy = Solver.greedy(order), greedyIDs = greedy.map(\.id).sorted()
    let greedyAllocation = allocation(greedyIDs, v, input)
    let ga = greedyAllocation.accepted, gr = greedyAllocation.retained, greedyValues = greedyAllocation.values, gw = ga + gr
    let critical = Dictionary(uniqueKeysWithValues: greedy.map {
        ($0.id, Payments.critical($0, order, reserve($0.bundle, input)))
    })
    let n = v.bidders.count
    var criticalPay = Array(repeating: 0, count: n)
    for bid in greedy {
        criticalPay[bid.bidder] += critical[bid.id]!.0
    }
    let criticalTotal = criticalPay.reduce(0, +), criticalUtility = (0..<n).map {
        greedyValues[$0] - criticalPay[$0]
    }
    let saa = ascending(auction.name, v, input, optimum.welfare)
    out.wdp.append("AUCTION \(auction.name) items \(v.offered.nonzeroBitCount) bidders \(n) bids \(v.total) valid \(v.valid.count) eligible \(v.eligible.count)")
    for (k, bidder) in v.bidders.enumerated() {
        out.wdp.append("BIDDER \(bidder.name) \(bidder.xor ? "XOR" : "OR") valid \(bidder.bids.count) eligible \(v.eligible.filter { $0.bidder == k }.count)")
    }
    for (id, name, message) in v.rejects {
        out.wdp.append("REJECT \(id) \(name) \(message)")
    }
    for bid in v.valid where bid.amount < reserve(bid.bundle, input) {
        out.wdp.append("BELOW_RESERVE \(bid.id) \(v.bidders[bid.bidder].name) value \(bid.amount) reserve \(reserve(bid.bundle, input))")
    }
    for (i, share, source) in optimum.shares {
        out.wdp.append("SHARE \(input.names[i]) \(share) \(source.map { "bid \($0)" } ?? "reserve")")
    }
    out.wdp.append("ROOT_BOUND \(optimum.bound)")
    for (node, welfare, ids) in optimum.improvements {
        out.wdp.append("IMPROVE \(node) welfare \(welfare) bids \(Report.numbers(ids))")
    }
    out.wdp.append("OPTIMAL welfare \(optimum.welfare) accepted \(a) retained \(r) winners \(optimum.chosen.count)")
    for id in optimum.chosen {
        let bid = v.valid.first {
            $0.id == id
        }!
        out.wdp.append("WIN \(id) \(v.bidders[bid.bidder].name) \(Report.bundle(bid.bundle, input.names)) \(bid.amount)")
    }
    out.wdp.append("UNSOLD \(unsold(optimalAllocation.unsold, input))")
    out.wdp.append("SEARCH nodes \(optimum.nodes) pruned \(optimum.pruned) leaves \(optimum.leaves) improvements \(optimum.improvements.count)")
    out.wdp.append("GREEDY_ORDER " + (order.isEmpty ? "-" : order.map {
        String($0.id)
    }.joined(separator: " ")))
    out.wdp.append("GREEDY welfare \(gw) accepted \(ga) retained \(gr) winners \(greedy.count) efficiency \(F(gw, optimum.welfare))")
    for id in greedyIDs {
        let bid = v.valid.first {
            $0.id == id
        }!, payment = critical[id]!
        out.wdp.append("GWIN \(id) \(v.bidders[bid.bidder].name) \(Report.bundle(bid.bundle, input.names)) \(bid.amount) critical \(payment.0) against \(payment.1.map(String.init) ?? "-")")
    }
    out.wdp.append("GUNSOLD \(unsold(greedyAllocation.unsold, input))")
    for i in input.names.indices where v.offered & (1 << i) != 0 {
        func owner(_ ids: [Int]) -> String {
            for id in ids {
                if let bid = v.valid.first(where: {
                    $0.id == id && $0.bundle & (1 << i) != 0
                }) {
                    return v.bidders[bid.bidder].name
                }
            }
            return "-"
        }
        out.wdp.append("ITEM \(input.names[i]) reserve \(input.reserves[i]) demand \(v.eligible.filter { $0.bundle & (1 << i) != 0 }.count) optimal \(owner(optimum.chosen)) greedy \(owner(greedyIDs))")
    }
    var vcgPay = Array(repeating: 0, count: n), vcgUtility = vcgPay
    out.vcg.append("AUCTION \(auction.name) welfare \(optimum.welfare)")
    for k in 0..<n {
        let ids = optimum.chosen.filter {
            id in v.valid.contains {
                $0.id == id && $0.bidder == k
            }
        }
        if ids.isEmpty {
            out.vcg.append("BIDDER \(v.bidders[k].name) lost");
            continue
        }
        let (payment, without, alternative) = Payments.vcg(k, v.eligible, input.reserves, v.offered, optimum.welfare, values[k])
        vcgPay[k] = payment
        vcgUtility[k] = values[k] - payment
        out.vcg.append("BIDDER \(v.bidders[k].name) won \(Report.numbers(ids)) value \(values[k]) without \(without) alternative \(Report.numbers(alternative)) payment \(payment) utility \(vcgUtility[k])")
    }
    let revenue = vcgPay.reduce(0, +)
    out.vcg.append("TOTAL revenue \(revenue) pay_as_bid \(a) retained \(r) seller \(revenue + r) bidders \(vcgUtility.reduce(0, +))")
    for k in 0..<n {
        out.vcg.append("PAYMENTS \(v.bidders[k].name) vcg \(vcgPay[k]) pay_as_bid \(values[k]) greedy \(greedyValues[k]) critical \(criticalPay[k]) saa \(saa.payments[k])")
    }
    for k in 0..<n {
        out.vcg.append("UTILITIES \(v.bidders[k].name) vcg \(vcgUtility[k]) critical \(criticalUtility[k]) saa \(saa.utilities[k])")
    }
    out.core.append("AUCTION \(auction.name) bidders \(n)")
    if n > input.params.core {
        out.coreCounts[1] += 1;
        out.core.append("SKIPPED")
    }
    else {
        out.coreCounts[0] += 1
        let coalitions = Payments.coalitions(n, v.eligible, input.reserves, v.offered)
        out.core.append("COALITIONS \(coalitions.count)")
        let outcomes = [("vcg", revenue + r, vcgUtility), ("greedy", gw, Array(repeating: 0, count: n)),
        ("critical", criticalTotal + gr, criticalUtility), ("saa", saa.revenue + saa.retained, saa.utilities)]
        for (k, outcome) in outcomes.enumerated() {
            let (name, seller, utilities) = outcome
            out.core.append("OUTCOME \(name) seller \(seller) utilities \(utilities.map(String.init).joined(separator: " "))")
            let blocking = Payments.blocking(coalitions, seller, utilities)
            for block in blocking where block.minimal {
                let coalition = coalitions[block.index]
                out.core.append("BLOCK \(coalitionName(coalition.members, v)) welfare \(coalition.welfare) payoff \(block.payoff) deficit \(block.deficit) bids \(Report.numbers(coalition.chosen))")
            }
            if blocking.isEmpty {
                out.coreCounts[k + 2] += 1;
                out.core.append("RESULT core")
            }
            else {
                let deficit = blocking.map(\.deficit).max()!, by = blocking.first {
                    $0.deficit == deficit
                }!
                out.core.append("RESULT blocked \(blocking.count) minimal \(blocking.filter(\.minimal).count) max_deficit \(deficit) by \(coalitionName(coalitions[by.index].members, v))")
            }
        }
    }
    out.ascending += saa.lines
    let mechanisms = [("vcg", revenue, optimum.welfare), ("pay_as_bid", a, optimum.welfare), ("greedy", ga, gw), ("critical", criticalTotal, gw), ("saa", saa.revenue, saa.welfare)]
    for (i, mechanism) in mechanisms.enumerated() {
        out.revenues[i] += mechanism.1
        out.summary.append("\(auction.name)/\(mechanism.0),\(mechanism.1),\(mechanism.2),\(F(mechanism.2, optimum.welfare))")
    }
    let totals = [1, v.total, v.valid.count, v.eligible.count, optimum.nodes, gw == optimum.welfare ? 1 : 0]
    for i in 0..<6 {
        out.totals[i] += totals[i]
    }
    out.saaCounts[0] += saa.rounds
    out.saaCounts[1] += saa.capped ? 1 : 0
    out.saaCounts[2] += saa.exposed
    out.saaCounts[3] += saa.exposure
}
func duplicate(_ group: Group) -> String? {
    var seen: Set<String> = []
    return group.people.first {
        !seen.insert($0.name).inserted
    }?.name
}
func lot(_ group: Group, _ input: Input, _ out: Output) {
    out.singleCounts[0] += 1
    let error: String?
    if group.people.isEmpty {
        error = "no bidders"
    }
    else if let name = duplicate(group) {
        error = "duplicate bidder \(name)"
    }
    else {
        error = group.people.first {
            $0.bid > $0.value
        }.map {
            "bid above value \($0.name)"
        }
    }
    if let error {
        out.singleCounts[2] += 1;
        out.single.append("LOT \(group.name) ERROR \(error)");
        return
    }
    let reserve = Int(group.args[0])!, values = group.people.map(\.value), bids = group.people.map(\.bid)
    func best(_ amounts: [Int]) -> Int? {
        amounts.indices.filter {
            amounts[$0] >= reserve
        }.min {
            amounts[$0] == amounts[$1] ? $0 < $1 : amounts[$0] > amounts[$1]
        }
    }
    let efficient = best(values), optimum = max(reserve, values.max()!)
    out.single.append("LOT \(group.name) reserve \(reserve) bidders \(group.people.count) efficient \(efficient.map { group.people[$0].name } ?? "-") optimum \(optimum)")
    let first = best(bids), firstPrice = first.map {
        bids[$0]
    } ?? 0
    let secondPrice = efficient.map {
        i in max(reserve, values.indices.filter {
            $0 != i
        }.map {
            values[$0]
        }.max() ?? 0)
    } ?? 0
    let (english, englishPrice, englishSteps, drops) = Auctions.english(values, reserve, input.params.english)
    let (dutch, dutchPrice, dutchSteps) = Auctions.dutch(bids, reserve, input.params.dutchStart, input.params.dutchDecrement)
    let results: [(Int?, Int, Int?)] = [(first, firstPrice, nil), (efficient, secondPrice, nil), (english, englishPrice, englishSteps), (dutch, dutchPrice, dutchSteps), (first, firstPrice, nil)]
    let labels = ["FIRST_PRICE", "SECOND_PRICE", "ENGLISH", "DUTCH", "ALL_PAY"], formats = ["first_price", "second_price", "english", "dutch", "all_pay"]
    var utilities = Array(repeating: Array(repeating: 0, count: 5), count: group.people.count), revenues: [Int] = []
    for (k, result) in results.enumerated() {
        let (winner, price, steps) = result
        if k == 4 {
            for i in bids.indices where bids[i] >= reserve {
                utilities[i][k] = -bids[i]
            }
        }
        if let winner {
            utilities[winner][k] = values[winner] - price
        }
        let revenue = k == 4 ? bids.filter {
            $0 >= reserve
        }.reduce(0, +) : price
        revenues.append(revenue)
        let welfare = winner.map {
            values[$0]
        } ?? reserve
        let notation = winner.map {
            "winner \(group.people[$0].name) price \(price) utility \(utilities[$0][k])"
        } ?? "unsold"
        out.single.append("\(labels[k]) \(notation)\(steps.map { " steps \($0)" } ?? "") revenue \(revenue) welfare \(welfare) efficiency \(F(welfare, optimum))")
        if k == 2 {
            out.single.append("ENGLISH_DROPS " + group.people.indices.map {
                "\(group.people[$0].name)=\(drops[$0].map(String.init) ?? "-")"
            }.joined(separator: " "))
        }
        out.summary.append("\(group.name)/\(formats[k]),\(revenue),\(welfare),\(F(welfare, optimum))")
    }
    for (i, person) in group.people.enumerated() {
        out.single.append("UTILITY \(person.name) " + utilities[i].map(String.init).joined(separator: " "))
    }
    let ranking = (0..<5).sorted {
        revenues[$0] == revenues[$1] ? $0 < $1 : revenues[$0] > revenues[$1]
    }
    out.single.append("RANKING " + ranking.map {
        formats[$0]
    }.joined(separator: " "))
}
func slots(_ group: Group, _ out: Output) {
    out.singleCounts[1] += 1
    var ctr: [F] = [], error: String?
    for text in group.args {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        let form = parts.count == 2 && parts.allSatisfy {
            !$0.isEmpty && $0.first != "0" && $0.utf8.allSatisfy {
                (48...57).contains($0)
            }
        }
        if !form {
            error = "bad ctr \(text)";
            break
        }
        let fraction = F(Int(parts[0])!, Int(parts[1])!)
        if fraction > F(1) || ctr.last.map({
            fraction >= $0
        }) == true {
            error = "bad ctr \(text)";
            break
        }
        ctr.append(fraction)
    }
    if error == nil {
        if group.people.isEmpty {
            error = "no advertisers"
        }
        else if let name = duplicate(group) {
            error = "duplicate advertiser \(name)"
        }
    }
    if let error {
        out.singleCounts[2] += 1;
        out.single.append("SLOTS \(group.name) ERROR \(error)");
        return
    }
    let n = group.people.count, k = ctr.count, values = group.people.map(\.value), bids = group.people.map(\.bid)
    let gsp = (0..<n).sorted {
        bids[$0] == bids[$1] ? $0 < $1 : bids[$0] > bids[$1]
    }
    let vcg = (0..<n).sorted {
        values[$0] == values[$1] ? $0 < $1 : values[$0] > values[$1]
    }
    func c(_ rank: Int) -> F {
        rank < k ? ctr[rank] : F(0)
    }
    func b(_ rank: Int) -> Int {
        rank < n ? bids[gsp[rank]] : 0
    }
    let optimum = (0..<min(n, k)).reduce(F(0)) {
        $0 + c($1) * F(values[vcg[$1]])
    }
    out.single.append("SLOTS \(group.name) slots \(k) advertisers \(n)")
    var gspRevenue = F(0), welfare = F(0), vcgRevenue = F(0)
    for s in 0..<min(n, k) {
        let i = gsp[s], price = Payments.gspPrice(s, gsp, bids), payment = c(s) * F(price), utility = c(s) * F(values[i] - price)
        gspRevenue = gspRevenue + payment
        welfare = welfare + c(s) * F(values[i])
        out.single.append("GSP \(s + 1) \(group.people[i].name) ctr \(c(s)) bid \(bids[i]) price \(price) payment \(payment) utility \(utility)")
    }
    out.single.append("GSP_TOTAL revenue \(gspRevenue) welfare \(welfare) efficiency \(welfare / optimum)")
    for s in 0..<min(n, k) {
        let i = vcg[s], payment = Payments.adVCG(s, vcg, values, ctr)
        vcgRevenue = vcgRevenue + payment
        out.single.append("VCG \(s + 1) \(group.people[i].name) ctr \(c(s)) value \(values[i]) payment \(payment) price \(payment / c(s)) utility \(c(s) * F(values[i]) - payment)")
    }
    out.single.append("VCG_TOTAL revenue \(vcgRevenue) welfare \(optimum) efficiency 1")
    var violations = 0
    for s in 1..<min(n, k + 1) {
        let i = gsp[s], stay = c(s) * F(values[i] - b(s + 1)), swap = c(s - 1) * F(values[i] - b(s))
        if stay < swap {
            violations += 1
        }
        out.single.append("ENVY \(s + 1) \(group.people[i].name) stay \(stay) swap \(swap) \(stay >= swap ? "ok" : "violated")")
    }
    if violations == 0 {
        out.singleCounts[3] += 1;
        out.single.append("ENVY_FREE yes")
    }
    else {
        out.single.append("ENVY_FREE no violations \(violations)")
    }
    var deviations = 0
    for s in 0..<n {
        let i = gsp[s], stay = c(s) * F(values[i] - b(s + 1))
        for t in 0..<k where t != s {
            let payoff = c(t) * F(values[i] - (t < s ? b(t) : b(t + 1)))
            if payoff > stay {
                deviations += 1;
                out.single.append("DEVIATE \(group.people[i].name) from \(s + 1) to \(t + 1) gain \(payoff - stay)")
            }
        }
    }
    if deviations == 0 {
        out.singleCounts[4] += 1;
        out.single.append("NASH yes")
    }
    else {
        out.single.append("NASH no deviations \(deviations)")
    }
    if violations == 0 && deviations == 0 {
        out.singleCounts[5] += 1;
        out.single.append("EQUILIBRIUM yes")
    }
    else {
        out.single.append("EQUILIBRIUM no")
    }
    out.summary.append("\(group.name)/gsp,\(gspRevenue),\(welfare),\(welfare / optimum)")
    out.summary.append("\(group.name)/vcg,\(vcgRevenue),\(optimum),1")
}
func runProgram() {
    let input = Input.read(), out = Output()
    for name in input.params.run {
        runAuction(input.auctions.first {
            $0.name == name
        }!, input, out)
    }
    for group in input.groups {
        if group.lot {
            lot(group, input, out)
        } else {
            slots(group, out)
        }
    }
    let t = out.totals, r = out.revenues, c = out.coreCounts, a = out.saaCounts, s = out.singleCounts
    out.wdp.append("TOTAL auctions \(t[0]) bids \(t[1]) valid \(t[2]) eligible \(t[3]) nodes \(t[4]) greedy_optimal \(t[5])")
    out.vcg.append("OVERALL vcg \(r[0]) pay_as_bid \(r[1]) greedy \(r[2]) critical \(r[3]) saa \(r[4])")
    out.core.append("SUMMARY checked \(c[0]) skipped \(c[1]) vcg \(c[2]) greedy \(c[3]) critical \(c[4]) saa \(c[5])")
    out.ascending.append("SUMMARY auctions \(input.params.run.count) rounds \(a[0]) capped \(a[1]) exposed \(a[2]) exposure \(a[3])")
    out.single.append("SUMMARY lots \(s[0]) slot_groups \(s[1]) errors \(s[2]) envy_free \(s[3]) nash \(s[4]) equilibria \(s[5])")
    Report.write("wdp.txt", out.wdp)
    Report.write("vcg.txt", out.vcg)
    Report.write("core_check.txt", out.core)
    Report.write("ascending_log.txt", out.ascending)
    Report.write("single_item.txt", out.single)
    Report.write("summary.csv", out.summary)
}
runProgram()
