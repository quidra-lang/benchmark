use crate::{
    Instruction,
    charset::Set
};
pub fn character(c: u8) -> String {
    if c >= 33 && c <= 126 && !b"\\]^-".contains(&c) {
        (c as char).to_string()
    } else {
        format!("\\x{:02X}", c)
    }
}
pub fn set(set: &Set, negated: bool) -> String {
    let mut text = if negated {
        "[^".to_string()
    } else {
        "[".to_string()
    };
    let values: Vec<u8> = set.iter().copied().collect();
    let mut i = 0;
    while i < values.len() {
        let mut end = i;
        while end + 1 < values.len() && values[end + 1] == values[end] + 1 {
            end += 1;
        }
        text.push_str(&character(values[i]));
        if end > i {
            if end - i >= 2 {
                text.push('-');
            }
            text.push_str(&character(values[end]));
        }
        i = end + 1;
    }
    text.push(']');
    text
}
pub fn instruction(instruction: &Instruction) -> String {
    match instruction {
        Instruction::Char(c) => format!("CHAR {}", character(*c)),
        Instruction::Any => "ANY".into(),
        Instruction::Class(s, n) => format!("CLASS {}", set(s, *n)),
        Instruction::Split(a, b) => format!("SPLIT {}, {}", a, b),
        Instruction::Jump(a) => format!("JMP {}", a),
        Instruction::Save(k) => format!("SAVE {}", k),
        Instruction::Assert(kind) => format!("ASSERT {}", kind),
        Instruction::Backref(k) => format!("BACKREF {}", k),
        Instruction::Look(kind, x) => format!("LOOK {} {}", kind, x),
        Instruction::Match => "MATCH".into()
    }
}
pub fn quote(value: &[u8]) -> String {
    let mut text = String::from("\"");
    for &c in value {
        match c {
            b'\\' => text.push_str("\\\\"),
            b'"' => text.push_str("\\\""),
            10 => text.push_str("\\n"),
            9 => text.push_str("\\t"),
            _ => text.push(c as char)
        }
    }
    text.push('"');
    text
}
