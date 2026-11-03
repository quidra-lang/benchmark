use std::{fs, io};

#[derive(Clone)]
pub struct Attribute {
    pub name: String,
    pub integer: bool,
    pub values: Vec<String>,
}

#[derive(Clone)]
pub struct Row {
    pub id: String,
    pub values: Vec<Option<i64>>,
    pub label: usize,
}

impl Row {
    pub fn missing_count(&self) -> usize { self.values.iter().filter(|value| value.is_none()).count() }
}

pub struct Settings {
    pub max_depth: usize,
    pub min_split: usize,
    pub min_leaf: usize,
    pub max_surrogates: usize,
    pub folds: usize,
    pub curve: Vec<usize>,
    pub bag_trees: usize,
    pub bag_seed: i64,
    pub repeats: usize,
    pub permutation_seed: i64,
}

pub struct Dataset {
    pub attributes: Vec<Attribute>,
    pub target: String,
    pub classes: Vec<String>,
    pub train: Vec<Row>,
    pub validation: Vec<Row>,
    pub test: Vec<Row>,
    pub settings: Settings,
}

pub fn read_lines(path: &str) -> io::Result<Vec<String>> {
    Ok(fs::read_to_string(path)?.lines().map(str::to_owned).collect())
}

fn read_rows(path: &str, attributes: &[Attribute], classes: &[String]) -> io::Result<Vec<Row>> {
    let mut rows = Vec::new();
    for line in read_lines(path)?.into_iter().skip(1) {
        let fields: Vec<_> = line.split(',').collect();
        let values = attributes.iter().enumerate().map(|(index, attribute)| {
            let text = fields[index + 1];
            if text == "?" { None }
            else if attribute.integer { Some(text.parse().unwrap()) }
            else { Some(attribute.values.iter().position(|value| value == text).unwrap() as i64) }
        }).collect();
        let label = classes.iter().position(|name| name == fields[fields.len() - 1]).unwrap();
        rows.push(Row { id: fields[0].to_owned(), values, label });
    }
    Ok(rows)
}

pub fn load_dataset(directory: &str) -> io::Result<Dataset> {
    let mut attributes = Vec::new();
    let mut target = String::new();
    let mut classes = Vec::new();
    for line in read_lines(&format!("{directory}/schema.txt"))? {
        let fields: Vec<_> = line.split(' ').collect();
        if fields[0] == "ATTRIBUTE" {
            attributes.push(Attribute { name: fields[1].to_owned(), integer: fields[2] == "INT",
                values: fields[3..].iter().map(|value| (*value).to_owned()).collect() });
        } else {
            target = fields[1].to_owned();
            classes = fields[2..].iter().map(|value| (*value).to_owned()).collect();
        }
    }
    let parameters: Vec<Vec<i64>> = read_lines(&format!("{directory}/params.txt"))?.iter()
        .map(|line| line.split(' ').skip(1).map(|value| value.parse().unwrap()).collect()).collect();
    let settings = Settings {
        max_depth: parameters[0][0] as usize, min_split: parameters[1][0] as usize,
        min_leaf: parameters[2][0] as usize, max_surrogates: parameters[3][0] as usize,
        folds: parameters[4][0] as usize, curve: parameters[5].iter().map(|&value| value as usize).collect(),
        bag_trees: parameters[6][0] as usize, bag_seed: parameters[7][0],
        repeats: parameters[8][0] as usize, permutation_seed: parameters[9][0],
    };
    let train = read_rows(&format!("{directory}/train.csv"), &attributes, &classes)?;
    let validation = read_rows(&format!("{directory}/validation.csv"), &attributes, &classes)?;
    let test = read_rows(&format!("{directory}/test.csv"), &attributes, &classes)?;
    Ok(Dataset { attributes, target, classes, train, validation, test, settings })
}
