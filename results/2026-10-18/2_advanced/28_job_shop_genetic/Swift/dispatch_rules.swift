let rules = ["SPT", "LPT", "MWKR", "FIFO"]
func dispatch(_ ins: Instance, _ rule: String, _ genes: [Int] = []) -> ([Int], Int, Int) {
    var starts = Array(repeating: 0, count: ins.operations.count), next = Array(repeating: 0, count: ins.jobs.count), ready = Array(repeating: 0, count: ins.jobs.count), free = Array(repeating: 0, count: ins.machines.count), decisions = 0, ties = 0
    for _ in starts.indices {
        var candidates = [(Int, Int)]();
        for(j, job)in ins.jobs.enumerated() {
            if next[j]<job.operations.count {
                let id = job.operations[next[j]];
                candidates.append((id, max(ready[j], free[ins.operations[id].machine])))
            }
        }
        let cutoff = candidates.map {
            $0.1+ins.operations[$0.0].duration
        }.min()!, m = candidates.filter {
            $0.1+ins.operations[$0.0].duration == cutoff
        }.map {
            ins.operations[$0.0].machine
        }.min()!, conflict = candidates.filter {
            ins.operations[$0.0].machine == m && $0.1<cutoff
        }
        func priority(_ id: Int) -> Int {
            let o = ins.operations[id];
            switch rule {
                case "SPT": return o.duration;
                case "LPT": return -o.duration;
                case "MWKR": return -o.duration-o.tail;
                case "FIFO": return ready[o.job];
                default: return genes[id]
            }
        }
        let low = conflict.map {
            priority($0.0)
        }.min()!;
        if conflict.count>1 {
            decisions += 1
        };
        if conflict.filter( {
            priority($0.0) == low
        }).count>1 {
            ties += 1
        }
        let(id, s) = conflict.first {
            priority($0.0) == low
        }!, o = ins.operations[id];
        starts[id] = s;
        ready[o.job] = s+o.duration;
        free[m] = s+o.duration;
        next[o.job] += 1
    };
    return(starts, decisions, ties)
}
