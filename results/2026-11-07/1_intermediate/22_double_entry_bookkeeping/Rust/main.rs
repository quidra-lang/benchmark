use std::collections::{BTreeMap, HashMap, VecDeque};
use std::io::{self, BufRead, Write};
use std::rc::Rc;

type Money = i64;
type Day = i32;

fn emit(output: &mut impl Write, text: impl AsRef<str>) {
    writeln!(output, "{}", text.as_ref()).unwrap();
}

fn money(cents: Money) -> String {
    let value = cents.abs();
    format!("{}{}.{:02}", if cents < 0 { "-" } else { "" }, value / 100, value % 100)
}

fn parse_money(text: &str) -> Money {
    let (whole, fraction) = text.split_once('.').unwrap();
    whole.parse::<Money>().unwrap() * 100 + fraction.parse::<Money>().unwrap()
}

fn leap(year: i32) -> bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }

fn month_days(year: i32, month: usize) -> i32 {
    let days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    days[month - 1] + i32::from(month == 2 && leap(year))
}

fn day_number(year: i32, month: usize, day: i32) -> Day {
    (2000..year).map(|y| 365 + i32::from(leap(y))).sum::<i32>()
        + (1..month).map(|m| month_days(year, m)).sum::<i32>() + day - 1
}

fn date_parts(mut day: Day) -> (i32, usize, i32) {
    let mut year = 2000;
    while day >= 365 + i32::from(leap(year)) {
        day -= 365 + i32::from(leap(year));
        year += 1;
    }
    let mut month = 1;
    while day >= month_days(year, month) {
        day -= month_days(year, month);
        month += 1;
    }
    (year, month, day + 1)
}

fn date_text(day: Day) -> String {
    let (year, month, day) = date_parts(day);
    format!("{year:04}-{month:02}-{day:02}")
}

fn parse_date(text: &str) -> Result<Day, String> {
    let year: i32 = text[..4].parse().unwrap();
    let month: usize = text[5..7].parse().unwrap();
    let day: i32 = text[8..].parse().unwrap();
    if !(2000..=2099).contains(&year) || !(1..=12).contains(&month)
        || day < 1 || day > month_days(year, month) {
        return Err(format!("invalid date {text}"));
    }
    Ok(day_number(year, month, day))
}

fn date_range(first: &str, last: &str) -> Result<(Day, Day), String> {
    let start = parse_date(first)?;
    let end = parse_date(last)?;
    if start > end { return Err(format!("invalid range {first} {last}")); }
    Ok((start, end))
}

fn months_after(date: Day, months: usize) -> Day {
    let (mut year, month, day) = date_parts(date);
    let total = month - 1 + months;
    year += (total / 12) as i32;
    let month = total % 12 + 1;
    day_number(year, month, day.min(month_days(year, month)))
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum AccountType { Asset, Liability, Equity, Revenue, Expense, ContraAsset }

impl AccountType {
    fn parse(text: &str) -> Self {
        match text {
            "ASSET" => Self::Asset,
            "LIABILITY" => Self::Liability,
            "EQUITY" => Self::Equity,
            "REVENUE" => Self::Revenue,
            "EXPENSE" => Self::Expense,
            "CONTRA_ASSET" => Self::ContraAsset,
            _ => unreachable!(),
        }
    }

    fn text(self) -> &'static str {
        match self {
            Self::Asset => "ASSET", Self::Liability => "LIABILITY", Self::Equity => "EQUITY",
            Self::Revenue => "REVENUE", Self::Expense => "EXPENSE", Self::ContraAsset => "CONTRA_ASSET",
        }
    }

    fn class(self) -> Self { if self == Self::ContraAsset { Self::Asset } else { self } }
    fn sign(self) -> Money { if matches!(self, Self::Asset | Self::Expense) { 1 } else { -1 } }
    fn temporary(self) -> bool { matches!(self, Self::Revenue | Self::Expense) }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Category { Journal, Recurring, Reversal, Closing, Reopen, Depreciation, Interest, Writeoff }

impl Category {
    fn text(self) -> &'static str {
        match self {
            Self::Journal => "journal", Self::Recurring => "recurring", Self::Reversal => "reversal",
            Self::Closing => "closing", Self::Reopen => "reopen", Self::Depreciation => "depreciation",
            Self::Interest => "interest", Self::Writeoff => "writeoff",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Side { Debit, Credit }

impl Side {
    fn text(self) -> &'static str { if self == Self::Debit { "DR" } else { "CR" } }
    fn sign(self) -> Money { if self == Self::Debit { 1 } else { -1 } }
    fn reversed(self) -> Self { if self == Self::Debit { Self::Credit } else { Self::Debit } }
}

struct Account {
    code: String,
    kind: AccountType,
    name: String,
    active: bool,
}

#[derive(Clone, Copy, Default)]
struct Totals { debit: Money, credit: Money }

impl Totals {
    fn difference(self) -> Money { self.debit - self.credit }
    fn add(&mut self, side: Side, amount: Money) {
        match side {
            Side::Debit => self.debit += amount,
            Side::Credit => self.credit += amount,
        }
    }
    fn merge(&mut self, other: Self) {
        self.debit += other.debit;
        self.credit += other.credit;
    }
}

#[derive(Clone)]
struct Line {
    side: Side,
    account: usize,
    amount: Money,
    partner: Option<String>,
}

impl Line {
    fn new(side: Side, account: usize, amount: Money) -> Self {
        Self { side, account, amount, partner: None }
    }
}

struct Lines {
    items: Vec<Line>,
    amount: Totals,
    accounts: BTreeMap<usize, Totals>,
}

impl Lines {
    fn new(items: Vec<Line>) -> Rc<Self> {
        let mut amount = Totals::default();
        let mut accounts: BTreeMap<usize, Totals> = BTreeMap::new();
        for line in &items {
            amount.add(line.side, line.amount);
            accounts.entry(line.account).or_default().add(line.side, line.amount);
        }
        Rc::new(Self { items, amount, accounts })
    }

    fn account_total(&self, account: usize) -> Totals {
        self.accounts.get(&account).copied().unwrap_or_default()
    }
}

struct DraftLine {
    side: Side,
    code: String,
    amount: Money,
    partner: Option<String>,
}

struct Draft {
    key: String,
    date: Option<String>,
    memo: String,
    lines: Vec<DraftLine>,
}

struct Entry {
    id: String,
    date: Day,
    category: Category,
    memo: String,
    lines: Rc<Lines>,
    reverses: Option<usize>,
    reversed_by: Option<usize>,
}

#[derive(Clone)]
struct Template { memo: String, lines: Rc<Lines>, uses: usize }

#[derive(Clone, Copy)]
struct CloseRecord { date: Day, entry: Option<usize> }

struct OpenItem { entry: usize, original: Money, remaining: Money }

#[derive(Default)]
struct Settlement { items: VecDeque<OpenItem>, unapplied: Money }

#[derive(Default)]
struct Book {
    accounts: Vec<Account>,
    account_ids: BTreeMap<String, usize>,
    entries: Vec<Entry>,
    entry_ids: HashMap<String, usize>,
    templates: BTreeMap<String, Template>,
    draft: Option<Draft>,
    closes: Vec<CloseRecord>,
    close_counter: usize,
    depreciation_counter: usize,
    interest_counter: usize,
    writeoff_counter: usize,
}

impl Book {
    fn account(&self, code: &str) -> Result<usize, String> {
        self.account_ids.get(code).copied().ok_or_else(|| format!("unknown account {code}"))
    }

    fn require_type(&self, code: &str, kind: AccountType) -> Result<usize, String> {
        let index = self.account(code)?;
        if self.accounts[index].kind != kind { return Err(format!("wrong type {code} {}", kind.text())); }
        Ok(index)
    }

    fn active(&self, index: usize) -> Result<(), String> {
        if !self.accounts[index].active { return Err(format!("inactive account {}", self.accounts[index].code)); }
        Ok(())
    }

    fn active_lines(&self, lines: &Lines) -> Result<(), String> {
        for line in &lines.items { self.active(line.account)?; }
        Ok(())
    }

    fn check_open(&self, date: Day) -> Result<(), String> {
        if self.closes.last().is_some_and(|record| date <= record.date) {
            return Err(format!("period closed {}", date_text(date)));
        }
        Ok(())
    }

    fn closed_text(&self) -> String {
        self.closes.last().map(|record| date_text(record.date)).unwrap_or_else(|| "none".into())
    }

    fn parent(&self, index: usize) -> Option<usize> {
        let code = &self.accounts[index].code;
        self.accounts.iter().enumerate().filter(|(i, account)| *i != index && code.starts_with(&account.code))
            .max_by_key(|(_, account)| account.code.len()).map(|(i, _)| i)
    }

    fn parent_code(&self, index: usize) -> &str {
        self.parent(index).map(|i| self.accounts[i].code.as_str()).unwrap_or("none")
    }

    fn ordered(&self) -> Vec<usize> {
        let mut indices: Vec<usize> = (0..self.entries.len()).collect();
        indices.sort_by_key(|&i| (self.entries[i].date, i));
        indices
    }

    fn post(&mut self, id: String, date: Day, category: Category, memo: String, lines: Rc<Lines>) -> usize {
        let index = self.entries.len();
        self.entry_ids.insert(id.clone(), index);
        self.entries.push(Entry { id, date, category, memo, lines, reverses: None, reversed_by: None });
        index
    }

    fn reverse(&mut self, original: usize, date: Day, category: Category, memo: String) -> usize {
        let source = &self.entries[original];
        let lines = source.lines.items.iter().map(|line| Line { side: line.side.reversed(), ..line.clone() }).collect();
        let id = format!("{}-R", source.id);
        let index = self.post(id, date, category, memo, Lines::new(lines));
        self.entries[original].reversed_by = Some(index);
        self.entries[index].reverses = Some(original);
        index
    }

    fn validate_draft(&self, draft: &Draft) -> Result<Rc<Lines>, String> {
        if draft.lines.len() < 2 { return Err(format!("too few lines {}", draft.key)); }
        let mut items = Vec::new();
        for line in &draft.lines {
            let account = self.account(&line.code)?;
            if draft.date.is_some() { self.active(account)?; }
            if line.amount == 0 { return Err(format!("zero amount {}", line.code)); }
            items.push(Line { side: line.side, account, amount: line.amount, partner: line.partner.clone() });
        }
        let lines = Lines::new(items);
        if lines.amount.debit != lines.amount.credit {
            return Err(format!("unbalanced {} debit {} credit {}", draft.key,
                               money(lines.amount.debit), money(lines.amount.credit)));
        }
        Ok(lines)
    }

    fn account_totals(&self, account: usize, start: Day, end: Day) -> Totals {
        let mut total = Totals::default();
        for entry in &self.entries {
            if (start..=end).contains(&entry.date) { total.merge(entry.lines.account_total(account)); }
        }
        total
    }

    fn balance(&self, account: usize, end: Day) -> Money {
        self.accounts[account].kind.sign() * self.account_totals(account, 0, end).difference()
    }

    fn totals(&self, start: Day, end: Day, income: bool) -> Vec<Totals> {
        let mut totals = vec![Totals::default(); self.accounts.len()];
        for entry in &self.entries {
            if !(start..=end).contains(&entry.date) || income && matches!(entry.category, Category::Closing | Category::Reopen) {
                continue;
            }
            for (&account, &amount) in &entry.lines.accounts { totals[account].merge(amount); }
        }
        totals
    }

    fn daily_sum(&self, account: usize, start: Day, end: Day) -> Money {
        let mut changes = vec![0; (end - start + 1) as usize];
        let mut running = 0;
        let sign = self.accounts[account].kind.sign();
        for entry in &self.entries {
            if entry.date > end { continue; }
            let change = sign * entry.lines.account_total(account).difference();
            if entry.date < start { running += change; }
            else { changes[(entry.date - start) as usize] += change; }
        }
        let mut total = 0;
        for change in changes {
            running += change;
            total += running;
        }
        total
    }

    fn settlements(&self, account: usize, date: Day) -> BTreeMap<String, Settlement> {
        let mut result: BTreeMap<String, Settlement> = BTreeMap::new();
        let sign = self.accounts[account].kind.sign();
        for index in self.ordered() {
            let entry = &self.entries[index];
            if entry.date > date { break; }
            if !entry.lines.accounts.contains_key(&account) { continue; }
            for line in &entry.lines.items {
                if line.account != account { continue; }
                let Some(partner) = &line.partner else { continue };
                let settlement = result.entry(partner.clone()).or_default();
                let value = sign * line.side.sign() * line.amount;
                if value > 0 {
                    let applied = value.min(settlement.unapplied);
                    settlement.unapplied -= applied;
                    if value > applied {
                        settlement.items.push_back(OpenItem { entry: index, original: value, remaining: value - applied });
                    }
                } else {
                    let mut payment = -value;
                    while payment > 0 {
                        let Some(item) = settlement.items.front_mut() else { break };
                        let applied = payment.min(item.remaining);
                        payment -= applied;
                        item.remaining -= applied;
                        if item.remaining == 0 { settlement.items.pop_front(); }
                    }
                    settlement.unapplied += payment;
                }
            }
        }
        result
    }

    fn section(&self, heading: &str, kinds: &[AccountType], sign: Money, totals: &[Totals],
               earnings: Option<Money>, output: &mut impl Write) -> Money {
        let amounts: Vec<Money> = self.accounts.iter().enumerate().map(|(i, account)| {
            if kinds.contains(&account.kind) { sign * totals[i].difference() } else { 0 }
        }).collect();
        let total = amounts.iter().sum::<Money>() + earnings.unwrap_or(0);
        emit(output, format!("  {heading} {}", money(total)));
        for &top in self.account_ids.values() {
            if self.parent(top).is_some() { continue; }
            let code = &self.accounts[top].code;
            let members: Vec<usize> = self.account_ids.values().copied()
                .filter(|&i| self.accounts[i].code.starts_with(code)).collect();
            if members.iter().all(|&i| amounts[i] == 0) { continue; }
            let subtotal: Money = members.iter().map(|&i| amounts[i]).sum();
            emit(output, format!("    {code} {} {}", self.accounts[top].name, money(subtotal)));
            for index in members {
                if amounts[index] != 0 {
                    emit(output, format!("      {} {} {}", self.accounts[index].code, self.accounts[index].name, money(amounts[index])));
                }
            }
        }
        if let Some(value) = earnings { emit(output, format!("    current earnings {}", money(value))); }
        total
    }

    fn execute(&mut self, words: &[&str], output: &mut impl Write) -> Result<(), String> {
        match words[0] {
            "ACCOUNT" => {
                let code = words[1];
                if self.account_ids.contains_key(code) { return Err(format!("duplicate account {code}")); }
                let kind = AccountType::parse(words[2]);
                for (other, &index) in &self.account_ids {
                    if (other.starts_with(code) || code.starts_with(other)) && kind.class() != self.accounts[index].kind.class() {
                        return Err(format!("class mismatch {code} {other}"));
                    }
                }
                let index = self.accounts.len();
                self.accounts.push(Account { code: code.into(), kind, name: words[3].into(), active: true });
                self.account_ids.insert(code.into(), index);
                emit(output, format!("ACCOUNT {code} {} {} parent {}", kind.text(), words[3], self.parent_code(index)));
            }
            "DEACTIVATE" => {
                let index = self.account(words[1])?;
                if !self.accounts[index].active { return Err(format!("already inactive {}", words[1])); }
                let balance = self.balance(index, Day::MAX);
                if balance != 0 { return Err(format!("nonzero balance {} {}", words[1], money(balance))); }
                self.accounts[index].active = false;
                emit(output, format!("DEACTIVATE {} {}", words[1], self.accounts[index].name));
            }
            "JOURNAL" | "TEMPLATE" => {
                if let Some(draft) = &self.draft { emit(output, format!("DISCARD {} lines {}", draft.key, draft.lines.len())); }
                let journal = words[0] == "JOURNAL";
                self.draft = Some(Draft {
                    key: words[1].into(), date: journal.then(|| words[2].into()),
                    memo: words[if journal { 3 } else { 2 }].into(), lines: Vec::new(),
                });
            }
            "DR" | "CR" => {
                let draft = self.draft.as_mut().ok_or("no open entry")?;
                draft.lines.push(DraftLine {
                    side: if words[0] == "DR" { Side::Debit } else { Side::Credit },
                    code: words[1].into(), amount: parse_money(words[2]), partner: words.get(3).map(|name| (*name).into()),
                });
            }
            "POST" => {
                let draft = self.draft.take().ok_or("no open entry")?;
                if let Some(token) = &draft.date {
                    if self.entry_ids.contains_key(&draft.key) { return Err(format!("duplicate entry {}", draft.key)); }
                    let date = parse_date(token)?;
                    self.check_open(date)?;
                    let lines = self.validate_draft(&draft)?;
                    let index = self.post(draft.key, date, Category::Journal, draft.memo, lines);
                    let entry = &self.entries[index];
                    emit(output, format!("POST {} {} lines {} amount {}", entry.id, date_text(date),
                                         entry.lines.items.len(), money(entry.lines.amount.debit)));
                } else {
                    if self.templates.contains_key(&draft.key) { return Err(format!("duplicate template {}", draft.key)); }
                    let lines = self.validate_draft(&draft)?;
                    emit(output, format!("TEMPLATE {} lines {} amount {}", draft.key, lines.items.len(), money(lines.amount.debit)));
                    self.templates.insert(draft.key, Template { memo: draft.memo, lines, uses: 0 });
                }
            }
            "DRAFT" => {
                let draft = self.draft.as_ref().ok_or("no open entry")?;
                let mut total = Totals::default();
                for line in &draft.lines { total.add(line.side, line.amount); }
                let kind = if draft.date.is_some() { "journal" } else { "template" };
                emit(output, format!("DRAFT {kind} {} lines {} debit {} credit {} difference {}", draft.key,
                                     draft.lines.len(), money(total.debit), money(total.credit), money(total.difference())));
            }
            "REVERSE" => {
                let index = *self.entry_ids.get(words[1]).ok_or_else(|| format!("unknown entry {}", words[1]))?;
                let entry = &self.entries[index];
                if matches!(entry.category, Category::Reversal | Category::Closing | Category::Reopen) {
                    return Err(format!("cannot reverse {}", words[1]));
                }
                if entry.reversed_by.is_some() { return Err(format!("already reversed {}", words[1])); }
                let date = parse_date(words[2])?;
                if date < entry.date { return Err(format!("reverse before entry {} {}", words[1], date_text(entry.date))); }
                self.check_open(date)?;
                self.active_lines(&entry.lines)?;
                let memo = entry.memo.clone();
                let reversed = self.reverse(index, date, Category::Reversal, memo);
                let entry = &self.entries[reversed];
                emit(output, format!("REVERSE {} entry {} {} amount {}", words[1], entry.id, date_text(date), money(entry.lines.amount.debit)));
            }
            "RECUR" => {
                let name = words[1];
                let template = self.templates.get(name).cloned().ok_or_else(|| format!("unknown template {name}"))?;
                let date = parse_date(words[2])?;
                let count: usize = words[3].parse().unwrap();
                if count == 0 { return Err("invalid count".into()); }
                self.check_open(date)?;
                self.active_lines(&template.lines)?;
                emit(output, format!("RECUR {name} count {count}"));
                for month in 0..count {
                    let pattern = self.templates.get_mut(name).unwrap();
                    pattern.uses += 1;
                    let id = format!("{name}-{}", pattern.uses);
                    let index = self.post(id, months_after(date, month), Category::Recurring, template.memo.clone(), Rc::clone(&template.lines));
                    let entry = &self.entries[index];
                    emit(output, format!("  POST {} {} lines {} amount {}", entry.id, date_text(entry.date),
                                         entry.lines.items.len(), money(entry.lines.amount.debit)));
                }
            }
            "DEPRECIATE" => {
                let date = parse_date(words[1])?;
                self.check_open(date)?;
                let asset = self.require_type(words[2], AccountType::Asset)?;
                let contra = self.require_type(words[3], AccountType::ContraAsset)?;
                let expense = self.require_type(words[4], AccountType::Expense)?;
                self.active(contra)?;
                self.active(expense)?;
                let cost = self.balance(asset, date);
                let accumulated = self.balance(contra, date);
                let life: Money = words[5].parse().unwrap();
                let amount = if cost > 0 { (cost / life).min(cost - accumulated) } else { 0 };
                if amount <= 0 { return Err(format!("nothing to depreciate {}", words[2])); }
                self.depreciation_counter += 1;
                let id = format!("DEP-{}", self.depreciation_counter);
                let lines = Lines::new(vec![Line::new(Side::Debit, expense, amount), Line::new(Side::Credit, contra, amount)]);
                self.post(id.clone(), date, Category::Depreciation, "depreciation".into(), lines);
                emit(output, format!("DEPRECIATE {} entry {id} {} amount {} accumulated {} book {}", words[2], date_text(date),
                                     money(amount), money(accumulated + amount), money(cost - accumulated - amount)));
            }
            "INTEREST" => {
                let account = self.account(words[1])?;
                let kind = self.accounts[account].kind;
                if !matches!(kind, AccountType::Asset | AccountType::Liability) {
                    return Err(format!("not interest bearing {}", words[1]));
                }
                let offset = self.require_type(words[2], if kind == AccountType::Asset { AccountType::Revenue } else { AccountType::Expense })?;
                let (start, end) = date_range(words[3], words[4])?;
                self.check_open(end)?;
                self.active(account)?;
                self.active(offset)?;
                let total = self.daily_sum(account, start, end);
                let rate: Money = words[5].parse().unwrap();
                let amount = total * rate / 3_650_000;
                if amount <= 0 { return Err(format!("no interest {}", words[1])); }
                let (debit, credit) = if kind == AccountType::Asset { (account, offset) } else { (offset, account) };
                let lines = Lines::new(vec![Line::new(Side::Debit, debit, amount), Line::new(Side::Credit, credit, amount)]);
                self.interest_counter += 1;
                let id = format!("INT-{}", self.interest_counter);
                self.post(id.clone(), end, Category::Interest, "interest".into(), lines);
                let days = end - start + 1;
                emit(output, format!("INTEREST {} entry {id} {} days {days} average {} amount {}", words[1], date_text(end),
                                     money(total / Money::from(days)), money(amount)));
            }
            "WRITEOFF" => {
                let date = parse_date(words[1])?;
                self.check_open(date)?;
                let account = self.require_type(words[2], AccountType::Asset)?;
                let expense = self.require_type(words[3], AccountType::Expense)?;
                self.active(account)?;
                self.active(expense)?;
                let age: Day = words[4].parse().unwrap();
                let targets: Vec<(String, Money)> = self.settlements(account, date).into_iter().filter_map(|(partner, settlement)| {
                    let amount: Money = settlement.items.iter().filter(|item| date - self.entries[item.entry].date > age)
                        .map(|item| item.remaining).sum();
                    (amount > 0).then_some((partner, amount))
                }).collect();
                let total: Money = targets.iter().map(|(_, amount)| amount).sum();
                if total == 0 { return Err(format!("nothing to write off {}", words[2])); }
                let mut lines = vec![Line::new(Side::Debit, expense, total)];
                for (partner, amount) in &targets {
                    lines.push(Line { side: Side::Credit, account, amount: *amount, partner: Some(partner.clone()) });
                }
                self.writeoff_counter += 1;
                let id = format!("WO-{}", self.writeoff_counter);
                self.post(id.clone(), date, Category::Writeoff, "writeoff".into(), Lines::new(lines));
                emit(output, format!("WRITEOFF {} entry {id} {} partners {} amount {}", words[2], date_text(date), targets.len(), money(total)));
                for (partner, amount) in targets { emit(output, format!("  {partner} {}", money(amount))); }
            }
            "CLOSE" => {
                let date = parse_date(words[1])?;
                self.check_open(date)?;
                let equity = self.require_type(words[2], AccountType::Equity)?;
                self.active(equity)?;
                let totals = self.totals(0, date, false);
                let targets: Vec<usize> = self.account_ids.values().copied()
                    .filter(|&i| self.accounts[i].kind.temporary() && totals[i].difference() != 0).collect();
                for &index in &targets { self.active(index)?; }
                let mut lines = Vec::new();
                let mut income = 0;
                for index in targets {
                    let difference = totals[index].difference();
                    lines.push(Line::new(if difference > 0 { Side::Credit } else { Side::Debit }, index, difference.abs()));
                    income -= difference;
                }
                if income != 0 { lines.push(Line::new(if income > 0 { Side::Credit } else { Side::Debit }, equity, income.abs())); }
                self.close_counter += 1;
                let entry = if lines.is_empty() { None } else {
                    Some(self.post(format!("CLOSE-{}", self.close_counter), date, Category::Closing, "closing".into(), Lines::new(lines)))
                };
                self.closes.push(CloseRecord { date, entry });
                if let Some(index) = entry {
                    let entry = &self.entries[index];
                    emit(output, format!("CLOSE {} entry {} lines {} net income {}", date_text(date), entry.id, entry.lines.items.len(), money(income)));
                } else { emit(output, format!("CLOSE {} no entry", date_text(date))); }
            }
            "REOPEN" => {
                let record = self.closes.last().copied().ok_or("nothing to reopen")?;
                if let Some(index) = record.entry { self.active_lines(&self.entries[index].lines)?; }
                let detail = if let Some(index) = record.entry {
                    let reversed = self.reverse(index, record.date, Category::Reopen, "reopen".into());
                    format!("entry {}", self.entries[reversed].id)
                } else { "no entry".into() };
                self.closes.pop();
                emit(output, format!("REOPEN {} {detail} closed {}", date_text(record.date), self.closed_text()));
            }
            "LEDGER" => {
                let index = self.account(words[1])?;
                let (start, end) = date_range(words[2], words[3])?;
                let account = &self.accounts[index];
                let mut running = self.balance(index, start - 1);
                let mut totals = Totals::default();
                emit(output, format!("LEDGER {} {} {} {}", account.code, account.name, words[2], words[3]));
                emit(output, format!("  opening {}", money(running)));
                for entry_index in self.ordered() {
                    let entry = &self.entries[entry_index];
                    if !(start..=end).contains(&entry.date) { continue; }
                    for line in &entry.lines.items {
                        if line.account != index { continue; }
                        totals.add(line.side, line.amount);
                        running += account.kind.sign() * line.side.sign() * line.amount;
                        emit(output, format!("  {} {} {} {} balance {} {}", date_text(entry.date), entry.id, line.side.text(),
                                             money(line.amount), money(running), entry.memo));
                    }
                }
                let days = end - start + 1;
                emit(output, format!("  ending {} debits {} credits {} days {days} average {}", money(running),
                                     money(totals.debit), money(totals.credit), money(self.daily_sum(index, start, end) / Money::from(days))));
            }
            "ACTIVITY" => {
                let index = self.account(words[1])?;
                let year: i32 = words[2].parse().unwrap();
                emit(output, format!("ACTIVITY {} {} {year}", words[1], self.accounts[index].name));
                let mut totals = Totals::default();
                for month in 1..=12 {
                    let start = day_number(year, month, 1);
                    let end = start + month_days(year, month) - 1;
                    let current = self.account_totals(index, start, end);
                    totals.merge(current);
                    emit(output, format!("  {year:04}-{month:02} debit {} credit {} balance {}", money(current.debit),
                                         money(current.credit), money(self.balance(index, end))));
                }
                emit(output, format!("  total debit {} credit {}", money(totals.debit), money(totals.credit)));
            }
            "TRIAL" => {
                let date = parse_date(words[1])?;
                let totals = self.totals(0, date, false);
                let mut total = Totals::default();
                emit(output, format!("TRIAL {}", words[1]));
                for &index in self.account_ids.values() {
                    let difference = totals[index].difference();
                    if difference == 0 { continue; }
                    let side = if difference > 0 { "debit" } else { "credit" };
                    let account = &self.accounts[index];
                    emit(output, format!("  {} {} {side} {}", account.code, account.name, money(difference.abs())));
                    if difference > 0 { total.debit += difference; } else { total.credit -= difference; }
                }
                emit(output, format!("  total debit {} credit {}", money(total.debit), money(total.credit)));
            }
            "INCOME" => {
                let (start, end) = date_range(words[1], words[2])?;
                let totals = self.totals(start, end, true);
                emit(output, format!("INCOME {} {}", words[1], words[2]));
                let revenue = self.section("REVENUE", &[AccountType::Revenue], -1, &totals, None, output);
                let expense = self.section("EXPENSE", &[AccountType::Expense], 1, &totals, None, output);
                emit(output, format!("  NET INCOME {}", money(revenue - expense)));
            }
            "BALANCE" => {
                let date = parse_date(words[1])?;
                let totals = self.totals(0, date, false);
                let earnings = -self.accounts.iter().enumerate().filter(|(_, account)| account.kind.temporary())
                    .map(|(i, _)| totals[i].difference()).sum::<Money>();
                emit(output, format!("BALANCE {}", words[1]));
                let assets = self.section("ASSETS", &[AccountType::Asset, AccountType::ContraAsset], 1, &totals, None, output);
                let liabilities = self.section("LIABILITIES", &[AccountType::Liability], -1, &totals, None, output);
                let equity = self.section("EQUITY", &[AccountType::Equity], -1, &totals, Some(earnings), output);
                if assets == liabilities + equity { emit(output, "  check ok"); }
                else { emit(output, format!("  check mismatch {}", money(assets - liabilities - equity))); }
            }
            "ROLLUP" => {
                let date = parse_date(words[2])?;
                let selected: Vec<usize> = self.account_ids.iter().filter(|(code, _)| code.starts_with(words[1])).map(|(_, &i)| i).collect();
                emit(output, format!("ROLLUP {} {}", words[1], words[2]));
                if selected.is_empty() { emit(output, "  (none)"); return Ok(()); }
                let totals = self.totals(0, date, false);
                let mut postings = Totals::default();
                for &index in &selected {
                    let account = &self.accounts[index];
                    let depth = selected.iter().filter(|&&i| i != index && account.code.starts_with(&self.accounts[i].code)).count();
                    let subtotal: Money = selected.iter().filter(|&&i| self.accounts[i].code.starts_with(&account.code))
                        .map(|&i| totals[i].difference()).sum();
                    emit(output, format!("{}{} {} own {} total {}", " ".repeat(2 * (1 + depth)), account.code, account.name,
                                         money(account.kind.sign() * totals[index].difference()), money(account.kind.sign() * subtotal)));
                    postings.merge(totals[index]);
                }
                emit(output, format!("  postings debit {} credit {}", money(postings.debit), money(postings.credit)));
            }
            "AGING" | "ITEMS" => {
                let index = self.account(words[1])?;
                let aging = words[0] == "AGING";
                let date = parse_date(words[if aging { 2 } else { 3 }])?;
                let account = &self.accounts[index];
                let mut settlements = self.settlements(index, date);
                if aging {
                    emit(output, format!("AGING {} {} {}", account.code, account.name, words[2]));
                    let mut totals = [0; 5];
                    for (partner, settlement) in settlements {
                        if settlement.items.is_empty() && settlement.unapplied == 0 { continue; }
                        let mut values = [0, 0, 0, 0, settlement.unapplied];
                        for item in settlement.items {
                            let age = date - self.entries[item.entry].date;
                            let bucket = if age <= 30 { 0 } else if age <= 60 { 1 } else if age <= 90 { 2 } else { 3 };
                            values[bucket] += item.remaining;
                        }
                        emit(output, aging_row(&partner, &values));
                        for i in 0..5 { totals[i] += values[i]; }
                    }
                    emit(output, aging_row("total", &totals));
                } else {
                    emit(output, format!("ITEMS {} {} {} {}", account.code, account.name, words[2], words[3]));
                    let settlement = settlements.remove(words[2]).unwrap_or_default();
                    let mut remaining = 0;
                    for item in settlement.items {
                        let entry = &self.entries[item.entry];
                        remaining += item.remaining;
                        emit(output, format!("  {} {} amount {} open {} age {}", date_text(entry.date), entry.id,
                                             money(item.original), money(item.remaining), date - entry.date));
                    }
                    emit(output, format!("  unapplied {} balance {}", money(settlement.unapplied), money(remaining - settlement.unapplied)));
                }
            }
            "ENTRY" => {
                let index = *self.entry_ids.get(words[1]).ok_or_else(|| format!("unknown entry {}", words[1]))?;
                let entry = &self.entries[index];
                emit(output, format!("ENTRY {} {} {} {}", entry.id, date_text(entry.date), entry.category.text(), entry.memo));
                for line in &entry.lines.items {
                    let account = &self.accounts[line.account];
                    let partner = line.partner.as_ref().map(|name| format!(" {name}")).unwrap_or_default();
                    emit(output, format!("  {} {} {} {}{partner}", line.side.text(), account.code, account.name, money(line.amount)));
                }
                emit(output, format!("  total {}", money(entry.lines.amount.debit)));
                if let Some(original) = entry.reverses { emit(output, format!("  reverses {}", self.entries[original].id)); }
                if let Some(reversal) = entry.reversed_by { emit(output, format!("  reversed by {}", self.entries[reversal].id)); }
            }
            "DAYBOOK" => {
                let (start, end) = date_range(words[1], words[2])?;
                emit(output, format!("DAYBOOK {} {}", words[1], words[2]));
                let mut count = 0;
                let mut total = 0;
                for index in self.ordered() {
                    let entry = &self.entries[index];
                    if !(start..=end).contains(&entry.date) { continue; }
                    count += 1;
                    total += entry.lines.amount.debit;
                    emit(output, format!("  {} {} {} {} {}", date_text(entry.date), entry.id, entry.category.text(), money(entry.lines.amount.debit), entry.memo));
                }
                emit(output, format!("  total entries {count} amount {}", money(total)));
            }
            "ACCOUNTS" => {
                emit(output, "ACCOUNTS");
                let totals = self.totals(0, Day::MAX, false);
                for &index in self.account_ids.values() {
                    let account = &self.accounts[index];
                    let status = if account.active { "active" } else { "inactive" };
                    emit(output, format!("  {} {} {} parent {} balance {} {status}", account.code, account.kind.text(), account.name,
                                         self.parent_code(index), money(account.kind.sign() * totals[index].difference())));
                }
                if self.accounts.is_empty() { emit(output, "  (none)"); }
            }
            "TEMPLATES" => {
                emit(output, "TEMPLATES");
                for (name, template) in &self.templates {
                    emit(output, format!("  {name} {} lines {} amount {} used {}", template.memo, template.lines.items.len(),
                                         money(template.lines.amount.debit), template.uses));
                }
                if self.templates.is_empty() { emit(output, "  (none)"); }
            }
            "STATUS" => {
                let inactive = self.accounts.iter().filter(|account| !account.active).count();
                let open = self.draft.as_ref().map(|draft| draft.key.as_str()).unwrap_or("none");
                emit(output, format!("STATUS accounts {} inactive {inactive} entries {} templates {} closed {} open {open}",
                                     self.accounts.len(), self.entries.len(), self.templates.len(), self.closed_text()));
            }
            _ => unreachable!(),
        }
        Ok(())
    }
}

fn aging_row(name: &str, values: &[Money; 5]) -> String {
    let balance = values[..4].iter().sum::<Money>() - values[4];
    format!("  {name} 0-30 {} 31-60 {} 61-90 {} 91+ {} unapplied {} balance {}",
            money(values[0]), money(values[1]), money(values[2]), money(values[3]), money(values[4]), money(balance))
}

fn main() {
    let stdin = io::stdin();
    let mut input = stdin.lock().lines();
    let count: usize = input.next().unwrap().unwrap().parse().unwrap();
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    let mut book = Book::default();
    for line in input.take(count) {
        let line = line.unwrap();
        let words: Vec<&str> = line.split_whitespace().collect();
        if let Err(error) = book.execute(&words, &mut output) { emit(&mut output, format!("ERROR {error}")); }
    }
}
