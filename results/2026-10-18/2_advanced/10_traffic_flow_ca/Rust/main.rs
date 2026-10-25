mod minstd;
mod road;
mod vehicles;
mod signals;
mod stats;

use std::{collections::{BTreeMap, BTreeSet, VecDeque}, fs};
use minstd::{select, Minstd};
use road::{BusStop, Change, Incident, Segment, Turn};
use vehicles::{random_slowdown, Vehicle, VehicleClass};
use signals::Junction;
use stats::{dec, frac, gcd, histogram_lines, percentile};

fn time_text(step: usize) -> String { format!("{step:04}") }
fn flag_text(value: bool) -> &'static str { if value { "Y" } else { "N" } }
#[derive(Clone, Copy)]
struct Rational { numerator: i64, denominator: i64 }
impl Rational {
    fn new(numerator: i64, denominator: i64) -> Self { let divisor = gcd(numerator, denominator); Self { numerator: numerator / divisor, denominator: denominator / divisor } }
    fn multiply(self, n: i64, d: i64) -> Self { Self::new(self.numerator * n, self.denominator * d) }
    fn add(self, other: Self) -> Self { Self::new(self.numerator * other.denominator + other.numerator * self.denominator, self.denominator * other.denominator) }
    fn text(self) -> String { format!("{}/{}", self.numerator, self.denominator) }
}
struct Source { node: String, rates: Vec<(i64, usize)>, segment: usize, queue: VecDeque<usize>, queue_start: usize, queue_max: usize }
impl Source { fn rate(&self, step: usize) -> i64 { self.rates.iter().find(|(_, end)| step <= *end).map_or(0, |(rate, _)| *rate) } }
struct Detector { name: String, segment: usize, cell: usize, width: usize }
struct Diagram { segment: usize, lane: usize, start: usize, end: usize, lines: Vec<String> }
struct Ring { number: usize, length: usize, vmax: usize, warmup: usize, measure: usize, seed: i64, counts: Vec<usize> }
struct Interval { arrivals: i64, insertions: i64, exits: i64, vehicle_steps: i64, speed_sum: i64, passing: Vec<i64>, occupancy: Vec<i64>, occupancy_speed: Vec<i64> }
impl Interval { fn new(count: usize) -> Self { Self { arrivals: 0, insertions: 0, exits: 0, vehicle_steps: 0, speed_sum: 0, passing: vec![0; count], occupancy: vec![0; count], occupancy_speed: vec![0; count] } } }
struct Move { vehicle: usize, segment: usize, cell: usize, speed: usize }
fn run_ring(ring: &Ring, count: usize, dawdle: i64, stopped: i64) -> i64 {
    let mut rng = Minstd::new(ring.seed); let mut positions: Vec<_> = (0..count).map(|j| j * ring.length / count).collect(); let mut speeds = vec![0usize; count]; let mut total = 0;
    for step in 1..=ring.warmup + ring.measure {
        let mut order: Vec<_> = (0..count).collect(); order.sort_by_key(|&j| std::cmp::Reverse(positions[j])); let mut next = vec![0; count];
        for (rank, &j) in order.iter().enumerate() {
            let ahead = order[if rank == 0 { count - 1 } else { rank - 1 }]; let gap = (positions[ahead] as i64 - positions[j] as i64 - 1).rem_euclid(ring.length as i64) as usize;
            next[j] = random_slowdown((speeds[j] + 1).min(ring.vmax).min(gap), speeds[j], rng.draw(), dawdle, stopped);
        }
        for j in 0..count { positions[j] = (positions[j] + next[j]) % ring.length; } speeds = next;
        if step > ring.warmup { total += speeds.iter().map(|&speed| speed as i64).sum::<i64>(); }
    } total
}
struct Simulation {
    segments: Vec<Segment>, by_id: BTreeMap<String, usize>, junctions: Vec<Junction>, incidents: Vec<Incident>, stops: Vec<BusStop>, classes: Vec<VehicleClass>, sources: Vec<Source>, sinks: Vec<String>,
    seed: i64, steps: usize, dawdle: i64, dawdle_stopped: i64, interval_length: usize, bin_width: i64,
    detectors: Vec<Detector>, diagrams: Vec<Diagram>, track_numbers: Vec<usize>, rings: Vec<Ring>, rng: Minstd, vehicles: Vec<Vehicle>, intervals: Vec<Interval>, events: Vec<String>, tracks: BTreeMap<usize, Vec<String>>,
}
impl Simulation {
    fn new() -> Self {
        let mut sim = Self { segments: Vec::new(), by_id: BTreeMap::new(), junctions: Vec::new(), incidents: Vec::new(), stops: Vec::new(), classes: Vec::new(), sources: Vec::new(), sinks: Vec::new(), seed: 1, steps: 0, dawdle: 0, dawdle_stopped: 0, interval_length: 1, bin_width: 1, detectors: Vec::new(), diagrams: Vec::new(), track_numbers: Vec::new(), rings: Vec::new(), rng: Minstd::new(1), vehicles: Vec::new(), intervals: Vec::new(), events: Vec::new(), tracks: BTreeMap::new() };
        for file in ["network.txt", "demand.txt", "params.txt"] {
            let text = fs::read_to_string(format!("input/{file}")).unwrap();
            for line in text.lines() {
                let tokens: Vec<_> = line.split(' ').collect(); let p = &tokens[1..]; let n = |j: usize| p[j].parse::<usize>().unwrap(); let integer = |j: usize| p[j].parse::<i64>().unwrap();
                match tokens[0] {
                    "SEGMENT" => { sim.by_id.insert(p[0].to_owned(), sim.segments.len()); sim.segments.push(Segment::new(p[0].to_owned(), p[1].to_owned(), p[2].to_owned(), n(3), n(4), n(5))); }
                    "JUNCTION" => { let index = sim.junctions.len(); let mut junction = Junction::new(p[0].to_owned(), n(1), &p[2..]); for (j, s) in sim.segments.iter_mut().enumerate() { if s.end == p[0] { s.junction = Some(index); junction.incoming.push(j); } } sim.junctions.push(junction); }
                    "INCIDENT" => sim.incidents.push(Incident { segment: sim.by_id[p[0]], lane: n(1), cell: n(2), start: n(3), end: n(4), state: "planned", active_start: None, active_end: None }),
                    "STOP" => { let segment = sim.by_id[p[0]]; sim.segments[segment].stop = Some(sim.stops.len()); sim.stops.push(BusStop { segment, cell: n(1), dwell: n(2), buses: 0 }); }
                    "CLASS" => sim.classes.push(VehicleClass { name: p[0].to_owned(), vmax: n(1), weight: integer(2), overtakes: p[3] == "Y", stops: p[4] == "Y" }),
                    "SOURCE" => { let rates = p[1..].iter().map(|period| { let (rate, end) = period.split_once(':').unwrap(); (rate.parse().unwrap(), end.parse().unwrap()) }).collect(); let segment = sim.segments.iter().position(|s| s.start == p[0]).unwrap(); sim.sources.push(Source { node: p[0].to_owned(), rates, segment, queue: VecDeque::new(), queue_start: 0, queue_max: 0 }); }
                    "SINK" => sim.sinks.push(p[0].to_owned()),
                    "TURN" => { let from = sim.by_id[p[0]]; let target = sim.by_id[p[1]]; sim.segments[from].turns.push(Turn { target, weight: integer(2), vehicles: 0 }); }
                    "seed" => sim.seed = integer(0), "steps" => sim.steps = n(0), "dawdle" => { sim.dawdle = integer(0); sim.dawdle_stopped = integer(1); }
                    "interval" => sim.interval_length = n(0), "bin" => sim.bin_width = integer(0),
                    "detector" => sim.detectors.push(Detector { name: p[0].to_owned(), segment: sim.by_id[p[1]], cell: n(2), width: n(3) }),
                    "diagram" => sim.diagrams.push(Diagram { segment: sim.by_id[p[0]], lane: n(1), start: n(2), end: n(3), lines: Vec::new() }),
                    "track" => { sim.track_numbers = p.iter().map(|number| number.parse().unwrap()).collect(); for &number in &sim.track_numbers { sim.tracks.insert(number, Vec::new()); } }
                    "ring" => sim.rings.push(Ring { number: sim.rings.len() + 1, length: n(0), vmax: n(1), warmup: n(2), measure: n(3), seed: integer(4), counts: p[5..].iter().map(|count| count.parse().unwrap()).collect() }),
                    _ => unreachable!(),
                }
            }
        } sim.rng = Minstd::new(sim.seed); sim
    }
    fn record(&mut self, step: usize, event: String) { self.events.push(format!("{} {event}", time_text(step))); }
    fn green(&self, segment: usize, step: usize) -> bool { let s = &self.segments[segment]; self.junctions[s.junction.unwrap()].green(&s.id, step) }
    fn heading(&self, vehicle: usize) -> bool { self.vehicles[vehicle].heading_for_stop(&self.classes, &self.segments, &self.stops) }
    fn vehicles_on(&self, segment: usize) -> Vec<usize> { let s = &self.segments[segment]; (1..=s.lanes).flat_map(|lane| s.vehicle_numbers(lane)).collect() }
    fn enter(&mut self, vehicle: usize, segment: usize) {
        self.vehicles[vehicle].route.push(segment); self.segments[segment].entered += 1;
        let turn = if self.segments[segment].junction.is_some() { let weights: Vec<_> = self.segments[segment].turns.iter().map(|turn| turn.weight).collect(); Some(select(&weights, self.rng.draw())) } else { None }; self.vehicles[vehicle].turn = turn;
    }
    fn update_incidents(&mut self, step: usize) {
        for j in 0..self.incidents.len() { if let Some(event) = self.incidents[j].update(&mut self.segments, step) { let incident = &self.incidents[j]; let text = format!("{event} {} lane {} cell {}", self.segments[incident.segment].id, incident.lane, incident.cell); self.record(step, text); } }
    }
    fn arrive(&mut self, step: usize) {
        let weights: Vec<_> = self.classes.iter().map(|class| class.weight).collect();
        for source in 0..self.sources.len() { if self.rng.draw() % 1000 < self.sources[source].rate(step) { let class = select(&weights, self.rng.draw()); let index = self.vehicles.len(); self.vehicles.push(Vehicle::new(index + 1, class, source, step)); self.sources[source].queue.push_back(index); self.intervals.last_mut().unwrap().arrivals += 1; } }
    }
    fn entry_lane(&self, segment: usize) -> Option<usize> {
        let s = &self.segments[segment]; let mut best = None; let mut first = 0;
        for lane in 1..=s.lanes { if s.empty(lane, 0) && (best.is_none() || s.first(lane) > first) { best = Some(lane); first = s.first(lane); } } best
    }
    fn insert(&mut self, step: usize) {
        for source in 0..self.sources.len() {
            let segment = self.sources[source].segment;
            while let Some(&vehicle) = self.sources[source].queue.front() { let Some(lane) = self.entry_lane(segment) else { break; }; self.sources[source].queue.pop_front(); self.vehicles[vehicle].place(&mut self.segments, segment, lane, 0); self.vehicles[vehicle].inserted = Some(step); self.enter(vehicle, segment); self.intervals.last_mut().unwrap().insertions += 1; }
            let source = &mut self.sources[source];
            if !source.queue.is_empty() && source.queue_start == 0 { source.queue_start = step; source.queue_max = 0; }
            let event = if source.queue_start != 0 { source.queue_max = source.queue_max.max(source.queue.len()); if source.queue.is_empty() { let text = format!("QUEUE {} from {} max {}", source.node, source.queue_start, source.queue_max); source.queue_start = 0; Some(text) } else { None } } else { None };
            if let Some(event) = event { self.record(step, event); }
        }
    }
    fn desired_lane(&self, vehicle: usize) -> (usize, Option<Change>) {
        let v = &self.vehicles[vehicle]; let s = &self.segments[v.segment.unwrap()]; let lane = v.lane; let cell = v.cell; let top = v.max_speed(&self.classes, &self.segments);
        let here = s.free(lane, cell as isize, top + 1); let want = (v.speed + 1).min(top); let ahead = cell + here + 1;
        if here < top + 1 && ahead < s.length && s.obstacle(lane, ahead) {
            for target in [lane + 1, lane - 1] { if target >= 1 && target <= s.lanes && s.free(target, cell as isize, top + 1) > here && s.safe(target, cell) { return (target, Some(Change::Avoidance)); } }
        }
        if self.heading(vehicle) { return if lane >= 2 && s.safe(lane - 1, cell) { (lane - 1, Some(Change::Return)) } else { (lane, None) }; }
        if self.classes[v.class].overtakes && lane < s.lanes && here < want && s.free(lane + 1, cell as isize, top + 1) > here && s.safe(lane + 1, cell) { return (lane + 1, Some(Change::Overtaking)); }
        if lane >= 2 && s.free(lane - 1, cell as isize, top + 1) > want && s.safe(lane - 1, cell) { return (lane - 1, Some(Change::Return)); } (lane, None)
    }
    fn change_lanes(&mut self) {
        let mut changes = Vec::new();
        for segment in 0..self.segments.len() {
            let s = &self.segments[segment]; if s.lanes < 2 { continue; } let mut reserved = BTreeSet::new();
            for lane in 1..=s.lanes { for vehicle in s.vehicle_numbers(lane) { let v = &self.vehicles[vehicle]; if v.dwell > 0 { continue; } let (target, kind) = self.desired_lane(vehicle); if target != lane && reserved.insert((target, v.cell)) { changes.push((vehicle, target, kind.unwrap())); } } }
        }
        for (vehicle, target, kind) in changes { let segment = self.vehicles[vehicle].segment.unwrap(); let cell = self.vehicles[vehicle].cell; self.vehicles[vehicle].place(&mut self.segments, segment, target, cell); self.vehicles[vehicle].lane_changes += 1; self.segments[segment].changes[kind as usize] += 1; }
    }
    fn processing_order(&self) -> Vec<Move> {
        let mut moves = Vec::new(); for (segment, s) in self.segments.iter().enumerate() { for lane in 1..=s.lanes { for vehicle in s.vehicle_numbers(lane).into_iter().rev() { moves.push(Move { vehicle, segment, cell: self.vehicles[vehicle].cell, speed: 0 }); } } } moves
    }
    fn determine_speed(&mut self, vehicle: usize, step: usize) -> usize {
        let v = &self.vehicles[vehicle]; let segment = v.segment.unwrap(); let s = &self.segments[segment]; let accelerated = (v.speed + 1).min(v.max_speed(&self.classes, &self.segments)); let mut gap = s.free(v.lane, v.cell as isize, accelerated);
        if gap < accelerated && v.cell + gap == s.length - 1 { if s.junction.is_none() { gap = accelerated; } else if self.green(segment, step) { let target = &self.segments[s.turns[v.turn.unwrap()].target]; gap += target.free(v.lane.min(target.lanes), -1, accelerated - gap); } }
        if self.heading(vehicle) { gap = gap.min(self.stops[s.stop.unwrap()].cell - v.cell); }
        let mut speed = random_slowdown(accelerated.min(gap), v.speed, self.rng.draw(), self.dawdle, self.dawdle_stopped);
        if self.vehicles[vehicle].dwell > 0 { speed = 0; self.vehicles[vehicle].dwell -= 1; } speed
    }
    fn move_vehicles(&mut self, moves: &[Move], step: usize) -> Vec<usize> {
        let mut passing = Vec::new();
        for (j, movement) in moves.iter().enumerate() { let vehicle = movement.vehicle; let segment = movement.segment; let lane = self.vehicles[vehicle].lane;
            if movement.cell + movement.speed < self.segments[segment].length { self.vehicles[vehicle].place(&mut self.segments, segment, lane, movement.cell + movement.speed); }
            else if self.segments[segment].junction.is_none() { self.vehicles[vehicle].leave(&mut self.segments); self.vehicles[vehicle].exited = Some(step); self.vehicles[vehicle].sink = Some(self.segments[segment].end.clone()); self.intervals.last_mut().unwrap().exits += 1; }
            else { passing.push(j); }
        } passing
    }
    fn pass_junctions(&mut self, moves: &mut [Move], passing: &[usize]) {
        for &j in passing {
            let movement = &mut moves[j]; let vehicle = movement.vehicle; let segment = movement.segment; let turn = self.vehicles[vehicle].turn.unwrap(); let target = self.segments[segment].turns[turn].target;
            let lane = self.vehicles[vehicle].lane.min(self.segments[target].lanes); let overshoot = movement.cell + movement.speed - self.segments[segment].length; let cell = (overshoot as isize).min(self.segments[target].first(lane) as isize - 1);
            if cell < overshoot as isize { self.segments[segment].blocked += 1; }
            if cell >= 0 { self.vehicles[vehicle].place(&mut self.segments, target, lane, cell as usize); movement.speed = self.segments[segment].length - movement.cell + cell as usize; self.segments[segment].passed += 1; self.segments[segment].turns[turn].vehicles += 1; self.enter(vehicle, target); }
            else { let lane = self.vehicles[vehicle].lane; let cell = self.segments[segment].length - 1; self.vehicles[vehicle].place(&mut self.segments, segment, lane, cell); movement.speed = cell - movement.cell; }
        }
    }
    fn track_line(&self, vehicle: usize, step: usize) -> String {
        let v = &self.vehicles[vehicle]; match v.segment { None => format!("{} EXIT {}", time_text(step), v.speed), Some(segment) => format!("{} {} {} {} {}", time_text(step), self.segments[segment].id, v.lane, v.cell, v.speed) }
    }
    fn aggregate_vehicle(&mut self, movement: &Move, step: usize) {
        let vehicle = movement.vehicle; let v = &mut self.vehicles[vehicle]; v.steps += 1; v.distance += movement.speed as i64;
        if movement.speed == 0 { v.stopped_steps += 1; if v.speed > 0 { v.stop_count += 1; } } v.speed = movement.speed;
        let interval = self.intervals.last_mut().unwrap(); interval.vehicle_steps += 1; interval.speed_sum += movement.speed as i64;
        if self.heading(vehicle) && self.vehicles[vehicle].lane == 1 {
            let segment = self.vehicles[vehicle].segment.unwrap(); let stop = self.segments[segment].stop.unwrap();
            if self.vehicles[vehicle].cell == self.stops[stop].cell { self.vehicles[vehicle].completed_stops.insert(segment); self.vehicles[vehicle].dwell = self.stops[stop].dwell; self.stops[stop].buses += 1; let event = format!("BUS_STOP {} {} cell {}", vehicle + 1, self.segments[segment].id, self.stops[stop].cell); self.record(step, event); }
        }
        let number = vehicle + 1; if self.tracks.contains_key(&number) { let line = self.track_line(vehicle, step); self.tracks.get_mut(&number).unwrap().push(line); }
        let v = &self.vehicles[vehicle];
        for (j, detector) in self.detectors.iter().enumerate() { if movement.segment == detector.segment && movement.cell < detector.cell && (v.segment != Some(detector.segment) || v.cell >= detector.cell) { self.intervals.last_mut().unwrap().passing[j] += 1; } }
    }
    fn signal_text(&self, segment: usize, step: usize) -> &'static str { if self.segments[segment].junction.is_none() { "E" } else if self.green(segment, step) { "G" } else { "R" } }
    fn aggregate_state(&mut self, step: usize) {
        for j in 0..self.detectors.len() {
            let detector = &self.detectors[j]; let mut occupancy = 0; let mut speed = 0;
            for vehicle in self.vehicles_on(detector.segment) { let v = &self.vehicles[vehicle]; if detector.cell <= v.cell && v.cell < detector.cell + detector.width { occupancy += 1; speed += v.speed as i64; } }
            let interval = self.intervals.last_mut().unwrap(); interval.occupancy[j] += occupancy; interval.occupancy_speed[j] += speed;
        }
        for segment in 0..self.segments.len() {
            let present = self.vehicles_on(segment); let speed: i64 = present.iter().map(|&v| self.vehicles[v].speed as i64).sum(); let queued = present.iter().filter(|&&v| self.vehicles[v].speed == 0).count();
            let junction = self.segments[segment].junction.is_some(); let green = junction && self.green(segment, step); let failure = junction && step < self.steps && queued > 0 && green && !self.green(segment, step + 1);
            let s = &mut self.segments[segment]; s.vehicle_sum += present.len() as i64; s.speed_sum += speed; s.max_vehicles = s.max_vehicles.max(present.len());
            if junction { s.green_steps += green as i64; s.queue_sum += queued as i64; s.max_queue = s.max_queue.max(queued); s.failures += failure as i64; }
        }
        for j in 0..self.diagrams.len() { let diagram = &self.diagrams[j]; if diagram.start <= step && step <= diagram.end { let line = format!("{} {} {}", time_text(step), self.segments[diagram.segment].cells_text(diagram.lane, &self.vehicles), self.signal_text(diagram.segment, step)); self.diagrams[j].lines.push(line); } }
    }
    fn run(&mut self) {
        for step in 1..=self.steps {
            self.update_incidents(step); if (step - 1) % self.interval_length == 0 { self.intervals.push(Interval::new(self.detectors.len())); }
            self.arrive(step); self.insert(step); self.change_lanes(); let mut moves = self.processing_order(); for movement in &mut moves { movement.speed = self.determine_speed(movement.vehicle, step); }
            let passing = self.move_vehicles(&moves, step); self.pass_junctions(&mut moves, &passing); for movement in &moves { self.aggregate_vehicle(movement, step); } self.aggregate_state(step);
        }
        for j in 0..self.sources.len() { let source = &self.sources[j]; if source.queue_start != 0 { let event = format!("QUEUE {} from {} max {} open", source.node, source.queue_start, source.queue_max); self.record(self.steps, event); } }
    }
    fn enumerate_routes(&self, segment: usize) -> Vec<(Vec<usize>, Rational)> {
        let s = &self.segments[segment]; if s.junction.is_none() { return vec![(vec![segment], Rational::new(1, 1))]; } let total: i64 = s.turns.iter().map(|turn| turn.weight).sum(); let mut routes = Vec::new();
        for turn in &s.turns { for (route, share) in self.enumerate_routes(turn.target) { let mut prefixed = vec![segment]; prefixed.extend(route); routes.push((prefixed, share.multiply(turn.weight, total))); } } routes
    }
    fn route_text(&self, route: &[usize], separator: &str) -> String { route.iter().map(|&s| self.segments[s].id.as_str()).collect::<Vec<_>>().join(separator) }
    fn spacetime_lines(&self) -> Vec<String> {
        let mut lines = Vec::new(); for diagram in &self.diagrams { lines.push(format!("DIAGRAM {} lane {} steps {}-{}", self.segments[diagram.segment].id, diagram.lane, diagram.start, diagram.end)); lines.extend(diagram.lines.iter().cloned()); } lines
    }
    fn detector_lines(&self) -> Vec<String> {
        let mut lines = vec!["detector,interval,flow,density,speed".to_owned()];
        for (j, detector) in self.detectors.iter().enumerate() { let capacity = (self.interval_length * detector.width * self.segments[detector.segment].lanes) as i64;
            for (k, interval) in self.intervals.iter().enumerate() { lines.push(format!("{},{},{},{},{}", detector.name, k + 1, interval.passing[j], dec(interval.occupancy[j], capacity, 4), dec(interval.occupancy_speed[j], interval.occupancy[j], 2))); }
        } lines
    }
    fn travel_block(&self, heading: &str, group: &[usize]) -> Vec<String> {
        let mut times: Vec<_> = group.iter().map(|&v| self.vehicles[v].travel_time()).collect(); times.sort_unstable(); if times.is_empty() { return vec![format!("{heading} exited 0")]; }
        let mut lines = vec![format!("{heading} exited {} min {} p50 {} p90 {} max {} mean {}", times.len(), times[0], percentile(&times, 50), percentile(&times, 90), times[times.len() - 1], dec(times.iter().sum(), times.len() as i64, 2))]; lines.extend(histogram_lines(&times, self.bin_width)); lines
    }
    fn outcome_text(&self, group: &[usize], exited: usize) -> String {
        let total: i64 = group.iter().map(|&v| self.vehicles[v].travel_time()).sum(); format!("vehicles {} share {} mean {}", group.len(), frac(group.len() as i64, exited as i64), dec(total, group.len() as i64, 2))
    }
    fn source_lines(&self, source: usize, exited: &[usize]) -> Vec<String> {
        let group: Vec<_> = exited.iter().copied().filter(|&v| self.vehicles[v].source == source).collect(); let routes = self.enumerate_routes(self.sources[source].segment);
        let mut lines = vec![format!("SOURCE {} exited {}", self.sources[source].node, group.len())];
        for (route, share) in &routes { let matched: Vec<_> = group.iter().copied().filter(|&v| self.vehicles[v].route == *route).collect(); lines.push(format!("  ROUTE {} expected {} {}", self.route_text(route, ","), share.text(), self.outcome_text(&matched, group.len()))); }
        for sink in &self.sinks {
            let mut share = Rational::new(0, 1); let mut found = false;
            for (route, expected) in &routes { if self.segments[*route.last().unwrap()].end == *sink { share = share.add(*expected); found = true; } }
            if !found { continue; } let matched: Vec<_> = group.iter().copied().filter(|&v| self.vehicles[v].sink.as_ref() == Some(sink)).collect(); lines.push(format!("  SINK {sink} expected {} {}", share.text(), self.outcome_text(&matched, group.len())));
        } lines
    }
    fn travel_time_lines(&self) -> Vec<String> {
        let exited: Vec<_> = (0..self.vehicles.len()).filter(|&v| self.vehicles[v].exited.is_some()).collect(); let mut lines = Vec::new();
        for (class, kind) in self.classes.iter().enumerate() { let group: Vec<_> = exited.iter().copied().filter(|&v| self.vehicles[v].class == class).collect(); lines.extend(self.travel_block(&format!("CLASS {}", kind.name), &group)); }
        lines.extend(self.travel_block("ALL", &exited)); for source in 0..self.sources.len() { lines.extend(self.source_lines(source, &exited)); } lines
    }
    fn class_block(&self, heading: String, group: &[usize]) -> Vec<String> {
        let mut inserted = 0; let mut exited = 0; let mut steps = 0; let mut distance = 0; let mut travel = 0; let mut delay = 0; let mut stopped = 0; let mut stops = 0; let mut changes = 0;
        for &j in group { let v = &self.vehicles[j]; if v.inserted.is_some() { inserted += 1; } steps += v.steps; distance += v.distance;
            if v.exited.is_some() { exited += 1; travel += v.travel_time(); delay += (v.inserted.unwrap() - v.arrival) as i64; stopped += v.stopped_steps; stops += v.stop_count; changes += v.lane_changes; }
        }
        vec![heading, format!("  generated {} inserted {inserted} exited {exited} in_network {} queued {}", group.len(), inserted - exited, group.len() - inserted), format!("  vehicle_steps {steps} distance {distance} mean_speed {} = {}", frac(distance, steps), dec(distance, steps, 3)), format!("  travel {} entry_delay {} stopped {} stops {} lane_changes {}", dec(travel, exited as i64, 2), dec(delay, exited as i64, 2), dec(stopped, exited as i64, 2), dec(stops, exited as i64, 2), dec(changes, exited as i64, 2))]
    }
    fn class_stats_lines(&self) -> Vec<String> {
        let mut lines = Vec::new(); for (class, kind) in self.classes.iter().enumerate() {
            let heading = format!("CLASS {} vmax {} weight {} overtake {} stops {}", kind.name, kind.vmax, kind.weight, flag_text(kind.overtakes), flag_text(kind.stops)); let group: Vec<_> = (0..self.vehicles.len()).filter(|&v| self.vehicles[v].class == class).collect(); lines.extend(self.class_block(heading, &group));
        } let all: Vec<_> = (0..self.vehicles.len()).collect(); lines.extend(self.class_block("ALL".to_owned(), &all)); lines
    }
    fn network_stats_lines(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for s in &self.segments { let changes = s.changes.iter().map(i64::to_string).collect::<Vec<_>>().join("/"); lines.push(format!("SEGMENT {} {} {} length {} lanes {} limit {} entered {} mean_vehicles {} density {} mean_speed {} max_vehicles {} changes {changes}", s.id, s.start, s.end, s.length, s.lanes, s.limit, s.entered, dec(s.vehicle_sum, self.steps as i64, 3), dec(s.vehicle_sum, (self.steps * s.length * s.lanes) as i64, 4), dec(s.speed_sum, s.vehicle_sum, 2), s.max_vehicles)); }
        for junction in &self.junctions { lines.extend(junction.plan_lines()); for &segment in &junction.incoming { let s = &self.segments[segment]; lines.push(format!("  IN {} green {} passed {} blocked {} max_queue {} mean_queue {} failures {}", s.id, s.green_steps, s.passed, s.blocked, s.max_queue, dec(s.queue_sum, self.steps as i64, 3), s.failures)); for turn in &s.turns { lines.push(format!("    TURN {} weight {} vehicles {}", self.segments[turn.target].id, turn.weight, turn.vehicles)); } } }
        for stop in &self.stops { lines.push(format!("STOP {} cell {} dwell {} buses {}", self.segments[stop.segment].id, stop.cell, stop.dwell, stop.buses)); }
        for incident in &self.incidents { let active = incident.active_start.map_or_else(|| "none".to_owned(), |start| format!("{start}-{}", incident.active_end.unwrap())); lines.push(format!("INCIDENT {} lane {} cell {} planned {}-{} active {active}", self.segments[incident.segment].id, incident.lane, incident.cell, incident.start, incident.end)); } lines
    }
    fn timeline_lines(&self) -> Vec<String> {
        let mut lines = vec!["interval,arrived,inserted,exited,in_network,queued,mean_speed".to_owned()]; let mut arrived = 0; let mut inserted = 0; let mut exited = 0;
        for (j, interval) in self.intervals.iter().enumerate() { arrived += interval.arrivals; inserted += interval.insertions; exited += interval.exits; lines.push(format!("{},{},{},{},{},{},{}", j + 1, interval.arrivals, interval.insertions, interval.exits, inserted - exited, arrived - inserted, dec(interval.speed_sum, interval.vehicle_steps, 2))); } lines
    }
    fn track_lines(&self) -> Vec<String> {
        let mut lines = Vec::new(); for &number in &self.track_numbers {
            if number > self.vehicles.len() { lines.push(format!("VEHICLE {number} none")); continue; } let v = &self.vehicles[number - 1];
            let optional = |value: Option<usize>| value.map_or_else(|| "-".to_owned(), |n| n.to_string());
            lines.push(format!("VEHICLE {number} class {} source {} arrival {} inserted {} exited {} sink {}", self.classes[v.class].name, self.sources[v.source].node, v.arrival, optional(v.inserted), optional(v.exited), v.sink.as_deref().unwrap_or("-")));
            lines.push(format!("ROUTE {}", if v.route.is_empty() { "-".to_owned() } else { self.route_text(&v.route, " ") })); lines.extend(self.tracks[&number].iter().cloned());
        } lines
    }
    fn fundamental_lines(&self) -> Vec<String> {
        let mut lines = vec!["ring,vehicles,density,flow,speed".to_owned()]; for ring in &self.rings { for &count in &ring.counts { let total = run_ring(ring, count, self.dawdle, self.dawdle_stopped); lines.push(format!("{},{},{},{},{}", ring.number, count, dec(count as i64, ring.length as i64, 4), dec(total, (ring.length * ring.measure) as i64, 4), dec(total, (count * ring.measure) as i64, 3))); } } lines
    }
    fn write(&self) {
        fs::create_dir_all("output").unwrap(); let outputs = [("spacetime.txt", self.spacetime_lines()), ("detectors.csv", self.detector_lines()), ("travel_times.txt", self.travel_time_lines()), ("class_stats.txt", self.class_stats_lines()), ("network_stats.txt", self.network_stats_lines()), ("timeline.csv", self.timeline_lines()), ("tracks.txt", self.track_lines()), ("fundamental.csv", self.fundamental_lines()), ("events.txt", self.events.clone())];
        for (name, lines) in outputs { let text = if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" }; fs::write(format!("output/{name}"), text).unwrap(); }
    }
}

fn main() { let mut simulation = Simulation::new(); simulation.run(); simulation.write(); }
