use crate::variable_charts::Limits;

pub struct Zones { pub limits: Limits, pub u1: f64, pub u2: f64, pub l1: f64, pub l2: f64 }

impl Zones {
    pub fn new(limits: Limits) -> Self {
        let a = (limits.ucl - limits.cl) / 3.0;
        let b = (limits.cl - limits.lcl) / 3.0;
        Self { limits, u1: limits.cl + a, u2: limits.cl + 2.0 * a, l1: limits.cl - b, l2: limits.cl - 2.0 * b }
    }
    pub fn name(&self, value: f64) -> &'static str {
        if value > self.limits.ucl { "OUT+" } else if value < self.limits.lcl { "OUT-" }
        else if value > self.u2 { "A+" } else if value > self.u1 { "B+" } else if value > self.limits.cl { "C+" }
        else if value < self.l2 { "A-" } else if value < self.l1 { "B-" } else if value < self.limits.cl { "C-" } else { "C0" }
    }
}

#[derive(Clone)]
pub struct Signal { pub chart: usize, pub rule: u8, pub start: usize, pub end: usize, pub value: f64, pub direction: &'static str }

impl Signal {
    pub fn subgroup(&self, size: usize) -> usize { if self.chart == 4 || self.chart == 5 { (self.end - 1) / size + 1 } else { self.end } }
}

pub fn rule_text(rule: u8) -> String { match rule { 9 => "UPPER".into(), 10 => "LOWER".into(), _ => rule.to_string() } }

fn direction(rule: u8, window: &[f64], z: &Zones) -> Option<&'static str> {
    let last = *window.last().unwrap();
    match rule {
        1 => if z.limits.outside(last) { Some(if last > z.limits.cl { "UP" } else { "DOWN" }) } else { None },
        2 | 3 => {
            let (upper, lower, needed) = if rule == 2 { (z.u2, z.l2, 2) } else { (z.u1, z.l1, 4) };
            if last > upper && window.iter().filter(|&&v| v > upper).count() >= needed { Some("UP") }
            else if last < lower && window.iter().filter(|&&v| v < lower).count() >= needed { Some("DOWN") } else { None }
        }
        4 => if window.iter().all(|&v| v > z.limits.cl) { Some("UP") } else if window.iter().all(|&v| v < z.limits.cl) { Some("DOWN") } else { None },
        5 => if window.windows(2).all(|v| v[1] > v[0]) { Some("UP") } else if window.windows(2).all(|v| v[1] < v[0]) { Some("DOWN") } else { None },
        6 => {
            let differences: Vec<f64> = window.windows(2).map(|v| v[1] - v[0]).collect();
            if differences.iter().all(|&v| v != 0.0) && differences.windows(2).all(|v| (v[0] > 0.0) != (v[1] > 0.0)) { Some("NONE") } else { None }
        }
        7 => if window.iter().all(|&v| z.l1 < v && v < z.u1) { Some("NONE") } else { None },
        8 => if window.iter().all(|&v| v > z.u1 || v < z.l1) && window.iter().any(|&v| v > z.u1) && window.iter().any(|&v| v < z.l1) { Some("NONE") } else { None },
        _ => unreachable!(),
    }
}

pub fn check_rules(chart: usize, numbers: &[usize], values: &[f64], limits: Limits, rules: &[u8]) -> Vec<Signal> {
    let lengths = [1,3,5,8,6,14,15,8];
    let zones = Zones::new(limits);
    let mut signals = Vec::new();
    for k in 1..=values.len() {
        for &rule in rules {
            let length = lengths[rule as usize - 1];
            if k >= length {
                if let Some(direction) = direction(rule, &values[k - length..k], &zones) { signals.push(Signal { chart, rule, start: numbers[k - length], end: numbers[k - 1], value: values[k - 1], direction }); }
            }
        }
    }
    signals
}
