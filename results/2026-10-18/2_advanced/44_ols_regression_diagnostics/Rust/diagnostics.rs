use crate::dataframe::Input;
use crate::inference::chi_probability;
use crate::qr_solver::{fit, sum, Fit, Matrix};

pub struct Diagnostics {
    pub standardized: Vec<f64>,
    pub studentized: Vec<f64>,
    pub cooks: Vec<f64>,
    pub dffits: Vec<f64>,
    pub flags: Vec<String>,
    pub dfbetas: Matrix,
    pub durbin_watson: f64,
    pub bp: f64,
    pub bp_degrees: usize,
    pub bp_probability: f64,
    pub jb: f64,
    pub jb_probability: f64,
    pub skewness: f64,
    pub kurtosis: f64,
}

pub fn calculate(input: &Input, model: &Fit, x: &Matrix, sigma: f64, degrees: usize) -> Diagnostics {
    let n = x.len();
    let rank = model.accepted.len();
    let standardized: Vec<_> = (0..n).map(|i| model.weighted_residuals[i] / (sigma * (1.0 - model.leverage[i]).sqrt())).collect();
    let studentized: Vec<_> = standardized.iter().map(|&z| z * ((degrees - 1) as f64 / (degrees as f64 - z * z)).sqrt()).collect();
    let cooks: Vec<_> = (0..n).map(|i| standardized[i] * standardized[i] * model.leverage[i] / (rank as f64 * (1.0 - model.leverage[i]))).collect();
    let dffits: Vec<_> = (0..n).map(|i| studentized[i] * (model.leverage[i] / (1.0 - model.leverage[i])).sqrt()).collect();
    let flags = (0..n).map(|i| {
        let mut flags = String::new();
        if model.leverage[i] > input.number("LEVERAGE") * rank as f64 / n as f64 { flags.push('H'); }
        if studentized[i].abs() > input.number("STUDENTIZED") { flags.push('O'); }
        if cooks[i] > input.number("COOK") / n as f64 { flags.push('C'); }
        if dffits[i].abs() > input.number("DFFITS") * (rank as f64 / n as f64).sqrt() { flags.push('F'); }
        if flags.is_empty() { flags.push('-'); }
        flags
    }).collect();
    let dfbetas = (0..n).map(|i| {
        let deleted_sigma = sigma * ((degrees as f64 - standardized[i] * standardized[i]) / (degrees - 1) as f64).sqrt();
        (0..rank).map(|k| model.g[i][k] * model.weighted_residuals[i] / (1.0 - model.leverage[i]) / (deleted_sigma * model.variance_factors[k].sqrt())).collect()
    }).collect();
    let durbin_watson = sum(model.weighted_residuals.windows(2).map(|pair| { let d = pair[1] - pair[0]; d * d })) / model.rss;
    let auxiliary: Matrix = x.iter().map(|row| model.accepted.iter().map(|&column| row[column]).collect()).collect();
    let squared: Vec<_> = model.weighted_residuals.iter().map(|e| e * e).collect();
    let bp_fit = fit(&auxiliary, &squared, &vec![1.0; n], input.number("RANK_TOL"));
    let mean = sum(squared.iter().copied()) / n as f64;
    let tss = sum(squared.iter().map(|&value| (value - mean) * (value - mean)));
    let bp = n as f64 * (1.0 - bp_fit.rss / tss);
    let bp_degrees = bp_fit.accepted.len() - 1;
    let bp_probability = chi_probability(bp, bp_degrees);
    let mean = sum(model.weighted_residuals.iter().copied()) / n as f64;
    let centered: Vec<_> = model.weighted_residuals.iter().map(|&e| e - mean).collect();
    let m2 = sum(centered.iter().map(|&d| d * d)) / n as f64;
    let m3 = sum(centered.iter().map(|&d| d * d * d)) / n as f64;
    let m4 = sum(centered.iter().map(|&d| d * d * d * d)) / n as f64;
    let skewness = m3 / (m2 * m2.sqrt());
    let kurtosis = m4 / (m2 * m2);
    let jb = n as f64 / 6.0 * (skewness * skewness + (kurtosis - 3.0) * (kurtosis - 3.0) / 4.0);
    Diagnostics { standardized, studentized, cooks, dffits, flags, dfbetas, durbin_watson, bp, bp_degrees, bp_probability, jb, jb_probability: chi_probability(jb, 2), skewness, kurtosis }
}
