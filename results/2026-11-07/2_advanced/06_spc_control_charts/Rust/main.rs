mod dataset;
mod variable_charts;
mod attribute_charts;
mod run_rules;
mod capability;
mod plot;

use std::collections::BTreeSet;
use std::fs;
use dataset::{Lot, Settings, CONSTANTS};
use variable_charts::{Limits, Subgroup, moving_ranges, real_sum, subgroup_statistics, variable_limits};
use attribute_charts::{LotPoint, center_line, lot_point};
use run_rules::{Signal, Zones, check_rules, rule_text};
use capability::{Capability, METRICS};

const CHARTS: [&str; 9] = ["XBAR_R","R","XBAR_S","S","I","MR","CUSUM","EWMA","MA"];
const FAMILIES: [&str; 3] = ["XBAR_R","XBAR_S","I_MR"];
const LABELS: [[&str; 2]; 3] = [["XBAR","R"],["XBAR","S"],["I","MR"]];
const FAMILY_CHARTS: [[usize; 2]; 3] = [[0,1],[2,3],[4,5]];
const EVENT_TYPES: [&str; 5] = ["SHIFT_UP","SHIFT_DOWN","SPREAD_UP","SPREAD_DOWN","PATTERN"];

fn real(value: f64) -> String { let text = format!("{value:.4}"); if text == "-0.0000" { "0.0000".into() } else { text } }
fn number_list(numbers: &[usize]) -> String { if numbers.is_empty() { "none".into() } else { numbers.iter().map(usize::to_string).collect::<Vec<_>>().join(" ") } }
fn status(converged: bool) -> &'static str { if converged { "converged" } else { "stopped" } }
fn limits_text(label: &str, limits: Limits) -> String { format!("{label} lcl {} cl {} ucl {}",real(limits.lcl),real(limits.cl),real(limits.ucl)) }
fn pair_text(family: usize, limits: [Limits; 2]) -> String { format!("{} {}",limits_text(LABELS[family][0],limits[0]),limits_text(LABELS[family][1],limits[1])) }

struct Series { numbers: Vec<usize>, values: Vec<f64> }
struct EstimationPass { points: usize, limits: [Limits; 2], outliers: Vec<usize> }
struct Estimate { passes: Vec<EstimationPass>, converged: bool, limits: [Limits; 2], retained: Vec<usize>, removed: Vec<usize> }
struct Check { points: usize, signals: Vec<Signal> }
struct Proposal { points: usize, limits: [Limits; 2] }
struct AttributePass { lots: usize, center: f64, outliers: Vec<usize> }
struct AttributeResult { passes: Vec<AttributePass>, converged: bool, retained: usize, removed: Vec<usize>, points: Vec<LotPoint>, signals: Vec<Signal> }
struct CapabilityGroup { name: &'static str, numbers: Vec<usize>, result: Capability }
struct RollingWindow { first: usize, last: usize, result: Capability }
struct Event {
    start: usize, end: usize, signals: Vec<Signal>, counts: [usize; 5], kind: usize, onset: usize,
    shift: f64, spread: f64, out: usize, detection: [Option<usize>; 9],
}

impl Event { fn contains(&self, point: usize) -> bool { self.start <= point && point <= self.end } }

struct Analysis {
    settings: Settings, values: Vec<i64>, lots: Vec<Lot>, groups: Vec<Subgroup>,
    estimates: Vec<Estimate>, checks: Vec<Check>, proposed: Vec<Proposal>,
    mu: f64, sigma: f64, reference: f64, interval: f64, ewma_width: f64, ma_width: f64,
    cusum: Vec<[f64; 2]>, ewma: Vec<[f64; 2]>, ma: Vec<[f64; 2]>, signals: Vec<Signal>,
    events: Vec<Event>, attributes: Vec<AttributeResult>, capability: Vec<CapabilityGroup>, rolling: Vec<RollingWindow>,
}

fn sequences(family: usize, numbers: &[usize], groups: &[Subgroup], values: &[i64]) -> [Series; 2] {
    if family == 2 {
        let selected: Vec<i64> = numbers.iter().map(|&i| values[i - 1]).collect();
        [Series { numbers: numbers.to_vec(), values: selected.iter().map(|&v| v as f64).collect() }, Series { numbers: numbers[1..].to_vec(), values: moving_ranges(&selected).into_iter().map(|v| v as f64).collect() }]
    } else {
        [Series { numbers: numbers.to_vec(), values: numbers.iter().map(|&i| groups[i - 1].mean).collect() }, Series { numbers: numbers.to_vec(), values: numbers.iter().map(|&i| if family == 0 { groups[i - 1].range as f64 } else { groups[i - 1].sd }).collect() }]
    }
}

fn estimate_family(family: usize, groups: &[Subgroup], values: &[i64], settings: &Settings) -> Estimate {
    let initial: Vec<usize> = (1..=settings.phase1 * if family == 2 { settings.size } else { 1 }).collect();
    let mut retained = initial.clone();
    let mut passes = Vec::new();
    let mut converged = false;
    let mut limits = [Limits::default(); 2];
    for pass in 1..=settings.passes {
        limits = variable_limits(family,&retained,groups,values,settings.size);
        let series = sequences(family,&retained,groups,values);
        let mut outliers = BTreeSet::new();
        for (index, series) in series.iter().enumerate() {
            for (&number, &value) in series.numbers.iter().zip(&series.values) { if limits[index].outside(value) { outliers.insert(number); } }
        }
        passes.push(EstimationPass { points: retained.len(), limits, outliers: outliers.iter().copied().collect() });
        if outliers.is_empty() { converged = true; break; }
        if pass == settings.passes { break; }
        retained.retain(|i| !outliers.contains(i));
    }
    let removed = initial.into_iter().filter(|i| !retained.contains(i)).collect();
    Estimate { passes, converged, limits, retained, removed }
}

fn monitor(a: &mut Analysis) {
    let s = &a.settings;
    for family in 0..3 {
        let factor = if family == 2 { s.size } else { 1 };
        let last = if family == 2 { a.values.len() } else { a.groups.len() };
        let numbers: Vec<usize> = (s.phase1 * factor + 1..=last).collect();
        let mut series = sequences(family,&numbers,&a.groups,&a.values);
        if family == 2 { series[1] = Series { numbers: numbers.clone(), values: numbers.iter().map(|&i| (a.values[i - 1] - a.values[i - 2]).abs() as f64).collect() }; }
        for (index, series) in series.iter().enumerate() {
            let chart = FAMILY_CHARTS[family][index];
            a.signals.extend(check_rules(chart,&series.numbers,&series.values,a.estimates[family].limits[index],&s.rules[chart]));
        }
    }
    a.mu = a.estimates[0].limits[0].cl;
    a.sigma = a.estimates[0].limits[1].cl / CONSTANTS[s.size - 2][6] / (s.size as f64).sqrt();
    a.reference = s.cusum_k * a.sigma; a.interval = s.cusum_h * a.sigma;
    let rho = s.lambda / (2.0 - s.lambda);
    let q = (1.0 - s.lambda) * (1.0 - s.lambda);
    a.ewma_width = s.ewma_l * a.sigma * rho.sqrt(); a.ma_width = 3.0 * a.sigma / (s.span as f64).sqrt();
    let (mut upper, mut lower) = (0.0_f64, 0.0_f64);
    let (mut eta_upper, mut eta_lower) = (0,0);
    let (mut z, mut factor) = (a.mu,1.0);
    for i in s.phase1 + 1..=a.groups.len() {
        let mean = a.groups[i - 1].mean;
        upper = (upper + (mean - a.mu - a.reference)).max(0.0); lower = (lower + (a.mu - mean - a.reference)).max(0.0);
        eta_upper = if upper > 0.0 { eta_upper + 1 } else { 0 }; eta_lower = if lower > 0.0 { eta_lower + 1 } else { 0 };
        a.cusum[i - 1] = [upper,lower];
        if upper > a.interval { a.signals.push(Signal { chart: 6, rule: 9, start: i - eta_upper + 1, end: i, value: upper, direction: "UP" }); upper = 0.0; eta_upper = 0; }
        if lower > a.interval { a.signals.push(Signal { chart: 6, rule: 10, start: i - eta_lower + 1, end: i, value: lower, direction: "DOWN" }); lower = 0.0; eta_lower = 0; }
        z = s.lambda * mean + (1.0 - s.lambda) * z; factor *= q;
        let width = s.ewma_l * a.sigma * (rho * (1.0 - factor)).sqrt(); a.ewma[i - 1] = [z,width];
        if z > a.mu + width { a.signals.push(Signal { chart: 7, rule: 9, start: i, end: i, value: z, direction: "UP" }); }
        else if z < a.mu - width { a.signals.push(Signal { chart: 7, rule: 10, start: i, end: i, value: z, direction: "DOWN" }); }
        let start = (s.phase1 + 1).max(i.saturating_sub(s.span - 1));
        let count = i - start + 1;
        let total: i64 = a.groups[start - 1..i].iter().map(|g| g.total).sum();
        let average = total as f64 / (s.size * count) as f64;
        let width = 3.0 * a.sigma / (count as f64).sqrt(); a.ma[i - 1] = [average,width];
        if average > a.mu + width { a.signals.push(Signal { chart: 8, rule: 9, start, end: i, value: average, direction: "UP" }); }
        else if average < a.mu - width { a.signals.push(Signal { chart: 8, rule: 10, start, end: i, value: average, direction: "DOWN" }); }
    }
    a.signals.sort_by_key(|signal| (signal.chart,signal.end,signal.rule));
}

fn group_events(a: &Analysis) -> Vec<Event> {
    let mut ranges: Vec<(usize,usize)> = Vec::new();
    let numbers: BTreeSet<usize> = a.signals.iter().map(|signal| signal.subgroup(a.settings.size)).collect();
    for number in numbers {
        if let Some(last) = ranges.last_mut() {
            if number - last.1 - 1 <= a.settings.gap { last.1 = number; continue; }
        }
        ranges.push((number,number));
    }
    ranges.into_iter().map(|(start,end)| {
        let signals: Vec<Signal> = a.signals.iter().filter(|signal| (start..=end).contains(&signal.subgroup(a.settings.size))).cloned().collect();
        let mut counts = [0_usize; 5];
        let mut detection = [None; 9];
        for signal in &signals {
            let index = if signal.direction == "NONE" { 4 } else { usize::from([1,3,5].contains(&signal.chart)) * 2 + usize::from(signal.direction == "DOWN") };
            counts[index] += 1;
            let g = signal.subgroup(a.settings.size);
            detection[signal.chart] = Some(detection[signal.chart].map_or(g, |old: usize| old.min(g)));
        }
        let kind = counts.iter().position(|&count| count == *counts.iter().max().unwrap()).unwrap();
        let onset = signals.iter().filter(|signal| signal.chart == 6).map(|signal| signal.start).min().unwrap_or(start);
        let groups = &a.groups[start - 1..end];
        let mean = groups.iter().map(|g| g.total).sum::<i64>() as f64 / (a.settings.size * groups.len()) as f64;
        let spread = (real_sum(groups.iter().map(|g| g.sd)) / groups.len() as f64) / a.estimates[1].limits[1].cl;
        let out = groups.iter().flat_map(|g| &g.values).filter(|&&value| value < a.settings.lsl || value > a.settings.usl).count();
        Event { start, end, signals, counts, kind, onset, shift: (mean - a.mu) / a.sigma, spread, out, detection }
    }).collect()
}

fn attribute_estimates(lots: &[Lot], settings: &Settings) -> Vec<AttributeResult> {
    (0..4).map(|chart| {
        let mut retained: Vec<&Lot> = lots.iter().collect();
        let mut passes = Vec::new();
        let mut converged = false;
        let mut center = center_line(chart,&retained);
        for pass in 1..=settings.passes {
            center = center_line(chart,&retained);
            let outliers: Vec<usize> = retained.iter().filter(|lot| lot_point(chart,lot,&center).status != "ok").map(|lot| lot.number).collect();
            passes.push(AttributePass { lots: retained.len(), center: center.value, outliers: outliers.clone() });
            if outliers.is_empty() { converged = true; break; }
            if pass == settings.passes { break; }
            retained.retain(|lot| !outliers.contains(&lot.number));
        }
        let points: Vec<LotPoint> = lots.iter().map(|lot| lot_point(chart,lot,&center)).collect();
        let numbers: Vec<usize> = lots.iter().map(|lot| lot.number).collect();
        let values: Vec<f64> = points.iter().map(|point| point.z).collect();
        let signals = check_rules(chart,&numbers,&values,Limits::new(-3.0,0.0,3.0),&settings.rules[6]);
        let removed = lots.iter().filter(|lot| !retained.iter().any(|other| other.number == lot.number)).map(|lot| lot.number).collect();
        AttributeResult { passes, converged, retained: retained.len(), removed, points, signals }
    }).collect()
}

impl Analysis {
    fn new(settings: Settings, values: Vec<i64>, lots: Vec<Lot>) -> Self {
        let groups = subgroup_statistics(&values,settings.size);
        let estimates: Vec<Estimate> = (0..3).map(|family| estimate_family(family,&groups,&values,&settings)).collect();
        let mut checks = Vec::new();
        for family in 0..3 {
            for (index, series) in sequences(family,&estimates[family].retained,&groups,&values).into_iter().enumerate() {
                let chart = FAMILY_CHARTS[family][index];
                checks.push(Check { points: series.numbers.len(), signals: check_rules(chart,&series.numbers,&series.values,estimates[family].limits[index],&settings.rules[chart]) });
            }
        }
        let count = groups.len();
        let mut a = Self { settings, values, lots, groups, estimates, checks, proposed: Vec::new(), mu: 0.0, sigma: 0.0, reference: 0.0, interval: 0.0, ewma_width: 0.0, ma_width: 0.0, cusum: vec![[0.0;2];count], ewma: vec![[0.0;2];count], ma: vec![[0.0;2];count], signals: Vec::new(), events: Vec::new(), attributes: Vec::new(), capability: Vec::new(), rolling: Vec::new() };
        monitor(&mut a); a.events = group_events(&a);
        for family in 0..3 {
            let mut numbers = a.estimates[family].retained.clone();
            for i in a.settings.phase1 + 1..=count {
                if a.event_number(i).is_none() {
                    if family == 2 { numbers.extend((i - 1) * a.settings.size + 1..=i * a.settings.size); } else { numbers.push(i); }
                }
            }
            a.proposed.push(Proposal { points: numbers.len(), limits: variable_limits(family,&numbers,&a.groups,&a.values,a.settings.size) });
        }
        a.attributes = attribute_estimates(&a.lots,&a.settings);
        for (name,numbers) in [("phase1",a.estimates[0].retained.clone()),("phase2",(a.settings.phase1 + 1..=count).collect())] {
            let selected: Vec<&Subgroup> = numbers.iter().map(|&i| &a.groups[i - 1]).collect();
            let result = Capability::new(&selected,&a.settings);
            a.capability.push(CapabilityGroup { name, numbers, result });
        }
        for first in (a.settings.phase1 + 1..=count - a.settings.window + 1).step_by(a.settings.step) {
            let last = first + a.settings.window - 1;
            let selected: Vec<&Subgroup> = a.groups[first - 1..last].iter().collect();
            a.rolling.push(RollingWindow { first, last, result: Capability::new(&selected,&a.settings) });
        }
        a
    }

    fn event_number(&self, subgroup: usize) -> Option<usize> { self.events.iter().position(|event| event.contains(subgroup)).map(|index| index + 1) }
    fn has_signal(&self, chart: usize, end: usize, rule: Option<u8>) -> bool { self.signals.iter().any(|signal| signal.chart == chart && signal.end == end && rule.is_none_or(|r| r == signal.rule)) }

    fn limits_lines(&self) -> Vec<String> {
        let s = &self.settings;
        let mut lines = vec![format!("characteristic {}",s.characteristic),format!("subgroup_size {}",s.size),format!("subgroups {}",self.groups.len()),format!("samples {}",self.values.len()),format!("phase1_subgroups {}",s.phase1)];
        for (family, estimate) in self.estimates.iter().enumerate() {
            lines.push(format!("family {}",FAMILIES[family]));
            for (index, pass) in estimate.passes.iter().enumerate() { lines.push(format!("pass {} points {} {} out {}",index + 1,pass.points,pair_text(family,pass.limits),number_list(&pass.outliers))); }
            lines.push(format!("result {} passes {} retained {} removed {}",status(estimate.converged),estimate.passes.len(),estimate.retained.len(),number_list(&estimate.removed)));
        }
        for (chart, check) in self.checks.iter().enumerate() {
            for signal in &check.signals { lines.push(format!("phase1_signal {} {} {} {} {}",CHARTS[chart],rule_text(signal.rule),signal.start,signal.end,real(signal.value))); }
            lines.push(format!("phase1_check {} points {} signals {}",CHARTS[chart],check.points,check.signals.len()));
        }
        for (family, proposal) in self.proposed.iter().enumerate() { lines.push(format!("proposed {} points {} {}",FAMILIES[family],proposal.points,pair_text(family,proposal.limits))); }
        lines.push(format!("cusum target {} sigma {} k {} h {}",real(self.mu),real(self.sigma),real(self.reference),real(self.interval)));
        lines.push(format!("ewma target {} sigma {} lcl {} ucl {}",real(self.mu),real(self.sigma),real(self.mu - self.ewma_width),real(self.mu + self.ewma_width)));
        lines.push(format!("ma target {} sigma {} span {} lcl {} ucl {}",real(self.mu),real(self.sigma),s.span,real(self.mu - self.ma_width),real(self.mu + self.ma_width)));
        for (chart, name) in CHARTS.iter().enumerate() {
            let signals: Vec<&Signal> = self.signals.iter().filter(|signal| signal.chart == chart).collect();
            let ends: BTreeSet<usize> = signals.iter().map(|signal| signal.end).collect();
            let first = ends.first().map_or_else(|| "none".into(), usize::to_string);
            let rules = if chart < 6 { s.rules[chart].clone() } else { vec![9,10] };
            let counts = rules.into_iter().map(|rule| format!("{}:{}",rule_text(rule),signals.iter().filter(|signal| signal.rule == rule).count())).collect::<Vec<_>>().join(" ");
            let points = (self.groups.len() - s.phase1) * if chart == 4 || chart == 5 { s.size } else { 1 };
            lines.push(format!("phase2 {name} points {points} signals {} signalled {} first {first} by_rule {counts}",signals.len(),ends.len()));
        }
        lines
    }

    fn signal_lines(&self) -> Vec<String> {
        let mut lines = vec!["chart,rule,start,end,value,direction".into()];
        for signal in &self.signals { lines.push(format!("{},{},{},{},{},{}",CHARTS[signal.chart],rule_text(signal.rule),signal.start,signal.end,real(signal.value),signal.direction)); }
        lines
    }

    fn event_lines(&self) -> Vec<String> {
        let mut lines = vec![format!("events {}",self.events.len())];
        for (index, event) in self.events.iter().enumerate() {
            let number = index + 1;
            let charts = CHARTS.iter().enumerate().filter(|&(chart, _)| event.detection[chart].is_some()).map(|(_, &name)| name).collect::<Vec<_>>().join(",");
            let counts = ["location_up","location_down","spread_up","spread_down","pattern"].iter().zip(event.counts).map(|(name,count)| format!("{name} {count}")).collect::<Vec<_>>().join(" ");
            lines.push(format!("event {number} start {} end {} length {} signals {} charts {charts} {counts} onset {} shift {} spread {} out_of_spec {} type {}",event.start,event.end,event.end - event.start + 1,event.signals.len(),event.onset,real(event.shift),real(event.spread),event.out,EVENT_TYPES[event.kind]));
            let detection = CHARTS.iter().zip(event.detection).map(|(name,number)| format!("{name}:{}",number.map_or_else(|| "-".into(),|i| i.to_string()))).collect::<Vec<_>>().join(" ");
            lines.push(format!("detection {number} {detection}"));
        }
        lines
    }

    fn subgroup_lines(&self) -> Vec<String> {
        let mut lines = vec!["subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event".into()];
        let zones = Zones::new(self.estimates[0].limits[0]);
        for (index, group) in self.groups.iter().enumerate() {
            let i = index + 1;
            let phase = if i > self.settings.phase1 { "phase2" } else if self.estimates[0].removed.contains(&i) { "excluded" } else { "phase1" };
            let trace = if i > self.settings.phase1 { [self.cusum[index][0],self.cusum[index][1],self.ewma[index][0],self.ma[index][0]].map(real) } else { std::array::from_fn(|_| "-".into()) };
            let count = self.signals.iter().filter(|signal| signal.subgroup(self.settings.size) == i).count();
            let event = self.event_number(i).map_or_else(|| "-".into(),|v| v.to_string());
            lines.push(format!("{i},{phase},{},{},{},{},{},{count},{event}",real(group.mean),zones.name(group.mean),group.range,real(group.sd),trace.join(",")));
        }
        lines
    }

    fn attribute_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for (chart, result) in self.attributes.iter().enumerate() {
            lines.push(format!("chart {}",attribute_charts::CHARTS[chart]));
            for (index, pass) in result.passes.iter().enumerate() { lines.push(format!("pass {} lots {} center {} out {}",index + 1,pass.lots,real(pass.center),number_list(&pass.outliers))); }
            lines.push(format!("result {} passes {} retained {} removed {}",status(result.converged),result.passes.len(),result.retained,number_list(&result.removed)));
            for (lot, point) in self.lots.iter().zip(&result.points) {
                let value = if chart == 1 || chart == 2 { (point.value as i64).to_string() } else { real(point.value) };
                lines.push(format!("lot {} size {} value {value} lcl {} ucl {} z {} status {}",lot.number,lot.inspected,real(point.lcl),real(point.ucl),real(point.z),point.status));
            }
            for signal in &result.signals { lines.push(format!("signal {} {} {} {}",rule_text(signal.rule),signal.start,signal.end,real(signal.value))); }
            lines.push(format!("signals {}",result.signals.len()));
        }
        lines
    }

    fn capability_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for group in &self.capability {
            let result = &group.result;
            lines.push(format!("group {} subgroups {} values {}",group.name,group.numbers.len(),result.count));
            for (label, value) in METRICS.iter().zip(result.metrics) { lines.push(format!("{label} {}",real(value))); }
            for (label, interval) in ["cpk_ci","ppk_ci"].iter().zip(result.intervals) { lines.push(format!("{label} {} {}",real(interval[0]),real(interval[1]))); }
            lines.push(format!("below_lsl {}",result.below)); lines.push(format!("above_usl {}",result.above)); lines.push(format!("ppm {}",real(result.ppm)));
            for &i in &group.numbers {
                for (index, &value) in self.groups[i - 1].values.iter().enumerate() {
                    if value < self.settings.lsl || value > self.settings.usl { lines.push(format!("out_of_spec sample {} subgroup {i} value {value} side {}",(i - 1) * self.settings.size + index + 1,if value < self.settings.lsl { "low" } else { "high" })); }
                }
            }
            lines.push(format!("verdict {}",result.verdict));
            for bin in &result.bins {
                let mut line = format!("bin {} {} {}",bin.lower,bin.upper,bin.frequency);
                if bin.length > 0 { line.push(' '); line.push_str(&"#".repeat(bin.length)); }
                if !bin.marks.is_empty() { line.push(' '); line.push_str(&bin.marks.join(" ")); }
                lines.push(line);
            }
        }
        for window in &self.rolling {
            let parts = [0,1,3,7,11].map(|i| format!("{} {}",METRICS[i],real(window.result.metrics[i]))).join(" ");
            lines.push(format!("rolling {} {} {parts} verdict {}",window.first,window.last,window.result.verdict));
        }
        lines
    }

    fn chart_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for (picture,family,limit_index,chart) in [("XBAR",0,0,0),("R",0,1,1),("S",1,1,3)] {
            let limits = self.estimates[family].limits[limit_index];
            lines.push(limits_text(&format!("chart {picture}"),limits));
            for (index, group) in self.groups.iter().enumerate() {
                let i = index + 1;
                let mark = if i > self.settings.phase1 { '2' } else if self.estimates[family].removed.contains(&i) { 'x' } else { '1' };
                let value = match chart { 0 => group.mean, 1 => group.range as f64, _ => group.sd };
                let band = plot::limits_band(limits,value,mark == '2' && self.has_signal(chart,i,None));
                lines.push(format!("{i:3} {mark} {band} {}",real(value)));
            }
        }
        lines.push(format!("chart CUSUM h {}",real(self.interval)));
        for i in self.settings.phase1 + 1..=self.groups.len() {
            let [upper,lower] = self.cusum[i - 1];
            let band = plot::cusum_band(upper,lower,self.interval,self.has_signal(6,i,Some(9)),self.has_signal(6,i,Some(10)));
            lines.push(format!("{i:3} {band} {} {}",real(upper),real(lower)));
        }
        for (chart,points,scale) in [(7,&self.ewma,self.ewma_width),(8,&self.ma,self.ma_width)] {
            lines.push(limits_text(&format!("chart {}",CHARTS[chart]),Limits::new(self.mu - scale,self.mu,self.mu + scale)));
            for i in self.settings.phase1 + 1..=self.groups.len() {
                let [value,width] = points[i - 1];
                let band = plot::width_band(scale,width,value,self.mu,self.has_signal(chart,i,None));
                lines.push(format!("{i:3} {band} {} {} {}",real(value),real(self.mu - width),real(self.mu + width)));
            }
        }
        for (chart, result) in self.attributes.iter().enumerate() {
            lines.push(format!("chart {}_STD lcl -3.0000 cl 0.0000 ucl 3.0000",attribute_charts::CHARTS[chart].to_ascii_uppercase()));
            for (lot,point) in self.lots.iter().zip(&result.points) { lines.push(format!("{:3} {} {}",lot.number,plot::standard_band(point.z,point.status == "ok"),real(point.z))); }
        }
        lines
    }
}

fn main() {
    let analysis = Analysis::new(Settings::read(),dataset::read_measurements(),dataset::read_attributes());
    fs::create_dir_all("output").unwrap();
    for (name,lines) in [("limits.txt",analysis.limits_lines()),("signals.csv",analysis.signal_lines()),("events.txt",analysis.event_lines()),("subgroups.csv",analysis.subgroup_lines()),("attribute_charts.txt",analysis.attribute_lines()),("capability.txt",analysis.capability_lines()),("charts.txt",analysis.chart_lines())] {
        fs::write(format!("output/{name}"),if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" }).unwrap();
    }
}
