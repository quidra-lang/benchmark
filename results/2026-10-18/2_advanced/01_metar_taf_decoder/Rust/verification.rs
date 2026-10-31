use super::*;

pub fn covers(report: &Report, time: i64) -> bool {
    let hour = time-time%60;
    report.kind == "TAF" && report.time <= time && report.start <= hour && hour<report.end
}

pub fn chosen<'a>(reports: &'a[Report], station: &str, time: i64) -> Option<&'a Report> {
    let mut best: Option<&Report> = None;
    for r in reports {
        if r.station == station && covers(r, time) && best.is_none_or(|b|r.time >= b.time) {
            best = Some(r);
        }
    }
    best
}

#[derive(Default)]
pub struct Contingency {
    pub table: [[i64; 4]; 4],
    pub temporary_hits: i64
}

impl Contingency {
    pub fn add(&mut self, forecast: usize, observation: usize, hit: bool) {
        self.table[forecast][observation] += 1;
        self.temporary_hits += i64::from(hit);
    }
    pub fn row(&self, i: usize) -> i64 {
        self.table[i].iter().sum()
    }
    pub fn column(&self, j: usize) -> i64 {
        self.table.iter().map(|row|row[j]).sum()
    }
    pub fn total(&self) -> i64 {
        self.table.iter().flatten().sum()
    }
    pub fn hits(&self) -> i64 {
        (0..4).map(|i|self.table[i][i]).sum()
    }
    pub fn skill(&self) -> (i64, i64) {
        let n = self.total();
        let e: i64 = (0..4).map(|i|self.row(i)*self.column(i)).sum();
        (n*self.hits()-e, n*n-e)
    }
    pub fn detection(&self, i: usize) -> (i64, i64) {
        (self.table[i][i], self.column(i))
    }
    pub fn false_alarm(&self, i: usize) -> (i64, i64) {
        (self.row(i)-self.table[i][i], self.row(i))
    }
}
