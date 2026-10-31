use std::{collections::{BTreeMap, BTreeSet}, fs, io};

pub struct Rating {
    pub user: usize,
    pub item: usize,
    pub rating: i64,
    pub time: i64,
}

pub struct Item {
    pub title: String,
    pub genres: Vec<String>,
}

pub struct Params {
    pub neighbors: usize,
    pub shrinkage: i64,
    pub minimum: f64,
    pub item_reg: f64,
    pub user_reg: f64,
    pub factors: usize,
    pub learning_rate: f64,
    pub regularization: f64,
    pub epochs: usize,
    pub als_reg: f64,
    pub iterations: usize,
    pub seed: i64,
    pub top_n: usize,
    pub cutoffs: Vec<usize>,
    pub grid: Vec<usize>,
    pub user_groups: Vec<usize>,
    pub item_groups: Vec<usize>,
    pub buckets: usize,
    pub list_size: usize,
    pub recommend: Vec<i64>,
    pub similar: Vec<i64>,
}

pub struct Data {
    pub users: Vec<i64>,
    pub items: Vec<i64>,
    pub catalog: BTreeMap<i64, Item>,
    pub train: Vec<Rating>,
    pub test: Vec<Rating>,
    pub table: Vec<Vec<Option<i64>>>,
    pub by_user: Vec<Vec<usize>>,
    pub by_item: Vec<Vec<usize>>,
    pub user_mean: Vec<f64>,
    pub item_mean: Vec<f64>,
    pub mean: f64,
    pub params: Params,
}

pub fn read() -> io::Result<Data> {
    let text = fs::read_to_string("input/ratings.csv")?;
    let raw: Vec<Vec<i64>> = text.lines().skip(1).map(|l| l.split(',').map(|s| s.parse().unwrap()).collect()).collect();
    let users: Vec<i64> = raw.iter().map(|r| r[0]).collect::<BTreeSet<_>>().into_iter().collect();
    let items: Vec<i64> = raw.iter().map(|r| r[1]).collect::<BTreeSet<_>>().into_iter().collect();
    let convert = |r: &[i64]| Rating {
        user: users.binary_search(&r[0]).unwrap(),
        item: items.binary_search(&r[1]).unwrap(),
        rating: r[2],
        time: r.get(3).copied().unwrap_or(0),
    };
    let train: Vec<Rating> = raw.iter().map(|r| convert(r)).collect();
    let test = fs::read_to_string("input/test.csv")?.lines().skip(1).map(|l| {
        let row: Vec<i64> = l.split(',').map(|s| s.parse().unwrap()).collect();
        convert(&row)
    }).collect();
    let catalog = fs::read_to_string("input/items.csv")?.lines().skip(1).map(|l| {
        let fields: Vec<&str> = l.split(',').collect();
        (fields[0].parse().unwrap(), Item {
            title: fields[1].into(),
            genres: fields[2].split('|').map(str::to_owned).collect(),
        })
    }).collect();
    let content = fs::read_to_string("input/params.txt")?;
    let q: Vec<Vec<&str>> = content.lines().map(|s| s.split_whitespace().collect()).collect();
    let list = |i: usize| q[i][1..].iter().map(|s| s.parse::<usize>().unwrap()).collect();
    let params = Params {
        neighbors: q[0][1].parse().unwrap(), shrinkage: q[1][1].parse().unwrap(),
        minimum: q[2][1].parse().unwrap(), item_reg: q[3][1].parse().unwrap(),
        user_reg: q[3][2].parse().unwrap(), factors: q[4][1].parse().unwrap(),
        learning_rate: q[5][1].parse().unwrap(), regularization: q[6][1].parse().unwrap(),
        epochs: q[7][1].parse().unwrap(), als_reg: q[8][1].parse().unwrap(),
        iterations: q[9][1].parse().unwrap(), seed: q[10][1].parse().unwrap(),
        top_n: q[11][1].parse().unwrap(), cutoffs: list(12), grid: list(13),
        user_groups: list(14), item_groups: list(15), buckets: q[16][1].parse().unwrap(),
        list_size: q[17][1].parse().unwrap(),
        recommend: q[18][1..].iter().map(|s| s.parse().unwrap()).collect(),
        similar: q[19][1..].iter().map(|s| s.parse().unwrap()).collect(),
    };
    let mut table = vec![vec![None; items.len()]; users.len()];
    for r in &train {
        table[r.user][r.item] = Some(r.rating);
    }
    let by_user: Vec<Vec<usize>> = table.iter().map(|r| (0..items.len()).filter(|&i| r[i].is_some()).collect()).collect();
    let by_item: Vec<Vec<usize>> = (0..items.len()).map(|i| (0..users.len()).filter(|&u| table[u][i].is_some()).collect()).collect();
    let user_mean = by_user.iter().enumerate().map(|(u, v)| v.iter().map(|&i| table[u][i].unwrap()).sum::<i64>() as f64 / v.len() as f64).collect();
    let item_mean = by_item.iter().enumerate().map(|(i, v)| v.iter().map(|&u| table[u][i].unwrap()).sum::<i64>() as f64 / v.len() as f64).collect();
    let mean = train.iter().map(|r| r.rating).sum::<i64>() as f64 / train.len() as f64;
    Ok(Data { users, items, catalog, train, test, table, by_user, by_item, user_mean, item_mean, mean, params })
}
