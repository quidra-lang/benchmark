use std::collections::BTreeSet;
use crate::{
    Instruction,
    Flags,
    Capture,
    consumes,
    charset
};
struct Threads {
    sequence: Vec<(usize, Capture)>,
    marks: BTreeSet<usize>
}
impl Threads {
    fn new() -> Self {
        Self {
            sequence: Vec::new(),
            marks: BTreeSet::new()
        }
    }
}
pub struct Pike<'a> {
    pub steps: usize,
    code: &'a [Instruction],
    subject: &'a [u8],
    flags: Flags,
    groups: usize,
    full: bool
}
impl<'a> Pike<'a> {
    pub fn new(code: &'a [Instruction], subject: &'a [u8], flags: Flags, groups: usize, full: bool) -> Self {
        Self {
            steps: 0,
            code,
            subject,
            flags,
            groups,
            full
        }
    }
    fn add(&mut self, list: &mut Threads, pc: usize, mut capture: Capture, position: usize) {
        if !list.marks.insert(pc) {
            return;
        }
        self.steps += 1;
        match self.code[pc].clone() {
            Instruction::Jump(x) => self.add(list, x, capture, position),
            Instruction::Split(x, y) => {
                self.add(list, x, capture.clone(), position);
                self.add(list, y, capture, position);
            },
            Instruction::Save(k) => {
                capture[k] = Some(position);
                self.add(list, pc + 1, capture, position);
            },
            Instruction::Assert(kind) => if charset::assertion(&kind, self.subject, position, self.flags) {
                self.add(list, pc + 1, capture, position);
            },
            _ => list.sequence.push((pc, capture))
        }
    }
    pub fn search(&mut self, start: usize) -> Option<Capture> {
        let mut matched = None;
        let mut list = Threads::new();
        let mut position = start;
        loop {
            if matched.is_none() && (!self.full || position == start) {
                self.add(&mut list, 0, vec![None; 2 * self.groups + 2], position);
            }
            let mut next = Threads::new();
            for (pc, capture) in list.sequence {
                self.steps += 1;
                if matches!(self.code[pc], Instruction::Match) {
                    if !self.full || position == self.subject.len() {
                        matched = Some(capture);
                        break;
                    }
                } else if consumes(&self.code[pc], self.subject, position, self.flags) {
                    self.add(&mut next, pc + 1, capture, position + 1);
                }
            }
            if position == self.subject.len() || (next.sequence.is_empty() && (matched.is_some() || self.full)) {
                break;
            }
            list = next;
            position += 1;
        }
        matched
    }
}
