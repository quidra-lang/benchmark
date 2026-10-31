use std::{fs, io};

#[derive(Clone)]
pub struct Row {
    pub id: String,
    pub values: Vec<f64>,
    pub label: i32,
}

pub struct Params {
    pub rounds: usize,
    pub variants: Vec<String>,
    pub bins: usize,
    pub smoothing: f64,
    pub convergence: f64,
    pub clip: f64,
    pub folds: usize,
    pub margins: Vec<f64>,
    pub classes: usize,
    pub samme_rounds: usize,
    pub permutations: usize,
    pub permutation_seed: i64,
    pub noise_seed: i64,
    pub noise: Vec<usize>,
    pub sizes: Vec<usize>,
    pub shrinkage: Vec<f64>,
    pub bootstrap: usize,
    pub bootstrap_seed: i64,
}

pub struct Data {
    pub names: Vec<String>,
    pub train: Vec<Row>,
    pub test: Vec<Row>,
    pub multi_names: Vec<String>,
    pub multi_train: Vec<Row>,
    pub multi_test: Vec<Row>,
    pub params: Params,
}

fn parse_row(fields: &[&str], d: usize) -> Row {
    Row {
        id: fields[0].into(),
        values: fields[1..=d].iter().map(|s| s.parse().unwrap()).collect(),
        label: fields[d + 1].parse().unwrap(),
    }
}

fn read_binary(path: &str) -> io::Result<(Vec<String>, Vec<Row>)> {
    let text = fs::read_to_string(path)?;
    let mut lines = text.lines();
    let header: Vec<&str> = lines.next().unwrap().split(',').collect();
    let d = header.len() - 2;
    let names = header[1..=d].iter().map(|s| s.to_string()).collect();
    let rows = lines.map(|s| parse_row(&s.split(',').collect::<Vec<_>>(), d)).collect();
    Ok((names, rows))
}

pub fn read() -> io::Result<Data> {
    let (names, train) = read_binary("input/train.csv")?;
    let (_, test) = read_binary("input/test.csv")?;
    let content = fs::read_to_string("input/multiclass.csv")?;
    let mut lines = content.lines();
    let header: Vec<&str> = lines.next().unwrap().split(',').collect();
    let e = header.len() - 3;
    let multi_names = header[1..=e].iter().map(|s| s.to_string()).collect();
    let (mut multi_train, mut multi_test) = (Vec::new(), Vec::new());
    for line in lines {
        let fields: Vec<&str> = line.split(',').collect();
        let row = parse_row(&fields, e);
        if fields[e + 2] == "train" { multi_train.push(row); } else { multi_test.push(row); }
    }
    let text = fs::read_to_string("input/params.txt")?;
    let q: Vec<Vec<&str>> = text.lines().map(|s| s.split_whitespace().collect()).collect();
    let params = Params {
        rounds: q[0][1].parse().unwrap(), variants: q[1][1..].iter().map(|s| s.to_string()).collect(),
        bins: q[2][1].parse().unwrap(), smoothing: q[3][1].parse().unwrap(), convergence: q[4][1].parse().unwrap(),
        clip: q[5][1].parse().unwrap(), folds: q[6][1].parse().unwrap(), margins: q[7][1..].iter().map(|s| s.parse().unwrap()).collect(),
        classes: q[8][1].parse().unwrap(), samme_rounds: q[9][1].parse().unwrap(), permutations: q[10][1].parse().unwrap(),
        permutation_seed: q[10][2].parse().unwrap(), noise_seed: q[11][1].parse().unwrap(),
        noise: q[11][2..].iter().map(|s| s.parse().unwrap()).collect(), sizes: q[12][1..].iter().map(|s| s.parse().unwrap()).collect(),
        shrinkage: q[13][1..].iter().map(|s| s.parse().unwrap()).collect(), bootstrap: q[14][1].parse().unwrap(),
        bootstrap_seed: q[14][2].parse().unwrap(),
    };
    Ok(Data { names, train, test, multi_names, multi_train, multi_test, params })
}
