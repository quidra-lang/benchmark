use std::collections::BTreeSet;
use crate::{
    Instruction,
    Flags,
    Capture,
    consumes,
    charset
};
#[derive(Clone)]
struct State {
    pc: usize,
    position: usize,
    capture: Capture,
    splits: BTreeSet<usize>
}
pub struct Backtrack<'a> {
    pub steps: usize,
    code: &'a [Instruction],
    subject: &'a [u8],
    flags: Flags,
    groups: usize,
    full: bool
}
impl<'a> Backtrack<'a> {
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
    fn execute(&mut self, pc: usize, position: usize, capture: Capture, partial: bool) -> Result<Option<(Capture, usize)>,
    ()> {
        let mut stack = vec![State {
            pc,
            position,
            capture,
            splits: BTreeSet::new()
        }];
        while let Some(mut state) = stack.pop() {
            loop {
                self.steps += 1;
                if self.steps > 200000 {
                    return Err(());
                }
                let instruction = self.code[state.pc].clone();
                match instruction {
                    Instruction::Char(_) | Instruction::Any | Instruction::Class(_, _) => {
                        if !consumes(&instruction, self.subject, state.position, self.flags) {
                            break;
                        }
                        state.position += 1;
                        state.pc += 1;
                        state.splits.clear();
                    },
                    Instruction::Split(x, y) => {
                        if !state.splits.insert(state.pc) {
                            break;
                        }
                        let mut alternative = state.clone();
                        alternative.pc = y;
                        stack.push(alternative);
                        state.pc = x;
                    },
                    Instruction::Jump(x) => state.pc = x,
                    Instruction::Save(k) => {
                        state.capture[k] = Some(state.position);
                        state.pc += 1;
                    },
                    Instruction::Assert(kind) => {
                        if !charset::assertion(&kind, self.subject, state.position, self.flags) {
                            break;
                        }
                        state.pc += 1;
                    },
                    Instruction::Backref(k) => {
                        let (a, b) = match (state.capture[2 * k], state.capture[2 * k + 1]) {
                            (Some(a), Some(b)) if a <= b => (a, b),
                            _ => break
                        };
                        let length = b - a;
                        if state.position + length > self.subject.len() || !(0..length).all(|j| charset::equal(self.subject[state.position + j], self.subject[a + j], self.flags)) {
                            break;
                        }
                        state.position += length;
                        state.pc += 1;
                        if length > 0 {
                            state.splits.clear();
                        }
                    },
                    Instruction::Look(kind, target) => {
                        let result = self.execute(state.pc + 1, state.position, state.capture.clone(), true)?;
                        match (kind.as_str(), result) {
                            ("NOT", None) => state.pc = target,
                            ("NOT", Some(_)) | (_, None) => break,
                            ("AHEAD", Some((capture, _))) => {
                                state.capture = capture;
                                state.pc = target;
                            },
                            (_, Some((capture, position))) => {
                                state.capture = capture;
                                if position > state.position {
                                    state.splits.clear();
                                }
                                state.position = position;
                                state.pc = target;
                            }
                        }
                    },
                    Instruction::Match => if partial || !self.full || state.position == self.subject.len() {
                        return Ok(Some((state.capture, state.position)));
                    } else {
                        break;
                    }
                }
            }
        }
        Ok(None)
    }
    pub fn search(&mut self, start: usize) -> Result<Option<Capture>,
    ()> {
        let end = if self.full {
            0
        } else {
            self.subject.len()
        };
        let begin = if self.full {
            0
        } else {
            start
        };
        for b in begin..=end {
            if let Some((capture, _)) = self.execute(0, b, vec![None; 2 * self.groups + 2], false)? {
                return Ok(Some(capture));
            }
        }
        Ok(None)
    }
}
