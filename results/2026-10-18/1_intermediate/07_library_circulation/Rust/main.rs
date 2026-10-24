use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};

type Result<T> = std::result::Result<T, &'static str>;
macro_rules! reject {
    ($condition:expr, $reason:expr) => {
        if $condition { return Err($reason); }
    };
}
const AVAILABLE: usize = 0;
const LOANED: usize = 1;
const HOLD: usize = 2;
const LOST: usize = 3;
const WITHDRAWN: usize = 4;
const STATES: [&str; 5] = ["AVAILABLE", "LOANED", "HOLD", "LOST", "WITHDRAWN"];
const KINDS: [&str; 3] = ["FINE", "FEE", "PRICE"];
#[derive(Clone, Copy, PartialEq, Eq)]
struct Ref { title: usize, copy: usize }
#[derive(Clone, Copy, Default)]
struct Copy { state: usize, member: usize, from: i32, due: i32, renewals: i32, expiry: i32 }
#[derive(Default)]
struct Title {
    isbn: String,
    name: String,
    folded: String,
    price: i32,
    borrowed: i32,
    counts: [i32; 5],
    copies: Vec<Copy>,
    queue: Vec<usize>,
}
struct Charge { day: i32, kind: usize, title: usize, amount: i32, unpaid: i32 }
#[derive(Default)]
struct Member {
    id: String,
    kind: String,
    name: String,
    limit: usize,
    period: i32,
    rate: i32,
    cap: i32,
    reserve_limit: i32,
    fee: i32,
    balance: i32,
    reservations: i32,
    loans: Vec<Ref>,
    holds: Vec<Ref>,
    charges: Vec<Charge>,
    history: Vec<String>,
}
#[derive(Default)]
struct Library {
    day: i32,
    borrowed: i32,
    returned: i32,
    renewed: i32,
    lost: i32,
    paid: i32,
    waived: i32,
    charged: [i32; 3],
    closed: BTreeSet<i32>,
    title_ids: BTreeMap<String, usize>,
    member_ids: BTreeMap<String, usize>,
    titles: Vec<Title>,
    members: Vec<Member>,
    output: Vec<String>,
}
fn number(s: &str) -> i32 { s.parse().unwrap() }
fn money(n: i32) -> String { format!("{}.{:02}", n / 100, n % 100) }
fn cents(s: &str) -> i32 {
    let (whole, fraction) = s.split_once('.').unwrap();
    number(whole) * 100 + number(fraction)
}
fn normalize(input: &str) -> Option<String> {
    let mut s = input.replace('-', "");
    if s.len() == 10 {
        let mut sum = 0;
        for (i, c) in s.bytes().enumerate() {
            if !c.is_ascii_digit() && !(i == 9 && c == b'X') { return None; }
            let value = if c == b'X' { 10 } else { i32::from(c - b'0') };
            sum += (10 - i as i32) * value;
        }
        if sum % 11 != 0 { return None; }
        s = "978".to_owned() + &s[..9];
        sum = s.bytes().enumerate().map(|(i, c)| (if i % 2 == 0 { 1 } else { 3 }) * i32::from(c - b'0')).sum();
        s.push((b'0' + ((10 - sum % 10) % 10) as u8) as char);
        return Some(s);
    }
    if s.len() != 13 || !(s.starts_with("978") || s.starts_with("979")) || !s.bytes().all(|c| c.is_ascii_digit()) { return None; }
    let sum: i32 = s.bytes().enumerate().map(|(i, c)| (if i % 2 == 0 { 1 } else { 3 }) * i32::from(c - b'0')).sum();
    if sum % 10 == 0 { Some(s) } else { None }
}
fn remove_ref(refs: &mut Vec<Ref>, r: Ref) {
    let i = refs.iter().position(|&other| other == r).unwrap();
    refs.remove(i);
}
fn find_ref(refs: &[Ref], title: usize) -> Option<usize> {
    refs.iter().find(|r| r.title == title).map(|r| r.copy)
}
impl Library {
    fn new() -> Self {
        Self { day: 1, ..Self::default() }
    }
    fn open(&self, mut d: i32) -> i32 {
        while self.closed.contains(&d) { d += 1; }
        d
    }
    fn cp(&self, r: Ref) -> &Copy { &self.titles[r.title].copies[r.copy] }
    fn holdings(&self, t: usize) -> i32 { self.titles[t].counts[..3].iter().sum() }
    fn state(&mut self, r: Ref, next: usize) {
        let t = &mut self.titles[r.title];
        t.counts[t.copies[r.copy].state] -= 1;
        t.copies[r.copy].state = next;
        t.counts[next] += 1;
    }
    fn member(&self, id: &str) -> Result<usize> { self.member_ids.get(id).copied().ok_or("unknown member") }
    fn title(&self, input: &str) -> Result<usize> {
        let isbn = normalize(input).ok_or("invalid isbn")?;
        self.title_ids.get(&isbn).copied().ok_or("unknown book")
    }
    fn late(&self, r: Ref) -> i32 { (self.day - self.cp(r).due).max(0) }
    fn fine(&self, r: Ref) -> i32 {
        let m = &self.members[self.cp(r).member];
        (self.late(r) * m.rate).min(m.cap)
    }
    fn charge(&mut self, m: usize, kind: usize, title: usize, amount: i32) {
        if amount == 0 { return; }
        self.members[m].charges.push(Charge { day: self.day, kind, title, amount, unpaid: amount });
        self.members[m].balance += amount;
        self.charged[kind] += amount;
    }
    fn release(&mut self, r: Ref) {
        if self.titles[r.title].queue.is_empty() {
            self.state(r, AVAILABLE);
            return;
        }
        let m = self.titles[r.title].queue.remove(0);
        let expiry = self.open(self.day + 3);
        self.state(r, HOLD);
        self.titles[r.title].copies[r.copy].member = m;
        self.titles[r.title].copies[r.copy].expiry = expiry;
        self.members[m].holds.push(r);
        self.output.push(format!("HOLD {} copy {} {} until {}", self.titles[r.title].isbn, r.copy + 1, self.members[m].id, expiry));
    }
    fn drop_queue(&mut self, t: usize) {
        if self.holdings(t) != 0 { return; }
        let queue = std::mem::take(&mut self.titles[t].queue);
        for m in queue {
            self.members[m].reservations -= 1;
            self.output.push(format!("DROPPED {} {}", self.titles[t].isbn, self.members[m].id));
        }
    }
    fn end_loan(&mut self, r: Ref, loss: bool, heading: &str) {
        let c = *self.cp(r);
        let (m, late, fine) = (c.member, self.late(r), self.fine(r));
        remove_ref(&mut self.members[m].loans, r);
        self.charge(m, 0, r.title, fine);
        let mut history = format!("{} {} copy {} from {} to {} late {} fine {}", if loss { "LOST" } else { "RETURNED" }, self.titles[r.title].isbn, r.copy + 1, c.from, self.day, late, money(fine));
        let mut result = format!("{} {} {} copy {} late {} fine {}", heading, self.members[m].id, self.titles[r.title].isbn, r.copy + 1, late, money(fine));
        if loss {
            let price = self.titles[r.title].price;
            history.push_str(&format!(" price {}", money(price)));
            result.push_str(&format!(" price {}", money(price)));
            self.charge(m, 2, r.title, price);
            self.state(r, LOST);
            self.lost += 1;
        } else { self.returned += 1; }
        self.members[m].history.push(history);
        self.output.push(format!("{} balance {}", result, money(self.members[m].balance)));
        if loss {
            self.drop_queue(r.title);
        } else {
            self.release(r);
        }
    }
    fn renewal_reason(&self, r: Ref) -> Option<&'static str> {
        if self.late(r) != 0 { return Some("loan overdue"); }
        if self.cp(r).renewals == 2 { return Some("renewal limit"); }
        if !self.titles[r.title].queue.is_empty() { return Some("title reserved"); }
        None
    }
    fn renew(&mut self, r: Ref) {
        let m = self.cp(r).member;
        let due = self.open(self.day + self.members[m].period);
        let c = &mut self.titles[r.title].copies[r.copy];
        c.due = due;
        c.renewals += 1;
        self.renewed += 1;
        self.output.push(format!("RENEW {} {} copy {} due {} renewals {}", self.members[m].id, self.titles[r.title].isbn, r.copy + 1, due, self.cp(r).renewals));
    }
    fn ordered(&self, refs: &[Ref], holds: bool) -> Vec<Ref> {
        let mut result = refs.to_vec();
        result.sort_by(|&a, &b| {
            let x = if holds { self.cp(a).expiry } else { self.cp(a).due };
            let y = if holds { self.cp(b).expiry } else { self.cp(b).due };
            (x, &self.titles[a.title].isbn).cmp(&(y, &self.titles[b.title].isbn))
        });
        result
    }
    fn execute(&mut self, a: &[&str]) -> Result<()> {
        let cmd = a[0];
        match cmd {
            "DAY" => {
                let target = number(a[1]);
                reject!(target <= self.day, "invalid day");
                self.output.push(format!("DAY {}", target));
                while self.day < target {
                    self.day += 1;
                    let mut losses = Vec::new();
                    for &m in self.member_ids.values() {
                        for &r in &self.members[m].loans {
                            if self.cp(r).due + 365 <= self.day { losses.push(r); }
                        }
                    }
                    for r in losses { self.end_loan(r, true, "AUTOLOST"); }
                    let mut expiries = Vec::new();
                    for &t in self.title_ids.values() {
                        for (i, c) in self.titles[t].copies.iter().enumerate() {
                            if c.state == HOLD && c.expiry < self.day { expiries.push(Ref { title: t, copy: i }); }
                        }
                    }
                    for r in expiries {
                        let m = self.cp(r).member;
                        self.charge(m, 1, r.title, self.members[m].fee);
                        remove_ref(&mut self.members[m].holds, r);
                        self.members[m].reservations -= 1;
                        self.output.push(format!("EXPIRED {} copy {} {} fee {}", self.titles[r.title].isbn, r.copy + 1, self.members[m].id, money(self.members[m].fee)));
                        self.release(r);
                    }
                }
            }
            "CLOSED" => {
                let d = number(a[1]);
                reject!(d <= self.day, "invalid day");
                reject!(self.closed.contains(&d), "already closed");
                self.closed.insert(d);
                self.output.push(format!("CLOSED {}", d));
                let next = self.open(d);
                for &t in self.title_ids.values() {
                    let book = &mut self.titles[t];
                    let isbn = &book.isbn;
                    for (i, c) in book.copies.iter_mut().enumerate() {
                        if c.state == LOANED && c.due == d {
                            c.due = next;
                            self.output.push(format!("MOVED {} copy {} {} due {}", isbn, i + 1, self.members[c.member].id, next));
                        } else if c.state == HOLD && c.expiry == d {
                            c.expiry = next;
                            self.output.push(format!("MOVED {} copy {} {} until {}", isbn, i + 1, self.members[c.member].id, next));
                        }
                    }
                }
            }
            "ADDBOOK" => {
                let isbn = normalize(a[1]).ok_or("invalid isbn")?;
                let name = a[4..].join(" ");
                let t = if let Some(&id) = self.title_ids.get(&isbn) {
                    reject!(self.titles[id].name != name, "title mismatch");
                    id
                } else {
                    let id = self.titles.len();
                    self.titles.push(Title { isbn: isbn.clone(), folded: name.to_ascii_lowercase(), name, ..Title::default() });
                    self.title_ids.insert(isbn.clone(), id);
                    id
                };
                self.titles[t].price = cents(a[3]);
                let (start, added) = (self.titles[t].copies.len(), number(a[2]) as usize);
                self.titles[t].copies.resize(start + added, Copy::default());
                self.titles[t].counts[AVAILABLE] += added as i32;
                self.output.push(format!("ADDBOOK {} added {} total {}", isbn, added, self.holdings(t)));
                for copy in start..start + added { self.release(Ref { title: t, copy }); }
            }
            "ADDMEMBER" => {
                reject!(self.member_ids.contains_key(a[1]), "duplicate member");
                reject!(a[2] != "STUDENT" && a[2] != "STAFF", "unknown type");
                let staff = a[2] == "STAFF";
                let m = Member {
                    id: a[1].to_owned(), kind: a[2].to_owned(), name: a[3..].join(" "),
                    limit: if staff { 10 } else { 3 }, period: if staff { 28 } else { 14 },
                    rate: if staff { 10 } else { 25 }, cap: if staff { 2000 } else { 1000 },
                    reserve_limit: if staff { 5 } else { 2 }, fee: if staff { 100 } else { 50 },
                    ..Member::default()
                };
                self.output.push(format!("ADDMEMBER {} {} loans {} days {}", m.id, m.kind, m.limit, m.period));
                self.member_ids.insert(m.id.clone(), self.members.len());
                self.members.push(m);
            }
            "WITHDRAW" => {
                let t = self.title(a[1])?;
                let i = number(a[2]) - 1;
                reject!(i < 0 || i as usize >= self.titles[t].copies.len(), "unknown copy");
                let r = Ref { title: t, copy: i as usize };
                reject!(self.cp(r).state != AVAILABLE, "copy not available");
                self.state(r, WITHDRAWN);
                self.output.push(format!("WITHDRAW {} copy {} total {}", self.titles[t].isbn, i + 1, self.holdings(t)));
            }
            "BORROW" | "RETURN" | "RENEW" | "RESERVE" | "CANCEL" | "LOST" => {
                let m = self.member(a[1])?;
                let t = self.title(a[2])?;
                let loan = find_ref(&self.members[m].loans, t);
                let held = find_ref(&self.members[m].holds, t);
                let queued = self.titles[t].queue.iter().position(|&id| id == m);
                match cmd {
                    "BORROW" => {
                        reject!(self.closed.contains(&self.day), "library closed");
                        reject!(loan.is_some(), "already borrowed");
                        reject!(self.members[m].balance > 500, "member blocked");
                        reject!(self.members[m].loans.iter().any(|&r| self.late(r) != 0), "overdue loans");
                        reject!(self.members[m].loans.len() >= self.members[m].limit, "loan limit");
                        let available = self.titles[t].copies.iter().position(|c| c.state == AVAILABLE);
                        let i = held.or(available).ok_or(if self.titles[t].counts[HOLD] != 0 { "all copies on hold" } else { "no copy available" })?;
                        let r = Ref { title: t, copy: i };
                        if held.is_some() {
                            remove_ref(&mut self.members[m].holds, r);
                            self.members[m].reservations -= 1;
                        }
                        self.state(r, LOANED);
                        self.titles[t].copies[i] = Copy { state: LOANED, member: m, from: self.day, due: self.open(self.day + self.members[m].period), renewals: 0, expiry: 0 };
                        self.members[m].loans.push(r);
                        let titles = &self.titles;
                        self.members[m].loans.sort_by(|a, b| titles[a.title].isbn.cmp(&titles[b.title].isbn));
                        self.borrowed += 1;
                        self.titles[t].borrowed += 1;
                        self.output.push(format!("BORROW {} {} copy {} due {}", self.members[m].id, self.titles[t].isbn, i + 1, self.cp(r).due));
                    }
                    "RETURN" | "LOST" | "RENEW" => {
                        let r = Ref { title: t, copy: loan.ok_or("not borrowed")? };
                        if cmd == "RENEW" {
                            reject!(self.members[m].balance > 500, "member blocked");
                            if let Some(reason) = self.renewal_reason(r) { return Err(reason); }
                            self.renew(r);
                        } else { self.end_loan(r, cmd == "LOST", cmd); }
                    }
                    "RESERVE" => {
                        reject!(loan.is_some(), "already borrowed");
                        reject!(queued.is_some() || held.is_some(), "already reserved");
                        reject!(self.members[m].balance > 500, "member blocked");
                        reject!(self.members[m].reservations >= self.members[m].reserve_limit, "reservation limit");
                        reject!(self.holdings(t) == 0, "no copies");
                        reject!(self.titles[t].counts[AVAILABLE] > 0, "copy available");
                        self.titles[t].queue.push(m);
                        self.members[m].reservations += 1;
                        let mut dues: Vec<i32> = self.titles[t].copies.iter().filter(|c| c.state == LOANED).map(|c| c.due).collect();
                        dues.sort();
                        let p = self.titles[t].queue.len();
                        let estimate = dues.get(p - 1).map(|d| d.to_string()).unwrap_or_else(|| "none".to_owned());
                        self.output.push(format!("RESERVE {} {} position {} estimate {}", self.members[m].id, self.titles[t].isbn, p, estimate));
                    }
                    _ => {
                        reject!(queued.is_none() && held.is_none(), "not reserved");
                        self.members[m].reservations -= 1;
                        if let Some(q) = queued {
                            self.titles[t].queue.remove(q);
                            self.output.push(format!("CANCEL {} {} queue", self.members[m].id, self.titles[t].isbn));
                        } else {
                            let r = Ref { title: t, copy: held.unwrap() };
                            remove_ref(&mut self.members[m].holds, r);
                            self.output.push(format!("CANCEL {} {} hold copy {}", self.members[m].id, self.titles[t].isbn, r.copy + 1));
                            self.release(r);
                        }
                    }
                }
            }
            "RENEWALL" => {
                let m = self.member(a[1])?;
                reject!(self.members[m].loans.is_empty(), "no loans");
                reject!(self.members[m].balance > 500, "member blocked");
                let (mut good, mut skipped) = (0, 0);
                for r in self.members[m].loans.clone() {
                    if let Some(reason) = self.renewal_reason(r) {
                        self.output.push(format!("SKIP {} {}", self.titles[r.title].isbn, reason));
                        skipped += 1;
                    } else {
                        self.renew(r);
                        good += 1;
                    }
                }
                self.output.push(format!("RENEWALL {} renewed {} skipped {}", self.members[m].id, good, skipped));
            }
            "PAYFINE" | "WAIVE" | "FINES" => {
                let m = self.member(a[1])?;
                let p = &mut self.members[m];
                match cmd {
                    "PAYFINE" => {
                        reject!(p.balance == 0, "no fines");
                        let amount = cents(a[2]);
                        let mut remaining = amount;
                        let mut details = Vec::new();
                        for (i, c) in p.charges.iter_mut().enumerate() {
                            let applied = remaining.min(c.unpaid);
                            if applied == 0 { continue; }
                            c.unpaid -= applied;
                            remaining -= applied;
                            details.push(format!("ITEM {} {} paid {} remaining {}", i + 1, KINDS[c.kind], money(applied), money(c.unpaid)));
                            if remaining == 0 { break; }
                        }
                        p.balance -= amount - remaining;
                        self.paid += amount - remaining;
                        self.output.push(format!("PAYFINE {} paid {} change {} balance {}", p.id, money(amount - remaining), money(remaining), money(p.balance)));
                        self.output.extend(details);
                    }
                    "WAIVE" => {
                        let i = number(a[2]) - 1;
                        reject!(i < 0 || i as usize >= p.charges.len(), "unknown item");
                        let c = &mut p.charges[i as usize];
                        reject!(c.unpaid == 0, "item settled");
                        let amount = c.unpaid;
                        c.unpaid = 0;
                        p.balance -= amount;
                        self.waived += amount;
                        self.output.push(format!("WAIVE {} item {} {} amount {} balance {}", p.id, i + 1, KINDS[c.kind], money(amount), money(p.balance)));
                    }
                    _ => {
                        self.output.push(format!("FINES {} items {} balance {}", p.id, p.charges.iter().filter(|c| c.unpaid > 0).count(), money(p.balance)));
                        for (i, c) in p.charges.iter().enumerate() {
                            if c.unpaid > 0 { self.output.push(format!("{} day {} {} {} amount {} remaining {}", i + 1, c.day, KINDS[c.kind], self.titles[c.title].isbn, money(c.amount), money(c.unpaid))); }
                        }
                    }
                }
            }
            "SEARCH" => {
                let keyword = a[1..].join(" ").to_ascii_lowercase();
                let mut found: Vec<usize> = (0..self.titles.len()).filter(|&i| self.titles[i].folded.contains(&keyword)).collect();
                found.sort_by(|&a, &b| (&self.titles[a].folded, &self.titles[a].isbn).cmp(&(&self.titles[b].folded, &self.titles[b].isbn)));
                self.output.push(format!("SEARCH {}", found.len()));
                for t in found { self.output.push(format!("{} {}/{} {}", self.titles[t].isbn, self.titles[t].counts[AVAILABLE], self.holdings(t), self.titles[t].name)); }
            }
            "OVERDUE" => {
                let mut refs: Vec<Ref> = self.members.iter().flat_map(|m| m.loans.iter().copied()).filter(|&r| self.late(r) > 0).collect();
                refs.sort_by(|&a, &b| (self.cp(a).due, &self.members[self.cp(a).member].id, &self.titles[a.title].isbn).cmp(&(self.cp(b).due, &self.members[self.cp(b).member].id, &self.titles[b.title].isbn)));
                self.output.push(format!("OVERDUE {}", refs.len()));
                for r in refs { self.output.push(format!("{} {} copy {} due {} late {} fine {}", self.members[self.cp(r).member].id, self.titles[r.title].isbn, r.copy + 1, self.cp(r).due, self.late(r), money(self.fine(r)))); }
            }
            "NOTICES" => {
                let mut notices = Vec::new();
                for &id in self.member_ids.values() {
                    let m = &self.members[id];
                    for r in self.ordered(&m.loans, false) {
                        if self.cp(r).due <= self.day + 2 { notices.push(format!("{} {} {} due {}", if self.late(r) > 0 { "OVERDUE" } else { "DUESOON" }, m.id, self.titles[r.title].isbn, self.cp(r).due)); }
                    }
                    for r in self.ordered(&m.holds, true) { notices.push(format!("PICKUP {} {} until {}", m.id, self.titles[r.title].isbn, self.cp(r).expiry)); }
                }
                self.output.push(format!("NOTICES {}", notices.len()));
                self.output.extend(notices);
            }
            "MEMBER" | "MEMBERS" | "HISTORY" => {
                let target = if cmd == "MEMBERS" { None } else { Some(self.member(a[1])?) };
                if cmd == "HISTORY" {
                    let m = &self.members[target.unwrap()];
                    self.output.push(format!("HISTORY {} {}", m.id, m.history.len()));
                    self.output.extend(m.history.iter().cloned());
                    return Ok(());
                }
                if cmd == "MEMBERS" { self.output.push(format!("MEMBERS {}", self.members.len())); }
                for &id in self.member_ids.values() {
                    if target.is_some() && target != Some(id) { continue; }
                    let m = &self.members[id];
                    let status = if m.balance > 500 { "BLOCKED" } else { "OK" };
                    if cmd == "MEMBERS" {
                        self.output.push(format!("{} {} loans {} reservations {} balance {} {}", m.id, m.kind, m.loans.len(), m.reservations, money(m.balance), status));
                        continue;
                    }
                    self.output.push(format!("MEMBER {} {} {}", m.id, m.kind, m.name));
                    self.output.push(format!("STATUS loans {}/{} reservations {}/{} balance {} {}", m.loans.len(), m.limit, m.reservations, m.reserve_limit, money(m.balance), status));
                    for r in self.ordered(&m.loans, false) {
                        let mut s = format!("LOAN {} copy {} due {} renewals {}", self.titles[r.title].isbn, r.copy + 1, self.cp(r).due, self.cp(r).renewals);
                        if self.late(r) > 0 { s.push_str(&format!(" late {} fine {}", self.late(r), money(self.fine(r)))); }
                        self.output.push(s);
                    }
                    for r in self.ordered(&m.holds, true) { self.output.push(format!("HOLD {} copy {} until {}", self.titles[r.title].isbn, r.copy + 1, self.cp(r).expiry)); }
                    for (isbn, &t) in &self.title_ids {
                        if let Some(q) = self.titles[t].queue.iter().position(|&m| m == id) { self.output.push(format!("QUEUE {} position {}", isbn, q + 1)); }
                    }
                }
            }
            "BOOK" => {
                let t = self.title(a[1])?;
                let book = &self.titles[t];
                self.output.push(format!("BOOK {} {}", book.isbn, book.name));
                self.output.push(format!("PRICE {} copies {} borrowed {}", money(book.price), self.holdings(t), book.borrowed));
                for (i, c) in book.copies.iter().enumerate() {
                    let mut s = format!("COPY {} {}", i + 1, STATES[c.state]);
                    if c.state == LOANED || c.state == HOLD { s.push_str(&format!(" {} {} {}", self.members[c.member].id, if c.state == LOANED { "due" } else { "until" }, if c.state == LOANED { c.due } else { c.expiry })); }
                    self.output.push(s);
                }
                let mut queue = format!("QUEUE {}", book.queue.len());
                for &m in &book.queue { queue.push_str(&format!(" {}", self.members[m].id)); }
                self.output.push(queue);
            }
            "INVENTORY" => {
                let mut totals = [0; 5];
                for t in &self.titles {
                    for (i, n) in t.counts.iter().enumerate() { totals[i] += n; }
                }
                self.output.push(format!("INVENTORY titles {} copies {} available {} loaned {} hold {} lost {} withdrawn {}", self.titles.len(), totals[0] + totals[1] + totals[2], totals[0], totals[1], totals[2], totals[3], totals[4]));
                for &id in self.title_ids.values() {
                    let t = &self.titles[id];
                    self.output.push(format!("{} copies {} available {} loaned {} hold {} queue {}", t.isbn, self.holdings(id), t.counts[0], t.counts[1], t.counts[2], t.queue.len()));
                }
            }
            "STATS" => {
                let active: usize = self.members.iter().map(|m| m.loans.len()).sum();
                let outstanding: i32 = self.members.iter().map(|m| m.balance).sum();
                self.output.push(format!("STATS day {} titles {} members {} closed {}", self.day, self.titles.len(), self.members.len(), self.closed.len()));
                self.output.push(format!("LOANS borrowed {} returned {} renewed {} lost {} active {}", self.borrowed, self.returned, self.renewed, self.lost, active));
                self.output.push(format!("MONEY fines {} fees {} charges {} paid {} waived {} outstanding {}", money(self.charged[0]), money(self.charged[1]), money(self.charged[2]), money(self.paid), money(self.waived), money(outstanding)));
                let mut top: Vec<usize> = (0..self.titles.len()).filter(|&t| self.titles[t].borrowed > 0).collect();
                top.sort_by(|&a, &b| (-self.titles[a].borrowed, &self.titles[a].isbn).cmp(&(-self.titles[b].borrowed, &self.titles[b].isbn)));
                for (i, &t) in top.iter().take(3).enumerate() { self.output.push(format!("TOP {} {} {} {}", i + 1, self.titles[t].isbn, self.titles[t].borrowed, self.titles[t].name)); }
            }
            _ => unreachable!(),
        }
        Ok(())
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut library = Library::new();
    let mut output = String::new();
    for _ in 0..count {
        let arguments: Vec<&str> = lines.next().unwrap().split(' ').collect();
        library.output.clear();
        if let Err(reason) = library.execute(&arguments) {
            library.output.clear();
            library.output.push(format!("ERROR {}", reason));
        }
        for line in &library.output {
            output.push_str(line);
            output.push('\n');
        }
    }
    print!("{}", output);
}
