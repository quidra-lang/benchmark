use crate::song_parser::Instrument;

pub const T: [i64; 12] = [26163, 27718, 29366, 31113, 32963, 34923, 36999, 39200, 41530, 44000, 46616, 49388];
const S: [i64; 32] = [0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253, 255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24];

pub fn frequency(note: i64) -> i64 {
    let octave = note / 12;
    let base = T[(note % 12) as usize];
    if octave >= 4 { base * (1_i64 << (octave - 4)) } else { base / (1_i64 << (4 - octave)) }
}

pub fn transpose(frequency: i64, semitones: i64) -> i64 {
    (frequency * T[(semitones % 12) as usize] / T[0]) * (1_i64 << (semitones / 12))
}

pub fn oscillation(position: i64, depth: i64, divisor: i64) -> i64 {
    let value = S[(position % 32) as usize] * depth / divisor;
    if position < 32 { value } else { -value }
}

pub fn envelope(instrument: &Instrument, ticks: i64, release: Option<(i64, i64)>) -> i64 {
    let [attack, decay, sustain, duration] = instrument.envelope;
    if let Some((start, value)) = release {
        let elapsed = ticks - start;
        if elapsed < duration { (value * (duration - 1 - elapsed)).div_euclid(duration) } else { 0 }
    } else if ticks < attack { 15 * (ticks + 1) / attack }
    else if ticks < attack + decay { 15 - (15 - sustain) * (ticks - attack + 1) / decay }
    else { sustain }
}

pub fn waveform(instrument: &Instrument, mode: i64, phase: i64, shift: i64) -> i64 {
    match instrument.waveform.as_str() {
        "PULSE" => if phase / 8192 < [1, 2, 4, 6][mode as usize] { 15 } else { 0 },
        "TRIANGLE" => { let j = phase / 2048; if j < 16 { 15 - j } else { j - 16 } }
        "SAW" => phase / 4096,
        "TABLE" => instrument.table[(phase / 2048) as usize],
        "NOISE" => if shift % 2 == 0 { 15 } else { 0 },
        _ => unreachable!(),
    }
}

pub fn clock(shift: i64, mode: i64) -> i64 {
    let bit = (shift & 1) ^ ((shift >> if mode == 0 { 1 } else { 6 }) & 1);
    shift / 2 + bit * 16384
}
