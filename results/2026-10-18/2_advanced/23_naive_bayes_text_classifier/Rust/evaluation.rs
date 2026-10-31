pub fn real_text(value: f64) -> String {
    let text = format!("{value:.4}");
    if text == "-0.0000" { "0.0000".to_owned() } else { text }
}
pub fn rounded(value: f64) -> i64 { (value * 10000.0).round() as i64 }
pub fn proportion_text(numerator: i64, denominator: i64) -> String { format!("{numerator}/{denominator} {}", real_text(numerator as f64 / denominator as f64)) }
pub fn fraction_text(numerator: i64, denominator: i64) -> String {
    if denominator == 0 { return "- -".to_owned(); }
    let (mut a, mut b) = (numerator.abs(), denominator);
    while b != 0 { (a, b) = (b, a % b); }
    proportion_text(numerator / a, denominator / a)
}
pub struct Evaluation { pub matrix: Vec<Vec<i64>>, pub total: i64, pub correct: i64, pub micro_f1: f64, pub macro_f1: f64 }
impl Evaluation {
    pub fn new(class_count: usize, truths: &[usize], predictions: &[usize]) -> Self {
        let mut matrix = vec![vec![0; class_count]; class_count];
        for (&truth, &predicted) in truths.iter().zip(predictions) { matrix[truth][predicted] += 1; }
        let total = truths.len() as i64;
        let correct = (0..class_count).map(|label| matrix[label][label]).sum();
        let mut result = Self { matrix, total, correct, micro_f1: correct as f64 / total as f64, macro_f1: 0.0 };
        let mut sum = 0.0;
        let mut scored = 0;
        for label in 0..class_count {
            let denominator = result.predicted_count(label) + result.support(label);
            if denominator > 0 { sum += (2 * result.matrix[label][label]) as f64 / denominator as f64; scored += 1; }
        }
        result.macro_f1 = sum / scored as f64;
        result
    }
    pub fn support(&self, label: usize) -> i64 { self.matrix[label].iter().sum() }
    pub fn predicted_count(&self, label: usize) -> i64 { self.matrix.iter().map(|row| row[label]).sum() }
    pub fn fields(&self) -> String { format!("{},{},{}", self.correct, real_text(self.micro_f1), real_text(self.macro_f1)) }
    pub fn lines(&self, names: &[String]) -> Vec<String> {
        let mut lines = vec![format!("true\\predicted {}", names.join(" "))];
        for (label, name) in names.iter().enumerate() { lines.push(format!("{} {}", name, self.matrix[label].iter().map(ToString::to_string).collect::<Vec<_>>().join(" "))); }
        for (label, name) in names.iter().enumerate() {
            let hits = self.matrix[label][label];
            let predicted = self.predicted_count(label);
            let support = self.support(label);
            lines.push(format!("class {name} precision {} recall {} f1 {} support {support}", fraction_text(hits, predicted), fraction_text(hits, support), fraction_text(2 * hits, predicted + support)));
        }
        lines.push(format!("micro_f1 {} macro_f1 {}", real_text(self.micro_f1), real_text(self.macro_f1)));
        lines
    }
}
