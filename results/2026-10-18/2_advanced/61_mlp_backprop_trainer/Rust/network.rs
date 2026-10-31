use crate::layers;

pub struct Layer {
    pub inputs: usize,
    pub units: usize,
    pub kind: String,
    pub weights: usize,
    pub biases: usize,
}

pub struct Network {
    pub name: String,
    pub layers: Vec<Layer>,
    pub initial: Vec<f64>,
    pub weight_indices: Vec<usize>,
}

pub struct Forward {
    pub activations: Vec<Vec<f64>>,
    pub preactivations: Vec<Vec<f64>>,
    pub scores: Vec<f64>,
    pub loss: f64,
    pub delta: Vec<f64>,
}

impl Network {
    pub fn new(name: String) -> Self { Self { name, layers: Vec::new(), initial: Vec::new(), weight_indices: Vec::new() } }

    pub fn add_layer(&mut self, inputs: usize, units: usize, kind: String) {
        let weights = self.layers.last().map_or(0, |l| l.biases+l.units);
        let biases = weights+inputs*units;
        self.weight_indices.extend(weights..biases);
        self.layers.push(Layer { inputs, units, kind, weights, biases });
    }

    pub fn forward(&self, theta: &[f64], input: &[f64], label: usize) -> Forward {
        let mut activations = vec![input.to_vec()];
        let mut preactivations = Vec::new();
        let (mut scores, mut loss, mut delta) = (Vec::new(), 0.0, Vec::new());
        for (l, layer) in self.layers.iter().enumerate() {
            let z: Vec<_> = (0..layer.units).map(|j| layers::preactivation(
                &theta[layer.weights+j*layer.inputs..layer.weights+(j+1)*layer.inputs], &activations[l], theta[layer.biases+j])).collect();
            if l+1 == self.layers.len() {
                (scores, loss, delta) = layers::output(&layer.kind, &z, label);
                activations.push(scores.clone());
            } else {
                activations.push(z.iter().map(|&v| layers::activation(&layer.kind, v)).collect());
            }
            preactivations.push(z);
        }
        Forward { activations, preactivations, scores, loss, delta }
    }

    pub fn gradients(&self, theta: &[f64], forward: &Forward) -> (Vec<f64>, Vec<f64>) {
        let mut deltas = vec![Vec::new(); self.layers.len()];
        let last = deltas.len()-1;
        deltas[last] = forward.delta.clone();
        for l in (0..last).rev() {
            let layer = &self.layers[l];
            let next = &self.layers[l+1];
            deltas[l] = (0..layer.units).map(|j| {
                let c = layers::propagate(&theta[next.weights..next.biases], &deltas[l+1], j, next.inputs);
                c*layers::derivative(&layer.kind, forward.preactivations[l][j], forward.activations[l+1][j])
            }).collect();
        }
        let mut gradient = vec![0.0; theta.len()];
        for (l, layer) in self.layers.iter().enumerate() {
            for j in 0..layer.units {
                for i in 0..layer.inputs { gradient[layer.weights+j*layer.inputs+i] = deltas[l][j]*forward.activations[l][i]; }
                gradient[layer.biases+j] = deltas[l][j];
            }
        }
        let layer = &self.layers[0];
        let input = (0..layer.inputs).map(|i| layers::propagate(&theta[layer.weights..layer.biases], &deltas[0], i, layer.inputs)).collect();
        (gradient, input)
    }

    pub fn classes(&self) -> usize { self.layers.last().unwrap().units }
    pub fn softmax(&self) -> bool { self.layers.last().unwrap().kind == "SOFTMAX" }
}
