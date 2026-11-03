use std::fs;
use crate::rules::{Fraction, Rule};

pub const RULES_HEADER: &str = "rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement";

pub fn fraction(value: Fraction) -> String {
    let numerator = value.numerator.abs(); let denominator = value.denominator; let scaled = 10000 * numerator / denominator;
    format!("{}{numerator}/{denominator}={}{}.{:04}",if value.numerator < 0 { "-" } else { "" },if value.numerator < 0 && scaled > 0 { "-" } else { "" },scaled / 10000,scaled % 10000)
}
pub fn percent(part: i64, whole: i64) -> String { let scaled = 10000 * part / whole; format!("{}.{:02}%",scaled / 100,scaled % 100) }
pub fn money(cents: i64) -> String { format!("{}.{:02}",cents / 100,cents % 100) }
pub fn arrow(rule: &Rule) -> String { format!("{} -> {}",rule.antecedent.join("+"),rule.consequent.join("+")) }
pub fn rules_csv(rules: &[Rule]) -> Vec<String> {
    let mut lines = vec![RULES_HEADER.into()];
    for rule in rules { lines.push(format!("{},{},{},{},{},{},{},{},{},{}",rule.rank,rule.antecedent.join("+"),rule.consequent.join("+"),rule.count,fraction(rule.support),fraction(rule.confidence),fraction(rule.lift),fraction(rule.leverage),rule.conviction.map_or_else(|| "INF".into(),fraction),fraction(rule.improvement))); }
    lines
}
pub fn write_report(name: &str, lines: Vec<String>) {
    fs::create_dir_all("output").unwrap(); fs::write(format!("output/{name}"),if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" }).unwrap();
}
