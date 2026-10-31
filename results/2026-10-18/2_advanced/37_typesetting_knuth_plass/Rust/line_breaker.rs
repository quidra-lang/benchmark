use crate::Metric;
use std::collections::BTreeMap;

pub fn class(slack: i64, last: bool) -> usize {
    if last { 1 } else if slack <= 1 { 0 } else if slack <= 3 { 1 } else if slack <= 6 { 2 } else { 3 }
}

pub fn cost(metric: &Metric, previous: usize, previous_mid: bool, current_mid: bool, last: bool, params: &BTreeMap<String, i64>) -> i64 {
    let mut value = params["line_penalty"];
    value += if metric.slack < 0 { params["overfull_penalty"] } else if last { 0 } else { metric.slack * metric.slack };
    if current_mid { value += params["hyphen_penalty"]; if previous_mid { value += params["double_hyphen_demerit"]; } }
    if last && previous_mid { value += params["final_hyphen_demerit"]; }
    if class(metric.slack, last).abs_diff(previous) >= 2 { value += params["fitness_demerit"]; }
    value
}

pub fn breaking(metrics: &[Vec<Option<Metric>>], middle: &[bool], params: &BTreeMap<String, i64>, greedy: bool) -> (Vec<usize>, i64) {
    let m = middle.len() - 1;
    if greedy {
        let mut a = 0;
        let mut previous_class = 1;
        let mut total = 0;
        let mut result = Vec::new();
        while a < m {
            let mut b = a + 1;
            if metrics[a][b].as_ref().unwrap().slack >= 0 {
                for candidate in a + 1..=m {
                    if metrics[a][candidate].as_ref().is_some_and(|metric| metric.slack >= 0) { b = candidate; }
                }
            }
            let metric = metrics[a][b].as_ref().unwrap();
            total += cost(metric, previous_class, middle[a], middle[b], b == m, params);
            previous_class = class(metric.slack, b == m);
            result.push(b);
            a = b;
        }
        return (result, total);
    }
    let mut totals = vec![[None; 4]; m + 1];
    let mut previous = vec![[None; 4]; m + 1];
    totals[0][1] = Some(0);
    for b in 1..=m {
        for a in 0..b {
            let Some(metric) = &metrics[a][b] else { continue; };
            let current_class = class(metric.slack, b == m);
            for previous_class in 0..4 {
                if let Some(total) = totals[a][previous_class] {
                    let candidate = total + cost(metric, previous_class, middle[a], middle[b], b == m, params);
                    if totals[b][current_class].is_none_or(|best| candidate < best) {
                        totals[b][current_class] = Some(candidate);
                        previous[b][current_class] = Some((a, previous_class));
                    }
                }
            }
        }
    }
    let total = totals[m][1].unwrap();
    let mut result = Vec::new();
    let (mut b, mut current_class) = (m, 1);
    while b > 0 {
        result.push(b);
        (b, current_class) = previous[b][current_class].unwrap();
    }
    result.reverse();
    (result, total)
}
