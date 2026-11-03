import Foundation
struct Example {
    let id: String,
    values: [Double],
    label: Int
}
struct Settings {
    let values: [String: [String]]
    init() throws {
        values = Dictionary(uniqueKeysWithValues: try String(contentsOfFile: "input/params.txt", encoding: .utf8).split(separator: "\n").map {
            let f = $0.split(separator: " ").map(String.init); return(f[0], Array(f.dropFirst()))
        })
    }
    func real(_ k: String, _ i: Int = 0) -> Double {
        Double(values[k]![i])!
    }
    func int(_ k: String, _ i: Int = 0) -> Int {
        Int(values[k]![i])!
    }
}
func readExamples(_ name: String) throws -> ([String], [Example]) {
    let lines = try String(contentsOfFile: "input/"+name+".csv", encoding: .utf8).split(separator: "\n"), headers = lines[0].split(separator: ",").map(String.init), names = Array(headers.dropFirst().dropLast());
    let rows = lines.dropFirst().map {
        line in let f = line.split(separator: ",");
        return Example(id: String(f[0]), values: f.dropFirst().dropLast().map {
            Double($0)!
        }, label: Int(f.last!)!)
    };
    return(names, rows)
}
func expansionTuples(_ d: Int, _ p: Int) -> [[Int]] {
    var out = [[Int]]();
    func extend(_ prefix: [Int], _ start: Int, _ left: Int) {
        if left == 0 {
            out.append(prefix);
            return
        };
        for i in start..<d {
            extend(prefix+[i], i, left-1)
        }
    };
    for k in 1...p {
        extend([], 0, k)
    };
    return out
}
func expandedValues(_ tuples: [[Int]], _ values: [Double]) -> [Double] {
    tuples.map {
        t in var p = values[t[0]];
        for i in t.dropFirst() {
            p *= values[i]
        };
        return p
    }
}
struct Statistics {
    let means: [Double],
    sd: [Double]
}
func statistics(_ rows: [[Double]], _ q: Int) -> Statistics {
    var means = [Double](), sd = [Double]();
    for j in 0..<q {
        let mean = rows.reduce(0.0) {
            $0+$1[j]
        }
        /Double(rows.count), squares = rows.reduce(0.0) {
            $0+($1[j]-mean)*($1[j]-mean)
        };
        means.append(mean);
        sd.append(sqrt(squares/Double(rows.count-1)))
    };
    return Statistics(means: means, sd: sd)
}
func standardize(_ values: [Double], _ s: Statistics, _ q: Int) -> [Double] {
    [1.0]+(0..<q).map {
        (values[$0]-s.means[$0])/s.sd[$0]
    }
}
