use crate::season::Match;

fn cholesky_solve(matrix: &[Vec<f64>], vector: &[f64]) -> Vec<f64> {
    let size = vector.len();
    let mut lower = vec![vec![0.0; size]; size];
    for i in 0..size { for j in 0..=i {
        let mut total = 0.0;
        for k in 0..j { total += lower[i][k] * lower[j][k]; }
        lower[i][j] = if j < i { (matrix[i][j] - total) / lower[j][j] } else { (matrix[i][i] - total).sqrt() };
    } }
    let mut forward = vec![0.0; size];
    for i in 0..size {
        let mut total = 0.0;
        for k in 0..i { total += lower[i][k] * forward[k]; }
        forward[i] = (vector[i] - total) / lower[i][i];
    }
    let mut solution = vec![0.0; size];
    for i in (0..size).rev() {
        let mut total = 0.0;
        for k in i + 1..size { total += lower[k][i] * solution[k]; }
        solution[i] = (forward[i] - total) / lower[i][i];
    }
    solution
}
fn gaussian_solve(mut matrix: Vec<Vec<f64>>, mut vector: Vec<f64>) -> Vec<f64> {
    let size = vector.len();
    for k in 0..size {
        let mut pivot = k;
        for row in k + 1..size { if matrix[row][k].abs() > matrix[pivot][k].abs() { pivot = row; } }
        matrix.swap(k, pivot); vector.swap(k, pivot);
        for i in k + 1..size {
            let factor = matrix[i][k] / matrix[k][k];
            for j in k..size { let pivot_value = matrix[k][j]; matrix[i][j] -= factor * pivot_value; }
            let pivot_value = vector[k];
            vector[i] -= factor * pivot_value;
        }
    }
    let mut solution = vec![0.0; size];
    for i in (0..size).rev() {
        let mut total = 0.0;
        for j in i + 1..size { total += matrix[i][j] * solution[j]; }
        solution[i] = (vector[i] - total) / matrix[i][i];
    }
    solution
}
pub fn colley_ratings(count: usize, matches: &[Match]) -> Vec<f64> {
    let mut matrix = vec![vec![0.0; count]; count];
    let mut balance = vec![0i64; count];
    for (team, row) in matrix.iter_mut().enumerate() { row[team] = 2.0; }
    for game in matches {
        matrix[game.home][game.home] += 1.0; matrix[game.away][game.away] += 1.0;
        matrix[game.home][game.away] -= 1.0; matrix[game.away][game.home] -= 1.0;
        let difference = game.margin().signum(); balance[game.home] += difference; balance[game.away] -= difference;
    }
    let vector: Vec<_> = balance.iter().map(|&value| 1.0 + value as f64 / 2.0).collect();
    cholesky_solve(&matrix, &vector)
}
pub fn massey_ratings(count: usize, matches: &[Match]) -> (Vec<f64>, f64) {
    let size = count + 1;
    let mut matrix = vec![vec![0.0; size]; size];
    let mut vector = vec![0.0; size];
    for game in matches {
        let (home, away) = (game.home, game.away);
        matrix[home][home] += 1.0; matrix[away][away] += 1.0; matrix[home][away] -= 1.0; matrix[away][home] -= 1.0;
        matrix[home][count] += 1.0; matrix[count][home] += 1.0; matrix[away][count] -= 1.0; matrix[count][away] -= 1.0; matrix[count][count] += 1.0;
        vector[home] += game.margin() as f64; vector[away] -= game.margin() as f64; vector[count] += game.margin() as f64;
    }
    matrix[count - 1] = vec![1.0; size]; matrix[count - 1][count] = 0.0; vector[count - 1] = 0.0;
    let solution = gaussian_solve(matrix, vector);
    (solution[..count].to_vec(), solution[count])
}
