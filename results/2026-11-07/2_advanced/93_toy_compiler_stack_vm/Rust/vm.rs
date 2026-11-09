use std::collections::BTreeMap;
use crate::codegen::Instruction;
#[derive(Clone)]
pub struct Frame {
    pub locals: Vec<i64>,
    pub return_address: usize
}
pub struct RuntimeError {
    pub message: String,
    pub pc: usize,
    pub frames: Vec<Frame>
}
pub struct Run {
    pub output: Vec<String>,
    pub error: Option<RuntimeError>,
    pub executed: usize,
    pub counts: Vec<usize>,
    pub calls: Vec<usize>,
    pub pairs: BTreeMap<(usize, usize),
    usize>,
    pub max_stack: usize,
    pub max_depth: usize,
}
pub fn run(code: &[Instruction], owners: &[usize], starts: &[usize], global_size: usize, input: &[i64]) -> Run {
    let mut result = Run {
        output: Vec::new(),
        error: None,
        executed: 0,
        counts: vec![0; code.len()],
        calls: vec![0; starts.len()],
        pairs: BTreeMap::new(),
        max_stack: 0,
        max_depth: 0
    };
    let entries: BTreeMap<usize,
    usize> = starts.iter().enumerate().map(|(i, &p)| (p, i)).collect();
    let mut globals = vec![0i64; global_size];
    let mut stack: Vec<i64> = Vec::new();
    let mut frames: Vec<Frame> = Vec::new();
    let mut pc = 0;
    let mut read = 0;
    loop {
        if result.executed == 100000 {
            result.error = Some(RuntimeError {
                message: "instruction limit exceeded".into(),
                pc,
                frames: frames.clone()
            });
            break;
        }
        let instruction = &code[pc];
        result.executed += 1;
        result.counts[pc] += 1;
        let mut next = pc + 1;
        let mut error: Option<String> = None;
        let mut halt = false;
        match instruction.op.as_str() {
            "PUSH" => stack.push(instruction.operands[0]),
            "POP" => {
                stack.pop().unwrap();
            },
            "LOADG" => stack.push(globals[instruction.operands[0] as usize]),
            "STOREG" => globals[instruction.operands[0] as usize] = stack.pop().unwrap(),
            "LOADL" => stack.push(frames.last().unwrap().locals[instruction.operands[0] as usize]),
            "STOREL" => frames.last_mut().unwrap().locals[instruction.operands[0] as usize] = stack.pop().unwrap(),
            "LOADA" | "STOREA" => {
                let store = instruction.op == "STOREA";
                let value = if store {
                    stack.pop().unwrap()
                } else {
                    0
                };
                let index = stack.pop().unwrap();
                let size = instruction.operands[1];
                if index < 0 || index >= size {
                    error = Some(format!("index {} out of bounds for array of size {}", index, size));
                }
                else {
                    let address = (instruction.operands[0] + index) as usize;
                    if store {
                        globals[address] = value;
                    } else {
                        stack.push(globals[address]);
                    }
                }
            },
            "ADD" | "SUB" | "MUL" | "DIV" | "MOD" => {
                let b = stack.pop().unwrap();
                let a = stack.pop().unwrap();
                if (instruction.op == "DIV" || instruction.op == "MOD") && b == 0 {
                    error = Some("division by zero".into());
                }
                else {
                    let value = match instruction.op.as_str() {
                        "ADD" => a + b,
                        "SUB" => a - b,
                        "MUL" => a * b,
                        "DIV" => a / b,
                        _ => a % b
                    };
                    if !(-2147483648..=2147483647).contains(&value) {
                        error = Some("integer overflow".into());
                    } else {
                        stack.push(value);
                    }
                }
            },
            "NEG" => {
                let value = -stack.pop().unwrap();
                if !(-2147483648..=2147483647).contains(&value) {
                    error = Some("integer overflow".into());
                } else {
                    stack.push(value);
                }
            },
            "NOT" => {
                let value = stack.pop().unwrap();
                stack.push(if value == 0 {
                    1
                } else {
                    0
                });
            },
            "LT" | "LE" | "GT" | "GE" | "EQ" | "NE" => {
                let b = stack.pop().unwrap();
                let a = stack.pop().unwrap();
                let value = match instruction.op.as_str() {
                    "LT" => a < b,
                    "LE" => a <= b,
                    "GT" => a > b,
                    "GE" => a >= b,
                    "EQ" => a == b,
                    _ => a != b
                };
                stack.push(if value {
                    1
                } else {
                    0
                });
            },
            "JUMP" => next = instruction.operands[0] as usize,
            "JUMPF" | "JUMPT" => {
                let value = stack.pop().unwrap();
                if (instruction.op == "JUMPF" && value == 0) || (instruction.op == "JUMPT" && value != 0) {
                    next = instruction.operands[0] as usize;
                }
            },
            "CALL" => {
                if frames.len() == 100 {
                    error = Some("call depth limit exceeded".into());
                }
                else {
                    let n = instruction.operands[1] as usize;
                    let locals = stack.split_off(stack.len() - n);
                    frames.push(Frame {
                        locals,
                        return_address: next
                    });
                    next = instruction.operands[0] as usize;
                    let callee = entries[&next];
                    result.calls[callee] += 1;
                    *result.pairs.entry((owners[pc], callee)).or_insert(0) += 1;
                }
            },
            "ENTER" => frames.last_mut().unwrap().locals.resize(instruction.operands[0] as usize, 0),
            "RET" | "RETV" => next = frames.pop().unwrap().return_address,
            "READ" => {
                if read == input.len() {
                    error = Some("read past end of input".into());
                }
                else {
                    stack.push(input[read]);
                    read += 1;
                }
            },
            "PRINT" => {
                let n = instruction.operands[0] as usize;
                let values = stack.split_off(stack.len() - n);
                result.output.push(values.iter().map(ToString::to_string).collect::<Vec<_>>().join(" "));
            },
            "HALT" => halt = true,
            _ => unreachable!()
        }
        if let Some(message) = error {
            result.error = Some(RuntimeError {
                message,
                pc,
                frames: frames.clone()
            });
            break;
        }
        result.max_stack = result.max_stack.max(stack.len());
        result.max_depth = result.max_depth.max(frames.len());
        if halt {
            break;
        }
        pc = next;
    }
    result
}
