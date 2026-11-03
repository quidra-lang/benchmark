use std::{fs, io};

pub struct Station {
    pub code: String,
    pub x: i64,
    pub y: i64,
    pub elevation: i64,
}

pub struct Waveform {
    pub start: i64,
    pub samples: Vec<i64>,
}

pub struct Params {
    pub sta: usize,
    pub lta: usize,
    pub on: (i64, i64),
    pub off: (i64, i64),
    pub duration: usize,
    pub noise: i64,
    pub amplitude: usize,
    pub clip: i64,
    pub window: i64,
    pub minimum: usize,
    pub velocity: f64,
    pub grid: [[i64; 3]; 3],
    pub residual: f64,
    pub quality: [[f64; 3]; 2],
    pub cluster: (f64, f64),
    pub local: [f64; 3],
    pub duration_mag: [f64; 3],
    pub area: [i64; 4],
    pub map_size: (usize, usize),
    pub section: (i64, usize),
    pub timeline: (i64, usize, i64, i64, usize),
}

pub struct Data {
    pub stations: Vec<Station>,
    pub waves: Vec<Waveform>,
    pub params: Params,
}

pub fn read() -> io::Result<Data> {
    let stations: Vec<Station> = fs::read_to_string("input/stations.csv")?.lines().skip(1).map(|l| {
        let v: Vec<&str> = l.split(',').collect();
        Station { code: v[0].into(), x: v[1].parse().unwrap(), y: v[2].parse().unwrap(), elevation: v[3].parse().unwrap() }
    }).collect();
    let wave_text = fs::read_to_string("input/waveforms.txt")?;
    let mut words = wave_text.split_whitespace();
    let mut waves = Vec::new();
    for _ in &stations {
        words.next();
        words.next();
        let start = words.next().unwrap().parse().unwrap();
        let count: usize = words.next().unwrap().parse().unwrap();
        let samples = (0..count).map(|_| words.next().unwrap().parse().unwrap()).collect();
        waves.push(Waveform { start, samples });
    }
    let text = fs::read_to_string("input/params.txt")?;
    let v: Vec<Vec<&str>> = text.lines().map(|s| s.split_whitespace().skip(1).collect()).collect();
    let integer = |i: usize, j: usize| v[i][j].parse::<i64>().unwrap();
    let real = |i: usize, j: usize| v[i][j].parse::<f64>().unwrap();
    let triple = |i: usize| [real(i, 0), real(i, 1), real(i, 2)];
    let params = Params {
        sta: integer(0, 0) as usize, lta: integer(1, 0) as usize, on: (integer(2, 0), integer(2, 1)), off: (integer(3, 0), integer(3, 1)),
        duration: integer(4, 0) as usize, noise: integer(5, 0), amplitude: integer(6, 0) as usize, clip: integer(7, 0),
        window: integer(8, 0), minimum: integer(9, 0) as usize, velocity: real(10, 0),
        grid: [[integer(11, 0), integer(11, 1), integer(11, 2)], [integer(12, 0), integer(12, 1), integer(12, 2)], [integer(13, 0), integer(13, 1), integer(13, 2)]],
        residual: real(14, 0), quality: [triple(15), triple(16)], cluster: (real(17, 0), real(17, 1)),
        local: triple(18), duration_mag: triple(19), area: [integer(20, 0), integer(20, 1), integer(20, 2), integer(20, 3)],
        map_size: (integer(21, 0) as usize, integer(21, 1) as usize), section: (integer(22, 0), integer(22, 1) as usize),
        timeline: (integer(23, 0), integer(23, 1) as usize, integer(23, 2), integer(23, 3), integer(23, 4) as usize),
    };
    Ok(Data { stations, waves, params })
}
