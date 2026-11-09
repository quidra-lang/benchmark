use std::fs;

pub struct Mesh {
    pub width: usize,
    pub height: usize,
    pub dx: f64,
    pub thickness: f64,
    pub codes: Vec<u8>,
}

impl Mesh {
    pub fn read() -> Self {
        let input = fs::read_to_string("input/plate.txt").unwrap();
        let mut lines = input.lines();
        let w: Vec<_> = lines.next().unwrap().split_whitespace().collect();
        Self { width: w[0].parse().unwrap(), height: w[1].parse().unwrap(),
            dx: w[2].parse().unwrap(), thickness: w[3].parse().unwrap(),
            codes: lines.flat_map(str::bytes).collect() }
    }

    pub fn neighbors(&self, p: usize) -> [Option<usize>; 4] {
        let (r, c) = (p / self.width, p % self.width);
        [if c > 0 { Some(p-1) } else { None },
         if c+1 < self.width { Some(p+1) } else { None },
         if r > 0 { Some(p-self.width) } else { None },
         if r+1 < self.height { Some(p+self.width) } else { None }]
    }

    pub fn segment(&self, edge: &str, start: usize, end: usize) -> Vec<(usize, usize)> {
        (start..=end).map(|i| match edge {
            "left" => (i*self.width, 0), "right" => (i*self.width+self.width-1, 1),
            "top" => (i, 2), _ => ((self.height-1)*self.width+i, 3),
        }).collect()
    }

    pub fn rectangle(&self, r1: usize, c1: usize, r2: usize, c2: usize) -> Vec<usize> {
        (r1..=r2).flat_map(|r| (c1..=c2).map(move |c| r*self.width+c)).collect()
    }

    pub fn cell(&self, p: usize) -> String { format!("{} {}", p/self.width, p%self.width) }
}

#[derive(Clone, Copy)]
pub struct Face {
    pub neighbor: Option<usize>,
    pub conductance: f64,
    pub outside: Option<f64>,
}

pub struct Plate {
    pub faces: Vec<[Face; 4]>,
    pub capacity: Vec<f64>,
    pub diagonal: Vec<f64>,
}
