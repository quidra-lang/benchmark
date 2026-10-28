use crate::model_io::{Model, Observation};

pub fn maximum(values: &[f64]) -> usize {
    let mut best = 0;
    for i in 1..values.len() { if values[i] > values[best] { best = i; } }
    best
}

pub fn emission(model: &Model, observation: Option<usize>, state: usize) -> f64 {
    observation.map_or(1.0, |c| model.emission[state][c])
}

pub struct ForwardBackward {
    pub forward: Vec<Vec<f64>>,
    pub backward: Vec<Vec<f64>>,
    pub gamma: Vec<Vec<f64>>,
    pub scales: Vec<f64>,
    pub loglik: f64,
}

pub fn forward_backward(model: &Model, observation: &Observation) -> ForwardBackward {
    let t = observation.len();
    let k = model.initial.len();
    let mut forward = vec![vec![0.0; k]; t];
    let mut scales = vec![0.0; t];
    for position in 0..t {
        for j in 0..k {
            let sum = if position == 0 { model.initial[j] } else { (0..k).map(|i| forward[position - 1][i] * model.transition[i][j]).sum() };
            forward[position][j] = sum * emission(model, observation[position], j);
        }
        scales[position] = forward[position].iter().sum();
        for value in &mut forward[position] { *value /= scales[position]; }
    }
    let mut backward = vec![vec![1.0; k]; t];
    for position in (0..t - 1).rev() {
        for i in 0..k {
            let sum: f64 = (0..k).map(|j| model.transition[i][j] * emission(model, observation[position + 1], j) * backward[position + 1][j]).sum();
            backward[position][i] = sum / scales[position + 1];
        }
    }
    let gamma = (0..t).map(|position| (0..k).map(|i| forward[position][i] * backward[position][i]).collect()).collect();
    let loglik = scales.iter().map(|s| s.ln()).sum();
    ForwardBackward { forward, backward, gamma, scales, loglik }
}

pub struct Viterbi {
    pub path: Vec<usize>,
    pub logprob: f64,
}

pub fn viterbi(model: &Model, observation: &Observation) -> Viterbi {
    let t = observation.len();
    let k = model.initial.len();
    let log_emission = |p: usize, j: usize| observation[p].map_or(0.0, |c| model.emission[j][c].ln());
    let mut delta: Vec<f64> = (0..k).map(|j| model.initial[j].ln() + log_emission(0, j)).collect();
    let mut previous = vec![vec![0; k]; t];
    for position in 1..t {
        let mut next = vec![0.0; k];
        for j in 0..k {
            let values: Vec<f64> = (0..k).map(|i| delta[i] + model.transition[i][j].ln()).collect();
            let best = maximum(&values);
            previous[position][j] = best;
            next[j] = values[best] + log_emission(position, j);
        }
        delta = next;
    }
    let mut path = vec![0; t];
    path[t - 1] = maximum(&delta);
    let logprob = delta[path[t - 1]];
    for position in (1..t).rev() { path[position - 1] = previous[position][path[position]]; }
    Viterbi { path, logprob }
}

pub struct Decoding {
    pub fb: ForwardBackward,
    pub viterbi: Viterbi,
    pub posterior: Vec<usize>,
    pub confidence: Vec<f64>,
}

pub fn decode(model: &Model, observation: &Observation) -> Decoding {
    let fb = forward_backward(model, observation);
    let posterior: Vec<usize> = fb.gamma.iter().map(|g| maximum(g)).collect();
    let confidence = fb.gamma.iter().zip(&posterior).map(|(g, &j)| g[j]).collect();
    Decoding { fb, viterbi: viterbi(model, observation), posterior, confidence }
}
