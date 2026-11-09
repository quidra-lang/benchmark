use std::{
    fs, io
};
pub const NAMES: [&str; 7] = ["ALLOC", "PUSH", "LOAD", "POP", "SET", "OVERWRITE", "CHECKPOINT"];
#[derive(Clone)]
pub struct Collector {
    pub name: String,
    pub algorithm: String,
    pub young: usize,
    pub age: usize
}
pub struct Config {
    pub size: usize,
    pub collectors: Vec<Collector>,
    pub maps: Vec<String>,
    pub windows: Vec<usize>,
    pub width: usize
}
pub fn read_config() -> io::Result<Config> {
    let mut c = Config {
        size: 0,
        collectors: vec![],
        maps: vec![],
        windows: vec![],
        width: 0
    };
    for l in fs::read_to_string("input/config.txt")?.lines() {
        let p = l.split(' ').collect::<Vec<_>>();
        match p[0] {
            "HEAP" => c.size = p[1].parse().unwrap(), "COLLECTOR" => c.collectors.push(Collector {
                name: p[1].into(),
                algorithm: p[2].into(),
                young: p.get(3).map_or(0, |s|s.parse().unwrap()),
                age: p.get(4).map_or(0, |s|s.parse().unwrap())
            }), "MAPS" => c.maps = p[1..].iter().map(|s|s.to_string()).collect(), "MMU" => c.windows = p[1..].iter().map(|s|s.parse().unwrap()).collect(), _ => c.width = p[1].parse().unwrap()
        }
    }
    Ok(c)
}
#[derive(Clone)]
pub enum Kind {
    Alloc(usize, usize),
    Push(Option<usize>),
    Load(usize, usize),
    Pop(usize),
    Set(usize, usize, Option<usize>),
    Overwrite(usize, Option<usize>),
    Checkpoint(String)
}
#[derive(Clone)]
pub struct Command {
    pub line: usize,
    pub kind: Kind
}
impl Command {
    pub fn name(&self) -> usize {
        match self.kind {
            Kind::Alloc(..) => 0, Kind::Push(..) => 1, Kind::Load(..) => 2, Kind::Pop(..) => 3, Kind::Set(..) => 4, Kind::Overwrite(..) => 5, Kind::Checkpoint(..) => 6
        }
    }
}
fn number(s: &str) -> bool {
    !s.is_empty() && s.len() <= 4 && (s.len() == 1 || !s.starts_with('0')) && s.bytes().all(|c|c.is_ascii_digit())
}
fn label(s: &str) -> bool {
    !s.is_empty() && s.len() <= 16 && s.bytes().all(|c|c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
}
pub fn parse(line: usize, text: &str) -> Result<Command, String> {
    let p = text.split(' ').collect::<Vec<_>>();
    let shape = match p[0] {
        "ALLOC" => "nn", "PUSH" => "r", "LOAD" => "nn", "POP" => "n", "SET" => "nnr", "OVERWRITE" => "nr", "CHECKPOINT" => "l", _ => return Err("syntax".into())
    };
    if p.len() != shape.len()+1 || shape.bytes().zip(&p[1..]).any(|(k, s)|match k {
        b'n' => !number(s), b'r' => *s != "-" && !number(s), _ => !label(s)
    }) {
        return Err("syntax".into())
    }
    let n = |i: usize|p[i].parse::<usize>().unwrap();
    let r = |i: usize|if p[i] == "-" {
        None
    }else {
        Some(n(i))
    };
    let kind = match p[0] {
        "ALLOC" => {
            if n(1)>6 || n(2)>24 {
                return Err("range".into())
            }
            Kind::Alloc(n(1), n(2))
        }, "PUSH" => Kind::Push(r(1)), "LOAD" => Kind::Load(n(1), n(2)), "POP" => {
            if n(1) == 0 {
                return Err("range".into())
            }
            Kind::Pop(n(1))
        }, "SET" => Kind::Set(n(1), n(2), r(3)), "OVERWRITE" => Kind::Overwrite(n(1), r(2)), _ => Kind::Checkpoint(p[1].into())
    };
    Ok(Command {
        line,
        kind
    })
}
pub fn read_script() -> io::Result<Vec<Result<Command, String>>> {
    Ok(fs::read_to_string("input/mutator.txt")?.lines().enumerate().map(|(i, l)|parse(i+1, l)).collect())
}
