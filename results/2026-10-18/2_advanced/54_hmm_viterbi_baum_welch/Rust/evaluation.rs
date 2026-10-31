pub type Confusion = Vec<Vec<i64>>;

pub fn fraction(mut n: i64, mut d: i64) -> String {
    if d == 0 { return "-".into(); }
    if d < 0 { n = -n; d = -d; }
    let (mut a, mut b) = (n.abs(), d);
    while b != 0 { let remainder = a % b; a = b; b = remainder; }
    format!("{}/{}", n / a, d / a)
}

pub fn accumulate(table: &mut Confusion, truth: &[usize], predicted: &[usize]) {
    for (&a, &b) in truth.iter().zip(predicted) { table[a][b] += 1; }
}

pub fn metrics(table: &Confusion, states: &[char]) -> Vec<String> {
    let k = states.len();
    let width = table.iter().flat_map(|r| r.iter()).map(|c| c.to_string().len()).max().unwrap();
    let mut header = " ".to_owned();
    for &state in states { header += &format!(" {:>width$}", state, width = width); }
    let mut lines = vec![header];
    for i in 0..k {
        let mut line = states[i].to_string();
        for j in 0..k { line += &format!(" {:>width$}", table[i][j], width = width); }
        lines.push(line);
    }
    let rows: Vec<i64> = table.iter().map(|r| r.iter().sum()).collect();
    let columns: Vec<i64> = (0..k).map(|j| table.iter().map(|r| r[j]).sum()).collect();
    let total: i64 = rows.iter().sum();
    let correct: i64 = (0..k).map(|i| table[i][i]).sum();
    let product: i64 = rows.iter().zip(&columns).map(|(r, c)| r * c).sum();
    lines.push(format!("ACCURACY {}", fraction(correct, total)));
    lines.push(format!("KAPPA {}", fraction(total * correct - product, total * total - product)));
    for i in 0..k {
        lines.push(format!("STATE {} precision {} recall {} f1 {}", states[i], fraction(table[i][i], columns[i]), fraction(table[i][i], rows[i]), fraction(2 * table[i][i], columns[i] + rows[i])));
    }
    lines
}

pub fn runs(path: &[usize]) -> Vec<(usize, usize, usize)> {
    let mut result = Vec::new();
    let mut start = 0;
    for position in 1..=path.len() {
        if position == path.len() || path[position] != path[start] { result.push((start, position - 1, path[start])); start = position; }
    }
    result
}

pub fn overlap(a: (usize, usize), b: (usize, usize)) -> bool {
    a.0 <= b.1 && b.0 <= a.1
}

pub fn boundaries(path: &[usize]) -> Vec<usize> {
    (1..path.len()).filter(|&i| path[i - 1] != path[i]).collect()
}

pub fn matched(boundaries: &[usize], other: &[usize], tolerance: usize) -> usize {
    boundaries.iter().filter(|&&a| other.iter().any(|&b| a.abs_diff(b) <= tolerance)).count()
}
