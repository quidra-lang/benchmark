use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};

const METHODS: [&str; 10] = [
    "NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
    "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD",
];

fn ceiling(number: i64, denominator: i64) -> i64 {
    (number + denominator - 1) / denominator
}

#[derive(Clone, Copy)]
struct Item {
    number: usize,
    size: i64,
}

impl Item {
    fn text(self) -> String {
        format!("{}:{}", self.number, self.size)
    }
}

fn descending(items: &[Item]) -> Vec<Item> {
    let mut ordered = items.to_vec();
    ordered.sort_by_key(|item| (-item.size, item.number));
    ordered
}

#[derive(Clone, Default)]
struct Bin {
    items: Vec<Item>,
    load: i64,
    category: usize,
}

impl Bin {
    fn new(category: usize) -> Self {
        Self {
            category,
            ..Self::default()
        }
    }

    fn put(&mut self, item: Item) {
        self.items.push(item);
        self.load += item.size;
    }
}

struct Step {
    item: Item,
    bin: usize,
    inspected: usize,
    opened: bool,
    closed: Option<usize>,
    category: usize,
}

struct Packing {
    method: String,
    parameter: usize,
    bins: Vec<Bin>,
    steps: Vec<Step>,
    inspections: usize,
    closes: usize,
}

impl Packing {
    fn new(method: &str, parameter: usize) -> Self {
        Self {
            method: method.to_owned(),
            parameter,
            bins: Vec::new(),
            steps: Vec::new(),
            inspections: 0,
            closes: 0,
        }
    }

    fn name(&self) -> String {
        if self.method == "HARMONIC" || self.method == "KBOUNDED" {
            format!("{} k={}", self.method, self.parameter)
        } else {
            self.method.clone()
        }
    }

    fn header(&self, capacity: i64, total: i64) -> String {
        let mut line = format!(
            "{} bins={} inspections={} waste={}",
            self.name(), self.bins.len(), self.inspections,
            self.bins.len() as i64 * capacity - total
        );
        if self.method == "KBOUNDED" {
            line.push_str(&format!(" closes={}", self.closes));
        }
        line
    }
}

fn pack(items: &[Item], capacity: i64, method: &str, parameter: usize) -> Packing {
    let mut result = Packing::new(method, parameter);
    let ordered = if matches!(method, "FFD" | "BFD" | "WFD") {
        descending(items)
    } else {
        items.to_vec()
    };
    let mut active = Vec::<usize>::new();
    let mut current = BTreeMap::<usize, usize>::new();

    for item in ordered {
        let before = result.inspections;
        let mut chosen = None;
        let mut closed = None;
        let mut category = 0;
        match method {
            "NEXTFIT" => {
                if !result.bins.is_empty() {
                    result.inspections += 1;
                    let last = result.bins.len() - 1;
                    if result.bins[last].load + item.size <= capacity {
                        chosen = Some(last);
                    }
                }
            }
            "FIRSTFIT" | "FFD" | "KBOUNDED" => {
                let candidates: Vec<usize> = if method == "KBOUNDED" {
                    active.clone()
                } else {
                    (0..result.bins.len()).collect()
                };
                for index in candidates {
                    result.inspections += 1;
                    if result.bins[index].load + item.size <= capacity {
                        chosen = Some(index);
                        break;
                    }
                }
            }
            "HARMONIC" => {
                category = ((capacity / item.size) as usize).min(parameter);
                if let Some(&index) = current.get(&category) {
                    result.inspections += 1;
                    if result.bins[index].load + item.size <= capacity {
                        chosen = Some(index);
                    }
                }
            }
            _ => {
                result.inspections += result.bins.len();
                let mut fitting: Vec<usize> = (0..result.bins.len())
                    .filter(|&i| result.bins[i].load + item.size <= capacity)
                    .collect();
                if !fitting.is_empty() {
                    if matches!(method, "BESTFIT" | "BFD") {
                        chosen = fitting.into_iter()
                            .max_by_key(|&i| (result.bins[i].load, -(i as i64)));
                    } else {
                        fitting.sort_by_key(|&i| (result.bins[i].load, i));
                        chosen = Some(
                            if method == "ALMOSTWORST" && fitting.len() >= 2 {
                                fitting[1]
                            } else {
                                fitting[0]
                            },
                        );
                    }
                }
            }
        }

        let opened = chosen.is_none();
        let index = if let Some(index) = chosen {
            index
        } else {
            if method == "KBOUNDED" && active.len() == parameter {
                let remove = *active.iter().max_by_key(|&&i| {
                    (result.bins[i].load, -(i as i64))
                }).unwrap();
                active.retain(|&i| i != remove);
                result.closes += 1;
                closed = Some(remove);
            }
            let index = result.bins.len();
            result.bins.push(Bin::new(category));
            if method == "KBOUNDED" {
                active.push(index);
            } else if method == "HARMONIC" {
                current.insert(category, index);
            }
            index
        };
        result.bins[index].put(item);
        result.steps.push(Step {
            item,
            bin: index,
            inspected: result.inspections - before,
            opened,
            closed,
            category,
        });
    }
    result
}

struct BoundRow {
    alpha: i64,
    j1: usize,
    j2: usize,
    j3: usize,
    bound: i64,
}

struct Bounds {
    l1: i64,
    l2: i64,
    rows: Vec<BoundRow>,
}

fn lower_bounds(items: &[Item], capacity: i64) -> Bounds {
    let total: i64 = items.iter().map(|item| item.size).sum();
    let mut thresholds = BTreeSet::from([0]);
    for item in items {
        if 2 * item.size <= capacity {
            thresholds.insert(item.size);
        }
    }
    let mut lower = 0;
    let mut rows = Vec::new();
    for alpha in thresholds {
        let (mut j1, mut j2, mut j3) = (0, 0, 0);
        let (mut sum2, mut sum3) = (0, 0);
        for item in items {
            let size = item.size;
            if size > capacity - alpha {
                j1 += 1;
            } else if 2 * size > capacity {
                j2 += 1;
                sum2 += size;
            } else if size >= alpha {
                j3 += 1;
                sum3 += size;
            }
        }
        let excess = sum3 - (j2 as i64 * capacity - sum2);
        let bound = j1 as i64 + j2 as i64 +
            if excess > 0 { ceiling(excess, capacity) } else { 0 };
        lower = lower.max(bound);
        rows.push(BoundRow { alpha, j1, j2, j3, bound });
    }
    Bounds { l1: ceiling(total, capacity), l2: lower, rows }
}

struct ExactSearch<'a> {
    items: Vec<Item>,
    capacity: i64,
    limit: usize,
    lower: i64,
    remaining: Vec<i64>,
    best: Vec<Bin>,
    live: Vec<Bin>,
    nodes: usize,
    status: Option<&'static str>,
    events: Vec<String>,
    marker: std::marker::PhantomData<&'a ()>,
}

impl ExactSearch<'_> {
    fn new(items: &[Item], capacity: i64, limit: usize, lower: i64,
           incumbent: &[Bin]) -> Self {
        let ordered = descending(items);
        let mut remaining = vec![0; ordered.len() + 1];
        for i in (0..ordered.len()).rev() {
            remaining[i] = remaining[i + 1] + ordered[i].size;
        }
        Self {
            items: ordered,
            capacity,
            limit,
            lower,
            remaining,
            best: incumbent.to_vec(),
            live: Vec::new(),
            nodes: 0,
            status: None,
            events: Vec::new(),
            marker: std::marker::PhantomData,
        }
    }

    fn visit(&mut self, index: usize) {
        if self.nodes == self.limit {
            self.status = Some("limit");
            return;
        }
        self.nodes += 1;
        let count = self.live.len();
        let used = self.remaining[0] - self.remaining[index];
        let free = count as i64 * self.capacity - used;
        let excess = self.remaining[index] - free;
        let minimum = count as i64 +
            if excess > 0 { ceiling(excess, self.capacity) } else { 0 };
        if minimum >= self.best.len() as i64 {
            return;
        }
        if index == self.items.len() {
            self.best = self.live.clone();
            self.events.push(format!("IMPROVE bins={} nodes={}", count, self.nodes));
            if count as i64 == self.lower {
                self.status = Some("bound");
            }
            return;
        }
        let item = self.items[index];
        let mut seen = BTreeSet::new();
        for i in 0..self.live.len() {
            let old = self.live[i].load;
            if !seen.insert(old) || old + item.size > self.capacity {
                continue;
            }
            self.live[i].put(item);
            self.visit(index + 1);
            self.live[i].items.pop();
            self.live[i].load = old;
            if self.status.is_some() {
                return;
            }
        }
        if count + 1 < self.best.len() {
            let mut bin = Bin::default();
            bin.put(item);
            self.live.push(bin);
            self.visit(index + 1);
            self.live.pop();
        }
    }
}

#[derive(Clone, Copy)]
struct Rect {
    number: usize,
    width: usize,
    height: usize,
}

impl Rect {
    fn letter(self) -> char {
        (b'A' + self.number as u8 - 1) as char
    }

    fn area(self) -> usize {
        self.width * self.height
    }
}

#[derive(Clone)]
struct Placement {
    rect: Rect,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    rotated: bool,
}

struct Shelf {
    bottom: usize,
    height: usize,
    used: usize,
    placements: Vec<Placement>,
}

#[derive(Clone)]
struct FreeRect {
    x: usize,
    y: usize,
    width: usize,
    height: usize,
}

impl FreeRect {
    fn area(&self) -> usize {
        self.width * self.height
    }

    fn text(&self) -> String {
        format!("{},{},{}x{}", self.x, self.y, self.width, self.height)
    }
}

struct Sheet {
    free: Vec<FreeRect>,
    placements: Vec<Placement>,
    area: usize,
}

impl Sheet {
    fn new(width: usize, height: usize) -> Self {
        Self {
            free: vec![FreeRect { x: 0, y: 0, width, height }],
            placements: Vec::new(),
            area: 0,
        }
    }
}

struct Piece {
    length: i64,
    demand: usize,
}

struct Pattern {
    counts: Vec<usize>,
    trim: i64,
}

struct Lab {
    items: Option<Vec<Item>>,
    capacity: i64,
    output: Vec<String>,
}

impl Lab {
    fn new() -> Self {
        Self { items: None, capacity: 0, output: Vec::new() }
    }

    fn emit(&mut self, line: String) {
        self.output.push(line);
    }

    fn items(&self) -> &[Item] {
        self.items.as_deref().unwrap()
    }

    fn total(&self) -> i64 {
        self.items().iter().map(|item| item.size).sum()
    }

    fn parameter(method: &str, words: &[&str], index: usize) -> Result<usize, String> {
        if method != "HARMONIC" && method != "KBOUNDED" {
            return Ok(0);
        }
        let number: usize = words[index].parse().unwrap();
        if number == 0 {
            Err("BAD PARAMETER".into())
        } else {
            Ok(number)
        }
    }

    fn bin_line(&mut self, number: usize, bin: &Bin, capacity: i64,
                class: bool, over: bool) {
        let contents = bin.items.iter().map(|item| item.text())
            .collect::<Vec<_>>().join(" ");
        let mut line = format!(
            "BIN {} load={}/{} items={}", number, bin.load, capacity, contents
        );
        if class {
            line.push_str(&format!(" class={}", bin.category));
        }
        if over {
            line.push_str(" OVER");
        }
        self.emit(line);
    }

    fn bin_lines(&mut self, bins: &[Bin], class: bool) {
        for (index, bin) in bins.iter().enumerate() {
            self.bin_line(index + 1, bin, self.capacity, class, false);
        }
    }

    fn cmd_items(&mut self, words: &[&str]) -> Result<(), String> {
        let capacity: i64 = words[1].parse().unwrap();
        if capacity == 0 {
            return Err("BAD CAPACITY".into());
        }
        let mut next = Vec::new();
        for (index, text) in words[2..].iter().enumerate() {
            let size: i64 = text.parse().unwrap();
            if size == 0 || size > capacity {
                return Err(format!("BAD ITEM {}", index + 1));
            }
            next.push(Item { number: index + 1, size });
        }
        self.capacity = capacity;
        self.items = Some(next);
        self.emit(format!(
            "ITEMS count={} capacity={} total={}",
            self.items().len(), capacity, self.total()
        ));
        Ok(())
    }

    fn cmd_random(&mut self, words: &[&str]) -> Result<(), String> {
        let count: usize = words[1].parse().unwrap();
        let capacity: i64 = words[2].parse().unwrap();
        let mut seed: i64 = words[3].parse().unwrap();
        if count == 0 || count > 40 {
            return Err("BAD COUNT".into());
        }
        if capacity == 0 {
            return Err("BAD CAPACITY".into());
        }
        if seed == 0 || seed >= 2_147_483_647 {
            return Err("BAD SEED".into());
        }
        let mut next = Vec::new();
        for number in 1..=count {
            seed = 48_271 * seed % 2_147_483_647;
            next.push(Item { number, size: seed % capacity + 1 });
        }
        let sizes = next.iter().map(|item| item.size.to_string())
            .collect::<Vec<_>>().join(" ");
        self.items = Some(next);
        self.capacity = capacity;
        self.emit(format!(
            "RANDOM count={} capacity={} total={}", count, capacity, self.total()
        ));
        self.emit(format!("SIZES {}", sizes));
        Ok(())
    }

    fn cmd_method(&mut self, method: &str, parameter: usize) {
        let result = pack(self.items(), self.capacity, method, parameter);
        self.emit(result.header(self.capacity, self.total()));
        self.bin_lines(&result.bins, method == "HARMONIC");
    }

    fn cmd_trace(&mut self, method: &str, parameter: usize) {
        let result = pack(self.items(), self.capacity, method, parameter);
        self.emit(format!("TRACE {}", result.header(self.capacity, self.total())));
        for (index, step) in result.steps.iter().enumerate() {
            let mut line = format!(
                "STEP {} item={} bin={} inspected={}", index + 1,
                step.item.text(), step.bin + 1, step.inspected
            );
            if step.opened {
                line.push_str(" new");
            }
            if let Some(closed) = step.closed {
                line.push_str(&format!(" closed={}", closed + 1));
            }
            if method == "HARMONIC" {
                line.push_str(&format!(" class={}", step.category));
            }
            self.emit(line);
        }
    }

    fn cmd_reduce(&mut self, method: &str, parameter: usize) {
        let result = pack(self.items(), self.capacity, method, parameter);
        let mut bins = result.bins;
        let before = bins.len();
        let mut events = Vec::new();
        loop {
            let mut sources: Vec<usize> = (0..bins.len()).collect();
            sources.sort_by_key(|&i| (bins[i].load, i));
            let mut eliminated = false;
            for source in sources {
                let mut loads = bins.iter().map(|bin| bin.load).collect::<Vec<_>>();
                let mut moves = Vec::<(Item, usize)>::new();
                let mut possible = true;
                for item in descending(&bins[source].items) {
                    let mut destination = None;
                    for i in 0..bins.len() {
                        if i == source || loads[i] + item.size > self.capacity {
                            continue;
                        }
                        if destination.map_or(true, |j| loads[i] > loads[j]) {
                            destination = Some(i);
                        }
                    }
                    if let Some(i) = destination {
                        loads[i] += item.size;
                        moves.push((item, i));
                    } else {
                        possible = false;
                        break;
                    }
                }
                if !possible {
                    continue;
                }
                let descriptions = moves.iter().map(|(item, i)| {
                    format!("{}->{}", item.text(), i + 1)
                }).collect::<Vec<_>>().join(" ");
                events.push(format!(
                    "ELIMINATE bin={} load={} moves={}",
                    source + 1, bins[source].load, descriptions
                ));
                for (item, destination) in moves {
                    bins[destination].put(item);
                }
                bins.remove(source);
                eliminated = true;
                break;
            }
            if !eliminated {
                break;
            }
        }
        self.emit(format!(
            "REDUCE {} before={} after={} eliminated={}",
            result.name(), before, bins.len(), before - bins.len()
        ));
        for event in events {
            self.emit(event);
        }
        self.bin_lines(&bins, method == "HARMONIC");
    }

    fn cmd_bounds(&mut self) {
        let result = lower_bounds(self.items(), self.capacity);
        self.emit(format!(
            "BOUNDS total={} L1={} L2={}", self.total(), result.l1, result.l2
        ));
        for row in result.rows {
            self.emit(format!(
                "ALPHA {} j1={} j2={} j3={} bound={}",
                row.alpha, row.j1, row.j2, row.j3, row.bound
            ));
        }
    }

    fn cmd_compare(&mut self, parameter: usize) -> Result<(), String> {
        if parameter == 0 {
            return Err("BAD PARAMETER".into());
        }
        let bounds = lower_bounds(self.items(), self.capacity);
        let mut results = METHODS.iter().map(|&method| {
            pack(self.items(), self.capacity, method, parameter)
        }).collect::<Vec<_>>();
        results.sort_by_key(|p| (p.bins.len(), p.method.clone()));
        self.emit(format!(
            "COMPARE k={} L1={} L2={}", parameter, bounds.l1, bounds.l2
        ));
        for p in results {
            let count = p.bins.len();
            self.emit(format!(
                "{} bins={} gap={} waste={} inspections={}",
                p.method, count, count as i64 - bounds.l2,
                count as i64 * self.capacity - self.total(), p.inspections
            ));
        }
        Ok(())
    }

    fn cmd_exact(&mut self, limit: usize) -> Result<(), String> {
        if limit == 0 {
            return Err("BAD PARAMETER".into());
        }
        if self.items().len() >= 21 {
            return Err("TOO MANY ITEMS".into());
        }
        let incumbent = pack(self.items(), self.capacity, "FFD", 0).bins;
        let lower = lower_bounds(self.items(), self.capacity).l2;
        self.emit(format!(
            "EXACT ffd={} L2={}", incumbent.len(), lower
        ));
        let mut search = ExactSearch::new(self.items(), self.capacity, limit, lower,
                                          &incumbent);
        if incumbent.len() as i64 == lower {
            search.status = Some("bound");
        } else {
            search.visit(0);
        }
        for event in search.events {
            self.emit(event);
        }
        self.emit(format!(
            "RESULT bins={} nodes={} status={}",
            search.best.len(), search.nodes, search.status.unwrap_or("complete")
        ));
        self.bin_lines(&search.best, false);
        Ok(())
    }

    fn cmd_check(&mut self, words: &[&str]) -> Result<(), String> {
        if words.len() - 1 != self.items().len() {
            return Err("BAD ASSIGNMENT".into());
        }
        let mut assigned = BTreeMap::<usize, Bin>::new();
        for (index, item) in self.items().iter().copied().enumerate() {
            let label: usize = words[index + 1].parse().unwrap();
            if label == 0 {
                return Err("BAD ASSIGNMENT".into());
            }
            assigned.entry(label).or_default().put(item);
        }
        let over = assigned.values().filter(|bin| bin.load > self.capacity).count();
        let lower = lower_bounds(self.items(), self.capacity).l2;
        self.emit(format!(
            "CHECK bins={} over={} L2={} status={}",
            assigned.len(), over, lower, if over == 0 { "valid" } else { "invalid" }
        ));
        for (label, bin) in assigned {
            self.bin_line(label, &bin, self.capacity, false, bin.load > self.capacity);
        }
        Ok(())
    }

    fn cover_lines(&mut self, name: &str, bins: &[Bin]) {
        let mut covered = Vec::new();
        let mut rest = None;
        for bin in bins {
            if bin.load >= self.capacity {
                covered.push(bin.clone());
            } else {
                rest = Some(bin);
            }
        }
        self.emit(format!(
            "{} covered={} rest={}",
            name, covered.len(), rest.map_or(0, |bin| bin.load)
        ));
        self.bin_lines(&covered, false);
        if let Some(bin) = rest {
            let contents = bin.items.iter().map(|item| item.text())
                .collect::<Vec<_>>().join(" ");
            self.emit(format!("REST items={}", contents));
        }
    }

    fn cmd_cover(&mut self) {
        self.emit(format!(
            "COVER total={} upper={}", self.total(), self.total() / self.capacity
        ));
        let mut sequential: Vec<Bin> = Vec::new();
        for &item in self.items() {
            if sequential.is_empty() || sequential.last().unwrap().load >= self.capacity {
                sequential.push(Bin::default());
            }
            sequential.last_mut().unwrap().put(item);
        }
        self.cover_lines("DNF", &sequential);

        let ordered = descending(self.items());
        let mut paired = Vec::new();
        let mut first = 0;
        let mut last = ordered.len();
        while first < last {
            let mut bin = Bin::default();
            bin.put(ordered[first]);
            first += 1;
            while bin.load < self.capacity && first < last {
                last -= 1;
                bin.put(ordered[last]);
            }
            paired.push(bin);
        }
        self.cover_lines("BIGSMALL", &paired);
    }

    fn machine_lines(&mut self, bins: &[Bin]) {
        for (index, bin) in bins.iter().enumerate() {
            let contents = if bin.items.is_empty() {
                "-".to_string()
            } else {
                bin.items.iter().map(|item| item.text())
                    .collect::<Vec<_>>().join(" ")
            };
            self.emit(format!(
                "MACHINE {} load={} items={}", index + 1, bin.load, contents
            ));
        }
    }

    fn cmd_multifit(&mut self, machines: usize) -> Result<(), String> {
        if machines == 0 {
            return Err("BAD PARAMETER".into());
        }
        let largest = self.items().iter().map(|item| item.size).max().unwrap();
        let mut low = ceiling(self.total(), machines as i64).max(largest);
        let mut high = ceiling(2 * self.total(), machines as i64).max(largest);
        self.emit(format!(
            "MULTIFIT m={} lower={} upper={}", machines, low, high
        ));
        while low < high {
            let middle = low + (high - low) / 2;
            let count = pack(self.items(), middle, "FFD", 0).bins.len();
            let ok = count <= machines;
            self.emit(format!(
                "TRY cap={} bins={} {}", middle, count, if ok { "ok" } else { "fail" }
            ));
            if ok { high = middle; } else { low = middle + 1; }
        }
        let mut result = pack(self.items(), high, "FFD", 0).bins;
        while result.len() < machines {
            result.push(Bin::default());
        }
        let makespan = result.iter().map(|bin| bin.load).max().unwrap();
        self.emit(format!("RESULT cap={} makespan={}", high, makespan));
        self.machine_lines(&result);

        let mut lpt = vec![Bin::default(); machines];
        for item in descending(self.items()) {
            let chosen = (0..machines).min_by_key(|&i| (lpt[i].load, i)).unwrap();
            lpt[chosen].put(item);
        }
        let makespan = lpt.iter().map(|bin| bin.load).max().unwrap();
        self.emit(format!("LPT makespan={}", makespan));
        self.machine_lines(&lpt);
        Ok(())
    }

    fn enumerate_patterns(index: usize, remaining: i64, pieces: &[Piece],
                          counts: &mut Vec<usize>, patterns: &mut Vec<Pattern>) {
        let maximum = (remaining / pieces[index].length) as usize;
        if index == pieces.len() - 1 {
            counts[index] = maximum;
            patterns.push(Pattern {
                counts: counts.clone(),
                trim: remaining - maximum as i64 * pieces[index].length,
            });
            return;
        }
        for count in (0..=maximum).rev() {
            counts[index] = count;
            Self::enumerate_patterns(
                index + 1, remaining - count as i64 * pieces[index].length,
                pieces, counts, patterns
            );
        }
    }

    fn cmd_cutstock(&mut self, words: &[&str]) -> Result<(), String> {
        let length: i64 = words[1].parse().unwrap();
        if length == 0 {
            return Err("BAD CAPACITY".into());
        }
        let mut pieces = Vec::new();
        let mut seen = BTreeSet::new();
        for (index, word) in words[2..].iter().enumerate() {
            let (size, demand) = word.split_once(':').unwrap();
            let size: i64 = size.parse().unwrap();
            let demand: usize = demand.parse().unwrap();
            if size == 0 || size > length || demand == 0 {
                return Err(format!("BAD PIECE {}", index + 1));
            }
            if !seen.insert(size) {
                return Err(format!("DUPLICATE PIECE {}", index + 1));
            }
            pieces.push(Piece { length: size, demand });
        }
        pieces.sort_by_key(|piece| -piece.length);
        let mut patterns = Vec::new();
        let mut counts = vec![0; pieces.len()];
        Self::enumerate_patterns(0, length, &pieces, &mut counts, &mut patterns);

        self.emit(format!(
            "CUTSTOCK L={} pieces={} patterns={}",
            length, pieces.len(), patterns.len()
        ));
        for (index, pattern) in patterns.iter().enumerate() {
            let breakdown = pattern.counts.iter().enumerate()
                .filter(|(_, count)| **count > 0)
                .map(|(i, count)| format!("{}x{}", count, pieces[i].length))
                .collect::<Vec<_>>().join("+");
            self.emit(format!(
                "PATTERN {} {} rest={}", index + 1, breakdown, pattern.trim
            ));
        }
        let mut remaining = pieces.iter().map(|piece| piece.demand)
            .collect::<Vec<_>>();
        let mut cut = vec![0; pieces.len()];
        let mut used = vec![0; patterns.len()];
        while remaining.iter().any(|&count| count > 0) {
            let mut chosen = 0;
            let mut highest = 0;
            for (index, pattern) in patterns.iter().enumerate() {
                let useful: usize = pattern.counts.iter().zip(&remaining)
                    .map(|(&count, &need)| count.min(need)).sum();
                if index == 0 || useful > highest {
                    chosen = index;
                    highest = useful;
                }
            }
            used[chosen] += 1;
            for i in 0..pieces.len() {
                cut[i] += patterns[chosen].counts[i];
                remaining[i] = remaining[i].saturating_sub(patterns[chosen].counts[i]);
            }
        }
        let mut bars = 0;
        let mut trim = 0;
        for (i, &times) in used.iter().enumerate() {
            if times > 0 {
                self.emit(format!("USE {} bars={}", i + 1, times));
                bars += times;
                trim += times as i64 * patterns[i].trim;
            }
        }
        let quantity: i64 = pieces.iter()
            .map(|piece| piece.length * piece.demand as i64).sum();
        let mut stock = Vec::new();
        for (index, piece) in pieces.iter().enumerate() {
            self.emit(format!(
                "PIECE {} demand={} cut={}",
                piece.length, piece.demand, cut[index]
            ));
            for _ in 0..piece.demand {
                stock.push(Item { number: stock.len() + 1, size: piece.length });
            }
        }
        let demand_total: usize = pieces.iter().map(|piece| piece.demand).sum();
        let cut_total: usize = cut.iter().sum();
        self.emit(format!(
            "TOTAL bars={} trim={} surplus={} waste={}",
            bars, trim, cut_total - demand_total, bars as i64 * length - quantity
        ));
        let ffd = pack(&stock, length, "FIRSTFIT", 0).bins.len();
        self.emit(format!(
            "FFD bars={} waste={}", ffd, ffd as i64 * length - quantity
        ));
        self.emit(format!("LOWER bars={}", ceiling(quantity, length)));
        Ok(())
    }

    fn rectangles(words: &[&str], start: usize, width: usize, height: usize,
                  rotate: bool) -> Result<Vec<Rect>, String> {
        let mut result = Vec::new();
        for (index, word) in words[start..].iter().enumerate() {
            let (w, h) = word.split_once('x').unwrap();
            let w: usize = w.parse().unwrap();
            let h: usize = h.parse().unwrap();
            let fits = if height == 0 {
                w <= width
            } else {
                (w <= width && h <= height) || (rotate && h <= width && w <= height)
            };
            if w == 0 || h == 0 || !fits {
                return Err(format!("BAD RECT {}", index + 1));
            }
            result.push(Rect { number: index + 1, width: w, height: h });
        }
        Ok(result)
    }

    fn draw(&mut self, width: usize, height: usize, placements: &[Placement]) {
        let mut grid = vec![vec![b'.'; width]; height];
        for p in placements {
            for y in p.y..p.y + p.height {
                for x in p.x..p.x + p.width {
                    grid[y][x] = p.rect.letter() as u8;
                }
            }
        }
        for row in grid.iter().rev() {
            self.emit(String::from_utf8(row.clone()).unwrap());
        }
    }

    fn cmd_shelf(&mut self, words: &[&str]) -> Result<(), String> {
        let width: usize = words[1].parse().unwrap();
        if width == 0 {
            return Err("BAD CAPACITY".into());
        }
        let mut rects = Self::rectangles(words, 2, width, 0, false)?;
        let area: usize = rects.iter().map(|rect| rect.area()).sum();
        self.emit(format!(
            "SHELF W={} rects={} area={}", width, rects.len(), area
        ));
        rects.sort_by_key(|rect| (
            -(rect.height as i64), -(rect.width as i64), rect.number
        ));
        for method in ["NFDH", "FFDH", "BFDH"] {
            let mut shelves: Vec<Shelf> = Vec::new();
            let mut placements = Vec::new();
            for &rect in &rects {
                let mut chosen = None;
                if method == "NFDH" {
                    if let Some(last) = shelves.last() {
                        if last.used + rect.width <= width {
                            chosen = Some(shelves.len() - 1);
                        }
                    }
                } else {
                    for (index, shelf) in shelves.iter().enumerate() {
                        if shelf.used + rect.width > width {
                            continue;
                        }
                        if chosen.map_or(true, |i| {
                            method == "BFDH" && shelf.used > shelves[i].used
                        }) {
                            chosen = Some(index);
                        }
                        if method == "FFDH" {
                            break;
                        }
                    }
                }
                let index = if let Some(index) = chosen {
                    index
                } else {
                    let bottom = shelves.last().map_or(0, |last| last.bottom + last.height);
                    shelves.push(Shelf {
                        bottom,
                        height: rect.height,
                        used: 0,
                        placements: Vec::new(),
                    });
                    shelves.len() - 1
                };
                let shelf = &mut shelves[index];
                let p = Placement {
                    rect,
                    x: shelf.used,
                    y: shelf.bottom,
                    width: rect.width,
                    height: rect.height,
                    rotated: false,
                };
                shelf.placements.push(p.clone());
                placements.push(p);
                shelf.used += rect.width;
            }
            let last = shelves.last().unwrap();
            let height = last.bottom + last.height;
            self.emit(format!(
                "{} height={} shelves={} util={}",
                method, height, shelves.len(), area * 100 / (width * height)
            ));
            for (index, shelf) in shelves.iter().enumerate() {
                let content = shelf.placements.iter()
                    .map(|p| format!("{}@{}", p.rect.letter(), p.x))
                    .collect::<Vec<_>>().join(" ");
                self.emit(format!(
                    "LEVEL {} y={} h={} used={} items={}",
                    index + 1, shelf.bottom, shelf.height, shelf.used, content
                ));
            }
            self.draw(width, height, &placements);
        }

        let mut columns = vec![0; width];
        let mut skyline = Vec::new();
        for &rect in &rects {
            let mut best = (usize::MAX, 0);
            for x in 0..=width - rect.width {
                let y = *columns[x..x + rect.width].iter().max().unwrap();
                if y < best.0 {
                    best = (y, x);
                }
            }
            let (y, x) = best;
            skyline.push(Placement {
                rect,
                x,
                y,
                width: rect.width,
                height: rect.height,
                rotated: false,
            });
            for column in &mut columns[x..x + rect.width] {
                *column = y + rect.height;
            }
        }
        let height = *columns.iter().max().unwrap();
        self.emit(format!(
            "SKYLINE height={} util={}", height, area * 100 / (width * height)
        ));
        for p in &skyline {
            self.emit(format!(
                "PLACE {} x={} y={} w={} h={}",
                p.rect.letter(), p.x, p.y, p.width, p.height
            ));
        }
        self.draw(width, height, &skyline);
        Ok(())
    }

    fn fits(rect: Rect, free: &FreeRect, rotate: bool) -> bool {
        (rect.width <= free.width && rect.height <= free.height) ||
        (rotate && rect.height <= free.width && rect.width <= free.height)
    }

    fn cmd_guillotine(&mut self, words: &[&str]) -> Result<(), String> {
        let width: usize = words[1].parse().unwrap();
        let height: usize = words[2].parse().unwrap();
        if width == 0 || height == 0 {
            return Err("BAD CAPACITY".into());
        }
        let rotate = words[3] == "ROTATE";
        let best = words[4] == "BEST";
        let mut rects = Self::rectangles(words, 5, width, height, rotate)?;
        rects.sort_by_key(|rect| (-(rect.area() as i64), rect.number));
        let area: usize = rects.iter().map(|rect| rect.area()).sum();
        let mut sheets: Vec<Sheet> = Vec::new();
        let mut rotated = 0;

        for rect in &rects {
            let mut selected = None;
            let mut free_index = 0;
            let mut selected_area = usize::MAX;
            for (s, sheet) in sheets.iter().enumerate() {
                for (i, free) in sheet.free.iter().enumerate() {
                    if !Self::fits(*rect, free, rotate) {
                        continue;
                    }
                    if selected.is_none() || (best && free.area() < selected_area) {
                        selected = Some(s);
                        free_index = i;
                        selected_area = free.area();
                    }
                    if !best {
                        break;
                    }
                }
                if selected.is_some() && !best {
                    break;
                }
            }
            let sheet_index = if let Some(index) = selected {
                index
            } else {
                sheets.push(Sheet::new(width, height));
                free_index = 0;
                sheets.len() - 1
            };
            let sheet = &mut sheets[sheet_index];
            let free = sheet.free.remove(free_index);
            let turned = rect.width > free.width || rect.height > free.height;
            let (w, h) = if turned {
                (rect.height, rect.width)
            } else {
                (rect.width, rect.height)
            };
            if turned {
                rotated += 1;
            }
            sheet.placements.push(Placement {
                rect: *rect,
                x: free.x,
                y: free.y,
                width: w,
                height: h,
                rotated: turned,
            });
            sheet.area += rect.area();
            let rw = free.width - w;
            let rh = free.height - h;
            let (top, right) = if rw <= rh {
                (
                    FreeRect { x: free.x, y: free.y + h, width: free.width, height: rh },
                    FreeRect { x: free.x + w, y: free.y, width: rw, height: h },
                )
            } else {
                (
                    FreeRect { x: free.x, y: free.y + h, width: w, height: rh },
                    FreeRect { x: free.x + w, y: free.y, width: rw, height: free.height },
                )
            };
            if top.width > 0 && top.height > 0 {
                sheet.free.push(top);
            }
            if right.width > 0 && right.height > 0 {
                sheet.free.push(right);
            }
        }
        self.emit(format!(
            "GUILLOTINE W={} H={} mode={} rule={} rects={} sheets={} rotated={} util={}",
            width, height, words[3], words[4], rects.len(), sheets.len(), rotated,
            area * 100 / (sheets.len() * width * height)
        ));
        for (index, sheet) in sheets.iter().enumerate() {
            self.emit(format!(
                "SHEET {} placed={} area={}",
                index + 1, sheet.placements.len(), sheet.area
            ));
            for p in &sheet.placements {
                self.emit(format!(
                    "PLACE {} x={} y={} w={} h={}{}",
                    p.rect.letter(), p.x, p.y, p.width, p.height,
                    if p.rotated { " rotated" } else { "" }
                ));
            }
            let free = if sheet.free.is_empty() {
                "FREE none".to_string()
            } else {
                format!("FREE {}", sheet.free.iter().map(|f| f.text())
                    .collect::<Vec<_>>().join(" "))
            };
            self.emit(free);
            self.draw(width, height, &sheet.placements);
        }
        Ok(())
    }

    fn process(&mut self, words: &[&str]) -> Result<(), String> {
        let method = words[0];
        match method {
            "ITEMS" => self.cmd_items(words),
            "RANDOM" => self.cmd_random(words),
            "CUTSTOCK" => self.cmd_cutstock(words),
            "SHELF" => self.cmd_shelf(words),
            "GUILLOTINE" => self.cmd_guillotine(words),
            _ => {
                if self.items.is_none() {
                    return Err("NO ITEMS".into());
                }
                match method {
                    "NEXTFIT" | "FIRSTFIT" | "BESTFIT" | "WORSTFIT" |
                    "ALMOSTWORST" | "HARMONIC" | "KBOUNDED" | "FFD" | "BFD" | "WFD" => {
                        let k = Self::parameter(method, words, 1)?;
                        self.cmd_method(method, k);
                    }
                    "TRACE" | "REDUCE" => {
                        let name = words[1];
                        let k = Self::parameter(name, words, 2)?;
                        if method == "TRACE" {
                            self.cmd_trace(name, k);
                        } else {
                            self.cmd_reduce(name, k);
                        }
                    }
                    "BOUNDS" => self.cmd_bounds(),
                    "COMPARE" => self.cmd_compare(words[1].parse().unwrap())?,
                    "EXACT" => self.cmd_exact(words[1].parse().unwrap())?,
                    "CHECK" => self.cmd_check(words)?,
                    "COVER" => self.cmd_cover(),
                    "MULTIFIT" => self.cmd_multifit(words[1].parse().unwrap())?,
                    _ => unreachable!(),
                }
                Ok(())
            }
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let n = lines.next().unwrap().parse::<usize>().unwrap();
    let mut lab = Lab::new();
    for line in lines.take(n) {
        let words = line.split(' ').collect::<Vec<_>>();
        if let Err(error) = lab.process(&words) {
            lab.emit(format!("ERROR {}", error));
        }
    }
    if !lab.output.is_empty() {
        println!("{}", lab.output.join("\n"));
    }
}
