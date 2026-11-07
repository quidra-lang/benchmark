use std::io;
use crate::features::{FEATURE_NAMES, Point, SQRT_FEATURES};
use crate::transactions::read_lines;

pub struct Condition { feature: usize, greater: bool, threshold: f64 }
pub struct Rule { pub name: String, conditions: Vec<Condition> }
pub fn read_rules(path: &str) -> io::Result<Vec<Rule>> {
    Ok(read_lines(path)?.iter().map(|line| {
        let words: Vec<_> = line.split(' ').collect();
        let conditions = words[1..].chunks(3).map(|fields| Condition {
            feature: FEATURE_NAMES.iter().position(|&name| name == fields[0]).unwrap(),
            greater: fields[1] == ">", threshold: fields[2].parse().unwrap(),
        }).collect();
        Rule { name: words[0].to_owned(), conditions }
    }).collect())
}
pub fn rule_number(rules: &[Rule], center: &[f64]) -> usize {
    rules.iter().position(|rule| rule.conditions.iter().all(|condition| {
        if condition.greater { center[condition.feature] > condition.threshold }
        else { center[condition.feature] < condition.threshold }
    })).unwrap()
}
pub fn original_scale(center: &[f64], means: &[f64], sds: &[f64]) -> Point {
    center.iter().enumerate().map(|(feature, component)| {
        let value = means[feature] + sds[feature] * component;
        if SQRT_FEATURES[feature] { value * value } else { value }
    }).collect()
}
