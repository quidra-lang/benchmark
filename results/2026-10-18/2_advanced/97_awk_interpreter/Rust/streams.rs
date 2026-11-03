use std::fs;
#[derive(Clone)]
pub enum Operand {
    Assignment(String, String),
    File(String, usize)
}
pub struct Arguments {
    pub options: Vec<(String, String)>,
    pub operands: Vec<Operand>,
    pub files: Vec<(String, usize)>
}
pub fn valid_name(text: &str) -> bool {
    !text.is_empty() && !text.starts_with('.') && text.bytes().all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
}
fn variable(text: &str) -> bool {
    !text.is_empty() && (text.as_bytes()[0].is_ascii_alphabetic() || text.as_bytes()[0] == b'_') && text.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_')
}
pub fn arguments(text: &str) -> Arguments {
    let mut arguments = Arguments {
        options: Vec::new(),
        operands: Vec::new(),
        files: Vec::new()
    };
    for line in text.lines() {
        if let Some(value) = line.strip_prefix("-F ") {
            arguments.options.push(("FS".into(), value.into()));
        }
        else if let Some(value) = line.strip_prefix("-v ") {
            let (name, value) = value.split_once('=').unwrap();
            arguments.options.push((name.into(), value.into()));
        }
        else if let Some((name, value)) = line.split_once('=').filter(|(name, _)| variable(name)) {
            arguments.operands.push(Operand::Assignment(name.into(), value.into()));
        }
        else {
            let i = arguments.files.len();
            arguments.files.push((line.into(), 0));
            arguments.operands.push(Operand::File(line.into(), i));
        }
    }
    arguments
}
pub struct Output {
    pub name: String,
    pub text: String,
    pub writes: usize,
    pub open: bool
}
pub struct Input {
    pub name: String,
    pub lines: Option<Vec<String>>,
    pub position: usize,
    pub reads: usize,
    pub opened: bool,
    pub open: bool
}
pub struct Streams {
    pub stdout: String,
    pub writes: usize,
    pub outputs: Vec<Output>,
    pub inputs: Vec<Input>
}
pub fn read_file(name: &str) -> Option<Vec<String>> {
    if !valid_name(name) {
        return None;
    }
    fs::read_to_string(format!("input/{}", name)).ok().map(|s| s.lines().map(str::to_string).collect())
}
impl Streams {
    pub fn new() -> Self {
        Self {
            stdout: String::new(),
            writes: 0,
            outputs: Vec::new(),
            inputs: Vec::new()
        }
    }
    pub fn output(&mut self, name: Option<&str>, append: bool, text: &str) {
        if let Some(name) = name {
            let index = match self.outputs.iter().position(|o| o.name == name) {
                Some(i) => i,
                None => {
                    self.outputs.push(Output {
                        name: name.into(),
                        text: String::new(),
                        writes: 0,
                        open: false
                    });
                    self.outputs.len() - 1
                }
            };
            let output = &mut self.outputs[index];
            if !output.open {
                output.open = true;
                if !append {
                    output.text.clear();
                }
            }
            output.text.push_str(text);
            output.writes += 1;
        } else {
            self.stdout.push_str(text);
            self.writes += 1;
        }
    }
    pub fn getline(&mut self, name: &str) -> (i64, Option<String>) {
        let index = match self.inputs.iter().position(|i| i.name == name) {
            Some(i) => i,
            None => {
                self.inputs.push(Input {
                    name: name.into(),
                    lines: None,
                    position: 0,
                    reads: 0,
                    opened: false,
                    open: false
                });
                self.inputs.len() - 1
            }
        };
        let input = &mut self.inputs[index];
        if !input.open {
            input.lines = read_file(name);
            input.position = 0;
            if input.lines.is_some() {
                input.open = true;
                input.opened = true;
            }
        }
        if let Some(lines) = &input.lines {
            if input.position < lines.len() {
                let line = lines[input.position].clone();
                input.position += 1;
                input.reads += 1;
                (1, Some(line))
            } else {
                (0, None)
            }
        } else {
            (-1, None)
        }
    }
    pub fn close(&mut self, name: &str) -> i64 {
        let mut closed = false;
        if let Some(output) = self.outputs.iter_mut().find(|o| o.name == name) {
            closed |= output.open;
            output.open = false;
        }
        if let Some(input) = self.inputs.iter_mut().find(|i| i.name == name) {
            closed |= input.open;
            input.open = false;
        }
        if closed {
            0
        } else {
            -1
        }
    }
    pub fn save(&self) {
        fs::create_dir_all("output").unwrap();
        fs::write("output/stdout.txt", &self.stdout).unwrap();
        for output in &self.outputs {
            fs::write(format!("output/{}", output.name), &output.text).unwrap();
        }
    }
}
