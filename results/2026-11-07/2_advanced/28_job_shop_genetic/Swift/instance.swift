import Foundation
struct Operation {
    let job: Int,
    index: Int,
    machine: Int,
    duration: Int,
    head: Int,
    tail: Int;
    let previous: Int?,
    next: Int?
}
struct Job {
    let number: Int,
    operations: [Int],
    work: Int
}
struct Machine {
    let operations: [Int],
    load: Int,
    head: Int,
    tail: Int,
    bound: Int
}
struct Instance {
    let jobs: [Job],
    operations: [Operation],
    machines: [Machine],
    errors: [String]
    init() throws {
        let lines = try String(contentsOfFile: "input/instance.txt", encoding: .utf8).split(separator: "\n"), dims = lines[0].split(separator: " ").map {
            Int($0)!
        };
        var jobs = [Job](), ops = [Operation](), errors = [String]()
        for number in 1...dims[0] {
            var steps = [(Int, Int)](), seen = Set<Int>(), valid = true
            for(index, token)in lines[number].split(separator: " ").enumerated() {
                let p = token.split(separator: ":").map {
                    Int($0)!
                }, m = p[0], d = p[1];
                let reason: String?
                if m<1 || m>dims[1] {
                    reason = "unknown machine \(m)"
                }else if d<1 || d>99 {
                    reason = "bad duration \(d)"
                }else if seen.contains(m) {
                    reason = "repeated machine \(m)"
                }else {
                    reason = nil
                }
                if let reason = reason {
                    errors.append("job \(number) operation \(index+1): \(reason)");
                    valid = false;
                    break
                };
                seen.insert(m);
                steps.append((m-1, d))
            }
            if !valid {
                continue
            };
            let work = steps.reduce(0) {
                $0+$1.1
            }, first = ops.count;
            var head = 0
            for(index, step)in steps.enumerated() {
                ops.append(Operation(job: jobs.count, index: index+1, machine: step.0, duration: step.1, head: head, tail: work-head-step.1, previous: index == 0 ? nil : first+index-1, next: index+1 == steps.count ? nil : first+index+1));
                head += step.1
            }
            jobs.append(Job(number: number, operations: Array(first..<ops.count), work: work))
        }
        self.jobs = jobs;
        operations = ops;
        self.errors = errors
        machines = (0..<dims[1]).map {
            m in let ids = ops.indices.filter {
                ops[$0].machine == m
            }, load = ids.reduce(0) {
                $0+ops[$1].duration
            }, head = ids.map {
                ops[$0].head
            }.min()!, tail = ids.map {
                ops[$0].tail
            }.min()!;
            return Machine(operations: ids, load: load, head: head, tail: tail, bound: head+load+tail)
        }
    }
    var durations: [Int] {
        operations.map(\.duration)
    }
    func code(_ i: Int) -> String {
        let o = operations[i];
        return "J\(jobs[o.job].number)-\(o.index)"
    }
}
