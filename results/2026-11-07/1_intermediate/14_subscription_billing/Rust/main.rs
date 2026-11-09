use std::collections::{BTreeMap, VecDeque};
use std::io::{self, Read};

type Item = (String, i64);

fn number(text: &str) -> i64 {
    text.parse().unwrap()
}

fn cents(text: &str) -> i64 {
    let (whole, fraction) = text.split_once('.').unwrap();
    number(whole) * 100 + number(fraction)
}

fn money(amount: i64) -> String {
    let absolute = amount.abs();
    format!("{}{}.{:02}", if amount < 0 { "-" } else { "" }, absolute / 100, absolute % 100)
}

fn percent(bp: i64) -> String {
    format!("{}%", money(bp))
}

#[derive(Clone, Copy, PartialEq)]
enum State {
    None,
    Trialing,
    Active,
    PastDue,
    Unpaid,
    Paused,
    Canceled,
}

impl State {
    fn name(self) -> &'static str {
        match self {
            Self::None => "NONE",
            Self::Trialing => "TRIALING",
            Self::Active => "ACTIVE",
            Self::PastDue => "PAST_DUE",
            Self::Unpaid => "UNPAID",
            Self::Paused => "PAUSED",
            Self::Canceled => "CANCELED",
        }
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Metering {
    None,
    Graduated,
    Volume,
}

struct Tier {
    limit: Option<i64>,
    unit: i64,
    flat: i64,
}

struct Plan {
    price: i64,
    length: i64,
    trial: i64,
    setup: i64,
    per_seat: bool,
    metering: Metering,
    tiers: Vec<Tier>,
}

impl Plan {
    fn fee(&self, seats: i64) -> i64 {
        self.price * if self.per_seat { seats } else { 1 }
    }

    fn usage_charge(&self, usage: i64) -> i64 {
        let mut lower = 0;
        let mut charge = 0;
        for (index, tier) in self.tiers.iter().enumerate() {
            let upper = if index + 1 == self.tiers.len() {
                usage
            } else {
                tier.limit.unwrap()
            };
            if self.metering == Metering::Volume {
                if usage <= upper {
                    return usage * tier.unit + tier.flat;
                }
            } else if lower < usage {
                charge += (usage.min(upper) - lower) * tier.unit + tier.flat;
            }
            lower = upper;
        }
        charge
    }
}

struct Customer {
    region: String,
    payment_ok: bool,
    balance: i64,
    ledger: Vec<(i64, String, i64, i64)>,
}

struct Coupon {
    percentage: bool,
    value: i64,
    applications: Option<i64>,
    limit: Option<i64>,
    redemptions: i64,
}

#[derive(Clone)]
struct AppliedCoupon {
    name: String,
    remaining: Option<i64>,
}

#[derive(Clone)]
struct Subscription {
    customer: String,
    plan: String,
    seats: i64,
    state: State,
    period: (i64, i64),
    trial_end: Option<i64>,
    paused_since: Option<i64>,
    pending: Option<(String, i64)>,
    cancel_end: bool,
    cancel_day: Option<i64>,
    canceled_day: Option<i64>,
    coupon: Option<AppliedCoupon>,
    usage: i64,
}

struct Charges {
    subtotal: i64,
    discount: i64,
    tax: i64,
    total: i64,
    credit: i64,
    due: i64,
}

impl Charges {
    fn print(&self) {
        println!("  subtotal {} discount {} tax {} total {}", money(self.subtotal),
                 money(self.discount), money(self.tax), money(self.total));
    }
}

struct Invoice {
    sub: usize,
    customer: String,
    day: i64,
    kind: &'static str,
    items: Vec<Item>,
    charges: Charges,
    paid: i64,
    refunded: i64,
    outstanding: i64,
    attempts: usize,
    retries: VecDeque<i64>,
}

struct Billing {
    day: i64,
    plans: BTreeMap<String, Plan>,
    taxes: BTreeMap<String, i64>,
    customers: BTreeMap<String, Customer>,
    coupons: BTreeMap<String, Coupon>,
    subs: Vec<Subscription>,
    invoices: Vec<Invoice>,
    events: Vec<(i64, usize, State, State)>,
}

impl Billing {
    fn new() -> Self {
        Self {
            day: 1,
            plans: BTreeMap::new(),
            taxes: BTreeMap::new(),
            customers: BTreeMap::new(),
            coupons: BTreeMap::new(),
            subs: Vec::new(),
            invoices: Vec::new(),
            events: Vec::new(),
        }
    }

    fn customer(&self, name: &str) -> Result<&Customer, String> {
        self.customers.get(name).ok_or_else(|| format!("unknown customer {name}"))
    }

    fn plan(&self, name: &str) -> Result<&Plan, String> {
        self.plans.get(name).ok_or_else(|| format!("unknown plan {name}"))
    }

    fn sub_index(&self, text: &str) -> Result<usize, String> {
        let id: usize = text.parse().unwrap();
        if id == 0 || id > self.subs.len() {
            Err(format!("unknown sub {text}"))
        } else {
            Ok(id - 1)
        }
    }

    fn invoice_index(&self, text: &str) -> Result<usize, String> {
        let id: usize = text.parse().unwrap();
        if id == 0 || id > self.invoices.len() {
            Err(format!("unknown invoice {text}"))
        } else {
            Ok(id - 1)
        }
    }

    fn check_state(&self, index: usize, allowed: &[State]) -> Result<(), String> {
        let state = self.subs[index].state;
        if allowed.contains(&state) {
            Ok(())
        } else {
            Err(format!("invalid state {} {}", index + 1, state.name()))
        }
    }

    fn check_coupon(&self, name: &str) -> Result<(), String> {
        let coupon = self.coupons.get(name).ok_or_else(|| format!("unknown coupon {name}"))?;
        if coupon.limit == Some(coupon.redemptions) {
            Err(format!("coupon exhausted {name}"))
        } else {
            Ok(())
        }
    }

    fn redeem(&mut self, name: &str) -> AppliedCoupon {
        let coupon = self.coupons.get_mut(name).unwrap();
        coupon.redemptions += 1;
        AppliedCoupon { name: name.into(), remaining: coupon.applications }
    }

    fn balance_change(&mut self, name: &str, description: String, change: i64) {
        if change != 0 {
            let customer = self.customers.get_mut(name).unwrap();
            customer.balance += change;
            customer.ledger.push((self.day, description, change, customer.balance));
        }
    }

    fn change_state(&mut self, index: usize, new: State) {
        let old = self.subs[index].state;
        if old == State::PastDue {
            for invoice in &mut self.invoices {
                if invoice.sub == index {
                    invoice.retries.clear();
                }
            }
        }
        self.subs[index].state = new;
        println!("  day {} sub {} {} -> {}", self.day, index + 1, old.name(), new.name());
        self.events.push((self.day, index, old, new));
    }

    fn charge_item(&self, plan: &str, seats: i64, start: i64) -> Item {
        let pricing = &self.plans[plan];
        (format!("charge {plan} seats {seats} {start}-{}", start + pricing.length),
         pricing.fee(seats))
    }

    fn opening_items(&self, index: usize, start: i64) -> Vec<Item> {
        let sub = &self.subs[index];
        let mut items = vec![self.charge_item(&sub.plan, sub.seats, start)];
        let setup = self.plans[&sub.plan].setup;
        if setup > 0 {
            items.push((format!("setup {}", sub.plan), setup));
        }
        items
    }

    fn usage_item(&self, index: usize) -> Option<Item> {
        let sub = &self.subs[index];
        let plan = &self.plans[&sub.plan];
        if plan.metering != Metering::None && sub.usage > 0 {
            Some((format!("usage {} {} units", sub.plan, sub.usage), plan.usage_charge(sub.usage)))
        } else {
            None
        }
    }

    fn close_usage(&mut self, index: usize) -> Vec<Item> {
        let item = self.usage_item(index);
        if item.is_some() {
            self.subs[index].usage = 0;
        }
        item.into_iter().collect()
    }

    fn calculate(&self, index: usize, items: &[Item]) -> Charges {
        let sub = &self.subs[index];
        let customer = &self.customers[&sub.customer];
        let subtotal: i64 = items.iter().map(|item| item.1).sum();
        let mut discount = 0;
        if let Some(applied) = &sub.coupon {
            if applied.remaining != Some(0) && subtotal > 0 {
                let coupon = &self.coupons[&applied.name];
                discount = if coupon.percentage { subtotal * coupon.value / 10000 }
                           else { subtotal.min(coupon.value) };
            }
        }
        let tax = (subtotal - discount) * self.taxes.get(&customer.region).copied().unwrap_or(0) / 10000;
        let total = subtotal - discount + tax;
        let credit = customer.balance.min(total);
        Charges { subtotal, discount, tax, total, credit, due: total - credit }
    }

    fn issue(&mut self, index: usize, kind: &'static str, items: Vec<Item>) {
        let charges = self.calculate(index, &items);
        if charges.subtotal > 0 {
            if let Some(applied) = &mut self.subs[index].coupon {
                if let Some(left) = &mut applied.remaining {
                    if *left > 0 {
                        *left -= 1;
                    }
                }
            }
        }
        let customer = self.subs[index].customer.clone();
        let id = self.invoices.len() + 1;
        self.balance_change(&customer, format!("applied invoice {id}"), -charges.credit);
        let (result, attempts, paid) = if charges.due == 0 {
            ("PAID", 0, 0)
        } else if self.subs[index].state == State::Unpaid {
            ("OPEN", 0, 0)
        } else if self.customers[&customer].payment_ok {
            ("PAID", 1, charges.due)
        } else {
            ("FAILED", 1, 0)
        };
        println!("  day {} invoice {id} sub {} {kind} total {} credit {} due {} {result}",
                 self.day, index + 1, money(charges.total), money(charges.credit), money(charges.due));
        self.invoices.push(Invoice {
            sub: index, customer, day: self.day, kind, items,
            outstanding: charges.due - paid, charges, paid, refunded: 0,
            attempts, retries: VecDeque::new(),
        });
        if result == "FAILED" {
            if self.subs[index].state == State::Active {
                self.change_state(index, State::PastDue);
            }
            if self.subs[index].state == State::PastDue {
                self.invoices[id - 1].retries = [self.day + 3, self.day + 5, self.day + 7].into();
            }
        }
    }

    fn payment_complete(&mut self, invoice: usize) {
        self.invoices[invoice].retries.clear();
        let index = self.invoices[invoice].sub;
        if matches!(self.subs[index].state, State::PastDue | State::Unpaid)
            && self.invoices.iter().all(|bill| bill.sub != index || bill.outstanding == 0)
        {
            self.subs[index].cancel_day = None;
            self.change_state(index, State::Active);
        }
    }

    fn cancel(&mut self, index: usize) {
        self.change_state(index, State::Canceled);
        let sub = &mut self.subs[index];
        sub.canceled_day = Some(self.day);
        sub.pending = None;
        sub.cancel_end = false;
        sub.cancel_day = None;
        let items = self.close_usage(index);
        if !items.is_empty() {
            self.issue(index, "final", items);
        }
    }

    fn advance(&mut self, target: i64) {
        while self.day < target {
            self.day += 1;
            for index in 0..self.subs.len() {
                if matches!(self.subs[index].state, State::Paused | State::Canceled) {
                    continue;
                }
                for invoice in 0..self.invoices.len() {
                    if self.invoices[invoice].sub != index
                        || self.invoices[invoice].retries.front() != Some(&self.day)
                    {
                        continue;
                    }
                    let bill = &mut self.invoices[invoice];
                    bill.retries.pop_front();
                    bill.attempts += 1;
                    let retry = bill.attempts - 1;
                    if self.customers[&bill.customer].payment_ok {
                        bill.paid += bill.outstanding;
                        bill.outstanding = 0;
                        println!("  day {} retry {retry} invoice {} PAID", self.day, invoice + 1);
                        self.payment_complete(invoice);
                    } else {
                        println!("  day {} retry {retry} invoice {} FAILED", self.day, invoice + 1);
                        if bill.retries.is_empty() {
                            self.change_state(index, State::Unpaid);
                            self.subs[index].cancel_day = Some(self.day + 14);
                        }
                    }
                }
                if self.subs[index].state == State::Unpaid && self.subs[index].cancel_day == Some(self.day) {
                    self.cancel(index);
                }
                if self.subs[index].state == State::Trialing && self.subs[index].trial_end == Some(self.day) {
                    if self.subs[index].cancel_end {
                        self.cancel(index);
                    } else {
                        self.change_state(index, State::Active);
                        let length = self.plans[&self.subs[index].plan].length;
                        self.subs[index].period = (self.day, self.day + length);
                        self.issue(index, "first", self.opening_items(index, self.day));
                    }
                }
                if matches!(self.subs[index].state, State::Active | State::PastDue | State::Unpaid)
                    && self.subs[index].period.1 == self.day
                {
                    if self.subs[index].cancel_end {
                        self.cancel(index);
                    } else {
                        let mut items = self.close_usage(index);
                        let sub = &mut self.subs[index];
                        if let Some((plan, seats)) = sub.pending.take() {
                            println!("  day {} sub {} {} seats {} -> {plan} seats {seats}",
                                     self.day, index + 1, sub.plan, sub.seats);
                            sub.plan = plan;
                            sub.seats = seats;
                        }
                        sub.period = (self.day, self.day + self.plans[&sub.plan].length);
                        items.push(self.charge_item(&self.subs[index].plan, self.subs[index].seats, self.day));
                        self.issue(index, "renewal", items);
                    }
                }
            }
        }
    }

    fn show_invoice(&self, index: usize) {
        let bill = &self.invoices[index];
        let charge = &bill.charges;
        println!("INVOICE {} sub {} {} day {} {} {}", index + 1, bill.sub + 1,
                 bill.customer, bill.day, bill.kind, if bill.outstanding == 0 { "PAID" } else { "OPEN" });
        for (description, amount) in &bill.items {
            println!("  {description} {}", money(*amount));
        }
        charge.print();
        println!("  credit {} due {} paid {} refunded {} outstanding {}", money(charge.credit),
                 money(charge.due), money(bill.paid), money(bill.refunded), money(bill.outstanding));
    }

    fn show_sub(&self, index: usize) {
        let sub = &self.subs[index];
        println!("SUB {} {} {} seats {} {}", index + 1, sub.customer, sub.plan, sub.seats, sub.state.name());
        if sub.state == State::Trialing {
            println!("  trial until {}", sub.trial_end.unwrap());
        }
        if matches!(sub.state, State::Active | State::PastDue | State::Unpaid | State::Paused) {
            println!("  period {}-{}", sub.period.0, sub.period.1);
        }
        if sub.state == State::Paused {
            println!("  paused since {}", sub.paused_since.unwrap());
        }
        if let Some((plan, seats)) = &sub.pending {
            println!("  pending {plan} seats {seats}");
        }
        if sub.cancel_end {
            println!("  cancel at end");
        }
        if let Some(day) = sub.cancel_day {
            println!("  cancel on {day}");
        }
        if sub.state == State::Canceled {
            println!("  canceled on {}", sub.canceled_day.unwrap());
        }
        if let Some(coupon) = &sub.coupon {
            match coupon.remaining {
                None => println!("  coupon {} forever", coupon.name),
                Some(left) if left > 0 => println!("  coupon {} left {left}", coupon.name),
                _ => {}
            }
        }
        if self.plans[&sub.plan].metering != Metering::None && sub.state != State::Canceled {
            println!("  usage {}", sub.usage);
        }
        let open: Vec<String> = self.invoices.iter().enumerate()
            .filter(|(_, bill)| bill.sub == index && bill.outstanding > 0)
            .map(|(id, _)| (id + 1).to_string()).collect();
        if !open.is_empty() {
            println!("  open {}", open.join(" "));
        }
    }

    fn preview(&self, index: usize) {
        let sub = &self.subs[index];
        let due = if sub.state == State::Trialing { sub.trial_end.unwrap() } else { sub.period.1 };
        let (kind, items) = if sub.cancel_end {
            ("final", if sub.state == State::Trialing { Vec::new() }
                      else { self.usage_item(index).into_iter().collect() })
        } else if sub.state == State::Trialing {
            ("first", self.opening_items(index, due))
        } else {
            let mut items: Vec<Item> = self.usage_item(index).into_iter().collect();
            let (plan, seats) = sub.pending.as_ref()
                .map(|(plan, seats)| (plan.as_str(), *seats)).unwrap_or((&sub.plan, sub.seats));
            items.push(self.charge_item(plan, seats, due));
            ("renewal", items)
        };
        println!("PREVIEW sub {} day {due} {kind}", index + 1);
        if items.is_empty() {
            println!("  (none)");
        } else {
            for (description, amount) in &items {
                println!("  {description} {}", money(*amount));
            }
            let charges = self.calculate(index, &items);
            charges.print();
            println!("  credit {} due {}", money(charges.credit), money(charges.due));
        }
    }

    fn statement(&self, name: &str) {
        let customer = &self.customers[name];
        println!("STATEMENT {name} region {} tax {} method {} balance {}", customer.region,
                 percent(self.taxes.get(&customer.region).copied().unwrap_or(0)),
                 if customer.payment_ok { "OK" } else { "FAIL" }, money(customer.balance));
        for (index, sub) in self.subs.iter().enumerate() {
            if sub.customer == name {
                println!("  sub {} {} {}", index + 1, sub.plan, sub.state.name());
            }
        }
        let mut outstanding = 0;
        for (index, bill) in self.invoices.iter().enumerate() {
            if bill.customer == name {
                println!("  invoice {} day {} sub {} {} total {} outstanding {}", index + 1,
                         bill.day, bill.sub + 1, bill.kind, money(bill.charges.total), money(bill.outstanding));
                outstanding += bill.outstanding;
            }
        }
        println!("  outstanding {}", money(outstanding));
    }

    fn mrr(&self) {
        let mut plans: BTreeMap<&str, (usize, i64)> = BTreeMap::new();
        let (mut count, mut total) = (0, 0);
        for sub in &self.subs {
            if matches!(sub.state, State::Active | State::PastDue) {
                let plan = &self.plans[&sub.plan];
                let fee = plan.fee(sub.seats);
                let monthly = match plan.length {
                    7 => fee * 30 / 7,
                    360 => fee / 12,
                    _ => fee,
                };
                let row = plans.entry(&sub.plan).or_default();
                row.0 += 1;
                row.1 += monthly;
                count += 1;
                total += monthly;
            }
        }
        println!("MRR");
        for (plan, (count, total)) in plans {
            println!("  {plan} subs {count} mrr {}", money(total));
        }
        println!("  total subs {count} mrr {}", money(total));
    }

    fn aging(&self) {
        let mut customers: BTreeMap<&str, [i64; 3]> = BTreeMap::new();
        let mut total = [0; 3];
        for bill in &self.invoices {
            if bill.outstanding > 0 {
                let age = self.day - bill.day;
                let bucket = if age <= 30 { 0 } else if age <= 60 { 1 } else { 2 };
                customers.entry(&bill.customer).or_default()[bucket] += bill.outstanding;
                total[bucket] += bill.outstanding;
            }
        }
        println!("AGING day {}", self.day);
        for (name, buckets) in customers.into_iter().chain(std::iter::once(("total", total))) {
            println!("  {name} 0-30 {} 31-60 {} 61+ {} sum {}", money(buckets[0]),
                     money(buckets[1]), money(buckets[2]), money(buckets.iter().sum()));
        }
    }

    fn revenue(&self) {
        let mut totals = [0; 8];
        for bill in &self.invoices {
            let values = [bill.charges.subtotal, bill.charges.discount, bill.charges.tax,
                          bill.charges.total, bill.charges.credit, bill.paid, bill.refunded, bill.outstanding];
            for (total, value) in totals.iter_mut().zip(values) {
                *total += value;
            }
        }
        let balances = self.customers.values().map(|customer| customer.balance).sum();
        println!("REVENUE");
        println!("  invoices {} subtotal {} discount {} tax {} total {}", self.invoices.len(),
                 money(totals[0]), money(totals[1]), money(totals[2]), money(totals[3]));
        println!("  credit {} paid {} refunded {} outstanding {} balances {}", money(totals[4]),
                 money(totals[5]), money(totals[6]), money(totals[7]), money(balances));
    }

    fn command(&mut self, parts: &[&str]) -> Result<(), String> {
        let a = &parts[1..];
        match parts[0] {
            "PLAN" => {
                if self.plans.contains_key(a[0]) {
                    return Err(format!("duplicate plan {}", a[0]));
                }
                let mut plan = Plan {
                    price: cents(a[1]), length: match a[2] { "WEEKLY" => 7, "MONTHLY" => 30, _ => 360 },
                    trial: 0, setup: 0, per_seat: false, metering: Metering::None, tiers: Vec::new(),
                };
                let mut position = 3;
                while position < a.len() {
                    match a[position] {
                        "TRIAL" => { plan.trial = number(a[position + 1]); position += 1; }
                        "SETUP" => { plan.setup = cents(a[position + 1]); position += 1; }
                        "PERSEAT" => plan.per_seat = true,
                        "GRADUATED" => plan.metering = Metering::Graduated,
                        "VOLUME" => plan.metering = Metering::Volume,
                        _ => unreachable!(),
                    }
                    position += 1;
                }
                let mut line = format!("PLAN {} {} {}", a[0], a[2], money(plan.price));
                if plan.trial > 0 { line.push_str(&format!(" trial {}", plan.trial)); }
                if plan.setup > 0 { line.push_str(&format!(" setup {}", money(plan.setup))); }
                if plan.per_seat { line.push_str(" perseat"); }
                match plan.metering {
                    Metering::Graduated => line.push_str(" graduated"),
                    Metering::Volume => line.push_str(" volume"),
                    Metering::None => {}
                }
                self.plans.insert(a[0].into(), plan);
                println!("{line}");
            }
            "TIER" => {
                let plan = self.plan(a[0])?;
                if plan.metering == Metering::None { return Err(format!("not metered {}", a[0])); }
                let limit = if a[1] == "INF" { None } else { Some(number(a[1])) };
                if let Some(last) = plan.tiers.last() {
                    if last.limit.is_none() || limit.is_some_and(|value| value <= last.limit.unwrap()) {
                        return Err(format!("tier order {}", a[0]));
                    }
                }
                let plan = self.plans.get_mut(a[0]).unwrap();
                plan.tiers.push(Tier { limit, unit: cents(a[2]), flat: cents(a[3]) });
                println!("TIER {} {} upto {} unit {} flat {}", a[0], plan.tiers.len(), a[1], a[2], a[3]);
            }
            "TAX" => {
                let rate = number(a[1]);
                self.taxes.insert(a[0].into(), rate);
                println!("TAX {} {}", a[0], percent(rate));
            }
            "CUSTOMER" => {
                if self.customers.contains_key(a[0]) { return Err(format!("duplicate customer {}", a[0])); }
                self.customers.insert(a[0].into(), Customer {
                    region: a[1].into(), payment_ok: true, balance: 0, ledger: Vec::new(),
                });
                println!("CUSTOMER {} region {}", a[0], a[1]);
            }
            "COUPON" => {
                if self.coupons.contains_key(a[0]) { return Err(format!("duplicate coupon {}", a[0])); }
                let percentage = a[1] == "PERCENT";
                let value = if percentage { number(a[2]) } else { cents(a[2]) };
                let (applications, application, position) = match a[3] {
                    "ONCE" => (Some(1), "once".to_string(), 4),
                    "FOREVER" => (None, "forever".to_string(), 4),
                    _ => (Some(number(a[4])), format!("repeating {}", a[4]), 5),
                };
                let limit = if position < a.len() { Some(number(a[position + 1])) } else { None };
                self.coupons.insert(a[0].into(), Coupon { percentage, value, applications, limit, redemptions: 0 });
                let discount = if percentage { format!("percent {}", percent(value)) }
                               else { format!("amount {}", money(value)) };
                println!("COUPON {} {discount} {application}{}", a[0],
                         limit.map(|count| format!(" max {count}")).unwrap_or_default());
            }
            "PAYMETHOD" => {
                self.customer(a[0])?;
                self.customers.get_mut(a[0]).unwrap().payment_ok = a[1] == "OK";
                println!("PAYMETHOD {} {}", a[0], a[1]);
            }
            "CREDIT" => {
                self.customer(a[0])?;
                let amount = cents(a[1]);
                if amount == 0 { return Err("invalid amount".into()); }
                self.balance_change(a[0], "grant".into(), amount);
                println!("CREDIT {} amount {} balance {}", a[0], money(amount), money(self.customers[a[0]].balance));
            }
            "DAY" => {
                let day = number(a[0]);
                if day <= self.day { return Err(format!("invalid day {}", a[0])); }
                println!("DAY {day}");
                self.advance(day);
            }
            "SUBSCRIBE" => {
                self.customer(a[0])?;
                let plan = self.plan(a[1])?;
                let mut position = 2;
                let explicit_seats = a.get(position) == Some(&"SEATS");
                if explicit_seats && !plan.per_seat { return Err(format!("not per-seat {}", a[1])); }
                let seats = if explicit_seats { position += 2; number(a[3]) } else { 1 };
                if seats == 0 { return Err("invalid seats".into()); }
                let coupon_name = if position < a.len() { Some(a[position + 1]) } else { None };
                if let Some(name) = coupon_name { self.check_coupon(name)?; }
                let (trial, length) = (plan.trial, plan.length);
                let coupon = coupon_name.map(|name| self.redeem(name));
                let index = self.subs.len();
                self.subs.push(Subscription {
                    customer: a[0].into(), plan: a[1].into(), seats, state: State::None,
                    period: (self.day, self.day + length),
                    trial_end: if trial > 0 { Some(self.day + trial) } else { None },
                    paused_since: None, pending: None, cancel_end: false,
                    cancel_day: None, canceled_day: None, coupon, usage: 0,
                });
                println!("SUBSCRIBE sub {} {} {} seats {seats}{}", index + 1, a[0], a[1],
                         coupon_name.map(|name| format!(" coupon {name}")).unwrap_or_default());
                if trial > 0 {
                    self.change_state(index, State::Trialing);
                } else {
                    self.change_state(index, State::Active);
                    self.issue(index, "first", self.opening_items(index, self.day));
                }
            }
            "CHANGE" => {
                let index = self.sub_index(a[0])?;
                self.check_state(index, &[State::Active, State::Trialing])?;
                let old = self.subs[index].clone();
                let old_plan = &self.plans[&old.plan];
                let (new_plan, seats) = if a[1] == "PLAN" {
                    let plan = self.plan(a[2])?;
                    (a[2], if plan.per_seat { old.seats } else { 1 })
                } else {
                    if !old_plan.per_seat { return Err(format!("not per-seat {}", old.plan)); }
                    let seats = number(a[2]);
                    if seats == 0 { return Err("invalid seats".into()); }
                    (old.plan.as_str(), seats)
                };
                if new_plan == old.plan && seats == old.seats { return Err(format!("no change {}", a[0])); }
                let (old_fee, old_length) = (old_plan.fee(old.seats), old_plan.length);
                let plan = &self.plans[new_plan];
                let (new_fee, new_length) = (plan.fee(seats), plan.length);
                self.subs[index].pending = None;
                let head = format!("CHANGE sub {} {} seats {} -> {new_plan} seats {seats}", a[0], old.plan, old.seats);
                if old.state == State::Trialing {
                    self.subs[index].plan = new_plan.into();
                    self.subs[index].seats = seats;
                    println!("{head} now");
                } else if new_fee * old_length > old_fee * new_length {
                    println!("{head} now");
                    let remaining = old.period.1 - self.day;
                    let mut items = self.close_usage(index);
                    items.push((format!("unused {} seats {} {remaining} days", old.plan, old.seats),
                                -(old_fee * remaining / old_length)));
                    items.push((format!("remaining {new_plan} seats {seats} {remaining} days"),
                                new_fee * remaining / new_length));
                    self.subs[index].plan = new_plan.into();
                    self.subs[index].seats = seats;
                    self.issue(index, "upgrade", items);
                } else {
                    self.subs[index].pending = Some((new_plan.into(), seats));
                    println!("{head} at {}", old.period.1);
                }
            }
            "PAUSE" => {
                let index = self.sub_index(a[0])?;
                self.check_state(index, &[State::Active])?;
                self.subs[index].paused_since = Some(self.day);
                println!("PAUSE sub {}", a[0]);
                self.change_state(index, State::Paused);
            }
            "RESUME" => {
                let index = self.sub_index(a[0])?;
                self.check_state(index, &[State::Paused])?;
                let sub = &mut self.subs[index];
                let shift = self.day - sub.paused_since.take().unwrap();
                sub.period.1 += shift;
                println!("RESUME sub {} shift {shift} period {}-{}", a[0], sub.period.0, sub.period.1);
                self.change_state(index, State::Active);
            }
            "CANCEL" => {
                let index = self.sub_index(a[0])?;
                let sub = self.subs[index].clone();
                if a[1] == "END" {
                    self.check_state(index, &[State::Active, State::Trialing])?;
                    if sub.cancel_end { return Err(format!("already canceling {}", a[0])); }
                    self.subs[index].cancel_end = true;
                    let day = if sub.state == State::Trialing { sub.trial_end.unwrap() } else { sub.period.1 };
                    println!("CANCEL sub {} end {day}", a[0]);
                } else {
                    if sub.state == State::Canceled { return Err(format!("invalid state {} CANCELED", a[0])); }
                    let plan = &self.plans[&sub.plan];
                    let remaining = match sub.state {
                        State::Active => sub.period.1 - self.day,
                        State::Paused => sub.period.1 - sub.paused_since.unwrap(),
                        _ => 0,
                    };
                    let refund = plan.fee(sub.seats) * remaining / plan.length;
                    self.balance_change(&sub.customer, format!("cancel sub {}", a[0]), refund);
                    println!("CANCEL sub {} now credit {}", a[0], money(refund));
                    self.cancel(index);
                }
            }
            "USAGE" => {
                let index = self.sub_index(a[0])?;
                self.check_state(index, &[State::Active, State::PastDue])?;
                let sub = &mut self.subs[index];
                if self.plans[&sub.plan].metering == Metering::None { return Err(format!("not metered {}", sub.plan)); }
                let units = number(a[1]);
                if units == 0 { return Err("invalid units".into()); }
                sub.usage += units;
                println!("USAGE sub {} units {units} total {}", a[0], sub.usage);
            }
            "APPLY" => {
                let index = self.sub_index(a[0])?;
                if self.subs[index].state == State::Canceled { return Err(format!("invalid state {} CANCELED", a[0])); }
                self.check_coupon(a[1])?;
                let coupon = self.redeem(a[1]);
                self.subs[index].coupon = Some(coupon);
                println!("APPLY sub {} coupon {}", a[0], a[1]);
            }
            "PAY" => {
                let index = self.invoice_index(a[0])?;
                let bill = &mut self.invoices[index];
                if bill.outstanding == 0 { return Err(format!("already paid {}", a[0])); }
                println!("PAY invoice {} amount {}", a[0], money(bill.outstanding));
                bill.paid += bill.outstanding;
                bill.outstanding = 0;
                self.payment_complete(index);
            }
            "REFUND" => {
                let index = self.invoice_index(a[0])?;
                let amount = cents(a[1]);
                if amount == 0 { return Err("invalid amount".into()); }
                let bill = &mut self.invoices[index];
                if amount > bill.charges.total - bill.refunded {
                    return Err(format!("refund exceeds {} {}", a[0], money(bill.charges.total - bill.refunded)));
                }
                let applied = amount.min(bill.outstanding);
                bill.refunded += amount;
                bill.outstanding -= applied;
                let completed = applied > 0 && bill.outstanding == 0;
                let customer = bill.customer.clone();
                self.balance_change(&customer, format!("refund invoice {}", a[0]), amount - applied);
                println!("REFUND invoice {} amount {} applied {} balance {}", a[0], money(amount),
                         money(applied), money(self.customers[&customer].balance));
                if completed { self.payment_complete(index); }
            }
            "INVOICE" => self.show_invoice(self.invoice_index(a[0])?),
            "SUB" => self.show_sub(self.sub_index(a[0])?),
            "PREVIEW" => {
                let index = self.sub_index(a[0])?;
                self.check_state(index, &[State::Trialing, State::Active, State::PastDue, State::Unpaid])?;
                self.preview(index);
            }
            "STATEMENT" => {
                self.customer(a[0])?;
                self.statement(a[0]);
            }
            "LEDGER" => {
                let customer = self.customer(a[0])?;
                println!("LEDGER {} balance {}", a[0], money(customer.balance));
                for (day, description, change, balance) in &customer.ledger {
                    println!("  day {day} {description} {}{} balance {}", if *change > 0 { "+" } else { "" },
                             money(*change), money(*balance));
                }
                if customer.ledger.is_empty() { println!("  (none)"); }
            }
            "MRR" => self.mrr(),
            "AGING" => self.aging(),
            "DUNNING" => {
                println!("DUNNING");
                let mut found = false;
                for (index, bill) in self.invoices.iter().enumerate() {
                    if let Some(next) = bill.retries.front() {
                        found = true;
                        println!("  invoice {} sub {} {} outstanding {} attempts {} next {next}",
                                 index + 1, bill.sub + 1, bill.customer, money(bill.outstanding), bill.attempts);
                    }
                }
                if !found { println!("  (none)"); }
            }
            "REVENUE" => self.revenue(),
            "EVENTS" => {
                let selected = if a.is_empty() { None } else { Some(self.sub_index(a[0])?) };
                println!("EVENTS{}", selected.map(|id| format!(" sub {}", id + 1)).unwrap_or_default());
                let mut found = false;
                for (day, index, old, new) in &self.events {
                    if selected.is_none() || selected == Some(*index) {
                        found = true;
                        println!("  day {day} sub {} {} -> {}", index + 1, old.name(), new.name());
                    }
                }
                if !found { println!("  (none)"); }
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
    let mut billing = Billing::new();
    for line in lines.take(count) {
        let parts: Vec<&str> = line.split_ascii_whitespace().collect();
        if let Err(error) = billing.command(&parts) {
            println!("ERROR {error}");
        }
    }
}
