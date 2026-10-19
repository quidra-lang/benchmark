use std::collections::{BTreeMap, HashMap, HashSet};
use std::io::{self, Read};

const TYPES: [&str; 3] = ["SINGLE", "DOUBLE", "SUITE"];
const WEEKDAYS: [&str; 7] = ["SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI"];

fn leap(year: i32) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

fn month_lengths(year: i32) -> [i32; 12] {
    [31, if leap(year) { 29 } else { 28 }, 31, 30, 31, 30,
     31, 31, 30, 31, 30, 31]
}

fn date_number(text: &str) -> Result<i32, String> {
    let year: i32 = text[0..4].parse().unwrap_or(0);
    let month: i32 = text[5..7].parse().unwrap_or(0);
    let day: i32 = text[8..10].parse().unwrap_or(0);
    if !(2000..=2099).contains(&year) || !(1..=12).contains(&month) {
        return Err(format!("invalid date {text}"));
    }
    let lengths = month_lengths(year);
    if day < 1 || day > lengths[(month - 1) as usize] {
        return Err(format!("invalid date {text}"));
    }
    let mut number = 0;
    for previous in 2000..year {
        number += if leap(previous) { 366 } else { 365 };
    }
    for previous in 0..(month - 1) as usize {
        number += lengths[previous];
    }
    Ok(number + day - 1)
}

fn date_text(mut number: i32) -> String {
    let mut year = 2000;
    loop {
        let days = if leap(year) { 366 } else { 365 };
        if number < days {
            break;
        }
        number -= days;
        year += 1;
    }
    let lengths = month_lengths(year);
    let mut month = 0;
    while number >= lengths[month] {
        number -= lengths[month];
        month += 1;
    }
    format!("{year:04}-{:02}-{:02}", month + 1, number + 1)
}

fn date_weekday(number: i32) -> String {
    format!("{} {}", date_text(number), WEEKDAYS[number.rem_euclid(7) as usize])
}

fn cents(text: &str) -> i64 {
    let (whole, fractional) = text.split_once('.').unwrap();
    whole.parse::<i64>().unwrap() * 100 + fractional.parse::<i64>().unwrap()
}

fn money(amount: i64) -> String {
    format!("{}.{:02}", amount / 100, amount % 100)
}

#[derive(Clone)]
struct Room {
    number: i32,
    kind: String,
    rate: i64,
    clean: bool,
}

#[derive(Clone)]
struct Season {
    first: i32,
    last: i32,
    percentage: i64,
}

#[derive(Clone)]
struct Night {
    day: i32,
    room: i32,
    rate: i64,
}

#[derive(Clone, Copy)]
struct Bill {
    lodging: i64,
    discount: i64,
    penalty: i64,
    extras: i64,
    tax: i64,
    total: i64,
}

#[derive(Clone)]
struct Reservation {
    id: String,
    guest: String,
    room: i32,
    arrival: i32,
    departure: i32,
    nights: Vec<Night>,
    status: String,
    extras: Vec<(String, i64)>,
    deposit: i64,
    paid: i64,
    posting: Option<i32>,
    fee: i64,
    penalty: Option<(i32, i64)>,
    bill: Option<Bill>,
}

impl Reservation {
    fn lodging(&self) -> i64 {
        self.nights.iter().map(|night| night.rate).sum()
    }

    fn first_rate(&self) -> i64 {
        self.nights[0].rate
    }
}

#[derive(Clone)]
struct Waiting {
    id: String,
    guest: String,
    kind: String,
    arrival: i32,
    departure: i32,
}

struct HotelDesk {
    today: i32,
    rooms: BTreeMap<i32, Room>,
    seasons: Vec<Season>,
    blocks: HashSet<(i32, i32)>,
    occupied: HashMap<(i32, i32), (String, i64)>,
    reservations: BTreeMap<String, Reservation>,
    order: Vec<String>,
    waitlist: Vec<Waiting>,
    used_ids: HashSet<String>,
    output: Vec<String>,
}

impl HotelDesk {
    fn new() -> Self {
        Self {
            today: date_number("2026-01-01").unwrap(),
            rooms: BTreeMap::new(),
            seasons: Vec::new(),
            blocks: HashSet::new(),
            occupied: HashMap::new(),
            reservations: BTreeMap::new(),
            order: Vec::new(),
            waitlist: Vec::new(),
            used_ids: HashSet::new(),
            output: Vec::new(),
        }
    }

    fn emit(&mut self, line: String, indent: bool) {
        self.output.push(if indent { format!("  {line}") } else { line });
    }

    fn require_room(&self, number: i32) -> Result<&Room, String> {
        self.rooms.get(&number).ok_or_else(|| format!("unknown room {number}"))
    }

    fn require_type(&self, kind: &str) -> Result<(), String> {
        if TYPES.contains(&kind) {
            Ok(())
        } else {
            Err(format!("invalid type {kind}"))
        }
    }

    fn require_unused(&self, id: &str) -> Result<(), String> {
        if self.used_ids.contains(id) {
            Err(format!("duplicate reservation {id}"))
        } else {
            Ok(())
        }
    }

    fn reservation(&self, id: &str, expected: Option<&str>) -> Result<&Reservation, String> {
        let reservation = self.reservations.get(id)
            .ok_or_else(|| format!("unknown reservation {id}"))?;
        if let Some(status) = expected {
            if reservation.status != status {
                return Err(format!("invalid status {id} {}", reservation.status));
            }
        }
        Ok(reservation)
    }

    fn stay(&self, first: &str, last: &str) -> Result<(i32, i32), String> {
        let arrival = date_number(first)?;
        let departure = date_number(last)?;
        if arrival < self.today {
            return Err(format!("past date {first}"));
        }
        if departure <= arrival {
            return Err(format!("invalid range {first} {last}"));
        }
        if departure - arrival > 30 {
            return Err(format!("too long {}", departure - arrival));
        }
        Ok((arrival, departure))
    }

    fn period(&self, first: &str, last: &str, restrict_past: bool,
              limit: bool) -> Result<(i32, i32), String> {
        let start = date_number(first)?;
        let end = date_number(last)?;
        if restrict_past && start < self.today {
            return Err(format!("past date {first}"));
        }
        if end < start {
            return Err(format!("invalid range {first} {last}"));
        }
        if limit && end - start + 1 > 31 {
            return Err(format!("too long {}", end - start + 1));
        }
        Ok((start, end))
    }

    fn night_rate(&self, room: &Room, day: i32) -> i64 {
        let percentage = self.seasons.iter().rev()
            .find(|s| s.first <= day && day <= s.last)
            .map_or(100, |s| s.percentage);
        room.rate * percentage / 100
    }

    fn price(&self, room: &Room, arrival: i32, departure: i32) -> Vec<Night> {
        (arrival..departure).map(|day| Night {
            day,
            room: room.number,
            rate: self.night_rate(room, day),
        }).collect()
    }

    fn first_unavailable(&self, room: i32, arrival: i32, departure: i32,
                         except_for: Option<&str>) -> Option<i32> {
        (arrival..departure).find(|day| {
            let key = (*day, room);
            self.blocks.contains(&key) ||
                self.occupied.get(&key)
                    .is_some_and(|(id, _)| Some(id.as_str()) != except_for)
        })
    }

    fn free_room(&self, kind: &str, arrival: i32, departure: i32,
                 except_for: Option<&str>) -> Option<i32> {
        self.rooms.iter()
            .find(|(number, room)| room.kind == kind &&
                  self.first_unavailable(**number, arrival, departure, except_for).is_none())
            .map(|(number, _)| *number)
    }

    fn inhouse(&self, room: i32) -> Option<&Reservation> {
        self.reservations.values()
            .find(|reservation| reservation.status == "inhouse" && reservation.room == room)
    }

    fn occupy(&mut self, id: &str, nights: &[Night]) {
        for night in nights {
            self.occupied.insert((night.day, night.room), (id.to_string(), night.rate));
        }
    }

    fn release(&mut self, nights: &[Night], first: Option<i32>) {
        for night in nights {
            if first.is_none_or(|day| night.day >= day) {
                self.occupied.remove(&(night.day, night.room));
            }
        }
    }

    fn create_reservation(&mut self, id: &str, guest: &str, room_number: i32,
                          arrival: i32, departure: i32, indent: bool) {
        let room = self.rooms[&room_number].clone();
        let nights = self.price(&room, arrival, departure);
        let total: i64 = nights.iter().map(|night| night.rate).sum();
        let reservation = Reservation {
            id: id.to_string(),
            guest: guest.to_string(),
            room: room_number,
            arrival,
            departure,
            nights: nights.clone(),
            status: "booked".into(),
            extras: Vec::new(),
            deposit: 0,
            paid: 0,
            posting: None,
            fee: 0,
            penalty: None,
            bill: None,
        };
        self.reservations.insert(id.to_string(), reservation);
        self.order.push(id.to_string());
        self.used_ids.insert(id.to_string());
        self.occupy(id, &nights);
        self.emit(format!(
            "BOOK {id} {guest} room {} {} {} -> {} nights {} total {}",
            room.number, room.kind, date_text(arrival), date_text(departure),
            departure - arrival, money(total)
        ), indent);
    }

    fn guest_total(&self, guest: &str) -> i64 {
        self.reservations.values()
            .filter(|r| r.guest == guest)
            .map(|r| r.paid)
            .sum()
    }

    fn tier(&self, guest: &str) -> &'static str {
        let points = self.guest_total(guest) / 100;
        if points >= 2000 {
            "GOLD"
        } else if points >= 500 {
            "SILVER"
        } else {
            "BRONZE"
        }
    }

    fn calculate_bill(&self, reservation: &Reservation) -> Bill {
        let lodging = reservation.lodging();
        let percentage = match self.tier(&reservation.guest) {
            "GOLD" => 10,
            "SILVER" => 5,
            _ => 0,
        };
        let discount = lodging * percentage / 100;
        let penalty = reservation.penalty.map_or(0, |(_, rate)| rate);
        let extras: i64 = reservation.extras.iter().map(|(_, amount)| amount).sum();
        let subtotal = lodging - discount + penalty + extras;
        let tax = subtotal / 10;
        Bill {
            lodging, discount, penalty, extras, tax, total: subtotal + tax,
        }
    }

    fn deposit_parts(reservation: &Reservation, total: i64) -> String {
        if total >= reservation.deposit {
            format!("deposit {} due {}", money(reservation.deposit),
                    money(total - reservation.deposit))
        } else {
            format!("deposit {} refund {}", money(reservation.deposit),
                    money(reservation.deposit - total))
        }
    }

    fn check_out(&mut self, id: &str, day: i32, indent: bool) {
        let mut reservation = self.reservations[id].clone();
        if day < reservation.departure {
            let rate = reservation.nights.iter().find(|night| night.day == day)
                .expect("early departure must have a priced night").rate;
            reservation.penalty = Some((day, rate));
            self.release(&reservation.nights, Some(day));
            reservation.nights.retain(|night| night.day < day);
            reservation.departure = day;
        }
        let bill = self.calculate_bill(&reservation);
        reservation.bill = Some(bill);
        reservation.paid = bill.total;
        reservation.status = "checkedout".into();
        reservation.posting = Some(day);
        self.rooms.get_mut(&reservation.room).unwrap().clean = false;
        self.emit(format!(
            "CHECKOUT {id} nights {} lodging {} discount {} penalty {} extras {} tax {} total {} {}",
            reservation.nights.len(), money(bill.lodging), money(bill.discount),
            money(bill.penalty), money(bill.extras), money(bill.tax),
            money(bill.total), Self::deposit_parts(&reservation, bill.total)
        ), indent);
        self.reservations.insert(id.to_string(), reservation);
    }

    fn process_waitlist(&mut self) {
        let entries = std::mem::take(&mut self.waitlist);
        let mut remaining = Vec::new();
        for entry in entries {
            if entry.arrival < self.today {
                self.emit(format!("WAITLIST {} expired", entry.id), true);
            } else if let Some(room) = self.free_room(&entry.kind, entry.arrival,
                                                       entry.departure, None) {
                self.create_reservation(&entry.id, &entry.guest, room,
                                        entry.arrival, entry.departure, true);
            } else {
                remaining.push(entry);
            }
        }
        self.waitlist = remaining;
    }

    fn occupancy_parts(&self, room_numbers: &[i32], day: i32) -> String {
        let blocked = room_numbers.iter()
            .filter(|number| self.blocks.contains(&(day, **number))).count();
        let occupied = room_numbers.iter()
            .filter(|number| self.occupied.contains_key(&(day, **number))).count();
        let available = room_numbers.len() - blocked;
        let rate = if available > 0 {
            format!("{}%", occupied * 100 / available)
        } else {
            "n/a".into()
        };
        format!("rooms {} blocked {blocked} occupied {occupied} rate {rate}",
                room_numbers.len())
    }

    fn daily_values(&self, day: i32) -> (i64, i64, i64) {
        let available = self.rooms.len() as i64 -
            self.rooms.keys().filter(|n| self.blocks.contains(&(day, **n))).count() as i64;
        let mut occupied = 0;
        let mut revenue = 0;
        for number in self.rooms.keys() {
            if let Some((_, rate)) = self.occupied.get(&(day, *number)) {
                occupied += 1;
                revenue += rate;
            }
        }
        (available, occupied, revenue)
    }

    fn metrics_parts(available: i64, occupied: i64, revenue: i64) -> String {
        let rate = if available > 0 {
            format!("{}%", occupied * 100 / available)
        } else { "n/a".into() };
        let adr = if occupied > 0 {
            money(revenue / occupied)
        } else { "n/a".into() };
        let revpar = if available > 0 {
            money(revenue / available)
        } else { "n/a".into() };
        format!("sold {occupied}/{available} rate {rate} revenue {} adr {adr} revpar {revpar}",
                money(revenue))
    }

    fn command(&mut self, words: &[&str]) -> Result<(), String> {
        let a = &words[1..];
        match words[0] {
            "ROOM" => {
                let number: i32 = a[0].parse().unwrap();
                if self.rooms.contains_key(&number) {
                    return Err(format!("duplicate room {number}"));
                }
                self.require_type(a[1])?;
                let rate = cents(a[2]);
                self.rooms.insert(number, Room {
                    number, kind: a[1].into(), rate, clean: true,
                });
                self.emit(format!("ROOM {number} {} {}", a[1], money(rate)), false);
            }
            "RATE" => {
                let number: i32 = a[0].parse().unwrap();
                let room = self.require_room(number)?.clone();
                let new_rate = cents(a[1]);
                self.rooms.get_mut(&number).unwrap().rate = new_rate;
                self.emit(format!("RATE {number} {} -> {}", money(room.rate),
                                  money(new_rate)), false);
            }
            "SEASON" => {
                let (start, end) = self.period(a[0], a[1], false, false)?;
                let percentage = a[2].parse::<i64>().unwrap();
                self.seasons.push(Season { first: start, last: end, percentage });
                self.emit(format!("SEASON {} {} -> {} {}%",
                                  self.seasons.len(), a[0], a[1], percentage), false);
            }
            "BLOCK" | "UNBLOCK" => {
                let number: i32 = a[0].parse().unwrap();
                self.require_room(number)?;
                let (start, end) = self.period(a[1], a[2], true, true)?;
                if words[0] == "BLOCK" {
                    for day in start..=end {
                        if self.occupied.contains_key(&(day, number)) {
                            return Err(format!("room unavailable {number} {}", date_text(day)));
                        }
                    }
                    let mut added = 0;
                    for day in start..=end {
                        if self.blocks.insert((day, number)) {
                            added += 1;
                        }
                    }
                    self.emit(format!("BLOCK {number} {} -> {} added {added}",
                                      a[1], a[2]), false);
                } else {
                    let mut removed = 0;
                    for day in start..=end {
                        if self.blocks.remove(&(day, number)) {
                            removed += 1;
                        }
                    }
                    self.emit(format!("UNBLOCK {number} {} -> {} removed {removed}",
                                      a[1], a[2]), false);
                }
            }
            "CLEAN" => {
                let number: i32 = a[0].parse().unwrap();
                let room = self.require_room(number)?;
                if room.clean {
                    return Err(format!("already clean {number}"));
                }
                self.rooms.get_mut(&number).unwrap().clean = true;
                self.emit(format!("CLEAN {number}"), false);
            }
            "TODAY" => {
                let day = date_number(a[0])?;
                if day < self.today {
                    return Err(format!("past date {}", a[0]));
                }
                self.emit(format!("TODAY {}", date_weekday(day)), false);
                let mut departing: Vec<(i32, String)> = self.reservations.values()
                    .filter(|r| r.status == "inhouse" && r.departure < day)
                    .map(|r| (r.departure, r.id.clone())).collect();
                departing.sort();
                for (departure, id) in departing {
                    self.check_out(&id, departure, true);
                }
                let mut absent: Vec<(i32, String)> = self.reservations.values()
                    .filter(|r| r.status == "booked" && r.arrival < day)
                    .map(|r| (r.arrival, r.id.clone())).collect();
                absent.sort();
                for (_, id) in absent {
                    let mut reservation = self.reservations[&id].clone();
                    self.release(&reservation.nights, None);
                    reservation.fee = reservation.first_rate();
                    reservation.paid = reservation.fee;
                    reservation.status = "noshow".into();
                    reservation.posting = Some(reservation.arrival);
                    self.emit(format!(
                        "NOSHOW {} {} fee {} {}",
                        id, reservation.guest, money(reservation.fee),
                        Self::deposit_parts(&reservation, reservation.fee)
                    ), true);
                    self.reservations.insert(id, reservation);
                }
                self.today = day;
            }
            "BOOK" | "BOOKROOM" | "WAITLIST" => {
                self.require_unused(a[0])?;
                let is_room = words[0] == "BOOKROOM";
                let requested_room = if is_room {
                    Some(self.require_room(a[2].parse().unwrap())?.clone())
                } else {
                    self.require_type(a[2])?;
                    None
                };
                let (arrival, departure) = self.stay(a[3], a[4])?;
                if let Some(room) = requested_room {
                    if let Some(day) = self.first_unavailable(room.number, arrival, departure, None) {
                        return Err(format!("room unavailable {} {}", room.number, date_text(day)));
                    }
                    self.create_reservation(a[0], a[1], room.number, arrival, departure, false);
                } else if let Some(room) = self.free_room(a[2], arrival, departure, None) {
                    self.create_reservation(a[0], a[1], room, arrival, departure, false);
                } else if words[0] == "BOOK" {
                    return Err(format!("no availability {} {} {}", a[2], a[3], a[4]));
                } else {
                    self.waitlist.push(Waiting {
                        id: a[0].into(), guest: a[1].into(), kind: a[2].into(),
                        arrival, departure,
                    });
                    self.used_ids.insert(a[0].to_string());
                    self.emit(format!("WAITLIST {} queued position {}", a[0], self.waitlist.len()),
                              false);
                }
            }
            "MODIFY" => {
                let old = self.reservation(a[0], Some("booked"))?.clone();
                let (arrival, departure) = self.stay(a[1], a[2])?;
                let current = self.require_room(old.room)?.clone();
                let (room, choice) = if self.first_unavailable(current.number, arrival,
                                                                 departure, Some(a[0])).is_none() {
                    (current.number, "kept")
                } else if let Some(other) = self.free_room(&current.kind, arrival,
                                                           departure, Some(a[0])) {
                    (other, "reassigned")
                } else {
                    return Err(format!("no availability {} {} {}", current.kind, a[1], a[2]));
                };
                let nights = self.price(self.require_room(room)?, arrival, departure);
                self.release(&old.nights, None);
                let mut updated = old;
                updated.room = room;
                updated.arrival = arrival;
                updated.departure = departure;
                updated.nights = nights.clone();
                self.occupy(a[0], &nights);
                self.emit(format!(
                    "MODIFY {} room {room} {choice} {} -> {} nights {} total {}",
                    a[0], a[1], a[2], departure - arrival, money(updated.lodging())
                ), false);
                self.reservations.insert(a[0].to_string(), updated);
            }
            "CANCEL" => {
                if let Some(position) = self.waitlist.iter().position(|e| e.id == a[0]) {
                    self.waitlist.remove(position);
                    self.emit(format!("CANCEL {} waitlist removed", a[0]), false);
                } else {
                    let mut reservation = self.reservation(a[0], Some("booked"))?.clone();
                    let days = reservation.arrival - self.today;
                    let first_rate = reservation.first_rate();
                    let fee = if days >= 7 {
                        0
                    } else if days >= 1 {
                        first_rate / 2
                    } else {
                        first_rate
                    };
                    self.release(&reservation.nights, None);
                    reservation.fee = fee;
                    reservation.paid = fee;
                    reservation.status = "cancelled".into();
                    reservation.posting = Some(self.today);
                    self.emit(format!(
                        "CANCEL {} days {days} fee {} {}",
                        a[0], money(fee), Self::deposit_parts(&reservation, fee)
                    ), false);
                    self.reservations.insert(a[0].to_string(), reservation);
                }
            }
            "CHECKIN" => {
                let reservation = self.reservation(a[0], Some("booked"))?.clone();
                if reservation.arrival != self.today {
                    return Err(format!("not arrival date {} {}",
                                       a[0], date_text(reservation.arrival)));
                }
                if let Some(occupant) = self.inhouse(reservation.room) {
                    return Err(format!("room occupied {} {}", reservation.room, occupant.id));
                }
                if !self.require_room(reservation.room)?.clean {
                    return Err(format!("room dirty {}", reservation.room));
                }
                self.reservations.get_mut(a[0]).unwrap().status = "inhouse".into();
                self.emit(format!(
                    "CHECKIN {} {} room {} until {}",
                    a[0], reservation.guest, reservation.room, date_text(reservation.departure)
                ), false);
            }
            "MOVE" => {
                let old = self.reservation(a[0], Some("inhouse"))?.clone();
                let destination: i32 = a[1].parse().unwrap();
                self.require_room(destination)?;
                if destination == old.room {
                    return Err(format!("same room {destination}"));
                }
                let remaining: Vec<Night> = old.nights.iter()
                    .filter(|n| n.day >= self.today).cloned().collect();
                if remaining.is_empty() {
                    return Err(format!("no remaining nights {}", a[0]));
                }
                if let Some(day) = self.first_unavailable(destination, remaining[0].day,
                                                          old.departure, Some(a[0])) {
                    return Err(format!("room unavailable {destination} {}", date_text(day)));
                }
                if let Some(occupant) = self.inhouse(destination) {
                    return Err(format!("room occupied {destination} {}", occupant.id));
                }
                if !self.require_room(destination)?.clean {
                    return Err(format!("room dirty {destination}"));
                }
                self.release(&old.nights, Some(self.today));
                let mut updated = old.clone();
                for night in &mut updated.nights {
                    if night.day >= self.today {
                        night.room = destination;
                    }
                }
                let new_nights: Vec<Night> = updated.nights.iter()
                    .filter(|n| n.day >= self.today).cloned().collect();
                self.occupy(a[0], &new_nights);
                self.rooms.get_mut(&old.room).unwrap().clean = false;
                updated.room = destination;
                self.emit(format!(
                    "MOVE {} {} -> {destination} nights {}",
                    a[0], old.room, remaining.len()
                ), false);
                self.reservations.insert(a[0].to_string(), updated);
            }
            "EXTEND" => {
                let old = self.reservation(a[0], Some("inhouse"))?.clone();
                let departure = date_number(a[1])?;
                if departure <= old.departure {
                    return Err(format!("invalid range {} {}", date_text(old.departure), a[1]));
                }
                if departure - old.arrival > 30 {
                    return Err(format!("too long {}", departure - old.arrival));
                }
                if let Some(day) = self.first_unavailable(old.room, old.departure,
                                                          departure, Some(a[0])) {
                    return Err(format!("room unavailable {} {}", old.room, date_text(day)));
                }
                let nights = self.price(self.require_room(old.room)?, old.departure, departure);
                let mut updated = old;
                updated.nights.extend(nights.iter().cloned());
                updated.departure = departure;
                self.occupy(a[0], &nights);
                self.emit(format!(
                    "EXTEND {} until {} nights {} total {}",
                    a[0], a[1], updated.nights.len(), money(updated.lodging())
                ), false);
                self.reservations.insert(a[0].to_string(), updated);
            }
            "CHARGE" => {
                let mut reservation = self.reservation(a[0], Some("inhouse"))?.clone();
                let amount = cents(a[1]);
                if amount == 0 {
                    return Err("invalid amount".into());
                }
                reservation.extras.push((a[2].into(), amount));
                let total: i64 = reservation.extras.iter().map(|(_, value)| *value).sum();
                self.emit(format!("CHARGE {} {} {} extras {}",
                                  a[0], a[2], a[1], money(total)), false);
                self.reservations.insert(a[0].to_string(), reservation);
            }
            "PAY" => {
                let mut reservation = self.reservation(a[0], None)?.clone();
                if reservation.status != "booked" && reservation.status != "inhouse" {
                    return Err(format!("invalid status {} {}", a[0], reservation.status));
                }
                let amount = cents(a[1]);
                if amount == 0 {
                    return Err("invalid amount".into());
                }
                reservation.deposit += amount;
                self.emit(format!("PAY {} {} deposit {}", a[0], a[1],
                                  money(reservation.deposit)), false);
                self.reservations.insert(a[0].to_string(), reservation);
            }
            "CHECKOUT" => {
                self.reservation(a[0], Some("inhouse"))?;
                self.check_out(a[0], self.today, false);
            }
            "INVOICE" => {
                let reservation = self.reservation(a[0], None)?.clone();
                let room = self.require_room(reservation.room)?;
                self.emit(format!("INVOICE {} {} room {} {} {}",
                                  a[0], reservation.guest, room.number, room.kind,
                                  reservation.status), false);
                if reservation.status == "cancelled" || reservation.status == "noshow" {
                    let label = if reservation.status == "cancelled" {
                        "cancellation"
                    } else {
                        "noshow"
                    };
                    self.emit(format!("{label} fee {}", money(reservation.fee)), true);
                    self.emit(format!("total {}", money(reservation.fee)), true);
                    self.emit(Self::deposit_parts(&reservation, reservation.fee), true);
                } else {
                    for night in &reservation.nights {
                        self.emit(format!("{} room {} {}",
                                          date_weekday(night.day), night.room, money(night.rate)), true);
                    }
                    let bill = reservation.bill.unwrap_or_else(|| self.calculate_bill(&reservation));
                    self.emit(format!("lodging {}", money(bill.lodging)), true);
                    self.emit(format!("discount {}", money(bill.discount)), true);
                    if let Some((day, _)) = reservation.penalty {
                        self.emit(format!("penalty {} {}", date_weekday(day), money(bill.penalty)),
                                  true);
                    }
                    for (item, amount) in &reservation.extras {
                        self.emit(format!("extra {item} {}", money(*amount)), true);
                    }
                    self.emit(format!("tax {}", money(bill.tax)), true);
                    self.emit(format!("total {}", money(bill.total)), true);
                    self.emit(Self::deposit_parts(&reservation, bill.total), true);
                }
            }
            "AVAIL" => {
                self.require_type(a[0])?;
                let (start, end) = self.period(a[1], a[2], false, true)?;
                self.emit(format!("AVAIL {} {} -> {}", a[0], a[1], a[2]), false);
                for day in start..=end {
                    let free: Vec<i32> = self.rooms.iter()
                        .filter(|(number, room)| room.kind == a[0] &&
                                !self.blocks.contains(&(day, **number)) &&
                                !self.occupied.contains_key(&(day, **number)))
                        .map(|(number, _)| *number).collect();
                    let suffix: String = free.iter().map(|number| format!(" {number}")).collect();
                    self.emit(format!("{} free {}{suffix}", date_weekday(day), free.len()), true);
                }
            }
            "OCCUPANCY" => {
                let day = date_number(a[0])?;
                let numbers: Vec<i32> = self.rooms.keys().copied().collect();
                self.emit(format!("OCCUPANCY {} {}", date_weekday(day),
                                  self.occupancy_parts(&numbers, day)), false);
                for kind in TYPES {
                    let numbers: Vec<i32> = self.rooms.values()
                        .filter(|room| room.kind == kind).map(|room| room.number).collect();
                    if !numbers.is_empty() {
                        self.emit(format!("{kind} {}", self.occupancy_parts(&numbers, day)), true);
                    }
                }
            }
            "STATS" => {
                let (start, end) = self.period(a[0], a[1], false, true)?;
                self.emit(format!("STATS {} -> {}", a[0], a[1]), false);
                let mut totals = (0, 0, 0);
                for day in start..=end {
                    let (available, occupied, revenue) = self.daily_values(day);
                    totals.0 += available;
                    totals.1 += occupied;
                    totals.2 += revenue;
                    self.emit(format!("{} {}", date_weekday(day),
                                      Self::metrics_parts(available, occupied, revenue)), true);
                }
                self.emit(format!("total {}", Self::metrics_parts(totals.0, totals.1, totals.2)), true);
            }
            "ROOMS" => {
                self.emit(format!("ROOMS {} rooms {}", date_weekday(self.today),
                                  self.rooms.len()), false);
                let rooms: Vec<Room> = self.rooms.values().cloned().collect();
                for room in rooms {
                    let occupancy = if let Some(occupant) = self.inhouse(room.number) {
                        format!("occupied {}", occupant.id)
                    } else if self.blocks.contains(&(self.today, room.number)) {
                        "blocked".into()
                    } else {
                        "vacant".into()
                    };
                    let mut line = format!(
                        "{} {} base {} tonight {} {} {occupancy}",
                        room.number, room.kind, money(room.rate),
                        money(self.night_rate(&room, self.today)),
                        if room.clean { "clean" } else { "dirty" }
                    );
                    if let Some(upcoming) = self.reservations.values()
                        .filter(|r| r.status == "booked" && r.room == room.number)
                        .min_by_key(|r| (r.arrival, &r.id)) {
                        line += &format!(" next {} {}", upcoming.id, date_text(upcoming.arrival));
                    }
                    self.emit(line, true);
                }
            }
            "LIST" => {
                let mut reservations: Vec<Reservation> = self.reservations.values()
                    .filter(|r| r.status == a[0]).cloned().collect();
                reservations.sort_by_key(|r| (r.arrival, &r.id));
                self.emit(format!("LIST {} {}", a[0], reservations.len()), false);
                for reservation in reservations {
                    let line = format!("{} {} room {} {} -> {}",
                                       reservation.id, reservation.guest, reservation.room,
                                       date_text(reservation.arrival), date_text(reservation.departure));
                    self.emit(line, true);
                }
            }
            "QUEUE" => {
                self.emit(format!("QUEUE {}", self.waitlist.len()), false);
                let entries = self.waitlist.clone();
                for (position, entry) in entries.iter().enumerate() {
                    self.emit(format!("{} {} {} {} {} -> {}",
                                      position + 1, entry.id, entry.guest, entry.kind,
                                      date_text(entry.arrival), date_text(entry.departure)), true);
                }
            }
            "SCHEDULE" => {
                let day = date_number(a[0])?;
                let arrivals: Vec<Reservation> = self.reservations.values()
                    .filter(|r| r.arrival == day && r.status != "cancelled")
                    .cloned().collect();
                let departures: Vec<Reservation> = self.reservations.values()
                    .filter(|r| r.departure == day &&
                            (r.status == "booked" || r.status == "inhouse" ||
                             r.status == "checkedout"))
                    .cloned().collect();
                self.emit(format!("SCHEDULE {} arrivals {} departures {}",
                                  date_weekday(day), arrivals.len(), departures.len()), false);
                for reservation in arrivals {
                    self.emit(format!("arrival {} {} room {} {}", reservation.id,
                                      reservation.guest, reservation.room, reservation.status), true);
                }
                for reservation in departures {
                    self.emit(format!("departure {} {} room {} {}", reservation.id,
                                      reservation.guest, reservation.room, reservation.status), true);
                }
            }
            "GUEST" => {
                let guest = a[0];
                if !self.reservations.values().any(|r| r.guest == guest) {
                    return Err(format!("unknown guest {guest}"));
                }
                self.emit(format!("GUEST {guest}"), false);
                let matches: Vec<Reservation> = self.order.iter()
                    .filter_map(|id| self.reservations.get(id))
                    .filter(|r| r.guest == guest).cloned().collect();
                for reservation in matches {
                    let room = self.require_room(reservation.room)?;
                    let part = if reservation.status == "booked" ||
                                  reservation.status == "inhouse" {
                        format!("deposit {}", money(reservation.deposit))
                    } else {
                        format!("paid {}", money(reservation.paid))
                    };
                    self.emit(format!("{} room {} {} {} -> {} {} {}",
                                      reservation.id, room.number, room.kind,
                                      date_text(reservation.arrival), date_text(reservation.departure),
                                      reservation.status, part), true);
                }
                let total = self.guest_total(guest);
                self.emit(format!("total paid {} points {} tier {}", money(total),
                                  total / 100, self.tier(guest)), true);
            }
            "REVENUE" => {
                let (start, end) = self.period(a[0], a[1], false, false)?;
                let posted: Vec<&Reservation> = self.reservations.values()
                    .filter(|r| r.posting.is_some_and(|day| start <= day && day <= end)).collect();
                let mut sums = [0i64; 7];
                let mut checkouts = 0;
                let mut cancellations = 0;
                let mut noshows = 0;
                for reservation in posted {
                    match reservation.status.as_str() {
                        "checkedout" => {
                            checkouts += 1;
                            let bill = reservation.bill.unwrap();
                            sums[0] += bill.lodging;
                            sums[1] += bill.discount;
                            sums[2] += bill.penalty;
                            sums[3] += bill.extras;
                            sums[4] += bill.tax;
                        }
                        "cancelled" => {
                            cancellations += 1;
                            sums[5] += reservation.fee;
                        }
                        "noshow" => {
                            noshows += 1;
                            sums[6] += reservation.fee;
                        }
                        _ => {}
                    }
                }
                self.emit(format!("REVENUE {} -> {}", a[0], a[1]), false);
                for (label, value) in ["lodging", "discount", "penalty", "extras",
                                      "tax", "cancellation", "noshow"].iter().zip(sums) {
                    self.emit(format!("{label} {}", money(value)), true);
                }
                let total = sums[0] - sums[1] + sums[2] + sums[3] + sums[4] + sums[5] + sums[6];
                self.emit(format!("total {}", money(total)), true);
                self.emit(format!("checkouts {checkouts} cancellations {cancellations} noshows {noshows}"),
                          true);
            }
            _ => unreachable!("input command names are guaranteed valid"),
        }
        Ok(())
    }

    fn execute(&mut self, line: &str) {
        let words: Vec<&str> = line.split_ascii_whitespace().collect();
        if let Err(reason) = self.command(&words) {
            self.emit(format!("ERROR {reason}"), false);
        }
        self.process_waitlist();
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let commands: usize = lines.next().unwrap().parse().unwrap();
    let mut hotel = HotelDesk::new();
    for line in lines.take(commands) {
        hotel.execute(line);
    }
    if !hotel.output.is_empty() {
        println!("{}", hotel.output.join("\n"));
    }
}
