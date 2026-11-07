use std::collections::{BTreeMap, BTreeSet};
use std::fs;

#[derive(Clone)]
pub struct Row {
    pub id: i64,
    pub values: Vec<f64>,
    pub class: usize,
}

pub struct Input {
    pub features: Vec<String>,
    pub classes: Vec<String>,
    pub train: Vec<Row>,
    pub test: Vec<Row>,
    pub costs: Vec<Vec<f64>>,
    pub params: BTreeMap<String, Vec<String>>,
    pub subsets: Vec<(String, Vec<usize>)>,
    pub pairs: Vec<[usize; 2]>,
}

fn rows(text: &str, classes: &[String]) -> Vec<Row> {
    text.lines().skip(1).map(|line| {
        let fields: Vec<_> = line.split(',').collect();
        Row { id: fields[0].parse().unwrap(), values: fields[1..fields.len() - 1].iter().map(|value| value.parse().unwrap()).collect(), class: classes.binary_search(&fields.last().unwrap().to_string()).unwrap() }
    }).collect()
}

pub fn read() -> Input {
    let train_text = fs::read_to_string("input/train.csv").unwrap();
    let fields: Vec<_> = train_text.lines().next().unwrap().split(',').collect();
    let features: Vec<_> = fields[1..fields.len() - 1].iter().map(|field| field.to_string()).collect();
    let classes: Vec<_> = train_text.lines().skip(1).map(|line| line.rsplit(',').next().unwrap().to_string()).collect::<BTreeSet<_>>().into_iter().collect();
    let train = rows(&train_text, &classes);
    let test = rows(&fs::read_to_string("input/test.csv").unwrap(), &classes);
    let cost_text = fs::read_to_string("input/costs.csv").unwrap();
    let names: Vec<_> = cost_text.lines().next().unwrap().split(',').skip(1).collect();
    let mut costs = vec![vec![0.0; classes.len()]; classes.len()];
    for line in cost_text.lines().skip(1) {
        let fields: Vec<_> = line.split(',').collect();
        let actual = classes.binary_search(&fields[0].to_string()).unwrap();
        for (i, &name) in names.iter().enumerate() { costs[actual][classes.binary_search(&name.to_string()).unwrap()] = fields[i + 1].parse().unwrap(); }
    }
    let mut params = BTreeMap::new();
    let mut subsets = Vec::new();
    let mut pairs = Vec::new();
    for line in fs::read_to_string("input/params.txt").unwrap().lines() {
        let fields: Vec<_> = line.split(' ').collect();
        let feature = |name: &str| features.iter().position(|f| f == name).unwrap();
        match fields[0] {
            "SUBSET" => subsets.push((fields[1].into(), fields[2..].iter().map(|name| feature(name)).collect())),
            "PAIR" => pairs.push([feature(fields[1]), feature(fields[2])]),
            _ => { params.insert(fields[0].into(), fields[1..].iter().map(|value| value.to_string()).collect()); }
        }
    }
    Input { features, classes, train, test, costs, params, subsets, pairs }
}
