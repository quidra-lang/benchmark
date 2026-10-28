use std::fs;
use crate::dataset::Example;

pub fn sign(value: f64) -> i32 { if value > 0.0 { 1 } else { -1 } }
pub fn real(value: f64, digits: usize) -> String {
    let s = format!("{:.*}", digits, value);
    if s.starts_with('-') && s[1..].bytes().all(|b| b == b'0' || b == b'.') { s[1..].to_owned() } else { s }
}
pub fn ratio(a: usize, b: usize) -> String { if b == 0 { "-".to_owned() } else { real(a as f64/b as f64, 4) } }
pub fn folds(n: usize, k: usize, fold: usize) -> (Vec<usize>, Vec<usize>) {
    ((0..n).filter(|i| i%k != fold).collect(), (0..n).filter(|i| i%k == fold).collect())
}
pub fn correct(data: &[Example], values: &[f64]) -> usize {
    data.iter().zip(values).filter(|(e, v)| e.label == sign(**v)).count()
}
pub fn binary(data: &[Example], values: &[f64]) -> [usize; 4] {
    let mut counts = [0; 4];
    for (e, &v) in data.iter().zip(values) {
        counts[match (e.label, sign(v)) { (1, 1) => 0, (-1, 1) => 1, (-1, -1) => 2, _ => 3 }] += 1;
    }
    counts
}
pub fn auc(data: &[Example], values: &[f64]) -> f64 {
    let mut sum = 0.0;
    let mut count = 0;
    for (i, _) in data.iter().enumerate().filter(|(_, e)| e.label == 1) {
        for (j, _) in data.iter().enumerate().filter(|(_, e)| e.label == -1) {
            sum += if values[i] > values[j] { 1.0 } else if values[i] == values[j] { 0.5 } else { 0.0 };
            count += 1;
        }
    }
    sum/count as f64
}
pub fn confusion(actual: &[usize], predicted: &[usize]) -> [[usize; 3]; 3] {
    let mut matrix = [[0; 3]; 3];
    for (&a, &p) in actual.iter().zip(predicted) { matrix[a-1][p-1] += 1; }
    matrix
}
pub fn write(file: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", file), lines.join("\n")+"\n").unwrap();
}
