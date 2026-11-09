use crate::{dataset::{Example, Settings}, kernels::Kernel, smo::{self, Model}};

pub struct Models { pub rest: Vec<Model>, pub pairs: Vec<Model> }

pub struct Prediction {
    pub rest_values: Vec<f64>,
    pub pair_values: Vec<f64>,
    pub rest: usize,
    pub one: usize,
    pub votes: [usize; 3],
    pub tie: bool,
}

pub fn train(examples: &[Example], kernel: &Kernel, params: &Settings) -> Models {
    let points: Vec<_> = examples.iter().map(|e| e.point).collect();
    let matrix = kernel.matrix(&points);
    let rest = (1..=3).map(|class| {
        let labels: Vec<_> = examples.iter().map(|e| if e.label == class { 1.0 } else { -1.0 }).collect();
        smo::train(&points, &labels, &matrix, params.multi_c, params)
    }).collect();
    let mut pairs = Vec::new();
    for (a, b) in [(1, 2), (1, 3), (2, 3)] {
        let indices: Vec<_> = examples.iter().enumerate().filter(|(_, e)| e.label == a || e.label == b).map(|(i, _)| i).collect();
        let p: Vec<_> = indices.iter().map(|&i| points[i]).collect();
        let labels: Vec<_> = indices.iter().map(|&i| if examples[i].label == a { 1.0 } else { -1.0 }).collect();
        let q: Vec<Vec<_>> = indices.iter().map(|&i| indices.iter().map(|&j| matrix[i][j]).collect()).collect();
        pairs.push(smo::train(&p, &labels, &q, params.multi_c, params));
    }
    Models { rest, pairs }
}

impl Models {
    pub fn classify(&self, kernel: &Kernel, point: [f64; 2]) -> Prediction {
        let rest_values: Vec<_> = self.rest.iter().map(|m| m.decision(kernel, point)).collect();
        let pair_values: Vec<_> = self.pairs.iter().map(|m| m.decision(kernel, point)).collect();
        let mut rest = 0;
        for c in 1..3 { if rest_values[c] > rest_values[rest] { rest = c; } }
        let mut votes = [0; 3];
        let mut scores = [0.0; 3];
        for (i, (a, b)) in [(0, 1), (0, 2), (1, 2)].iter().copied().enumerate() {
            let h = pair_values[i];
            votes[if h > 0.0 { a } else { b }] += 1;
            scores[a] += h;
            scores[b] -= h;
        }
        let most = *votes.iter().max().unwrap();
        let tie = votes.iter().filter(|&&v| v == most).count() > 1;
        let mut one = (0..3).find(|&c| votes[c] == most).unwrap();
        for c in one+1..3 { if votes[c] == most && scores[c] > scores[one] { one = c; } }
        Prediction { rest_values, pair_values, rest: rest+1, one: one+1, votes, tie }
    }
}
