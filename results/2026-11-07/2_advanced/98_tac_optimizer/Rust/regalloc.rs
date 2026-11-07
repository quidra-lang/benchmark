use std::collections::{
    BTreeMap,
    BTreeSet
};
use std::cmp::Ordering;
use std::fmt;
use crate::tac_parser::Function;
use crate::cfg::Graph;
use crate::dataflow::{
    Analysis,
    live_transfer
};
#[derive(Clone, Eq, PartialEq)]
pub struct Cost(Vec<u32>);
impl Cost {
    fn zero() -> Self {
        Self(vec![0])
    }
    fn power(exponent: usize) -> Self {
        let mut digits = vec![0; exponent / 9 + 1];
        digits[exponent / 9] = 10u32.pow((exponent % 9) as u32);
        Self(digits)
    }
    fn add(&mut self, other: &Self) {
        let mut carry = 0u64;
        self.0.resize(self.0.len().max(other.0.len()), 0);
        for i in 0..self.0.len() {
            let sum = self.0[i] as u64 + other.0.get(i).copied().unwrap_or(0) as u64 + carry;
            self.0[i] = (sum % 1000000000) as u32;
            carry = sum / 1000000000;
        }
        if carry > 0 {
            self.0.push(carry as u32);
        }
    }
    fn multiply(&self, factor: usize) -> Self {
        let mut result = Self::zero();
        result.0.clear();
        let mut carry = 0u64;
        for &digit in &self.0 {
            let value = digit as u64 * factor as u64 + carry;
            result.0.push((value % 1000000000) as u32);
            carry = value / 1000000000;
        }
        while carry > 0 {
            result.0.push((carry % 1000000000) as u32);
            carry /= 1000000000;
        }
        while result.0.len() > 1 && result.0.last() == Some(&0) {
            result.0.pop();
        }
        result
    }
}
impl Ord for Cost {
    fn cmp(&self, other: &Self) -> Ordering {
        self.0.len().cmp(&other.0.len()).then_with(|| self.0.iter().rev().cmp(other.0.iter().rev()))
    }
}
impl PartialOrd for Cost {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}
impl fmt::Display for Cost {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}", self.0.last().unwrap())?;
        for digit in self.0.iter().rev().skip(1) {
            write!(f, "{:09}", digit)?;
        }
        Ok(())
    }
}
pub struct Allocation {
    pub neighbors: BTreeMap<String,
    BTreeSet<String>>,
    pub costs: BTreeMap<String,
    Cost>,
    pub order: Vec<String>,
    pub potentials: Vec<(String, usize)>,
    pub registers: BTreeMap<String,
    Option<usize>>
}
fn edge(graph: &mut BTreeMap<String, BTreeSet<String>>, a: &str, b: &str) {
    if a != b {
        graph.get_mut(a).unwrap().insert(b.into());
        graph.get_mut(b).unwrap().insert(a.into());
    }
}
pub fn allocate(function: &Function, graph: &Graph, analysis: &Analysis, count: usize) -> Allocation {
    let instructions = function.instructions();
    let mut nodes: BTreeSet<String> = function.parameters.iter().cloned().collect();
    for (i, instruction) in instructions.iter().enumerate() {
        if graph.reachable.contains(&graph.owners[i]) {
            nodes.extend(instruction.destination.iter().cloned());
            nodes.extend(instruction.used());
        }
    }
    let mut neighbors: BTreeMap<String,
    BTreeSet<String>> = nodes.iter().map(|n| (n.clone(), BTreeSet::new())).collect();
    let mut costs: BTreeMap<String,
    Cost> = nodes.iter().map(|n| (n.clone(), Cost::zero())).collect();
    let mut partners: BTreeMap<String,
    BTreeSet<String>> = neighbors.clone();
    for &b in &graph.reachable {
        let weight = Cost::power(graph.depths[b]);
        let mut live = analysis.live.output[b].clone();
        for i in (graph.blocks[b].first..=graph.blocks[b].last).rev() {
            let instruction = &instructions[i];
            for variable in instruction.destination.iter().cloned().chain(instruction.used()) {
                costs.get_mut(&variable).unwrap().add(&weight);
            }
            if let Some(destination) = &instruction.destination {
                let source = if instruction.kind == "copy" {
                    instruction.a.as_ref().and_then(|a| a.variable())
                } else {
                    None
                };
                for other in &live {
                    if source != Some(other.as_str()) {
                        edge(&mut neighbors, destination, other);
                    }
                }
            }
            live_transfer(&mut live, instruction);
        }
    }
    let parameter_live: BTreeSet<String> = analysis.live.input[0].iter().cloned().chain(function.parameters.iter().cloned()).collect();
    for parameter in &function.parameters {
        costs.get_mut(parameter).unwrap().add(&Cost::power(0));
        for other in &parameter_live {
            edge(&mut neighbors, parameter, other);
        }
    }
    for instruction in &instructions {
        if instruction.kind == "copy" {
            if let (Some(destination), Some(source)) = (&instruction.destination, instruction.a.as_ref().and_then(|a| a.variable())) {
                if destination != source && nodes.contains(destination) && nodes.contains(source) {
                    partners.get_mut(destination).unwrap().insert(source.into());
                    partners.get_mut(source).unwrap().insert(destination.clone());
                }
            }
        }
    }
    let mut remaining = nodes.clone();
    let mut order = Vec::new();
    let mut potentials = Vec::new();
    while !remaining.is_empty() {
        let degrees: BTreeMap<String,
        usize> = remaining.iter().map(|n| (n.clone(), neighbors[n].intersection(&remaining).count())).collect();
        let low = remaining.iter().filter(|n| degrees[*n] < count).min_by(|a, b| degrees[*a].cmp(&degrees[*b]).then_with(|| a.cmp(b))).cloned();
        let chosen = if let Some(low) = low {
            low
        } else {
            let chosen = remaining.iter().min_by(|a, b| costs[*a].multiply(degrees[*b]).cmp(&costs[*b].multiply(degrees[*a])).then_with(|| a.cmp(b))).unwrap().clone();
            potentials.push((chosen.clone(), degrees[&chosen]));
            chosen
        };
        remaining.remove(&chosen);
        order.push(chosen);
    }
    let mut registers: BTreeMap<String,
    Option<usize>> = BTreeMap::new();
    for node in order.iter().rev() {
        let taken: BTreeSet<usize> = neighbors[node].iter().filter_map(|n| registers.get(n).copied().flatten()).collect();
        let free: BTreeSet<usize> = (0..count).filter(|r| !taken.contains(r)).collect();
        let bias = partners[node].iter().filter_map(|n| registers.get(n).copied().flatten()).filter(|r| free.contains(r)).min();
        let assigned = bias.or_else(|| free.iter().next().copied());
        registers.insert(node.clone(), assigned);
    }
    Allocation {
        neighbors,
        costs,
        order,
        potentials,
        registers
    }
}
