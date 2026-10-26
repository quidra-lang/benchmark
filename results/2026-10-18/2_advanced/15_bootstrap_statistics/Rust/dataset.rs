use std::{fs, io};

pub struct Group { pub name: String, pub values: Vec<i64> }
pub struct Paired { pub before: Vec<i64>, pub after: Vec<i64>, pub differences: Vec<i64> }
pub struct Settings {
    pub seed: i64,
    pub bootstrap: usize,
    pub permutations: usize,
    pub confidence: usize,
    pub pilot: usize,
    pub power_sims: usize,
    pub power_perms: usize,
    pub bins: usize,
}
pub struct Dataset { pub groups: Vec<Group>, pub paired: Paired, pub settings: Settings, pub pairs: Vec<(usize, usize)> }

pub fn hundredths(text: &str) -> i64 {
    let (whole, fraction) = text.split_once('.').unwrap_or((text, ""));
    let padded = format!("{fraction:0<2}");
    whole.parse::<i64>().unwrap() * 100 + padded.parse::<i64>().unwrap()
}
fn read_lines(path: &str) -> io::Result<Vec<String>> { Ok(fs::read_to_string(path)?.lines().map(str::to_owned).collect()) }

pub fn load_dataset(folder: &str) -> io::Result<Dataset> {
    let mut groups: Vec<Group> = Vec::new();
    for line in read_lines(&format!("{folder}/samples.csv"))?.iter().skip(1) {
        let fields: Vec<_> = line.split(',').collect();
        let index = groups.iter().position(|group| group.name == fields[0]).unwrap_or_else(|| {
            groups.push(Group { name: fields[0].to_owned(), values: Vec::new() }); groups.len() - 1
        });
        groups[index].values.push(hundredths(fields[1]));
    }
    let mut before = Vec::new();
    let mut after = Vec::new();
    for line in read_lines(&format!("{folder}/paired.csv"))?.iter().skip(1) {
        let fields: Vec<_> = line.split(',').collect();
        before.push(hundredths(fields[1]));
        after.push(hundredths(fields[2]));
    }
    let differences = before.iter().zip(&after).map(|(first, second)| second - first).collect();
    let lines = read_lines(&format!("{folder}/params.txt"))?;
    let entries: Vec<Vec<i64>> = lines[..7].iter().map(|line| line.split(' ').skip(1).map(|value| value.parse().unwrap()).collect()).collect();
    let settings = Settings { seed: entries[0][0], bootstrap: entries[1][0] as usize, permutations: entries[2][0] as usize,
        confidence: entries[3][0] as usize, pilot: entries[4][0] as usize, power_sims: entries[5][0] as usize,
        power_perms: entries[5][1] as usize, bins: entries[6][0] as usize };
    let pairs = lines[7..].iter().map(|line| { let fields: Vec<_> = line.split(' ').collect();
        (groups.iter().position(|group| group.name == fields[1]).unwrap(), groups.iter().position(|group| group.name == fields[2]).unwrap()) }).collect();
    Ok(Dataset { groups, paired: Paired { before, after, differences }, settings, pairs })
}
