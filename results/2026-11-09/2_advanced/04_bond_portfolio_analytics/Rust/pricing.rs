pub const BP: f64 = 0.0001;
pub fn bisection(mut function: impl FnMut(f64) -> f64, mut low: f64, mut high: f64, target: f64) -> f64 {
    for _ in 0..80 { let middle = (low + high) / 2.0; if function(middle) > target { low = middle; } else { high = middle; } }
    (low + high) / 2.0
}
#[derive(Clone, Default)]
pub struct Risk { pub macaulay: f64, pub modified: f64, pub convexity: f64, pub dv01: f64 }
#[derive(Clone)]
pub struct YieldPricer { pub flows: Vec<i64>, pub fraction: f64, pub frequency: i32, pub outstanding: i64 }
impl YieldPricer {
    fn values(&self, rate: f64) -> Vec<f64> {
        let first = 1.0 + self.fraction * rate / self.frequency as f64; let growth = 1.0 + rate / self.frequency as f64;
        let mut factor = 1.0; let mut values = Vec::new();
        for &flow in &self.flows { values.push(flow as f64 / (first * factor)); factor *= growth; }
        values
    }
    pub fn dirty(&self, rate: f64) -> f64 { let mut total = 0.0; for value in self.values(rate) { total += value; } total * 100.0 / self.outstanding as f64 }
    pub fn solve(&self, target: f64) -> f64 { bisection(|rate| self.dirty(rate), 0.0, 1.0, target) }
    pub fn in_range(&self, target: f64) -> bool { self.dirty(0.0) > target && target > self.dirty(1.0) }
    pub fn risk(&self, rate: f64) -> Risk {
        let frequency = self.frequency as f64; let growth = 1.0 + rate / frequency;
        let (mut total, mut weighted, mut curvature) = (0.0, 0.0, 0.0);
        for (index, value) in self.values(rate).into_iter().enumerate() { let years = (index as f64 + self.fraction) / frequency; total += value; weighted += years * value; curvature += years * (years + 1.0 / frequency) * value; }
        let macaulay = weighted / total;
        Risk { macaulay, modified: macaulay / growth, convexity: curvature / (total * growth * growth), dv01: (self.dirty(rate - BP) - self.dirty(rate + BP)) / 2.0 }
    }
}
