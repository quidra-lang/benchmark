import Foundation
func score(_ w: [Double], _ x: [Double]) -> Double {
    zip(w, x).reduce(0.0) {
        $0+$1.0*$1.1
    }
}
func probability(_ u: Double) -> Double {
    if u >= 0 {
        return 1/(1+exp(-u))
    };
    let e = exp(u);
    return e/(1+e)
}
func loss(_ u: Double, _ y: Int) -> Double {
    max(u, 0)-Double(y)*u+log(1+exp(-abs(u)))
}
func averageLoss(_ w: [Double], _ x: [[Double]], _ y: [Int]) -> Double {
    zip(x, y).reduce(0.0) {
        $0+loss(score(w, $1.0), $1.1)
    }
    /Double(x.count)
}
func objective(_ w: [Double], _ x: [[Double]], _ y: [Int], _ lam: Double) -> Double {
    averageLoss(w, x, y)+lam*w.dropFirst().reduce(0.0) {
        $0+$1*$1
    }
    /2
}
func gradient(_ w: [Double], _ x: [[Double]], _ y: [Int], _ lam: Double) -> [Double] {
    var g = Array(repeating: 0.0, count: w.count);
    for(v, y)in zip(x, y) {
        let error = probability(score(w, v))-Double(y);
        for j in w.indices {
            g[j] += error*v[j]
        }
    };
    for j in w.indices {
        g[j] /= Double(x.count);
        if j>0 {
            g[j] += lam*w[j]
        }
    };
    return g
}
func hessian(_ w: [Double], _ x: [[Double]], _ lam: Double) -> [[Double]] {
    let n = w.count;
    var h = Array(repeating: Array(repeating: 0.0, count: n), count: n);
    for v in x {
        let p = probability(score(w, v)), a = p*(1-p);
        for j in 0..<n {
            for k in 0...j {
                h[j][k] += a*v[j]*v[k]
            }
        }
    };
    for j in 0..<n {
        for k in 0...j {
            h[j][k] /= Double(x.count);
            if j == k && j>0 {
                h[j][k] += lam
            };
            h[k][j] = h[j][k]
        }
    };
    return h
}
