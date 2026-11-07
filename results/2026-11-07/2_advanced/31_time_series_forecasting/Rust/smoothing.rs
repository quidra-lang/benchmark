use crate::decomposition::total;

#[derive(Clone, Copy)]
pub struct Parameters {
    pub alpha: f64,
    pub beta: f64,
    pub gamma: f64,
    pub phi: f64,
}

#[derive(Clone)]
pub struct State {
    pub level: f64,
    pub slope: f64,
    pub seasonal: Vec<f64>,
}

pub fn recurse(name: &str, values: &[f64], season: usize, parameters: Parameters) -> (Vec<f64>, Vec<State>) {
    let Parameters { alpha, beta, gamma, phi } = parameters;
    let seasonal = name == "hw_add" || name == "hw_mult";
    let mut level;
    let mut slope;
    let mut components = Vec::new();
    if seasonal {
        level = total(values[..season].iter().copied()) / season as f64;
        slope = (total(values[season..2 * season].iter().copied()) / season as f64 - level) / season as f64;
        components = values[..season].iter().map(|&v| if name == "hw_add" { v - level } else { v / level }).collect();
    } else {
        level = values[0];
        slope = if name == "ses" { 0.0 } else { (values[season] - values[0]) / season as f64 };
    }
    let mut states = Vec::new();
    let mut errors = Vec::new();
    for (t, &observed) in values.iter().enumerate() {
        states.push(State { level, slope, seasonal: components.clone() });
        let predicted;
        let next_level;
        let next_slope;
        if name == "ses" {
            predicted = level;
            next_level = alpha * observed + (1.0 - alpha) * level;
            next_slope = slope;
        } else if seasonal {
            let j = t % season;
            let previous = components[j];
            let base = level + slope;
            if name == "hw_add" {
                predicted = base + previous;
                next_level = alpha * (observed - previous) + (1.0 - alpha) * base;
                components[j] = gamma * (observed - base) + (1.0 - gamma) * previous;
            } else {
                predicted = base * previous;
                next_level = alpha * (observed / previous) + (1.0 - alpha) * base;
                components[j] = gamma * (observed / base) + (1.0 - gamma) * previous;
            }
            next_slope = beta * (next_level - level) + (1.0 - beta) * slope;
        } else {
            predicted = level + phi * slope;
            next_level = alpha * observed + (1.0 - alpha) * predicted;
            next_slope = beta * (next_level - level) + (1.0 - beta) * phi * slope;
        }
        errors.push(observed - predicted);
        level = next_level;
        slope = next_slope;
    }
    states.push(State { level, slope, seasonal: components });
    (errors, states)
}

pub fn forecast(name: &str, state: &State, parameters: Parameters, origin: usize, steps: usize, season: usize) -> Vec<f64> {
    if name == "ses" {
        return vec![state.level; steps];
    }
    if name == "holt" || name == "damped" {
        let mut power = parameters.phi;
        let mut accumulated = 0.0;
        let mut result = Vec::new();
        for _ in 0..steps {
            accumulated += power;
            result.push(state.level + accumulated * state.slope);
            power *= parameters.phi;
        }
        return result;
    }
    (1..=steps).map(|step| {
        let component = state.seasonal[(origin + step - 1) % season];
        let base = state.level + step as f64 * state.slope;
        if name == "hw_add" { base + component } else { base * component }
    }).collect()
}
