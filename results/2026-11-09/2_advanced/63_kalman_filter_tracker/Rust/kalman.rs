use crate::matrix::{self, Matrix};

pub struct Config { pub sigma: f64, pub velocity: f64, pub acceleration: f64, pub q_cv: f64, pub q_ca: f64 }

#[derive(Clone)]
pub struct State { pub x: Vec<f64>, pub covariance: Matrix }

pub struct Innovation { pub residual: [f64; 2], pub covariance: Matrix, pub inverse: Matrix, pub distance: f64 }

pub fn transition(ca: bool, t: f64) -> Matrix {
    let mut f = matrix::identity(if ca { 6 } else { 4 });
    f[0][2] = t; f[1][3] = t;
    if ca { f[0][4] = t*t/2.0; f[1][5] = t*t/2.0; f[2][4] = t; f[3][5] = t; }
    f
}

pub fn noise(ca: bool, t: f64, q: f64) -> Matrix {
    let mut result = vec![vec![0.0; if ca { 6 } else { 4 }]; if ca { 6 } else { 4 }];
    let entries = if ca {
        vec![(0, 0, q*t*t*t*t*t/20.0), (0, 1, q*t*t*t*t/8.0), (0, 2, q*t*t*t/6.0),
            (1, 1, q*t*t*t/3.0), (1, 2, q*t*t/2.0), (2, 2, q*t)]
    } else { vec![(0, 0, q*t*t*t/3.0), (0, 1, q*t*t/2.0), (1, 1, q*t)] };
    for axis in 0..2 { for &(a, b, value) in &entries {
        result[2*a+axis][2*b+axis] = value; result[2*b+axis][2*a+axis] = value;
    } }
    result
}

impl State {
    pub fn new(position: [f64; 2], ca: bool, config: &Config) -> Self {
        let mut x = vec![position[0], position[1], 0.0, 0.0];
        let mut diagonal = vec![config.sigma*config.sigma, config.sigma*config.sigma, config.velocity, config.velocity];
        if ca { x.extend([0.0, 0.0]); diagonal.extend([config.acceleration, config.acceleration]); }
        Self { x, covariance: matrix::diagonal(&diagonal) }
    }

    pub fn predict(&self, t: f64, q: f64) -> (Self, Matrix) {
        let ca = self.x.len() == 6;
        let f = transition(ca, t);
        let x = matrix::vector(&f, &self.x);
        let covariance = matrix::add(&matrix::product(&matrix::product(&f, &self.covariance), &matrix::transpose(&f)), &noise(ca, t, q));
        (Self { x, covariance }, f)
    }

    pub fn innovation(&self, measurement: [f64; 2], sigma: f64) -> Innovation {
        let residual = [measurement[0]-self.x[0], measurement[1]-self.x[1]];
        let mut covariance = vec![self.covariance[0][..2].to_vec(), self.covariance[1][..2].to_vec()];
        covariance[0][0] += sigma*sigma; covariance[1][1] += sigma*sigma;
        let inverse = matrix::inverse(&covariance);
        let distance = matrix::quadratic(residual, &inverse);
        Innovation { residual, covariance, inverse, distance }
    }

    pub fn update(&mut self, measurement: [f64; 2], sigma: f64) -> (f64, f64, f64) {
        let innovation = self.innovation(measurement, sigma);
        let n = self.x.len();
        let ph: Matrix = self.covariance.iter().map(|row| row[..2].to_vec()).collect();
        let gain = matrix::product(&ph, &innovation.inverse);
        let change = matrix::vector(&gain, &innovation.residual);
        for i in 0..n { self.x[i] += change[i]; }
        let mut h = vec![vec![0.0; n]; 2]; h[0][0] = 1.0; h[1][1] = 1.0;
        let j = matrix::subtract(&matrix::identity(n), &matrix::product(&gain, &h));
        let r = matrix::diagonal(&[sigma*sigma, sigma*sigma]);
        self.covariance = matrix::add(&matrix::product(&matrix::product(&j, &self.covariance), &matrix::transpose(&j)),
            &matrix::product(&matrix::product(&gain, &r), &matrix::transpose(&gain)));
        let determinant = matrix::determinant(&innovation.covariance);
        let log_likelihood = -(2.0*std::f64::consts::PI).ln()-determinant.ln()/2.0-innovation.distance/2.0;
        let likelihood = (-innovation.distance/2.0).exp()/(2.0*std::f64::consts::PI*determinant.sqrt());
        (innovation.distance, log_likelihood, likelihood)
    }
}

pub fn smooth(states: &[State], predictions: &[Option<State>], transitions: &[Option<Matrix>]) -> Vec<Vec<f64>> {
    let mut result: Vec<_> = states.iter().map(|s| s.x.clone()).collect();
    for i in (0..states.len()-1).rev() {
        let predicted = predictions[i+1].as_ref().unwrap();
        let c = matrix::product(&matrix::product(&states[i].covariance, &matrix::transpose(transitions[i+1].as_ref().unwrap())), &matrix::inverse(&predicted.covariance));
        let difference: Vec<_> = result[i+1].iter().zip(&predicted.x).map(|(x, p)| x-p).collect();
        let correction = matrix::vector(&c, &difference);
        result[i] = states[i].x.iter().zip(&correction).map(|(x, c)| x+c).collect();
    }
    result
}
