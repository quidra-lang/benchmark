use std::collections::{BTreeMap,BTreeSet};
use crate::expressions::Value;
pub fn points(domains: &[(String,Vec<Value>)]) -> Vec<BTreeMap<String,Value>> {
    fn visit(domains: &[(String,Vec<Value>)], index: usize, point: &mut BTreeMap<String,Value>, result: &mut Vec<BTreeMap<String,Value>>) {
        if index == domains.len() {
            result.push(point.clone());
            return;
        }
        for value in &domains[index].1 {
            point.insert(domains[index].0.clone(),value.clone());
            visit(domains,index+1,point,result);
        }
    }
    let mut result = Vec::new();
    visit(domains,0,&mut BTreeMap::new(),&mut result);
    result
}
pub fn days(days: &BTreeSet<usize>) -> String {
    let mut runs = Vec::new();
    let mut first = None;
    let mut last = 0;
    for &day in days {
        if first.is_none() {
            first = Some(day);
        } else if day != last+1 {
            runs.push(format!("{}-{}",first.unwrap(),last));
            first = Some(day);
        }
        last = day;
    }
    if let Some(first) = first {
        runs.push(format!("{}-{}",first,last));
    }
    runs.join(",")
}
pub fn winner(algorithm: &str, first: usize, second: usize, first_effect: usize) -> usize {
    match algorithm {
        "first-applicable" => first,"deny-overrides" | "permit-unless-deny" => if first_effect == 1 {
            first
        } else {
            second
        },_ => if first_effect == 0 {
            first
        } else {
            second
        }
    }
}
pub fn blocker(earlier: &[usize], standalone: &[usize]) -> Option<usize> {
    earlier.iter().copied().find(|&rule| standalone[rule] != 2)
}
