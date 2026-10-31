use crate::dataset::Subject;
use crate::numerics::{solve, Matrix};

pub struct EventRisk {
    pub time: i64,
    pub events: usize,
    pub s0: f64,
    pub s1: Vec<f64>,
}

pub struct Evaluation {
    pub likelihood: f64,
    pub score: Vec<f64>,
    pub information: Matrix,
    pub theta: Vec<f64>,
    pub event_risks: Vec<EventRisk>,
}

pub fn evaluate(subjects: &[Subject], x: &[Vec<i64>], beta: &[f64]) -> Evaluation {
    let p = beta.len();
    let theta: Vec<_> = x.iter().map(|row| row.iter().zip(beta).fold(0.0, |total, (&x, &b)| total + b * x as f64)).collect();
    let risks: Vec<_> = theta.iter().map(|&theta| theta.exp()).collect();
    let mut order: Vec<_> = (0..subjects.len()).collect();
    order.sort_by_key(|&i| (-subjects[i].time, subjects[i].id));
    let mut result = Evaluation { likelihood: 0.0, score: vec![0.0; p], information: vec![vec![0.0; p]; p], theta, event_risks: Vec::new() };
    let mut s0 = 0.0;
    let mut s1 = vec![0.0; p];
    let mut s2 = vec![vec![0.0; p]; p];
    let mut i = 0;
    while i < order.len() {
        let time = subjects[order[i]].time;
        let mut events = Vec::new();
        while i < order.len() && subjects[order[i]].time == time {
            let index = order[i];
            let risk = risks[index];
            s0 += risk;
            for c in 0..p {
                s1[c] += risk * x[index][c] as f64;
                for d in 0..p { s2[c][d] += risk * x[index][c] as f64 * x[index][d] as f64; }
            }
            if subjects[index].event { events.push(index); }
            i += 1;
        }
        if events.is_empty() { continue; }
        let e = events.len() as f64;
        result.likelihood += events.iter().fold(0.0, |sum, &i| sum + result.theta[i]) - e * s0.ln();
        for c in 0..p {
            result.score[c] += events.iter().map(|&i| x[i][c]).sum::<i64>() as f64 - e * s1[c] / s0;
            for d in 0..p { result.information[c][d] += e * (s2[c][d] / s0 - (s1[c] / s0) * (s1[d] / s0)); }
        }
        result.event_risks.push(EventRisk { time, events: events.len(), s0, s1: s1.clone() });
    }
    result
}

pub struct Fit {
    pub beta: Vec<f64>,
    pub history: Vec<(f64, Vec<f64>)>,
    pub null: Evaluation,
    pub final_evaluation: Evaluation,
}

pub fn fit(subjects: &[Subject], x: &[Vec<i64>]) -> Fit {
    let mut beta = vec![0.0; x[0].len()];
    let null = evaluate(subjects, x, &beta);
    let mut history = Vec::new();
    for _ in 0..25 {
        let evaluation = evaluate(subjects, x, &beta);
        let delta = solve(&evaluation.information, &evaluation.score);
        for (beta, delta) in beta.iter_mut().zip(delta) { *beta += delta; }
        history.push((evaluation.likelihood, beta.clone()));
    }
    let final_evaluation = evaluate(subjects, x, &beta);
    Fit { beta, history, null, final_evaluation }
}
