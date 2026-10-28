mod network;
mod clocks;
mod processes;
mod snapshot;
mod analysis;

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use processes::{Action, Destination, Event, EventKind, Message, Copy, Program};
use network::{Kind, Packet, Topology};

struct Params {
    seed: i64,
    end: i64,
    count_time: i64,
    compare: Vec<(String, String)>,
    cuts: Vec<Vec<usize>>,
    predicates: Vec<i64>,
}

impl Params {
    fn read() -> Self {
        let mut p = Self { seed: 0, end: 0, count_time: 0, compare: Vec::new(),
            cuts: Vec::new(), predicates: Vec::new() };
        for line in fs::read_to_string("input/params.txt").unwrap().lines() {
            let w: Vec<_> = line.split_whitespace().collect();
            match w[0] {
                "SEED" => p.seed = w[1].parse().unwrap(),
                "END" => p.end = w[1].parse().unwrap(),
                "CUTCOUNT" => p.count_time = w[1].parse().unwrap(),
                "COMPARE" => p.compare.push((w[1].to_owned(), w[2].to_owned())),
                "CUT" => p.cuts.push(w[1..].iter().map(|x| x.parse().unwrap()).collect()),
                _ => p.predicates.push(w[1].parse().unwrap()),
            }
        }
        p
    }
}

enum Item { Action(Action), Arrival(usize) }

enum Occurrence { Event(usize), Snapshot(usize, usize) }

struct Simulation<'a> {
    topology: &'a Topology,
    programs: &'a [Program],
    end: i64,
    raw: bool,
    time: i64,
    serial: usize,
    queue: BTreeMap<(i64, usize, usize), Item>,
    rng: network::Generator,
    channels: Vec<network::State>,
    states: Vec<processes::State>,
    events: Vec<Event>,
    messages: Vec<Message>,
    copies: Vec<Copy>,
    packets: Vec<Packet>,
    snapshots: Vec<snapshot::Snapshot>,
    occurrences: Vec<Occurrence>,
}

impl<'a> Simulation<'a> {
    fn run(topology: &'a Topology, programs: &'a [Program], params: &Params, raw: bool) -> Self {
        let n = programs.len();
        let mut s = Self { topology, programs, end: params.end, raw, time: 0, serial: 0,
            queue: BTreeMap::new(), rng: network::Generator { state: params.seed, draws: 0 },
            channels: (0..n*n).map(|_| network::State::new(n)).collect(),
            states: programs.iter().map(|p| processes::State::new(p.initial, n)).collect(),
            events: Vec::new(), messages: Vec::new(), copies: Vec::new(), packets: Vec::new(),
            snapshots: Vec::new(), occurrences: Vec::new() };
        for (time, process, action) in processes::expand(programs, params.end) {
            s.enqueue(time, process, Item::Action(action));
        }
        while let Some((key, item)) = s.queue.pop_first() {
            if key.0 > s.end { break; }
            s.time = key.0;
            match item {
                Item::Action(action) => s.execute(key.1, action, None),
                Item::Arrival(packet) => s.arrive(packet),
            }
        }
        s
    }

    fn enqueue(&mut self, time: i64, process: usize, item: Item) {
        self.serial += 1;
        self.queue.insert((time, process, self.serial), item);
    }

    fn record(&mut self, process: usize, kind: EventKind, sent: Option<usize>) -> usize {
        let incoming = sent.map(|e| (self.events[e].lamport, self.events[e].vector.clone()));
        let state = &mut self.states[process];
        if let Some((l, v)) = incoming {
            clocks::receive(&mut state.lamport, &mut state.vector, process, l, &v);
        } else {
            clocks::local(&mut state.lamport, &mut state.vector, process);
        }
        let category = match &kind {
            EventKind::Local(_) => 0, EventKind::NoFunds { .. } => 1,
            EventKind::Send(_) => 2, EventKind::Broadcast(_) => 3, EventKind::Receive(_) => 4,
        };
        state.counts[category] += 1;
        state.minimum = state.minimum.min(state.balance);
        let index = self.events.len();
        self.events.push(Event { process, ordinal: state.events.len() + 1, time: self.time,
            lamport: state.lamport, vector: state.vector.clone(), balance: state.balance, kind });
        state.events.push(index);
        self.occurrences.push(Occurrence::Event(index));
        index
    }

    fn destination(destination: Destination, sender: Option<usize>) -> usize {
        match destination { Destination::Process(p) => p, Destination::Sender => sender.unwrap() }
    }

    fn execute(&mut self, process: usize, action: Action, sender: Option<usize>) {
        match action {
            Action::Local(label) => { self.record(process, EventKind::Local(label), None); }
            Action::Send(destination, tag) => {
                let d = Self::destination(destination, sender);
                self.send(process, Some(d), tag, 0);
            }
            Action::Transfer(destination, amount) => {
                let d = Self::destination(destination, sender);
                if self.states[process].balance < amount {
                    self.record(process, EventKind::NoFunds { destination: d, amount }, None);
                } else {
                    self.states[process].balance -= amount;
                    self.states[process].sent += amount;
                    self.send(process, Some(d), "transfer".to_owned(), amount);
                }
            }
            Action::Broadcast(tag) => {
                self.states[process].broadcast[process] += 1;
                self.send(process, None, tag, 0);
            }
            Action::Snapshot(name) => {
                let index = self.snapshots.iter().position(|s| s.name == name).unwrap_or_else(|| {
                    self.snapshots.push(snapshot::Snapshot::new(name, self.time, self.states.len()));
                    self.snapshots.len() - 1
                });
                if self.snapshots[index].records[process].is_some() {
                    self.snapshots[index].ignored.push((process, self.time));
                } else { self.record_snapshot(index, process, "initiate".to_owned()); }
            }
        }
    }

    fn send(&mut self, source: usize, destination: Option<usize>, tag: String, amount: i64) {
        let index = self.messages.len();
        self.messages.push(Message { source, destination, broadcast: destination.is_none(), tag, amount,
            event: self.events.len(), stamp: self.states[source].broadcast.clone(), copies: Vec::new() });
        self.record(source, if destination.is_none() { EventKind::Broadcast(index) }
            else { EventKind::Send(index) }, None);
        let destinations: Vec<_> = if let Some(d) = destination { vec![d] }
            else { (0..self.states.len()).filter(|&d| d != source).collect() };
        for d in destinations {
            let copy = self.copies.len();
            self.copies.push(Copy { message: index, source, destination: d, packet: self.packets.len(),
                received: None, fifo: false, causal: false, missing: Vec::new() });
            self.messages[index].copies.push(copy);
            self.dispatch(source, d, Kind::Copy(copy));
        }
    }

    fn dispatch(&mut self, source: usize, destination: usize, kind: Kind) {
        let channel = source * self.states.len() + destination;
        let vector = match kind {
            Kind::Copy(c) => Some(self.events[self.messages[self.copies[c].message].event].vector.clone()),
            Kind::Marker(_) => None,
        };
        let (sequence, arrival) = self.channels[channel].dispatch(
            self.topology.channels[channel].as_ref().unwrap(), &mut self.rng, self.time, vector.as_deref());
        let index = self.packets.len();
        self.packets.push(Packet { source, destination, sequence, dispatch: self.time, arrival, kind });
        if let Kind::Marker(s) = kind { self.snapshots[s].channels[channel].dispatched = Some(self.time); }
        self.enqueue(arrival, destination, Item::Arrival(index));
    }

    fn record_snapshot(&mut self, snapshot: usize, process: usize, reason: String) {
        let state = &self.states[process];
        self.snapshots[snapshot].records[process] = Some(snapshot::Record {
            time: self.time, reason, balance: state.balance, lamport: state.lamport,
            vector: state.vector.clone(), pending: state.hold.clone(),
        });
        self.occurrences.push(Occurrence::Snapshot(snapshot, process));
        for destination in 0..self.states.len() {
            if destination != process { self.dispatch(process, destination, Kind::Marker(snapshot)); }
        }
    }

    fn marker(&mut self, snapshot: usize, source: usize, destination: usize) {
        if self.snapshots[snapshot].records[destination].is_none() {
            self.record_snapshot(snapshot, destination, format!("marker {}", self.topology.names[source]));
        }
        let n = self.states.len();
        self.snapshots[snapshot].channels[source * n + destination].accepted = Some(self.time);
        if (0..n).all(|s| (0..n).all(|d| s == d || self.snapshots[snapshot].channels[s*n+d].accepted.is_some())) {
            self.snapshots[snapshot].completed = Some(self.time);
        }
    }

    fn arrive(&mut self, index: usize) {
        let packet = self.packets[index].clone();
        let p = packet.destination;
        let r = packet.source;
        if self.raw {
            self.accept(index);
        } else if packet.sequence != self.states[p].next[r] {
            self.states[p].reorder[r].insert(packet.sequence, index);
            self.channels[r * self.states.len() + p].buffered += 1;
            if let Kind::Copy(copy) = packet.kind { self.copies[copy].fifo = true; }
        } else {
            self.accept(index);
            loop {
                let next = self.states[p].next[r];
                let waiting = self.states[p].reorder[r].remove(&next);
                if let Some(i) = waiting { self.accept(i); } else { break; }
            }
        }
        let held = self.states[p].hold.len() + self.states[p].reorder.iter().map(BTreeMap::len).sum::<usize>();
        self.states[p].max_held = self.states[p].max_held.max(held);
    }

    fn acceptable(&self, copy: usize) -> bool {
        let c = &self.copies[copy];
        clocks::deliverable(&self.messages[c.message].stamp, &self.states[c.destination].broadcast, c.source)
    }

    fn accept(&mut self, index: usize) {
        let packet = self.packets[index].clone();
        let p = packet.destination;
        self.states[p].next[packet.source] += 1;
        let copy = match packet.kind {
            Kind::Marker(snapshot) => { self.marker(snapshot, packet.source, p); return; }
            Kind::Copy(copy) => copy,
        };
        let channel = packet.source * self.states.len() + p;
        for snapshot in &mut self.snapshots {
            if snapshot.records[p].is_some() && snapshot.channels[channel].accepted.is_none() {
                snapshot.channels[channel].copies.push(copy);
            }
        }
        if !self.messages[self.copies[copy].message].broadcast || self.raw {
            self.deliver(copy);
        } else if self.acceptable(copy) {
            self.deliver(copy);
            loop {
                let next = self.states[p].hold.iter().position(|&c| self.acceptable(c));
                if let Some(position) = next {
                    let c = self.states[p].hold.remove(position);
                    self.deliver(c);
                } else { break; }
            }
        } else {
            self.copies[copy].causal = true;
            self.copies[copy].missing = clocks::missing(&self.messages[self.copies[copy].message].stamp,
                &self.states[p].broadcast, packet.source);
            self.states[p].hold.push(copy);
        }
    }

    fn deliver(&mut self, copy: usize) {
        let c = &self.copies[copy];
        let (p, source, message) = (c.destination, c.source, c.message);
        let m = &self.messages[message];
        let (event, amount, broadcast, tag) = (m.event, m.amount, m.broadcast, m.tag.clone());
        if broadcast { self.states[p].broadcast[source] += 1; }
        self.states[p].balance += amount;
        self.states[p].received += amount;
        let received = self.record(p, EventKind::Receive(copy), Some(event));
        self.copies[copy].received = Some(received);
        self.states[p].delivered.push(copy);
        let actions: Vec<_> = self.programs[p].reactions.iter().filter(|(t, _)| *t == tag)
            .map(|(_, a)| a.clone()).collect();
        for action in actions { self.execute(p, action, Some(source)); }
    }

    fn name(&self, event: usize) -> String {
        let e = &self.events[event];
        format!("{}.{}", self.topology.names[e.process], e.ordinal)
    }

    fn names(&self, processes: &[usize]) -> String {
        processes.iter().map(|&p| self.topology.names[p].as_str()).collect::<Vec<_>>().join(",")
    }

    fn copy_name(&self, copy: usize) -> String {
        let c = &self.copies[copy];
        format!("m{}->{}", c.message + 1, self.topology.names[c.destination])
    }

    fn initial(&self) -> i64 { self.programs.iter().map(|p| p.initial).sum() }

    fn cut(&self, c: &[usize]) -> snapshot::Cut {
        snapshot::evaluate(c, self.programs, &self.states, &self.events, &self.messages, &self.copies)
    }

    fn verdict(&self, cut: &snapshot::Cut) -> String {
        if cut.orphans.is_empty() { "yes".to_owned() }
        else { format!("no {}", cut.orphans.iter().map(|&c| self.copy_name(c)).collect::<Vec<_>>().join(" ")) }
    }

    fn ranges(&self, events: &[usize]) -> String {
        let mut parts = Vec::new();
        let mut i = 0;
        while i < events.len() {
            let first = &self.events[events[i]];
            let mut j = i + 1;
            while j < events.len() && self.events[events[j]].process == first.process
                && self.events[events[j]].ordinal == self.events[events[j-1]].ordinal + 1 { j += 1; }
            let mut part = self.name(events[i]);
            if j > i + 1 { part.push_str(&format!("-{}", self.events[events[j-1]].ordinal)); }
            parts.push(part);
            i = j;
        }
        parts.join(" ")
    }

    fn longest(&self) -> Vec<usize> {
        let Some((mut current, _)) = self.events.iter().enumerate().min_by_key(|(i, e)|
            (std::cmp::Reverse(e.lamport), *i)) else { return Vec::new(); };
        let mut chain = vec![current];
        while self.events[current].lamport > 1 {
            let e = &self.events[current];
            let sent = match e.kind { EventKind::Receive(c) => Some(self.messages[self.copies[c].message].event), _ => None };
            current = if let Some(sent) = sent.filter(|&s| self.events[s].lamport + 1 == e.lamport) { sent }
                else { self.states[e.process].events[e.ordinal - 2] };
            chain.push(current);
        }
        chain.reverse();
        chain
    }

    fn broadcast_lists(&self) -> Vec<Vec<usize>> {
        self.states.iter().map(|s| s.events.iter().filter_map(|&e| match self.events[e].kind {
            EventKind::Broadcast(m) => Some(m),
            EventKind::Receive(c) if self.messages[self.copies[c].message].broadcast => Some(self.copies[c].message),
            _ => None,
        }).collect()).collect()
    }

    fn trace(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for (i, event) in self.events.iter().enumerate() {
            let (kind, details) = match &event.kind {
                EventKind::Local(label) => ("LOCAL", label.clone()),
                EventKind::NoFunds { destination, amount } => ("NOFUNDS", format!("to {} amount {} balance {}",
                    self.topology.names[*destination], amount, event.balance)),
                EventKind::Send(m) => {
                    let message = &self.messages[*m];
                    ("SEND", format!("m{} to {} tag {}{}", m + 1,
                        self.topology.names[message.destination.unwrap()], message.tag, amount_part(message, event.balance)))
                }
                EventKind::Broadcast(m) => ("BCAST", format!("m{} tag {}", m + 1, self.messages[*m].tag)),
                EventKind::Receive(c) => {
                    let copy = &self.copies[*c];
                    let m = &self.messages[copy.message];
                    ("RECV", format!("m{} from {} tag {}{}", copy.message + 1,
                        self.topology.names[copy.source], m.tag, amount_part(m, event.balance)))
                }
            };
            lines.push(format!("{} t={} {} {} {} L={} V={}", i + 1, event.time, self.name(i),
                kind, details, event.lamport, clocks::text(&event.vector)));
        }
        let delivered = self.copies.iter().filter(|c| c.received.is_some()).count();
        lines.push(format!("SUMMARY events {} messages {} copies {} delivered {} undelivered {} draws {}",
            self.events.len(), self.messages.len(), self.copies.len(), delivered, self.copies.len() - delivered, self.rng.draws));
        for (p, s) in self.states.iter().enumerate() {
            lines.push(format!("FINAL {} events {} L={} V={} B={} balance {} in {} out {} refused {} min {}",
                self.topology.names[p], s.events.len(), s.lamport, clocks::text(&s.vector), clocks::text(&s.broadcast),
                s.balance, s.received, s.sent, s.counts[1], s.minimum));
        }
        for (p, s) in self.states.iter().enumerate() {
            lines.push(format!("COUNTS {} local {} nofunds {} send {} bcast {} recv {}", self.topology.names[p],
                s.counts[0], s.counts[1], s.counts[2], s.counts[3], s.counts[4]));
        }
        lines
    }

    fn deliveries(&self) -> Vec<String> {
        let mut lines = Vec::new();
        let lists = self.broadcast_lists();
        for (p, state) in self.states.iter().enumerate() {
            lines.push(format!("PROCESS {}", self.topology.names[p]));
            let mut modes = [0; 4];
            let (mut waiting, mut max_wait) = (0, 0);
            for (i, &c) in state.delivered.iter().enumerate() {
                let copy = &self.copies[c];
                let packet = &self.packets[copy.packet];
                let time = self.events[copy.received.unwrap()].time;
                let wait = time - packet.arrival;
                waiting += wait;
                max_wait = max_wait.max(wait);
                modes[usize::from(copy.fifo) + 2 * usize::from(copy.causal)] += 1;
                let mode = match (copy.fifo, copy.causal) {
                    (false, false) => "direct".to_owned(), (true, false) => "fifo".to_owned(),
                    (false, true) => format!("causal {}", self.names(&copy.missing)),
                    (true, true) => format!("fifo+causal {}", self.names(&copy.missing)),
                };
                lines.push(format!("{} {} arrived {} delivered {} wait {} {}", i + 1,
                    self.delivery_prefix(c), packet.arrival, time, wait, mode));
            }
            for (c, copy) in self.copies.iter().enumerate().filter(|(_, c)| c.destination == p && c.received.is_none()) {
                let packet = &self.packets[copy.packet];
                if packet.arrival <= self.end {
                    let place = if state.hold.contains(&c) { format!("causal {}", self.names(&copy.missing)) }
                        else { "fifo".to_owned() };
                    lines.push(format!("HELD {} arrived {} {}", self.delivery_prefix(c), packet.arrival, place));
                }
            }
            for (c, copy) in self.copies.iter().enumerate().filter(|(_, c)| c.destination == p) {
                let packet = &self.packets[copy.packet];
                if packet.arrival > self.end {
                    lines.push(format!("TRANSIT {} arrival {}", self.delivery_prefix(c), packet.arrival));
                }
            }
            lines.push(format!("TOTAL delivered {} direct {} fifo {} causal {} both {} wait {} max_wait {} max_held {}",
                state.delivered.len(), modes[0], modes[1], modes[2], modes[3], waiting, max_wait, state.max_held));
            lines.push(format!("BCASTS {}", message_list(&lists[p], "none")));
        }
        let n = self.states.len();
        for source in 0..n {
            for destination in 0..n {
                if source == destination { continue; }
                let c = self.topology.channels[source*n+destination].as_ref().unwrap();
                let s = &self.channels[source*n+destination];
                let delay = if c.a == c.b { c.a.to_string() } else { format!("{}-{}", c.a, c.b) };
                lines.push(format!("CHANNEL {}->{} {} {} messages {} markers {} buffered {} max_delay {} entries {}",
                    self.topology.names[source], self.topology.names[destination], if c.fifo { "FIFO" } else { "NONFIFO" },
                    delay, s.copies, s.markers, s.buffered, s.max_delay, s.entries));
            }
        }
        let tags: BTreeSet<_> = self.messages.iter().map(|m| m.tag.as_str()).collect();
        for tag in tags {
            let mut count = 0;
            let mut delivered = 0;
            let (mut latency, mut maximum) = (0, 0);
            for c in &self.copies {
                let m = &self.messages[c.message];
                if m.tag != tag { continue; }
                count += 1;
                if let Some(e) = c.received {
                    delivered += 1;
                    let time = self.events[e].time - self.events[m.event].time;
                    latency += time;
                    maximum = maximum.max(time);
                }
            }
            lines.push(format!("TAG {} copies {} delivered {} latency {} max {}", tag, count, delivered, latency, maximum));
        }
        let broadcasts: Vec<_> = self.messages.iter().enumerate().filter(|(_, m)| m.broadcast).map(|(i, _)| i).collect();
        for &i in &broadcasts {
            let m = &self.messages[i];
            let stable = if m.copies.iter().all(|&c| self.copies[c].received.is_some()) {
                m.copies.iter().map(|&c| self.events[self.copies[c].received.unwrap()].time).max().unwrap().to_string()
            } else { "none".to_owned() };
            lines.push(format!("STABLE m{} {} tag {} sent {} stable {}", i+1, self.topology.names[m.source],
                m.tag, self.events[m.event].time, stable));
        }
        let mut disagreements = 0;
        for (a, &first) in broadcasts.iter().enumerate() {
            for &second in &broadcasts[a+1..] {
                let (mut earlier, mut later) = (Vec::new(), Vec::new());
                for (p, list) in lists.iter().enumerate() {
                    if let (Some(x), Some(y)) = (list.iter().position(|&m| m == first), list.iter().position(|&m| m == second)) {
                        if x < y { earlier.push(p); } else { later.push(p); }
                    }
                }
                if !earlier.is_empty() && !later.is_empty() {
                    disagreements += 1;
                    lines.push(format!("DISAGREE m{} m{} {} {}", first+1, second+1, self.names(&earlier), self.names(&later)));
                }
            }
        }
        lines.push(format!("DISAGREEMENTS {}", disagreements));
        lines
    }

    fn delivery_prefix(&self, copy: usize) -> String {
        let c = &self.copies[copy];
        let m = &self.messages[c.message];
        format!("m{} from {} {} tag {} sent {}", c.message+1, self.topology.names[c.source],
            if m.broadcast { "BCAST" } else { "P2P" }, m.tag, self.events[m.event].time)
    }

    fn snapshot_money(&self, s: &snapshot::Snapshot) -> (i64, i64) {
        let balances = s.records.iter().map(|r| r.as_ref().unwrap().balance).sum();
        let amounts = s.channels.iter().flat_map(|c| &c.copies).map(|&c| self.messages[self.copies[c].message].amount).sum();
        (balances, amounts)
    }

    fn snapshot_lines(&self, raw: &Self) -> Vec<String> {
        let mut lines = Vec::new();
        let n = self.states.len();
        for s in &self.snapshots {
            lines.push(format!("SNAPSHOT {} started {} completed {}", s.name, s.started, s.completed.unwrap()));
            let mut pending = Vec::new();
            let mut channel_copies = Vec::new();
            for (p, r) in s.records.iter().enumerate() {
                let r = r.as_ref().unwrap();
                pending.extend_from_slice(&r.pending);
                let ids: Vec<_> = r.pending.iter().map(|&c| self.copies[c].message).collect();
                lines.push(format!("RECORD {} t={} {} balance {} L={} V={} pending {}", self.topology.names[p],
                    r.time, r.reason, r.balance, r.lamport, clocks::text(&r.vector), message_list(&ids, "none")));
            }
            for source in 0..n {
                for destination in 0..n {
                    if source == destination { continue; }
                    let c = &s.channels[source*n+destination];
                    channel_copies.extend_from_slice(&c.copies);
                    let state = if c.copies.is_empty() { "empty".to_owned() } else {
                        c.copies.iter().map(|&c| {
                            let m = &self.messages[self.copies[c].message];
                            if m.amount == 0 { format!("m{}", self.copies[c].message+1) }
                            else { format!("m{}:{}", self.copies[c].message+1, m.amount) }
                        }).collect::<Vec<_>>().join(" ")
                    };
                    lines.push(format!("CHANNEL {}->{} marker {} {} state {}", self.topology.names[source],
                        self.topology.names[destination], c.dispatched.unwrap(), c.accepted.unwrap(), state));
                }
            }
            for &(p, time) in &s.ignored { lines.push(format!("IGNORED {} t={}", self.topology.names[p], time)); }
            let cut = s.cut();
            let evaluated = self.cut(&cut);
            let vector = s.records.iter().all(|r| clocks::le(&r.as_ref().unwrap().vector, &cut));
            lines.push(format!("CUT {} consistent {} vector {}", clocks::text(&cut), self.verdict(&evaluated), yes(vector)));
            let channels = channel_copies.len();
            let pending_count = pending.len();
            channel_copies.extend(pending);
            channel_copies.sort_unstable();
            lines.push(format!("TRANSIT channels {} pending {} cut {} match {}", channels, pending_count,
                evaluated.transit.len(), yes(channel_copies == evaluated.transit)));
            let (balances, amounts) = self.snapshot_money(s);
            lines.push(format!("MONEY balances {} channels {} total {} initial {} conserved {}", balances, amounts,
                balances+amounts, self.initial(), yes(balances+amounts == self.initial())));
        }
        for s in &raw.snapshots {
            let cut = s.cut();
            let evaluated = raw.cut(&cut);
            let (balances, amounts) = raw.snapshot_money(s);
            lines.push(format!("RAW {} completed {} cut {} consistent {} money {} conserved {}", s.name,
                s.completed.unwrap(), clocks::text(&cut), raw.verdict(&evaluated), balances+amounts,
                yes(balances+amounts == raw.initial())));
        }
        lines
    }

    fn analysis_lines(&self, raw: &Self, params: &Params) -> Vec<String> {
        let mut lines = Vec::new();
        let n = self.states.len();
        let graph = analysis::graph(&self.states, &self.events, &self.messages, &self.copies);
        let lookup: BTreeMap<_, _> = (0..self.events.len()).map(|i| (self.name(i), i)).collect();
        for (a, b) in &params.compare {
            let (i, j) = (lookup[a], lookup[b]);
            let (e, f) = (&self.events[i], &self.events[j]);
            let relation = clocks::relation(&e.vector, &f.vector);
            let path = analysis::path(&graph, i, j);
            let (graph_relation, path) = if path.is_some() { ("->", path) }
                else if let Some(p) = analysis::path(&graph, j, i) { ("<-", Some(p)) } else { ("||", None) };
            lines.push(format!("COMPARE {} {} {} L={},{} graph {} agree {}", a, relation, b, e.lamport,
                f.lamport, graph_relation, yes(relation == graph_relation)));
            if let Some(path) = path {
                let messages = path.windows(2).filter(|p| self.events[p[0]].process != self.events[p[1]].process).count();
                lines.push(format!("PATH length {} messages {} {}", path.len(), messages, self.ranges(&path)));
            }
            for event in [i, j] {
                let e = &self.events[event];
                let future: Vec<_> = self.states.iter().map(|s| s.events.iter().filter(|&&f|
                    self.events[f].vector[e.process] < e.ordinal).count()).collect();
                lines.push(format!("WINDOW {} past {} future {}", self.name(event), clocks::text(&e.vector), clocks::text(&future)));
            }
        }
        let c = analysis::concurrency(&self.events, n);
        lines.push(format!("CONCURRENCY events {} pairs {} ordered {} concurrent {} same_lamport {} inversions {}",
            self.events.len(), self.events.len() * self.events.len().saturating_sub(1) / 2, c.ordered, c.concurrent, c.equal, c.inversions));
        for i in 0..n { for j in i+1..n {
            lines.push(format!("PAIR {} {} {}", self.topology.names[i], self.topology.names[j], c.pairs[i][j]));
        } }
        let chain = self.longest();
        lines.push(format!("CHAIN length {} {}", chain.len(), self.ranges(&chain)));
        let order = analysis::ordering(&self.states, &self.events, &self.messages, &self.copies);
        for &(p, a, b) in &order.races {
            lines.push(format!("RACE {} m{} {} m{} {}", self.topology.names[p], self.copies[a].message+1,
                self.topology.names[self.copies[a].source], self.copies[b].message+1, self.topology.names[self.copies[b].source]));
        }
        lines.push(format!("RACES {}", order.races.len()));
        for &(p, a, b) in &order.violations {
            lines.push(format!("VIOLATION {} m{} {} overtook m{} {}", self.topology.names[p], self.copies[a].message+1,
                self.topology.names[self.copies[a].source], self.copies[b].message+1, self.topology.names[self.copies[b].source]));
        }
        lines.push(format!("VIOLATIONS causal {} fifo {}", order.violations.len(), order.fifo));
        let order = analysis::ordering(&raw.states, &raw.events, &raw.messages, &raw.copies);
        lines.push(format!("RAW events {} delivered {} causal {} fifo {}", raw.events.len(),
            raw.copies.iter().filter(|c| c.received.is_some()).count(), order.violations.len(), order.fifo));
        for cut in &params.cuts {
            let c = self.cut(cut);
            let status = if c.orphans.is_empty() { "consistent".to_owned() } else {
                format!("inconsistent orphans {}", c.orphans.iter().map(|&c| self.copy_name(c)).collect::<Vec<_>>().join(" ")) };
            lines.push(format!("CUT {} {} transit {} money {} initial {}", clocks::text(cut), status,
                c.transit.len(), c.money, self.initial()));
        }
        let e = analysis::enumerate(params.count_time, &params.predicates, self.programs, &self.states, &self.events);
        lines.push(format!("CUTCOUNT t={} events {} product {} consistent {}", params.count_time,
            clocks::text(&e.limits), e.product, e.consistent));
        lines.push(format!("LEVELS {}", e.levels.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")));
        for (i, &(count, definitely)) in e.predicates.iter().enumerate() {
            lines.push(format!("PREDICATE transit>={} cuts {} possibly {} definitely {}", params.predicates[i],
                count, yes(count > 0), yes(definitely)));
        }
        lines
    }

    fn diagram(&self) -> Vec<String> {
        let n = self.states.len();
        let header = |label: char| {
            let mut line = format!("    {} ", label).into_bytes();
            for (p, name) in self.topology.names.iter().enumerate() { write_at(&mut line, 8*p+6, name); }
            String::from_utf8(line).unwrap().trim_end().to_owned()
        };
        let draw = |event: Option<usize>, snapshot: Option<(usize, usize)>, lamport: bool| {
            let (p, value) = if let Some(e) = event {
                (self.events[e].process, if lamport { self.events[e].lamport as i64 } else { self.events[e].time })
            } else {
                let (s, p) = snapshot.unwrap();
                (p, self.snapshots[s].records[p].as_ref().unwrap().time)
            };
            let mut line = vec![b' '; 8*(n-1)+7];
            write_at(&mut line, 0, &format!("{:5}", value));
            for q in 0..n { line[8*q+6] = b'|'; }
            let own = 8*p+6;
            if let Some(e) = event {
                match &self.events[e].kind {
                    EventKind::Local(_) => line[own] = b'*',
                    EventKind::NoFunds { .. } => line[own] = b'x',
                    EventKind::Send(m) | EventKind::Broadcast(m) => {
                        line[own] = if matches!(&self.events[e].kind, EventKind::Send(_)) { b'S' } else { b'B' };
                        write_at(&mut line, own+1, &format!("m{}", m+1));
                    }
                    EventKind::Receive(c) => {
                        let copy = &self.copies[*c];
                        let source = 8*copy.source+6;
                        let (a, z) = (source.min(own), source.max(own));
                        line[own] = b'R';
                        for k in a+1..z { line[k] = if k >= 6 && (k-6)%8 == 0 { b'+' } else { b'-' }; }
                        if source < own { line[z-1] = b'>'; } else { line[a+1] = b'<'; }
                        write_at(&mut line, a+2, &format!("m{}", copy.message+1));
                    }
                }
            } else {
                line[own] = b'#';
                write_at(&mut line, own+1, &self.snapshots[snapshot.unwrap().0].name);
            }
            String::from_utf8(line).unwrap().trim_end().to_owned()
        };
        let mut lines = vec![header('t')];
        for occurrence in &self.occurrences {
            lines.push(match *occurrence {
                Occurrence::Event(e) => draw(Some(e), None, false),
                Occurrence::Snapshot(s, p) => draw(None, Some((s, p)), false),
            });
        }
        lines.push(header('L'));
        let mut events: Vec<_> = (0..self.events.len()).collect();
        events.sort_by_key(|&e| (self.events[e].lamport, self.events[e].process));
        for e in events { lines.push(draw(Some(e), None, true)); }
        lines
    }
}

fn yes(value: bool) -> &'static str { if value { "yes" } else { "no" } }

fn amount_part(message: &Message, balance: i64) -> String {
    if message.tag == "transfer" { format!(" amount {} balance {}", message.amount, balance) } else { String::new() }
}

fn message_list(messages: &[usize], empty: &str) -> String {
    if messages.is_empty() { empty.to_owned() }
    else { messages.iter().map(|m| format!("m{}", m+1)).collect::<Vec<_>>().join(" ") }
}

fn write_at(line: &mut Vec<u8>, position: usize, text: &str) {
    if line.len() < position + text.len() { line.resize(position + text.len(), b' '); }
    line[position..position+text.len()].copy_from_slice(text.as_bytes());
}

fn main() {
    let topology = Topology::read();
    let programs = processes::read(&topology.names);
    let params = Params::read();
    let simulation = Simulation::run(&topology, &programs, &params, false);
    let raw = Simulation::run(&topology, &programs, &params, true);
    fs::create_dir_all("output").unwrap();
    for (file, lines) in [
        ("trace.txt", simulation.trace()), ("deliveries.txt", simulation.deliveries()),
        ("snapshots.txt", simulation.snapshot_lines(&raw)),
        ("analysis.txt", simulation.analysis_lines(&raw, &params)), ("diagram.txt", simulation.diagram()),
    ] { fs::write(format!("output/{}", file), lines.join("\n") + "\n").unwrap(); }
}
