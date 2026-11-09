import Foundation

struct InputError: Error {
    let text: String
}

func fail(_ text: String) throws -> Never {
    throw InputError(text: text)
}
let kinds = ["AND","OR","NAND","NOR","XOR","XNOR","NOT","BUF","MUX2","DFF"]

func validName(_ s: String, _ upper: Bool = false) -> Bool {
    let a = Array(s.utf8)
    let lo: UInt8 = upper ? 65 : 97
    let hi: UInt8 = upper ? 90 : 122
    return (1...16).contains(a.count) && (lo...hi).contains(a[0]) && a.allSatisfy {
        (lo...hi).contains($0) || (48...57).contains($0) || $0 == 95
    }
}

func numeric(_ s: String) -> Int? {
    guard (1...9).contains(s.count), s == "0" || s.first != "0", s.utf8.allSatisfy({
        (48...57).contains($0)
    }) else {
        return nil
    }
    return Int(s)
}

func num(_ s: String, _ positive: Bool = false) throws -> Int {
    guard let n = numeric(s), !positive || n > 0 else {
        try fail("bad number \(s)")
    }
    return n
}

func value(_ s: String) throws -> String {
    if !["0","1","X"].contains(s) {
        try fail("bad value \(s)")
    }
    return s
}

func bits(_ r: Int, _ n: Int) -> [String] {
    (0..<n).map {
        r & (1 << (n-1-$0)) == 0 ? "0" : "1"
    }
}

func gateValue(_ kind: String, _ v: [String]) -> String {
    var r: String
    switch kind {
        case "AND","NAND": r = v.contains("0") ? "0" : (v.contains("X") ? "X" : "1")
        case "OR","NOR": r = v.contains("1") ? "1" : (v.contains("X") ? "X" : "0")
        case "XOR","XNOR": r = v.contains("X") ? "X" : String(v.filter {
            $0 == "1"
        }.count % 2)
        case "MUX2": r = v[0] == "0" ? v[1] : (v[0] == "1" ? v[2] : (v[1] == v[2] ? v[1] : "X"))
        default: r = v[0]
    }
    if ["NAND","NOR","XNOR","NOT"].contains(kind) {
        r = r == "0" ? "1" : (r == "1" ? "0" : "X")
    }
    return r
}

struct Gate {
    let name: String
    let kind: String
    let inputs: [String]
    let output: String
    let delay: Int
}

struct Instance {
    let name: String
    let module: String
    let connections: [(String,String)]
}

enum Item {
    case gate(Gate)
    case instance(Instance)
}

struct Module {
    let name: String
    let inputs: [String]
    let outputs: [String]
    let body: [Item]
}
var modules: [String: Module] = [:]
var moduleOrder: [String] = []

func lookup(_ name: String) throws -> Module {
    guard let m = modules[name] else {
        try fail("unknown module \(name)")
    }
    return m
}

struct Circuit {
    let name: String
    let inputs: [String]
    let outputs: [String]
    var gates: [Gate] = []
    var signals: [String] = []
    var readers: [String: [Int]] = [:]
    var driver: [String: Int] = [:]
    var order: [Int]? = nil
    var dffs: [Int] {
        gates.indices.filter {
            gates[$0].kind == "DFF"
        }
    }
    init(_ module: Module) {
        name = module.name
        inputs = module.inputs
        outputs = module.outputs
        func expand(_ m: Module, _ prefix: String, _ ports: [String:String]) -> [Gate] {
            func actual(_ s: String) -> String {
                ports[s] ?? prefix + s
            }
            var result: [Gate] = []
            for item in m.body {
                switch item {
                    case .gate(let g): result.append(Gate(name: prefix+g.name, kind: g.kind, inputs: g.inputs.map(actual), output: actual(g.output), delay: g.delay))
                    case .instance(let i): result += expand(modules[i.module]!,prefix+i.name+".",Dictionary(uniqueKeysWithValues: i.connections.map {
                        ($0.0,actual($0.1))
                    }))
                }
            }
            return result
        }
        gates = expand(module,"",[:])
        signals = inputs + gates.map {
            $0.output
        }
        for s in signals {
            readers[s] = []
        }
        for (i,g) in gates.enumerated() {
            driver[g.output] = i
            for s in Set(g.inputs) {
                readers[s]!.append(i)
            }
        }
        var ready = Set(inputs + dffs.map {
            gates[$0].output
        }), remaining = Set(gates.indices.filter {
            gates[$0].kind != "DFF"
        }), sorted: [Int] = []
        while let i = remaining.sorted().first(where: {
            gates[$0].inputs.allSatisfy {
                ready.contains($0)
            }
        }) {
            sorted.append(i)
            ready.insert(gates[i].output)
            remaining.remove(i)
        }
        if remaining.isEmpty {
            order = sorted
        }
    }
    func combinational() throws {
        if !dffs.isEmpty {
            try fail("\(name) is not combinational")
        }
        if order == nil {
            try fail("\(name) has a combinational loop")
        }
        if inputs.count > 8 {
            try fail("too many inputs \(inputs.count)")
        }
    }
    func evaluate(_ b: [String], _ fault: String = "", _ stuck: String = "") -> String {
        var v = Dictionary(uniqueKeysWithValues: zip(inputs,b).map {
            ($0.0,$0.1)
        })
        if inputs.contains(fault) {
            v[fault] = stuck
        }
        for i in order! {
            let g = gates[i]
            v[g.output] = g.output == fault ? stuck : gateValue(g.kind,g.inputs.map {
                v[$0]!
            })
        }
        return outputs.map {
            v[$0]!
        }.joined()
    }
    func arrivals(_ sources: [String:Int]) -> ([String:Int],[String:Int],[String:String]) {
        var latest = sources
        var earliest = sources
        var previous: [String:String] = [:]
        for i in order! {
            let g = gates[i]
            let reached = g.inputs.filter {
                latest[$0] != nil
            }
            if let first = reached.first {
                let best = reached.dropFirst().reduce(first) {
                    latest[$1]! > latest[$0]! ? $1 : $0
                }
                latest[g.output] = latest[best]! + g.delay
                earliest[g.output] = reached.map {
                    earliest[$0]!
                }.min()! + g.delay
                previous[g.output] = best
            }
        }
        return (latest,earliest,previous)
    }
}

func path(_ previous: [String:String], _ end: String) -> String {
    var a = [end]
    while let s = previous[a.last!] {
        a.append(s)
    }
    return a.reversed().joined(separator: " -> ")
}

func define(_ header: [String], _ body: [(Int,[String])], _ headerLine: Int) {
    var line = headerLine
    do {
        if header.count < 5 || header[2] != "IN" || header.dropFirst(3).filter({
            $0 == "OUT"
        }).count != 1 || header.last == "OUT" {
            try fail("bad module header")
        }
        let name = header[1]
        if !validName(name,true) {
            try fail("bad module name \(name)")
        }
        if modules[name] != nil {
            try fail("duplicate module \(name)")
        }
        let split = header.dropFirst(3).firstIndex(of: "OUT")!
        let inputs = Array(header[3..<split])
        let outputs = Array(header[(split+1)...])
        var seen = Set<String>()
        var driven = Set(inputs)
        var used = Set<String>()
        var items: [Item] = []
        var reads: [(Int,String)] = []
        var count = 0
        for p in inputs + outputs {
            if !validName(p) {
                try fail("bad name \(p)")
            }
            if seen.contains(p) {
                try fail("duplicate port \(p)")
            }
            seen.insert(p)
        }
        for (n,w) in body {
            line = n
            if kinds.contains(w[0]) {
                if w.count < 5 || w[w.count-3] != "->" || w.filter({
                    $0 == "->"
                }).count != 1 {
                    try fail("bad gate syntax")
                }
                let kind = w[0]
                let gname = w[1]
                let ins = Array(w[2..<(w.count-3)])
                let out = w[w.count-2]
                let delay = w.last!
                if !validName(gname) {
                    try fail("bad name \(gname)")
                }
                let range = ["NOT","BUF"].contains(kind) ? 1...1 : (kind == "MUX2" ? 3...3 : (kind == "DFF" ? 2...2 : 2...8))
                if !range.contains(ins.count) {
                    try fail("bad input count \(ins.count) for \(kind)")
                }
                for s in ins + [out] {
                    if !validName(s) {
                        try fail("bad name \(s)")
                    }
                }
                guard let d = numeric(delay), d <= 1000 else {
                    try fail("bad delay \(delay)")
                }
                if used.contains(gname) {
                    try fail("duplicate name \(gname)")
                }
                if driven.contains(out) {
                    try fail("multiple drivers for \(out)")
                }
                used.insert(gname)
                driven.insert(out)
                count += 1
                items.append(.gate(Gate(name:gname,kind:kind,inputs:ins,output:out,delay:d)))
                reads += ins.map {
                    (n,$0)
                }
            } else if w[0] == "INST" {
                if w.count < 3 {
                    try fail("bad instance syntax")
                }
                let iname = w[1]
                if !validName(iname) {
                    try fail("bad name \(iname)")
                }
                let m = try lookup(w[2])
                var connections: [(String,String)] = []
                var ports = Set<String>()
                for word in w.dropFirst(3) {
                    let parts = word.components(separatedBy:"=")
                    if parts.count != 2 || parts[0].isEmpty || parts[1].isEmpty {
                        try fail("bad connection \(word)")
                    }
                    let p = parts[0]
                    let s = parts[1]
                    if !(m.inputs+m.outputs).contains(p) {
                        try fail("unknown port \(p)")
                    }
                    if ports.contains(p) {
                        try fail("duplicate connection \(p)")
                    }
                    if !validName(s) {
                        try fail("bad name \(s)")
                    }
                    ports.insert(p)
                    connections.append((p,s))
                }
                for p in m.inputs where !ports.contains(p) {
                    try fail("unconnected input \(p)")
                }
                if used.contains(iname) {
                    try fail("duplicate name \(iname)")
                }
                for (p,s) in connections where m.outputs.contains(p) {
                    if driven.contains(s) {
                        try fail("multiple drivers for \(s)")
                    }
                    driven.insert(s)
                }
                used.insert(iname)
                items.append(.instance(Instance(name:iname,module:m.name,connections:connections)))
                reads += connections.filter {
                    m.inputs.contains($0.0)
                }.map {
                    (n,$0.1)
                }
            } else {
                try fail("unknown statement \(w[0])")
            }
        }
        for (n,s) in reads + outputs.map({
            (headerLine,$0)
        }) {
            line = n
            if !driven.contains(s) {
                try fail("undriven signal \(s)")
            }
        }
        modules[name] = Module(name:name,inputs:inputs,outputs:outputs,body:items)
        moduleOrder.append(name)
        print("defined \(name) inputs \(inputs.count) outputs \(outputs.count) gates \(count) instances \(items.count-count)")
    } catch let e as InputError {
        print("error: line \(line): \(e.text)")
    } catch {
    }
}

struct Event {
    let time: Int
    let serial: Int
    let signal: String
    let value: String
}

final class Simulation {
    let circuit: Circuit
    var values: [String:String] = [:]
    var history: [String:[(Int,String)]] = [:]
    var watch: [String] = []
    var queue: [Event] = []
    var time = 0
    var serial = 0
    var processed = 0
    var halted = false
    init(_ circuit: Circuit) {
        self.circuit = circuit
        reset()
    }
    func reset() {
        values = Dictionary(uniqueKeysWithValues:circuit.signals.map {
            ($0,"X")
        })
        history = Dictionary(uniqueKeysWithValues:circuit.signals.map {
            ($0,[])
        })
        queue = []
        time = 0
        serial = 0
        processed = 0
        halted = false
    }
    func before(_ a: Event, _ b: Event) -> Bool {
        a.time < b.time || a.time == b.time && a.serial < b.serial
    }
    func schedule(_ t: Int, _ s: String, _ v: String) {
        queue.append(Event(time:t,serial:serial,signal:s,value:v))
        serial += 1
        var i = queue.count-1
        while i > 0 {
            let p = (i-1)/2
            if !before(queue[i],queue[p]) {
                break
            }
            queue.swapAt(i,p)
            i = p
        }
    }
    func pop() -> Event {
        let e = queue[0]
        let last = queue.removeLast()
        if !queue.isEmpty {
            queue[0] = last
            var i = 0
            while i*2+1 < queue.count {
                var c = i*2+1
                if c+1 < queue.count && before(queue[c+1],queue[c]) {
                    c += 1
                }
                if !before(queue[c],queue[i]) {
                    break
                }
                queue.swapAt(c,i)
                i = c
            }
        }
        return e
    }
    func run(_ end: Int) {
        var events = 0
        var glitches = 0
        while let first = queue.first, first.time < end {
            let t = first.time
            let original = values
            var changed = Set<String>()
            var count = 0
            while queue.first?.time == t {
                if count == 1000 {
                    print("halted: oscillation at time \(t)")
                    queue = []
                    time = t
                    halted = true
                    return
                }
                let e = pop()
                count += 1
                events += 1
                processed += 1
                let old = values[e.signal]!
                if old == e.value {
                    continue
                }
                values[e.signal] = e.value
                changed.insert(e.signal)
                for i in circuit.readers[e.signal]! {
                    let g = circuit.gates[i]
                    if g.kind != "DFF" {
                        schedule(t+g.delay,g.output,gateValue(g.kind,g.inputs.map {
                            values[$0]!
                        }))
                    }
                    else if e.signal == g.inputs[0] && old == "0" && e.value == "1" {
                        schedule(t+g.delay,g.output,values[g.inputs[1]]!)
                    }
                }
            }
            for s in changed {
                if values[s] == original[s] {
                    glitches += 1
                } else {
                    history[s]!.append((t,values[s]!))
                }
            }
            for s in watch where values[s] != original[s] {
                print("\(t) \(s) \(values[s]!)")
            }
        }
        time = end
        print("run \(end) events \(events) glitches \(glitches) pending \(queue.count)")
    }
    func input(_ s: String) throws {
        if !circuit.inputs.contains(s) {
            try fail("not an input \(s)")
        }
    }
    func signal(_ s: String) throws {
        if values[s] == nil {
            try fail("unknown signal \(s)")
        }
    }
    func parseTime(_ s: String) throws -> Int {
        let t = try num(s)
        if t < time {
            try fail("time \(t) is in the past")
        }
        return t
    }
    func describe(_ a: [String]) -> [String] {
        a.map {
            "\($0)=\(values[$0]!)"
        }
    }
}
var simulation: Simulation? = nil
let counts = ["BUILD":1,"RESET":0,"SET":3,"APPLY":2,"PULSE":3,"CLOCK":4,"RUN":1,"WATCH":1,"UNWATCH":1,"SHOW":0,"CHECK":2,"PROBE":1,"WAVE":2,"HISTORY":1,"ACTIVITY":1,"STATUS":0,"MODULES":0,"NETLIST":1,"HIERARCHY":1,"STATS":1,"TRUTHTABLE":1,"EQUIV":2,"FAULTS":1,"CRITICAL":1,"PERIOD":1]
let simCommands = Set(["RESET","SET","APPLY","PULSE","CLOCK","RUN","WATCH","UNWATCH","SHOW","CHECK","PROBE","WAVE","HISTORY","ACTIVITY","STATUS"])

func execute(_ w: [String]) throws {
    let cmd = w[0]
    let a = Array(w.dropFirst())
    guard let expected = counts[cmd] else {
        try fail("unknown command \(cmd)")
    }
    if a.count < expected || !["WATCH","UNWATCH","SHOW"].contains(cmd) && a.count != expected {
        try fail("wrong argument count")
    }
    if simCommands.contains(cmd) && simulation == nil {
        try fail("no circuit")
    }
    if ["SET","APPLY","PULSE","CLOCK","RUN"].contains(cmd) && simulation!.halted {
        try fail("simulation halted")
    }
    if cmd == "MODULES" {
        print("modules \(moduleOrder.count)")
        for n in moduleOrder {
            let m = modules[n]!
            print("\(n) inputs \(m.inputs.count) outputs \(m.outputs.count) gates \(Circuit(m).gates.count)")
        }
        return
    }
    if ["NETLIST","HIERARCHY","STATS","TRUTHTABLE","EQUIV","FAULTS","CRITICAL","PERIOD","BUILD"].contains(cmd) {
        let m = try lookup(a[0])
        var second: Circuit? = nil
        if cmd == "EQUIV" {
            second = Circuit(try lookup(a[1]))
        }
        let c = Circuit(m)
        switch cmd {
            case "BUILD": simulation = Simulation(c)
            print("built \(c.name) signals \(c.signals.count) gates \(c.gates.count)")
            case "NETLIST": print("netlist \(c.name) gates \(c.gates.count) signals \(c.signals.count)")
            for g in c.gates {
                print(([g.name,g.kind]+g.inputs+["->",g.output,String(g.delay)]).joined(separator:" "))
            }
            case "HIERARCHY":
            func show(_ m: Module, _ depth: Int) {
                for item in m.body {
                    if case .instance(let i) = item {
                        print(String(repeating:"  ",count:depth)+i.name+" "+i.module)
                        show(modules[i.module]!,depth+1)
                    }
                }
            }
            print(m.name)
            show(m,1)
            case "STATS":
            var levels = Dictionary(uniqueKeysWithValues:(c.inputs+c.dffs.map {
                c.gates[$0].output
            }).map {
                ($0,0)
            })
            if let order = c.order {
                for i in order {
                    let g = c.gates[i]
                    levels[g.output] = g.inputs.map {
                        levels[$0]!
                    }.max()! + 1
                }
            }
            print("stats \(c.name) gates \(c.gates.count) signals \(c.signals.count) depth \(c.order == nil ? "-" : String(levels.values.max() ?? 0))")
            print((["types"]+kinds.flatMap {
                k -> [String] in let n = c.gates.filter {
                    $0.kind == k
                }.count
                return n == 0 ? [] : [k,String(n)]
            }).joined(separator:" "))
            let busiest = c.signals.dropFirst().reduce(c.signals[0]) {
                c.readers[$1]!.count > c.readers[$0]!.count ? $1 : $0
            }
            print("max fanout \(busiest) \(c.readers[busiest]!.count)")
            case "TRUTHTABLE","EQUIV","FAULTS":
            try c.combinational()
            if let other = second {
                try other.combinational()
                if c.inputs.count != other.inputs.count || c.outputs.count != other.outputs.count {
                    try fail("port mismatch")
                }
            }
            let rows = (0..<(1 << c.inputs.count)).map {
                bits($0,c.inputs.count)
            }, outputs = (0..<(1 << c.inputs.count)).map {
                c.evaluate(bits($0,c.inputs.count))
            }
            if cmd == "TRUTHTABLE" {
                print((c.inputs+["|"]+c.outputs).joined(separator:" "))
                for (i,b) in rows.enumerated() {
                    print((b+["|"]+outputs[i].map(String.init)).joined(separator:" "))
                }
            }
            else if cmd == "EQUIV" {
                if let r = rows.indices.first(where: {
                    outputs[$0] != second!.evaluate(rows[$0])
                }) {
                    print("not equivalent at \(rows[r].joined()): \(outputs[r]) vs \(second!.evaluate(rows[r]))")
                } else {
                    print("equivalent")
                }
            }
            else {
                var missing: [String] = []
                var tests = Set<Int>()
                for s in c.signals {
                    for v in ["0","1"] {
                        if let r = rows.indices.first(where: {
                            outputs[$0] != c.evaluate(rows[$0],s,v)
                        }) {
                            tests.insert(r)
                        } else {
                            missing.append(s+"/"+v)
                        }
                    }
                }
                print("faults \(c.signals.count*2) detected \(c.signals.count*2-missing.count)")
                for f in missing {
                    print("undetected \(f)")
                }
                print((["tests"]+tests.sorted().map {
                    rows[$0].joined()
                }).joined(separator:" ").trimmingCharacters(in:.whitespaces))
            }
            case "CRITICAL","PERIOD":
            if cmd == "PERIOD" && c.dffs.isEmpty {
                try fail("\(c.name) has no flip-flops")
            }
            if c.order == nil {
                try fail("\(c.name) has a combinational loop")
            }
            let sources = cmd == "CRITICAL" ? Dictionary(uniqueKeysWithValues:c.inputs.map {
                ($0,0)
            }) : Dictionary(uniqueKeysWithValues:c.dffs.map {
                (c.gates[$0].output,c.gates[$0].delay)
            })
            let (latest,earliest,previous) = c.arrivals(sources)
            let ends = cmd == "CRITICAL" ? c.outputs : c.dffs.map {
                c.gates[$0].inputs[1]
            }
            if cmd == "CRITICAL" {
                for s in ends {
                    if let l = latest[s] {
                        print("\(s) min \(earliest[s]!) max \(l)")
                    } else {
                        print("\(s) unreachable")
                    }
                }
            }
            let reached = ends.filter {
                latest[$0] != nil
            }, prefix = cmd == "CRITICAL" ? "critical" : "flip-flops \(c.dffs.count) period"
            if let first = reached.first {
                let end = reached.dropFirst().reduce(first) {
                    latest[$1]! > latest[$0]! ? $1 : $0
                }
                print("\(prefix) \(latest[end]!): \(path(previous,end))")
            } else {
                print("\(prefix) none")
            }
            default: break
        }
        return
    }
    let s = simulation!
    let c = s.circuit
    switch cmd {
        case "RESET": s.reset()
        print("reset")
        case "SET": let t = try s.parseTime(a[0])
        try s.input(a[1])
        let v = try value(a[2])
        s.schedule(t,a[1],v)
        print("set \(a[1]) \(v) at \(t)")
        case "APPLY": let t = try s.parseTime(a[0])
        let b = a[1].map(String.init)
        if b.count != c.inputs.count || !b.allSatisfy({
            ["0","1","X"].contains($0)
        }) {
            try fail("bad vector \(a[1])")
        }
        for (p,v) in zip(c.inputs,b) {
            s.schedule(t,p,v)
        }
        print("apply \(a[1]) at \(t)")
        case "PULSE": try s.input(a[0])
        let t = try s.parseTime(a[1])
        let width = try num(a[2],true)
        s.schedule(t,a[0],"1")
        s.schedule(t+width,a[0],"0")
        print("pulse \(a[0]) \(t) \(t+width)")
        case "CLOCK": try s.input(a[0])
        let t = try s.parseTime(a[1])
        let half = try num(a[2],true)
        let count = try num(a[3],true)
        for i in 0..<count {
            s.schedule(t+i*half,a[0],i%2 == 0 ? "0" : "1")
        }
        print("clock \(a[0]) events \(count) last \(t+(count-1)*half)")
        case "RUN": let t = try num(a[0])
        if t <= s.time {
            try fail("time \(t) is not after \(s.time)")
        }
        s.run(t)
        case "WATCH","UNWATCH":
        var seen = Set<String>()
        for p in a {
            try s.signal(p)
            if cmd == "WATCH" && (s.watch.contains(p) || seen.contains(p)) {
                try fail("already watched \(p)")
            }
            if cmd == "UNWATCH" && (!s.watch.contains(p) || seen.contains(p)) {
                try fail("not watched \(p)")
            }
            seen.insert(p)
        }
        if cmd == "WATCH" {
            s.watch += a
        } else {
            s.watch.removeAll {
                seen.contains($0)
            }
        }
        print("watching " + (s.watch.isEmpty ? "nothing" : s.watch.joined(separator:" ")))
        case "SHOW": for p in a {
            try s.signal(p)
        }
        print((a.isEmpty ? s.describe(c.inputs)+["|"]+s.describe(c.outputs) : s.describe(a)).joined(separator:" "))
        case "CHECK": try s.signal(a[0])
        let v = try value(a[1])
        let actual = s.values[a[0]]!
        print("check \(a[0])=\(v) " + (v == actual ? "ok" : "failed (\(actual))"))
        case "PROBE":
        let p = a[0]
        try s.signal(p)
        if c.inputs.contains(p) {
            print("\(p)=\(s.values[p]!) driven by input")
        } else {
            let g = c.gates[c.driver[p]!]
            print("\(p)=\(s.values[p]!) driven by \(g.name) \(g.kind) \(s.describe(g.inputs).joined(separator:" ")) delay \(g.delay)")
        }
        print((["fanout",String(c.readers[p]!.count)]+c.readers[p]!.map {
            c.gates[$0].name
        }).joined(separator:" "))
        case "WAVE":
        let lo = try num(a[0])
        let hi = try num(a[1])
        if !(lo < hi && hi <= s.time) {
            try fail("bad range \(lo) \(hi)")
        }
        if s.watch.isEmpty {
            try fail("nothing watched")
        }
        for p in s.watch {
            var v = "X"
            var index = 0
            var wave = ""
            let changes = s.history[p]!
            for t in lo..<hi {
                while index < changes.count && changes[index].0 <= t {
                    v = changes[index].1
                    index += 1
                }
                wave += v
            }
            print("\(p) \(wave)")
        }
        case "HISTORY": let p = a[0]
        try s.signal(p)
        let h = s.history[p]!
        print((["history",p,"changes",String(h.count)]+h.map {
            "\($0.0):\($0.1)"
        }).joined(separator:" "))
        case "ACTIVITY": let k = try num(a[0],true)
        for p in c.signals.sorted(by: {
            s.history[$0]!.count == s.history[$1]!.count ? $0 < $1 : s.history[$0]!.count > s.history[$1]!.count
        }).prefix(k) {
            print("\(p) \(s.history[p]!.count)")
        }
        case "STATUS": print("circuit \(c.name) time \(s.time) pending \(s.queue.count) events \(s.processed) halted \(s.halted ? "yes" : "no")")
        print("values 0:\(s.values.values.filter { $0 == "0" }.count) 1:\(s.values.values.filter { $0 == "1" }.count) X:\(s.values.values.filter { $0 == "X" }.count)")
        default: break
    }
}
var lineNumber = 0
while let line = readLine() {
    lineNumber += 1
    if line == "END" {
        break
    }
    let w = line.components(separatedBy:" ")
    if w[0] == "MODULE" {
        let headerLine = lineNumber
        var body: [(Int,[String])] = []
        while let b = readLine() {
            lineNumber += 1
            if b == "ENDMODULE" {
                break
            }
            body.append((lineNumber,b.components(separatedBy:" ")))
        }
        define(w,body,headerLine)
    } else {
        do {
            try execute(w)
        } catch let e as InputError {
            print("error: line \(lineNumber): \(e.text)")
        } catch {
        }
    }
}
