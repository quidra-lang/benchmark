use std::collections::{
    BTreeMap,
    BTreeSet
};
use crate::tac_parser::{
    Function,
    Line
};
#[derive(Clone)]
pub struct Block {
    pub first: usize,
    pub last: usize,
    pub labels: Vec<String>,
    pub predecessors: Vec<usize>,
    pub successors: Vec<usize>
}
#[derive(Clone)]
pub struct Loop {
    pub header: usize,
    pub latches: BTreeSet<usize>,
    pub blocks: BTreeSet<usize>,
    pub exits: BTreeSet<usize>,
    pub outside: BTreeSet<usize>,
    pub depth: usize
}
pub struct Graph {
    pub blocks: Vec<Block>,
    pub owners: Vec<usize>,
    pub reachable: BTreeSet<usize>,
    pub postorder: Vec<usize>,
    pub order: Vec<usize>,
    pub dominators: Vec<BTreeSet<usize>>,
    pub idom: Vec<Option<usize>>,
    pub loops: Vec<Loop>,
    pub depths: Vec<usize>
}
fn visit(block: usize, blocks: &[Block], seen: &mut BTreeSet<usize>, order: &mut Vec<usize>) {
    if !seen.insert(block) {
        return;
    }
    for &next in &blocks[block].successors {
        visit(next, blocks, seen, order);
    }
    order.push(block);
}
pub fn build(function: &Function) -> Graph {
    let instructions = function.instructions();
    let mut labels: Vec<Vec<String>> = vec![Vec::new(); instructions.len()];
    let mut n = 0;
    for line in &function.code {
        match line {
            Line::Label(label) => labels[n].push(label.clone()),
            Line::Instruction(_) => n += 1
        }
    }
    let mut leaders = vec![0];
    for i in 1..instructions.len() {
        if !labels[i].is_empty() || ["goto", "if", "return"].contains(&instructions[i - 1].kind) {
            leaders.push(i);
        }
    }
    let mut blocks = Vec::new();
    let mut owners = vec![0; instructions.len()];
    let mut label_blocks = BTreeMap::new();
    for (b, &first) in leaders.iter().enumerate() {
        let last = if b + 1 < leaders.len() {
            leaders[b + 1] - 1
        } else {
            instructions.len() - 1
        };
        for i in first..=last {
            owners[i] = b;
        }
        for label in &labels[first] {
            label_blocks.insert(label.clone(), b);
        }
        blocks.push(Block {
            first,
            last,
            labels: labels[first].clone(),
            predecessors: Vec::new(),
            successors: Vec::new()
        });
    }
    for b in 0..blocks.len() {
        let last = &instructions[blocks[b].last];
        let mut successors = Vec::new();
        if last.kind != "goto" && last.kind != "return" {
            successors.push(b + 1);
        }
        if last.kind == "goto" || last.kind == "if" {
            let target = label_blocks[&last.target];
            if !successors.contains(&target) {
                successors.push(target);
            }
        }
        blocks[b].successors = successors;
    }
    for b in 0..blocks.len() {
        for next in blocks[b].successors.clone() {
            blocks[next].predecessors.push(b);
        }
    }
    let mut reachable = BTreeSet::new();
    let mut postorder = Vec::new();
    visit(0, &blocks, &mut reachable, &mut postorder);
    let order: Vec<usize> = postorder.iter().rev().copied().collect();
    let mut dominators = vec![BTreeSet::new(); blocks.len()];
    for &b in &reachable {
        dominators[b] = if b == 0 {
            BTreeSet::from([0])
        } else {
            reachable.clone()
        };
    }
    loop {
        let mut changed = false;
        for &b in order.iter().skip(1) {
            let mut intersection = reachable.clone();
            for &p in &blocks[b].predecessors {
                if reachable.contains(&p) {
                    intersection = intersection.intersection(&dominators[p]).copied().collect();
                }
            }
            intersection.insert(b);
            if intersection != dominators[b] {
                dominators[b] = intersection;
                changed = true;
            }
        }
        if !changed {
            break;
        }
    }
    let mut idom = vec![None; blocks.len()];
    for &b in reachable.iter().filter(|&&b| b != 0) {
        idom[b] = dominators[b].iter().filter(|&&d| d != b).max_by_key(|&&d| dominators[d].len()).copied();
    }
    let mut headers: BTreeMap<usize,
    BTreeSet<usize>> = BTreeMap::new();
    for &tail in &reachable {
        for &head in &blocks[tail].successors {
            if dominators[tail].contains(&head) {
                headers.entry(head).or_default().insert(tail);
            }
        }
    }
    let mut loops = Vec::new();
    for (header, latches) in headers {
        let mut members = latches.clone();
        members.insert(header);
        let mut pending: Vec<usize> = latches.iter().copied().filter(|&b| b != header).collect();
        while let Some(b) = pending.pop() {
            for &p in &blocks[b].predecessors {
                if reachable.contains(&p) && members.insert(p) && p != header {
                    pending.push(p);
                }
            }
        }
        let mut exits = BTreeSet::new();
        let mut outside = BTreeSet::new();
        for &b in &members {
            if instructions[blocks[b].last].kind == "return" {
                exits.insert(b);
            }
            for &s in &blocks[b].successors {
                if !members.contains(&s) {
                    outside.insert(s);
                    exits.insert(b);
                }
            }
        }
        loops.push(Loop {
            header,
            latches,
            blocks: members,
            exits,
            outside,
            depth: 0
        });
    }
    for i in 0..loops.len() {
        loops[i].depth = loops.iter().filter(|l| l.blocks.contains(&loops[i].header)).count();
    }
    let depths = (0..blocks.len()).map(|b| loops.iter().filter(|l| l.blocks.contains(&b)).count()).collect();
    Graph {
        blocks,
        owners,
        reachable,
        postorder,
        order,
        dominators,
        idom,
        loops,
        depths
    }
}
