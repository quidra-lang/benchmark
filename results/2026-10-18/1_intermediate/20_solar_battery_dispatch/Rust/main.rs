use std::collections::BTreeMap;
use std::io::{self, Read};

const PARAMETERS: [(&str, i64, i64); 13] = [
    ("CAPACITY", 1, 100000), ("INITIAL", 0, 100), ("CHARGE", 1, 20000),
    ("DISCHARGE", 1, 20000), ("CEFF", 1, 100), ("DEFF", 1, 100),
    ("RESERVE", 0, 100), ("COST", 0, 100000), ("EXPORT", 0, 100000),
    ("FEEDIN", 0, 10000), ("FIXED", 0, 100000), ("DEMAND", 0, 100000), ("PVSCALE", 0, 300),
];
const DAY_NAMES: [&str; 7] = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];
const FLOWS: [&str; 8] = ["PV>LOAD", "PV>BATTERY", "PV>GRID", "PV>CURTAIL", "BATTERY>LOAD", "BATTERY>GRID", "GRID>LOAD", "GRID>BATTERY"];

fn number(text: &str) -> i64 { text.parse().unwrap() }

fn money(value: i64) -> String {
    format!("{}{}.{:02}", if value < 0 { "-" } else { "" }, value.abs() / 100, value.abs() % 100)
}

fn percentage(numerator: i64, denominator: i64) -> String {
    money(if denominator == 0 { 0 } else { 10000 * numerator / denominator })
}

fn ceil_div(numerator: i64, denominator: i64) -> i64 { (numerator + denominator - 1) / denominator }

fn bar(width: i64) -> String { format!("|{}{}|", "#".repeat(width as usize), ".".repeat((20 - width) as usize)) }

fn arity(args: &[&str], expected: usize) -> Result<(), String> {
    if args.len() == expected { Ok(()) } else { Err("wrong number of arguments".into()) }
}

fn bounds(item: &str) -> Result<(i64, i64), String> {
    PARAMETERS.iter().find(|(name, _, _)| *name == item).map(|(_, low, high)| (*low, *high))
        .ok_or_else(|| format!("unknown parameter {item}"))
}

fn check_range(low: i64, high: i64, step: i64, minimum: i64, maximum: i64) -> Result<(), String> {
    if low < minimum || high > maximum || high < low || step < 1 || (high - low) / step + 1 > 20 {
        Err("invalid range".into())
    } else { Ok(()) }
}

#[derive(Clone, Copy)]
struct Settings {
    capacity: i64,
    initial: i64,
    charge: i64,
    discharge: i64,
    ceff: i64,
    deff: i64,
    reserve: i64,
    cost: i64,
    export: i64,
    feedin: i64,
    fixed: i64,
    demand: i64,
    pvscale: i64,
}

impl Settings {
    fn set(&mut self, item: &str, value: i64) -> i64 {
        let field = match item {
            "CAPACITY" => &mut self.capacity, "INITIAL" => &mut self.initial,
            "CHARGE" => &mut self.charge, "DISCHARGE" => &mut self.discharge,
            "CEFF" => &mut self.ceff, "DEFF" => &mut self.deff,
            "RESERVE" => &mut self.reserve, "COST" => &mut self.cost,
            "EXPORT" => &mut self.export, "FEEDIN" => &mut self.feedin,
            "FIXED" => &mut self.fixed, "DEMAND" => &mut self.demand,
            "PVSCALE" => &mut self.pvscale, _ => unreachable!(),
        };
        std::mem::replace(field, value)
    }
}

#[derive(Clone)]
struct Tariff { names: Vec<String>, prices: Vec<i64> }

impl Tariff {
    fn extremes(&self) -> (usize, usize) {
        let (mut cheapest, mut peak) = (0, 0);
        for index in 1..self.prices.len() {
            if self.prices[index] < self.prices[cheapest] { cheapest = index; }
            if self.prices[index] > self.prices[peak] { peak = index; }
        }
        (cheapest, peak)
    }
}

#[derive(Clone, Copy)]
enum Strategy { SelfConsumption, Tou(i64), PeakShave(i64), Backup(i64), ExportPeak }

impl Strategy {
    fn text(self) -> String {
        match self {
            Self::SelfConsumption => "SELF".into(), Self::Tou(target) => format!("TOU {target}"),
            Self::PeakShave(limit) => format!("PEAKSHAVE {limit}"), Self::Backup(reserve) => format!("BACKUP {reserve}"),
            Self::ExportPeak => "EXPORTPEAK".into(),
        }
    }

    fn parse_sequence(tokens: &[&str]) -> Result<Vec<Self>, String> {
        let mut strategies = Vec::new();
        let mut position = 0;
        while position < tokens.len() {
            let name = tokens[position];
            position += 1;
            let strategy = match name {
                "SELF" => Self::SelfConsumption,
                "EXPORTPEAK" => Self::ExportPeak,
                "TOU" | "PEAKSHAVE" | "BACKUP" => {
                    if position == tokens.len() { return Err(format!("missing parameter for {name}")); }
                    let value = number(tokens[position]);
                    position += 1;
                    let (low, high) = match name { "TOU" => (1, 100), "BACKUP" => (0, 100), _ => (0, 100000) };
                    if value < low || value > high { return Err(format!("invalid parameter for {name}")); }
                    match name { "TOU" => Self::Tou(value), "BACKUP" => Self::Backup(value), _ => Self::PeakShave(value) }
                }
                _ => return Err(format!("unknown strategy {name}")),
            };
            strategies.push(strategy);
        }
        Ok(strategies)
    }

    fn parse_one(tokens: &[&str]) -> Result<Self, String> {
        let strategies = Self::parse_sequence(tokens)?;
        if strategies.len() != 1 { Err("wrong number of arguments".into()) } else { Ok(strategies[0]) }
    }
}

struct Data {
    days: usize,
    load: Vec<i64>,
    pv: Vec<i64>,
    periods: Vec<usize>,
    weekend: Vec<bool>,
    day_names: Vec<&'static str>,
}

struct Record {
    period: usize,
    load: i64,
    pv: i64,
    charge: i64,
    discharge: i64,
    drawn: i64,
    soc: i64,
    import: i64,
    export: i64,
    curtailed: i64,
    shortfall: i64,
    loss: i64,
    flows: [i64; 8],
    import_cost: i64,
    income: i64,
}

#[derive(Default)]
struct Totals {
    hours: usize,
    load: i64,
    pv: i64,
    charge: i64,
    discharge: i64,
    drawn: i64,
    soc: i64,
    import: i64,
    export: i64,
    curtailed: i64,
    shortfall: i64,
    loss: i64,
    flows: [i64; 8],
    import_cost: i64,
    income: i64,
}

impl Totals {
    fn of<'a>(records: impl IntoIterator<Item = &'a Record>) -> Self {
        let mut total = Self::default();
        for record in records {
            total.hours += 1;
            total.load += record.load;
            total.pv += record.pv;
            total.charge += record.charge;
            total.discharge += record.discharge;
            total.drawn += record.drawn;
            total.soc += record.soc;
            total.import += record.import;
            total.export += record.export;
            total.curtailed += record.curtailed;
            total.shortfall += record.shortfall;
            total.loss += record.loss;
            total.import_cost += record.import_cost;
            total.income += record.income;
            for (value, flow) in total.flows.iter_mut().zip(record.flows) { *value += flow; }
        }
        total
    }

    fn net_cost(&self) -> i64 { self.import_cost - self.income }

    fn sufficiency(&self) -> String { percentage((self.load - self.import).max(0), self.load) }
}

struct Simulation {
    strategy: Strategy,
    settings: Settings,
    tariff: Tariff,
    records: Vec<Record>,
    starting: i64,
    reserve: i64,
    totals: Totals,
    peak: i64,
    demand_charge: i64,
    bill: i64,
}

impl Simulation {
    fn run(data: &Data, settings: Settings, tariff: &Tariff, strategy: Strategy, outage: Option<(usize, usize, usize)>) -> Self {
        let (cheapest, peak_period) = tariff.extremes();
        let reserve_pct = match strategy { Strategy::Backup(value) => settings.reserve.max(value), _ => settings.reserve };
        let reserve = settings.capacity * reserve_pct / 100;
        let starting = settings.capacity * settings.initial / 100;
        let mut soc = starting;
        let arbitrage = matches!(strategy, Strategy::ExportPeak) && settings.feedin > tariff.prices[cheapest];
        let mut records = Vec::new();
        for index in 0..data.load.len() {
            let (load, pv, period) = (data.load[index], data.pv[index] * settings.pvscale / 100, data.periods[index]);
            let interrupted = outage.is_some_and(|(day, start, end)| index / 24 + 1 == day && (start..=end).contains(&(index % 24)));
            let direct = load.min(pv);
            let (mut surplus, mut deficit) = (pv - direct, load - direct);
            let pv_charge = surplus.min(settings.charge).min(ceil_div(100 * (settings.capacity - soc), settings.ceff));
            let pv_stored = pv_charge * settings.ceff / 100;
            soc += pv_stored;
            surplus -= pv_charge;
            let target = if interrupted { deficit } else {
                match strategy {
                    Strategy::SelfConsumption | Strategy::Backup(_) => deficit,
                    Strategy::Tou(_) => if period == peak_period { deficit } else { 0 },
                    Strategy::PeakShave(limit) => (deficit - limit).max(0),
                    Strategy::ExportPeak => if arbitrage && period == cheapest && period != peak_period { 0 } else { deficit },
                }
            };
            let lower = if interrupted { 0 } else { reserve };
            let load_drawn = ceil_div(100 * target, settings.deff).min(settings.discharge).min((soc - lower).max(0));
            let battery_load = load_drawn * settings.deff / 100;
            soc -= load_drawn;
            deficit -= battery_load;
            let (grid_load, pv_export, curtailed, shortfall, grid_charge, export_drawn, battery_export);
            if interrupted {
                grid_load = 0;
                pv_export = 0;
                curtailed = surplus;
                shortfall = deficit;
                grid_charge = 0;
                export_drawn = 0;
                battery_export = 0;
            } else {
                grid_load = deficit;
                pv_export = surplus.min(settings.export);
                curtailed = surplus - pv_export;
                shortfall = 0;
                let mut headroom = settings.charge - pv_charge;
                let charge_target = match strategy {
                    Strategy::Tou(target) if period == cheapest && period != peak_period => Some(settings.capacity * target / 100),
                    Strategy::PeakShave(limit) if period == cheapest => {
                        headroom = headroom.min((limit - grid_load).max(0));
                        Some(settings.capacity)
                    }
                    Strategy::Backup(_) if period == cheapest => Some(reserve),
                    Strategy::ExportPeak if arbitrage && period == cheapest && period != peak_period => Some(settings.capacity),
                    _ => None,
                };
                grid_charge = charge_target.map(|target| headroom.min(ceil_div(100 * (target - soc).max(0), settings.ceff))).unwrap_or(0);
                soc += grid_charge * settings.ceff / 100;
                export_drawn = if arbitrage && period == peak_period && pv_charge == 0 {
                    ceil_div(100 * (settings.export - pv_export), settings.deff)
                        .min(settings.discharge - load_drawn).min((soc - reserve).max(0))
                } else { 0 };
                battery_export = export_drawn * settings.deff / 100;
                soc -= export_drawn;
            }
            let import = grid_load + grid_charge;
            let export = pv_export + battery_export;
            records.push(Record {
                period, load, pv, charge: pv_charge + grid_charge, discharge: battery_load + battery_export,
                drawn: load_drawn + export_drawn, soc, import, export, curtailed, shortfall,
                loss: pv_charge - pv_stored + grid_charge - grid_charge * settings.ceff / 100
                    + load_drawn - battery_load + export_drawn - battery_export,
                flows: [direct, pv_charge, pv_export, curtailed, battery_load, battery_export, grid_load, grid_charge],
                import_cost: import * tariff.prices[period] / 100000, income: export * settings.feedin / 100000,
            });
        }
        let totals = Totals::of(&records);
        let peak = records.iter().map(|record| record.import).max().unwrap();
        let demand_charge = peak * settings.demand / 1000;
        let bill = totals.net_cost() + settings.fixed + demand_charge;
        Self { strategy, settings, tariff: tariff.clone(), records, starting, reserve, totals, peak, demand_charge, bill }
    }

    fn baseline(data: &Data, mut settings: Settings, tariff: &Tariff) -> Self {
        settings.capacity = 0;
        Self::run(data, settings, tariff, Strategy::SelfConsumption, None)
    }

    fn day(&self, day: usize) -> &[Record] { &self.records[(day - 1) * 24..day * 24] }

    fn last_soc(&self) -> i64 { self.records.last().unwrap().soc }

    fn period_total(&self, period: usize) -> Totals { Totals::of(self.records.iter().filter(|record| record.period == period)) }
}

struct App {
    data: Data,
    settings: Settings,
    tariff: Tariff,
    initial_settings: Settings,
    initial_tariff: Tariff,
    current: Option<Simulation>,
}

impl App {
    fn result(&self) -> Result<&Simulation, String> { self.current.as_ref().ok_or_else(|| "no run".into()) }

    fn check_day(&self, text: &str) -> Result<usize, String> {
        let day = number(text);
        if day < 1 || day > self.data.days as i64 { Err("invalid day".into()) } else { Ok(day as usize) }
    }

    fn config(&self) {
        let settings = self.settings;
        println!("BATTERY capacity {} initial {} charge {} discharge {} ceff {} deff {} reserve {} cost {}",
                 settings.capacity, settings.initial, settings.charge, settings.discharge, settings.ceff,
                 settings.deff, settings.reserve, settings.cost);
        println!("GRID export {} feedin {} fixed {} demand {}", settings.export, settings.feedin, settings.fixed, settings.demand);
        println!("SOLAR pvscale {}", settings.pvscale);
        let (cheapest, peak) = self.tariff.extremes();
        let prices = self.tariff.names.iter().zip(&self.tariff.prices).map(|(name, price)| format!("{name} {price}")).collect::<Vec<_>>().join(" ");
        println!("TARIFF {prices} cheapest {} peak {}", self.tariff.names[cheapest], self.tariff.names[peak]);
    }

    fn hourly(&self, result: &Simulation, day: usize) {
        println!("HOURLY day {day} {} strategy {}", self.data.day_names[day - 1], result.strategy.text());
        println!("hour   load     pv charge  disch    soc import export   curt");
        let records = result.day(day);
        for (hour, record) in records.iter().enumerate() {
            println!("{hour:>4}{:>7}{:>7}{:>7}{:>7}{:>7}{:>7}{:>7}{:>7}", record.load, record.pv,
                     record.charge, record.discharge, record.soc, record.import, record.export, record.curtailed);
        }
        let total = Totals::of(records);
        println!("{:>4}{:>7}{:>7}{:>7}{:>7}{:>7}{:>7}{:>7}{:>7}", "sum", total.load, total.pv,
                 total.charge, total.discharge, "", total.import, total.export, total.curtailed);
    }

    fn daily(&self, result: &Simulation) {
        println!("DAILY strategy {}", result.strategy.text());
        println!("day name    load      pv  import  export    curt     soc      cost");
        for day in 1..=self.data.days {
            let records = result.day(day);
            let total = Totals::of(records);
            println!("{day:>3}{:>5}{:>8}{:>8}{:>8}{:>8}{:>8}{:>8}{:>10}", self.data.day_names[day - 1], total.load,
                     total.pv, total.import, total.export, total.curtailed, records[23].soc, money(total.net_cost()));
        }
        let total = &result.totals;
        println!("TOTAL load {} pv {} import {} export {} curtailed {} cost {}", total.load, total.pv,
                 total.import, total.export, total.curtailed, money(total.net_cost()));
    }

    fn bill(&self, result: &Simulation) {
        println!("BILL strategy {} days {}", result.strategy.text(), self.data.days);
        for (index, name) in result.tariff.names.iter().enumerate() {
            let total = result.period_total(index);
            println!("IMPORT {name} {} Wh {}", total.import, money(total.import_cost));
        }
        println!("EXPORT {} Wh {}", result.totals.export, money(-result.totals.income));
        println!("FIXED {}", money(result.settings.fixed));
        println!("DEMAND {} Wh {}", result.peak, money(result.demand_charge));
        println!("TOTAL {}", money(result.bill));
    }

    fn savings(&self, result: &Simulation) {
        let baseline = Simulation::baseline(&self.data, result.settings, &result.tariff);
        println!("SAVINGS strategy {}", result.strategy.text());
        for (index, name) in result.tariff.names.iter().enumerate() {
            let before = baseline.period_total(index).import_cost;
            let after = result.period_total(index).import_cost;
            println!("{name} {} -> {} saving {}", money(before), money(after), money(before - after));
        }
        for (name, before, after) in [
            ("EXPORT", -baseline.totals.income, -result.totals.income),
            ("DEMAND", baseline.demand_charge, result.demand_charge), ("TOTAL", baseline.bill, result.bill),
        ] {
            println!("{name} {} -> {} saving {}", money(before), money(after), money(before - after));
        }
    }

    fn by_period(&self, result: &Simulation) {
        println!("BYPERIOD strategy {}", result.strategy.text());
        for (index, name) in result.tariff.names.iter().enumerate() {
            let total = result.period_total(index);
            println!("{name} hours {} load {} pv {} charge {} discharge {} import {} export {}", total.hours,
                     total.load, total.pv, total.charge, total.discharge, total.import, total.export);
        }
    }

    fn day_type(&self, result: &Simulation) {
        println!("DAYTYPE strategy {}", result.strategy.text());
        for (name, weekend) in [("WEEKDAY", false), ("WEEKEND", true)] {
            let count = self.data.weekend.iter().filter(|value| **value == weekend).count() as i64;
            let total = Totals::of(result.records.iter().enumerate().filter(|(index, _)| self.data.weekend[index / 24] == weekend).map(|(_, record)| record));
            println!("{name} days {count} load {} pv {} import {} export {} cost {}", total.load / count, total.pv / count,
                     total.import / count, total.export / count, money(total.net_cost() / count));
        }
    }

    fn peaks(&self, result: &Simulation, count: usize) {
        let mut records: Vec<(usize, &Record)> = result.records.iter().enumerate().filter(|(_, record)| record.import > 0).collect();
        records.sort_by_key(|(index, record)| (-record.import, *index));
        println!("PEAKS strategy {}", result.strategy.text());
        if records.is_empty() { println!("none"); }
        for (rank, (index, record)) in records.into_iter().take(count).enumerate() {
            println!("{}. day {} hour {} {} import {} load {} soc {}", rank + 1, index / 24 + 1, index % 24,
                     result.tariff.names[record.period], record.import, record.load, record.soc);
        }
    }

    fn profile(&self, result: &Simulation) {
        println!("PROFILE strategy {} days {}", result.strategy.text(), self.data.days);
        println!("hour   load     pv import export    soc");
        let days = self.data.days as i64;
        for hour in 0..24 {
            let total = Totals::of(result.records.iter().skip(hour).step_by(24));
            println!("{hour:>4}{:>7}{:>7}{:>7}{:>7}{:>7}", total.load / days, total.pv / days,
                     total.import / days, total.export / days, total.soc / days);
        }
    }

    fn flows(&self, result: &Simulation) {
        println!("FLOWS strategy {}", result.strategy.text());
        for (name, value) in FLOWS.iter().zip(result.totals.flows) { println!("{name} {value}"); }
        println!("LOSSES {}", result.totals.loss);
        println!("STORED {}", result.last_soc() - result.starting);
    }

    fn cycles(&self, result: &Simulation) {
        let drawn = result.totals.drawn;
        let capacity = result.settings.capacity;
        let (mut divisor, mut remainder) = (drawn, capacity);
        while remainder != 0 { (divisor, remainder) = (remainder, divisor % remainder); }
        let cycles = 1000 * drawn / capacity;
        println!("CYCLES {}/{} {}.{:03} drawn {drawn} losses {}", drawn / divisor, capacity / divisor,
                 cycles / 1000, cycles % 1000, result.totals.loss);
    }

    fn usage(&self, result: &Simulation) {
        let (mut charging, mut discharging, mut idle, mut full, mut low) = (0, 0, 0, 0, 0);
        let (mut run, mut longest, mut start) = (0, 0, 0);
        for (index, record) in result.records.iter().enumerate() {
            if record.charge > 0 { charging += 1; }
            if record.drawn > 0 { discharging += 1; }
            if record.charge == 0 && record.drawn == 0 { idle += 1; }
            if record.soc == result.settings.capacity { full += 1; }
            if record.soc <= result.reserve {
                low += 1;
                run += 1;
                if run > longest { longest = run; start = index + 1 - run; }
            } else { run = 0; }
        }
        println!("USAGE charging {charging} discharging {discharging} idle {idle} full {full} low {low} longest {longest}{}",
                 if longest == 0 { String::new() } else { format!(" from day {} hour {}", start / 24 + 1, start % 24) });
    }

    fn histogram(&self, result: &Simulation) {
        let mut bands = [0; 10];
        for record in &result.records { bands[(10 * record.soc / result.settings.capacity).min(9) as usize] += 1; }
        println!("HISTOGRAM strategy {}", result.strategy.text());
        for (index, count) in bands.iter().enumerate() {
            println!("{:>3}% {} {count}", index * 10, bar(20 * count / result.records.len() as i64));
        }
    }

    fn chart(&self, result: &Simulation, day: usize) {
        println!("CHART day {day} {} strategy {}", self.data.day_names[day - 1], result.strategy.text());
        for (hour, record) in result.day(day).iter().enumerate() {
            println!("{hour:>2} {} {}%", bar(20 * record.soc / result.settings.capacity), percentage(record.soc, result.settings.capacity));
        }
    }

    fn outage(&self, result: &Simulation, day: usize, start: usize, end: usize) {
        let outage = Simulation::run(&self.data, result.settings, &result.tariff, result.strategy, Some((day, start, end)));
        let first = (day - 1) * 24 + start;
        let before = if first == 0 { outage.starting } else { outage.records[first - 1].soc };
        println!("OUTAGE day {day} hours {start}-{end} strategy {} soc {before}", result.strategy.text());
        println!("hour   load     pv  disch    soc  short   curt");
        for hour in start..=end {
            let record = &outage.day(day)[hour];
            println!("{hour:>4}{:>7}{:>7}{:>7}{:>7}{:>7}{:>7}", record.load, record.pv, record.discharge,
                     record.soc, record.shortfall, record.curtailed);
        }
        let total = Totals::of(&outage.day(day)[start..=end]);
        println!("TOTAL load {} unserved {} served {}% bill {}", total.load, total.shortfall,
                 if total.load == 0 { "100.00".into() } else { percentage(total.load - total.shortfall, total.load) }, money(outage.bill));
    }

    fn diff(&self, result: &Simulation, day: usize, strategy: Strategy) {
        let comparison = Simulation::run(&self.data, result.settings, &result.tariff, strategy, None);
        println!("DIFF day {day} {} {} vs {}", self.data.day_names[day - 1], result.strategy.text(), strategy.text());
        println!("hour   imp1   imp2   exp1   exp2   soc1   soc2");
        for (hour, (first, second)) in result.day(day).iter().zip(comparison.day(day)).enumerate() {
            println!("{hour:>4}{:>7}{:>7}{:>7}{:>7}{:>7}{:>7}", first.import, second.import, first.export,
                     second.export, first.soc, second.soc);
        }
        let first = Totals::of(result.day(day)).net_cost();
        let second = Totals::of(comparison.day(day)).net_cost();
        println!("TOTAL cost1 {} cost2 {} difference {}", money(first), money(second), money(second - first));
    }

    fn command(&mut self, tokens: &[&str]) -> Result<(), String> {
        let a = &tokens[1..];
        match tokens[0] {
            "RUN" => {
                let strategy = Strategy::parse_one(a)?;
                let result = Simulation::run(&self.data, self.settings, &self.tariff, strategy, None);
                println!("RUN {} bill {} import {} export {} soc {}", strategy.text(), money(result.bill),
                         result.totals.import, result.totals.export, result.last_soc());
                self.current = Some(result);
            }
            "SET" => {
                arity(a, 2)?;
                let (low, high) = bounds(a[0])?;
                let value = number(a[1]);
                if value < low || value > high { return Err(format!("invalid value for {}", a[0])); }
                let old = self.settings.set(a[0], value);
                println!("SET {} {old} -> {value}", a[0]);
            }
            "PRICE" => {
                arity(a, 2)?;
                let index = self.tariff.names.iter().position(|name| name == a[0]).ok_or_else(|| format!("unknown period {}", a[0]))?;
                let price = number(a[1]);
                if !(0..=10000).contains(&price) { return Err(format!("invalid value for {}", a[0])); }
                let old = std::mem::replace(&mut self.tariff.prices[index], price);
                let (cheapest, peak) = self.tariff.extremes();
                println!("PRICE {} {old} -> {price} cheapest {} peak {}", a[0], self.tariff.names[cheapest], self.tariff.names[peak]);
            }
            "RESET" => {
                arity(a, 0)?;
                self.settings = self.initial_settings;
                self.tariff = self.initial_tariff.clone();
                println!("RESET");
            }
            "CONFIG" => { arity(a, 0)?; self.config(); }
            "NOBATTERY" => {
                arity(a, 0)?;
                let result = Simulation::baseline(&self.data, self.settings, &self.tariff);
                println!("NOBATTERY bill {} import {} export {} curtailed {} peak {}", money(result.bill), result.totals.import,
                         result.totals.export, result.totals.curtailed, result.peak);
            }
            "COMPARE" => {
                let strategies = Strategy::parse_sequence(a)?;
                if strategies.is_empty() { return Err("wrong number of arguments".into()); }
                let baseline = Simulation::baseline(&self.data, self.settings, &self.tariff).bill;
                let mut outcomes = Vec::new();
                for (index, strategy) in strategies.iter().enumerate() {
                    let result = Simulation::run(&self.data, self.settings, &self.tariff, *strategy, None);
                    outcomes.push((result.bill, index, result.totals.sufficiency()));
                }
                outcomes.sort_by_key(|(bill, index, _)| (*bill, *index));
                println!("COMPARE baseline {}", money(baseline));
                for (rank, (bill, index, sufficiency)) in outcomes.into_iter().enumerate() {
                    println!("{}. {} bill {} saving {} sufficiency {sufficiency}%", rank + 1, strategies[index].text(), money(bill), money(baseline - bill));
                }
            }
            "SIZE" => {
                arity(a, 3)?;
                let (low, high, step) = (number(a[0]), number(a[1]), number(a[2]));
                check_range(low, high, step, 1, 100000)?;
                let baseline = Simulation::baseline(&self.data, self.settings, &self.tariff).bill;
                let mut best = None;
                let mut capacity = low;
                while capacity <= high {
                    let settings = Settings { capacity, ..self.settings };
                    let result = Simulation::run(&self.data, settings, &self.tariff, Strategy::SelfConsumption, None);
                    let saving = baseline - result.bill;
                    let cost = capacity * settings.cost / 1000;
                    let payback = if saving > 0 {
                        let tenths = 10 * cost / saving;
                        if best.is_none_or(|(old_cost, old_saving, _)| cost * old_saving < old_cost * saving) {
                            best = Some((cost, saving, capacity));
                        }
                        format!("{}.{:01}", tenths / 10, tenths % 10)
                    } else { "never".into() };
                    println!("SIZE {capacity} bill {} saving {} cost {} payback {payback}", money(result.bill), money(saving), money(cost));
                    capacity += step;
                }
                println!("BEST {}", best.map(|(_, _, capacity)| capacity.to_string()).unwrap_or_else(|| "none".into()));
            }
            "SWEEP" => {
                if a.len() < 5 { return Err("wrong number of arguments".into()); }
                let (minimum, maximum) = bounds(a[0])?;
                let (low, high, step) = (number(a[1]), number(a[2]), number(a[3]));
                check_range(low, high, step, minimum, maximum)?;
                let strategy = Strategy::parse_one(&a[4..])?;
                let mut best = None;
                let mut value = low;
                while value <= high {
                    let mut settings = self.settings;
                    settings.set(a[0], value);
                    let result = Simulation::run(&self.data, settings, &self.tariff, strategy, None);
                    let baseline = Simulation::baseline(&self.data, settings, &self.tariff).bill;
                    println!("SWEEP {} {value} bill {} saving {} sufficiency {}%", a[0], money(result.bill), money(baseline - result.bill), result.totals.sufficiency());
                    if best.is_none_or(|(bill, _)| result.bill < bill) { best = Some((result.bill, value)); }
                    value += step;
                }
                println!("BEST {}", best.unwrap().1);
            }
            "OUTAGE" => {
                arity(a, 3)?;
                let day = self.check_day(a[0])?;
                let (start, end) = (number(a[1]), number(a[2]));
                if start < 0 || start > end || end > 23 { return Err("invalid hours".into()); }
                self.outage(self.result()?, day, start as usize, end as usize);
            }
            "DIFF" => {
                if a.len() < 2 { return Err("wrong number of arguments".into()); }
                let day = self.check_day(a[0])?;
                let strategy = Strategy::parse_one(&a[1..])?;
                self.diff(self.result()?, day, strategy);
            }
            "HOURLY" | "CHART" => {
                arity(a, 1)?;
                let day = self.check_day(a[0])?;
                let result = self.result()?;
                if tokens[0] == "HOURLY" { self.hourly(result, day); } else { self.chart(result, day); }
            }
            "PEAKS" => {
                arity(a, 1)?;
                let count = number(a[0]);
                if count < 1 { return Err("invalid count".into()); }
                self.peaks(self.result()?, count as usize);
            }
            "DAILY" | "BILL" | "SAVINGS" | "BYPERIOD" | "DAYTYPE" | "PROFILE" | "FLOWS" | "SELFSUFF" | "CYCLES" | "USAGE" | "HISTOGRAM" => {
                arity(a, 0)?;
                let result = self.result()?;
                match tokens[0] {
                    "DAILY" => self.daily(result), "BILL" => self.bill(result), "SAVINGS" => self.savings(result),
                    "BYPERIOD" => self.by_period(result), "DAYTYPE" => self.day_type(result), "PROFILE" => self.profile(result),
                    "FLOWS" => self.flows(result), "CYCLES" => self.cycles(result), "USAGE" => self.usage(result),
                    "HISTOGRAM" => self.histogram(result),
                    "SELFSUFF" => println!("SELFSUFF sufficiency {}% consumption {}%", result.totals.sufficiency(),
                        percentage(result.totals.flows[0] + result.totals.flows[1], result.totals.pv)),
                    _ => unreachable!(),
                }
            }
            _ => return Err(format!("unknown command {}", tokens[0])),
        }
        Ok(())
    }
}

fn tokens<'a>(lines: &mut std::str::Lines<'a>) -> Vec<&'a str> {
    lines.next().unwrap().split_ascii_whitespace().collect()
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let battery = tokens(&mut lines);
    let grid = tokens(&mut lines);
    let settings = Settings {
        capacity: number(battery[1]), initial: number(battery[2]), charge: number(battery[3]), discharge: number(battery[4]),
        ceff: number(battery[5]), deff: number(battery[6]), reserve: number(battery[7]), cost: number(battery[8]),
        export: number(grid[1]), feedin: number(grid[2]), fixed: number(grid[3]), demand: number(grid[4]), pvscale: 100,
    };
    let count = number(tokens(&mut lines)[1]) as usize;
    let mut tariff = Tariff { names: Vec::new(), prices: Vec::new() };
    for _ in 0..count {
        let parts = tokens(&mut lines);
        tariff.names.push(parts[0].into());
        tariff.prices.push(number(parts[1]));
    }
    let mut divisions = [[0; 24]; 2];
    for division in &mut divisions {
        let parts = tokens(&mut lines);
        for position in (1..parts.len()).step_by(2) {
            let start = number(parts[position]) as usize;
            let end = if position + 2 < parts.len() { number(parts[position + 2]) as usize } else { 24 };
            let period = tariff.names.iter().position(|name| name == parts[position + 1]).unwrap();
            division[start..end].fill(period);
        }
    }
    let count = number(tokens(&mut lines)[1]) as usize;
    let mut loads = BTreeMap::new();
    let mut generation = BTreeMap::new();
    for _ in 0..count {
        let parts = tokens(&mut lines);
        let values: Vec<i64> = parts[2..].iter().map(|text| number(text)).collect();
        let profiles = if parts[0] == "LOAD" { &mut loads } else { &mut generation };
        profiles.insert(parts[1].to_string(), values);
    }
    let days = number(tokens(&mut lines)[1]) as usize;
    let mut load = Vec::new();
    let mut pv = Vec::new();
    for _ in 0..days {
        let parts = tokens(&mut lines);
        let (load_pct, pv_pct) = (number(parts[1]), number(parts[3]));
        for hour in 0..24 {
            load.push(loads[parts[0]][hour] * load_pct / 100);
            pv.push(generation[parts[2]][hour] * pv_pct / 100);
        }
    }
    let parts = tokens(&mut lines);
    let mut holidays = vec![false; days];
    for day in &parts[2..] { holidays[number(day) as usize - 1] = true; }
    let mut data = Data { days, load, pv, periods: Vec::new(), weekend: Vec::new(), day_names: Vec::new() };
    for (day, holiday) in holidays.iter().enumerate() {
        let weekend = *holiday || day % 7 >= 5;
        data.weekend.push(weekend);
        data.day_names.push(if *holiday { "HOL" } else { DAY_NAMES[day % 7] });
        data.periods.extend_from_slice(&divisions[usize::from(weekend)]);
    }
    let count = number(tokens(&mut lines)[1]) as usize;
    for _ in 0..count {
        let parts = tokens(&mut lines);
        let index = (number(parts[0]) as usize - 1) * 24 + number(parts[1]) as usize;
        data.load[index] = number(parts[2]);
        data.pv[index] = number(parts[3]);
    }
    let mut app = App { data, settings, initial_settings: settings, initial_tariff: tariff.clone(), tariff, current: None };
    for line in lines {
        let parts: Vec<&str> = line.split_ascii_whitespace().collect();
        if parts[0] == "END" { break; }
        if let Err(error) = app.command(&parts) { println!("ERROR {error}"); }
    }
}
