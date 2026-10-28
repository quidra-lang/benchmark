pub fn fixed(v: f64, p: usize) -> String {
    let s = format!("{v:.p$}");
    if s.starts_with('-') && s.parse::<f64>().unwrap() == 0.0 {
        s[1..].into()
    }else {
        s
    }
}
pub fn ratio(a: i64, b: i64) -> String {
    if b == 0 {
        return "-".into()
    }
    let q = (20000*a+b)/(2*b);
    format!("{}.{:04}", q/10000, q%10000)
}
pub fn fraction(a: i64, b: i64) -> String {
    let(mut x, mut y) = (a, b);
    while y != 0 {
        let r = x%y;
        x = y;
        y = r;
    }
    format!("{}/{} {}", a/x, b/x, ratio(a, b))
}
pub struct Confusion {
    pub tp: i64,
    pub fp: i64,
    pub tn: i64,
    pub fn_: i64
}
impl Confusion {
    pub fn new(pred: &[usize], y: &[usize]) -> Self {
        let mut c = Self {
            tp: 0,
            fp: 0,
            tn: 0,
            fn_: 0
        };
        for(&p, &y)in pred.iter().zip(y) {
            match(p, y) {
                (1, 1) => c.tp += 1, (1, _) => c.fp += 1, (_, 0) => c.tn += 1, _ => c.fn_ += 1
            }
        }
        c
    }
}
pub fn auc(scores: &[f64], y: &[usize]) -> (i64, i64) {
    let mut order = (0..scores.len()).collect::<Vec<_>>();
    order.sort_by(|&a, &b|scores[a].total_cmp(&scores[b]).then(a.cmp(&b)));
    let pos = y.iter().sum::<usize>()as i64;
    let neg = y.len()as i64-pos;
    let(mut sum, mut start) = (0, 0);
    while start<order.len() {
        let mut end = start;
        while end+1<order.len() && scores[order[end+1]] == scores[order[start]] {
            end += 1
        }
        for k in start..=end {
            if y[order[k]] == 1 {
                sum += (start+end+2)as i64
            }
        }
        start = end+1;
    }
    (sum-pos*(pos+1), 2*pos*neg)
}
pub struct RocPoint {
    pub threshold: f64,
    pub tp: i64,
    pub fp: i64
}
pub fn roc(scores: &[f64], y: &[usize]) -> Vec<RocPoint> {
    let mut order = (0..scores.len()).collect::<Vec<_>>();
    order.sort_by(|&a, &b|scores[b].total_cmp(&scores[a]).then(a.cmp(&b)));
    let(mut tp, mut fp) = (0, 0);
    let mut out = vec![];
    for(k, &i)in order.iter().enumerate() {
        if y[i] == 1 {
            tp += 1
        }else {
            fp += 1
        }
        if k+1 == order.len() || scores[order[k+1]] != scores[i] {
            out.push(RocPoint {
                threshold: scores[i],
                tp,
                fp
            });
        }
    }
    out
}
