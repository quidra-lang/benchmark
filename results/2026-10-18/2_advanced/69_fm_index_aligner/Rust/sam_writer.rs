use std::fs;
use crate::sequence_io::Reference;

pub fn ratio(numerator: usize, denominator: usize) -> String {
    if denominator == 0 { "-".to_owned() } else { format!("{:.4}", numerator as f64/denominator as f64) }
}
pub fn header(references: &[Reference]) -> Vec<String> {
    let mut lines = vec!["@HD\tVN:1.6\tSO:unsorted".to_owned()];
    for reference in references { lines.push(format!("@SQ\tSN:{}\tLN:{}", reference.name, reference.sequence.len())); }
    lines.push("@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0".to_owned()); lines
}
pub fn record(fields: &[String]) -> String { fields.join("\t") }
pub fn write(file: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap(); fs::write(format!("output/{}", file), lines.join("\n")+"\n").unwrap();
}
