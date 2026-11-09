use std::collections::BTreeMap;
use std::fmt;
use std::io::{self, BufRead, Write};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode { Chain, Linear, Quadratic, Double, RobinHood, Cuckoo }

impl Mode {
    const ALL: [Self; 6] = [Self::Chain, Self::Linear, Self::Quadratic, Self::Double, Self::RobinHood, Self::Cuckoo];
    fn name(self) -> &'static str {
        match self {
            Self::Chain => "CHAIN", Self::Linear => "LINEAR", Self::Quadratic => "QUADRATIC",
            Self::Double => "DOUBLE", Self::RobinHood => "ROBINHOOD", Self::Cuckoo => "CUCKOO",
        }
    }
    fn parse(text: &str) -> Result<Self, String> {
        Self::ALL.iter().copied().find(|mode| mode.name() == text).ok_or_else(|| format!("BAD MODE {text}"))
    }
}

#[derive(Clone)]
struct Item { key: String, value: i64 }
impl fmt::Display for Item {
    fn fmt(&self, output: &mut fmt::Formatter<'_>) -> fmt::Result { write!(output, "{}={}", self.key, self.value) }
}
#[derive(Clone, Default)]
enum Slot { #[default] Empty, Tomb, Live(Item) }
impl Slot {
    fn content(&self) -> &str {
        match self { Self::Empty => "-", Self::Tomb => "D", Self::Live(item) => &item.key }
    }
}
#[derive(Default)]
struct Counters { probes: i64, rehashes: i64, inserts: i64, updates: i64, hits: i64, misses: i64, deletes: i64, absent: i64 }
#[derive(Clone, Copy)]
struct Location { position: usize, chain_index: usize }
#[derive(Default)]
struct Search { found: Option<Location>, available: Option<usize>, probes: usize, path: Vec<String> }
#[derive(Default)]
struct Placement { position: Option<usize>, pending: Option<Item>, reused: bool, movements: usize, moves: Vec<String> }
struct Record { item: Item, position: usize, cost: usize }
#[derive(Clone, Copy, PartialEq, Eq)]
enum Reporting { Silent, Rehashes, Full(bool) }
impl Reporting {
    fn trace(self) -> bool { self == Self::Full(true) }
    fn details(self) -> bool { matches!(self, Self::Full(_)) }
}

fn hash(key: &str, base: usize, modulus: usize) -> usize {
    key.bytes().fold(0, |value, ch| (value * base + ch as usize) % modulus)
}
fn prime(value: usize) -> bool {
    if value < 2 { return false; }
    let mut divisor = 2;
    while divisor <= value / divisor {
        if value % divisor == 0 { return false; }
        divisor += 1;
    }
    true
}
fn next_prime(mut value: usize) -> usize {
    value = value.max(2);
    while !prime(value) { value += 1; }
    value
}
fn decimal(numerator: i64, denominator: i64) -> String {
    let value = if denominator == 0 { 0 } else { 100 * numerator / denominator };
    format!("{}.{:02}", value / 100, value % 100)
}
fn gauge(value: usize) -> char { if value < 10 { (b'0' + value as u8) as char } else { '+' } }
fn histogram(values: impl IntoIterator<Item = usize>) -> Vec<String> {
    let mut frequencies = BTreeMap::<usize, usize>::new();
    for value in values { *frequencies.entry(value).or_default() += 1; }
    frequencies.into_iter().map(|(value, count)| {
        format!("{value} {count} {}{}", "#".repeat(count.min(50)), if count > 50 { "+" } else { "" })
    }).collect()
}
fn generate(count: usize, length: usize, mut seed: i64) -> Vec<String> {
    (0..count).map(|_| (0..length).map(|_| {
        seed = 48271 * seed % 2147483647;
        (b'a' + (seed % 26) as u8) as char
    }).collect()).collect()
}
fn capacity(value: i64) -> Result<usize, String> {
    if !(2..=10000).contains(&value) { return Err("BAD CAPACITY".into()); }
    Ok(value as usize)
}
fn generation(count: i64, length: i64, seed: i64) -> Result<(usize, usize, i64), String> {
    if !(1..=500).contains(&count) || !(1..=10).contains(&length) || !(1..=2147483646).contains(&seed) {
        return Err("BAD ARGUMENT".into());
    }
    Ok((count as usize, length as usize, seed))
}

struct Table {
    mode: Mode,
    cap: usize,
    size: usize,
    tomb: usize,
    buckets: Vec<Vec<Item>>,
    slots: Vec<Slot>,
    counters: Counters,
}

impl Table {
    fn new(mode: Mode, cap: usize) -> Self {
        Self {
            mode, cap, size: 0, tomb: 0, counters: Counters::default(),
            buckets: if mode == Mode::Chain { vec![Vec::new(); cap] } else { Vec::new() },
            slots: if mode == Mode::Chain { Vec::new() } else { vec![Slot::Empty; cap * if mode == Mode::Cuckoo { 2 } else { 1 }] },
        }
    }
    fn slot_count(&self) -> usize { self.cap * if self.mode == Mode::Cuckoo { 2 } else { 1 } }
    fn position(&self, position: usize) -> String {
        if self.mode == Mode::Cuckoo { format!("T{}.{}", position / self.cap + 1, position % self.cap) }
        else { position.to_string() }
    }
    fn distance(&self, item: &Item, position: usize) -> usize { (position + self.cap - hash(&item.key, 31, self.cap)) % self.cap }
    fn items(&self) -> Vec<Item> {
        if self.mode == Mode::Chain { self.buckets.iter().flatten().cloned().collect() }
        else { self.slots.iter().filter_map(|slot| if let Slot::Live(item) = slot { Some(item.clone()) } else { None }).collect() }
    }
    fn observe(&self, search: &mut Search, position: usize, content: &str, trace: bool) {
        search.probes += 1;
        if trace { search.path.push(format!("{}:{content}", self.position(position))); }
    }
    fn search(&self, key: &str, trace: bool) -> Search {
        let mut result = Search::default();
        let home = hash(key, 31, self.cap);
        if self.mode == Mode::Chain {
            for (index, item) in self.buckets[home].iter().enumerate() {
                self.observe(&mut result, home, &item.key, trace);
                if item.key == key { result.found = Some(Location { position: home, chain_index: index }); break; }
            }
            return result;
        }
        let step = if self.mode == Mode::Double { 1 + hash(key, 37, self.cap - 1) } else { 1 };
        let limit = if self.mode == Mode::Cuckoo { 2 } else { self.cap };
        for i in 0..limit {
            let position = if self.mode == Mode::Cuckoo {
                if i == 0 { home } else { self.cap + hash(key, 37, self.cap) }
            } else { (home + if self.mode == Mode::Quadratic { i * i } else { i * step }) % self.cap };
            let slot = &self.slots[position];
            self.observe(&mut result, position, slot.content(), trace);
            if let Slot::Live(item) = slot {
                if item.key == key { result.found = Some(Location { position, chain_index: 0 }); break; }
            }
            if self.mode == Mode::Cuckoo { continue; }
            match slot {
                Slot::Empty => { result.available.get_or_insert(position); break; }
                Slot::Tomb => { result.available.get_or_insert(position); }
                Slot::Live(item) => {
                    if self.mode == Mode::RobinHood && self.distance(item, position) < i { break; }
                }
            }
        }
        result
    }
    fn item(&self, location: Location) -> &Item {
        if self.mode == Mode::Chain { &self.buckets[location.position][location.chain_index] }
        else if let Slot::Live(item) = &self.slots[location.position] { item }
        else { unreachable!() }
    }
    fn place(&mut self, item: Item, initial: Option<&Search>, trace: bool) -> Placement {
        let mut result = Placement::default();
        let home = hash(&item.key, 31, self.cap);
        if self.mode == Mode::Chain {
            self.buckets[home].push(item);
            result.position = Some(home);
            return result;
        }
        if matches!(self.mode, Mode::Linear | Mode::Quadratic | Mode::Double) {
            let available = match initial { Some(search) => search.available, None => self.search(&item.key, false).available };
            if let Some(position) = available {
                result.reused = matches!(self.slots[position], Slot::Tomb);
                if result.reused { self.tomb -= 1; }
                self.slots[position] = Slot::Live(item);
                result.position = Some(position);
            } else { result.pending = Some(item); }
            return result;
        }
        let original_key = item.key.clone();
        let mut carried = item;
        if self.mode == Mode::RobinHood {
            let (mut position, mut traveled) = (home, 0);
            let mut from: Option<usize> = None;
            loop {
                if matches!(self.slots[position], Slot::Empty) {
                    if trace {
                        if let Some(source) = from { result.moves.push(format!("SHIFT {} {source} -> {position}", carried.key)); }
                    }
                    self.slots[position] = Slot::Live(carried);
                    result.position.get_or_insert(position);
                    return result;
                }
                let resident_distance = match &self.slots[position] {
                    Slot::Live(resident) => self.distance(resident, position), _ => unreachable!(),
                };
                if resident_distance < traveled {
                    if trace {
                        if let Some(source) = from { result.moves.push(format!("SHIFT {} {source} -> {position}", carried.key)); }
                    }
                    let Slot::Live(displaced) = std::mem::replace(&mut self.slots[position], Slot::Live(carried)) else { unreachable!() };
                    carried = displaced;
                    result.position.get_or_insert(position);
                    from = Some(position);
                    traveled = resident_distance;
                    result.movements += 1;
                }
                position = (position + 1) % self.cap;
                traveled += 1;
            }
        }
        let mut part = 0;
        loop {
            let position = part * self.cap + hash(&carried.key, if part == 0 { 31 } else { 37 }, self.cap);
            if matches!(self.slots[position], Slot::Empty) {
                self.slots[position] = Slot::Live(carried);
                result.position = Some(self.search(&original_key, false).found.unwrap().position);
                return result;
            }
            if result.movements == self.cap { result.pending = Some(carried); return result; }
            let Slot::Live(displaced) = std::mem::replace(&mut self.slots[position], Slot::Live(carried)) else { unreachable!() };
            if trace { result.moves.push(format!("KICK {} {}", displaced.key, self.position(position))); }
            carried = displaced;
            result.movements += 1;
            part = 1 - part;
        }
    }
    fn remove(&mut self, location: Location, trace: bool) -> (usize, Vec<String>) {
        let mut shifted = 0;
        let mut moves = Vec::new();
        let position = location.position;
        if self.mode == Mode::Chain { self.buckets[position].remove(location.chain_index); }
        else if matches!(self.mode, Mode::Linear | Mode::Quadratic | Mode::Double) {
            self.slots[position] = Slot::Tomb;
            self.tomb += 1;
        } else {
            self.slots[position] = Slot::Empty;
            if self.mode == Mode::RobinHood {
                let mut source = (position + 1) % self.cap;
                while let Slot::Live(item) = &self.slots[source] {
                    if self.distance(item, source) == 0 { break; }
                    let destination = (source + self.cap - 1) % self.cap;
                    if trace { moves.push(format!("SHIFT {} {source} -> {destination}", item.key)); }
                    self.slots[destination] = std::mem::replace(&mut self.slots[source], Slot::Empty);
                    shifted += 1;
                    source = (source + 1) % self.cap;
                }
            }
        }
        self.size -= 1;
        (shifted, moves)
    }
    fn rebuilt(mode: Mode, cap: usize, items: &[Item]) -> Option<Self> {
        let mut table = Self::new(mode, cap);
        for item in items {
            table.place(item.clone(), None, false).position?;
            table.size += 1;
        }
        Some(table)
    }
    fn adopt(&mut self, mut replacement: Self) {
        replacement.counters = std::mem::take(&mut self.counters);
        *self = replacement;
    }
    fn automatic(&mut self, mut cap: usize, reason: &str, pending: Option<Item>) -> String {
        let old = self.cap;
        let mut items = self.items();
        if let Some(item) = pending { items.push(item); }
        loop {
            if let Some(replacement) = Self::rebuilt(self.mode, cap, &items) {
                self.adopt(replacement);
                self.counters.rehashes += 1;
                return format!("REHASH {reason} {old} -> {cap}");
            }
            cap = next_prime(2 * cap);
        }
    }
    fn load_check(&mut self, maximum: usize) -> Option<String> {
        let threshold = maximum * self.slot_count();
        if (self.size + self.tomb) * 100 <= threshold { return None; }
        let grow = self.size * 200 > threshold;
        Some(self.automatic(if grow { next_prime(2 * self.cap) } else { self.cap }, if grow { "load" } else { "tomb" }, None))
    }
    fn shrink_check(&mut self, minimum: usize, maximum: usize) -> Option<String> {
        let cap = next_prime(self.cap / 2);
        let slots = cap * if self.mode == Mode::Cuckoo { 2 } else { 1 };
        if self.size * 100 >= minimum * self.slot_count() || cap >= self.cap || self.size * 100 > maximum * slots { return None; }
        let replacement = Self::rebuilt(self.mode, cap, &self.items())?;
        let old = self.cap;
        self.adopt(replacement);
        self.counters.rehashes += 1;
        Some(format!("REHASH shrink {old} -> {cap}"))
    }
    fn path_line(search: &Search) -> String {
        format!("PATH {}", if search.path.is_empty() { "none".to_owned() } else { search.path.join(" ") })
    }
    fn put(&mut self, item: Item, add: bool, maximum: usize, reporting: Reporting) -> (bool, Vec<String>) {
        let search = self.search(&item.key, reporting.trace());
        self.counters.probes += search.probes as i64;
        let command = if add { "ADD" } else { "PUT" };
        let mut lines = Vec::new();
        if let Some(location) = search.found {
            let old = self.item(location).value;
            let stored = Item { key: item.key, value: if add { old + item.value } else { item.value } };
            if reporting.details() {
                lines.push(format!("{command} {stored} UPDATED old={old} at={} probes={}", self.position(location.position), search.probes));
            }
            if self.mode == Mode::Chain { self.buckets[location.position][location.chain_index] = stored; }
            else { self.slots[location.position] = Slot::Live(stored); }
            self.counters.updates += 1;
            if reporting.trace() { lines.push(Self::path_line(&search)); }
            return (false, lines);
        }
        let mut row = if reporting.details() { format!("{command} {item} NEW") } else { String::new() };
        let placed = self.place(item, Some(&search), reporting.trace());
        self.counters.inserts += 1;
        if reporting.details() {
            if let Some(position) = placed.position {
                row.push_str(&format!(" at={} probes={}", self.position(position), search.probes));
                if placed.reused { row.push_str(" reused"); }
                if self.mode == Mode::RobinHood { row.push_str(&format!(" shifted={}", placed.movements)); }
                if self.mode == Mode::Cuckoo { row.push_str(&format!(" kicks={}", placed.movements)); }
            } else {
                row.push_str(&format!(" probes={}", search.probes));
                if self.mode == Mode::Quadratic { row.push_str(" full"); }
                else { row.push_str(&format!(" kicks={} failed", placed.movements)); }
            }
            lines.push(row);
        }
        if reporting.trace() { lines.push(Self::path_line(&search)); lines.extend(placed.moves); }
        if placed.position.is_some() { self.size += 1; }
        else {
            let rehash = self.automatic(next_prime(2 * self.cap), if self.mode == Mode::Quadratic { "full" } else { "kicks" }, placed.pending);
            if reporting != Reporting::Silent { lines.push(rehash); }
        }
        if let Some(rehash) = self.load_check(maximum) {
            if reporting != Reporting::Silent { lines.push(rehash); }
        }
        (true, lines)
    }
    fn delete(&mut self, key: &str, minimum: usize, maximum: usize, reporting: Reporting) -> (bool, Vec<String>) {
        let search = self.search(key, reporting.trace());
        self.counters.probes += search.probes as i64;
        let mut lines = Vec::new();
        if let Some(location) = search.found {
            let (shifted, moves) = self.remove(location, reporting.trace());
            self.counters.deletes += 1;
            if reporting.details() {
                let mut row = format!("DEL {key} OK at={} probes={}", self.position(location.position), search.probes);
                if self.mode == Mode::RobinHood { row.push_str(&format!(" shifted={shifted}")); }
                lines.push(row);
            }
            if reporting.trace() { lines.push(Self::path_line(&search)); lines.extend(moves); }
            if let Some(rehash) = self.shrink_check(minimum, maximum) {
                if reporting != Reporting::Silent { lines.push(rehash); }
            }
            (true, lines)
        } else {
            self.counters.absent += 1;
            if reporting.details() { lines.push(format!("DEL {key} NOT FOUND probes={}", search.probes)); }
            if reporting.trace() { lines.push(Self::path_line(&search)); }
            (false, lines)
        }
    }
    fn get(&mut self, key: &str, trace: bool) -> Vec<String> {
        let search = self.search(key, trace);
        self.counters.probes += search.probes as i64;
        let row = if let Some(location) = search.found {
            self.counters.hits += 1;
            format!("GET {} at={} probes={}", self.item(location), self.position(location.position), search.probes)
        } else {
            self.counters.misses += 1;
            format!("GET {key} NOT FOUND probes={}", search.probes)
        };
        let mut lines = vec![row];
        if trace { lines.push(Self::path_line(&search)); }
        lines
    }
    fn records(&self) -> Vec<Record> {
        let mut records = Vec::with_capacity(self.size);
        if self.mode == Mode::Chain {
            for (position, bucket) in self.buckets.iter().enumerate() {
                for (index, item) in bucket.iter().enumerate() { records.push(Record { item: item.clone(), position, cost: index + 1 }); }
            }
        } else {
            for (position, slot) in self.slots.iter().enumerate() {
                if let Slot::Live(item) = slot {
                    let cost = match self.mode {
                        Mode::Cuckoo => position / self.cap + 1,
                        Mode::Linear | Mode::RobinHood => self.distance(item, position) + 1,
                        _ => self.search(&item.key, false).probes,
                    };
                    records.push(Record { item: item.clone(), position, cost });
                }
            }
        }
        records
    }
    fn metrics(&self) -> (usize, String) {
        let records = self.records();
        (records.iter().map(|record| record.cost).max().unwrap_or(0),
            decimal(records.iter().map(|record| record.cost as i64).sum(), self.size as i64))
    }
    fn dump(&self) -> Vec<String> {
        let mut lines = vec![format!("DUMP {} cap={} size={} tomb={}", self.mode.name(), self.cap, self.size, self.tomb)];
        if self.mode == Mode::Chain {
            for (position, bucket) in self.buckets.iter().enumerate() {
                let content = if bucket.is_empty() { "-".into() } else { bucket.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ") };
                lines.push(format!("{position} {content}"));
            }
        } else {
            for (position, slot) in self.slots.iter().enumerate() {
                let prefix = if self.mode == Mode::Cuckoo { format!("T{} {}", position / self.cap + 1, position % self.cap) } else { position.to_string() };
                let content = match slot {
                    Slot::Live(item) if self.mode == Mode::RobinHood => format!("{item} d={}", self.distance(item, position)),
                    Slot::Live(item) => item.to_string(), _ => slot.content().to_owned(),
                };
                lines.push(format!("{prefix} {content}"));
            }
        }
        lines
    }
    fn map(&self) -> Vec<String> {
        let mut lines = vec![format!("MAP {} cap={}", self.mode.name(), self.cap)];
        let mut costs = vec![0; self.slot_count()];
        if self.mode != Mode::Chain { for record in self.records() { costs[record.position] = record.cost; } }
        for part in 0..if self.mode == Mode::Cuckoo { 2 } else { 1 } {
            for start in (0..self.cap).step_by(40) {
                let mut text = String::new();
                for index in start..(start + 40).min(self.cap) {
                    let ch = if self.mode == Mode::Chain {
                        if self.buckets[index].is_empty() { '.' } else { gauge(self.buckets[index].len()) }
                    } else {
                        let position = part * self.cap + index;
                        match &self.slots[position] {
                            Slot::Empty => '.', Slot::Tomb => 'D',
                            Slot::Live(_) if self.mode == Mode::Cuckoo => '#', Slot::Live(_) => gauge(costs[position] - 1),
                        }
                    };
                    text.push(ch);
                }
                let prefix = if self.mode == Mode::Cuckoo { format!("T{} ", part + 1) } else { String::new() };
                lines.push(format!("{prefix}{start:05} {text}"));
            }
        }
        lines
    }
    fn statistics(&self) -> Vec<String> {
        let (longest, average) = self.metrics();
        let c = &self.counters;
        vec![format!("STATS {} size={} cap={} slots={} tomb={} load={}% longest={longest} avg={average} probes={} rehashes={}",
            self.mode.name(), self.size, self.cap, self.slot_count(), self.tomb, decimal(100 * self.size as i64, self.slot_count() as i64), c.probes, c.rehashes),
            format!("OPS inserts={} updates={} hits={} misses={} deletes={} absent={}", c.inserts, c.updates, c.hits, c.misses, c.deletes, c.absent)]
    }
    fn scan(&self, mut cursor: usize, limit: usize) -> String {
        let mut keys = Vec::new();
        while cursor < self.slot_count() && keys.len() < limit {
            if self.mode == Mode::Chain { keys.extend(self.buckets[cursor].iter().map(|item| item.key.as_str())); }
            else if let Slot::Live(item) = &self.slots[cursor] { keys.push(item.key.as_str()); }
            cursor += 1;
        }
        if cursor == self.slot_count() { cursor = 0; }
        let mut line = format!("SCAN next={cursor}");
        for key in keys { line.push(' '); line.push_str(key); }
        line
    }
    fn clusters(&self) -> Vec<String> {
        let mut runs = Vec::new();
        if self.mode == Mode::Chain { runs.extend(self.buckets.iter().filter(|bucket| !bucket.is_empty()).map(Vec::len)); }
        else {
            for part in self.slots.chunks(self.cap) {
                if let Some(empty) = part.iter().position(|slot| matches!(slot, Slot::Empty)) {
                    let mut length = 0;
                    for offset in 1..=self.cap {
                        if !matches!(part[(empty + offset) % self.cap], Slot::Empty) { length += 1; }
                        else if length > 0 { runs.push(length); length = 0; }
                    }
                } else { runs.push(self.cap); }
            }
        }
        let mut lines = vec![format!("CLUSTERS runs={} longest={}", runs.len(), runs.iter().max().unwrap_or(&0))];
        lines.extend(histogram(runs));
        lines
    }
    fn distribution(&self) -> Vec<String> {
        let values: Vec<_> = self.records().into_iter().map(|record| record.cost).collect();
        let mut lines = vec![format!("DIST keys={} longest={}", self.size, values.iter().max().unwrap_or(&0))];
        lines.extend(histogram(values));
        lines
    }
}

fn compare(table: &Table, cap: usize, maximum: usize) -> Vec<String> {
    let mut items = table.items();
    items.sort_by(|a, b| a.key.cmp(&b.key));
    let mut lines = vec![format!("COMPARE keys={} cap={cap}", items.len())];
    for mode in Mode::ALL {
        let mut trial = Table::new(mode, cap);
        for item in &items { trial.put(item.clone(), false, maximum, Reporting::Silent); }
        let (longest, average) = trial.metrics();
        lines.push(format!("{} cap={} longest={longest} avg={average} probes={} rehashes={}",
            mode.name(), trial.cap, trial.counters.probes, trial.counters.rehashes));
    }
    lines
}
fn benchmark(cap: usize, count: usize, length: usize, seed: i64, maximum: usize) -> Vec<String> {
    let keys = generate(2 * count, length, seed);
    let mut lines = vec![format!("BENCH cap={cap} count={count} len={length} seed={seed}")];
    for mode in Mode::ALL {
        let mut trial = Table::new(mode, cap);
        for (index, key) in keys[..count].iter().enumerate() {
            trial.put(Item { key: key.clone(), value: index as i64 + 1 }, false, maximum, Reporting::Silent);
        }
        let (mut misses, mut probes) = (0, 0);
        for key in &keys[count..] {
            let search = trial.search(key, false);
            if search.found.is_none() { misses += 1; probes += search.probes as i64; }
        }
        lines.push(format!("{} cap={} keys={} hit={} misses={misses} miss={} rehashes={}",
            mode.name(), trial.cap, trial.size, trial.metrics().1, decimal(probes, misses), trial.counters.rehashes));
    }
    lines
}

struct Simulator { table: Option<Table>, maximum: usize, minimum: usize, trace: bool }
impl Simulator {
    fn execute(&mut self, line: &str) -> Result<Vec<String>, String> {
        let words: Vec<_> = line.split(' ').collect();
        let command = words[0];
        let number = |index: usize| words[index].parse::<i64>().unwrap();
        if !matches!(command, "CREATE" | "MAXLOAD" | "MINLOAD" | "TRACE" | "HASH" | "PUT" | "ADD" | "GET" | "DEL" |
            "PROBE" | "GEN" | "GENDEL" | "RESIZE" | "CONVERT" | "CLEAR" | "DUMP" | "MAP" | "STATS" | "KEYS" |
            "TOP" | "SCAN" | "CLUSTERS" | "DIST" | "COMPARE" | "BENCH") {
            return Err(format!("UNKNOWN COMMAND {command}"));
        }
        match command {
            "CREATE" => {
                let mode = Mode::parse(words[1])?;
                let cap = next_prime(capacity(number(2))?);
                self.table = Some(Table::new(mode, cap));
                return Ok(vec![format!("CREATE {} cap={cap}", mode.name())]);
            }
            "MAXLOAD" | "MINLOAD" => {
                let value = number(1);
                let range = if command == "MAXLOAD" { 10..=95 } else { 0..=40 };
                if !range.contains(&value) { return Err("BAD LOAD".into()); }
                if command == "MAXLOAD" { self.maximum = value as usize; } else { self.minimum = value as usize; }
                return Ok(vec![format!("{command} {value}")]);
            }
            "TRACE" => {
                if !matches!(words[1], "ON" | "OFF") { return Err("BAD ARGUMENT".into()); }
                self.trace = words[1] == "ON";
                return Ok(vec![format!("TRACE {}", words[1])]);
            }
            "HASH" => {
                let cap = capacity(number(2))?;
                let key = words[1];
                return Ok(vec![format!("HASH {key} m={cap} h31={} h37={} step={}", hash(key, 31, cap), hash(key, 37, cap), 1 + hash(key, 37, cap - 1))]);
            }
            "BENCH" => {
                let cap = next_prime(capacity(number(1))?);
                let (count, length, seed) = generation(number(2), number(3), number(4))?;
                return Ok(benchmark(cap, count, length, seed, self.maximum));
            }
            _ => {}
        }
        let table = self.table.as_mut().ok_or_else(|| "NO TABLE".to_owned())?;
        let lines = match command {
            "PUT" | "ADD" => table.put(Item { key: words[1].into(), value: number(2) }, command == "ADD", self.maximum, Reporting::Full(self.trace)).1,
            "GET" => table.get(words[1], self.trace),
            "DEL" => table.delete(words[1], self.minimum, self.maximum, Reporting::Full(self.trace)).1,
            "PROBE" => {
                let search = table.search(words[1], true);
                let mut row = format!("PROBE {}", words[1]);
                for element in search.path { row.push(' '); row.push_str(&element); }
                row.push_str(&format!(" {} probes={}", if search.found.is_some() { "FOUND" } else { "MISS" }, search.probes));
                vec![row]
            }
            "GEN" | "GENDEL" => {
                let (count, length, seed) = generation(number(1), number(2), number(3))?;
                let mut lines = Vec::new();
                let mut changed = 0;
                for (index, key) in generate(count, length, seed).into_iter().enumerate() {
                    let (did_change, output) = if command == "GEN" {
                        table.put(Item { key, value: index as i64 + 1 }, false, self.maximum, Reporting::Rehashes)
                    } else { table.delete(&key, self.minimum, self.maximum, Reporting::Rehashes) };
                    if did_change { changed += 1; }
                    lines.extend(output);
                }
                lines.push(if command == "GEN" { format!("GEN {count} new={changed} updated={}", count - changed) }
                    else { format!("GENDEL {count} deleted={changed} missing={}", count - changed) });
                lines
            }
            "RESIZE" | "CONVERT" => {
                let cap = if command == "RESIZE" { next_prime(capacity(number(1))?) } else { table.cap };
                let mode = if command == "CONVERT" { Mode::parse(words[1])? } else { table.mode };
                let slots = cap * if mode == Mode::Cuckoo { 2 } else { 1 };
                if table.size * 100 > self.maximum * slots { return Err("TOO SMALL".into()); }
                let replacement = Table::rebuilt(mode, cap, &table.items()).ok_or_else(|| "REBUILD FAILED".to_owned())?;
                let row = if command == "RESIZE" { format!("RESIZE {} -> {cap}", table.cap) }
                    else { format!("CONVERT {} -> {} cap={cap}", table.mode.name(), mode.name()) };
                table.adopt(replacement);
                vec![row]
            }
            "CLEAR" => {
                let row = format!("CLEAR {}", table.size);
                table.adopt(Table::new(table.mode, table.cap));
                vec![row]
            }
            "DUMP" => table.dump(), "MAP" => table.map(), "STATS" => table.statistics(),
            "KEYS" => {
                let mut keys: Vec<_> = table.items().into_iter().map(|item| item.key).collect();
                keys.sort();
                let mut row = format!("KEYS {}", keys.len());
                for key in keys { row.push(' '); row.push_str(&key); }
                vec![row]
            }
            "TOP" => {
                let limit = number(1);
                if !(1..=100).contains(&limit) { return Err("BAD ARGUMENT".into()); }
                let mut records = table.records();
                records.sort_by(|a, b| b.cost.cmp(&a.cost).then_with(|| a.item.key.cmp(&b.item.key)));
                records.truncate(limit as usize);
                let mut lines = vec![format!("TOP {}", records.len())];
                lines.extend(records.into_iter().map(|record| format!("{} cost={} at={}", record.item.key, record.cost, table.position(record.position))));
                lines
            }
            "SCAN" => {
                let (cursor, limit) = (number(1), number(2));
                if !(1..=100).contains(&limit) { return Err("BAD ARGUMENT".into()); }
                if cursor >= table.slot_count() as i64 { return Err("BAD CURSOR".into()); }
                vec![table.scan(cursor as usize, limit as usize)]
            }
            "CLUSTERS" => table.clusters(), "DIST" => table.distribution(),
            "COMPARE" => compare(table, next_prime(capacity(number(1))?), self.maximum),
            _ => unreachable!(),
        };
        Ok(lines)
    }
}

fn main() {
    let stdin = io::stdin();
    let mut input = stdin.lock().lines();
    let Some(Ok(first)) = input.next() else { return; };
    let count: usize = first.parse().unwrap();
    let mut simulator = Simulator { table: None, maximum: 75, minimum: 0, trace: false };
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    for line in input.take(count) {
        match simulator.execute(&line.unwrap()) {
            Ok(lines) => for line in lines { writeln!(output, "{line}").unwrap(); },
            Err(reason) => writeln!(output, "ERROR {reason}").unwrap(),
        }
    }
}
