use crate::harmonic_fit::{self, Fit};

pub fn level(fit: &Fit, time: f64) -> f64 {
    let mut level = fit.coefficients[0];
    for (k, &speed) in fit.speeds.iter().enumerate() {
        let theta = harmonic_fit::angle(speed, time);
        level += fit.coefficients[2*k+1]*theta.cos()+fit.coefficients[2*k+2]*theta.sin();
    }
    level
}

pub struct Extremum { pub minute: f64, pub rounded: i64, pub height: f64, pub high: bool, pub label: String }

pub fn extrema(fit: &Fit, start: i64, duration: i64, grid: i64) -> Vec<Extremum> {
    let count = duration*60/grid;
    let values: Vec<_> = (0..=count).map(|j| level(fit, (60*start+j*grid) as f64/60.0)).collect();
    let mut result = Vec::new();
    for j in 1..count as usize {
        let high = values[j-1] < values[j] && values[j] > values[j+1];
        let low = values[j-1] > values[j] && values[j] < values[j+1];
        if !high && !low { continue; }
        let delta = (values[j-1]-values[j+1])/(2.0*(values[j-1]-2.0*values[j]+values[j+1]));
        let minute = (60*start+j as i64*grid) as f64+delta*grid as f64;
        let height = values[j]-(values[j-1]-values[j+1])*delta/4.0;
        result.push(Extremum { minute, rounded: (minute+0.5).floor() as i64, height, high, label: String::new() });
    }
    result
}
