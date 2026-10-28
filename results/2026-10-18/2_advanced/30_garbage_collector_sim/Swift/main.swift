import Foundation
func reach(_ objects: [HeapObject], _ roots: [Int?]) -> Set<Int> {
    var reached = Set<Int>(), stack = roots.compactMap {
        $0
    };
    while let id = stack.popLast() {
        if reached.insert(id).inserted {
            stack += objects[id].fields.compactMap {
                $0
            }
        }
    };
    return reached
}
func pair(_ objects: [HeapObject], _ ids: [Int]) -> Pair {
    var p = Pair();
    for id in ids {
        p.add(objects[id])
    };
    return p
}
func value(_ roots: [Int?], _ source: Int?) -> Int? {
    source.flatMap {
        roots[$0]
    }
}
struct Checkpoint {
    let label: String,
    line: Int,
    depth: Int,
    live: Pair,
    allocated: Pair,
    phase: Pair,
    survivors: Pair,
    reached: Set<Int>
}
final class Script {
    var commands = [Command](),
    errors = [(Int, String)](),
    objects = [HeapObject](),
    roots = [Int?](),
    deaths = [Int](),
    lifetimes = [Int?](),
    checkpoints = [Checkpoint](),
    counts = Array(repeating: 0, count: 7),
    peak = Pair(),
    peakLine = 0
    let lineCount: Int
    init(_ parsed: [ParsedLine]) {
        lineCount = parsed.count;
        var clock = 0, phaseStart = 0, births = [Int](), alive = Set<Int>(), labels = Set<String>()
        for(i, result)in parsed.enumerated() {
            guard let c = result.command else {
                errors.append((i+1, result.reason!));
                continue
            };
            let depth = roots.count;
            var reason: String?, index: Int?, source: Int?, pushes = false
            switch c.kind {
                case .alloc: pushes = true;
                case .push(let r): pushes = true;
                source = r;
                case .load(let i, _): pushes = true;
                index = i;
                case .set(let i, _, let r): index = i;
                source = r;
                case .overwrite(let i, let r): index = i;
                source = r;
                default: break
            }
            if (pushes && depth == 64) || (index.map {
                $0 >= depth
            } ?? false) || (source.map {
                $0 >= depth
            } ?? false) {
                reason = "stack"
            }
            if case .pop(let n) = c.kind, n>depth {
                reason = "stack"
            }
            if reason == nil {
                switch c.kind {
                    case .load(let i, let f), .set(let i, let f, _): if let id = roots[i] {
                        if f >= objects[id].fields.count {
                            reason = "field"
                        }
                    }else {
                        reason = "null"
                    };
                    case .checkpoint(let label): if labels.contains(label) {
                        reason = "duplicate"
                    };
                    default: break
                }
            }
            if let reason = reason {
                errors.append((c.line, reason));
                continue
            };
            counts[c.name] += 1
            switch c.kind {
                case .alloc(let p, let d): let id = objects.count, o = HeapObject(p, d);
                births.append(clock);
                clock += o.size;
                objects.append(o);
                deaths.append(0);
                lifetimes.append(nil);
                roots.append(id);
                case .push(let r): roots.append(value(roots, r));
                case .load(let i, let f): roots.append(objects[roots[i]!].fields[f]);
                case .pop(let n): roots.removeLast(n);
                case .set(let i, let f, let r): let new = value(roots, r);
                objects[roots[i]!].fields[f] = new;
                case .overwrite(let i, let r): let new = value(roots, r);
                roots[i] = new;
                case .checkpoint: break
            }
            let reached = reach(objects, roots);
            for id in alive.subtracting(reached) {
                deaths[id] = c.line;
                lifetimes[id] = clock-births[id]-objects[id].size
            };
            alive = reached;
            let live = pair(objects, Array(reached))
            if peakLine == 0 || live.words>peak.words {
                peak = live;
                peakLine = c.line
            }
            if case .checkpoint(let label) = c.kind {
                labels.insert(label);
                let allocated = pair(objects, Array(objects.indices)), phase = pair(objects, Array(phaseStart..<objects.count)), survivors = pair(objects, (phaseStart..<objects.count).filter {
                    reached.contains($0)
                });
                phaseStart = objects.count;
                checkpoints.append(Checkpoint(label: label, line: c.line, depth: roots.count, live: live, allocated: allocated, phase: phase, survivors: survivors, reached: reached))
            };
            commands.append(c)
        }
    }
    func report() -> [String] {
        var lines = ["script lines \(lineCount) valid \(commands.count) errors \(errors.count)"]+errors.map {
            "error line \($0.0) \($0.1)"
        };
        lines.append("commands "+zip(commandNames, counts).map {
            "\($0.0) \($0.1)"
        }.joined(separator: " "));
        lines.append("allocated objects \(objects.count) words \(objects.reduce(0){$0+$1.size}) sizes \(classTable(objects.map(\.size)))");
        lines.append("peak_live objects \(peak.count) words \(peak.words) line \(peakLine)");
        let live = pair(objects, Array(reach(objects, roots)));
        lines.append("end_live objects \(live.count) words \(live.words) stack \(roots.count)");
        var distribution = Array(repeating: 0, count: 6);
        for lifetime in lifetimes {
            let k = lifetime.map {
                v in [63, 255, 1023, 4095].firstIndex {
                    $0 >= v
                } ?? 4
            } ?? 5;
            distribution[k] += 1
        };
        lines.append("lifetimes 0-63 \(distribution[0]) 64-255 \(distribution[1]) 256-1023 \(distribution[2]) 1024-4095 \(distribution[3]) 4096+ \(distribution[4]) live \(distribution[5])");
        for c in checkpoints {
            lines.append("checkpoint \(c.label) line \(c.line) stack \(c.depth) live \(c.live.text) allocated \(c.allocated.text) phase \(c.phase.text) survivors \(c.survivors.text) survival \(pct(c.survivors.words,c.phase.words))")
        };
        return lines
    }
}
func leakReport(_ title: String, _ m: Memory, _ garbage: [Int], _ deaths: [Int]) -> [String] {
    let members = Set(garbage);
    var neighbors = Array(repeating: [Int](), count: m.objects.count)
    for id in garbage {
        for child in m.objects[id].fields.compactMap( {
            $0
        }) {
            if members.contains(child) {
                neighbors[id].append(child);
                neighbors[child].append(id)
            }
        }
    }
    var grouped = Set<Int>(), groups = [[Int]]();
    for id in garbage {
        if !grouped.insert(id).inserted {
            continue
        };
        var stack = [id], group = [Int]();
        while let i = stack.popLast() {
            group.append(i);
            for j in neighbors[i] {
                if grouped.insert(j).inserted {
                    stack.append(j)
                }
            }
        };
        groups.append(group.sorted())
    }
    var lines = ["\(title) groups \(groups.count) objects \(garbage.count) words \(pair(m.objects,garbage).words)"]
    for(k, g)in groups.enumerated() {
        var cycles = 0, ids = [String]();
        for id in g {
            var visited = Set<Int>(), stack = m.objects[id].fields.compactMap {
                $0
            }.filter {
                members.contains($0)
            }, cycle = false;
            while let j = stack.popLast() {
                if j == id {
                    cycle = true;
                    break
                };
                if visited.insert(j).inserted {
                    stack += m.objects[j].fields.compactMap {
                        $0
                    }.filter {
                        members.contains($0)
                    }
                }
            };
            if cycle {
                cycles += 1
            };
            ids.append("\(id+1)"+(cycle ? "*" : ""))
        };
        let died = g.map {
            deaths[$0]
        }.max()!;
        lines.append("group \(k+1) objects \(g.count) words \(pair(m.objects,g).words) cycle \(cycles) died \(died) ids \(ids.joined(separator:" "))")
    };
    return lines
}
struct Pause {
    let line: Int,
    work: Int,
    freed: Pair,
    collection: Bool
}
struct Stats {
    let count: Int,
    collections: Int,
    work: Int,
    freed: Int,
    maximum: Int,
    p50: String,
    p90: String
    init(_ pauses: [Pause]) {
        let works = pauses.map(\.work).sorted();
        func percentile(_ rank: Int) -> String {
            works.isEmpty ? "-" : String(works[(rank*works.count+99)/100-1])
        };
        count = pauses.count;
        collections = pauses.filter(\.collection).count;
        work = works.reduce(0, +);
        freed = pauses.reduce(0) {
            $0+$1.freed.words
        };
        maximum = works.last ?? 0;
        p50 = percentile(50);
        p90 = percentile(90)
    }
}
struct Segment {
    let start: Int,
    mutator: Bool,
    before: Int;
    var length: Int
}
struct Timeline {
    var segments = [Segment](),
    length = 0,
    mutator = 0
    mutating func add(_ flag: Bool, _ units: Int) {
        if units == 0 {
            return
        };
        if segments.last?.mutator == flag {
            segments[segments.count-1].length += units
        }else {
            segments.append(Segment(start: length, mutator: flag, before: mutator, length: units))
        };
        length += units;
        if flag {
            mutator += units
        }
    }
    func prefix(_ position: Int) -> Int {
        var lo = 0, hi = segments.count;
        while lo<hi {
            let mid = (lo+hi)/2;
            if segments[mid].start <= position {
                lo = mid+1
            }else {
                hi = mid
            }
        };
        let s = segments[lo-1];
        return s.before+(s.mutator ? position-s.start : 0)
    }
    func mmu(_ width: Int) -> String {
        if width>length {
            return "-"
        };
        var lowest = width;
        for s in segments {
            for begin in [s.start, s.start+s.length-width] {
                if begin >= 0 && begin <= length-width {
                    lowest = min(lowest, prefix(begin+width)-prefix(begin))
                }
            }
        };
        return pct(lowest, width)
    }
}
final class Run {
    let entry: Collector,
    m: Memory
    var roots = [Int?](),
    observations = [[String]](),
    cascades = [Pause](),
    timeline = Timeline(),
    failed: (Int, Int)?,
    peakUsed = 0,
    increments = 0,
    decrements = 0,
    released = Pair(),
    releasedWork = 0,
    reports = [[String]]()
    init(_ entry: Collector, _ size: Int) {
        self.entry = entry;
        m = Memory(entry, size)
    }
    var rc: Bool {
        entry.algorithm == "REFCOUNT"
    }
    func retain(_ id: Int?) {
        if rc, let id = id {
            m.objects[id].count += 1;
            increments += 1
        }
    }
    func release(_ id: Int?) {
        guard rc, let id = id else {
            return
        };
        var pending = [id];
        while let id = pending.popLast() {
            decrements += 1;
            m.objects[id].count -= 1;
            if m.objects[id].count != 0 {
                continue
            };
            released.add(m.objects[id]);
            releasedWork += 1+m.objects[id].fields.count;
            m.objects[id].present = false;
            pending += m.objects[id].fields.reversed().compactMap {
                $0
            }
        }
    }
    func push(_ id: Int?) {
        retain(id);
        roots.append(id)
    }
    func backup(_ line: Int, _ request: Int, _ deaths: [Int]) {
        var r = Record(line, request, "backup", m.freeList);
        mark(m, roots, &r);
        let garbage = m.ids.filter {
            !m.objects[$0].marked
        };
        reports.append(leakReport("backup \(m.records.count+1) line \(line)", m, garbage, deaths));
        sweep(m, &r);
        for id in garbage {
            for child in m.objects[id].fields.compactMap( {
                $0
            }) {
                if m.objects[child].marked {
                    m.objects[child].count -= 1;
                    decrements += 1
                }
            }
        };
        r.after = freeAmount(m.freeList);
        m.records.append(r)
    }
    func allocate(_ object: HeapObject, _ line: Int, _ deaths: [Int]) -> Bool {
        let size = object.size;
        var address: Int?
        switch entry.algorithm {
            case "MARK_SWEEP", "REFCOUNT": address = firstFit(m.freeList, size);
            if address == nil {
                if rc {
                    backup(line, size, deaths)
                }else {
                    collectMark(m, roots, line, size, false)
                };
                address = firstFit(m.freeList, size)
            }
            case "MARK_COMPACT": if m.top+size>m.size {
                collectMark(m, roots, line, size, true)
            };
            address = m.top+size <= m.size ? m.top : nil
            case "COPYING": if m.top+size>m.base+m.size/2 {
                collectCopy(m, roots, line, size)
            };
            address = m.top+size <= m.base+m.size/2 ? m.top : nil
            default: let half = m.young/2;
            var aborted = false;
            for step in 0..<2 {
                if m.top+size <= m.base+half {
                    break
                };
                let tight = freeAmount(m.oldBlocks).1<m.top-m.base, kind = step == 0 ? (tight ? "major" : "minor") : (tight ? "full" : "tenure");
                if !collectGeneration(m, roots, line, size, kind) {
                    aborted = true;
                    break
                }
            };
            address = !aborted && m.top+size <= m.base+half ? m.top : nil
        }
        guard let address = address else {
            return false
        };
        var o = object;
        o.address = address;
        if !["MARK_SWEEP", "REFCOUNT"].contains(entry.algorithm) {
            m.top += size
        };
        let id = m.objects.count;
        m.objects.append(o);
        push(id);
        peakUsed = max(peakUsed, m.pair(m.ids).words);
        return true
    }
    func simulate(_ config: Config, _ script: Script) {
        for c in script.commands {
            let before = m.records.count;
            var placed = true, units = 1
            switch c.kind {
                case .alloc(let p, let d): let o = HeapObject(p, d);
                units = o.size;
                placed = allocate(o, c.line, script.deaths);
                case .push(let r): push(value(roots, r));
                case .load(let i, let f): push(m.objects[roots[i]!].fields[f]);
                case .pop(let n): for _ in 0..<n {
                    release(roots.removeLast())
                };
                case .set(let i, let f, let r): let id = roots[i]!, new = value(roots, r);
                if entry.algorithm == "GENERATIONAL" {
                    writeBarrier(m, id, new)
                };
                retain(new);
                let previous = m.objects[id].fields[f];
                m.objects[id].fields[f] = new;
                release(previous);
                case .overwrite(let i, let r): let new = value(roots, r);
                retain(new);
                let previous = roots[i];
                roots[i] = new;
                release(previous);
                case .checkpoint: let cp = script.checkpoints[observations.count];
                observations.append(observe(config, cp))
            }
            for r in m.records.dropFirst(before) {
                timeline.add(false, r.work)
            };
            if !placed {
                failed = (c.line, units);
                return
            };
            timeline.add(true, units)
            if released.count>0 {
                cascades.append(Pause(line: c.line, work: releasedWork, freed: released, collection: false));
                timeline.add(false, releasedWork);
                released = Pair();
                releasedWork = 0
            }
        }
        if rc {
            let reached = reach(m.objects, roots), garbage = m.ids.filter {
                !reached.contains($0)
            };
            reports.append(leakReport("end", m, garbage, script.deaths))
        }
    }
    func observe(_ config: Config, _ cp: Checkpoint) -> [String] {
        let ids = m.ids, all = m.pair(ids), live = m.pair(ids.filter {
            cp.reached.contains($0)
        }), garbage = Pair(count: all.count-live.count, words: all.words-live.words), blocks = m.freeList, (total, largest) = freeAmount(blocks)
        var pointers = 0, forward = 0, backward = 0, distance = 0
        for id in ids {
            if !cp.reached.contains(id) {
                continue
            };
            for child in m.objects[id].fields.compactMap( {
                $0
            }) {
                let a = m.objects[id].address, b = m.objects[child].address;
                pointers += 1;
                if b>a {
                    forward += 1
                }else if b<a {
                    backward += 1
                };
                distance += abs(a-b)
            }
        }
        let mean = pointers == 0 ? "-" : dec2(distance, pointers)
        var lines = ["heap objects \(all.text) reachable \(live.text) garbage \(garbage.text)", "free total \(total) largest \(largest) blocks \(blocks.count) sizes \(classTable(blocks.map{$0.1})) fragmentation \(pct(total-largest,total))", "locality pointers \(pointers) forward \(forward) backward \(backward) mean_distance \(mean)"]
        if entry.algorithm == "GENERATIONAL" {
            let young = m.pair(ids.filter {
                m.objects[$0].address<m.young
            }), old = Pair(count: all.count-young.count, words: all.words-young.words);
            var ages = Array(repeating: 0, count: 4);
            for i in ids {
                if m.objects[i].address<m.young {
                    ages[min(m.objects[i].age, 3)] += 1
                }
            };
            lines.append("generations young \(young.text) old \(old.text) remembered \(m.remembered.count) ages 0:\(ages[0]) 1:\(ages[1]) 2:\(ages[2]) 3+:\(ages[3])")
        }
        if config.maps.contains(cp.label) {
            let map = Array(heapMap(m, cp.reached));
            for a in stride(from: 0, to: config.size, by: config.width) {
                lines.append(String(format: "%04d", a)+" "+String(map[a..<(a+config.width)]))
            }
        };
        return lines
    }
    var pauses: [Pause] {
        m.records.map {
            Pause(line: $0.line, work: $0.work, freed: $0.freed, collection: true)
        }
        +cascades
    }
    func failedBefore(_ line: Int) -> Bool {
        failed.map {
            $0.0<line
        } ?? false
    }
    func collectionLines(_ config: Config, _ script: Script) -> [String] {
        var lines = ["collector \(entry.name) \(entry.algorithm)"]
        for(i, r)in m.records.enumerated() {
            lines.append("\(i+1) line \(r.line) size \(r.request) kind \(r.kind) live \(r.live.text) freed \(r.freed.text) moved \(r.moved.text) promoted \(r.promoted.text) stack \(r.stack) work \(r.work) before \(r.before.0) \(r.before.1) after \(r.after.0) \(r.after.1)")
        }
        let allPauses = pauses, s = Stats(allPauses);
        lines.append("totals collections \(s.collections) pauses \(s.count) work \(s.work) freed \(s.freed) pause p50 \(s.p50) p90 \(s.p90) max \(s.maximum)")
        lines.append("utilization \(pct(timeline.mutator,timeline.length)) mmu "+config.windows.map {
            "\($0):\(timeline.mmu($0))"
        }.joined(separator: " "))
        if entry.algorithm == "GENERATIONAL" {
            var promoted = Pair();
            for r in m.records {
                promoted.merge(r.promoted)
            };
            let kinds = ["minor", "major", "tenure", "full"].map {
                kind in let records = m.records.filter {
                    $0.kind == kind
                };
                return "\(kind) \(records.count) \(records.reduce(0){$0+$1.work})"
            }.joined(separator: " ");
            lines.append("generational \(kinds) promoted \(promoted.text) barrier \(m.barriers) remembered \(m.remembers)")
        }
        if rc {
            var freed = Pair(), maximum: Pause?;
            for c in cascades {
                freed.merge(c.freed);
                if maximum == nil || c.work>maximum!.work {
                    maximum = c
                }
            };
            let maxText = maximum.map {
                "max_cascade \($0.freed.count) \($0.work) line \($0.line)"
            } ?? "max_cascade 0 0 line -";
            lines.append("refcount increments \(increments) decrements \(decrements) cascades \(cascades.count) freed \(freed.text) \(maxText)")
        }
        var previous = 0;
        for c in script.checkpoints {
            if failedBefore(c.line) {
                lines.append("phase \(c.label) out_of_memory")
            }else {
                let s = Stats(allPauses.filter {
                    $0.line>previous && $0.line <= c.line
                });
                lines.append("phase \(c.label) collections \(s.collections) pauses \(s.count) work \(s.work) freed \(s.freed) max_pause \(s.maximum)")
            };
            previous = c.line
        }
        lines.append(failed.map {
            "status out_of_memory line \($0.0) size \($0.1)"
        } ?? "status completed");
        return lines
    }
    var summary: String {
        let s = Stats(pauses), moves = m.objects.map(\.moves);
        let ending: [String]
        if failed != nil {
            ending = Array(repeating: "-", count: 4)
        }else {
            let(total, largest) = freeAmount(m.freeList);
            ending = [String(m.pair(m.ids).words), String(total), String(largest), pct(total-largest, total)]
        }
        let values = [entry.name, entry.algorithm, failed == nil ? "completed" : "out_of_memory", String(m.records.count), String(s.count), String(m.records.reduce(0) {
            $0+$1.live.count
        }), String(m.records.reduce(0) {
            $0+$1.moved.count
        }), String(moves.filter {
            $0>0
        }.count), String(moves.max() ?? 0), String(s.freed), String(s.work), s.p50, s.p90, String(s.maximum), String(peakUsed)];
        return(values+ending).joined(separator: ",")
    }
}
func writeLines(_ name: String, _ lines: [String]) throws {
    try(lines.isEmpty ? "" : lines.joined(separator: "\n")+"\n").write(toFile: "output/"+name, atomically: true, encoding: .utf8)
}
func joinBlocks(_ parts: [[String]]) -> [String] {
    var out = [String]();
    for(i, lines)in parts.enumerated() {
        if i>0 {
            out.append("")
        };
        out += lines
    };
    return out
}
let config = try Config(), script = Script(try readScript()), runs = config.collectors.map {
    entry in let run = Run(entry, config.size);
    run.simulate(config, script);
    return run
}
var maps = [[String]]()
for(i, c)in script.checkpoints.enumerated() {
    for r in runs {
        maps.append(["checkpoint \(c.label) line \(c.line) collector \(r.entry.name)"]+(i<r.observations.count ? r.observations[i] : ["out_of_memory"]))
    }
}
var leaks = [[String]]()
for r in runs {
    if !r.rc {
        continue
    };
    var block = ["collector \(r.entry.name)"];
    for report in r.reports {
        block += report
    };
    if r.failed != nil {
        block.append("status out_of_memory")
    };
    leaks.append(block)
}
let summary = ["collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation"]+runs.map(\.summary)
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
try writeLines("mutator.txt", script.report())
try writeLines("heap_maps.txt", joinBlocks(maps))
try writeLines("collections.txt", joinBlocks(runs.map {
    $0.collectionLines(config, script)
}))
try writeLines("summary.csv", summary)
try writeLines("leaks.txt", leaks.isEmpty ? ["none"] : joinBlocks(leaks))
