use crate::selection::sum;

type Curve = (Vec<f64>, Vec<f64>);

pub struct Spline {
    positions: Vec<i64>,
    x: Vec<f64>,
    h: Vec<f64>,
    lambda: f64,
    d: Vec<f64>,
    l1: Vec<f64>,
    l2: Vec<f64>,
    pub curve: Curve,
    basis: Vec<Curve>,
    pub leverage: Vec<f64>,
    pub edf: f64,
}

impl Spline {
    pub fn new(positions: &[i64], values: &[f64], lambda: f64, full: bool) -> Self {
        let x: Vec<_> = positions.iter().map(|&v| v as f64 / 100.0).collect();
        let h: Vec<_> = x.windows(2).map(|v| v[1] - v[0]).collect();
        let m = positions.len() - 2;
        let a: Vec<_> = (0..m).map(|i| 1.0 / h[i]).collect();
        let c: Vec<_> = (0..m).map(|i| 1.0 / h[i + 1]).collect();
        let b: Vec<_> = (0..m).map(|i| -(a[i] + c[i])).collect();
        let diagonal: Vec<_> = (0..m).map(|i| (h[i] + h[i + 1]) / 3.0 + lambda * (a[i] * a[i] + b[i] * b[i] + c[i] * c[i])).collect();
        let first: Vec<_> = (0..m.saturating_sub(1)).map(|i| h[i + 1] / 6.0 + lambda * c[i] * (b[i] + b[i + 1])).collect();
        let second: Vec<_> = (0..m.saturating_sub(2)).map(|i| lambda * c[i] * c[i + 1]).collect();
        let mut result = Self {
            positions: positions.to_vec(), x, h, lambda, d: vec![0.0; m], l1: vec![0.0; m], l2: vec![0.0; m],
            curve: (Vec::new(), Vec::new()), basis: Vec::new(), leverage: Vec::new(), edf: 0.0,
        };
        for i in 0..m {
            if i >= 2 { result.l2[i] = second[i - 2] / result.d[i - 2]; }
            if i >= 1 {
                let correction = if i >= 2 { result.l2[i] * result.d[i - 2] * result.l1[i - 1] } else { 0.0 };
                result.l1[i] = (first[i - 1] - correction) / result.d[i - 1];
            }
            let mut value = diagonal[i];
            if i >= 1 { value -= result.l1[i] * result.l1[i] * result.d[i - 1]; }
            if i >= 2 { value -= result.l2[i] * result.l2[i] * result.d[i - 2]; }
            result.d[i] = value;
        }
        result.curve = result.fit(values);
        if full {
            for i in 0..positions.len() {
                let mut unit = vec![0.0; positions.len()];
                unit[i] = 1.0;
                result.basis.push(result.fit(&unit));
            }
            result.leverage = result.basis.iter().enumerate().map(|(i, fit)| fit.0[i]).collect();
            result.edf = sum(result.leverage.iter().copied());
        }
        result
    }

    pub fn fit(&self, values: &[f64]) -> Curve {
        let n = values.len();
        let m = n - 2;
        let mut z = vec![0.0; m];
        for i in 0..m {
            let mut value = (values[i + 2] - values[i + 1]) / self.h[i + 1] - (values[i + 1] - values[i]) / self.h[i];
            if i >= 1 { value -= self.l1[i] * z[i - 1]; }
            if i >= 2 { value -= self.l2[i] * z[i - 2]; }
            z[i] = value;
        }
        let mut gamma = vec![0.0; n];
        for i in (0..m).rev() {
            let mut value = z[i] / self.d[i];
            if i + 1 < m { value -= self.l1[i + 1] * gamma[i + 2]; }
            if i + 2 < m { value -= self.l2[i + 2] * gamma[i + 3]; }
            gamma[i + 1] = value;
        }
        let mut fitted = Vec::new();
        for i in 0..n {
            let omega = if i == 0 { (gamma[1] - gamma[0]) / self.h[0] }
                else if i == n - 1 { 0.0 - (gamma[n - 1] - gamma[n - 2]) / self.h[n - 2] }
                else { (gamma[i + 1] - gamma[i]) / self.h[i] - (gamma[i] - gamma[i - 1]) / self.h[i - 1] };
            fitted.push(values[i] - self.lambda * omega);
        }
        (fitted, gamma)
    }

    pub fn evaluate(&self, curve: &Curve, position: i64) -> f64 {
        let n = self.positions.len();
        let (g, gamma) = curve;
        let x0 = position as f64 / 100.0;
        let index = self.positions.partition_point(|&x| x < position);
        if index < n && self.positions[index] == position { return g[index]; }
        if index == 0 {
            let tau = (g[1] - g[0]) / self.h[0] - self.h[0] * gamma[1] / 6.0;
            return g[0] - (self.x[0] - x0) * tau;
        }
        if index == n {
            let tau = (g[n - 1] - g[n - 2]) / self.h[n - 2] + self.h[n - 2] * gamma[n - 2] / 6.0;
            return g[n - 1] + (x0 - self.x[n - 1]) * tau;
        }
        let i = index - 1;
        let pl = x0 - self.x[i];
        let pr = self.x[i + 1] - x0;
        (pl * g[i + 1] + pr * g[i]) / self.h[i] - pl * pr * ((1.0 + pl / self.h[i]) * gamma[i + 1] + (1.0 + pr / self.h[i]) * gamma[i]) / 6.0
    }

    pub fn estimate(&self, position: i64) -> f64 { self.evaluate(&self.curve, position) }

    pub fn weights(&self, position: i64) -> Vec<f64> {
        self.basis.iter().map(|curve| self.evaluate(curve, position)).collect()
    }
}
