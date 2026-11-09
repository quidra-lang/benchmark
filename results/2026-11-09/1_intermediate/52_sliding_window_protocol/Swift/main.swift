import Foundation

let keys = [
    "PROTOCOL",
    "FRAMES",
    "WINDOW",
    "SEQBITS",
    "TIMEOUT",
    "DELAY",
    "INTERVAL",
    "MAXTICKS",
    "DUPACK",
    "NAK",
    "BACKOFF",
    "CONGESTION",
    "UNSAFE",
    "TRACE",
    "RANDOM",
    "LOSEDATA",
    "LOSECTRL",
    "CORRUPTDATA",
    "CORRUPTCTRL",
    "DELAYDATA",
    "DELAYCTRL",
    "SNAPSHOT"
]
var output: [String] = []
func modulo(_ a: Int, _ b: Int) -> Int {
    (a % b + b) % b
}
func fixed(_ numerator: Int, _ denominator: Int, _ digits: Int) -> String {
    let scale = digits == 2 ? 100 : 10
    let value = denominator == 0 ? 0 : numerator * scale / denominator
    let fraction = String(value % scale)
    return "\(value / scale)." + String(repeating: "0", count: digits - fraction.count) + fraction
}
func stamp(_ tick: Int) -> String {
    tick < 0 ? "-" : String(tick)
}
struct SettingsError: Error { let message: String }
struct Config {
    var name: String
    var protocolName = ""
    var trace = "ALL"
    var n = 0
    var w = 0
    var k = 0
    var timeout = 0
    var delay = 0
    var interval = 0
    var limit = 1000
    var dupack = 0
    var nak = false
    var backoff = false
    var congestion = false
    var unsafeWindow = false
    var random: (seed: Int, loss: Int, corruption: Int)?
    var lostData: Set<Int> = []
    var lostControl: Set<Int> = []
    var corruptData: Set<Int> = []
    var corruptControl: Set<Int> = []
    var delayData: [Int: Int] = [:]
    var delayControl: [Int: Int] = [:]
    var snapshots: Set<Int> = []
}
func validate(_ name: String, _ lines: [[String]]) throws -> Config {
    var values: [String: [String]] = [:]
    func fail(_ message: String) throws -> Never {
        throw SettingsError(message: message)
    }
    for line in lines {
        let key = line[0]
        guard let index = keys.firstIndex(of: key) else {
            try fail("unknown key \(key)")
        }
        if values[key] != nil {
            try fail("duplicate key \(key)")
        }
        let count = line.count - 1
        if key == "RANDOM" ? count != 3 : index >= 15 ? count < 1 : count != 1 {
            try fail("wrong number of values for \(key)")
        }
        values[key] = Array(line.dropFirst())
    }
    for key in keys.prefix(6) {
        if values[key] == nil {
            try fail("missing key \(key)")
        }
    }
    for (index, key) in keys.enumerated() {
        guard let v = values[key] else {
            continue
        }
        var valid = true
        switch index {
        case 0:
            valid = ["SW", "GBN", "SR"].contains(v[0])
        case 9...12:
            valid = ["ON", "OFF"].contains(v[0])
        case 13:
            valid = ["ALL", "SENDER", "RECEIVER", "NONE"].contains(v[0])
        case 14:
            let numbers = v.map { Int($0)! }
            valid = (1...2147483646)
                .contains(numbers[0]) && numbers[1] >= 0 && numbers[2] >= 0 && numbers[1] + numbers[2] <= 100
        case 15...21:
            var seen: Set<Int> = []
            for value in v {
                let parts = value.split(separator: ":").map { Int($0)! }
                let lower = index == 21 ? 0 : 1
                let upper = index == 21 ? 2000 : 9999
                if !(lower...upper).contains(parts[0]) || !seen.insert(parts[0]).inserted {
                    valid = false
                }
                if index == 19 || index == 20 {
                    if !(1...50).contains(parts[1]) {
                        valid = false
                    }
                }
            }
        default:
            let number = Int(v[0])!
            let lower = index == 6 ? 0 : 1
            let upper: Int
            switch index {
            case 1:
                upper = 60
            case 2:
                upper = 32
            case 3:
                upper = 6
            case 4:
                upper = 50
            case 7:
                upper = 2000
            default:
                upper = 10
            }
            valid = (lower...upper).contains(number)
        }
        if !valid {
            try fail("bad value for \(key)")
        }
    }
    func get(_ key: String, _ fallback: String) -> String {
        values[key]?.first ?? fallback
    }
    func number(_ key: String, _ fallback: Int) -> Int {
        Int(get(key, String(fallback)))!
    }
    var c = Config(name: name)
    c.protocolName = get("PROTOCOL", "")
    c.n = number("FRAMES", 0)
    c.w = number("WINDOW", 0)
    c.k = number("SEQBITS", 0)
    c.timeout = number("TIMEOUT", 0)
    c.delay = number("DELAY", 0)
    c.interval = number("INTERVAL", 0)
    c.limit = number("MAXTICKS", 1000)
    c.dupack = number("DUPACK", 0)
    c.nak = get("NAK", "OFF") == "ON"
    c.backoff = get("BACKOFF", "OFF") == "ON"
    c.congestion = get("CONGESTION", "OFF") == "ON"
    c.unsafeWindow = get("UNSAFE", "OFF") == "ON"
    c.trace = get("TRACE", "ALL")
    if c.protocolName == "SR" && values["DUPACK"] != nil {
        try fail("DUPACK not supported for SR")
    }
    let upper = c.protocolName == "SW" ? 1 : c.protocolName == "GBN" ? (1 << c.k) - 1 : 1 << (c.k - 1)
    if c.w > upper && !(c.unsafeWindow && c.protocolName != "SW") {
        try fail("window \(c.w) exceeds limit \(upper) for \(c.protocolName)")
    }
    if let v = values["RANDOM"] {
        c.random = (Int(v[0])!, Int(v[1])!, Int(v[2])!)
    }
    func set(_ key: String) -> Set<Int> {
        Set((values[key] ?? []).map { Int($0)! })
    }
    func delays(_ key: String) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for value in values[key] ?? [] {
            let parts = value.split(separator: ":").map { Int($0)! }
            result[parts[0]] = parts[1]
        }
        return result
    }
    c.lostData = set("LOSEDATA")
    c.lostControl = set("LOSECTRL")
    c.corruptData = set("CORRUPTDATA")
    c.corruptControl = set("CORRUPTCTRL")
    c.delayData = delays("DELAYDATA")
    c.delayControl = delays("DELAYCTRL")
    c.snapshots = set("SNAPSHOT")
    if let conflict = c.lostData.intersection(c.corruptData)
        .min()
    {
        try fail("data #\(conflict) both lost and corrupted")
    }
    if let conflict = c.lostControl.intersection(c.corruptControl)
        .min()
    {
        try fail("control #\(conflict) both lost and corrupted")
    }
    return c
}
struct Transmission {
    let arrival: Int
    let number: Int
    let value: Int
    let outcome: Int
    let nak: Bool
}
struct Result {
    let name: String
    let protocolName: String
    let status: String
    let delivered: Int
    let data: Int
    let completion: Int
    let order: Int
}
@MainActor
final class Simulation {
    let c: Config
    let sr: Bool
    let modulus: Int
    var dataEvents: [Transmission] = []
    var controlEvents: [Transmission] = []
    var queue: [Int] = []
    var buffer: [Int: Int] = [:]
    var acknowledged: [Bool]
    var timers: [Int]
    var tx: [Int]
    var first: [Int]
    var deliveredAt: [Int]
    var ackedAt: [Int]
    var tick = 0
    var base = 0
    var high = 0
    var next = 0
    var duration: Int
    var timer = -1
    var duplicates = 0
    var receiver = 0
    var cwnd = 1
    var threshold: Int
    var credit = 0
    var random: Int
    var nakSent = false
    var data = 0
    var control = 0
    var resent = 0
    var naks = 0
    var timeouts = 0
    var fast = 0
    var lostData = 0
    var lostControl = 0
    var corruptData = 0
    var corruptControl = 0
    var delivered = 0
    var errors = 0
    var discarded = 0
    var maxBuffer = 0
    var latency = 0
    init(_ config: Config) {
        c = config
        sr = config.protocolName == "SR"
        modulus = 1 << config.k
        duration = config.timeout
        threshold = config.w
        random = config.random?.seed ?? 0
        acknowledged = Array(repeating: false, count: config.n)
        timers = Array(repeating: -1, count: config.n)
        tx = Array(repeating: 0, count: config.n)
        first = Array(repeating: -1, count: config.n)
        deliveredAt = Array(repeating: -1, count: config.n)
        ackedAt = Array(repeating: -1, count: config.n)
    }
    var effective: Int {
        c.congestion ? min(c.w, cwnd) : c.w
    }
    func log(_ side: String, _ text: String) {
        if c.trace == "ALL" || c.trace == side || side == "ALWAYS" {
            output.append("\(tick) \(text)")
        }
    }
    func outcome(_ isData: Bool, _ number: Int) -> Int {
        var result = 0
        if let option = c.random {
            random = random * 48271 % 2147483647
            let value = random % 100
            result = value < option.loss ? 1 : value < option.loss + option.corruption ? 2 : 0
        }
        if (isData ? c.lostData : c.lostControl).contains(number) {
            result = 1
        }
        if (isData ? c.corruptData : c.corruptControl).contains(number) {
            result = 2
        }
        return result
    }
    func sendControl(_ nak: Bool, _ value: Int) {
        control += 1
        if nak {
            naks += 1
        }
        log("RECEIVER", "\(nak ? "NAK" : "ACK") a=\(value) #\(control)")
        let event = Transmission(
            arrival: tick + c.delay + c.delayControl[control, default: 0],
            number: control,
            value: value,
            outcome: outcome(false, control),
            nak: nak
        )
        controlEvents.append(event)
    }
    func deliver(_ payload: Int) {
        if payload == receiver {
            log("RECEIVER", "DELIVER f=\(receiver)")
            delivered += 1
            if deliveredAt[payload] < 0 {
                deliveredAt[payload] = tick
            }
            latency += tick - first[payload]
        } else {
            log("RECEIVER", "DELIVER f=\(receiver) wrong=\(payload)")
            errors += 1
        }
        receiver += 1
        nakSent = false
    }
    func discard(_ sequence: Int) {
        discarded += 1
        log("RECEIVER", "DISCARD seq=\(sequence)")
    }
    func receive(_ e: Transmission) {
        if e.outcome != 0 {
            if e.outcome == 1 {
                lostData += 1
            } else {
                corruptData += 1
            }
            log("RECEIVER", "\(e.outcome == 1 ? "LOST" : "CORRUPT") data #\(e.number)")
            return
        }
        let sequence = e.value % modulus
        log("RECEIVER", "RECV seq=\(sequence) #\(e.number)")
        if !sr {
            if sequence == receiver % modulus {
                deliver(e.value)
                sendControl(false, sequence)
            } else {
                discard(sequence)
                if c.nak && !nakSent {
                    sendControl(true, receiver % modulus)
                    nakSent = true
                } else if receiver > 0 {
                    sendControl(false, (receiver - 1) % modulus)
                }
            }
            return
        }
        let offset = modulo(sequence - receiver, modulus)
        let position = receiver + offset
        if offset < c.w {
            if buffer[position] != nil {
                discard(sequence)
                sendControl(false, sequence)
            } else if offset == 0 {
                deliver(e.value)
                while let payload = buffer.removeValue(forKey: receiver) {
                    deliver(payload)
                }
                sendControl(false, sequence)
            } else {
                buffer[position] = e.value
                maxBuffer = max(maxBuffer, buffer.count)
                log("RECEIVER", "BUFFER f=\(position)")
                sendControl(false, sequence)
                if c.nak && !nakSent {
                    sendControl(true, receiver % modulus)
                    nakSent = true
                }
            }
        } else {
            discard(sequence)
            if modulo(receiver - sequence, modulus) <= c.w {
                sendControl(false, sequence)
            }
        }
    }
    func goBack() {
        next = base
        timer = -1
        duplicates = 0
    }
    func increase(_ count: Int) {
        if !c.congestion {
            return
        }
        for _ in 0..<count {
            if cwnd >= c.w {
                break
            }
            if cwnd < threshold {
                cwnd += 1
            } else {
                credit += 1
                if credit == cwnd {
                    cwnd += 1
                    credit = 0
                }
            }
        }
    }
    func decrease(_ timeout: Bool) {
        if !c.congestion {
            return
        }
        threshold = max(cwnd / 2, 1)
        cwnd = timeout ? 1 : threshold
        credit = 0
    }
    func cwndLine(_ oldWindow: Int, _ oldThreshold: Int) {
        if c.congestion && (oldWindow != cwnd || oldThreshold != threshold) {
            log("SENDER", "CWND \(cwnd) ssthresh=\(threshold)")
        }
    }
    func controlArrival(_ e: Transmission) {
        let kind = e.nak ? "NAK" : "ACK"
        if e.outcome != 0 {
            if e.outcome == 1 {
                lostControl += 1
            } else {
                corruptControl += 1
            }
            log("SENDER", "\(e.outcome == 1 ? "LOST" : "CORRUPT") \(kind.lowercased()) #\(e.number)")
            return
        }
        let oldWindow = cwnd, oldThreshold = threshold, oldBase = base
        let frame = base + modulo(e.value - base, modulus)
        let accepted = sr ? frame < high && !acknowledged[frame] : e.nak ? frame <= high : frame < high
        if accepted {
            if sr {
                timers[frame] = -1
                if e.nak {
                    if !queue.contains(frame) {
                        queue.append(frame)
                    }
                } else {
                    acknowledged[frame] = true
                    queue.removeAll { $0 == frame }
                    if ackedAt[frame] < 0 {
                        ackedAt[frame] = tick
                    }
                    while base < high && acknowledged[base] {
                        base += 1
                    }
                    increase(1)
                }
            } else {
                base = frame + (e.nak ? 0 : 1)
                increase(base - oldBase)
                for f in oldBase..<base {
                    if ackedAt[f] < 0 {
                        ackedAt[f] = tick
                    }
                }
            }
            if base > oldBase {
                duration = c.timeout
                duplicates = 0
            }
            if !sr {
                if e.nak {
                    goBack()
                } else {
                    next = max(next, base)
                    timer = base == next ? -1 : tick + duration
                }
            }
            if e.nak {
                decrease(false)
            }
            log("SENDER", "GOT\(kind) a=\(e.value) #\(e.number) base=\(base)")
        } else {
            log("SENDER", "OLD\(kind) a=\(e.value) #\(e.number)")
            if !sr && !e.nak && c.dupack > 0 && base >= 1 && e.value == (base - 1) % modulus {
                duplicates += 1
                if duplicates == c.dupack {
                    fast += 1
                    log("SENDER", "FASTRETX f=\(base)")
                    goBack()
                    decrease(false)
                }
            }
        }
        cwndLine(oldWindow, oldThreshold)
    }
    func timeout(_ frame: Int) {
        let oldWindow = cwnd, oldThreshold = threshold
        timeouts += 1
        log("SENDER", "TIMEOUT f=\(frame)")
        if sr {
            timers[frame] = -1
            if !queue.contains(frame) {
                queue.append(frame)
            }
        } else {
            goBack()
        }
        if c.backoff {
            duration = min(duration * 2, c.timeout * 8)
        }
        decrease(true)
        cwndLine(oldWindow, oldThreshold)
    }
    func send(_ frame: Int) {
        data += 1
        let retry = tx[frame] > 0
        if retry {
            resent += 1
        } else {
            first[frame] = tick
        }
        tx[frame] += 1
        log("SENDER", "\(retry ? "RESEND" : "SEND") f=\(frame) seq=\(frame % modulus) #\(data)")
        let event = Transmission(
            arrival: tick + c.delay + c.delayData[data, default: 0],
            number: data,
            value: frame,
            outcome: outcome(true, data),
            nak: false
        )
        dataEvents.append(event)
        if sr {
            timers[frame] = tick + duration
        } else if timer < 0 {
            timer = tick + duration
        }
    }
    func snapshot() {
        var sender = "", receiving = ""
        for f in 0..<c.n {
            if sr ? acknowledged[f] : f < base {
                sender += "A"
            } else if sr ? queue.contains(f) : next <= f && f < high {
                sender += "R"
            } else if sr ? f < high : f < next {
                sender += "O"
            } else {
                sender += f < base + effective ? "W" : "."
            }
            if f < receiver {
                receiving += "D"
            } else if sr && buffer[f] != nil {
                receiving += "B"
            } else {
                receiving += (sr ? f < receiver + c.w : f == receiver) ? "W" : "."
            }
        }
        log("ALWAYS", "SNAPSHOT sender=\(sender) receiver=\(receiving)")
    }
    func run(_ order: Int) -> Result {
        output.append("config: \(c.protocolName) n=\(c.n) w=\(c.w) k=\(c.k) T=\(c.timeout) d=\(c.delay)")
        func on(_ value: Bool) -> String {
            value ? "on" : "off"
        }
        let randomOption = c.random.map { "\($0.seed)/\($0.loss)/\($0.corruption)" } ?? "off"
        let dupack = c.dupack == 0 ? "off" : String(c.dupack)
        output
            .append(
                "options: interval=\(c.interval) limit=\(c.limit) dupack=\(dupack) nak=\(on(c.nak)) backoff=\(on(c.backoff)) congestion=\(on(c.congestion)) unsafe=\(on(c.unsafeWindow)) trace=\(c.trace.lowercased()) random=\(randomOption)"
            )
        var complete = false
        for currentTick in 0...c.limit {
            tick = currentTick
            for event in dataEvents.filter({ $0.arrival == tick }) {
                receive(event)
            }
            for event in controlEvents.filter({ $0.arrival == tick }) {
                controlArrival(event)
            }
            complete = base == c.n
            if !complete {
                if sr {
                    for frame in base..<high {
                        if timers[frame] == tick {
                            timeout(frame)
                        }
                    }
                } else if timer == tick {
                    timeout(base)
                }
                if sr {
                    if !queue.isEmpty {
                        send(queue.removeFirst())
                    } else if high < c.n && high < base + effective && high * c.interval <= tick {
                        let frame = high
                        high += 1
                        send(frame)
                    }
                } else if next < c.n && next < base + effective && (next < high || next * c.interval <= tick) {
                    let frame = next
                    next += 1
                    high = max(high, next)
                    send(frame)
                }
            }
            if c.snapshots.contains(tick) {
                snapshot()
            }
            if complete || tick == c.limit {
                log("ALWAYS", complete ? "DONE" : "ABORT")
                break
            }
        }
        for f in 0..<c.n {
            output
                .append(
                    "frame \(f): seq=\(f % modulus) tx=\(tx[f]) first=\(stamp(first[f])) delivered=\(stamp(deliveredAt[f])) acked=\(stamp(ackedAt[f]))"
                )
        }
        output
            .append(
                "totals: data=\(data) resent=\(resent) control=\(control) nak=\(naks) timeouts=\(timeouts) fastretx=\(fast)"
            )
        output
            .append(
                "channel: lost_data=\(lostData) lost_ctrl=\(lostControl) corrupt_data=\(corruptData) corrupt_ctrl=\(corruptControl)"
            )
        output
            .append("receiver: delivered=\(delivered) errors=\(errors) discarded=\(discarded) max_buffer=\(maxBuffer)")
        let completion = complete ? String(tick) : "-"
        let goodput = complete ? fixed(delivered, tick, 2) : "-"
        let average = delivered == 0 ? "-" : fixed(latency, delivered, 2)
        output
            .append(
                "result: completion=\(completion) goodput=\(goodput) efficiency=\(fixed(delivered * 100, data, 1))% utilization=\(fixed(data * 100, tick + 1, 1))% latency=\(average)"
            )
        return Result(
            name: c.name,
            protocolName: c.protocolName,
            status: complete ? "complete" : "aborted",
            delivered: delivered,
            data: data,
            completion: tick,
            order: order
        )
    }
}
let count = Int(readLine()!)!
var results: [Result] = []
for order in 0..<count {
    let name = String(readLine()!.split(separator: " ")[1])
    var settings: [[String]] = []
    while let line = readLine(), line != "END" {
        settings.append(line.split(separator: " ").map(String.init))
    }
    output.append("== \(name) ==")
    do {
        let config = try validate(name, settings)
        results.append(Simulation(config).run(order))
    } catch let error as SettingsError {
        output.append("error: \(error.message)")
        results.append(Result(
            name: name,
            protocolName: "",
            status: "invalid",
            delivered: 0,
            data: 0,
            completion: 0,
            order: order
        ))
    } catch { fatalError("Unexpected settings error") }
}
output.append("== ranking ==")
let completed = results.filter { $0.status == "complete" }.sorted {
    let left = $0.delivered * $1.completion, right = $1.delivered * $0.completion
    if left != right {
        return left > right
    }
    let leftEfficiency = $0.delivered * $1.data, rightEfficiency = $1.delivered * $0.data
    if leftEfficiency != rightEfficiency {
        return leftEfficiency > rightEfficiency
    }
    return $0.order < $1.order
}
for (index, result) in completed.enumerated() {
    output
        .append(
            "\(index + 1). \(result.name) \(result.protocolName) goodput=\(fixed(result.delivered, result.completion, 2)) efficiency=\(fixed(result.delivered * 100, result.data, 1))%"
        )
}
for result in results where result.status != "complete" {
    output.append("- \(result.name) \(result.status)")
}
output.append("== protocols ==")
for protocolName in ["SW", "GBN", "SR"] {
    let runs = completed.filter { $0.protocolName == protocolName }
    if runs.isEmpty {
        continue
    }
    let delivered = runs.reduce(0) { $0 + $1.delivered }
    let ticks = runs.reduce(0) { $0 + $1.completion }
    let data = runs.reduce(0) { $0 + $1.data }
    output
        .append(
            "\(protocolName): runs=\(runs.count) goodput=\(fixed(delivered, ticks, 2)) efficiency=\(fixed(delivered * 100, data, 1))%"
        )
}
print(output.joined(separator: "\n"))
