use crate::signals::peak;

pub fn energy(samples: &[i64]) -> i64 { samples.iter().map(|&x| x * x).sum() }
pub fn isqrt(n: i64) -> i64 {
    let mut low = 0; let mut high = n + 1;
    while high - low > 1 { let middle = (low + high) / 2; if middle <= n / middle { low = middle; } else { high = middle; } } low
}
pub fn rms(samples: &[i64]) -> i64 { isqrt(energy(samples) / samples.len() as i64) }
pub fn zero_crossings(samples: &[i64]) -> usize { samples.windows(2).filter(|pair| (pair[0] < 0) != (pair[1] < 0)).count() }
pub fn clipped(samples: &[i64]) -> usize { samples.iter().filter(|&&x| x == -32768 || x == 32767).count() }
pub fn crest(samples: &[i64]) -> String {
    let denominator = energy(samples); if denominator == 0 { return "none".to_owned(); } let p = peak(samples); let numerator = p * p * samples.len() as i64;
    let mut a = numerator; let mut b = denominator; while b != 0 { let next = a % b; a = b; b = next; } format!("{}/{}", numerator / a, denominator / a)
}
pub fn autocorrelation(samples: &[i64], lag: usize) -> i64 { samples.iter().zip(&samples[lag..]).map(|(&a, &b)| a * b).sum() }
pub fn pitch_lag(samples: &[i64], low: usize, high: usize) -> Option<usize> {
    let mut best_lag = low; let mut best_value = autocorrelation(samples, low);
    for lag in low + 1..=high { let value = autocorrelation(samples, lag); if value > best_value { best_lag = lag; best_value = value; } } (best_value > 0).then_some(best_lag)
}
