mod dataframe;
mod diagnostics;
mod formula;
mod inference;
mod qr_solver;

use dataframe::Input;
use diagnostics::Diagnostics;
use formula::{Design, Model};
use inference::{f_probability, probability, real, significance, t_probability, t_quantile};
use qr_solver::{fit, sum, Fit, Matrix};
use std::collections::BTreeMap;
use std::fs;

struct Statistics {
    degrees: usize,
    sigma: f64,
    r_squared: f64,
    adjusted: f64,
    f: Option<f64>,
    f_probability: Option<f64>,
    likelihood: f64,
    aic: f64,
    bic: f64,
    press: f64,
    predicted_r_squared: f64,
    quantiles: [f64; 5],
    critical: f64,
}

fn statistics(input: &Input, model: &Fit, y: &[f64], weights: &[f64]) -> Statistics {
    let n = y.len();
    let rank = model.accepted.len();
    let degrees = n - rank;
    let sigma = (model.rss / degrees as f64).sqrt();
    let total_weight = sum(weights.iter().copied());
    let mean = sum(weights.iter().zip(y).map(|(&w, &y)| w * y)) / total_weight;
    let tss = sum(weights.iter().zip(y).map(|(&w, &y)| w * (y - mean) * (y - mean)));
    let r_squared = 1.0 - model.rss / tss;
    let adjusted = 1.0 - (1.0 - r_squared) * (n - 1) as f64 / degrees as f64;
    let f = (rank > 1).then(|| ((tss - model.rss) / (rank - 1) as f64) / (model.rss / degrees as f64));
    let likelihood = 0.5 * (sum(weights.iter().map(|w| w.ln())) - n as f64 * ((2.0 * std::f64::consts::PI).ln() + 1.0 - (n as f64).ln() + model.rss.ln()));
    let aic = -2.0 * likelihood + 2.0 * (rank + 1) as f64;
    let bic = -2.0 * likelihood + (n as f64).ln() * (rank + 1) as f64;
    let press = sum((0..n).map(|i| { let value = model.weighted_residuals[i] / (1.0 - model.leverage[i]); value * value }));
    let mut sorted = model.weighted_residuals.clone();
    sorted.sort_by(f64::total_cmp);
    let quantiles = std::array::from_fn(|i| {
        let g = (n - 1) as f64 * (i as f64 / 4.0);
        let k = g.floor() as usize;
        if k + 1 < n { sorted[k] + (g - k as f64) * (sorted[k + 1] - sorted[k]) } else { sorted[k] }
    });
    Statistics { degrees, sigma, r_squared, adjusted, f, f_probability: f.map(|value| f_probability(value, rank - 1, degrees)), likelihood, aic, bic, press, predicted_r_squared: 1.0 - press / tss, quantiles, critical: t_quantile(input.number("CONFIDENCE"), degrees) }
}

struct Context {
    model: Model,
    design: Design,
    x: Matrix,
    y: Vec<f64>,
    weights: Vec<f64>,
    fit: Fit,
    statistics: Statistics,
    diagnostics: Diagnostics,
}

fn context(input: &Input, text: &str) -> Context {
    let model = formula::parse(text, input);
    let design = Design::build(input, &model);
    let x = design.used.iter().map(|&i| design.values(&input.rows[i])).collect();
    let y: Vec<_> = design.used.iter().map(|&i| input.rows[i][model.response].number().unwrap()).collect();
    let weights: Vec<_> = design.used.iter().map(|&i| model.weight.map_or(1.0, |column| input.rows[i][column].number().unwrap())).collect();
    let fit = fit(&x, &y, &weights, input.number("RANK_TOL"));
    let statistics = statistics(input, &fit, &y, &weights);
    let diagnostics = diagnostics::calculate(input, &fit, &x, statistics.sigma, statistics.degrees);
    Context { model, design, x, y, weights, fit, statistics, diagnostics }
}

fn table_dynamic(header: Vec<String>, rows: Vec<(Vec<String>, String)>) -> Vec<String> {
    let mut all = vec![(header, String::new())];
    all.extend(rows);
    let mut widths = vec![0; all[0].0.len()];
    for (fields, _) in &all { for (i, field) in fields.iter().enumerate() { widths[i] = widths[i].max(field.len()); } }
    all.into_iter().map(|(fields, mark)| {
        let mut line = format!("{:<width$}", fields[0], width = widths[0]);
        for (i, field) in fields.iter().enumerate().skip(1) { line.push_str(&format!("  {:>width$}", field, width = widths[i])); }
        if !mark.is_empty() { line.push(' '); line.push_str(&mark); }
        line.trim_end().into()
    }).collect()
}

fn table(header: &[&str], rows: Vec<(Vec<String>, String)>) -> Vec<String> { table_dynamic(header.iter().map(|s| s.to_string()).collect(), rows) }
fn plain(fields: Vec<String>) -> (Vec<String>, String) { (fields, String::new()) }
fn optional(value: Option<f64>) -> String { value.map_or_else(|| "NA".into(), real) }
fn optional_probability(value: Option<f64>) -> String { value.map_or_else(|| "NA".into(), probability) }

fn data_summary(input: &Input) -> Vec<String> {
    let mut lines = vec![format!("Data: {} rows, {} columns", input.rows.len(), input.names.len()), String::new(), "Numeric columns:".into()];
    let numeric: Vec<_> = (0..input.names.len()).filter(|&i| !input.categorical[i]).collect();
    let numeric_rows = numeric.iter().map(|&column| {
        let values: Vec<_> = input.rows.iter().filter_map(|row| row[column].number()).collect();
        let mean = sum(values.iter().copied()) / values.len() as f64;
        let deviation = (sum(values.iter().map(|&v| (v - mean) * (v - mean))) / (values.len() - 1) as f64).sqrt();
        plain(vec![input.names[column].clone(), values.len().to_string(), (input.rows.len() - values.len()).to_string(), real(mean), real(deviation), real(values.iter().copied().fold(f64::INFINITY, f64::min)), real(values.iter().copied().fold(f64::NEG_INFINITY, f64::max))])
    }).collect();
    lines.extend(table(&["column", "n", "missing", "Mean", "SD", "Min", "Max"], numeric_rows));
    lines.extend([String::new(), "Categorical columns:".into()]);
    for column in (0..input.names.len()).filter(|&i| input.categorical[i]) {
        let mut counts = BTreeMap::new();
        for label in input.rows.iter().filter_map(|row| row[column].label()) { *counts.entry(label).or_insert(0) += 1; }
        let count = counts.values().sum::<usize>();
        lines.push(format!("{}: {} values, {} missing, {} levels: {}", input.names[column], count, input.rows.len() - count, counts.len(), counts.iter().map(|(label, count)| format!("{label} {count}")).collect::<Vec<_>>().join(", ")));
    }
    lines.extend([String::new(), "Correlations (pairwise complete observations):".into()]);
    let mut header = vec!["column".into()];
    header.extend(numeric.iter().map(|&i| input.names[i].clone()));
    let rows = numeric.iter().map(|&a| {
        let mut fields = vec![input.names[a].clone()];
        for &b in &numeric {
            let pairs: Vec<_> = input.rows.iter().filter_map(|row| row[a].number().zip(row[b].number())).collect();
            let xbar = sum(pairs.iter().map(|p| p.0)) / pairs.len() as f64;
            let ybar = sum(pairs.iter().map(|p| p.1)) / pairs.len() as f64;
            let xy = sum(pairs.iter().map(|&(x, y)| (x - xbar) * (y - ybar)));
            let xx = sum(pairs.iter().map(|&(x, _)| (x - xbar) * (x - xbar)));
            let yy = sum(pairs.iter().map(|&(_, y)| (y - ybar) * (y - ybar)));
            fields.push(real(xy / (xx * yy).sqrt()));
        }
        plain(fields)
    }).collect();
    lines.extend(table_dynamic(header, rows));
    lines.push(String::new());
    lines
}

fn subset_fit(input: &Input, context: &Context, selected: &[usize]) -> (Fit, Statistics) {
    let columns = context.design.indices(selected);
    let x = context.x.iter().map(|row| columns.iter().map(|&j| row[j]).collect()).collect();
    let fit = fit(&x, &context.y, &context.weights, input.number("RANK_TOL"));
    let statistics = statistics(input, &fit, &context.y, &context.weights);
    (fit, statistics)
}

struct DropTest {
    term: usize,
    degrees: usize,
    squares: f64,
    rss: f64,
    f: Option<f64>,
    probability: Option<f64>,
}

fn marginal(input: &Input, context: &Context, selected: &[usize], current: &Fit, statistics: &Statistics) -> Vec<DropTest> {
    let mut tests = Vec::new();
    for &term in selected {
        if selected.iter().any(|&other| context.model.terms[term].contained(&context.model.terms[other])) { continue; }
        let remaining: Vec<_> = selected.iter().copied().filter(|&i| i != term).collect();
        let (reduced, _) = subset_fit(input, context, &remaining);
        let degrees = current.accepted.len() - reduced.accepted.len();
        let squares = reduced.rss - current.rss;
        let f = (degrees > 0).then(|| (squares / degrees as f64) / (current.rss / statistics.degrees as f64));
        tests.push(DropTest { term, degrees, squares, rss: reduced.rss, f, probability: f.map(|f| f_probability(f, degrees, statistics.degrees)) });
    }
    tests
}

fn largest_absolute(values: &[f64]) -> usize {
    let mut best = 0;
    for i in 1..values.len() { if values[i].abs() > values[best].abs() { best = i; } }
    best
}

fn model_summary(input: &Input, context: &Context, number: usize) -> Vec<String> {
    let model = &context.model;
    let design = &context.design;
    let fit = &context.fit;
    let statistics = &context.statistics;
    let diagnostics = &context.diagnostics;
    let n = context.y.len();
    let rank = fit.accepted.len();
    let alias: Vec<_> = design.columns.iter().enumerate().filter(|(j, _)| fit.coefficients[*j].is_none()).map(|(_, column)| column.name.clone()).collect();
    let mut lines = vec![format!("Model {number}: {}", model.formula), format!("Terms: {}", model.terms.iter().map(|term| term.name()).collect::<Vec<_>>().join(", ")), format!("Weights: {}", model.weight.map_or("none", |j| input.names[j].as_str())), format!("Observations: {} used, {} dropped", n, input.rows.len() - n), format!("Columns: {}, rank {}, aliased: {}", design.columns.len(), rank, if alias.is_empty() { "none".into() } else { alias.join(", ") }), String::new(),
        format!("Residuals: Min {}, 1Q {}, Median {}, 3Q {}, Max {}", real(statistics.quantiles[0]), real(statistics.quantiles[1]), real(statistics.quantiles[2]), real(statistics.quantiles[3]), real(statistics.quantiles[4])), String::new(), "Coefficients:".into()];
    let mut coefficient_rows = Vec::new();
    let mut confidence_rows = Vec::new();
    let mut robust_rows = Vec::new();
    for (j, column) in design.columns.iter().enumerate() {
        if let Some(k) = fit.accepted.iter().position(|&accepted| accepted == j) {
            let coefficient = fit.coefficients[j].unwrap();
            let error = statistics.sigma * fit.variance_factors[k].sqrt();
            let t = coefficient / error;
            let p = t_probability(t, statistics.degrees);
            coefficient_rows.push((vec![column.name.clone(), real(coefficient), real(error), real(t), probability(p)], significance(p).into()));
            confidence_rows.push(plain(vec![column.name.clone(), real(coefficient - statistics.critical * error), real(coefficient + statistics.critical * error)]));
            let robust = sum((0..n).map(|i| {
                let omega = fit.weighted_residuals[i] * fit.weighted_residuals[i] / ((1.0 - fit.leverage[i]) * (1.0 - fit.leverage[i]));
                omega * fit.g[i][k] * fit.g[i][k]
            })).sqrt();
            let t = coefficient / robust;
            let p = t_probability(t, statistics.degrees);
            robust_rows.push((vec![column.name.clone(), real(robust), real(t), probability(p)], significance(p).into()));
        } else {
            coefficient_rows.push(plain(vec![column.name.clone(), "NA".into(), "NA".into(), "NA".into(), "NA".into()]));
            confidence_rows.push(plain(vec![column.name.clone(), "NA".into(), "NA".into()]));
            robust_rows.push(plain(vec![column.name.clone(), "NA".into(), "NA".into(), "NA".into()]));
        }
    }
    lines.extend(table(&["term", "Estimate", "Std. Error", "t value", "Pr(>|t|)"], coefficient_rows));
    lines.extend(["---".into(), "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1".into(), String::new(),
        format!("Residual standard error: {} on {} degrees of freedom", real(statistics.sigma), statistics.degrees),
        format!("Multiple R-squared: {}, Adjusted R-squared: {}", real(statistics.r_squared), real(statistics.adjusted)),
        format!("F-statistic: {} on {} and {} DF, p-value: {}", optional(statistics.f), rank - 1, statistics.degrees, optional_probability(statistics.f_probability)),
        format!("Log-likelihood: {}, AIC: {}, BIC: {}", real(statistics.likelihood), real(statistics.aic), real(statistics.bic)),
        format!("PRESS: {}, Predicted R-squared: {}", real(statistics.press), real(statistics.predicted_r_squared)), String::new(),
        format!("Confidence intervals (level {}, t {}):", real(input.number("CONFIDENCE")), real(statistics.critical))]);
    lines.extend(table(&["term", "Lower", "Upper"], confidence_rows));
    lines.extend([String::new(), "Robust standard errors (HC3):".into()]);
    lines.extend(table(&["term", "Std. Error", "t value", "Pr(>|t|)"], robust_rows));
    lines.extend([String::new(), "Analysis of variance (sequential):".into()]);
    let mut sequential = Vec::new();
    for (term, name) in model.terms.iter().enumerate() {
        let accepted: Vec<_> = fit.accepted.iter().enumerate().filter(|(_, j)| design.columns[**j].term == Some(term)).map(|(k, _)| k).collect();
        if accepted.is_empty() { continue; }
        let squares = sum(accepted.iter().map(|&k| fit.effects[k] * fit.effects[k]));
        let mean = squares / accepted.len() as f64;
        let f = mean / (fit.rss / statistics.degrees as f64);
        let p = f_probability(f, accepted.len(), statistics.degrees);
        sequential.push((vec![name.name(), accepted.len().to_string(), real(squares), real(mean), real(f), probability(p)], significance(p).into()));
    }
    sequential.push(plain(vec!["Residuals".into(), statistics.degrees.to_string(), real(fit.rss), real(fit.rss / statistics.degrees as f64)]));
    lines.extend(table(&["term", "Df", "Sum Sq", "Mean Sq", "F value", "Pr(>F)"], sequential));
    lines.extend([String::new(), "Marginal F tests (drop one term):".into()]);
    let selected: Vec<_> = (0..model.terms.len()).collect();
    let drop = marginal(input, context, &selected, fit, statistics).into_iter().map(|test| {
        (vec![model.terms[test.term].name(), test.degrees.to_string(), real(test.squares), real(test.rss), optional(test.f), optional_probability(test.probability)], test.probability.map_or("", significance).into())
    }).collect();
    lines.extend(table(&["term", "Df", "Sum Sq", "RSS", "F value", "Pr(>F)"], drop));
    lines.extend([String::new(), "Variance inflation factors:".into()]);
    let mut vif_rows = Vec::new();
    for &column in fit.accepted.iter().skip(1) {
        let auxiliary: Matrix = context.x.iter().map(|row| fit.accepted.iter().copied().filter(|&j| j != column).map(|j| row[j]).collect()).collect();
        let response: Vec<_> = context.x.iter().map(|row| row[column]).collect();
        let auxiliary_fit = qr_solver::fit(&auxiliary, &response, &context.weights, input.number("RANK_TOL"));
        let mean = sum(response.iter().zip(&context.weights).map(|(&x, &w)| w * x)) / sum(context.weights.iter().copied());
        let total = sum(response.iter().zip(&context.weights).map(|(&x, &w)| w * (x - mean) * (x - mean)));
        let r_squared = 1.0 - auxiliary_fit.rss / total;
        let vif = 1.0 / (1.0 - r_squared);
        vif_rows.push((vec![design.columns[column].name.clone(), real(vif)], if vif > input.number("VIF") { "high".into() } else { String::new() }));
    }
    lines.extend(table(&["column", "VIF"], vif_rows));
    let reset_matrix: Matrix = context.x.iter().enumerate().map(|(i, row)| {
        let mut values: Vec<_> = fit.accepted.iter().map(|&j| row[j]).collect();
        let value = fit.fitted[i];
        values.extend([value * value, value * value * value]);
        values
    }).collect();
    let reset = qr_solver::fit(&reset_matrix, &context.y, &context.weights, input.number("RANK_TOL"));
    let reset_degrees = reset.accepted.len() - rank;
    let reset_residual_degrees = n - reset.accepted.len();
    let reset_f = ((fit.rss - reset.rss) / reset_degrees as f64) / (reset.rss / reset_residual_degrees as f64);
    let outlier = largest_absolute(&diagnostics.studentized);
    let outlier_p = t_probability(diagnostics.studentized[outlier], statistics.degrees - 1);
    let autocorrelation = if diagnostics.durbin_watson < input.number("DURBIN_WATSON") { "positive autocorrelation" } else if diagnostics.durbin_watson > 4.0 - input.number("DURBIN_WATSON") { "negative autocorrelation" } else { "no autocorrelation" };
    let flagged = |flag| diagnostics.flags.iter().filter(|flags| flags.contains(flag)).count();
    lines.extend([String::new(), "Diagnostics:".into(), format!("Durbin-Watson: {} ({autocorrelation})", real(diagnostics.durbin_watson)),
        format!("Breusch-Pagan: {} on {} DF, p-value: {} ({})", real(diagnostics.bp), diagnostics.bp_degrees, probability(diagnostics.bp_probability), if diagnostics.bp_probability < input.number("BREUSCH_PAGAN") { "heteroscedastic" } else { "homoscedastic" }),
        format!("Jarque-Bera: {} on 2 DF, p-value: {}, skewness {}, kurtosis {} ({})", real(diagnostics.jb), probability(diagnostics.jb_probability), real(diagnostics.skewness), real(diagnostics.kurtosis), if diagnostics.jb_probability < input.number("NORMALITY") { "non-normal" } else { "normal" }),
        format!("RESET (powers 2 and 3): F {} on {} and {} DF, p-value: {}", real(reset_f), reset_degrees, reset_residual_degrees, probability(f_probability(reset_f, reset_degrees, reset_residual_degrees))),
        format!("Outlier test: row {}, studentized {}, unadjusted p-value: {}, Bonferroni p-value: {}", design.used[outlier] + 1, real(diagnostics.studentized[outlier]), probability(outlier_p), probability((n as f64 * outlier_p).min(1.0))),
        format!("Flagged rows: leverage {}, outlier {}, cooks {}, dffits {}, any {}", flagged('H'), flagged('O'), flagged('C'), flagged('F'), diagnostics.flags.iter().filter(|flags| flags.as_str() != "-").count()),
        "Largest Cook's distances:".into()]);
    let mut order: Vec<_> = (0..n).collect();
    order.sort_by(|&a, &b| diagnostics.cooks[b].total_cmp(&diagnostics.cooks[a]).then(a.cmp(&b)));
    for i in order.into_iter().take(3) { lines.push(format!("row {}: cooks_d {}, leverage {}, studentized {}, flags {}", design.used[i] + 1, real(diagnostics.cooks[i]), real(fit.leverage[i]), real(diagnostics.studentized[i]), diagnostics.flags[i])); }
    lines.push("Largest absolute DFBETAS:".into());
    let rows = fit.accepted.iter().enumerate().map(|(k, &j)| {
        let i = largest_absolute(&diagnostics.dfbetas.iter().map(|row| row[k]).collect::<Vec<_>>());
        plain(vec![design.columns[j].name.clone(), (design.used[i] + 1).to_string(), real(diagnostics.dfbetas[i][k])])
    }).collect();
    lines.extend(table(&["column", "row", "DFBETAS"], rows));
    lines
}

struct PredictionCheck {
    predicted: usize,
    actual: usize,
    rmse: Option<f64>,
    covered: usize,
}

fn prediction_lines(input: &Input, context: &Context, number: usize) -> (Vec<String>, PredictionCheck) {
    let mut lines = Vec::new();
    let mut check = PredictionCheck { predicted: 0, actual: 0, rmse: None, covered: 0 };
    let mut squares = 0.0;
    for (i, row) in input.prediction_rows.iter().enumerate() {
        let mut fields = vec![number.to_string(), (i + 1).to_string()];
        if !context.design.predictable(row) { fields.extend(vec!["NA".into(); 9]); lines.push(fields.join(",")); continue; }
        check.predicted += 1;
        let values = context.design.values(row);
        let fit = &context.fit;
        let estimate = sum(fit.accepted.iter().map(|&j| values[j] * fit.coefficients[j].unwrap()));
        let u: Vec<_> = (0..fit.accepted.len()).map(|k| sum(fit.accepted.iter().enumerate().map(|(m, &j)| values[j] * fit.inverse[m][k]))).collect();
        let error = context.statistics.sigma * sum(u.iter().map(|v| v * v)).sqrt();
        let confidence = context.statistics.critical * error;
        let prediction = context.statistics.critical * (context.statistics.sigma * context.statistics.sigma + error * error).sqrt();
        fields.extend([estimate, error, estimate - confidence, estimate + confidence, estimate - prediction, estimate + prediction].iter().map(|&v| real(v)));
        if let Some(actual) = row[context.model.response].number() {
            let residual = actual - estimate;
            let covered = estimate - prediction <= actual && actual <= estimate + prediction;
            fields.extend([real(actual), real(residual), if covered { "yes".into() } else { "no".into() }]);
            squares += residual * residual;
            check.actual += 1;
            check.covered += usize::from(covered);
        } else { fields.extend(vec!["NA".into(); 3]); }
        lines.push(fields.join(","));
    }
    if check.actual > 0 { check.rmse = Some((squares / check.actual as f64).sqrt()); }
    (lines, check)
}

fn selection(input: &Input, context: &Context) -> Vec<String> {
    let term_count = context.model.terms.len();
    let n = context.y.len();
    let alpha = input.number("ALPHA_REMOVE");
    let mut lines = vec![format!("Backward elimination (model 1, alpha {}, rows {n})", real(alpha))];
    let mut selected: Vec<_> = (0..term_count).collect();
    let mut step = 1;
    loop {
        let (fit, statistics) = subset_fit(input, context, &selected);
        lines.push(format!("Step {}: {} (RSS {}, df {}, AIC {})", step, formula::format(&context.model, &selected, input), real(fit.rss), statistics.degrees, real(statistics.aic)));
        if selected.is_empty() { lines.push("  stop: no removable terms".into()); break; }
        let tests = marginal(input, context, &selected, &fit, &statistics);
        for test in &tests { lines.push(format!("  - {}: F {} on {} and {} DF, p-value {}", context.model.terms[test.term].name(), optional(test.f), test.degrees, statistics.degrees, optional_probability(test.probability))); }
        let mut largest = 0;
        for i in 1..tests.len() { if tests[i].probability.unwrap() > tests[largest].probability.unwrap() { largest = i; } }
        let test = &tests[largest];
        if test.probability.unwrap() > alpha {
            lines.push(format!("  remove {}", context.model.terms[test.term].name()));
            selected.retain(|&term| term != test.term);
            step += 1;
        } else { lines.push(format!("  stop: largest p-value {} is not above {}", probability(test.probability.unwrap()), real(alpha))); break; }
    }
    lines.push(format!("Final model: {}", formula::format(&context.model, &selected, input)));
    lines.extend([String::new(), format!("Forward selection by AIC (model 1, rows {n})")]);
    selected.clear();
    step = 1;
    loop {
        let (_, statistics) = subset_fit(input, context, &selected);
        lines.push(format!("Step {}: {} (AIC {})", step, formula::format(&context.model, &selected, input), real(statistics.aic)));
        let candidates: Vec<_> = (0..term_count).filter(|term| !selected.contains(term) && (0..term_count).filter(|&other| context.model.terms[other].contained(&context.model.terms[*term])).all(|other| selected.contains(&other))).collect();
        if candidates.is_empty() { lines.push("  stop: no candidate terms remain".into()); break; }
        let mut results = Vec::new();
        for term in candidates {
            let mut expanded = selected.clone();
            expanded.push(term);
            expanded.sort_unstable();
            let (_, result) = subset_fit(input, context, &expanded);
            lines.push(format!("  + {}: AIC {}", context.model.terms[term].name(), real(result.aic)));
            results.push((term, result.aic));
        }
        let mut smallest = 0;
        for i in 1..results.len() { if results[i].1 < results[smallest].1 { smallest = i; } }
        let (term, aic) = results[smallest];
        if aic < statistics.aic {
            selected.push(term);
            selected.sort_unstable();
            lines.push(format!("  add {}", context.model.terms[term].name()));
            step += 1;
        } else { lines.push("  stop: no candidate lowers the AIC".into()); break; }
    }
    lines.push(format!("Final model: {}", formula::format(&context.model, &selected, input)));
    let mut subsets = Vec::new();
    for mask in 0..1_usize << term_count {
        let selected: Vec<_> = (0..term_count).filter(|&term| mask & (1 << term) != 0).collect();
        let hierarchical = selected.iter().all(|&term| (0..term_count).filter(|&other| context.model.terms[other].contained(&context.model.terms[term])).all(|other| selected.contains(&other)));
        if !hierarchical { continue; }
        let (fit, statistics) = subset_fit(input, context, &selected);
        subsets.push((mask, selected, statistics.bic, statistics.aic, fit.accepted.len()));
    }
    subsets.sort_by(|a, b| a.2.total_cmp(&b.2).then(a.0.cmp(&b.0)));
    lines.extend([String::new(), format!("Best subsets by BIC (model 1, rows {}, subsets {})", n, subsets.len())]);
    for (i, (_, selected, bic, aic, rank)) in subsets.into_iter().take(input.number("BEST_SUBSETS") as usize).enumerate() {
        lines.push(format!("{}. BIC {}, AIC {}, rank {}: {}", i + 1, real(bic), real(aic), rank, formula::format(&context.model, &selected, input)));
    }
    lines
}

fn plot_counts(horizontal: &[f64], vertical: &[f64], low: f64, high: f64, width: usize, height: usize, limit: f64) -> Vec<Vec<usize>> {
    let mut cells = vec![vec![0; width]; height];
    for (&x, &y) in horizontal.iter().zip(vertical) {
        let column = (((x - low) / (high - low) * width as f64).floor() as usize).min(width - 1);
        let row = ((limit - y) / (2.0 * limit) * height as f64).floor().max(0.0).min((height - 1) as f64) as usize;
        cells[row][column] += 1;
    }
    cells
}

fn frame(cells: &[Vec<usize>]) -> Vec<String> {
    let border = format!("+{}+", "-".repeat(cells[0].len()));
    let mut lines = vec![border.clone()];
    for (r, row) in cells.iter().enumerate() {
        let marks: String = row.iter().map(|&count| if count == 0 { if r == cells.len() / 2 { '-' } else { '.' } } else if count <= 9 { (b'0' + count as u8) as char } else { '*' }).collect();
        lines.push(format!("|{marks}|"));
    }
    lines.push(border);
    lines
}

fn residual_plot(input: &Input, context: &Context, number: usize) -> Vec<String> {
    let width = input.number("PLOT") as usize;
    let height: usize = input.params["PLOT"][1].parse().unwrap();
    let limit: f64 = input.params["PLOT"][2].parse().unwrap();
    let fitted = &context.fit.fitted;
    let low = fitted.iter().copied().fold(f64::INFINITY, f64::min);
    let high = fitted.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let residuals = &context.diagnostics.studentized;
    let cells = plot_counts(fitted, residuals, low, high, width, height, limit);
    let mut lines = vec![format!("Model {number}: studentized residuals vs fitted values"), format!("fitted {} to {}, studentized {} to {}", real(low), real(high), real(-limit), real(limit))];
    lines.extend(frame(&cells));
    lines.push(format!("points: {}, above +2: {}, below -2: {}, outside range: {}", fitted.len(), residuals.iter().filter(|&&t| t > 2.0).count(), residuals.iter().filter(|&&t| t < -2.0).count(), residuals.iter().filter(|t| t.abs() > limit).count()));
    lines.push("Histogram of studentized residuals:".into());
    let counts: Vec<_> = cells.iter().map(|row| row.iter().sum::<usize>()).collect();
    let maximum = *counts.iter().max().unwrap();
    for (row, count) in counts.into_iter().enumerate() {
        let bar = (count * 40 + maximum - 1) / maximum;
        let suffix = if bar > 0 { format!(" {}", "#".repeat(bar)) } else { String::new() };
        lines.push(format!("{} to {}: {}{}", real(limit - 2.0 * limit * (row + 1) as f64 / height as f64), real(limit - 2.0 * limit * row as f64 / height as f64), count, suffix));
    }
    let maximum = context.fit.leverage.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    lines.extend([format!("Model {number}: studentized residuals vs leverage"), format!("leverage 0.0000 to {}, studentized {} to {}", real(maximum), real(-limit), real(limit))]);
    lines.extend(frame(&plot_counts(&context.fit.leverage, residuals, 0.0, maximum, width, height, limit)));
    lines
}

fn write(name: &str, lines: &[String]) { fs::write(format!("output/{name}"), format!("{}\n", lines.join("\n"))).unwrap(); }

fn main() {
    let input = dataframe::read();
    let models: Vec<_> = input.model_lines.iter().map(|line| context(&input, line)).collect();
    let mut summary = data_summary(&input);
    let mut diagnostics = vec!["model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags".into()];
    let mut predictions = vec!["model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered".into()];
    let mut checks = Vec::new();
    let mut plots = Vec::new();
    for (index, model) in models.iter().enumerate() {
        if index > 0 { summary.push(String::new()); plots.push(String::new()); }
        summary.extend(model_summary(&input, model, index + 1));
        for i in 0..model.y.len() {
            diagnostics.push(format!("{},{},{},{},{},{},{},{},{}", index + 1, model.design.used[i] + 1, real(model.fit.fitted[i]), real(model.fit.residuals[i]), real(model.fit.leverage[i]), real(model.diagnostics.studentized[i]), real(model.diagnostics.cooks[i]), real(model.diagnostics.dffits[i]), model.diagnostics.flags[i]));
        }
        let (lines, check) = prediction_lines(&input, model, index + 1);
        predictions.extend(lines);
        checks.push(check);
        plots.extend(residual_plot(&input, model, index + 1));
    }
    summary.extend([String::new(), "Model comparison:".into()]);
    let comparison = models.iter().enumerate().map(|(index, model)| {
        let s = &model.statistics;
        plain(vec![(index + 1).to_string(), model.y.len().to_string(), model.fit.accepted.len().to_string(), real(s.sigma), real(s.r_squared), real(s.adjusted), real(s.predicted_r_squared), real(s.aic), real(s.bic)])
    }).collect();
    summary.extend(table(&["model", "n", "rank", "sigma", "R-squared", "Adj. R-squared", "Pred. R-squared", "AIC", "BIC"], comparison));
    summary.extend([String::new(), "Prediction check:".into()]);
    for (i, check) in checks.iter().enumerate() { summary.push(format!("model {}: {} predicted, {} with actual values, RMSE {}, inside prediction interval {}", i + 1, check.predicted, check.actual, optional(check.rmse), check.covered)); }
    fs::create_dir_all("output").unwrap();
    write("summary.txt", &summary);
    write("diagnostics.csv", &diagnostics);
    write("selection.txt", &selection(&input, &models[0]));
    write("predictions.csv", &predictions);
    write("residual_plot.txt", &plots);
}
