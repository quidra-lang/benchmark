use crate::signals::{peak, rdiv};

pub fn envelope(samples: &[i64], attack: i64, release: i64) -> Vec<i64> {
    let mut levels = Vec::new(); let mut level = 0;
    for &x in samples { let magnitude = x.abs().min(32767); let coefficient = if magnitude > level { attack } else { release }; level += rdiv((magnitude - level) * coefficient, 32768); levels.push(level); } levels
}
pub fn normalize(samples: &[i64], target: i64) -> (Vec<i64>, i64) {
    let source_peak = peak(samples); (if source_peak == 0 { samples.to_vec() } else { samples.iter().map(|&x| rdiv(x * target, source_peak)).collect() }, source_peak)
}
pub fn gate(samples: &[i64], threshold: i64, hold: usize) -> (Vec<i64>, usize) {
    let mut output = Vec::new(); let mut muted = 0; let mut last = None;
    for (i, &x) in samples.iter().enumerate() {
        if x.abs() >= threshold { last = Some(i); }
        if last.is_some_and(|last| i - last <= hold) { output.push(x); } else { output.push(0); muted += 1; }
    } (output, muted)
}
pub fn compress(samples: &[i64], threshold: i64, ratio_num: i64, ratio_den: i64, attack: i64, release: i64) -> (Vec<i64>, i64, usize) {
    let levels = envelope(samples, attack, release); let mut output = Vec::new(); let mut gain: i64 = 32768; let mut minimum: i64 = 32768; let mut reduced = 0;
    for (&x, level) in samples.iter().zip(levels) {
        let target = if level > threshold { rdiv((threshold + rdiv((level - threshold) * ratio_den, ratio_num)) * 32768, level) } else { 32768 };
        gain = if target < gain { target } else { gain + rdiv((target - gain) * release, 32768) }; minimum = minimum.min(gain); if gain < 32768 { reduced += 1; } output.push(rdiv(x * gain, 32768));
    } (output, minimum, reduced)
}
