use crate::models::Model;

pub fn step(model: &Model<'_>, state: &[f64], multiplier: f64) -> Vec<f64> {
    let h = 0.25;
    let k1 = model.rate(state, multiplier);
    let temp: Vec<_> = state.iter().zip(&k1).map(|(a, p)| a+(h/2.0)*p).collect();
    let k2 = model.rate(&temp, multiplier);
    let temp: Vec<_> = state.iter().zip(&k2).map(|(a, q)| a+(h/2.0)*q).collect();
    let k3 = model.rate(&temp, multiplier);
    let temp: Vec<_> = state.iter().zip(&k3).map(|(a, r)| a+h*r).collect();
    let k4 = model.rate(&temp, multiplier);
    (0..state.len()).map(|i| state[i]+(h/6.0)*(((k1[i]+2.0*k2[i])+2.0*k3[i])+k4[i])).collect()
}

pub fn simulate(model: &Model<'_>, initial: &[f64], multipliers: &[f64]) -> Vec<Vec<f64>> {
    let mut state = initial.to_vec();
    let cumulative = model.cumulative();
    let mut result = Vec::new();
    for &multiplier in multipliers {
        for &p in &cumulative { state[p] = 0.0; }
        for _ in 0..4 { state = step(model, &state, multiplier); }
        result.push(state.clone());
    }
    result
}
