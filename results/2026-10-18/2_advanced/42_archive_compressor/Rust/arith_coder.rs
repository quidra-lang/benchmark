use crate::bitio::{DecodeError, Reader, Writer};
use std::collections::BTreeSet;

const HALF: usize = 32768;
const QUARTER: usize = 16384;
const THREE: usize = 49152;

struct Model {
    frequencies: Vec<Vec<usize>>,
    totals: Vec<usize>,
    rescales: usize,
}

impl Model {
    fn new() -> Self { Self { frequencies: vec![vec![1; 257]; 256], totals: vec![257; 256], rescales: 0 } }
    fn update(&mut self, context: usize, symbol: usize) {
        self.frequencies[context][symbol] += 32;
        self.totals[context] += 32;
        if self.totals[context] >= 8192 {
            self.totals[context] = 0;
            for frequency in &mut self.frequencies[context] { *frequency = (*frequency + 1) / 2; self.totals[context] += *frequency; }
            self.rescales += 1;
        }
    }
}

fn output(writer: &mut Writer, bit: usize, follow: &mut usize) {
    writer.write(bit, 1);
    for _ in 0..*follow { writer.write(1 - bit, 1); }
    *follow = 0;
}

pub fn encode(data: &[u8]) -> (Vec<u8>, usize, usize, usize) {
    let mut model = Model::new();
    let mut contexts = BTreeSet::new();
    let mut writer = Writer::default();
    let (mut low, mut high, mut follow, mut context) = (0, 65535, 0, 10);
    for symbol in data.iter().map(|&b| usize::from(b)).chain(std::iter::once(256)) {
        contexts.insert(context);
        let cumulative: usize = model.frequencies[context][..symbol].iter().sum();
        let range = high - low + 1;
        high = low + range * (cumulative + model.frequencies[context][symbol]) / model.totals[context] - 1;
        low += range * cumulative / model.totals[context];
        loop {
            if high < HALF { output(&mut writer, 0, &mut follow); }
            else if low >= HALF { output(&mut writer, 1, &mut follow); low -= HALF; high -= HALF; }
            else if low >= QUARTER && high < THREE { follow += 1; low -= QUARTER; high -= QUARTER; }
            else { break; }
            low *= 2;
            high = 2 * high + 1;
        }
        if symbol != 256 { model.update(context, symbol); context = symbol; }
    }
    follow += 1;
    output(&mut writer, usize::from(low >= QUARTER), &mut follow);
    (writer.bytes(), writer.bits.len(), contexts.len(), model.rescales)
}

pub fn decode(payload: &[u8], original: usize) -> Result<Vec<u8>, DecodeError> {
    let mut reader = Reader::new(payload);
    let mut value = 0;
    for _ in 0..16 { value = value * 2 + reader.zero_bit(); }
    let (mut low, mut high, mut context) = (0, 65535, 10);
    let mut model = Model::new();
    let mut output = Vec::new();
    loop {
        let range = high - low + 1;
        let q = ((value - low + 1) * model.totals[context] - 1) / range;
        let mut cumulative = 0;
        let mut symbol = 0;
        while cumulative + model.frequencies[context][symbol] <= q { cumulative += model.frequencies[context][symbol]; symbol += 1; }
        high = low + range * (cumulative + model.frequencies[context][symbol]) / model.totals[context] - 1;
        low += range * cumulative / model.totals[context];
        loop {
            if high < HALF { }
            else if low >= HALF { low -= HALF; high -= HALF; value -= HALF; }
            else if low >= QUARTER && high < THREE { low -= QUARTER; high -= QUARTER; value -= QUARTER; }
            else { break; }
            low *= 2;
            high = 2 * high + 1;
            value = 2 * value + reader.zero_bit();
        }
        if symbol == 256 {
            if output.len() < original { return Err(DecodeError::new("early_end", output.len())); }
            return Ok(output);
        }
        if output.len() == original { return Err(DecodeError::new("overrun", output.len())); }
        output.push(symbol as u8);
        model.update(context, symbol);
        context = symbol;
    }
}
