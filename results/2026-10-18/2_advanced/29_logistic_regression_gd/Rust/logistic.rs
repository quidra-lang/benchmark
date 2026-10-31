pub fn score(w: &[f64], x: &[f64]) -> f64 {
    w.iter().zip(x).fold(0.0, |s, (w, x)|s+w*x)
}
pub fn probability(u: f64) -> f64 {
    if u >= 0.0 {
        1.0/(1.0+(-u).exp())
    }else {
        let e = u.exp();
        e/(1.0+e)
    }
}
pub fn loss(u: f64, y: usize) -> f64 {
    u.max(0.0)-y as f64*u+(1.0+(-u.abs()).exp()).ln()
}
pub fn average_loss(w: &[f64], x: &[Vec<f64>], y: &[usize]) -> f64 {
    x.iter().zip(y).fold(0.0, |s, (x, &y)|s+loss(score(w, x), y))/x.len() as f64
}
pub fn objective(w: &[f64], x: &[Vec<f64>], y: &[usize], lam: f64) -> f64 {
    average_loss(w, x, y)+lam*w[1..].iter().fold(0.0, |s, w|s+w*w)/2.0
}
pub fn gradient(w: &[f64], x: &[Vec<f64>], y: &[usize], lam: f64) -> Vec<f64> {
    let mut g = vec![0.0; w.len()];
    for(x, &y)in x.iter().zip(y) {
        let e = probability(score(w, x))-y as f64;
        for j in 0..w.len() {
            g[j] += e*x[j];
        }
    }
    for j in 0..w.len() {
        g[j] /= x.len() as f64;
        if j>0 {
            g[j] += lam*w[j]
        }
    }
    g
}
pub fn hessian(w: &[f64], x: &[Vec<f64>], lam: f64) -> Vec<Vec<f64>> {
    let n = w.len();
    let mut h = vec![vec![0.0; n]; n];
    for v in x {
        let p = probability(score(w, v));
        let a = p*(1.0-p);
        for j in 0..n {
            for k in 0..=j {
                h[j][k] += a*v[j]*v[k];
            }
        }
    }
    for j in 0..n {
        for k in 0..=j {
            h[j][k] /= x.len()as f64;
            if j == k && j>0 {
                h[j][k] += lam
            }
            h[k][j] = h[j][k];
        }
    }
    h
}
