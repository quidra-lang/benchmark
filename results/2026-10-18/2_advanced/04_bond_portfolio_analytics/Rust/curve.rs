use crate::daycount::year_fraction;
use crate::pricing::bisection;
use crate::schedule::coupon_schedule;
#[derive(Clone)]
pub struct ZeroCurve { pub days: Vec<i32>, pub rates: Vec<f64> }
impl ZeroCurve {
    pub fn zero(&self, day: i32) -> f64 {
        if day <= self.days[0] { return self.rates[0]; }
        let last = self.days.len() - 1;
        if day >= self.days[last] { return self.rates[last]; }
        let mut index = 1; while self.days[index] < day { index += 1; }
        let low = self.days[index - 1];
        self.rates[index - 1] + (self.rates[index] - self.rates[index - 1]) * ((day - low) as f64 / (self.days[index] - low) as f64)
    }
    pub fn discount(&self, day: i32, spread: f64) -> f64 {
        let rate = self.zero(day) + spread; let mut growth = 1.0;
        for _ in 0..day / 365 { growth *= 1.0 + rate; }
        1.0 / (growth * (1.0 + rate * (day % 365) as f64 / 365.0))
    }
    pub fn forward(&self, start: i32, end: i32) -> f64 { (self.discount(start, 0.0) / self.discount(end, 0.0) - 1.0) * 365.0 / (end - start) as f64 }
    pub fn shifted(&self, deltas: &[f64]) -> Self { Self { days: self.days.clone(), rates: self.rates.iter().zip(deltas).map(|(rate, delta)| rate + delta).collect() } }
    pub fn present_value(&self, flows: &[(i32, f64)], spread: f64) -> f64 { let mut total = 0.0; for &(day, flow) in flows { total += flow * self.discount(day, spread); } total }
}
pub fn bootstrap(settlement: i32, pillars: &[(i32, i64, i32)]) -> ZeroCurve {
    let mut curve = ZeroCurve { days: Vec::new(), rates: Vec::new() };
    for &(maturity, coupon, frequency) in pillars {
        let dates = coupon_schedule(settlement, maturity, frequency, false, false); let mut flows = Vec::new();
        for index in 1..dates.len() {
            let (n, m) = year_fraction("30/360", dates[index - 1], dates[index]);
            let mut flow = coupon as f64 * n as f64 / (10000.0 * m as f64);
            if index == dates.len() - 1 { flow += 1.0; }
            flows.push((dates[index] - settlement, flow));
        }
        curve.days.push(maturity - settlement); curve.rates.push(0.0);
        let last = curve.rates.len() - 1;
        let rate = bisection(|trial| { curve.rates[last] = trial; curve.present_value(&flows, 0.0) }, 0.0, 1.0, 1.0);
        curve.rates[last] = rate;
    }
    curve
}
pub fn z_spread(curve: &ZeroCurve, flows: &[(i32, f64)], target: i64) -> f64 { bisection(|spread| curve.present_value(flows, spread), -0.5, 0.5, target as f64) }
