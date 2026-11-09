use crate::dataset::Row;
use std::{fs, io};

pub fn fixed(value: f64, decimals: usize) -> String {
    let s = format!("{:.*}", decimals, value);
    if s.starts_with('-') && s[1..].chars().all(|c| c == '0' || c == '.') { s[1..].into() } else { s }
}

pub fn real(value: f64) -> String { fixed(value, 4) }

pub fn ratio(a: usize, b: usize) -> String {
    if b == 0 { "-".into() } else { real(a as f64 / b as f64) }
}

pub fn prediction(score: f64) -> i32 { if score > 0.0 { 1 } else { -1 } }

pub fn auc(rows: &[Row], scores: &[f64]) -> String {
    let (mut positives, mut negatives, mut wins, mut ties) = (0usize, 0usize, 0usize, 0usize);
    for (a, row) in rows.iter().enumerate() {
        if row.label == 1 {
            positives += 1;
            for (b, other) in rows.iter().enumerate() {
                if other.label == -1 {
                    if scores[a] > scores[b] { wins += 1; }
                    if scores[a] == scores[b] { ties += 1; }
                }
            }
        } else { negatives += 1; }
    }
    ratio(2 * wins + ties, 2 * positives * negatives)
}

pub fn confusion(rows: &[Row], predicted: &[usize], classes: usize) -> Vec<Vec<usize>> {
    let mut table = vec![vec![0; classes]; classes];
    for (r, &p) in rows.iter().zip(predicted) { table[r.label as usize - 1][p - 1] += 1; }
    table
}

pub fn below(margins: &[f64], threshold: f64) -> usize {
    margins.iter().filter(|&&m| m <= threshold).count()
}

pub fn write(name: &str, lines: &[String]) -> io::Result<()> {
    fs::create_dir_all("output")?;
    fs::write(format!("output/{}", name), lines.join("\n") + "\n")
}
