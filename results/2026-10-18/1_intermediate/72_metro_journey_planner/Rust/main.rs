use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};
fn time(s: &str) -> i32 {
    let (h,m) = s.split_once(':').unwrap();
    h.parse::<i32>().unwrap()*60+m.parse::<i32>().unwrap()
}
fn clock(t: i32) -> String {
    format!("{:02}:{:02}",t/60,t%60)
}
fn pair(a: &str, b: &str) -> (String,String) {
    if a < b {
        (a.into(),b.into())
    } else {
        (b.into(),a.into())
    }
}
#[derive(Clone)]
struct Station {
    zone: i32, name: String, transfer: i32, closed: bool
}
#[derive(Clone)]
struct Line {
    first: i32, last: i32, headway: i32, stops: Vec<String>, offsets: Vec<i32>, delay: i32, suspended: bool
}
impl Line {
    fn total(&self) -> i32 {
        *self.offsets.last().unwrap()
    }
    fn trips(&self) -> i32 {
        (self.last-self.first)/self.headway+1
    }
    fn direction(&self, reverse: bool) -> (Vec<String>,Vec<i32>) {
        if reverse {
            (self.stops.iter().rev().cloned().collect(),self.offsets.iter().rev().map(|&t|self.total()-t).collect())
        } else {
            (self.stops.clone(),self.offsets.clone())
        }
    }
    fn next(&self, offset: i32, ready: i32) -> Option<i32> {
        let delta = ready-self.first-self.delay-offset;
        let q = if delta <= 0 {
            0
        } else {
            (delta+self.headway-1)/self.headway
        };
        (q < self.trips()).then_some(q)
    }
    fn at(&self, q: i32, offset: i32) -> i32 {
        self.first+self.delay+q*self.headway+offset
    }
}
#[derive(Clone)]
enum Leg {
    Ride {
        line: String, terminal: String, from: String, departure: i32, to: String, arrival: i32, stops: usize
    },
    Walk {
        from: String, departure: i32, to: String, arrival: i32
    },
    Stay {
        station: String, start: i32, end: i32
    },
}
impl Leg {
    fn end(&self) -> i32 {
        match self {
            Self::Ride {
                arrival,..
            }|Self::Walk {
                arrival,..
            } => *arrival, Self::Stay {
                end,..
            } => *end
        }
    }
}
#[derive(Clone)]
struct Label {
    arrival: i32, journey: Vec<Leg>
}
type Labels = BTreeMap<String,Label>;
fn rides(j: &[Leg]) -> usize {
    j.iter().filter(|l|matches!(l,Leg::Ride {
        ..
    })).count()
}
fn relax(labels: &mut Labels, station: &str, arrival: i32, journey: &[Leg], leg: Leg) -> bool {
    if labels.get(station).is_none_or(|old|old.arrival > arrival) {
        let mut j = journey.to_vec();
        j.push(leg);
        labels.insert(station.into(),Label {
            arrival,journey:j
        });
        true
    } else {
        false
    }
}
fn print_journey(heading: &str, departure: i32, label: &Label) -> Vec<String> {
    let mut out = vec![format!("{heading} {} -> {} total {} rides {} walks {}",clock(departure),clock(label.arrival),label.arrival-departure,rides(&label.journey),label.journey.iter().filter(|l|matches!(l,Leg::Walk {
        ..
    })).count())];
    let mut previous = departure;
    for leg in &label.journey {
        out.push(match leg {
            Leg::Ride {
                line,terminal,from,departure,to,arrival,stops
            } => format!("RIDE {line} toward {terminal} {from} {} -> {to} {} wait {} stops {stops}",clock(*departure),clock(*arrival),departure-previous),
            Leg::Walk {
                from,departure,to,arrival
            } => format!("WALK {from} {} -> {to} {}",clock(*departure),clock(*arrival)),
            Leg::Stay {
                station,start,end
            } => format!("STAY {station} {} -> {}",clock(*start),clock(*end)),
        });
        previous = leg.end();
    }
    out
}
struct Planner {
    stations: BTreeMap<String,Station>, lines: BTreeMap<String,Line>, walks: BTreeMap<(String,String),i32>, closed: BTreeSet<(String,String)>, tariff: Option<(i32,i32,Vec<i32>)>
}
impl Planner {
    fn station(&self, s: &str) -> Result<&Station,String> {
        self.stations.get(s).ok_or_else(||format!("unknown station {s}"))
    }
    fn line(&self, s: &str) -> Result<&Line,String> {
        self.lines.get(s).ok_or_else(||format!("unknown line {s}"))
    }
    fn open_station(&self, s: &str) -> Result<(),String> {
        if self.station(s)?.closed {
            Err(format!("station {s} is closed"))
        } else {
            Ok(())
        }
    }
    fn common(&self, a: &str, b: &str) -> Result<(),String> {
        self.station(a)?;
        self.station(b)?;
        if a == b {
            return Err("origin and destination are the same".into());
        }
        self.open_station(a)?;
        self.open_station(b)
    }
    fn neighbors(&self, s: &str) -> Vec<(String,i32)> {
        let mut out: Vec<_> = self.walks.iter().filter_map(|((a,b),&t)|if a == s {
            Some((b.clone(),t))
        } else if b == s {
            Some((a.clone(),t))
        } else {
            None
        }).collect();
        out.sort_by(|a,b|a.0.cmp(&b.0));
        out
    }
    fn earliest(&self, origin: &str, departure: i32) -> Labels {
        let mut labels = Labels::from([(origin.into(),Label {
            arrival:departure,journey:Vec::new()
        })]);
        let mut settled = BTreeSet::new();
        loop {
            let Some((u,label)) = labels.iter().filter(|(s,_)|!settled.contains(*s)).min_by_key(|(s,l)|(l.arrival,*s)).map(|(s,l)|(s.clone(),l.clone())) else {
                break;
            };
            settled.insert(u.clone());
            let ready = label.arrival+if u == origin {
                0
            } else {
                self.stations[&u].transfer
            };
            for (id,line) in &self.lines {
                if line.suspended || !line.stops.contains(&u) {
                    continue;
                }
                for reverse in [false,true] {
                    let (stops,offsets) = line.direction(reverse);
                    let i = stops.iter().position(|s|s == &u).unwrap();
                    if i+1 == stops.len() {
                        continue;
                    }
                    let Some(q) = line.next(offsets[i],ready) else {
                        continue;
                    };
                    let d = line.at(q,offsets[i]);
                    for j in i+1..stops.len() {
                        if self.closed.contains(&pair(&stops[j-1],&stops[j])) {
                            break;
                        }
                        if self.stations[&stops[j]].closed {
                            continue;
                        }
                        let t = line.at(q,offsets[j]);
                        relax(&mut labels,&stops[j],t,&label.journey,Leg::Ride {
                            line:id.clone(),terminal:stops.last().unwrap().clone(),from:u.clone(),departure:d,to:stops[j].clone(),arrival:t,stops:j-i
                        });
                    }
                }
            }
            for (v,w) in self.neighbors(&u) {
                let t = label.arrival+w;
                if !self.stations[&v].closed && t <= 1440 {
                    relax(&mut labels,&v,t,&label.journey,Leg::Walk {
                        from:u.clone(),departure:label.arrival,to:v.clone(),arrival:t
                    });
                }
            }
        }
        labels
    }
    fn walk_step(&self, labels: &mut Labels, sources: &BTreeSet<String>, changed: &mut BTreeSet<String>) {
        let recorded: Vec<_> = sources.iter().map(|s|(s.clone(),labels[s].clone())).collect();
        for (u,label) in recorded {
            for (v,w) in self.neighbors(&u) {
                let t = label.arrival+w;
                if !self.stations[&v].closed && t <= 1440 && relax(labels,&v,t,&label.journey,Leg::Walk {
                    from:u.clone(),departure:label.arrival,to:v.clone(),arrival:t
                }) {
                    changed.insert(v);
                }
            }
        }
    }
    fn rounds(&self, origin: &str, departure: i32) -> Vec<Labels> {
        let mut labels = Labels::from([(origin.into(),Label {
            arrival:departure,journey:Vec::new()
        })]);
        let mut changed = BTreeSet::from([origin.to_string()]);
        self.walk_step(&mut labels,&BTreeSet::from([origin.to_string()]),&mut changed);
        let mut result = vec![labels.clone()];
        while !changed.is_empty() {
            let previous = labels.clone();
            let marked = changed;
            changed = BTreeSet::new();
            let mut sources = BTreeSet::new();
            for (id,line) in &self.lines {
                if line.suspended {
                    continue;
                }
                for reverse in [false,true] {
                    let (stops,offsets) = line.direction(reverse);
                    let mut boarded: Option<(i32,usize,i32,Vec<Leg>)> = None;
                    for j in 0..stops.len() {
                        if j > 0 && self.closed.contains(&pair(&stops[j-1],&stops[j])) {
                            boarded = None;
                        }
                        if self.stations[&stops[j]].closed {
                            continue;
                        }
                        if let Some((q,b,d,journey)) = &boarded {
                            let t = line.at(*q,offsets[j]);
                            if relax(&mut labels,&stops[j],t,journey,Leg::Ride {
                                line:id.clone(),terminal:stops.last().unwrap().clone(),from:stops[*b].clone(),departure:*d,to:stops[j].clone(),arrival:t,stops:j-*b
                            }) {
                                sources.insert(stops[j].clone());
                                changed.insert(stops[j].clone());
                            }
                        }
                        if j+1 < stops.len() && marked.contains(&stops[j]) {
                            let old = &previous[&stops[j]];
                            let ready = old.arrival+if stops[j] == origin {
                                0
                            } else {
                                self.stations[&stops[j]].transfer
                            };
                            if let Some(q) = line.next(offsets[j],ready) {
                                if boarded.as_ref().is_none_or(|b|q < b.0) {
                                    boarded = Some((q,j,line.at(q,offsets[j]),old.journey.clone()));
                                }
                            }
                        }
                    }
                }
            }
            self.walk_step(&mut labels,&sources,&mut changed);
            result.push(labels.clone());
        }
        result
    }
    fn fare(&self, journey: &[Leg], child: bool) -> (i32,Vec<String>) {
        let (discount,window,prices) = self.tariff.as_ref().unwrap();
        let half = |n:i32|(n+19)/20*10;
        let cap = if child {
            half(*discount)
        } else {
            *discount
        };
        let mut previous = None;
        let mut total = 0;
        let mut tickets = Vec::new();
        for leg in journey {
            if let Leg::Ride {
                line,from,to,departure,arrival,..
            } = leg {
                let stops = &self.lines[line].stops;
                let a = stops.iter().position(|s|s == from).unwrap();
                let b = stops.iter().position(|s|s == to).unwrap();
                let zones = stops[a.min(b)..=a.max(b)].iter().map(|s|self.stations[s].zone).collect::<BTreeSet<_>>().len();
                let mut price = prices[zones.min(prices.len())-1];
                if child {
                    price = half(price);
                }
                let reduction = if previous.is_some_and(|t|departure-t <= *window) {
                    cap.min(price)
                } else {
                    0
                };
                let pay = price-reduction;
                total += pay;
                previous = Some(*arrival);
                tickets.push(format!("TICKET {line} {from} {to} zones {zones} price {price} discount {reduction} pay {pay}"));
            }
        } (total,tickets)
    }
    fn command(&mut self, w: &[&str]) -> Result<Vec<String>,String> {
        let c = w[0];
        let a = &w[1..];
        let num = |i:usize|a[i].parse::<i32>().unwrap();
        let mut out = Vec::new();
        match c {
            "STATION" => {
                if self.stations.contains_key(a[0]) {
                    return Err(format!("station {} already exists",a[0]));
                }
                self.stations.insert(a[0].into(),Station {
                    zone:num(1),name:a[2].into(),transfer:0,closed:false
                });
                out.push(format!("STATION {} zone {} {}",a[0],num(1),a[2]));
            }
            "LINE" => {
                if self.lines.contains_key(a[0]) {
                    return Err(format!("line {} already exists",a[0]));
                }
                let stops: Vec<String> = a[4..].iter().step_by(2).map(|s|s.to_string()).collect();
                for s in &stops {
                    self.station(s)?;
                }
                let mut seen = BTreeSet::new();
                for s in &stops {
                    if !seen.insert(s.clone()) {
                        return Err(format!("station {s} appears twice on line {}",a[0]));
                    }
                }
                let first = time(a[1]);
                let last = time(a[2]);
                let mut offsets = vec![0];
                for s in a[5..].iter().step_by(2) {
                    offsets.push(offsets.last().unwrap()+s.parse::<i32>().unwrap());
                }
                if first > last {
                    return Err(format!("line {} first departure is after last departure",a[0]));
                }
                if last+offsets.last().unwrap() > 1440 {
                    return Err(format!("line {} runs past 24:00",a[0]));
                }
                let line = Line {
                    first,last,headway:num(3),stops,offsets,delay:0,suspended:false
                };
                out.push(format!("LINE {} stops {} time {} trips {}",a[0],line.stops.len(),line.total(),line.trips()));
                self.lines.insert(a[0].into(),line);
            }
            "TRANSFER" => {
                self.station(a[0])?;
                self.stations.get_mut(a[0]).unwrap().transfer = num(1);
                out.push(format!("TRANSFER {} {}",a[0],num(1)));
            }
            "WALK" => {
                self.station(a[0])?;
                self.station(a[1])?;
                if a[0] == a[1] {
                    return Err(format!("walk from {} to itself",a[0]));
                }
                let old = self.walks.insert(pair(a[0],a[1]),num(2));
                out.push(format!("WALK {} {} {}{}",a[0],a[1],num(2),old.map_or(String::new(),|n|format!(" was {n}"))));
            }
            "TARIFF" => {
                let prices: Vec<_> = (2..a.len()).map(num).collect();
                if prices.windows(2).any(|p|p[0] > p[1]) {
                    return Err("tariff prices must not decrease".into());
                }
                out.push(format!("TARIFF zones {} discount {} window {}",prices.len(),num(0),num(1)));
                self.tariff = Some((num(0),num(1),prices));
            }
            "CLOSE" | "OPEN" => {
                self.station(a[0])?;
                let close = c == "CLOSE";
                if a.len() == 1 {
                    let station = self.stations.get_mut(a[0]).unwrap();
                    if station.closed == close {
                        return Err(format!("station {} is {}closed",a[0],if close {
                            "already "
                        } else {
                            "not "
                        }));
                    } station.closed = close;
                    out.push(format!("{c} {}",a[0]));
                }
                else {
                    self.station(a[1])?;
                    let key = pair(a[0],a[1]);
                    let lines: Vec<_> = self.lines.iter().filter(|(_,l)|l.stops.windows(2).any(|s|pair(&s[0],&s[1]) == key)).map(|(id,_)|id.clone()).collect();
                    if close && lines.is_empty() {
                        return Err(format!("no segment {}-{}",a[0],a[1]));
                    }
                    if self.closed.contains(&key) == close {
                        return Err(format!("segment {}-{} is {}closed",a[0],a[1],if close {
                            "already "
                        } else {
                            "not "
                        }));
                    }
                    if close {
                        self.closed.insert(key);
                    } else {
                        self.closed.remove(&key);
                    }
                    out.push(format!("{c} {}-{}{}",a[0],a[1],if close {
                        " lines ".to_string()+&lines.join(" ")
                    } else {
                        String::new()
                    }));
                }
            }
            "DELAY" => {
                let line = self.line(a[0])?;
                if line.last+num(1)+line.total() > 1440 {
                    return Err(format!("line {} runs past 24:00",a[0]));
                }
                self.lines.get_mut(a[0]).unwrap().delay = num(1);
                out.push(format!("DELAY {} {}",a[0],num(1)));
            }
            "SUSPEND" | "RESUME" => {
                let suspended = c == "SUSPEND";
                let line = self.line(a[0])?;
                if line.suspended == suspended {
                    return Err(format!("line {} is {}suspended",a[0],if suspended {
                        "already "
                    } else {
                        "not "
                    }));
                }
                self.lines.get_mut(a[0]).unwrap().suspended = suspended;
                out.push(format!("{c} {}",a[0]));
            }
            "ROUTE" | "FEWEST" | "PARETO" | "FARE" | "LASTTRAIN" | "ARRIVEBY" | "PROFILE" => {
                self.common(a[0],a[1])?;
                if c == "FARE" {
                    if !["ADULT","CHILD"].contains(&a[3]) {
                        return Err(format!("unknown fare class {}",a[3]));
                    }
                    if self.tariff.is_none() {
                        return Err("no tariff".into());
                    }
                }
                if c == "PROFILE" && time(a[2]) > time(a[3]) {
                    return Err(format!("empty interval {} {}",a[2],a[3]));
                }
                let heading = format!("{c} {} {}",a[0],a[1]);
                if c == "LASTTRAIN" || c == "ARRIVEBY" {
                    let bound = if c == "LASTTRAIN" {
                        1440
                    } else {
                        time(a[2])
                    };
                    let title = if c == "ARRIVEBY" {
                        format!("{heading} by {}",a[2])
                    } else {
                        heading.clone()
                    };
                    for t in (0..bound).rev() {
                        if let Some(label) = self.earliest(a[0],t).get(a[1]) {
                            if c == "LASTTRAIN" || label.arrival <= bound {
                                return Ok(print_journey(&title,t,label));
                            }
                        }
                    }
                    out.push(format!("{title} none"));
                }
                else if c == "PROFILE" {
                    let start = time(a[2]);
                    let end = time(a[3]);
                    let arrivals: Vec<_> = (start..=end).map(|t|self.earliest(a[0],t).get(a[1]).map(|l|l.arrival)).collect();
                    let mut selected = Vec::new();
                    for (i,&arrival) in arrivals.iter().enumerate() {
                        if let Some(arrival) = arrival {
                            if i+1 == arrivals.len() || arrivals[i+1].is_none_or(|next|arrival < next) {
                                selected.push(format!("{} -> {} total {}",clock(start+i as i32),clock(arrival),arrival-start-i as i32));
                            }
                        }
                    }
                    out.push(format!("{heading} {} {} count {}",a[2],a[3],selected.len()));
                    out.extend(selected);
                }
                else if c == "FEWEST" || c == "PARETO" {
                    let start = time(a[2]);
                    let rounds = self.rounds(a[0],start);
                    if c == "FEWEST" {
                        for (k,labels) in rounds.iter().enumerate() {
                            if let Some(label) = labels.get(a[1]) {
                                return Ok(print_journey(&format!("{heading} trips {k}"),start,label));
                            }
                        }
                        out.push(format!("{heading} {} unreachable",a[2]));
                    } else {
                        let mut options = Vec::new();
                        let mut previous = None;
                        let mut count = 0;
                        for (k,labels) in rounds.iter().enumerate() {
                            if let Some(label) = labels.get(a[1]) {
                                if previous.is_none_or(|t|t > label.arrival) {
                                    count += 1;
                                    options.extend(print_journey(&format!("OPTION trips {k}"),start,label));
                                } previous = Some(label.arrival);
                            }
                        }
                        out.push(format!("{heading} {} options {count}",a[2]));
                        out.extend(options);
                    }
                }
                else {
                    let start = time(a[2]);
                    let labels = self.earliest(a[0],start);
                    if let Some(label) = labels.get(a[1]) {
                        if c == "FARE" {
                            let (total,tickets) = self.fare(&label.journey,a[3] == "CHILD");
                            out.push(format!("{heading} {} {} rides {} total {total}",a[2],a[3],rides(&label.journey)));
                            out.extend(tickets);
                        } else {
                            out = print_journey(&heading,start,label);
                        }
                    } else {
                        out.push(format!("{heading} {}{} unreachable",a[2],if c == "FARE" {
                            " ".to_string()+a[3]
                        } else {
                            String::new()
                        }));
                    }
                }
            }
            "VIA" => {
                self.station(a[0])?;
                self.station(a[1])?;
                self.station(a[2])?;
                if a[0] == a[2] {
                    return Err("origin and destination are the same".into());
                }
                if a[1] == a[0] || a[1] == a[2] {
                    return Err(format!("via station {} must differ from origin and destination",a[1]));
                }
                self.open_station(a[0])?;
                self.open_station(a[1])?;
                self.open_station(a[2])?;
                let start = time(a[3]);
                let heading = format!("VIA {} {} {}",a[0],a[1],a[2]);
                if let Some(first) = self.earliest(a[0],start).get(a[1]) {
                    let next = first.arrival+self.stations[a[1]].transfer;
                    if let Some(second) = self.earliest(a[1],next).get(a[2]) {
                        let mut journey = first.journey.clone();
                        journey.push(Leg::Stay {
                            station:a[1].into(),start:first.arrival,end:next
                        });
                        journey.extend(second.journey.clone());
                        return Ok(print_journey(&heading,start,&Label {
                            arrival:second.arrival,journey
                        }));
                    }
                }
                out.push(format!("{heading} {} unreachable",a[3]));
            }
            "REACH" => {
                self.open_station(a[0])?;
                let start = time(a[1]);
                let mut selected: Vec<_> = self.earliest(a[0],start).into_iter().filter(|(_,l)|l.arrival <= start+num(2)).collect();
                selected.sort_by(|a,b|a.1.arrival.cmp(&b.1.arrival).then(a.0.cmp(&b.0)));
                out.push(format!("REACH {} {} {} count {}",a[0],a[1],num(2),selected.len()));
                for (s,label) in selected {
                    out.push(format!("{s} {} {} {} rides {}",self.stations[&s].name,clock(label.arrival),label.arrival-start,rides(&label.journey)));
                }
            }
            "TIMETABLE" => {
                self.station(a[0])?;
                let line = self.line(a[1])?;
                if !line.stops.iter().any(|s|s == a[0]) {
                    return Err(format!("station {} is not on line {}",a[0],a[1]));
                }
                if a[2] != line.stops[0] && a[2] != *line.stops.last().unwrap() {
                    return Err(format!("{} is not a terminal of line {}",a[2],a[1]));
                }
                if a[0] == a[2] {
                    return Err(format!("no departures from {} toward {}",a[0],a[2]));
                }
                if line.suspended {
                    return Err(format!("line {} is suspended",a[1]));
                }
                self.open_station(a[0])?;
                let (stops,offsets) = line.direction(a[2] == line.stops[0]);
                let i = stops.iter().position(|s|s == a[0]).unwrap();
                let selected: Vec<_> = (0..line.trips()).map(|q|line.at(q,offsets[i])).filter(|&t|t >= time(a[3])).take(num(4) as usize).map(clock).collect();
                out.push(format!("TIMETABLE {} {} toward {} {} next {}{}",a[0],a[1],a[2],a[3],selected.len(),if selected.is_empty() {
                    String::new()
                } else {
                    " ".to_string()+&selected.join(" ")
                }));
            }
            "DEPARTURES" | "ARRIVALS" => {
                self.open_station(a[0])?;
                let mut events = Vec::new();
                for (id,line) in &self.lines {
                    if line.suspended || !line.stops.iter().any(|s|s == a[0]) {
                        continue;
                    }
                    for reverse in [false,true] {
                        let (stops,offsets) = line.direction(reverse);
                        let i = stops.iter().position(|s|s == a[0]).unwrap();
                        if (c == "DEPARTURES" && i+1 == stops.len()) || (c == "ARRIVALS" && i == 0) {
                            continue;
                        }
                        for q in 0..line.trips() {
                            let t = line.at(q,offsets[i]);
                            if t >= time(a[1]) {
                                events.push((t,id.clone(),reverse,if c == "DEPARTURES" {
                                    stops.last().unwrap().clone()
                                } else {
                                    stops[0].clone()
                                }));
                            }
                        }
                    }
                } events.sort();
                events.truncate(num(2) as usize);
                out.push(format!("{c} {} {} count {}",a[0],a[1],events.len()));
                for (t,id,_,endpoint) in events {
                    out.push(format!("{} {id} {} {endpoint}",clock(t),if c == "DEPARTURES" {
                        "toward"
                    } else {
                        "from"
                    }));
                }
            }
            "TRIP" => {
                let line = self.line(a[0])?;
                if a[1] != line.stops[0] && a[1] != *line.stops.last().unwrap() {
                    return Err(format!("{} is not a terminal of line {}",a[1],a[0]));
                }
                if line.suspended {
                    return Err(format!("line {} is suspended",a[0]));
                }
                let (stops,offsets) = line.direction(a[1] == line.stops[0]);
                let heading = format!("TRIP {} toward {} {}",a[0],a[1],a[2]);
                if let Some(q) = line.next(0,time(a[2])) {
                    out.push(format!("{heading} trip {} departs {}",q+1,clock(line.at(q,0))));
                    for j in 0..stops.len() {
                        out.push(format!("{} {}{}{}",clock(line.at(q,offsets[j])),stops[j],if self.stations[&stops[j]].closed {
                            " closed"
                        } else {
                            ""
                        },if j > 0 && self.closed.contains(&pair(&stops[j-1],&stops[j])) {
                            " blocked"
                        } else {
                            ""
                        }));
                    }
                } else {
                    out.push(format!("{heading} none"));
                }
            }
            "SHOWLINE" => {
                let line = self.line(a[0])?;
                out.push(format!("SHOWLINE {} {} first {} last {} headway {} delay {} trips {}",a[0],if line.suspended {
                    "suspended"
                } else {
                    "running"
                },clock(line.first),clock(line.last),line.headway,line.delay,line.trips()));
                for j in 0..line.stops.len() {
                    let s = &line.stops[j];
                    out.push(format!("{} {s} zone {}{}{}",line.offsets[j],self.stations[s].zone,if self.stations[s].closed {
                        " closed"
                    } else {
                        ""
                    },if j > 0 && self.closed.contains(&pair(&line.stops[j-1],s)) {
                        " blocked"
                    } else {
                        ""
                    }));
                }
            }
            "INFO" => {
                let s = self.station(a[0])?;
                out.push(format!("INFO {} {} zone {} transfer {} {}",a[0],s.name,s.zone,s.transfer,if s.closed {
                    "closed"
                } else {
                    "open"
                }));
                let lines: Vec<_> = self.lines.iter().filter(|(_,l)|l.stops.iter().any(|s|s == a[0])).map(|(id,_)|id.clone()).collect();
                out.push(format!("LINES {}",if lines.is_empty() {
                    "none".into()
                } else {
                    lines.join(" ")
                }));
                let walks = self.neighbors(a[0]);
                out.push(format!("WALKS {}",if walks.is_empty() {
                    "none".into()
                } else {
                    walks.iter().map(|(s,t)|format!("{s} {t}")).collect::<Vec<_>>().join(" ")
                }));
            }
            "STATUS" => {
                out.push(format!("STATUS stations {} lines {} walks {}",self.stations.len(),self.lines.len(),self.walks.len()));
                for (s,station) in &self.stations {
                    if station.closed {
                        out.push(format!("CLOSED {s}"));
                    }
                }
                for (a,b) in &self.closed {
                    out.push(format!("CLOSED {a}-{b}"));
                }
                for (id,line) in &self.lines {
                    if line.suspended {
                        out.push(format!("SUSPENDED {id}"));
                    }
                }
                for (id,line) in &self.lines {
                    if line.delay != 0 {
                        out.push(format!("DELAYED {id} {}",line.delay));
                    }
                }
            }
            _ => unreachable!(),
        } Ok(out)
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let n: usize = lines.next().unwrap().parse().unwrap();
    let mut planner = Planner {
        stations:BTreeMap::new(),lines:BTreeMap::new(),walks:BTreeMap::new(),closed:BTreeSet::new(),tariff:None
    };
    for line in lines.take(n) {
        match planner.command(&line.split(' ').collect::<Vec<_>>()) {
            Ok(out) => for line in out {
                println!("{line}");
            }, Err(error) => println!("ERROR {error}")
        }
    }
}
