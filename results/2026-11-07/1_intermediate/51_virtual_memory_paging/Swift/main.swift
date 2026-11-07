import Foundation

let policies = ["FIFO", "LRU", "LFU", "NRU", "AGING", "CLOCK", "ECLOCK", "WSCLOCK", "RANDOM", "OPT"]
func hex(_ value: Int) -> String {
    "0x" + String(value, radix: 16, uppercase: true)
}
func address(_ text: String) -> Int {
    Int(text.dropFirst(2), radix: 16)!
}
func decimal(_ value: Int) -> String {
    "\(value / 100)." + (value % 100 < 10 ? "0" : "") + "\(value % 100)"
}
func ratio(_ x: Int, _ y: Int) -> String {
    decimal(y == 0 ? 0 : 10000 * x / y) + "%"
}
enum CommandError: Error { case message(String) }
struct Config {
    var page = 256, frames = 4, tlb = 4, sets = 1, tick = 0, tau = 8, seed = 1
    var policy = "FIFO", scope = "GLOBAL", asid = "OFF"
    var description: String {
        "SYSTEM page=\(page) frames=\(frames) tlb=\(tlb) sets=\(sets) policy=\(policy) scope=\(scope) asid=\(asid) tick=\(tick) tau=\(tau) seed=\(seed)"
    }
}
func settings(_ tokens: [String]) throws -> Config {
    var c = Config()
    let keys = ["page", "frames", "tlb", "sets", "policy", "scope", "asid", "tick", "tau", "seed"]
    var seen = Set<String>()
    for token in tokens.dropFirst() {
        let pair = token.split(separator: "=").map(String.init)
        let key = pair[0], value = pair[1]
        guard keys.contains(key) else {
            throw CommandError.message("unknown key " + key)
        }
        guard seen.insert(key).inserted else {
            throw CommandError.message("duplicate key " + key)
        }
        var valid: Bool
        switch key {
        case "policy":
            valid = policies.contains(value)
            if valid {
                c.policy = value
            }
        case "scope":
            valid = ["GLOBAL", "LOCAL"].contains(value)
            if valid {
                c.scope = value
            }
        case "asid":
            valid = ["ON", "OFF"].contains(value)
            if valid {
                c.asid = value
            }
        default:
            let n = Int(value)!
            switch key {
            case "page":
                valid = n >= 16 && n <= 4096 && (n & (n - 1)) == 0
                if valid {
                    c.page = n
                }
            case "frames":
                valid = n >= 1 && n <= 16
                if valid {
                    c.frames = n
                }
            case "tlb":
                valid = n >= 1 && n <= 8
                if valid {
                    c.tlb = n
                }
            case "sets":
                valid = n >= 1 && n <= 8
                if valid {
                    c.sets = n
                }
            case "tick":
                valid = n >= 0 && n <= 1000
                if valid {
                    c.tick = n
                }
            case "tau":
                valid = n >= 1 && n <= 1000
                if valid {
                    c.tau = n
                }
            default:
                valid = n >= 1 && n <= 2147483646
                if valid {
                    c.seed = n
                }
            }
        }
        guard valid else {
            throw CommandError.message("invalid " + key)
        }
    }
    guard c.tlb % c.sets == 0 else {
        throw CommandError.message("invalid sets")
    }
    return c
}
final class Page {
    let pid: Int, number: Int
    var frame = -1, slot = -1, r = 0, m = 0, load = 0, last = 0, uses = 0, age = 0, references = 0
    var ro = false, locked = false, ever = false
    init(_ pid: Int, _ number: Int) {
        self.pid = pid
        self.number = number
    }
    var label: String {
        "P\(pid):\(number)"
    }
}
final class VMProcess {
    let pid: Int, pages: [Page]
    var accesses = 0, faults = 0, writebacks = 0, segfaults = 0, protfaults = 0, peak = 0, hand = 0
    var exited = false
    var history: [Int] = []
    init(_ pid: Int, _ count: Int) {
        self.pid = pid
        pages = (0..<count).map { Page(pid, $0) }
    }
    var resident: Int {
        pages.filter { $0.frame >= 0 }.count
    }
}
struct Access { let pid: Int
    let op: String
    let address: Int
}
enum Event {
    case access(Access), exit(Int), clean, lock(Int, Int, Int, Bool)
}
final class Simulation {
    let c: Config, silent: Bool, future: [Access]
    var processes: [Int: VMProcess] = [:]
    var frames: [Page?], tlb: [[Page]], swap: [Int: Page] = [:]
    var cursor = -1, previous = -1, hand = 0, time = 0, faults = 0, zero = 0, swapin = 0, tlbhits = 0, writebacks = 0,
        switches = 0
    var random: Int
    var fixed = false, trace = false
    var faultHistory: [Bool] = []
    var log: [Event] = []
    var pids: [Int] {
        processes.keys.sorted()
    }
    init(_ config: Config, _ references: [Access], silent: Bool = false) {
        c = config
        future = references
        self.silent = silent
        random = config.seed
        frames = Array(repeating: nil, count: config.frames)
        tlb = Array(repeating: [], count: config.sets)
    }
    func emit(_ text: String) {
        if !silent {
            print(text)
        }
    }
    func process(_ pid: Int) throws -> VMProcess {
        guard let p = processes[pid] else {
            throw CommandError.message("unknown process \(pid)")
        }
        guard !p.exited else {
            throw CommandError.message("process \(pid) exited")
        }
        return p
    }
    func quota(_ pid: Int) -> Int {
        c.frames / processes.count + (pids.firstIndex(of: pid)! < c.frames % processes.count ? 1 : 0)
    }
    func declare(_ pid: Int, _ count: Int) throws {
        guard !fixed else {
            throw CommandError.message("processes are fixed")
        }
        guard processes[pid] == nil else {
            throw CommandError.message("duplicate process \(pid)")
        }
        guard count >= 1 && count <= 256 else {
            throw CommandError.message("invalid page count")
        }
        guard processes.count < 8 && !(c.scope == "LOCAL" && processes.count == c.frames)
        else {
            throw CommandError.message("too many processes")
        }
        processes[pid] = VMProcess(pid, count)
    }
    func invalidate(_ page: Page) {
        for i in tlb.indices {
            tlb[i].removeAll { $0 === page }
        }
    }
    func write(_ p: Page) {
        writebacks += 1
        processes[p.pid]!.writebacks += 1
        p.m = 0
        if p.slot < 0 {
            var slot = 0
            while swap[slot] != nil {
                slot += 1
            }
            p.slot = slot
            swap[slot] = p
        }
    }
    func nextUse(_ p: Page) -> Int {
        for i in (cursor + 1)..<future.count {
            let a = future[i]
            if a.pid == p.pid && a.address / c.page == p.number {
                return i
            }
        }
        return Int.max
    }
    func choose(_ input: [Int], _ owner: VMProcess) -> Int {
        let unlocked = input.filter { !frames[$0]!.locked }
        var candidates = unlocked.isEmpty ? input : unlocked
        if ["FIFO", "LRU", "LFU", "NRU", "AGING", "OPT"].contains(c.policy) {
            candidates.sort { a, b in
                let x = frames[a]!, y = frames[b]!
                switch c.policy {
                case "FIFO":
                    return x.load < y.load
                case "LRU":
                    return x.last < y.last
                case "LFU":
                    return x.uses != y.uses ? x.uses < y.uses : x.load < y.load
                case "NRU":
                    return 2 * x.r + x.m != 2 * y.r + y.m ? 2 * x.r + x.m < 2 * y.r + y.m : a < b
                case "AGING":
                    return x.age != y.age ? x.age < y.age : x.load < y.load
                default:
                    let nx = nextUse(x), ny = nextUse(y)
                    return nx != ny ? nx > ny : a < b
                }
            }
            return candidates[0]
        }
        if c.policy == "RANDOM" {
            random = random * 48271 % 2147483647
            return candidates[random % candidates.count]
        }
        let h = c.scope == "GLOBAL" ? hand : owner.hand
        candidates.sort { ($0 - h + c.frames) % c.frames < ($1 - h + c.frames) % c.frames }
        var chosen: Int? = nil
        if c.policy == "CLOCK" {
            while chosen == nil {
                for f in candidates {
                    if frames[f]!.r == 0 {
                        chosen = f
                        break
                    }
                    frames[f]!.r = 0
                }
            }
        } else if c.policy == "ECLOCK" {
            while chosen == nil {
                for f in candidates where frames[f]!.r == 0 && frames[f]!.m == 0 {
                    chosen = f
                    break
                }
                if chosen != nil {
                    break
                }
                for f in candidates {
                    if frames[f]!.r == 0 && frames[f]!.m == 1 {
                        chosen = f
                        break
                    }
                    frames[f]!.r = 0
                }
            }
        } else {
            for f in candidates {
                let p = frames[f]!
                if p.r == 1 {
                    p.r = 0
                    p.last = time
                } else if time - p.last > c.tau {
                    if p.m == 0 {
                        chosen = f
                        break
                    }
                    write(p)
                }
            }
            if chosen == nil {
                chosen = candidates.first { frames[$0]!.m == 0 } ?? candidates[0]
            }
        }
        let result = chosen!
        if c.scope == "GLOBAL" {
            hand = (result + 1) % c.frames
        } else {
            owner.hand = (result + 1) % c.frames
        }
        return result
    }
    func access(_ a: Access) throws {
        fixed = true
        cursor += 1
        let owner = try process(a.pid)
        if a.address >= owner.pages.count * c.page {
            owner.segfaults += 1
            emit("SEGFAULT P\(a.pid) \(hex(a.address))")
            return
        }
        let p = owner.pages[a.address / c.page]
        if a.op == "W" && p.ro {
            owner.protfaults += 1
            emit("PROTFAULT P\(a.pid) \(hex(a.address))")
            return
        }
        time += 1
        owner.accesses += 1
        let switched = previous >= 0 && previous != a.pid
        if switched {
            switches += 1
            if c.asid == "OFF" {
                for i in tlb.indices {
                    tlb[i].removeAll()
                }
            }
        }
        previous = a.pid
        let set = p.number % c.sets
        let hitIndex = tlb[set].firstIndex { $0 === p }
        var fault = false, result: String
        if let index = hitIndex {
            tlb[set].remove(at: index)
            tlbhits += 1
            result = "TLBHIT"
        } else if p.frame >= 0 {
            result = "HIT"
        } else {
            fault = true
            faults += 1
            owner.faults += 1
            if p.slot >= 0 {
                swapin += 1
                result = "FAULT SWAPIN"
            } else {
                zero += 1
                result = "FAULT ZERO"
            }
            var frame: Int? = nil
            if c.scope == "GLOBAL" || owner.resident < quota(a.pid) {
                frame = frames.firstIndex { $0 == nil }
            }
            if frame == nil {
                let candidates = frames.indices.filter { f in
                    guard let page = frames[f] else {
                        return false
                    }
                    return c.scope == "GLOBAL" || page.pid == a.pid
                }
                frame = choose(candidates, owner)
                let victim = frames[frame!]!
                result += " evict=" + victim.label
                invalidate(victim)
                if victim.m == 1 {
                    write(victim)
                    result += " writeback"
                }
                victim.frame = -1
            }
            let f = frame!
            frames[f] = p
            p.frame = f
            p.load = time
            p.uses = 0
            p.m = 0
            p.age = 0
            owner.peak = max(owner.peak, owner.resident)
        }
        if tlb[set].count == c.tlb / c.sets {
            tlb[set].removeFirst()
        }
        tlb[set].append(p)
        p.r = 1
        if a.op == "W" {
            p.m = 1
        }
        p.last = time
        p.uses += 1
        p.ever = true
        p.references += 1
        owner.history.append(p.number)
        faultHistory.append(fault)
        log.append(.access(a))
        let interrupt = c.tick > 0 && time % c.tick == 0
        if interrupt {
            for case let page? in frames {
                page.age = page.age / 2 + 128 * page.r
                page.r = 0
            }
        }
        if trace {
            emit("t=\(time) P\(a.pid) \(a.op) \(hex(a.address)) page=\(p.number) frame=\(p.frame) phys=\(hex(p.frame * c.page + a.address % c.page)) \(result)" +
                (switched ? " switch" : ""))
            if interrupt {
                emit("t=\(time) tick")
            }
        }
    }
    func exit(_ pid: Int) throws {
        let p = try process(pid)
        var count = 0, slots = 0
        for page in p.pages {
            if page.frame >= 0 {
                frames[page.frame] = nil
                page.frame = -1
                count += 1
            }
            invalidate(page)
            if page.slot >= 0 {
                swap.removeValue(forKey: page.slot)
                page.slot = -1
                slots += 1
            }
        }
        p.exited = true
        log.append(.exit(pid))
        emit("EXIT P\(pid) freed=\(count) slots=\(slots)")
    }
    func attributes(_ cmd: String, _ pid: Int, _ first: Int, _ last: Int, _ protection: String = "") throws {
        let p = try process(pid)
        guard first <= last && last < p.pages.count else {
            throw CommandError.message("invalid page range")
        }
        for i in first...last {
            if cmd == "PROTECT" {
                p.pages[i].ro = protection == "RO"
            } else {
                p.pages[i].locked = cmd == "LOCK"
            }
        }
        if cmd != "PROTECT" {
            log.append(.lock(pid, first, last, cmd == "LOCK"))
        }
    }
    func clean() {
        var count = 0
        for case let p? in frames where p.m == 1 {
            write(p)
            count += 1
        }
        log.append(.clean)
        emit("CLEAN written=\(count)")
    }
    func rerun(_ policy: String, _ count: Int) throws -> Simulation {
        var config = c
        config.policy = policy
        config.frames = count
        let references: [Access] = log.compactMap { event in
            if case let .access(a) = event {
                return a
            }
            return nil
        }
        let replay = Simulation(config, references, silent: true)
        for pid in pids {
            try replay.declare(pid, processes[pid]!.pages.count)
        }
        for event in log {
            switch event {
            case let .access(a):
                try replay.access(a)
            case let .exit(pid):
                try replay.exit(pid)
            case .clean:
                replay.clean()
            case let .lock(pid, first, last, locked):
                try replay.attributes(
                    locked ? "LOCK" : "UNLOCK",
                    pid,
                    first,
                    last
                )
            }
        }
        return replay
    }
    func summary() {
        emit("SUMMARY policy=\(c.policy) scope=\(c.scope) time=\(time)")
        let seg = processes.values.reduce(0) { $0 + $1.segfaults },
            prot = processes.values.reduce(0) { $0 + $1.protfaults }
        emit(
            "total faults=\(faults) zero=\(zero) swapin=\(swapin) faultrate=\(ratio(faults, time)) tlbhits=\(tlbhits) tlbrate=\(ratio(tlbhits, time)) writebacks=\(writebacks) switches=\(switches) segfaults=\(seg) protfaults=\(prot)"
        )
        for pid in pids {
            let p = processes[pid]!
            emit("P\(pid) accesses=\(p.accesses) faults=\(p.faults) writebacks=\(p.writebacks) segfaults=\(p.segfaults) protfaults=\(p.protfaults) resident=\(p.resident) peak=\(p.peak)" +
                (c.scope == "LOCAL" ? " quota=\(quota(pid))" : "") + (p.exited ? " exited" : ""))
        }
    }
    func frameDump() {
        emit("FRAMES used=\(frames.compactMap { $0 }.count)/\(c.frames)")
        for i in frames.indices {
            if let p = frames[i] {
                emit("\(i) \(p.label) R=\(p.r) M=\(p.m) load=\(p.load) last=\(p.last) uses=\(p.uses) age=\(p.age)" +
                    (p.locked ? " locked" : ""))
            } else {
                emit("\(i) free")
            }
        }
        if ["CLOCK", "ECLOCK", "WSCLOCK"].contains(c.policy) {
            emit(c.scope == "GLOBAL" ? "hand=\(hand)" : "hand" + pids.map { " P\($0)=\(processes[$0]!.hand)" }.joined())
        }
    }
    func pageTable(_ pid: Int) throws {
        let p = try process(pid)
        emit("PAGETABLE P\(pid) pages=\(p.pages.count) resident=\(p.resident)")
        for page in p.pages where page.ever {
            let info = page.frame >= 0 ? "frame=\(page.frame) R=\(page.r) M=\(page.m)" : page
                .slot >= 0 ? "swap=\(page.slot)" : "zero"
            emit("\(page.number) \(info)" + (page.ro ? " RO" : "") + (page.locked ? " locked" : ""))
        }
    }
    func compare() throws {
        emit("COMPARE accesses=\(time) frames=\(c.frames)")
        var results: [String: Simulation] = [:]
        for policy in policies {
            let r = try rerun(policy, c.frames)
            results[policy] = r
            emit("\(policy) faults=\(r.faults) writebacks=\(r.writebacks) tlbhits=\(r.tlbhits)")
        }
        let ranking = policies.sorted { a, b in
            let x = results[a]!, y = results[b]!
            if x.faults != y.faults {
                return x.faults < y.faults
            }
            if x.writebacks != y.writebacks {
                return x.writebacks < y.writebacks
            }
            return policies.firstIndex(of: a)! < policies.firstIndex(of: b)!
        }
        emit("ranking " + ranking.joined(separator: " "))
    }
    func execute(_ t: [String]) throws {
        let cmd = t[0]
        if cmd.first!.isNumber {
            try access(Access(pid: Int(cmd)!, op: t[1], address: address(t[2])))
            return
        }
        switch cmd {
        case "PROCESS":
            try declare(Int(t[1])!, Int(t[2])!)
        case "EXIT":
            try exit(Int(t[1])!)
        case "PROTECT", "LOCK", "UNLOCK":
            try attributes(
                cmd,
                Int(t[1])!,
                Int(t[2])!,
                Int(t[3])!,
                t.count > 4 ? t[4] : ""
            )
        case "TRACE":
            trace = t[1] == "ON"
        case "SUMMARY":
            summary()
        case "FRAMES":
            frameDump()
        case "PAGETABLE":
            try pageTable(Int(t[1])!)
        case "TLB":
            emit("TLB used=\(tlb.reduce(0) { $0 + $1.count })/\(c.tlb) sets=\(c.sets)")
            for i in tlb.indices {
                emit("set \(i):" + tlb[i].reversed().map { " \($0.label)->\($0.frame)" }.joined())
            }
        case "SWAP":
            emit("SWAP used=\(swap.count)")
            for slot in swap.keys.sorted() {
                emit("\(slot) \(swap[slot]!.label)")
            }
        case "CLEAN":
            clean()
        case "COMPARE":
            try compare()
        case "CURVE":
            let policy = t[1], lo = Int(t[2])!, hi = Int(t[3])!
            guard policies.contains(policy) else {
                throw CommandError.message("unknown policy")
            }
            guard lo >= 1 && lo <= hi && hi <= 16 && !(c.scope == "LOCAL" && lo < processes.count)
            else {
                throw CommandError.message("invalid frame range")
            }
            emit("CURVE \(policy) frames=\(lo)..\(hi)")
            var previousFaults = Int.max
            for f in lo...hi {
                let value = try rerun(policy, f).faults
                emit("F=\(f) faults=\(value)" + (value > previousFaults ? " ANOMALY" : ""))
                previousFaults = value
            }
        case "EAT":
            let total = Int(t[1])! * time + Int(t[2])! * (2 * time - tlbhits) + Int(t[3])! * (swapin + writebacks)
            emit(time == 0 ? "EAT accesses=0" :
                "EAT accesses=\(time) total=\(total) average=\(decimal(100 * total / time))")
        case "TIMELINE":
            let w = Int(t[1])!
            guard w >= 1 else {
                throw CommandError.message("invalid window")
            }
            var text = "TIMELINE window=\(w)"
            for i in stride(from: 0, to: faultHistory.count, by: w) {
                text += " \(faultHistory[i..<min(i + w, faultHistory.count)].filter { $0 }.count)"
            }
            emit(text)
        case "WSET":
            let pid = Int(t[1])!, p = try process(pid), w = Int(t[2])!
            guard w >= 1 else {
                throw CommandError.message("invalid window")
            }
            let pages = Set(p.history.suffix(w)).sorted()
            emit("WSET P\(pid) window=\(w) size=\(pages.count)" + pages.map { " \($0)" }.joined())
        case "HOT":
            let pid = Int(t[1])!, p = try process(pid), k = Int(t[2])!
            guard k >= 1 else {
                throw CommandError.message("invalid count")
            }
            let pages = p.pages.filter { $0.references > 0 }.sorted { a, b in
                a.references != b.references ? a.references > b.references : a.number < b.number
            }
            emit("HOT P\(pid)" + pages.prefix(k).map { " \($0.number):\($0.references)" }.joined())
        default:
            break
        }
    }
}
let n = Int(readLine()!)!
var commands: [[String]] = []
for _ in 0..<n {
    let t = readLine()!.split(separator: " ").map(String.init)
    if t[0] == "LOOP" {
        let start = address(t[3]), interval = Int(t[4])!, length = Int(t[5])!, repeats = Int(t[6])!
        for _ in 0..<repeats {
            for j in 0..<length {
                commands.append([t[1], t[2], hex(start + j * interval)])
            }
        }
    } else if t[0] == "RAND" {
        let lo = address(t[2]), hi = address(t[3]), count = Int(t[4])!, rate = Int(t[6])!
        var x = Int(t[5])!
        for _ in 0..<count {
            x = x * 48271 % 2147483647
            let a = lo + x % (hi - lo)
            x = x * 48271 % 2147483647
            commands.append([t[1], x % 100 < rate ? "W" : "R", hex(a)])
        }
    } else {
        commands.append(t)
    }
}
var simulation: Simulation? = nil
for i in commands.indices {
    let t = commands[i]
    do {
        if t[0] == "SYSTEM" {
            simulation = nil
            let c = try settings(t)
            var future: [Access] = []
            for j in (i + 1)..<commands.count {
                let line = commands[j]
                if line[0] == "SYSTEM" {
                    break
                }
                if line[0].first!.isNumber {
                    future.append(Access(
                        pid: Int(line[0])!,
                        op: line[1],
                        address: address(line[2])
                    ))
                }
            }
            simulation = Simulation(c, future)
            print(c.description)
        } else if let current = simulation {
            try current.execute(t)
        } else {
            print("ERROR no system")
        }
    } catch {
        if case CommandError.message(let message) = error {
            print("ERROR " + message)
        }
    }
}
