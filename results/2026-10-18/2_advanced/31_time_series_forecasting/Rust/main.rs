mod autoregression;
mod decomposition;
mod evaluation;
mod series_io;
mod smoothing;

use decomposition::{decompose, least_squares_line, mean, sample_variance, total, Decomposition};
use series_io::{next_month, optional_real, real, Inventory, Series, Settings};
use smoothing::{Parameters, State};
use std::collections::BTreeMap;

const METHODS: [&str; 11] = [
    "naive", "snaive", "drift", "ses", "holt", "damped", "hw_add", "hw_mult",
    "decomp_add", "decomp_mult", "ar",
];
const MODELS: [&str; 12] = [
    "naive", "snaive", "drift", "ses", "holt", "damped", "hw_add", "hw_mult",
    "decomp_add", "decomp_mult", "ar", "combo",
];

#[derive(Clone)]
struct ArFit {
    kind: usize,
    differenced: Vec<f64>,
    offset: usize,
    average: f64,
    variances: Vec<f64>,
    order: usize,
    sigma2: f64,
    aic: Vec<f64>,
    coefficients: Vec<f64>,
    correlations: Vec<f64>,
    partial: Vec<f64>,
}

#[derive(Clone)]
enum Fit {
    Naive,
    SeasonalNaive,
    Drift(f64),
    Smooth { parameters: Parameters, states: Vec<State> },
    Decomp { intercept: f64, slope: f64, seasonal: Vec<f64> },
    Ar(ArFit),
    Combo(Vec<Model>),
}

#[derive(Clone)]
struct Model {
    name: &'static str,
    values: Vec<f64>,
    season: usize,
    residuals: Vec<f64>,
    fit: Fit,
}

struct CrossValidation {
    counts: Vec<usize>,
    sigma: Vec<f64>,
    mae: Vec<f64>,
    rmse: f64,
}

struct Interval {
    forecast: f64,
    lo80: f64,
    hi80: f64,
    lo95: f64,
    hi95: f64,
}

impl Interval {
    fn csv(&self) -> String {
        [self.forecast, self.lo80, self.hi80, self.lo95, self.hi95]
            .into_iter().map(real).collect::<Vec<_>>().join(",")
    }
}

struct Measures {
    accuracy: evaluation::Accuracy,
    cover80: usize,
    cover95: usize,
    winkler80: f64,
    winkler95: f64,
}

struct Lift {
    kind: String,
    times: Vec<usize>,
    value: f64,
}

struct Prepared {
    values: Vec<f64>,
    corrected: Vec<f64>,
    components: Decomposition,
    past: Vec<Option<String>>,
    outliers: Vec<Option<f64>>,
    lifts: Vec<Lift>,
    strength_trend: f64,
    strength_seasonal: f64,
    future_periods: Vec<String>,
}

struct Reports {
    decomposition: Vec<String>,
    models: Vec<String>,
    forecasts: Vec<String>,
    accuracy: Vec<String>,
    cv: Vec<String>,
    correlogram: Vec<String>,
    chart: Vec<String>,
    plan: Vec<String>,
}

fn rmse(errors: &[f64]) -> f64 {
    (total(errors.iter().map(|e| e * e)) / errors.len() as f64).sqrt()
}

fn prepare(record: &Series, settings: &Settings) -> Prepared {
    let count = record.raw.len();
    let mut values: Vec<f64> = record.raw.iter().map(|v| v.unwrap_or(0) as f64).collect();
    let mut left = 0;
    while left + 1 < count {
        let mut right = left + 1;
        while record.raw[right].is_none() {
            right += 1;
        }
        for t in left + 1..right {
            values[t] = record.raw[left].unwrap() as f64
                + (record.raw[right].unwrap() - record.raw[left].unwrap()) as f64
                    * (t - left) as f64 / (right - left) as f64;
        }
        left = right;
    }
    let components = decompose(&values, settings.season);
    let residuals: Vec<f64> = components.defined.iter().map(|&t| components.residual_add[t].unwrap()).collect();
    let average = mean(&residuals);
    let deviation = sample_variance(&residuals).sqrt();
    let mut past = vec![None; count];
    let mut lifts: Vec<Lift> = Vec::new();
    for t in 0..count {
        if let Some(kind) = record.events.get(&record.periods[t]) {
            past[t] = Some(kind.clone());
            let index = match lifts.iter().position(|lift| lift.kind == *kind) {
                Some(index) => index,
                None => {
                    lifts.push(Lift { kind: kind.clone(), times: Vec::new(), value: 0.0 });
                    lifts.len() - 1
                }
            };
            lifts[index].times.push(t);
        }
    }
    for lift in &mut lifts {
        lift.value = total(lift.times.iter().map(|&t| values[t]
            / (components.trend[t].unwrap() + components.additive[t % settings.season])))
            / lift.times.len() as f64;
    }
    let mut outliers = vec![None; count];
    for &t in &components.defined {
        let centered = components.residual_add[t].unwrap() - average;
        if record.raw[t].is_some() && past[t].is_none() && centered.abs() > settings.outlier * deviation {
            outliers[t] = Some(centered / deviation);
        }
    }
    let corrected = (0..count).map(|t| {
        if past[t].is_some() || outliers[t].is_some() {
            components.trend[t].unwrap() + components.additive[t % settings.season]
        } else {
            values[t]
        }
    }).collect();
    let trend_residuals: Vec<f64> = components.defined.iter().map(|&t| components.trend[t].unwrap() + components.residual_add[t].unwrap()).collect();
    let seasonal_residuals: Vec<f64> = components.defined.iter().map(|&t| components.additive[t % settings.season] + components.residual_add[t].unwrap()).collect();
    let variance = sample_variance(&residuals);
    let strength_trend = (1.0 - variance / sample_variance(&trend_residuals)).max(0.0);
    let strength_seasonal = (1.0 - variance / sample_variance(&seasonal_residuals)).max(0.0);
    let mut period = record.periods.last().unwrap().clone();
    let mut future_periods = Vec::new();
    for _ in 0..settings.horizon {
        period = next_month(&period);
        future_periods.push(period.clone());
    }
    Prepared { values, corrected, components, past, outliers, lifts, strength_trend, strength_seasonal, future_periods }
}

fn fit_ar(values: &[f64], settings: &Settings) -> (ArFit, Vec<f64>) {
    let candidates: Vec<_> = (0..4).map(|kind| {
        let (transformed, offset) = autoregression::difference(values, settings.season, kind);
        let (average, variance, _) = autoregression::autocorrelation(&transformed, 0);
        (transformed, offset, average, variance)
    }).collect();
    let mut kind = 0;
    for i in 1..4 {
        if candidates[i].3 < candidates[kind].3 {
            kind = i;
        }
    }
    let (differenced, offset, average, variance) = &candidates[kind];
    let (_, _, correlations) = autoregression::autocorrelation(differenced, settings.max_lag);
    let recursion = autoregression::durbin_levinson(&correlations);
    let aic: Vec<f64> = (0..=settings.max_ar).map(|p| differenced.len() as f64
        * (variance * recursion.variances[p]).ln() + 2.0 * p as f64).collect();
    let order = evaluation::rank_models(&aic)[0];
    let coefficients = recursion.coefficients[order].clone();
    let errors = autoregression::residuals(differenced, *average, &coefficients);
    let fit = ArFit {
        kind, differenced: differenced.clone(), offset: *offset, average: *average,
        variances: candidates.iter().map(|candidate| candidate.3).collect(), order,
        sigma2: variance * recursion.variances[order], aic, coefficients, correlations,
        partial: recursion.partial,
    };
    (fit, errors)
}

fn fit_method(name: &'static str, values: &[f64], settings: &Settings) -> Model {
    let count = values.len();
    let season = settings.season;
    let fit;
    let residuals;
    match name {
        "naive" => {
            fit = Fit::Naive;
            residuals = (1..count).map(|t| values[t] - values[t - 1]).collect();
        }
        "snaive" => {
            fit = Fit::SeasonalNaive;
            residuals = (season..count).map(|t| values[t] - values[t - season]).collect();
        }
        "drift" => {
            let slope = (values[count - 1] - values[0]) / (count - 1) as f64;
            fit = Fit::Drift(slope);
            residuals = (1..count).map(|t| values[t] - values[t - 1] - slope).collect();
        }
        "ses" | "holt" | "damped" | "hw_add" | "hw_mult" => {
            let zero = [0.0];
            let one = [1.0];
            let beta = if name == "ses" { &zero[..] } else { &settings.beta[..] };
            let gamma = if name == "hw_add" || name == "hw_mult" { &settings.gamma[..] } else { &zero[..] };
            let phi = if name == "damped" { &settings.phi[..] } else { &one[..] };
            let mut best: Option<(f64, Parameters, Vec<f64>, Vec<State>)> = None;
            for &alpha in &settings.alpha {
                for &beta in beta {
                    for &gamma in gamma {
                        for &phi in phi {
                            let parameters = Parameters { alpha, beta, gamma, phi };
                            let (errors, states) = smoothing::recurse(name, values, season, parameters);
                            let score = total(errors.iter().map(|e| e * e));
                            if best.as_ref().map_or(true, |current| score < current.0) {
                                best = Some((score, parameters, errors, states));
                            }
                        }
                    }
                }
            }
            let (_, parameters, errors, states) = best.unwrap();
            residuals = errors;
            fit = Fit::Smooth { parameters, states };
        }
        "decomp_add" | "decomp_mult" => {
            let components = decompose(values, season);
            let seasonal = if name == "decomp_add" { components.additive } else { components.multiplicative };
            let adjusted: Vec<f64> = values.iter().enumerate().map(|(t, &v)| {
                if name == "decomp_add" { v - seasonal[t % season] } else { v / seasonal[t % season] }
            }).collect();
            let (intercept, slope) = least_squares_line(&adjusted);
            residuals = values.iter().enumerate().map(|(t, &v)| {
                let base = intercept + slope * (t + 1) as f64;
                v - if name == "decomp_add" { base + seasonal[t % season] } else { base * seasonal[t % season] }
            }).collect();
            fit = Fit::Decomp { intercept, slope, seasonal };
        }
        _ => {
            let (ar, errors) = fit_ar(values, settings);
            fit = Fit::Ar(ar);
            residuals = errors;
        }
    }
    Model { name, values: values.to_vec(), season, residuals, fit }
}

fn combination(members: Vec<Model>, values: &[f64], season: usize) -> Model {
    Model { name: "combo", values: values.to_vec(), season, residuals: Vec::new(), fit: Fit::Combo(members) }
}

fn forecast(model: &Model, origin: usize, steps: usize) -> Vec<f64> {
    let values = &model.values;
    match &model.fit {
        Fit::Naive => vec![values[origin - 1]; steps],
        Fit::SeasonalNaive => (0..steps).map(|i| values[origin - model.season + i % model.season]).collect(),
        Fit::Drift(_) => {
            let slope = (values[origin - 1] - values[0]) / (origin - 1) as f64;
            (1..=steps).map(|k| values[origin - 1] + k as f64 * slope).collect()
        }
        Fit::Smooth { parameters, states } => smoothing::forecast(model.name, &states[origin], *parameters, origin, steps, model.season),
        Fit::Decomp { intercept, slope, seasonal } => (0..steps).map(|i| {
            let t = origin + i;
            let base = intercept + slope * (t + 1) as f64;
            if model.name == "decomp_add" { base + seasonal[t % model.season] } else { base * seasonal[t % model.season] }
        }).collect(),
        Fit::Ar(ar) => autoregression::forecast(values, &ar.differenced, ar.offset, ar.kind,
            ar.average, &ar.coefficients, origin, steps, model.season),
        Fit::Combo(members) => {
            let predictions: Vec<Vec<f64>> = members.iter().map(|member| forecast(member, origin, steps)).collect();
            (0..steps).map(|i| total(predictions.iter().map(|row| row[i])) / members.len() as f64).collect()
        }
    }
}

fn cross_validate(model: &Model, settings: &Settings) -> CrossValidation {
    let mut counts = vec![0; settings.horizon];
    let mut squared = vec![0.0; settings.horizon];
    let mut absolute = vec![0.0; settings.horizon];
    for origin in settings.cv_start..model.values.len() {
        let predictions = forecast(model, origin, settings.horizon.min(model.values.len() - origin));
        for (i, prediction) in predictions.iter().enumerate() {
            let error = model.values[origin + i] - prediction;
            counts[i] += 1;
            squared[i] += error * error;
            absolute[i] += error.abs();
        }
    }
    let sigma = squared.iter().zip(&counts).map(|(value, &count)| (value / count as f64).sqrt()).collect();
    let mae = absolute.iter().zip(&counts).map(|(value, &count)| value / count as f64).collect();
    let denominator: usize = counts[..settings.holdout].iter().sum();
    let rmse = (total(squared[..settings.holdout].iter().copied()) / denominator as f64).sqrt();
    CrossValidation { counts, sigma, mae, rmse }
}

fn intervals(predictions: &[f64], sigma: &[f64], coefficients: &[f64], multipliers: &[f64]) -> Vec<Interval> {
    predictions.iter().enumerate().map(|(i, &value)| {
        let multiplier = multipliers[i];
        Interval {
            forecast: value * multiplier,
            lo80: (value - coefficients[0] * sigma[i]) * multiplier,
            hi80: (value + coefficients[0] * sigma[i]) * multiplier,
            lo95: (value - coefficients[1] * sigma[i]) * multiplier,
            hi95: (value + coefficients[1] * sigma[i]) * multiplier,
        }
    }).collect()
}

fn model_lines(model: &Model) -> Vec<String> {
    let name = model.name;
    let common = format!("rmse {} residuals {}", real(rmse(&model.residuals)), model.residuals.len());
    match &model.fit {
        Fit::Naive | Fit::SeasonalNaive => vec![format!("{name} {common}")],
        Fit::Drift(slope) => vec![format!("drift slope {} {common}", real(*slope))],
        Fit::Smooth { parameters, states } => {
            let mut first = format!("{name} alpha {}", real(parameters.alpha));
            if name != "ses" {
                first += &format!(" beta {}", real(parameters.beta));
            }
            if name == "damped" {
                first += &format!(" phi {}", real(parameters.phi));
            }
            if name == "hw_add" || name == "hw_mult" {
                first += &format!(" gamma {}", real(parameters.gamma));
            }
            let state = states.last().unwrap();
            first += &format!(" {common} level {}", real(state.level));
            if name != "ses" {
                first += &format!(" slope {}", real(state.slope));
            }
            let mut lines = vec![first];
            if !state.seasonal.is_empty() {
                let seasonal = (0..model.season).map(|i| real(state.seasonal[(model.values.len() + i) % model.season])).collect::<Vec<_>>().join(" ");
                lines.push(format!("{name} seasonal {seasonal}"));
            }
            lines
        }
        Fit::Decomp { intercept, slope, seasonal } => vec![
            format!("{name} intercept {} slope {} {common}", real(*intercept), real(*slope)),
            format!("{name} seasonal {}", seasonal.iter().copied().map(real).collect::<Vec<_>>().join(" ")),
        ],
        Fit::Ar(ar) => {
            let variances = autoregression::KINDS.iter().zip(&ar.variances).map(|(kind, &v)| format!("{kind} {}", real(v))).collect::<Vec<_>>().join(" ");
            let coefficients = if ar.coefficients.is_empty() { "none".to_owned() }
                else { ar.coefficients.iter().copied().map(real).collect::<Vec<_>>().join(" ") };
            vec![
                format!("ar variance {variances}"),
                format!("ar difference {} n {} mean {} order {} sigma2 {} {common}",
                    autoregression::KINDS[ar.kind], ar.differenced.len(), real(ar.average), ar.order, real(ar.sigma2)),
                format!("ar aic {}", ar.aic.iter().copied().map(real).collect::<Vec<_>>().join(" ")),
                format!("ar coefficients {coefficients}"),
            ]
        }
        Fit::Combo(_) => Vec::new(),
    }
}

fn inventory_plan(model: &Model, demands: &[f64], periods: &[String], policy: &Inventory,
                  settings: &Settings, lines: &mut Vec<String>) {
    let protection = policy.lead_time + policy.review;
    let errors: Vec<f64> = (settings.cv_start..=model.values.len() - protection).map(|origin| {
        let predictions = forecast(model, origin, protection);
        total(predictions.iter().enumerate().map(|(i, prediction)| model.values[origin + i] - prediction))
    }).collect();
    let safety = policy.service * rmse(&errors);
    lines.push(format!("policy on_hand {} lead_time {} review {} service {} safety_stock {}",
        policy.on_hand, policy.lead_time, policy.review, real(policy.service), real(safety)));
    let reviews: Vec<usize> = (1..=demands.len() - protection + 1).step_by(policy.review).collect();
    let end = reviews.last().unwrap() - 1 + protection;
    let mut receipts = vec![0_i64; end + policy.lead_time + 1];
    let mut on_hand = policy.on_hand as f64;
    let mut outstanding = 0_i64;
    let mut orders = 0;
    let mut ordered = 0_i64;
    let mut short_periods = 0;
    let mut stocks = Vec::new();
    for step in 1..=end {
        let receipt = receipts[step];
        on_hand += receipt as f64;
        outstanding -= receipt;
        let period = &periods[step - 1];
        if reviews.contains(&step) {
            let position = on_hand + outstanding as f64;
            let target = total(demands[step - 1..step - 1 + protection].iter().copied()) + safety;
            let quantity = (target - position).ceil().max(0.0) as i64;
            lines.push(format!("review {period} position {} target {} order {quantity}", real(position), real(target)));
            if quantity > 0 {
                orders += 1;
                ordered += quantity;
                outstanding += quantity;
                receipts[step + policy.lead_time] = quantity;
            }
        }
        on_hand -= demands[step - 1];
        let status = if on_hand < 0.0 { "short" } else if on_hand < safety { "low" } else { "ok" };
        if status == "short" {
            short_periods += 1;
        }
        stocks.push(on_hand);
        lines.push(format!("period {period} demand {} receipt {receipt} on_hand {} status {status}", real(demands[step - 1]), real(on_hand)));
    }
    let lowest = stocks.iter().copied().fold(f64::INFINITY, f64::min);
    lines.push(format!("summary orders {orders} ordered {ordered} short_periods {short_periods} lowest {} average {}", real(lowest), real(mean(&stocks))));
}

fn yearly_totals(record: &Series, data: &Prepared, demands: &[f64], lines: &mut Vec<String>) {
    let mut years: BTreeMap<String, (usize, f64, usize, f64)> = BTreeMap::new();
    for (period, &value) in record.periods.iter().zip(&data.values) {
        let row = years.entry(period[..4].to_owned()).or_insert((0, 0.0, 0, 0.0));
        row.0 += 1;
        row.1 += value;
    }
    for (period, &value) in data.future_periods.iter().zip(demands) {
        let row = years.entry(period[..4].to_owned()).or_insert((0, 0.0, 0, 0.0));
        row.2 += 1;
        row.3 += value;
    }
    let mut previous: Option<(bool, f64)> = None;
    for (year, (actual_months, actual, forecast_months, forecast)) in years {
        let total = actual + forecast;
        let complete = actual_months + forecast_months == 12;
        let growth = previous.filter(|(was_complete, _)| complete && *was_complete)
            .map(|(_, old)| 100.0 * (total - old) / old);
        lines.push(format!("year {year} actual_months {actual_months} actual {} forecast_months {forecast_months} forecast {} total {} growth {}",
            real(actual), real(forecast), real(total), optional_real(growth)));
        previous = Some((complete, total));
    }
}

fn centered_bar(value: f64, center: usize, width: usize, band: Option<f64>) -> String {
    let mut cells = vec![b' '; center * 2 + 1];
    if let Some(band) = band {
        let threshold = (band * center as f64 + 0.5).floor() as usize;
        cells[center - threshold] = b':';
        cells[center + threshold] = b':';
    }
    cells[center] = b'|';
    if value > 0.0 {
        for i in center + 1..center + 1 + width {
            cells[i] = b'#';
        }
    } else if value < 0.0 {
        for i in center - width..center {
            cells[i] = b'#';
        }
    }
    String::from_utf8(cells).unwrap()
}

fn residual_diagnostics(model: &Model, lags: &[usize], lines: &mut Vec<String>) {
    let errors = &model.residuals;
    let count = errors.len();
    let average = mean(errors);
    let centered: Vec<f64> = errors.iter().map(|e| e - average).collect();
    let squared = total(centered.iter().map(|v| v * v));
    let m2 = squared / count as f64;
    let m3 = total(centered.iter().map(|v| v * v * v)) / count as f64;
    let m4 = total(centered.iter().map(|v| v * v * v * v)) / count as f64;
    let sd = (squared / (count - 1) as f64).sqrt();
    let dw = total((1..count).map(|i| (errors[i] - errors[i - 1]) * (errors[i] - errors[i - 1])))
        / total(errors.iter().map(|v| v * v));
    let skewness = m3 / (m2 * m2.sqrt());
    let kurtosis = m4 / (m2 * m2) - 3.0;
    let jb = count as f64 / 6.0 * (skewness * skewness + kurtosis * kurtosis / 4.0);
    lines.push(format!("residuals {} n {count} mean {} sd {} dw {} skewness {} kurtosis {} jb {}",
        model.name, real(average), real(sd), real(dw), real(skewness), real(kurtosis), real(jb)));
    let tests = autoregression::ljung_box(errors, lags).into_iter().map(|(lag, q, p)| format!("lag {lag} q {} p {}", real(q), real(p))).collect::<Vec<_>>().join(" ");
    lines.push(format!("ljung_box {} {tests}", model.name));
}

fn forecast_chart(row: &Interval, actual: Option<f64>, low: f64, high: f64) -> String {
    let column = |value: f64| ((value - low) / (high - low) * 60.0 + 0.5).floor() as usize;
    let mut cells = vec![b' '; 61];
    for (start, stop, symbol) in [(row.lo95, row.hi95, b'-'), (row.lo80, row.hi80, b'=')] {
        for i in column(start)..=column(stop) {
            cells[i] = symbol;
        }
    }
    cells[column(row.forecast)] = b'o';
    if let Some(value) = actual {
        cells[column(value)] = b'*';
    }
    String::from_utf8(cells).unwrap()
}

fn analyze(record: &Series, settings: &Settings, reports: &mut Reports) {
    let data = prepare(record, settings);
    let count = data.values.len();
    let training_count = count - settings.holdout;
    let training = &data.corrected[..training_count];
    let actual = &data.values[training_count..];
    let mut models: Vec<Model> = METHODS.iter().map(|&name| fit_method(name, training, settings)).collect();
    let mut cvs: Vec<CrossValidation> = models.iter().map(|model| cross_validate(model, settings)).collect();
    let selected = evaluation::rank_models(&cvs.iter().map(|cv| cv.rmse).collect::<Vec<_>>())[..settings.combo].to_vec();
    let members: Vec<usize> = (0..METHODS.len()).filter(|i| selected.contains(i)).collect();
    let combo = combination(members.iter().map(|&i| models[i].clone()).collect(), training, settings.season);
    cvs.push(cross_validate(&combo, settings));
    models.push(combo);
    let scale = evaluation::seasonal_scale(training, settings.season);
    let mut holdout = Vec::new();
    let mut metrics = Vec::new();
    for i in 0..models.len() {
        let predicted = forecast(&models[i], training_count, settings.holdout);
        let rows = intervals(&predicted, &cvs[i].sigma, &settings.interval, &vec![1.0; settings.holdout]);
        let accuracy = evaluation::accuracy(actual, &predicted, scale);
        let cover80 = actual.iter().zip(&rows).filter(|(a, row)| row.lo80 <= **a && **a <= row.hi80).count();
        let cover95 = actual.iter().zip(&rows).filter(|(a, row)| row.lo95 <= **a && **a <= row.hi95).count();
        let winkler80 = total(actual.iter().zip(&rows).map(|(&a, row)| evaluation::winkler(a, row.lo80, row.hi80, 10.0))) / actual.len() as f64;
        let winkler95 = total(actual.iter().zip(&rows).map(|(&a, row)| evaluation::winkler(a, row.lo95, row.hi95, 40.0))) / actual.len() as f64;
        metrics.push(Measures { accuracy, cover80, cover95, winkler80, winkler95 });
        holdout.push(rows);
    }
    let ranking = evaluation::rank_models(&metrics.iter().map(|m| m.accuracy.rmse).collect::<Vec<_>>());
    let best = ranking[0];
    let final_names = if best == 11 { members.clone() } else { vec![best] };
    let final_fits: Vec<Model> = final_names.iter().map(|&i| fit_method(METHODS[i], &data.corrected, settings)).collect();
    let final_model = if best == 11 { combination(final_fits.clone(), &data.corrected, settings.season) } else { final_fits[0].clone() };
    let final_cv = cross_validate(&final_model, settings);
    let multipliers: Vec<f64> = data.future_periods.iter().map(|period| {
        record.events.get(period).map_or(1.0, |kind| data.lifts.iter().find(|lift| lift.kind == *kind).unwrap().value)
    }).collect();
    let future = intervals(&forecast(&final_model, count, settings.horizon), &final_cv.sigma, &settings.interval, &multipliers);
    let demands: Vec<f64> = future.iter().map(|row| row.forecast).collect();
    let name = &record.name;
    let components = &data.components;
    for t in 0..count {
        let j = t % settings.season;
        let flag = if let Some(kind) = &data.past[t] { kind.as_str() }
            else if record.raw[t].is_none() { "missing" }
            else if data.outliers[t].is_some() { "outlier" } else { "ok" };
        reports.decomposition.push(format!("{name},{},{},{},{},{},{},{},{},{flag}", record.periods[t],
            real(data.values[t]), real(data.corrected[t]), optional_real(components.trend[t]),
            real(components.additive[j]), optional_real(components.residual_add[t]),
            real(components.multiplicative[j]), optional_real(components.residual_mult[t])));
    }
    reports.models.push(format!("series {name}"));
    reports.models.push(format!("data observations {count} train {training_count} holdout {} missing {} outliers {} events {}",
        settings.holdout, record.raw.iter().filter(|v| v.is_none()).count(),
        data.outliers.iter().filter(|v| v.is_some()).count(), data.past.iter().filter(|v| v.is_some()).count()));
    for lift in &data.lifts {
        reports.models.push(format!("event {} occurrences {} lift {}", lift.kind, lift.times.len(), real(lift.value)));
    }
    for (t, score) in data.outliers.iter().enumerate() {
        if let Some(score) = score {
            reports.models.push(format!("outlier {} value {} expected {} score {}", record.periods[t], real(data.values[t]), real(data.corrected[t]), real(*score)));
        }
    }
    reports.models.push(format!("strength trend {} seasonal {}", real(data.strength_trend), real(data.strength_seasonal)));
    for model in &models[..11] {
        reports.models.extend(model_lines(model));
    }
    reports.models.push(format!("combo members {}", members.iter().map(|&i| METHODS[i]).collect::<Vec<_>>().join(" ")));
    reports.models.push(format!("best {} rmse {}", MODELS[best], real(metrics[best].accuracy.rmse)));
    for model in &final_fits {
        reports.models.extend(model_lines(model).into_iter().map(|line| format!("final {line}")));
    }
    for i in 0..models.len() {
        for (t, row) in holdout[i].iter().enumerate() {
            reports.forecasts.push(format!("{name},holdout,{},{},{},{}", MODELS[i], record.periods[training_count + t], record.raw[training_count + t].unwrap(), row.csv()));
        }
        let m = &metrics[i];
        let a = &m.accuracy;
        let fva = 100.0 * (metrics[0].accuracy.mae - a.mae) / metrics[0].accuracy.mae;
        let reals = [a.me, a.mae, a.rmse, a.mape, a.smape, a.mase, fva, cvs[i].rmse].into_iter().map(real).collect::<Vec<_>>().join(",");
        let rank = ranking.iter().position(|&j| i == j).unwrap() + 1;
        reports.accuracy.push(format!("{name},{},{reals},{},{},{},{},{rank}", MODELS[i], m.cover80, m.cover95, real(m.winkler80), real(m.winkler95)));
        for k in 0..settings.horizon {
            reports.cv.push(format!("{name},{},{},{},{},{}", MODELS[i], k + 1, cvs[i].counts[k], real(cvs[i].mae[k]), real(cvs[i].sigma[k])));
        }
    }
    for (period, row) in data.future_periods.iter().zip(&future) {
        reports.forecasts.push(format!("{name},future,{},{period},NA,{}", MODELS[best], row.csv()));
    }
    if let Fit::Ar(ar) = &models[10].fit {
        let band = 2.0 / (ar.differenced.len() as f64).sqrt();
        reports.correlogram.push(format!("series {name} difference {} n {} band {}", autoregression::KINDS[ar.kind], ar.differenced.len(), real(band)));
        for (label, sequence) in [("acf", &ar.correlations), ("pacf", &ar.partial)] {
            for (lag, &value) in sequence.iter().enumerate().skip(1) {
                let width = (value.abs() * 20.0 + 0.5).floor() as usize;
                let marker = if value.abs() > band { " *" } else { "" };
                reports.correlogram.push(format!("{label} {lag:2} {:>7} [{}]{marker}", real(value), centered_bar(value, 20, width, Some(band))));
            }
        }
    }
    for model in &models[..11] {
        residual_diagnostics(model, &settings.ljung_box, &mut reports.correlogram);
    }
    let chart_rows: Vec<(&str, &Interval, Option<f64>)> = holdout[best].iter().enumerate()
        .map(|(t, row)| (record.periods[training_count + t].as_str(), row, Some(actual[t])))
        .chain(data.future_periods.iter().zip(&future).map(|(period, row)| (period.as_str(), row, None))).collect();
    let low = chart_rows.iter().map(|(_, row, actual)| actual.map_or(row.lo95, |a| a.min(row.lo95))).fold(f64::INFINITY, f64::min);
    let high = chart_rows.iter().map(|(_, row, actual)| actual.map_or(row.hi95, |a| a.max(row.hi95))).fold(f64::NEG_INFINITY, f64::max);
    reports.chart.push(format!("chart {name} method {}", MODELS[best]));
    reports.chart.push(format!("scale low {} high {}", real(low), real(high)));
    for (period, row, actual) in chart_rows {
        reports.chart.push(format!("{period} |{}|", forecast_chart(row, actual, low, high)));
    }
    let peak = components.multiplicative.iter().map(|v| (v - 1.0).abs()).fold(0.0, f64::max);
    reports.chart.push(format!("profile peak {}", real(peak)));
    for (j, &value) in components.multiplicative.iter().enumerate() {
        let width = ((value - 1.0).abs() / peak * 30.0 + 0.5).floor() as usize;
        reports.chart.push(format!("season {:2} {} [{}]", j + 1, real(value), centered_bar(value - 1.0, 30, width, None)));
    }
    reports.plan.push(format!("series {name} method {}", MODELS[best]));
    inventory_plan(&final_model, &demands, &data.future_periods, &record.inventory, settings, &mut reports.plan);
    yearly_totals(record, &data, &demands, &mut reports.plan);
}

fn main() {
    let (series, settings) = series_io::read_inputs();
    let mut reports = Reports {
        decomposition: vec!["series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag".to_owned()],
        models: Vec::new(),
        forecasts: vec!["series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95".to_owned()],
        accuracy: vec!["series,method,me,mae,rmse,mape,smape,mase,fva,cv_rmse,cover80,cover95,winkler80,winkler95,rank".to_owned()],
        cv: vec!["series,method,step,origins,mae,rmse".to_owned()],
        correlogram: Vec::new(), chart: Vec::new(), plan: Vec::new(),
    };
    for record in &series {
        analyze(record, &settings, &mut reports);
    }
    for (name, lines) in [
        ("decomposition.csv", &reports.decomposition), ("models.txt", &reports.models),
        ("forecasts.csv", &reports.forecasts), ("accuracy.csv", &reports.accuracy),
        ("cv.csv", &reports.cv), ("correlogram.txt", &reports.correlogram),
        ("chart.txt", &reports.chart), ("plan.txt", &reports.plan),
    ] {
        series_io::write_lines(name, lines);
    }
}
