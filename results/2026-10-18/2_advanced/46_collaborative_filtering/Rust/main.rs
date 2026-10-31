mod ratings;
mod neighborhood;
mod factorization;
mod evaluation;
mod report;

use ratings::Data;
use report::{real, optional};
use std::{collections::{BTreeMap, BTreeSet}, io};

const METHODS: [&str; 7] = ["GLOBAL", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"];
const RANKINGS: [&str; 7] = ["POPULAR", "BASELINE", "USER_KNN", "ITEM_KNN", "SLOPE_ONE", "SVD", "ALS"];

struct Prediction {
    value: f64,
    top: Option<usize>,
    neighbors: usize,
    similarity: f64,
    fallback: bool,
}

impl Prediction {
    fn value(value: f64) -> Self {
        Self { value, top: None, neighbors: 0, similarity: 0.0, fallback: false }
    }
}

struct Engine<'a> {
    data: &'a Data,
    similarities: neighborhood::Similarities,
    users: Vec<f64>,
    items: Vec<f64>,
    baseline_log: Vec<f64>,
    svd: factorization::Svd,
    als: factorization::Als,
    popularity: Vec<usize>,
}

impl<'a> Engine<'a> {
    fn train(data: &'a Data) -> Self {
        let mut users = vec![0.0; data.users.len()];
        let mut items = vec![0.0; data.items.len()];
        let mut baseline_log = Vec::new();
        for _ in 0..10 {
            for i in 0..items.len() {
                let sum: f64 = data.by_item[i].iter().map(|&u| data.table[u][i].unwrap() as f64 - data.mean - users[u]).sum();
                items[i] = sum / (data.params.item_reg + data.by_item[i].len() as f64);
            }
            for u in 0..users.len() {
                let sum: f64 = data.by_user[u].iter().map(|&i| data.table[u][i].unwrap() as f64 - data.mean - items[i]).sum();
                users[u] = sum / (data.params.user_reg + data.by_user[u].len() as f64);
            }
            let errors: Vec<f64> = data.train.iter().map(|r| r.rating as f64 - ((data.mean + users[r.user]) + items[r.item])).collect();
            baseline_log.push(evaluation::rmse(&errors));
        }
        let similarities = neighborhood::build(data);
        let svd = factorization::svd(data);
        let als = factorization::als(data, &users, &items);
        let mut popularity: Vec<usize> = (0..items.len()).collect();
        popularity.sort_by(|&i, &j| data.by_item[j].len().cmp(&data.by_item[i].len())
            .then(data.item_mean[j].partial_cmp(&data.item_mean[i]).unwrap()).then(i.cmp(&j)));
        Self { data, similarities, users, items, baseline_log, svd, als, popularity }
    }

    fn baseline(&self, u: usize, i: usize) -> f64 {
        (self.data.mean + self.users[u]) + self.items[i]
    }

    fn predict(&self, method: usize, u: usize, i: usize, k: usize) -> Prediction {
        let d = self.data;
        let sims = &self.similarities;
        match method {
            0 => Prediction::value(d.mean),
            1 => Prediction::value(self.baseline(u, i)),
            2 | 3 => {
                let candidates = if method == 2 { &d.by_item[i] } else { &d.by_user[u] };
                let neighbors = neighborhood::select(candidates.iter().filter_map(|&j| {
                    let sim = if method == 2 { sims.users[u][j] } else { sims.items[i][j] };
                    sim.filter(|&s| s > d.params.minimum).map(|s| (j, s))
                }).collect(), k);
                if neighbors.is_empty() {
                    let mut prediction = Prediction::value(self.baseline(u, i));
                    prediction.fallback = true;
                    return prediction;
                }
                let mut numerator = 0.0;
                let mut denominator = 0.0;
                for &(j, similarity) in &neighbors {
                    let difference = if method == 2 {
                        d.table[j][i].unwrap() as f64 - d.user_mean[j]
                    } else {
                        d.table[u][j].unwrap() as f64 - d.item_mean[j]
                    };
                    numerator += similarity * difference;
                    denominator += similarity;
                }
                let center = if method == 2 { d.user_mean[u] } else { d.item_mean[i] };
                Prediction { value: center + numerator / denominator, top: Some(neighbors[0].0),
                    neighbors: neighbors.len(), similarity: denominator, fallback: false }
            }
            4 => {
                let mut numerator = 0.0;
                let mut denominator = 0i64;
                for &j in &d.by_user[u] {
                    let count = sims.common[i][j];
                    if count >= 1 {
                        let deviation = sims.differences[i][j] as f64 / (count + d.params.shrinkage) as f64;
                        numerator += (deviation + d.table[u][j].unwrap() as f64) * count as f64;
                        denominator += count;
                    }
                }
                if denominator == 0 {
                    let mut prediction = Prediction::value(self.baseline(u, i));
                    prediction.fallback = true;
                    prediction
                } else {
                    Prediction::value(numerator / denominator as f64)
                }
            }
            5 => Prediction::value(self.svd.predict(d.mean, u, i)),
            6 => Prediction::value(self.baseline(u, i) + factorization::dot(&self.als.x[u], &self.als.y[i])),
            _ => unreachable!(),
        }
    }

    fn ranked(&self, u: usize, method: usize) -> Vec<usize> {
        if method == 0 {
            return self.popularity.iter().copied().filter(|&i| self.data.table[u][i].is_none()).collect();
        }
        let mut predictions: Vec<(usize, f64)> = (0..self.data.items.len()).filter(|&i| self.data.table[u][i].is_none())
            .map(|i| (i, self.predict(method, u, i, self.data.params.neighbors).value)).collect();
        predictions.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap().then(a.0.cmp(&b.0)));
        predictions.iter().map(|r| r.0).collect()
    }
}

fn join_ints(values: &[usize]) -> String {
    values.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")
}

fn group(count: usize, boundaries: &[usize]) -> usize {
    boundaries.iter().filter(|&&b| count >= b).count()
}

fn metrics(errors: &[Vec<f64>], indices: &[usize], absolute: bool) -> String {
    (0..7).map(|method| {
        let values: Vec<f64> = indices.iter().map(|&i| errors[i][method]).collect();
        let value = if values.is_empty() { None }
            else if absolute { Some(evaluation::mae(&values)) } else { Some(evaluation::rmse(&values)) };
        format!("{} {}", METHODS[method], optional(value))
    }).collect::<Vec<_>>().join(" ")
}

fn count_summary(counts: &[usize]) -> (usize, f64, usize) {
    let mut values = counts.to_vec();
    values.sort();
    let n = values.len();
    let median = if n % 2 == 1 { values[n / 2] as f64 } else { (values[n / 2 - 1] + values[n / 2]) as f64 / 2.0 };
    (values[0], median, values[n - 1])
}

fn genres(data: &Data, u: usize, liked: bool) -> Vec<(String, usize)> {
    let mut counts = BTreeMap::new();
    for &i in &data.by_user[u] {
        let rating = data.table[u][i].unwrap();
        if (liked && rating >= 4) || (!liked && rating <= 2) {
            for genre in &data.catalog[&data.items[i]].genres {
                *counts.entry(genre.clone()).or_insert(0usize) += 1;
            }
        }
    }
    let mut result: Vec<_> = counts.into_iter().collect();
    result.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    result.truncate(3);
    result
}

fn genre_line(label: &str, values: &[(String, usize)]) -> String {
    format!("{} {}", label, if values.is_empty() { "-".into() } else {
        values.iter().map(|(name, count)| format!("{} {}", name, count)).collect::<Vec<_>>().join(" ")
    })
}

fn recommendations(engine: &Engine, lists: &[Vec<Vec<usize>>], predictions: &[Vec<Prediction>]) -> Vec<String> {
    let d = engine.data;
    let mut lines = Vec::new();
    for (request, &id) in d.params.recommend.iter().enumerate() {
        if request > 0 {
            lines.push(String::new());
        }
        let u = match d.users.binary_search(&id) {
            Ok(u) => u,
            Err(_) => {
                lines.extend([format!("user {} unknown", id), "list POPULAR".into()]);
                for (rank, &i) in engine.popularity.iter().take(d.params.top_n).enumerate() {
                    lines.push(format!("  {} {} count {} mean {} {}", rank + 1, d.items[i], d.by_item[i].len(), real(d.item_mean[i]), d.catalog[&d.items[i]].title));
                }
                continue;
            }
        };
        lines.push(format!("user {} ratings {} mean {} bias {}", id, d.by_user[u].len(), real(d.user_mean[u]), real(engine.users[u])));
        let liked = genres(d, u, true);
        lines.push(genre_line("liked_genres", &liked));
        lines.push(genre_line("disliked_genres", &genres(d, u, false)));
        let mut recent: Vec<usize> = (0..d.train.len()).filter(|&t| d.train[t].user == u).collect();
        recent.sort_by(|&a, &b| d.train[b].time.cmp(&d.train[a].time).then(d.train[a].item.cmp(&d.train[b].item)));
        lines.push(format!("recent {}", recent.iter().take(3).map(|&t| format!("{} {}", d.items[d.train[t].item], d.train[t].rating)).collect::<Vec<_>>().join(" ")));
        let neighbors = neighborhood::select((0..d.users.len()).filter_map(|v| engine.similarities.users[u][v]
            .filter(|&s| s > d.params.minimum).map(|s| (v, s))).collect(), d.params.list_size);
        for (v, similarity) in neighbors {
            lines.push(format!("neighbor {} similarity {} common {}", d.users[v], real(similarity), engine.similarities.user_common[u][v]));
        }
        for (t, r) in d.test.iter().enumerate().filter(|(_, r)| r.user == u) {
            lines.push(format!("heldout {} actual {} {}", d.items[r.item], r.rating, predictions[t].iter()
                .map(|p| real(evaluation::clip(p.value))).collect::<Vec<_>>().join(" ")));
        }
        for method in 0..7 {
            let list = &lists[u][method][..d.params.top_n];
            let matched = list.iter().filter(|&&i| d.catalog[&d.items[i]].genres.iter().any(|g| liked.iter().any(|(l, _)| l == g))).count();
            lines.push(format!("list {} genre_match {}", RANKINGS[method], matched));
            for (rank, &i) in list.iter().enumerate() {
                let title = &d.catalog[&d.items[i]].title;
                let prefix = format!("  {} {}", rank + 1, d.items[i]);
                if method == 0 {
                    lines.push(format!("{} count {} mean {} {}", prefix, d.by_item[i].len(), real(d.item_mean[i]), title));
                } else {
                    let prediction = engine.predict(method, u, i, d.params.neighbors);
                    if method == 2 || method == 3 {
                        let top = prediction.top.map_or("-".into(), |j| (if method == 2 { d.users[j] } else { d.items[j] }).to_string());
                        lines.push(format!("{} {} via {} {}", prefix, real(prediction.value), top, title));
                    } else {
                        lines.push(format!("{} {} {}", prefix, real(prediction.value), title));
                    }
                }
            }
        }
    }
    lines
}

fn similar_items(engine: &Engine) -> Vec<String> {
    let d = engine.data;
    let sims = &engine.similarities;
    let mut lines = Vec::new();
    for (request, &id) in d.params.similar.iter().enumerate() {
        if request > 0 {
            lines.push(String::new());
        }
        let i = d.items.binary_search(&id).unwrap();
        let item = &d.catalog[&id];
        lines.push(format!("item {} ratings {} mean {} bias {} genres {} title {}", id, d.by_item[i].len(),
            real(d.item_mean[i]), real(engine.items[i]), item.genres.join("|"), item.title));
        lines.push("cosine".into());
        let cosine = neighborhood::select((0..d.items.len()).filter_map(|j| sims.items[i][j].map(|s| (j, s))).collect(), d.params.list_size);
        for (rank, (j, value)) in cosine.iter().enumerate() {
            lines.push(format!("  {} {} similarity {} common {} {}", rank + 1, d.items[*j], real(*value), sims.common[i][*j], d.catalog[&d.items[*j]].title));
        }
        lines.push("factors".into());
        let factors = neighborhood::select((0..d.items.len()).filter(|&j| j != i).map(|j| {
            let a = &engine.svd.q[i];
            let b = &engine.svd.q[j];
            let similarity = factorization::dot(a, b) / (factorization::dot(a, a) * factorization::dot(b, b)).sqrt();
            (j, similarity)
        }).collect(), d.params.list_size);
        for (rank, (j, value)) in factors.iter().enumerate() {
            lines.push(format!("  {} {} similarity {} {}", rank + 1, d.items[*j], real(*value), d.catalog[&d.items[*j]].title));
        }
        let mut common: Vec<usize> = (0..d.items.len()).filter(|&j| j != i && sims.common[i][j] >= 1).collect();
        common.sort_by(|&a, &b| sims.common[i][b].cmp(&sims.common[i][a]).then(a.cmp(&b)));
        lines.push("co_rated".into());
        for (rank, &j) in common.iter().take(d.params.list_size).enumerate() {
            lines.push(format!("  {} {} common {} {}", rank + 1, d.items[j], sims.common[i][j], d.catalog[&d.items[j]].title));
        }
        common.sort_by(|&a, &b| {
            let da = sims.differences[a][i] as f64 / (sims.common[a][i] + d.params.shrinkage) as f64;
            let db = sims.differences[b][i] as f64 / (sims.common[b][i] + d.params.shrinkage) as f64;
            db.partial_cmp(&da).unwrap().then(sims.common[b][i].cmp(&sims.common[a][i])).then(a.cmp(&b))
        });
        lines.push("slope_one".into());
        for (rank, &j) in common.iter().take(d.params.list_size).enumerate() {
            lines.push(format!("  {} {} difference {} common {} {}", rank + 1, d.items[j], sims.differences[j][i], sims.common[j][i], d.catalog[&d.items[j]].title));
        }
    }
    lines
}

fn main() -> io::Result<()> {
    let d = ratings::read()?;
    let engine = Engine::train(&d);
    let params = &d.params;
    let nu = d.users.len();
    let ni = d.items.len();
    let m = d.test.len();
    let predictions: Vec<Vec<Prediction>> = d.test.iter().map(|r| (0..7).map(|method| engine.predict(method, r.user, r.item, params.neighbors)).collect()).collect();
    let q: Vec<Vec<f64>> = predictions.iter().map(|row| row.iter().map(|p| evaluation::clip(p.value)).collect()).collect();
    let errors: Vec<Vec<f64>> = q.iter().zip(&d.test).map(|(row, r)| row.iter().map(|x| x - r.rating as f64).collect()).collect();
    let mut prediction_lines = vec!["user,item,actual,GLOBAL,BASELINE,USER_KNN,ITEM_KNN,SLOPE_ONE,SVD,ALS".into()];
    for (t, r) in d.test.iter().enumerate() {
        prediction_lines.push(format!("{},{},{},{}", d.users[r.user], d.items[r.item], r.rating, q[t].iter().map(|&v| real(v)).collect::<Vec<_>>().join(",")));
    }
    let lists: Vec<Vec<Vec<usize>>> = (0..nu).map(|u| (0..7).map(|method| engine.ranked(u, method)).collect()).collect();
    let relevant: Vec<BTreeSet<usize>> = (0..nu).map(|u| d.test.iter().filter(|r| r.user == u && r.rating >= 4).map(|r| r.item).collect()).collect();
    let evaluated: Vec<usize> = (0..nu).filter(|&u| !relevant[u].is_empty()).collect();
    let e = evaluated.len();
    let mut parts: Vec<Vec<String>> = Vec::new();
    let mut histogram = [0usize; 5];
    for r in &d.train {
        histogram[(r.rating - 1) as usize] += 1;
    }
    let (umin, umedian, umax) = count_summary(&d.by_user.iter().map(Vec::len).collect::<Vec<_>>());
    let (imin, imedian, imax) = count_summary(&d.by_item.iter().map(Vec::len).collect::<Vec<_>>());
    let first = d.train.iter().map(|r| r.time).min().unwrap();
    let last = d.train.iter().map(|r| r.time).max().unwrap();
    let sims = &engine.similarities;
    let user_pairs: Vec<(usize, usize)> = (0..nu).flat_map(|u| (u + 1..nu).map(move |v| (u, v))).collect();
    let item_pairs: Vec<(usize, usize)> = (0..ni).flat_map(|i| (i + 1..ni).map(move |j| (i, j))).collect();
    parts.push(vec![format!("data users {} items {} catalog {} ratings {} test {}", nu, ni, d.catalog.len(), d.train.len(), m),
        format!("density {} global_mean {}", real(d.train.len() as f64 / (nu * ni) as f64), real(d.mean)),
        format!("histogram {}", join_ints(&histogram)), format!("user_ratings min {} median {} max {}", umin, real(umedian), umax),
        format!("item_ratings min {} median {} max {}", imin, real(imedian), imax), format!("timestamps first {} last {}", first, last),
        format!("cold_items {}", d.catalog.len() - ni), format!("similarities user_pairs {} usable {} item_pairs {} usable {} slope_pairs {}",
            user_pairs.iter().filter(|&&(u, v)| sims.users[u][v].is_some()).count(),
            user_pairs.iter().filter(|&&(u, v)| sims.users[u][v].map_or(false, |s| s > params.minimum)).count(),
            item_pairs.iter().filter(|&&(i, j)| sims.items[i][j].is_some()).count(),
            item_pairs.iter().filter(|&&(i, j)| sims.items[i][j].map_or(false, |s| s > params.minimum)).count(),
            item_pairs.iter().filter(|&&(i, j)| sims.common[i][j] >= 1).count())]);
    let all_genres: BTreeSet<String> = d.items.iter().flat_map(|id| d.catalog[id].genres.iter().cloned()).collect();
    let mut lines = vec!["genre_stats".into()];
    for genre in &all_genres {
        let items: BTreeSet<usize> = (0..ni).filter(|&i| d.catalog[&d.items[i]].genres.contains(genre)).collect();
        let count: usize = items.iter().map(|&i| d.by_item[i].len()).sum();
        let high = d.train.iter().filter(|r| items.contains(&r.item) && r.rating >= 4).count();
        lines.push(format!("genre {} items {} ratings {} high {}", genre, items.len(), count, high));
    }
    parts.push(lines);
    let mut lines = vec![format!("time_buckets {}", params.buckets)];
    for bucket in 0..params.buckets {
        let ratings: Vec<_> = d.train.iter().filter(|r| ((r.time - first) * params.buckets as i64 / (last - first + 1)) as usize == bucket).collect();
        let users: BTreeSet<usize> = ratings.iter().map(|r| r.user).collect();
        let mean = if ratings.is_empty() { None } else { Some(ratings.iter().map(|r| r.rating).sum::<i64>() as f64 / ratings.len() as f64) };
        lines.push(format!("bucket {} ratings {} users {} mean {}", bucket + 1, ratings.len(), users.len(), optional(mean)));
    }
    parts.push(lines);
    let test_rmse: Vec<f64> = (0..7).map(|j| evaluation::rmse(&errors.iter().map(|r| r[j]).collect::<Vec<_>>())).collect();
    let mut lines = vec!["rating_metrics".into()];
    for j in 0..7 {
        let column: Vec<f64> = errors.iter().map(|r| r[j]).collect();
        lines.push(format!("{} rmse {} mae {} clipped {} fallback {}", METHODS[j], real(test_rmse[j]), real(evaluation::mae(&column)),
            predictions.iter().filter(|r| r[j].value < 1.0 || r[j].value > 5.0).count(), predictions.iter().filter(|r| r[j].fallback).count()));
    }
    parts.push(lines);
    let global_train = evaluation::rmse(&d.train.iter().map(|r| r.rating as f64 - d.mean).collect::<Vec<_>>());
    let mut lines = vec!["generalization".into()];
    for (j, train) in [(0, global_train), (1, *engine.baseline_log.last().unwrap()), (5, *engine.svd.log.last().unwrap()), (6, *engine.als.log.last().unwrap())] {
        lines.push(format!("{} train {} test {} gap {}", METHODS[j], real(train), real(test_rmse[j]), real(test_rmse[j] - train)));
    }
    parts.push(lines);
    let mut lines = vec![format!("neighborhoods k {}", params.neighbors)];
    for method in 2..=3 {
        let used: Vec<&Prediction> = predictions.iter().map(|r| &r[method]).filter(|p| !p.fallback).collect();
        let count = used.len();
        let neighbors = if count == 0 { None } else { Some(used.iter().map(|p| p.neighbors).sum::<usize>() as f64 / count as f64) };
        let similarity = if count == 0 { None } else { Some(used.iter().map(|p| p.similarity / p.neighbors as f64).sum::<f64>() / count as f64) };
        lines.push(format!("{} predictions {} with_neighbors {} mean_neighbors {} mean_similarity {}", METHODS[method], m, count, optional(neighbors), optional(similarity)));
    }
    parts.push(lines);
    let actual_mean = d.test.iter().map(|r| r.rating).sum::<i64>() as f64 / m as f64;
    let actual_ss = d.test.iter().map(|r| (r.rating as f64 - actual_mean) * (r.rating as f64 - actual_mean)).sum::<f64>();
    let mut lines = vec![format!("prediction_stats actual mean {} std {}", real(actual_mean), real((actual_ss / m as f64).sqrt()))];
    for j in 0..7 {
        let mean = q.iter().map(|r| r[j]).sum::<f64>() / m as f64;
        let ss = q.iter().map(|r| (r[j] - mean) * (r[j] - mean)).sum::<f64>();
        let numerator = q.iter().zip(&d.test).map(|(r, a)| (r[j] - mean) * (a.rating as f64 - actual_mean)).sum::<f64>();
        let constant = q.iter().all(|r| r[j] == q[0][j]);
        let correlation = if constant || actual_ss == 0.0 { None } else { Some(numerator / (ss * actual_ss).sqrt()) };
        lines.push(format!("{} mean {} std {} correlation {}", METHODS[j], real(mean), real((ss / m as f64).sqrt()), optional(correlation)));
    }
    parts.push(lines);
    let mut lines = vec!["error_bins edges 0.5 1.0 1.5 2.0".into()];
    for j in 0..7 {
        let mut bins = [0usize; 5];
        for row in &errors {
            let bin = ((row[j].abs() / 0.5).floor() as usize).min(4);
            bins[bin] += 1;
        }
        lines.push(format!("{} {}", METHODS[j], join_ints(&bins)));
    }
    parts.push(lines);
    let mut lines = vec!["comparison".into()];
    for a in 0..6 {
        for b in a + 1..7 {
            let wins = errors.iter().filter(|r| r[a].abs() < r[b].abs()).count();
            let ties = errors.iter().filter(|r| r[a].abs() == r[b].abs()).count();
            lines.push(format!("{} {} wins {} ties {} losses {}", METHODS[a], METHODS[b], wins, ties, m - wins - ties));
        }
    }
    parts.push(lines);
    for (label, boundaries, user) in [("user_groups", &params.user_groups, true), ("item_groups", &params.item_groups, false)] {
        let mut lines = vec![format!("{} bounds {}", label, join_ints(boundaries))];
        for g in 0..=boundaries.len() {
            let indices: Vec<usize> = (0..m).filter(|&t| {
                let r = &d.test[t];
                let count = if user { d.by_user[r.user].len() } else { d.by_item[r.item].len() };
                group(count, boundaries) == g
            }).collect();
            let low = if g == 0 { 1 } else { boundaries[g - 1] };
            let high = if g == boundaries.len() { "-".into() } else { (boundaries[g] - 1).to_string() };
            lines.push(format!("group {} from {} to {} pairs {} {}", g + 1, low, high, indices.len(), metrics(&errors, &indices, false)));
        }
        parts.push(lines);
    }
    let mut lines = vec!["by_rating".into()];
    for value in 1..=5 {
        let indices: Vec<usize> = (0..m).filter(|&t| d.test[t].rating == value).collect();
        lines.push(format!("rating {} pairs {} {}", value, indices.len(), metrics(&errors, &indices, true)));
    }
    parts.push(lines);
    let test_genres: BTreeSet<String> = d.test.iter().flat_map(|r| d.catalog[&d.items[r.item]].genres.iter().cloned()).collect();
    let mut lines = vec!["genres".into()];
    for genre in test_genres {
        let indices: Vec<usize> = (0..m).filter(|&t| d.catalog[&d.items[d.test[t].item]].genres.contains(&genre)).collect();
        lines.push(format!("genre {} pairs {} {}", genre, indices.len(), metrics(&errors, &indices, false)));
    }
    parts.push(lines);
    let mut lines = vec![format!("ranking users {} relevant {}", e, evaluated.iter().map(|&u| relevant[u].len()).sum::<usize>())];
    for &c in &params.cutoffs {
        lines.push(format!("cutoff {}", c));
        for method in 0..7 {
            let values: Vec<_> = evaluated.iter().map(|&u| evaluation::ranking(&lists[u][method], &relevant[u], c)).collect();
            lines.push(format!("  {} precision {} recall {} ndcg {} map {} mrr {} hit_rate {}", RANKINGS[method],
                real(values.iter().map(|v| v.hits).sum::<usize>() as f64 / (c * e) as f64),
                real(values.iter().map(|v| v.recall).sum::<f64>() / e as f64), real(values.iter().map(|v| v.ndcg).sum::<f64>() / e as f64),
                real(values.iter().map(|v| v.ap).sum::<f64>() / e as f64), real(values.iter().map(|v| v.rr).sum::<f64>() / e as f64),
                real(values.iter().filter(|v| v.hits >= 1).count() as f64 / e as f64)));
        }
    }
    parts.push(lines);
    let head = ni / 5;
    let popular: BTreeSet<usize> = engine.popularity[..head].iter().copied().collect();
    let mut lines = vec![format!("beyond_accuracy top_n {} head {}", params.top_n, head)];
    for method in 0..7 {
        let mut union = BTreeSet::new();
        let (mut diversity, mut novelty, mut similarity) = (0usize, 0.0, 0.0);
        let (mut popularity, mut tail) = (0usize, 0usize);
        for &u in &evaluated {
            let list = &lists[u][method][..params.top_n];
            union.extend(list.iter().copied());
            let genres: BTreeSet<&str> = list.iter().flat_map(|&i| d.catalog[&d.items[i]].genres.iter().map(String::as_str)).collect();
            diversity += genres.len();
            let mut nov = 0.0;
            for &i in list {
                nov += (nu as f64 / d.by_item[i].len() as f64).log2();
                popularity += d.by_item[i].len();
                if !popular.contains(&i) {
                    tail += 1;
                }
            }
            novelty += nov / params.top_n as f64;
            let mut ils = 0.0;
            for a in 0..params.top_n - 1 {
                for b in a + 1..params.top_n {
                    ils += sims.items[list[a]][list[b]].unwrap_or(0.0);
                }
            }
            similarity += ils / (params.top_n * (params.top_n - 1) / 2) as f64;
        }
        lines.push(format!("{} coverage {} diversity {} novelty {} popularity {} long_tail {} similarity {}", RANKINGS[method],
            real(union.len() as f64 / ni as f64), real(diversity as f64 / e as f64), real(novelty / e as f64),
            real(popularity as f64 / (params.top_n * e) as f64), real(tail as f64 / (params.top_n * e) as f64), real(similarity / e as f64)));
    }
    parts.push(lines);
    let mut lines = vec![format!("ranking_groups top_n {} bounds {}", params.top_n, join_ints(&params.user_groups))];
    for g in 0..=params.user_groups.len() {
        let users: Vec<usize> = evaluated.iter().copied().filter(|&u| group(d.by_user[u].len(), &params.user_groups) == g).collect();
        let pairs: Vec<String> = (0..7).map(|method| {
            let value = if users.is_empty() { None } else { Some(users.iter().map(|&u|
                evaluation::ranking(&lists[u][method], &relevant[u], params.top_n).ndcg).sum::<f64>() / users.len() as f64) };
            format!("{} {}", RANKINGS[method], optional(value))
        }).collect();
        lines.push(format!("group {} users {} {}", g + 1, users.len(), pairs.join(" ")));
    }
    parts.push(lines);
    let mut lines = vec![format!("agreement top_n {}", params.top_n)];
    for a in 0..6 {
        for b in a + 1..7 {
            let mut total = 0.0;
            for &u in &evaluated {
                let left: BTreeSet<usize> = lists[u][a][..params.top_n].iter().copied().collect();
                let right: BTreeSet<usize> = lists[u][b][..params.top_n].iter().copied().collect();
                total += left.intersection(&right).count() as f64 / left.union(&right).count() as f64;
            }
            lines.push(format!("{} {} jaccard {}", RANKINGS[a], RANKINGS[b], real(total / e as f64)));
        }
    }
    parts.push(lines);
    let mut lines = vec!["neighbor_grid".into()];
    let mut best = [(params.grid[0], f64::INFINITY); 2];
    for &k in &params.grid {
        let mut values = [0.0; 2];
        for j in 0..2 {
            let errors: Vec<f64> = d.test.iter().map(|r| evaluation::clip(engine.predict(j + 2, r.user, r.item, k).value) - r.rating as f64).collect();
            values[j] = evaluation::rmse(&errors);
            if values[j] < best[j].1 {
                best[j] = (k, values[j]);
            }
        }
        lines.push(format!("k {} USER_KNN {} ITEM_KNN {}", k, real(values[0]), real(values[1])));
    }
    lines.push(format!("best USER_KNN {} ITEM_KNN {}", best[0].0, best[1].0));
    parts.push(lines);
    let mut lines = vec!["biases".into()];
    for (label, values, item, high) in [("item_high", &engine.items, true, true), ("item_low", &engine.items, true, false),
        ("user_high", &engine.users, false, true), ("user_low", &engine.users, false, false)] {
        let mut order: Vec<usize> = (0..values.len()).collect();
        order.sort_by(|&a, &b| {
            let cmp = if high { values[b].partial_cmp(&values[a]) } else { values[a].partial_cmp(&values[b]) };
            cmp.unwrap().then(a.cmp(&b))
        });
        for &j in order.iter().take(params.list_size) {
            if item {
                lines.push(format!("{} {} bias {} count {} mean {} {}", label, d.items[j], real(values[j]), d.by_item[j].len(), real(d.item_mean[j]), d.catalog[&d.items[j]].title));
            } else {
                lines.push(format!("{} {} bias {} count {} mean {}", label, d.users[j], real(values[j]), d.by_user[j].len(), real(d.user_mean[j])));
            }
        }
    }
    parts.push(lines);
    let mut evaluation_lines = Vec::new();
    for (i, part) in parts.into_iter().enumerate() {
        if i > 0 {
            evaluation_lines.push(String::new());
        }
        evaluation_lines.extend(part);
    }
    let mut log = vec!["method,epoch,train_rmse".into()];
    for (method, values) in [("BASELINE", &engine.baseline_log), ("SVD", &engine.svd.log), ("ALS", &engine.als.log)] {
        for (epoch, &value) in values.iter().enumerate() {
            log.push(format!("{},{},{}", method, epoch + 1, real(value)));
        }
    }
    report::write("predictions.csv", &prediction_lines)?;
    report::write("evaluation.txt", &evaluation_lines)?;
    report::write("recommendations.txt", &recommendations(&engine, &lists, &predictions))?;
    report::write("similar_items.txt", &similar_items(&engine))?;
    report::write("training_log.csv", &log)?;
    Ok(())
}
