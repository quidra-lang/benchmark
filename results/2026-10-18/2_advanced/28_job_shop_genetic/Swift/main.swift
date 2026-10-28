import Foundation
func percentage(_ a: Int, _ b: Int) -> String {
    let t = (2000*a+b)/(2*b);
    return "\(t/10).\(t%10)%"
}
func letter(_ number: Int) -> Character {
    Character(UnicodeScalar(64+number)!)
}
func integers(_ xs: [Int]) -> String {
    xs.map(String.init).joined(separator: " ")
}
struct Params {
    let values: [String: [String]]
    init() throws {
        values = Dictionary(uniqueKeysWithValues: try String(contentsOfFile: "input/ga_params.txt", encoding: .utf8).split(separator: "\n").map {
            let p = $0.split(separator: " ").map(String.init); return(p[0], Array(p.dropFirst()))
        })
    }
    func get(_ k: String) -> Int {
        Int(values[k]![0])!
    }
    func chance(_ k: String) -> (Int, Int) {
        let p = values[k]![0].split(separator: "/").map {
            Int($0)!
        };
        return(p[0], p[1])
    }
}
struct Schedule {
    let starts: [Int],
    ends: [Int],
    order: [[Int]],
    previous: [Int?],
    next: [Int?],
    makespan: Int
    init(_ ins: Instance, _ starts: [Int]) {
        self.starts = starts;
        let ends = zip(starts, ins.operations).map {
            $0.0+$0.1.duration
        };
        self.ends = ends;
        makespan = ends.max()!
        var order = Array(repeating: [Int](), count: ins.machines.count), previous = Array<Int?>(repeating: nil, count: starts.count), next = previous
        for i in starts.indices.sorted(by: {
            starts[$0] != starts[$1] ? starts[$0]<starts[$1] : $0<$1
        }) {
            order[ins.operations[i].machine].append(i)
        }
        for seq in order {
            for k in seq.indices.dropFirst() {
                next[seq[k-1]] = seq[k];
                previous[seq[k]] = seq[k-1]
            }
        }
        self.order = order;
        self.previous = previous;
        self.next = next
    }
    var byStart: [Int] {
        starts.indices.sorted {
            starts[$0] != starts[$1] ? starts[$0]<starts[$1] : $0<$1
        }
    }
    func chromosome(_ ins: Instance) -> [Int] {
        byStart.map {
            ins.operations[$0].job
        }
    }
    func path(_ ins: Instance) -> [Int] {
        var id = ends.firstIndex(of: makespan)!, path = [id];
        while starts[id] != 0 {
            if let p = previous[id], ends[p] == starts[id] {
                id = p
            }else {
                id = ins.operations[id].previous!
            };
            path.append(id)
        };
        return Array(path.reversed())
    }
    func blocks(_ ins: Instance) -> [[Int]] {
        var out = [[Int]]();
        for id in path(ins) {
            if let last = out.last, ins.operations[last[0]].machine == ins.operations[id].machine {
                out[out.count-1].append(id)
            }else {
                out.append([id])
            }
        };
        return out
    }
    func moves(_ ins: Instance) -> [(Int, Int)] {
        blocks(ins).flatMap {
            b in b.indices.dropFirst().map {
                (b[$0-1], b[$0])
            }
        }
    }
    func pathCount(_ ins: Instance) -> Int {
        var ways = Array(repeating: 0, count: starts.count);
        for id in byStart {
            if starts[id] == 0 {
                ways[id] = 1
            }else {
                for p in [ins.operations[id].previous, previous[id]].compactMap( {
                    $0
                }) {
                    if ends[p] == starts[id] {
                        ways[id] += ways[p]
                    }
                }
            }
        };
        return ends.indices.filter {
            ends[$0] == makespan
        }.reduce(0) {
            $0+ways[$1]
        }
    }
    func pathCounts(_ ins: Instance) -> [Int] {
        var counts = Array(repeating: 0, count: ins.machines.count);
        for id in path(ins) {
            counts[ins.operations[id].machine] += 1
        };
        return counts
    }
    func bottleneck(_ ins: Instance) -> Int {
        let c = pathCounts(ins);
        return c.firstIndex(of: c.max()!)!
    }
    func leftShift(_ ins: Instance, _ id: Int) -> (Int, Int)? {
        let o = ins.operations[id], seq = order[o.machine], pos = seq.firstIndex(of: id)!, ready = o.previous.map {
            ends[$0]
        } ?? 0;
        for at in 0..<pos {
            let low = at == 0 ? 0 : ends[seq[at-1]], s = max(low, ready);
            if s+o.duration <= starts[seq[at]] {
                return(s, at)
            }
        };
        return nil
    }
    func slacks(_ ins: Instance) -> ([Int], [Int]) {
        var latest = Array(repeating: 0, count: starts.count), slack = latest, free = latest;
        for id in byStart.reversed() {
            let successors = [ins.operations[id].next, next[id]].compactMap {
                $0
            };
            latest[id] = (successors.map {
                latest[$0]
            }.min() ?? makespan)-ins.operations[id].duration;
            slack[id] = latest[id]-starts[id];
            free[id] = (successors.map {
                starts[$0]
            }.min() ?? makespan)-ends[id]
        };
        return(slack, free)
    }
    func flow(_ ins: Instance) -> Int {
        ins.jobs.reduce(0) {
            $0+ends[$1.operations.last!]
        }
    }
    func idle(_ ins: Instance) -> Int {
        ins.machines.count*makespan-ins.machines.reduce(0) {
            $0+$1.load
        }
    }
    func letters(_ ins: Instance, _ m: Int) -> String {
        String(order[m].map {
            letter(ins.jobs[ins.operations[$0].job].number)
        })
    }
}
func orderStarts(_ ins: Instance, _ order: [[Int]], _ durations: [Int]) -> [Int] {
    var starts = Array(repeating: -1, count: ins.operations.count), ends = Array(repeating: 0, count: starts.count), positions = Array(repeating: 0, count: order.count), placed = 0
    while placed<starts.count {
        for(m, seq)in order.enumerated() {
            while positions[m]<seq.count {
                let pos = positions[m], id = seq[pos], p = ins.operations[id].previous;
                if let p = p, starts[p]<0 {
                    break
                };
                let ready = p.map {
                    ends[$0]
                } ?? 0, free = pos == 0 ? 0 : ends[seq[pos-1]];
                starts[id] = max(ready, free);
                ends[id] = starts[id]+durations[id];
                positions[m] += 1;
                placed += 1
            }
        }
    };
    return starts
}
func scheduleOrder(_ ins: Instance, _ order: [[Int]]) -> Schedule {
    Schedule(ins, orderStarts(ins, order, ins.durations))
}
func orderValue(_ ins: Instance, _ order: [[Int]], _ durations: [Int]) -> Int {
    zip(orderStarts(ins, order, durations), durations).map {
        $0.0+$0.1
    }.max()!
}
func applyMove(_ ins: Instance, _ order: [[Int]], _ pair: (Int, Int)) -> [[Int]] {
    var out = order;
    let m = ins.operations[pair.0].machine, pos = out[m].firstIndex(of: pair.0)!;
    out[m].swapAt(pos, pos+1);
    return out
}
func distances(_ a: Schedule, _ b: Schedule) -> [Int] {
    zip(a.order, b.order).map {
        x, y in let rank = Dictionary(uniqueKeysWithValues: y.enumerated().map {
            ($1, $0)
        });
        var count = 0;
        for i in x.indices {
            for j in (i+1)..<x.count {
                if rank[x[i]]!>rank[x[j]]! {
                    count += 1
                }
            }
        };
        return count
    }
}
func jackson(_ ins: Instance, _ m: Int) -> Int {
    let ids = ins.machines[m].operations;
    var remaining = ids.map {
        ins.operations[$0].duration
    }, t = 0, bound = 0
    while remaining.contains(where: {
        $0>0
    }) {
        if !ids.indices.contains(where: {
            remaining[$0]>0 && ins.operations[ids[$0]].head <= t
        }) {
            t = ids.indices.filter {
                remaining[$0]>0
            }.map {
                ins.operations[ids[$0]].head
            }.min()!
        }
        let released = ids.indices.filter {
            remaining[$0]>0 && ins.operations[ids[$0]].head <= t
        }, k = released.min {
            a, b in let x = ins.operations[ids[a]], y = ins.operations[ids[b]];
            return x.tail != y.tail ? x.tail>y.tail : x.job<y.job
        }!, later = ids.map {
            ins.operations[$0].head
        }.filter {
            $0>t
        }.min(), step = min(remaining[k], later.map {
            $0-t
        } ?? remaining[k]);
        t += step;
        remaining[k] -= step;
        if remaining[k] == 0 {
            bound = max(bound, t+ins.operations[ids[k]].tail)
        }
    };
    return bound
}
struct Pair: Hashable {
    let u: Int,
    v: Int;
    init(_ p: (Int, Int)) {
        u = p.0;
        v = p.1
    }
}
struct TabuRecord {
    let iteration: Int,
    moves: Int,
    tabu: Int,
    pair: (Int, Int),
    aspiration: Bool,
    value: Int,
    best: Int
}
struct Search {
    var order: [[Int]],
    start: Int,
    best: Int,
    found: Int,
    records: [TabuRecord],
    reason: String
}
func tabu(_ ins: Instance, _ initial: [[Int]], _ p: Params) -> Search {
    var current = initial;
    let start = orderValue(ins, current, ins.durations);
    var out = Search(order: current, start: start, best: start, found: 0, records: [], reason: "limit"), expiry = [Pair: Int]()
    for it in 1...p.get("tabu_iterations") {
        let moves = scheduleOrder(ins, current).moves(ins);
        if moves.isEmpty {
            out.reason = "no_moves";
            break
        };
        let values = moves.map {
            orderValue(ins, applyMove(ins, current, $0), ins.durations)
        }, flags = moves.map {
            (expiry[Pair($0)] ?? -1) >= it
        }, selectable = moves.indices.filter {
            !flags[$0] || values[$0]<out.best
        }
        guard let i = selectable.min(by: {
            values[$0] != values[$1] ? values[$0]<values[$1] : $0<$1
        })else {
            out.reason = "all_tabu";
            break
        };
        let(u, v) = moves[i];
        current = applyMove(ins, current, (u, v));
        expiry[Pair((v, u))] = it+p.get("tabu_tenure");
        if values[i]<out.best {
            out.order = current;
            out.best = values[i];
            out.found = it
        };
        out.records.append(TabuRecord(iteration: it, moves: moves.count, tabu: flags.filter {
            $0
        }.count, pair: (u, v), aspiration: flags[i], value: values[i], best: out.best))
    };
    return out
}
struct Baseline {
    let schedule: Schedule,
    decisions: Int,
    ties: Int,
    search: Search
}
struct Ga {
    var population: [[Int]],
    values: [Int],
    records: [(Int, Int, Int)],
    progress: [String],
    crossovers: Int,
    swaps: Int,
    inserts: Int
}
func ranking(_ values: [Int]) -> [Int] {
    values.indices.sorted {
        values[$0] != values[$1] ? values[$0]<values[$1] : $0<$1
    }
}
func gcd(_ first: Int, _ second: Int) -> Int {
    var a = first, b = second;
    while b != 0 {
        let r = a%b;
        a = b;
        b = r
    };
    return a
}
func runGa(_ ins: Instance, _ p: Params, _ seeds: [[Int]]) -> Ga {
    var rng = Minstd(state: p.get("seed")), ga = Ga(population: seeds, values: [], records: [], progress: ["generation,best,mean,worst,distinct"], crossovers: 0, swaps: 0, inserts: 0)
    while ga.population.count<p.get("population") {
        var c = ins.jobs.enumerated().flatMap {
            j, job in Array(repeating: j, count: job.operations.count)
        };
        rng.shuffle(&c);
        ga.population.append(c)
    }
    let checkpoints = Set(p.values["checkpoints"]!.map {
        Int($0)!
    });
    var previous = Int.max
    for g in 0...p.get("generations") {
        ga.values = ga.population.map {
            Schedule(ins, decode(ins, $0)).makespan
        };
        let rank = ranking(ga.values), best = ga.values[rank[0]];
        if best<previous {
            ga.records.append((g, best, rank[0]+1))
        };
        previous = best
        if checkpoints.contains(g) {
            let total = ga.values.reduce(0, +), d = gcd(total, ga.values.count), distinct = Set(ga.population).count;
            ga.progress.append("\(g),\(best),\(total/d)/\(ga.values.count/d),\(ga.values.max()!),\(distinct)")
        }
        if g == p.get("generations") {
            break
        };
        var children = rank.prefix(p.get("elitism")).map {
            ga.population[$0]
        }
        while children.count<ga.population.count {
            let a = tournament(&rng, ga.values, p.get("tournament")), b = tournament(&rng, ga.values, p.get("tournament"));
            var pair: ([Int], [Int]);
            if rng.chance(p.chance("crossover")) {
                ga.crossovers += 1;
                pair = crossover(&rng, ga.population[a], ga.population[b], ins.jobs.count)
            }else {
                pair = (ga.population[a], ga.population[b])
            }
            var offspring = [pair.0, pair.1];
            for i in offspring.indices {
                if rng.chance(p.chance("swap_mutation")) {
                    ga.swaps += 1;
                    swapMutation(&rng, &offspring[i])
                };
                if rng.chance(p.chance("insert_mutation")) {
                    ga.inserts += 1;
                    insertMutation(&rng, &offspring[i])
                }
            };
            children += offspring
        };
        ga.population = children
    };
    return ga
}
func writeLines(_ name: String, _ lines: [String]) throws {
    try (lines.joined(separator: "\n")+"\n").write(toFile: "output/"+name, atomically: true, encoding: .utf8)
}
let ins = try Instance(), p = try Params()
let baselines = rules.map {
    rule in let(starts, decisions, ties) = dispatch(ins, rule), s = Schedule(ins, starts);
    return Baseline(schedule: s, decisions: decisions, ties: ties, search: tabu(ins, s.order, p))
}
let jacksons = ins.machines.indices.map {
    jackson(ins, $0)
}, jb = ins.jobs.indices.min {
    a, b in ins.jobs[a].work != ins.jobs[b].work ? ins.jobs[a].work>ins.jobs[b].work : a<b
}!, mb = ins.machines.indices.min {
    a, b in ins.machines[a].bound != ins.machines[b].bound ? ins.machines[a].bound>ins.machines[b].bound : a<b
}!, jx = jacksons.firstIndex(of: jacksons.max()!)!, lb = max(ins.jobs[jb].work, ins.machines[mb].bound, jacksons[jx])
let ga = runGa(ins, p, baselines.map {
    $0.schedule.chromosome(ins)
}), rank = ranking(ga.values), genes = ga.population[rank[0]], gaSchedule = Schedule(ins, decode(ins, genes))
var positions = Array(repeating: 0, count: ins.operations.count)
for(pos, id)in geneOperations(ins, genes).enumerated() {
    positions[id] = pos+1
}
let(active, activeDecisions, _) = dispatch(ins, "GENES", positions), activeValue = Schedule(ins, active).makespan
var activated = gaSchedule.order, shifts = [(Int, Int, Int)]()
while true {
    let s = scheduleOrder(ins, activated);
    guard let id = s.byStart.first(where: {
        s.leftShift(ins, $0) != nil
    })else {
        break
    };
    let(start, at) = s.leftShift(ins, id)!, m = ins.operations[id].machine, pos = activated[m].firstIndex(of: id)!;
    activated[m].remove(at: pos);
    activated[m].insert(id, at: at);
    shifts.append((id, s.starts[id], start))
}
let search = tabu(ins, activated, p), s = scheduleOrder(ins, search.order), path = s.path(ins), blocks = s.blocks(ins), counts = s.pathCounts(ins), bottleneck = s.bottleneck(ins), (slack, free) = s.slacks(ins)
var base = ["INSTANCE jobs \(ins.jobs.count) machines \(ins.machines.count) operations \(ins.operations.count) work \(ins.jobs.reduce(0){$0+$1.work}) errors \(ins.errors.count)"]
base += ins.errors.map {
    "ERROR "+$0
}
for j in ins.jobs {
    let route = j.operations.map {
        "M\(ins.operations[$0].machine+1)"
    }.joined(separator: " ");
    base.append("JOB J\(j.number) operations \(j.operations.count) work \(j.work) route \(route)")
}
for(m, machine)in ins.machines.enumerated() {
    base.append("MACHINE M\(m+1) operations \(machine.operations.count) load \(machine.load) head \(machine.head) tail \(machine.tail) bound \(machine.bound) jackson \(jacksons[m])")
}
base += ["BOUND job \(ins.jobs[jb].work) J\(ins.jobs[jb].number)", "BOUND machine \(ins.machines[mb].bound) M\(mb+1)", "BOUND jackson \(jacksons[jx]) M\(jx+1)", "BOUND lower \(lb)"]
for(i, b)in baselines.enumerated() {
    let rule = rules[i], c = b.schedule.makespan;
    base.append("RULE \(rule) makespan \(c) gap \(percentage(c-lb,lb)) flow \(b.schedule.flow(ins)) idle \(b.schedule.idle(ins)) decisions \(b.decisions) ties \(b.ties)");
    base.append("PATH \(rule) operations \(b.schedule.path(ins).count) blocks \(b.schedule.blocks(ins).count) critical_paths \(b.schedule.pathCount(ins)) bottleneck M\(b.schedule.bottleneck(ins)+1)");
    base.append("TABU \(rule) makespan \(c) -> \(b.search.best) found \(b.search.found) iterations \(b.search.records.count) stop \(b.search.reason)")
}
let best = baselines.indices.min {
    baselines[$0].schedule.makespan != baselines[$1].schedule.makespan ? baselines[$0].schedule.makespan<baselines[$1].schedule.makespan : $0<$1
}!
base.append("BEST \(rules[best]) makespan \(baselines[best].schedule.makespan)")
for(m, machine)in ins.machines.enumerated() {
    base.append("UTILIZATION M\(m+1) "+baselines.indices.map {
        "\(rules[$0]) \(percentage(machine.load,baselines[$0].schedule.makespan))"
    }.joined(separator: " "))
}
var out = ["GA best \(gaSchedule.makespan) generation \(ga.records.last!.0) crossovers \(ga.crossovers) swaps \(ga.swaps) inserts \(ga.inserts)"]
for(g, c, i)in ga.records {
    out.append("RECORD generation \(g) makespan \(c) individual \(i)")
}
var seen = Set<[Int]>(), top = 0
for i in rank {
    if !seen.insert(ga.population[i]).inserted {
        continue
    };
    top += 1;
    let d = distances(Schedule(ins, decode(ins, ga.population[i])), gaSchedule).reduce(0, +);
    out.append("TOP \(top) individual \(i+1) makespan \(ga.values[i]) distance \(d)");
    if top == 5 {
        break
    }
}
out.append("GA_CHROMOSOME "+integers(genes.map {
    ins.jobs[$0].number
}))
out.append("ACTIVE_DECODE makespan \(activeValue) decisions \(activeDecisions)")
for(i, shift)in shifts.enumerated() {
    out.append("SHIFT \(i+1) \(ins.code(shift.0)) M\(ins.operations[shift.0].machine+1) start \(shift.1) -> \(shift.2)")
}
out.append("ACTIVATED makespan \(gaSchedule.makespan) -> \(search.start) shifts \(shifts.count)")
out.append("SCHEDULE makespan \(s.makespan) lower_bound \(lb) gap \(percentage(s.makespan-lb,lb)) improvement \(gaSchedule.makespan-s.makespan) shiftable \(ins.operations.indices.filter{s.leftShift(ins,$0) != nil}.count)")
out.append("CHROMOSOME "+integers(s.chromosome(ins).map {
    ins.jobs[$0].number
}))
out.append("LEGEND "+ins.jobs.map {
    "\(letter($0.number))=J\($0.number)"
}.joined(separator: " "))
let(q, n) = chartScale(s.makespan, p.get("gantt_width")), onPath = Set(path)
var intervals = Array(repeating: [Interval](), count: ins.machines.count)
for(i, o)in ins.operations.enumerated() {
    let mark = String(letter(ins.jobs[o.job].number));
    intervals[o.machine].append((s.starts[i], s.ends[i], Character(onPath.contains(i) ? mark.lowercased() : mark)))
}
out += ["GANTT scale \(q) columns \(n)", timeRow(q, n), ruleRow(n)]
for(m, row)in intervals.enumerated() {
    out.append(chartRow("M\(m+1)", row, q, n))
}
out.append(busyRow(intervals, q, n))
for j in ins.jobs {
    let row: [Interval] = j.operations.map {
        (s.starts[$0], s.ends[$0], Character(String((ins.operations[$0].machine+1)%10)))
    };
    out.append(chartRow("J\(j.number)", row, q, n))
}
for m in ins.machines.indices {
    out.append("ORDER M\(m+1) FINAL \(s.letters(ins,m)) "+baselines.indices.map {
        "\(rules[$0]) \(baselines[$0].schedule.letters(ins,m))"
    }.joined(separator: " "))
}
for(m, machine)in ins.machines.enumerated() {
    let seq = s.order[m], gaps = seq.indices.dropFirst().map {
        s.starts[seq[$0]]-s.ends[seq[$0-1]]
    }.filter {
        $0>0
    }, sequence = seq.map {
        "J\(ins.jobs[ins.operations[$0].job].number):\(s.starts[$0])-\(s.ends[$0])"
    }.joined(separator: " ");
    out.append("MACHINE M\(m+1) load \(machine.load) idle \(s.makespan-machine.load) utilization \(percentage(machine.load,s.makespan)) gaps \(gaps.count) longest_gap \(gaps.max() ?? 0) sequence \(sequence)");
    var idle = [(0, s.starts[seq[0]])];
    idle += seq.indices.dropFirst().map {
        (s.ends[seq[$0-1]], s.starts[seq[$0]])
    };
    idle.append((s.ends[seq.last!], s.makespan));
    let text = idle.filter {
        $0.1>$0.0
    }.map {
        "\($0.0)-\($0.1)"
    }.joined(separator: " ");
    out.append("IDLE M\(m+1) \(text.isEmpty ? "none" : text)")
}
var waiting = 0
for j in ins.jobs {
    let c = s.ends[j.operations.last!];
    waiting += c-j.work;
    out.append("JOB J\(j.number) operations \(j.operations.count) work \(j.work) start \(s.starts[j.operations[0]]) completion \(c) waiting \(c-j.work)")
}
out.append("TOTAL flow \(s.flow(ins)) waiting \(waiting) idle \(s.idle(ins))")
let others = baselines.map(\.schedule)+[gaSchedule], labels = rules+["GA"], distance = others.map {
    distances(s, $0)
}
var pairsTotal = 0
for(m, machine)in ins.machines.enumerated() {
    let count = machine.operations.count, pairs = count*(count-1)/2;
    pairsTotal += pairs;
    out.append("DISTANCE M\(m+1) pairs \(pairs) "+labels.indices.map {
        "\(labels[$0]) \(distance[$0][m])"
    }.joined(separator: " "))
}
out.append("DISTANCE total pairs \(pairsTotal) "+labels.indices.map {
    "\(labels[$0]) \(distance[$0].reduce(0,+))"
}.joined(separator: " "))
var critical = ["SEARCH start \(search.start) iterations \(p.get("tabu_iterations")) tenure \(p.get("tabu_tenure"))"]
for r in search.records {
    critical.append("ITER \(r.iteration) moves \(r.moves) tabu \(r.tabu) swap M\(ins.operations[r.pair.0].machine+1) \(ins.code(r.pair.0)) \(ins.code(r.pair.1)) \(r.aspiration ? "aspiration" : "free") makespan \(r.value) best \(r.best)")
}
critical.append("STOP iterations \(search.records.count) reason \(search.reason) best \(search.best) found \(search.found)")
critical.append("PATH operations \(path.count) blocks \(blocks.count) makespan \(s.makespan) critical_paths \(s.pathCount(ins))")
for(k, id)in path.enumerated() {
    let link = k == 0 ? "start" : s.previous[id] == path[k-1] ? "machine" : "job";
    critical.append("NODE \(k+1) \(ins.code(id)) M\(ins.operations[id].machine+1) \(s.starts[id])-\(s.ends[id]) \(link)")
}
for(k, b)in blocks.enumerated() {
    critical.append("BLOCK \(k+1) M\(ins.operations[b[0]].machine+1) \(s.starts[b[0]])-\(s.ends[b.last!]) "+b.map {
        ins.code($0)
    }.joined(separator: " "))
}
for(k, pair)in s.moves(ins).enumerated() {
    critical.append("NEIGHBOUR \(k+1) M\(ins.operations[pair.0].machine+1) \(ins.code(pair.0)) \(ins.code(pair.1)) makespan \(orderValue(ins,applyMove(ins,s.order,pair),ins.durations))")
}
critical.append("CRITICAL operations \(slack.filter{$0==0}.count) total \(ins.operations.count)")
for(label, values)in [("SLACK", slack), ("FREE", free)] {
    for j in ins.jobs {
        critical.append("\(label) J\(j.number) "+integers(j.operations.map {
            values[$0]
        }))
    }
}
for(m, machine)in ins.machines.enumerated() {
    let durations = ins.operations.map {
        $0.duration+($0.machine == m ? ($0.duration+9)/10 : 0)
    }, sensitivity = orderValue(ins, s.order, durations);
    critical.append("MACHINE M\(m+1) critical \(machine.operations.filter{slack[$0]==0}.count) path \(counts[m]) sensitivity \(sensitivity) delta \(sensitivity-s.makespan)")
}
critical.append("BOTTLENECK M\(bottleneck+1) path \(counts[bottleneck])")
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
try writeLines("baselines.txt", base)
try writeLines("ga_progress.csv", ga.progress)
try writeLines("best_schedule.txt", out)
try writeLines("critical_path.txt", critical)
