use crate::signals::{rdiv, ClipCounter};

pub fn gain(samples: &[i64], num: i64, den: i64) -> (Vec<i64>, usize) {
    let mut clips = ClipCounter::default(); let output = samples.iter().map(|&x| clips.saturate(rdiv(x * num, den))).collect(); (output, clips.count)
}
pub fn mix(tracks: &[&[i64]], weights: &[i64], den: i64) -> (Vec<i64>, usize) {
    let length = tracks.iter().map(|track| track.len()).max().unwrap(); let mut clips = ClipCounter::default(); let mut output = Vec::new();
    for i in 0..length { let mut total = 0; for (track, &weight) in tracks.iter().zip(weights) { if i < track.len() { total += weight * track[i]; } } output.push(clips.saturate(rdiv(total, den))); }
    (output, clips.count)
}
pub fn delay(samples: &[i64], count: usize) -> Vec<i64> { let mut output = vec![0; count]; output.extend_from_slice(samples); output }
pub fn echo(samples: &[i64], delay: usize, num: i64, den: i64, tail: usize) -> (Vec<i64>, usize) {
    let mut output = samples.to_vec(); output.resize(samples.len() + tail, 0); let mut clips = ClipCounter::default();
    for i in delay..output.len() { output[i] = clips.saturate(output[i] + rdiv(num * output[i - delay], den)); } (output, clips.count)
}
pub fn resampled_length(length: usize, old_rate: i64, new_rate: i64) -> usize { (((length - 1) as i64 * new_rate) / old_rate + 1) as usize }
pub fn resample(samples: &[i64], old_rate: i64, new_rate: i64) -> Vec<i64> {
    let mut output = Vec::new();
    for j in 0..resampled_length(samples.len(), old_rate, new_rate) {
        let position = (j as i64 * old_rate / new_rate) as usize; let fraction = j as i64 * old_rate % new_rate; let mut value = samples[position];
        if fraction > 0 { value += rdiv((samples[position + 1] - value) * fraction, new_rate); } output.push(value);
    } output
}
pub fn fade(samples: &[i64], fade_in: usize, fade_out: usize) -> Vec<i64> {
    let mut output = samples.to_vec(); let length = samples.len();
    for i in 0..fade_in { output[i] = rdiv(output[i] * i as i64, fade_in as i64); }
    for i in length - fade_out..length { output[i] = rdiv(output[i] * (length - 1 - i) as i64, fade_out as i64); } output
}
