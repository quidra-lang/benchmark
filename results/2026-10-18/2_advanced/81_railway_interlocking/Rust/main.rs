mod layout;
mod interlocking;
mod signals;
mod trains;
mod safety;
use std::collections::BTreeSet;
use std::fs;
use layout::{Beyond,Layout,Motion};
use interlocking::Interlocking;
use trains::Train;
fn log(lines: &mut Vec<String>, time: usize, content: String) {
    lines.push(format!("{} {}",time,content));
}
fn occupied(layout: &Layout, occupancy: &[Vec<usize>]) -> Vec<bool> {
    layout.sections.iter().enumerate().map(|(i,s)| s.failed || !occupancy[i].is_empty()).collect()
}
fn position(reverse: bool) -> char {
    if reverse {
        'R'
    } else {
        'N'
    }
}
fn pass_signal(train: &mut Train, signal: usize, layout: &mut Layout, locks: &mut Interlocking, checker: &mut safety::Checker, time: usize, events: &mut Vec<String>) {
    let route = locks.routes.iter().position(|r| r.start == signal && (r.state == 1 || r.state == 3));
    let aspect = layout.signals[signal].aspect;
    log(events,time,format!("PASS {} {} {} {}",train.name,layout.signals[signal].name,signals::ASPECTS[aspect],route.map_or("-",|r| locks.routes[r].name.as_str())));
    layout.signals[signal].passes += 1;
    train.passes += 1;
    if let Some(route) = route {
        locks.routes[route].state = 2;
        locks.routes[route].statistics[2] += 1;
    }
    if aspect == 0 {
        log(events,time,format!("SPAD {} {}",train.name,layout.signals[signal].name));
        train.emergency = true;
    }
    checker.passing(time,&train.name,&layout.signals[signal].name,aspect == 0);
}
fn run_train(train: &mut Train, layout: &mut Layout, locks: &mut Interlocking, occupancy: &[Vec<usize>], entered: &mut BTreeSet<usize>, checker: &mut safety::Checker, time: usize, events: &mut Vec<String>) {
    if train.state == 2 {
        return;
    }
    if train.state == 0 {
        let boundary = &layout.boundaries[train.entry];
        if time < train.scheduled_entry || layout.sections[boundary.section].failed || !occupancy[boundary.section].is_empty() || entered.contains(&train.entry) {
            return;
        }
        entered.insert(train.entry);
        train.state = 1;
        train.up = boundary.end == 0;
        train.path = vec![(boundary.section,0)];
        train.head = 0;
        train.speed = train.initial_speed;
        train.actual_entry = Some(time);
        log(events,time,format!("ENTER {} {}",train.name,boundary.name));
    }
    if train.dwelling {
        let stop = &train.stops[train.next_stop];
        if time < stop.actual_arrival.unwrap()+stop.dwell || time < stop.departure {
            return;
        }
        let finished = train.next_stop;
        train.dwelling = false;
        train.awaiting = Some(finished);
        train.next_stop += 1;
        if train.stops[finished].turn {
            let (section,start) = train.path[train.head_index()];
            let end = start+layout.sections[section].length;
            let body = train.body(layout);
            train.path = body.iter().rev().map(|&(section,start,_,_)| (section,end-(start+layout.sections[section].length))).collect();
            train.head = end-(train.head-train.length);
            train.up = !train.up;
            log(events,time,format!("REVERSE {} {}",train.name,layout.sections[train.stops[finished].section].name));
        }
    }
    let old_speed = train.speed;
    let mut head_index = train.head_index();
    let (mut section,start) = train.path[head_index];
    let distance = if train.crossed.is_some() {
        None
    } else {
        let mut distance = start+layout.sections[section].length-train.head;
        loop {
            if layout.signal(section,train.up).map_or(false,|g| layout.signals[g].aspect == 0) || train.stops.get(train.next_stop).map_or(false,|s| s.section == section) {
                break Some(distance);
            }
            match layout.beyond(section,train.up) {
                Beyond::Boundary(_) => break None,Beyond::Buffer | Beyond::Impassable => break Some(distance),Beyond::Section(next) => {
                    distance += layout.sections[next].length;
                    section = next;
                }
            }
        }
    };
    let speed = trains::speed(train,distance);
    let mut remaining = speed;
    head_index = train.head_index();
    while remaining > 0 {
        if train.crossed.is_some() {
            train.head += remaining;
            break;
        }
        let (section,start) = train.path[head_index];
        let end = start+layout.sections[section].length;
        if train.head+remaining <= end {
            train.head += remaining;
            break;
        }
        remaining -= end-train.head;
        train.head = end;
        if let Some(signal) = layout.signal(section,train.up) {
            pass_signal(train,signal,layout,locks,checker,time,events);
        }
        if let Some(stop) = train.awaiting {
            if train.stops[stop].section == section {
                log(events,time,format!("DEPART {} {}",train.name,layout.sections[section].name));
                train.stops[stop].actual_departure = Some(time);
                train.awaiting = None;
            }
        }
        match layout.beyond(section,train.up) {
            Beyond::Boundary(_) => train.crossed = Some(end),Beyond::Section(next) => {
                train.path.push((next,end));
                head_index = train.path.len()-1;
            },_ => unreachable!()
        }
    }
    train.speed = speed;
    train.distance += speed;
    train.max_speed = train.max_speed.max(speed);
    if speed == 0 {
        train.emergency = false;
    }
    let (section,start) = train.path[train.head_index()];
    let mut arrived = false;
    if let Some(stop) = train.stops.get_mut(train.next_stop) {
        if speed == 0 && section == stop.section && train.head == start+layout.sections[section].length {
            stop.actual_arrival = Some(time);
            train.dwelling = true;
            arrived = true;
            log(events,time,format!("ARRIVE {} {}",train.name,layout.sections[section].name));
        }
    }
    if speed == 0 && !arrived {
        train.standing += 1;
        if old_speed > 0 {
            log(events,time,format!("HOLD {} {}",train.name,layout.sections[section].name));
        }
    }
    if train.crossed.map_or(false,|boundary| train.head-train.length >= boundary) {
        train.state = 2;
        train.actual_exit = Some(time);
        log(events,time,format!("EXIT {} {}",train.name,layout.boundaries[train.exit].name));
    }
}
struct Request {
    number: usize,
    route: usize,
    time: usize,
    reason: String
}
struct Simulation {
    layout: Layout,
    locks: Interlocking,
    trains: Vec<Train>,
    scheduled: Vec<(usize,usize,usize)>,
    script: Vec<(usize,Vec<String>)>,
    end: usize,
    throw_time: usize,
    overlap_time: usize,
    snapshot_times: Vec<usize>,
    occupancy: Vec<Vec<usize>>,
    queue: Vec<Request>,
    request_count: usize,
    granted: usize,
    dropped: usize,
    checker: safety::Checker,
    events: Vec<String>,
    snapshots: Vec<String>,
    time: usize
}
impl Simulation {
    fn new() -> Self {
        let layout = Layout::read();
        let locks = Interlocking::read(&layout);
        let (trains,scheduled) = trains::read(&layout,&locks);
        let params: Vec<Vec<usize>> = fs::read_to_string("input/params.txt").unwrap().lines().map(|line| line.split_whitespace().skip(1).map(|n| n.parse().unwrap()).collect()).collect();
        let script = fs::read_to_string("input/events.txt").unwrap().lines().map(|line| {
            let w: Vec<_> = line.split_whitespace().collect();
            (w[0].parse().unwrap(),w[1..].iter().map(|s| (*s).to_owned()).collect())
        }).collect();
        let occupancy = vec![Vec::new();layout.sections.len()];
        Self {
            layout,
            locks,
            trains,
            scheduled,
            script,
            end: params[0][0],
            throw_time: params[1][0],
            overlap_time: params[2][0],
            snapshot_times: params[3].clone(),
            occupancy,
            queue: Vec::new(),
            request_count: 0,
            granted: 0,
            dropped: 0,
            checker: safety::Checker::new(),
            events: Vec::new(),
            snapshots: Vec::new(),
            time: 0
        }
    }
    fn add_request(&mut self, route: usize, requester: &str) {
        self.request_count += 1;
        self.queue.push(Request {
            number: self.request_count,
            route,
            time: self.time,
            reason: "none".to_owned()
        });
        self.locks.routes[route].statistics[0] += 1;
        log(&mut self.events,self.time,format!("REQUEST q{} {} {}",self.request_count,self.locks.routes[route].name,requester));
    }
    fn throw(&mut self, point: usize, target: bool) {
        self.layout.points[point].motion = Some(Motion {
            target,
            completion: Some(self.time+self.throw_time)
        });
        log(&mut self.events,self.time,format!("MOVE {} {} until {}",self.layout.points[point].name,position(target),self.time+self.throw_time));
    }
    fn cancel(&mut self, route: usize) {
        let requests: Vec<_> = self.queue.iter().filter(|q| q.route == route).map(|q| q.number).collect();
        if !requests.is_empty() {
            for number in requests {
                log(&mut self.events,self.time,format!("DROP q{} {}",number,self.locks.routes[route].name));
                self.dropped += 1;
            }
            self.queue.retain(|q| q.route != route);
            return;
        }
        if self.locks.routes[route].state == 1 {
            self.locks.routes[route].statistics[3] += 1;
            let start = self.locks.routes[route].start;
            let approach = self.layout.signals[start].section;
            if self.layout.signals[start].aspect != 0 && (self.layout.sections[approach].failed || !self.occupancy[approach].is_empty()) {
                let until = self.time+self.locks.routes[route].approach;
                self.locks.routes[route].state = 3;
                self.locks.routes[route].release = Some(until);
                log(&mut self.events,self.time,format!("CANCEL {} approach until {}",self.locks.routes[route].name,until));
            } else {
                self.locks.release(route,&self.layout);
                log(&mut self.events,self.time,format!("CANCEL {} released",self.locks.routes[route].name));
            }
        } else {
            log(&mut self.events,self.time,format!("CANCEL {} {}",self.locks.routes[route].name,if self.locks.routes[route].state == 0 {
                "none"
            } else {
                "refused"
            }));
        }
    }
    fn event(&mut self, w: &[String]) {
        match w[0].as_str() {
            "REQUEST" => {
                let route = self.locks.route(&w[1]);
                self.add_request(route,"OPERATOR");
            }
            "CANCEL" => {
                let route = self.locks.route(&w[1]);
                self.cancel(route);
            }
            "THROW" => {
                let p = self.layout.point(&w[1]);
                let target = w[2] == "R";
                let point = &self.layout.points[p];
                let result = if !self.locks.point_locks[p].is_empty() {
                    "locked"
                } else if point.failed {
                    "failed"
                } else if point.motion.is_some() {
                    "moving"
                } else if self.layout.sections[point.common].failed || !self.occupancy[point.common].is_empty() {
                    "occupied"
                } else if point.position == target {
                    "none"
                } else {
                    "start"
                };
                log(&mut self.events,self.time,format!("THROW {} {} {}",point.name,position(target),result));
                if result == "start" {
                    self.throw(p,target);
                }
            }
            "TCFAIL" | "TCFIX" => {
                let section = self.layout.section(&w[1]);
                self.layout.sections[section].failed = w[0] == "TCFAIL";
                log(&mut self.events,self.time,format!("{} {}",w[0],w[1]));
            }
            "POINTFAIL" => {
                let p = self.layout.point(&w[1]);
                self.layout.points[p].failed = true;
                if let Some(motion) = &mut self.layout.points[p].motion {
                    motion.completion = None;
                }
                log(&mut self.events,self.time,format!("POINTFAIL {}",w[1]));
            }
            _ => {
                let p = self.layout.point(&w[1]);
                self.layout.points[p].failed = false;
                log(&mut self.events,self.time,format!("POINTFIX {}",w[1]));
                if let Some(motion) = &mut self.layout.points[p].motion {
                    motion.completion = Some(self.time+self.throw_time);
                    log(&mut self.events,self.time,format!("MOVE {} {} until {}",w[1],position(motion.target),self.time+self.throw_time));
                }
            }
        }
    }
    fn reason(&self, route: usize) -> Option<String> {
        let r = &self.locks.routes[route];
        let occupied = occupied(&self.layout,&self.occupancy);
        let opposite = |other: usize| self.locks.routes[other].up != r.up;
        if r.state != 0 {
            return Some("busy".to_owned());
        }
        if let Some(&other) = r.conflicts.iter().find(|&&other| self.locks.routes[other].state == 1 || self.locks.routes[other].state == 3) {
            return Some(format!("conflict {}",self.locks.routes[other].name));
        }
        for &section in &r.sections {
            if occupied[section] {
                return Some(format!("occupied {}",self.layout.sections[section].name));
            }
            if self.locks.section_route[section].is_some() || self.locks.section_overlap[section].iter().any(|&other| opposite(other)) {
                return Some(format!("locked {}",self.layout.sections[section].name));
            }
        }
        for &section in &r.overlap {
            if occupied[section] {
                return Some(format!("occupied {}",self.layout.sections[section].name));
            }
            if self.locks.section_route[section].map_or(false,|other| opposite(other)) || self.locks.section_overlap[section].iter().any(|&other| opposite(other)) {
                return Some(format!("locked {}",self.layout.sections[section].name));
            }
        }
        for &(p,target) in r.points.iter().chain(&r.flank) {
            let point = &self.layout.points[p];
            if self.locks.point_locks[p].iter().any(|&(_,position)| position != target) {
                return Some(format!("point {} locked",point.name));
            }
            if point.motion.as_ref().map_or(point.position == target,|m| m.target == target) {
                continue;
            }
            let reason = if point.failed {
                Some("failed")
            } else if point.motion.is_some() {
                Some("moving")
            } else if occupied[point.common] {
                Some("occupied")
            } else {
                None
            };
            if let Some(reason) = reason {
                return Some(format!("point {} {}",point.name,reason));
            }
        }
        None
    }
    fn judge_requests(&mut self) {
        let mut index = 0;
        while index < self.queue.len() {
            let route = self.queue[index].route;
            if let Some(reason) = self.reason(route) {
                if reason != self.queue[index].reason {
                    log(&mut self.events,self.time,format!("WAIT q{} {} {}",self.queue[index].number,self.locks.routes[route].name,reason));
                    self.queue[index].reason = reason;
                }
                index += 1;
            } else {
                let request = self.queue.remove(index);
                self.locks.lock(route);
                let wait = self.time-request.time;
                self.granted += 1;
                let r = &mut self.locks.routes[route];
                r.statistics[1] += 1;
                r.statistics[4] += wait;
                r.statistics[5] = r.statistics[5].max(wait);
                log(&mut self.events,self.time,format!("GRANT q{} {} wait {}",request.number,r.name,wait));
                let points: Vec<_> = r.points.iter().chain(&r.flank).copied().collect();
                for (p,target) in points {
                    if self.layout.points[p].motion.is_none() && self.layout.points[p].position != target {
                        self.throw(p,target);
                    }
                }
            }
        }
    }
    fn release_sections(&mut self) {
        let occupied = occupied(&self.layout,&self.occupancy);
        for route in 0..self.locks.routes.len() {
            if self.locks.routes[route].state != 2 {
                continue;
            }
            let sections = self.locks.routes[route].sections.clone();
            for &section in &sections {
                if self.locks.section_route[section] == Some(route) && occupied[section] {
                    self.locks.routes[route].passed.insert(section);
                }
            }
            for &section in &sections {
                if self.locks.section_route[section] != Some(route) {
                    continue;
                }
                if self.locks.routes[route].passed.contains(&section) && !occupied[section] {
                    self.locks.unlock_section(route,section,&self.layout);
                    log(&mut self.events,self.time,format!("RELEASE {} {}",self.locks.routes[route].name,self.layout.sections[section].name));
                } else {
                    break;
                }
            }
            if sections.iter().all(|&s| self.locks.section_route[s] != Some(route)) {
                self.locks.release(route,&self.layout);
                log(&mut self.events,self.time,format!("DONE {}",self.locks.routes[route].name));
            } else if !self.locks.routes[route].overlap.is_empty() && self.locks.routes[route].overlap_locked {
                let last = *sections.last().unwrap();
                if occupied[last] {
                    self.locks.routes[route].counter += 1;
                } else {
                    self.locks.routes[route].counter = 0;
                }
                if self.locks.routes[route].counter == self.overlap_time {
                    self.locks.unlock_overlap(route,&self.layout);
                    log(&mut self.events,self.time,format!("OVERLAP {}",self.locks.routes[route].name));
                }
            }
        }
    }
    fn statistics(&mut self) {
        for route in &mut self.locks.routes {
            route.statistics[6] += usize::from(route.state != 0);
        }
        for (p,point) in self.layout.points.iter_mut().enumerate() {
            point.locked_seconds += usize::from(!self.locks.point_locks[p].is_empty());
            point.moving_seconds += usize::from(point.motion.is_some());
        }
        for (s,section) in self.layout.sections.iter_mut().enumerate() {
            section.occupied_seconds += usize::from(section.failed || !self.occupancy[s].is_empty());
            section.locked_seconds += usize::from(self.locks.section_route[s].is_some() || !self.locks.section_overlap[s].is_empty());
            section.trains.extend(self.occupancy[s].iter().copied());
        }
        for signal in &mut self.layout.signals {
            signal.seconds[signal.aspect] += 1;
        }
    }
    fn snapshot(&self) -> Vec<String> {
        let mut height = 0;
        let mut width = 0;
        for s in &self.layout.sections {
            height = height.max(s.row+1);
            width = width.max(s.last+1);
        }
        for p in &self.layout.points {
            height = height.max(p.row+1);
            width = width.max(p.column+1);
        }
        for s in &self.layout.signals {
            height = height.max(s.row+1);
            width = width.max(s.column+1);
        }
        for b in &self.layout.buffers {
            height = height.max(b.row+1);
            width = width.max(b.column+1);
        }
        for label in &self.layout.labels {
            height = height.max(label.row+1);
            width = width.max(label.column+label.text.len());
        }
        let mut grid = vec![vec![b' ';width];height];
        for label in &self.layout.labels {
            for (i,b) in label.text.bytes().enumerate() {
                grid[label.row][label.column+i] = b;
            }
        }
        for (s,section) in self.layout.sections.iter().enumerate() {
            let character = if section.failed {
                b'#'
            } else if self.locks.section_route[s].is_some() {
                b'='
            } else if !self.locks.section_overlap[s].is_empty() {
                b'~'
            } else {
                b'-'
            };
            for c in section.first..=section.last {
                grid[section.row][c] = character;
            }
        }
        for (i,train) in self.trains.iter().enumerate() {
            for (s,start,lo,hi) in train.body(&self.layout) {
                let section = &self.layout.sections[s];
                let length = section.length;
                let n = (section.last-section.first+1) as i64;
                let (p,q) = if train.up {
                    (lo-start,hi-start)
                } else {
                    (length-(hi-start),length-(lo-start))
                };
                for j in 0..n {
                    if p*n < (j+1)*length && q*n > j*length {
                        let target = &mut grid[section.row][section.first+j as usize];
                        *target = if target.is_ascii_lowercase() || *target == b'*' {
                            b'*'
                        } else {
                            b'a'+i as u8
                        };
                    }
                }
            }
        }
        for buffer in &self.layout.buffers {
            grid[buffer.row][buffer.column] = b'|';
        }
        for point in &self.layout.points {
            grid[point.row][point.column] = point.display() as u8;
        }
        for signal in &self.layout.signals {
            grid[signal.row][signal.column] = b"XYG"[signal.aspect];
        }
        let mut lines = vec![format!("SNAPSHOT {}",self.time)];
        for row in grid {
            lines.push(String::from_utf8(row).unwrap().trim_end_matches(' ').to_owned());
        }
        for (i,train) in self.trains.iter().enumerate() {
            if train.state == 1 {
                let sections = train.body(&self.layout).iter().map(|&(s,_,_,_)| self.layout.sections[s].name.as_str()).collect::<Vec<_>>().join(",");
                lines.push(format!("TRAIN {} {} {} {} {}",(b'a'+i as u8) as char,train.name,if train.up {
                    "UP"
                } else {
                    "DOWN"
                },train.speed,sections));
            }
        }
        let routes: Vec<_> = self.locks.routes.iter().filter(|r| r.state != 0).map(|r| format!("{}/{}",r.name,interlocking::STATES[r.state])).collect();
        lines.push(format!("ROUTES {}",if routes.is_empty() {
            "-".to_owned()
        } else {
            routes.join(" ")
        }));
        lines
    }
    fn run(&mut self) {
        for time in 0..=self.end {
            self.time = time;
            for p in 0..self.layout.points.len() {
                if self.layout.points[p].motion.as_ref().map_or(false,|m| m.completion == Some(time)) {
                    let target = self.layout.points[p].motion.as_ref().unwrap().target;
                    self.layout.points[p].position = target;
                    self.layout.points[p].motion = None;
                    self.layout.points[p].throws += 1;
                    log(&mut self.events,time,format!("POINT {} {}",self.layout.points[p].name,position(target)));
                }
            }
            for r in 0..self.locks.routes.len() {
                if self.locks.routes[r].state == 3 && self.locks.routes[r].release == Some(time) {
                    self.locks.release(r,&self.layout);
                    log(&mut self.events,time,format!("TIMEOUT {}",self.locks.routes[r].name));
                }
            }
            let requests: Vec<_> = self.scheduled.iter().filter(|&&(t,_,_)| t == time).map(|&(_,route,train)| (route,train)).collect();
            for (route,train) in requests {
                let name = self.trains[train].name.clone();
                self.add_request(route,&name);
            }
            let events: Vec<_> = self.script.iter().filter(|(t,_)| *t == time).map(|(_,w)| w.clone()).collect();
            for event in events {
                self.event(&event);
            }
            self.judge_requests();
            let aspects = signals::decide(&self.layout,&self.locks,&occupied(&self.layout,&self.occupancy));
            for (i,aspect) in aspects.into_iter().enumerate() {
                if aspect != self.layout.signals[i].aspect {
                    self.layout.signals[i].aspect = aspect;
                    log(&mut self.events,time,format!("SIGNAL {} {}",self.layout.signals[i].name,signals::ASPECTS[aspect]));
                }
            }
            let mut entered = BTreeSet::new();
            for train in &mut self.trains {
                run_train(train,&mut self.layout,&mut self.locks,&self.occupancy,&mut entered,&mut self.checker,time,&mut self.events);
            }
            self.occupancy = vec![Vec::new();self.layout.sections.len()];
            for (i,train) in self.trains.iter().enumerate() {
                for (section,_,_,_) in train.body(&self.layout) {
                    self.occupancy[section].push(i);
                }
            }
            self.release_sections();
            let names: Vec<_> = self.trains.iter().map(|t| t.name.clone()).collect();
            self.checker.check(time,&self.layout,&self.locks,&self.occupancy,&names);
            self.statistics();
            if self.snapshot_times.contains(&time) {
                self.snapshots.extend(self.snapshot());
            }
        }
    }
    fn reports(&self) -> (Vec<String>,Vec<String>) {
        let mut summary = Vec::new();
        for route in &self.locks.routes {
            let s = route.statistics;
            summary.push(format!("ROUTE {} {}-{} requests {} grants {} uses {} cancels {} wait {} maxwait {} locked {}",route.name,self.layout.signals[route.start].name,route.finish_name,s[0],s[1],s[2],s[3],s[4],s[5],s[6]));
        }
        for point in &self.layout.points {
            summary.push(format!("POINT {} throws {} locked {} moving {} final {}",point.name,point.throws,point.locked_seconds,point.moving_seconds,point.display()));
        }
        for section in &self.layout.sections {
            summary.push(format!("SECTION {} occupied {} locked {} trains {}",section.name,section.occupied_seconds,section.locked_seconds,section.trains.len()));
        }
        for signal in &self.layout.signals {
            summary.push(format!("SIGNAL {} red {} yellow {} green {} passes {}",signal.name,signal.seconds[0],signal.seconds[1],signal.seconds[2],signal.passes));
        }
        for (i,train) in self.trains.iter().enumerate() {
            summary.push(format!("TRAIN {} {} {} distance {} maxspeed {} standing {} passes {}",train.name,(b'a'+i as u8) as char,["WAITING","RUNNING","EXITED"][train.state],train.distance,train.max_speed,train.standing,train.passes));
        }
        let mut counts = [0usize;3];
        for train in &self.trains {
            counts[train.state] += 1;
        }
        summary.push(format!("TRAINS total {} exited {} running {} waiting {}",self.trains.len(),counts[2],counts[1],counts[0]));
        let mut csv = vec!["train,location,scheduled,actual,delay".to_owned()];
        let mut punctuality = [0i64;5];
        for train in &self.trains {
            let mut records = vec![(format!("enter:{}",self.layout.boundaries[train.entry].name),train.scheduled_entry,train.actual_entry)];
            for stop in &train.stops {
                records.push((format!("arr:{}",self.layout.sections[stop.section].name),stop.arrival,stop.actual_arrival));
                records.push((format!("dep:{}",self.layout.sections[stop.section].name),stop.departure,stop.actual_departure));
            }
            records.push((format!("exit:{}",self.layout.boundaries[train.exit].name),train.scheduled_exit,train.actual_exit));
            for (location,scheduled,actual) in records {
                if let Some(actual) = actual {
                    let delay = actual as i64-scheduled as i64;
                    punctuality[usize::from(delay > 0)] += 1;
                    punctuality[3] += delay.max(0);
                    punctuality[4] = punctuality[4].max(delay);
                    csv.push(format!("{},{},{},{},{}",train.name,location,scheduled,actual,delay));
                } else {
                    punctuality[2] += 1;
                    csv.push(format!("{},{},{},-,-",train.name,location,scheduled));
                }
            }
        }
        summary.push(format!("PUNCTUALITY on_time {} late {} missing {} total_delay {} max_delay {}",punctuality[0],punctuality[1],punctuality[2],punctuality[3],punctuality[4]));
        summary.push(format!("REQUESTS total {} granted {} dropped {} pending {}",self.request_count,self.granted,self.dropped,self.queue.len()));
        (csv,summary)
    }
}
fn write(name: &str, lines: &[String]) {
    let content = if lines.is_empty() {
        String::new()
    } else {
        lines.join("\n")+"\n"
    };
    fs::write(format!("output/{}",name),content).unwrap();
}
fn main() {
    let mut simulation = Simulation::new();
    simulation.run();
    let (train_log,summary) = simulation.reports();
    fs::create_dir_all("output").unwrap();
    for (name,lines) in [("events.txt",simulation.events),("snapshots.txt",simulation.snapshots),("train_log.csv",train_log),("safety.txt",simulation.checker.lines()),("summary.txt",summary)] {
        write(name,&lines);
    }
}
