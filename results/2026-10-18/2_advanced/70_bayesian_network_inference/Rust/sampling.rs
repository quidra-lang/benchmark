use crate::learning;
pub struct Generator {
    pub state: i64
}
impl Generator {
    pub fn next(&mut self) -> f64 {
        self.state = self.state*48271%2147483647;
        self.state as f64/2147483647.0
    }
}
pub fn weighted(generator: &mut Generator, order: &[usize], parents: &[Vec<usize>], cards: &[usize], cpts: &[Vec<Vec<f64>>], evidence: &[(usize, usize)]) -> (Vec<usize>, f64) {
    let mut states = vec![0; cards.len()];
    let mut weight = 1.0;
    for &v in order {
        let row = learning::combination(&parents[v], &states, cards);
        if let Some(&(_, state)) = evidence.iter().find(|&&(variable, _)| variable == v) {
            states[v] = state;
            weight *= cpts[v][row][state];
        } else {
            let u = generator.next();
            let mut cumulative = 0.0;
            let mut chosen = cards[v]-1;
            for s in 0..cards[v] {
                cumulative += cpts[v][row][s];
                if u < cumulative {
                    chosen = s;
                    break;
                }
            }
            states[v] = chosen;
        }
    }
    (states, weight)
}
