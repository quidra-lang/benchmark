use crate::season::Match;

pub struct EloRun { pub ratings: Vec<f64>, pub expected: Vec<f64>, pub changes: Vec<f64>, pub round_ratings: Vec<Vec<f64>> }
pub fn expected_score(home: f64, away: f64, advantage: i64) -> f64 { 1.0 / (1.0 + 10f64.powf((away - home - advantage as f64) / 400.0)) }
fn multiplier(game: Match, home: f64, away: f64, advantage: i64) -> f64 {
    let goals = game.margin().abs();
    if goals == 0 { return 1.0; }
    let difference = if game.margin() > 0 { home + advantage as f64 - away } else { away - home - advantage as f64 };
    ((goals + 1) as f64).ln() * 2.2 / (0.001 * difference + 2.2)
}
pub fn run_elo(count: usize, matches: &[Match], k: i64, advantage: i64, initial: i64) -> EloRun {
    let mut run = EloRun { ratings: vec![initial as f64; count], expected: Vec::new(), changes: Vec::new(), round_ratings: Vec::new() };
    for (index, &game) in matches.iter().enumerate() {
        let (home, away) = (run.ratings[game.home], run.ratings[game.away]);
        let expected = expected_score(home, away, advantage);
        let change = k as f64 * multiplier(game, home, away, advantage) * (game.y() - expected);
        run.ratings[game.home] = home + change; run.ratings[game.away] = away - change;
        run.expected.push(expected); run.changes.push(change);
        if index + 1 == matches.len() || matches[index + 1].round != game.round { run.round_ratings.push(run.ratings.clone()); }
    }
    run
}
