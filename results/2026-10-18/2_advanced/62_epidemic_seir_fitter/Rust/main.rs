mod data_io;
mod models;
mod integrator;
mod fitting;
mod report;

use data_io::Data;
use models::{Kind, Model};
use report::real;

fn multipliers(lines: &[(usize, f64)], days: usize) -> Vec<f64> {
    (1..=days).map(|day| lines.iter().rev().find(|&&(d, _)| d <= day).unwrap().1).collect()
}

fn simulate(data: &Data, kind: Kind, beta: f64, gamma: f64, sigma: f64, matrix: &[Vec<f64>], multipliers: &[f64], initial: Option<&[f64]>) -> Vec<Vec<f64>> {
    let model = Model::new(kind, beta, gamma, sigma, data, matrix);
    let start = initial.map_or_else(|| model.initial(), <[f64]>::to_vec);
    integrator::simulate(&model, &start, multipliers)
}

fn error(series: &[f64], scale: f64, observed: &[i64]) -> f64 {
    series.iter().zip(observed).map(|(&x, &y)| { let e = scale*x-y as f64; e*e }).sum()
}
fn rmse(value: f64, count: usize) -> f64 { (value/count as f64).sqrt() }
fn largest(values: &[f64]) -> usize {
    let mut best = 0;
    for i in 1..values.len() { if values[i] > values[best] { best = i; } }
    best
}
fn incidence(states: &[Vec<f64>], kind: Kind) -> Vec<f64> {
    states.iter().map(|y| match kind {
        Kind::Seird => y[5], Kind::Sir => y[3], Kind::Generation => y[2],
        Kind::Age => y.chunks(6).map(|g| g[5]).sum(),
    }).collect()
}
fn sse(data: &Data, beta: f64, gamma: f64, rho: f64, sigma: f64, multipliers: &[f64]) -> f64 {
    let states = simulate(data, Kind::Seird, beta, gamma, sigma, &[], multipliers, None);
    error(&incidence(&states, Kind::Seird), rho, &data.cases[..multipliers.len()])
}
fn final_size(r: f64) -> f64 {
    if r <= 1.0 { return 0.0; }
    let (mut lo, mut hi) = (1.0-1.0/r, 1.0);
    for _ in 0..20 {
        let mid = (lo+hi)/2.0;
        let g = 1.0-mid-(-r*mid).exp();
        if g > 0.0 { lo = mid; } else { hi = mid; }
    }
    (lo+hi)/2.0
}
fn power(matrix: &[Vec<f64>]) -> (f64, Vec<f64>) {
    let n = matrix.len();
    let mut v = vec![1.0/n as f64; n];
    let mut nu = 0.0;
    for _ in 0..200 {
        let u: Vec<_> = matrix.iter().map(|row| row.iter().zip(&v).map(|(m, v)| m*v).sum::<f64>()).collect();
        nu = u.iter().sum();
        v = u.iter().map(|u| u/nu).collect();
    }
    (nu, v)
}
fn ngm(data: &Data, w: &[Vec<f64>], r0: f64, susceptible: Option<&[f64]>, multiplier: f64) -> Vec<Vec<f64>> {
    data.groups.iter().enumerate().map(|(g, group)| data.groups.iter().enumerate().map(|(h, other)| {
        if let Some(state) = susceptible { multiplier*r0*w[g][h]*state[6*g]/other.population as f64 }
        else { r0*w[g][h]*group.population as f64/other.population as f64 }
    }).collect()).collect()
}

struct Fitted<'a> {
    data: &'a Data,
    beta: f64,
    gamma: f64,
    rho: f64,
    sse: f64,
    multipliers: Vec<f64>,
    states: Vec<Vec<f64>>,
    incidence: Vec<f64>,
    reported: Vec<f64>,
    deaths: Vec<f64>,
    residuals: Vec<f64>,
    w: Vec<Vec<f64>>,
    age: Vec<Vec<f64>>,
    total: f64,
    fatality: f64,
    kbar: f64,
}

impl<'a> Fitted<'a> {
    fn new(data: &'a Data, beta: f64, gamma: f64, rho: f64, sse_value: f64, multipliers: Vec<f64>) -> Self {
        let total = data.groups.iter().map(|g| g.population).sum::<i64>() as f64;
        let fatality = data.groups.iter().map(|g| g.population as f64*g.fatality).sum::<f64>()/total;
        let kbar = data.groups.iter().enumerate().map(|(g, group)| group.population as f64*data.contacts[g].iter().sum::<f64>()).sum::<f64>()/total;
        let w: Vec<Vec<_>> = data.contacts.iter().map(|row| row.iter().map(|v| v/kbar).collect()).collect();
        let states = simulate(data, Kind::Seird, beta, gamma, data.params.sigma, &[], &multipliers, None);
        let incidence = incidence(&states, Kind::Seird);
        let reported: Vec<_> = incidence.iter().map(|j| rho*j).collect();
        let deaths = states.iter().enumerate().map(|(d, y)| y[4]-if d == 0 { 0.0 } else { states[d-1][4] }).collect();
        let residuals = data.cases.iter().zip(&reported).map(|(&c, &p)| c as f64-p).collect();
        let age = simulate(data, Kind::Age, beta, gamma, data.params.sigma, &w, &multipliers, None);
        Self { data, beta, gamma, rho, sse: sse_value, multipliers, states, incidence, reported, deaths,
            residuals, w, age, total, fatality, kbar }
    }

    fn fit_analysis(&self, lines: &mut Vec<String>, delta_beta: f64, delta_rho: f64) -> f64 {
        let data = self.data;
        let p = &data.params;
        let days = data.cases.len();
        let observed: i64 = data.cases.iter().sum();
        let deaths_observed: i64 = data.deaths.iter().sum();
        let u: f64 = self.residuals.iter().map(|e| e*e).sum();
        let absolute: Vec<_> = self.residuals.iter().map(|e| e.abs()).collect();
        let worst = largest(&absolute);
        let runs = 1+self.residuals.windows(2).filter(|v| (v[0] > 0.0) != (v[1] > 0.0)).count();
        let dw = self.residuals.windows(2).map(|v| { let e = v[1]-v[0]; e*e }).sum::<f64>()/u;
        lines.push(format!("residuals sum {} mae {} max {} day {} positive {} runs {} durbin_watson {}",
            real(self.residuals.iter().sum(), 1), real(absolute.iter().sum::<f64>()/days as f64, 1), real(self.residuals[worst], 1), worst+1,
            self.residuals.iter().filter(|&&e| e > 0.0).count(), runs, real(dw, 4)));
        lines.push(format!("autocorrelation {}", (1..=7).map(|k| real((0..days-k).map(|d| self.residuals[d]*self.residuals[d+k]).sum::<f64>()/u, 4)).collect::<Vec<_>>().join(" ")));
        let mut outliers = 0;
        for d in 0..days {
            let z = self.residuals[d]/self.reported[d].sqrt();
            if z.abs() > p.outlier {
                outliers += 1;
                lines.push(format!("outlier {} observed {} fitted {} z {}", d+1, data.cases[d], real(self.reported[d], 1), real(z, 4)));
            }
        }
        lines.push(format!("outliers {}", outliers));
        let mut factors = vec![0.0; 7];
        for k in 0..7 {
            let observed: i64 = (k..days).step_by(7).map(|d| data.cases[d]).sum();
            let fitted: f64 = (k..days).step_by(7).map(|d| self.reported[d]).sum();
            factors[k] = observed as f64/fitted;
            lines.push(format!("weekday {} observed {} fitted {} factor {}", k+1, observed, real(fitted, 1), real(factors[k], 4)));
        }
        let adjusted: Vec<_> = (0..days).map(|d| self.reported[d]*factors[d%7]).collect();
        lines.push(format!("weekday_adjusted rmse {}", real(rmse(error(&adjusted, 1.0, &data.cases), days), 4)));
        let infections: f64 = self.incidence.iter().sum();
        lines.push(format!("burden infections {} ascertainment {} deaths_per_infection {}", real(infections, 1), real(observed as f64/infections, 4), real(deaths_observed as f64/infections, 6)));
        let kappa = self.deaths.iter().zip(&data.deaths).map(|(&v, &q)| v*q as f64).sum::<f64>()/self.deaths.iter().map(|v| v*v).sum::<f64>();
        lines.push(format!("deaths observed {} model {} rmse {} scale {} implied_fatality {} cfr {}", deaths_observed,
            real(self.states[days-1][4], 1), real(rmse(error(&self.deaths, 1.0, &data.deaths), days), 4), real(kappa, 4),
            real(self.fatality*kappa, 6), real(deaths_observed as f64/observed as f64, 4)));
        let mut correlations = Vec::new();
        for k in 0..=p.lag {
            let a: i64 = (0..days-k).map(|d| data.cases[d]*data.deaths[d+k]).sum();
            let b: i64 = data.cases[..days-k].iter().map(|c| c*c).sum();
            let y: i64 = data.deaths[k..].iter().map(|q| q*q).sum();
            let correlation = a as f64/(b as f64*y as f64).sqrt();
            correlations.push(correlation);
            let cfr = data.deaths[k..].iter().sum::<i64>() as f64/data.cases[..days-k].iter().sum::<i64>() as f64;
            lines.push(format!("death_lag {} correlation {} cfr {}", k, real(correlation, 4), real(cfr, 4)));
        }
        lines.push(format!("death_best_lag {}", largest(&correlations)));
        let mut previous = 0;
        for (week, first) in (0..days).step_by(7).enumerate() {
            let end = (first+7).min(days);
            let count: i64 = data.cases[first..end].iter().sum();
            let growth = if week == 0 { "-".to_owned() } else { real(count as f64/previous as f64, 4) };
            lines.push(format!("weekly {} days {} {} observed {} fitted {} deaths_observed {} deaths_model {} growth {}", week+1, first+1, end,
                count, real(self.reported[first..end].iter().sum(), 1), data.deaths[first..end].iter().sum::<i64>(), real(self.deaths[first..end].iter().sum(), 1), growth));
            previous = count;
        }
        let fitted = [self.beta, self.gamma, self.rho];
        let mut standard_errors = Vec::new();
        for parameter in 0..3 {
            let mut profile = Vec::new();
            for k in -5..=5 {
                let mut values = fitted;
                values[parameter] = fitted[parameter]*(1.0+k as f64/100.0);
                let value = sse(data, values[0], values[1], values[2], p.sigma, &self.multipliers);
                profile.push(value);
                lines.push(format!("profile {} {} value {} rmse {}", ["beta", "gamma", "rho"][parameter], k, real(values[parameter], 6), real(rmse(value, days), 4)));
            }
            let h = fitted[parameter]/100.0;
            let curvature = (profile[6]-2.0*profile[5]+profile[4])/(h*h);
            let variance = self.sse/(days-3) as f64;
            let se = (2.0*variance/curvature).sqrt();
            standard_errors.push(se);
            lines.push(format!("profile_se {} {}", ["beta", "gamma", "rho"][parameter], real(se, 6)));
        }
        let train_days = days-p.holdout;
        let beta = fitting::golden(|x| sse(data, x, self.gamma, self.rho, p.sigma, &self.multipliers[..train_days]), self.beta-delta_beta, self.beta+delta_beta, p.golden).point;
        let rho = fitting::golden(|x| sse(data, beta, self.gamma, x, p.sigma, &self.multipliers[..train_days]), self.rho-delta_rho, self.rho+delta_rho, p.golden);
        let backtest = simulate(data, Kind::Seird, beta, self.gamma, p.sigma, &[], &self.multipliers, None);
        let forecast: Vec<_> = backtest.iter().map(|y| rho.point*y[5]).collect();
        lines.push(format!("backtest train_days {} beta {} rho {} train_rmse {} test_rmse {} full_fit_test_rmse {}", train_days,
            real(beta, 6), real(rho.point, 6), real(rmse(rho.value, train_days), 4), real(rmse(error(&forecast[train_days..], 1.0, &data.cases[train_days..]), p.holdout), 4),
            real(rmse(error(&self.reported[train_days..], 1.0, &data.cases[train_days..]), p.holdout), 4)));
        for d in train_days..days { lines.push(format!("backtest_day {} observed {} forecast {} error {}", d+1, data.cases[d], real(forecast[d], 1), real(data.cases[d] as f64-forecast[d], 1))); }
        let mut interventions = data.interventions.clone();
        let mut effect_sse = self.sse;
        for k in 1..interventions.len() {
            let given = data.interventions[k].1;
            let result = fitting::golden(|value| {
                let mut changed = interventions.clone(); changed[k].1 = value;
                sse(data, self.beta, self.gamma, self.rho, p.sigma, &multipliers(&changed, days))
            }, given-p.effect, given+p.effect, p.golden);
            interventions[k].1 = result.point;
            effect_sse = result.value;
            lines.push(format!("effect {} day {} given {} estimated {} sse {}", k+1, interventions[k].0, real(given, 4), real(result.point, 6), real(result.value, 1)));
        }
        lines.push(format!("effect_sse before {} after {} rmse {}", real(self.sse, 1), real(effect_sse, 1), real(rmse(effect_sse, days), 4)));
        for parameter in 0..4 {
            for factor in [0.9, 1.1] {
                let mut values = [self.beta, self.gamma, p.sigma, self.rho];
                values[parameter] *= factor;
                let states = simulate(data, Kind::Seird, values[0], values[1], values[2], &[], &self.multipliers, None);
                let series = incidence(&states, Kind::Seird);
                let peak = largest(&series);
                lines.push(format!("sensitivity {} {} r0 {} rmse {} peak_day {} peak {} attack {}", ["beta", "gamma", "sigma", "rho"][parameter], real(factor, 2),
                    real(values[0]/values[1], 4), real(rmse(error(&series, values[3], &data.cases), days), 4), peak+1, real(values[3]*series[peak], 1), real((self.total-states[days-1][0])/self.total, 4)));
            }
        }
        let sir = incidence(&simulate(data, Kind::Sir, self.beta, self.gamma, p.sigma, &[], &self.multipliers, None), Kind::Sir);
        let age = incidence(&self.age, Kind::Age);
        for (name, series) in [("sir", &sir), ("seir", &self.incidence), ("age", &age)] {
            let optimum = data.cases.iter().zip(series).map(|(&c, &x)| c as f64*x).sum::<f64>()/series.iter().map(|x| x*x).sum::<f64>();
            lines.push(format!("model {} rmse {} peak_day {} rho_opt {} rmse_opt {}", name, real(rmse(error(series, self.rho, &data.cases), days), 4),
                largest(series)+1, real(optimum, 6), real(rmse(error(series, optimum, &data.cases), days), 4)));
        }
        let sir_fit = fitting::golden(|beta| {
            let series = incidence(&simulate(data, Kind::Sir, beta, self.gamma, p.sigma, &[], &self.multipliers, None), Kind::Sir);
            error(&series, self.rho, &data.cases)
        }, p.beta.0, p.beta.1, p.golden);
        let sir_series = incidence(&simulate(data, Kind::Sir, sir_fit.point, self.gamma, p.sigma, &[], &self.multipliers, None), Kind::Sir);
        lines.push(format!("model sir_fit beta {} rmse {} peak_day {}", real(sir_fit.point, 6), real(rmse(sir_fit.value, days), 4), largest(&sir_series)+1));
        standard_errors[0]
    }

    fn reproduction(&self, se_beta: f64) -> (Vec<String>, Vec<String>) {
        let data = self.data;
        let p = &data.params;
        let days = data.cases.len();
        let r0 = self.beta/self.gamma;
        let final_states = simulate(data, Kind::Seird, self.beta, self.gamma, p.sigma, &[], &vec![1.0; 730], None);
        let mut lines = vec![format!("r0 {} herd_immunity {}", real(r0, 4), real(1.0-1.0/r0, 4)),
            format!("final_size equation {} simulated {}", real(final_size(r0), 4), real((self.total-final_states[729][0])/self.total, 4))];
        let generation = incidence(&simulate(data, Kind::Generation, 0.0, self.gamma, p.sigma, &[], &vec![1.0; p.generation], None), Kind::Generation);
        let coverage: f64 = generation.iter().sum();
        let weights: Vec<_> = generation.iter().map(|a| a/coverage).collect();
        let mean = weights.iter().enumerate().map(|(i, w)| (i as f64+1.0-0.5)*w).sum();
        lines.push(format!("generation mean {} theory {} coverage {}", real(mean, 4), real(1.0/p.sigma+1.0/self.gamma, 4), real(coverage, 4)));
        for (i, &w) in weights.iter().enumerate() { lines.push(format!("generation_weight {} {}", i+1, real(w, 6))); }
        let rt: Vec<_> = (0..days).map(|d| r0*self.multipliers[d]*if d == 0 { self.total-p.e0-p.i0 } else { self.states[d-1][0] }/self.total).collect();
        let average: Vec<_> = (0..days).map(|d| data.cases[d.saturating_sub(6)..=d].iter().sum::<i64>() as f64/(d+1).min(7) as f64).collect();
        let peak = largest(&self.incidence);
        let infectious: Vec<_> = self.states.iter().map(|y| y[2]).collect();
        let infectious_peak = largest(&infectious);
        lines.push(format!("peak model day {} incidence {} reported {} infectious_day {} infectious {}", peak+1, real(self.incidence[peak], 1),
            real(self.reported[peak], 1), infectious_peak+1, real(infectious[infectious_peak], 1)));
        let observed_peak = data.cases.iter().enumerate().min_by_key(|&(d, &c)| (std::cmp::Reverse(c), d)).unwrap().0;
        let average_peak = largest(&average);
        lines.push(format!("peak observed day {} cases {} average7_day {} average7 {}", observed_peak+1, data.cases[observed_peak], average_peak+1, real(average[average_peak], 2)));
        for (k, &(first, multiplier)) in data.interventions.iter().enumerate() {
            let end = if k+1 < data.interventions.len() { data.interventions[k+1].0-1 } else { days };
            let count = end-first+1;
            let sum_error: f64 = self.residuals[first-1..end].iter().sum();
            let square_error: f64 = self.residuals[first-1..end].iter().map(|e| e*e).sum();
            lines.push(format!("period {} days {} {} multiplier {} rt_start {} rt_end {} observed {} fitted {} rmse {} bias {}", k+1, first, end,
                real(multiplier, 4), real(rt[first-1], 4), real(rt[end-1], 4), data.cases[first-1..end].iter().sum::<i64>(),
                real(self.reported[first-1..end].iter().sum(), 1), real(rmse(square_error, count), 4), real(sum_error/count as f64, 1)));
        }
        for &target in &p.milestones {
            let (mut observed, mut fitted) = (None, None);
            let (mut sum_o, mut sum_f) = (0, 0.0);
            for d in 0..days {
                sum_o += data.cases[d]; sum_f += self.reported[d];
                if observed.is_none() && sum_o >= target { observed = Some(d+1); }
                if fitted.is_none() && sum_f >= target as f64 { fitted = Some(d+1); }
            }
            lines.push(format!("milestone {} observed {} fitted {}", target, observed.map_or_else(|| "never".to_owned(), |d| d.to_string()), fitted.map_or_else(|| "never".to_owned(), |d| d.to_string())));
        }
        let total_reported: f64 = self.reported.iter().sum();
        let counterfactual = |multipliers: &[f64]| {
            incidence(&simulate(data, Kind::Seird, self.beta, self.gamma, p.sigma, &[], multipliers, None), Kind::Seird)
                .iter().map(|j| self.rho*j).collect::<Vec<_>>()
        };
        let none = counterfactual(&vec![data.interventions[0].1; days]);
        let peak = largest(&none);
        let total_none: f64 = none.iter().sum();
        lines.push(format!("counterfactual none reported {} peak_day {} peak {} averted {}", real(total_none, 1), peak+1, real(none[peak], 1), real(total_none-total_reported, 1)));
        for k in 1..data.interventions.len() {
            let mut interventions = data.interventions.clone(); interventions.remove(k);
            let total: f64 = counterfactual(&multipliers(&interventions, days)).iter().sum();
            lines.push(format!("counterfactual without {} reported {} averted {}", k+1, real(total, 1), real(total-total_reported, 1)));
        }
        for k in 1..data.interventions.len() {
            for shift in [-7i64, 7] {
                let mut interventions = data.interventions.clone();
                interventions[k].0 = (interventions[k].0 as i64+shift) as usize;
                let total: f64 = counterfactual(&multipliers(&interventions, days)).iter().sum();
                lines.push(format!("timing {} shift {} reported {} change {}", k+1, shift, real(total, 1), real(total-total_reported, 1)));
            }
        }
        for d in 1..days {
            if (rt[d] < 1.0) != (rt[d-1] < 1.0) { lines.push(format!("rt_cross day {} {}", d+1, if rt[d] < 1.0 { "down" } else { "up" })); }
        }
        let pressure: Vec<f64> = (0..days).map(|d| (1..=p.generation.min(d)).map(|s| weights[s-1]*data.cases[d-s] as f64).sum()).collect();
        for d in 0..days {
            let empirical = if d+1 < p.generation+7 { "-".to_owned() } else {
                real(data.cases[d-6..=d].iter().sum::<i64>() as f64/pressure[d-6..=d].iter().sum::<f64>(), 4)
            };
            lines.push(format!("rt {} model {} empirical {}", d+1, real(rt[d], 4), empirical));
        }
        let next_generation = ngm(data, &self.w, r0, None, 1.0);
        for (g, row) in next_generation.iter().enumerate() { lines.push(format!("ngm {} {}", data.groups[g].name, row.iter().map(|&v| real(v, 4)).collect::<Vec<_>>().join(" "))); }
        let (age_r0, eigenvector) = power(&next_generation);
        lines.push(format!("r0_age {} ratio {} kbar {} eigenvector {}", real(age_r0, 4), real(age_r0/r0, 4), real(self.kbar, 4),
            eigenvector.iter().map(|&v| real(v, 4)).collect::<Vec<_>>().join(" ")));
        let groups = data.groups.len();
        let mut final_fraction = vec![1.0; groups];
        for _ in 0..100 {
            final_fraction = (0..groups).map(|g| 1.0-(-(0..groups).map(|h| r0*self.w[g][h]*final_fraction[h]).sum::<f64>()).exp()).collect();
        }
        let final_age = simulate(data, Kind::Age, self.beta, self.gamma, p.sigma, &self.w, &vec![1.0; 730], None);
        let simulated_fraction: Vec<_> = data.groups.iter().enumerate().map(|(g, group)| (group.population as f64-final_age[729][6*g])/group.population as f64).collect();
        for (g, group) in data.groups.iter().enumerate() { lines.push(format!("final_size_age {} equation {} simulated {}", group.name, real(final_fraction[g], 4), real(simulated_fraction[g], 4))); }
        let overall = |fractions: &[f64]| data.groups.iter().zip(fractions).map(|(g, &z)| g.population as f64*z).sum::<f64>()/self.total;
        lines.push(format!("final_size_age total equation {} simulated {}", real(overall(&final_fraction), 4), real(overall(&simulated_fraction), 4)));
        let age_model = Model::new(Kind::Age, self.beta, self.gamma, p.sigma, data, &self.w);
        let initial_age = age_model.initial();
        for d in (0..days).step_by(7) {
            let susceptible = if d == 0 { &initial_age } else { &self.age[d-1] };
            let (value, _) = power(&ngm(data, &self.w, r0, Some(susceptible), self.multipliers[d]));
            lines.push(format!("age_rt {} {} homogeneous {}", d+1, real(value, 4), real(rt[d], 4)));
        }
        for (week, first) in (0..days).step_by(7).enumerate() {
            let end = (first+7).min(days);
            let totals: Vec<_> = (0..groups).map(|g| real((first..end).map(|d| self.age[d][6*g+5]).sum(), 1)).collect();
            lines.push(format!("age_weekly {} days {} {} {}", week+1, first+1, end, totals.join(" ")));
        }
        let infections: Vec<f64> = (0..groups).map(|g| self.age.iter().map(|y| y[6*g+5]).sum()).collect();
        let all_infections: f64 = infections.iter().sum();
        for (g, group) in data.groups.iter().enumerate() {
            let series: Vec<_> = self.age.iter().map(|y| y[6*g+5]).collect();
            let peak = largest(&series);
            lines.push(format!("age {} attack {} infections {} share {} deaths {} peak_day {} peak {}", group.name,
                real((group.population as f64-self.age[days-1][6*g])/group.population as f64, 4), real(infections[g], 1),
                real(infections[g]/all_infections, 4), real(self.age[days-1][6*g+4], 1), peak+1, real(series[peak], 1)));
        }
        for change in &p.changes {
            let target = data.groups.iter().position(|g| g.name == change.group).unwrap();
            let changed: Vec<Vec<_>> = (0..groups).map(|g| (0..groups).map(|h| self.w[g][h]
                *if g == target { change.factor } else { 1.0 }*if h == target { change.factor } else { 1.0 }).collect()).collect();
            let (value, _) = power(&ngm(data, &changed, r0, None, 1.0));
            let states = simulate(data, Kind::Age, self.beta, self.gamma, p.sigma, &changed, &self.multipliers, None);
            let infections: f64 = states.iter().map(|y| (0..groups).map(|g| y[6*g+5]).sum::<f64>()).sum();
            let deaths: f64 = (0..groups).map(|g| states[days-1][6*g+4]).sum();
            let attack = data.groups.iter().enumerate().map(|(g, group)| group.population as f64-states[days-1][6*g]).sum::<f64>()/self.total;
            lines.push(format!("contact_change {} group {} factor {} r0_age {} infections {} deaths {} attack {}", change.name, change.group,
                real(change.factor, 4), real(value, 4), real(infections, 1), real(deaths, 1), real(attack, 4)));
        }
        let mut csv = vec!["scenario,day,incidence,reported".to_owned()];
        let mut first_total = 0.0;
        for (i, (name, multiplier)) in p.scenarios.iter().enumerate() {
            let states = simulate(data, Kind::Seird, self.beta, self.gamma, p.sigma, &[], &vec![*multiplier; p.horizon], Some(&self.states[days-1]));
            let reported: Vec<_> = states.iter().map(|y| self.rho*y[5]).collect();
            let total: f64 = reported.iter().sum();
            if i == 0 { first_total = total; }
            let peak = largest(&reported);
            let below = reported.iter().position(|&v| v < p.threshold).map_or_else(|| "never".to_owned(), |d| (days+d+1).to_string());
            lines.push(format!("scenario {} multiplier {} rt {} reported {} peak_day {} peak {} attack {} final_size {} averted {} below {} days_above {}",
                name, real(*multiplier, 4), real(r0*multiplier*self.states[days-1][0]/self.total, 4), real(total, 1), days+peak+1,
                real(reported[peak], 1), real((self.total-states[p.horizon-1][0])/self.total, 4), real(final_size(r0*multiplier), 4),
                real(first_total-total, 1), below, reported.iter().filter(|&&v| v >= p.threshold).count()));
            let mut multipliers = self.multipliers.clone(); multipliers.extend(vec![*multiplier; p.horizon]);
            let mut bands = Vec::new();
            for beta in [self.beta-2.0*se_beta, self.beta+2.0*se_beta] {
                let states = simulate(data, Kind::Seird, beta, self.gamma, p.sigma, &[], &multipliers, None);
                bands.push(states[days..].iter().map(|y| self.rho*y[5]).sum::<f64>());
            }
            lines.push(format!("scenario_band {} beta_low {} reported_low {} beta_high {} reported_high {}", name,
                real(self.beta-2.0*se_beta, 6), real(bands[0], 1), real(self.beta+2.0*se_beta, 6), real(bands[1], 1)));
            let age = simulate(data, Kind::Age, self.beta, self.gamma, p.sigma, &self.w, &vec![*multiplier; p.horizon], Some(&self.age[days-1]));
            let final_age = &age[p.horizon-1];
            let fractions: Vec<_> = data.groups.iter().enumerate().map(|(g, group)| real((group.population as f64-final_age[6*g])/group.population as f64, 4)).collect();
            let deaths: f64 = (0..groups).map(|g| final_age[6*g+4]).sum();
            lines.push(format!("scenario_age {} attack {} deaths {}", name, fractions.join(" "), real(deaths, 1)));
            for (d, y) in states.iter().enumerate() { csv.push(format!("{},{},{},{}", name, days+d+1, real(y[5], 1), real(reported[d], 1))); }
        }
        (lines, csv)
    }

    fn trajectories(&self) -> Vec<String> {
        let mut lines = vec!["day,S,E,I,R,D,incidence,reported,observed,average7,cumulative_observed,cumulative_reported".to_owned()];
        let (mut observed, mut reported) = (0, 0.0);
        for (d, state) in self.states.iter().enumerate() {
            observed += self.data.cases[d]; reported += self.reported[d];
            let average = self.data.cases[d.saturating_sub(6)..=d].iter().sum::<i64>() as f64/(d+1).min(7) as f64;
            lines.push(format!("{},{},{},{},{},{},{}", d+1, state[..6].iter().map(|&v| real(v, 1)).collect::<Vec<_>>().join(","),
                real(self.reported[d], 1), self.data.cases[d], real(average, 2), observed, real(reported, 1)));
        }
        lines
    }
}

fn golden_lines(lines: &mut Vec<String>, search: &fitting::Golden, round: usize, name: &str, days: usize) {
    for (i, &[a, b, c, d, fc, fd]) in search.records.iter().enumerate() {
        lines.push(format!("golden {} {} {} a {} b {} c {} d {} rmse {} {}", round, name, i,
            real(a, 6), real(b, 6), real(c, 6), real(d, 6), real(rmse(fc, days), 4), real(rmse(fd, days), 4)));
    }
    lines.push(format!("golden_result {} {} {} sse {}", round, name, real(search.point, 6), real(search.value, 1)));
}

fn main() {
    let data = data_io::read();
    let p = &data.params;
    let days = data.cases.len();
    let m = multipliers(&data.interventions, days);
    let total: i64 = data.groups.iter().map(|g| g.population).sum();
    let fatality = data.groups.iter().map(|g| g.population as f64*g.fatality).sum::<f64>()/total as f64;
    let delta_beta = (p.beta.1-p.beta.0)/(p.beta.2-1) as f64;
    let delta_rho = (p.rho.1-p.rho.0)/(p.rho.2-1) as f64;
    let betas: Vec<_> = (0..p.beta.2).map(|i| p.beta.0+(p.beta.1-p.beta.0)*i as f64/(p.beta.2-1) as f64).collect();
    let rhos: Vec<_> = (0..p.rho.2).map(|j| p.rho.0+(p.rho.1-p.rho.0)*j as f64/(p.rho.2-1) as f64).collect();
    let mut lines = vec![format!("data days {} cases {} deaths {} population {} fatality {}", days, data.cases.iter().sum::<i64>(), data.deaths.iter().sum::<i64>(), total, real(fatality, 6)),
        format!("grid gamma {} rho {}", real(p.gamma, 4), rhos.iter().map(|&v| real(v, 4)).collect::<Vec<_>>().join(" "))];
    let mut best = (f64::INFINITY, 0.0, 0.0);
    for &beta in &betas {
        let states = simulate(&data, Kind::Seird, beta, p.gamma, p.sigma, &[], &m, None);
        let incidence = incidence(&states, Kind::Seird);
        let mut errors = Vec::new();
        for &rho in &rhos {
            let value = error(&incidence, rho, &data.cases);
            errors.push(real(rmse(value, days), 2));
            if value < best.0 { best = (value, beta, rho); }
        }
        lines.push(format!("grid beta {} rmse {}", real(beta, 4), errors.join(" ")));
    }
    let (grid_sse, grid_beta, grid_rho) = best;
    lines.push(format!("grid_best beta {} rho {} sse {} rmse {}", real(grid_beta, 4), real(grid_rho, 4), real(grid_sse, 1), real(rmse(grid_sse, days), 4)));
    let (mut beta, mut rho) = (grid_beta, grid_rho);
    let mut golden_sse = 0.0;
    for round in 1..=p.rounds {
        let search = fitting::golden(|x| sse(&data, x, p.gamma, rho, p.sigma, &m), beta-delta_beta, beta+delta_beta, p.golden);
        golden_lines(&mut lines, &search, round, "beta", days); beta = search.point;
        let search = fitting::golden(|x| sse(&data, beta, p.gamma, x, p.sigma, &m), rho-delta_rho, rho+delta_rho, p.golden);
        golden_lines(&mut lines, &search, round, "rho", days); rho = search.point; golden_sse = search.value;
    }
    let golden_beta = beta;
    let simplex = fitting::nelder_mead(|point| sse(&data, point[0], point[1], rho, p.sigma, &m), [beta, p.gamma], p.simplex, p.nm, p.iterations);
    for vertex in &simplex.initial {
        lines.push(format!("simplex {} beta {} gamma {} rmse {}", vertex.number, real(vertex.point[0], 6), real(vertex.point[1], 6), real(rmse(vertex.value, days), 4)));
    }
    for (i, (operation, vertex)) in simplex.records.iter().enumerate() {
        lines.push(format!("nelder_mead {} {} beta {} gamma {} rmse {}", i+1, operation, real(vertex.point[0], 6), real(vertex.point[1], 6), real(rmse(vertex.value, days), 4)));
    }
    for (rank, vertex) in simplex.final_vertices.iter().enumerate() {
        lines.push(format!("final_simplex {} beta {} gamma {} rmse {}", rank+1, real(vertex.point[0], 6), real(vertex.point[1], 6), real(rmse(vertex.value, days), 4)));
    }
    let fitted = &simplex.final_vertices[0];
    let (beta, gamma) = (fitted.point[0], fitted.point[1]);
    let r0 = beta/gamma;
    let mean = data.cases.iter().sum::<i64>() as f64/days as f64;
    let sst = data.cases.iter().map(|&c| { let e = c as f64-mean; e*e }).sum::<f64>();
    lines.push(format!("fitted beta {} gamma {} rho {} sigma {} r0 {}", real(beta, 6), real(gamma, 6), real(rho, 6), real(p.sigma, 6), real(r0, 4)));
    lines.push(format!("sse grid {} golden {} nelder_mead {} rmse {} r2 {}", real(grid_sse, 1), real(golden_sse, 1), real(fitted.value, 1), real(rmse(fitted.value, days), 4), real(1.0-fitted.value/sst, 4)));
    for (name, beta, gamma, rho, value) in [("grid", grid_beta, p.gamma, grid_rho, grid_sse), ("golden", golden_beta, p.gamma, rho, golden_sse), ("nelder_mead", beta, gamma, rho, fitted.value)] {
        lines.push(format!("stage {} beta {} gamma {} rho {} r0 {} rmse {}", name, real(beta, 6), real(gamma, 6), real(rho, 6), real(beta/gamma, 4), real(rmse(value, days), 4)));
    }
    let result = Fitted::new(&data, beta, gamma, rho, fitted.value, m);
    let se_beta = result.fit_analysis(&mut lines, delta_beta, delta_rho);
    let (reproduction, scenarios) = result.reproduction(se_beta);
    for (file, output) in [("fit.txt", lines), ("trajectories.csv", result.trajectories()), ("scenarios.csv", scenarios),
        ("reproduction.txt", reproduction), ("curve_plot.txt", report::plot(&data.cases, &result.reported))] { data_io::write(file, &output); }
}
