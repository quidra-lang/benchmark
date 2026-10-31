use crate::{model_io::{Model, Observation, normalize}, inference};

pub fn total_loglik(model: &Model, sequences: &[Observation]) -> f64 {
    sequences.iter().map(|s| inference::forward_backward(model, s).loglik).sum()
}

fn from_counts(initial: Vec<f64>, transition: Vec<Vec<f64>>, emission: Vec<Vec<f64>>, smoothing: f64, name: &str) -> Model {
    let finish = |mut values: Vec<f64>| {
        for value in &mut values { *value += smoothing; }
        normalize(&mut values);
        values
    };
    Model { name: name.into(), initial: finish(initial), transition: transition.into_iter().map(&finish).collect(), emission: emission.into_iter().map(&finish).collect() }
}

pub fn baum_step(model: &Model, sequences: &[Observation], smoothing: f64) -> Model {
    let k = model.initial.len();
    let m = model.emission[0].len();
    let mut initial = vec![0.0; k];
    let mut transition = vec![vec![0.0; k]; k];
    let mut emission = vec![vec![0.0; m]; k];
    for sequence in sequences {
        let fb = inference::forward_backward(model, sequence);
        for i in 0..k { initial[i] += fb.gamma[0][i]; }
        for position in 0..sequence.len() {
            for i in 0..k {
                if let Some(c) = sequence[position] { emission[i][c] += fb.gamma[position][i]; }
                if position + 1 < sequence.len() {
                    for j in 0..k {
                        transition[i][j] += fb.forward[position][i] * model.transition[i][j]
                            * inference::emission(model, sequence[position + 1], j) * fb.backward[position + 1][j] / fb.scales[position + 1];
                    }
                }
            }
        }
    }
    from_counts(initial, transition, emission, smoothing, "BAUM_WELCH")
}

pub fn count(pairs: &[(Observation, Vec<usize>)], states: usize, symbols: usize, smoothing: f64, name: &str) -> Model {
    let mut initial = vec![0.0; states];
    let mut transition = vec![vec![0.0; states]; states];
    let mut emission = vec![vec![0.0; symbols]; states];
    for (observation, path) in pairs {
        initial[path[0]] += 1.0;
        for position in 0..path.len() {
            if let Some(c) = observation[position] { emission[path[position]][c] += 1.0; }
            if position + 1 < path.len() { transition[path[position]][path[position + 1]] += 1.0; }
        }
    }
    from_counts(initial, transition, emission, smoothing, name)
}
