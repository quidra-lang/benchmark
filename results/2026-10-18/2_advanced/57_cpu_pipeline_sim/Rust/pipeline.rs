use crate::{trace_io::{Instruction, Variant}, hazards::{self, Source}};

pub const CAUSES: [&str; 4] = ["control", "structural", "load_use", "raw"];

#[derive(Clone, Copy)]
pub struct Timing {
    pub f: usize,
    pub d: usize,
    pub x: usize,
    pub m: usize,
    pub w: usize,
}

pub struct Stall {
    pub cause: usize,
    pub cycles: usize,
    pub responsible: usize,
    pub waiting: Option<usize>,
    pub producer: Option<usize>,
}

pub struct Run {
    pub timing: Vec<Timing>,
    pub stalls: Vec<Stall>,
    pub totals: [usize; 4],
    pub events: [usize; 4],
    pub cycles: usize,
}

pub fn simulate(instructions: &[Instruction], sources: &[Vec<Source>], variant: &Variant, mispredicted: &[bool]) -> Run {
    let mut timing: Vec<Timing> = Vec::new();
    let mut stalls = Vec::new();
    for i in 0..instructions.len() {
        let (f, d, x) = if i == 0 { (1, 2, 3) } else {
            let previous = timing[i - 1];
            let f = if mispredicted[i - 1] { previous.x + usize::from(!hazards::id_resolved(&instructions[i - 1], variant)) } else { previous.d };
            let d = (f + 1).max(previous.x);
            let base = previous.x + 1;
            let mut bounds = [d + 1, previous.m, base, base];
            let mut producers = [None; 4];
            for source in &sources[i] {
                if let Some(p) = source.producer {
                    let cause = if instructions[p].class == 2 { 2 } else { 3 };
                    let ready = hazards::ready(&instructions[i], &instructions[p], &timing[p], variant);
                    if ready > bounds[cause] { bounds[cause] = ready; producers[cause] = Some(p); }
                }
            }
            let mut x = base;
            for cause in 0..4 {
                if bounds[cause] > x {
                    stalls.push(Stall { cause, cycles: bounds[cause] - x, responsible: if cause < 2 { i - 1 } else { i }, waiting: Some(i), producer: producers[cause] });
                    x = bounds[cause];
                }
            }
            (f, d, x)
        };
        let m = x + if instructions[i].class == 1 { variant.multiply } else { 1 };
        timing.push(Timing { f, d, x, m, w: m + 1 });
    }
    let last = instructions.len() - 1;
    if instructions[last].class == 1 && variant.multiply >= 2 { stalls.push(Stall { cause: 1, cycles: variant.multiply - 1, responsible: last, waiting: None, producer: None }); }
    let mut totals = [0; 4];
    let mut events = [0; 4];
    for stall in &stalls { totals[stall.cause] += stall.cycles; events[stall.cause] += 1; }
    let cycles = timing.last().unwrap().w;
    Run { timing, stalls, totals, events, cycles }
}
