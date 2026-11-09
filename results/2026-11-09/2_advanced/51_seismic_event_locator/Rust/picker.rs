use crate::{waveform_io::{Waveform, Params}, magnitude};

pub struct Pick {
    pub station: usize,
    pub sample: i64,
    pub duration: usize,
    pub ratio: f64,
    pub amplitude: i64,
    pub clipped: bool,
}

pub struct Statistics {
    pub mean: i64,
    pub noise: f64,
    pub peak: i64,
    pub clipped: usize,
    pub triggers: usize,
    pub short: usize,
    pub picks: usize,
}

pub fn detect(station: usize, wave: &Waveform, params: &Params) -> (Vec<Pick>, Statistics) {
    let n = wave.samples.len();
    let mean = wave.samples.iter().sum::<i64>().div_euclid(n as i64);
    let differences: Vec<i64> = wave.samples.iter().map(|s| s - mean).collect();
    let energy: Vec<i64> = differences.iter().map(|d| d * d).collect();
    let mut prefix = vec![0];
    for &e in &energy { prefix.push(prefix.last().unwrap() + e); }
    let mut starts = Vec::new();
    let mut on = None;
    for i in params.sta + params.lta - 1..n {
        let sta = prefix[i + 1] - prefix[i + 1 - params.sta];
        let lta = prefix[i + 1 - params.sta] - prefix[i + 1 - params.sta - params.lta];
        if let Some(start) = on {
            if sta * params.lta as i64 * params.off.1 < params.off.0 * lta * params.sta as i64 {
                starts.push((start, i));
                on = None;
            }
        } else if sta * params.lta as i64 * params.on.1 >= params.on.0 * lta * params.sta as i64 { on = Some(i); }
    }
    if let Some(start) = on { starts.push((start, n)); }
    let mut picks = Vec::new();
    let mut short = 0;
    for &(start, end) in &starts {
        if end - start < params.duration { short += 1; continue; }
        let mut ratio: f64 = 0.0;
        for i in start..end {
            let sta = prefix[i + 1] - prefix[i + 1 - params.sta];
            let lta = prefix[i + 1 - params.sta] - prefix[i + 1 - params.sta - params.lta];
            ratio = ratio.max((sta * params.lta as i64) as f64 / (lta * params.sta as i64) as f64);
        }
        let mut k = start;
        while k > start + 1 - params.sta && energy[k - 1] >= params.noise { k -= 1; }
        let stop = (k + params.amplitude).min(n);
        let amplitude = differences[k..stop].iter().map(|d| d.abs()).max().unwrap();
        let clipped = wave.samples[k..stop].iter().any(|s| s.abs() >= params.clip);
        picks.push(Pick { station, sample: wave.start + k as i64, duration: end - start, ratio, amplitude, clipped });
    }
    let stats = Statistics {
        mean, noise: magnitude::median(&differences.iter().map(|d| d.abs() as f64).collect::<Vec<_>>()),
        peak: differences.iter().map(|d| d.abs()).max().unwrap(), clipped: wave.samples.iter().filter(|s| s.abs() >= params.clip).count(),
        triggers: starts.len(), short, picks: picks.len(),
    };
    (picks, stats)
}
