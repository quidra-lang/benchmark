mod config_io;
mod cache;
mod protocol;
mod bus;
mod stats;
use std::collections::{BTreeMap,BTreeSet,VecDeque};
use config_io::{Config,Scenario,address};
use cache::Cache;
use stats::{Core,SERVICE};
struct Event {
    number: usize,
    cycle: usize,
    core: usize,
    operation: u8,
    address: usize,
    distance: Option<usize>
}
fn validate(config: &Config, lines: &[String]) -> (Vec<Event>,Vec<(usize,&'static str)>) {
    let mut events = Vec::new();
    let mut rejected = Vec::new();
    let mut previous = 0;
    for (index,line) in lines.iter().enumerate() {
        let w: Vec<_> = line.split(' ').collect();
        let mut reason = None;
        if !(w.len() == 3 || w.len() == 4) || w.iter().any(|s| s.is_empty()) {
            reason = Some("fields");
        } else if !config_io::decimal(w[0]) || w[0].len() > 7 {
            reason = Some("cycle");
        } else if !config_io::decimal(w[1]) || w[1].parse::<usize>().unwrap() >= config.cores {
            reason = Some("core");
        } else if !["R","W","FENCE"].contains(&w[2]) || (w[2] == "FENCE" && w.len() != 3) || (w[2] != "FENCE" && w.len() != 4) {
            reason = Some("op");
        } else if w[2] != "FENCE" && (!config_io::hexadecimal(w[3]) || usize::from_str_radix(w[3],16).unwrap()%4 != 0 || usize::from_str_radix(w[3],16).unwrap() > 0x7fffffff) {
            reason = Some("address");
        } else if w[0].parse::<usize>().unwrap() < previous {
            reason = Some("order");
        }
        if let Some(reason) = reason {
            rejected.push((index+1,reason));
        } else {
            let cycle = w[0].parse().unwrap();
            events.push(Event {
                number: events.len()+1,
                cycle,
                core: w[1].parse().unwrap(),
                operation: w[2].as_bytes()[0],
                address: if w[2] == "FENCE" {
                    0
                } else {
                    usize::from_str_radix(w[3],16).unwrap()
                },
                distance: None
            });
            previous = cycle;
        }
    }
    (events,rejected)
}
struct Fenwick {
    tree: Vec<i64>
}
impl Fenwick {
    fn add(&mut self, mut i: usize, value: i64) {
        while i < self.tree.len() {
            self.tree[i] += value;
            i += i&(!i+1);
        }
    }
    fn prefix(&self, mut i: usize) -> i64 {
        let mut sum = 0;
        while i > 0 {
            sum += self.tree[i];
            i &= i-1;
        }
        sum
    }
}
fn reuse(config: &Config, events: &mut [Event]) -> Vec<String> {
    let capacity = config.l1[1]*config.l1[2];
    let mut lines = Vec::new();
    for core in 0..config.cores {
        let indices: Vec<_> = events.iter().enumerate().filter(|(_,e)| e.core == core && e.operation != b'F').map(|(i,_)| i).collect();
        let blocks: Vec<_> = indices.iter().map(|&i| events[i].address/config.line).collect();
        let mut last = BTreeMap::new();
        let mut fenwick = Fenwick {
            tree: vec![0;indices.len()+1]
        };
        let mut histogram = [0usize;6];
        let mut cold = 0;
        let mut lru = [0usize;5];
        let capacities = [capacity/4,capacity/2,capacity,2*capacity,4*capacity];
        for (position,(&index,&block)) in indices.iter().zip(&blocks).enumerate() {
            let distance = if let Some(&previous) = last.get(&block) {
                let distance = (fenwick.prefix(position)-fenwick.prefix(previous)+1) as usize;
                fenwick.add(previous,-1);
                Some(distance)
            } else {
                cold += 1;
                None
            };
            last.insert(block,position+1);
            fenwick.add(position+1,1);
            events[index].distance = distance;
            if let Some(distance) = distance {
                let bucket = if distance == 1 {
                    0
                } else if distance <= 4 {
                    1
                } else if distance <= 16 {
                    2
                } else if distance <= 64 {
                    3
                } else if distance <= 256 {
                    4
                } else {
                    5
                };
                histogram[bucket] += 1;
            }
            for i in 0..5 {
                lru[i] += usize::from(distance.map_or(true,|d| d > capacities[i]));
            }
        }
        let mut future = BTreeMap::<usize,VecDeque<usize>>::new();
        for (i,&block) in blocks.iter().enumerate() {
            future.entry(block).or_default().push_back(i);
        }
        let mut held = BTreeSet::new();
        let mut optimal = 0;
        for &block in &blocks {
            future.get_mut(&block).unwrap().pop_front();
            if !held.contains(&block) {
                optimal += 1;
                if held.len() == capacity {
                    let mut victim = None;
                    let mut farthest = 0;
                    for &candidate in &held {
                        let next = future[&candidate].front().copied().unwrap_or(usize::MAX);
                        if victim.is_none() || next > farthest {
                            victim = Some(candidate);
                            farthest = next;
                        }
                    }
                    held.remove(&victim.unwrap());
                }
                held.insert(block);
            }
        }
        lines.push(format!("reuse c{} accesses {} lines {} distance {} cold {}",core,indices.len(),last.len(),stats::ranges(&["1","2-4","5-16","17-64","65-256","257+"],&histogram),cold));
        lines.push(format!("mrc c{} lru {} opt {}:{}",core,capacities.iter().zip(lru.iter()).map(|(capacity,misses)| format!("{}:{}",capacity,misses)).collect::<Vec<_>>().join(" "),capacity,optimal));
    }
    lines
}
#[derive(Default)] struct Hot {
    types: [usize;5],
    misses: usize,
    coherence: usize,
    invalidations: usize,
    cores: BTreeSet<usize>
}
struct Access {
    event: usize,
    issue: usize,
    core: usize,
    operation: u8,
    address: usize,
    latency: usize,
    service: usize,
    miss: Option<usize>,
    sharing: Option<bool>
}
struct Simulation<'a> {
    config: &'a Config,
    scenario: &'a Scenario,
    l1: Vec<Cache>,
    l2: Cache,
    bus: bus::Bus,
    cores: Vec<Core>,
    invalidations: BTreeMap<(usize,usize),BTreeSet<usize>>,
    l2_stats: [usize;7],
    snoop_hits: usize,
    fanout: Vec<usize>,
    latency_kind: [usize;2],
    histogram: [usize;6],
    accesses: Vec<Access>,
    hot: BTreeMap<usize,Hot>,
    watch: Vec<String>,
    last_writer: BTreeMap<usize,usize>,
    handoffs: BTreeMap<usize,usize>,
    word_writer: BTreeMap<(usize,usize),(usize,BTreeSet<usize>)>,
    communication: Vec<Vec<usize>>,
    coherence: BTreeMap<usize,[usize;2]>
}
impl<'a> Simulation<'a> {
    fn new(config: &'a Config, scenario: &'a Scenario) -> Self {
        Self {
            config,
            scenario,
            l1: (0..config.cores).map(|_| Cache::new(config.l1[2],config.l1[1],&scenario.l1_policy)).collect(),
            l2: Cache::new(config.l2[2],config.l2[1],&scenario.l2_policy),
            bus: bus::Bus::new(config.latency[3]),
            cores: vec![Core::default();config.cores],
            invalidations: BTreeMap::new(),
            l2_stats: [0;7],
            snoop_hits: 0,
            fanout: vec![0;config.cores],
            latency_kind: [0;2],
            histogram: [0;6],
            accesses: Vec::new(),
            hot: BTreeMap::new(),
            watch: Vec::new(),
            last_writer: BTreeMap::new(),
            handoffs: BTreeMap::new(),
            word_writer: BTreeMap::new(),
            communication: vec![vec![0;config.cores];config.cores],
            coherence: BTreeMap::new()
        }
    }
    fn tuple(&self, block: usize) -> Vec<u8> {
        self.l1.iter().map(|cache| cache.state(block)).chain(std::iter::once(self.l2.state(block))).collect()
    }
    fn record_transaction(&mut self, core: usize, kind: usize, block: usize) {
        self.cores[core].bus[kind] += 1;
        let hot = self.hot.entry(block).or_default();
        hot.types[kind] += 1;
        hot.cores.insert(core);
    }
    fn transaction(&mut self, core: usize, kind: usize, block: usize, word: usize, request: usize) -> (usize,usize) {
        let index = self.bus.assign(request,core,kind,block);
        let start = self.bus.transactions[index].start;
        self.record_transaction(core,kind,block);
        let mut snoops = Vec::new();
        let mut supplier = None;
        let mut flushed = false;
        let mut invalidations = 0;
        for other in 0..self.config.cores {
            if other == core {
                continue;
            }
            let state = self.l1[other].state(block);
            if state == b'I' {
                continue;
            }
            self.snoop_hits += 1;
            let (next,supply,flush) = protocol::snoop(&self.scenario.protocol,state,kind);
            snoops.push(format!("c{}:{}>{}",other,state as char,next as char));
            if next == b'I' {
                self.l1[other].remove(block);
                self.cores[core].snoop[0] += 1;
                self.cores[other].snoop[1] += 1;
                invalidations += 1;
                self.invalidations.insert((other,block),std::iter::once(word).collect());
            } else {
                self.l1[other].change(block,next);
            }
            if supply {
                supplier = Some(other);
                self.cores[other].snoop[2] += 1;
            }
            flushed |= flush;
        }
        self.hot.entry(block).or_default().invalidations += invalidations;
        if kind != 0 {
            self.fanout[invalidations] += 1;
        }
        let mut hit = false;
        let mut eviction = String::new();
        if kind != 2 {
            self.l2_stats[0] += 1;
            hit = self.l2.state(block) != b'I';
            if hit {
                self.l2_stats[1] += 1;
                self.l2.touch(block);
            } else {
                self.l2_stats[2] += 1;
                if let Some(victim) = self.l2.fill(block,b'C') {
                    self.l2_stats[5] += 1;
                    let mut back = Vec::new();
                    let mut dirty = victim.state == b'D';
                    for other in 0..self.config.cores {
                        if let Some(line) = self.l1[other].remove(victim.block) {
                            self.cores[other].snoop[3] += 1;
                            dirty |= protocol::dirty(line.state);
                            back.push(format!("c{}:{}",other,line.state as char));
                        }
                    }
                    if dirty {
                        self.l2_stats[6] += 1;
                    }
                    eviction = format!(" evict {} {} {}",address(victim.block*self.config.line),if back.is_empty() {
                        "none".to_owned()
                    } else {
                        back.join(" ")
                    },if dirty {
                        "dirty"
                    } else {
                        "clean"
                    });
                }
            }
            if flushed || kind == 3 {
                self.l2.change(block,b'D');
            }
            if flushed {
                self.l2_stats[3] += 1;
            }
        }
        let snoops = if snoops.is_empty() {
            "none".to_owned()
        } else {
            snoops.join(" ")
        };
        let mut detail = format!(" snoop {}",snoops);
        if kind == 0 || kind == 1 {
            detail.push_str(&format!(" data {} l2 {}{}",supplier.map_or_else(|| if hit {
                "L2".to_owned()
            } else {
                "mem".to_owned()
            },|c| format!("c{}",c)),if hit {
                "hit"
            } else {
                "miss"
            },eviction));
        } else if kind == 3 {
            detail.push_str(&format!(" l2 {}{}",if hit {
                "hit"
            } else {
                "miss"
            },eviction));
        }
        self.bus.describe(index,self.config.line,&detail);
        let service = if kind == 2 {
            1
        } else if kind == 3 {
            2
        } else if supplier.is_some() {
            3
        } else if hit {
            4
        } else {
            5
        };
        let end = start+self.config.latency[3]+if kind == 2 || (kind != 3 && supplier.is_some()) {
            0
        } else {
            self.config.latency[1]+if hit {
                0
            } else {
                self.config.latency[2]
            }
        };
        (end,service)
    }
    fn writeback(&mut self, core: usize, block: usize) {
        let index = self.bus.assign(self.bus.free,core,4,block);
        self.record_transaction(core,4,block);
        self.l2.touch(block);
        self.l2.change(block,b'D');
        self.l2_stats[4] += 1;
        self.bus.describe(index,self.config.line,"");
    }
    fn access(&mut self, event: &Event, issue: usize) -> usize {
        let core = event.core;
        let block = event.address/self.config.line;
        let word = (event.address%self.config.line)/4;
        let write = event.operation == b'W';
        let before: Vec<_> = self.config.watched.iter().map(|&address| self.tuple(address/self.config.line)).collect();
        let state = self.l1[core].state(block);
        let hit = state != b'I';
        let (kind,mut next) = protocol::request(&self.scenario.protocol,state,write);
        let mut miss = None;
        let mut sharing = None;
        self.cores[core].accesses += 1;
        self.cores[core].reads += usize::from(!write);
        self.cores[core].writes += usize::from(write);
        if hit {
            self.cores[core].hits += 1;
            self.l1[core].touch(block);
        } else {
            self.cores[core].misses += 1;
            let class = if event.distance.is_none() {
                0
            } else if let Some(words) = self.invalidations.get(&(core,block)) {
                let is_true = words.contains(&word);
                sharing = Some(is_true);
                self.cores[core].classes[if is_true {
                    4
                } else {
                    5
                }] += 1;
                self.coherence.entry(block).or_insert([0;2])[usize::from(!is_true)] += 1;
                3
            } else if event.distance.unwrap() > self.config.l1[1]*self.config.l1[2] {
                1
            } else {
                2
            };
            miss = Some(class);
            self.cores[core].classes[class] += 1;
            let hot = self.hot.entry(block).or_default();
            hot.misses += 1;
            hot.coherence += usize::from(class == 3);
        }
        if write {
            for other in 0..self.config.cores {
                if other != core {
                    if let Some(words) = self.invalidations.get_mut(&(other,block)) {
                        words.insert(word);
                    }
                }
            }
            if self.last_writer.get(&block).map_or(false,|&last| last != core) {
                *self.handoffs.entry(block).or_insert(0) += 1;
            }
            self.last_writer.insert(block,core);
            self.word_writer.insert((block,word),(core,BTreeSet::new()));
        } else if let Some((writer,readers)) = self.word_writer.get_mut(&(block,word)) {
            if *writer != core && readers.insert(core) {
                self.communication[*writer][core] += 1;
            }
        }
        if next == b'?' {
            next = if (0..self.config.cores).any(|other| other != core && self.l1[other].state(block) != b'I') {
                b'S'
            } else {
                b'E'
            };
        }
        let (end,service) = if let Some(kind) = kind {
            self.transaction(core,kind,block,word,issue+self.config.latency[0])
        } else {
            (issue+self.config.latency[0],0)
        };
        if hit {
            self.l1[core].change(block,next);
        } else if next != b'I' {
            let evicted = self.l1[core].fill(block,next);
            self.invalidations.remove(&(core,block));
            if let Some(evicted) = evicted {
                if protocol::dirty(evicted.state) {
                    self.writeback(core,evicted.block);
                }
            }
        }
        let latency = end-issue;
        self.cores[core].latency += latency;
        self.cores[core].service[service] += 1;
        self.cores[core].finish = self.cores[core].finish.max(end);
        self.latency_kind[usize::from(write)] += latency;
        let bucket = if latency == 1 {
            0
        } else if latency <= 9 {
            1
        } else if latency <= 29 {
            2
        } else if latency <= 99 {
            3
        } else if latency <= 299 {
            4
        } else {
            5
        };
        self.histogram[bucket] += 1;
        self.accesses.push(Access {
            event: event.number,
            issue,
            core,
            operation: event.operation,
            address: event.address,
            latency,
            service,
            miss,
            sharing
        });
        for (i,&watched) in self.config.watched.iter().enumerate() {
            let after = self.tuple(watched/self.config.line);
            if watched/self.config.line == block || before[i] != after {
                self.watch.push(format!("{} {} c{} {} {} line {} {} L2:{}",event.number,issue,core,event.operation as char,address(event.address),address(watched),after[..self.config.cores].iter().enumerate().map(|(c,&state)| format!("c{}:{}",c,state as char)).collect::<Vec<_>>().join(" "),after[self.config.cores] as char));
            }
        }
        end
    }
    fn run(&mut self, events: &[Event]) {
        let per_core: Vec<Vec<_>> = (0..self.config.cores).map(|c| events.iter().enumerate().filter(|(_,e)| e.core == c).map(|(i,_)| i).collect()).collect();
        let mut positions = vec![0;self.config.cores];
        let mut ready = vec![0usize;self.config.cores];
        let mut writes = ready.clone();
        loop {
            let Some(core) = (0..self.config.cores).filter(|&c| positions[c] < per_core[c].len()).min_by_key(|&c| (events[per_core[c][positions[c]]].cycle.max(ready[c]),c)) else {
                break;
            };
            let event = &events[per_core[core][positions[core]]];
            positions[core] += 1;
            let issue = event.cycle.max(ready[core]);
            if event.operation == b'F' {
                let end = issue.max(writes[core]);
                self.cores[core].fences += 1;
                self.cores[core].fence_stall += end-issue;
                self.cores[core].finish = self.cores[core].finish.max(end);
                ready[core] = end;
            } else {
                let end = self.access(event,issue);
                if event.operation == b'R' {
                    ready[core] = end;
                } else {
                    ready[core] = issue+self.config.latency[0];
                    writes[core] = writes[core].max(end);
                }
            }
        }
    }
    fn scenario_report(&self) -> Vec<String> {
        let mut lines = vec![format!("scenario {} {} {} {}",self.scenario.name,self.scenario.protocol,self.scenario.l1_policy,self.scenario.l2_policy)];
        for (c,statistics) in self.cores.iter().enumerate() {
            lines.extend(stats::lines(&format!("c{}",c),statistics));
        }
        let total = stats::total(&self.cores);
        lines.extend(stats::lines("total",&total));
        let l2 = self.l2_stats;
        let transactions = self.bus.transactions.len();
        let busy = transactions*self.config.latency[3];
        lines.push(format!("l2 lookups {} hits {} misses {} flushes {} writebacks {} evictions {} dirty_evictions {}",l2[0],l2[1],l2[2],l2[3],l2[4],l2[5],l2[6]));
        lines.push(format!("bus transactions {} busy {} wait {} utilization {}",transactions,busy,self.bus.wait,stats::decimal(100*busy,total.finish)));
        lines.push(format!("traffic command_bytes {} data_bytes {} memory_bytes {}",8*transactions,self.config.line*(total.bus[0]+total.bus[1]+total.bus[4])+4*total.bus[3],self.config.line*(l2[2]+l2[6])));
        lines.push(format!("snoops probes {} hits {} fanout {}",(self.config.cores-1)*(transactions-total.bus[4]),self.snoop_hits,self.fanout.iter().enumerate().map(|(n,count)| format!("{}:{}",n,count)).collect::<Vec<_>>().join(" ")));
        lines.push(format!("latencies reads {} writes {} histogram {}",self.latency_kind[0],self.latency_kind[1],stats::ranges(&["1","2-9","10-29","30-99","100-299","300+"],&self.histogram)));
        lines
    }
    fn hot_report(&self) -> Vec<String> {
        let mut entries: Vec<_> = self.hot.iter().filter(|(_,h)| h.types.iter().sum::<usize>() > 0).collect();
        entries.sort_by_key(|(&block,hot)| (std::cmp::Reverse(hot.types.iter().sum::<usize>()),block));
        let mut lines = vec![format!("hot {}",self.scenario.name)];
        for (rank,(&block,hot)) in entries.into_iter().take(self.config.top).enumerate() {
            lines.push(format!("{} {} transactions {} BusRd {} BusRdX {} BusUpgr {} BusWr {} WB {} misses {} coherence {} invalidations {} cores {}",rank+1,address(block*self.config.line),hot.types.iter().sum::<usize>(),hot.types[0],hot.types[1],hot.types[2],hot.types[3],hot.types[4],hot.misses,hot.coherence,hot.invalidations,stats::cores(&hot.cores)));
        }
        lines
    }
    fn interval_report(&self) -> Vec<String> {
        let width = self.config.interval;
        let finish = stats::total(&self.cores).finish;
        let mut lines = vec![format!("intervals {} {}",self.scenario.name,width)];
        for k in 0..=finish/width {
            let first = k*width;
            let end = first+width;
            let mut accesses = vec![0usize;self.config.cores];
            let mut misses = 0;
            for access in self.accesses.iter().filter(|a| first <= a.issue && a.issue < end) {
                accesses[access.core] += 1;
                misses += usize::from(access.miss.is_some());
            }
            let count = self.bus.transactions.iter().filter(|t| first <= t.start && t.start < end).count();
            let busy: usize = self.bus.transactions.iter().map(|t| (t.start+self.config.latency[3]).min(end).saturating_sub(t.start.max(first))).sum();
            lines.push(format!("{} {}-{} accesses {} misses {} transactions {} busy {} utilization {}",k,first,end-1,accesses.iter().map(usize::to_string).collect::<Vec<_>>().join(" "),misses,count,busy,stats::decimal(100*busy,width)));
        }
        lines
    }
    fn slow_report(&self) -> Vec<String> {
        let mut accesses: Vec<_> = self.accesses.iter().collect();
        accesses.sort_by_key(|a| (std::cmp::Reverse(a.latency),a.event));
        let mut lines = vec![format!("slowest {}",self.scenario.name)];
        for (rank,access) in accesses.into_iter().take(self.config.top).enumerate() {
            lines.push(format!("{} event {} cycle {} c{} {} {} latency {} service {}",rank+1,access.event,access.issue,access.core,access.operation as char,address(access.address),access.latency,SERVICE[access.service]));
        }
        lines
    }
    fn region_report(&self) -> Vec<String> {
        let find = |address: usize| self.config.regions.iter().position(|r| r.first <= address && address <= r.last).unwrap_or(self.config.regions.len());
        let mut rows = vec![[0usize;11];self.config.regions.len()+1];
        for access in &self.accesses {
            let row = &mut rows[find(access.address)];
            row[0] += 1;
            row[if access.operation == b'R' {
                1
            } else {
                2
            }] += 1;
            if let Some(class) = access.miss {
                row[4+class] += 1;
            } else {
                row[3] += 1;
            }
            row[10] += access.latency;
        }
        for transaction in &self.bus.transactions {
            rows[find(transaction.block*self.config.line)][8] += 1;
        }
        let mut lines = vec![format!("regions {}",self.scenario.name)];
        for (i,row) in rows.iter().enumerate() {
            let name = self.config.regions.get(i).map_or("other",|r| r.name.as_str());
            lines.push(format!("{} accesses {} reads {} writes {} hits {} compulsory {} capacity {} conflict {} coherence {} transactions {} latency {} amat {}",name,row[0],row[1],row[2],row[3],row[4],row[5],row[6],row[7],row[8],row[10],stats::amat(row[10],row[0])));
        }
        lines
    }
    fn sharing_report(&self, events: &[Event]) -> Vec<String> {
        struct Shared {
            readers: BTreeSet<usize>,
            writers: BTreeSet<usize>,
            reads: usize,
            writes: usize,
            words: BTreeMap<usize,(BTreeSet<usize>,BTreeSet<usize>)>
        }
        let mut sharing = BTreeMap::<usize,Shared>::new();
        for event in events.iter().filter(|e| e.operation != b'F') {
            let block = event.address/self.config.line;
            let word = (event.address%self.config.line)/4;
            let line = sharing.entry(block).or_insert_with(|| Shared {
                readers: BTreeSet::new(),
                writers: BTreeSet::new(),
                reads: 0,
                writes: 0,
                words: BTreeMap::new()
            });
            let entry = line.words.entry(word).or_default();
            if event.operation == b'R' {
                line.readers.insert(event.core);
                entry.0.insert(event.core);
                line.reads += 1;
            } else {
                line.writers.insert(event.core);
                entry.1.insert(event.core);
                line.writes += 1;
            }
        }
        let mut lines = Vec::new();
        let mut counts = [0usize;5];
        for (block,line) in sharing {
            let cores: BTreeSet<_> = line.readers.union(&line.writers).copied().collect();
            if cores.len() < 2 || line.writers.is_empty() {
                continue;
            }
            let true_line = line.words.values().any(|(readers,writers)| !writers.is_empty() && readers.union(writers).count() >= 2);
            let coherence = self.coherence.get(&block).copied().unwrap_or([0;2]);
            counts[0] += 1;
            counts[if true_line {
                1
            } else {
                2
            }] += 1;
            counts[3] += coherence[0];
            counts[4] += coherence[1];
            let words = line.words.iter().map(|(word,(readers,writers))| format!("w{}={}/{}",word,stats::cores(readers),stats::cores(writers))).collect::<Vec<_>>().join(" ");
            lines.push(format!("{} {} cores {} writers {} reads {} writes {} handoffs {} coherence {} true {} false {} words {}",address(block*self.config.line),if true_line {
                "true"
            } else {
                "false"
            },stats::cores(&cores),stats::cores(&line.writers),line.reads,line.writes,self.handoffs.get(&block).unwrap_or(&0),coherence[0]+coherence[1],coherence[0],coherence[1],words));
        }
        lines.push(format!("lines {} true_lines {} false_lines {} coherence {} true {} false {}",counts[0],counts[1],counts[2],counts[3]+counts[4],counts[3],counts[4]));
        lines.push("communication".to_owned());
        for (core,row) in self.communication.iter().enumerate() {
            lines.push(format!("c{} {}",core,row.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")));
        }
        lines
    }
    fn final_report(&self) -> Vec<String> {
        fn sets(cache: &Cache, name: &str, line_size: usize) -> Vec<String> {
            cache.sets.iter().enumerate().map(|(index,set)| format!("{} {} {} {} {} fills {} evictions {}",name,index,set.ways.iter().map(|line| line.map_or_else(|| "-".to_owned(),|line| format!("{}:{}",address(line.block*line_size),line.state as char))).collect::<Vec<_>>().join(" "),cache.policy.to_ascii_lowercase(),cache.order(index),set.fills,set.evictions)).collect()
        }
        let mut lines = Vec::new();
        for (core,cache) in self.l1.iter().enumerate() {
            lines.extend(sets(cache,&format!("c{}",core),self.config.line));
            let held: Vec<_> = cache.sets.iter().flat_map(|s| s.ways.iter().flatten()).collect();
            lines.push(format!("c{} lines {} M {} O {} E {} S {} V {}",core,held.len(),held.iter().filter(|l| l.state == b'M').count(),held.iter().filter(|l| l.state == b'O').count(),held.iter().filter(|l| l.state == b'E').count(),held.iter().filter(|l| l.state == b'S').count(),held.iter().filter(|l| l.state == b'V').count()));
        }
        lines.extend(sets(&self.l2,"L2",self.config.line));
        let held: Vec<_> = self.l2.sets.iter().flat_map(|s| s.ways.iter().flatten()).collect();
        let dirty = held.iter().filter(|l| l.state == b'D').count();
        let in_l1 = held.iter().filter(|l| self.l1.iter().any(|c| c.state(l.block) != b'I')).count();
        lines.push(format!("L2 lines {} dirty {} clean {} in_l1 {}",held.len(),dirty,held.len()-dirty,in_l1));
        lines
    }
}
fn main() {
    let (config,trace) = config_io::read();
    let (mut events,rejected) = validate(&config,&trace);
    let reuse = reuse(&config,&mut events);
    let mut header = vec![format!("trace lines {} accepted {} rejected {}",trace.len(),events.len(),rejected.len())];
    for (line,reason) in rejected {
        header.push(format!("reject line {} {}",line,reason));
    }
    header.push(format!("geometry cores {} line {} l1 {} {} sets {} l2 {} {} sets {}",config.cores,config.line,config.l1[0],config.l1[1],config.l1[2],config.l2[0],config.l2[1],config.l2[2]));
    header.push(format!("latency l1 {} l2 {} memory {} bus {}",config.latency[0],config.latency[1],config.latency[2],config.latency[3]));
    let mut paragraphs = vec![header,reuse];
    let mut simulations = Vec::new();
    for scenario in &config.scenarios {
        let mut simulation = Simulation::new(&config,scenario);
        simulation.run(&events);
        paragraphs.push(simulation.scenario_report());
        simulations.push(simulation);
    }
    let mut ranking: Vec<_> = (0..simulations.len()).collect();
    ranking.sort_by_key(|&i| (stats::total(&simulations[i].cores).finish,simulations[i].bus.transactions.len(),i));
    let mut lines = vec!["ranking".to_owned()];
    for (rank,&i) in ranking.iter().enumerate() {
        let s = &simulations[i];
        let total = stats::total(&s.cores);
        lines.push(format!("{} {} finish {} transactions {} amat {}",rank+1,s.scenario.name,total.finish,s.bus.transactions.len(),stats::amat(total.latency,total.accesses)));
    }
    paragraphs.push(lines);
    let primary = &simulations[config.primary];
    paragraphs.push(primary.hot_report());
    paragraphs.push(primary.interval_report());
    paragraphs.push(primary.slow_report());
    paragraphs.push(primary.region_report());
    let statistics = vec![paragraphs.iter().map(|p| p.join("\n")).collect::<Vec<_>>().join("\n\n")];
    config_io::write("stats.txt",&statistics);
    config_io::write("bus_log.txt",&primary.bus.transactions.iter().map(|t| t.text.clone()).collect::<Vec<_>>());
    config_io::write("watch.txt",&primary.watch);
    config_io::write("sharing.txt",&primary.sharing_report(&events));
    config_io::write("final_state.txt",&primary.final_report());
}
