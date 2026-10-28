pub struct Signals {
    pub lowpass: Vec<i64>,
    pub bandpass: Vec<i64>,
    pub derivative: Vec<i64>,
    pub squared: Vec<i64>,
    pub integrated: Vec<i64>,
}

fn previous(values: &[i64], index: usize, lag: usize) -> i64 { if index >= lag { values[index - lag] } else { 0 } }

pub fn apply(ecg: &[i64]) -> Signals {
    let n = ecg.len();
    let mut c = vec![0; n];
    let mut lowpass = vec![0; n];
    let mut bandpass = vec![0; n];
    let mut derivative = vec![0; n];
    let mut squared = vec![0; n];
    let mut integrated = vec![0; n];
    let (mut high_sum, mut window) = (0, 0);
    for i in 0..n {
        c[i] = 2 * previous(&c, i, 1) - previous(&c, i, 2) + ecg[i] - 2 * previous(ecg, i, 6) + previous(ecg, i, 12);
        lowpass[i] = c[i].div_euclid(32);
        high_sum += lowpass[i] - previous(&lowpass, i, 32);
        bandpass[i] = previous(&lowpass, i, 16) - high_sum.div_euclid(32);
        derivative[i] = (2 * bandpass[i] + previous(&bandpass, i, 1) - previous(&bandpass, i, 3) - 2 * previous(&bandpass, i, 4)).div_euclid(8);
        squared[i] = derivative[i] * derivative[i];
        window += squared[i] - previous(&squared, i, 30);
        integrated[i] = window / 30;
    }
    Signals { lowpass, bandpass, derivative, squared, integrated }
}
