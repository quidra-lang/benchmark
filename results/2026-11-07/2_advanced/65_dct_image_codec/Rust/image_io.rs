use std::fs;
use crate::entropy::Table;

#[derive(Clone)]
pub struct Image { pub width: usize, pub height: usize, pub pixels: Vec<[i64; 3]> }

impl Image {
    pub fn read() -> Self {
        let input = fs::read_to_string("input/image.ppm").unwrap();
        let mut w = input.split_whitespace(); w.next();
        let width = w.next().unwrap().parse().unwrap();
        let height = w.next().unwrap().parse().unwrap(); w.next();
        let values: Vec<i64> = w.map(|v| v.parse().unwrap()).collect();
        Self { width, height, pixels: values.chunks(3).map(|v| [v[0], v[1], v[2]]).collect() }
    }
    pub fn write(&self, name: &str) {
        let mut lines = vec!["P3".to_owned(), format!("{} {}", self.width, self.height), "255".to_owned()];
        for row in self.pixels.chunks(self.width) {
            lines.push(row.iter().flat_map(|p| p.iter()).map(i64::to_string).collect::<Vec<_>>().join(" "));
        }
        write(name, &lines);
    }
}

pub struct Params { pub qualities: Vec<usize>, pub sampling: String, pub restart: usize, pub optimized: bool, pub target: usize, pub generations: usize, pub truncate: Vec<usize> }
pub struct Tables { pub dct: [[i64; 8]; 8], pub basic: [[i64; 64]; 2], pub huffman: Vec<Table> }

pub fn params() -> Params {
    let mut p = Params { qualities: Vec::new(), sampling: String::new(), restart: 0, optimized: false, target: 0, generations: 0, truncate: Vec::new() };
    for line in fs::read_to_string("input/params.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        match w[0] {
            "qualities" => p.qualities = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
            "sampling" => p.sampling = w[1].to_owned(), "restart_interval" => p.restart = w[1].parse().unwrap(),
            "huffman" => p.optimized = w[1] == "optimized", "target_bytes" => p.target = w[1].parse().unwrap(),
            "generations" => p.generations = w[1].parse().unwrap(),
            _ => p.truncate = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
        }
    }
    p
}

pub fn tables() -> Tables {
    let input = fs::read_to_string("input/tables.txt").unwrap();
    let lines: Vec<_> = input.lines().collect();
    let mut dct = [[0; 8]; 8];
    for u in 0..8 { for (x, v) in lines[1+u].split_whitespace().enumerate() { dct[u][x] = v.parse().unwrap(); } }
    let mut basic = [[0; 64]; 2];
    for t in 0..2 { for u in 0..8 { for (v, value) in lines[10+9*t+u].split_whitespace().enumerate() { basic[t][u*8+v] = value.parse().unwrap(); } } }
    let mut huffman = Vec::new();
    for t in 0..4 {
        let mut counts = [0; 16];
        for (i, value) in lines[28+3*t].split_whitespace().enumerate() { counts[i] = value.parse().unwrap(); }
        let symbols = lines[29+3*t].split_whitespace().map(|v| v.parse().unwrap()).collect();
        huffman.push(Table::new(counts, symbols));
    }
    Tables { dct, basic, huffman }
}

pub fn read_hex() -> Vec<u8> {
    let input: String = fs::read_to_string("input/stream.hex").unwrap().lines().collect();
    (0..input.len()).step_by(2).map(|i| u8::from_str_radix(&input[i..i+2], 16).unwrap()).collect()
}
pub fn write_hex(name: &str, bytes: &[u8]) {
    let lines: Vec<_> = bytes.chunks(32).map(|chunk| chunk.iter().map(|b| format!("{:02x}", b)).collect()).collect();
    write(name, &lines);
}
pub fn write(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", name), lines.join("\n")+"\n").unwrap();
}
