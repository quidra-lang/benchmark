use std::collections::{BTreeMap, VecDeque};
use std::io::{self, Read};

const STAGES: [&str; 4] = ["RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY"];

fn number(text: &str) -> i64 {
    text.parse().unwrap()
}

fn money(value: i64) -> String {
    format!("{}.{:02}", value / 100, value % 100)
}

fn decimal(numerator: i64, denominator: i64, places: usize) -> String {
    let scale = 10_i64.pow(places as u32);
    let value = numerator * scale / denominator;
    format!("{}.{:0width$}", value / scale, value % scale, width = places)
}

fn ratio(numerator: i64, denominator: i64, places: usize) -> String {
    if denominator == 0 { "n/a".into() } else { decimal(numerator, denominator, places) }
}

fn stage_index(name: &str) -> Result<usize, String> {
    STAGES.iter().position(|stage| *stage == name).ok_or_else(|| format!("unknown stage {name}"))
}

fn targets(name: &str) -> Result<Vec<usize>, String> {
    if name == "ALL" { Ok((0..4).collect()) } else { Ok(vec![stage_index(name)?]) }
}

fn capacity_text(capacity: Option<i64>) -> String {
    capacity.map(|value| value.to_string()).unwrap_or_else(|| "OFF".into())
}

fn pipeline_text(pipeline: &VecDeque<i64>) -> String {
    pipeline.iter().map(ToString::to_string).collect::<Vec<_>>().join(",")
}

fn range(args: &[&str], limit: usize) -> Result<(usize, usize), String> {
    if args.is_empty() { return Ok((1, limit)); }
    let (from, to) = (number(args[0]) as usize, number(args[1]) as usize);
    if from < 1 || from > to || to > limit {
        Err(format!("bad range {} {}", args[0], args[1]))
    } else {
        Ok((from, to))
    }
}

fn variation(values: &[i64]) -> i64 {
    let sum: i64 = values.iter().sum();
    values.len() as i64 * values.iter().map(|value| value * value).sum::<i64>() - sum * sum
}

#[derive(Clone, Copy)]
enum Rule {
    Fixed(i64),
    Pass,
    BaseStock(i64),
    MinMax(i64, i64),
    MovingAverage(usize, i64),
    Smooth(i64, i64),
    Sterman(i64, i64, i64, i64),
}

#[derive(Clone)]
struct Policy {
    rule: Rule,
    text: String,
}

impl Policy {
    fn parse(tokens: &[&str]) -> Result<Self, String> {
        let name = tokens[0];
        let count = match name {
            "PASS" => 0,
            "FIXED" | "BASESTOCK" => 1,
            "MINMAX" | "MOVAVG" | "SMOOTH" => 2,
            "STERMAN" => 4,
            _ => return Err(format!("unknown policy {name}")),
        };
        if tokens.len() != count + 1 { return Err(format!("{name} needs {count} parameters")); }
        let values: Vec<i64> = tokens[1..].iter().enumerate().map(|(index, text)| {
            if name == "STERMAN" && index < 3 {
                let (whole, fraction) = text.split_once('.').unwrap();
                number(whole) * 100 + number(fraction)
            } else { number(text) }
        }).collect();
        let valid = match name {
            "FIXED" => values[0] <= 1000,
            "BASESTOCK" => values[0] <= 10000,
            "MINMAX" => values[0] < values[1] && values[1] <= 10000,
            "MOVAVG" => (1..=52).contains(&values[0]) && values[1] <= 10000,
            "SMOOTH" => (1..=10).contains(&values[0]) && values[1] <= 10000,
            "STERMAN" => values[..3].iter().all(|value| *value <= 100) && values[3] <= 10000,
            _ => true,
        };
        if !valid { return Err(format!("invalid parameter for {name}")); }
        let rule = match name {
            "FIXED" => Rule::Fixed(values[0]),
            "PASS" => Rule::Pass,
            "BASESTOCK" => Rule::BaseStock(values[0]),
            "MINMAX" => Rule::MinMax(values[0], values[1]),
            "MOVAVG" => Rule::MovingAverage(values[0] as usize, values[1]),
            "SMOOTH" => Rule::Smooth(values[0], values[1]),
            _ => Rule::Sterman(values[0], values[1], values[2], values[3]),
        };
        Ok(Self { rule, text: tokens.join(" ") })
    }

    fn base_stock(level: i64) -> Self {
        Self { rule: Rule::BaseStock(level), text: format!("BASESTOCK {level}") }
    }
}

struct Configuration {
    inventory: i64,
    quantity: i64,
    shipping_delay: usize,
    order_delay: usize,
    holding: i64,
    backlog_rate: i64,
    policy: Policy,
}

#[derive(Clone, Copy, Default)]
struct Record {
    received: i64,
    incoming: i64,
    shipped: i64,
    previous_backlog: i64,
    on_time: i64,
    inventory: i64,
    backlog: i64,
    order: i64,
    holding_cost: i64,
    backlog_cost: i64,
    cost: i64,
}

impl Record {
    fn value(self, kind: &str) -> i64 {
        match kind {
            "ORDERS" => self.order,
            "INV" => self.inventory,
            "BACK" => self.backlog,
            _ => self.inventory - self.backlog,
        }
    }
}

#[derive(Clone)]
struct Stage {
    inventory: i64,
    backlog: i64,
    shipping: VecDeque<i64>,
    orders: VecDeque<i64>,
    shipping_delay: usize,
    order_delay: usize,
    policy: Policy,
    expected: i64,
    holding: i64,
    backlog_rate: i64,
    lot: i64,
    capacity: Option<i64>,
    records: Vec<Record>,
}

impl Stage {
    fn new(config: &Configuration) -> Self {
        Self {
            inventory: config.inventory, backlog: 0,
            shipping: vec![config.quantity; config.shipping_delay].into(),
            orders: vec![config.quantity; config.order_delay].into(),
            shipping_delay: config.shipping_delay, order_delay: config.order_delay,
            policy: config.policy.clone(), expected: config.quantity * 100,
            holding: config.holding, backlog_rate: config.backlog_rate,
            lot: 1, capacity: None, records: Vec::new(),
        }
    }

    fn costs(&self) -> [i64; 3] {
        let holding = self.records.iter().map(|record| record.holding_cost).sum();
        let backlog = self.records.iter().map(|record| record.backlog_cost).sum();
        [holding, backlog, holding + backlog]
    }

    fn fill_rate(&self) -> String {
        let incoming: i64 = self.records.iter().map(|record| record.incoming).sum();
        let on_time: i64 = self.records.iter().map(|record| record.on_time).sum();
        if incoming == 0 { "n/a".into() } else { format!("{}%", decimal(on_time * 100, incoming, 2)) }
    }
}

#[derive(Clone)]
struct Plant {
    backlog: i64,
    capacity: Option<i64>,
    records: Vec<(i64, i64, i64)>,
}

#[derive(Clone)]
struct Simulation {
    week: usize,
    stages: Vec<Stage>,
    plant: Plant,
    visible: bool,
    demand: Vec<i64>,
}

impl Simulation {
    fn new(configs: &[Configuration], demand: Vec<i64>) -> Self {
        Self { week: 0, stages: configs.iter().map(Stage::new).collect(),
               plant: Plant { backlog: 0, capacity: None, records: Vec::new() }, visible: false, demand }
    }

    fn require_weeks(&self) -> Result<(), String> {
        if self.week == 0 { Err("no weeks simulated".into()) } else { Ok(()) }
    }

    fn signal(&self, index: usize, week: usize) -> i64 {
        if self.visible { self.demand[week - 1] } else { self.stages[index].records[week - 1].incoming }
    }

    fn position(&self, index: usize) -> (i64, i64) {
        let stage = &self.stages[index];
        let upstream = if index == 3 { self.plant.backlog } else { self.stages[index + 1].backlog };
        let supply = stage.orders.iter().sum::<i64>() + upstream + stage.shipping.iter().sum::<i64>();
        (supply, stage.inventory + supply - stage.backlog)
    }

    fn step(&mut self) {
        let mut records = [Record::default(); 4];
        for (stage, record) in self.stages.iter_mut().zip(&mut records) {
            record.received = stage.shipping.pop_front().unwrap();
            stage.inventory += record.received;
        }
        let mut incoming = [0; 5];
        incoming[0] = self.demand[self.week];
        for (index, stage) in self.stages.iter_mut().enumerate() {
            incoming[index + 1] = stage.orders.pop_front().unwrap();
        }
        for index in 0..4 {
            let stage = &mut self.stages[index];
            let record = &mut records[index];
            record.incoming = incoming[index];
            record.previous_backlog = stage.backlog;
            let requested = stage.backlog + record.incoming;
            record.shipped = stage.inventory.min(requested).min(stage.capacity.unwrap_or(i64::MAX));
            record.on_time = (record.shipped - stage.backlog).max(0).min(record.incoming);
            stage.inventory -= record.shipped;
            stage.backlog = requested - record.shipped;
            record.inventory = stage.inventory;
            record.backlog = stage.backlog;
            if index > 0 { self.stages[index - 1].shipping.push_back(record.shipped); }
        }
        let requested = self.plant.backlog + incoming[4];
        let produced = requested.min(self.plant.capacity.unwrap_or(i64::MAX));
        self.plant.backlog = requested - produced;
        self.plant.records.push((incoming[4], produced, self.plant.backlog));
        self.stages[3].shipping.push_back(produced);

        let positions: Vec<(i64, i64)> = (0..4).map(|index| self.position(index)).collect();
        for index in 0..4 {
            let (supply, position) = positions[index];
            let signal = if self.visible { incoming[0] } else { incoming[index] };
            let stage = &self.stages[index];
            let order = match stage.policy.rule {
                Rule::Fixed(quantity) => quantity,
                Rule::Pass => incoming[index],
                Rule::BaseStock(level) => (level - position).max(0),
                Rule::MinMax(low, high) => if position <= low { high - position } else { 0 },
                Rule::MovingAverage(window, level) => {
                    let count = window.min(self.week + 1);
                    let sum = signal + (self.week + 2 - count..=self.week)
                        .map(|week| self.signal(index, week)).sum::<i64>();
                    let forecast = sum / count as i64;
                    (level + forecast * (stage.shipping_delay + stage.order_delay) as i64 - position).max(0)
                }
                Rule::Smooth(window, level) => (signal + (level - position).div_euclid(window)).max(0),
                Rule::Sterman(theta, alpha, beta, target) => {
                    let expected = (100 * theta * signal + (100 - theta) * stage.expected) / 100;
                    let net = stage.inventory - stage.backlog;
                    let order = (100 * expected + alpha * (100 * (target - net) - beta * supply))
                        .div_euclid(10000).max(0);
                    self.stages[index].expected = expected;
                    order
                }
            };
            let stage = &mut self.stages[index];
            let record = &mut records[index];
            record.order = (order + stage.lot - 1) / stage.lot * stage.lot;
            stage.orders.push_back(record.order);
            record.holding_cost = stage.holding * stage.inventory;
            record.backlog_cost = stage.backlog_rate * stage.backlog;
            record.cost = record.holding_cost + record.backlog_cost;
        }
        for (stage, record) in self.stages.iter_mut().zip(records) { stage.records.push(record); }
        self.week += 1;
    }

    fn total_cost(&self) -> i64 {
        self.stages.iter().map(|stage| stage.costs()[2]).sum()
    }

    fn status(&self) {
        println!("STATUS week {} of {}", self.week, self.demand.len());
        for (index, stage) in self.stages.iter().enumerate() {
            let (supply, position) = self.position(index);
            println!("{} inv {} back {} transit {} pending {} supply {supply} position {position} policy {}{}",
                     STAGES[index], stage.inventory, stage.backlog, pipeline_text(&stage.shipping),
                     pipeline_text(&stage.orders), stage.policy.text,
                     if matches!(stage.policy.rule, Rule::Sterman(..)) { format!(" expect {}", money(stage.expected)) }
                     else { String::new() });
        }
        println!("PLANT back {}", self.plant.backlog);
    }

    fn settings(&self) {
        println!("SETTINGS");
        for (name, stage) in STAGES.iter().zip(&self.stages) {
            println!("{name} holding {} backlog {} batch {} capacity {} delays {} {}", stage.holding,
                     stage.backlog_rate, stage.lot, capacity_text(stage.capacity), stage.shipping_delay, stage.order_delay);
        }
        println!("PLANT capacity {}", capacity_text(self.plant.capacity));
        println!("VISIBILITY {}", if self.visible { "ON" } else { "OFF" });
    }

    fn show_week(&self, week: usize) {
        println!("WEEK {week} demand {}", self.demand[week - 1]);
        for (name, stage) in STAGES.iter().zip(&self.stages) {
            let record = stage.records[week - 1];
            println!("{name} recv {} in {} ship {} inv {} back {} order {} cost {}", record.received,
                     record.incoming, record.shipped, record.inventory, record.backlog, record.order, money(record.cost));
        }
        let (incoming, made, backlog) = self.plant.records[week - 1];
        println!("PLANT in {incoming} made {made} back {backlog}");
    }

    fn costs(&self) {
        println!("COSTS week {}", self.week);
        let mut totals = [0; 3];
        for (name, stage) in STAGES.iter().zip(&self.stages) {
            let costs = stage.costs();
            println!("{name} holding {} backlog {} total {}", money(costs[0]), money(costs[1]), money(costs[2]));
            for (total, cost) in totals.iter_mut().zip(costs) { *total += cost; }
        }
        println!("TOTAL holding {} backlog {} total {}", money(totals[0]), money(totals[1]), money(totals[2]));
    }

    fn summary(&self) {
        println!("SUMMARY weeks 1-{}", self.week);
        for (name, stage) in STAGES.iter().zip(&self.stages) {
            let inventory = stage.records.iter().map(|record| record.inventory).sum();
            let backlog = stage.records.iter().map(|record| record.backlog).sum();
            let orders: Vec<i64> = stage.records.iter().map(|record| record.order).collect();
            println!("{name} avg_inv {} avg_back {} orders {} min {} max {} zero_weeks {}",
                     decimal(inventory, self.week as i64, 2), decimal(backlog, self.week as i64, 2),
                     orders.iter().sum::<i64>(), orders.iter().min().unwrap(), orders.iter().max().unwrap(),
                     orders.iter().filter(|order| **order == 0).count());
        }
    }

    fn fill_rates(&self) {
        println!("FILLRATE weeks 1-{}", self.week);
        for (name, stage) in STAGES.iter().zip(&self.stages) {
            let on_time: i64 = stage.records.iter().map(|record| record.on_time).sum();
            let incoming: i64 = stage.records.iter().map(|record| record.incoming).sum();
            let stockouts = stage.records.iter().filter(|record| record.backlog > 0).count();
            println!("{name} fill {} ontime {on_time} ordered {incoming} stockout_weeks {stockouts} service {}%",
                     stage.fill_rate(), decimal((self.week - stockouts) as i64 * 100, self.week as i64, 2));
        }
    }

    fn bullwhip(&self) {
        let n = self.week as i64;
        let demand = &self.demand[..self.week];
        let demand_variation = variation(demand);
        let mut previous = demand_variation;
        println!("BULLWHIP weeks 1-{n} demand mean {} var {}", decimal(demand.iter().sum(), n, 4),
                 decimal(demand_variation, n * n, 4));
        for (name, stage) in STAGES.iter().zip(&self.stages) {
            let orders: Vec<i64> = stage.records.iter().map(|record| record.order).collect();
            let current = variation(&orders);
            println!("{name} mean {} var {} ratio {} step {}", decimal(orders.iter().sum(), n, 4),
                     decimal(current, n * n, 4), ratio(current, demand_variation, 4), ratio(current, previous, 4));
            previous = current;
        }
    }

    fn peaks(&self) {
        println!("PEAKS weeks 1-{}", self.week);
        for (name, stage) in STAGES.iter().zip(&self.stages) {
            let (mut max_inventory, mut inventory_week, mut max_backlog, mut backlog_week) = (0, 0, 0, 0);
            let (mut run, mut longest, mut end) = (0, 0, 0);
            for (index, record) in stage.records.iter().enumerate() {
                if record.inventory > max_inventory { max_inventory = record.inventory; inventory_week = index + 1; }
                if record.backlog > max_backlog { max_backlog = record.backlog; backlog_week = index + 1; }
                run = if record.backlog > 0 { run + 1 } else { 0 };
                if run > longest { longest = run; end = index + 1; }
            }
            println!("{name} max_inv {max_inventory} week {} max_back {max_backlog} week {} longest_stockout {}",
                     if inventory_week == 0 { "-".into() } else { inventory_week.to_string() },
                     if backlog_week == 0 { "-".into() } else { backlog_week.to_string() },
                     if longest == 0 { "0".into() } else { format!("{longest} weeks {}-{end}", end + 1 - longest) });
        }
    }
}

struct Game {
    configs: Vec<Configuration>,
    base_demand: Vec<i64>,
    current: Simulation,
    saved: BTreeMap<String, Simulation>,
}

impl Game {
    fn reset(&mut self) {
        self.current = Simulation::new(&self.configs, self.base_demand.clone());
    }

    fn set_demand(&mut self, demand: Vec<i64>) {
        self.base_demand = demand;
        self.reset();
        let demand = &self.current.demand;
        println!("DEMAND weeks {} total {} min {} max {}", demand.len(), demand.iter().sum::<i64>(),
                 demand.iter().min().unwrap(), demand.iter().max().unwrap());
    }

    fn trial(&self, policies: &[Policy]) -> Simulation {
        let mut trial = Simulation::new(&self.configs, self.current.demand.clone());
        trial.visible = self.current.visible;
        trial.plant.capacity = self.current.plant.capacity;
        for (index, stage) in trial.stages.iter_mut().enumerate() {
            let live = &self.current.stages[index];
            stage.policy = policies[index].clone();
            stage.lot = live.lot;
            stage.capacity = live.capacity;
            stage.holding = live.holding;
            stage.backlog_rate = live.backlog_rate;
        }
        while trial.week < trial.demand.len() { trial.step(); }
        trial
    }

    fn balance(&self) {
        let simulation = &self.current;
        println!("BALANCE week {}", simulation.week);
        for (index, stage) in simulation.stages.iter().enumerate() {
            let received: i64 = stage.records.iter().map(|record| record.received).sum();
            let shipped: i64 = stage.records.iter().map(|record| record.shipped).sum();
            println!("{} start {} received {received} shipped {shipped} end {} owed {}",
                     STAGES[index], self.configs[index].inventory, stage.inventory, stage.backlog);
        }
        let initial: i64 = self.configs.iter().map(|config| config.inventory + config.quantity * config.shipping_delay as i64).sum();
        let produced: i64 = simulation.plant.records.iter().map(|record| record.1).sum();
        let delivered: i64 = simulation.stages[0].records.iter().map(|record| record.shipped).sum();
        let stock: i64 = simulation.stages.iter().map(|stage| stage.inventory).sum();
        let transit: i64 = simulation.stages.iter().map(|stage| stage.shipping.iter().sum::<i64>()).sum();
        println!("SYSTEM initial {initial} produced {produced} delivered {delivered} stock {stock} transit {transit}");
    }

    fn lead_time(&self, index: usize) {
        let stage = &self.current.stages[index];
        let nominal = stage.shipping_delay + stage.order_delay;
        let mut received = -(nominal as i64 * self.configs[index].quantity);
        let cumulative: Vec<i64> = stage.records.iter().map(|record| { received += record.received; received }).collect();
        let mut ordered = 0;
        let mut count = 0;
        let mut lead_times = Vec::new();
        for (week, record) in stage.records.iter().enumerate() {
            ordered += record.order;
            if record.order == 0 { continue; }
            count += 1;
            if let Some(arrival) = (week + 1..self.current.week).find(|arrival| cumulative[*arrival] >= ordered) {
                lead_times.push((arrival - week) as i64);
            }
        }
        let statistics = if lead_times.is_empty() { "min - avg - max -".into() } else {
            format!("min {} avg {} max {}", lead_times.iter().min().unwrap(),
                    decimal(lead_times.iter().sum(), lead_times.len() as i64, 2), lead_times.iter().max().unwrap())
        };
        println!("LEADTIME {} nominal {nominal} orders {count} completed {} open {} {statistics}",
                 STAGES[index], lead_times.len(), count - lead_times.len());
    }

    fn plot(&self, index: usize, kind: &str, from: usize, to: usize) {
        let values: Vec<i64> = self.current.stages[index].records[from - 1..to].iter()
            .map(|record| record.value(kind)).collect();
        let maximum = *values.iter().max().unwrap();
        if kind == "NET" {
            let minimum = *values.iter().min().unwrap();
            let magnitude = minimum.abs().max(maximum.abs());
            println!("PLOT {} NET {from}-{to} min {minimum} max {maximum}", STAGES[index]);
            for (offset, value) in values.iter().enumerate() {
                let width = if magnitude == 0 { 0 } else { (value.abs() * 25 / magnitude) as usize };
                let left = if *value < 0 { format!("{}{}", " ".repeat(25 - width), "-".repeat(width)) }
                           else { " ".repeat(25) };
                let right = if *value > 0 { "+".repeat(width) } else { String::new() };
                println!("{:>3} {left}|{right} {value}", from + offset);
            }
        } else {
            println!("PLOT {} {kind} {from}-{to} max {maximum}", STAGES[index]);
            for (offset, value) in values.iter().enumerate() {
                let width = if maximum == 0 { 0 } else { (value * 50 / maximum) as usize };
                println!("{:>3} |{} {value}", from + offset, "#".repeat(width));
            }
        }
    }

    fn command(&mut self, tokens: &[&str]) -> Result<(), String> {
        let a = &tokens[1..];
        match tokens[0] {
            "DEMAND" => self.set_demand(a.iter().map(|text| number(text)).collect()),
            "GENERATE" => {
                let weeks = number(a[0]);
                let (base, spread, mut random) = (number(a[1]), number(a[2]), number(a[3]));
                let changes: Vec<(&str, i64, i64)> = a[4..].chunks(3)
                    .map(|change| (change[0], number(change[1]), number(change[2]))).collect();
                for (_, week, _) in &changes {
                    if *week < 1 || *week > weeks { return Err(format!("week {week} outside horizon")); }
                }
                let mut demand = Vec::new();
                for week in 1..=weeks {
                    let mut level = base;
                    for (kind, start, amount) in &changes {
                        level += match *kind {
                            "STEP" if week >= *start => *amount,
                            "PULSE" if week == *start => *amount,
                            "RAMP" if week >= *start => amount * (week - start + 1),
                            _ => 0,
                        };
                    }
                    if level < 0 { return Err(format!("negative level at week {week}")); }
                    random = random * 48271 % 2147483647;
                    demand.push(level + random % spread);
                }
                self.set_demand(demand);
            }
            "RUN" => {
                let simulation = &mut self.current;
                let horizon = simulation.demand.len();
                if simulation.week == horizon { return Err(format!("horizon reached at week {horizon}")); }
                let from = simulation.week + 1;
                let to = horizon.min(simulation.week + number(a[0]) as usize);
                let mut cost = 0;
                while simulation.week < to {
                    simulation.step();
                    for (name, stage) in STAGES.iter().zip(&simulation.stages) {
                        let record = stage.records.last().unwrap();
                        cost += record.cost;
                        if record.previous_backlog == 0 && record.backlog > 0 {
                            println!("STOCKOUT {name} week {} backlog {}", simulation.week, record.backlog);
                        } else if record.previous_backlog > 0 && record.backlog == 0 {
                            println!("RECOVER {name} week {}", simulation.week);
                        }
                    }
                }
                println!("RUN {from}-{to} demand {} cost {}", simulation.demand[from - 1..to].iter().sum::<i64>(), money(cost));
                if simulation.week == horizon { println!("HORIZON {horizon}"); }
            }
            "RESET" => { self.reset(); println!("RESET week 0"); }
            "SAVE" => {
                self.saved.insert(a[0].into(), self.current.clone());
                println!("SAVE {} week {}", a[0], self.current.week);
            }
            "LOAD" => {
                let snapshot = self.saved.get(a[0]).ok_or_else(|| format!("no snapshot {}", a[0]))?;
                self.current = snapshot.clone();
                println!("LOAD {} week {}", a[0], self.current.week);
            }
            "SET" => {
                let selected = targets(a[0])?;
                let policy = Policy::parse(&a[1..])?;
                for index in selected {
                    let expected = if self.current.week == 0 { self.configs[index].quantity }
                                   else { self.current.signal(index, self.current.week) } * 100;
                    let stage = &mut self.current.stages[index];
                    stage.policy = policy.clone();
                    if matches!(policy.rule, Rule::Sterman(..)) { stage.expected = expected; }
                }
                println!("SET {} {}", a[0], policy.text);
            }
            "BATCH" => {
                let index = stage_index(a[0])?;
                let lot = number(a[1]);
                if !(1..=100).contains(&lot) { return Err(format!("invalid batch size {}", a[1])); }
                self.current.stages[index].lot = lot;
                println!("BATCH {} {lot}", a[0]);
            }
            "CAPACITY" => {
                let index = if a[0] == "PLANT" { None } else { Some(stage_index(a[0])?) };
                let capacity = if a[1] == "OFF" { None } else { Some(number(a[1])) };
                if capacity.is_some_and(|value| value > 10000) { return Err(format!("invalid capacity {}", a[1])); }
                if let Some(index) = index { self.current.stages[index].capacity = capacity; }
                else { self.current.plant.capacity = capacity; }
                println!("CAPACITY {} {}", a[0], a[1]);
            }
            "COST" => {
                let index = stage_index(a[0])?;
                let (holding, backlog) = (number(a[1]), number(a[2]));
                if holding > 1000 || backlog > 1000 { return Err("invalid cost".into()); }
                self.current.stages[index].holding = holding;
                self.current.stages[index].backlog_rate = backlog;
                println!("COST {} holding {holding} backlog {backlog}", a[0]);
            }
            "VISIBILITY" => {
                if !["ON", "OFF"].contains(&a[0]) { return Err(format!("unknown visibility {}", a[0])); }
                self.current.visible = a[0] == "ON";
                println!("VISIBILITY {}", a[0]);
            }
            "SHOCK" => {
                let week = number(a[0]) as usize;
                if week < 1 || week > self.current.demand.len() { return Err(format!("week {} outside horizon", a[0])); }
                if week <= self.current.week { return Err(format!("week {} already simulated", a[0])); }
                let demand = number(a[1]);
                println!("SHOCK week {week} {} -> {demand}", self.current.demand[week - 1]);
                self.current.demand[week - 1] = demand;
            }
            "STATUS" => self.current.status(),
            "SETTINGS" => self.current.settings(),
            "WEEK" => {
                self.current.require_weeks()?;
                let week = number(a[0]) as usize;
                if week < 1 || week > self.current.week { return Err(format!("bad week {}", a[0])); }
                self.current.show_week(week);
            }
            "TABLE" => {
                let index = stage_index(a[0])?;
                self.current.require_weeks()?;
                let (from, to) = range(&a[1..], self.current.week)?;
                println!("TABLE {} {from}-{to}", a[0]);
                println!("week     in   ship   recv    inv   back  order      cost");
                for week in from..=to {
                    let record = self.current.stages[index].records[week - 1];
                    println!("{week:>4} {:>6} {:>6} {:>6} {:>6} {:>6} {:>6} {:>9}", record.incoming,
                             record.shipped, record.received, record.inventory, record.backlog, record.order, money(record.cost));
                }
            }
            "CHAIN" => {
                self.current.require_weeks()?;
                let (from, to) = range(a, self.current.week)?;
                println!("CHAIN {from}-{to}");
                println!("{:>4} {:>6} {:>11} {:>11} {:>11} {:>11}", "week", "demand", STAGES[0], STAGES[1], STAGES[2], STAGES[3]);
                for week in from..=to {
                    println!("{week:>4} {:>6} {:>11} {:>11} {:>11} {:>11}", self.current.demand[week - 1],
                             self.current.stages[0].records[week - 1].order, self.current.stages[1].records[week - 1].order,
                             self.current.stages[2].records[week - 1].order, self.current.stages[3].records[week - 1].order);
                }
            }
            "DEMANDS" => {
                let (from, to) = range(a, self.current.demand.len())?;
                let demand = &self.current.demand[from - 1..to];
                println!("DEMANDS {from}-{to} total {} min {} max {}", demand.iter().sum::<i64>(),
                         demand.iter().min().unwrap(), demand.iter().max().unwrap());
                println!("{}", demand.iter().map(ToString::to_string).collect::<Vec<_>>().join(" "));
            }
            "COSTS" => self.current.costs(),
            "SUMMARY" => { self.current.require_weeks()?; self.current.summary(); }
            "BALANCE" => self.balance(),
            "FILLRATE" => { self.current.require_weeks()?; self.current.fill_rates(); }
            "BULLWHIP" => { self.current.require_weeks()?; self.current.bullwhip(); }
            "PEAKS" => { self.current.require_weeks()?; self.current.peaks(); }
            "LEADTIME" => {
                let index = stage_index(a[0])?;
                self.current.require_weeks()?;
                self.lead_time(index);
            }
            "PLOT" | "HISTOGRAM" => {
                let index = stage_index(a[0])?;
                let kind = a[1];
                if !["ORDERS", "INV", "BACK", "NET"].contains(&kind) { return Err(format!("unknown mode {kind}")); }
                if tokens[0] == "PLOT" {
                    self.current.require_weeks()?;
                    let (from, to) = range(&a[2..], self.current.week)?;
                    self.plot(index, kind, from, to);
                } else {
                    let width = number(a[2]);
                    if !(1..=100).contains(&width) { return Err(format!("invalid width {}", a[2])); }
                    self.current.require_weeks()?;
                    let mut bins: BTreeMap<i64, usize> = BTreeMap::new();
                    for record in &self.current.stages[index].records {
                        *bins.entry(record.value(kind).div_euclid(width)).or_default() += 1;
                    }
                    println!("HISTOGRAM {} {kind} width {width} weeks 1-{}", a[0], self.current.week);
                    for bin in *bins.first_key_value().unwrap().0..=*bins.last_key_value().unwrap().0 {
                        let count = bins.get(&bin).copied().unwrap_or(0);
                        println!("{}..{} {count}{}", bin * width, bin * width + width - 1,
                                 if count == 0 { String::new() } else { format!(" {}", "*".repeat(count)) });
                    }
                }
            }
            "COMPARE" => {
                let policies: Vec<Policy> = a.split(|token| *token == "/").map(Policy::parse).collect::<Result<_, _>>()?;
                let demand_variation = variation(&self.current.demand);
                let mut results = Vec::new();
                for (index, policy) in policies.iter().enumerate() {
                    let trial = self.trial(&vec![policy.clone(); 4]);
                    let orders: Vec<i64> = trial.stages[3].records.iter().map(|record| record.order).collect();
                    results.push((trial.total_cost(), index, trial.stages[0].fill_rate(), ratio(variation(&orders), demand_variation, 4)));
                }
                results.sort_by_key(|row| (row.0, row.1));
                println!("COMPARE {} weeks {}", policies.len(), self.current.demand.len());
                for (rank, (cost, index, fill, bullwhip)) in results.iter().enumerate() {
                    println!("{} {} total {} fill {fill} bullwhip {bullwhip}", rank + 1, policies[*index].text, money(*cost));
                }
            }
            "OPTIMIZE" => {
                let selected = targets(a[0])?;
                let (low, high) = (number(a[1]), number(a[2]));
                if low > high { return Err(format!("bad range {} {}", a[1], a[2])); }
                if high - low > 200 { return Err("range too large".into()); }
                let mut best = None;
                for level in low..=high {
                    let mut policies: Vec<Policy> = self.current.stages.iter().map(|stage| stage.policy.clone()).collect();
                    for index in &selected { policies[*index] = Policy::base_stock(level); }
                    let trial = self.trial(&policies);
                    let total = trial.total_cost();
                    let objective = if selected.len() == 4 { total } else { trial.stages[selected[0]].costs()[2] };
                    if best.is_none_or(|(cost, _, _)| objective < cost) { best = Some((objective, level, total)); }
                }
                let (objective, level, total) = best.unwrap();
                println!("OPTIMIZE {} BASESTOCK {level} cost {} total {}", a[0], money(objective), money(total));
            }
            _ => return Err(format!("unknown command {}", tokens[0])),
        }
        Ok(())
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let configs: Vec<Configuration> = (0..4).map(|_| {
        let parts: Vec<&str> = lines.next().unwrap().split_ascii_whitespace().collect();
        Configuration {
            inventory: number(parts[1]), quantity: number(parts[2]),
            shipping_delay: number(parts[3]) as usize, order_delay: number(parts[4]) as usize,
            holding: number(parts[5]), backlog_rate: number(parts[6]), policy: Policy::parse(&parts[7..]).unwrap(),
        }
    }).collect();
    let current = Simulation::new(&configs, Vec::new());
    let mut game = Game { configs, current, base_demand: Vec::new(), saved: BTreeMap::new() };
    for line in lines {
        let tokens: Vec<&str> = line.split_ascii_whitespace().collect();
        if tokens[0] == "END" { break; }
        if let Err(error) = game.command(&tokens) { println!("ERROR {error}"); }
    }
}
