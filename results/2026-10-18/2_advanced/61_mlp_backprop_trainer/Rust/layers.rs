pub fn activation(kind: &str, z: f64) -> f64 {
    match kind { "TANH" => z.tanh(), "SIGMOID" => 1.0/(1.0+(-z).exp()), _ => if z > 0.0 { z } else { 0.0 } }
}

pub fn derivative(kind: &str, z: f64, a: f64) -> f64 {
    match kind { "TANH" => 1.0-a*a, "SIGMOID" => a*(1.0-a), _ => if z > 0.0 { 1.0 } else { 0.0 } }
}

pub fn preactivation(weights: &[f64], inputs: &[f64], bias: f64) -> f64 {
    let mut sum = 0.0;
    for (&w, &a) in weights.iter().zip(inputs) { sum += w*a; }
    sum+bias
}

pub fn propagate(weights: &[f64], delta: &[f64], input: usize, width: usize) -> f64 {
    let mut sum = 0.0;
    for (k, &d) in delta.iter().enumerate() { sum += weights[k*width+input]*d; }
    sum
}

pub fn output(kind: &str, z: &[f64], label: usize) -> (Vec<f64>, f64, Vec<f64>) {
    if kind == "SOFTMAX" {
        let maximum = z.iter().copied().fold(f64::NEG_INFINITY, f64::max);
        let e: Vec<_> = z.iter().map(|&v| (v-maximum).exp()).collect();
        let sum: f64 = e.iter().sum();
        let scores: Vec<_> = e.iter().map(|v| v/sum).collect();
        let delta = scores.iter().enumerate().map(|(k, &s)| s-if k == label { 1.0 } else { 0.0 }).collect();
        (scores, sum.ln()-(z[label]-maximum), delta)
    } else {
        let scores: Vec<_> = z.iter().map(|&v| activation("SIGMOID", v)).collect();
        let mut loss = 0.0;
        let mut delta = Vec::new();
        for (k, &s) in scores.iter().enumerate() {
            let error = s-if k == label { 1.0 } else { 0.0 };
            loss += error*error;
            delta.push(2.0*error*s*(1.0-s)/z.len() as f64);
        }
        (scores, loss/z.len() as f64, delta)
    }
}
