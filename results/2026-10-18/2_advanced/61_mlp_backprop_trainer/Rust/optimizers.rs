use crate::dataset::Run;

pub struct State {
    first: Vec<f64>,
    second: Vec<f64>,
    pi1: f64,
    pi2: f64,
}

impl State {
    pub fn new(parameters: usize) -> Self { Self { first: vec![0.0; parameters], second: vec![0.0; parameters], pi1: 1.0, pi2: 1.0 } }

    pub fn update(&mut self, theta: &mut [f64], gradient: &[f64], run: &Run, eta: f64) {
        if run.optimizer == "ADAM" {
            self.pi1 *= run.arguments[0];
            self.pi2 *= run.arguments[1];
        }
        for p in 0..theta.len() {
            match run.optimizer.as_str() {
                "SGD" => theta[p] -= eta*gradient[p],
                "MOMENTUM" => {
                    self.first[p] = run.arguments[0]*self.first[p]+gradient[p];
                    theta[p] -= eta*self.first[p];
                }
                _ => {
                    let (beta1, beta2, epsilon) = (run.arguments[0], run.arguments[1], run.arguments[2]);
                    self.first[p] = beta1*self.first[p]+(1.0-beta1)*gradient[p];
                    self.second[p] = beta2*self.second[p]+(1.0-beta2)*gradient[p]*gradient[p];
                    let m = self.first[p]/(1.0-self.pi1);
                    let v = self.second[p]/(1.0-self.pi2);
                    theta[p] -= eta*m/(v.sqrt()+epsilon);
                }
            }
        }
    }
}

pub fn learning_rate(run: &Run, epoch: usize, step: usize, gamma: f64) -> f64 {
    let mut eta = run.eta;
    for _ in 0..(epoch-1)/step { eta *= gamma; }
    eta
}
