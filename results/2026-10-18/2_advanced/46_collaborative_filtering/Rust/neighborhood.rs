use crate::ratings::Data;

pub struct Similarities {
    pub users: Vec<Vec<Option<f64>>>,
    pub user_common: Vec<Vec<i64>>,
    pub items: Vec<Vec<Option<f64>>>,
    pub common: Vec<Vec<i64>>,
    pub differences: Vec<Vec<i64>>,
}

pub fn build(data: &Data) -> Similarities {
    let nu = data.users.len();
    let ni = data.items.len();
    let lambda = data.params.shrinkage;
    let mut users = vec![vec![None; nu]; nu];
    let mut user_common = vec![vec![0; nu]; nu];
    for u in 0..nu {
        for v in u + 1..nu {
            let mut n = 0;
            let (mut sx, mut sy, mut sxx, mut syy, mut sxy) = (0i64, 0i64, 0i64, 0i64, 0i64);
            for i in 0..ni {
                if let (Some(x), Some(y)) = (data.table[u][i], data.table[v][i]) {
                    n += 1;
                    sx += x;
                    sy += y;
                    sxx += x * x;
                    syy += y * y;
                    sxy += x * y;
                }
            }
            user_common[u][v] = n;
            user_common[v][u] = n;
            if n >= 2 {
                let num = n * sxy - sx * sy;
                let dx = n * sxx - sx * sx;
                let dy = n * syy - sy * sy;
                if dx != 0 && dy != 0 {
                    let a = (num * n) * (num * n);
                    let b = dx * dy * (n + lambda) * (n + lambda);
                    let value = num.signum() as f64 * (a as f64 / b as f64).sqrt();
                    users[u][v] = Some(value);
                    users[v][u] = Some(value);
                }
            }
        }
    }
    let mut items = vec![vec![None; ni]; ni];
    let mut common = vec![vec![0; ni]; ni];
    let mut differences = vec![vec![0; ni]; ni];
    for i in 0..ni {
        for j in i + 1..ni {
            let mut n = 0;
            let mut difference = 0;
            let (mut num, mut xx, mut yy) = (0.0, 0.0, 0.0);
            for u in 0..nu {
                if let (Some(x), Some(y)) = (data.table[u][i], data.table[u][j]) {
                    n += 1;
                    difference += x - y;
                    let a = x as f64 - data.user_mean[u];
                    let b = y as f64 - data.user_mean[u];
                    num += a * b;
                    xx += a * a;
                    yy += b * b;
                }
            }
            common[i][j] = n;
            common[j][i] = n;
            differences[i][j] = difference;
            differences[j][i] = -difference;
            if n >= 2 && xx != 0.0 && yy != 0.0 {
                let value = num / (xx * yy).sqrt() * n as f64 / (n + lambda) as f64;
                items[i][j] = Some(value);
                items[j][i] = Some(value);
            }
        }
    }
    Similarities { users, user_common, items, common, differences }
}

pub fn select(mut candidates: Vec<(usize, f64)>, k: usize) -> Vec<(usize, f64)> {
    candidates.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap().then(a.0.cmp(&b.0)));
    candidates.truncate(k);
    candidates
}
