use crate::signals::{floor_div, rdiv, ClipCounter};

pub fn fir(samples: &[i64], divisor: i64, taps: &[i64]) -> (Vec<i64>, usize) {
    let mut clips = ClipCounter::default(); let mut output = Vec::new();
    for n in 0..samples.len() { let mut total = 0; for k in 0..taps.len().min(n + 1) { total += taps[k] * samples[n - k]; } output.push(clips.saturate(floor_div(total, divisor))); } (output, clips.count)
}
pub fn biquad(samples: &[i64], sections: &[[i64; 5]]) -> (Vec<i64>, usize) {
    let mut clips = ClipCounter::default(); let mut current = samples.to_vec();
    for &[b0, b1, b2, a1, a2] in sections {
        let mut output = Vec::new(); let (mut u1, mut u2, mut v1, mut v2) = (0, 0, 0, 0);
        for u in current { let v = clips.saturate(floor_div(b0 * u + b1 * u1 + b2 * u2 - a1 * v1 - a2 * v2, 16384)); output.push(v); u2 = u1; u1 = u; v2 = v1; v1 = v; } current = output;
    } (current, clips.count)
}
pub fn moving_average(samples: &[i64], width: usize) -> Vec<i64> {
    let mut output = Vec::new(); let mut total = 0;
    for (n, &x) in samples.iter().enumerate() { total += x; if n >= width { total -= samples[n - width]; } output.push(rdiv(total, width as i64)); } output
}
pub fn dc_block(samples: &[i64], num: i64, den: i64) -> (Vec<i64>, usize) {
    let mut clips = ClipCounter::default(); let mut output = Vec::new(); let mut previous_input = 0; let mut previous_output = 0;
    for &x in samples { previous_output = clips.saturate(x - previous_input + rdiv(num * previous_output, den)); previous_input = x; output.push(previous_output); } (output, clips.count)
}
