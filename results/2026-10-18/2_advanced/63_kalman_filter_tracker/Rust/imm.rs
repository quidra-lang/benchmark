use crate::{kalman::{Config as KalmanConfig, State as KalmanState}, matrix::Matrix};

pub struct Config { pub noise: [f64; 2], pub transition: [[f64; 2]; 2], pub initial: [f64; 2] }
pub struct State { pub models: [KalmanState; 2], pub probabilities: [f64; 2] }

impl State {
    pub fn new(position: [f64; 2], config: &Config, kalman: &KalmanConfig) -> Self {
        let model = KalmanState::new(position, false, kalman);
        Self { models: [model.clone(), model], probabilities: config.initial }
    }

    pub fn step(&mut self, t: f64, measurement: Option<[f64; 2]>, config: &Config, kalman: &KalmanConfig) {
        let c: Vec<_> = (0..2).map(|j| config.transition[0][j]*self.probabilities[0]+config.transition[1][j]*self.probabilities[1]).collect();
        let mut mixed = Vec::new();
        for j in 0..2 {
            let w = [config.transition[0][j]*self.probabilities[0]/c[j], config.transition[1][j]*self.probabilities[1]/c[j]];
            let x: Vec<_> = (0..4).map(|r| w[0]*self.models[0].x[r]+w[1]*self.models[1].x[r]).collect();
            let covariance: Matrix = (0..4).map(|r| (0..4).map(|s| {
                w[0]*(self.models[0].covariance[r][s]+(self.models[0].x[r]-x[r])*(self.models[0].x[s]-x[s]))
                + w[1]*(self.models[1].covariance[r][s]+(self.models[1].x[r]-x[r])*(self.models[1].x[s]-x[s]))
            }).collect()).collect();
            mixed.push(KalmanState { x, covariance });
        }
        let mut likelihood = [1.0; 2];
        for j in 0..2 {
            let mut predicted = mixed[j].predict(t, config.noise[j]).0;
            if let Some(z) = measurement { likelihood[j] = predicted.update(z, kalman.sigma).2; }
            self.models[j] = predicted;
        }
        let denominator = likelihood[0]*c[0]+likelihood[1]*c[1];
        self.probabilities = [likelihood[0]*c[0]/denominator, likelihood[1]*c[1]/denominator];
    }

    pub fn estimate(&self) -> Vec<f64> {
        (0..4).map(|r| self.probabilities[0]*self.models[0].x[r]+self.probabilities[1]*self.models[1].x[r]).collect()
    }
}
