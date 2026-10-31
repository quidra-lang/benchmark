struct SessionKey: Hashable, Comparable {
    let asn: Int, link: Int
    static func < (a: Self, b: Self) -> Bool { a.asn == b.asn ? a.link < b.link : a.asn < b.asn }
}
struct PairKey: Hashable, Comparable {
    let asn: Int, prefix: Prefix
    static func < (a: Self, b: Self) -> Bool { a.asn == b.asn ? a.prefix < b.prefix : a.asn < b.asn }
}
final class Session { var incoming: [Prefix: Attribute] = [:], outgoing: [Prefix: Attribute] = [:], pending: Set<Prefix> = [], timer: Int?, sent = 0, received = 0 }
struct Counters { var convergence = 0, updates = 0, withdrawals = 0, drops = 0, changes = 0, exploration: [PairKey: Int] = [:] }
struct Forward { var result: String; var visits: [Int]; var hops: [(Int, Prefix, Int?)] }
final class TraceRecord {
    let trace: Int, start: Int, result: String, visits: [Int]
    var end: Int?
    init(_ trace: Int, _ start: Int, _ result: String, _ visits: [Int]) { self.trace = trace; self.start = start; self.result = result; self.visits = visits }
}
struct RingKey: Hashable { let prefix: Prefix; let cycle: [Int] }
final class RingRecord {
    let prefix: Prefix, start: Int, cycle: [Int]
    var end: Int?
    init(_ prefix: Prefix, _ start: Int, _ cycle: [Int]) { self.prefix = prefix; self.start = start; self.cycle = cycle }
}
struct BestLine { let time: Int, asn: Int, prefix: Prefix, route: Route? }
struct Divergence { let event: Int, first: Int, again: Int, lines: [BestLine] }
func valley(_ pattern: String) -> Int {
    let symbols = Array(pattern); var i = 0
    while i < symbols.count && symbols[i] == "U" { i += 1 }
    if i < symbols.count && symbols[i] == "P" { i += 1 }
    while i < symbols.count && symbols[i] == "D" { i += 1 }
    return i
}
final class BGP {
    let topology = Topology(), policy = Policy(), parameters = Parameters(), queue = MessageQueue()
    var sessions: [SessionKey: Session] = [:], origins: [Int: [Prefix: Route]] = [:], ribs: [Int: [Prefix: Route]] = [:], asChanges: [Int: Int] = [:], time = 0, logs: [String] = [], convergence = ["event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration"], counter = Counters(), changed: Set<Prefix> = [], bestLines: [BestLine] = [], traceRecords: [TraceRecord] = [], traceActive: [Int?] = [], ringRecords: [RingRecord] = [], ringActive: [RingKey: Int] = [:], divergences: [Divergence] = []
    init() {
        traceActive = Array(repeating: nil, count: parameters.traces.count)
        for x in topology.ases { origins[x] = [:]; ribs[x] = [:]; asChanges[x] = 0; for link in topology.sessions(x) { sessions[SessionKey(asn: x, link: link)] = Session() } }
    }
    func session(_ x: Int, _ link: Int) -> Session { sessions[SessionKey(asn: x, link: link)]! }
    func log(_ text: String) { logs.append("\(time) \(text)") }
    func importRoute(_ x: Int, _ link: Int, _ prefix: Prefix, _ attribute: Attribute) -> (Route?, Int?) {
        let rule = policy.applied(true, x, topology.links[link], prefix, attribute.path, attribute.communities)
        var route = Route(attribute: attribute, localPref: parameters.defaults[topology.links[link].role(x)], link: link)
        if let rule {
            for action in policy.rules[rule].actions { switch action { case .deny: return (nil, rule); case .local(let value): route.localPref = value; case .med(let value): route.attribute.med = value; default: break } }
            route.attribute.communities = policy.edit(rule, attribute.communities)
        }
        return (route, rule)
    }
    func candidates(_ x: Int, _ prefix: Prefix) -> [Route] { topology.sessions(x).compactMap { link in session(x, link).incoming[prefix].flatMap { importRoute(x, link, prefix, $0).0 } } }
    func decide(_ x: Int, _ prefix: Prefix) {
        let route: Route?
        if let local = origins[x]![prefix] { route = local }
        else { let candidates = candidates(x, prefix); route = candidates.isEmpty ? nil : Decision.best(candidates, topology).0 }
        if ribs[x]![prefix] == route { return }
        ribs[x]![prefix] = route; log("BEST \(x) \(prefix.text) \(Report.route(route, topology))")
        counter.changes += 1; counter.exploration[PairKey(asn: x, prefix: prefix), default: 0] += 1; asChanges[x, default: 0] += 1; changed.insert(prefix); bestLines.append(BestLine(time: time, asn: x, prefix: prefix, route: route))
        for link in topology.sessions(x) where topology.links[link].up { let s = session(x, link); s.pending.insert(prefix); if s.timer == nil { pending(x, link) } }
    }
    func advertised(_ x: Int, _ link: Int, _ prefix: Prefix) -> (Attribute?, Int?) {
        guard let route = ribs[x]![prefix] else { return (nil, nil) }
        let l = topology.links[link]
        if (route.link != nil && route.neighbor == l.other(x)) || route.attribute.communities.contains(Community("NO_EXPORT")) { return (nil, nil) }
        let rule = policy.applied(false, x, l, prefix, route.attribute.path, route.attribute.communities)
        var allow = false, prepend = 0, med = 0
        if let rule { for action in policy.rules[rule].actions { switch action { case .deny: return (nil, rule); case .allow: allow = true; case .prepend(let n): prepend = n; case .med(let n): med = n; default: break } } }
        if !allow && route.link.map({ topology.links[$0].role(x) != 0 }) == true && l.role(x) != 0 { return (nil, rule) }
        return (Attribute(path: Array(repeating: x, count: 1 + prepend) + route.attribute.path, origin: route.attribute.origin, med: med, communities: rule.map { policy.edit($0, route.attribute.communities) } ?? route.attribute.communities), rule)
    }
    func pending(_ x: Int, _ link: Int) {
        let s = session(x, link), l = topology.links[link]
        var sent = false
        for prefix in s.pending.sorted() {
            let (content, rule) = advertised(x, link, prefix)
            if s.outgoing[prefix] == content { continue }
            s.outgoing[prefix] = content
            let message = queue.send(time, l.delay, x, l.other(x), link, prefix, content)
            log("SEND #\(message.serial) \(x)->\(message.receiver) \(l.name) \(prefix.text) \(content.map { "ANNOUNCE " + Report.attribute($0) } ?? "WITHDRAW")")
            s.sent += 1; counter.updates += 1; if content == nil { counter.withdrawals += 1 }; if let rule { policy.rules[rule].hits += 1 }; sent = true
        }
        s.pending.removeAll(); s.timer = sent && l.mrai > 0 ? time + l.mrai : nil
    }
    func receive(_ message: Message) {
        let x = message.receiver, link = message.link, prefix = message.prefix, s = session(x, link)
        s.received += 1
        let result: String
        if let attribute = message.content {
            if attribute.path.contains(x) { s.incoming[prefix] = nil; result = "ANNOUNCE loop" }
            else {
                s.incoming[prefix] = attribute
                let (accepted, rule) = importRoute(x, link, prefix, attribute)
                if let rule { policy.rules[rule].hits += 1; result = "ANNOUNCE \(accepted == nil ? "deny" : "accept") \(policy.rules[rule].name)" }
                else { result = "ANNOUNCE accept" }
            }
        } else { s.incoming[prefix] = nil; result = "WITHDRAW" }
        log("RECV #\(message.serial) \(message.sender)->\(x) \(topology.links[link].name) \(prefix.text) \(result)"); decide(x, prefix)
    }
    func execute(_ number: Int, _ event: Event) {
        log("EVENT \(number) \(event.text)")
        let w = event.fields
        switch w[0] {
        case "INITIAL": for (x, prefix, origin, communities) in topology.initial { origins[x]![prefix] = .local(origin, communities); decide(x, prefix) }
        case "ANNOUNCE": let x = Int(w[1])!, prefix = Prefix(w[2]); origins[x]![prefix] = .local(w[3], Set(w.dropFirst(4).map(Community.init))); decide(x, prefix)
        case "WITHDRAW": let x = Int(w[1])!, prefix = Prefix(w[2]); origins[x]![prefix] = nil; decide(x, prefix)
        case "LINK":
            let link = topology.links.firstIndex { $0.name == w[2] }!, l = topology.links[link], endpoints = [l.a, l.b].sorted()
            l.up = w[1] == "UP"
            if !l.up {
                l.downs += 1
                for message in queue.remove(link) { counter.drops += 1; log("DROP #\(message.serial) \(message.sender)->\(message.receiver) \(l.name) \(message.prefix.text)") }
                var remembered: [(Int, [Prefix])] = []
                for x in endpoints { let s = session(x, link); remembered.append((x, s.incoming.keys.sorted())); s.incoming.removeAll(); s.outgoing.removeAll(); s.pending.removeAll(); s.timer = nil }
                for (x, prefixes) in remembered { for prefix in prefixes { decide(x, prefix) } }
            } else { for x in endpoints { session(x, link).pending = Set(ribs[x]!.keys); pending(x, link) } }
        default:
            let index = policy.rules.firstIndex { $0.name == w[2] }!, rule = policy.rules[index], x = rule.owner
            rule.on = w[1] == "ON"
            if rule.importing {
                let prefixes = Set(topology.sessions(x).flatMap { Array(session(x, $0).incoming.keys) })
                for prefix in prefixes.sorted() { decide(x, prefix) }
            } else {
                for link in topology.sessions(x) where topology.links[link].up { let s = session(x, link); s.pending.formUnion(ribs[x]!.keys); s.pending.formUnion(s.outgoing.keys); if s.timer == nil { pending(x, link) } }
            }
        }
    }
    func forward(_ source: Int, _ address: Int) -> Forward {
        var result = Forward(result: "UNREACHABLE", visits: [source], hops: []), x = source
        while true {
            guard let prefix = ribs[x]!.keys.filter({ $0.contains(address) }).max(by: { $0.length < $1.length }) else { result.result = result.hops.isEmpty ? "UNREACHABLE" : "BLACKHOLE"; return result }
            let route = ribs[x]![prefix]!
            result.hops.append((x, prefix, route.link))
            if let link = route.link { let next = topology.links[link].other(x), repeated = result.visits.contains(next); result.visits.append(next); if repeated { result.result = "LOOP"; return result }; x = next }
            else { result.result = "DELIVERED"; return result }
        }
    }
    func rings(_ prefix: Prefix) -> Set<[Int]> {
        var graph: [Int: Int] = [:], rings: Set<[Int]> = []
        for x in topology.ases { if let link = ribs[x]![prefix]?.link { graph[x] = topology.links[link].other(x) } }
        for start in graph.keys.sorted() {
            var path: [Int] = [], x = start
            while let next = graph[x] {
                if let index = path.firstIndex(of: x) { let cycle = Array(path[index...]), first = cycle.firstIndex(of: cycle.min()!)!; rings.insert(Array(cycle[first...]) + Array(cycle[..<first])); break }
                path.append(x); x = next
            }
        }
        return rings
    }
    func forwardingCheck() {
        for prefix in changed.sorted() {
            let rings = rings(prefix), ended = ringActive.keys.filter { $0.prefix == prefix && !rings.contains($0.cycle) }
            for key in ended { let id = ringActive.removeValue(forKey: key)!; ringRecords[id].end = time }
            for cycle in rings.sorted(by: { $0.lexicographicallyPrecedes($1) }) { let key = RingKey(prefix: prefix, cycle: cycle); if ringActive[key] == nil { ringActive[key] = ringRecords.count; ringRecords.append(RingRecord(prefix, time, cycle)) } }
        }
        for i in parameters.traces.indices {
            let (source, _, address) = parameters.traces[i], result = forward(source, address), bad = result.result == "LOOP" || result.result == "BLACKHOLE"
            if let id = traceActive[i] { let old = traceRecords[id]; if !bad || old.result != result.result || old.visits != result.visits { old.end = time; traceActive[i] = nil } }
            if bad && traceActive[i] == nil { traceActive[i] = traceRecords.count; traceRecords.append(TraceRecord(i, time, result.result, result.visits)) }
        }
    }
    func state() -> String {
        func table(_ table: [Prefix: Attribute]) -> String { table.keys.sorted().map { $0.text + "=" + Report.attribute(table[$0]!) }.joined(separator: ";") }
        var values: [String] = []
        for key in sessions.keys.sorted() { let s = sessions[key]!; values.append("\(table(s.incoming))|\(table(s.outgoing))|\(s.pending.sorted().map(\.text).joined(separator: ","))|\(s.timer.map { String($0 - time) } ?? "none")") }
        values.append("messages")
        for m in queue.messages.sorted(by: Message.before) { values.append("\(m.arrival - time)|\(m.receiver)|\(m.sender)|\(m.link)|\(m.prefix.text)|\(m.content.map(Report.attribute) ?? "withdraw")") }
        return values.joined(separator: "\n")
    }
    var quiet: Bool { queue.messages.isEmpty && sessions.values.allSatisfy { $0.pending.isEmpty } }
    func run(_ events: [Event]) {
        for (index, event) in events.enumerated() {
            time = event.time; counter = Counters(); bestLines.removeAll(); changed.removeAll()
            let start = ribs
            var deliveries = 0, seen: [String: Int] = [:], divergent: (Int, Int)?
            execute(index, event)
            while true {
                let messages = queue.deliveries(time)
                if !messages.isEmpty { counter.convergence = time - event.time }
                for message in messages { receive(message) }
                let expiring = sessions.keys.sorted().filter { sessions[$0]!.timer == time }
                for key in expiring { let s = sessions[key]!; s.timer = nil; if !s.pending.isEmpty { pending(key.asn, key.link) } }
                if !changed.isEmpty { forwardingCheck() }
                if !messages.isEmpty {
                    deliveries += 1
                    if divergent == nil && deliveries <= parameters.stepcap {
                        let state = state()
                        if let first = seen[state] { divergent = (first, time); divergences.append(Divergence(event: index, first: first, again: time, lines: bestLines.filter { first < $0.time && $0.time <= time })) }
                        else { seen[state] = time }
                    }
                }
                if index + 1 == events.count {
                    if quiet || divergent != nil || deliveries >= parameters.stepcap { break }
                } else if time == events[index + 1].time - 1 { break }
                time += 1; changed.removeAll()
            }
            let status = divergent != nil ? "DIVERGENT" : quiet ? "CONVERGED" : index + 1 == events.count ? "CAPPED" : "UNSETTLED"
            var routesChanged = 0
            for x in topology.ases { for prefix in Set(start[x]!.keys).union(ribs[x]!.keys) where start[x]![prefix] != ribs[x]![prefix] { routesChanged += 1 } }
            convergence.append("\(index),\(event.time),\(event.kind),\(status),\(counter.convergence),\(counter.updates),\(counter.withdrawals),\(counter.drops),\(counter.changes),\(routesChanged),\(counter.exploration.values.max() ?? 0)")
        }
    }
    func ribsReport() -> [String] {
        var lines: [String] = []
        for x in topology.ases {
            let rib = ribs[x]!, links = topology.sessions(x), sent = links.reduce(0) { $0 + session(x, $1).sent }, received = links.reduce(0) { $0 + session(x, $1).received }
            lines.append("AS \(x) routes \(rib.count) local \(rib.values.filter { $0.link == nil }.count) sent \(sent) received \(received) changes \(asChanges[x]!)")
            for link in links {
                let s = session(x, link), l = topology.links[link], accepted = s.incoming.filter { importRoute(x, link, $0.key, $0.value).0 != nil }.count
                lines.append("SESSION \(l.name) \(l.other(x)) \(l.roleText(x)) \(l.up ? "UP" : "DOWN") in \(s.incoming.count) accepted \(accepted) out \(s.outgoing.count) sent \(s.sent) received \(s.received) flaps \(l.downs)")
            }
            for prefix in rib.keys.sorted() {
                let route = rib[prefix]!
                var choices = candidates(x, prefix)
                let reason = route.link == nil ? "" : " reason " + Decision.best(choices, topology).1
                lines.append("\(prefix.text) \(Report.route(route, topology)) candidates \(choices.count)\(reason)")
                choices.removeAll { $0 == route }
                while !choices.isEmpty { let best = Decision.best(choices, topology).0; lines.append("ALT " + Report.route(best, topology)); choices.removeAll { $0 == best } }
            }
        }
        return lines
    }
    func pathsReport() -> [String] {
        var lines: [String] = []
        for (source, address, value) in parameters.traces {
            let result = forward(source, value), hops = result.hops.filter { $0.2 != nil }.count
            lines.append("TRACE \(source) \(address) \(result.result) hops \(hops)")
            for (x, prefix, link) in result.hops {
                if let link { lines.append("HOP \(x) \(prefix.text) next \(topology.links[link].other(x)) link \(topology.links[link].name)") }
                else { lines.append("HOP \(x) \(prefix.text) LOCAL") }
            }
            if result.result == "LOOP" { lines.append("HOP \(result.visits.last!) REVISIT") }
            else if result.result != "DELIVERED" { lines.append("HOP \(result.visits.last!) NOROUTE") }
            if let first = result.hops.first {
                let route = ribs[source]![first.1]!
                var merged: [Int] = []
                for x in route.attribute.path where merged.last != x { merged.append(x) }
                let match = result.result == "DELIVERED" && merged == Array(result.visits.dropFirst())
                lines.append("CONTROL \(route.link == nil ? "LOCAL" : Report.path(route.attribute.path)) \(match ? "MATCH" : "MISMATCH")")
            } else { lines.append("CONTROL NONE") }
            if hops > 0 {
                let pattern = String(result.hops.compactMap { x, _, link in link.map { topology.links[$0].symbol(x) } })
                lines.append("PATTERN \(pattern) \(valley(pattern) == pattern.count ? "VALLEYFREE" : "VALLEY")")
            }
        }
        let prefixes = Set(origins.values.flatMap { Array($0.keys) }).sorted()
        lines.append("PREFIXES " + prefixes.map(\.text).joined(separator: ","))
        for source in topology.ases {
            let symbols = prefixes.map { prefix -> String in
                let result = forward(source, prefix.address)
                switch result.result {
                case "DELIVERED": return result.hops.allSatisfy { $0.2 == nil } ? "*" : origins[result.visits.last!]![prefix] != nil ? "+" : "X"
                case "LOOP": return "L"
                case "BLACKHOLE": return "B"
                default: return "U"
                }
            }.joined()
            lines.append("REACH \(source) \(symbols)")
        }
        return lines
    }
    func auditReport() -> [String] {
        var lines: [String] = [], loops = 0, blackholes = 0
        let traces = traceRecords.sorted { $0.start == $1.start ? $0.trace < $1.trace : $0.start < $1.start }
        for record in traces {
            let (source, address, _) = parameters.traces[record.trace], end = record.end.map(String.init) ?? "END"
            if record.result == "LOOP" { loops += 1; lines.append("LOOP \(source) \(address) from \(record.start) to \(end) path \(Report.path(record.visits))") }
            else { blackholes += 1; lines.append("BLACKHOLE \(source) \(address) from \(record.start) to \(end) at \(record.visits.last!) path \(Report.path(record.visits))") }
        }
        let rings = ringRecords.sorted { a, b in if a.start != b.start { return a.start < b.start }; if a.prefix != b.prefix { return a.prefix < b.prefix }; return a.cycle[0] < b.cycle[0] }
        for record in rings { lines.append("RING \(record.prefix.text) from \(record.start) to \(record.end.map(String.init) ?? "END") path \(Report.path(record.cycle))") }
        var routes = 0, valleys = 0
        for x in topology.ases {
            for prefix in ribs[x]!.keys.sorted() {
                let route = ribs[x]![prefix]!
                if route.link == nil { continue }
                routes += 1
                var h: [Int] = []
                for asn in [x] + route.attribute.path where h.last != asn { h.append(asn) }
                let pattern = String(zip(h, h.dropFirst()).map { topology.connecting($0.0, $0.1).symbol($0.0) }), g = valley(pattern)
                if g < pattern.count { valleys += 1; lines.append("VALLEY \(x) \(prefix.text) path \(Report.path(route.attribute.path)) pattern \(pattern) leaker \(h[g])") }
            }
        }
        for rule in policy.rules { lines.append("RULE \(rule.name) \(rule.importing ? "IMPORT" : "EXPORT") \(rule.on ? "ON" : "OFF") hits \(rule.hits)") }
        for divergence in divergences {
            lines.append("DIVERGENT event \(divergence.event) first \(divergence.first) repeat \(divergence.again) period \(divergence.again - divergence.first)")
            var oscillate: [PairKey: Int] = [:]
            for line in divergence.lines { lines.append("CYCLE \(line.time) \(line.asn) \(line.prefix.text) \(Report.route(line.route, topology))"); oscillate[PairKey(asn: line.asn, prefix: line.prefix), default: 0] += 1 }
            for key in oscillate.keys.sorted() { lines.append("OSCILLATE \(key.asn) \(key.prefix.text) changes \(oscillate[key]!)") }
        }
        lines.append("SUMMARY loops \(loops) blackholes \(blackholes) rings \(ringRecords.count) routes \(routes) valleys \(valleys) divergent \(divergences.count) end \(time)")
        return lines
    }
}
let events = Event.read(), bgp = BGP()
bgp.run(events)
Report.write("updates.txt", bgp.logs); Report.write("convergence.csv", bgp.convergence); Report.write("ribs.txt", bgp.ribsReport()); Report.write("paths.txt", bgp.pathsReport()); Report.write("audit.txt", bgp.auditReport())
