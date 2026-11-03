use crate::season::Match;

pub fn bradley_terry(count: usize, matches: &[Match], iterations: usize) -> (Vec<f64>, f64) {
    let mut wins = vec![0i64; count];
    let mut home_wins = 0;
    for game in matches { wins[game.home] += game.result_twice(); wins[game.away] += 2 - game.result_twice(); home_wins += game.result_twice(); }
    let mut strengths = vec![1.0; count];
    let mut theta = 1.0;
    for _ in 0..iterations {
        let mut zeta = vec![0.0; count];
        for game in matches { let q = theta * strengths[game.home] + strengths[game.away]; zeta[game.home] += theta / q; zeta[game.away] += 1.0 / q; }
        for team in 0..count { strengths[team] = (wins[team] as f64 / 2.0) / zeta[team]; }
        let mut total = 0.0;
        for &strength in &strengths { total += strength; }
        for strength in &mut strengths { *strength = *strength * count as f64 / total; }
        let mut denominator = 0.0;
        for game in matches { let home = strengths[game.home]; denominator += home / (theta * home + strengths[game.away]); }
        theta = (home_wins as f64 / 2.0) / denominator;
    }
    (strengths, theta)
}
pub fn offense_defense(count: usize, matches: &[Match], iterations: usize) -> (Vec<f64>, Vec<f64>, Vec<f64>) {
    let mut points = vec![vec![0i64; count]; count];
    for game in matches { points[game.home][game.away] += game.away_score; points[game.away][game.home] += game.home_score; }
    let mut offense = vec![0.0; count];
    let mut defense = vec![1.0; count];
    for _ in 0..iterations {
        for j in 0..count { let mut total = 0.0; for i in 0..count { total += points[i][j] as f64 / defense[i]; } offense[j] = total; }
        for i in 0..count { let mut total = 0.0; for j in 0..count { total += points[i][j] as f64 / offense[j]; } defense[i] = total; }
    }
    let ratings = (0..count).map(|team| offense[team] / defense[team]).collect();
    (offense, defense, ratings)
}
