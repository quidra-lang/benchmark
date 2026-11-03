use std::collections::{BTreeMap, VecDeque};
use std::io::{self, Read};

const STATIONS: [&str; 4] = ["GRILL", "FRY", "COLD", "BAR"];
const COURSES: [&str; 4] = ["DRINK", "STARTER", "MAIN", "DESSERT"];

fn number(text: &str) -> i64 { text.parse().unwrap() }

fn cents(text: &str) -> i64 {
    let (whole, fraction) = text.split_once('.').unwrap();
    number(whole) * 100 + number(fraction)
}

fn money(value: i64) -> String { format!("{}.{:02}", value / 100, value % 100) }

fn clock(time: i64) -> String { format!("{:02}:{:02}", (660 + time) / 60, (660 + time) % 60) }

fn rounded(amount: i64, rate: i64) -> i64 { (amount * rate + 50) / 100 }

fn station_index(name: &str) -> Result<usize, String> {
    STATIONS.iter().position(|station| *station == name).ok_or_else(|| format!("unknown station {name}"))
}

fn course_index(name: &str) -> Result<usize, String> {
    COURSES.iter().position(|course| *course == name).ok_or_else(|| format!("unknown course {name}"))
}

fn numbers(lines: &[usize]) -> String {
    lines.iter().map(|index| format!("#{}", index + 1)).collect::<Vec<_>>().join(" ")
}

fn allocate(values: &BTreeMap<i64, i64>, rate: i64) -> BTreeMap<i64, i64> {
    let mut shares: BTreeMap<i64, i64> = values.iter().map(|(seat, value)| (*seat, value * rate / 100)).collect();
    let remaining = rounded(values.values().sum(), rate) - shares.values().sum::<i64>();
    let mut seats: Vec<i64> = values.keys().copied().collect();
    seats.sort_by_key(|seat| (-(values[seat] * rate % 100), *seat));
    for seat in seats.into_iter().take(remaining as usize) { *shares.get_mut(&seat).unwrap() += 1; }
    shares
}

#[derive(Clone, Copy, PartialEq)]
enum State { Ordered, Queued, Cooking, Ready, Served, Void }

impl State {
    fn name(self) -> &'static str {
        match self {
            Self::Ordered => "ORDERED", Self::Queued => "QUEUED", Self::Cooking => "COOKING",
            Self::Ready => "READY", Self::Served => "SERVED", Self::Void => "VOID",
        }
    }
}

struct Table { seats: i64, check: Option<usize> }

struct Server { name: String, parties: i64, sales: i64, tips: i64 }

struct WaitingParty { name: String, size: i64, joined: i64 }

struct Check {
    party: String,
    size: i64,
    table: i64,
    server: usize,
    seated: i64,
    lines: Vec<usize>,
    paid: i64,
    discount: i64,
    closed: bool,
}

struct MenuItem { station: usize, prep: i64, price: i64, course: usize, stock: Option<i64> }

struct Order {
    check: usize,
    seat: i64,
    item: String,
    quantity: i64,
    station: usize,
    prep: i64,
    unit_price: i64,
    course: usize,
    state: State,
    comp: Option<String>,
    fire_time: Option<i64>,
    ready_time: Option<i64>,
    started: bool,
}

impl Order {
    fn amount(&self) -> i64 { if self.comp.is_some() { 0 } else { self.unit_price * self.quantity } }

    fn comp_text(&self) -> String {
        self.comp.as_ref().map(|reason| format!(" COMP {reason}")).unwrap_or_default()
    }
}

#[derive(Default)]
struct Station {
    down: bool,
    queue: VecDeque<usize>,
    cooking: Vec<usize>,
    tickets: i64,
    ticket_sum: i64,
    ticket_max: i64,
    remakes: i64,
}

#[derive(Default, Clone, Copy)]
struct Amounts { subtotal: i64, discount: i64, service: i64, tax: i64, total: i64 }

#[derive(Default)]
struct Statistics {
    covers: i64,
    parties: i64,
    closed: i64,
    stay: i64,
    sales: [i64; 4],
    totals: Amounts,
    payments: [i64; 2],
    tips: i64,
    comps: i64,
    comp_amount: i64,
    voids: i64,
    served: BTreeMap<String, i64>,
}

#[derive(Default)]
struct Restaurant {
    time: i64,
    tables: BTreeMap<i64, Table>,
    servers: Vec<Server>,
    waiting: Vec<WaitingParty>,
    checks: Vec<Check>,
    menu: BTreeMap<String, MenuItem>,
    orders: Vec<Order>,
    stations: [Station; 4],
    happy: Option<(i64, i64)>,
    statistics: Statistics,
}

impl Restaurant {
    fn table(&self, number: i64) -> Result<&Table, String> {
        self.tables.get(&number).ok_or_else(|| format!("unknown table {number}"))
    }

    fn check_index(&self, table: i64) -> Result<usize, String> {
        self.table(table)?.check.ok_or_else(|| format!("table {table} is free"))
    }

    fn order_index(&self, text: &str) -> Result<usize, String> {
        let id = number(text) as usize;
        if id < 1 || id > self.orders.len() { Err(format!("unknown line {text}")) } else { Ok(id - 1) }
    }

    fn unlocked(&self, index: usize) -> Result<(), String> {
        let check = &self.checks[index];
        if check.paid > 0 { Err(format!("check for table {} is locked", check.table)) } else { Ok(()) }
    }

    fn modifiable(&self, index: usize) -> Result<(), String> {
        let order = &self.orders[index];
        if order.state == State::Void { return Err(format!("#{} is void", index + 1)); }
        if self.checks[order.check].closed { return Err(format!("#{} is on a closed check", index + 1)); }
        self.unlocked(order.check)
    }

    fn all_served(&self, index: usize) -> Result<(), String> {
        let check = &self.checks[index];
        let count = check.lines.iter().filter(|line| !matches!(self.orders[**line].state, State::Served | State::Void)).count();
        if count == 0 { Ok(()) } else { Err(format!("table {} has {count} unserved items", check.table)) }
    }

    fn load(&self, server: usize) -> usize {
        self.checks.iter().filter(|check| !check.closed && check.server == server).count()
    }

    fn choose_table(&self, size: i64) -> Option<i64> {
        self.tables.iter().filter(|(_, table)| table.check.is_none() && table.seats >= size)
            .min_by_key(|(number, table)| (table.seats, **number)).map(|(number, _)| *number)
    }

    fn seat(&mut self, party: &str, size: i64, table: i64) -> usize {
        let server = (0..self.servers.len()).min_by_key(|index| (self.load(*index), *index)).unwrap();
        let index = self.checks.len();
        self.checks.push(Check { party: party.into(), size, table, server, seated: self.time,
                                 lines: Vec::new(), paid: 0, discount: 0, closed: false });
        self.tables.get_mut(&table).unwrap().check = Some(index);
        self.servers[server].parties += 1;
        self.statistics.covers += size;
        self.statistics.parties += 1;
        server
    }

    fn seat_waiting(&mut self) {
        let mut index = 0;
        while index < self.waiting.len() {
            if let Some(table) = self.choose_table(self.waiting[index].size) {
                let party = self.waiting.remove(index);
                let server = self.seat(&party.name, party.size, table);
                println!("SEATED {} {} table {table} server {} waited {}", party.name, party.size,
                         self.servers[server].name, self.time - party.joined);
            } else { index += 1; }
        }
    }

    fn amounts(&self, index: usize) -> Amounts {
        let check = &self.checks[index];
        let subtotal = check.lines.iter().map(|line| &self.orders[*line])
            .filter(|order| order.state != State::Void).map(Order::amount).sum();
        let discount = rounded(subtotal, check.discount);
        let net = subtotal - discount;
        let service = if check.size >= 6 { rounded(net, 18) } else { 0 };
        let tax = rounded(net, 8);
        Amounts { subtotal, discount, service, tax, total: net + service + tax }
    }

    fn seats(&self, index: usize) -> BTreeMap<i64, i64> {
        let mut seats = BTreeMap::new();
        for line in &self.checks[index].lines {
            let order = &self.orders[*line];
            if order.state != State::Void { *seats.entry(order.seat).or_default() += order.amount(); }
        }
        seats
    }

    fn close(&mut self, index: usize) {
        let amounts = self.amounts(index);
        let check = &mut self.checks[index];
        let stay = self.time - check.seated;
        self.statistics.closed += 1;
        self.statistics.stay += stay;
        for line in &check.lines {
            let order = &self.orders[*line];
            if order.state != State::Void { self.statistics.sales[order.course] += order.amount(); }
        }
        let totals = &mut self.statistics.totals;
        totals.subtotal += amounts.subtotal;
        totals.discount += amounts.discount;
        totals.service += amounts.service;
        totals.tax += amounts.tax;
        totals.total += amounts.total;
        self.servers[check.server].sales += amounts.total;
        check.closed = true;
        self.tables.get_mut(&check.table).unwrap().check = None;
        println!("FREE table {} {} stayed {stay}", check.table, check.party);
        self.seat_waiting();
    }

    fn start_cooking(&mut self, index: usize, time: i64) {
        let station = &mut self.stations[index];
        let capacity = if index == 3 { 2 } else { 1 };
        while !station.down && !station.queue.is_empty() && station.cooking.len() < capacity {
            let line = station.queue.pop_front().unwrap();
            let order = &mut self.orders[line];
            order.state = State::Cooking;
            order.started = true;
            order.ready_time = Some(time + order.prep);
            station.cooking.push(line);
        }
    }

    fn tick(&mut self, minutes: i64) {
        let target = self.time + minutes;
        println!("TICK {}", clock(target));
        loop {
            let next = self.stations.iter().flat_map(|station| &station.cooking)
                .map(|line| self.orders[*line].ready_time.unwrap()).min();
            let Some(time) = next.filter(|time| *time <= target) else { break; };
            for index in 0..4 {
                let orders = &self.orders;
                let station = &mut self.stations[index];
                let mut finished: Vec<usize> = station.cooking.iter().copied()
                    .filter(|line| orders[*line].ready_time == Some(time)).collect();
                finished.sort_unstable();
                station.cooking.retain(|line| orders[*line].ready_time != Some(time));
                for line in finished {
                    let order = &mut self.orders[line];
                    order.state = State::Ready;
                    let ticket = time - order.fire_time.unwrap();
                    station.tickets += 1;
                    station.ticket_sum += ticket;
                    station.ticket_max = station.ticket_max.max(ticket);
                    println!("READY {} {} #{} {} x{} table {} seat {}", clock(time), STATIONS[index],
                             line + 1, order.item, order.quantity, self.checks[order.check].table, order.seat);
                }
            }
            for index in 0..4 { self.start_cooking(index, time); }
        }
        self.time = target;
    }

    fn bill(&self, index: usize) {
        let check = &self.checks[index];
        println!("BILL table {} {} guests {}", check.table, check.party, check.size);
        for (seat, subtotal) in self.seats(index) {
            println!("SEAT {seat} {}", money(subtotal));
            for line in &check.lines {
                let order = &self.orders[*line];
                if order.state != State::Void && order.seat == seat {
                    println!("#{} {} x{} {}{}", line + 1, order.item, order.quantity, money(order.amount()), order.comp_text());
                }
            }
        }
        let amounts = self.amounts(index);
        println!("SUBTOTAL {}", money(amounts.subtotal));
        if check.discount > 0 { println!("DISCOUNT {}% {}", check.discount, money(amounts.discount)); }
        if check.size >= 6 { println!("SERVICE {}", money(amounts.service)); }
        println!("TAX {}", money(amounts.tax));
        println!("TOTAL {}", money(amounts.total));
        if check.paid > 0 {
            println!("PAID {}", money(check.paid));
            println!("DUE {}", money(amounts.total - check.paid));
        }
    }

    fn split_by_seat(&self, index: usize) {
        let check = &self.checks[index];
        let subtotals = self.seats(index);
        let discounts = allocate(&subtotals, check.discount);
        let net: BTreeMap<i64, i64> = subtotals.iter().map(|(seat, subtotal)| (*seat, subtotal - discounts[seat])).collect();
        let service = allocate(&net, if check.size >= 6 { 18 } else { 0 });
        let taxes = allocate(&net, 8);
        println!("SPLIT table {} BYSEAT total {}", check.table, money(self.amounts(index).total));
        for (seat, subtotal) in subtotals {
            println!("SEAT {seat} subtotal {} discount {} service {} tax {} total {}", money(subtotal),
                     money(discounts[&seat]), money(service[&seat]), money(taxes[&seat]),
                     money(net[&seat] + service[&seat] + taxes[&seat]));
        }
    }

    fn status(&self, index: usize) {
        let check = &self.checks[index];
        println!("STATUS table {} {} guests {} since {}", check.table, check.party, check.size, clock(check.seated));
        for line in &check.lines {
            let order = &self.orders[*line];
            println!("#{} seat {} {} x{} {} {}{}{}", line + 1, order.seat, order.item, order.quantity,
                     COURSES[order.course], order.state.name(),
                     if order.state == State::Cooking { format!(" until {}", clock(order.ready_time.unwrap())) }
                     else { String::new() }, order.comp_text());
        }
    }

    fn kitchen(&self) {
        println!("KITCHEN {}", clock(self.time));
        for (name, station) in STATIONS.iter().zip(&self.stations) {
            let mut cooking = station.cooking.clone();
            cooking.sort_by_key(|line| (self.orders[*line].ready_time.unwrap(), *line));
            let cooking = if cooking.is_empty() { "-".into() } else {
                cooking.iter().map(|line| format!("#{}@{}", line + 1, clock(self.orders[*line].ready_time.unwrap())))
                    .collect::<Vec<_>>().join(" ")
            };
            let queue = if station.queue.is_empty() { "-".into() } else {
                station.queue.iter().map(|line| format!("#{}", line + 1)).collect::<Vec<_>>().join(" ")
            };
            println!("{name} {} cooking {cooking} queue {queue}", if station.down { "down" } else { "up" });
        }
    }

    fn floor(&self) {
        let free = self.tables.values().filter(|table| table.check.is_none()).count();
        println!("FLOOR {} free {free} seated {} waiting {}", clock(self.time), self.tables.len() - free, self.waiting.len());
        for (number, table) in &self.tables {
            if let Some(index) = table.check {
                let check = &self.checks[index];
                let items = check.lines.iter().filter(|line| self.orders[**line].state != State::Void).count();
                println!("table {number} seats {} {} guests {} server {} since {} items {items} total {}{}", table.seats,
                         check.party, check.size, self.servers[check.server].name, clock(check.seated), money(self.amounts(index).total),
                         if check.paid > 0 { format!(" paid {}", money(check.paid)) } else { String::new() });
            } else { println!("table {number} seats {} free", table.seats); }
        }
        for (index, party) in self.waiting.iter().enumerate() {
            println!("WAITING {} {} {} since {}", index + 1, party.name, party.size, clock(party.joined));
        }
    }

    fn report(&self) {
        let stats = &self.statistics;
        println!("REPORT {}", clock(self.time));
        println!("COVERS {} parties {}", stats.covers, stats.parties);
        println!("TURNS {} avg_stay {}", stats.closed,
                 if stats.closed == 0 { "-".into() } else { (stats.stay / stats.closed).to_string() });
        println!("SALES DRINK {} STARTER {} MAIN {} DESSERT {}", money(stats.sales[0]), money(stats.sales[1]),
                 money(stats.sales[2]), money(stats.sales[3]));
        let amounts = stats.totals;
        println!("TOTALS subtotal {} discount {} service {} tax {} total {}", money(amounts.subtotal),
                 money(amounts.discount), money(amounts.service), money(amounts.tax), money(amounts.total));
        println!("PAYMENTS cash {} card {} tips {}", money(stats.payments[0]), money(stats.payments[1]), money(stats.tips));
        println!("COMPS {} {} VOIDS {}", stats.comps, money(stats.comp_amount), stats.voids);
        let mut served: Vec<(&String, &i64)> = stats.served.iter().filter(|(_, count)| **count > 0).collect();
        served.sort_by(|(left_name, left_count), (right_name, right_count)| right_count.cmp(left_count).then(left_name.cmp(right_name)));
        for (rank, (item, count)) in served.into_iter().take(3).enumerate() { println!("TOP {} {item} {count}", rank + 1); }
        for (name, station) in STATIONS.iter().zip(&self.stations) {
            println!("{name} tickets {} avg {} max {} remakes {}", station.tickets,
                     if station.tickets == 0 { "-".into() } else { (station.ticket_sum / station.tickets).to_string() },
                     if station.tickets == 0 { "-".into() } else { station.ticket_max.to_string() }, station.remakes);
        }
        for (index, server) in self.servers.iter().enumerate() {
            println!("SERVER {} tables {} parties {} sales {} tips {}", server.name, self.load(index),
                     server.parties, money(server.sales), money(server.tips));
        }
    }

    fn command(&mut self, tokens: &[&str]) -> Result<(), String> {
        let a = &tokens[1..];
        match tokens[0] {
            "TABLE" => {
                let table = number(a[0]);
                if self.tables.contains_key(&table) { return Err(format!("table {table} already exists")); }
                let seats = number(a[1]);
                self.tables.insert(table, Table { seats, check: None });
                println!("TABLE {table} seats {seats}");
                self.seat_waiting();
            }
            "STAFF" => {
                if self.servers.iter().any(|server| server.name == a[0]) { return Err(format!("{} is already on duty", a[0])); }
                self.servers.push(Server { name: a[0].into(), parties: 0, sales: 0, tips: 0 });
                println!("STAFF {}", a[0]);
            }
            "SEAT" => {
                if let Some(check) = self.checks.iter().find(|check| !check.closed && check.party == a[0]) {
                    return Err(format!("{} is already seated at table {}", a[0], check.table));
                }
                if self.waiting.iter().any(|party| party.name == a[0]) { return Err(format!("{} is already waiting", a[0])); }
                let size = number(a[1]);
                if !self.tables.values().any(|table| table.seats >= size) { return Err(format!("no table for party of {size}")); }
                if self.servers.is_empty() { return Err("no server on duty".into()); }
                if let Some(table) = self.choose_table(size) {
                    let server = self.seat(a[0], size, table);
                    println!("SEAT {} {size} table {table} server {}", a[0], self.servers[server].name);
                } else {
                    self.waiting.push(WaitingParty { name: a[0].into(), size, joined: self.time });
                    println!("WAIT {} {size} position {}", a[0], self.waiting.len());
                }
            }
            "CANCEL" => {
                let index = self.waiting.iter().position(|party| party.name == a[0])
                    .ok_or_else(|| format!("{} is not waiting", a[0]))?;
                let party = self.waiting.remove(index);
                println!("CANCEL {} {} waited {}", party.name, party.size, self.time - party.joined);
            }
            "MOVE" => {
                let (from, to) = (number(a[0]), number(a[1]));
                self.table(from)?;
                self.table(to)?;
                let index = self.check_index(from)?;
                if self.tables[&to].check.is_some() { return Err(format!("table {to} is occupied")); }
                if self.tables[&to].seats < self.checks[index].size {
                    return Err(format!("table {to} is too small for {}", self.checks[index].party));
                }
                self.tables.get_mut(&from).unwrap().check = None;
                self.tables.get_mut(&to).unwrap().check = Some(index);
                self.checks[index].table = to;
                println!("MOVE {} table {from} -> {to}", self.checks[index].party);
                self.seat_waiting();
            }
            "MENU" => {
                let station = station_index(a[1])?;
                let course = course_index(a[4])?;
                let action = if self.menu.contains_key(a[0]) { "UPDATE" } else { "ADD" };
                let stock = self.menu.get(a[0]).and_then(|item| item.stock);
                let (prep, price) = (number(a[2]), cents(a[3]));
                self.menu.insert(a[0].into(), MenuItem { station, course, prep, price, stock });
                println!("MENU {action} {} {} {prep} {} {}", a[0], a[1], money(price), a[4]);
            }
            "STOCK" => {
                let item = self.menu.get_mut(a[0]).ok_or_else(|| format!("unknown item {}", a[0]))?;
                let stock = number(a[1]);
                item.stock = Some(stock);
                println!("STOCK {} {stock}", a[0]);
            }
            "HAPPY" => {
                let (rate, end) = (number(a[0]), self.time + number(a[1]));
                self.happy = Some((rate, end));
                println!("HAPPY {rate}% until {}", clock(end));
            }
            "ITEMS" => {
                let mut items: Vec<(&String, &MenuItem)> = self.menu.iter().collect();
                items.sort_by(|(left_name, left), (right_name, right)| {
                    left.course.cmp(&right.course).then(left_name.cmp(right_name))
                });
                println!("ITEMS {}", items.len());
                for (name, item) in items {
                    println!("{} {name} {} {} {} {}", COURSES[item.course], STATIONS[item.station], item.prep,
                             money(item.price), item.stock.map(|stock| stock.to_string()).unwrap_or_else(|| "-".into()));
                }
            }
            "ORDER" => {
                let table = number(a[0]);
                let index = self.check_index(table)?;
                self.unlocked(index)?;
                let seat = number(a[1]);
                if seat > self.checks[index].size { return Err(format!("seat {seat} out of range for table {table}")); }
                let item = self.menu.get(a[2]).ok_or_else(|| format!("unknown item {}", a[2]))?;
                let quantity = number(a[3]);
                if let Some(stock) = item.stock {
                    if stock < quantity { return Err(format!("only {stock} {} left", a[2])); }
                }
                let happy = item.course == 0 && self.happy.is_some_and(|(_, end)| self.time < end);
                let unit_price = if happy { item.price - rounded(item.price, self.happy.unwrap().0) } else { item.price };
                let line = self.orders.len();
                self.orders.push(Order {
                    check: index, seat, item: a[2].into(), quantity, station: item.station,
                    prep: item.prep, course: item.course, unit_price, state: State::Ordered,
                    comp: None, fire_time: None, ready_time: None, started: false,
                });
                self.checks[index].lines.push(line);
                println!("ORDER #{} table {table} seat {seat} {} x{quantity} {}{}", line + 1, a[2],
                         money(unit_price * quantity), if happy { " HAPPY" } else { "" });
                if let Some(stock) = &mut self.menu.get_mut(a[2]).unwrap().stock {
                    *stock -= quantity;
                    if *stock == 0 { println!("SOLDOUT {}", a[2]); }
                }
            }
            "FIRE" => {
                let table = number(a[0]);
                let index = self.check_index(table)?;
                let course = course_index(a[1])?;
                let lines: Vec<usize> = self.checks[index].lines.iter().copied()
                    .filter(|line| self.orders[*line].course == course && self.orders[*line].state == State::Ordered).collect();
                if lines.is_empty() { return Err(format!("nothing to fire for {} at table {table}", a[1])); }
                for earlier in 1..course {
                    if self.checks[index].lines.iter().any(|line| self.orders[*line].course == earlier && self.orders[*line].state == State::Ordered) {
                        return Err(format!("fire {} first", COURSES[earlier]));
                    }
                }
                for line in &lines {
                    let order = &mut self.orders[*line];
                    order.state = State::Queued;
                    order.fire_time = Some(self.time);
                    self.stations[order.station].queue.push_back(*line);
                }
                println!("FIRE table {table} {} {}", a[1], numbers(&lines));
                for station in 0..4 { self.start_cooking(station, self.time); }
            }
            "TICK" => self.tick(number(a[0])),
            "SERVE" => {
                let table = number(a[0]);
                let index = self.check_index(table)?;
                let lines: Vec<usize> = self.checks[index].lines.iter().copied()
                    .filter(|line| self.orders[*line].state == State::Ready).collect();
                if lines.is_empty() { return Err(format!("nothing ready for table {table}")); }
                for line in &lines {
                    let order = &mut self.orders[*line];
                    order.state = State::Served;
                    *self.statistics.served.entry(order.item.clone()).or_default() += order.quantity;
                }
                println!("SERVE table {table} {}", numbers(&lines));
            }
            "RUSH" => {
                let index = self.order_index(a[0])?;
                let order = &self.orders[index];
                if order.state != State::Queued { return Err(format!("#{} is not queued", a[0])); }
                let station = &mut self.stations[order.station];
                station.queue.retain(|line| *line != index);
                station.queue.push_front(index);
                println!("RUSH #{} {}", a[0], STATIONS[order.station]);
            }
            "REMAKE" => {
                let index = self.order_index(a[0])?;
                let order = &mut self.orders[index];
                if self.checks[order.check].closed { return Err(format!("#{} is on a closed check", a[0])); }
                if !matches!(order.state, State::Ready | State::Served) { return Err(format!("#{} is not ready or served", a[0])); }
                order.state = State::Queued;
                order.fire_time = Some(self.time);
                let station = order.station;
                self.stations[station].queue.push_front(index);
                self.stations[station].remakes += 1;
                println!("REMAKE #{} {} {}", a[0], order.item, STATIONS[station]);
                self.start_cooking(station, self.time);
            }
            "VOID" => {
                let index = self.order_index(a[0])?;
                let order = &mut self.orders[index];
                if order.state == State::Void { return Err(format!("#{} is already void", a[0])); }
                if order.started { return Err(format!("#{} has already started", a[0])); }
                if order.state == State::Queued { self.stations[order.station].queue.retain(|line| *line != index); }
                order.state = State::Void;
                if let Some(stock) = &mut self.menu.get_mut(&order.item).unwrap().stock { *stock += order.quantity; }
                self.statistics.voids += 1;
                println!("VOID #{} {} x{}", a[0], order.item, order.quantity);
            }
            "STATION" => {
                let index = station_index(a[0])?;
                let down = a[1] == "DOWN";
                if down && self.stations[index].down { return Err(format!("station {} is already down", a[0])); }
                if !down && !self.stations[index].down { return Err(format!("station {} is not down", a[0])); }
                self.stations[index].down = down;
                if !down { self.start_cooking(index, self.time); }
                println!("STATION {} {}", a[0], a[1]);
            }
            "COMP" => {
                let index = self.order_index(a[0])?;
                self.modifiable(index)?;
                let order = &mut self.orders[index];
                if order.comp.is_some() { return Err(format!("#{} is already comped", a[0])); }
                let amount = order.amount();
                println!("COMP #{} {} {} {}", a[0], order.item, money(amount), a[1]);
                self.statistics.comps += 1;
                self.statistics.comp_amount += amount;
                order.comp = Some(a[1].into());
            }
            "TRANSFER" => {
                let index = self.order_index(a[0])?;
                self.modifiable(index)?;
                let order = &mut self.orders[index];
                let check = &self.checks[order.check];
                let seat = number(a[1]);
                if seat > check.size { return Err(format!("seat {seat} out of range for table {}", check.table)); }
                if seat == order.seat { return Err(format!("#{} is already on seat {seat}", a[0])); }
                println!("TRANSFER #{} seat {} -> {seat}", a[0], order.seat);
                order.seat = seat;
            }
            "DISCOUNT" => {
                let table = number(a[0]);
                let index = self.check_index(table)?;
                self.unlocked(index)?;
                let rate = number(a[1]);
                self.checks[index].discount = rate;
                println!("DISCOUNT table {table} {rate}%");
            }
            "BILL" => self.bill(self.check_index(number(a[0]))?),
            "SPLIT" => {
                let table = number(a[0]);
                let index = self.check_index(table)?;
                let check = &self.checks[index];
                let due = self.amounts(index).total - check.paid;
                if due == 0 { return Err(format!("nothing to split for table {table}")); }
                if a[1] == "EVEN" {
                    let count = number(a[2]);
                    if count > check.size { return Err(format!("cannot split table {table} {count} ways")); }
                    println!("SPLIT table {table} EVEN {count} due {}", money(due));
                    for payer in 1..=count {
                        println!("PAYER {payer} {}", money(due / count + if payer <= due % count { 1 } else { 0 }));
                    }
                } else {
                    if check.paid > 0 { return Err(format!("table {table} has payments")); }
                    self.split_by_seat(index);
                }
            }
            "PAY" => {
                let table = number(a[0]);
                let index = self.check_index(table)?;
                let method = match a[1] {
                    "CASH" => 0, "CARD" => 1, _ => return Err(format!("unknown method {}", a[1])),
                };
                self.all_served(index)?;
                let due = self.amounts(index).total - self.checks[index].paid;
                if due == 0 { return Err(format!("nothing to pay for table {table}")); }
                let amount = cents(a[2]);
                let applied = amount.min(due);
                self.checks[index].paid += applied;
                self.statistics.payments[method] += applied;
                if amount < due {
                    println!("PAY table {table} {} {} remaining {}", a[1], money(amount), money(due - amount));
                } else {
                    if method == 0 {
                        println!("PAY table {table} CASH {} change {}", money(amount), money(amount - due));
                    } else {
                        let tip = amount - due;
                        self.statistics.tips += tip;
                        self.servers[self.checks[index].server].tips += tip;
                        println!("PAY table {table} CARD {} tip {}", money(amount), money(tip));
                    }
                    self.close(index);
                }
            }
            "CLOSE" => {
                let table = number(a[0]);
                let index = self.check_index(table)?;
                self.all_served(index)?;
                let due = self.amounts(index).total - self.checks[index].paid;
                if due != 0 { return Err(format!("table {table} still owes {}", money(due))); }
                self.close(index);
            }
            "STATUS" => self.status(self.check_index(number(a[0]))?),
            "KITCHEN" => self.kitchen(),
            "FLOOR" => self.floor(),
            "REPORT" => self.report(),
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
    let mut restaurant = Restaurant::default();
    for line in lines.take(count) {
        let tokens: Vec<&str> = line.split_ascii_whitespace().collect();
        if let Err(error) = restaurant.command(&tokens) { println!("ERROR {error}"); }
    }
}
