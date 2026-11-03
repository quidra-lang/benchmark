use crate::rational::Fraction as F;
#[derive(Clone)]
pub struct Tableau { pub t: Vec<Vec<F>>, pub beta: Vec<F>, pub basis: Vec<usize> }
impl Tableau {
    pub fn reduced(&self, costs: &[F]) -> Vec<F> {
        (0..costs.len()).map(|k| costs[k] - (0..self.t.len()).fold(F::zero(), |sum, i| sum + costs[self.basis[i]] * self.t[i][k])).collect()
    }
    pub fn value(&self, costs: &[F]) -> F {
        (0..self.t.len()).fold(F::zero(), |sum, i| sum + costs[self.basis[i]] * self.beta[i])
    }
    pub fn pivot(&mut self, p: usize, q: usize) {
        let value = self.t[p][q];
        for cell in &mut self.t[p] { *cell = *cell / value; }
        self.beta[p] = self.beta[p] / value;
        let row = self.t[p].clone();
        let beta = self.beta[p];
        for i in 0..self.t.len() {
            if i == p { continue; }
            let f = self.t[i][q];
            for k in 0..row.len() { self.t[i][k] = self.t[i][k] - f * row[k]; }
            self.beta[i] = self.beta[i] - f * beta;
        }
        self.basis[p] = q;
    }
    pub fn display(&self, heading: &str, columns: &[String], rows: &[String], costs: &[F], constant: F, sign: F) -> Vec<String> {
        let mut lines = vec![format!("TABLEAU {}", heading), format!("COLUMNS {}", columns.join(" "))];
        for i in 0..self.t.len() {
            lines.push(format!("ROW {} {} {} | {}", rows[i], columns[self.basis[i]], self.t[i].iter().map(F::to_string).collect::<Vec<_>>().join(" "), self.beta[i]));
        }
        lines.push(format!("COST {} | {}", self.reduced(costs).iter().map(F::to_string).collect::<Vec<_>>().join(" "), constant + sign * self.value(costs)));
        lines
    }
}
