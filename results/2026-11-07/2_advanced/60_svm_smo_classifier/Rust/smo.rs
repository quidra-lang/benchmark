use crate::{dataset::Settings, kernels::Kernel};

pub struct Pass {
    pub full: bool,
    pub examined: usize,
    pub changed: usize,
    pub alpha: Option<Vec<f64>>,
}

pub struct Model {
    pub points: Vec<[f64; 2]>,
    pub labels: Vec<f64>,
    pub alpha: Vec<f64>,
    pub b: f64,
    pub c: f64,
    pub full: usize,
    pub nonbound: usize,
    pub examined: usize,
    pub steps: usize,
    pub choices: [usize; 3],
    pub clipping: [usize; 3],
    pub converged: bool,
    pub passes: Vec<Pass>,
}

struct Trainer<'a> { model: Model, errors: Vec<f64>, matrix: &'a [Vec<f64>], params: &'a Settings }

impl<'a> Trainer<'a> {
    fn nonbound(&self, i: usize) -> bool { self.model.alpha[i] > 0.0 && self.model.alpha[i] < self.model.c }
    fn snap(&self, value: f64) -> f64 {
        if value < 0.00000001 { 0.0 } else if value > self.model.c-0.00000001 { self.model.c } else { value }
    }

    fn take(&mut self, i1: usize, i2: usize) -> bool {
        if i1 == i2 { return false; }
        let m = &self.model;
        let (alpha1, alpha2, y1, y2, e1, e2) = (m.alpha[i1], m.alpha[i2], m.labels[i1], m.labels[i2], self.errors[i1], self.errors[i2]);
        let (lo, hi) = if y1 != y2 { (0.0_f64.max(alpha2-alpha1), m.c.min(m.c+alpha2-alpha1)) }
            else { (0.0_f64.max(alpha2+alpha1-m.c), m.c.min(alpha2+alpha1)) };
        if lo == hi { return false; }
        let (k11, k12, k22) = (self.matrix[i1][i1], self.matrix[i1][i2], self.matrix[i2][i2]);
        let eta = k11+k22-2.0*k12;
        if eta <= 0.0 { return false; }
        let mut a2 = alpha2+y2*(e1-e2)/eta;
        let clipping = if a2 < lo { a2 = lo; 1 } else if a2 > hi { a2 = hi; 2 } else { 0 };
        a2 = self.snap(a2);
        if (a2-alpha2).abs() < self.params.eps*(a2+alpha2+self.params.eps) { return false; }
        let a1 = self.snap(alpha1+y1*y2*(alpha2-a2));
        let (t1, t2) = (y1*(a1-alpha1), y2*(a2-alpha2));
        let b1 = e1+t1*k11+t2*k12+m.b;
        let b2 = e2+t1*k12+t2*k22+m.b;
        let b = if a1 > 0.0 && a1 < m.c { b1 } else if a2 > 0.0 && a2 < m.c { b2 } else { (b1+b2)/2.0 };
        let delta = b-m.b;
        for i in 0..self.errors.len() { self.errors[i] += t1*self.matrix[i1][i]+t2*self.matrix[i2][i]-delta; }
        if a1 > 0.0 && a1 < m.c { self.errors[i1] = 0.0; }
        if a2 > 0.0 && a2 < m.c { self.errors[i2] = 0.0; }
        self.model.alpha[i1] = a1;
        self.model.alpha[i2] = a2;
        self.model.b = b;
        self.model.steps += 1;
        self.model.clipping[clipping] += 1;
        true
    }

    fn examine(&mut self, i2: usize) -> usize {
        self.model.examined += 1;
        let r = self.errors[i2]*self.model.labels[i2];
        if !((r < -self.params.tolerance && self.model.alpha[i2] < self.model.c)
            || (r > self.params.tolerance && self.model.alpha[i2] > 0.0)) { return 0; }
        let mut best = None;
        let mut difference = -1.0;
        for i in 0..self.model.alpha.len() {
            if i != i2 && self.nonbound(i) {
                let d = (self.errors[i]-self.errors[i2]).abs();
                if d > difference { best = Some(i); difference = d; }
            }
        }
        if let Some(i) = best {
            if self.take(i, i2) { self.model.choices[0] += 1; return 1; }
        }
        for i in 0..self.model.alpha.len() {
            if self.nonbound(i) && self.take(i, i2) { self.model.choices[1] += 1; return 1; }
        }
        for i in 0..self.model.alpha.len() {
            if self.take(i, i2) { self.model.choices[2] += 1; return 1; }
        }
        0
    }
}

pub fn train(points: &[[f64; 2]], labels: &[f64], matrix: &[Vec<f64>], c: f64, params: &Settings) -> Model {
    let model = Model { points: points.to_vec(), labels: labels.to_vec(), alpha: vec![0.0; points.len()], b: 0.0, c,
        full: 0, nonbound: 0, examined: 0, steps: 0, choices: [0; 3], clipping: [0; 3], converged: false, passes: Vec::new() };
    let mut t = Trainer { model, errors: labels.iter().map(|y| -y).collect(), matrix, params };
    let mut all = true;
    for _ in 0..params.max_passes {
        let before = t.model.examined;
        let mut changed = 0;
        for i in 0..points.len() { if all || t.nonbound(i) { changed += t.examine(i); } }
        if all { t.model.full += 1; } else { t.model.nonbound += 1; }
        let alpha = if all { Some(t.model.alpha.clone()) } else { None };
        t.model.passes.push(Pass { full: all, examined: t.model.examined-before, changed, alpha });
        if all && changed == 0 { t.model.converged = true; break; }
        if all { all = false; } else if changed == 0 { all = true; }
    }
    t.model
}

impl Model {
    pub fn decision(&self, kernel: &Kernel, point: [f64; 2]) -> f64 {
        let mut sum = 0.0;
        for i in 0..self.alpha.len() {
            if self.alpha[i] > 0.0 { sum += self.alpha[i]*self.labels[i]*kernel.value(self.points[i], point); }
        }
        sum-self.b
    }

    pub fn support(&self) -> (usize, usize, usize) {
        let total = self.alpha.iter().filter(|&&a| a > 0.0).count();
        let bound = self.alpha.iter().filter(|&&a| a == self.c).count();
        (total, bound, total-bound)
    }
}

pub fn objective(alpha: &[f64], labels: &[f64], matrix: &[Vec<f64>]) -> (f64, f64) {
    let mut q = 0.0;
    for i in 0..alpha.len() {
        let mut s = 0.0;
        for j in 0..alpha.len() { if alpha[j] > 0.0 { s += alpha[j]*labels[j]*matrix[i][j]; } }
        q += alpha[i]*labels[i]*s;
    }
    (q, alpha.iter().sum::<f64>()-q/2.0)
}
