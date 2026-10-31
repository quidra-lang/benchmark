pub fn real(value: f64, digits: usize) -> String {
    let s = format!("{:.*}", digits, value);
    if s.starts_with('-') && s[1..].bytes().all(|b| b == b'0' || b == b'.') { s[1..].to_owned() } else { s }
}

pub fn ratio(a: usize, b: usize) -> String {
    if b == 0 { return "-".to_owned(); }
    let q = (20000*a+b)/(2*b);
    format!("{}.{:04}", q/10000, q%10000)
}

pub fn prediction(scores: &[f64]) -> usize {
    let mut best = 0;
    for i in 1..scores.len() { if scores[i] > scores[best] { best = i; } }
    best
}

pub fn second(scores: &[f64], first: usize) -> usize {
    let mut best = if first == 0 { 1 } else { 0 };
    for i in 0..scores.len() { if i != first && scores[i] > scores[best] { best = i; } }
    best
}

pub fn confusion(actual: &[usize], predicted: &[usize], classes: usize) -> Vec<Vec<usize>> {
    let mut result = vec![vec![0; classes]; classes];
    for (&a, &p) in actual.iter().zip(predicted) { result[a][p] += 1; }
    result
}

pub fn class_values(confusion: &[Vec<usize>], class: usize) -> (usize, usize, String, String, String) {
    let support = confusion[class].iter().sum();
    let predicted = confusion.iter().map(|r| r[class]).sum();
    let correct = confusion[class][class];
    (support, predicted, ratio(correct, predicted), ratio(correct, support), ratio(2*correct, support+predicted))
}

pub fn maps(levels: &[Vec<usize>], width: usize, height: usize) -> Vec<String> {
    (0..height).map(|r| levels.iter().map(|m| m[r*width..(r+1)*width].iter()
        .map(|&v| (b'0'+v as u8) as char).collect::<String>()).collect::<Vec<_>>().join(" ")).collect()
}

pub fn image(pixels: &[u8], width: usize) -> Vec<String> {
    pixels.chunks(width).map(|r| r.iter().map(|&b| if b == b'1' { '#' } else { '.' }).collect()).collect()
}
