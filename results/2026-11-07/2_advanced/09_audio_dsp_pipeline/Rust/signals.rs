use std::{fs, rc::Rc};

pub struct Signal {
    pub name: String,
    pub rate: i64,
    pub samples: Vec<i64>,
    pub origin: String,
    pub ingredients: Vec<Rc<Signal>>,
}
pub fn floor_div(a: i64, b: i64) -> i64 { let q = a / b; if a % b != 0 && (a < 0) != (b < 0) { q - 1 } else { q } }
pub fn rdiv(a: i64, b: i64) -> i64 { floor_div(2 * a + b, 2 * b) }
pub fn peak(samples: &[i64]) -> i64 { samples.iter().map(|x| x.abs()).max().unwrap() }
#[derive(Default)]
pub struct ClipCounter { pub count: usize }
impl ClipCounter {
    pub fn saturate(&mut self, value: i64) -> i64 { let limited = value.clamp(-32768, 32767); if limited != value { self.count += 1; } limited }
}
pub fn read_signals() -> Vec<Rc<Signal>> {
    let text = fs::read_to_string("input/signals.txt").unwrap(); let mut tokens = text.split_whitespace(); let mut signals = Vec::new();
    while tokens.next().is_some() {
        let name = tokens.next().unwrap().to_owned(); let rate = tokens.next().unwrap().parse().unwrap(); let count: usize = tokens.next().unwrap().parse().unwrap();
        let samples = (0..count).map(|_| tokens.next().unwrap().parse().unwrap()).collect();
        signals.push(Rc::new(Signal { name, rate, samples, origin: "input".to_owned(), ingredients: Vec::new() }));
    } signals
}
pub fn format_signal(signal: &Signal) -> Vec<String> {
    let mut lines = vec![format!("SIGNAL {} {} {}", signal.name, signal.rate, signal.samples.len())];
    lines.extend(signal.samples.chunks(16).map(|chunk| chunk.iter().map(i64::to_string).collect::<Vec<_>>().join(" "))); lines
}
pub fn impulse(count: usize, position: usize, amplitude: i64) -> Vec<i64> { let mut samples = vec![0; count]; samples[position] = amplitude; samples }
pub fn step(count: usize, position: usize, amplitude: i64) -> Vec<i64> { (0..count).map(|i| if i >= position { amplitude } else { 0 }).collect() }
pub fn noise(count: usize, mut seed: i64) -> Vec<i64> {
    (0..count).map(|_| { seed = 48271 * seed % 2147483647; seed % 65536 - 32768 }).collect()
}
