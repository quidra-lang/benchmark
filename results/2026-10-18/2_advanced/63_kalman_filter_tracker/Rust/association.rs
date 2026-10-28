pub fn optimal(costs: &[Vec<Option<f64>>], columns: usize) -> Vec<(usize, usize)> {
    if costs.is_empty() || columns == 0 { return Vec::new(); }
    let rows = costs.len();
    let transposed = rows > columns;
    let (n, m) = if transposed { (columns, rows) } else { (rows, columns) };
    let maximum = costs.iter().flatten().filter_map(|v| *v).fold(0.0, f64::max);
    let penalty = (maximum+1.0)*(n+1) as f64;
    let value = |i: usize, j: usize| (if transposed { costs[j][i] } else { costs[i][j] }).unwrap_or(penalty);
    let (mut u, mut v, mut p, mut way) = (vec![0.0; n+1], vec![0.0; m+1], vec![0; m+1], vec![0; m+1]);
    for i in 1..=n {
        p[0] = i;
        let mut j0 = 0;
        let mut minimum = vec![f64::INFINITY; m+1];
        let mut used = vec![false; m+1];
        loop {
            used[j0] = true;
            let i0 = p[j0];
            let mut delta = f64::INFINITY;
            let mut j1 = 0;
            for j in 1..=m {
                if used[j] { continue; }
                let current = value(i0-1, j-1)-u[i0]-v[j];
                if current < minimum[j] { minimum[j] = current; way[j] = j0; }
                if minimum[j] < delta { delta = minimum[j]; j1 = j; }
            }
            for j in 0..=m {
                if used[j] { u[p[j]] += delta; v[j] -= delta; } else { minimum[j] -= delta; }
            }
            j0 = j1;
            if p[j0] == 0 { break; }
        }
        loop {
            let j1 = way[j0]; p[j0] = p[j1]; j0 = j1;
            if j0 == 0 { break; }
        }
    }
    let mut pairs = Vec::new();
    for j in 1..=m {
        if p[j] == 0 { continue; }
        let pair = if transposed { (j-1, p[j]-1) } else { (p[j]-1, j-1) };
        if costs[pair.0][pair.1].is_some() { pairs.push(pair); }
    }
    pairs.sort_unstable();
    pairs
}
