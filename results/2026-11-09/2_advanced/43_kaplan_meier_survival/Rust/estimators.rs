use crate::dataset::Subject;
use crate::Z;
use std::collections::BTreeSet;

#[derive(Clone)]
pub struct KmRow {
    pub time: i64,
    pub risk: usize,
    pub events: usize,
    pub censored: usize,
    pub survival: f64,
    pub error: Option<f64>,
    pub lower: Option<f64>,
    pub upper: Option<f64>,
    pub hazard: f64,
    pub hazard_error: f64,
}

pub fn kaplan_meier(subjects: &[Subject], reverse: bool) -> Vec<KmRow> {
    let times: Vec<_> = subjects.iter().filter(|s| s.event != reverse).map(|s| s.time).collect::<BTreeSet<_>>().into_iter().collect();
    let (mut survival, mut greenwood, mut hazard, mut hazard_variance) = (1.0, Some(0.0), 0.0, 0.0);
    let mut rows = Vec::new();
    for (i, &time) in times.iter().enumerate() {
        let risk = subjects.iter().filter(|s| s.time >= time).count();
        let events = subjects.iter().filter(|s| s.time == time && s.event != reverse).count();
        let censored = subjects.iter().filter(|s| s.event == reverse && s.time >= time && times.get(i + 1).is_none_or(|&next| s.time < next)).count();
        survival *= (risk - events) as f64 / risk as f64;
        greenwood = if risk == events { None } else { greenwood.map(|g| g + events as f64 / (risk * (risk - events)) as f64) };
        let (error, lower, upper) = if let Some(g) = greenwood {
            let logarithm = survival.ln();
            let omega = Z * g.sqrt() / (-logarithm);
            (Some(survival * g.sqrt()), Some((logarithm * omega.exp()).exp()), Some((logarithm * (-omega).exp()).exp()))
        } else { (None, None, None) };
        hazard += events as f64 / risk as f64;
        hazard_variance += events as f64 / (risk * risk) as f64;
        rows.push(KmRow { time, risk, events, censored, survival, error, lower, upper, hazard, hazard_error: hazard_variance.sqrt() });
    }
    rows
}

pub fn at(rows: &[KmRow], time: i64) -> KmRow {
    rows.iter().rev().find(|row| row.time <= time).cloned().unwrap_or(KmRow { time: 0, risk: 0, events: 0, censored: 0, survival: 1.0, error: Some(0.0), lower: None, upper: None, hazard: 0.0, hazard_error: 0.0 })
}

pub struct LifeRow {
    pub start: i64,
    pub end: i64,
    pub risk: usize,
    pub events: usize,
    pub withdrawn: usize,
    pub exposed: f64,
    pub q: f64,
    pub survival: f64,
    pub error: f64,
    pub hazard: f64,
}

pub fn life_table(subjects: &[Subject], width: i64, count: i64) -> Vec<LifeRow> {
    let mut rows = Vec::new();
    let (mut survival, mut variance) = (1.0, 0.0);
    for i in 0..count {
        let start = i * width;
        let end = (i + 1) * width;
        let risk = subjects.iter().filter(|s| s.time >= start).count();
        let events = subjects.iter().filter(|s| start <= s.time && s.time < end && s.event).count();
        let withdrawn = subjects.iter().filter(|s| start <= s.time && s.time < end && !s.event).count();
        let f = (2 * risk - withdrawn) as i64;
        survival *= (f - 2 * events as i64) as f64 / f as f64;
        variance += (4 * events) as f64 / (f * (f - 2 * events as i64)) as f64;
        rows.push(LifeRow { start, end, risk, events, withdrawn, exposed: f as f64 / 2.0, q: (2 * events) as f64 / f as f64, survival, error: survival * variance.sqrt(), hazard: (2000 * events) as f64 / (width * (f - events as i64)) as f64 });
    }
    rows
}
