use std::collections::{BTreeMap, HashSet};
use std::io::{self, BufRead, Write};

const CLASSES: [char; 3] = ['F', 'J', 'Y'];
const TYPES: [&str; 3] = ["ADULT", "CHILD", "INFANT"];
const TIERS: [&str; 4] = ["PLATINUM", "GOLD", "SILVER", "NONE"];
struct Seat {
    row: usize,
    cabin: usize,
    block: usize,
    kind: usize,
    letter: u8,
}
#[derive(Clone, Default)]
struct Cabin {
    from: usize,
    to: usize,
    blocks: Vec<String>,
}
struct Aircraft {
    model: String,
    base: i32,
    limit: i32,
    cabins: [Cabin; 3],
    seats: Vec<Seat>,
    blocked: Vec<bool>,
    lookup: [Option<usize>; 2600],
    exits: [bool; 100],
    capacity: [usize; 3],
}
impl Aircraft {
    fn new() -> Self {
        Self {
            model: String::new(),
            base: 0,
            limit: 0,
            cabins: Default::default(),
            seats: Vec::new(),
            blocked: Vec::new(),
            lookup: [None; 2600],
            exits: [false; 100],
            capacity: [0; 3],
        }
    }
    fn seat_name(&self, seat: Option<usize>) -> String {
        seat.map_or_else(
            || "UNASSIGNED".to_owned(),
            |i| format!("{}{}", self.seats[i].row, self.seats[i].letter as char),
        )
    }
}
struct Flight {
    name: String,
    model: usize,
    closed: bool,
    limit: [usize; 3],
    blocked: Vec<bool>,
    occupants: Vec<Option<usize>>,
    passengers: Vec<usize>,
    volunteers: Vec<usize>,
}
struct Booking {
    pnr: String,
    flight: usize,
    checked: bool,
    people: Vec<usize>,
}
struct Person {
    name: String,
    booking: usize,
    kind: usize,
    preference: Option<usize>,
    cabin: usize,
    seat: Option<usize>,
    lap: Option<usize>,
    active: bool,
    volunteer: bool,
}
struct World {
    aircraft: Vec<Aircraft>,
    flights: Vec<Flight>,
    bookings: Vec<Booking>,
    people: Vec<Person>,
    model_ids: BTreeMap<String, usize>,
    flight_ids: BTreeMap<String, usize>,
    booking_ids: BTreeMap<String, usize>,
    tiers: BTreeMap<String, usize>,
    building: Aircraft,
}
fn number(s: &str) -> usize {
    s.parse().unwrap()
}
fn cabin_id(s: &str) -> usize {
    "FJY".find(s).unwrap()
}
fn seat_key(s: &str) -> usize {
    number(&s[..s.len() - 1]) * 26 + (s.as_bytes()[s.len() - 1] - b'A') as usize
}
impl World {
    fn tier(&self, id: usize) -> usize {
        self.tiers.get(&self.people[id].name).copied().unwrap_or(3)
    }
    fn flight_id(&self, name: &str, open: bool) -> Result<usize, String> {
        let &id = self
            .flight_ids
            .get(name)
            .ok_or_else(|| format!("unknown flight {name}"))?;
        if open && self.flights[id].closed {
            return Err(format!("flight {name} is closed"));
        }
        Ok(id)
    }
    fn active_count(&self, b: usize) -> usize {
        self.bookings[b]
            .people
            .iter()
            .filter(|&&i| self.people[i].active)
            .count()
    }
    fn booking_id(&self, pnr: &str, open: bool) -> Result<usize, String> {
        let id = self
            .booking_ids
            .get(pnr)
            .copied()
            .filter(|&i| self.active_count(i) > 0)
            .ok_or_else(|| format!("unknown PNR {pnr}"))?;
        if open && self.flights[self.bookings[id].flight].closed {
            return Err(format!(
                "flight {} is closed",
                self.flights[self.bookings[id].flight].name
            ));
        }
        Ok(id)
    }
    fn passenger_id(&self, b: usize, name: &str) -> Result<usize, String> {
        self.bookings[b]
            .people
            .iter()
            .copied()
            .find(|&i| self.people[i].active && self.people[i].name == name)
            .ok_or_else(|| format!("no passenger {name} in {}", self.bookings[b].pnr))
    }
    fn resolve(&self, pnr: &str, name: &str) -> Result<usize, String> {
        self.passenger_id(self.booking_id(pnr, true)?, name)
    }
    fn has_infant(&self, id: usize) -> bool {
        self.people[id].kind == 0 && self.people[id].lap.is_some_and(|i| self.people[i].active)
    }
    fn booking_infants(&self, b: usize) -> bool {
        self.bookings[b]
            .people
            .iter()
            .any(|&i| self.people[i].active && self.people[i].kind == 2)
    }
    fn booked_count(&self, f: usize, c: usize) -> usize {
        self.flights[f]
            .passengers
            .iter()
            .filter(|&&i| {
                self.people[i].active && self.people[i].kind != 2 && self.people[i].cabin == c
            })
            .count()
    }
    fn exit_allowed(&self, id: usize, plane: &Aircraft, target: usize) -> bool {
        !plane.exits[plane.seats[target].row] || self.people[id].kind == 0 && !self.has_infant(id)
    }
    fn infant_allowed(
        &self,
        f: usize,
        id: usize,
        target: usize,
        moving: &[usize],
        ids: &[usize],
        assigned: &[usize],
    ) -> bool {
        if !self.has_infant(id) {
            return true;
        }
        let plane = &self.aircraft[self.flights[f].model];
        let s = &plane.seats[target];
        for letter in plane.cabins[s.cabin].blocks[s.block].bytes() {
            let peer = plane.lookup[s.row * 26 + (letter - b'A') as usize].unwrap();
            if let Some(owner) = self.flights[f].occupants[peer] {
                if owner != id && !moving.contains(&owner) && self.has_infant(owner) {
                    return false;
                }
            }
        }
        for (&other, &seat) in ids.iter().zip(assigned) {
            let t = &plane.seats[seat];
            if other != id && self.has_infant(other) && t.row == s.row && t.block == s.block {
                return false;
            }
        }
        true
    }
    fn fits(&self, f: usize, ids: &[usize], assigned: &[usize], vacated: &[usize]) -> bool {
        let plane = &self.aircraft[self.flights[f].model];
        let mut moving = ids.to_vec();
        moving.extend_from_slice(vacated);
        for (&id, &target) in ids.iter().zip(assigned) {
            if self.flights[f].blocked[target]
                || self.flights[f].occupants[target].is_some_and(|owner| !moving.contains(&owner))
                || !self.exit_allowed(id, plane, target)
                || !self.infant_allowed(f, id, target, &moving, ids, assigned)
            {
                return false;
            }
        }
        true
    }
    fn choose_seat(&self, f: usize, id: usize, c: usize) -> Option<usize> {
        let plane = &self.aircraft[self.flights[f].model];
        let mut first = None;
        for (target, s) in plane.seats.iter().enumerate() {
            if s.cabin != c
                || self.flights[f].blocked[target]
                || self.flights[f].occupants[target].is_some()
                || !self.exit_allowed(id, plane, target)
                || !self.infant_allowed(f, id, target, &[], &[], &[])
            {
                continue;
            }
            if first.is_none() {
                first = Some(target);
            }
            if self.people[id].preference.is_none_or(|kind| kind == s.kind) {
                return Some(target);
            }
        }
        first
    }
    fn seat_person(&mut self, f: usize, id: usize, target: Option<usize>) {
        if let Some(old) = self.people[id].seat {
            self.flights[f].occupants[old] = None;
        }
        self.people[id].seat = target;
        if let Some(target) = target {
            self.flights[f].occupants[target] = Some(id);
        }
    }
    fn reassign(&mut self, f: usize) -> Vec<String> {
        let mut out = Vec::new();
        for position in 0..self.flights[f].passengers.len() {
            let id = self.flights[f].passengers[position];
            let p = &self.people[id];
            if !p.active || p.kind == 2 || p.seat.is_some() {
                continue;
            }
            if let Some(target) = self.choose_seat(f, id, p.cabin) {
                self.seat_person(f, id, Some(target));
                let p = &self.people[id];
                out.push(format!(
                    "REASSIGNED {} {} {}",
                    self.bookings[p.booking].pnr,
                    p.name,
                    self.aircraft[self.flights[f].model].seat_name(Some(target))
                ));
            }
        }
        out
    }
    fn remove_person(&mut self, id: usize) {
        if !self.people[id].active {
            return;
        }
        let (kind, lap) = (self.people[id].kind, self.people[id].lap);
        if let Some(lap) = lap {
            if kind == 0 {
                self.remove_person(lap);
            }
            if kind == 2 {
                self.people[lap].lap = None;
            }
        }
        self.seat_person(self.bookings[self.people[id].booking].flight, id, None);
        self.people[id].active = false;
        self.people[id].volunteer = false;
        self.people[id].lap = None;
    }
    fn passenger_result(&self, id: usize) -> String {
        let p = &self.people[id];
        if p.kind == 2 {
            "LAP".to_owned()
        } else {
            self.aircraft[self.flights[self.bookings[p.booking].flight].model].seat_name(p.seat)
        }
    }
    fn assign_booking(&mut self, f: usize, c: usize, ids: &[usize]) -> &'static str {
        if ids.len() == 1 {
            self.seat_person(f, ids[0], self.choose_seat(f, ids[0], c));
            return "SINGLE";
        }
        let model = self.flights[f].model;
        let cabin = self.aircraft[model].cabins[c].clone();
        let count = ids.len();
        for stage in 0..3 {
            let blocks = if stage == 1 {
                vec![cabin.blocks.concat()]
            } else {
                cabin.blocks.clone()
            };
            let heights = if stage == 2 { 2..=count } else { 1..=1 };
            for height in heights {
                let width = if stage == 2 {
                    count.div_ceil(height)
                } else {
                    count
                };
                let used_rows = count.div_ceil(width);
                for row in cabin.from..=cabin.to {
                    if row + used_rows - 1 > cabin.to {
                        break;
                    }
                    for block in &blocks {
                        if block.len() < width {
                            continue;
                        }
                        for x in 0..=block.len() - width {
                            let candidate: Vec<usize> = (0..count)
                                .map(|j| {
                                    self.aircraft[model].lookup[(row + j / width) * 26
                                        + (block.as_bytes()[x + j % width] - b'A') as usize]
                                        .unwrap()
                                })
                                .collect();
                            if !self.fits(f, ids, &candidate, &[]) {
                                continue;
                            }
                            for (&id, &seat) in ids.iter().zip(&candidate) {
                                self.seat_person(f, id, Some(seat));
                            }
                            return ["BLOCK", "ROW", "STACK"][stage];
                        }
                    }
                }
            }
        }
        for &id in ids {
            self.seat_person(f, id, self.choose_seat(f, id, c));
        }
        "SPLIT"
    }
    fn execute(&mut self, v: &[&str]) -> Result<Vec<String>, String> {
        let mut out = Vec::new();
        match v[0] {
            "AIRCRAFT" => {
                self.building = Aircraft::new();
                self.building.model = v[1].to_owned();
                self.building.base = number(v[2]) as i32;
                self.building.limit = number(v[3]) as i32;
            }
            "CABIN" => {
                let c = cabin_id(v[1]);
                let cabin = Cabin {
                    from: number(v[2]),
                    to: number(v[3]),
                    blocks: v[4..].iter().map(|s| (*s).to_owned()).collect(),
                };
                for row in cabin.from..=cabin.to {
                    for (b, block) in cabin.blocks.iter().enumerate() {
                        for (position, letter) in block.bytes().enumerate() {
                            let kind = if b == 0 && position == 0
                                || b + 1 == cabin.blocks.len() && position + 1 == block.len()
                            {
                                0
                            } else if position == 0 || position + 1 == block.len() {
                                2
                            } else {
                                1
                            };
                            self.building.lookup[row * 26 + (letter - b'A') as usize] =
                                Some(self.building.seats.len());
                            self.building.seats.push(Seat {
                                row,
                                cabin: c,
                                block: b,
                                kind,
                                letter,
                            });
                            self.building.blocked.push(false);
                        }
                    }
                }
                self.building.cabins[c] = cabin;
            }
            "EXIT" => {
                for value in &v[1..] {
                    self.building.exits[number(value)] = true;
                }
            }
            "BLOCKED" => {
                for value in &v[1..] {
                    self.building.blocked[self.building.lookup[seat_key(value)].unwrap()] = true;
                }
            }
            "END" => {
                for (i, seat) in self.building.seats.iter().enumerate() {
                    if !self.building.blocked[i] {
                        self.building.capacity[seat.cabin] += 1;
                    }
                }
                let mut line = format!("AIRCRAFT {}", self.building.model);
                for c in 0..3 {
                    if self.building.cabins[c].from > 0 {
                        line.push_str(&format!(" {} {}", CLASSES[c], self.building.capacity[c]));
                    }
                }
                let plane = std::mem::replace(&mut self.building, Aircraft::new());
                self.model_ids
                    .insert(plane.model.clone(), self.aircraft.len());
                self.aircraft.push(plane);
                out.push(line);
            }
            "FLIGHT" => {
                if self.flight_ids.contains_key(v[1]) {
                    return Err(format!("duplicate flight {}", v[1]));
                }
                let &model = self
                    .model_ids
                    .get(v[2])
                    .ok_or_else(|| format!("unknown aircraft {}", v[2]))?;
                let plane = &self.aircraft[model];
                let mut flight = Flight {
                    name: v[1].to_owned(),
                    model,
                    closed: false,
                    limit: [0; 3],
                    blocked: plane.blocked.clone(),
                    occupants: vec![None; plane.seats.len()],
                    passengers: Vec::new(),
                    volunteers: Vec::new(),
                };
                let mut line = format!("FLIGHT {} {}", flight.name, plane.model);
                for c in 0..3 {
                    flight.limit[c] = plane.capacity[c] * (100 + number(v[3])) / 100;
                    if plane.cabins[c].from > 0 {
                        line.push_str(&format!(
                            " {} {}/{}",
                            CLASSES[c], plane.capacity[c], flight.limit[c]
                        ));
                    }
                }
                self.flight_ids
                    .insert(flight.name.clone(), self.flights.len());
                self.flights.push(flight);
                out.push(line);
            }
            "BOOK" => {
                if self.booking_ids.contains_key(v[1]) {
                    return Err(format!("duplicate PNR {}", v[1]));
                }
                let (f, c) = (self.flight_id(v[2], true)?, cabin_id(v[3]));
                if self.aircraft[self.flights[f].model].cabins[c].from == 0 {
                    return Err(format!("no cabin {} on {}", v[3], v[2]));
                }
                let mut draft = Vec::new();
                let mut names = HashSet::new();
                let (mut adults, mut infants) = (Vec::new(), Vec::new());
                for item in &v[4..] {
                    let fields: Vec<&str> = item.split(':').collect();
                    if !names.insert(fields[0]) {
                        return Err(format!("duplicate name {} in {}", fields[0], v[1]));
                    }
                    let kind = TYPES.iter().position(|&s| s == fields[1]).unwrap();
                    let preference = fields.get(2).map(|s| "WMA".find(*s).unwrap());
                    if kind == 0 {
                        adults.push(draft.len());
                    }
                    if kind == 2 {
                        infants.push(draft.len());
                    }
                    draft.push(Person {
                        name: fields[0].to_owned(),
                        booking: self.bookings.len(),
                        kind,
                        preference,
                        cabin: c,
                        seat: None,
                        lap: None,
                        active: true,
                        volunteer: false,
                    });
                }
                for p in &draft {
                    if self.flights[f]
                        .passengers
                        .iter()
                        .any(|&id| self.people[id].active && self.people[id].name == p.name)
                    {
                        return Err(format!("{} already on {}", p.name, v[2]));
                    }
                }
                if adults.is_empty() {
                    return Err(format!("no adult in {}", v[1]));
                }
                if infants.len() > adults.len() {
                    return Err(format!("too many infants in {}", v[1]));
                }
                if self.booked_count(f, c) + draft.len() - infants.len() > self.flights[f].limit[c]
                {
                    return Err(format!("limit exceeded for {} {}", v[2], v[3]));
                }
                let base = self.people.len();
                for (i, &infant) in infants.iter().enumerate() {
                    draft[adults[i]].lap = Some(base + infant);
                    draft[infant].lap = Some(base + adults[i]);
                }
                let mut booking = Booking {
                    pnr: v[1].to_owned(),
                    flight: f,
                    checked: false,
                    people: Vec::new(),
                };
                let mut needs = Vec::new();
                for p in draft {
                    let id = self.people.len();
                    if p.kind != 2 {
                        needs.push(id);
                    }
                    self.people.push(p);
                    booking.people.push(id);
                    self.flights[f].passengers.push(id);
                }
                let b = self.bookings.len();
                self.booking_ids.insert(booking.pnr.clone(), b);
                self.bookings.push(booking);
                let method = self.assign_booking(f, c, &needs);
                let mut line = format!("BOOKED {} {} {} {method}", v[1], v[2], v[3]);
                for &id in &self.bookings[b].people {
                    line.push_str(&format!(
                        " {}:{}",
                        self.people[id].name,
                        self.passenger_result(id)
                    ));
                }
                out.push(line);
            }
            "STATUS" => {
                self.tiers.insert(
                    v[1].to_owned(),
                    TIERS.iter().position(|&s| s == v[2]).unwrap(),
                );
                out.push(format!("STATUS {} {}", v[1], v[2]));
            }
            "FIND" => {
                let membership = self.tiers.get(v[1]).copied().unwrap_or(3);
                let mut found = Vec::new();
                for f in &self.flights {
                    for &id in &f.passengers {
                        let p = &self.people[id];
                        if p.active && p.name == v[1] {
                            found.push(format!(
                                "{} {} {} {} {}",
                                f.name,
                                self.bookings[p.booking].pnr,
                                CLASSES[p.cabin],
                                self.passenger_result(id),
                                if f.closed { "CLOSED" } else { "OPEN" }
                            ));
                        }
                    }
                }
                out.push(format!(
                    "FIND {} {} {}",
                    v[1],
                    TIERS[membership],
                    found.len()
                ));
                out.extend(found);
            }
            "SEAT" => {
                let id = self.resolve(v[1], v[2])?;
                let p = &self.people[id];
                let f = self.bookings[p.booking].flight;
                let plane = &self.aircraft[self.flights[f].model];
                if p.kind == 2 {
                    return Err(format!("infant {} has no seat", p.name));
                }
                let target = plane.lookup[seat_key(v[3])]
                    .filter(|&seat| plane.seats[seat].cabin == p.cabin)
                    .ok_or_else(|| format!("no seat {} in cabin {}", v[3], CLASSES[p.cabin]))?;
                if self.flights[f].blocked[target] {
                    return Err(format!("seat {} is blocked", v[3]));
                }
                if self.flights[f].occupants[target].is_some() {
                    return Err(format!("seat {} is occupied", v[3]));
                }
                if !self.exit_allowed(id, plane, target) {
                    return Err(format!(
                        "exit row {} not allowed for {}",
                        plane.seats[target].row, p.name
                    ));
                }
                if !self.infant_allowed(f, id, target, &[], &[], &[]) {
                    return Err(format!("infant limit reached at {}", v[3]));
                }
                let old = plane.seat_name(p.seat);
                self.seat_person(f, id, Some(target));
                out.push(format!("MOVED {} {} {old} -> {}", v[1], v[2], v[3]));
                out.extend(self.reassign(f));
            }
            "SWAP" => {
                let first = self.resolve(v[1], v[2])?;
                let second = self.resolve(v[3], v[4])?;
                if first == second {
                    return Err(format!("cannot swap {} with itself", v[2]));
                }
                for id in [first, second] {
                    if self.people[id].kind == 2 {
                        return Err(format!("infant {} has no seat", self.people[id].name));
                    }
                }
                let f = self.bookings[self.people[first].booking].flight;
                if f != self.bookings[self.people[second].booking].flight {
                    return Err(format!("{} and {} are on different flights", v[1], v[3]));
                }
                if self.people[first].cabin != self.people[second].cabin {
                    return Err(format!("{} and {} are in different cabins", v[2], v[4]));
                }
                for id in [first, second] {
                    if self.people[id].seat.is_none() {
                        return Err(format!("{} has no seat", self.people[id].name));
                    }
                }
                let (old_first, old_second) = (
                    self.people[first].seat.unwrap(),
                    self.people[second].seat.unwrap(),
                );
                if !self.fits(f, &[first, second], &[old_second, old_first], &[]) {
                    return Err(format!(
                        "swap of {} and {} breaks seating rules",
                        v[2], v[4]
                    ));
                }
                self.flights[f].occupants[old_first] = None;
                self.flights[f].occupants[old_second] = None;
                self.people[first].seat = None;
                self.people[second].seat = None;
                self.seat_person(f, first, Some(old_second));
                self.seat_person(f, second, Some(old_first));
                let plane = &self.aircraft[self.flights[f].model];
                out.push(format!(
                    "SWAPPED {} {} {} {} {} {}",
                    v[1],
                    v[2],
                    plane.seat_name(Some(old_second)),
                    v[3],
                    v[4],
                    plane.seat_name(Some(old_first))
                ));
                out.extend(self.reassign(f));
            }
            "CANCEL" => {
                let b = self.booking_id(v[1], true)?;
                let target = if v.len() == 3 {
                    Some(self.passenger_id(b, v[2])?)
                } else {
                    None
                };
                let removed: Vec<usize> = self.bookings[b]
                    .people
                    .iter()
                    .copied()
                    .filter(|&id| {
                        self.people[id].active
                            && target.is_none_or(|t| {
                                id == t
                                    || self.people[t].kind == 0 && self.people[t].lap == Some(id)
                            })
                    })
                    .collect();
                let remaining: Vec<usize> = self.bookings[b]
                    .people
                    .iter()
                    .copied()
                    .filter(|&id| self.people[id].active && !removed.contains(&id))
                    .collect();
                if target.is_some()
                    && !remaining.is_empty()
                    && !remaining.iter().any(|&id| self.people[id].kind == 0)
                {
                    return Err(format!("{} would have no adult", v[1]));
                }
                let mut line = format!("CANCELLED {}", v[1]);
                for &id in &removed {
                    line.push_str(&format!(" {}", self.people[id].name));
                }
                for id in removed {
                    self.remove_person(id);
                }
                out.push(line);
                out.extend(self.reassign(self.bookings[b].flight));
            }
            "CHECKIN" | "VOLUNTEER" | "INFO" => {
                let b = self.booking_id(v[1], v[0] != "INFO")?;
                if v[0] == "CHECKIN" {
                    if self.bookings[b].checked {
                        return Err(format!("{} already checked in", v[1]));
                    }
                    self.bookings[b].checked = true;
                    out.push(format!("CHECKIN {} {}", v[1], self.active_count(b)));
                } else if v[0] == "INFO" {
                    let book = &self.bookings[b];
                    out.push(format!(
                        "INFO {} {} {} {}",
                        book.pnr,
                        self.flights[book.flight].name,
                        self.active_count(b),
                        if book.checked {
                            "CHECKED"
                        } else {
                            "NOT-CHECKED"
                        }
                    ));
                    for &id in &book.people {
                        let p = &self.people[id];
                        if p.active {
                            out.push(format!(
                                "{} {} {} {}",
                                p.name,
                                TYPES[p.kind],
                                CLASSES[p.cabin],
                                self.passenger_result(id)
                            ));
                        }
                    }
                } else {
                    let id = self.passenger_id(b, v[2])?;
                    let p = &self.people[id];
                    if p.kind != 0 || self.has_infant(id) {
                        return Err(format!("{} cannot volunteer", p.name));
                    }
                    if p.seat.is_none() {
                        return Err(format!("{} has no seat", p.name));
                    }
                    if p.volunteer {
                        return Err(format!("{} already volunteered", p.name));
                    }
                    self.people[id].volunteer = true;
                    self.flights[self.bookings[b].flight].volunteers.push(id);
                    out.push(format!(
                        "VOLUNTEER {} {} {}",
                        v[1],
                        v[2],
                        self.passenger_result(id)
                    ));
                }
            }
            _ => {
                let modifying = ["UPGRADE", "CLOSE", "BLOCK", "UNBLOCK"].contains(&v[0]);
                let f = self.flight_id(v[1], modifying)?;
                out.extend(self.flight_command(f, v)?);
            }
        }
        Ok(out)
    }
    fn flight_command(&mut self, f: usize, v: &[&str]) -> Result<Vec<String>, String> {
        let mut out = Vec::new();
        let model = self.flights[f].model;
        let name = self.flights[f].name.clone();
        match v[0] {
            "BLOCK" | "UNBLOCK" => {
                let target = self.aircraft[model].lookup[seat_key(v[2])]
                    .ok_or_else(|| format!("no seat {} on {name}", v[2]))?;
                if v[0] == "BLOCK" && self.flights[f].blocked[target] {
                    return Err(format!("seat {} is blocked", v[2]));
                }
                if v[0] == "UNBLOCK" && !self.flights[f].blocked[target] {
                    return Err(format!("seat {} is not blocked", v[2]));
                }
                self.flights[f].blocked[target] = v[0] == "BLOCK";
                out.push(format!("{} {name} {}", v[0], v[2]));
                if v[0] == "BLOCK" {
                    if let Some(id) = self.flights[f].occupants[target] {
                        self.seat_person(f, id, None);
                        let seat = self.choose_seat(f, id, self.people[id].cabin);
                        self.seat_person(f, id, seat);
                        out.push(format!(
                            "DISPLACED {} {} {} -> {}",
                            self.bookings[self.people[id].booking].pnr,
                            self.people[id].name,
                            v[2],
                            self.passenger_result(id)
                        ));
                    }
                }
                out.extend(self.reassign(f));
            }
            "UPGRADE" => {
                let cabins: Vec<usize> = (0..3)
                    .filter(|&c| self.aircraft[model].cabins[c].from > 0)
                    .collect();
                let mut upgraded = 0;
                for pair in cabins.windows(2) {
                    let (higher, lower) = (pair[0], pair[1]);
                    let mut booked = self.booked_count(f, higher);
                    let mut targets: Vec<(usize, usize)> = self.flights[f]
                        .passengers
                        .iter()
                        .copied()
                        .filter(|&id| {
                            let p = &self.people[id];
                            p.active
                                && p.cabin == lower
                                && p.kind == 0
                                && !self.has_infant(id)
                                && self.tier(id) < 3
                        })
                        .map(|id| (self.tier(id), id))
                        .collect();
                    targets.sort_by_key(|t| t.0);
                    for (_, id) in targets {
                        if booked >= self.flights[f].limit[higher] {
                            break;
                        }
                        let Some(target) = self.choose_seat(f, id, higher) else {
                            break;
                        };
                        let old = self.passenger_result(id);
                        self.people[id].cabin = higher;
                        self.seat_person(f, id, Some(target));
                        booked += 1;
                        upgraded += 1;
                        out.push(format!(
                            "UPGRADED {} {} {} {old} -> {} {}",
                            self.bookings[self.people[id].booking].pnr,
                            self.people[id].name,
                            CLASSES[lower],
                            CLASSES[higher],
                            self.aircraft[model].seat_name(Some(target))
                        ));
                    }
                }
                out.extend(self.reassign(f));
                out.push(format!("UPGRADE {name} {upgraded}"));
            }
            "CLOSE" => {
                for b in 0..self.bookings.len() {
                    if self.bookings[b].flight != f
                        || self.bookings[b].checked
                        || self.active_count(b) == 0
                    {
                        continue;
                    }
                    out.push(format!(
                        "NOSHOW {} {}",
                        self.bookings[b].pnr,
                        self.active_count(b)
                    ));
                    for position in 0..self.bookings[b].people.len() {
                        let id = self.bookings[b].people[position];
                        self.remove_person(id);
                    }
                }
                out.extend(self.reassign(f));
                let (mut denied, mut compensation) = (0, 0);
                let voluntary = [500, 300, 150];
                let involuntary = [1000, 600, 300];
                for c in 0..3 {
                    let targets: Vec<usize> = self.flights[f]
                        .volunteers
                        .iter()
                        .copied()
                        .filter(|&id| {
                            let p = &self.people[id];
                            p.active && p.volunteer && p.seat.is_some() && p.cabin == c
                        })
                        .collect();
                    for id in targets {
                        let target = self.people[id].seat.unwrap();
                        let useful = self.flights[f].passengers.iter().copied().any(|other| {
                            let p = &self.people[other];
                            p.active
                                && p.kind != 2
                                && p.cabin == c
                                && p.seat.is_none()
                                && self.fits(f, &[other], &[target], &[id])
                        });
                        if !useful {
                            continue;
                        }
                        out.push(format!(
                            "DENIED VOLUNTARY {} {} {} {}",
                            self.bookings[self.people[id].booking].pnr,
                            self.people[id].name,
                            CLASSES[c],
                            voluntary[c]
                        ));
                        denied += 1;
                        compensation += voluntary[c];
                        self.remove_person(id);
                        out.extend(self.reassign(f));
                    }
                }
                for position in 0..self.flights[f].passengers.len() {
                    let id = self.flights[f].passengers[position];
                    let p = &self.people[id];
                    if !p.active || p.kind == 2 || p.seat.is_some() {
                        continue;
                    }
                    let value = involuntary[p.cabin] / if p.kind == 1 { 2 } else { 1 };
                    out.push(format!(
                        "DENIED INVOLUNTARY {} {} {} {value}",
                        self.bookings[p.booking].pnr, p.name, CLASSES[p.cabin]
                    ));
                    denied += 1;
                    compensation += value;
                    self.remove_person(id);
                }
                self.flights[f].closed = true;
                out.push(format!(
                    "CLOSED {name} denied {denied} compensation {compensation}"
                ));
            }
            "MAP" => {
                out.push(format!("MAP {name}"));
                let plane = &self.aircraft[model];
                for c in 0..3 {
                    let cabin = &plane.cabins[c];
                    if cabin.from == 0 {
                        continue;
                    }
                    out.push(format!("CABIN {}", CLASSES[c]));
                    out.push(format!("   {}", cabin.blocks.join(" ")));
                    for row in cabin.from..=cabin.to {
                        let mut line = format!("{row:2} ");
                        for (b, block) in cabin.blocks.iter().enumerate() {
                            if b > 0 {
                                line.push(' ');
                            }
                            for letter in block.bytes() {
                                let target =
                                    plane.lookup[row * 26 + (letter - b'A') as usize].unwrap();
                                line.push(if self.flights[f].blocked[target] {
                                    '#'
                                } else if self.flights[f].occupants[target].is_some() {
                                    'X'
                                } else if plane.exits[row] {
                                    'E'
                                } else {
                                    '.'
                                });
                            }
                        }
                        out.push(line);
                    }
                }
            }
            "MANIFEST" => {
                let mut order: Vec<usize> = self.flights[f]
                    .occupants
                    .iter()
                    .flatten()
                    .copied()
                    .collect();
                let seated = order.len();
                let (mut unassigned, mut infants) = (0, 0);
                for &id in &self.flights[f].passengers {
                    let p = &self.people[id];
                    if !p.active {
                        continue;
                    }
                    if p.kind == 2 {
                        infants += 1;
                    } else if p.seat.is_none() {
                        unassigned += 1;
                        order.push(id);
                    }
                }
                out.push(format!(
                    "MANIFEST {name} seated {seated} unassigned {unassigned} infants {infants}"
                ));
                for id in order {
                    let p = &self.people[id];
                    let b = &self.bookings[p.booking];
                    let position = if p.seat.is_some() {
                        self.aircraft[model].seat_name(p.seat)
                    } else {
                        "---".to_owned()
                    };
                    let mut line = format!(
                        "{position} {} {} {} {}",
                        CLASSES[p.cabin], b.pnr, p.name, TYPES[p.kind]
                    );
                    if self.has_infant(id) {
                        line.push_str(&format!(" +{}", self.people[p.lap.unwrap()].name));
                    }
                    if self.tier(id) < 3 {
                        line.push_str(&format!(" {}", TIERS[self.tier(id)]));
                    }
                    if b.checked {
                        line.push_str(" CHECKED");
                    }
                    if p.volunteer {
                        line.push_str(" VOL");
                    }
                    out.push(line);
                }
            }
            "LOADFACTOR" => {
                out.push(format!("LOADFACTOR {name}"));
                let (mut all_seated, mut all_seats) = (0, 0);
                for c in 0..3 {
                    if self.aircraft[model].cabins[c].from == 0 {
                        continue;
                    }
                    let (mut seats, mut seated) = (0, 0);
                    for (i, s) in self.aircraft[model].seats.iter().enumerate() {
                        if s.cabin != c {
                            continue;
                        }
                        seats += usize::from(!self.flights[f].blocked[i]);
                        seated += usize::from(self.flights[f].occupants[i].is_some());
                    }
                    let factor = seated * 1000 / seats;
                    out.push(format!(
                        "{} {seated}/{seats} {}.{}% booked {}/{}",
                        CLASSES[c],
                        factor / 10,
                        factor % 10,
                        self.booked_count(f, c),
                        self.flights[f].limit[c]
                    ));
                    all_seated += seated;
                    all_seats += seats;
                }
                let factor = all_seated * 1000 / all_seats;
                out.push(format!(
                    "ALL {all_seated}/{all_seats} {}.{}%",
                    factor / 10,
                    factor % 10
                ));
            }
            "BALANCE" => {
                let (mut weight, mut moment) = (0i32, 0i32);
                for &id in self.flights[f].occupants.iter().flatten() {
                    let p = &self.people[id];
                    let value = (if p.kind == 0 { 80 } else { 40 })
                        + (if self.has_infant(id) { 10 } else { 0 });
                    weight += value;
                    moment += value
                        * (self.aircraft[model].seats[p.seat.unwrap()].row as i32
                            - self.aircraft[model].base);
                }
                let limit = self.aircraft[model].limit;
                let verdict = if moment < -limit {
                    "NOSE-HEAVY"
                } else if moment > limit {
                    "TAIL-HEAVY"
                } else {
                    "OK"
                };
                out.push(format!(
                    "BALANCE {name} weight {weight} moment {moment} limit {limit} {verdict}"
                ));
            }
            "BOARDING" => {
                struct Item {
                    id: usize,
                    group: usize,
                    zone: usize,
                    kind: usize,
                    row: usize,
                    letter: u8,
                }
                let mut order = Vec::new();
                for &id in self.flights[f].occupants.iter().flatten() {
                    let p = &self.people[id];
                    let s = &self.aircraft[model].seats[p.seat.unwrap()];
                    let group = if self.booking_infants(p.booking) {
                        0
                    } else if p.cabin < 2 {
                        1
                    } else if self.tier(id) < 2 {
                        2
                    } else {
                        3
                    };
                    let zone = if group == 3 {
                        (s.row - self.aircraft[model].cabins[2].from) / 5 + 1
                    } else {
                        0
                    };
                    order.push(Item {
                        id,
                        group,
                        zone,
                        kind: s.kind,
                        row: s.row,
                        letter: s.letter,
                    });
                }
                order.sort_by(|x, y| {
                    x.group
                        .cmp(&y.group)
                        .then_with(|| {
                            if x.group == 3 {
                                y.zone
                                    .cmp(&x.zone)
                                    .then(x.kind.cmp(&y.kind))
                                    .then(y.row.cmp(&x.row))
                            } else {
                                x.row.cmp(&y.row)
                            }
                        })
                        .then(x.letter.cmp(&y.letter))
                });
                out.push(format!("BOARDING {name} {}", order.len()));
                for (i, item) in order.iter().enumerate() {
                    let p = &self.people[item.id];
                    let group = if item.group == 3 {
                        format!("ZONE{}", item.zone)
                    } else {
                        ["PRE", "CABIN", "TIER"][item.group].to_owned()
                    };
                    out.push(format!(
                        "{} {group} {} {} {}",
                        i + 1,
                        self.aircraft[model].seat_name(p.seat),
                        self.bookings[p.booking].pnr,
                        p.name
                    ));
                }
            }
            "AVAIL" => {
                let c = cabin_id(v[2]);
                if self.aircraft[model].cabins[c].from == 0 {
                    return Err(format!("no cabin {} on {name}", v[2]));
                }
                let (mut free, mut exits) = (0, 0);
                let mut kinds = [0; 3];
                for (i, s) in self.aircraft[model].seats.iter().enumerate() {
                    if s.cabin != c
                        || self.flights[f].blocked[i]
                        || self.flights[f].occupants[i].is_some()
                    {
                        continue;
                    }
                    free += 1;
                    kinds[s.kind] += 1;
                    exits += usize::from(self.aircraft[model].exits[s.row]);
                }
                out.push(format!(
                    "AVAIL {name} {} free {free} W {} M {} A {} EXIT {exits}",
                    CLASSES[c], kinds[0], kinds[1], kinds[2]
                ));
            }
            _ => unreachable!(),
        }
        Ok(out)
    }
}
fn main() {
    let mut world = World {
        aircraft: Vec::new(),
        flights: Vec::new(),
        bookings: Vec::new(),
        people: Vec::new(),
        model_ids: BTreeMap::new(),
        flight_ids: BTreeMap::new(),
        booking_ids: BTreeMap::new(),
        tiers: BTreeMap::new(),
        building: Aircraft::new(),
    };
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let count: usize = lines.next().unwrap().unwrap().parse().unwrap();
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    for line in lines.take(count) {
        let line = line.unwrap();
        let values: Vec<&str> = line.split(' ').collect();
        let result = world
            .execute(&values)
            .unwrap_or_else(|message| vec![format!("ERROR {message}")]);
        for line in result {
            writeln!(output, "{line}").unwrap();
        }
    }
}
