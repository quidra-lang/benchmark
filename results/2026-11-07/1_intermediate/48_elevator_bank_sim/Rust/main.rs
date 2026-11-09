use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};
const POLICIES: [&str; 4] = ["COST", "NEAREST", "ROUND", "ETA"];
const KEYS: [&str; 13] = ["FLOORS", "CARS", "CAPACITY", "DOOR", "START", "POLICY", "ZONES", "PARK", "PATIENCE", "BYPASS", "PERIOD", "LIMIT", "COMPARE"];
fn check(ok: bool, message: String) -> Result<(), String> {
    if ok {
        Ok(())
    } else {
        Err(message)
    }
}
fn joined(a: Vec<String>) -> String {
    if a.is_empty() {
        "-".into()
    } else {
        a.join(",")
    }
}
fn average(total: i64, count: i64) -> String {
    if count == 0 {
        "-".into()
    } else {
        let x = total * 100 / count;
        format!("{}.{:02}", x / 100, x % 100)
    }
}
#[derive(Clone)]
struct Config {
    floors: i64,
    cars: usize,
    capacity: i64,
    door: i64,
    starts: Vec<i64>,
    zones: Vec<(i64, i64)>,
    park: Option<i64>,
    homes: Vec<i64>,
    patience: Option<i64>,
    bypass: i64,
    period: Option<i64>,
    limit: i64,
    policy: String,
    compare: Vec<String>,
}
impl Config {
    fn contains(&self, e: usize, f: i64) -> bool {
        self.zones[e].0 <= f && f <= self.zones[e].1
    }
    fn parse(settings: &[Vec<&str>]) -> Result<Self, String> {
        let mut entries = BTreeMap::new();
        for w in settings {
            check(KEYS.contains(&w[0]), format!("unknown key {}", w[0]))?;
            check(!entries.contains_key(w[0]), format!("duplicate key {}", w[0]))?;
            entries.insert(w[0], &w[1..]);
        }
        for k in &KEYS[..5] {
            check(entries.contains_key(k), format!("missing key {}", k))?;
        }
        let mut c = Self {
            floors: 0, cars: 0, capacity: 0, door: 0, starts: vec![], zones: vec![], park: None, homes: vec![], patience: None, bypass: 100, period: None, limit: 1000, policy: "COST".into(), compare: vec![]
        };
        for k in KEYS {
            let Some(a) = entries.get(k) else {
                continue;
            };
            let count = match k {
                "START" | "ZONES" => a.len() == c.cars,
                "PARK" => a.len() == c.cars + 1,
                "COMPARE" => (1..=4).contains(&a.len()), _ => a.len() == 1
            };
            check(count, format!("wrong number of values for {}", k))?;
            let bound = |s: &str, lo: i64, hi: i64| -> Result<i64, String> {
                let n: i64 = s.parse().unwrap();
                check(n >= lo && n <= hi, format!("bad value for {}", k))?;
                Ok(n)
            };
            match k {
                "FLOORS" => c.floors = bound(a[0], 2, 50)?,
                "CARS" => c.cars = bound(a[0], 1, 8)? as usize,
                "CAPACITY" => c.capacity = bound(a[0], 1, 20)?,
                "DOOR" => c.door = bound(a[0], 1, 9)?,
                "START" => c.starts = a.iter().map(|s| bound(s, 1, c.floors)).collect::<Result<_, _>>()?,
                "POLICY" => {
                    check(POLICIES.contains(&a[0]), format!("bad value for {}", k))?;
                    c.policy = a[0].into();
                }
                "ZONES" => {
                    for s in *a {
                        let z: Vec<i64> = s.split(':').map(|p| p.parse().unwrap()).collect();
                        check(1 <= z[0] && z[0] < z[1] && z[1] <= c.floors, "bad value for ZONES".into())?;
                        c.zones.push((z[0], z[1]));
                    }
                }
                "PARK" => {
                    c.park = Some(bound(a[0], 0, 100)?);
                    c.homes = a[1..].iter().map(|s| bound(s, 1, c.floors)).collect::<Result<_, _>>()?;
                }
                "PATIENCE" => c.patience = Some(bound(a[0], 1, 1000)?),
                "BYPASS" => c.bypass = bound(a[0], 50, 100)?,
                "PERIOD" => c.period = Some(bound(a[0], 1, 1000)?),
                "LIMIT" => c.limit = bound(a[0], 1, 5000)?,
                _ => {
                    check(a.iter().all(|p| POLICIES.contains(p)) && a.iter().collect::<BTreeSet<_>>().len() == a.len(), format!("bad value for {}", k))?;
                    c.compare = a.iter().map(|s| s.to_string()).collect();
                }
            }
        }
        if c.zones.is_empty() {
            c.zones = vec![(1, c.floors); c.cars];
        }
        for e in 0..c.cars {
            check(c.contains(e, c.starts[e]), format!("car {} starts outside its zone", e + 1))?;
            check(c.park.is_none() || c.contains(e, c.homes[e]), format!("car {} home outside its zone", e + 1))?;
        }
        Ok(c)
    }
    fn header(&self) -> Vec<String> {
        let opt = |n: Option<i64>| n.map_or("off".into(), |x| x.to_string());
        let mut out = vec![format!("config: floors={} cars={} capacity={} door={} policy={} park={} patience={} bypass={} period={} limit={} compare={}", self.floors, self.cars, self.capacity, self.door, self.policy, opt(self.park), opt(self.patience), self.bypass, opt(self.period), self.limit, joined(self.compare.clone()))];
        for e in 0..self.cars {
            out.push(format!("E{}: start={} zone={}-{} home={}", e + 1, self.starts[e], self.zones[e].0, self.zones[e].1, if self.park.is_none() {
                "-".into()
            } else {
                self.homes[e].to_string()
            }
            ));
        }
        out
    }
}
#[derive(Clone)]
struct Event {
    time: i64,
    command: String,
    values: Vec<i64>,
}
fn validate(c: &Config, raw: &[(usize, Vec<&str>)], out: &mut Vec<String>) -> Vec<Event> {
    let (mut last, mut groups, mut fire) = (0, 0, false);
    let mut outs = BTreeSet::new();
    let mut accepted = vec![];
    for (line, w) in raw {
        let t = w[0].parse::<i64>().unwrap();
        let cmd = w[1];
        let mut a = vec![];
        let count = match cmd {
            "CALL" => Some(3),
            "HOLD" => Some(2), "CANCEL" | "OUT" | "IN" | "FIRE" | "WHERE" => Some(1), "RESET" | "STATUS" => Some(0), _ => None
        };
        let error = if count.is_none() {
            Some(format!("unknown command {}", cmd))
        } else if w.len() - 2 != count.unwrap() {
            Some(format!("wrong number of arguments for {}", cmd))
        } else if t < last {
            Some("time goes backwards".into())
        } else {
            a = w[2..].iter().map(|s| s.parse::<i64>().unwrap()).collect();
            let floor = |f| f >= 1 && f <= c.floors;
            let car = |e: i64| e >= 1 && e <= c.cars as i64;
            match cmd {
                "CALL" => if !floor(a[0]) || !floor(a[1]) {
                    Some("bad floor".into())
                } else if a[0] == a[1] {
                    Some("same floor".into())
                } else if !(1..=99).contains(&a[2]) {
                    Some("bad count".into())
                } else if !(0..c.cars).any(|e| c.contains(e, a[0]) && c.contains(e, a[1])) {
                    Some(format!("no car serves {}->{}", a[0], a[1]))
                } else if fire {
                    Some("fire service active".into())
                } else {
                    None
                },
                "CANCEL" | "WHERE" => if a[0] < 1 || a[0] > groups {
                    Some("unknown group".into())
                } else {
                    None
                },
                "OUT" | "IN" => if !car(a[0]) {
                    Some("bad car".into())
                } else if cmd == "OUT" && outs.contains(&a[0]) {
                    Some(format!("car {} already out", a[0]))
                } else if cmd == "IN" && !outs.contains(&a[0]) {
                    Some(format!("car {} already in", a[0]))
                } else {
                    None
                },
                "HOLD" => if !car(a[0]) {
                    Some("bad car".into())
                } else if !(1..=9).contains(&a[1]) {
                    Some("bad ticks".into())
                } else {
                    None
                },
                "FIRE" => if !floor(a[0]) {
                    Some("bad floor".into())
                } else if fire {
                    Some("fire already active".into())
                } else {
                    None
                },
                "RESET" if !fire => Some("fire not active".into()), _ => None,
            }
        };
        if let Some(error) = error {
            out.push(format!("line {}: {}", line, error));
            continue;
        }
        last = t;
        match cmd {
            "CALL" => groups += 1,
            "OUT" => {
                outs.insert(a[0]);
            },
            "IN" => {
                outs.remove(&a[0]);
            },
            "FIRE" => fire = true,
            "RESET" => fire = false, _ => ()
        }
        accepted.push(Event {
            time: t, command: cmd.into(), values: a
        });
    }
    accepted
}
struct Group {
    a: i64,
    b: i64,
    count: i64,
    time: i64,
    waiting: i64,
    car: Option<usize>,
    boarded: i64,
    delivered: i64,
    lost: i64,
    last_board: i64,
    last_alight: i64,
    cars: BTreeSet<usize>,
    wait_total: i64,
    travel_total: i64,
}
#[derive(Clone)]
struct Passenger {
    group: usize,
    count: i64,
    time: i64,
}
struct Car {
    floor: i64,
    direction: i64,
    door: i64,
    service: bool,
    idle_start: i64,
    calls: Vec<usize>,
    passengers: Vec<Passenger>,
    distance: i64,
    stops: i64,
    boarded: i64,
    busy: i64,
    energy: i64,
}
impl Car {
    fn load(&self) -> i64 {
        self.passengers.iter().map(|p| p.count).sum()
    }
}
struct Simulation {
    config: Config,
    events: Vec<Event>,
    policy: String,
    cars: Vec<Car>,
    groups: Vec<Group>,
    pending: Vec<usize>,
    fire: Option<i64>,
    last_round: usize,
    time: i64,
    status: String,
    log: Vec<String>,
    abandoned: i64,
    evacuated: i64,
    delivered: i64,
    wait_total: i64,
    travel_total: i64,
    max_wait: i64,
}
impl Simulation {
    fn new(c: &Config, events: &[Event], policy: &str) -> Self {
        Self {
            config: c.clone(), events: events.to_vec(), policy: policy.into(), cars: c.starts.iter().map(|&f| Car {
                floor: f, direction: 0, door: 0, service: true, idle_start: 0, calls: vec![], passengers: vec![], distance: 0, stops: 0, boarded: 0, busy: 0, energy: 0
            }
            ).collect(), groups: vec![], pending: vec![], fire: None, last_round: 0, time: 0, status: String::new(), log: vec![], abandoned: 0, evacuated: 0, delivered: 0, wait_total: 0, travel_total: 0, max_wait: 0
        }
    }
    fn emit(&mut self, text: String) {
        self.log.push(format!("{} {}", self.time, text));
    }
    fn targets(&self, e: usize) -> BTreeSet<i64> {
        self.cars[e].passengers.iter().map(|p| self.groups[p.group].b).chain(self.cars[e].calls.iter().map(|&g| self.groups[g].a)).collect()
    }
    fn bypass(&self, e: usize) -> bool {
        self.cars[e].load() * 100 >= self.config.capacity * self.config.bypass
    }
    fn cost(&self, e: usize, g: usize) -> i64 {
        let c = &self.cars[e];
        let g = &self.groups[g];
        let (f, d, x) = (c.floor, c.direction, g.a);
        if self.policy == "NEAREST" || d == 0 {
            return (f - x).abs();
        }
        let targets = self.targets(e);
        let (distance, via);
        if (g.b - g.a).signum() == d && (x - f) * d >= 0 {
            distance = (x - f).abs();
            via = targets.iter().filter(|&&y| (y - f) * d > 0 && (x - y) * d > 0).count();
        } else {
            let m = if d > 0 {
                targets.iter().copied().chain([f]).max().unwrap()
            } else {
                targets.iter().copied().chain([f]).min().unwrap()
            };
            distance = (f - m).abs() + (m - x).abs();
            via = targets.iter().filter(|&&y| (y - f) * d > 0).count();
        }
        if self.policy == "COST" {
            distance
        } else {
            distance + self.config.door * via as i64 + c.door
        }
    }
    fn assign(&mut self, g: usize, exclude: Option<usize>) -> bool {
        let group = &self.groups[g];
        let candidates: Vec<usize> = (0..self.cars.len()).filter(|&e| Some(e) != exclude && self.cars[e].service && self.config.contains(e, group.a) && self.config.contains(e, group.b)).collect();
        if candidates.is_empty() {
            return false;
        }
        let e;
        if self.policy == "ROUND" {
            e = candidates.iter().copied().find(|&e| e + 1 > self.last_round).unwrap_or(candidates[0]);
            self.last_round = e + 1;
            self.emit(format!("E{} ASSIGN G{}", e + 1, g + 1));
        } else {
            e = *candidates.iter().min_by_key(|&&e| (self.cost(e, g), e)).unwrap();
            self.emit(format!("E{} ASSIGN G{} cost={}", e + 1, g + 1, self.cost(e, g)));
        }
        if let Some(old) = self.groups[g].car {
            self.cars[old].calls.retain(|&i| i != g);
        }
        self.cars[e].calls.push(g);
        self.groups[g].car = Some(e);
        true
    }
    fn dispatch(&mut self, g: usize) {
        if !self.assign(g, None) {
            self.pending.push(g);
            self.emit(format!("PENDING G{}", g + 1));
        }
    }
    fn walk(&mut self, g: usize, word: &str) {
        if let Some(e) = self.groups[g].car {
            self.cars[e].calls.retain(|&i| i != g);
        } else {
            self.pending.retain(|&i| i != g);
        }
        self.emit(format!("{} G{} x{}", word, g + 1, self.groups[g].waiting));
        let g = &mut self.groups[g];
        g.car = None;
        g.lost += g.waiting;
        self.abandoned += g.waiting;
        g.waiting = 0;
    }
    fn execute(&mut self, ev: Event) {
        let a = ev.values;
        match ev.command.as_str() {
            "CALL" => {
                let g = self.groups.len();
                self.groups.push(Group {
                    a: a[0], b: a[1], count: a[2], time: self.time, waiting: a[2], car: None, boarded: 0, delivered: 0, lost: 0, last_board: 0, last_alight: 0, cars: BTreeSet::new(), wait_total: 0, travel_total: 0
                });
                self.emit(format!("CALL G{} {}->{} x{}", g + 1, a[0], a[1], a[2]));
                self.dispatch(g);
            }
            "CANCEL" => {
                let g = a[0] as usize - 1;
                if self.groups[g].waiting > 0 {
                    self.walk(g, "CANCEL");
                } else {
                    self.emit(format!("CANCEL G{} ignored", g + 1));
                }
            }
            "OUT" => {
                let e = a[0] as usize - 1;
                self.cars[e].service = false;
                self.emit(format!("E{} OUT", e + 1));
                let calls = std::mem::take(&mut self.cars[e].calls);
                for g in calls {
                    self.groups[g].car = None;
                    self.dispatch(g);
                }
            }
            "IN" => {
                let e = a[0] as usize - 1;
                self.cars[e].service = true;
                self.cars[e].idle_start = self.time;
                self.emit(format!("E{} IN", e + 1));
                let pending = std::mem::take(&mut self.pending);
                for g in pending {
                    if !self.assign(g, None) {
                        self.pending.push(g);
                    }
                }
            }
            "HOLD" => {
                let e = a[0] as usize - 1;
                if self.cars[e].door > 0 {
                    self.cars[e].door += a[1];
                    self.emit(format!("E{} HOLD {}", e + 1, self.cars[e].door));
                } else {
                    self.emit(format!("E{} HOLD ignored", e + 1));
                }
            }
            "FIRE" => {
                self.fire = Some(a[0]);
                self.emit(format!("FIRE {}", a[0]));
                for g in 0..self.groups.len() {
                    if self.groups[g].waiting > 0 {
                        self.walk(g, "ABANDON");
                    }
                }
            }
            "RESET" => {
                self.fire = None;
                self.emit("RESET".into());
                for c in &mut self.cars {
                    c.idle_start = self.time;
                }
            }
            "WHERE" => {
                let g = a[0] as usize - 1;
                let group = &self.groups[g];
                let place = if group.waiting == 0 {
                    "-".into()
                } else {
                    group.car.map_or("pending".into(), |e| format!("E{}", e + 1))
                };
                let riding = self.cars.iter().enumerate().filter_map(|(e, c)| {
                    let n: i64 = c.passengers.iter().filter(|p| p.group == g).map(|p| p.count).sum();
                    if n > 0 {
                        Some(format!("E{}x{}", e + 1, n))
                    } else {
                        None
                    }
                }
                ).collect();
                self.emit(format!("WHERE G{} waiting={} car={} riding={} delivered={} lost={}", g + 1, group.waiting, place, joined(riding), group.delivered, group.lost));
            }
            "STATUS" => {
                for e in 0..self.cars.len() {
                    let c = &self.cars[e];
                    let stops: BTreeSet<i64> = c.passengers.iter().map(|p| self.groups[p.group].b).collect();
                    self.emit(format!("STATUS E{} floor={} dir={} door={} load={} stops={} calls={} service={}", e + 1, c.floor, if c.direction > 0 {
                        "up"
                    } else if c.direction < 0 {
                        "down"
                    } else {
                        "idle"
                    }, c.door, c.load(), joined(stops.iter().map(|f| f.to_string()).collect()), joined(c.calls.iter().map(|g| format!("G{}", g + 1)).collect()), if c.service {
                        "in"
                    } else {
                        "out"
                    }
                    ));
                }
                self.emit(format!("STATUS pending={}", joined(self.pending.iter().map(|g| format!("G{}", g + 1)).collect())));
            }
            _ => unreachable!(),
        }
    }
    fn direction(&self, e: usize) -> i64 {
        let c = &self.cars[e];
        let (f, d) = (c.floor, c.direction);
        let here: Vec<usize> = if self.bypass(e) {
            vec![]
        } else {
            c.calls.iter().copied().filter(|&g| self.groups[g].a == f).collect()
        };
        let targets = self.targets(e);
        if d != 0 && (targets.iter().any(|y| (y - f) * d > 0) || here.iter().any(|&g| (self.groups[g].b - self.groups[g].a).signum() == d)) {
            return d;
        }
        if let Some(&g) = here.first() {
            return (self.groups[g].b - self.groups[g].a).signum();
        }
        if d != 0 && targets.iter().any(|y| (y - f) * d < 0) {
            return -d;
        }
        if d == 0 {
            if let Some(&g) = c.calls.first() {
                return (self.groups[g].a - f).signum();
            }
        }
        0
    }
    fn move_car(&mut self, e: usize, d: i64) {
        let c = &mut self.cars[e];
        c.energy += if d > 0 {
            3 + c.load()
        } else {
            1
        };
        c.distance += 1;
        c.floor += d;
    }
    fn open(&mut self, e: usize) {
        self.emit(format!("E{} OPEN {}", e + 1, self.cars[e].floor));
        self.cars[e].door = self.config.door;
        self.cars[e].stops += 1;
        self.cars[e].energy += 2;
        let passengers = std::mem::take(&mut self.cars[e].passengers);
        for p in passengers {
            let g = p.group;
            if self.groups[g].b == self.cars[e].floor {
                self.emit(format!("E{} ALIGHT G{} x{}", e + 1, g + 1, p.count));
                let group = &mut self.groups[g];
                let w = p.time - group.time;
                let r = self.time - group.time;
                group.delivered += p.count;
                group.last_alight = self.time;
                group.wait_total += w * p.count;
                group.travel_total += r * p.count;
                self.delivered += p.count;
                self.wait_total += w * p.count;
                self.travel_total += r * p.count;
                self.max_wait = self.max_wait.max(w);
            } else if self.fire.is_some() {
                self.emit(format!("E{} EVACUATE G{} x{}", e + 1, g + 1, p.count));
                self.groups[g].lost += p.count;
                self.evacuated += p.count;
            } else {
                self.cars[e].passengers.push(p);
            }
        }
        if self.fire.is_some() {
            return;
        }
        let n = self.direction(e);
        if n != 0 {
            self.cars[e].direction = n;
        }
        let boarding: Vec<usize> = self.cars[e].calls.iter().copied().filter(|&g| self.groups[g].a == self.cars[e].floor && (self.groups[g].b - self.groups[g].a).signum() == n).collect();
        for g in boarding {
            let k = (self.config.capacity - self.cars[e].load()).min(self.groups[g].waiting);
            if k > 0 {
                self.cars[e].passengers.push(Passenger {
                    group: g, count: k, time: self.time
                });
                self.cars[e].boarded += k;
                let group = &mut self.groups[g];
                group.waiting -= k;
                group.boarded += k;
                group.last_board = self.time;
                group.cars.insert(e + 1);
                self.emit(format!("E{} BOARD G{} x{}", e + 1, g + 1, k));
            }
            if self.groups[g].waiting == 0 {
                self.cars[e].calls.retain(|&i| i != g);
                self.groups[g].car = None;
            } else {
                self.emit(format!("E{} LEFT G{} x{}", e + 1, g + 1, self.groups[g].waiting));
                self.assign(g, Some(e));
            }
        }
    }
    fn advance(&mut self, e: usize) {
        let old = self.cars[e].floor;
        if self.cars[e].door > 0 {
            self.cars[e].door -= 1;
        }
        if self.cars[e].door == 0 {
            let n = self.fire.map_or_else(|| self.direction(e), |f| (f - old).signum());
            let stop = if self.fire.is_some() {
                n == 0 && !self.cars[e].passengers.is_empty()
            } else {
                self.cars[e].passengers.iter().any(|p| self.groups[p.group].b == old) || !self.bypass(e) && self.cars[e].calls.iter().any(|&g| self.groups[g].a == old && (self.groups[g].b - self.groups[g].a).signum() == n)
            };
            if stop {
                self.open(e);
            } else if n != 0 {
                self.cars[e].direction = n;
                self.move_car(e, n);
            } else {
                if self.cars[e].direction != 0 {
                    self.emit(format!("E{} IDLE {}", e + 1, old));
                    self.cars[e].direction = 0;
                    self.cars[e].idle_start = self.time;
                }
                if self.fire.is_none() && self.cars[e].service {
                    if let Some(p) = self.config.park {
                        let h = self.config.homes[e];
                        if old != h && self.time - self.cars[e].idle_start >= p {
                            self.move_car(e, (h - old).signum());
                            if self.cars[e].floor == h {
                                self.emit(format!("E{} PARK {}", e + 1, h));
                            }
                        }
                    }
                }
            }
        }
        if self.cars[e].door > 0 || self.cars[e].floor != old {
            self.cars[e].busy += 1;
        }
    }
    fn run(&mut self) {
        let mut index = 0;
        loop {
            if let Some(p) = self.config.patience {
                for g in 0..self.groups.len() {
                    if self.groups[g].waiting > 0 && self.time == self.groups[g].time + p {
                        self.walk(g, "ABANDON");
                    }
                }
            }
            while index < self.events.len() && self.events[index].time == self.time {
                self.execute(self.events[index].clone());
                index += 1;
            }
            for e in 0..self.cars.len() {
                self.advance(e);
            }
            let settled = self.cars.iter().enumerate().all(|(e, c)| c.door == 0 && c.passengers.is_empty() && c.calls.is_empty() && self.fire.map_or_else(|| !c.service || self.config.park.is_none() || c.floor == self.config.homes[e], |f| c.floor == f));
            if index == self.events.len() && settled {
                self.status = "end".into();
                self.emit("END".into());
                break;
            }
            if self.time == self.config.limit {
                self.status = "abort".into();
                self.emit("ABORT".into());
                break;
            }
            self.time += 1;
        }
    }
    fn averages(&self) -> String {
        format!("avg_wait={} avg_travel={} max_wait={}", average(self.wait_total, self.delivered), average(self.travel_total, self.delivered), if self.delivered == 0 {
            "-".into()
        } else {
            self.max_wait.to_string()
        })
    }
    fn breakdown(&self, label: String, gs: Vec<&Group>) -> String {
        format!("{}: groups={} passengers={} delivered={} avg_wait={}", label, gs.len(), gs.iter().map(|g| g.count).sum::<i64>(), gs.iter().map(|g| g.delivered).sum::<i64>(), average(gs.iter().map(|g| g.wait_total).sum(), gs.iter().map(|g| g.delivered).sum()))
    }
    fn report(&self) -> Vec<String> {
        let mut out = vec![];
        for (g, x) in self.groups.iter().enumerate() {
            out.push(format!("G{} t={} {}->{} n={} delivered={} lost={} wait={} travel={} cars={}", g + 1, x.time, x.a, x.b, x.count, x.delivered, x.lost, if x.boarded == x.count {
                (x.last_board - x.time).to_string()
            } else {
                "-".into()
            }, if x.delivered == x.count {
                (x.last_alight - x.time).to_string()
            } else {
                "-".into()
            }, joined(x.cars.iter().map(|e| e.to_string()).collect())));
        }
        for (e, c) in self.cars.iter().enumerate() {
            let x = c.busy * 1000 / (self.time + 1);
            out.push(format!("E{} distance={} stops={} boarded={} busy={} util={}.{}% energy={}", e + 1, c.distance, c.stops, c.boarded, c.busy, x / 10, x % 10, c.energy));
        }
        for f in self.groups.iter().map(|g| g.a).collect::<BTreeSet<_>>() {
            out.push(self.breakdown(format!("F{}", f), self.groups.iter().filter(|g| g.a == f).collect()));
        }
        if let Some(w) = self.config.period {
            for k in self.groups.iter().map(|g| g.time / w).collect::<BTreeSet<_>>() {
                out.push(self.breakdown(format!("P{} {}-{}", k, k * w, k * w + w - 1), self.groups.iter().filter(|g| g.time / w == k).collect()));
            }
        }
        out.push(format!("summary: groups={} passengers={} delivered={} abandoned={} evacuated={} {} end={}", self.groups.len(), self.groups.iter().map(|g| g.count).sum::<i64>(), self.delivered, self.abandoned, self.evacuated, self.averages(), self.time));
        out
    }
}
struct Scenario {
    name: String,
    config: Option<Config>,
    simulation: Option<Simulation>,
}
impl Scenario {
    fn outcome(&self) -> &str {
        match &self.simulation {
            None => "invalid", Some(s) if s.status == "abort" => "aborted", Some(s) if s.delivered == 0 => "empty", _ => "ranked"
        }
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let lines: Vec<&str> = input.lines().collect();
    let q: usize = lines[0].parse().unwrap();
    let mut index = 1;
    let mut scenarios = vec![];
    let mut out = vec![];
    for _ in 0..q {
        let name = lines[index].split(' ').nth(1).unwrap().to_string();
        index += 1;
        let mut settings = vec![];
        let mut raw = vec![];
        while lines[index] != "END" {
            let w: Vec<&str> = lines[index].split(' ').collect();
            if w[0].as_bytes()[0].is_ascii_digit() {
                raw.push((index + 1, w));
            } else {
                settings.push(w);
            }
            index += 1;
        }
        index += 1;
        out.push(format!("== {} ==", name));
        match Config::parse(&settings) {
            Err(e) => {
                out.push(format!("error: {}", e));
                scenarios.push(Scenario {
                    name, config: None, simulation: None
                });
            }
            Ok(c) => {
                out.extend(c.header());
                let events = validate(&c, &raw, &mut out);
                let mut sim = Simulation::new(&c, &events, &c.policy);
                sim.run();
                out.extend(sim.log.clone());
                out.extend(sim.report());
                for p in &c.compare {
                    let mut r = Simulation::new(&c, &events, p);
                    r.run();
                    out.push(format!("compare {}: delivered={} {} end={} status={}", p, r.delivered, r.averages(), r.time, r.status));
                }
                scenarios.push(Scenario {
                    name, config: Some(c), simulation: Some(sim)
                });
            }
        }
    }
    out.push("== ranking ==".into());
    let mut ranked: Vec<usize> = (0..scenarios.len()).filter(|&i| scenarios[i].outcome() == "ranked").collect();
    ranked.sort_by(|&a, &b| {
        let x = scenarios[a].simulation.as_ref().unwrap();
        let y = scenarios[b].simulation.as_ref().unwrap();
        (x.wait_total * y.delivered).cmp(&(y.wait_total * x.delivered)).then((x.travel_total * y.delivered).cmp(&(y.travel_total * x.delivered))).then(a.cmp(&b))
    });
    for (i, &j) in ranked.iter().enumerate() {
        let s = &scenarios[j];
        out.push(format!("{}. {} policy={} {}", i + 1, s.name, s.config.as_ref().unwrap().policy, s.simulation.as_ref().unwrap().averages()));
    }
    for s in &scenarios {
        if s.outcome() != "ranked" {
            out.push(format!("- {} {}", s.name, s.outcome()));
        }
    }
    out.push("== policies ==".into());
    for p in POLICIES {
        let runs: Vec<&Simulation> = ranked.iter().filter(|&&i| scenarios[i].config.as_ref().unwrap().policy == p).map(|&i| scenarios[i].simulation.as_ref().unwrap()).collect();
        if !runs.is_empty() {
            let n = runs.iter().map(|r| r.delivered).sum();
            out.push(format!("{}: runs={} avg_wait={} avg_travel={}", p, runs.len(), average(runs.iter().map(|r| r.wait_total).sum(), n), average(runs.iter().map(|r| r.travel_total).sum(), n)));
        }
    }
    println!("{}", out.join("\n"));
}
