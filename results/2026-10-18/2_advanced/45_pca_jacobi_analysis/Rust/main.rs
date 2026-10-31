mod dataset;
mod eigen;
mod matrix;
mod pca;
mod plot;

use dataset::{Params, Row};
use matrix::Matrix;
use std::{fs, io};

fn fixed(x: f64, digits: usize) -> String {
    let result = format!("{:.*}", digits, x);
    if result.starts_with('-') && result[1..].chars().all(|c| c == '0' || c == '.') {
        result[1..].to_owned()
    } else {
        result
    }
}

fn real(x: f64) -> String {
    fixed(x, 4)
}

fn numbers(values: &[f64]) -> String {
    values.iter().map(|&x| real(x)).collect::<Vec<_>>().join(" ")
}

fn top(values: &[f64], count: usize) -> Vec<usize> {
    let mut order: Vec<usize> = (0..values.len()).collect();
    order.sort_by(|&a, &b| values[b].partial_cmp(&values[a]).unwrap().then(a.cmp(&b)));
    order.truncate(count);
    order
}

fn maximum(values: &[f64]) -> usize {
    let mut winner = 0;
    for j in 1..values.len() {
        if values[j] > values[winner] {
            winner = j;
        }
    }
    winner
}

struct Summary {
    count: usize,
    mean: f64,
    sd: f64,
    minimum: f64,
    maximum: f64,
}

fn summarize(rows: &[Row], p: usize) -> Vec<Summary> {
    (0..p).map(|j| {
        let values: Vec<f64> = rows.iter().filter_map(|r| r.values[j]).collect();
        let count = values.len();
        let mean = values.iter().sum::<f64>() / count as f64;
        let sd = (values.iter().map(|x| (x - mean) * (x - mean)).sum::<f64>() / (count - 1) as f64).sqrt();
        Summary {
            count,
            mean,
            sd,
            minimum: values.iter().copied().fold(f64::INFINITY, f64::min),
            maximum: values.iter().copied().fold(f64::NEG_INFINITY, f64::max),
        }
    }).collect()
}

fn analysis(rows: &[Row], summary: &[Summary], missing: &str) -> (Vec<String>, Matrix) {
    let mut ids = Vec::new();
    let mut values = Vec::new();
    for row in rows {
        if missing == "listwise" && row.values.iter().any(Option::is_none) {
            continue;
        }
        ids.push(row.id.clone());
        values.push(row.values.iter().enumerate().map(|(j, x)| x.unwrap_or(summary[j].mean)).collect());
    }
    (ids, values)
}

fn criterion(g: &Matrix) -> f64 {
    let p = g.len();
    let mut result = 0.0;
    for k in 0..g[0].len() {
        let mut q2 = 0.0;
        let mut q4 = 0.0;
        for row in g {
            let square = row[k] * row[k];
            q4 += square * square;
            q2 += square;
        }
        result += q4 / p as f64 - (q2 / p as f64) * (q2 / p as f64);
    }
    result
}

struct Rotation {
    columns: Matrix,
    sums: Vec<f64>,
    history: Vec<f64>,
    closest: Vec<(usize, f64)>,
}

fn rotate(loadings: &Matrix, k: usize, cycles: usize) -> Rotation {
    let p = loadings.len();
    let eta: Vec<f64> = loadings.iter().map(|r| matrix::length(&r[..k])).collect();
    let mut g: Matrix = (0..p).map(|j| (0..k).map(|h| loadings[j][h] / eta[j]).collect()).collect();
    let mut history = vec![criterion(&g)];
    for _ in 0..cycles {
        for a in 0..k - 1 {
            for b in a + 1..k {
                let mut sa = 0.0;
                let mut sb = 0.0;
                let mut sc = 0.0;
                let mut sd = 0.0;
                for row in &g {
                    let phi = row[a] * row[a] - row[b] * row[b];
                    let psi = 2.0 * row[a] * row[b];
                    sa += phi;
                    sb += psi;
                    sc += phi * phi - psi * psi;
                    sd += 2.0 * phi * psi;
                }
                let num = sd - 2.0 * sa * sb / p as f64;
                let den = sc - (sa * sa - sb * sb) / p as f64;
                let omega = (num * num + den * den).sqrt();
                if omega == 0.0 {
                    continue;
                }
                let cos4 = den / omega;
                let sin4 = num / omega;
                let cos2 = ((1.0 + cos4) / 2.0).sqrt();
                let sin2 = if cos2 == 0.0 { 1.0 } else { sin4 / (2.0 * cos2) };
                let cos1 = ((1.0 + cos2) / 2.0).sqrt();
                let sin1 = sin2 / (2.0 * cos1);
                for row in &mut g {
                    let x = row[a];
                    let y = row[b];
                    row[a] = cos1 * x + sin1 * y;
                    row[b] = -sin1 * x + cos1 * y;
                }
            }
        }
        history.push(criterion(&g));
    }
    let mut columns: Matrix = (0..k).map(|h| (0..p).map(|j| g[j][h] * eta[j]).collect()).collect();
    for column in &mut columns {
        matrix::orient(column);
    }
    let sums: Vec<f64> = columns.iter().map(|v| matrix::dot(v, v)).collect();
    let order = top(&sums, k);
    let columns: Matrix = order.iter().map(|&h| columns[h].clone()).collect();
    let sums = order.iter().map(|&h| sums[h]).collect();
    let closest = columns.iter().map(|v| {
        let values: Vec<f64> = (0..k).map(|h| {
            let original = matrix::column(loadings, h);
            (matrix::dot(v, &original) / (matrix::dot(v, v) * matrix::dot(&original, &original)).sqrt()).abs()
        }).collect();
        let h = maximum(&values);
        (h, values[h])
    }).collect();
    Rotation { columns, sums, history, closest }
}

struct Diagnostic {
    scores: Vec<f64>,
    t2: f64,
    spe: f64,
    quality: f64,
    flag: String,
    t_contributions: Vec<f64>,
    q_contributions: Vec<f64>,
}

fn diagnose(z: &[f64], eig: &eigen::Decomposition, k: usize, params: &Params) -> Diagnostic {
    let scores = pca::scores(z, &eig.vectors);
    let t2 = pca::t2(&scores, &eig.values, k);
    let residuals = pca::residuals(z, &scores, &eig.vectors, k);
    let spe = matrix::dot(&residuals, &residuals);
    let quality = matrix::dot(&scores[..k], &scores[..k]) / matrix::dot(z, z);
    let mut flag = String::new();
    if t2 > params.t2_limit {
        flag.push('T');
    }
    if spe > params.spe_limit {
        flag.push('Q');
    }
    if flag.is_empty() {
        flag.push('-');
    }
    let t_contributions = (0..z.len()).map(|j| {
        let mut w = 0.0;
        for h in 0..k {
            w += (scores[h] / eig.values[h]) * eig.vectors[h][j];
        }
        z[j] * w
    }).collect();
    let q_contributions = residuals.iter().map(|x| x * x).collect();
    Diagnostic { scores, t2, spe, quality, flag, t_contributions, q_contributions }
}

fn plots(params: &Params, names: &[String], eig: &eigen::Decomposition, broken: &[f64],
    loadings: &Matrix, s: &Matrix, data: &[Diagnostic], supplementary: &[Diagnostic]) -> Vec<String> {
    let p = names.len();
    let total: f64 = eig.values.iter().sum();
    let width = params.scree_width;
    let kaiser = ((total / p as f64) / eig.values[0] * width as f64 + 0.5).floor() as usize;
    let mut lines = vec![format!("scree width {} kaiser_column {}", width, kaiser)];
    for h in 0..p {
        let length = (eig.values[h] / eig.values[0] * width as f64 + 0.5).floor() as usize;
        let beta = (broken[h] * total / eig.values[0] * width as f64 + 0.5).floor() as usize;
        lines.push(format!("|{}| pc{} {}", plot::scree(width, length, beta, kaiser), h + 1, real(eig.values[h])));
    }
    let m1 = data.iter().chain(supplementary).map(|d| d.scores[0].abs()).fold(0.0, f64::max);
    let m2 = data.iter().chain(supplementary).map(|d| d.scores[1].abs()).fold(0.0, f64::max);
    let l1 = loadings.iter().map(|r| r[0].abs()).fold(0.0, f64::max);
    let l2 = loadings.iter().map(|r| r[1].abs()).fold(0.0, f64::max);
    let scale = 0.9 * (m1 / l1).min(m2 / l2);
    let (w, h) = params.biplot;
    let origin = plot::cell(0.0, 0.0, m1, m2, w, h);
    let tips: Vec<_> = loadings.iter().map(|r| plot::cell(scale * r[0], scale * r[1], m1, m2, w, h)).collect();
    let mut grid = plot::grid(w, h);
    plot::axes(&mut grid, origin);
    for &tip in &tips {
        for (r, c, mark) in plot::shaft(origin, tip) {
            grid[r][c] = mark;
        }
    }
    let positions: Vec<_> = data.iter().map(|d| plot::cell(d.scores[0], d.scores[1], m1, m2, w, h)).collect();
    plot::density(&mut grid, &positions);
    for (i, &(r, c)) in positions.iter().enumerate() {
        if data[i].flag != "-" {
            grid[r][c] = 'X';
        }
    }
    for d in supplementary {
        let (r, c) = plot::cell(d.scores[0], d.scores[1], m1, m2, w, h);
        grid[r][c] = '*';
    }
    for (j, &(r, c)) in tips.iter().enumerate() {
        grid[r][c] = (b'A' + j as u8) as char;
    }
    lines.extend([String::new(), format!("biplot pc1 pc2 width {} height {}", w, h),
        format!("x {} {} y {} {} arrow_scale {}", real(-m1), real(m1), real(-m2), real(m2), real(scale))]);
    lines.extend(plot::frame(&grid));
    for j in 0..p {
        lines.push(format!("{} {} {} {}", (b'A' + j as u8) as char, names[j], real(loadings[j][0]), real(loadings[j][1])));
    }
    let radius = params.radius as i64;
    let rc = radius / 2 + 1;
    let cc = radius + 1;
    let inside = |r: i64, c: i64| {
        (c - cc) * (c - cc) + (2 * (r - rc)) * (2 * (r - rc)) <= radius * radius
    };
    let mut grid = plot::grid((2 * radius + 3) as usize, (radius + 3) as usize);
    plot::axes(&mut grid, (rc as usize, cc as usize));
    for r in 0..grid.len() {
        for c in 0..grid[r].len() {
            let (r0, c0) = (r as i64, c as i64);
            if inside(r0, c0) && [(r0 - 1, c0), (r0 + 1, c0), (r0, c0 - 1), (r0, c0 + 1)]
                .iter().any(|&(a, b)| !inside(a, b)) {
                grid[r][c] = '.';
            }
        }
    }
    let correlations: Vec<(f64, f64)> = (0..p).map(|j| {
        (loadings[j][0] / s[j][j].sqrt(), loadings[j][1] / s[j][j].sqrt())
    }).collect();
    for (j, &(q1, q2)) in correlations.iter().enumerate() {
        let row = rc - (q2 * (radius / 2) as f64 + 0.5).floor() as i64;
        let column = cc + (q1 * radius as f64 + 0.5).floor() as i64;
        grid[row as usize][column as usize] = (b'A' + j as u8) as char;
    }
    lines.extend([String::new(), format!("circle radius {}", radius)]);
    lines.extend(plot::frame(&grid));
    for j in 0..p {
        let (q1, q2) = correlations[j];
        lines.push(format!("{} {} {} {} {}", (b'A' + j as u8) as char, names[j], real(q1), real(q2), real(q1 * q1 + q2 * q2)));
    }
    let (w, h) = params.diagnostic;
    let x = 2.0 * params.t2_limit;
    let y = 2.0 * params.spe_limit;
    let mut grid = plot::grid(w, h);
    plot::axes(&mut grid, plot::diagnostic(params.t2_limit, params.spe_limit, x, y, w, h));
    let positions: Vec<_> = data.iter().map(|d| plot::diagnostic(d.t2, d.spe, x, y, w, h)).collect();
    plot::density(&mut grid, &positions);
    for d in supplementary {
        let (r, c) = plot::diagnostic(d.t2, d.spe, x, y, w, h);
        grid[r][c] = '*';
    }
    lines.extend([String::new(), format!("diagnostic width {} height {} t2_max {} spe_max {}", w, h, real(x), real(y))]);
    lines.extend(plot::frame(&grid));
    lines
}

fn main() -> io::Result<()> {
    let input = dataset::read()?;
    let params = &input.params;
    let names = &input.names;
    let p = names.len();
    let summary = summarize(&input.data, p);
    let (ids, values) = analysis(&input.data, &summary, &params.missing);
    let n = values.len();
    let stats = pca::statistics(&values);
    let (s, scales) = if params.scaling == "covariance" {
        (stats.covariance.clone(), vec![1.0; p])
    } else {
        (stats.correlation.clone(), stats.deviations.clone())
    };
    let z: Matrix = values.iter().map(|r| pca::standardize(r, &stats.means, &scales)).collect();
    let eig = eigen::jacobi(&s);
    let power = eigen::power(&s, &eig);
    let total: f64 = eig.values.iter().sum();
    let average = total / p as f64;
    let ratios: Vec<f64> = eig.values.iter().map(|v| v / total).collect();
    let mut cumulative = Vec::new();
    let mut running = 0.0;
    for ratio in &ratios {
        running += ratio;
        cumulative.push(running);
    }
    let broken: Vec<f64> = (0..p).map(|k| ((k + 1..=p).map(|i| 1.0 / i as f64).sum::<f64>()) / p as f64).collect();
    let mut parallel = vec![0.0; p];
    let mut state = params.seed;
    for _ in 0..params.repetitions {
        let random: Matrix = (0..n).map(|_| (0..p).map(|_| {
            state = 48271 * state % 2147483647;
            state as f64 / 2147483647.0
        }).collect()).collect();
        let random_stats = pca::statistics(&random);
        let random_eigen = eigen::jacobi(&random_stats.correlation);
        let random_total: f64 = random_eigen.values.iter().sum();
        for h in 0..p {
            parallel[h] += random_eigen.values[h] / random_total;
        }
    }
    for g in &mut parallel {
        *g /= params.repetitions as f64;
    }
    let counts = [eig.values.iter().filter(|&&v| v > average).count(),
        (0..p).find(|&h| ratios[h] <= broken[h]).unwrap_or(p),
        (0..p).find(|&h| ratios[h] <= parallel[h]).unwrap_or(p),
        cumulative.iter().position(|&v| v >= params.target).unwrap() + 1];
    let k = match params.components.as_str() {
        "kaiser" => counts[0],
        "broken_stick" => counts[1],
        "parallel" => counts[2],
        "cumulative" => counts[3],
        value => value.parse().unwrap(),
    }.max(1);
    let (inverse, determinant) = matrix::inverse_determinant(&stats.correlation);
    let mut rr = vec![0.0; p];
    let mut pp = vec![0.0; p];
    for j in 0..p {
        for h in 0..p {
            if j != h {
                rr[j] += stats.correlation[j][h] * stats.correlation[j][h];
                let partial = -inverse[j][h] / (inverse[j][j] * inverse[h][h]).sqrt();
                pp[j] += partial * partial;
            }
        }
    }
    let msa: Vec<f64> = (0..p).map(|j| rr[j] / (rr[j] + pp[j])).collect();
    let rr_total: f64 = rr.iter().sum();
    let kmo = rr_total / (rr_total + pp.iter().sum::<f64>());
    let bartlett = -(n as f64 - 1.0 - (2 * p + 5) as f64 / 6.0) * determinant.ln();
    let loadings: Matrix = (0..p).map(|j| (0..p).map(|h| eig.vectors[h][j] * eig.values[h].sqrt()).collect()).collect();
    let communalities: Vec<f64> = (0..p).map(|j| matrix::dot(&loadings[j][..k], &loadings[j][..k]) / s[j][j]).collect();
    let rotation = rotate(&loadings, k, params.cycles);
    let data: Vec<Diagnostic> = z.iter().map(|r| diagnose(r, &eig, k, params)).collect();
    let supplementary: Vec<Diagnostic> = input.supplementary.iter().map(|r| {
        let z = pca::supplementary(&r.values, &stats.means, &scales);
        diagnose(&z, &eig, k, params)
    }).collect();
    let incomplete: Vec<&str> = input.data.iter().filter(|r| r.values.iter().any(Option::is_none)).map(|r| r.id.as_str()).collect();
    let mut report = vec![format!("pca rows {} used {} variables {} missing {} scaling {}", input.data.len(), n, p, params.missing, params.scaling),
        format!("incomplete {} {}", incomplete.len(), if incomplete.is_empty() { "-".into() } else { incomplete.join(" ") }),
        String::new(), "variable observed missing mean sd min max msa".into()];
    for j in 0..p {
        let v = &summary[j];
        report.push(format!("{} {} {} {} {} {} {} {}", names[j], v.count, input.data.len() - v.count,
            real(v.mean), real(v.sd), real(v.minimum), real(v.maximum), real(msa[j])));
    }
    report.extend([format!("adequacy kmo {} determinant {} bartlett {} df {}", real(kmo), fixed(determinant, 6), real(bartlett), p * (p - 1) / 2),
        String::new(), format!("matrix {}", params.scaling)]);
    for j in 0..p {
        report.push(format!("{} {}", names[j], numbers(&s[j])));
    }
    let mut pairs = Vec::new();
    for j in 0..p - 1 {
        for h in j + 1..p {
            pairs.push((j, h));
        }
    }
    let pair_values: Vec<f64> = pairs.iter().map(|&(j, h)| stats.correlation[j][h].abs()).collect();
    let strongest: Vec<String> = top(&pair_values, params.top).iter().map(|&i| {
        let (j, h) = pairs[i];
        format!("{}:{}:{}", names[j], names[h], real(stats.correlation[j][h]))
    }).collect();
    report.extend([format!("strongest {}", strongest.join(" ")), String::new(),
        format!("jacobi sweeps {}", eig.sweeps), format!("eigenvalues total {} average {}", real(total), real(average)),
        "k eigenvalue ratio cumulative broken_stick parallel se separated".into()]);
    for h in 0..p {
        let se = eig.values[h] * (2.0 / n as f64).sqrt();
        let separated = (h == 0 || (eig.values[h] - eig.values[h - 1]).abs() > se)
            && (h + 1 == p || (eig.values[h] - eig.values[h + 1]).abs() > se);
        report.push(format!("{} {} {} {} {} {} {} {}", h + 1, real(eig.values[h]), real(ratios[h]), real(cumulative[h]),
            real(broken[h]), real(parallel[h]), real(se), if separated { "yes" } else { "no" }));
    }
    report.extend([format!("retention kaiser {} broken_stick {} parallel {} cumulative {} target {}", counts[0], counts[1], counts[2], counts[3], real(params.target)),
        format!("components {} rule {}", k, params.components), String::new(), "eigenvectors".into(),
        format!("variable {}", (1..=p).map(|h| format!("pc{}", h)).collect::<Vec<_>>().join(" "))]);
    for j in 0..p {
        let row: Vec<f64> = eig.vectors.iter().map(|v| v[j]).collect();
        report.push(format!("{} {}", names[j], numbers(&row)));
    }
    report.extend([String::new(), "power_iteration iterations 1000".into(), "k jacobi power agree_at match".into()]);
    for h in 0..p {
        report.push(format!("{} {} {} {} {}", h + 1, real(eig.values[h]), real(power[h].value),
            power[h].agreement.map_or("-".into(), |t| t.to_string()), if power[h].matches { "yes" } else { "no" }));
    }
    report.extend([format!("cross_check {}/{}", power.iter().filter(|r| r.matches).count(), p), String::new(),
        "scores".into(), "component sd min min_id max max_id contributors".into()]);
    for h in 0..k {
        let scores: Vec<f64> = data.iter().map(|d| d.scores[h]).collect();
        let maximum = maximum(&scores);
        let negatives: Vec<f64> = scores.iter().map(|x| -x).collect();
        let minimum = crate::maximum(&negatives);
        let contributions: Vec<f64> = scores.iter().map(|x| x * x / ((n - 1) as f64 * eig.values[h])).collect();
        let contributors: Vec<String> = top(&contributions, params.top).iter().map(|&i| format!("{}:{}", ids[i], real(contributions[i]))).collect();
        report.push(format!("pc{} {} {} {} {} {} {}", h + 1, real((matrix::dot(&scores, &scores) / (n - 1) as f64).sqrt()),
            real(scores[minimum]), ids[minimum], real(scores[maximum]), ids[maximum], contributors.join(" ")));
    }
    report.extend([String::new(), format!("varimax components {} cycles {}", k, params.cycles)]);
    for (cycle, &value) in rotation.history.iter().enumerate() {
        report.push(format!("cycle {} criterion {}", cycle, fixed(value, 6)));
    }
    for h in 0..k {
        report.push(format!("rc{} ss {} ratio {} closest pc{} congruence {}", h + 1, real(rotation.sums[h]),
            real(rotation.sums[h] / total), rotation.closest[h].0 + 1, real(rotation.closest[h].1)));
    }
    report.extend([String::new(), "sensitivity".into(), "missing scaling rows sweeps eigenvalues cumulative congruence".into()]);
    for missing in ["listwise", "mean"] {
        let (_, values) = analysis(&input.data, &summary, missing);
        let stats = pca::statistics(&values);
        for scaling in ["covariance", "correlation"] {
            let matrix = if scaling == "covariance" { &stats.covariance } else { &stats.correlation };
            let alt = eigen::jacobi(matrix);
            let total: f64 = alt.values.iter().sum();
            let cumulative = alt.values[..k].iter().map(|v| v / total).sum::<f64>();
            let congruences: Vec<f64> = (0..k).map(|h| matrix::dot(&alt.vectors[h], &eig.vectors[h]).abs()).collect();
            report.push(format!("{} {} {} {} {} {} {}", missing, scaling, values.len(), alt.sweeps,
                numbers(&alt.values[..k]), real(cumulative), numbers(&congruences)));
        }
    }
    let mut loadings_report = vec![format!("variable,{},communality,{}",
        (1..=k).map(|h| format!("pc{}", h)).collect::<Vec<_>>().join(","),
        (1..=k).map(|h| format!("rc{}", h)).collect::<Vec<_>>().join(","))];
    for j in 0..p {
        let mut fields = vec![names[j].clone()];
        fields.extend(loadings[j][..k].iter().map(|&v| real(v)));
        fields.push(real(communalities[j]));
        fields.extend(rotation.columns.iter().map(|v| real(v[j])));
        loadings_report.push(fields.join(","));
    }
    let mut scores_report = vec![format!("id,set,{}", (1..=k).map(|h| format!("pc{}", h)).collect::<Vec<_>>().join(","))];
    for (i, d) in data.iter().enumerate() {
        scores_report.push(format!("{},data,{}", ids[i], d.scores[..k].iter().map(|&v| real(v)).collect::<Vec<_>>().join(",")));
    }
    for (i, d) in supplementary.iter().enumerate() {
        scores_report.push(format!("{},supplementary,{}", input.supplementary[i].id,
            d.scores[..k].iter().map(|&v| real(v)).collect::<Vec<_>>().join(",")));
    }
    let mut outliers = vec![format!("diagnostics components {} t2_limit {} spe_limit {}", k, real(params.t2_limit), real(params.spe_limit)),
        "id t2 spe quality flag".into()];
    for (i, d) in data.iter().enumerate() {
        outliers.push(format!("{} {} {} {} {}", ids[i], real(d.t2), real(d.spe), real(d.quality), d.flag));
    }
    outliers.push(format!("flagged t2 {} spe {} both {} any {}", data.iter().filter(|d| d.flag.contains('T')).count(),
        data.iter().filter(|d| d.flag.contains('Q')).count(), data.iter().filter(|d| d.flag == "TQ").count(),
        data.iter().filter(|d| d.flag != "-").count()));
    for kind in ["t2", "spe"] {
        outliers.extend([String::new(), format!("top {}", kind), format!("rank id {} variable contribution", kind)]);
        let values: Vec<f64> = data.iter().map(|d| if kind == "t2" { d.t2 } else { d.spe }).collect();
        for (rank, &i) in top(&values, params.top).iter().enumerate() {
            let contributions = if kind == "t2" { &data[i].t_contributions } else { &data[i].q_contributions };
            let j = maximum(contributions);
            outliers.push(format!("{} {} {} {} {}", rank + 1, ids[i], real(values[i]), names[j], real(contributions[j])));
        }
    }
    outliers.extend([String::new(), "reconstruction".into(), "k mean_spe max_spe max_id".into()]);
    for h in 1..p {
        let errors: Vec<f64> = z.iter().zip(&data).map(|(row, d)| {
            let residuals = pca::residuals(row, &d.scores, &eig.vectors, h);
            matrix::dot(&residuals, &residuals)
        }).collect();
        let i = maximum(&errors);
        outliers.push(format!("{} {} {} {}", h, real(errors.iter().sum::<f64>() / n as f64), real(errors[i]), ids[i]));
    }
    outliers.extend([String::new(), "supplementary".into(), format!("id {} t2 spe flag nearest distance",
        (1..=k).map(|h| format!("pc{}", h)).collect::<Vec<_>>().join(" "))]);
    for (i, d) in supplementary.iter().enumerate() {
        let distances: Vec<f64> = data.iter().map(|other| {
            let mut distance = 0.0;
            for h in 0..k {
                let difference = d.scores[h] - other.scores[h];
                distance += difference * difference;
            }
            distance
        }).collect();
        let negatives: Vec<f64> = distances.iter().map(|v| -v).collect();
        let nearest = maximum(&negatives);
        outliers.push(format!("{} {} {} {} {} {} {}", input.supplementary[i].id, numbers(&d.scores[..k]),
            real(d.t2), real(d.spe), d.flag, ids[nearest], real(distances[nearest].sqrt())));
    }
    let plots_report = plots(params, names, &eig, &broken, &loadings, &s, &data, &supplementary);
    fs::create_dir_all("output")?;
    for (name, lines) in [("eigen.txt", report), ("loadings.csv", loadings_report),
        ("scores.csv", scores_report), ("outliers.txt", outliers), ("plots.txt", plots_report)] {
        fs::write(format!("output/{}", name), lines.join("\n") + "\n")?;
    }
    Ok(())
}
