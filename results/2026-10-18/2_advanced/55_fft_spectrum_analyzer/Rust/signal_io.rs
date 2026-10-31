use std::{fs, io};

pub struct Params {
    pub main_length: usize,
    pub main_window: String,
    pub threshold: f64,
    pub peak_count: usize,
    pub fundamental: f64,
    pub search: usize,
    pub welch_length: usize,
    pub welch_window: String,
    pub frame_length: usize,
    pub hop: usize,
    pub shade: i64,
    pub frame_window: String,
    pub onset: f64,
    pub pitch: [usize; 2],
    pub bandpass: [usize; 2],
    pub notch: [usize; 2],
    pub envelope: [usize; 2],
    pub zoom: [usize; 3],
    pub fir: Vec<f64>,
    pub lag: usize,
    pub bands: Vec<usize>,
    pub thirds: [i32; 2],
    pub block: usize,
}

pub struct Input {
    pub rate: usize,
    pub first: Vec<f64>,
    pub second: Vec<f64>,
    pub params: Params,
}

pub fn read() -> io::Result<Input> {
    let text = fs::read_to_string("input/signal.csv")?;
    let mut lines = text.lines();
    let rate = lines.next().unwrap().split(',').next().unwrap().parse().unwrap();
    let mut first = Vec::new();
    let mut second = Vec::new();
    for line in lines {
        let values: Vec<f64> = line.split(',').map(|s| s.parse().unwrap()).collect();
        first.push(values[0]);
        second.push(values[1]);
    }
    let text = fs::read_to_string("input/params.txt")?;
    let q: Vec<Vec<&str>> = text.lines().map(|s| s.split_whitespace().skip(1).collect()).collect();
    let integer = |i: usize, j: usize| q[i][j].parse::<usize>().unwrap();
    let decimal = |i: usize, j: usize| q[i][j].parse::<f64>().unwrap();
    let params = Params {
        main_length: integer(0, 0), main_window: q[1][0].into(), threshold: decimal(2, 0), peak_count: integer(3, 0), fundamental: decimal(4, 0), search: integer(4, 1),
        welch_length: integer(5, 0), welch_window: q[5][1].into(), frame_length: integer(6, 0), hop: integer(6, 1), shade: integer(6, 2) as i64, frame_window: q[6][3].into(),
        onset: decimal(7, 0), pitch: [integer(8, 0), integer(8, 1)], bandpass: [integer(9, 0), integer(9, 1)], notch: [integer(10, 0), integer(10, 1)],
        envelope: [integer(11, 0), integer(11, 1)], zoom: [integer(12, 0), integer(12, 1), integer(12, 2)], fir: q[13].iter().map(|s| s.parse().unwrap()).collect(),
        lag: integer(14, 0), bands: q[15].iter().map(|s| s.parse().unwrap()).collect(), thirds: [q[16][0].parse().unwrap(), q[16][1].parse().unwrap()], block: integer(17, 0),
    };
    Ok(Input { rate, first, second, params })
}
