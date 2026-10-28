use crate::fft::{self, Complex, PI};

pub const NAMES: [&str; 5] = ["rectangular", "hann", "hamming", "blackman", "flattop"];

pub fn values(length: usize, name: &str) -> Vec<f64> {
    let coefficients: &[f64] = match name {
        "rectangular" => &[1.0],
        "hann" => &[0.5, 0.5],
        "hamming" => &[0.54, 0.46],
        "blackman" => &[0.42, 0.5, 0.08],
        "flattop" => &[0.21557895, 0.41663158, 0.277263158, 0.083578947, 0.006947368],
        _ => unreachable!(),
    };
    (0..length).map(|n| coefficients.iter().enumerate().map(|(j, &a)| {
        let value = a * (2.0 * PI * j as f64 * n as f64 / length as f64).cos();
        if j % 2 == 0 { value } else { -value }
    }).sum()).collect()
}

pub struct Figures {
    pub sum: f64,
    pub squared_sum: f64,
    pub gain: f64,
    pub enbw_bins: f64,
    pub enbw_hz: f64,
    pub scalloping: f64,
}

pub fn figures(window: &[f64], rate: usize) -> Figures {
    let length = window.len() as f64;
    let sum: f64 = window.iter().sum();
    let squared_sum: f64 = window.iter().map(|w| w * w).sum();
    let enbw_bins = length * squared_sum / (sum * sum);
    let mut value = Complex::default();
    for (n, &w) in window.iter().enumerate() { value = value + fft::rot(PI * n as f64 / length).scale(w); }
    Figures { sum, squared_sum, gain: sum / length, enbw_bins, enbw_hz: enbw_bins * rate as f64 / length,
        scalloping: -20.0 * (value.abs() / sum).log10() }
}
