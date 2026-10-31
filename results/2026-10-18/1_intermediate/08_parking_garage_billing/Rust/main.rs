use std::collections::BTreeMap;
use std::io::{self, Read};

type Result<T> = std::result::Result<T, String>;
macro_rules! reject {
    ($condition:expr, $reason:expr) => {
        if $condition {
            return Err($reason);
        }
    };
}
const TYPES: [&str; 5] = ["MOTORCYCLE", "CAR", "ECAR", "VAN", "BUS"];
const KINDS: [&str; 4] = ["MOTO", "COMPACT", "LARGE", "EV"];
const PREFERENCES: [&[usize]; 5] = [&[0, 1, 2], &[1, 2], &[3, 1, 2], &[2], &[2]];
struct Spot {
    level: usize,
    number: usize,
    kind: usize,
    vehicle: Option<usize>,
    closed: bool,
}
#[derive(Default)]
struct Vehicle {
    plate: String,
    kind: usize,
    spot: usize,
    entry: i32,
    energy: i32,
    charge: i32,
    validation: i32,
    paid: bool,
    payment: i32,
    parking: i32,
    night: i32,
}
struct Waiting {
    plate: String,
    kind: usize,
    joined: i32,
}
struct Bill {
    parking: i32,
    night: i32,
    lost: i32,
    charge: i32,
    total: i32,
    due: i32,
}
struct Record {
    entry: i32,
    exit: i32,
    kind: usize,
    total: i32,
    location: String,
    lost: bool,
}
#[derive(Clone, Copy, Default)]
struct Counts {
    entries: i32,
    exits: i32,
    refused: i32,
    revenue: i32,
    stay: i32,
}
#[derive(Clone, Copy, Default)]
struct Revenue {
    exits: i32,
    parking: i32,
    night: i32,
    lost: i32,
    charge: i32,
    total: i32,
}
#[derive(Default)]
struct Garage {
    now: i32,
    peak: usize,
    peak_time: i32,
    rates: [i32; 5],
    caps: [i32; 5],
    fees: [i32; 3],
    spots: Vec<Spot>,
    levels: Vec<Vec<usize>>,
    vehicles: Vec<Vehicle>,
    queue: Vec<Waiting>,
    parked: BTreeMap<String, usize>,
    passes: BTreeMap<String, i32>,
    histories: BTreeMap<String, Vec<Record>>,
    totals: [Counts; 5],
    daily: BTreeMap<i32, [Counts; 5]>,
    revenue: [Revenue; 5],
    output: Vec<String>,
}
fn number(s: &str) -> i32 {
    s.parse().unwrap()
}
fn time_text(t: i32) -> String {
    format!("{}-{:02}:{:02}", t / 1440 + 1, t % 1440 / 60, t % 60)
}
fn duration(t: i32) -> String {
    format!("{}:{:02}", t / 60, t % 60)
}
fn tenth(q: i32) -> String {
    format!("{}.{}", q / 10, q % 10)
}
fn lookup(names: &[&str], s: &str) -> Option<usize> {
    names.iter().position(|&name| name == s)
}
fn preference(kind: usize, spot_kind: usize) -> Option<usize> {
    PREFERENCES[kind].iter().position(|&k| k == spot_kind)
}
impl Garage {
    fn new() -> Self {
        Self {
            rates: [100, 200, 200, 300, 600],
            caps: [800, 1600, 1600, 2400, 4800],
            fees: [300, 2000, 30],
            ..Self::default()
        }
    }
    fn label(&self, s: usize) -> String {
        format!("L{}-{}", self.spots[s].level, self.spots[s].number)
    }
    fn location(&self, v: &Vehicle) -> String {
        let mut result = self.label(v.spot);
        if v.kind == 4 {
            result.push_str(&format!("..{}", self.spots[v.spot].number + 2));
        }
        result
    }
    fn free(&self, s: usize) -> bool {
        !self.spots[s].closed && self.spots[s].vehicle.is_none()
    }
    fn valid_pass(&self, plate: &str) -> bool {
        self.passes
            .get(plate)
            .is_some_and(|&last| self.now / 1440 + 1 <= last)
    }
    fn spot_id(&self, s: &str) -> Option<usize> {
        let (level, n) = s[1..].split_once('-').unwrap();
        self.levels
            .get(number(level) as usize - 1)?
            .get(number(n) as usize - 1)
            .copied()
    }
    fn vehicle(&self, plate: &str) -> Result<usize> {
        self.parked
            .get(plate)
            .copied()
            .ok_or_else(|| format!("{} is not parked", plate))
    }
    fn waiting(&self, plate: &str) -> Option<usize> {
        self.queue.iter().position(|w| w.plate == plate)
    }
    fn assign(&self, kind: usize) -> Option<usize> {
        if kind == 4 {
            for level in &self.levels {
                for triple in level.windows(3) {
                    if triple
                        .iter()
                        .all(|&s| self.spots[s].kind == 2 && self.free(s))
                    {
                        return Some(triple[0]);
                    }
                }
            }
        } else {
            for &k in PREFERENCES[kind] {
                if let Some(s) =
                    (0..self.spots.len()).find(|&s| self.spots[s].kind == k && self.free(s))
                {
                    return Some(s);
                }
            }
        }
        None
    }
    fn occupy(&mut self, id: usize, s: usize) {
        self.vehicles[id].spot = s;
        let size = if self.vehicles[id].kind == 4 { 3 } else { 1 };
        for i in 0..size {
            self.spots[s + i].vehicle = Some(id);
        }
    }
    fn vacate(&mut self, id: usize) {
        let v = &self.vehicles[id];
        let size = if v.kind == 4 { 3 } else { 1 };
        for i in 0..size {
            self.spots[v.spot + i].vehicle = None;
        }
    }
    fn park(&mut self, plate: &str, kind: usize, s: usize) -> usize {
        let id = self.vehicles.len();
        self.vehicles.push(Vehicle {
            plate: plate.to_owned(),
            kind,
            spot: s,
            entry: self.now,
            ..Vehicle::default()
        });
        self.parked.insert(plate.to_owned(), id);
        self.occupy(id, s);
        self.totals[kind].entries += 1;
        self.daily.entry(self.now / 1440 + 1).or_default()[kind].entries += 1;
        if self.parked.len() > self.peak {
            self.peak = self.parked.len();
            self.peak_time = self.now;
        }
        id
    }
    fn refuse(&mut self, kind: usize, time: i32) {
        self.totals[kind].refused += 1;
        self.daily.entry(time / 1440 + 1).or_default()[kind].refused += 1;
    }
    fn giveups(&mut self) {
        let queue = std::mem::take(&mut self.queue);
        for w in queue {
            if self.now - w.joined >= 30 {
                self.output.push(format!(
                    "GIVEUP {} {} {}",
                    w.plate,
                    TYPES[w.kind],
                    time_text(w.joined + 30)
                ));
                self.refuse(w.kind, w.joined + 30);
            } else {
                self.queue.push(w);
            }
        }
    }
    fn process_queue(&mut self) {
        let queue = std::mem::take(&mut self.queue);
        for w in queue {
            if let Some(s) = self.assign(w.kind) {
                let id = self.park(&w.plate, w.kind, s);
                self.output.push(format!(
                    "ADMIT {} {} {} waited {}",
                    w.plate,
                    TYPES[w.kind],
                    self.location(&self.vehicles[id]),
                    duration(self.now - w.joined)
                ));
            } else {
                self.queue.push(w);
            }
        }
    }
    fn interval(&self, v: &Vehicle, from: i32, free_time: i32) -> (i32, i32) {
        let length = self.now - from;
        if self.valid_pass(&v.plate) || length <= free_time {
            return (0, 0);
        }
        let mut parking = 0;
        let mut i = 0;
        while i * 1440 < length {
            let minutes = (length - i * 1440).min(1440) - if i == 0 { free_time } else { 0 };
            parking += ((minutes + 29) / 30 * self.rates[v.kind]).min(self.caps[v.kind]);
            i += 1;
        }
        (parking, (self.now / 1440 - from / 1440) * self.fees[0])
    }
    fn bill(&self, v: &Vehicle, loss: bool) -> Bill {
        let (additional, night_add) = self.interval(
            v,
            if v.paid { v.payment } else { v.entry },
            if v.paid { 15 } else { 15 + v.validation },
        );
        let parking = additional + if v.paid { v.parking } else { 0 };
        let night = night_add + if v.paid { v.night } else { 0 };
        let lost = if loss { self.fees[1] } else { 0 };
        let total = parking + night + lost + v.charge;
        Bill {
            parking,
            night,
            lost,
            charge: v.charge,
            total,
            due: if v.paid {
                additional + night_add
            } else {
                total
            },
        }
    }
    fn fee_line(&self, heading: &str, v: &Vehicle, b: &Bill) -> String {
        format!(
            "{} {} {} stay {} parking {} night {} lost {} charge {} total {} due {}",
            heading,
            v.plate,
            self.location(v),
            duration(self.now - v.entry),
            b.parking,
            b.night,
            b.lost,
            b.charge,
            b.total,
            b.due
        )
    }
    fn annotation(&self, v: &Vehicle) -> String {
        let mut s = String::new();
        if self.valid_pass(&v.plate) {
            s.push_str(" PASS");
        }
        if v.validation != 0 {
            s.push_str(&format!(" VAL {}", v.validation));
        }
        if v.energy != 0 {
            s.push_str(&format!(" KWH {}", v.energy));
        }
        if v.paid {
            s.push_str(" PAID");
        }
        s
    }
    fn ordered_vehicles(&self) -> Vec<usize> {
        let mut ids: Vec<usize> = self.parked.values().copied().collect();
        ids.sort_by_key(|&id| self.vehicles[id].spot);
        ids
    }
    fn move_vehicle(&mut self, id: usize, s: usize) {
        let before = self.location(&self.vehicles[id]);
        self.vacate(id);
        self.occupy(id, s);
        self.output.push(format!(
            "MOVE {} {} -> {}",
            self.vehicles[id].plate,
            before,
            self.label(s)
        ));
    }
    fn execute(&mut self, a: &[&str]) -> Result<()> {
        let cmd = a[0];
        match cmd {
            "LEVEL" => {
                let mut level = Vec::new();
                for k in 0..4 {
                    for _ in 0..number(a[k + 1]) {
                        level.push(self.spots.len());
                        self.spots.push(Spot {
                            level: self.levels.len() + 1,
                            number: level.len(),
                            kind: k,
                            vehicle: None,
                            closed: false,
                        });
                    }
                }
                self.output.push(format!(
                    "LEVEL {} spots {} MOTO {} COMPACT {} LARGE {} EV {}",
                    self.levels.len() + 1,
                    level.len(),
                    a[1],
                    a[2],
                    a[3],
                    a[4]
                ));
                self.levels.push(level);
                self.process_queue();
            }
            "CLOSE" | "OPEN" => {
                let s = self
                    .spot_id(a[1])
                    .ok_or_else(|| format!("unknown spot {}", a[1]))?;
                let spot = &mut self.spots[s];
                if cmd == "CLOSE" {
                    reject!(spot.closed, format!("spot {} is already closed", a[1]));
                    if let Some(id) = spot.vehicle {
                        return Err(format!(
                            "spot {} is occupied by {}",
                            a[1], self.vehicles[id].plate
                        ));
                    }
                    spot.closed = true;
                } else {
                    reject!(!spot.closed, format!("spot {} is not closed", a[1]));
                    spot.closed = false;
                }
                self.output
                    .push(format!("{} {} {}", cmd, a[1], KINDS[spot.kind]));
                if cmd == "OPEN" {
                    self.process_queue();
                }
            }
            "RATE" => {
                let kind = lookup(&TYPES, a[1]).ok_or_else(|| format!("unknown type {}", a[1]))?;
                let (rate, cap) = (number(a[2]), number(a[3]));
                reject!(cap < rate, format!("cap below rate for {}", a[1]));
                self.rates[kind] = rate;
                self.caps[kind] = cap;
                self.output.push(format!("RATE {} {} {}", a[1], rate, cap));
            }
            "FEE" => {
                let item = lookup(&["NIGHT", "LOST", "KWH"], a[1])
                    .ok_or_else(|| format!("unknown fee {}", a[1]))?;
                self.fees[item] = number(a[2]);
                self.output.push(format!("FEE {} {}", a[1], a[2]));
            }
            "ENTER" => {
                let kind = lookup(&TYPES, a[2]).ok_or_else(|| format!("unknown type {}", a[2]))?;
                if let Some(&id) = self.parked.get(a[1]) {
                    return Err(format!(
                        "{} is already parked at {}",
                        a[1],
                        self.location(&self.vehicles[id])
                    ));
                }
                reject!(
                    self.waiting(a[1]).is_some(),
                    format!("{} is already waiting", a[1])
                );
                if let Some(s) = self.assign(kind) {
                    let id = self.park(a[1], kind, s);
                    self.output.push(format!(
                        "ENTER {} {} {}",
                        a[1],
                        a[2],
                        self.location(&self.vehicles[id])
                    ));
                } else if self.queue.len() < 3 {
                    self.queue.push(Waiting {
                        plate: a[1].to_owned(),
                        kind,
                        joined: self.now,
                    });
                    self.output
                        .push(format!("WAIT {} {} {}", a[1], a[2], self.queue.len()));
                } else {
                    self.refuse(kind, self.now);
                    self.output.push(format!("FULL {} {}", a[1], a[2]));
                }
            }
            "LEAVE" => {
                let i = self
                    .waiting(a[1])
                    .ok_or_else(|| format!("{} is not waiting", a[1]))?;
                let w = self.queue.remove(i);
                self.output
                    .push(format!("LEAVE {} {}", w.plate, TYPES[w.kind]));
            }
            "EXIT" | "PAY" | "QUOTE" | "CHARGE" | "VALIDATE" | "MOVE" => {
                let id = self.vehicle(a[1])?;
                let v = &self.vehicles[id];
                match cmd {
                    "EXIT" => {
                        let loss = a.len() == 3;
                        reject!(loss && v.paid, format!("{} has already paid", a[1]));
                        let b = self.bill(v, loss);
                        self.output.push(self.fee_line("EXIT", v, &b));
                        let record = Record {
                            entry: v.entry,
                            exit: self.now,
                            kind: v.kind,
                            total: b.total,
                            location: self.location(v),
                            lost: loss,
                        };
                        self.histories
                            .entry(v.plate.clone())
                            .or_default()
                            .push(record);
                        let all = &mut self.totals[v.kind];
                        all.exits += 1;
                        all.stay += self.now - v.entry;
                        all.revenue += b.total;
                        let today = &mut self.daily.entry(self.now / 1440 + 1).or_default()[v.kind];
                        today.exits += 1;
                        today.revenue += b.total;
                        let r = &mut self.revenue[v.kind];
                        r.exits += 1;
                        r.parking += b.parking;
                        r.night += b.night;
                        r.lost += b.lost;
                        r.charge += b.charge;
                        r.total += b.total;
                        self.vacate(id);
                        self.parked.remove(a[1]);
                        self.process_queue();
                    }
                    "QUOTE" => self
                        .output
                        .push(self.fee_line("QUOTE", v, &self.bill(v, false))),
                    "PAY" => {
                        reject!(v.paid, format!("{} has already paid", a[1]));
                        let b = self.bill(v, false);
                        let current = &mut self.vehicles[id];
                        current.paid = true;
                        current.payment = self.now;
                        current.parking = b.parking;
                        current.night = b.night;
                        self.output.push(format!(
                            "PAY {} parking {} night {} charge {} total {}",
                            a[1], b.parking, b.night, b.charge, b.total
                        ));
                    }
                    "CHARGE" => {
                        reject!(v.kind != 2, format!("{} is not an electric car", a[1]));
                        reject!(
                            self.spots[v.spot].kind != 3,
                            format!("{} is not at a charger", a[1])
                        );
                        reject!(v.paid, format!("{} has already paid", a[1]));
                        let energy = number(a[2]);
                        reject!(
                            v.energy + energy > 100,
                            format!("charge limit exceeded for {}", a[1])
                        );
                        let cost = energy * self.fees[2];
                        self.vehicles[id].energy += energy;
                        self.vehicles[id].charge += cost;
                        self.output.push(format!(
                            "CHARGE {} kwh {} cost {} stay_kwh {} stay_cost {}",
                            a[1], energy, cost, self.vehicles[id].energy, self.vehicles[id].charge
                        ));
                    }
                    "VALIDATE" => {
                        reject!(v.paid, format!("{} has already paid", a[1]));
                        let minutes = number(a[2]);
                        reject!(
                            v.validation + minutes > 180,
                            format!("validation limit exceeded for {}", a[1])
                        );
                        self.vehicles[id].validation += minutes;
                        self.output.push(format!(
                            "VALIDATE {} {} total {}",
                            a[1], minutes, self.vehicles[id].validation
                        ));
                    }
                    _ => {
                        reject!(v.kind == 4, format!("bus {} cannot be moved", a[1]));
                        let s = self
                            .spot_id(a[2])
                            .ok_or_else(|| format!("unknown spot {}", a[2]))?;
                        reject!(s == v.spot, format!("{} is already at {}", a[1], a[2]));
                        reject!(self.spots[s].closed, format!("spot {} is closed", a[2]));
                        if let Some(other) = self.spots[s].vehicle {
                            return Err(format!(
                                "spot {} is occupied by {}",
                                a[2], self.vehicles[other].plate
                            ));
                        }
                        reject!(
                            preference(v.kind, self.spots[s].kind).is_none(),
                            format!(
                                "{} cannot use {} spot {}",
                                TYPES[v.kind], KINDS[self.spots[s].kind], a[2]
                            )
                        );
                        self.move_vehicle(id, s);
                        self.process_queue();
                    }
                }
            }
            "PASS" => {
                let last = if self.valid_pass(a[1]) {
                    self.passes[a[1]] + number(a[2])
                } else {
                    self.now / 1440 + number(a[2])
                };
                self.passes.insert(a[1].to_owned(), last);
                self.output.push(format!("PASS {} until {}", a[1], last));
            }
            "UNPASS" => {
                reject!(!self.valid_pass(a[1]), format!("{} has no pass", a[1]));
                self.passes.remove(a[1]);
                self.output.push(format!("UNPASS {}", a[1]));
            }
            "REBALANCE" => {
                let ids = self.ordered_vehicles();
                let mut moved = 0;
                for id in ids {
                    let v = &self.vehicles[id];
                    if v.kind == 4 {
                        continue;
                    }
                    let current = preference(v.kind, self.spots[v.spot].kind).unwrap();
                    if current == 0 {
                        continue;
                    }
                    if let Some(s) = self.assign(v.kind) {
                        if preference(v.kind, self.spots[s].kind).unwrap() < current {
                            self.move_vehicle(id, s);
                            moved += 1;
                        }
                    }
                }
                self.output.push(format!("REBALANCE {}", moved));
                self.process_queue();
            }
            "WHERE" => {
                if let Some(&id) = self.parked.get(a[1]) {
                    let v = &self.vehicles[id];
                    self.output.push(format!(
                        "WHERE {} {} {} {} stay {}{}",
                        a[1],
                        self.location(v),
                        TYPES[v.kind],
                        time_text(v.entry),
                        duration(self.now - v.entry),
                        self.annotation(v)
                    ));
                } else if let Some(q) = self.waiting(a[1]) {
                    self.output
                        .push(format!("WHERE {} waiting {}", a[1], q + 1));
                } else if let Some(records) = self.histories.get(a[1]) {
                    self.output.push(format!(
                        "WHERE {} gone {}",
                        a[1],
                        time_text(records.last().unwrap().exit)
                    ));
                } else {
                    return Err(format!("unknown plate {}", a[1]));
                }
            }
            "LIST" | "OVERSTAY" => {
                let level = if cmd == "LIST" && a.len() == 2 {
                    number(a[1]) as usize
                } else {
                    0
                };
                reject!(
                    level > self.levels.len(),
                    format!("unknown level {}", level)
                );
                let mut ids: Vec<usize> = self
                    .ordered_vehicles()
                    .into_iter()
                    .filter(|&id| {
                        let v = &self.vehicles[id];
                        (level == 0 || self.spots[v.spot].level == level)
                            && (cmd != "OVERSTAY" || self.now - v.entry >= number(a[1]) * 60)
                    })
                    .collect();
                if cmd == "OVERSTAY" {
                    ids.sort_by_key(|&id| self.vehicles[id].entry);
                    self.output.push(format!("OVERSTAY {} {}", a[1], ids.len()));
                } else {
                    self.output.push(format!("LIST {}", ids.len()));
                }
                for id in ids {
                    let v = &self.vehicles[id];
                    let suffix = if cmd == "LIST" {
                        self.annotation(v)
                    } else {
                        format!(" stay {}", duration(self.now - v.entry))
                    };
                    self.output.push(format!(
                        "{} {} {} {}{}",
                        self.location(v),
                        v.plate,
                        TYPES[v.kind],
                        time_text(v.entry),
                        suffix
                    ));
                }
            }
            "MAP" => {
                self.output.push(format!("MAP {}", self.levels.len()));
                for (i, level) in self.levels.iter().enumerate() {
                    let mut symbols = String::new();
                    for (j, &id) in level.iter().enumerate() {
                        if j != 0 && j % 10 == 0 {
                            symbols.push(' ');
                        }
                        let s = &self.spots[id];
                        let c = if s.closed {
                            '#'
                        } else if s.vehicle.is_some() {
                            b"MCLE"[s.kind] as char
                        } else {
                            b"mcle"[s.kind] as char
                        };
                        symbols.push(c);
                    }
                    self.output.push(format!("L{} {}", i + 1, symbols));
                }
            }
            "OCCUPANCY" => {
                self.output.push(format!(
                    "OCCUPANCY vehicles {} waiting {}",
                    self.parked.len(),
                    self.queue.len()
                ));
                let (mut all_used, mut all_available, mut all_closed) = ([0; 4], [0; 4], 0);
                for (i, level) in self.levels.iter().enumerate() {
                    let (mut used, mut available, mut closed) = ([0; 4], [0; 4], 0);
                    for &id in level {
                        let s = &self.spots[id];
                        if s.closed {
                            closed += 1;
                        } else {
                            available[s.kind] += 1;
                        }
                        if s.vehicle.is_some() {
                            used[s.kind] += 1;
                        }
                    }
                    let mut s = format!("L{}", i + 1);
                    for k in 0..4 {
                        s.push_str(&format!(" {} {}/{}", KINDS[k], used[k], available[k]));
                        all_used[k] += used[k];
                        all_available[k] += available[k];
                    }
                    all_closed += closed;
                    self.output.push(format!("{} closed {}", s, closed));
                }
                let mut s = "TOTAL".to_owned();
                for k in 0..4 {
                    s.push_str(&format!(
                        " {} {}/{}",
                        KINDS[k], all_used[k], all_available[k]
                    ));
                }
                let used: i32 = all_used.iter().sum();
                let available: i32 = all_available.iter().sum();
                self.output.push(format!(
                    "{} closed {} rate {}%",
                    s,
                    all_closed,
                    tenth(if available == 0 {
                        0
                    } else {
                        used * 1000 / available
                    })
                ));
            }
            "SIGN" => {
                let (mut free_counts, mut buses) = ([0; 4], 0);
                for level in &self.levels {
                    let mut run = 0;
                    for &id in level {
                        if self.free(id) {
                            free_counts[self.spots[id].kind] += 1;
                        }
                        if self.free(id) && self.spots[id].kind == 2 {
                            run += 1;
                        } else {
                            buses += run / 3;
                            run = 0;
                        }
                    }
                    buses += run / 3;
                }
                let mut s = "SIGN".to_owned();
                for k in 0..5 {
                    let count: i32 = if k == 4 {
                        buses
                    } else {
                        PREFERENCES[k].iter().map(|&kind| free_counts[kind]).sum()
                    };
                    s.push_str(&format!(
                        " {} {}",
                        TYPES[k],
                        if count == 0 {
                            "FULL".to_owned()
                        } else {
                            count.to_string()
                        }
                    ));
                }
                self.output.push(s);
            }
            "RATES" => {
                self.output.push("RATES".to_owned());
                for k in 0..5 {
                    self.output
                        .push(format!("{} {} {}", TYPES[k], self.rates[k], self.caps[k]));
                }
                self.output.push(format!(
                    "NIGHT {} LOST {} KWH {}",
                    self.fees[0], self.fees[1], self.fees[2]
                ));
            }
            "PASSES" => {
                let valid: Vec<(&String, &i32)> = self
                    .passes
                    .iter()
                    .filter(|(_, last)| self.now / 1440 + 1 <= **last)
                    .collect();
                self.output.push(format!("PASSES {}", valid.len()));
                for (plate, last) in valid {
                    self.output.push(format!(
                        "{} until {}{}",
                        plate,
                        last,
                        if self.parked.contains_key(plate) {
                            " IN"
                        } else {
                            ""
                        }
                    ));
                }
            }
            "HISTORY" => {
                let records = self
                    .histories
                    .get(a[1])
                    .ok_or_else(|| format!("no history for {}", a[1]))?;
                let total: i32 = records.iter().map(|r| r.total).sum();
                self.output.push(format!(
                    "HISTORY {} visits {} paid {}",
                    a[1],
                    records.len(),
                    total
                ));
                for r in records {
                    self.output.push(format!(
                        "{} {} {} {} {}{}",
                        time_text(r.entry),
                        time_text(r.exit),
                        r.location,
                        TYPES[r.kind],
                        r.total,
                        if r.lost { " LOST" } else { "" }
                    ));
                }
            }
            "REVENUE" => {
                self.output.push("REVENUE".to_owned());
                let mut all = Revenue::default();
                for k in 0..5 {
                    let r = self.revenue[k];
                    self.output.push(format!(
                        "{} exits {} parking {} night {} lost {} charge {} total {}",
                        TYPES[k], r.exits, r.parking, r.night, r.lost, r.charge, r.total
                    ));
                    all.exits += r.exits;
                    all.parking += r.parking;
                    all.night += r.night;
                    all.lost += r.lost;
                    all.charge += r.charge;
                    all.total += r.total;
                }
                self.output.push(format!(
                    "TOTAL exits {} parking {} night {} lost {} charge {} total {}",
                    all.exits, all.parking, all.night, all.lost, all.charge, all.total
                ));
            }
            "DAILY" | "STATS" => {
                let counts = if cmd == "DAILY" {
                    self.daily.get(&number(a[1])).copied().unwrap_or_default()
                } else {
                    self.totals
                };
                let mut all = Counts::default();
                for c in counts {
                    all.entries += c.entries;
                    all.exits += c.exits;
                    all.refused += c.refused;
                    all.revenue += c.revenue;
                    all.stay += c.stay;
                }
                if cmd == "DAILY" {
                    self.output.push(format!(
                        "DAILY {} entries {} exits {} refused {} revenue {}",
                        a[1], all.entries, all.exits, all.refused, all.revenue
                    ));
                } else {
                    self.output.push(format!(
                        "STATS parked {} peak {} at {}",
                        self.parked.len(),
                        self.peak,
                        if self.peak == 0 {
                            "-".to_owned()
                        } else {
                            time_text(self.peak_time)
                        }
                    ));
                }
                for k in 0..if cmd == "DAILY" { 5 } else { 6 } {
                    let c = if k == 5 { all } else { counts[k] };
                    let label = if k == 5 { "ALL" } else { TYPES[k] };
                    let s = format!(
                        "{} entries {} exits {} refused {}",
                        label, c.entries, c.exits, c.refused
                    );
                    if cmd == "DAILY" {
                        self.output.push(format!("{} revenue {}", s, c.revenue));
                    } else {
                        self.output.push(format!(
                            "{} avg_stay {}",
                            s,
                            tenth(if c.exits == 0 {
                                0
                            } else {
                                c.stay * 10 / c.exits
                            })
                        ));
                    }
                }
            }
            _ => unreachable!(),
        }
        Ok(())
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut garage = Garage::new();
    let mut output = String::new();
    for _ in 0..count {
        let a: Vec<&str> = lines.next().unwrap().split(' ').collect();
        let (hour, minute) = a[1].split_once(':').unwrap();
        garage.now = (number(a[0]) - 1) * 1440 + number(hour) * 60 + number(minute);
        garage.output.clear();
        garage.giveups();
        if let Err(reason) = garage.execute(&a[2..]) {
            garage.output.push(format!("ERROR {}", reason));
        }
        for line in &garage.output {
            output.push_str(line);
            output.push('\n');
        }
    }
    print!("{}", output);
}
