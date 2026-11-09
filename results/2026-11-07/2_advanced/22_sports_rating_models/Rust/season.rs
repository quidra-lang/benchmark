use std::collections::BTreeMap;
use std::{fs, io};
use crate::report::Fraction;

pub struct Team { pub code: String, pub name: String }
#[derive(Clone, Copy)]
pub struct Match { pub round: usize, pub home: usize, pub away: usize, pub home_score: i64, pub away_score: i64 }
impl Match {
    pub fn margin(self) -> i64 { self.home_score - self.away_score }
    pub fn result_twice(self) -> i64 { if self.home_score > self.away_score { 2 } else if self.home_score == self.away_score { 1 } else { 0 } }
    pub fn result(self) -> Fraction { Fraction::new(self.result_twice(), 2) }
    pub fn y(self) -> f64 { self.result_twice() as f64 / 2.0 }
}
pub struct Settings {
    pub win_points: i64,
    pub draw_points: i64,
    pub form_length: usize,
    pub close_margin: i64,
    pub exponent: f64,
    pub elo_k: i64,
    pub elo_home: i64,
    pub elo_initial: i64,
    pub grid_k: Vec<i64>,
    pub grid_home: Vec<i64>,
    pub bt_iterations: usize,
    pub od_iterations: usize,
    pub link_iterations: usize,
    pub holdout_round: usize,
    pub upsets: usize,
    pub calibration_bins: usize,
    pub simulations: usize,
    pub seed: i64,
    pub top_positions: usize,
    pub bottom_positions: usize,
}
pub fn matches_before(matches: &[Match], round: usize) -> Vec<Match> { matches.iter().copied().filter(|game| game.round < round).collect() }
pub fn load_season() -> io::Result<(Vec<Team>, Vec<Match>, Settings)> {
    let teams: Vec<_> = fs::read_to_string("input/teams.csv")?.lines().skip(1).map(|line| {
        let (code, name) = line.split_once(',').unwrap(); Team { code: code.to_owned(), name: name.to_owned() }
    }).collect();
    let indices: BTreeMap<_, _> = teams.iter().enumerate().map(|(index, team)| (team.code.as_str(), index)).collect();
    let mut matches: Vec<_> = fs::read_to_string("input/matches.csv")?.lines().skip(1).map(|line| {
        let words: Vec<_> = line.split(',').collect();
        Match { round: words[0].parse().unwrap(), home: indices[words[1]], away: indices[words[2]], home_score: words[3].parse().unwrap(), away_score: words[4].parse().unwrap() }
    }).collect();
    matches.sort_by_key(|game| game.round);
    let text = fs::read_to_string("input/params.txt")?;
    let values: BTreeMap<_, _> = text.lines().map(|line| { let mut words = line.split(' '); (words.next().unwrap(), words.collect::<Vec<_>>()) }).collect();
    let integer = |key: &str| values[key][0].parse::<i64>().unwrap();
    let list = |key: &str| values[key].iter().map(|word| word.parse().unwrap()).collect();
    let settings = Settings { win_points: integer("WIN_POINTS"), draw_points: integer("DRAW_POINTS"), form_length: integer("FORM_LENGTH") as usize,
        close_margin: integer("CLOSE_MARGIN"), exponent: values["PYTHAGOREAN_EXPONENT"][0].parse().unwrap(), elo_k: integer("ELO_K"), elo_home: integer("ELO_HOME"),
        elo_initial: integer("ELO_INITIAL"), grid_k: list("ELO_GRID_K"), grid_home: list("ELO_GRID_HOME"), bt_iterations: integer("BT_ITERATIONS") as usize,
        od_iterations: integer("OD_ITERATIONS") as usize, link_iterations: integer("LINK_ITERATIONS") as usize, holdout_round: integer("HOLDOUT_ROUND") as usize,
        upsets: integer("UPSETS") as usize, calibration_bins: integer("CALIBRATION_BINS") as usize, simulations: integer("SIMULATIONS") as usize,
        seed: integer("SIM_SEED"), top_positions: integer("TOP_POSITIONS") as usize, bottom_positions: integer("BOTTOM_POSITIONS") as usize };
    Ok((teams, matches, settings))
}
