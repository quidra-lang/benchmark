use std::collections::BTreeSet;
use crate::learning;
#[derive(Clone)] pub struct Factor {
    pub variables: Vec<usize>,
    pub values: Vec<f64>
}
pub fn count(variables: &[usize], cards: &[usize]) -> usize {
    variables.iter().map(|&v| cards[v]).product()
}
pub fn assignment(mut index: usize, variables: &[usize], cards: &[usize]) -> Vec<usize> {
    let mut state = vec![0; cards.len()];
    for &v in variables.iter().rev() {
        state[v] = index%cards[v];
        index /= cards[v];
    }
    state
}
impl Factor {
    pub fn value(&self, state: &[usize], cards: &[usize]) -> f64 {
        let index = self.variables.iter().fold(0, |i, &v| i*cards[v]+state[v]);
        self.values[index]
    }
    pub fn cpt(variable: usize, parents: &[usize], cpt: &[Vec<f64>], cards: &[usize]) -> Self {
        let variables: Vec<_> = parents.iter().copied().chain(std::iter::once(variable)).collect::<BTreeSet<_>>().into_iter().collect();
        let values = (0..count(&variables, cards)).map(|i| {
            let state = assignment(i, &variables, cards);
            cpt[learning::combination(parents, &state, cards)][state[variable]]
        }).collect();
        Self {
            variables,
            values
        }
    }
    pub fn reduce(&self, evidence: &[(usize, usize)], cards: &[usize]) -> Self {
        let variables: Vec<_> = self.variables.iter().copied().filter(|v| !evidence.iter().any(|e| e.0 == *v)).collect();
        let values = (0..count(&variables, cards)).map(|i| {
            let mut state = assignment(i, &variables, cards);
            for &(v, s) in evidence {
                state[v] = s;
            }
            self.value(&state, cards)
        }).collect();
        Self {
            variables,
            values
        }
    }
    pub fn multiply(&self, other: &Self, cards: &[usize]) -> Self {
        let variables: Vec<_> = self.variables.iter().chain(&other.variables).copied().collect::<BTreeSet<_>>().into_iter().collect();
        let values = (0..count(&variables, cards)).map(|i| {
            let state = assignment(i, &variables, cards);
            self.value(&state, cards)*other.value(&state, cards)
        }).collect();
        Self {
            variables,
            values
        }
    }
    pub fn eliminate(&self, variable: usize, maximum: bool, cards: &[usize]) -> Self {
        let variables: Vec<_> = self.variables.iter().copied().filter(|&v| v != variable).collect();
        let values = (0..count(&variables, cards)).map(|i| {
            let mut state = assignment(i, &variables, cards);
            let mut value = if maximum {
                f64::NEG_INFINITY
            } else {
                0.0
            };
            for s in 0..cards[variable] {
                state[variable] = s;
                let next = self.value(&state, cards);
                if maximum {
                    value = value.max(next);
                } else {
                    value += next;
                }
            }
            value
        }).collect();
        Self {
            variables,
            values
        }
    }
}
pub fn product(factors: &[Factor], cards: &[usize]) -> Factor {
    let Some(first) = factors.first() else {
        return Factor {
            variables: Vec::new(),
            values: vec![1.0]
        };
    };
    factors[1..].iter().fold(first.clone(), |product, factor| product.multiply(factor, cards))
}
