mod heap;
mod mutator;
mod mark_sweep;
mod copying;
mod generational;
use std::{
    collections::BTreeSet, fs, io
};
use heap::{
    HeapObject, Pair, Record, Memory, free_amount, first_fit, class_table, dec2, pct, heap_map
};
use mutator::{
    Command, Kind, Collector, Config, NAMES, read_config, read_script
};
fn reach(objects: &[HeapObject], roots: &[Option<usize>]) -> BTreeSet<usize> {
    let mut reached = BTreeSet::new();
    let mut stack = roots.iter().flatten().copied().collect::<Vec<_>>();
    while let Some(id) = stack.pop() {
        if reached.insert(id) {
            stack.extend(objects[id].fields.iter().flatten().copied());
        }
    }
    reached
}
fn pair(objects: &[HeapObject], ids: impl IntoIterator<Item = usize>) -> Pair {
    let mut p = Pair::default();
    for id in ids {
        p.add(&objects[id])
    }
    p
}
fn value(roots: &[Option<usize>], r: Option<usize>) -> Option<usize> {
    r.and_then(|r|roots[r])
}
struct Checkpoint {
    label: String,
    line: usize,
    depth: usize,
    live: Pair,
    allocated: Pair,
    phase: Pair,
    survivors: Pair,
    reached: BTreeSet<usize>
}
struct Script {
    commands: Vec<Command>,
    errors: Vec<(usize, String)>,
    objects: Vec<HeapObject>,
    roots: Vec<Option<usize>>,
    deaths: Vec<usize>,
    lifetimes: Vec<Option<usize>>,
    checkpoints: Vec<Checkpoint>,
    counts: [usize; 7],
    peak: Pair,
    peak_line: usize,
    line_count: usize
}
impl Script {
    fn analyze(parsed: Vec<Result<Command, String>>) -> Self {
        let mut s = Self {
            commands: vec![],
            errors: vec![],
            objects: vec![],
            roots: vec![],
            deaths: vec![],
            lifetimes: vec![],
            checkpoints: vec![],
            counts: [0; 7],
            peak: Pair::default(),
            peak_line: 0,
            line_count: parsed.len()
        };
        let(mut clock, mut phase_start) = (0, 0);
        let mut births = vec![];
        let mut alive = BTreeSet::new();
        let mut labels = BTreeSet::new();
        for(i, result)in parsed.into_iter().enumerate() {
            let c = match result {
                Ok(c) => c, Err(r) => {
                    s.errors.push((i+1, r));
                    continue
                }
            };
            let depth = s.roots.len();
            let mut reason = None;
            let index = match c.kind {
                Kind::Load(i, _)|Kind::Set(i, ..)|Kind::Overwrite(i, _) => Some(i), _ => None
            };
            let source = match c.kind {
                Kind::Push(r)|Kind::Set(_, _, r)|Kind::Overwrite(_, r) => r, _ => None
            };
            if matches!(c.kind, Kind::Alloc(..)|Kind::Push(..)|Kind::Load(..)) && depth == 64 || index.is_some_and(|i|i >= depth) || source.is_some_and(|i|i >= depth) || matches!(c.kind, Kind::Pop(n)if n>depth) {
                reason = Some("stack");
            }else {
                match &c.kind {
                    Kind::Load(i, f)|Kind::Set(i, f, _) => {
                        if let Some(id) = s.roots[*i] {
                            if *f >= s.objects[id].fields.len() {
                                reason = Some("field")
                            }
                        }else {
                            reason = Some("null")
                        }
                    }, Kind::Checkpoint(label)if labels.contains(label) => reason = Some("duplicate"), _ => {
                    }
                }
            }
            if let Some(r) = reason {
                s.errors.push((c.line, r.into()));
                continue
            }
            s.counts[c.name()] += 1;
            match &c.kind {
                Kind::Alloc(p, d) => {
                    let id = s.objects.len();
                    let o = HeapObject::new(*p, *d);
                    births.push(clock);
                    clock += o.size;
                    s.objects.push(o);
                    s.deaths.push(0);
                    s.lifetimes.push(None);
                    s.roots.push(Some(id));
                }, Kind::Push(r) => s.roots.push(value(&s.roots, *r)), Kind::Load(i, f) => s.roots.push(s.objects[s.roots[*i].unwrap()].fields[*f]), Kind::Pop(n) => s.roots.truncate(depth-n), Kind::Set(i, f, r) => {
                    let new = value(&s.roots, *r);
                    s.objects[s.roots[*i].unwrap()].fields[*f] = new;
                }, Kind::Overwrite(i, r) => {
                    let new = value(&s.roots, *r);
                    s.roots[*i] = new
                }, Kind::Checkpoint(_) => {
                }
            }
            let reached = reach(&s.objects, &s.roots);
            for &id in alive.difference(&reached) {
                s.deaths[id] = c.line;
                s.lifetimes[id] = Some(clock-births[id]-s.objects[id].size);
            }
            alive = reached.clone();
            let live = pair(&s.objects, reached.iter().copied());
            if s.peak_line == 0 || live.words>s.peak.words {
                s.peak = live;
                s.peak_line = c.line
            }
            if let Kind::Checkpoint(label) = &c.kind {
                labels.insert(label.clone());
                let allocated = pair(&s.objects, 0..s.objects.len());
                let phase = pair(&s.objects, phase_start..s.objects.len());
                let survivors = pair(&s.objects, (phase_start..s.objects.len()).filter(|id|reached.contains(id)));
                phase_start = s.objects.len();
                s.checkpoints.push(Checkpoint {
                    label: label.clone(),
                    line: c.line,
                    depth: s.roots.len(),
                    live,
                    allocated,
                    phase,
                    survivors,
                    reached
                });
            }
            s.commands.push(c);
        }
        s
    }
    fn report(&self) -> Vec<String> {
        let mut lines = vec![format!("script lines {} valid {} errors {}", self.line_count, self.commands.len(), self.errors.len())];
        lines.extend(self.errors.iter().map(|(line, r)|format!("error line {line} {r}")));
        lines.push(format!("commands {}", NAMES.iter().zip(self.counts).map(|(n, c)|format!("{n} {c}")).collect::<Vec<_>>().join(" ")));
        lines.push(format!("allocated objects {} words {} sizes {}", self.objects.len(), self.objects.iter().map(|o|o.size).sum::<usize>(), class_table(self.objects.iter().map(|o|o.size))));
        lines.push(format!("peak_live objects {} words {} line {}", self.peak.count, self.peak.words, self.peak_line));
        let live = pair(&self.objects, reach(&self.objects, &self.roots));
        lines.push(format!("end_live objects {} words {} stack {}", live.count, live.words, self.roots.len()));
        let mut counts = [0; 6];
        for lifetime in &self.lifetimes {
            let k = lifetime.map_or(5, |v|[63, 255, 1023, 4095].iter().position(|&limit|v <= limit).unwrap_or(4));
            counts[k] += 1;
        }
        lines.push(format!("lifetimes 0-63 {} 64-255 {} 256-1023 {} 1024-4095 {} 4096+ {} live {}", counts[0], counts[1], counts[2], counts[3], counts[4], counts[5]));
        for c in &self.checkpoints {
            lines.push(format!("checkpoint {} line {} stack {} live {} allocated {} phase {} survivors {} survival {}", c.label, c.line, c.depth, c.live.text(), c.allocated.text(), c.phase.text(), c.survivors.text(), pct(c.survivors.words, c.phase.words)));
        }
        lines
    }
}
fn leak_report(title: &str, m: &Memory, garbage: Vec<usize>, deaths: &[usize]) -> Vec<String> {
    let members = garbage.iter().copied().collect::<BTreeSet<_>>();
    let mut neighbors = vec![vec![]; m.objects.len()];
    for &id in &garbage {
        for child in m.objects[id].fields.iter().flatten() {
            if members.contains(child) {
                neighbors[id].push(*child);
                neighbors[*child].push(id);
            }
        }
    }
    let mut grouped = BTreeSet::new();
    let mut groups = vec![];
    for &id in &garbage {
        if !grouped.insert(id) {
            continue
        }
        let mut stack = vec![id];
        let mut group = vec![];
        while let Some(i) = stack.pop() {
            group.push(i);
            for &j in &neighbors[i] {
                if grouped.insert(j) {
                    stack.push(j);
                }
            }
        }
        group.sort();
        groups.push(group);
    }
    let mut lines = vec![format!("{title} groups {} objects {} words {}", groups.len(), garbage.len(), pair(&m.objects, garbage).words)];
    for(k, g)in groups.iter().enumerate() {
        let mut cycles = 0;
        let mut ids = vec![];
        for &id in g {
            let mut visited = BTreeSet::new();
            let mut stack = m.objects[id].fields.iter().flatten().filter(|j|members.contains(j)).copied().collect::<Vec<_>>();
            let mut cycle = false;
            while let Some(j) = stack.pop() {
                if j == id {
                    cycle = true;
                    break
                }
                if visited.insert(j) {
                    stack.extend(m.objects[j].fields.iter().flatten().filter(|j|members.contains(j)).copied())
                }
            }
            if cycle {
                cycles += 1
            }
            ids.push(format!("{}{}", id+1, if cycle {
                "*"
            }else {
                ""
            }));
        }
        lines.push(format!("group {} objects {} words {} cycle {cycles} died {} ids {}", k+1, g.len(), pair(&m.objects, g.iter().copied()).words, g.iter().map(|&i|deaths[i]).max().unwrap(), ids.join(" ")));
    }
    lines
}
#[derive(Clone)]
struct Pause {
    line: usize,
    work: usize,
    freed: Pair,
    collection: bool
}
struct Stats {
    count: usize,
    collections: usize,
    work: usize,
    freed: usize,
    max: usize,
    p50: String,
    p90: String
}
fn stats(pauses: &[Pause]) -> Stats {
    let mut work = pauses.iter().map(|p|p.work).collect::<Vec<_>>();
    work.sort();
    let percentile = |rank|if work.is_empty() {
        "-".into()
    }else {
        work[(rank*work.len()+99)/100-1].to_string()
    };
    Stats {
        count: pauses.len(),
        collections: pauses.iter().filter(|p|p.collection).count(),
        work: work.iter().sum(),
        freed: pauses.iter().map(|p|p.freed.words).sum(),
        max: work.last().copied().unwrap_or(0),
        p50: percentile(50),
        p90: percentile(90)
    }
}
struct Segment {
    start: usize,
    len: usize,
    mutator: bool,
    before: usize
}
#[derive(Default)]
struct Timeline {
    segments: Vec<Segment>,
    length: usize,
    mutator: usize
}
impl Timeline {
    fn add(&mut self, mutator: bool, len: usize) {
        if len == 0 {
            return
        }
        if self.segments.last().is_some_and(|s|s.mutator == mutator) {
            self.segments.last_mut().unwrap().len += len;
        }else {
            self.segments.push(Segment {
                start: self.length,
                len,
                mutator,
                before: self.mutator
            });
        }
        self.length += len;
        if mutator {
            self.mutator += len
        }
    }
    fn prefix(&self, p: usize) -> usize {
        let k = self.segments.partition_point(|s|s.start <= p)-1;
        let s = &self.segments[k];
        s.before+if s.mutator {
            p-s.start
        }else {
            0
        }
    }
    fn mmu(&self, w: usize) -> String {
        if w>self.length {
            return "-".into()
        }
        let mut lowest = w;
        for s in &self.segments {
            let mut candidates = vec![s.start];
            if s.start+s.len >= w {
                candidates.push(s.start+s.len-w)
            }
            for b in candidates {
                if b <= self.length-w {
                    lowest = lowest.min(self.prefix(b+w)-self.prefix(b));
                }
            }
        }
        pct(lowest, w)
    }
}
struct Run {
    entry: Collector,
    m: Memory,
    roots: Vec<Option<usize>>,
    observations: Vec<Vec<String>>,
    cascades: Vec<Pause>,
    timeline: Timeline,
    failed: Option<(usize, usize)>,
    peak_used: usize,
    increments: usize,
    decrements: usize,
    released: Pair,
    released_work: usize,
    reports: Vec<Vec<String>>
}
impl Run {
    fn new(entry: Collector, size: usize) -> Self {
        let m = Memory {
            algorithm: entry.algorithm.clone(),
            size,
            objects: vec![],
            base: 0,
            top: 0,
            young: entry.young,
            promotion_age: entry.age,
            remembered: BTreeSet::new(),
            barriers: 0,
            remembers: 0,
            records: vec![]
        };
        Self {
            entry,
            m,
            roots: vec![],
            observations: vec![],
            cascades: vec![],
            timeline: Timeline::default(),
            failed: None,
            peak_used: 0,
            increments: 0,
            decrements: 0,
            released: Pair::default(),
            released_work: 0,
            reports: vec![]
        }
    }
    fn rc(&self) -> bool {
        self.entry.algorithm == "REFCOUNT"
    }
    fn retain(&mut self, id: Option<usize>) {
        if self.rc() {
            if let Some(id) = id {
                self.m.objects[id].count += 1;
                self.increments += 1
            }
        }
    }
    fn release(&mut self, id: Option<usize>) {
        if !self.rc() {
            return
        }
        let Some(id) = id else {
            return
        };
        let mut pending = vec![id];
        while let Some(id) = pending.pop() {
            self.decrements += 1;
            self.m.objects[id].count -= 1;
            if self.m.objects[id].count != 0 {
                continue
            }
            self.released.add(&self.m.objects[id]);
            self.released_work += 1+self.m.objects[id].fields.len();
            self.m.objects[id].present = false;
            for child in self.m.objects[id].fields.iter().rev().flatten() {
                pending.push(*child);
            }
        }
    }
    fn push(&mut self, id: Option<usize>) {
        self.retain(id);
        self.roots.push(id)
    }
    fn backup(&mut self, line: usize, request: usize, deaths: &[usize]) {
        let mut r = Record::new(line, request, "backup", &self.m.free_list());
        mark_sweep::mark(&mut self.m, &self.roots, &mut r);
        let garbage = self.m.ids().into_iter().filter(|&i|!self.m.objects[i].marked).collect::<Vec<_>>();
        self.reports.push(leak_report(&format!("backup {} line {line}", self.m.records.len()+1), &self.m, garbage.clone(), deaths));
        mark_sweep::sweep(&mut self.m, &mut r);
        for id in garbage {
            for child in self.m.objects[id].fields.clone().into_iter().flatten() {
                if self.m.objects[child].marked {
                    self.m.objects[child].count -= 1;
                    self.decrements += 1
                }
            }
        }
        r.after = free_amount(&self.m.free_list());
        self.m.records.push(r);
    }
    fn allocate(&mut self, o: HeapObject, line: usize, deaths: &[usize]) -> bool {
        let size = o.size;
        let address = match self.entry.algorithm.as_str() {
            "MARK_SWEEP"|"REFCOUNT" => {
                let mut a = first_fit(&self.m.free_list(), size);
                if a.is_none() {
                    if self.rc() {
                        self.backup(line, size, deaths)
                    }else {
                        mark_sweep::collect(&mut self.m, &self.roots, line, size, false)
                    }
                    a = first_fit(&self.m.free_list(), size)
                }
                a
            }, "MARK_COMPACT" => {
                if self.m.top+size>self.m.size {
                    mark_sweep::collect(&mut self.m, &self.roots, line, size, true)
                }
                if self.m.top+size <= self.m.size {
                    Some(self.m.top)
                }else {
                    None
                }
            }, "COPYING" => {
                if self.m.top+size>self.m.base+self.m.size/2 {
                    copying::collect(&mut self.m, &self.roots, line, size)
                }
                if self.m.top+size <= self.m.base+self.m.size/2 {
                    Some(self.m.top)
                }else {
                    None
                }
            }, _ => {
                let half = self.m.young/2;
                let mut aborted = false;
                for step in 0..2 {
                    if self.m.top+size <= self.m.base+half {
                        break
                    }
                    let tight = free_amount(&self.m.old_blocks()).1<self.m.top-self.m.base;
                    let kind = match(step, tight) {
                        (0, true) => "major", (0, false) => "minor", (_, true) => "full", _ => "tenure"
                    };
                    if !generational::collect(&mut self.m, &self.roots, line, size, kind) {
                        aborted = true;
                        break
                    }
                }
                if !aborted && self.m.top+size <= self.m.base+half {
                    Some(self.m.top)
                }else {
                    None
                }
            }
        };
        let Some(a) = address else {
            return false
        };
        let mut o = o;
        o.address = a;
        if !["MARK_SWEEP", "REFCOUNT"].contains(&self.entry.algorithm.as_str()) {
            self.m.top += size
        }
        let id = self.m.objects.len();
        self.m.objects.push(o);
        self.push(Some(id));
        self.peak_used = self.peak_used.max(self.m.pair(self.m.ids()).words);
        true
    }
    fn simulate(&mut self, config: &Config, script: &Script) {
        for c in &script.commands {
            let before = self.m.records.len();
            let mut placed = true;
            let units = match &c.kind {
                Kind::Alloc(p, d) => {
                    let o = HeapObject::new(*p, *d);
                    let n = o.size;
                    placed = self.allocate(o, c.line, &script.deaths);
                    n
                }, Kind::Push(r) => {
                    self.push(value(&self.roots, *r));
                    1
                }, Kind::Load(i, f) => {
                    self.push(self.m.objects[self.roots[*i].unwrap()].fields[*f]);
                    1
                }, Kind::Pop(n) => {
                    for _ in 0..*n {
                        let id = self.roots.pop().unwrap();
                        self.release(id)
                    }
                    1
                }, Kind::Set(i, f, r) => {
                    let id = self.roots[*i].unwrap();
                    let new = value(&self.roots, *r);
                    if self.entry.algorithm == "GENERATIONAL" {
                        generational::write_barrier(&mut self.m, id, new)
                    }
                    self.retain(new);
                    let previous = self.m.objects[id].fields[*f];
                    self.m.objects[id].fields[*f] = new;
                    self.release(previous);
                    1
                }, Kind::Overwrite(i, r) => {
                    let new = value(&self.roots, *r);
                    self.retain(new);
                    let previous = self.roots[*i];
                    self.roots[*i] = new;
                    self.release(previous);
                    1
                }, Kind::Checkpoint(_) => {
                    let cp = &script.checkpoints[self.observations.len()];
                    self.observations.push(self.observe(config, cp));
                    1
                }
            };
            for r in &self.m.records[before..] {
                self.timeline.add(false, r.work)
            }
            if !placed {
                self.failed = Some((c.line, units));
                return
            }
            self.timeline.add(true, units);
            if self.released.count>0 {
                self.cascades.push(Pause {
                    line: c.line,
                    work: self.released_work,
                    freed: self.released,
                    collection: false
                });
                self.timeline.add(false, self.released_work);
                self.released = Pair::default();
                self.released_work = 0;
            }
        }
        if self.rc() {
            let reached = reach(&self.m.objects, &self.roots);
            let garbage = self.m.ids().into_iter().filter(|i|!reached.contains(i)).collect();
            self.reports.push(leak_report("end", &self.m, garbage, &script.deaths));
        }
    }
    fn observe(&self, config: &Config, cp: &Checkpoint) -> Vec<String> {
        let ids = self.m.ids();
        let all = self.m.pair(ids.iter().copied());
        let live = self.m.pair(ids.iter().copied().filter(|i|cp.reached.contains(i)));
        let garbage = Pair {
            count: all.count-live.count,
            words: all.words-live.words
        };
        let blocks = self.m.free_list();
        let(total, largest) = free_amount(&blocks);
        let(mut pointers, mut forward, mut backward, mut distance) = (0, 0, 0, 0);
        for &id in &ids {
            if !cp.reached.contains(&id) {
                continue
            }
            for child in self.m.objects[id].fields.iter().flatten() {
                let a = self.m.objects[id].address;
                let b = self.m.objects[*child].address;
                pointers += 1;
                forward += usize::from(b>a);
                backward += usize::from(b<a);
                distance += a.abs_diff(b);
            }
        }
        let mut lines = vec![format!("heap objects {} reachable {} garbage {}", all.text(), live.text(), garbage.text()), format!("free total {total} largest {largest} blocks {} sizes {} fragmentation {}", blocks.len(), class_table(blocks.iter().map(|b|b.1)), pct(total-largest, total)), format!("locality pointers {pointers} forward {forward} backward {backward} mean_distance {}", if pointers == 0 {
            "-".into()
        }else {
            dec2(distance, pointers)
        })];
        if self.entry.algorithm == "GENERATIONAL" {
            let young = self.m.pair(ids.iter().copied().filter(|&i|self.m.objects[i].address<self.m.young));
            let old = Pair {
                count: all.count-young.count,
                words: all.words-young.words
            };
            let mut ages = [0; 4];
            for &i in &ids {
                if self.m.objects[i].address<self.m.young {
                    ages[self.m.objects[i].age.min(3)] += 1
                }
            }
            lines.push(format!("generations young {} old {} remembered {} ages 0:{} 1:{} 2:{} 3+:{}", young.text(), old.text(), self.m.remembered.len(), ages[0], ages[1], ages[2], ages[3]));
        }
        if config.maps.contains(&cp.label) {
            let map = heap_map(&self.m, &cp.reached);
            for a in (0..config.size).step_by(config.width) {
                lines.push(format!("{a:04} {}", &map[a..a+config.width]));
            }
        }
        lines
    }
    fn pauses(&self) -> Vec<Pause> {
        let mut p = self.m.records.iter().map(|r|Pause {
            line: r.line,
            work: r.work,
            freed: r.freed,
            collection: true
        }).collect::<Vec<_>>();
        p.extend(self.cascades.clone());
        p
    }
    fn failed_before(&self, line: usize) -> bool {
        self.failed.is_some_and(|(at, _)|at<line)
    }
    fn collection_lines(&self, config: &Config, script: &Script) -> Vec<String> {
        let mut lines = vec![format!("collector {} {}", self.entry.name, self.entry.algorithm)];
        for(i, r)in self.m.records.iter().enumerate() {
            lines.push(format!("{} line {} size {} kind {} live {} freed {} moved {} promoted {} stack {} work {} before {} {} after {} {}", i+1, r.line, r.request, r.kind, r.live.text(), r.freed.text(), r.moved.text(), r.promoted.text(), r.stack, r.work, r.before.0, r.before.1, r.after.0, r.after.1));
        }
        let pauses = self.pauses();
        let s = stats(&pauses);
        lines.push(format!("totals collections {} pauses {} work {} freed {} pause p50 {} p90 {} max {}", s.collections, s.count, s.work, s.freed, s.p50, s.p90, s.max));
        lines.push(format!("utilization {} mmu {}", pct(self.timeline.mutator, self.timeline.length), config.windows.iter().map(|&w|format!("{w}:{}", self.timeline.mmu(w))).collect::<Vec<_>>().join(" ")));
        if self.entry.algorithm == "GENERATIONAL" {
            let mut promoted = Pair::default();
            for r in &self.m.records {
                promoted.merge(r.promoted)
            }
            let kinds = ["minor", "major", "tenure", "full"].iter().map(|kind| {
                let records = self.m.records.iter().filter(|r|r.kind == *kind).collect::<Vec<_>>(); format!("{kind} {} {}", records.len(), records.iter().map(|r|r.work).sum::<usize>())
            }).collect::<Vec<_>>().join(" ");
            lines.push(format!("generational {kinds} promoted {} barrier {} remembered {}", promoted.text(), self.m.barriers, self.m.remembers));
        }
        if self.rc() {
            let mut freed = Pair::default();
            let mut maximum = None;
            for c in &self.cascades {
                freed.merge(c.freed);
                if maximum.is_none_or(|p: &Pause|c.work>p.work) {
                    maximum = Some(c)
                }
            }
            let max = maximum.map_or("max_cascade 0 0 line -".into(), |p|format!("max_cascade {} {} line {}", p.freed.count, p.work, p.line));
            lines.push(format!("refcount increments {} decrements {} cascades {} freed {} {max}", self.increments, self.decrements, self.cascades.len(), freed.text()));
        }
        let mut previous = 0;
        for c in &script.checkpoints {
            if self.failed_before(c.line) {
                lines.push(format!("phase {} out_of_memory", c.label));
            }else {
                let p = pauses.iter().filter(|p|p.line>previous && p.line <= c.line).cloned().collect::<Vec<_>>();
                let s = stats(&p);
                lines.push(format!("phase {} collections {} pauses {} work {} freed {} max_pause {}", c.label, s.collections, s.count, s.work, s.freed, s.max));
            }
            previous = c.line;
        }
        lines.push(self.failed.map_or("status completed".into(), |(line, size)|format!("status out_of_memory line {line} size {size}")));
        lines
    }
    fn summary(&self) -> String {
        let s = stats(&self.pauses());
        let moves = self.m.objects.iter().map(|o|o.moves).collect::<Vec<_>>();
        let ending = if self.failed.is_some() {
            "-,-,-,-".into()
        }else {
            let(total, largest) = free_amount(&self.m.free_list());
            format!("{},{total},{largest},{}", self.m.pair(self.m.ids()).words, pct(total-largest, total))
        };
        format!("{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{ending}", self.entry.name, self.entry.algorithm, if self.failed.is_some() {
            "out_of_memory"
        }else {
            "completed"
        }, self.m.records.len(), s.count, self.m.records.iter().map(|r|r.live.count).sum::<usize>(), self.m.records.iter().map(|r|r.moved.count).sum::<usize>(), moves.iter().filter(| && m|m>0).count(), moves.iter().max().unwrap_or(&0), s.freed, s.work, s.p50, s.p90, s.max, self.peak_used)
    }
}
fn write_lines(name: &str, lines: Vec<String>) -> io::Result<()> {
    fs::write(format!("output/{name}"), if lines.is_empty() {
        String::new()
    }else {
        lines.join("\n")+"\n"
    })
}
fn join_blocks(parts: Vec<Vec<String>>) -> Vec<String> {
    let mut out = vec![];
    for(p, lines)in parts.into_iter().enumerate() {
        if p>0 {
            out.push(String::new())
        }
        out.extend(lines);
    }
    out
}
fn main() -> io::Result<()> {
    let config = read_config()?;
    let script = Script::analyze(read_script()?);
    let mut runs = vec![];
    for entry in &config.collectors {
        let mut run = Run::new(entry.clone(), config.size);
        run.simulate(&config, &script);
        runs.push(run);
    }
    let mut maps = vec![];
    for(i, c)in script.checkpoints.iter().enumerate() {
        for r in &runs {
            let mut block = vec![format!("checkpoint {} line {} collector {}", c.label, c.line, r.entry.name)];
            block.extend(r.observations.get(i).cloned().unwrap_or_else( || vec!["out_of_memory".into()]));
            maps.push(block);
        }
    }
    let mut leaks = vec![];
    for r in &runs {
        if !r.rc() {
            continue
        }
        let mut block = vec![format!("collector {}", r.entry.name)];
        for report in &r.reports {
            block.extend(report.clone())
        }
        if r.failed.is_some() {
            block.push("status out_of_memory".into())
        }
        leaks.push(block);
    }
    let mut summary = vec!["collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation".into()];
    summary.extend(runs.iter().map(Run::summary));
    fs::create_dir_all("output")?;
    write_lines("mutator.txt", script.report())?;
    write_lines("heap_maps.txt", join_blocks(maps))?;
    write_lines("collections.txt", join_blocks(runs.iter().map(|r|r.collection_lines(&config, &script)).collect()))?;
    write_lines("summary.csv", summary)?;
    write_lines("leaks.txt", if leaks.is_empty() {
        vec!["none".into()]
    }else {
        join_blocks(leaks)
    })
}
