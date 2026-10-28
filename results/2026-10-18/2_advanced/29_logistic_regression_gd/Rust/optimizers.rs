use crate::logistic::{
    gradient, hessian
};
pub type Checkpoints = Vec<(usize, Vec<f64>)>;
pub struct Minstd {
    pub state: i64
}
impl Minstd {
    pub fn draw(&mut self) -> usize {
        self.state = self.state*48271%2147483647;
        self.state as usize
    }
    pub fn shuffle(&mut self, items: &mut [usize]) {
        for n in (2..=items.len()).rev() {
            let k = self.draw()%n;
            items.swap(n-1, k);
        }
    }
}
pub fn cholesky(a: &[Vec<f64>]) -> Vec<Vec<f64>> {
    let n = a.len();
    let mut l = vec![vec![0.0; n]; n];
    for j in 0..n {
        for i in j..n {
            let total = (0..j).fold(0.0, |s, k|s+l[i][k]*l[j][k]);
            let r = a[i][j]-total;
            l[i][j] = if i == j {
                r.sqrt()
            }else {
                r/l[j][j]
            };
        }
    }
    l
}
pub fn solve(l: &[Vec<f64>], b: &[f64]) -> Vec<f64> {
    let n = b.len();
    let mut z = vec![0.0; n];
    for i in 0..n {
        let sum = (0..i).fold(0.0, |s, k|s+l[i][k]*z[k]);
        z[i] = (b[i]-sum)/l[i][i];
    }
    let mut x = vec![0.0; n];
    for i in (0..n).rev() {
        let sum = (i+1..n).fold(0.0, |s, k|s+l[k][i]*x[k]);
        x[i] = (z[i]-sum)/l[i][i];
    }
    x
}
pub fn newton_direction(w: &[f64], x: &[Vec<f64>], y: &[usize], lam: f64) -> (Vec<f64>, Vec<f64>) {
    let g = gradient(w, x, y, lam);
    let step = solve(&cholesky(&hessian(w, x, lam)), &g);
    (g, step)
}
pub fn newton(x: &[Vec<f64>], y: &[usize], lam: f64) -> Checkpoints {
    let mut w = vec![0.0; x[0].len()];
    let mut out = vec![(0, w.clone())];
    for t in 1..=10 {
        let(_, step) = newton_direction(&w, x, y, lam);
        for j in 0..w.len() {
            w[j] -= step[j]
        }
        out.push((t, w.clone()));
    }
    out
}
pub fn gd(x: &[Vec<f64>], y: &[usize], lam: f64, rate: f64, iterations: usize) -> Checkpoints {
    let mut w = vec![0.0; x[0].len()];
    let mut out = vec![(0, w.clone())];
    for t in 1..=iterations {
        let g = gradient(&w, x, y, lam);
        for j in 0..w.len() {
            w[j] -= rate*g[j]
        }
        if t%100 == 0 {
            out.push((t, w.clone()))
        }
    }
    out
}
pub fn sgd(x: &[Vec<f64>], y: &[usize], lam: f64, rate: f64, batch: usize, epochs: usize, seed: i64) -> Checkpoints {
    let mut rng = Minstd {
        state: seed
    };
    let mut order = (0..x.len()).collect::<Vec<_>>();
    let mut w = vec![0.0; x[0].len()];
    let mut out = vec![(0, w.clone())];
    for e in 1..=epochs {
        rng.shuffle(&mut order);
        for ids in order.chunks(batch) {
            let bx = ids.iter().map(|&i|x[i].clone()).collect::<Vec<_>>();
            let by = ids.iter().map(|&i|y[i]).collect::<Vec<_>>();
            let g = gradient(&w, &bx, &by, lam);
            for j in 0..w.len() {
                w[j] -= rate*g[j]
            }
        }
        out.push((e, w.clone()));
    }
    out
}
