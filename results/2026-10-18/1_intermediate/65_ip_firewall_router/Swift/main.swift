import Foundation

struct Problem: Error { let reason: String }
func ip(_ word: String) throws -> Int {
    let fields = word.components(separatedBy: ".")
    guard fields.count == 4 else {
        throw Problem(reason: "bad address \(word)")
    }
    var a = 0
    for field in fields {
        guard (1...3).contains(field.count), !(field.count > 1 && field.hasPrefix("0")),
              field.utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(field),
              n <= 255
        else {
            throw Problem(reason: "bad address \(word)")
        }
        a = a * 256 + n
    }
    return a
}
func address(_ a: Int) -> String {
    "\(a >> 24).\((a >> 16) & 255).\((a >> 8) & 255).\(a & 255)"
}
func mask(_ length: Int) -> Int {
    length == 0 ? 0 : (0xffff_ffff << (32 - length)) & 0xffff_ffff
}
struct Prefix: Equatable {
    let network: Int, length: Int
    func contains(_ a: Int) -> Bool {
        a & mask(length) == network & mask(length)
    }
    var notation: String {
        "\(address(network))/\(length)"
    }
    var aclNotation: String {
        length == 0 ? "any" : notation
    }
}
func prefix(_ word: String, _ hostBits: Bool = true) throws -> Prefix {
    let fields = word.components(separatedBy: "/")
    guard fields.count == 2, let a = try? ip(fields[0]), (1...2).contains(fields[1].count),
          !(fields[1].count == 2 && fields[1].hasPrefix("0")), fields[1].utf8.allSatisfy({ (48...57).contains($0) }),
          let length = Int(fields[1]), length <= 32
    else {
        throw Problem(reason: "bad prefix \(word)")
    }
    if hostBits && a & (0xffff_ffff ^ mask(length)) != 0 {
        throw Problem(reason: "host bits set in \(word)")
    }
    return Prefix(network: a, length: length)
}
struct Ports {
    let low: Int, high: Int, any: Bool
    var notation: String {
        any ? "any" : (low == high ? String(low) : "\(low)-\(high)")
    }
    func contains(_ n: Int) -> Bool {
        low <= n && n <= high
    }
}
func ports(_ word: String) throws -> Ports {
    if word == "ANY" {
        return Ports(low: 0, high: 65535, any: true)
    }
    let values = word.components(separatedBy: "-").map { Int($0)! }
    let a = values[0], b = values.last!
    guard a <= 65535 && b <= 65535 && a <= b else {
        throw Problem(reason: "bad port range \(word)")
    }
    return Ports(low: a, high: b, any: false)
}
final class Interface {
    let name: String, address: Int, length: Int
    var up = true, outside = false, pool: Int? = nil, rpf = "off", rx = 0, tx = 0, drop = 0
    var defaults = [0, 0]
    init(_ name: String, _ address: Int, _ length: Int) {
        self.name = name
        self.address = address
        self.length = length
    }
}
final class Route {
    let kind: String, dest: Prefix, iface: Int, hop: Int?, metric: Int
    var hits = 0
    init(_ kind: String, _ dest: Prefix, _ iface: Int, _ hop: Int?, _ metric: Int) {
        self.kind = kind
        self.dest = dest
        self.iface = iface
        self.hop = hop
        self.metric = metric
    }
}
final class Rule {
    let iface: Int, dir: Int, seq: Int, action: String, proto: String, src: Prefix, sports: Ports, dst: Prefix,
        dports: Ports, established: Bool
    var hits = 0
    init(
        _ iface: Int,
        _ dir: Int,
        _ seq: Int,
        _ action: String,
        _ proto: String,
        _ src: Prefix,
        _ sports: Ports,
        _ dst: Prefix,
        _ dports: Ports,
        _ established: Bool
    ) {
        self.iface = iface
        self.dir = dir
        self.seq = seq
        self.action = action
        self.proto = proto
        self.src = src
        self.sports = sports
        self.dst = dst
        self.dports = dports
        self.established = established
    }
}
struct Forward { let iface: Int, proto: String, port: Int, inside: Int, inport: Int }
final class Pat {
    let iface: Int, proto: String, inside: Int, inport: Int, port: Int
    var used: Int
    init(_ iface: Int, _ proto: String, _ inside: Int, _ inport: Int, _ port: Int, _ used: Int) {
        self.iface = iface
        self.proto = proto
        self.inside = inside
        self.inport = inport
        self.port = port
        self.used = used
    }
}
struct PacketTuple: Equatable {
    let proto: String, src: Int, sport: Int, dst: Int, dport: Int
    var notation: String {
        "\(address(src)):\(sport) > \(address(dst)):\(dport)"
    }
}
final class Connection {
    let number: Int, orig: PacketTuple, reply: PacketTuple, input: Int, output: Int
    var state: String, packets = [0, 0], used: Int, fin = [false, false]
    init(_ number: Int, _ orig: PacketTuple, _ reply: PacketTuple, _ input: Int, _ output: Int, _ used: Int) {
        self.number = number
        self.orig = orig
        self.reply = reply
        self.input = input
        self.output = output
        self.used = used
        state = orig.proto == "TCP" ? "SYN_SENT" : "UNREPLIED"
    }
}
let reasons = ["down", "martian", "rpf", "invalid", "acl_in", "ttl", "noroute", "acl_out", "exhausted"]
func protocolIndex(_ p: String) -> Int {
    p == "TCP" ? 0 : (p == "UDP" ? 1 : 2)
}
final class Router {
    var ifaces: [Interface] = [], routes: [Route] = [], rules: [Rule] = [], statics: [(Int, Int)] = [],
        forwards: [Forward] = [], pats: [Pat] = [], conns: [Connection] = []
    var timeouts = [300, 60, 30], clock = 0, packetNumber = 0, connectionNumber = 0, forwarded = 0, local = 0,
        drops = Array(
            repeating: 0,
            count: 9
        ), errors = 0
    func iface(_ name: String) throws -> Int {
        guard let i = ifaces.firstIndex(where: { $0.name == name })
        else {
            throw Problem(reason: "no interface \(name)")
        }
        return i
    }
    func localAddress(_ a: Int) -> Int? {
        ifaces.firstIndex { $0.address == a }
    }
    func select(_ a: Int) -> Int? {
        var selected: Int? = nil
        for (i, r) in routes.enumerated() where ifaces[r.iface].up && r.dest.contains(a) {
            if let j = selected {
                if r.dest.length > routes[j].dest
                    .length || (r.dest.length == routes[j].dest.length && r.metric < routes[j].metric)
                {
                    selected = i
                }
            } else {
                selected = i
            }
        }
        return selected
    }
    func routeText(_ r: Route)
        -> String
    {
        "\(r.kind) \(r.dest.notation)\(r.hop.map { " via " + address($0) } ?? "") dev \(ifaces[r.iface].name) metric \(r.metric)"
    }
    func acl(_ i: Int, _ d: Int, _ tuple: PacketTuple, _ existing: Bool) -> String? {
        let list = rules.filter { $0.iface == i && $0.dir == d }.sorted { $0.seq < $1.seq }
        if list.isEmpty {
            return nil
        }
        let name = ifaces[i].name, dir = d == 0 ? "in" : "out"
        for r in list {
            if (r.proto != "ANY" && r.proto != tuple.proto) || !r.src.contains(tuple.src) || !r.dst
                .contains(tuple.dst) || (r.established && !existing)
            {
                continue
            }
            if (r.proto == "TCP" || r.proto == "UDP") &&
                (!r.sports.contains(tuple.sport) || !r.dports.contains(tuple.dport))
            {
                continue
            }
            r.hits += 1
            if r.action == "PERMIT" {
                return nil
            }
            if r.action == "DENY" {
                return "DROP acl \(name) \(dir) \(r.seq)"
            }
            return "REJECT acl \(name) \(dir) \(r.seq) \(tuple.proto == "TCP" ? "tcp-reset" : "icmp-prohibited")"
        }
        ifaces[i].defaults[d] += 1
        return "DROP acl \(name) \(dir) default"
    }
    func packet(_ input: Int, _ flags: String, _ orig: PacketTuple, _ ttl: Int) -> (String, Int) {
        if !ifaces[input].up {
            return ("DROP down", 0)
        }
        func martian(_ a: Int) -> Bool {
            a >> 24 == 0 || a >> 24 == 127 || a >= 0xe000_0000
        }
        if martian(orig.src) || martian(orig.dst) || localAddress(orig.src) != nil {
            return ("DROP martian", 1)
        }
        if ifaces[input].rpf != "off" {
            guard let r = select(orig.src) else {
                return ("DROP rpf", 2)
            }
            if ifaces[input].rpf == "strict" && routes[r].iface != input {
                return ("DROP rpf", 2)
            }
        }
        let pureSyn = orig.proto == "TCP" && flags == "S"
        var found: (Int, Int)? = nil
        for (i, c) in conns.enumerated() {
            if c.orig == orig {
                found = (i, 0)
                break
            }
            if c.reply == orig {
                found = (i, 1)
                break
            }
        }
        if let (i, _) = found, conns[i].state == "CLOSED" && pureSyn {
            conns.remove(at: i)
            found = nil
        }
        if orig.proto == "TCP" && found == nil && !pureSyn {
            return ("DROP invalid", 3)
        }
        if let verdict = acl(input, 0, orig, found != nil) {
            return (verdict, 4)
        }
        var dst = orig.dst, dport = orig.dport, used: Pat? = nil
        if ifaces[input].outside {
            if let pair = statics.first(where: { $0.1 == dst }) {
                dst = pair.0
            } else if dst == ifaces[input].address {
                if let f = forwards
                    .first(where: { $0.iface == input && $0.proto == orig.proto && $0.port == dport })
                {
                    dst = f.inside
                    dport = f.inport
                } else if let p = pats
                    .first(where: { $0.iface == input && $0.proto == orig.proto && $0.port == dport })
                {
                    dst = p.inside
                    dport = p.inport
                    used = p
                }
            }
        }
        if let i = localAddress(dst) {
            return ("LOCAL \(ifaces[i].name)", -2)
        }
        if ttl == 1 {
            return ("DROP ttl", 5)
        }
        guard let r = select(dst) else {
            return ("DROP noroute", 6)
        }
        let output = routes[r].iface
        let outgoing = PacketTuple(proto: orig.proto, src: orig.src, sport: orig.sport, dst: dst, dport: dport)
        if let verdict = acl(output, 1, outgoing, found != nil) {
            return (verdict, 7)
        }
        var src = orig.src, sport = orig.sport
        if !ifaces[input].outside && ifaces[output].outside {
            if let pair = statics.first(where: { $0.0 == src }) {
                src = pair.1
            } else if let f = forwards
                .first(where: { $0.iface == output && $0.proto == orig.proto && $0.inside == src && $0.inport == sport
                })
            {
                src = ifaces[output].address
                sport = f.port
            } else if let count = ifaces[output].pool {
                var mapping = pats
                    .first { $0.iface == output && $0.proto == orig.proto && $0.inside == src && $0.inport == sport }
                if mapping == nil {
                    guard let port = (20000..<(20000 + count))
                        .first(where: { p in
                            !pats.contains { $0.iface == output && $0.port == p } && !forwards
                                .contains { $0.iface == output && $0.port == p }
                        })
                    else {
                        return (
                            "DROP exhausted",
                            8
                        )
                    }
                    mapping = Pat(output, orig.proto, src, sport, port, clock)
                    pats.append(mapping!)
                }
                used = mapping
                src = ifaces[output].address
                sport = mapping!.port
            }
        }
        used?.used = clock
        let connection: Connection, side: Int, direction: String
        if let (i, d) = found {
            connection = conns[i]
            side = d
            direction = d == 0 ? "orig" : "reply"
        } else {
            connectionNumber += 1
            let reply = PacketTuple(proto: orig.proto, src: dst, sport: dport, dst: src, dport: sport)
            connection = Connection(connectionNumber, orig, reply, input, output, clock)
            conns.append(connection)
            side = 0
            direction = "new"
        }
        connection.packets[side] += 1
        connection.used = clock
        if orig.proto != "TCP" {
            if side == 1 {
                connection.state = "REPLIED"
            }
        } else if flags.contains("R") {
            connection.state = "CLOSED"
        } else {
            if connection.state == "SYN_SENT" && side == 1 && flags.contains("S") && flags
                .contains("A")
            {
                connection.state = "ESTABLISHED"
            }
            if flags
                .contains("F") &&
                (connection.state == "ESTABLISHED" || connection.state == "FIN_WAIT")
            {
                connection.fin[side] = true
                connection.state = connection.fin[0] && connection.fin[1] ? "CLOSED" : "FIN_WAIT"
            }
        }
        ifaces[output].tx += 1
        routes[r].hits += 1
        let hop = routes[r].hop.map { "via " + address($0) } ?? "direct"
        var verdict = "FORWARD \(ifaces[output].name) \(hop) ttl=\(ttl - 1)"
        if dst != orig.dst || dport != orig.dport {
            verdict += " dnat=\(address(dst)):\(dport)"
        }
        if src != orig.src || sport != orig.sport {
            verdict += " snat=\(address(src)):\(sport)"
        }
        verdict += " conn=\(connection.number) \(direction)"
        return (verdict, -1)
    }
    func command(_ w: [String]) throws -> [String] {
        func n(_ i: Int) -> Int {
            Int(w[i])!
        }
        func d(_ s: String) -> Int {
            s == "IN" ? 0 : 1
        }
        func require(_ condition: Bool, _ reason: String) throws {
            if !condition {
                throw Problem(reason: reason)
            }
        }
        let text: String
        switch w[0] {
        case "IFACE":
            try require(!ifaces.contains { $0.name == w[1] }, "duplicate interface \(w[1])")
            let p = try prefix(w[2], false)
            try require((8...30).contains(p.length), "bad prefix \(w[2])")
            let host = p.network & (0xffff_ffff ^ mask(p.length))
            try require(host != 0 && host != (0xffff_ffff ^ mask(p.length)), "bad host address \(w[2])")
            if let old = ifaces.first(where: { $0.address & mask(min($0.length, p.length)) == p.network & mask(min(
                $0.length,
                p.length
            )) }) {
                throw Problem(reason: "subnet overlaps \(old.name)")
            }
            let i = ifaces.count, dest = Prefix(network: p.network & mask(p.length), length: p.length)
            ifaces.append(Interface(w[1], p.network, p.length))
            routes.append(Route("C", dest, i, nil, 0))
            text = "ok iface \(w[1]) \(w[2]) network \(dest.notation)"
        case "UP", "DOWN":
            let i = try iface(w[1]), up = w[0] == "UP"
            try require(ifaces[i].up != up, "interface \(w[1]) already \(w[0].lowercased())")
            ifaces[i].up = up
            text = "ok \(w[0].lowercased()) \(w[1])"
        case "ROUTE":
            let dest = try prefix(w[1])
            var hop: Int? = nil
            var output = 0
            if w[2] == "VIA" {
                hop = try ip(w[3])
            } else {
                output = try iface(w[3])
            }
            try require((1...255).contains(n(4)), "bad metric \(w[4])")
            if let hop {
                try require(localAddress(hop) == nil, "nexthop \(w[3]) is local")
                guard let i = ifaces
                    .firstIndex(where: { Prefix(network: $0.address, length: $0.length).contains(hop) })
                else {
                    throw Problem(reason: "nexthop \(w[3]) unreachable")
                }
                output = i
            }
            try require(
                !routes.contains { $0.kind == "S" && $0.dest == dest && $0.iface == output && $0.hop == hop },
                "duplicate route \(w[1])"
            )
            let route = Route("S", dest, output, hop, n(4))
            text = "ok route " + routeText(route)
            routes.append(route)
        case "NOROUTE":
            let dest = try prefix(w[1]), old = routes.count
            try require(routes.contains { $0.kind == "S" && $0.dest == dest }, "no static route \(w[1])")
            routes.removeAll { $0.kind == "S" && $0.dest == dest }
            text = "ok noroute \(w[1]) removed=\(old - routes.count)"
        case "LOOKUP":
            let a = try ip(w[1])
            text = "lookup \(w[1]) \(select(a).map { routeText(routes[$0]) } ?? "none")"
        case "ACL":
            let i = try iface(w[1]), dir = d(w[2])
            try require((1...9999).contains(n(3)), "bad sequence \(w[3])")
            let src: Prefix
            if w[6] == "ANY" {
                src = Prefix(network: 0, length: 0)
            } else {
                src = try prefix(w[6])
            }
            let sports = try ports(w[7])
            let dst: Prefix
            if w[8] == "ANY" {
                dst = Prefix(network: 0, length: 0)
            } else {
                dst = try prefix(w[8])
            }
            let dports = try ports(w[9])
            try require(!["ICMP", "ANY"].contains(w[5]) || (sports.any && dports.any), "ports not allowed for \(w[5])")
            try require(
                !rules.contains { $0.iface == i && $0.dir == dir && $0.seq == n(3) },
                "duplicate sequence \(w[3])"
            )
            rules.append(Rule(i, dir, n(3), w[4], w[5], src, sports, dst, dports, w.count == 11))
            text = "ok acl \(w[1]) \(w[2].lowercased()) \(w[3])"
        case "NOACL":
            let i = try iface(w[1]), dir = d(w[2])
            guard let at = rules.firstIndex(where: { $0.iface == i && $0.dir == dir && $0.seq == n(3) })
            else {
                throw Problem(reason: "no rule \(w[3]) on \(w[1]) \(w[2].lowercased())")
            }
            let rule = rules.remove(at: at)
            text = "ok noacl \(w[1]) \(w[2].lowercased()) \(w[3]) hits=\(rule.hits)"
        case "NAT":
            switch w[1] {
            case "STATIC":
                let inside = try ip(w[2]), outside = try ip(w[3])
                try require(localAddress(inside) == nil, "address \(w[2]) is local")
                try require(localAddress(outside) == nil, "address \(w[3]) is local")
                try require(!statics.contains { $0.0 == inside }, "duplicate static \(w[2])")
                try require(!statics.contains { $0.1 == outside }, "duplicate static \(w[3])")
                statics.append((inside, outside))
                text = "ok nat static \(w[2]) \(w[3])"
            case "OUTSIDE":
                let i = try iface(w[2])
                try require(!ifaces[i].outside, "interface \(w[2]) already outside")
                ifaces[i].outside = true
                text = "ok nat outside \(w[2])"
            case "PAT":
                let i = try iface(w[2])
                try require((1...1000).contains(n(3)), "bad pool size \(w[3])")
                try require(ifaces[i].pool == nil, "pat already on \(w[2])")
                ifaces[i].pool = n(3)
                ifaces[i].outside = true
                text = "ok nat pat \(w[2]) \(address(ifaces[i].address)) 20000-\(20000 + n(3) - 1)"
            default:
                let i = try iface(w[2])
                try require((1...65535).contains(n(4)), "bad port \(w[4])")
                let inside = try ip(w[5])
                try require((1...65535).contains(n(6)), "bad port \(w[6])")
                try require(ifaces[i].outside, "interface \(w[2]) not outside")
                try require(localAddress(inside) == nil, "address \(w[5]) is local")
                try require(
                    !forwards.contains { $0.iface == i && $0.proto == w[3] && $0.port == n(4) },
                    "duplicate forward \(w[2]) \(w[3]) \(w[4])"
                )
                forwards.append(Forward(iface: i, proto: w[3], port: n(4), inside: inside, inport: n(6)))
                text = "ok nat forward \(w[2]) \(w[3]) \(w[4]) \(w[5]):\(w[6])"
            }
        case "RPF":
            let i = try iface(w[1])
            ifaces[i].rpf = w[2].lowercased()
            text = "ok rpf \(w[1]) \(w[2].lowercased())"
        case "TIMEOUT":
            try require((1...86400).contains(n(2)), "bad timeout \(w[2])")
            timeouts[protocolIndex(w[1])] = n(2)
            text = "ok timeout \(w[1]) \(w[2])"
        case "TICK":
            try require((1...86400).contains(n(1)), "bad tick \(w[1])")
            clock += n(1)
            let old = conns.count, oldNat = pats.count
            conns.removeAll { c in
                let timeout: Int
                if c.orig.proto == "TCP" {
                    switch c.state { case "SYN_SENT", "FIN_WAIT":
                        timeout = 60
                    case "CLOSED":
                        timeout = 10
                    default:
                        timeout = timeouts[0] }
                } else {
                    timeout = timeouts[protocolIndex(c.orig.proto)]
                }
                return clock - c.used >= timeout
            }
            pats.removeAll { clock - $0.used >= timeouts[protocolIndex($0.proto)] }
            text = "ok tick time=\(clock) expired conns=\(old - conns.count) nat=\(oldNat - pats.count)"
        case "PACKET":
            let i = try iface(w[1])
            try require(w[2] == "TCP" || w[3] == "-", "flags not allowed for \(w[2])")
            if w[2] == "TCP" && w[3] != "-" {
                try require(
                    w[3].allSatisfy { "SAFR".contains($0) } && Set(w[3]).count == w[3].count,
                    "bad flags \(w[3])"
                )
            }
            let src = try ip(w[4])
            try require((0...65535).contains(n(5)), "bad port \(w[5])")
            let dst = try ip(w[6])
            try require((0...65535).contains(n(7)), "bad port \(w[7])")
            try require((1...255).contains(n(8)), "bad ttl \(w[8])")
            packetNumber += 1
            ifaces[i].rx += 1
            let (verdict, reason) = packet(
                i,
                w[3],
                PacketTuple(proto: w[2], src: src, sport: n(5), dst: dst, dport: n(7)),
                n(8)
            )
            if reason == -1 {
                forwarded += 1
            } else if reason == -2 {
                local += 1
            } else {
                drops[reason] += 1
                ifaces[i].drop += 1
            }
            text = "#\(packetNumber) \(w[2]) \(w[3]) \(w[4]):\(w[5]) > \(w[6]):\(w[7]) \(verdict)"
        case "SHOW":
            return show(w[1])
        default:
            if w[1] == "CONNS" {
                text = "ok clear conns=\(conns.count) nat=\(pats.count)"
                conns.removeAll()
                pats.removeAll()
            } else {
                forwarded = 0
                local = 0
                drops = Array(repeating: 0, count: 9)
                errors = 0
                for i in ifaces {
                    i.rx = 0
                    i.tx = 0
                    i.drop = 0
                    i.defaults = [0, 0]
                }
                for r in routes {
                    r.hits = 0
                }
                for r in rules {
                    r.hits = 0
                }
                text = "ok clear counters"
            }
        }
        return [text]
    }
    func show(_ what: String) -> [String] {
        let names = ifaces.indices.sorted { ifaces[$0].name < ifaces[$1].name }
        var lines: [String] = []
        switch what {
        case "IFACES":
            lines.append("show ifaces count=\(ifaces.count)")
            for i in names {
                let f = ifaces[i]
                var s = "\(f.name) \(address(f.address))/\(f.length) \(f.up ? "up" : "down") \(f.outside ? "outside" : "inside") rpf=\(f.rpf)"
                if let pool = f.pool {
                    s += " pat=\(pats.filter { $0.iface == i }.count)/\(pool)"
                }
                lines.append(s)
            }
        case "ROUTES":
            lines.append("show routes count=\(routes.count)")
            let indices = routes.indices.sorted { a, b in let x = routes[a], y = routes[b]
                if x.dest.network != y.dest.network {
                    return x.dest.network < y.dest.network
                }
                if x.dest.length != y.dest.length {
                    return x.dest.length < y.dest.length
                }
                if x.metric != y.metric {
                    return x.metric < y.metric
                }
                return a < b
            }
            for i in indices {
                let r = routes[i]
                lines.append(routeText(r) + " hits=\(r.hits)" + (ifaces[r.iface].up ? "" : " inactive"))
            }
        case "ACL":
            lines.append("show acl count=\(rules.count)")
            for i in names {
                for d in 0...1 {
                    let list = rules.filter { $0.iface == i && $0.dir == d }.sorted { $0.seq < $1.seq }
                    if list.isEmpty {
                        continue
                    }
                    let name = ifaces[i].name, dir = d == 0 ? "in" : "out"
                    for r in list {
                        lines
                            .append(
                                "acl \(name) \(dir) \(r.seq) \(r.action) \(r.proto) \(r.src.aclNotation) \(r.sports.notation) \(r.dst.aclNotation) \(r.dports.notation)\(r.established ? " established" : "") hits=\(r.hits)"
                            )
                    }
                    lines.append("acl \(name) \(dir) default DENY hits=\(ifaces[i].defaults[d])")
                }
            }
        case "NAT":
            lines.append("show nat static=\(statics.count) forward=\(forwards.count) pat=\(pats.count)")
            for (a, b) in statics.sorted(by: { $0.0 < $1.0 }) {
                lines.append("static \(address(a)) \(address(b))")
            }
            for f in forwards
                .sorted(by: { a, b in
                    if ifaces[a.iface].name != ifaces[b.iface].name {
                        return ifaces[a.iface].name < ifaces[b.iface].name
                    }
                    if a.port != b.port {
                        return a.port < b.port
                    }
                    return a.proto < b.proto
                })
            {
                lines.append("forward \(ifaces[f.iface].name) \(f.proto) \(f.port) \(address(f.inside)):\(f.inport)")
            }
            for p in pats
                .sorted(by: { a, b in
                    if ifaces[a.iface].name != ifaces[b.iface].name {
                        return ifaces[a.iface].name < ifaces[b.iface].name
                    }
                    return a.port < b.port
                })
            {
                lines
                    .append(
                        "pat \(ifaces[p.iface].name) \(p.port) \(p.proto) \(address(p.inside)):\(p.inport) idle=\(clock - p.used)"
                    )
            }
        case "CONNS":
            lines.append("show conns count=\(conns.count)")
            for c in conns {
                lines
                    .append(
                        "conn \(c.number) \(c.orig.proto) \(c.orig.notation) reply \(c.reply.notation) in=\(ifaces[c.input].name) out=\(ifaces[c.output].name) state=\(c.state) pkts=\(c.packets[0])/\(c.packets[1]) idle=\(clock - c.used)"
                    )
            }
        default:
            let dropped = drops.reduce(0,+)
            lines
                .append(
                    "show counters packets=\(forwarded + local + dropped) forwarded=\(forwarded) local=\(local) dropped=\(dropped) errors=\(errors)"
                )
            lines
                .append("drops " + reasons.indices.map { reasons[$0] + "=" + String(drops[$0]) }.joined(separator: " "))
            for i in names {
                let f = ifaces[i]
                lines.append("iface \(f.name) rx=\(f.rx) tx=\(f.tx) drop=\(f.drop)")
            }
        }
        return lines
    }
}
let router = Router()
let count = Int(readLine()!)!
for _ in 0..<count {
    let words = readLine()!.components(separatedBy: " ")
    do { for line in try router.command(words) {
        print(line)
    } } catch let p as Problem { router.errors += 1
        print("error: " + p.reason)
    } catch { fatalError("unexpected error") }
}
