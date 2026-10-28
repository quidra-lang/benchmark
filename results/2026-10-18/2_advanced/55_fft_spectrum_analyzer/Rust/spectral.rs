use crate::{fft::{self, Complex}, windows};

pub struct Spectrum {
    pub windowed: Vec<f64>,
    pub transform: Vec<Complex>,
    pub amplitude: Vec<f64>,
    pub sum: f64,
}

pub fn amplitude(values: &[f64], window: &[f64]) -> Spectrum {
    let m = window.len();
    let windowed: Vec<f64> = values[..m].iter().zip(window).map(|(x, w)| x * w).collect();
    let transform = fft::real(&windowed);
    let sum: f64 = window.iter().sum();
    let amplitude = (0..=m / 2).map(|k| {
        let coefficient = if k == 0 || 2 * k == m { 1.0 } else { 2.0 };
        coefficient * transform[k].abs() / sum
    }).collect();
    Spectrum { windowed, transform, amplitude, sum }
}

pub fn local_maximum(values: &[f64], k: usize) -> bool {
    k > 0 && k + 1 < values.len() && values[k] > values[k - 1] && values[k] > values[k + 1]
}

pub fn interpolate(values: &[f64], k: usize, logarithmic: bool) -> (f64, f64) {
    if !local_maximum(values, k) { return (k as f64, values[k]); }
    let value = |v: f64| if logarithmic { v.ln() } else { v };
    let alpha = value(values[k - 1]);
    let beta = value(values[k]);
    let gamma = value(values[k + 1]);
    let delta = (alpha - gamma) / (2.0 * (alpha - 2.0 * beta + gamma));
    let height = beta - (alpha - gamma) * delta / 4.0;
    (k as f64 + delta, if logarithmic { height.exp() } else { height })
}

pub fn median(values: &[f64]) -> f64 {
    let mut sorted = values.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let n = sorted.len();
    if n % 2 == 1 { sorted[n / 2] } else { (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0 }
}

fn checked_packing(values: &[f64], error: &mut f64) -> Vec<Complex> {
    let packed = fft::packed(values);
    let reference = fft::real(values);
    for k in 0..packed.len() { *error = (*error).max((packed[k] - reference[k]).abs()); }
    packed
}

pub struct Welch {
    pub count: usize,
    pub psd: Vec<f64>,
    pub coherence: Vec<f64>,
    pub transfer: Vec<Complex>,
    pub packing_error: f64,
}

pub fn welch(x: &[f64], y: &[f64], length: usize, name: &str, rate: usize) -> Welch {
    let window = windows::values(length, name);
    let squared_sum: f64 = window.iter().map(|w| w * w).sum();
    let count = (x.len() - length) / (length / 2) + 1;
    let mut pxx = vec![0.0; length / 2 + 1];
    let mut pyy = pxx.clone();
    let mut pxy = vec![Complex::default(); length / 2 + 1];
    let mut packing_error = 0.0;
    for j in 0..count {
        let start = j * length / 2;
        let first: Vec<f64> = (0..length).map(|i| x[start + i] * window[i]).collect();
        let second: Vec<f64> = (0..length).map(|i| y[start + i] * window[i]).collect();
        let a = checked_packing(&first, &mut packing_error);
        let b = checked_packing(&second, &mut packing_error);
        for k in 0..=length / 2 {
            pxx[k] += a[k].norm2();
            pyy[k] += b[k].norm2();
            pxy[k] = pxy[k] + a[k].conj() * b[k];
        }
    }
    let psd = (0..=length / 2).map(|k| {
        let coefficient = if k == 0 || k == length / 2 { 1.0 } else { 2.0 };
        coefficient * pxx[k] / (count as f64 * rate as f64 * squared_sum)
    }).collect();
    let coherence = (0..=length / 2).map(|k| pxy[k].norm2() / (pxx[k] * pyy[k])).collect();
    let transfer = (0..=length / 2).map(|k| pxy[k] / pxx[k]).collect();
    Welch { count, psd, coherence, transfer, packing_error }
}

pub struct Frames {
    pub magnitude: Vec<Vec<f64>>,
    pub packing_error: f64,
}

pub fn frames(values: &[f64], length: usize, hop: usize, name: &str) -> Frames {
    let window = windows::values(length, name);
    let count = (values.len() - length) / hop + 1;
    let mut packing_error = 0.0;
    let magnitude = (0..count).map(|t| {
        let data: Vec<f64> = (0..length).map(|i| values[t * hop + i] * window[i]).collect();
        checked_packing(&data, &mut packing_error).iter().map(|v| v.abs()).collect()
    }).collect();
    Frames { magnitude, packing_error }
}
