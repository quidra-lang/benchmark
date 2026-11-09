use std::collections::BTreeMap;
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum Operand {
    Constant(i64),
    Variable(String)
}
impl Operand {
    pub fn parse(text: &str) -> Self {
        if text.starts_with('-') || text.as_bytes()[0].is_ascii_digit() {
            Self::Constant(text.parse().unwrap())
        } else {
            Self::Variable(text.into())
        }
    }
    pub fn text(&self) -> String {
        match self {
            Self::Constant(n) => n.to_string(),
            Self::Variable(s) => s.clone()
        }
    }
    pub fn variable(&self) -> Option<&str> {
        if let Self::Variable(s) = self {
            Some(s)
        } else {
            None
        }
    }
    pub fn constant(&self) -> Option<i64> {
        if let Self::Constant(n) = self {
            Some(*n)
        } else {
            None
        }
    }
}
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Expression {
    pub kind: &'static str,
    pub operation: String,
    pub a: Operand,
    pub b: Option<Operand>
}
impl Expression {
    pub fn text(&self) -> String {
        if self.kind == "load" {
            format!("{}[{}]", self.operation, self.a.text())
        } else {
            format!("{}{}{}", self.a.text(), self.operation, self.b.as_ref().unwrap().text())
        }
    }
    pub fn uses(&self, name: &str) -> bool {
        self.a.variable() == Some(name) || self.b.as_ref().and_then(Operand::variable) == Some(name)
    }
}
#[derive(Clone)]
pub struct Instruction {
    pub kind: &'static str,
    pub destination: Option<String>,
    pub a: Option<Operand>,
    pub b: Option<Operand>,
    pub operation: String,
    pub target: String,
    pub array: String,
    pub function: String,
    pub count: usize
}
impl Instruction {
    pub fn new(kind: &'static str) -> Self {
        Self {
            kind,
            destination: None,
            a: None,
            b: None,
            operation: String::new(),
            target: String::new(),
            array: String::new(),
            function: String::new(),
            count: 0
        }
    }
    pub fn copy(destination: String, a: Operand) -> Self {
        let mut instruction = Self::new("copy");
        instruction.destination = Some(destination);
        instruction.a = Some(a);
        instruction
    }
    pub fn operands(&self) -> Vec<&Operand> {
        self.a.iter().chain(self.b.iter()).collect()
    }
    pub fn operands_mut(&mut self) -> Vec<&mut Operand> {
        self.a.iter_mut().chain(self.b.iter_mut()).collect()
    }
    pub fn used(&self) -> Vec<String> {
        self.operands().into_iter().filter_map(|o| o.variable().map(str::to_string)).collect()
    }
    pub fn expression(&self) -> Option<Expression> {
        if self.kind == "bin" || self.kind == "load" {
            Some(Expression {
                kind: self.kind,
                operation: if self.kind == "bin" {
                    self.operation.clone()
                } else {
                    self.array.clone()
                },
                a: self.a.clone().unwrap(),
                b: self.b.clone()
            })
        } else {
            None
        }
    }
    pub fn text(&self) -> String {
        let a = self.a.as_ref().map(Operand::text).unwrap_or_default();
        let b = self.b.as_ref().map(Operand::text).unwrap_or_default();
        let destination = self.destination.as_deref().unwrap_or("");
        match self.kind {
            "copy" => format!("{} = {}", destination, a),
            "bin" => format!("{} = {} {} {}", destination, a, self.operation, b),
            "load" => format!("{} = {}[{}]", destination, self.array, a),
            "store" => format!("{}[{}] = {}", self.array, a, b),
            "goto" => format!("goto {}", self.target),
            "if" => format!("if {} {} {} goto {}", a, self.operation, b, self.target),
            "param" | "print" => format!("{} {}", self.kind, a),
            "read" => format!("read {}", destination),
            "return" => if self.a.is_some() {
                format!("return {}", a)
            } else {
                "return".into()
            },
            "call" => format!("{}call {} {}", if self.destination.is_some() {
                format!("{} = ", destination)
            } else {
                String::new()
            }, self.function, self.count),
            _ => unreachable!()
        }
    }
}
#[derive(Clone)]
pub enum Line {
    Label(String),
    Instruction(Instruction)
}
#[derive(Clone)]
pub struct Function {
    pub name: String,
    pub parameters: Vec<String>,
    pub code: Vec<Line>,
    pub temporary: usize,
    pub preheader: usize
}
impl Function {
    pub fn instructions(&self) -> Vec<Instruction> {
        self.code.iter().filter_map(|l| if let Line::Instruction(i) = l {
            Some(i.clone())
        } else {
            None
        }).collect()
    }
    pub fn text(&self) -> Vec<String> {
        let mut lines = vec![format!("func {}{}", self.name, self.parameters.iter().map(|p| format!(" {}", p)).collect::<Vec<_>>().join(""))];
        for line in &self.code {
            lines.push(match line {
                Line::Label(label) => format!("{}:", label),
                Line::Instruction(i) => format!("    {}", i.text())
            });
        }
        lines.push("end".into());
        lines
    }
}
#[derive(Clone)]
pub struct Program {
    pub arrays: Vec<(String, usize)>,
    pub functions: Vec<Function>
}
impl Program {
    pub fn text(&self) -> Vec<String> {
        let mut lines: Vec<String> = self.arrays.iter().map(|(a, n)| format!("array {} {}", a, n)).collect();
        for function in &self.functions {
            if !lines.is_empty() {
                lines.push(String::new());
            }
            lines.extend(function.text());
        }
        lines
    }
}
fn indexed(text: &str) -> (String, Operand) {
    let open = text.find('[').unwrap();
    (text[..open].into(), Operand::parse(&text[open + 1..text.len() - 1]))
}
pub fn parse(text: &str) -> Program {
    let mut program = Program {
        arrays: Vec::new(),
        functions: Vec::new()
    };
    for line in text.lines() {
        let words: Vec<&str> = line.split_whitespace().collect();
        if words.is_empty() || words[0].starts_with('#') {
            continue;
        }
        if words[0] == "array" {
            program.arrays.push((words[1].into(), words[2].parse().unwrap()));
            continue;
        }
        if words[0] == "func" {
            program.functions.push(Function {
                name: words[1].into(),
                parameters: words[2..].iter().map(|s| s.to_string()).collect(),
                code: Vec::new(),
                temporary: 0,
                preheader: 0
            });
            continue;
        }
        if words[0] == "end" {
            continue;
        }
        let function = program.functions.last_mut().unwrap();
        if words.len() == 1 && words[0].ends_with(':') {
            function.code.push(Line::Label(words[0][..words[0].len() - 1].into()));
            continue;
        }
        let mut instruction = Instruction::new("copy");
        match words[0] {
            "goto" => {
                instruction.kind = "goto";
                instruction.target = words[1].into();
            },
            "if" => {
                instruction.kind = "if";
                instruction.a = Some(Operand::parse(words[1]));
                instruction.operation = words[2].into();
                instruction.b = Some(Operand::parse(words[3]));
                instruction.target = words[5].into();
            },
            "param" | "return" | "read" | "print" => {
                instruction.kind = match words[0] {
                    "param" => "param",
                    "return" => "return",
                    "read" => "read",
                    _ => "print"
                };
                if words.len() > 1 {
                    if instruction.kind == "read" {
                        instruction.destination = Some(words[1].into());
                    } else {
                        instruction.a = Some(Operand::parse(words[1]));
                    }
                }
            },
            _ => {
                if words[0].contains('[') {
                    instruction.kind = "store";
                    let (array, index) = indexed(words[0]);
                    instruction.array = array;
                    instruction.a = Some(index);
                    instruction.b = Some(Operand::parse(words[2]));
                }
                else {
                    let start = if words[0] == "call" {
                        0
                    } else {
                        instruction.destination = Some(words[0].into());
                        2
                    };
                    if words[start] == "call" {
                        instruction.kind = "call";
                        instruction.function = words[start + 1].into();
                        instruction.count = words[start + 2].parse().unwrap();
                    }
                    else if words.len() == 5 {
                        instruction.kind = "bin";
                        instruction.a = Some(Operand::parse(words[2]));
                        instruction.operation = words[3].into();
                        instruction.b = Some(Operand::parse(words[4]));
                    }
                    else if words[2].contains('[') {
                        instruction.kind = "load";
                        let (array, index) = indexed(words[2]);
                        instruction.array = array;
                        instruction.a = Some(index);
                    }
                    else {
                        instruction.a = Some(Operand::parse(words[2]));
                    }
                }
            }
        }
        function.code.push(Line::Instruction(instruction));
    }
    program
}
pub fn operation(op: &str, a: i64, b: i64) -> i64 {
    match op {
        "+" => a + b,
        "-" => a - b,
        "*" => a * b,
        "/" => a / b,
        "%" => a % b,
        "<" => if a < b {
            1
        } else {
            0
        },
        "<=" => if a <= b {
            1
        } else {
            0
        },
        ">" => if a > b {
            1
        } else {
            0
        },
        ">=" => if a >= b {
            1
        } else {
            0
        },
        "==" => if a == b {
            1
        } else {
            0
        },
        "!=" => if a != b {
            1
        } else {
            0
        },
        _ => unreachable!()
    }
}
pub fn labels(function: &Function) -> BTreeMap<String, usize> {
    let mut labels = BTreeMap::new();
    let mut index = 0;
    for line in &function.code {
        match line {
            Line::Label(label) => {
                labels.insert(label.clone(), index);
            },
            Line::Instruction(_) => index += 1
        }
    }
    labels
}
