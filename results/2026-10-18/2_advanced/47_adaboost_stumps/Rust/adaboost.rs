use crate::{dataset::Row, stumps::{self, Search, Stump}};

#[derive(Clone)]
pub struct Round {
    pub stump: Stump,
    pub polarity: i32,
    pub error: f64,
    pub alpha: f64,
    pub z: f64,
    pub bound: f64,
    pub weights: Vec<f64>,
    pub loss: f64,
}

pub struct Model {
    pub rounds: Vec<Round>,
    pub stop: String,
    pub cuts: Vec<Vec<f64>>,
}

pub fn discrete(rows: &[Row], maximum: usize, shrinkage: f64, initial: Option<Vec<f64>>) -> Model {
    let search = Search::new(rows);
    let mut weights = initial.unwrap_or_else(|| vec![1.0 / rows.len() as f64; rows.len()]);
    let mut model = Model { rounds: Vec::new(), stop: "completed".into(), cuts: Vec::new() };
    let mut bound = 1.0;
    for _ in 0..maximum {
        let (mut stump, error, polarity) = stumps::discrete(rows, &weights, &search);
        if error >= 0.5 {
            model.stop = "weak".into();
            break;
        }
        let alpha = if error <= 1e-10 { 1.0 } else { shrinkage * (0.5 * ((1.0 - error) / error).ln()) };
        stump.values[0] = -polarity as f64 * alpha;
        stump.values[1] = polarity as f64 * alpha;
        let before = weights.clone();
        for i in 0..rows.len() {
            let decision = if rows[i].values[stump.feature] > stump.thresholds[0] { polarity } else { -polarity };
            weights[i] *= if decision == rows[i].label { (-alpha).exp() } else { alpha.exp() };
        }
        let z: f64 = weights.iter().sum();
        for w in &mut weights { *w /= z; }
        bound *= z;
        model.rounds.push(Round { stump, polarity, error, alpha, z, bound, weights: before, loss: 0.0 });
        if error <= 1e-10 {
            model.stop = "perfect".into();
            break;
        }
    }
    model
}

pub fn samme(rows: &[Row], maximum: usize, classes: usize) -> Model {
    let search = Search::new(rows);
    let mut weights = vec![1.0 / rows.len() as f64; rows.len()];
    let mut model = Model { rounds: Vec::new(), stop: "completed".into(), cuts: Vec::new() };
    for _ in 0..maximum {
        let (stump, error) = stumps::multiclass(rows, &weights, &search, classes);
        if error >= (classes - 1) as f64 / classes as f64 {
            model.stop = "weak".into();
            break;
        }
        let alpha = if error <= 1e-10 { 1.0 } else { ((1.0 - error) / error).ln() + ((classes - 1) as f64).ln() };
        for (row, w) in rows.iter().zip(&mut weights) {
            if row.label != stump.output(&row.values) as i32 { *w *= alpha.exp(); }
        }
        let total: f64 = weights.iter().sum();
        for w in &mut weights { *w /= total; }
        model.rounds.push(Round { stump, error, alpha, polarity: 0, z: 0.0, bound: 0.0, weights: Vec::new(), loss: 0.0 });
        if error <= 1e-10 {
            model.stop = "perfect".into();
            break;
        }
    }
    model
}
