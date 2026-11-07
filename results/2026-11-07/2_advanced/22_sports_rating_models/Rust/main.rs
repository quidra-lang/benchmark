mod season;
mod elo;
mod linear_models;
mod iterative_models;
mod evaluation;
mod report;

use std::collections::BTreeMap;
use std::{fs, io};
use season::{Match, Settings, Team, load_season, matches_before};
use elo::{EloRun, expected_score, run_elo};
use linear_models::{colley_ratings, massey_ratings};
use iterative_models::{bradley_terry, offense_defense};
use evaluation::{brier_score, correctness_twice, fit_link, kendall_tau, log_loss, sigma, spearman_rho};
use report::{Fraction, decimal_value, fixed, write_lines};

const RATING_MODELS: [&str; 6] = ["elo", "colley", "massey", "bt", "od", "winpct"];
const COMPARISON_MODELS: [&str; 9] = ["standings", "elo", "colley", "massey", "bt", "od", "winpct", "rpi", "pythag"];
const LINK_MODELS: [&str; 4] = ["colley", "massey", "od", "winpct"];
const PREDICTION_MODELS: [&str; 8] = ["base", "elo", "colley", "massey", "bt", "od", "winpct", "ensemble"];
const STANDINGS_HEADER: &str = "pos,team,name,played,won,drawn,lost,scored,conceded,diff,points,home,away,form,streak,close,longest_win,longest_unbeaten,winpct,sos,sos2,rpi,pythag,luck";
const RATINGS_HEADER: &str = "team,elo,elo_rank,colley,colley_rank,massey,massey_rank,bt,bt_rank,offense,defense,od,od_rank,winpct,winpct_rank,consensus,best_rank,worst_rank";
const HISTORY_HEADER: &str = "round,team,elo,change,elo_rank,points,position";
const PROJECTION_HEADER: &str = "projected,team,points_now,position_now,remaining_opponent_elo,expected_points,title,top,bottom,final_points,final_position";
fn sequential_sum(values: impl IntoIterator<Item = f64>) -> f64 { let mut total = 0.0; for value in values { total += value; } total }
fn mean(values: &[f64]) -> f64 { sequential_sum(values.iter().copied()) / values.len() as f64 }
fn competition_ranks(values: &[Fraction]) -> Vec<usize> { values.iter().map(|value| 1 + values.iter().filter(|&other| other > value).count()).collect() }
fn rounded_values(values: &[f64], places: usize) -> Vec<Fraction> { values.iter().map(|&value| Fraction::integer(decimal_value(value, places))).collect() }
fn join_parts(parts: Vec<Vec<String>>) -> Vec<String> {
    let mut lines = Vec::new();
    for part in parts { if !lines.is_empty() { lines.push(String::new()); } lines.extend(part); }
    lines
}
struct Appearance { game: Match, home: bool, opponent: usize, scored: i64, conceded: i64, letter: u8 }
fn appearances_of(team: usize, matches: &[Match]) -> Vec<Appearance> {
    matches.iter().filter(|game| game.home == team || game.away == team).map(|&game| {
        let home = game.home == team;
        let (scored, conceded, opponent) = if home { (game.home_score, game.away_score, game.away) } else { (game.away_score, game.home_score, game.home) };
        Appearance { game, home, opponent, scored, conceded, letter: if scored > conceded { b'W' } else if scored == conceded { b'D' } else { b'L' } }
    }).collect()
}
fn record_text<'a>(appearances: impl IntoIterator<Item = &'a Appearance>) -> String {
    let (mut won, mut drawn, mut lost) = (0, 0, 0);
    for item in appearances { match item.letter { b'W' => won += 1, b'D' => drawn += 1, _ => lost += 1 } }
    format!("{won}-{drawn}-{lost}")
}
#[derive(Clone, Default)]
struct Record { played: i64, won: i64, drawn: i64, lost: i64, scored: i64, conceded: i64, points: i64 }
impl Record {
    fn add(&mut self, scored: i64, conceded: i64, settings: &Settings) {
        self.played += 1; self.scored += scored; self.conceded += conceded;
        if scored > conceded { self.won += 1; self.points += settings.win_points; }
        else if scored == conceded { self.drawn += 1; self.points += settings.draw_points; }
        else { self.lost += 1; }
    }
    fn difference(&self) -> i64 { self.scored - self.conceded }
    fn win_percentage(&self) -> Fraction { Fraction::new(2 * self.won + self.drawn, 2 * self.played) }
}
fn team_records(count: usize, matches: &[Match], settings: &Settings) -> Vec<Record> {
    let mut records = vec![Record::default(); count];
    for game in matches { records[game.home].add(game.home_score, game.away_score, settings); records[game.away].add(game.away_score, game.home_score, settings); }
    records
}
struct Standings { records: Vec<Record>, h2h_points: Vec<i64>, h2h_difference: Vec<i64>, order: Vec<usize>, positions: Vec<usize> }
impl Standings {
    fn new(teams: &[Team], matches: &[Match], settings: &Settings) -> Self {
        let count = teams.len();
        let records = team_records(count, matches, settings);
        let mut groups: BTreeMap<i64, Vec<usize>> = BTreeMap::new();
        for (team, record) in records.iter().enumerate() { groups.entry(record.points).or_default().push(team); }
        let mut h2h_points = vec![0; count];
        let mut h2h_difference = vec![0; count];
        for members in groups.values() {
            let inner: Vec<_> = matches.iter().copied().filter(|game| members.contains(&game.home) && members.contains(&game.away)).collect();
            let inner_records = team_records(count, &inner, settings);
            for &team in members { h2h_points[team] = inner_records[team].points; h2h_difference[team] = inner_records[team].difference(); }
        }
        let mut order: Vec<_> = (0..count).collect();
        order.sort_by_key(|&team| (-records[team].points, -h2h_points[team], -h2h_difference[team], -records[team].difference(), -records[team].scored, teams[team].code.as_str()));
        let mut positions = vec![0; count];
        for (index, &team) in order.iter().enumerate() { positions[team] = index + 1; }
        Self { records, h2h_points, h2h_difference, order, positions }
    }
    fn tied_groups(&self) -> Vec<Vec<usize>> {
        let mut groups: Vec<Vec<usize>> = Vec::new();
        for &team in &self.order {
            if groups.last().is_some_and(|group| self.records[group[0]].points == self.records[team].points) { groups.last_mut().unwrap().push(team); }
            else { groups.push(vec![team]); }
        }
        groups.into_iter().filter(|group| group.len() >= 2).collect()
    }
}
struct Streak { length: usize, first: usize, last: usize }
fn longest_streak(appearances: &[Appearance], unbeaten: bool) -> Streak {
    let mut best = Streak { length: 0, first: 0, last: 0 };
    let (mut start, mut length) = (0, 0);
    for (index, item) in appearances.iter().enumerate() {
        if item.letter != b'W' && !(unbeaten && item.letter == b'D') { length = 0; continue; }
        if length == 0 { start = index; }
        length += 1;
        if length > best.length { best = Streak { length, first: appearances[start].game.round, last: item.game.round }; }
    }
    best
}
fn current_streak(appearances: &[Appearance]) -> String {
    let last = appearances.last().unwrap().letter;
    let count = appearances.iter().rev().take_while(|item| item.letter == last).count();
    format!("{}{count}", last as char)
}
struct ModelFit {
    elo: EloRun,
    colley: Vec<f64>,
    massey: Vec<f64>,
    home_advantage: f64,
    strengths: Vec<f64>,
    home_factor: f64,
    offense: Vec<f64>,
    defense: Vec<f64>,
    od: Vec<f64>,
    win_percentages: Vec<Fraction>,
}
impl ModelFit {
    fn new(count: usize, matches: &[Match], settings: &Settings) -> Self {
        let elo = run_elo(count, matches, settings.elo_k, settings.elo_home, settings.elo_initial);
        let colley = colley_ratings(count, matches);
        let (massey, home_advantage) = massey_ratings(count, matches);
        let (strengths, home_factor) = bradley_terry(count, matches, settings.bt_iterations);
        let (offense, defense, od) = offense_defense(count, matches, settings.od_iterations);
        let win_percentages = team_records(count, matches, settings).iter().map(Record::win_percentage).collect();
        Self { elo, colley, massey, home_advantage, strengths, home_factor, offense, defense, od, win_percentages }
    }
    fn feature(&self, model: usize, game: Match) -> f64 {
        match model { 0 => self.colley[game.home] - self.colley[game.away], 1 => self.massey[game.home] - self.massey[game.away],
            2 => self.od[game.home].ln() - self.od[game.away].ln(), _ => self.win_percentages[game.home].real() - self.win_percentages[game.away].real() }
    }
    fn bt_probability(&self, game: Match) -> f64 { let home = self.home_factor * self.strengths[game.home]; home / (home + self.strengths[game.away]) }
    fn predicted_margin(&self, game: Match) -> f64 { self.massey[game.home] - self.massey[game.away] + self.home_advantage }
}
struct Prediction { game: Match, probabilities: [f64; 8], losses: [f64; 8], briers: [f64; 8], scores: [i64; 8], margin_error: f64 }
impl Prediction {
    fn new(game: Match, probabilities: [f64; 8], margin_error: f64) -> Self {
        let losses = probabilities.map(|probability| log_loss(probability, game.result_twice()));
        let briers = probabilities.map(|probability| brier_score(probability, game.result_twice()));
        let scores = probabilities.map(|probability| correctness_twice(probability, game.result_twice()));
        Self { game, probabilities, losses, briers, scores, margin_error }
    }
}
struct ValidationRound { number: usize, training_count: usize, fit: ModelFit, base: f64, links: Vec<(f64, f64)>, predictions: Vec<Prediction> }
impl ValidationRound {
    fn new(number: usize, count: usize, matches: &[Match], settings: &Settings) -> Self {
        let training = matches_before(matches, number);
        let fit = ModelFit::new(count, &training, settings);
        let sum_twice: i64 = training.iter().map(|game| game.result_twice()).sum();
        let base = Fraction::new(sum_twice, 2 * training.len() as i64).real();
        let results: Vec<_> = training.iter().map(|game| game.y()).collect();
        let links: Vec<_> = (0..4).map(|model| {
            let features: Vec<_> = training.iter().map(|&game| fit.feature(model, game)).collect();
            fit_link(&features, &results, settings.link_iterations)
        }).collect();
        let mut predictions = Vec::new();
        for &game in matches.iter().filter(|game| game.round == number) {
            let mut probabilities = [0.0; 8];
            probabilities[0] = base;
            probabilities[1] = expected_score(fit.elo.ratings[game.home], fit.elo.ratings[game.away], settings.elo_home);
            for (model, &target) in [2, 3, 5, 6].iter().enumerate() { probabilities[target] = sigma(links[model].0 + links[model].1 * fit.feature(model, game)); }
            probabilities[4] = fit.bt_probability(game);
            probabilities[7] = sequential_sum([1, 2, 3, 4, 5, 6].map(|index| probabilities[index])) / 6.0;
            predictions.push(Prediction::new(game, probabilities, game.margin() as f64 - fit.predicted_margin(game)));
        }
        Self { number, training_count: training.len(), fit, base, links, predictions }
    }
}
struct ModelScores { losses: Vec<f64>, briers: Vec<f64>, skills: Vec<f64>, accuracies: Vec<Fraction>, loss_ranking: Vec<usize>, brier_ranking: Vec<usize>, accuracy_ranking: Vec<usize> }
impl ModelScores {
    fn new(predictions: &[&Prediction]) -> Self {
        let count = predictions.len();
        let losses: Vec<_> = (0..8).map(|model| sequential_sum(predictions.iter().map(|item| item.losses[model])) / count as f64).collect();
        let briers: Vec<_> = (0..8).map(|model| sequential_sum(predictions.iter().map(|item| item.briers[model])) / count as f64).collect();
        let skills = briers.iter().map(|&brier| 1.0 - brier / briers[0]).collect();
        let accuracies: Vec<_> = (0..8).map(|model| Fraction::new(predictions.iter().map(|item| item.scores[model]).sum(), 2 * count as i64)).collect();
        let mut loss_ranking: Vec<_> = (0..8).collect(); loss_ranking.sort_by_key(|&model| (decimal_value(losses[model], 4), model));
        let mut brier_ranking: Vec<_> = (0..8).collect(); brier_ranking.sort_by_key(|&model| (decimal_value(briers[model], 4), model));
        let mut accuracy_ranking: Vec<_> = (0..8).collect(); accuracy_ranking.sort_by(|&a, &b| accuracies[b].cmp(&accuracies[a]).then(a.cmp(&b)));
        Self { losses, briers, skills, accuracies, loss_ranking, brier_ranking, accuracy_ranking }
    }
}
struct Projection { current: Standings, ratings: Vec<f64>, remaining: Vec<Match>, total_points: Vec<i64>, titles: Vec<i64>, tops: Vec<i64>, bottoms: Vec<i64>, order: Vec<usize>, ranks: Vec<usize> }
impl Projection {
    fn new(teams: &[Team], matches: &[Match], settings: &Settings) -> Self {
        let count = teams.len();
        let current_matches = matches_before(matches, settings.holdout_round);
        let current = Standings::new(teams, &current_matches, settings);
        let ratings = run_elo(count, &current_matches, settings.elo_k, settings.elo_home, settings.elo_initial).ratings;
        let remaining: Vec<_> = matches.iter().copied().filter(|game| game.round >= settings.holdout_round).collect();
        let probabilities: Vec<_> = remaining.iter().map(|game| expected_score(ratings[game.home], ratings[game.away], settings.elo_home)).collect();
        let (mut total_points, mut titles, mut tops, mut bottoms) = (vec![0; count], vec![0; count], vec![0; count], vec![0; count]);
        let mut state = settings.seed;
        for _ in 0..settings.simulations {
            let mut points: Vec<_> = current.records.iter().map(|record| record.points).collect();
            for (game, &probability) in remaining.iter().zip(&probabilities) {
                state = 48271 * state % 2147483647;
                let winner = if (state as f64 / 2147483647.0) < probability { game.home } else { game.away };
                points[winner] += settings.win_points;
            }
            let mut order: Vec<_> = (0..count).collect(); order.sort_by_key(|&team| (-points[team], current.positions[team]));
            for (index, &team) in order.iter().enumerate() {
                total_points[team] += points[team];
                if index == 0 { titles[team] += 1; }
                if index + 1 <= settings.top_positions { tops[team] += 1; }
                if index + 1 >= count - settings.bottom_positions + 1 { bottoms[team] += 1; }
            }
        }
        let mut order: Vec<_> = (0..count).collect(); order.sort_by_key(|&team| (-total_points[team], current.positions[team]));
        let mut ranks = vec![0; count]; for (index, &team) in order.iter().enumerate() { ranks[team] = index + 1; }
        Self { current, ratings, remaining, total_points, titles, tops, bottoms, order, ranks }
    }
    fn opponent_strength(&self, team: usize) -> f64 {
        let mut ratings = Vec::new();
        for game in &self.remaining { if game.home == team { ratings.push(self.ratings[game.away]); } else if game.away == team { ratings.push(self.ratings[game.home]); } }
        mean(&ratings)
    }
}
struct LeagueAnalysis {
    teams: Vec<Team>, matches: Vec<Match>, settings: Settings, appearances: Vec<Vec<Appearance>>, final_table: Standings, fit: ModelFit,
    round_tables: Vec<Standings>, win_streaks: Vec<Streak>, unbeaten_streaks: Vec<Streak>, sos: Vec<Fraction>, sos2: Vec<Fraction>, rpi: Vec<Fraction>,
    pythag: Vec<f64>, luck: Vec<f64>, comparison: Vec<Vec<Fraction>>, ranks: Vec<Vec<usize>>, rounds: Vec<ValidationRound>, scores: ModelScores, projection: Projection,
}
impl LeagueAnalysis {
    fn new(teams: Vec<Team>, matches: Vec<Match>, settings: Settings) -> Self {
        let count = teams.len();
        let final_round = matches.last().unwrap().round;
        let appearances: Vec<_> = (0..count).map(|team| appearances_of(team, &matches)).collect();
        let final_table = Standings::new(&teams, &matches, &settings);
        let fit = ModelFit::new(count, &matches, &settings);
        let round_tables = (1..=final_round).map(|round| Standings::new(&teams, &matches_before(&matches, round + 1), &settings)).collect();
        let win_streaks = appearances.iter().map(|items| longest_streak(items, false)).collect();
        let unbeaten_streaks = appearances.iter().map(|items| longest_streak(items, true)).collect();
        let opponent_average = |values: &[Fraction]| -> Vec<Fraction> {
            appearances.iter().map(|items| { let mut total = Fraction::integer(0); for item in items { total = total + values[item.opponent]; } total / Fraction::integer(items.len() as i64) }).collect()
        };
        let sos = opponent_average(&fit.win_percentages);
        let sos2 = opponent_average(&sos);
        let rpi: Vec<_> = (0..count).map(|team| (fit.win_percentages[team] + Fraction::integer(2) * sos[team] + sos2[team]) / Fraction::integer(4)).collect();
        let pythag: Vec<_> = final_table.records.iter().map(|record| 1.0 / (1.0 + (record.conceded as f64 / record.scored as f64).powf(settings.exponent))).collect();
        let luck = (0..count).map(|team| fit.win_percentages[team].real() - pythag[team]).collect();
        let comparison = vec![final_table.positions.iter().map(|&position| Fraction::integer(-(position as i64))).collect(), rounded_values(&fit.elo.ratings, 2),
            rounded_values(&fit.colley, 4), rounded_values(&fit.massey, 4), rounded_values(&fit.strengths, 4), rounded_values(&fit.od, 2), fit.win_percentages.clone(), rpi.clone(), rounded_values(&pythag, 4)];
        let ranks = (1..=RATING_MODELS.len()).map(|model| competition_ranks(&comparison[model])).collect();
        let rounds: Vec<_> = (settings.holdout_round..=final_round).map(|number| ValidationRound::new(number, count, &matches, &settings)).collect();
        let scores = {
            let predictions: Vec<_> = rounds.iter().flat_map(|round| &round.predictions).collect();
            ModelScores::new(&predictions)
        };
        let projection = Projection::new(&teams, &matches, &settings);
        Self { teams, matches, settings, appearances, final_table, fit, round_tables, win_streaks, unbeaten_streaks, sos, sos2, rpi, pythag, luck, comparison, ranks, rounds, scores, projection }
    }
    fn code(&self, team: usize) -> &str { &self.teams[team].code }
    fn final_round(&self) -> usize { self.round_tables.len() }
    fn predictions(&self) -> Vec<&Prediction> { self.rounds.iter().flat_map(|round| &round.predictions).collect() }
    fn standings_lines(&self) -> Vec<String> {
        let mut lines = vec![STANDINGS_HEADER.to_owned()];
        for (position, &team) in self.final_table.order.iter().enumerate() {
            let record = &self.final_table.records[team];
            let appearances = &self.appearances[team];
            let home = record_text(appearances.iter().filter(|item| item.home));
            let away = record_text(appearances.iter().filter(|item| !item.home));
            let close = record_text(appearances.iter().filter(|item| (item.scored - item.conceded).abs() <= self.settings.close_margin));
            let form: String = appearances[appearances.len().saturating_sub(self.settings.form_length)..].iter().map(|item| item.letter as char).collect();
            lines.push(vec![(position + 1).to_string(), self.code(team).to_owned(), self.teams[team].name.clone(), record.played.to_string(), record.won.to_string(), record.drawn.to_string(),
                record.lost.to_string(), record.scored.to_string(), record.conceded.to_string(), record.difference().to_string(), record.points.to_string(), home, away, form, current_streak(appearances), close,
                self.win_streaks[team].length.to_string(), self.unbeaten_streaks[team].length.to_string(), self.fit.win_percentages[team].text(), self.sos[team].fixed(4), self.sos2[team].fixed(4),
                self.rpi[team].fixed(4), fixed(self.pythag[team], 4), fixed(self.luck[team], 4)].join(","));
        }
        lines
    }
    fn ratings_lines(&self) -> Vec<String> {
        let totals: Vec<usize> = (0..self.teams.len()).map(|team| self.ranks.iter().map(|ranks| ranks[team]).sum()).collect();
        let mut order: Vec<_> = (0..self.teams.len()).collect(); order.sort_by_key(|&team| (totals[team], self.code(team)));
        let mut lines = vec![RATINGS_HEADER.to_owned()];
        for team in order {
            let ranks: Vec<_> = self.ranks.iter().map(|ranks| ranks[team]).collect();
            let fit = &self.fit;
            lines.push(vec![self.code(team).to_owned(), fixed(fit.elo.ratings[team], 2), ranks[0].to_string(), fixed(fit.colley[team], 4), ranks[1].to_string(), fixed(fit.massey[team], 4),
                ranks[2].to_string(), fixed(fit.strengths[team], 4), ranks[3].to_string(), fixed(fit.offense[team], 2), fixed(fit.defense[team], 4), fixed(fit.od[team], 2), ranks[4].to_string(),
                fit.win_percentages[team].fixed(4), ranks[5].to_string(), totals[team].to_string(), ranks.iter().min().unwrap().to_string(), ranks.iter().max().unwrap().to_string()].join(","));
        }
        lines
    }
    fn history_lines(&self) -> Vec<String> {
        let mut lines = vec![HISTORY_HEADER.to_owned()];
        let mut previous = vec![self.settings.elo_initial as f64; self.teams.len()];
        for (index, table) in self.round_tables.iter().enumerate() {
            let ratings = &self.fit.elo.round_ratings[index];
            let ranks = competition_ranks(&rounded_values(ratings, 2));
            for team in 0..self.teams.len() { lines.push(format!("{},{},{},{},{},{},{}", index + 1, self.code(team), fixed(ratings[team], 2), fixed(ratings[team] - previous[team], 2), ranks[team], table.records[team].points, table.positions[team])); }
            previous.clone_from(ratings);
        }
        lines
    }
    fn summary_lines(&self) -> Vec<String> {
        let won = self.matches.iter().filter(|game| game.result_twice() == 2).count();
        let drawn = self.matches.iter().filter(|game| game.result_twice() == 1).count();
        let lost = self.matches.len() - won - drawn;
        let rate = Fraction::new((2 * won + drawn) as i64, 2 * self.matches.len() as i64);
        vec![format!("season teams {} matches {} rounds {}", self.teams.len(), self.matches.len(), self.final_round()),
            format!("home won {won} drawn {drawn} lost {lost} rate {}", rate.with_real()), format!("massey_home_advantage {}", fixed(self.fit.home_advantage, 4)),
            format!("bt_home_factor {}", fixed(self.fit.home_factor, 4))]
    }
    fn upset_lines(&self) -> Vec<String> {
        let mut candidates: Vec<_> = self.matches.iter().enumerate().filter(|(_, game)| game.margin() != 0).map(|(index, game)| {
            let expected = if game.margin() > 0 { self.fit.elo.expected[index] } else { 1.0 - self.fit.elo.expected[index] };
            (index, expected)
        }).collect();
        candidates.sort_by_key(|&(index, expected)| (decimal_value(expected, 4), index));
        let mut lines = vec![format!("upsets top {}", self.settings.upsets)];
        for &(index, expected) in candidates.iter().take(self.settings.upsets) {
            let game = self.matches[index];
            let (winner, loser, scored, conceded, side) = if game.margin() > 0 { (game.home, game.away, game.home_score, game.away_score, "home") }
                else { (game.away, game.home, game.away_score, game.home_score, "away") };
            lines.push(format!("round {} {} beat {} {scored}-{conceded} {side} expected {} gain {}", game.round, self.code(winner), self.code(loser), fixed(expected, 4), fixed(self.fit.elo.changes[index].abs(), 2)));
        }
        lines
    }
    fn tiebreak_lines(&self) -> Vec<String> {
        let mut lines = vec!["tiebreaks".to_owned()];
        for group in self.final_table.tied_groups() {
            let points = self.final_table.records[group[0]].points;
            let order = group.iter().map(|&team| self.code(team)).collect::<Vec<_>>().join(" ");
            let h2h_points = group.iter().map(|&team| self.final_table.h2h_points[team].to_string()).collect::<Vec<_>>().join(" ");
            let h2h_difference = group.iter().map(|&team| self.final_table.h2h_difference[team].to_string()).collect::<Vec<_>>().join(" ");
            lines.push(format!("points {points} order {order} h2h_points {h2h_points} h2h_diff {h2h_difference}"));
        }
        if lines.len() == 1 { lines.push("none".to_owned()); }
        lines
    }
    fn leader_lines(&self) -> Vec<String> {
        let mut lines = vec!["leaders".to_owned()];
        let mut previous = None;
        let mut recorded = 0;
        for (index, table) in self.round_tables.iter().enumerate() {
            let leader = table.order[0];
            if previous != Some(leader) { lines.push(format!("round {} {} points {}", index + 1, self.code(leader), table.records[leader].points)); recorded += 1; }
            previous = Some(leader);
        }
        lines.push(format!("lead_changes {}", recorded - 1)); lines
    }
    fn streak_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for (label, streaks) in [("longest_win_streak", &self.win_streaks), ("longest_unbeaten_streak", &self.unbeaten_streaks)] {
            let longest = streaks.iter().map(|streak| streak.length).max().unwrap();
            for (team, streak) in streaks.iter().enumerate() { if streak.length == longest { lines.push(format!("{label} {} length {} rounds {}-{}", self.code(team), streak.length, streak.first, streak.last)); } }
        }
        lines
    }
    fn crosstable_lines(&self) -> Vec<String> {
        let top = &self.final_table.order[..self.settings.top_positions];
        let mut lines = vec![format!("crosstable top {}", self.settings.top_positions), format!("team {}", top.iter().map(|&team| self.code(team)).collect::<Vec<_>>().join(" "))];
        for &first in top {
            let entries: Vec<_> = top.iter().map(|&second| if first == second { "-".to_owned() } else { record_text(self.appearances[first].iter().filter(|item| item.opponent == second)) }).collect();
            lines.push(format!("{} {}", self.code(first), entries.join(" ")));
        }
        lines
    }
    fn trajectory_lines(&self) -> Vec<String> {
        let mut lines = vec!["trajectories".to_owned()];
        for team in 0..self.teams.len() {
            let ratings: Vec<_> = self.fit.elo.round_ratings.iter().map(|snapshot| snapshot[team]).collect();
            let rounded: Vec<_> = ratings.iter().map(|&rating| decimal_value(rating, 2)).collect();
            let positions: Vec<_> = self.round_tables.iter().map(|table| table.positions[team]).collect();
            let (mut peak, mut low, mut best, mut worst) = (0, 0, 0, 0);
            for index in 1..self.final_round() {
                if rounded[index] > rounded[peak] { peak = index; }
                if rounded[index] < rounded[low] { low = index; }
                if positions[index] < positions[best] { best = index; }
                if positions[index] > positions[worst] { worst = index; }
            }
            lines.push(format!("{} elo_peak {} round {} elo_low {} round {} best_position {} round {} worst_position {} round {}", self.code(team), fixed(ratings[peak], 2), peak + 1,
                fixed(ratings[low], 2), low + 1, positions[best], best + 1, positions[worst], worst + 1));
        }
        lines
    }
    fn correlation_lines(&self, title: &str, measure: fn(&[Fraction], &[Fraction]) -> Fraction) -> Vec<String> {
        let mut lines = vec![title.to_owned(), format!("model {}", COMPARISON_MODELS.join(" "))];
        for (first, label) in COMPARISON_MODELS.iter().enumerate() {
            let values: Vec<_> = self.comparison.iter().map(|second| measure(&self.comparison[first], second).text()).collect();
            lines.push(format!("{label} {}", values.join(" ")));
        }
        lines
    }
    fn similarity_lines(&self) -> Vec<String> {
        let mut pairs = Vec::new();
        for first in 0..COMPARISON_MODELS.len() { for second in first + 1..COMPARISON_MODELS.len() { pairs.push((first, second, kendall_tau(&self.comparison[first], &self.comparison[second]))); } }
        let (mut most, mut least) = (pairs[0], pairs[0]);
        for &pair in &pairs[1..] { if pair.2 > most.2 { most = pair; } if pair.2 < least.2 { least = pair; } }
        [("most_similar", most), ("least_similar", least)].iter().map(|(label, pair)| format!("{label} {} {} tau {}", COMPARISON_MODELS[pair.0], COMPARISON_MODELS[pair.1], pair.2.with_real())).collect()
    }
    fn season_lines(&self) -> Vec<String> {
        join_parts(vec![self.summary_lines(), self.upset_lines(), self.tiebreak_lines(), self.leader_lines(), self.streak_lines(), self.crosstable_lines(), self.trajectory_lines(),
            self.correlation_lines("kendall", kendall_tau), self.correlation_lines("spearman", spearman_rho), self.similarity_lines()])
    }
    fn prediction_lines(&self) -> Vec<String> {
        let mut lines = vec![format!("round,home,away,home_score,away_score,result,{}", PREDICTION_MODELS.join(","))];
        for prediction in self.predictions() {
            let game = prediction.game;
            let result = match game.result_twice() { 2 => "H", 0 => "A", _ => "D" };
            let mut fields = vec![game.round.to_string(), self.code(game.home).to_owned(), self.code(game.away).to_owned(), game.home_score.to_string(), game.away_score.to_string(), result.to_owned()];
            fields.extend(prediction.probabilities.iter().map(|&value| fixed(value, 4))); lines.push(fields.join(","));
        }
        lines
    }
    fn link_lines(&self) -> Vec<String> {
        let mut lines = vec!["links".to_owned()];
        for validation in &self.rounds {
            let mut parts = vec![format!("round {} train {} base {} bt_home {}", validation.number, validation.training_count, fixed(validation.base, 4), fixed(validation.fit.home_factor, 4))];
            for (model, name) in LINK_MODELS.iter().enumerate() { parts.push(format!("{name} {} {}", fixed(validation.links[model].0, 4), fixed(validation.links[model].1, 4))); }
            lines.push(parts.join(" "));
        }
        lines
    }
    fn score_lines(&self) -> Vec<String> {
        let scores = &self.scores;
        let mut lines = vec!["scores".to_owned(), "model log_loss brier skill accuracy".to_owned()];
        for (model, name) in PREDICTION_MODELS.iter().enumerate() { lines.push(format!("{name} {} {} {} {}", fixed(scores.losses[model], 4), fixed(scores.briers[model], 4), fixed(scores.skills[model], 4), scores.accuracies[model].with_real())); }
        for (label, ranking) in [("ranking_log_loss", &scores.loss_ranking), ("ranking_brier", &scores.brier_ranking), ("ranking_accuracy", &scores.accuracy_ranking)] {
            lines.push(format!("{label} {}", ranking.iter().map(|&model| PREDICTION_MODELS[model]).collect::<Vec<_>>().join(" ")));
        }
        lines
    }
    fn paired_lines(&self) -> Vec<String> {
        let reference = self.scores.loss_ranking[0];
        let predictions = self.predictions();
        let count = predictions.len();
        let mut lines = vec![format!("paired_log_loss reference {}", PREDICTION_MODELS[reference])];
        for (model, name) in PREDICTION_MODELS.iter().enumerate() {
            if model == reference { continue; }
            let deltas: Vec<_> = predictions.iter().map(|item| item.losses[model] - item.losses[reference]).collect();
            let average = mean(&deltas);
            let squares = sequential_sum(deltas.iter().map(|&delta| (delta - average) * (delta - average)));
            let spread = (squares / (count - 1) as f64).sqrt();
            let statistic = average / (spread / (count as f64).sqrt());
            lines.push(format!("{name} mean_diff {} sd {} t {}", fixed(average, 4), fixed(spread, 4), fixed(statistic, 2)));
        }
        lines
    }
    fn margin_lines(&self) -> Vec<String> {
        let errors: Vec<_> = self.predictions().iter().map(|item| item.margin_error).collect();
        let absolute = sequential_sum(errors.iter().map(|value| value.abs())) / errors.len() as f64;
        let squared = sequential_sum(errors.iter().map(|&value| value * value)) / errors.len() as f64;
        vec![format!("massey_margin mae {} rmse {} bias {}", fixed(absolute, 4), fixed(squared.sqrt(), 4), fixed(mean(&errors), 4))]
    }
    fn round_loss_lines(&self) -> Vec<String> {
        let mut lines = vec!["round_log_loss".to_owned(), format!("round {}", PREDICTION_MODELS.join(" "))];
        for validation in &self.rounds {
            let losses: Vec<_> = (0..8).map(|model| fixed(sequential_sum(validation.predictions.iter().map(|item| item.losses[model])) / validation.predictions.len() as f64, 4)).collect();
            lines.push(format!("{} {}", validation.number, losses.join(" ")));
        }
        lines
    }
    fn calibration_lines(&self) -> Vec<String> {
        let bins = self.settings.calibration_bins;
        let mut lines = vec![format!("calibration bins {bins}")];
        for (model, name) in PREDICTION_MODELS.iter().enumerate() {
            let mut groups: Vec<Vec<&Prediction>> = vec![Vec::new(); bins];
            for prediction in self.predictions() { let bin = ((bins as f64 * prediction.probabilities[model]).floor() as usize).min(bins - 1); groups[bin].push(prediction); }
            for (index, group) in groups.iter().enumerate() {
                if group.is_empty() { lines.push(format!("{name} bin {} count 0 predicted - observed -", index + 1)); continue; }
                let predicted = sequential_sum(group.iter().map(|item| item.probabilities[model])) / group.len() as f64;
                let observed = Fraction::new(group.iter().map(|item| item.game.result_twice()).sum(), 2 * group.len() as i64);
                lines.push(format!("{name} bin {} count {} predicted {} observed {}", index + 1, group.len(), fixed(predicted, 4), observed.text()));
            }
        }
        lines
    }
    fn grid_lines(&self) -> Vec<String> {
        let settings = &self.settings;
        let mut lines = vec!["elo_grid".to_owned(), format!("k {}", settings.grid_home.iter().map(|home| format!("h{home}")).collect::<Vec<_>>().join(" "))];
        let mut best: Option<(i64, i64, f64)> = None;
        for &k in &settings.grid_k {
            let mut row = vec![k.to_string()];
            for &home in &settings.grid_home {
                let run = run_elo(self.teams.len(), &self.matches, k, home, settings.elo_initial);
                let losses: Vec<_> = self.matches.iter().enumerate().filter(|(_, game)| game.round >= settings.holdout_round).map(|(index, game)| log_loss(run.expected[index], game.result_twice())).collect();
                let loss = mean(&losses);
                row.push(fixed(loss, 4));
                if best.is_none_or(|(_, _, previous)| decimal_value(loss, 4) < decimal_value(previous, 4)) { best = Some((k, home, loss)); }
            }
            lines.push(row.join(" "));
        }
        let (k, home, loss) = best.unwrap(); lines.push(format!("best k {k} home {home} log_loss {}", fixed(loss, 4))); lines
    }
    fn projection_tau(&self) -> Fraction {
        let projected: Vec<_> = self.projection.ranks.iter().map(|&rank| Fraction::integer(-(rank as i64))).collect();
        let final_values: Vec<_> = self.final_table.positions.iter().map(|&rank| Fraction::integer(-(rank as i64))).collect();
        kendall_tau(&projected, &final_values)
    }
    fn evaluation_lines(&self) -> Vec<String> {
        join_parts(vec![vec![format!("holdout rounds {}-{} matches {}", self.settings.holdout_round, self.final_round(), self.predictions().len())], self.link_lines(), self.score_lines(), self.paired_lines(),
            self.margin_lines(), self.round_loss_lines(), self.calibration_lines(), self.grid_lines(), vec![format!("projection simulations {} kendall {}", self.settings.simulations, self.projection_tau().with_real())]])
    }
    fn projection_lines(&self) -> Vec<String> {
        let projection = &self.projection;
        let simulations = self.settings.simulations as i64;
        let mut lines = vec![PROJECTION_HEADER.to_owned()];
        for (index, &team) in projection.order.iter().enumerate() {
            lines.push(vec![(index + 1).to_string(), self.code(team).to_owned(), projection.current.records[team].points.to_string(), projection.current.positions[team].to_string(),
                fixed(projection.opponent_strength(team), 2), Fraction::new(projection.total_points[team], simulations).fixed(4), Fraction::new(projection.titles[team], simulations).fixed(4),
                Fraction::new(projection.tops[team], simulations).fixed(4), Fraction::new(projection.bottoms[team], simulations).fixed(4), self.final_table.records[team].points.to_string(), self.final_table.positions[team].to_string()].join(","));
        }
        lines
    }
    fn output_files(&self) -> Vec<(&'static str, Vec<String>)> {
        vec![("standings.csv", self.standings_lines()), ("ratings.csv", self.ratings_lines()), ("history.csv", self.history_lines()), ("season.txt", self.season_lines()),
            ("predictions.csv", self.prediction_lines()), ("evaluation.txt", self.evaluation_lines()), ("projection.csv", self.projection_lines())]
    }
}

fn main() -> io::Result<()> {
    let (teams, matches, settings) = load_season()?;
    let analysis = LeagueAnalysis::new(teams, matches, settings);
    fs::create_dir_all("output")?;
    for (name, lines) in analysis.output_files() { write_lines(&format!("output/{name}"), &lines)?; }
    Ok(())
}
