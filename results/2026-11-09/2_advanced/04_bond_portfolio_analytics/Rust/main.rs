mod dates_calendar;
mod daycount;
mod schedule;
mod pricing;
mod curve;

use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::io;
use std::rc::Rc;
use dates_calendar::{Calendar, civil_date, format_date, parse_date, valid_date, BUSINESS_DAY_RULES};
use daycount::{year_fraction, DAY_COUNTS};
use schedule::coupon_schedule;
use pricing::{bisection, Risk, YieldPricer, BP};
use curve::{bootstrap, z_spread, ZeroCurve};

const TYPES: [&str; 4] = ["FIXED", "ZERO", "AMORT", "FRN"];
const FREQUENCIES: [i32; 4] = [1, 2, 4, 12];
const BUCKETS: [&str; 5] = ["0-1Y", "1-3Y", "3-5Y", "5-10Y", "10Y+"];
type Scenario = (String, Vec<f64>);
fn integer(text: &str) -> i64 { text.parse().unwrap() }
fn rounded(a: i64, b: i64) -> i64 { (2 * a + b) / (2 * b) }
fn hundredths(value: i64) -> String { let magnitude = if value < 0 { -value } else { value }; format!("{}{}.{:02}", if value < 0 { "-" } else { "" }, magnitude / 100, magnitude % 100) }
fn decimals(value: f64, digits: usize) -> String {
    let mut scale = 1; for _ in 0..digits { scale *= 10; }
    let magnitude = if value < 0.0 { -value } else { value };
    let rounded = (magnitude * scale as f64 + 0.5) as i64;
    format!("{}{}.{:0width$}", if value < 0.0 && rounded != 0 { "-" } else { "" }, rounded / scale, rounded % scale, width = digits)
}
fn percent(value: f64) -> String { decimals(value * 100.0, 4) }
fn amount(cents: f64) -> String { decimals(cents / 100.0, 2) }
fn thousandths(text: &str) -> i64 { let (whole, fraction) = text.split_once('.').unwrap(); integer(whole) * 1000 + integer(fraction) }
fn read_lines(name: &str) -> io::Result<Vec<String>> { Ok(fs::read_to_string(format!("input/{name}"))?.split_terminator('\n').map(str::to_owned).collect()) }
fn rows(name: &str) -> io::Result<Vec<(usize, Vec<String>)>> { Ok(read_lines(name)?.into_iter().skip(1).enumerate().map(|(index, line)| (index + 2, line.split(',').map(str::to_owned).collect())).collect()) }
fn write_lines(name: &str, lines: &[String]) -> io::Result<()> { fs::write(format!("output/{name}"), if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" }) }
fn record(errors: &mut Vec<String>, file: &str, number: usize, key: &str, reason: &str) { errors.push(format!("{file}:{number}: {key}: {reason}")); }

#[derive(Default)]
struct Options { eom: bool, long: bool, lag: Option<i32>, cap: Option<i64>, floor: Option<i64>, sinks: Vec<(String, i64)>, calls: Vec<(String, i64)> }
fn parse_options(kind: &str, text: &str) -> Result<Options, &'static str> {
    let mut options = Options::default(); let mut seen = HashSet::new();
    for item in text.split(';').filter(|item| *item != "-") {
        let (key, value) = item.split_once('=').unwrap_or((item, ""));
        let allowed = matches!(key, "EOM" | "LONG") || match kind { "FIXED" => key == "CALL", "AMORT" => key == "SINK", "FRN" => matches!(key, "LAG" | "CAP" | "FLOOR"), _ => false };
        if !allowed || (!seen.insert(key) && !matches!(key, "SINK" | "CALL")) { return Err("invalid option"); }
        match key {
            "EOM" => options.eom = true, "LONG" => options.long = true,
            "LAG" => options.lag = Some(integer(value) as i32), "CAP" => options.cap = Some(integer(value)), "FLOOR" => options.floor = Some(integer(value)),
            _ => { let (date, number) = value.split_once(':').unwrap(); if key == "SINK" { options.sinks.push((date.to_owned(), integer(number))); } else { options.calls.push((date.to_owned(), thousandths(number))); } }
        }
    }
    if kind == "FRN" && (options.lag.is_none_or(|lag| !(1..=5).contains(&lag)) || options.cap.unwrap_or(1200) > 1200 || options.floor.unwrap_or(0) > options.cap.unwrap_or(1200)) { return Err("invalid option"); }
    Ok(options)
}
fn schedule_days(items: &[(String, i64)], dates: &[i32], reason: &'static str) -> Result<Vec<(i32, i64)>, &'static str> {
    let mut result = Vec::new(); let mut previous = -1;
    for (text, value) in items {
        if !valid_date(text) { return Err(reason); }
        let day = parse_date(text);
        if !dates[1..dates.len() - 1].contains(&day) || day <= previous { return Err(reason); }
        result.push((day, *value)); previous = day;
    }
    Ok(result)
}
fn latest_fixing(fixings: &[(i32, i64)], day: i32) -> Option<i64> { let index = fixings.partition_point(|&(date, _)| date <= day); index.checked_sub(1).map(|index| fixings[index].1) }

#[derive(Clone)]
struct Period { number: usize, start: i32, end: i32, payment: i32, n: i64, m: i64, rate: i64, opening: i64, coupon: i64, principal: i64, cash: i64 }
#[derive(Clone)]
struct Bond { code: String, kind: String, issue: i32, maturity: i32, frequency: i32, daycount: String, face: i64, calls: Vec<(i32, i64)>, periods: Vec<Period> }
fn parse_bond(fields: &[String], seen: &HashSet<String>, calendar: &Calendar, fixings: &[(i32, i64)]) -> Result<Bond, &'static str> {
    let code = &fields[0]; let kind = fields[1].as_str(); let coupon = integer(&fields[4]); let frequency = integer(&fields[5]) as i32;
    let daycount = fields[6].as_str(); let bdc = fields[7].as_str(); let face = integer(&fields[8]);
    if seen.contains(code) { return Err("duplicate id"); }
    if !TYPES.contains(&kind) { return Err("unknown type"); }
    if !valid_date(&fields[2]) || !valid_date(&fields[3]) { return Err("invalid date"); }
    let issue = parse_date(&fields[2]); let maturity = parse_date(&fields[3]);
    if maturity <= issue { return Err("maturity not after issue"); }
    if !FREQUENCIES.contains(&frequency) { return Err("invalid frequency"); }
    if !DAY_COUNTS.contains(&daycount) { return Err("unknown day count"); }
    if !BUSINESS_DAY_RULES.contains(&bdc) { return Err("unknown business day rule"); }
    if face % 100000 != 0 || face > 10000000 { return Err("invalid face"); }
    if coupon > 1200 || kind == "ZERO" && coupon != 0 { return Err("invalid coupon"); }
    let options = parse_options(kind, &fields[9])?;
    let dates = coupon_schedule(issue, maturity, frequency, options.eom, options.long);
    let sink_items = schedule_days(&options.sinks, &dates, "invalid sinking fund")?;
    let mut sinks = BTreeMap::new(); let mut total = 0;
    for (day, value) in sink_items { if value == 0 { return Err("invalid sinking fund"); } sinks.insert(day, value); total += value; }
    if kind == "AMORT" && (total == 0 || total >= face) { return Err("invalid sinking fund"); }
    let calls = schedule_days(&options.calls, &dates, "invalid call schedule")?;
    if calls.iter().any(|&(_, price)| !(100000..=110000).contains(&price)) { return Err("invalid call schedule"); }
    let mut opening = face; let mut periods = Vec::new();
    for number in 1..dates.len() {
        let (start, end) = (dates[number - 1], dates[number]); let (n, m) = year_fraction(daycount, start, end);
        let mut rate = if kind == "ZERO" { 0 } else { coupon };
        if kind == "FRN" {
            let fixing_day = calendar.move_days(calendar.adjust(start, bdc), -options.lag.unwrap());
            rate = latest_fixing(fixings, fixing_day).ok_or("missing fixing")? + coupon;
            if let Some(floor) = options.floor { rate = rate.max(floor); }
            if let Some(cap) = options.cap { rate = rate.min(cap); }
        }
        let principal = if number == dates.len() - 1 { opening } else { *sinks.get(&end).unwrap_or(&0) };
        let coupon = rounded(opening * rate * n, 10000 * m);
        periods.push(Period { number, start, end, payment: calendar.adjust(end, bdc), n, m, rate, opening, coupon, principal, cash: coupon + principal });
        opening -= principal;
    }
    Ok(Bond { code: code.clone(), kind: kind.to_owned(), issue, maturity, frequency, daycount: daycount.to_owned(), face, calls, periods })
}

struct Valuation {
    bond: Bond, clean: i64, remaining: Vec<Period>, outstanding: i64, clean_amount: i64, unit_value: i64,
    accrued: f64, target: f64, fraction: f64, flows: Vec<(i32, f64)>, pricer: YieldPricer,
    ytm: f64, ytw: f64, workout: i32, next_payment: i32, wal: f64, risk: Risk, curve_clean: f64, spread: f64,
}
impl Valuation {
    fn new(bond: Bond, clean: i64, settlement: i32) -> Self {
        let index = bond.periods.iter().position(|period| period.end > settlement).unwrap(); let current = &bond.periods[index];
        let remaining = bond.periods[index..].to_vec(); let outstanding = current.opening;
        let (n, m) = year_fraction(&bond.daycount, current.start, settlement);
        let accrued = current.rate as f64 * n as f64 / (100.0 * m as f64);
        let accrued_amount = rounded(outstanding * current.rate * n, 10000 * m); let clean_amount = rounded(outstanding * clean, 100000);
        let unit_value = clean_amount + accrued_amount; let target = clean as f64 / 1000.0 + accrued;
        let (n, m) = year_fraction(&bond.daycount, settlement, current.end); let fraction = bond.frequency as f64 * n as f64 / m as f64;
        let cashflows: Vec<_> = remaining.iter().filter(|period| period.cash >= 1).collect();
        let next_payment = cashflows[0].payment; let flows = cashflows.iter().map(|period| (period.payment - settlement, period.cash as f64)).collect();
        let pricer = YieldPricer { flows: remaining.iter().map(|period| period.cash).collect(), fraction, frequency: bond.frequency, outstanding };
        let workout = bond.maturity;
        Self { bond, clean, remaining, outstanding, clean_amount, unit_value, accrued, target, fraction, flows, pricer, ytm: 0.0, ytw: 0.0, workout, next_payment, wal: 0.0, risk: Risk::default(), curve_clean: 0.0, spread: 0.0 }
    }
    fn analyze(&mut self, curve: &ZeroCurve, settlement: i32) {
        self.ytm = self.pricer.solve(self.target); self.risk = self.pricer.risk(self.ytm); self.ytw = self.ytm;
        for &(day, price) in &self.bond.calls {
            if day <= settlement { continue; }
            let mut flows = Vec::new();
            for period in &self.remaining {
                flows.push(period.coupon);
                if period.end == day { *flows.last_mut().unwrap() += rounded(period.opening * price, 100000); break; }
            }
            let rate = YieldPricer { flows, fraction: self.fraction, frequency: self.bond.frequency, outstanding: self.outstanding }.solve(self.target);
            if rate < self.ytw { self.ytw = rate; self.workout = day; }
        }
        let mut principal_days = 0;
        for period in self.remaining.iter().filter(|period| period.cash >= 1) { principal_days += period.principal * (period.payment - settlement) as i64; }
        self.wal = principal_days as f64 / (365.0 * self.outstanding as f64);
        self.curve_clean = curve.present_value(&self.flows, 0.0) * 100.0 / self.outstanding as f64 - self.accrued;
        self.spread = z_spread(curve, &self.flows, self.unit_value);
    }
}
struct Position { valuation: Rc<Valuation>, units: i64, book: i64 }
impl Position {
    fn value(&self) -> i64 { self.units * self.valuation.unit_value }
    fn face(&self) -> i64 { self.units * self.valuation.bond.face }
    fn outstanding(&self) -> i64 { self.units * self.valuation.outstanding }
    fn gain(&self) -> i64 { self.units * self.valuation.clean_amount - self.book }
    fn dv01(&self) -> f64 { self.valuation.risk.dv01 * self.units as f64 * self.valuation.outstanding as f64 / 10000.0 }
    fn pv(&self, curve: &ZeroCurve) -> f64 { self.units as f64 * curve.present_value(&self.valuation.flows, self.valuation.spread) }
}
#[derive(Clone, Default)]
struct Group { count: usize, value: i64, duration: f64, dv01: f64 }
impl Group { fn add(&mut self, position: &Position) { self.count += 1; self.value += position.value(); self.duration += position.value() as f64 * position.valuation.risk.modified; self.dv01 += position.dv01(); } }
struct ScenarioResult { name: String, values: Vec<f64>, pnls: Vec<f64>, total: f64, pnl: f64 }
struct Portfolio {
    name: String, positions: Vec<Position>, total: i64, income: i64,
    ytm: f64, modified: f64, convexity: f64, spread: f64, dv01: f64, cash_yield: f64, base: f64, effective: f64,
    base_values: Vec<f64>, key_rates: Vec<f64>, types: Vec<Group>, buckets: Vec<Group>, ladder: BTreeMap<i32, (i64, i64)>, results: Vec<ScenarioResult>,
}
impl Portfolio {
    fn new(name: String, positions: Vec<Position>) -> Self {
        let total = positions.iter().map(Position::value).sum();
        Self { name, positions, total, income: 0, ytm: 0.0, modified: 0.0, convexity: 0.0, spread: 0.0, dv01: 0.0, cash_yield: 0.0, base: 0.0, effective: 0.0,
            base_values: Vec::new(), key_rates: Vec::new(), types: vec![Group::default(); 4], buckets: vec![Group::default(); 5], ladder: BTreeMap::new(), results: Vec::new() }
    }
    fn weight(&self, value: i64) -> f64 { value as f64 * 100.0 / self.total as f64 }
    fn pv(&self, curve: &ZeroCurve) -> f64 { let mut total = 0.0; for position in &self.positions { total += position.pv(curve); } total }
    fn rate_duration(&self, curve: &ZeroCurve, pillar: Option<usize>) -> f64 {
        let mut down = vec![0.0; curve.rates.len()]; let mut up = down.clone();
        for index in 0..down.len() { if pillar.is_none_or(|selected| selected == index) { down[index] = -BP; up[index] = BP; } }
        (self.pv(&curve.shifted(&down)) - self.pv(&curve.shifted(&up))) / (2.0 * BP * self.base)
    }
    fn analyze(&mut self, curve: &ZeroCurve, scenarios: &[Scenario], settlement: i32) {
        let mut flows = Vec::new();
        for position in &self.positions {
            let v = &position.valuation; let value = position.value() as f64;
            self.ytm += value * v.ytm; self.modified += value * v.risk.modified; self.convexity += value * v.risk.convexity; self.spread += value * v.spread; self.dv01 += position.dv01();
            let kind = TYPES.iter().position(|&kind| kind == v.bond.kind).unwrap(); self.types[kind].add(position);
            let days = v.bond.maturity - settlement; let bucket = [365, 1095, 1825, 3650].iter().position(|&limit| days < limit).unwrap_or(4); self.buckets[bucket].add(position);
            for period in v.remaining.iter().filter(|period| period.cash >= 1) {
                let days = period.payment - settlement; flows.push((days, (position.units * period.cash) as f64));
                if days <= 365 { self.income += position.units * period.coupon; }
                let entry = self.ladder.entry(civil_date(period.payment).0).or_default(); entry.0 += position.units * period.coupon; entry.1 += position.units * period.principal;
            }
            self.base_values.push(position.pv(curve));
        }
        self.ytm /= self.total as f64; self.modified /= self.total as f64; self.convexity /= self.total as f64; self.spread /= self.total as f64;
        self.cash_yield = bisection(|rate| ZeroCurve { days: vec![0], rates: vec![rate] }.present_value(&flows, 0.0), 0.0, 1.0, self.total as f64);
        for value in &self.base_values { self.base += value; }
        self.effective = self.rate_duration(curve, None); self.key_rates = (0..curve.rates.len()).map(|index| self.rate_duration(curve, Some(index))).collect();
        let mut all = vec![("BASE".to_owned(), vec![0.0; curve.rates.len()])]; all.extend(scenarios.iter().cloned());
        for (name, deltas) in all {
            let shifted = curve.shifted(&deltas); let mut values = Vec::new(); let mut pnls = Vec::new(); let mut total = 0.0;
            for (index, position) in self.positions.iter().enumerate() { let value = position.pv(&shifted); values.push(value); pnls.push(value - self.base_values[index]); total += value; }
            self.results.push(ScenarioResult { name, values, pnls, total, pnl: total - self.base });
        }
    }
    fn report(&self) -> Vec<String> {
        let mut lines = vec![format!("portfolio {}", self.name)]; let (mut face, mut outstanding, mut book, mut gain) = (0, 0, 0, 0);
        for position in &self.positions {
            let v = &position.valuation;
            lines.push(format!("position {} face {} outstanding {} clean {} value {} weight {} book {} gain {} ytm {} modified {} dv01 {}", v.bond.code, hundredths(position.face()), hundredths(position.outstanding()), decimals(v.clean as f64 / 1000.0, 6), hundredths(position.value()), decimals(self.weight(position.value()), 4), hundredths(position.book), hundredths(position.gain()), percent(v.ytm), decimals(v.risk.modified, 4), decimals(position.dv01(), 2)));
            face += position.face(); outstanding += position.outstanding(); book += position.book; gain += position.gain();
        }
        lines.push(format!("total positions {} face {} outstanding {} value {} book {} gain {} income {}", self.positions.len(), hundredths(face), hundredths(outstanding), hundredths(self.total), hundredths(book), hundredths(gain), hundredths(self.income)));
        lines.push(format!("risk ytm {} yield {} modified {} convexity {} zspread {} dv01 {}", percent(self.ytm), percent(self.cash_yield), decimals(self.modified, 4), decimals(self.convexity, 4), percent(self.spread), decimals(self.dv01, 2)));
        lines.push(format!("curve effective {} krd {}", decimals(self.effective, 4), self.key_rates.iter().map(|&value| decimals(value, 4)).collect::<Vec<_>>().join(" ")));
        for (label, names, groups) in [("type", TYPES.as_slice(), &self.types), ("bucket", BUCKETS.as_slice(), &self.buckets)] {
            for (name, group) in names.iter().zip(groups) { lines.push(format!("{label} {name} positions {} value {} weight {} duration {} dv01 {}", group.count, hundredths(group.value), decimals(self.weight(group.value), 4), decimals(group.duration / self.total as f64, 4), decimals(group.dv01, 2))); }
        }
        let (mut coupons, mut principals) = (0, 0);
        for (year, &(coupon, principal)) in &self.ladder { lines.push(format!("ladder {year} coupon {} principal {} total {}", hundredths(coupon), hundredths(principal), hundredths(coupon + principal))); coupons += coupon; principals += principal; }
        lines.push(format!("ladder total coupon {} principal {} total {}", hundredths(coupons), hundredths(principals), hundredths(coupons + principals)));
        let mut worst: Option<&ScenarioResult> = None;
        for result in self.results.iter().skip(1) { if worst.is_none_or(|current| result.pnl < current.pnl) { worst = Some(result); } }
        if let Some(worst) = worst {
            let mut order: Vec<_> = (0..self.positions.len()).collect();
            order.sort_by(|&a, &b| worst.pnls[a].partial_cmp(&worst.pnls[b]).unwrap().then_with(|| self.positions[a].valuation.bond.code.cmp(&self.positions[b].valuation.bond.code)));
            let mut line = format!("stress worst {} pnl {} losers", worst.name, amount(worst.pnl));
            for index in order.into_iter().take(3) { line.push_str(&format!(" {} {}", self.positions[index].valuation.bond.code, amount(worst.pnls[index]))); }
            lines.push(line);
        }
        lines
    }
    fn scenario_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for result in &self.results {
            for (index, position) in self.positions.iter().enumerate() { lines.push(format!("{},{},{},{},{}", self.name, result.name, position.valuation.bond.code, amount(result.values[index]), amount(result.pnls[index]))); }
            lines.push(format!("{},{},*,{},{}", self.name, result.name, amount(result.total), amount(result.pnl)));
        }
        lines
    }
    fn compliance(&self, limits: &[Vec<String>], settlement: i32) -> Vec<String> {
        let mut lines = Vec::new(); let mut breaches = 0;
        for words in limits {
            let kind = words[0].as_str();
            let (detail, breach) = match kind {
                "position_weight" => {
                    let limit = integer(&words[1]); let mut largest = &self.positions[0];
                    for position in &self.positions { if position.value() > largest.value() { largest = position; } }
                    (format!("{} {} limit {}", largest.valuation.bond.code, decimals(self.weight(largest.value()), 4), hundredths(limit)), largest.value() * 10000 > limit * self.total)
                }
                "type_weight" => { let limit = integer(&words[2]); let group = TYPES.iter().position(|&kind| kind == words[1]).unwrap(); let value = self.types[group].value; (format!("{} {} limit {}", words[1], decimals(self.weight(value), 4), hundredths(limit)), value * 10000 > limit * self.total) }
                "max_maturity" => { let years = integer(&words[1]); let count = self.positions.iter().filter(|position| (position.valuation.bond.maturity - settlement) as i64 > 365 * years).count(); (format!("{years}Y positions {count}"), count > 0) }
                "min_yield" => { let limit = integer(&words[1]); (format!("{} limit {}", percent(self.ytm), hundredths(limit)), self.ytm * 10000.0 < limit as f64) }
                "duration" => { let low = integer(&words[1]); let high = integer(&words[2]); (format!("{} range {} {}", decimals(self.modified, 4), hundredths(low), hundredths(high)), self.modified < low as f64 / 100.0 || self.modified > high as f64 / 100.0) }
                _ => { let limit = integer(&words[1]); (format!("{} limit {}", decimals(self.dv01, 2), hundredths(limit)), self.dv01 * 100.0 > limit as f64) }
            };
            if breach { breaches += 1; }
            lines.push(format!("{} {kind} {detail} {}", self.name, if breach { "BREACH" } else { "PASS" }));
        }
        lines.push(format!("{} breaches {breaches}", self.name)); lines
    }
}

fn main() -> io::Result<()> {
    let mut valuation_date = 0; let mut settlement_days = 0; let mut scenario_lines = Vec::new(); let mut limits = Vec::new();
    for (index, line) in read_lines("params.txt")?.iter().enumerate() {
        let words: Vec<_> = line.split(' ').collect();
        match words[0] {
            "valuation_date" => valuation_date = parse_date(words[1]), "settlement_days" => settlement_days = integer(words[1]) as i32,
            "scenario" => scenario_lines.push((index + 1, words[1].to_owned(), words[2..].iter().map(|word| integer(word)).collect::<Vec<_>>())),
            _ => limits.push(words[1..].iter().map(|word| (*word).to_owned()).collect::<Vec<_>>()),
        }
    }
    let calendar = Calendar::new(read_lines("calendar.txt")?.iter().map(|line| parse_date(line)));
    let fixings: Vec<_> = rows("fixings.csv")?.into_iter().map(|(_, fields)| (parse_date(&fields[0]), integer(&fields[1]))).collect();
    let settlement = calendar.move_days(valuation_date, settlement_days); let mut errors = Vec::new(); let mut seen = HashSet::new(); let mut pillars = Vec::new();
    for (number, fields) in rows("curve_quotes.csv")? {
        let text = &fields[0]; let frequency = integer(&fields[2]) as i32;
        let reason = if seen.contains(text) { Some("duplicate pillar") } else if !valid_date(text) { Some("invalid date") } else if parse_date(text) <= settlement { Some("pillar not after settlement") } else if !FREQUENCIES.contains(&frequency) { Some("invalid frequency") } else { None };
        if let Some(reason) = reason { record(&mut errors, "curve_quotes.csv", number, text, reason); } else { pillars.push((parse_date(text), integer(&fields[1]), frequency)); }
        seen.insert(text.clone());
    }
    pillars.sort_by_key(|pillar| pillar.0); seen.clear(); let mut scenarios = Vec::new();
    for (number, name, shifts) in scenario_lines {
        if seen.contains(&name) { record(&mut errors, "params.txt", number, &name, "duplicate scenario"); }
        else if shifts.len() != pillars.len() { record(&mut errors, "params.txt", number, &name, "wrong number of shifts"); }
        else { scenarios.push((name.clone(), shifts.into_iter().map(|shift| shift as f64 * BP).collect())); }
        seen.insert(name);
    }
    seen.clear(); let mut bonds = BTreeMap::new();
    for (number, fields) in rows("bonds.csv")? {
        match parse_bond(&fields, &seen, &calendar, &fixings) { Ok(bond) => { bonds.insert(bond.code.clone(), bond); } Err(reason) => record(&mut errors, "bonds.csv", number, &fields[0], reason) }
        seen.insert(fields[0].clone());
    }
    seen.clear(); let mut valuations = BTreeMap::new();
    for (number, fields) in rows("prices.csv")? {
        let code = &fields[0];
        let result = (|| -> Result<Valuation, &'static str> {
            let bond = bonds.get(code).ok_or("unknown bond")?;
            if seen.contains(code) { return Err("duplicate price"); }
            if bond.issue > settlement || settlement >= bond.maturity { return Err("not outstanding"); }
            let value = Valuation::new(bond.clone(), thousandths(&fields[1]), settlement);
            if !value.pricer.in_range(value.target) { return Err("yield out of range"); }
            Ok(value)
        })();
        match result { Ok(value) => { valuations.insert(code.clone(), value); } Err(reason) => record(&mut errors, "prices.csv", number, code, reason) }
        seen.insert(code.clone());
    }
    let mut holdings: BTreeMap<(String, String), (i64, i64)> = BTreeMap::new();
    for (number, fields) in rows("holdings.csv")? {
        let code = &fields[1]; let face = integer(&fields[2]);
        let result = (|| -> Result<(i64, i64), &'static str> {
            let bond = bonds.get(code).ok_or("unknown bond")?; let value = valuations.get(code).ok_or("no price")?;
            if face % bond.face != 0 { return Err("invalid face"); }
            let units = face / bond.face; Ok((units, rounded(units * value.outstanding * thousandths(&fields[3]), 100000)))
        })();
        match result { Ok((units, book)) => { let entry = holdings.entry((fields[0].clone(), code.clone())).or_default(); entry.0 += units; entry.1 += book; } Err(reason) => record(&mut errors, "holdings.csv", number, code, reason) }
    }
    let curve = bootstrap(settlement, &pillars); for value in valuations.values_mut() { value.analyze(&curve, settlement); }
    let valuations: BTreeMap<String, Rc<Valuation>> = valuations.into_iter().map(|(code, value)| (code, Rc::new(value))).collect();
    let mut portfolio_positions: BTreeMap<String, Vec<Position>> = BTreeMap::new();
    for ((name, code), (units, book)) in holdings { portfolio_positions.entry(name).or_default().push(Position { valuation: Rc::clone(&valuations[&code]), units, book }); }
    let mut report = Vec::new(); let mut scenario_rows = vec!["portfolio,scenario,bond,value,pnl".to_owned()]; let mut compliance = Vec::new();
    for (name, positions) in portfolio_positions { let mut portfolio = Portfolio::new(name, positions); portfolio.analyze(&curve, &scenarios, settlement); report.extend(portfolio.report()); scenario_rows.extend(portfolio.scenario_lines()); compliance.extend(portfolio.compliance(&limits, settlement)); }
    let mut cashflows = vec!["bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal".to_owned()];
    for bond in bonds.values() { for period in bond.periods.iter().filter(|period| period.cash >= 1) { cashflows.push(format!("{},{},{},{},{},{},{},{},{},{}", bond.code, period.number, format_date(period.start), format_date(period.end), format_date(period.payment), decimals(period.n as f64 / period.m as f64, 6), period.rate, period.opening, period.coupon, period.principal)); } }
    let mut analytics = vec!["bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread".to_owned()];
    for (code, v) in &valuations { analytics.push(format!("{code},{},{},{},{},{},{},{},{},{},{},{},{},{},{}", decimals(v.clean as f64 / 1000.0, 6), decimals(v.accrued, 6), decimals(v.target, 6), percent(v.ytm), percent(v.ytw), format_date(v.workout), format_date(v.next_payment), decimals(v.wal, 4), decimals(v.risk.macaulay, 4), decimals(v.risk.modified, 4), decimals(v.risk.convexity, 4), decimals(v.risk.dv01, 6), decimals(v.curve_clean, 6), percent(v.spread))); }
    let mut curve_rows = vec![format!("valuation {} settlement {}", format_date(valuation_date), format_date(settlement))]; let mut previous = 0;
    for (index, &(maturity, coupon, frequency)) in pillars.iter().enumerate() { let days = curve.days[index]; curve_rows.push(format!("pillar {} days {days} frequency {frequency} par {} zero {} df {} forward {}", format_date(maturity), hundredths(coupon), percent(curve.rates[index]), decimals(curve.discount(days, 0.0), 6), percent(curve.forward(previous, days)))); previous = days; }
    for year in 1..=curve.days.last().unwrap() / 365 { let days = 365 * year; curve_rows.push(format!("grid {year}Y days {days} zero {} df {} forward {}", percent(curve.zero(days)), decimals(curve.discount(days, 0.0), 6), percent(curve.forward(days - 365, days)))); }
    fs::create_dir_all("output")?;
    for (name, lines) in [("errors.txt", &errors), ("cashflows.csv", &cashflows), ("analytics.csv", &analytics), ("curve.txt", &curve_rows), ("portfolio.txt", &report), ("scenarios.csv", &scenario_rows), ("compliance.txt", &compliance)] { write_lines(name, lines)?; }
    Ok(())
}
