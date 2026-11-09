mod cox;
mod dataset;
mod estimators;
mod group_tests;
mod numerics;
mod plot;

use dataset::{Input, Subject};
use estimators::{at, kaplan_meier, life_table, KmRow, LifeRow};
use group_tests::{weighted, Test};
use numerics::{inverse, p_value, solve, sum};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;

pub const Z: f64 = 1.959963984540054;
const WEIGHTS: [&str; 3] = ["logrank", "gehan_wilcoxon", "tarone_ware"];

fn real(value: f64) -> String { if value.abs() < 0.00005 { "0.0000".into() } else { format!("{value:.4}") } }
fn optional(value: Option<f64>) -> String { value.map_or_else(|| "NA".into(), real) }
fn day(value: Option<i64>) -> String { value.map_or_else(|| "NA".into(), |v| v.to_string()) }
fn reals(values: &[f64]) -> String { values.iter().map(|&v| real(v)).collect::<Vec<_>>().join(" ") }
fn numbers(values: &[usize]) -> String { values.iter().map(usize::to_string).collect::<Vec<_>>().join(" ") }
fn append(lines: &mut Vec<String>, block: Vec<String>) { if !lines.is_empty() { lines.push(String::new()); } lines.extend(block); }

struct Summary {
    events: usize,
    rate: f64,
    rmst: f64,
    rmst_error: f64,
}

fn rmst(rows: &[KmRow], tau: i64) -> (f64, f64) {
    let rows: Vec<_> = rows.iter().filter(|row| row.time <= tau).collect();
    let mut rectangles = Vec::new();
    let mut previous_time = 0;
    let mut survival = 1.0;
    for row in &rows { rectangles.push(survival * (row.time - previous_time) as f64); survival = row.survival; previous_time = row.time; }
    rectangles.push(survival * (tau - previous_time) as f64);
    let mut tails = rectangles.clone();
    for i in (0..tails.len() - 1).rev() { tails[i] = rectangles[i] + tails[i + 1]; }
    let variance = sum(rows.iter().enumerate().map(|(i, row)| tails[i + 1] * tails[i + 1] * (row.events as f64 / (row.risk * (row.risk - row.events)) as f64)));
    (tails[0], variance.sqrt())
}

fn collection_report(name: &str, subjects: &[Subject], rows: &[KmRow], life: &[LifeRow], input: &Input) -> (Vec<String>, Summary) {
    let events = subjects.iter().filter(|s| s.event).count();
    let person_days = subjects.iter().map(|s| s.time).sum::<i64>();
    let rate = (1000 * events) as f64 / person_days as f64;
    let eta = Z / (events as f64).sqrt();
    let followup = kaplan_meier(subjects, true).iter().find(|row| row.survival <= 0.5).map(|row| row.time);
    let life_median = life.iter().enumerate().find(|(_, row)| row.survival <= 0.5).map(|(i, row)| {
        let previous = if i == 0 { 1.0 } else { life[i - 1].survival };
        row.start as f64 + (row.end - row.start) as f64 * (previous - 0.5) / (previous - row.survival)
    });
    let (rmst, rmst_error) = rmst(rows, input.number("TAU"));
    let mut lines = vec![format!("group {} subjects {} events {} censored {} max_time {}", name, subjects.len(), events, subjects.len() - events, subjects.iter().map(|s| s.time).max().unwrap()),
        format!("person_days {} rate {} lower {} upper {}", person_days, real(rate), real((rate.ln() - eta).exp()), real((rate.ln() + eta).exp())),
        format!("followup_median {}", day(followup)), format!("life_table_median {}", optional(life_median))];
    for (percentile, probability) in [(25, 0.75), (50, 0.5), (75, 0.25)] {
        let time = rows.iter().find(|row| row.survival <= probability).map(|row| row.time);
        let lower = rows.iter().find(|row| if row.survival == 0.0 { true } else { row.lower.is_some_and(|value| value <= probability) }).map(|row| row.time);
        let upper = rows.iter().find(|row| if row.survival == 0.0 { true } else { row.upper.is_some_and(|value| value <= probability) }).map(|row| row.time);
        lines.push(format!("percentile {} time {} lower {} upper {}", percentile, day(time), day(lower), day(upper)));
    }
    lines.push(format!("rmst tau {} estimate {} se {} lower {} upper {}", input.number("TAU"), real(rmst), real(rmst_error), real(rmst - Z * rmst_error), real(rmst + Z * rmst_error)));
    for t in input.numbers("REPORT_TIMES") {
        let row = at(rows, t);
        lines.push(format!("at {} at_risk {} events {} survival {} std_err {} lower {} upper {} cum_hazard {} hazard_se {}", t, subjects.iter().filter(|s| s.time >= t).count(), subjects.iter().filter(|s| s.time <= t && s.event).count(), real(row.survival), optional(row.error), optional(row.lower), optional(row.upper), real(row.hazard), real(row.hazard_error)));
    }
    lines.push(["time", "at_risk", "events", "censored", "survival", "std_err", "lower", "upper", "cum_haz", "haz_se"].iter().map(|field| format!("{field:>9}")).collect());
    for row in rows {
        let fields = [row.time.to_string(), row.risk.to_string(), row.events.to_string(), row.censored.to_string(), real(row.survival), optional(row.error), optional(row.lower), optional(row.upper), real(row.hazard), real(row.hazard_error)];
        lines.push(fields.iter().map(|field| format!("{field:>9}")).collect());
    }
    (lines, Summary { events, rate, rmst, rmst_error })
}

fn value(subject: &Subject, variable: &str) -> String { if variable == "sex" { (subject.sex as char).to_string() } else { subject.stage.to_string() } }
fn levels(input: &Input, variable: &str) -> Vec<String> { input.subjects.iter().map(|s| value(s, variable)).collect::<BTreeSet<_>>().into_iter().collect() }

fn baseline(input: &Input, collections: &[Vec<Subject>], names: &[String]) -> Vec<String> {
    let mut lines = vec!["baseline".into()];
    for (name, subjects) in names.iter().zip(collections) {
        let mean = subjects.iter().map(|s| s.age).sum::<i64>() as f64 / subjects.len() as f64;
        let deviation = (sum(subjects.iter().map(|s| { let d = s.age as f64 - mean; d * d })) / (subjects.len() - 1) as f64).sqrt();
        let mut ages: Vec<_> = subjects.iter().map(|s| s.age).collect();
        ages.sort_unstable();
        let median = (ages[(ages.len() - 1) / 2] + ages[ages.len() / 2]) as f64 / 2.0;
        let stage: Vec<_> = (1..=4).map(|stage| subjects.iter().filter(|s| s.stage == stage).count()).collect();
        lines.push(format!("  group {} subjects {} age_mean {} age_sd {} age_median {:.1} male {} stage {}", name, subjects.len(), real(mean), real(deviation), median, subjects.iter().filter(|s| s.sex == b'M').count(), numbers(&stage)));
    }
    let n = input.subjects.len();
    let mut order: Vec<_> = (0..n).collect();
    order.sort_by_key(|&i| (input.subjects[i].age, input.subjects[i].id));
    let mut ranks = vec![0.0; n];
    let mut ties = 0_i64;
    let mut p = 0;
    while p < n {
        let mut q = p + 1;
        while q < n && input.subjects[order[q]].age == input.subjects[order[p]].age { q += 1; }
        let rank = (p + 1 + q) as f64 / 2.0;
        for &i in &order[p..q] { ranks[i] = rank; }
        let size = (q - p) as i64;
        ties += size * size * size - size;
        p = q;
    }
    let mut rank_sums = vec![0.0; input.groups.len()];
    for (i, subject) in input.subjects.iter().enumerate() { rank_sums[subject.group] += ranks[i]; }
    let initial = 12.0 * sum((0..input.groups.len()).map(|g| rank_sums[g] * rank_sums[g] / collections[g].len() as f64)) / (n * (n + 1)) as f64 - (3 * (n + 1)) as f64;
    let statistic = initial / (1.0 - ties as f64 / (n * n * n - n) as f64);
    lines.push(format!("  age kruskal_wallis chisq {} df {} p {}", real(statistic), input.groups.len() - 1, real(p_value(statistic, input.groups.len() - 1))));
    for variable in ["sex", "stage"] {
        let levels = levels(input, variable);
        let mut statistic = 0.0;
        for subjects in collections.iter().take(input.groups.len()) {
            for level in &levels {
                let observed = subjects.iter().filter(|s| value(s, variable) == *level).count();
                let count = input.subjects.iter().filter(|s| value(s, variable) == *level).count();
                let expected = (subjects.len() * count) as f64 / n as f64;
                let difference = observed as f64 - expected;
                statistic += difference * difference / expected;
            }
        }
        let degrees = (input.groups.len() - 1) * (levels.len() - 1);
        lines.push(format!("  {variable} chisq {} df {} p {}", real(statistic), degrees, real(p_value(statistic, degrees))));
    }
    lines
}

fn group_lines(input: &Input, test: &Test) -> Vec<String> {
    test.groups.iter().enumerate().map(|(i, &g)| format!("  group {} events {} observed {} expected {} o_minus_e {} variance {}", input.groups[g], test.events[i], real(test.observed[i]), real(test.expected[i]), real(test.observed[i] - test.expected[i]), real(test.covariance[i][i]))).collect()
}

struct Pairwise {
    test: Test,
    ratio: f64,
    lower: f64,
    upper: f64,
    phi: f64,
    logarithm: f64,
}

fn two_groups(input: &Input, subjects: &[Subject], a: usize, b: usize) -> Pairwise {
    let test = weighted(subjects, &[a, b], "logrank", input.subjects.len());
    let ratio = (test.observed[1] / test.expected[1]) / (test.observed[0] / test.expected[0]);
    let phi = 1.0 / test.expected[0] + 1.0 / test.expected[1];
    let logarithm = ratio.ln();
    Pairwise { ratio, lower: (logarithm - Z * phi.sqrt()).exp(), upper: (logarithm + Z * phi.sqrt()).exp(), phi, logarithm, test }
}

fn difference_line(prefix: &str, difference: f64, error: f64) -> String {
    let zeta = difference / error;
    format!("{} difference {} se {} lower {} upper {} z {} p {}", prefix, real(difference), real(error), real(difference - Z * error), real(difference + Z * error), real(zeta), real(p_value(zeta * zeta, 1)))
}

fn tests(input: &Input, collections: &[Vec<Subject>], names: &[String], tables: &[Vec<KmRow>], summaries: &[Summary]) -> Vec<String> {
    let groups: Vec<_> = (0..input.groups.len()).collect();
    let mut lines = baseline(input, collections, names);
    let overall: Vec<_> = WEIGHTS.iter().map(|weight| weighted(&input.subjects, &groups, weight, input.subjects.len())).collect();
    let mut block = Vec::new();
    for (weight, test) in WEIGHTS.iter().zip(&overall) {
        block.push(format!("test {weight} chisq {} df {} p {}", real(test.statistic), groups.len() - 1, real(test.p)));
        block.extend(group_lines(input, test));
    }
    let logrank = &overall[0];
    let trend_u = sum((0..groups.len()).map(|g| (g + 1) as f64 * (logrank.observed[g] - logrank.expected[g])));
    let trend_v = sum((0..groups.len()).map(|g| sum((0..groups.len()).map(|h| ((g + 1) * (h + 1)) as f64 * logrank.covariance[g][h]))));
    let trend = trend_u * trend_u / trend_v;
    block.push(format!("test logrank_trend chisq {} df 1 p {}", real(trend), real(p_value(trend, 1))));
    append(&mut lines, block);
    let variable = &input.params["STRATA"][0];
    let levels = levels(input, variable);
    let mut block = Vec::new();
    for weight in WEIGHTS {
        let mut total = Test::empty(&groups);
        let mut stratum_lines = Vec::new();
        for level in &levels {
            let subjects: Vec<_> = input.subjects.iter().filter(|s| value(s, variable) == *level).cloned().collect();
            let test = weighted(&subjects, &groups, weight, input.subjects.len());
            total.add(&test);
            stratum_lines.push(format!("  stratum {} subjects {} events {} chisq {} p {}", level, subjects.len(), subjects.iter().filter(|s| s.event).count(), real(test.statistic), real(test.p)));
        }
        total.finish();
        block.push(format!("stratified {weight} by {variable} chisq {} df {} p {}", real(total.statistic), groups.len() - 1, real(total.p)));
        block.extend(stratum_lines);
        block.extend(group_lines(input, &total));
    }
    append(&mut lines, block);
    let landmark = input.number("LANDMARK");
    let subjects: Vec<_> = input.subjects.iter().filter(|s| s.time > landmark).cloned().collect();
    let test = weighted(&subjects, &groups, "logrank", input.subjects.len());
    let mut block = vec![format!("landmark {} subjects {} chisq {} df {} p {}", landmark, subjects.len(), real(test.statistic), groups.len() - 1, real(test.p))];
    block.extend(group_lines(input, &test));
    append(&mut lines, block);
    let mut pairs = Vec::new();
    for a in 0..groups.len() {
        for b in a + 1..groups.len() {
            let subjects: Vec<_> = input.subjects.iter().filter(|s| s.group == a || s.group == b).cloned().collect();
            pairs.push((a, b, two_groups(input, &subjects, a, b)));
        }
    }
    let mut order: Vec<_> = (0..pairs.len()).collect();
    order.sort_by(|&a, &b| pairs[a].2.test.p.total_cmp(&pairs[b].2.test.p).then(a.cmp(&b)));
    let mut adjusted = vec![0.0_f64; pairs.len()];
    let mut preceding = 0.0_f64;
    for (r, &i) in order.iter().enumerate() { preceding = preceding.max(((pairs.len() - r) as f64 * pairs[i].2.test.p).min(1.0)); adjusted[i] = preceding; }
    let mut block = vec!["pairwise logrank adjust holm".into()];
    for (i, (a, b, pair)) in pairs.iter().enumerate() {
        block.push(format!("  {} {} chisq {} p {} p_holm {} hr {} lower {} upper {}", input.groups[*a], input.groups[*b], real(pair.test.statistic), real(pair.test.p), real(adjusted[i]), real(pair.ratio), real(pair.lower), real(pair.upper)));
    }
    append(&mut lines, block);
    let mut block = vec![format!("subgroups reference {}", input.groups[0])];
    for variable in &input.params["SUBGROUPS"] {
        let levels = self::levels(input, variable);
        for b in 1..groups.len() {
            let mut results = Vec::new();
            for level in &levels {
                let subjects: Vec<_> = input.subjects.iter().filter(|s| (s.group == 0 || s.group == b) && value(s, variable) == *level).cloned().collect();
                let pair = two_groups(input, &subjects, 0, b);
                block.push(format!("  {} {} {} subjects {} events {} hr {} lower {} upper {} p {}", variable, level, input.groups[b], subjects.len(), subjects.iter().filter(|s| s.event).count(), real(pair.ratio), real(pair.lower), real(pair.upper), real(pair.test.p)));
                results.push(pair);
            }
            let mean = sum(results.iter().map(|pair| 1.0 / pair.phi * pair.logarithm)) / sum(results.iter().map(|pair| 1.0 / pair.phi));
            let heterogeneity = sum(results.iter().map(|pair| 1.0 / pair.phi * (pair.logarithm - mean) * (pair.logarithm - mean)));
            block.push(format!("  {} {} heterogeneity chisq {} df {} p {}", variable, input.groups[b], real(heterogeneity), levels.len() - 1, real(p_value(heterogeneity, levels.len() - 1))));
        }
    }
    append(&mut lines, block);
    let mut block = vec![format!("rmst_difference tau {} reference {}", input.number("TAU"), input.groups[0])];
    for g in 1..groups.len() {
        let error = (summaries[g].rmst_error * summaries[g].rmst_error + summaries[0].rmst_error * summaries[0].rmst_error).sqrt();
        block.push(difference_line(&format!("  {}", input.groups[g]), summaries[g].rmst - summaries[0].rmst, error));
    }
    append(&mut lines, block);
    let mut block = vec![format!("rate_ratio reference {}", input.groups[0])];
    for g in 1..groups.len() {
        let ratio = summaries[g].rate / summaries[0].rate;
        let error = (1.0 / summaries[g].events as f64 + 1.0 / summaries[0].events as f64).sqrt();
        let logarithm = ratio.ln();
        let statistic = logarithm / error;
        block.push(format!("  {} ratio {} lower {} upper {} z {} p {}", input.groups[g], real(ratio), real((logarithm - Z * error).exp()), real((logarithm + Z * error).exp()), real(statistic), real(p_value(statistic * statistic, 1))));
    }
    append(&mut lines, block);
    let mut block = vec![format!("survival_difference reference {}", input.groups[0])];
    for t in input.numbers("REPORT_TIMES") {
        for g in 1..groups.len() {
            let control = at(&tables[0], t);
            let treatment = at(&tables[g], t);
            let error = (treatment.error.unwrap() * treatment.error.unwrap() + control.error.unwrap() * control.error.unwrap()).sqrt();
            block.push(difference_line(&format!("  at {} {}", t, input.groups[g]), treatment.survival - control.survival, error));
        }
    }
    append(&mut lines, block);
    lines
}

fn covariate(input: &Input, subject: &Subject, name: &str) -> i64 {
    match name { "age" => subject.age, "male" => i64::from(subject.sex == b'M'), "stage" => subject.stage, _ => i64::from(input.groups[subject.group] == name) }
}

fn coefficient_line(prefix: &str, coefficient: f64, error: f64) -> String {
    let statistic = coefficient / error;
    format!("{} coef {} se {} z {} p {} hr {} lower {} upper {}", prefix, real(coefficient), real(error), real(statistic), real(p_value(statistic * statistic, 1)), real(coefficient.exp()), real((coefficient - Z * error).exp()), real((coefficient + Z * error).exp()))
}

fn cox_report(input: &Input) -> Vec<String> {
    let names = &input.params["COX"];
    let x: Vec<Vec<_>> = input.subjects.iter().map(|subject| names.iter().map(|name| covariate(input, subject, name)).collect()).collect();
    let fit = cox::fit(&input.subjects, &x);
    let final_evaluation = &fit.final_evaluation;
    let p = names.len();
    let covariance = inverse(&final_evaluation.information);
    let mut lines = vec![format!("cox covariates {} subjects {} events {} event_times {}", names.join(" "), input.subjects.len(), input.subjects.iter().filter(|s| s.event).count(), final_evaluation.event_risks.len())];
    for (i, (likelihood, beta)) in fit.history.iter().enumerate() { lines.push(format!("iter {} loglik {} beta {}", i + 1, real(*likelihood), reals(beta))); }
    lines.push(format!("final loglik {} null_loglik {}", real(final_evaluation.likelihood), real(fit.null.likelihood)));
    for c in 0..p { lines.push(coefficient_line(&format!("term {}", names[c]), fit.beta[c], covariance[c][c].sqrt())); }
    for a in 0..p {
        if !input.groups.contains(&names[a]) { continue; }
        for b in a + 1..p {
            if input.groups.contains(&names[b]) {
                let coefficient = fit.beta[b] - fit.beta[a];
                let error = (covariance[b][b] + covariance[a][a] - 2.0 * covariance[a][b]).sqrt();
                lines.push(coefficient_line(&format!("contrast {} vs {}", names[b], names[a]), coefficient, error));
            }
        }
    }
    let likelihood_ratio = 2.0 * (final_evaluation.likelihood - fit.null.likelihood);
    let wald = sum((0..p).map(|c| fit.beta[c] * sum((0..p).map(|d| final_evaluation.information[c][d] * fit.beta[d]))));
    let solution = solve(&fit.null.information, &fit.null.score);
    let score = sum((0..p).map(|c| fit.null.score[c] * solution[c]));
    for (name, statistic) in [("likelihood_ratio", likelihood_ratio), ("wald", wald), ("score", score)] { lines.push(format!("{name} chisq {} df {} p {}", real(statistic), p, real(p_value(statistic, p)))); }
    for c in 0..p {
        let likelihood = if p == 1 { fit.null.likelihood } else {
            let reduced: Vec<_> = x.iter().map(|row| row.iter().enumerate().filter(|(j, _)| *j != c).map(|(_, &value)| value).collect()).collect();
            cox::fit(&input.subjects, &reduced).final_evaluation.likelihood
        };
        let statistic = 2.0 * (final_evaluation.likelihood - likelihood);
        lines.push(format!("drop {} loglik {} chisq {} df 1 p {}", names[c], real(likelihood), real(statistic), real(p_value(statistic, 1))));
    }
    let (mut comparable, mut concordant, mut tied) = (0, 0, 0);
    for (i, a) in input.subjects.iter().enumerate().filter(|(_, subject)| subject.event) {
        for (j, b) in input.subjects.iter().enumerate() {
            if i == j || !(a.time < b.time || (a.time == b.time && !b.event)) { continue; }
            comparable += 1;
            if x[i] == x[j] { tied += 1; }
            else if final_evaluation.theta[i] > final_evaluation.theta[j] { concordant += 1; }
        }
    }
    lines.push(format!("concordance {} comparable {} concordant {} tied {}", real((2 * concordant + tied) as f64 / (2 * comparable) as f64), comparable, concordant, tied));
    let event_map: BTreeMap<_, _> = final_evaluation.event_risks.iter().map(|risk| (risk.time, risk)).collect();
    let mut events: Vec<_> = input.subjects.iter().enumerate().filter(|(_, subject)| subject.event).map(|(i, _)| i).collect();
    events.sort_by_key(|&i| (input.subjects[i].time, input.subjects[i].id));
    let time_mean = events.iter().map(|&i| input.subjects[i].time).sum::<i64>() as f64 / events.len() as f64;
    for c in 0..p {
        let residuals: Vec<_> = events.iter().map(|&i| {
            let risk = event_map[&input.subjects[i].time];
            x[i][c] as f64 - risk.s1[c] / risk.s0
        }).collect();
        let mean = sum(residuals.iter().copied()) / events.len() as f64;
        let sxy = sum(events.iter().zip(&residuals).map(|(&i, &residual)| (residual - mean) * (input.subjects[i].time as f64 - time_mean)));
        let sxx = sum(residuals.iter().map(|&residual| (residual - mean) * (residual - mean)));
        let syy = sum(events.iter().map(|&i| { let difference = input.subjects[i].time as f64 - time_mean; difference * difference }));
        let rho = sxy / (sxx * syy).sqrt();
        let statistic = 0.5 * ((1.0 + rho) / (1.0 - rho)).ln() * ((events.len() - 3) as f64).sqrt();
        lines.push(format!("ph_check {} rho {} z {} p {}", names[c], real(rho), real(statistic), real(p_value(statistic * statistic, 1))));
    }
    let mut hazards = Vec::new();
    let mut cumulative = 0.0;
    for (time, risk) in &event_map { cumulative += risk.events as f64 / risk.s0; hazards.push((*time, cumulative)); }
    let baseline = |time| hazards.iter().rev().find(|&&(u, _)| u <= time).map_or(0.0, |&(_, hazard)| hazard);
    let mut residuals: Vec<_> = input.subjects.iter().enumerate().map(|(i, subject)| {
        let martingale = i64::from(subject.event) as f64 - baseline(subject.time) * final_evaluation.theta[i].exp();
        let magnitude = if subject.event { (-2.0 * (martingale + (1.0 - martingale).ln())).sqrt() } else { (-2.0 * martingale).sqrt() };
        (i, martingale, if martingale > 0.0 { magnitude } else { -magnitude })
    }).collect();
    residuals.sort_by(|a, b| b.2.abs().total_cmp(&a.2.abs()).then(input.subjects[a.0].id.cmp(&input.subjects[b.0].id)));
    let count = input.number("RESIDUALS") as usize;
    lines.push(format!("residuals top {count}"));
    for &(i, martingale, deviance) in residuals.iter().take(count) {
        let subject = &input.subjects[i];
        lines.push(format!("  id {} group {} time {} event {} martingale {} deviance {}", subject.id, input.groups[subject.group], subject.time, usize::from(subject.event), real(martingale), real(deviance)));
    }
    let means: Vec<_> = (0..p).map(|c| x.iter().map(|row| row[c]).sum::<i64>() as f64 / input.subjects.len() as f64).collect();
    let continuous: Vec<_> = (0..p).filter(|&c| ["age", "male", "stage"].contains(&names[c].as_str())).collect();
    let description = if continuous.is_empty() { "none".into() } else { continuous.iter().map(|&c| format!("{} {}", names[c], real(means[c]))).collect::<Vec<_>>().join(" ") };
    lines.push(format!("adjusted_survival mean {description}"));
    let risks: Vec<_> = input.groups.iter().map(|group| {
        sum((0..p).map(|c| fit.beta[c] * if continuous.contains(&c) { means[c] } else { if names[c] == *group { 1.0 } else { 0.0 } })).exp()
    }).collect();
    for time in input.numbers("REPORT_TIMES") {
        lines.push(format!("  at {} {}", time, input.groups.iter().zip(&risks).map(|(group, &risk)| format!("{} {}", group, real((-baseline(time) * risk).exp()))).collect::<Vec<_>>().join(" ")));
    }
    lines.push(format!("  median {}", input.groups.iter().zip(risks).map(|(group, risk)| format!("{} {}", group, day(hazards.iter().find(|&&(_, hazard)| (-hazard * risk).exp() <= 0.5).map(|&(time, _)| time)))).collect::<Vec<_>>().join(" ")));
    lines
}

fn write(name: &str, lines: &[String]) { fs::write(format!("output/{name}"), format!("{}\n", lines.join("\n"))).unwrap(); }

fn main() {
    let input = dataset::read();
    let mut collections: Vec<Vec<_>> = (0..input.groups.len()).map(|group| input.subjects.iter().filter(|s| s.group == group).cloned().collect()).collect();
    collections.push(input.subjects.clone());
    let mut names = input.groups.clone();
    names.push("all".into());
    let tables: Vec<_> = collections.iter().map(|subjects| kaplan_meier(subjects, false)).collect();
    let life_params = input.numbers("LIFE_TABLE");
    let life: Vec<_> = collections.iter().map(|subjects| life_table(subjects, life_params[0], life_params[1])).collect();
    let mut km_lines = Vec::new();
    let mut summaries = Vec::new();
    let mut life_lines = vec!["group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard".into()];
    for i in 0..collections.len() {
        let (block, summary) = collection_report(&names[i], &collections[i], &tables[i], &life[i], &input);
        append(&mut km_lines, block);
        summaries.push(summary);
        for row in &life[i] { life_lines.push(format!("{},{}-{},{},{},{},{:.1},{},{},{},{}", names[i], row.start, row.end, row.risk, row.events, row.withdrawn, row.exposed, real(row.q), real(row.survival), real(row.error), real(row.hazard))); }
    }
    let plot_params = input.numbers("PLOT");
    let mut plot = plot::render(&input.groups, &collections, &tables, plot_params[0] as usize, plot_params[1] as usize, plot_params[2]);
    let times: Vec<_> = (0..=plot_params[3]).map(|i| i * (plot_params[2] / plot_params[3])).collect();
    plot.push(format!("at_risk {}", times.iter().map(i64::to_string).collect::<Vec<_>>().join(" ")));
    for g in 0..input.groups.len() { plot.push(format!("{} {}", input.groups[g], times.iter().map(|&time| collections[g].iter().filter(|s| s.time >= time).count().to_string()).collect::<Vec<_>>().join(" "))); }
    fs::create_dir_all("output").unwrap();
    write("km_tables.txt", &km_lines);
    write("life_table.csv", &life_lines);
    write("tests.txt", &tests(&input, &collections, &names, &tables, &summaries));
    write("cox.txt", &cox_report(&input));
    write("km_plot.txt", &plot);
}
