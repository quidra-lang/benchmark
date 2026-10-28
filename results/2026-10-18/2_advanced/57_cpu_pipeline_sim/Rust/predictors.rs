use crate::trace_io::Predictor;

pub struct Btb {
    entries: Vec<Option<(i64, i64)>>,
}

impl Btb {
    pub fn new(size: usize) -> Self { Self { entries: vec![None; size] } }

    pub fn lookup(&self, pc: i64) -> Option<i64> {
        self.entries[(pc / 4) as usize % self.entries.len()].filter(|&(tag, _)| tag == pc).map(|(_, target)| target)
    }

    pub fn insert(&mut self, pc: i64, target: i64) {
        let index = (pc / 4) as usize % self.entries.len();
        self.entries[index] = Some((pc, target));
    }
}

pub struct Ras {
    entries: Vec<i64>,
    depth: usize,
}

impl Ras {
    pub fn new(depth: usize) -> Self { Self { entries: Vec::new(), depth } }

    pub fn push(&mut self, value: i64) {
        if self.depth == 0 { return; }
        if self.entries.len() == self.depth { self.entries.remove(0); }
        self.entries.push(value);
    }

    pub fn pop(&mut self) -> Option<i64> { self.entries.pop() }
}

pub struct Direction<'a> {
    definition: &'a Predictor,
    local: Vec<usize>,
    global: Vec<usize>,
    chooser: Vec<usize>,
    history: usize,
    bits: usize,
}

fn update(counter: &mut usize, taken: bool) {
    if taken { *counter = (*counter + 1).min(3); } else { *counter = (*counter).saturating_sub(1); }
}

impl<'a> Direction<'a> {
    pub fn new(definition: &'a Predictor) -> Self {
        let p = &definition.parameters;
        let mut result = Self { definition, local: Vec::new(), global: Vec::new(), chooser: Vec::new(), history: 0, bits: 0 };
        match definition.scheme.as_str() {
            "ONEBIT" => result.local = vec![0; p[0]],
            "TWOBIT" => result.local = vec![1; p[0]],
            "GSHARE" => { result.global = vec![1; p[0]]; result.bits = p[1]; }
            "TOURNAMENT" => { result.local = vec![1; p[0]]; result.global = vec![1; p[1]]; result.bits = p[2]; result.chooser = vec![1; p[3]]; }
            _ => {}
        }
        result
    }

    pub fn predict(&self, pc: i64, target: i64) -> bool {
        let pc = (pc / 4) as usize;
        match self.definition.scheme.as_str() {
            "STATIC_NT" | "PERFECT" => false,
            "BTFN" => target < (pc * 4) as i64,
            "ONEBIT" => self.local[pc % self.local.len()] == 1,
            "TWOBIT" => self.local[pc % self.local.len()] >= 2,
            "GSHARE" => self.global[(pc ^ self.history) % self.global.len()] >= 2,
            "TOURNAMENT" => if self.chooser[pc % self.chooser.len()] >= 2 { self.global[(pc ^ self.history) % self.global.len()] >= 2 } else { self.local[pc % self.local.len()] >= 2 },
            _ => unreachable!(),
        }
    }

    pub fn update(&mut self, pc: i64, taken: bool) {
        let pc = (pc / 4) as usize;
        match self.definition.scheme.as_str() {
            "ONEBIT" => { let index = pc % self.local.len(); self.local[index] = usize::from(taken); }
            "TWOBIT" => { let index = pc % self.local.len(); update(&mut self.local[index], taken); }
            "GSHARE" | "TOURNAMENT" => {
                let global = (pc ^ self.history) % self.global.len();
                if self.definition.scheme == "TOURNAMENT" {
                    let local = pc % self.local.len();
                    let chooser = pc % self.chooser.len();
                    let a = self.local[local] >= 2;
                    let b = self.global[global] >= 2;
                    if a != b { update(&mut self.chooser[chooser], b == taken); }
                    update(&mut self.local[local], taken);
                }
                update(&mut self.global[global], taken);
                self.history = (2 * self.history + usize::from(taken)) % (1 << self.bits);
            }
            _ => {}
        }
    }
}

pub fn storage(predictor: &Predictor) -> usize {
    let p = &predictor.parameters;
    match predictor.scheme.as_str() {
        "ONEBIT" => p[0],
        "TWOBIT" => 2 * p[0],
        "GSHARE" => 2 * p[0] + p[1],
        "TOURNAMENT" => 2 * (p[0] + p[1] + p[3]) + p[2],
        _ => 0,
    }
}
