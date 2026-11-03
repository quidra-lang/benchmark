use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};

const MODES: [&str; 6] = ["FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY"];
#[derive(Clone)]
struct Block {
    start: usize,
    size: usize,
    owner: Option<String>,
    stamp: usize,
}
impl Block {
    fn new(start: usize, size: usize) -> Self {
        Self { start, size, owner: None, stamp: 0 }
    }
    fn end(&self) -> usize { self.start + self.size }
    fn area(&self) -> String { format!("{}+{}", self.start, self.size) }
}
struct Heap {
    mode: String,
    size: usize,
    rover: usize,
    age: usize,
    blocks: Vec<Block>,
}
fn class(size: usize) -> usize { size.ilog2() as usize }
impl Heap {
    fn new(size: usize, mode: &str) -> Self {
        let mut block = Block::new(0, size);
        block.stamp = 1;
        Self { mode: mode.into(), size, rover: 0, age: 1, blocks: vec![block] }
    }
    fn buddy(&self) -> bool { self.mode == "BUDDY" }
    fn register(&mut self, mut block: Block) -> Block {
        self.age += 1;
        block.stamp = self.age;
        block
    }
    fn required(&self, n: usize) -> usize {
        let length = n.div_ceil(8) * 8 + 8;
        if self.buddy() { length.max(32).next_power_of_two() } else { length }
    }
    fn locate(&self, address: usize) -> usize {
        self.blocks.iter().position(|b| b.start <= address && address < b.end()).unwrap()
    }
    fn owned(&self, id: &str) -> usize {
        self.blocks.iter().position(|b| b.owner.as_deref() == Some(id)).unwrap()
    }
    fn used(&self) -> usize {
        self.blocks.iter().filter(|b| b.owner.is_some()).map(|b| b.size).sum()
    }
    fn fragmentation(&self) -> usize {
        let free: Vec<&Block> = self.blocks.iter().filter(|b| b.owner.is_none()).collect();
        let total: usize = free.iter().map(|b| b.size).sum();
        let largest = free.iter().map(|b| b.size).max().unwrap_or(0);
        if total == 0 { 0 } else { (total - largest) * 100 / total }
    }
    fn allocate(&mut self, length: usize, alignment: usize, id: &str) -> Option<usize> {
        let rover = self.locate(self.rover);
        let mut selected: Option<(i64, i64, usize, usize)> = None;
        for (i, block) in self.blocks.iter().enumerate() {
            if block.owner.is_some() { continue; }
            let mut place = (block.start + 8).div_ceil(alignment) * alignment - 8;
            if place > block.start && place - block.start < 16 { place += alignment; }
            if place + length > block.end() { continue; }
            let (first, second) = match self.mode.as_str() {
                "NEXT" => (((i + self.blocks.len() - rover) % self.blocks.len()) as i64, 0),
                "BEST" | "BUDDY" => (block.size as i64, block.start as i64),
                "WORST" => (-(block.size as i64), block.start as i64),
                "SEGFIT" => (class(block.size) as i64, -(block.stamp as i64)),
                _ => (block.start as i64, 0),
            };
            let choice = (first, second, i, place);
            if selected.is_none_or(|old| (first, second) < (old.0, old.1)) { selected = Some(choice); }
        }
        let (_, _, mut index, place) = selected?;
        if self.buddy() {
            while self.blocks[index].size > length {
                self.blocks[index].size /= 2;
                let block = &self.blocks[index];
                let upper = Block::new(block.end(), block.size);
                let upper = self.register(upper);
                self.blocks.insert(index + 1, upper);
            }
        } else {
            let old = self.blocks[index].clone();
            if place > old.start {
                let leading = self.register(Block::new(old.start, place - old.start));
                self.blocks[index] = leading;
                index += 1;
                self.blocks.insert(index, Block::new(place, old.end() - place));
            }
            let remainder = self.blocks[index].size - length;
            if remainder >= 16 {
                self.blocks[index].size = length;
                let tail = self.register(Block::new(place + length, remainder));
                self.blocks.insert(index + 1, tail);
            }
        }
        self.blocks[index].owner = Some(id.into());
        if self.mode == "NEXT" { self.rover = self.blocks[index].end() % self.size; }
        Some(index)
    }
    fn merge_next(&mut self, index: usize) {
        let upper = self.blocks.remove(index + 1);
        self.blocks[index].size += upper.size;
    }
    fn coalesce(&mut self, mut index: usize) -> (usize, usize) {
        let mut merges = 0;
        if self.buddy() {
            while self.blocks[index].size < self.size {
                let block = &self.blocks[index];
                let partner = if block.start % (2 * block.size) == 0 {
                    index + 1
                } else if index > 0 { index - 1 } else { break; };
                if partner >= self.blocks.len() || self.blocks[partner].owner.is_some()
                    || self.blocks[partner].size != block.size { break; }
                index = index.min(partner);
                self.merge_next(index);
                merges += 1;
            }
        } else {
            if index + 1 < self.blocks.len() && self.blocks[index + 1].owner.is_none() {
                self.merge_next(index);
                merges += 1;
            }
            if index > 0 && self.blocks[index - 1].owner.is_none() {
                index -= 1;
                self.merge_next(index);
                merges += 1;
            }
        }
        self.age += 1;
        self.blocks[index].stamp = self.age;
        (index, merges)
    }
    fn release(&mut self, index: usize) -> (usize, usize) {
        self.blocks[index].owner = None;
        self.coalesce(index)
    }
    fn resize(&mut self, index: usize, length: usize) -> Option<&'static str> {
        let start = self.blocks[index].start;
        let size = self.blocks[index].size;
        if length <= size {
            if self.buddy() {
                if length == size { return Some("kept"); }
                while self.blocks[index].size > length {
                    self.blocks[index].size /= 2;
                    let size = self.blocks[index].size;
                    let tail = self.register(Block::new(start + size, size));
                    self.blocks.insert(index + 1, tail);
                }
            } else {
                if size - length < 16 { return Some("kept"); }
                self.blocks[index].size = length;
                self.blocks.insert(index + 1, Block::new(start + length, size - length));
                self.coalesce(index + 1);
            }
            return Some("shrunk");
        }
        if self.buddy() {
            let mut extent = size;
            let mut last = index + 1;
            while extent < length {
                if start % (2 * extent) != 0 || last >= self.blocks.len()
                    || self.blocks[last].owner.is_some() || self.blocks[last].size != extent
                    || self.blocks[last].start != start + extent { return None; }
                extent *= 2;
                last += 1;
            }
            self.blocks.drain(index + 1..last);
            self.blocks[index].size = length;
        } else {
            if index + 1 >= self.blocks.len() || self.blocks[index + 1].owner.is_some() { return None; }
            let total = size + self.blocks[index + 1].size;
            if total < length { return None; }
            self.blocks.remove(index + 1);
            self.blocks[index].size = total;
            if total - length >= 16 {
                self.blocks[index].size = length;
                let tail = self.register(Block::new(start + length, total - length));
                self.blocks.insert(index + 1, tail);
            }
        }
        Some("grown")
    }
}
#[derive(Default)]
struct Record {
    state: u8,
    contents: Vec<i16>,
    root: bool,
    links: BTreeSet<String>,
    history: Vec<String>,
}
#[derive(Default)]
struct Simulator {
    heap: Option<Heap>,
    ids: BTreeMap<String, Record>,
    counters: [usize; 6],
    peak: usize,
    output: Vec<String>,
}
fn number(text: &str) -> usize { text.parse().unwrap() }
impl Simulator {
    fn emit(&mut self, text: String) { self.output.push(text); }
    fn record(&mut self, id: &str, text: String) {
        self.ids.entry(id.into()).or_default().history.push(text.clone());
        self.emit(text);
    }
    fn live(&self, id: &str) -> Result<(), String> {
        match self.ids.get(id).map_or(0, |r| r.state) {
            1 => Ok(()),
            2 => Err(format!("USE AFTER FREE {id}")),
            _ => Err(format!("UNKNOWN ID {id}")),
        }
    }
    fn range(&self, id: &str, offset: usize, length: usize) -> Result<(), String> {
        self.live(id)?;
        if offset + length > self.ids[id].contents.len() { return Err(format!("OUT OF BOUNDS {id}")); }
        Ok(())
    }
    fn reachable(&self) -> BTreeSet<String> {
        let mut found: BTreeSet<String> = self.ids.iter().filter(|(_, r)| r.state == 1 && r.root).map(|(id, _)| id.clone()).collect();
        let mut pending: Vec<String> = found.iter().cloned().collect();
        while let Some(id) = pending.pop() {
            for target in &self.ids[&id].links {
                if found.insert(target.clone()) { pending.push(target.clone()); }
            }
        }
        found
    }
    fn oom(&mut self, id: &str) -> String {
        self.counters[4] += 1;
        format!("OUT OF MEMORY {id}")
    }
    fn allocate_id(&mut self, verb: &str, id: &str, n: usize, alignment: usize, fill: i16) -> Result<(), String> {
        if n == 0 { return Err("BAD SIZE".into()); }
        if self.ids.get(id).is_some_and(|r| r.state == 1) { return Err(format!("DUPLICATE ID {id}")); }
        let heap = self.heap.as_mut().unwrap();
        let length = heap.required(n);
        let Some(index) = heap.allocate(length, alignment, id) else { return Err(self.oom(id)); };
        let text = format!("{verb} {id} addr={} block={}", heap.blocks[index].start + 8, heap.blocks[index].size);
        let record = self.ids.entry(id.into()).or_default();
        record.state = 1;
        record.contents = vec![fill; n];
        self.counters[0] += 1;
        self.record(id, text);
        Ok(())
    }
    fn free_id(&mut self, id: &str, verb: &str) -> Result<(), String> {
        let state = self.ids.get(id).map_or(0, |r| r.state);
        if state != 1 { return Err(format!("{} {id}", if state == 2 { "DOUBLE FREE" } else { "UNKNOWN ID" })); }
        let heap = self.heap.as_mut().unwrap();
        let index = heap.owned(id);
        let size = heap.blocks[index].size;
        let (index, merges) = heap.release(index);
        let text = format!("{verb} {id} block={size} merges={merges} free={}", heap.blocks[index].area());
        let record = self.ids.get_mut(id).unwrap();
        record.state = 2;
        record.root = false;
        record.links.clear();
        record.contents.clear();
        for record in self.ids.values_mut() { record.links.remove(id); }
        self.record(id, text);
        if verb == "FREE" { self.counters[1] += 1; }
        Ok(())
    }
    fn tree_lines(heap: &Heap, start: usize, size: usize, depth: usize, out: &mut Vec<String>) {
        let label = format!("{}{start}+{size}", " ".repeat(depth * 2));
        let block = &heap.blocks[heap.locate(start)];
        if block.start == start && block.size == size {
            out.push(format!("{label} {}", block.owner.as_ref().map_or("FREE".into(), |id| format!("USED {id}"))));
        } else {
            out.push(format!("{label} split"));
            Self::tree_lines(heap, start, size / 2, depth + 1, out);
            Self::tree_lines(heap, start + size / 2, size / 2, depth + 1, out);
        }
    }
    fn run(&mut self, a: &[&str]) -> Result<(), String> {
        let op = a[0];
        if op == "HEAP" {
            let size = number(a[1]);
            if !(32..=65536).contains(&size) || size % 8 != 0 || (a[2] == "BUDDY" && !size.is_power_of_two()) {
                return Err("BAD HEAP SIZE".into());
            }
            self.heap = Some(Heap::new(size, a[2]));
            self.ids.clear(); self.counters = [0; 6]; self.peak = 0;
            self.emit(format!("HEAP size={size} mode={}", a[2]));
            return Ok(());
        }
        if op == "BENCH" {
            let size = number(a[1]);
            if !(32..=65536).contains(&size) || !size.is_power_of_two() { return Err("BAD HEAP SIZE".into()); }
            let seed: u64 = a[2].parse().unwrap();
            let ops = number(a[3]); let maxreq = number(a[4]);
            self.emit(format!("BENCH heap={size} seed={seed} ops={ops} maxreq={maxreq}"));
            for mode in MODES {
                let mut heap = Heap::new(size, mode);
                let mut live = Vec::<String>::new();
                let (mut ok, mut fail, mut peak) = (0, 0, 0);
                let mut x = seed;
                for step in 0..ops {
                    x = x * 48271 % 2147483647;
                    let alloc = live.is_empty() || x % 3 != 0;
                    x = x * 48271 % 2147483647;
                    if alloc {
                        let id = step.to_string();
                        let n = 1 + x as usize % maxreq;
                        let length = heap.required(n);
                        if heap.allocate(length, 8, &id).is_some() { ok += 1; live.push(id); } else { fail += 1; }
                    } else {
                        let id = live.remove(x as usize % live.len());
                        let index = heap.owned(&id); heap.release(index);
                    }
                    peak = peak.max(heap.used());
                }
                self.emit(format!("BENCH {mode} ok={ok} fail={fail} peak={peak} used={} frag={} blocks={}", heap.used(), heap.fragmentation(), heap.blocks.len()));
            }
            return Ok(());
        }
        if self.heap.is_none() { return Err("NO HEAP".into()); }
        match op {
            "MALLOC" | "CALLOC" | "MEMALIGN" => {
                let mut alignment = 8;
                let n = match op {
                    "CALLOC" => number(a[2]) * number(a[3]),
                    "MEMALIGN" => {
                        if self.heap.as_ref().unwrap().buddy() { return Err("UNSUPPORTED IN BUDDY MODE".into()); }
                        alignment = number(a[2]);
                        if !(8..=4096).contains(&alignment) || !alignment.is_power_of_two() { return Err("BAD ALIGNMENT".into()); }
                        number(a[3])
                    }
                    _ => number(a[2]),
                };
                self.allocate_id(op, a[1], n, alignment, if op == "CALLOC" { 0 } else { -1 })?;
            }
            "FREE" => self.free_id(a[1], "FREE")?,
            "REALLOC" => {
                let id = a[1]; let n = number(a[2]);
                if n == 0 { return self.free_id(id, "FREE"); }
                let state = self.ids.get(id).map_or(0, |r| r.state);
                if state == 0 { return self.allocate_id("MALLOC", id, n, 8, -1); }
                self.live(id)?;
                let heap = self.heap.as_mut().unwrap();
                let index = heap.owned(id); let old = heap.blocks[index].start;
                let length = heap.required(n);
                let kind = if let Some(kind) = heap.resize(index, length) {
                    kind.to_string()
                } else {
                    if heap.allocate(length, 8, id).is_none() { return Err(self.oom(id)); }
                    let old_index = heap.locate(old);
                    heap.release(old_index);
                    self.counters[3] += 1;
                    format!("moved from={}", old + 8)
                };
                let index = heap.owned(id);
                let text = format!("REALLOC {id} addr={} block={} {kind}", heap.blocks[index].start + 8, heap.blocks[index].size);
                self.ids.get_mut(id).unwrap().contents.resize(n, -1);
                self.counters[2] += 1;
                self.record(id, text);
            }
            "FILL" | "READ" | "COPY" => {
                let id = a[1]; let offset = number(a[2]);
                let length = number(a[if op == "COPY" { 5 } else { 3 }]);
                self.range(id, offset, length)?;
                if op == "COPY" {
                    let source = a[3]; let source_offset = number(a[4]);
                    self.range(source, source_offset, length)?;
                    let bytes = self.ids[source].contents[source_offset..source_offset + length].to_vec();
                    self.ids.get_mut(id).unwrap().contents[offset..offset + length].copy_from_slice(&bytes);
                    self.emit(format!("COPY {id} {offset}+{length} from {source} {source_offset}"));
                } else if op == "FILL" {
                    let value = number(a[4]) as i16;
                    self.ids.get_mut(id).unwrap().contents[offset..offset + length].fill(value);
                    self.emit(format!("FILL {id} {offset}+{length} = {value}"));
                } else {
                    let bytes: Vec<String> = self.ids[id].contents[offset..offset + length].iter().map(|v| if *v < 0 { "?".into() } else { v.to_string() }).collect();
                    self.emit(format!("READ {id} {offset}+{length} = {}", bytes.join(" ")));
                }
            }
            "ROOT" | "UNROOT" | "LINK" | "UNLINK" => {
                let id = a[1]; self.live(id)?;
                if op == "ROOT" || op == "UNROOT" {
                    let record = self.ids.get_mut(id).unwrap();
                    if op == "UNROOT" && !record.root { return Err(format!("NOT ROOT {id}")); }
                    record.root = op == "ROOT";
                    self.emit(format!("{op} {id}"));
                } else {
                    let target = a[2]; self.live(target)?;
                    let record = self.ids.get_mut(id).unwrap();
                    if op == "LINK" { record.links.insert(target.into()); }
                    else if !record.links.remove(target) { return Err(format!("NO LINK {id} {target}")); }
                    self.emit(format!("{op} {id} {target}"));
                }
            }
            "GC" | "LEAKS" => {
                let found = self.reachable();
                let heap = self.heap.as_ref().unwrap();
                let mut names: Vec<String> = heap.blocks.iter().filter_map(|b| b.owner.clone()).collect();
                if op == "GC" {
                    names.retain(|id| !found.contains(id));
                    let bytes: usize = names.iter().map(|id| heap.blocks[heap.owned(id)].size).sum();
                    self.emit(format!("GC collected={} bytes={bytes}", names.len()));
                    for id in &names { self.free_id(id, "COLLECT")?; }
                    self.counters[5] += names.len();
                } else {
                    names.sort();
                    let requested: usize = names.iter().map(|id| self.ids[id].contents.len()).sum();
                    let lost = names.iter().filter(|id| !found.contains(*id)).count();
                    let mut lines = vec![format!("LEAKS count={} requested={requested} lost={lost}", names.len())];
                    for id in &names {
                        let block = &heap.blocks[heap.owned(id)];
                        lines.push(format!("LEAK {id} addr={} block={} req={} {}", block.start + 8, block.size, self.ids[id].contents.len(), if found.contains(id) { "reachable" } else { "lost" }));
                    }
                    self.output.extend(lines);
                }
            }
            "HISTORY" => {
                let events = self.ids.get(a[1]).map_or_else(Vec::new, |r| r.history.clone());
                self.emit(format!("HISTORY {} events={}", a[1], events.len()));
                self.output.extend(events);
            }
            "SBRK" => {
                let k = number(a[1]); let heap = self.heap.as_mut().unwrap();
                if heap.size + k > 65536 || if heap.buddy() { k != heap.size } else { k < 16 || k % 8 != 0 } {
                    return Err("BAD SBRK SIZE".into());
                }
                heap.blocks.push(Block::new(heap.size, k)); heap.size += k;
                let last = heap.blocks.len() - 1;
                let (index, _) = heap.coalesce(last);
                let text = format!("SBRK heap={} free={}", heap.size, heap.blocks[index].area()); self.emit(text);
            }
            "TRIM" => {
                let heap = self.heap.as_mut().unwrap(); let old = heap.size;
                while heap.blocks.len() > 1 {
                    let block = heap.blocks.last().unwrap();
                    if block.owner.is_some() || (heap.buddy() && block.size * 2 != heap.size) { break; }
                    heap.size = block.start; heap.blocks.pop();
                    if !heap.buddy() { break; }
                }
                if heap.rover >= heap.size { heap.rover = 0; }
                let text = format!("TRIM heap={} released={}", heap.size, old - heap.size); self.emit(text);
            }
            "COMPACT" => {
                let heap = self.heap.as_mut().unwrap();
                if heap.buddy() { return Err("UNSUPPORTED IN BUDDY MODE".into()); }
                heap.blocks.retain(|b| b.owner.is_some());
                let mut address = 0; let mut moved = Vec::new();
                for block in &mut heap.blocks {
                    if block.start != address {
                        let id = block.owner.as_ref().unwrap().clone();
                        moved.push((id.clone(), format!("MOVE {id} {} -> {}", block.start + 8, address + 8)));
                        block.start = address;
                    }
                    address += block.size;
                }
                let free = if address < heap.size {
                    let block = heap.register(Block::new(address, heap.size - address));
                    let area = block.area(); heap.blocks.push(block); area
                } else { "none".into() };
                heap.rover = 0; self.counters[3] += moved.len();
                self.emit(format!("COMPACT moved={} free={free}", moved.len()));
                for (id, line) in moved { self.record(&id, line); }
            }
            "WHO" => {
                let address = number(a[1]); let heap = self.heap.as_ref().unwrap();
                let detail = if address >= heap.size { "outside".into() } else {
                    let block = &heap.blocks[heap.locate(address)];
                    if let Some(id) = &block.owner {
                        if address < block.start + 8 { format!("header {id}") }
                        else {
                            let offset = address - block.start - 8;
                            format!("{} {id}+{offset}", if offset < self.ids[id].contents.len() { "data" } else { "slack" })
                        }
                    } else { format!("free {}", block.area()) }
                };
                self.emit(format!("WHO {address} {detail}"));
            }
            "DUMP" => {
                let heap = self.heap.as_ref().unwrap();
                let mut first = format!("DUMP mode={} heap={} blocks={}", heap.mode, heap.size, heap.blocks.len());
                if heap.mode == "NEXT" { first += &format!(" rover={}", heap.rover); }
                let mut lines = vec![first];
                for block in &heap.blocks {
                    let detail = block.owner.as_ref().map_or("FREE".into(), |id| format!("USED {id} req={}", self.ids[id].contents.len()));
                    lines.push(format!("{} {} {detail}", block.start, block.size));
                }
                self.output.extend(lines);
            }
            "MAP" => {
                let heap = self.heap.as_ref().unwrap();
                let mut units = String::new();
                for block in &heap.blocks {
                    units.push(if block.owner.is_some() { 'H' } else { 'F' });
                    for k in 0..block.size / 8 - 1 {
                        units.push(block.owner.as_ref().map_or('.', |id| if k * 8 < self.ids[id].contents.len() { '#' } else { '-' }));
                    }
                }
                let mut lines = vec![format!("MAP heap={}", heap.size)];
                for first in (0..units.len()).step_by(64) { lines.push(format!("{:05} {}", first * 8, &units[first..(first + 64).min(units.len())])); }
                self.output.extend(lines);
            }
            "FREELIST" => {
                let heap = self.heap.as_ref().unwrap();
                let mut groups = BTreeMap::<usize, Vec<&Block>>::new(); let mut count = 0;
                for block in &heap.blocks {
                    if block.owner.is_none() { groups.entry(class(block.size)).or_default().push(block); count += 1; }
                }
                let mut lines = vec![format!("FREELIST count={count}")];
                for (k, mut blocks) in groups {
                    if heap.mode == "SEGFIT" { blocks.sort_by_key(|b| std::cmp::Reverse(b.stamp)); }
                    lines.push(format!("{}-{}: {}", 1usize << k, (1usize << (k + 1)) - 1, blocks.iter().map(|b| b.area()).collect::<Vec<_>>().join(" ")));
                }
                self.output.extend(lines);
            }
            "TREE" => {
                let heap = self.heap.as_ref().unwrap();
                if !heap.buddy() { return Err("REQUIRES BUDDY MODE".into()); }
                self.output.push(format!("TREE heap={}", heap.size));
                Self::tree_lines(heap, 0, heap.size, 0, &mut self.output);
            }
            "STATS" => {
                let heap = self.heap.as_ref().unwrap();
                let used = heap.used();
                let free: Vec<&Block> = heap.blocks.iter().filter(|b| b.owner.is_none()).collect();
                let largest = free.iter().map(|b| b.size).max().unwrap_or(0);
                let requested: usize = self.ids.values().filter(|r| r.state == 1).map(|r| r.contents.len()).sum();
                let text = format!("STATS used={used} used_blocks={} free={} free_blocks={} largest={largest} frag={} requested={requested} peak={}", heap.blocks.len() - free.len(), heap.size - used, free.len(), heap.fragmentation(), self.peak);
                self.emit(text);
                let c = self.counters;
                self.emit(format!("OPS allocs={} frees={} reallocs={} moves={} failures={} collected={}", c[0], c[1], c[2], c[3], c[4], c[5]));
            }
            _ => unreachable!(),
        }
        Ok(())
    }
}
fn main() {
    let mut input = String::new(); io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines(); let count: usize = lines.next().unwrap().parse().unwrap();
    let mut simulator = Simulator::default();
    for line in lines.take(count) {
        let args: Vec<&str> = line.split_whitespace().collect();
        if let Err(message) = simulator.run(&args) { simulator.emit(format!("ERROR {message}")); }
        if let Some(heap) = &simulator.heap { simulator.peak = simulator.peak.max(heap.used()); }
    }
    println!("{}", simulator.output.join("\n"));
}
