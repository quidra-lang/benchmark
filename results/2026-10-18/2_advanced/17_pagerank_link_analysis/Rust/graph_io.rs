use std::{fs, io};

#[derive(Clone)]
pub struct Page {
    pub ident: i32,
    pub host: String,
    pub title: String,
    pub words: Vec<String>,
}

pub struct LinkRecord {
    pub line: usize,
    pub source: i32,
    pub target: i32,
}

pub struct Query {
    pub number: usize,
    pub words: Vec<String>,
    pub seeds: Vec<i32>,
}

pub struct Settings {
    pub damping: f64,
    pub iterations: usize,
    pub tolerance: f64,
    pub sweep: Vec<f64>,
    pub trusted: Vec<i32>,
    pub spam_top: usize,
    pub spam_threshold: f64,
    pub hits_iterations: usize,
    pub top_k: usize,
    pub root_limit: usize,
    pub neighbor_limit: usize,
}

fn read_lines(path: &str) -> io::Result<Vec<String>> {
    Ok(fs::read_to_string(path)?.lines().map(str::to_owned).collect())
}

pub fn read_pages(path: &str) -> io::Result<Vec<Page>> {
    Ok(read_lines(path)?.iter().skip(1).map(|line| {
        let fields: Vec<_> = line.split(',').collect();
        Page {
            ident: fields[0].parse().unwrap(),
            host: fields[1].to_owned(),
            title: fields[2].to_owned(),
            words: fields[2].split(' ').map(str::to_owned).collect(),
        }
    }).collect())
}

pub fn read_links(path: &str) -> io::Result<Vec<LinkRecord>> {
    Ok(read_lines(path)?.iter().skip(1).enumerate().map(|(number, line)| {
        let fields: Vec<_> = line.split(',').collect();
        LinkRecord { line: number + 2, source: fields[0].parse().unwrap(), target: fields[1].parse().unwrap() }
    }).collect())
}

pub fn read_queries(path: &str) -> io::Result<Vec<Query>> {
    Ok(read_lines(path)?.iter().enumerate().map(|(number, line)| {
        let (words, seeds) = line.split_once(" | ").unwrap();
        Query {
            number: number + 1,
            words: words.split(' ').map(str::to_owned).collect(),
            seeds: seeds.split(' ').map(|word| word.parse().unwrap()).collect(),
        }
    }).collect())
}

pub fn read_settings(path: &str) -> io::Result<Settings> {
    let entries: Vec<Vec<String>> = read_lines(path)?.iter()
        .map(|line| line.split(' ').skip(1).map(str::to_owned).collect()).collect();
    let integer = |index: usize| entries[index][0].parse::<usize>().unwrap();
    Ok(Settings {
        damping: entries[0][0].parse().unwrap(),
        iterations: integer(1), tolerance: entries[2][0].parse().unwrap(),
        sweep: entries[3].iter().map(|word| word.parse().unwrap()).collect(),
        trusted: entries[4].iter().map(|word| word.parse().unwrap()).collect(),
        spam_top: integer(5), spam_threshold: entries[6][0].parse().unwrap(),
        hits_iterations: integer(7), top_k: integer(8), root_limit: integer(9), neighbor_limit: integer(10),
    })
}
