use crate::{trace_io::{Instruction, Variant}, pipeline::Timing};

pub struct Source {
    pub register: usize,
    pub producer: Option<usize>,
}

pub fn dependencies(instructions: &[Instruction]) -> Vec<Vec<Source>> {
    let mut latest = [None; 32];
    let mut sources = Vec::new();
    for (i, instruction) in instructions.iter().enumerate() {
        sources.push([instruction.rs1, instruction.rs2].iter().filter_map(|&r| r.filter(|&r| r > 0))
            .map(|register| Source { register, producer: latest[register] }).collect());
        if let Some(register) = instruction.rd.filter(|&r| r > 0) { latest[register] = Some(i); }
    }
    sources
}

pub fn id_resolved(instruction: &Instruction, variant: &Variant) -> bool {
    instruction.control() && ((instruction.class == 5 && instruction.rs1.is_none()) || variant.id)
}

pub fn ready(consumer: &Instruction, producer: &Instruction, timing: &Timing, variant: &Variant) -> usize {
    if variant.forwarding {
        (if producer.class == 2 { timing.w } else { timing.m }) + usize::from(id_resolved(consumer, variant))
    } else { timing.w + 1 }
}

pub fn forwarding(consumer: &Instruction, producer: &Timing, timing: &Timing, variant: &Variant) -> usize {
    if !variant.forwarding { return 0; }
    let id = id_resolved(consumer, variant);
    let used = if id { timing.x - 1 } else { timing.x };
    if producer.m == used { 1 } else if !id && producer.w == used { 2 } else { 0 }
}
