use crate::day_rules::{DAY, DaySpec, POS_INFINITY};
use crate::tz_parser::Until;

pub struct Rule {
    pub number: usize, pub fields: Vec<String>, pub name: String,
    pub from_year: i64, pub to_year: i64, pub month: usize, pub day: DaySpec,
    pub at: i64, pub at_type: u8, pub save: i64, pub letter: String,
}
pub struct RuleInstance { pub rule: usize, pub nominal: i64 }
pub struct LineRun { pub last_pre_start: Option<usize>, pub applied: Vec<(i64, usize)>, pub end: i64 }
pub fn instance_sequence(rules: &[Rule], indices: &[usize]) -> Vec<RuleInstance> {
    let mut instances = Vec::new();
    for &index in indices {
        let rule = &rules[index];
        for year in rule.from_year..=rule.to_year { instances.push(RuleInstance { rule: index, nominal: rule.day.value(year, rule.month) * DAY + rule.at }); }
    }
    instances.sort_by_key(|instance| (instance.nominal, rules[instance.rule].number));
    instances
}
pub fn adjustment(kind: u8, stdoff: i64, save: i64) -> i64 { match kind { b'u' => 0, b's' => stdoff, _ => stdoff + save } }
pub fn run_instances(instances: &[RuleInstance], rules: &[Rule], stdoff: i64, start: i64, until: Option<&Until>) -> LineRun {
    let mut run = LineRun { last_pre_start: None, applied: Vec::new(), end: POS_INFINITY };
    let mut save = 0;
    for instance in instances {
        let rule = &rules[instance.rule];
        let time = instance.nominal - adjustment(rule.at_type, stdoff, save);
        if let Some(until) = until { if time >= until.value - adjustment(until.time_type, stdoff, save) { break; } }
        if time <= start { run.last_pre_start = Some(instance.rule); } else { run.applied.push((time, instance.rule)); }
        save = rule.save;
    }
    if let Some(until) = until { run.end = until.value - adjustment(until.time_type, stdoff, save); }
    run
}
pub fn abbreviation(format: &str, save: i64, letter: &str) -> String {
    if let Some((standard, daylight)) = format.split_once('/') { if save == 0 { standard.to_owned() } else { daylight.to_owned() } }
    else { format.replace("%s", letter) }
}
