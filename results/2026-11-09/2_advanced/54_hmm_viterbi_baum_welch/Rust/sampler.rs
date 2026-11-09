use crate::{model_io::{Model, Observation}, inference::ForwardBackward};

pub struct Generator(pub i64);

impl Generator {
    pub fn draw(&mut self, weights: &[f64]) -> usize {
        self.0 = 48271 * self.0 % 2147483647;
        let u = self.0 as f64 / 2147483647.0;
        let sum: f64 = weights.iter().sum();
        let target = u * sum;
        let mut cumulative = 0.0;
        for (i, &weight) in weights.iter().enumerate() {
            cumulative += weight;
            if target < cumulative { return i; }
        }
        weights.len() - 1
    }
}

pub fn synthetic(model: &Model, length: usize, generator: &mut Generator) -> (Observation, Vec<usize>) {
    let mut observation = Vec::new();
    let mut path = Vec::new();
    for position in 0..length {
        let weights = if position == 0 { &model.initial } else { &model.transition[path[position - 1]] };
        let state = generator.draw(weights);
        let symbol = generator.draw(&model.emission[state]);
        path.push(state);
        observation.push(Some(symbol));
    }
    (observation, path)
}

pub fn posterior(model: &Model, fb: &ForwardBackward, generator: &mut Generator) -> Vec<usize> {
    let t = fb.forward.len();
    let mut path = vec![0; t];
    path[t - 1] = generator.draw(&fb.forward[t - 1]);
    for position in (0..t - 1).rev() {
        let next = path[position + 1];
        let weights: Vec<f64> = (0..model.initial.len()).map(|i| fb.forward[position][i] * model.transition[i][next]).collect();
        path[position] = generator.draw(&weights);
    }
    path
}
