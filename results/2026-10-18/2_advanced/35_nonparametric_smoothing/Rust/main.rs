mod dataset;
mod kernels;
mod loess;
mod selection;
mod spline;

use dataset::{hundredths, Point, Series};
use selection::sum;
use std::collections::BTreeMap;
use std::fs;

#[derive(Clone)]
struct Block {
    first: usize,
    last: usize,
    total: i64,
    count: i64,
}

fn isotonic(points: &[Point], increasing: bool) -> (Vec<f64>, Vec<Block>) {
    let mut blocks: Vec<Block> = Vec::new();
    for (index, point) in points.iter().enumerate() {
        blocks.push(Block { first: index, last: index, total: point.y, count: 1 });
        while blocks.len() >= 2 {
            let a = &blocks[blocks.len() - 2];
            let b = &blocks[blocks.len() - 1];
            let comparison = a.total * b.count - b.total * a.count;
            if (increasing && comparison <= 0) || (!increasing && comparison >= 0) { break; }
            let b = blocks.pop().unwrap();
            let a = blocks.last_mut().unwrap();
            a.last = b.last;
            a.total += b.total;
            a.count += b.count;
        }
    }
    let mut fitted = vec![0.0; points.len()];
    for block in &blocks {
        let value = block.total as f64 / (100 * block.count) as f64;
        fitted[block.first..=block.last].fill(value);
    }
    (fitted, blocks)
}

fn residuals(points: &[Point], fitted: &[f64]) -> Vec<f64> {
    points.iter().zip(fitted).map(|(p, &f)| p.y as f64 / 100.0 - f).collect()
}

fn squares(values: &[f64]) -> f64 { sum(values.iter().map(|&v| v * v)) }

fn linear(points: &[Point]) -> (f64, f64, f64, f64) {
    let n = points.len() as f64;
    let xbar = sum(points.iter().map(|p| p.x as f64 / 100.0)) / n;
    let ybar = sum(points.iter().map(|p| p.y as f64 / 100.0)) / n;
    let sxx = sum(points.iter().map(|p| {
        let d = p.x as f64 / 100.0 - xbar;
        d * d
    }));
    let sxy = sum(points.iter().map(|p| (p.x as f64 / 100.0 - xbar) * (p.y as f64 / 100.0 - ybar)));
    let slope = sxy / sxx;
    (ybar - slope * xbar, slope, xbar, sxx)
}

enum Core {
    Linear(f64, f64, f64, f64),
    Window(usize),
    Kernel(String, i64, bool),
    Loess(loess::Loess),
    Spline(spline::Spline),
    Isotonic(Vec<Block>),
}

struct Fit {
    points: Vec<Point>,
    method: String,
    parameter: String,
    core: Core,
    fitted: Vec<f64>,
    leverage: Option<Vec<f64>>,
    edf: Option<f64>,
}

impl Fit {
    fn build(points: &[Point], method: &str, parameter: &str, robust: usize, full: bool) -> Self {
        let n = points.len();
        let mut fitted = Vec::new();
        let mut leverage = None;
        let mut edf = None;
        let core = if method == "linear" {
            let (a, b, xbar, sxx) = linear(points);
            fitted = points.iter().map(|p| a + b * (p.x as f64 / 100.0)).collect();
            leverage = Some(points.iter().map(|p| {
                let d = p.x as f64 / 100.0 - xbar;
                1.0 / n as f64 + d * d / sxx
            }).collect());
            edf = Some(2.0);
            Core::Linear(a, b, xbar, sxx)
        } else if method.starts_with("running_") {
            let width: usize = parameter.parse().unwrap();
            let mut diagonal = Vec::new();
            for i in 0..n {
                let r = ((width - 1) / 2).min(i).min(n - 1 - i);
                let window = &points[i - r..=i + r];
                let value = if method == "running_mean" {
                    window.iter().map(|p| p.y).sum::<i64>() as f64 / (100 * window.len()) as f64
                } else {
                    let mut y: Vec<_> = window.iter().map(|p| p.y).collect();
                    y.sort_unstable();
                    y[r] as f64 / 100.0
                };
                fitted.push(value);
                diagonal.push(1.0 / window.len() as f64);
            }
            if method == "running_mean" {
                edf = Some(sum(diagonal.iter().copied()));
                leverage = Some(diagonal);
            }
            Core::Window(width)
        } else if method.starts_with("nw_") || method.starts_with("ll_") {
            let kernel = method[3..].to_string();
            let bandwidth = hundredths(parameter);
            let local_linear = method.starts_with("ll_");
            if full {
                let results: Vec<_> = points.iter().map(|p| kernels::estimate(points, p.x, bandwidth, &kernel, local_linear)).collect();
                if results.iter().all(Option::is_some) {
                    fitted = results.iter().map(|r| r.as_ref().unwrap().0).collect();
                    let diagonal: Vec<_> = results.iter().enumerate().map(|(i, r)| r.as_ref().unwrap().1[i]).collect();
                    edf = Some(sum(diagonal.iter().copied()));
                    leverage = Some(diagonal);
                }
            }
            Core::Kernel(kernel, bandwidth, local_linear)
        } else if method.starts_with("loess") {
            let degree = method[5..].parse().unwrap();
            let fit = loess::Loess::new(points, hundredths(parameter), degree, robust, full);
            if full {
                fitted = fit.fitted.clone();
                leverage = Some(fit.leverage.clone());
                edf = Some(fit.edf);
            }
            Core::Loess(fit)
        } else if method == "spline" {
            let positions: Vec<_> = points.iter().map(|p| p.x).collect();
            let values: Vec<_> = points.iter().map(|p| p.y as f64 / 100.0).collect();
            let fit = spline::Spline::new(&positions, &values, parameter.parse().unwrap(), full);
            fitted = fit.curve.0.clone();
            if full {
                leverage = Some(fit.leverage.clone());
                edf = Some(fit.edf);
            }
            Core::Spline(fit)
        } else {
            let (values, blocks) = isotonic(points, parameter == "increasing");
            fitted = values;
            edf = Some(blocks.len() as f64);
            Core::Isotonic(blocks)
        };
        Self { points: points.to_vec(), method: method.into(), parameter: parameter.into(), core, fitted, leverage, edf }
    }

    fn estimate(&self, position: i64) -> Option<f64> {
        match &self.core {
            Core::Linear(a, b, _, _) => Some(a + b * (position as f64 / 100.0)),
            Core::Window(_) => {
                let nearest = (0..self.points.len()).min_by_key(|&i| ((self.points[i].x - position).abs(), i)).unwrap();
                Some(self.fitted[nearest])
            }
            Core::Kernel(kernel, bandwidth, local_linear) => kernels::estimate(&self.points, position, *bandwidth, kernel, *local_linear).map(|r| r.0),
            Core::Loess(fit) => Some(fit.local(&self.points, position).0),
            Core::Spline(fit) => Some(fit.estimate(position)),
            Core::Isotonic(_) => {
                let after = self.points.partition_point(|p| p.x <= position);
                Some(self.fitted[after.saturating_sub(1)])
            }
        }
    }

    fn weights(&self, position: i64) -> Option<Vec<f64>> {
        match &self.core {
            Core::Linear(_, _, xbar, sxx) => Some(self.points.iter().map(|p| {
                1.0 / self.points.len() as f64 + (position as f64 / 100.0 - xbar) * (p.x as f64 / 100.0 - xbar) / sxx
            }).collect()),
            Core::Window(width) if self.method == "running_mean" => {
                let n = self.points.len();
                let c = (0..n).min_by_key(|&i| ((self.points[i].x - position).abs(), i)).unwrap();
                let r = ((width - 1) / 2).min(c).min(n - 1 - c);
                let mut weights = vec![0.0; n];
                weights[c - r..=c + r].fill(1.0 / (2 * r + 1) as f64);
                Some(weights)
            }
            Core::Kernel(kernel, bandwidth, local_linear) => kernels::estimate(&self.points, position, *bandwidth, kernel, *local_linear).map(|r| r.1),
            Core::Loess(fit) => Some(fit.local(&self.points, position).2),
            Core::Spline(fit) => Some(fit.weights(position)),
            _ => None,
        }
    }
}

fn cross_validate(points: &[Point], method: &str, parameter: &str, folds: Option<usize>) -> Option<f64> {
    let groups = folds.unwrap_or(points.len());
    let mut predictions = vec![None; points.len()];
    for group in 0..groups {
        let subset: Vec<_> = points.iter().enumerate().filter(|(i, _)| i % groups != group).map(|(_, p)| p.clone()).collect();
        let fit = Fit::build(&subset, method, parameter, 0, false);
        for (i, point) in points.iter().enumerate().filter(|(i, _)| i % groups == group) { predictions[i] = fit.estimate(point.x); }
    }
    let values: Vec<_> = points.iter().map(|p| p.y as f64 / 100.0).collect();
    selection::cv(&values, &predictions)
}

fn number(value: f64) -> String {
    if value.abs() < 0.00005 { "0.0000".into() } else { format!("{value:.4}") }
}

fn optional(value: Option<f64>) -> String { value.map_or_else(|| "NA".into(), number) }

fn position(value: i64) -> String {
    format!("{}{}.{:02}", if value < 0 { "-" } else { "" }, value.abs() / 100, value.abs() % 100)
}

fn param_usize(params: &BTreeMap<String, Vec<String>>, name: &str) -> usize { params[name][0].parse().unwrap() }

fn methods(params: &BTreeMap<String, Vec<String>>) -> Vec<String> {
    let mut methods = vec!["linear".into(), "running_mean".into(), "running_median".into()];
    for prefix in ["nw", "ll"] { methods.extend(params["KERNELS"].iter().map(|k| format!("{prefix}_{k}"))); }
    methods.extend(params["LOESS_DEGREES"].iter().map(|p| format!("loess{p}")));
    methods.extend(["spline".into(), "isotonic".into()]);
    methods
}

struct ResultSet {
    fits: Vec<Fit>,
    loo: Vec<f64>,
    kfold: Vec<Option<f64>>,
    gcv: f64,
    grid: Vec<i64>,
    estimates: Vec<Vec<Option<f64>>>,
    residuals: Vec<Vec<f64>>,
    rss: Vec<f64>,
    rse: Vec<Option<f64>>,
    ranking: Vec<usize>,
    outlier_method: usize,
    standardized: Vec<(usize, f64)>,
    isotonic_rss: (f64, f64),
}

fn fit_series(series: &Series, series_index: usize, params: &BTreeMap<String, Vec<String>>, methods: &[String], selection_lines: &mut Vec<String>) -> ResultSet {
    let points = &series.points;
    let n = points.len();
    let increasing_rss = squares(&residuals(points, &isotonic(points, true).0));
    let decreasing_rss = squares(&residuals(points, &isotonic(points, false).0));
    let mode = &params["ISOTONIC"][series_index];
    let direction = if mode == "auto" { if increasing_rss <= decreasing_rss { "increasing" } else { "decreasing" } } else { mode };
    let robust = param_usize(params, "ROBUST_ITERATIONS");
    let mut fits = Vec::new();
    let mut loo = Vec::new();
    let mut selected_gcv = 0.0;
    for method in methods {
        let key = if method.starts_with("running_") { "WINDOWS" }
            else if method.starts_with("nw_") || method.starts_with("ll_") { "BANDWIDTHS" }
            else if method.starts_with("loess") { "SPANS" }
            else if method == "spline" { "LAMBDAS" } else { "" };
        let (parameter, score) = if key.is_empty() {
            (if method == "isotonic" { direction.to_string() } else { "-".into() }, None)
        } else {
            let mut scores = Vec::new();
            let mut edfs = Vec::new();
            for candidate in &params[key] {
                let fit = Fit::build(points, method, candidate, 0, true);
                let score = if method == "spline" {
                    Some(selection::gcv(squares(&residuals(points, &fit.fitted)), fit.edf.unwrap(), n))
                } else { cross_validate(points, method, candidate, None) };
                scores.push(score);
                edfs.push(fit.edf);
            }
            let selected = selection::select(&scores);
            for (i, candidate) in params[key].iter().enumerate() {
                selection_lines.push(format!("{},{},{},{},{},{}", series.name, method, candidate, optional(scores[i]), optional(edfs[i]), usize::from(i == selected)));
            }
            if method == "spline" { selected_gcv = scores[selected].unwrap(); }
            (params[key][selected].clone(), scores[selected])
        };
        let fit = Fit::build(points, method, &parameter, robust, true);
        let cv = if key.is_empty() || method == "spline" { cross_validate(points, method, &parameter, None).unwrap() } else { score.unwrap() };
        loo.push(cv);
        fits.push(fit);
    }
    let grid_count = param_usize(params, "GRID_POINTS");
    let first = points[0].x;
    let last = points[n - 1].x;
    let grid: Vec<_> = (0..grid_count).map(|k| first + k as i64 * (last - first) / (grid_count - 1) as i64).collect();
    let estimates = fits.iter().map(|fit| grid.iter().map(|&x| fit.estimate(x)).collect()).collect();
    let residuals: Vec<_> = fits.iter().map(|fit| residuals(points, &fit.fitted)).collect();
    let rss: Vec<_> = residuals.iter().map(|e| squares(e)).collect();
    let rse: Vec<_> = fits.iter().enumerate().map(|(i, fit)| fit.edf.map(|edf| (rss[i] / (n as f64 - edf)).sqrt())).collect();
    let kfold = fits.iter().map(|fit| cross_validate(points, &fit.method, &fit.parameter, Some(param_usize(params, "CV_FOLDS")))).collect();
    let mut ranking: Vec<_> = (0..methods.len()).collect();
    ranking.sort_by(|&a, &b| loo[a].total_cmp(&loo[b]).then(a.cmp(&b)));
    let outlier_method = *ranking.iter().find(|&&i| fits[i].leverage.is_some()).unwrap();
    let standardized = fits[outlier_method].leverage.as_ref().unwrap().iter().enumerate().filter(|(_, lev)| **lev < 1.0).map(|(i, &lev)| {
        (i, residuals[outlier_method][i] / (rse[outlier_method].unwrap() * (1.0 - lev).sqrt()))
    }).collect();
    ResultSet { fits, loo, kfold, gcv: selected_gcv, grid, estimates, residuals, rss, rse, ranking, outlier_method, standardized, isotonic_rss: (increasing_rss, decreasing_rss) }
}

fn diagnostics(series: &Series, result: &ResultSet, params: &BTreeMap<String, Vec<String>>) -> Vec<String> {
    let points = &series.points;
    let n = points.len();
    let ymin = points.iter().map(|p| p.y).min().unwrap();
    let ymax = points.iter().map(|p| p.y).max().unwrap();
    let ybar = sum(points.iter().map(|p| p.y as f64 / 100.0)) / n as f64;
    let tss = sum(points.iter().map(|p| { let d = p.y as f64 / 100.0 - ybar; d * d }));
    let mut lines = vec![format!("series {} n {} x {} {} y {} {}", series.name, n, position(points[0].x), position(points[n - 1].x), position(ymin), position(ymax))];
    for (m, fit) in result.fits.iter().enumerate() {
        let residuals = &result.residuals[m];
        let rss = result.rss[m];
        let mut line = format!("method {} parameter {} loo {}", fit.method, fit.parameter, number(result.loo[m]));
        if fit.method == "spline" { line.push_str(&format!(" gcv {}", number(result.gcv))); }
        lines.push(line);
        let df = fit.edf.map(|edf| n as f64 - edf);
        let f_nonlinear = fit.edf.filter(|&edf| m != 0 && edf > 2.0).map(|edf| ((result.rss[0] - rss) / (edf - 2.0)) / (rss / df.unwrap()));
        lines.push(format!("  rss {} edf {} df {} rse {} r2 {} f_nonlinear {}", number(rss), optional(fit.edf), optional(df), optional(result.rse[m]), number(1.0 - rss / tss), optional(f_nonlinear)));
        let ebar = sum(residuals.iter().copied()) / n as f64;
        let denominator = sum(residuals.iter().map(|&e| (e - ebar) * (e - ebar)));
        let acf: Vec<_> = (1..=5).map(|k| number(sum((0..n - k).map(|i| (residuals[i] - ebar) * (residuals[i + k] - ebar))) / denominator)).collect();
        let dw = sum(residuals.windows(2).map(|pair| { let d = pair[1] - pair[0]; d * d })) / rss;
        lines.push(format!("  acf {} dw {}", acf.join(" "), number(dw)));
        let signs: Vec<_> = residuals.iter().copied().filter(|&e| e != 0.0).map(|e| e > 0.0).collect();
        let positive = signs.iter().filter(|&&sign| sign).count() as i64;
        let negative = signs.len() as i64 - positive;
        let runs = 1 + signs.windows(2).filter(|pair| pair[0] != pair[1]).count();
        let total = positive + negative;
        let product = 2 * positive * negative;
        let mu = 1.0 + product as f64 / total as f64;
        let variance = (product * (product - total)) as f64 / (total * total * (total - 1)) as f64;
        lines.push(format!("  runs {} positive {} negative {} z {}", runs, positive, negative, number((runs as f64 - mu) / variance.sqrt())));
        let mut largest = 0;
        for i in 1..n { if residuals[i].abs() > residuals[largest].abs() { largest = i; } }
        let defined: Vec<_> = result.estimates[m].iter().filter_map(|&v| v).collect();
        let changes: Vec<_> = defined.windows(2).map(|pair| pair[1] - pair[0]).filter(|&d| d != 0.0).map(|d| d > 0.0).collect();
        let turning = changes.windows(2).filter(|pair| pair[0] != pair[1]).count();
        lines.push(format!("  max_residual {} at {} turning {}", number(residuals[largest]), position(points[largest].x), turning));
        let mut sorted = residuals.clone();
        sorted.sort_by(f64::total_cmp);
        let quantiles: Vec<_> = (0..=4).map(|k| {
            let j = (n - 1) * k / 4;
            let r = (n - 1) * k - 4 * j;
            number(if r == 0 { sorted[j] } else { sorted[j] + r as f64 / 4.0 * (sorted[j + 1] - sorted[j]) })
        }).collect();
        lines.push(format!("  quantiles {}", quantiles.join(" ")));
        if let Core::Loess(loess) = &fit.core {
            for (iteration, &(scale, zero, change)) in loess.records.iter().enumerate() {
                lines.push(format!("  robust {} scale {} zero_weight {} max_change {}", iteration + 1, number(scale), zero, number(change)));
            }
            let zero: Vec<_> = loess.rho.iter().enumerate().filter(|(_, rho)| **rho == 0.0).map(|(i, _)| position(points[i].x)).collect();
            lines.push(format!("  zero_weight_points {}", if zero.is_empty() { "none".into() } else { zero.join(" ") }));
        }
    }
    lines.push("ranking".into());
    for (rank, &m) in result.ranking.iter().enumerate() { lines.push(format!("  {} {} {} kfold {}", rank + 1, result.fits[m].method, number(result.loo[m]), optional(result.kfold[m]))); }
    let best = result.ranking[0];
    lines.push(format!("agreement with {}", result.fits[best].method));
    for m in 0..result.fits.len() {
        if m == best { continue; }
        let differences: Vec<_> = result.estimates[m].iter().zip(&result.estimates[best]).enumerate().filter_map(|(k, (&a, &b))| a.zip(b).map(|(a, b)| (k, (a - b).abs()))).collect();
        let mut largest = 0;
        for i in 1..differences.len() { if differences[i].1 > differences[largest].1 { largest = i; } }
        let rms = (sum(differences.iter().map(|&(_, delta)| delta * delta)) / differences.len() as f64).sqrt();
        lines.push(format!("  {} points {} rms {} max {} at {}", result.fits[m].method, differences.len(), number(rms), number(differences[largest].1), position(result.grid[differences[largest].0])));
    }
    let spline_index = result.fits.len() - 2;
    let slopes: Vec<_> = (1..result.grid.len() - 1).map(|k| {
        (result.estimates[spline_index][k + 1].unwrap() - result.estimates[spline_index][k - 1].unwrap()) / ((result.grid[k + 1] - result.grid[k - 1]) as f64 / 100.0)
    }).collect();
    let (mut maximum, mut minimum) = (0, 0);
    for k in 1..slopes.len() {
        if slopes[k] > slopes[maximum] { maximum = k; }
        if slopes[k] < slopes[minimum] { minimum = k; }
    }
    lines.push(format!("slope spline max {} at {} min {} at {}", number(slopes[maximum]), position(result.grid[maximum + 1]), number(slopes[minimum]), position(result.grid[minimum + 1])));
    let outlier = result.outlier_method;
    let threshold: f64 = params["OUTLIER_THRESHOLD"][0].parse().unwrap();
    lines.push(format!("outliers method {} threshold {}", result.fits[outlier].method, params["OUTLIER_THRESHOLD"][0]));
    let mut outliers: Vec<_> = result.standardized.iter().copied().filter(|&(_, t)| t.abs() > threshold).collect();
    outliers.sort_by(|a, b| b.1.abs().total_cmp(&a.1.abs()).then(a.0.cmp(&b.0)));
    if outliers.is_empty() { lines.push("  none".into()); }
    for (i, t) in outliers {
        lines.push(format!("  x {} y {} fit {} residual {} standardized {}", position(points[i].x), position(points[i].y), number(result.fits[outlier].fitted[i]), number(result.residuals[outlier][i]), number(t)));
    }
    let fit = &result.fits[outlier];
    let leverage = fit.leverage.as_ref().unwrap();
    let mut influential: Vec<_> = result.standardized.iter().map(|&(i, t)| (i, t * t * leverage[i] / ((1.0 - leverage[i]) * fit.edf.unwrap()))).collect();
    influential.sort_by(|a, b| b.1.total_cmp(&a.1).then(a.0.cmp(&b.0)));
    lines.push(format!("influence method {}", fit.method));
    for &(i, cook) in influential.iter().take(3) { lines.push(format!("  x {} lev {} cook {}", position(points[i].x), number(leverage[i]), number(cook))); }
    lines.push("bands".into());
    let z: f64 = params["BAND_Z"][0].parse().unwrap();
    for method in &params["BAND_METHODS"] {
        let m = result.fits.iter().position(|f| &f.method == method).unwrap();
        let fit = &result.fits[m];
        let rse = result.rse[m].unwrap();
        let standard_errors: Vec<_> = result.grid.iter().filter_map(|&x| fit.weights(x).map(|weights| rse * squares(&weights).sqrt())).collect();
        let coverage = points.iter().enumerate().filter(|&(i, point)| {
            let se = rse * squares(&fit.weights(point.x).unwrap()).sqrt();
            result.residuals[m][i].abs() <= z * (rse * rse + se * se).sqrt()
        }).count();
        lines.push(format!("  {} mean_se {} coverage {} of {}", method, number(sum(standard_errors.iter().copied()) / standard_errors.len() as f64), coverage, n));
    }
    lines
}

fn band_lines(series: &Series, result: &ResultSet, params: &BTreeMap<String, Vec<String>>, seed: &mut i64) -> Vec<String> {
    let mut lines = Vec::new();
    let z: f64 = params["BAND_Z"][0].parse().unwrap();
    for method in &params["BAND_METHODS"] {
        let m = result.fits.iter().position(|fit| &fit.method == method).unwrap();
        let fit = &result.fits[m];
        for &x in &result.grid {
            let values = fit.estimate(x).zip(fit.weights(x)).map(|(value, weights)| {
                let se = result.rse[m].unwrap() * squares(&weights).sqrt();
                [value, se, value - z * se, value + z * se]
            });
            let values = values.map_or_else(|| "NA,NA,NA,NA".into(), |values| values.iter().map(|&v| number(v)).collect::<Vec<_>>().join(","));
            lines.push(format!("{},{},{},{}", series.name, method, position(x), values));
        }
    }
    let m = result.fits.len() - 2;
    let Core::Spline(fit) = &result.fits[m].core else { unreachable!(); };
    let repetitions: usize = params["BOOTSTRAP"][0].parse().unwrap();
    let trim: usize = params["BOOTSTRAP"][1].parse().unwrap();
    let residuals = &result.residuals[m];
    let mean = sum(residuals.iter().copied()) / residuals.len() as f64;
    let centered: Vec<_> = residuals.iter().map(|&e| e - mean).collect();
    let mut boot = vec![Vec::new(); result.grid.len()];
    for _ in 0..repetitions {
        let mut values = Vec::new();
        for &value in &fit.curve.0 {
            *seed = *seed * 48271 % 2147483647;
            values.push(value + centered[*seed as usize % centered.len()]);
        }
        let curve = fit.fit(&values);
        for (samples, &x) in boot.iter_mut().zip(&result.grid) { samples.push(fit.evaluate(&curve, x)); }
    }
    for (k, mut samples) in boot.into_iter().enumerate() {
        let mean = sum(samples.iter().copied()) / repetitions as f64;
        let se = (sum(samples.iter().map(|&v| (v - mean) * (v - mean))) / (repetitions - 1) as f64).sqrt();
        samples.sort_by(f64::total_cmp);
        lines.push(format!("{},spline_bootstrap,{},{},{},{},{}", series.name, position(result.grid[k]), number(fit.estimate(result.grid[k])), number(se), number(samples[trim]), number(samples[repetitions - trim - 1])));
    }
    lines
}

fn isotonic_lines(series: &Series, index: usize, result: &ResultSet, params: &BTreeMap<String, Vec<String>>) -> Vec<String> {
    let m = result.fits.len() - 1;
    let fit = &result.fits[m];
    let Core::Isotonic(blocks) = &fit.core else { unreachable!(); };
    let mode = &params["ISOTONIC"][index];
    let mut first = format!("series {} direction {} mode {}", series.name, fit.parameter, mode);
    if mode == "auto" { first.push_str(&format!(" rss_increasing {} rss_decreasing {}", number(result.isotonic_rss.0), number(result.isotonic_rss.1))); }
    let mut lines = vec![first, format!("blocks {} rss {} loo {}", blocks.len(), number(result.rss[m]), number(result.loo[m]))];
    for (i, block) in blocks.iter().enumerate() {
        lines.push(format!("block {} x {} {} count {} value {}", i + 1, position(series.points[block.first].x), position(series.points[block.last].x), block.count, number(block.total as f64 / (100 * block.count) as f64)));
    }
    lines
}

fn frame(cells: &[Vec<u8>]) -> Vec<String> {
    let border = format!("+{}+", "-".repeat(cells[0].len()));
    let mut lines = vec![border.clone()];
    lines.extend(cells.iter().map(|row| format!("|{}|", String::from_utf8(row.clone()).unwrap())));
    lines.push(border);
    lines
}

fn plot_lines(series: &Series, result: &ResultSet, params: &BTreeMap<String, Vec<String>>) -> Vec<String> {
    let width: usize = params["PLOT_SIZE"][0].parse().unwrap();
    let height: usize = params["PLOT_SIZE"][1].parse().unwrap();
    let points = &series.points;
    let first = points[0].x;
    let last = points.last().unwrap().x;
    let ymin = points.iter().map(|p| p.y).min().unwrap();
    let ymax = points.iter().map(|p| p.y).max().unwrap();
    let column = |x| ((width as i64 * (x - first) / (last - first)) as usize).min(width - 1);
    let row = |real: f64| real.floor().max(0.0).min((height - 1) as f64) as usize;
    let mut canvas = vec![vec![b' '; width]; height];
    for point in points {
        let r = (height as i64 * (ymax - point.y) / (ymax - ymin)) as usize;
        canvas[r.min(height - 1)][column(point.x)] = b'.';
    }
    let mut legend = String::from("legend . data");
    for (index, method) in params["PLOT_METHODS"].iter().enumerate() {
        legend.push_str(&format!(" {} {}", index + 1, method));
        let fit = result.fits.iter().find(|fit| &fit.method == method).unwrap();
        let digit = b'1' + index as u8;
        for c in 0..width {
            let x = first + (2 * c + 1) as i64 * (last - first) / (2 * width) as i64;
            if let Some(value) = fit.estimate(x) {
                let r = row(height as f64 * (ymax as f64 / 100.0 - value) / (ymax as f64 / 100.0 - ymin as f64 / 100.0));
                let existing = canvas[r][c];
                canvas[r][c] = if existing == b' ' || existing == b'.' || existing == digit { digit } else { b'*' };
            }
        }
    }
    let mut lines = vec![format!("plot {} size {}x{} x {} {} y {} {}", series.name, width, height, position(first), position(last), position(ymin), position(ymax)), legend];
    lines.extend(frame(&canvas));
    let count = |symbol| canvas.iter().flatten().filter(|&&c| c == symbol).count();
    let curves = canvas.iter().flatten().filter(|c| c.is_ascii_digit()).count();
    lines.push(format!("cells data {} curve {} overlap {}", count(b'.'), curves, count(b'*')));
    lines.push(String::new());
    let best = result.ranking[0];
    let residuals = &result.residuals[best];
    let limit = residuals.iter().map(|v| v.abs()).fold(0.0, f64::max);
    lines.push(format!("residuals {} method {} limit {}", series.name, result.fits[best].method, number(limit)));
    let mut canvas = vec![vec![b' '; width]; height];
    canvas[height / 2].fill(b'-');
    for (point, &e) in points.iter().zip(residuals) {
        canvas[row(height as f64 * ((limit - e) / (2.0 * limit)))][column(point.x)] = b'o';
    }
    lines.extend(frame(&canvas));
    lines.push(String::new());
    lines.push(format!("histogram {} method {}", series.name, result.fits[result.outlier_method].method));
    let mut bins = [0; 14];
    for &(_, t) in &result.standardized {
        let bin = if t < -3.0 { 0 } else if t >= 3.0 { 13 } else { ((t + 3.0) / 0.5).floor() as usize + 1 };
        bins[bin] += 1;
    }
    for (bin, &count) in bins.iter().enumerate() {
        let lower = if bin == 0 { "-inf".into() } else { format!("{:.2}", -3.0 + 0.5 * (bin - 1) as f64) };
        let upper = if bin == 13 { "inf".into() } else { format!("{:.2}", -3.0 + 0.5 * bin as f64) };
        lines.push(format!("{lower} {upper} {count} |{}", "#".repeat(count)));
    }
    lines
}

fn add_block(lines: &mut Vec<String>, block: Vec<String>) {
    if !lines.is_empty() { lines.push(String::new()); }
    lines.extend(block);
}

fn write(name: &str, lines: &[String]) {
    fs::write(format!("output/{name}"), format!("{}\n", lines.join("\n"))).unwrap();
}

fn main() {
    let input = dataset::read();
    let methods = methods(&input.params);
    let header = format!("series,x,{}", methods.join(","));
    let mut selections = vec!["series,method,parameter,score,edf,selected".into()];
    let mut fits = vec![header.clone()];
    let mut predictions = vec![header];
    let mut bands = vec!["series,method,x,fit,se,lower,upper".into()];
    let mut diagnostic_lines = Vec::new();
    let mut isotonic_report = Vec::new();
    let mut results = Vec::new();
    let mut seed: i64 = input.params["BOOTSTRAP"][2].parse().unwrap();
    for (index, series) in input.series.iter().enumerate() {
        let result = fit_series(series, index, &input.params, &methods, &mut selections);
        for (k, &x) in result.grid.iter().enumerate() {
            fits.push(format!("{},{},{}", series.name, position(x), result.estimates.iter().map(|values| optional(values[k])).collect::<Vec<_>>().join(",")));
        }
        bands.extend(band_lines(series, &result, &input.params, &mut seed));
        add_block(&mut diagnostic_lines, diagnostics(series, &result, &input.params));
        add_block(&mut isotonic_report, isotonic_lines(series, index, &result, &input.params));
        results.push(result);
    }
    for (name, x) in &input.tests {
        let index = input.series.iter().position(|s| &s.name == name).unwrap();
        predictions.push(format!("{},{},{}", name, position(*x), results[index].fits.iter().map(|fit| optional(fit.estimate(*x))).collect::<Vec<_>>().join(",")));
    }
    let mut plots = Vec::new();
    for name in &input.params["PLOT_SERIES"] {
        let index = input.series.iter().position(|s| &s.name == name).unwrap();
        add_block(&mut plots, plot_lines(&input.series[index], &results[index], &input.params));
    }
    fs::create_dir_all("output").unwrap();
    for (name, lines) in [("selection.csv", selections), ("fits.csv", fits), ("predictions.csv", predictions), ("bands.csv", bands), ("diagnostics.txt", diagnostic_lines), ("isotonic.txt", isotonic_report), ("plots.txt", plots)] { write(name, &lines); }
}
