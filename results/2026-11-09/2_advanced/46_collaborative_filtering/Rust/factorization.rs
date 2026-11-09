use crate::ratings::Data;

pub type Matrix = Vec<Vec<f64>>;

struct Generator(i64);

impl Generator {
    fn draw(&mut self) -> i64 {
        self.0 = 48271 * self.0 % 2147483647;
        self.0
    }

    fn factor(&mut self) -> f64 {
        (self.draw() % 2001 - 1000) as f64 / 10000.0
    }
}

pub fn dot(a: &[f64], b: &[f64]) -> f64 {
    a.iter().zip(b).map(|(x, y)| x * y).sum()
}

pub struct Svd {
    pub p: Matrix,
    pub q: Matrix,
    pub users: Vec<f64>,
    pub items: Vec<f64>,
    pub log: Vec<f64>,
}

impl Svd {
    pub fn predict(&self, mean: f64, u: usize, i: usize) -> f64 {
        ((mean + self.users[u]) + self.items[i]) + dot(&self.p[u], &self.q[i])
    }
}

pub fn svd(data: &Data) -> Svd {
    let params = &data.params;
    let mut generator = Generator(params.seed);
    let p = (0..data.users.len()).map(|_| (0..params.factors).map(|_| generator.factor()).collect()).collect();
    let q = (0..data.items.len()).map(|_| (0..params.factors).map(|_| generator.factor()).collect()).collect();
    let mut model = Svd { p, q, users: vec![0.0; data.users.len()], items: vec![0.0; data.items.len()], log: Vec::new() };
    let mut order: Vec<usize> = (0..data.train.len()).collect();
    for _ in 0..params.epochs {
        for t in (1..order.len()).rev() {
            let y = generator.draw() as usize % (t + 1);
            order.swap(t, y);
        }
        for &t in &order {
            let r = &data.train[t];
            let (u, i) = (r.user, r.item);
            let error = r.rating as f64 - model.predict(data.mean, u, i);
            let user_bias = model.users[u];
            let item_bias = model.items[i];
            model.users[u] = user_bias + params.learning_rate * (error - params.regularization * user_bias);
            model.items[i] = item_bias + params.learning_rate * (error - params.regularization * item_bias);
            for f in 0..params.factors {
                let a = model.p[u][f];
                let b = model.q[i][f];
                model.p[u][f] = a + params.learning_rate * (error * b - params.regularization * a);
                model.q[i][f] = b + params.learning_rate * (error * a - params.regularization * b);
            }
        }
        let rmse = (data.train.iter().map(|r| {
            let e = r.rating as f64 - model.predict(data.mean, r.user, r.item);
            e * e
        }).sum::<f64>() / data.train.len() as f64).sqrt();
        model.log.push(rmse);
    }
    model
}

fn solve(a: &Matrix, w: &[f64]) -> Vec<f64> {
    let d = a.len();
    let mut l = vec![vec![0.0; d]; d];
    for i in 0..d {
        for j in 0..=i {
            let sum: f64 = (0..j).map(|t| l[i][t] * l[j][t]).sum();
            let s = a[i][j] - sum;
            l[i][j] = if i == j { s.sqrt() } else { s / l[j][j] };
        }
    }
    let mut z = vec![0.0; d];
    for i in 0..d {
        let sum: f64 = (0..i).map(|t| l[i][t] * z[t]).sum();
        z[i] = (w[i] - sum) / l[i][i];
    }
    let mut x = vec![0.0; d];
    for i in (0..d).rev() {
        let sum: f64 = (i + 1..d).map(|t| l[t][i] * x[t]).sum();
        x[i] = (z[i] - sum) / l[i][i];
    }
    x
}

pub struct Als {
    pub x: Matrix,
    pub y: Matrix,
    pub log: Vec<f64>,
}

pub fn als(data: &Data, users: &[f64], items: &[f64]) -> Als {
    let params = &data.params;
    let f = params.factors;
    let mut generator = Generator(params.seed);
    let mut model = Als {
        x: vec![vec![0.0; f]; data.users.len()],
        y: (0..data.items.len()).map(|_| (0..f).map(|_| generator.factor()).collect()).collect(),
        log: Vec::new(),
    };
    for _ in 0..params.iterations {
        for u in 0..data.users.len() {
            let mut a = vec![vec![0.0; f]; f];
            let mut w = vec![0.0; f];
            for &i in &data.by_user[u] {
                let residual = data.table[u][i].unwrap() as f64 - ((data.mean + users[u]) + items[i]);
                for h in 0..f {
                    for j in 0..f {
                        a[h][j] += model.y[i][h] * model.y[i][j];
                    }
                    w[h] += residual * model.y[i][h];
                }
            }
            for h in 0..f {
                a[h][h] += params.als_reg * data.by_user[u].len() as f64;
            }
            model.x[u] = solve(&a, &w);
        }
        for i in 0..data.items.len() {
            let mut a = vec![vec![0.0; f]; f];
            let mut w = vec![0.0; f];
            for &u in &data.by_item[i] {
                let residual = data.table[u][i].unwrap() as f64 - ((data.mean + users[u]) + items[i]);
                for h in 0..f {
                    for j in 0..f {
                        a[h][j] += model.x[u][h] * model.x[u][j];
                    }
                    w[h] += residual * model.x[u][h];
                }
            }
            for h in 0..f {
                a[h][h] += params.als_reg * data.by_item[i].len() as f64;
            }
            model.y[i] = solve(&a, &w);
        }
        let rmse = (data.train.iter().map(|r| {
            let prediction = ((data.mean + users[r.user]) + items[r.item]) + dot(&model.x[r.user], &model.y[r.item]);
            let e = r.rating as f64 - prediction;
            e * e
        }).sum::<f64>() / data.train.len() as f64).sqrt();
        model.log.push(rmse);
    }
    model
}
