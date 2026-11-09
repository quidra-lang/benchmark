import Foundation
func softmaxProbabilities(_ w: [[Double]], _ x: [Double]) -> [Double] {
    let a = w.map {
        score($0, x)
    }, top = a.max()!, shifted = a.map {
        $0-top
    }, total = shifted.reduce(0.0) {
        $0+exp($1)
    };
    return shifted.map {
        exp($0)/total
    }
}
func predictedClass(_ p: [Double]) -> Int {
    p.firstIndex(of: p.max()!)!
}
func softmaxLoss(_ w: [[Double]], _ x: [[Double]], _ labels: [Int]) -> Double {
    var total = 0.0;
    for(v, c)in zip(x, labels) {
        let a = w.map {
            score($0, v)
        }, top = a.max()!, s = a.reduce(0.0) {
            $0+exp($1-top)
        };
        total += log(s)-(a[c]-top)
    };
    return total/Double(x.count)
}
func softmaxObjective(_ w: [[Double]], _ x: [[Double]], _ labels: [Int], _ lam: Double) -> Double {
    var penalty = 0.0;
    for row in w {
        for v in row.dropFirst() {
            penalty += v*v
        }
    };
    return softmaxLoss(w, x, labels)+lam*penalty/2
}
func softmaxGradient(_ w: [[Double]], _ x: [[Double]], _ labels: [Int], _ lam: Double) -> [[Double]] {
    var g = Array(repeating: Array(repeating: 0.0, count: w[0].count), count: w.count);
    for(v, c)in zip(x, labels) {
        let p = softmaxProbabilities(w, v);
        for k in w.indices {
            let error = p[k]-(c == k ? 1.0 : 0.0);
            for j in v.indices {
                g[k][j] += error*v[j]
            }
        }
    };
    for k in w.indices {
        for j in w[k].indices {
            g[k][j] /= Double(x.count);
            if j>0 {
                g[k][j] += lam*w[k][j]
            }
        }
    };
    return g
}
func trainSoftmax(_ x: [[Double]], _ labels: [Int], _ classes: Int, _ lam: Double, _ rate: Double, _ iterations: Int) -> [(Int, [[Double]])] {
    var w = Array(repeating: Array(repeating: 0.0, count: x[0].count), count: classes), out = [(Int, [[Double]])]();
    out.append((0, w));
    for t in 1...iterations {
        let g = softmaxGradient(w, x, labels, lam);
        for k in w.indices {
            for j in w[k].indices {
                w[k][j] -= rate*g[k][j]
            }
        };
        if t%100 == 0 {
            out.append((t, w))
        }
    };
    return out
}
