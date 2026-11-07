use crate::instruments::{clock, waveform};
use crate::song_parser::Instrument;
use crate::Channel;
use std::collections::BTreeMap;

pub fn tick(channels: &mut [Channel], instruments: &BTreeMap<i64, Instrument>, count: usize, gain: i64, mute: &[bool], lanes: &mut [Vec<i64>], samples: &mut Vec<i64>) -> usize {
    let mut clipped = 0;
    for _ in 0..count {
        let mut total = 0;
        for (index, channel) in channels.iter_mut().enumerate() {
            let value = if channel.note.is_some() {
                let instrument = &instruments[&channel.instrument.unwrap()];
                let value = (2 * waveform(instrument, channel.mode, channel.phase, channel.shift) - 15) * channel.amplitude;
                channel.phase += channel.increment;
                if channel.phase >= 65536 {
                    channel.phase -= 65536;
                    if instrument.waveform == "NOISE" { channel.shift = clock(channel.shift, channel.mode); }
                }
                value
            } else { 0 };
            lanes[index].push(value);
            if !mute[index] { total += value; }
        }
        let value = 128 + (gain * total).div_euclid(4096);
        if !(0..=255).contains(&value) { clipped += 1; }
        samples.push(value.clamp(0, 255));
    }
    clipped
}

pub fn fade(samples: &mut [i64], duration: usize) {
    let length = samples.len();
    let count = length.min(duration);
    if count == 0 { return; }
    for (i, sample) in samples.iter_mut().enumerate().skip(length - count) {
        *sample = 128 + ((*sample - 128) * (length - 1 - i) as i64).div_euclid(count as i64);
    }
}
