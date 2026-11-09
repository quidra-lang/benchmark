use std::collections::BTreeMap;
use std::fs;

#[derive(Clone)]
pub struct Subject {
    pub id: usize,
    pub group: usize,
    pub time: i64,
    pub event: bool,
    pub age: i64,
    pub sex: u8,
    pub stage: i64,
}

pub struct Input {
    pub subjects: Vec<Subject>,
    pub groups: Vec<String>,
    pub params: BTreeMap<String, Vec<String>>,
}

impl Input {
    pub fn number(&self, name: &str) -> i64 { self.params[name][0].parse().unwrap() }
    pub fn numbers(&self, name: &str) -> Vec<i64> { self.params[name].iter().map(|v| v.parse().unwrap()).collect() }
}

pub fn read() -> Input {
    let params: BTreeMap<String, Vec<String>> = fs::read_to_string("input/params.txt").unwrap().lines().map(|line| {
        let mut parts = line.split(' ');
        (parts.next().unwrap().into(), parts.map(String::from).collect())
    }).collect();
    let groups = params["GROUPS"].clone();
    let mut subjects: Vec<_> = fs::read_to_string("input/subjects.csv").unwrap().lines().skip(1).map(|line| {
        let p: Vec<_> = line.split(',').collect();
        Subject { id: p[0].parse().unwrap(), group: groups.iter().position(|g| g == p[1]).unwrap(), time: p[2].parse().unwrap(), event: p[3] == "1", age: p[4].parse().unwrap(), sex: p[5].as_bytes()[0], stage: p[6].parse().unwrap() }
    }).collect();
    subjects.sort_by_key(|subject| subject.id);
    Input { subjects, groups, params }
}
