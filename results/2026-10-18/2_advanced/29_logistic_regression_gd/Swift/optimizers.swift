import Foundation
typealias Checkpoints = [(Int, [Double])]
struct Minstd {
    var state: Int
    mutating func draw() -> Int {
        state = state*48271%2147483647;
        return state
    }
    mutating func shuffle(_ items: inout [Int]) {
        if items.count>1 {
            for n in stride(from: items.count, through: 2, by: -1) {
                let k = draw()%n;
                items.swapAt(n-1, k)
            }
        }
    }
}
func cholesky(_ a: [[Double]]) -> [[Double]] {
    let n = a.count;
    var l = Array(repeating: Array(repeating: 0.0, count: n), count: n);
    for j in 0..<n {
        for i in j..<n {
            let total = (0..<j).reduce(0.0) {
                $0+l[i][$1]*l[j][$1]
            }, r = a[i][j]-total;
            l[i][j] = i == j ? sqrt(r) : r/l[j][j]
        }
    };
    return l
}
func solve(_ l: [[Double]], _ b: [Double]) -> [Double] {
    let n = b.count;
    var z = Array(repeating: 0.0, count: n), x = z;
    for i in 0..<n {
        let total = (0..<i).reduce(0.0) {
            $0+l[i][$1]*z[$1]
        };
        z[i] = (b[i]-total)/l[i][i]
    };
    for i in stride(from: n-1, through: 0, by: -1) {
        let total = ((i+1)..<n).reduce(0.0) {
            $0+l[$1][i]*x[$1]
        };
        x[i] = (z[i]-total)/l[i][i]
    };
    return x
}
func newtonDirection(_ w: [Double], _ x: [[Double]], _ y: [Int], _ lam: Double) -> ([Double], [Double]) {
    let g = gradient(w, x, y, lam);
    return(g, solve(cholesky(hessian(w, x, lam)), g))
}
func newton(_ x: [[Double]], _ y: [Int], _ lam: Double) -> Checkpoints {
    var w = Array(repeating: 0.0, count: x[0].count), out: Checkpoints = [(0, Array(repeating: 0.0, count: x[0].count))];
    for t in 1...10 {
        let(_, step) = newtonDirection(w, x, y, lam);
        for j in w.indices {
            w[j] -= step[j]
        };
        out.append((t, w))
    };
    return out
}
func gradientDescent(_ x: [[Double]], _ y: [Int], _ lam: Double, _ rate: Double, _ iterations: Int) -> Checkpoints {
    var w = Array(repeating: 0.0, count: x[0].count), out: Checkpoints = [(0, Array(repeating: 0.0, count: x[0].count))];
    for t in 1...iterations {
        let g = gradient(w, x, y, lam);
        for j in w.indices {
            w[j] -= rate*g[j]
        };
        if t%100 == 0 {
            out.append((t, w))
        }
    };
    return out
}
func stochasticDescent(_ x: [[Double]], _ y: [Int], _ lam: Double, _ rate: Double, _ batch: Int, _ epochs: Int, _ seed: Int) -> Checkpoints {
    var rng = Minstd(state: seed), order = Array(x.indices), w = Array(repeating: 0.0, count: x[0].count), out: Checkpoints = [(0, Array(repeating: 0.0, count: x[0].count))];
    for epoch in 1...epochs {
        rng.shuffle(&order);
        for start in stride(from: 0, to: order.count, by: batch) {
            let ids = order[start..<min(start+batch, order.count)], g = gradient(w, ids.map {
                x[$0]
            }, ids.map {
                y[$0]
            }, lam);
            for j in w.indices {
                w[j] -= rate*g[j]
            }
        };
        out.append((epoch, w))
    };
    return out
}
