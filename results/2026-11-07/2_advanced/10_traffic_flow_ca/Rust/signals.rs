use std::collections::BTreeSet;

pub struct Phase { pub duration: usize, pub token: String, pub greens: BTreeSet<String> }
pub struct Junction { pub node: String, pub offset: usize, pub phases: Vec<Phase>, pub cycle: usize, pub incoming: Vec<usize> }
impl Junction {
    pub fn new(node: String, offset: usize, tokens: &[&str]) -> Self {
        let phases: Vec<_> = tokens.iter().map(|token| {
            let (duration, greens) = token.split_once(':').unwrap(); Phase { duration: duration.parse().unwrap(), token: greens.to_owned(), greens: if greens == "-" { BTreeSet::new() } else { greens.split(',').map(str::to_owned).collect() } }
        }).collect(); let cycle = phases.iter().map(|phase| phase.duration).sum(); Self { node, offset, phases, cycle, incoming: Vec::new() }
    }
    pub fn green(&self, segment: &str, step: usize) -> bool {
        if self.phases.is_empty() { return true; } let mut position = (step - 1 + self.offset) % self.cycle;
        for phase in &self.phases { if position < phase.duration { return phase.greens.contains(segment); } position -= phase.duration; } unreachable!()
    }
    pub fn plan_lines(&self) -> Vec<String> {
        if self.phases.is_empty() { return vec![format!("JUNCTION {} unsignalized", self.node)]; } let mut lines = vec![format!("JUNCTION {} signal cycle {} offset {}", self.node, self.cycle, self.offset)]; let mut begin = 0;
        for (j, phase) in self.phases.iter().enumerate() { let end = begin + phase.duration - 1; lines.push(format!("  PHASE {} {begin}-{end} {}", j + 1, phase.token)); begin = end + 1; } lines
    }
}
