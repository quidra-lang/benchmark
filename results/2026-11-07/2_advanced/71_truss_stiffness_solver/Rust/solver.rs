pub fn cholesky(matrix: &[Vec<f64>], free: &[usize]) -> Result<Vec<Vec<f64>>, usize> {
    let n = matrix.len();
    let mut lower = vec![vec![0.0; n]; n];
    for i in 0..n {
        for j in 0..=i {
            let mut w = matrix[i][j];
            for h in 0..j {
                w -= lower[i][h]*lower[j][h];
            }
            if i == j {
                if w <= 0.000000001*matrix[i][i] {
                    return Err(free[i]);
                }
                lower[i][j] = w.sqrt();
            } else {
                lower[i][j] = w/lower[j][j];
            }
        }
    }
    Ok(lower)
}
pub fn solve(lower: &[Vec<f64>], right: &[f64]) -> Vec<f64> {
    let n = right.len();
    let mut y = vec![0.0; n];
    let mut x = y.clone();
    for i in 0..n {
        let mut w = right[i];
        for h in 0..i {
            w -= lower[i][h]*y[h];
        }
        y[i] = w/lower[i][i];
    }
    for i in (0..n).rev() {
        let mut w = y[i];
        for h in i+1..n {
            w -= lower[h][i]*x[h];
        }
        x[i] = w/lower[i][i];
    }
    x
}
