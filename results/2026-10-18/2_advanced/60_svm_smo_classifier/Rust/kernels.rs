use crate::evaluation::real;

#[derive(Clone)]
pub enum Kind { Linear, Polynomial { degree: usize, gamma: f64, constant: f64 }, Rbf(f64) }

#[derive(Clone)]
pub struct Kernel { pub name: String, pub kind: Kind }

impl Kernel {
    pub fn value(&self, a: [f64; 2], b: [f64; 2]) -> f64 {
        match self.kind {
            Kind::Linear => a[0]*b[0]+a[1]*b[1],
            Kind::Polynomial { degree, gamma, constant } => {
                let s = gamma*(a[0]*b[0]+a[1]*b[1])+constant;
                let mut value = 1.0;
                for _ in 0..degree { value *= s; }
                value
            }
            Kind::Rbf(gamma) => {
                let (e1, e2) = (a[0]-b[0], a[1]-b[1]);
                (-gamma*(e1*e1+e2*e2)).exp()
            }
        }
    }

    pub fn description(&self) -> String {
        match self.kind {
            Kind::Linear => "linear".to_owned(),
            Kind::Polynomial { degree, gamma, constant } => format!("poly degree {} gamma {} coef0 {}", degree, real(gamma, 4), real(constant, 4)),
            Kind::Rbf(gamma) => format!("rbf gamma {}", real(gamma, 4)),
        }
    }

    pub fn matrix(&self, points: &[[f64; 2]]) -> Vec<Vec<f64>> {
        points.iter().map(|&a| points.iter().map(|&b| self.value(a, b)).collect()).collect()
    }
}
