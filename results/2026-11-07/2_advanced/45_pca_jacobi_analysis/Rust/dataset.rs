use std::{fs, io};

pub struct Row {
    pub id: String,
    pub values: Vec<Option<f64>>,
}

pub struct Params {
    pub missing: String,
    pub scaling: String,
    pub components: String,
    pub target: f64,
    pub repetitions: usize,
    pub seed: i64,
    pub t2_limit: f64,
    pub spe_limit: f64,
    pub cycles: usize,
    pub top: usize,
    pub scree_width: usize,
    pub biplot: (usize, usize),
    pub radius: usize,
    pub diagnostic: (usize, usize),
}

pub struct Dataset {
    pub names: Vec<String>,
    pub data: Vec<Row>,
    pub supplementary: Vec<Row>,
    pub params: Params,
}

fn read_rows(path: &str) -> io::Result<(Vec<String>, Vec<Row>)> {
    let content = fs::read_to_string(path)?;
    let mut lines = content.lines();
    let names = lines.next().unwrap().split(',').skip(1).map(str::to_owned).collect();
    let rows = lines.map(|line| {
        let mut fields = line.split(',');
        Row {
            id: fields.next().unwrap().to_owned(),
            values: fields.map(|s| if s == "NA" { None } else { Some(s.parse().unwrap()) }).collect(),
        }
    }).collect();
    Ok((names, rows))
}

pub fn read() -> io::Result<Dataset> {
    let (names, data) = read_rows("input/data.csv")?;
    let (_, supplementary) = read_rows("input/supplementary.csv")?;
    let text = fs::read_to_string("input/params.txt")?;
    let lines: Vec<Vec<&str>> = text.lines().map(|s| s.split_whitespace().collect()).collect();
    let params = Params {
        missing: lines[0][1].into(),
        scaling: lines[1][1].into(),
        components: lines[2][1].into(),
        target: lines[3][1].parse().unwrap(),
        repetitions: lines[4][1].parse().unwrap(),
        seed: lines[4][2].parse().unwrap(),
        t2_limit: lines[5][1].parse().unwrap(),
        spe_limit: lines[6][1].parse().unwrap(),
        cycles: lines[7][1].parse().unwrap(),
        top: lines[8][1].parse().unwrap(),
        scree_width: lines[9][1].parse().unwrap(),
        biplot: (lines[10][1].parse().unwrap(), lines[10][2].parse().unwrap()),
        radius: lines[11][1].parse().unwrap(),
        diagnostic: (lines[12][1].parse().unwrap(), lines[12][2].parse().unwrap()),
    };
    Ok(Dataset { names, data, supplementary, params })
}
