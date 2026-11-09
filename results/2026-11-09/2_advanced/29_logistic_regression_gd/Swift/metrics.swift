import Foundation
func fixed(_ value: Double, _ places: Int) -> String {
    let s = String(format: "%.*f", places, value);
    return s.hasPrefix("-") && Double(s) == 0 ? String(s.dropFirst()) : s
}
func ratio(_ a: Int, _ b: Int) -> String {
    if b == 0 {
        return "-"
    };
    let q = (20000*a+b)/(2*b);
    return "\(q/10000)."+String(format: "%04d", q%10000)
}
func fraction(_ a: Int, _ b: Int) -> String {
    var x = a, y = b;
    while y != 0 {
        let r = x%y;
        x = y;
        y = r
    };
    return "\(a/x)/\(b/x) \(ratio(a,b))"
}
struct Confusion {
    var tp = 0,
    fp = 0,
    tn = 0,
    fn = 0
    init(_ pred: [Int], _ y: [Int]) {
        for(p, y)in zip(pred, y) {
            if p == 1 && y == 1 {
                tp += 1
            }else if p == 1 {
                fp += 1
            }else if y == 0 {
                tn += 1
            }else {
                fn += 1
            }
        }
    }
}
func auc(_ scores: [Double], _ y: [Int]) -> (Int, Int) {
    let order = scores.indices.sorted {
        scores[$0] != scores[$1] ? scores[$0]<scores[$1] : $0<$1
    }, pos = y.reduce(0, +), neg = y.count-pos;
    var sum = 0, start = 0;
    while start<order.count {
        var end = start;
        while end+1<order.count && scores[order[end+1]] == scores[order[start]] {
            end += 1
        };
        for k in start...end {
            if y[order[k]] == 1 {
                sum += start+end+2
            }
        };
        start = end+1
    };
    return(sum-pos*(pos+1), 2*pos*neg)
}
struct RocPoint {
    let threshold: Double,
    tp: Int,
    fp: Int
}
func roc(_ p: [Double], _ y: [Int]) -> [RocPoint] {
    let order = p.indices.sorted {
        p[$0] != p[$1] ? p[$0]>p[$1] : $0<$1
    };
    var tp = 0, fp = 0, out = [RocPoint]();
    for(k, i)in order.enumerated() {
        if y[i] == 1 {
            tp += 1
        }else {
            fp += 1
        };
        if k+1 == order.count || p[order[k+1]] != p[i] {
            out.append(RocPoint(threshold: p[i], tp: tp, fp: fp))
        }
    };
    return out
}
