func geneOperations(_ ins: Instance, _ genes: [Int]) -> [Int] {
    var counts = Array(repeating: 0, count: ins.jobs.count);
    return genes.map {
        j in let id = ins.jobs[j].operations[counts[j]];
        counts[j] += 1;
        return id
    }
}
func decode(_ ins: Instance, _ genes: [Int]) -> [Int] {
    var starts = Array(repeating: 0, count: ins.operations.count), ready = Array(repeating: 0, count: ins.jobs.count), free = Array(repeating: 0, count: ins.machines.count);
    for id in geneOperations(ins, genes) {
        let o = ins.operations[id], s = max(ready[o.job], free[o.machine]);
        starts[id] = s;
        ready[o.job] = s+o.duration;
        free[o.machine] = s+o.duration
    };
    return starts
}
func tournament(_ rng: inout Minstd, _ values: [Int], _ size: Int) -> Int {
    var best = 0;
    for i in 0..<size {
        let pick = rng.below(values.count);
        if i == 0 || values[pick]<values[best] || (values[pick] == values[best] && pick<best) {
            best = pick
        }
    };
    return best
}
func crossover(_ rng: inout Minstd, _ a: [Int], _ b: [Int], _ jobs: Int) -> ([Int], [Int]) {
    var keep = Set<Int>();
    for j in 0..<jobs {
        if rng.below(2) == 0 {
            keep.insert(j)
        }
    };
    func child(_ x: [Int], _ y: [Int]) -> [Int] {
        let fill = y.filter {
            !keep.contains($0)
        };
        var i = 0;
        return x.map {
            g in if keep.contains(g) {
                return g
            };
            let v = fill[i];
            i += 1;
            return v
        }
    };
    return(child(a, b), child(b, a))
}
func swapMutation(_ rng: inout Minstd, _ c: inout [Int]) {
    let a = rng.below(c.count), b = rng.below(c.count);
    c.swapAt(a, b)
}
func insertMutation(_ rng: inout Minstd, _ c: inout [Int]) {
    let a = rng.below(c.count), b = rng.below(c.count), g = c.remove(at: a);
    c.insert(g, at: b)
}
