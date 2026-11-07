use crate::logistic::score;
pub fn probabilities(w: &[Vec<f64>], x: &[f64]) -> Vec<f64> {
    let a = w.iter().map(|w|score(w, x)).collect::<Vec<_>>();
    let top = a.iter().fold(f64::NEG_INFINITY, |a, &b|a.max(b));
    let shifted = a.iter().map(|&v|v-top).collect::<Vec<_>>();
    let total = shifted.iter().fold(0.0, |s, &v|s+v.exp());
    shifted.iter().map(|v|v.exp()/total).collect()
}
pub fn predicted(p: &[f64]) -> usize {
    let mut k = 0;
    for i in 1..p.len() {
        if p[i]>p[k] {
            k = i
        }
    }
    k
}
pub fn average_loss(w: &[Vec<f64>], x: &[Vec<f64>], labels: &[usize]) -> f64 {
    let mut loss = 0.0;
    for(x, &c)in x.iter().zip(labels) {
        let a = w.iter().map(|w|score(w, x)).collect::<Vec<_>>();
        let top = a.iter().fold(f64::NEG_INFINITY, |a, &b|a.max(b));
        let sum = a.iter().fold(0.0, |s, &v|s+(v-top).exp());
        loss += sum.ln()-(a[c]-top);
    }
    loss/x.len()as f64
}
pub fn objective(w: &[Vec<f64>], x: &[Vec<f64>], labels: &[usize], lam: f64) -> f64 {
    let mut penalty = 0.0;
    for row in w {
        for v in &row[1..] {
            penalty += v*v
        }
    }
    average_loss(w, x, labels)+lam*penalty/2.0
}
pub fn gradient(w: &[Vec<f64>], x: &[Vec<f64>], labels: &[usize], lam: f64) -> Vec<Vec<f64>> {
    let mut g = vec![vec![0.0; w[0].len()]; w.len()];
    for(x, &c)in x.iter().zip(labels) {
        let p = probabilities(w, x);
        for k in 0..w.len() {
            let e = p[k]-if c == k {
                1.0
            }else {
                0.0
            };
            for j in 0..x.len() {
                g[k][j] += e*x[j];
            }
        }
    }
    for k in 0..w.len() {
        for j in 0..w[k].len() {
            g[k][j] /= x.len()as f64;
            if j>0 {
                g[k][j] += lam*w[k][j]
            }
        }
    }
    g
}
pub fn train(x: &[Vec<f64>], labels: &[usize], classes: usize, lam: f64, rate: f64, iterations: usize) -> Vec<(usize, Vec<Vec<f64>>)> {
    let mut w = vec![vec![0.0; x[0].len()]; classes];
    let mut out = vec![(0, w.clone())];
    for t in 1..=iterations {
        let g = gradient(&w, x, labels, lam);
        for k in 0..classes {
            for j in 0..w[k].len() {
                w[k][j] -= rate*g[k][j]
            }
        }
        if t%100 == 0 {
            out.push((t, w.clone()))
        }
    }
    out
}
