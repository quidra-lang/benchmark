use std::collections::BTreeSet;
use crate::factors::{ self, Factor };
pub struct Step {
    pub variable: usize,
    pub fill: usize,
    pub variables: Vec<usize>,
    pub size: usize
}
pub struct Plan {
    pub steps: Vec<Step>,
    pub maximum: usize,
    pub total: usize
}
pub fn plan(factors: &[Factor], eliminate: &[usize], cards: &[usize], minfill: bool, given: &[usize]) -> Plan {
    let n = cards.len();
    let mut graph = vec![BTreeSet::new(); n];
    for factor in factors {
        for &a in &factor.variables {
            for &b in &factor.variables {
                if a != b {
                    graph[a].insert(b);
                }
            }
        }
    }
    let mut remaining: BTreeSet<_> = eliminate.iter().copied().collect();
    let mut steps = Vec::new();
    let mut maximum = 0;
    let mut total = 0;
    while !remaining.is_empty() {
        let fill = |v: usize| {
            let neighbors: Vec<_> = graph[v].iter().copied().collect();
            let mut fill = 0;
            for (i, &a) in neighbors.iter().enumerate() {
                for &b in &neighbors[i+1..] {
                    fill += usize::from(!graph[a].contains(&b));
                }
            }
            fill
        };
        let variable = if minfill {
            *remaining.iter().min_by_key(|&&v| (fill(v), graph[v].len(), v)).unwrap()
        } else {
            *given.iter().find(|v| remaining.contains(*v)).unwrap()
        };
        let filled = fill(variable);
        let neighbors: Vec<_> = graph[variable].iter().copied().collect();
        let variables: Vec<_> = neighbors.iter().copied().chain(std::iter::once(variable)).collect::<BTreeSet<_>>().into_iter().collect();
        let size = factors::count(&variables, cards);
        maximum = maximum.max(size);
        total += size;
        steps.push(Step {
            variable,
            fill: filled,
            variables,
            size
        });
        for &a in &neighbors {
            for &b in &neighbors {
                if a != b {
                    graph[a].insert(b);
                }
            }
            graph[a].remove(&variable);
        }
        graph[variable].clear();
        remaining.remove(&variable);
    }
    Plan {
        steps,
        maximum,
        total
    }
}
pub struct Result {
    pub factor: Factor,
    pub traceback: Vec<(usize, Factor)>
}
pub fn execute(initial: &[Factor], plan: &Plan, maximum: bool, cards: &[usize]) -> Result {
    let mut sequence = initial.to_vec();
    let mut traceback = Vec::new();
    for step in &plan.steps {
        let mut selected = Vec::new();
        let mut rest = Vec::new();
        for factor in sequence {
            if factor.variables.contains(&step.variable) {
                selected.push(factor);
            } else {
                rest.push(factor);
            }
        }
        let product = factors::product(&selected, cards);
        let reduced = product.eliminate(step.variable, maximum, cards);
        if maximum {
            traceback.push((step.variable, product));
        }
        rest.push(reduced);
        sequence = rest;
    }
    Result {
        factor: factors::product(&sequence, cards),
        traceback
    }
}
pub fn traceback(result: &Result, evidence: &[(usize, usize)], cards: &[usize]) -> Vec<usize> {
    let mut states = vec![0; cards.len()];
    for &(v, s) in evidence {
        states[v] = s;
    }
    for (v, product) in result.traceback.iter().rev() {
        let mut best = f64::NEG_INFINITY;
        let mut chosen = 0;
        for s in 0..cards[*v] {
            states[*v] = s;
            let value = product.value(&states, cards);
            if value > best {
                best = value;
                chosen = s;
            }
        }
        states[*v] = chosen;
    }
    states
}
