use std::fs;
pub struct Variable {
    pub name: String,
    pub states: Vec<String>,
    pub parents: Vec<usize>,
    pub given: Option<Vec<Vec<f64>>>
}
pub struct Params {
    pub pseudocount: f64,
    pub minfill: bool,
    pub order: Vec<usize>,
    pub limit: usize,
    pub seed: i64,
    pub learned: Vec<bool>
}
pub struct Input {
    pub variables: Vec<Variable>,
    pub samples: Vec<Vec<usize>>,
    pub queries: Vec<String>,
    pub params: Params
}
pub fn read() -> Input {
    let input = fs::read_to_string("input/network.txt").unwrap();
    let lines: Vec<Vec<_>> = input.lines().filter(|l| !l.is_empty() && !l.starts_with('#')).map(|l| l.split_whitespace().collect()).collect();
    let mut variables = Vec::<Variable>::new();
    let mut i = 0;
    while i < lines.len() {
        let w = &lines[i];
        if w[0] == "VARIABLE" {
            variables.push(Variable {
                name: w[1].to_owned(),
                states: w[2..].iter().map(|s| (*s).to_owned()).collect(),
                parents: Vec::new(),
                given: None
            });
        } else if w[0] == "PARENTS" {
            let child = variables.iter().position(|v| v.name == w[1]).unwrap();
            variables[child].parents = w[2..].iter().map(|name| variables.iter().position(|v| v.name == *name).unwrap()).collect();
        } else {
            let variable = variables.iter().position(|v| v.name == w[1]).unwrap();
            let rows: usize = variables[variable].parents.iter().map(|&p| variables[p].states.len()).product();
            let values = (0..rows).map(|r| lines[i+r+1].iter().map(|s| s.parse().unwrap()).collect()).collect();
            variables[variable].given = Some(values);
            i += rows;
        }
        i += 1;
    }
    let input = fs::read_to_string("input/samples.csv").unwrap();
    let mut lines = input.lines();
    let header: Vec<_> = lines.next().unwrap().split(',').map(|name| variables.iter().position(|v| v.name == name).unwrap()).collect();
    let samples = lines.map(|line| {
        let mut states = vec![0; variables.len()];
        for (column, value) in line.split(',').enumerate() {
            let v = header[column];
            states[v] = variables[v].states.iter().position(|s| s == value).unwrap();
        }
        states
    }).collect();
    let input = fs::read_to_string("input/params.txt").unwrap();
    let lines: Vec<Vec<_>> = input.lines().map(|line| line.split_whitespace().collect()).collect();
    let params = Params {
        pseudocount: lines[0][1].parse().unwrap(),
        minfill: lines[1][1] == "MINFILL",
        order: lines[2][1..].iter().map(|name| variables.iter().position(|v| v.name == *name).unwrap()).collect(),
        limit: lines[3][1].parse().unwrap(),
        seed: lines[4][1].parse().unwrap(),
        learned: lines[5..].iter().map(|w| w[2] == "LEARNED").collect()
    };
    let queries = fs::read_to_string("input/queries.txt").unwrap().lines().map(str::to_owned).collect();
    Input {
        variables,
        samples,
        queries,
        params
    }
}
