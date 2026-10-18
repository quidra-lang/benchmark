use std::collections::{BTreeMap, HashSet};
use std::io::{self, BufRead, Write};

type Integer = i64;
struct Member { name: String, active: bool, day: Integer }
#[derive(Clone)]
struct Part { member: usize, value: Integer, result: Integer }
#[derive(Clone, Default)]
struct Expense {
    id: String,
    currency: String,
    category: String,
    mode: String,
    day: Integer,
    serial: Integer,
    amount: Integer,
    total: Integer,
    interval: Integer,
    next: Integer,
    copies: Integer,
    payers: Vec<Part>,
    participants: Vec<Part>,
}
struct Settlement { from: usize, to: usize, amount: Integer, total: Integer, day: Integer, serial: Integer, currency: String }
struct Transfer { from: usize, to: usize, amount: Integer }
#[derive(Default)]
struct Engine {
    members: Vec<Member>,
    expenses: Vec<Expense>,
    settlements: Vec<Settlement>,
    currencies: BTreeMap<String, Integer>,
    budgets: BTreeMap<String, Integer>,
    used: HashSet<String>,
    day: Integer,
    serial: Integer,
}
fn integer(s: &str) -> Integer { s.parse().unwrap() }
fn amount(s: &str) -> Integer {
    let (a, b) = s.split_once('.').unwrap();
    integer(a)*100+integer(b)
}
fn money(n: Integer) -> String { format!("{}.{:02}", n/100, n%100) }
fn signed_money(n: Integer) -> String {
    if n > 0 { format!("+{}", money(n)) }
    else if n < 0 { format!("-{}", money(-n)) }
    else { "0.00".to_owned() }
}
fn rate_text(n: Integer) -> String { format!("{}.{:04}", n/10000, n%10000) }
fn percentage(p: Integer, w: Integer) -> String { format!("{}%", money(p*10000/w)) }
fn amount_spec(s: &str) -> (Integer, String) {
    let (value, currency) = s.split_once('@').unwrap_or((s, ""));
    (amount(value), currency.to_owned())
}
fn note(value: Integer, currency: &str) -> String {
    if currency.is_empty() { String::new() } else { format!(" [{} {currency}]", money(value)) }
}
fn distribute(total: Integer, weights: &[Integer]) -> Vec<Integer> {
    let sum: Integer = weights.iter().sum();
    let mut result: Vec<Integer> = weights.iter().map(|w| total*w/sum).collect();
    let remainders: Vec<Integer> = weights.iter().map(|w| total*w%sum).collect();
    let left = total-result.iter().sum::<Integer>();
    let mut order: Vec<usize> = (0..weights.len()).collect();
    order.sort_by(|&i, &j| remainders[j].cmp(&remainders[i]));
    for &i in &order[..left as usize] { result[i] += 1; }
    result
}
fn equal_distribution(total: Integer, count: usize) -> Vec<Integer> {
    (0..count).map(|i| total/count as Integer+Integer::from((i as Integer) < total%count as Integer)).collect()
}
fn contributions(e: &mut Expense) {
    let weights: Vec<Integer> = e.payers.iter().map(|p| p.value).collect();
    for (p, value) in e.payers.iter_mut().zip(distribute(e.total, &weights)) { p.result = value; }
}
fn net(e: &Expense, count: usize) -> Vec<Integer> {
    let mut result = vec![0; count];
    for p in &e.payers { result[p.member] += p.result; }
    for p in &e.participants { result[p.member] -= p.result; }
    result
}
fn involved(e: &Expense, id: usize) -> bool {
    e.payers.iter().chain(&e.participants).any(|p| p.member == id)
}
fn greedy(group: &[usize], original: &[Integer]) -> Vec<Transfer> {
    let mut values = original.to_vec();
    let mut result = Vec::new();
    loop {
        let (mut from, mut to): (Option<usize>, Option<usize>) = (None, None);
        for &i in group {
            if values[i] < 0 && from.is_none_or(|j| values[i] < values[j]) { from = Some(i); }
            if values[i] > 0 && to.is_none_or(|j| values[i] > values[j]) { to = Some(i); }
        }
        let Some(from) = from else { break; };
        let to = to.unwrap();
        let amount = (-values[from]).min(values[to]);
        result.push(Transfer { from, to, amount });
        values[from] += amount;
        values[to] -= amount;
    }
    result
}
fn best_groups(mask: usize, sums: &[Integer], memo: &mut [Option<usize>]) -> usize {
    if let Some(value) = memo[mask] { return value; }
    let first = 1usize << mask.trailing_zeros();
    let mut sub = mask;
    let mut result = 0;
    while sub > 0 {
        if sub & first != 0 && sums[sub] == 0 { result = result.max(1+best_groups(mask^sub, sums, memo)); }
        sub = (sub-1)&mask;
    }
    memo[mask] = Some(result);
    result
}
impl Engine {
    fn convert(&self, value: Integer, currency: &str) -> Result<Integer, String> {
        if currency.is_empty() { return Ok(value); }
        let rate = self.currencies.get(currency).ok_or_else(|| format!("unknown currency {currency}"))?;
        Ok((value*rate+5000)/10000)
    }
    fn member_id(&self, name: &str, active: bool) -> Result<usize, String> {
        let id = self.members.iter().position(|m| m.name == name).ok_or_else(|| format!("unknown member {name}"))?;
        if active && !self.members[id].active { return Err(format!("inactive member {name}")); }
        Ok(id)
    }
    fn ordered_members(&self, active: bool) -> Vec<usize> {
        let mut order: Vec<usize> = (0..self.members.len()).filter(|&i| !active || self.members[i].active).collect();
        order.sort_by(|&i, &j| self.members[i].name.cmp(&self.members[j].name));
        order
    }
    fn expense_id(&self, id: &str) -> Result<usize, String> {
        self.expenses.iter().position(|e| e.id == id).ok_or_else(|| format!("unknown expense {id}"))
    }
    fn check_frozen(&self, e: &Expense) -> Result<(), String> {
        for p in e.payers.iter().chain(&e.participants) {
            if !self.members[p.member].active { return Err(format!("inactive member {}", self.members[p.member].name)); }
        }
        Ok(())
    }
    fn compute(&self, e: &mut Expense) -> Result<(), String> {
        e.total = self.convert(e.amount, &e.currency)?;
        let specified: Vec<Integer> = e.participants.iter().map(|p| p.value).collect();
        let portions = match e.mode.as_str() {
            "EQUAL" => equal_distribution(e.amount, specified.len()),
            "EXACT" => specified,
            "ADJUST" => {
                let extras: Integer = specified.iter().sum();
                equal_distribution(e.amount-extras, specified.len()).iter().zip(&specified).map(|(a, b)| a+b).collect()
            }
            _ => distribute(e.amount, &specified),
        };
        for (p, share) in e.participants.iter_mut().zip(distribute(e.total, &portions)) { p.result = share; }
        contributions(e);
        Ok(())
    }
    fn draft_expense(&self, a: &[&str], previous: Option<&Expense>) -> Result<Expense, String> {
        let mut e = previous.cloned().unwrap_or_default();
        let payer = self.member_id(a[2], true)?;
        let (value, currency) = amount_spec(a[3]);
        let total = self.convert(value, &currency)?;
        if value == 0 || total == 0 { return Err("invalid amount".to_owned()); }
        e.amount = value;
        e.currency = currency;
        e.category = a[4].to_owned();
        e.mode = a[5].to_owned();
        e.payers = vec![Part { member: payer, value, result: 0 }];
        e.participants.clear();
        if e.mode == "EQUAL" && a[6] == "ALL" {
            for i in self.ordered_members(true) { e.participants.push(Part { member: i, value: 0, result: 0 }); }
        } else {
            let mut seen = HashSet::new();
            for item in &a[6..] {
                let (name, specified) = item.split_once(':').unwrap_or((*item, ""));
                let member = self.member_id(name, true)?;
                if !seen.insert(member) { return Err(format!("duplicate member {name}")); }
                let value = if specified.is_empty() { 0 } else if e.mode == "PERCENT" || e.mode == "SHARES" { integer(specified) } else { amount(specified) };
                e.participants.push(Part { member, value, result: 0 });
            }
        }
        let sum: Integer = e.participants.iter().map(|p| p.value).sum();
        if e.mode == "EXACT" && sum != e.amount || e.mode == "PERCENT" && sum != 10000 || e.mode == "SHARES" && sum == 0 || e.mode == "ADJUST" && sum > e.amount {
            return Err("splits do not add up".to_owned());
        }
        self.compute(&mut e)?;
        Ok(e)
    }
    fn balances(&self) -> Vec<Integer> {
        let mut result = vec![0; self.members.len()];
        for e in &self.expenses {
            for (i, value) in net(e, self.members.len()).into_iter().enumerate() { result[i] += value; }
        }
        for s in &self.settlements {
            result[s.from] += s.total;
            result[s.to] -= s.total;
        }
        result
    }
    fn debts(&self) -> Vec<Vec<Integer>> {
        let count = self.members.len();
        let mut result = vec![vec![0; count]; count];
        let order = self.ordered_members(false);
        for e in &self.expenses {
            let mut change = net(e, count);
            let borrowers: Vec<usize> = order.iter().copied().filter(|&i| change[i] < 0).collect();
            let lenders: Vec<usize> = order.iter().copied().filter(|&i| change[i] > 0).collect();
            let (mut i, mut j) = (0, 0);
            while i < borrowers.len() && j < lenders.len() {
                let (from, to) = (borrowers[i], lenders[j]);
                let value = (-change[from]).min(change[to]);
                result[from][to] += value;
                change[from] += value;
                change[to] -= value;
                if change[from] == 0 { i += 1; }
                if change[to] == 0 { j += 1; }
            }
        }
        for s in &self.settlements { result[s.from][s.to] -= s.total; }
        for i in 0..count {
            for j in i+1..count {
                let value = result[i][j]-result[j][i];
                result[i][j] = value;
                result[j][i] = -value;
            }
        }
        result
    }
    fn spent(&self, category: &str) -> Integer {
        self.expenses.iter().filter(|e| e.category == category).map(|e| e.total).sum()
    }
    fn warning(&self, e: &Expense, out: &mut Vec<String>) {
        if let Some(&budget) = self.budgets.get(&e.category) {
            let total = self.spent(&e.category);
            if total > budget { out.push(format!("  WARNING {} over budget by {}", e.category, money(total-budget))); }
        }
    }
    fn parts_text(&self, parts: &[Part]) -> String {
        parts.iter().map(|p| format!("{} {}", self.members[p.member].name, money(p.result))).collect::<Vec<_>>().join(" + ")
    }
    fn chronological(&self) -> Vec<usize> {
        let mut order: Vec<usize> = (0..self.expenses.len()).collect();
        order.sort_by_key(|&i| (self.expenses[i].day, self.expenses[i].serial));
        order
    }
    fn transfer_lines(&self, transfers: &[Transfer], indent: &str) -> Vec<String> {
        transfers.iter().map(|t| format!("{indent}{} -> {} {}", self.members[t.from].name, self.members[t.to].name, money(t.amount))).collect()
    }
    fn execute(&mut self, line: &str) -> Result<Vec<String>, String> {
        let a: Vec<&str> = line.split(' ').collect();
        let command = a[0];
        let mut out = Vec::new();
        match command {
            "DAY" => {
                let day = integer(a[1]);
                if day <= self.day { return Err(format!("invalid day {}", a[1])); }
                out.push(format!("DAY {day}"));
                loop {
                    let selected = self.expenses.iter().enumerate().filter(|(_, e)| e.interval > 0 && e.next <= day)
                        .min_by_key(|(_, e)| (e.next, e.serial)).map(|(i, _)| i);
                    let Some(i) = selected else { break; };
                    if self.check_frozen(&self.expenses[i]).is_err() || self.convert(self.expenses[i].amount, &self.expenses[i].currency)? == 0 {
                        out.push(format!("  CANCEL {}", self.expenses[i].id));
                        self.expenses[i].interval = 0;
                        continue;
                    }
                    let mut copy = self.expenses[i].clone();
                    copy.id = format!("{}#{}", copy.id, copy.copies+2);
                    copy.day = copy.next;
                    self.serial += 1;
                    copy.serial = self.serial;
                    copy.interval = 0;
                    copy.next = 0;
                    copy.copies = 0;
                    self.expenses[i].copies += 1;
                    let interval = self.expenses[i].interval;
                    self.expenses[i].next += interval;
                    self.compute(&mut copy)?;
                    self.used.insert(copy.id.clone());
                    out.push(format!("  RECUR {} {}", copy.id, money(copy.total)));
                    self.expenses.push(copy);
                    self.warning(self.expenses.last().unwrap(), &mut out);
                }
                self.day = day;
            }
            "MEMBER" => {
                let previous = self.members.iter().position(|m| m.name == a[1]);
                if let Some(i) = previous {
                    if self.members[i].active { return Err(format!("duplicate member {}", a[1])); }
                    self.members[i].active = true;
                    self.members[i].day = self.day;
                } else { self.members.push(Member { name: a[1].to_owned(), active: true, day: self.day }); }
                out.push(format!("MEMBER {} {}", a[1], if previous.is_some() { "rejoined" } else { "joined" }));
            }
            "LEAVE" => {
                let i = self.member_id(a[1], true)?;
                if self.balances()[i] != 0 { return Err(format!("member has a balance {}", a[1])); }
                self.members[i].active = false;
                self.members[i].day = self.day;
                out.push(format!("LEAVE {}", a[1]));
            }
            "CURRENCY" => {
                let value = integer(a[2]);
                let mut result = format!("CURRENCY {} {}", a[1], rate_text(value));
                if let Some(old) = self.currencies.insert(a[1].to_owned(), value) { result.push_str(&format!(" was {}", rate_text(old))); }
                out.push(result);
            }
            "EXPENSE" | "EDIT" => {
                let previous = if command == "EXPENSE" {
                    if self.used.contains(a[1]) { return Err(format!("duplicate id {}", a[1])); }
                    None
                } else {
                    let i = self.expense_id(a[1])?;
                    self.check_frozen(&self.expenses[i])?;
                    Some(i)
                };
                let mut e = self.draft_expense(&a, previous.map(|i| &self.expenses[i]))?;
                let position = previous.unwrap_or(self.expenses.len());
                if let Some(i) = previous { self.expenses[i] = e; }
                else {
                    e.id = a[1].to_owned();
                    e.day = self.day;
                    self.serial += 1;
                    e.serial = self.serial;
                    self.used.insert(e.id.clone());
                    self.expenses.push(e);
                }
                let e = &self.expenses[position];
                out.push(format!("{command} {} {}{} = {}", e.id, money(e.total), note(e.amount, &e.currency), self.parts_text(&e.participants)));
                self.warning(e, &mut out);
            }
            "PAYERS" => {
                let i = self.expense_id(a[1])?;
                self.check_frozen(&self.expenses[i])?;
                let mut payers = Vec::new();
                let mut seen = HashSet::new();
                let mut sum = 0;
                for item in &a[2..] {
                    let (name, payment) = item.split_once(':').unwrap();
                    let member = self.member_id(name, true)?;
                    if !seen.insert(member) { return Err(format!("duplicate member {name}")); }
                    let value = amount(payment);
                    sum += value;
                    payers.push(Part { member, value, result: 0 });
                }
                let e = &mut self.expenses[i];
                if sum != e.amount { return Err("payers do not add up".to_owned()); }
                e.payers = payers;
                contributions(e);
                let e = &self.expenses[i];
                out.push(format!("PAYERS {} {}{} = {}", e.id, money(e.total), note(e.amount, &e.currency), self.parts_text(&e.payers)));
            }
            "DELETE" => {
                let i = self.expense_id(a[1])?;
                self.check_frozen(&self.expenses[i])?;
                self.expenses.remove(i);
                out.push(format!("DELETE {}", a[1]));
            }
            "RECURRING" => {
                let i = self.expense_id(a[1])?;
                let e = &mut self.expenses[i];
                e.interval = integer(a[2]);
                if e.interval > 0 {
                    e.next = self.day+e.interval;
                    out.push(format!("RECURRING {} interval {} next {}", e.id, e.interval, e.next));
                } else { out.push(format!("RECURRING {} stopped", e.id)); }
            }
            "SETTLE" => {
                let from = self.member_id(a[1], true)?;
                let to = self.member_id(a[2], true)?;
                if from == to { return Err(format!("same member {}", a[1])); }
                let (amount, currency) = amount_spec(a[3]);
                let total = self.convert(amount, &currency)?;
                if amount == 0 || total == 0 { return Err("invalid amount".to_owned()); }
                self.serial += 1;
                out.push(format!("SETTLE {} -> {} {}{}", a[1], a[2], money(total), note(amount, &currency)));
                self.settlements.push(Settlement { from, to, amount, total, day: self.day, serial: self.serial, currency });
            }
            "BUDGET" => {
                let value = amount(a[2]);
                if value > 0 {
                    self.budgets.insert(a[1].to_owned(), value);
                    out.push(format!("BUDGET {} {}", a[1], money(value)));
                } else {
                    self.budgets.remove(a[1]);
                    out.push(format!("BUDGET {} removed", a[1]));
                }
            }
            "BALANCES" => {
                out.push("BALANCES".to_owned());
                let values = self.balances();
                for i in self.ordered_members(true) { out.push(format!("  {} {}", self.members[i].name, signed_money(values[i]))); }
            }
            "OWES" => {
                let id = self.member_id(a[1], false)?;
                out.push(format!("OWES {}", a[1]));
                let values = self.debts();
                for i in self.ordered_members(false) {
                    if i == id || values[id][i] == 0 { continue; }
                    let (from, to) = if values[id][i] > 0 { (id, i) } else { (i, id) };
                    out.push(format!("  {} owes {} {}", self.members[from].name, self.members[to].name, money(values[from][to])));
                }
            }
            "HISTORY" => {
                let id = self.member_id(a[1], false)?;
                let mut items: Vec<(Integer, Integer, Integer, String)> = Vec::new();
                for e in &self.expenses {
                    if involved(e, id) { items.push((e.day, e.serial, net(e, self.members.len())[id], e.id.clone())); }
                }
                for s in &self.settlements {
                    if s.from == id || s.to == id {
                        items.push((s.day, s.serial, if s.from == id { s.total } else { -s.total }, format!("{}->{}", self.members[s.from].name, self.members[s.to].name)));
                    }
                }
                items.sort_by_key(|item| (item.0, item.1));
                out.push(format!("HISTORY {}", a[1]));
                let mut running = 0;
                for (day, _, change, label) in items {
                    running += change;
                    out.push(format!("  day {day} {label} {} balance {}", signed_money(change), signed_money(running)));
                }
            }
            "MATRIX" => {
                out.push("MATRIX".to_owned());
                let order = self.ordered_members(true);
                if order.is_empty() { out.push("  (none)".to_owned()); }
                else {
                    let values = self.debts();
                    let l = order.iter().map(|&i| self.members[i].name.len()).max().unwrap();
                    let mut w = l;
                    for &i in &order {
                        for &j in &order {
                            if i != j { w = w.max(money(values[i][j].max(0)).len()); }
                        }
                    }
                    let mut header = " ".repeat(l);
                    for &i in &order { header.push_str(&format!("  {:>w$}", self.members[i].name)); }
                    out.push(header);
                    for &i in &order {
                        let mut row = format!("{:<l$}", self.members[i].name);
                        for &j in &order {
                            let cell = if i == j { "-".to_owned() } else { money(values[i][j].max(0)) };
                            row.push_str(&format!("  {cell:>w$}"));
                        }
                        out.push(row);
                    }
                }
            }
            "CATEGORY" => {
                out.push("CATEGORY".to_owned());
                let mut totals: BTreeMap<&str, Integer> = BTreeMap::new();
                let mut total = 0;
                for e in &self.expenses {
                    *totals.entry(&e.category).or_default() += e.total;
                    total += e.total;
                }
                let mut categories: Vec<&str> = totals.keys().copied().collect();
                categories.sort_by(|&x, &y| totals[y].cmp(&totals[x]).then(x.cmp(y)));
                for category in categories {
                    out.push(format!("  {category} {} {}", money(totals[category]), percentage(totals[category], total)));
                    let mut shares = vec![0; self.members.len()];
                    for e in &self.expenses {
                        if e.category == category {
                            for p in &e.participants { shares[p.member] += p.result; }
                        }
                    }
                    let mut order = self.ordered_members(false);
                    order.sort_by(|&i, &j| shares[j].cmp(&shares[i]));
                    for i in order {
                        if shares[i] != 0 { out.push(format!("    {} {} {}", self.members[i].name, money(shares[i]), percentage(shares[i], totals[category]))); }
                    }
                }
            }
            "BUDGETS" => {
                out.push("BUDGETS".to_owned());
                for (category, &budget) in &self.budgets {
                    let spent = self.spent(category);
                    let suffix = if spent <= budget { format!("left {}", money(budget-spent)) } else { format!("over {}", money(spent-budget)) };
                    out.push(format!("  {category} spent {} budget {} used {} {suffix}", money(spent), money(budget), percentage(spent, budget)));
                }
            }
            "TOTALS" => {
                out.push("TOTALS".to_owned());
                let count = self.members.len();
                let (mut paid, mut shares, mut sent, mut received) = (vec![0; count], vec![0; count], vec![0; count], vec![0; count]);
                let (mut expense_total, mut settlement_total) = (0, 0);
                for e in &self.expenses {
                    expense_total += e.total;
                    for p in &e.payers { paid[p.member] += p.result; }
                    for p in &e.participants { shares[p.member] += p.result; }
                }
                for s in &self.settlements {
                    settlement_total += s.total;
                    sent[s.from] += s.total;
                    received[s.to] += s.total;
                }
                for i in self.ordered_members(false) { out.push(format!("  {} paid {} share {} sent {} received {}", self.members[i].name, money(paid[i]), money(shares[i]), money(sent[i]), money(received[i]))); }
                for currency in self.currencies.keys() {
                    let (mut count, mut original, mut base) = (0, 0, 0);
                    for e in &self.expenses {
                        if &e.currency == currency {
                            count += 1;
                            original += e.amount;
                            base += e.total;
                        }
                    }
                    if count > 0 { out.push(format!("  currency {currency} expenses {count} amount {} base {}", money(original), money(base))); }
                }
                out.push(format!("  expenses {} total {} settlements {} total {}", self.expenses.len(), money(expense_total), self.settlements.len(), money(settlement_total)));
            }
            "MEMBERS" => {
                out.push("MEMBERS".to_owned());
                for i in self.ordered_members(false) {
                    let count = self.expenses.iter().filter(|e| involved(e, i)).count();
                    let m = &self.members[i];
                    out.push(format!("  {} {} day {} expenses {count}", m.name, if m.active { "active" } else { "left" }, m.day));
                }
            }
            "EXPENSES" => {
                let member = if a[1] == "MEMBER" { Some(self.member_id(a[2], false)?) } else { None };
                out.push(line.to_owned());
                let (mut count, mut total) = (0, 0);
                for i in self.chronological() {
                    let e = &self.expenses[i];
                    let matches = match a[1] {
                        "ALL" => true,
                        "CATEGORY" => e.category == a[2],
                        "MEMBER" => involved(e, member.unwrap()),
                        _ => e.day >= integer(a[2]) && e.day <= integer(a[3]),
                    };
                    if !matches { continue; }
                    let names = e.payers.iter().map(|p| self.members[p.member].name.as_str()).collect::<Vec<_>>().join(",");
                    out.push(format!("  day {} {} {} {} by {names}", e.day, e.id, e.category, money(e.total)));
                    count += 1;
                    total += e.total;
                }
                out.push(format!("  count {count} total {}", money(total)));
            }
            "PERIODS" => {
                let k = integer(a[1]);
                let mut groups: BTreeMap<Integer, (usize, Integer)> = BTreeMap::new();
                for e in &self.expenses {
                    let group = groups.entry((e.day-1)/k).or_default();
                    group.0 += 1;
                    group.1 += e.total;
                }
                out.push(format!("PERIODS {k}"));
                for (i, (count, total)) in groups { out.push(format!("  days {}-{} expenses {count} total {}", i*k+1, i*k+k, money(total))); }
            }
            "SHOW" => {
                let e = &self.expenses[self.expense_id(a[1])?];
                out.push(format!("SHOW {}", a[1]));
                out.push(format!("  day {} category {} mode {} total {}{}", e.day, e.category, e.mode, money(e.total), note(e.amount, &e.currency)));
                for p in &e.payers { out.push(format!("  paid {} {}", self.members[p.member].name, money(p.result))); }
                let units: Integer = e.participants.iter().map(|p| p.value).sum();
                for p in &e.participants {
                    let suffix = match e.mode.as_str() {
                        "EXACT" => format!(" {}", money(p.value)),
                        "PERCENT" => format!(" {}%", money(p.value)),
                        "SHARES" => format!(" {}/{units}", p.value),
                        "ADJUST" => format!(" +{}", money(p.value)),
                        _ => String::new(),
                    };
                    out.push(format!("  share {} {}{suffix}", self.members[p.member].name, money(p.result)));
                }
                if e.interval > 0 { out.push(format!("  recurring interval {} next {}", e.interval, e.next)); }
            }
            "SIMPLIFY" => {
                let values = self.balances();
                let order: Vec<usize> = self.ordered_members(false).into_iter().filter(|&i| values[i] != 0).collect();
                if a[1] == "GREEDY" {
                    let transfers = greedy(&order, &values);
                    out.push(format!("SIMPLIFY GREEDY transfers {}", transfers.len()));
                    out.extend(self.transfer_lines(&transfers, "  "));
                } else {
                    let n = order.len();
                    if n > 12 { return Err("too many members".to_owned()); }
                    let mut sums = vec![0; 1<<n];
                    for mask in 1usize..1<<n {
                        let bit = mask.trailing_zeros() as usize;
                        sums[mask] = sums[mask^(1<<bit)]+values[order[bit]];
                    }
                    let mut memo = vec![None; 1<<n];
                    memo[0] = Some(0);
                    let mut remaining = (1<<n)-1;
                    let group_count = best_groups(remaining, &sums, &mut memo);
                    out.push(format!("SIMPLIFY OPTIMAL transfers {} groups {group_count}", n-group_count));
                    while remaining > 0 {
                        let first = 1usize << remaining.trailing_zeros();
                        let (mut chosen, mut chosen_list) = (0, Vec::new());
                        let mut sub = remaining;
                        while sub > 0 {
                            if sub&first != 0 && sums[sub] == 0 && 1+best_groups(remaining^sub, &sums, &mut memo) == best_groups(remaining, &sums, &mut memo) {
                                let list: Vec<usize> = (0..n).filter(|&i| sub&(1<<i) != 0).collect();
                                if chosen == 0 || list < chosen_list {
                                    chosen = sub;
                                    chosen_list = list;
                                }
                            }
                            sub = (sub-1)&remaining;
                        }
                        let group: Vec<usize> = chosen_list.iter().map(|&i| order[i]).collect();
                        let names = group.iter().map(|&i| self.members[i].name.as_str()).collect::<Vec<_>>().join(" ");
                        out.push(format!("  group {names}"));
                        out.extend(self.transfer_lines(&greedy(&group, &values), "    "));
                        remaining ^= chosen;
                    }
                }
            }
            _ => unreachable!(),
        }
        if ["BALANCES", "OWES", "HISTORY", "CATEGORY", "BUDGETS", "MEMBERS", "PERIODS"].contains(&command) && out.len() == 1 { out.push("  (none)".to_owned()); }
        Ok(out)
    }
}
fn main() {
    let mut engine = Engine { day: 1, ..Engine::default() };
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let count: usize = lines.next().unwrap().unwrap().parse().unwrap();
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    for line in lines.take(count) {
        let line = line.unwrap();
        let result = engine.execute(&line).unwrap_or_else(|message| vec![format!("ERROR {message}")]);
        for line in result { writeln!(output, "{line}").unwrap(); }
    }
}
