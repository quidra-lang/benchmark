use std::fs;

pub struct Image { pub width: usize, pub height: usize, pub pixels: Vec<i64> }
impl Image {
    pub fn read(file: &str) -> Self {
        let input = fs::read_to_string(file).unwrap();
        let mut words = input.split_whitespace(); words.next();
        let width = words.next().unwrap().parse().unwrap();
        let height = words.next().unwrap().parse().unwrap(); words.next();
        Self { width, height, pixels: words.map(|v| v.parse().unwrap()).collect() }
    }
    pub fn write(&self, file: &str) {
        let mut lines = vec!["P2".to_owned(), format!("{} {}", self.width, self.height), "255".to_owned()];
        for row in self.pixels.chunks(self.width) { lines.push(row.iter().map(i64::to_string).collect::<Vec<_>>().join(" ")); }
        write(file, &lines);
    }
}

pub struct Params {
    pub minimum: i64, pub maximum: i64, pub windows: [Vec<usize>; 3],
    pub texture_window: usize, pub texture_threshold: i64, pub uniqueness: i64, pub lr: i64,
    pub wta_cost: String, pub sgm_cost: String, pub sgm_window: usize, pub paths: usize,
    pub p1: i64, pub p2: i64, pub gamma: i64, pub speckle_size: usize, pub speckle_range: i64,
    pub votes: usize, pub object_range: i64, pub object_size: usize, pub focal: i64, pub baseline: i64,
    pub samples: Vec<(usize, usize)>,
}

pub fn params() -> Params {
    let mut p = Params { minimum: 0, maximum: 0, windows: [Vec::new(), Vec::new(), Vec::new()], texture_window: 0,
        texture_threshold: 0, uniqueness: 0, lr: 0, wta_cost: String::new(), sgm_cost: String::new(), sgm_window: 0, paths: 0,
        p1: 0, p2: 0, gamma: 0, speckle_size: 0, speckle_range: 0, votes: 0, object_range: 0, object_size: 0,
        focal: 0, baseline: 0, samples: Vec::new() };
    for line in fs::read_to_string("input/params.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        match w[0] {
            "disparity_min" => p.minimum = w[1].parse().unwrap(), "disparity_max" => p.maximum = w[1].parse().unwrap(),
            "sad_windows" => p.windows[0] = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
            "ssd_windows" => p.windows[1] = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
            "census_windows" => p.windows[2] = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
            "texture_window" => p.texture_window = w[1].parse().unwrap(), "texture_threshold" => p.texture_threshold = w[1].parse().unwrap(),
            "uniqueness" => p.uniqueness = w[1].parse().unwrap(), "lr_max_diff" => p.lr = w[1].parse().unwrap(),
            "wta_cost" => p.wta_cost = w[1].to_owned(), "sgm_cost" => p.sgm_cost = w[1].to_owned(),
            "sgm_window" => p.sgm_window = w[1].parse().unwrap(), "sgm_paths" => p.paths = w[1].parse().unwrap(),
            "p1" => p.p1 = w[1].parse().unwrap(), "p2" => p.p2 = w[1].parse().unwrap(), "p2_gamma" => p.gamma = w[1].parse().unwrap(),
            "speckle_size" => p.speckle_size = w[1].parse().unwrap(), "speckle_range" => p.speckle_range = w[1].parse().unwrap(),
            "fusion_min_votes" => p.votes = w[1].parse().unwrap(), "object_range" => p.object_range = w[1].parse().unwrap(),
            "object_min_size" => p.object_size = w[1].parse().unwrap(), "focal_length" => p.focal = w[1].parse().unwrap(), "baseline" => p.baseline = w[1].parse().unwrap(),
            "sample" => p.samples.push((w[1].parse().unwrap(), w[2].parse().unwrap())), _ => {}
        }
    }
    p
}

pub fn write(file: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}", file), lines.join("\n")+"\n").unwrap();
}
