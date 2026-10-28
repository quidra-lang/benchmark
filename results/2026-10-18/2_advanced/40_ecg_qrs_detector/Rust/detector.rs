use crate::filters::Signals;

pub struct Peak {
    pub time: usize,
    pub r: usize,
    pub integrated: i64,
    pub filtered: i64,
    pub slope: i64,
    pub threshold_i: i64,
    pub threshold_f: i64,
    pub class: &'static str,
}

pub fn peaks(signals: &Signals) -> Vec<Peak> {
    let mut peaks = Vec::new();
    let n = signals.integrated.len();
    for time in 0..n {
        let value = signals.integrated[time];
        if value <= 0 || signals.integrated[time.saturating_sub(20)..time].iter().any(|&v| v >= value) || signals.integrated[time + 1..(time + 21).min(n)].iter().any(|&v| v > value) { continue; }
        let mut r = time.saturating_sub(30);
        for i in time.saturating_sub(30)..=time { if signals.bandpass[i].abs() > signals.bandpass[r].abs() { r = i; } }
        peaks.push(Peak { time, r, integrated: value, filtered: signals.bandpass[r].abs(), slope: signals.derivative[time.saturating_sub(29)..=time].iter().map(|v| v.abs()).max().unwrap(), threshold_i: 0, threshold_f: 0, class: "unprocessed" });
    }
    peaks
}

pub fn initial(signals: &Signals) -> [i64; 4] {
    [*signals.integrated[..400].iter().max().unwrap() / 3, signals.integrated[..400].iter().sum::<i64>() / 800,
        signals.bandpass[..400].iter().map(|v| v.abs()).max().unwrap() / 3, signals.bandpass[..400].iter().map(|v| v.abs()).sum::<i64>() / 800]
}

pub fn width(signals: &Signals, peak: &Peak) -> i64 {
    let positions: Vec<_> = (peak.r.saturating_sub(25)..=(peak.r + 25).min(signals.bandpass.len() - 1)).filter(|&i| 4 * signals.bandpass[i].abs() >= peak.filtered).collect();
    5 * (positions.last().unwrap() - positions[0] + 1) as i64
}
