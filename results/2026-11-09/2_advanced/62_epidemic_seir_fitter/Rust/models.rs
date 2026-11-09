use crate::data_io::Data;

#[derive(Clone, Copy)]
pub enum Kind { Seird, Sir, Age, Generation }

pub struct Model<'a> {
    pub kind: Kind,
    pub beta: f64,
    pub gamma: f64,
    pub sigma: f64,
    pub data: &'a Data,
    pub matrix: &'a [Vec<f64>],
    pub total: f64,
    pub fatality: f64,
}

impl<'a> Model<'a> {
    pub fn new(kind: Kind, beta: f64, gamma: f64, sigma: f64, data: &'a Data, matrix: &'a [Vec<f64>]) -> Self {
        let total = data.groups.iter().map(|g| g.population).sum::<i64>() as f64;
        let fatality = data.groups.iter().map(|g| g.population as f64*g.fatality).sum::<f64>()/total;
        Self { kind, beta, gamma, sigma, data, matrix, total, fatality }
    }

    pub fn initial(&self) -> Vec<f64> {
        let p = &self.data.params;
        match self.kind {
            Kind::Seird => vec![self.total-p.e0-p.i0, p.e0, p.i0, 0.0, 0.0, 0.0],
            Kind::Sir => vec![self.total-p.e0-p.i0, p.e0+p.i0, 0.0, 0.0],
            Kind::Generation => vec![1.0, 0.0, 0.0],
            Kind::Age => self.data.groups.iter().flat_map(|g| {
                let e = p.e0*g.population as f64/self.total;
                let i = p.i0*g.population as f64/self.total;
                [g.population as f64-e-i, e, i, 0.0, 0.0, 0.0]
            }).collect(),
        }
    }

    pub fn cumulative(&self) -> Vec<usize> {
        match self.kind { Kind::Seird => vec![5], Kind::Sir => vec![3], Kind::Generation => vec![2],
            Kind::Age => (0..self.data.groups.len()).map(|g| 6*g+5).collect() }
    }

    pub fn rate(&self, y: &[f64], multiplier: f64) -> Vec<f64> {
        match self.kind {
            Kind::Seird => {
                let flow = self.beta*multiplier*y[0]*y[2]/self.total;
                vec![-flow, flow-self.sigma*y[1], self.sigma*y[1]-self.gamma*y[2],
                    (1.0-self.fatality)*self.gamma*y[2], self.fatality*self.gamma*y[2], self.sigma*y[1]]
            }
            Kind::Sir => {
                let flow = self.beta*multiplier*y[0]*y[1]/self.total;
                vec![-flow, flow-self.gamma*y[1], self.gamma*y[1], flow]
            }
            Kind::Generation => vec![-self.sigma*y[0], self.sigma*y[0]-self.gamma*y[1], self.gamma*y[1]],
            Kind::Age => {
                let mut result = vec![0.0; y.len()];
                for (g, group) in self.data.groups.iter().enumerate() {
                    let mut contacts = 0.0;
                    for (h, other) in self.data.groups.iter().enumerate() { contacts += self.matrix[g][h]*y[6*h+2]/other.population as f64; }
                    let lambda = self.beta*multiplier*contacts;
                    let flow = lambda*y[6*g];
                    let (e, i) = (y[6*g+1], y[6*g+2]);
                    result[6*g..6*g+6].copy_from_slice(&[-flow, flow-self.sigma*e, self.sigma*e-self.gamma*i,
                        (1.0-group.fatality)*self.gamma*i, group.fatality*self.gamma*i, self.sigma*e]);
                }
                result
            }
        }
    }
}
