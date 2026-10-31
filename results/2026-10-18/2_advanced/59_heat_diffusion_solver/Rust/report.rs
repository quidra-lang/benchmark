use std::fs;
use crate::mesh::Mesh;

pub fn real(x: f64, digits: usize) -> String {
    let value = format!("{:.*}", digits, x);
    if value.starts_with('-') && value[1..].bytes().all(|c| c == b'0' || c == b'.') { value[1..].to_owned() } else { value }
}

pub fn time(t: i64) -> String { format!("{}.{:03}", t/1000, t%1000) }

pub fn field(mesh: &Mesh, x: &[f64]) -> Vec<String> {
    x.chunks(mesh.width).map(|r| r.iter().map(|&v| real(v, 2)).collect::<Vec<_>>().join(" ")).collect()
}

pub fn hottest(x: &[f64]) -> usize {
    let mut best = 0;
    for p in 1..x.len() { if x[p] > x[best] { best = p; } }
    best
}

pub fn summary(mesh: &Mesh, x: &[f64]) -> String {
    let p = hottest(x);
    format!("max {} at {} min {} mean {}", real(x[p], 2), mesh.cell(p),
        real(x.iter().copied().fold(f64::INFINITY, f64::min), 2), real(x.iter().sum::<f64>() / x.len() as f64, 2))
}

pub fn isotherms(mesh: &Mesh, x: &[f64], bands: &[f64]) -> (String, Vec<String>) {
    let mut counts = vec![0; bands.len()+1];
    let hot = hottest(x);
    let cells: Vec<_> = x.iter().enumerate().map(|(p, &v)| {
        let digit = bands.iter().filter(|&&b| b <= v).count();
        counts[digit] += 1;
        if p == hot { b'*' } else { b'0' + digit as u8 }
    }).collect();
    (counts.iter().map(usize::to_string).collect::<Vec<_>>().join(" "),
        cells.chunks(mesh.width).map(|r| String::from_utf8(r.to_vec()).unwrap()).collect())
}

pub fn write(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", name), lines.join("\n") + "\n").unwrap();
}
