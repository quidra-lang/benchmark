use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::io::{self, Read};

const FIELDS: [&str; 32] = [
    "R", "O", "D", "N", "P", "accrued", "salary", "leave", "deduction",
    "sales", "commission", "earnings", "bonus", "gross", "retirement", "health",
    "federal", "supplemental", "state", "social", "medicare", "garnishment", "net",
    "employer_social", "employer_medicare", "unemployment", "match", "employer",
    "W", "Y", "F", "J",
];
const SETTINGS: [(&str, i64); 15] = [
    ("STATE", 500), ("SUPP", 2200), ("SSRATE", 620), ("MEDRATE", 145),
    ("ADDMED", 90), ("UIRATE", 270), ("MATCH", 5000), ("MATCHMAX", 600),
    ("GARNCAP", 2500), ("SSBASE", 16860000), ("ADDBASE", 20000000),
    ("UIBASE", 700000), ("RETIRECAP", 2300000), ("ALLOWANCE", 15000),
    ("NIGHT", 100),
];
const WEEKDAYS: [&str; 7] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

type Stub = HashMap<String, i64>;

fn cents(text: &str) -> i64 {
    let (whole, fraction) = text.split_once('.').unwrap();
    whole.parse::<i64>().unwrap() * 100 + fraction.parse::<i64>().unwrap()
}

fn money(value: i64) -> String {
    format!("{}.{:02}", value / 100, value % 100)
}

fn rate_text(value: i64) -> String {
    format!("{}%", money(value))
}

fn duration(minutes: i64) -> String {
    format!("{}:{:02}", minutes / 60, minutes % 60)
}

fn clock(minutes: i32) -> String {
    format!("{:02}:{:02}", minutes / 60, minutes % 60)
}

fn weekday(day: i32) -> &'static str {
    WEEKDAYS[((day - 1) % 7) as usize]
}

fn period_of(day: i32) -> i32 {
    (day - 1) / 14 + 1
}

fn new_stub() -> Stub {
    FIELDS.iter().map(|field| ((*field).to_string(), 0)).collect()
}

fn value(stub: &Stub, field: &str) -> i64 {
    *stub.get(field).unwrap_or(&0)
}

fn set(stub: &mut Stub, field: &str, amount: i64) {
    stub.insert(field.to_string(), amount);
}

fn sum_stubs<'a>(stubs: impl IntoIterator<Item = &'a Stub>) -> Stub {
    let mut totals = new_stub();
    for stub in stubs {
        for field in FIELDS {
            *totals.get_mut(field).unwrap() += value(stub, field);
        }
    }
    totals
}

fn progressive(table: &BTreeMap<i64, i64>, amount: i64) -> i64 {
    let pairs: Vec<(i64, i64)> = table.iter().map(|(a, b)| (*a, *b)).collect();
    let mut numerator = 0;
    for (i, (lower, rate)) in pairs.iter().enumerate() {
        if *lower >= amount {
            break;
        }
        let upper = pairs.get(i + 1).map_or(amount, |next| next.0);
        numerator += rate * (amount.min(upper) - lower);
    }
    numerator / 10000
}

fn deduct(stub: &mut Stub, remaining: &mut i64, field: &str, amount: i64) {
    let actual = amount.min(*remaining);
    set(stub, field, actual);
    *remaining -= actual;
}

#[derive(Clone)]
struct Garnishment {
    rate: i64,
    balance: i64,
}

#[derive(Clone, Copy)]
struct Shift {
    start: i32,
    end: i32,
}

#[derive(Clone)]
struct Employee {
    id: i32,
    department: String,
    kind: String,
    base: i64,
    active: bool,
    retirement: i64,
    health: i64,
    allowances: i64,
    extra: i64,
    garnishments: Vec<Garnishment>,
    bonus: i64,
    pto_balance: i64,
    shifts: BTreeMap<i32, Vec<Shift>>,
    pto: BTreeMap<i32, i64>,
    leave: BTreeSet<i32>,
    sales: BTreeMap<i32, i64>,
    stubs: BTreeMap<i32, (Stub, String)>,
    ytd: Stub,
    periods: i32,
}

impl Employee {
    fn new(id: i32, department: &str, kind: &str, base: i64) -> Self {
        Self {
            id, department: department.into(), kind: kind.into(), base,
            active: true, retirement: 0, health: 0, allowances: 0, extra: 0,
            garnishments: Vec::new(), bonus: 0, pto_balance: 0,
            shifts: BTreeMap::new(), pto: BTreeMap::new(),
            leave: BTreeSet::new(), sales: BTreeMap::new(),
            stubs: BTreeMap::new(), ytd: new_stub(), periods: 0,
        }
    }

    fn garnish_balance(&self) -> i64 {
        self.garnishments.iter().map(|order| order.balance).sum()
    }
}

struct Calculation {
    stub: Stub,
    balances: Vec<i64>,
}

struct Payroll {
    settings: BTreeMap<String, i64>,
    brackets: BTreeMap<i64, i64>,
    tiers: BTreeMap<i64, i64>,
    holidays: BTreeSet<i32>,
    employees: BTreeMap<i32, Employee>,
    closed: i32,
    output: Vec<String>,
}

impl Payroll {
    fn new() -> Self {
        Self {
            settings: SETTINGS.iter().map(|(name, value)| (name.to_string(), *value)).collect(),
            brackets: BTreeMap::new(),
            tiers: BTreeMap::new(),
            holidays: BTreeSet::new(),
            employees: BTreeMap::new(),
            closed: 0,
            output: Vec::new(),
        }
    }

    fn emit(&mut self, line: String, indent: usize) {
        self.output.push(format!("{}{line}", " ".repeat(indent)));
    }

    fn setting(&self, name: &str) -> i64 {
        self.settings[name]
    }

    fn employee(&self, id: &str, active: bool, kind: Option<&str>) -> Result<&Employee, String> {
        let person = self.employees.get(&id.parse::<i32>().unwrap())
            .ok_or_else(|| format!("unknown employee {id}"))?;
        if active && !person.active {
            return Err(format!("terminated employee {id}"));
        }
        if let Some(kind) = kind {
            if person.kind != kind {
                return Err(format!("not {} {id}", kind.to_ascii_lowercase()));
            }
        }
        Ok(person)
    }

    fn day_check(&self, text: &str) -> Result<i32, String> {
        let day = text.parse::<i32>().unwrap();
        if !(1..=364).contains(&day) {
            return Err(format!("invalid day {text}"));
        }
        let period = period_of(day);
        if period <= self.closed {
            return Err(format!("period closed {period}"));
        }
        Ok(day)
    }

    fn period_check(&self, text: &str) -> Result<i32, String> {
        let period = text.parse::<i32>().unwrap();
        if !(1..=26).contains(&period) {
            Err(format!("invalid period {text}"))
        } else {
            Ok(period)
        }
    }

    fn rate_check(text: &str) -> Result<i64, String> {
        let amount = cents(text);
        if amount > 10000 {
            Err(format!("invalid rate {text}"))
        } else {
            Ok(amount)
        }
    }

    fn amount_check(text: &str) -> Result<i64, String> {
        let amount = cents(text);
        if amount == 0 {
            Err("invalid amount".into())
        } else {
            Ok(amount)
        }
    }

    fn time_check(text: &str) -> Result<i32, String> {
        let (hour, minute) = text.split_once(':').unwrap();
        let hour = hour.parse::<i32>().unwrap();
        let minute = minute.parse::<i32>().unwrap();
        if hour > 23 || minute > 59 {
            Err(format!("invalid time {text}"))
        } else {
            Ok(hour * 60 + minute)
        }
    }

    fn daily(&self, employee: &Employee, day: i32) -> [i64; 6] {
        let shifts = employee.shifts.get(&day);
        let mut worked = 0i64;
        let mut night = 0i64;
        if let Some(shifts) = shifts {
            for shift in shifts {
                worked += (shift.end - shift.start) as i64;
                night += (shift.end.min(360) - shift.start).max(0) as i64;
                night += (shift.end - shift.start.max(1320)).max(0) as i64;
            }
        }
        let pto = *employee.pto.get(&day).unwrap_or(&0);
        let special = day % 7 == 0 || self.holidays.contains(&day);
        let (regular, overtime, double) = if special {
            (0, 0, worked)
        } else {
            (worked.min(480), (worked - 480).max(0).min(240), (worked - 720).max(0))
        };
        [worked, regular, overtime, double, night, pto]
    }

    fn weekly(&self, employee: &Employee, week: i32) -> ([i64; 5], i64) {
        let mut total = [0; 5];
        for day in (7 * week - 6)..=(7 * week) {
            let daily = self.daily(employee, day);
            for i in 0..5 {
                total[i] += daily[i + 1];
            }
        }
        let extra = (total[0] - 2400).max(0);
        total[0] -= extra;
        total[1] += extra;
        (total, extra)
    }

    fn breakdown(&self, employee: &Employee, period: i32) -> [i64; 5] {
        let (first, _) = self.weekly(employee, 2 * period - 1);
        let (second, _) = self.weekly(employee, 2 * period);
        let mut result = [0; 5];
        for i in 0..5 {
            result[i] = first[i] + second[i];
        }
        result
    }

    fn calculate(&self, employee: &Employee, period: i32) -> Option<Calculation> {
        let mut stub = new_stub();
        let ytd = &employee.ytd;
        match employee.kind.as_str() {
            "HOURLY" => {
                let [regular, overtime, double, night, pto] =
                    self.breakdown(employee, period);
                for (field, amount) in ["R", "O", "D", "N", "P"]
                    .iter().zip([regular, overtime, double, night, pto]) {
                    set(&mut stub, field, amount);
                }
                let weighted = 2 * (regular + pto) + 3 * overtime + 4 * double;
                set(&mut stub, "earnings",
                    (weighted * employee.base + 2 * night * self.setting("NIGHT")) / 120);
            }
            "SALARIED" => {
                if employee.active {
                    let salary = employee.base / 26;
                    let leave = employee.leave.iter()
                        .filter(|day| period_of(**day) == period &&
                                !self.holidays.contains(day)).count() as i64;
                    let deduction = leave * (employee.base / 260);
                    set(&mut stub, "salary", salary);
                    set(&mut stub, "leave", leave);
                    set(&mut stub, "deduction", deduction);
                    set(&mut stub, "earnings", salary - deduction);
                }
            }
            "COMMISSION" => {
                let sales = *employee.sales.get(&period).unwrap_or(&0);
                let commission = progressive(&self.tiers, sales);
                set(&mut stub, "sales", sales);
                set(&mut stub, "commission", commission);
                set(&mut stub, "earnings",
                    commission + if employee.active { employee.base } else { 0 });
            }
            _ => unreachable!(),
        }
        set(&mut stub, "bonus", employee.bonus);
        let gross = value(&stub, "earnings") + employee.bonus;
        if gross == 0 {
            return None;
        }
        set(&mut stub, "gross", gross);
        let mut remaining = gross;

        let room = (self.setting("RETIRECAP") - value(ytd, "retirement")).max(0);
        deduct(&mut stub, &mut remaining, "retirement",
               (gross * employee.retirement / 10000).min(room));
        deduct(&mut stub, &mut remaining, "health", employee.health);
        set(&mut stub, "W", remaining);
        let base_taxable =
            (value(&stub, "earnings") - value(&stub, "retirement") - value(&stub, "health")).max(0);
        let taxable = (base_taxable - employee.allowances * self.setting("ALLOWANCE")).max(0);
        deduct(&mut stub, &mut remaining, "federal",
               progressive(&self.brackets, taxable) + employee.extra);
        deduct(&mut stub, &mut remaining, "supplemental",
               (value(&stub, "W") - base_taxable) * self.setting("SUPP") / 10000);
        deduct(&mut stub, &mut remaining, "state",
               value(&stub, "W") * self.setting("STATE") / 10000);

        let medicare_wages = gross - value(&stub, "health");
        let social_wages = medicare_wages.min((self.setting("SSBASE") - value(ytd, "Y")).max(0));
        let additional = (value(ytd, "F") + medicare_wages - self.setting("ADDBASE"))
            .min(medicare_wages).max(0);
        set(&mut stub, "F", medicare_wages);
        set(&mut stub, "Y", social_wages);
        deduct(&mut stub, &mut remaining, "social",
               social_wages * self.setting("SSRATE") / 10000);
        deduct(&mut stub, &mut remaining, "medicare",
               medicare_wages * self.setting("MEDRATE") / 10000 +
               additional * self.setting("ADDMED") / 10000);

        let disposable = remaining;
        let cap = disposable * self.setting("GARNCAP") / 10000;
        let mut garnishment = 0;
        let mut balances = Vec::new();
        for order in &employee.garnishments {
            let taken = (disposable * order.rate / 10000)
                .min(order.balance).min(cap - garnishment);
            garnishment += taken;
            balances.push(order.balance - taken);
        }
        set(&mut stub, "garnishment", garnishment);
        set(&mut stub, "garnishment_balance", balances.iter().sum());
        set(&mut stub, "net", remaining - garnishment);
        set(&mut stub, "employer_social",
            social_wages * self.setting("SSRATE") / 10000);
        set(&mut stub, "employer_medicare",
            medicare_wages * self.setting("MEDRATE") / 10000);
        let j = medicare_wages.min((self.setting("UIBASE") - value(ytd, "J")).max(0));
        set(&mut stub, "J", j);
        set(&mut stub, "unemployment", j * self.setting("UIRATE") / 10000);
        let eligible_match = value(&stub, "retirement")
            .min(gross * self.setting("MATCHMAX") / 10000);
        set(&mut stub, "match", eligible_match * self.setting("MATCH") / 10000);
        set(&mut stub, "employer",
            ["employer_social", "employer_medicare", "unemployment", "match"]
                .iter().map(|f| value(&stub, f)).sum());
        if employee.kind == "HOURLY" {
            set(&mut stub, "accrued",
                (960 - employee.pto_balance)
                    .min((value(&stub, "R") + value(&stub, "O") + value(&stub, "D")) / 20));
        }
        set(&mut stub, "pto_balance", employee.pto_balance + value(&stub, "accrued"));
        Some(Calculation { stub, balances })
    }

    fn hours_parts(times: &[i64; 5]) -> String {
        ["reg", "ot", "dbl", "night", "pto"].iter()
            .zip(times).map(|(label, amount)| format!("{label} {}", duration(*amount)))
            .collect::<Vec<_>>().join(" ")
    }

    fn stub_block(&mut self, person: &Employee, stub: &Stub, indent: usize) {
        match person.kind.as_str() {
            "HOURLY" => {
                let times = ["R", "O", "D", "N", "P"].map(|field| value(stub, field));
                self.emit(format!("hours {}", Self::hours_parts(&times)), indent);
                self.emit(format!("pto accrued {} balance {}",
                    duration(value(stub, "accrued")), duration(value(stub, "pto_balance"))), indent);
            }
            "SALARIED" => self.emit(format!("salary {} leave {} deduction {}",
                money(value(stub, "salary")), value(stub, "leave"),
                money(value(stub, "deduction"))), indent),
            "COMMISSION" => self.emit(format!("sales {} commission {}",
                money(value(stub, "sales")), money(value(stub, "commission"))), indent),
            _ => unreachable!(),
        }
        for field in ["earnings", "bonus", "gross", "retirement", "health",
                      "federal", "supplemental", "state", "social", "medicare"] {
            let label = if field == "social" { "social-security" } else { field };
            self.emit(format!("{label} {}", money(value(stub, field))), indent);
        }
        self.emit(format!("garnishment {} balance {}",
                money(value(stub, "garnishment")),
                money(value(stub, "garnishment_balance"))), indent);
        self.emit(format!("net {}", money(value(stub, "net"))), indent);
        self.emit(format!("employer social-security {} medicare {} unemployment {} match {}",
                money(value(stub, "employer_social")),
                money(value(stub, "employer_medicare")),
                money(value(stub, "unemployment")),
                money(value(stub, "match"))), indent);
    }

    fn print_stub(&mut self, person: &Employee, period: i32,
                  stub: &Stub, department: &str) {
        self.emit(format!("STUB {} {department} {} period {period}",
                          person.id, person.kind), 2);
        self.stub_block(person, stub, 4);
    }

    fn show_hours(&mut self, person: &Employee, period: i32) {
        self.emit(format!("HOURS {} period {period}", person.id), 0);
        let mut found = false;
        for day in (14 * period - 13)..=(14 * period) {
            let mut shifts = person.shifts.get(&day).cloned().unwrap_or_default();
            shifts.sort_by_key(|shift| shift.start);
            if shifts.is_empty() && !person.pto.contains_key(&day) {
                continue;
            }
            let daily = self.daily(person, day);
            let mut text = format!("day {day} {}", weekday(day));
            if self.holidays.contains(&day) {
                text += " holiday";
            }
            for shift in shifts {
                text += &format!(" {}-{}", clock(shift.start), clock(shift.end));
            }
            let values = [daily[1], daily[2], daily[3], daily[4], daily[5]];
            text += &format!(" total {} {}", duration(daily[0]), Self::hours_parts(&values));
            self.emit(text, 2);
            found = true;
        }
        if !found {
            self.emit("(none)".into(), 2);
        }
        for week in [2 * period - 1, 2 * period] {
            let (values, overtime) = self.weekly(person, week);
            self.emit(format!("week {week} {} weekly-ot {}",
                Self::hours_parts(&values), duration(overtime)), 2);
        }
        self.emit(format!("total {}", Self::hours_parts(&self.breakdown(person, period))), 2);
    }

    fn run(&mut self, period: i32) {
        self.closed = period;
        self.emit(format!("RUN {period} days {}-{}", 14 * period - 13, 14 * period), 0);
        let mut paid = 0;
        let mut skipped = 0;
        let mut stubs = Vec::new();
        let ids: Vec<i32> = self.employees.keys().copied().collect();
        for id in ids {
            let person = self.employees[&id].clone();
            let calculated = self.calculate(&person, period);
            let Some(calculation) = calculated else {
                if person.active {
                    skipped += 1;
                }
                continue;
            };
            self.print_stub(&person, period, &calculation.stub, &person.department);
            let employee = self.employees.get_mut(&id).unwrap();
            employee.bonus = 0;
            employee.pto_balance = value(&calculation.stub, "pto_balance");
            for (order, balance) in employee.garnishments.iter_mut().zip(&calculation.balances) {
                order.balance = *balance;
            }
            for field in FIELDS {
                *employee.ytd.get_mut(field).unwrap() += value(&calculation.stub, field);
            }
            employee.periods += 1;
            employee.stubs.insert(period, (calculation.stub.clone(), employee.department.clone()));
            stubs.push(calculation.stub);
            paid += 1;
        }
        let total = sum_stubs(stubs.iter());
        self.emit(format!(
            "TOTAL paid {paid} skipped {skipped} gross {} deductions {} net {} employer {}",
            money(value(&total, "gross")),
            money(value(&total, "gross") - value(&total, "net")),
            money(value(&total, "net")),
            money(value(&total, "employer"))
        ), 2);
    }

    fn journal(&mut self, period: i32) {
        let stubs: Vec<Stub> = self.employees.values()
            .filter_map(|person| person.stubs.get(&period).map(|record| record.0.clone()))
            .collect();
        let total = sum_stubs(stubs.iter());
        let rows = [
            ("debit", "wages", value(&total, "gross")),
            ("debit", "employer-tax",
                value(&total, "employer_social") + value(&total, "employer_medicare")
                + value(&total, "unemployment")),
            ("debit", "retirement-match", value(&total, "match")),
            ("credit", "retirement", value(&total, "retirement") + value(&total, "match")),
            ("credit", "health", value(&total, "health")),
            ("credit", "federal", value(&total, "federal") + value(&total, "supplemental")),
            ("credit", "state", value(&total, "state")),
            ("credit", "fica", value(&total, "social") + value(&total, "medicare")
                + value(&total, "employer_social") + value(&total, "employer_medicare")),
            ("credit", "unemployment", value(&total, "unemployment")),
            ("credit", "garnishment", value(&total, "garnishment")),
            ("credit", "net-pay", value(&total, "net")),
        ];
        self.emit(format!("JOURNAL {period} stubs {}", stubs.len()), 0);
        let mut debits = 0;
        let mut credits = 0;
        for (side, label, amount) in rows {
            self.emit(format!("{side} {label} {}", money(amount)), 2);
            if side == "debit" {
                debits += amount;
            } else {
                credits += amount;
            }
        }
        self.emit(format!("total debit {} credit {}", money(debits), money(credits)), 2);
    }

    fn report_line(&mut self, department: &str, stubs: &[Stub]) {
        let total = sum_stubs(stubs.iter());
        let taxes: i64 = ["federal", "supplemental", "state", "social", "medicare"]
            .iter().map(|field| value(&total, field)).sum();
        self.emit(format!(
            "{department} stubs {} gross {} pretax {} taxes {} garnishment {} net {} employer {}",
            stubs.len(), money(value(&total, "gross")),
            money(value(&total, "retirement") + value(&total, "health")),
            money(taxes), money(value(&total, "garnishment")),
            money(value(&total, "net")), money(value(&total, "employer"))
        ), 2);
    }

    fn command(&mut self, parts: &[&str]) -> Result<(), String> {
        let cmd = parts[0];
        let a = &parts[1..];
        match cmd {
            "SET" => {
                if !self.settings.contains_key(a[0]) {
                    return Err(format!("unknown setting {}", a[0]));
                }
                let rate = SETTINGS.iter().take(9).any(|(name, _)| *name == a[0]);
                let new = if rate { Self::rate_check(a[1])? } else { cents(a[1]) };
                let before = self.settings[a[0]];
                self.settings.insert(a[0].to_string(), new);
                self.emit(format!("SET {} {} -> {}", a[0],
                    if rate { rate_text(before) } else { money(before) },
                    if rate { rate_text(new) } else { money(new) }), 0);
            }
            "BRACKET" | "TIER" => {
                let rate = Self::rate_check(a[1])?;
                let lower = cents(a[0]);
                let table = if cmd == "BRACKET" { &mut self.brackets } else { &mut self.tiers };
                let action = if table.insert(lower, rate).is_some() { "replaced" } else { "added" };
                self.emit(format!("{cmd} {} {} {action}", money(lower), rate_text(rate)), 0);
            }
            "EMP" => {
                let id = a[0].parse::<i32>().unwrap();
                if self.employees.contains_key(&id) {
                    return Err(format!("duplicate employee {}", a[0]));
                }
                let base = Self::amount_check(a[3])?;
                self.employees.insert(id, Employee::new(id, a[1], a[2], base));
                self.emit(format!("EMP {id} {} {} {}", a[1], a[2], money(base)), 0);
            }
            "RATE" | "DEPT" | "BENEFIT" | "W4" | "GARNISH" | "TERM" | "BONUS" => {
                let old = self.employee(a[0], true, None)?.clone();
                let id = old.id;
                match cmd {
                    "RATE" => {
                        let base = Self::amount_check(a[1])?;
                        self.employees.get_mut(&id).unwrap().base = base;
                        self.emit(format!("RATE {id} {} -> {}", money(old.base), money(base)), 0);
                    }
                    "DEPT" => {
                        if a[1] == old.department {
                            return Err(format!("same department {}", a[1]));
                        }
                        self.employees.get_mut(&id).unwrap().department = a[1].into();
                        self.emit(format!("DEPT {id} {} -> {}", old.department, a[1]), 0);
                    }
                    "BENEFIT" => {
                        let rate = Self::rate_check(a[1])?;
                        let health = cents(a[2]);
                        let employee = self.employees.get_mut(&id).unwrap();
                        employee.retirement = rate;
                        employee.health = health;
                        self.emit(format!("BENEFIT {id} retirement {} health {}",
                                          rate_text(rate), money(health)), 0);
                    }
                    "W4" => {
                        let count = a[1].parse::<i64>().unwrap();
                        let extra = cents(a[2]);
                        let employee = self.employees.get_mut(&id).unwrap();
                        employee.allowances = count;
                        employee.extra = extra;
                        self.emit(format!("W4 {id} allowances {count} extra {}", money(extra)), 0);
                    }
                    "GARNISH" => {
                        let rate = Self::rate_check(a[1])?;
                        let balance = Self::amount_check(a[2])?;
                        let employee = self.employees.get_mut(&id).unwrap();
                        employee.garnishments.push(Garnishment { rate, balance });
                        let position = employee.garnishments.len();
                        self.emit(format!("GARNISH {id} order {position} {} balance {}",
                                          rate_text(rate), money(balance)), 0);
                    }
                    "TERM" => {
                        self.employees.get_mut(&id).unwrap().active = false;
                        self.emit(format!("TERM {id}"), 0);
                    }
                    "BONUS" => {
                        let amount = Self::amount_check(a[1])?;
                        let employee = self.employees.get_mut(&id).unwrap();
                        employee.bonus += amount;
                        let pending = employee.bonus;
                        self.emit(format!("BONUS {id} {} pending {}", money(amount),
                                          money(pending)), 0);
                    }
                    _ => unreachable!(),
                }
            }
            "HOLIDAY" => {
                let day = self.day_check(a[0])?;
                if !self.holidays.insert(day) {
                    return Err(format!("duplicate holiday {}", a[0]));
                }
                self.emit(format!("HOLIDAY {day} {}", weekday(day)), 0);
            }
            "TIME" | "UNTIME" | "PTO" | "LEAVE" | "SALES" => {
                let kind = match cmd {
                    "LEAVE" => "SALARIED",
                    "SALES" => "COMMISSION",
                    _ => "HOURLY",
                };
                let person = self.employee(a[0], true, Some(kind))?.clone();
                let id = person.id;
                let day = self.day_check(a[1])?;
                match cmd {
                    "TIME" => {
                        let start = Self::time_check(a[2])?;
                        let end = Self::time_check(a[3])?;
                        if start >= end {
                            return Err(format!("invalid shift {}-{}", a[2], a[3]));
                        }
                        let mut shifts = person.shifts.get(&day).cloned().unwrap_or_default();
                        shifts.sort_by_key(|shift| shift.start);
                        for shift in &shifts {
                            if start < shift.end && shift.start < end {
                                return Err(format!("overlapping shift {}-{}",
                                                   clock(shift.start), clock(shift.end)));
                            }
                        }
                        let worked: i32 = shifts.iter().map(|shift| shift.end - shift.start).sum();
                        if worked + end - start > 960 {
                            return Err(format!("daily limit {} {}", a[0], a[1]));
                        }
                        self.employees.get_mut(&id).unwrap().shifts.entry(day).or_default()
                            .push(Shift { start, end });
                        self.emit(format!("TIME {id} day {day} {}-{} {}",
                                          clock(start), clock(end),
                                          duration((end - start) as i64)), 0);
                    }
                    "UNTIME" => {
                        let start = Self::time_check(a[2])?;
                        let shifts = person.shifts.get(&day).cloned().unwrap_or_default();
                        let found = shifts.iter().find(|shift| shift.start == start)
                            .copied().ok_or_else(|| {
                                format!("no shift {} {} {}", a[0], a[1], a[2])
                            })?;
                        let live = self.employees.get_mut(&id).unwrap()
                            .shifts.get_mut(&day).unwrap();
                        let position = live.iter().position(|shift| shift.start == start).unwrap();
                        live.remove(position);
                        self.emit(format!("UNTIME {id} day {day} {}-{}",
                                          clock(found.start), clock(found.end)), 0);
                    }
                    "PTO" => {
                        let (hours, minutes) = a[2].split_once(':').unwrap();
                        let hours = hours.parse::<i64>().unwrap();
                        let minutes = minutes.parse::<i64>().unwrap();
                        let length = hours * 60 + minutes;
                        if minutes > 59 || !(1..=480).contains(&length) {
                            return Err(format!("invalid duration {}", a[2]));
                        }
                        if person.pto.contains_key(&day) {
                            return Err(format!("duplicate pto {} {}", a[0], a[1]));
                        }
                        if length > person.pto_balance {
                            return Err(format!("insufficient pto {} {}",
                                               a[0], duration(person.pto_balance)));
                        }
                        let employee = self.employees.get_mut(&id).unwrap();
                        employee.pto.insert(day, length);
                        employee.pto_balance -= length;
                        let balance = employee.pto_balance;
                        self.emit(format!("PTO {id} day {day} {} balance {}",
                                          duration(length), duration(balance)), 0);
                    }
                    "LEAVE" => {
                        if day % 7 == 0 || day % 7 == 6 || self.holidays.contains(&day) {
                            return Err(format!("not workday {}", a[1]));
                        }
                        if person.leave.contains(&day) {
                            return Err(format!("duplicate leave {} {}", a[0], a[1]));
                        }
                        self.employees.get_mut(&id).unwrap().leave.insert(day);
                        self.emit(format!("LEAVE {id} day {day} {}", weekday(day)), 0);
                    }
                    "SALES" => {
                        let amount = Self::amount_check(a[2])?;
                        let period = period_of(day);
                        let employee = self.employees.get_mut(&id).unwrap();
                        *employee.sales.entry(period).or_insert(0) += amount;
                        let total = employee.sales[&period];
                        self.emit(format!("SALES {id} day {day} {} period {period} total {}",
                                          money(amount), money(total)), 0);
                    }
                    _ => unreachable!(),
                }
            }
            "HOURS" => {
                let person = self.employee(a[0], false, Some("HOURLY"))?.clone();
                let period = self.period_check(a[1])?;
                self.show_hours(&person, period);
            }
            "RUN" => {
                let period = a[0].parse::<i32>().unwrap();
                if period != self.closed + 1 || period > 26 {
                    return Err(format!("invalid period {}", a[0]));
                }
                self.run(period);
            }
            "PREVIEW" => {
                let person = self.employee(a[0], false, None)?.clone();
                let period = self.closed + 1;
                let calculated = self.calculate(&person, period);
                self.emit(format!("PREVIEW {} period {period}", person.id), 0);
                if let Some(result) = calculated {
                    self.print_stub(&person, period, &result.stub, &person.department);
                } else {
                    self.emit("no pay".into(), 2);
                }
            }
            "REPRINT" => {
                let person = self.employee(a[0], false, None)?.clone();
                let period = self.period_check(a[1])?;
                let (stub, department) = person.stubs.get(&period)
                    .ok_or_else(|| format!("no stub {} {}", a[0], a[1]))?;
                self.emit(format!("REPRINT {} {period}", person.id), 0);
                self.print_stub(&person, period, stub, department);
            }
            "YTD" => {
                let person = self.employee(a[0], false, None)?.clone();
                self.emit(format!("YTD {} {} {} {} periods {}", person.id,
                    person.department, person.kind,
                    if person.active { "active" } else { "terminated" }, person.periods), 0);
                let mut totals = person.ytd.clone();
                set(&mut totals, "pto_balance", person.pto_balance);
                set(&mut totals, "garnishment_balance", person.garnish_balance());
                self.stub_block(&person, &totals, 2);
                self.emit(format!("wages federal {} social-security {} medicare {} unemployment {}",
                    money(value(&totals, "W")), money(value(&totals, "Y")),
                    money(value(&totals, "F")), money(value(&totals, "J"))), 2);
                self.emit(format!("retirement-room {} pending-bonus {}",
                    money((self.setting("RETIRECAP") - value(&totals, "retirement")).max(0)),
                    money(person.bonus)), 2);
            }
            "JOURNAL" => {
                let period = a[0].parse::<i32>().unwrap();
                if period < 1 || period > self.closed {
                    return Err(format!("no run {}", a[0]));
                }
                self.journal(period);
            }
            "REPORT" => {
                let mut departments: BTreeMap<String, Vec<Stub>> = BTreeMap::new();
                let mut stubs = Vec::new();
                for person in self.employees.values() {
                    for (stub, department) in person.stubs.values() {
                        departments.entry(department.clone()).or_default().push(stub.clone());
                        stubs.push(stub.clone());
                    }
                }
                self.emit(format!("REPORT period {}", self.closed), 0);
                for (department, entries) in &departments {
                    self.report_line(department, entries);
                }
                self.report_line("total", &stubs);
            }
            "TOP" => {
                let limit = a[0].parse::<usize>().unwrap();
                let mut people: Vec<Employee> = self.employees.values()
                    .filter(|e| e.periods > 0).cloned().collect();
                people.sort_by(|a, b| {
                    value(&b.ytd, "gross").cmp(&value(&a.ytd, "gross"))
                        .then(a.id.cmp(&b.id))
                });
                self.emit(format!("TOP {limit}"), 0);
                for (rank, person) in people.iter().take(limit).enumerate() {
                    self.emit(format!("{} {} {} gross {} net {}", rank + 1,
                        person.id, person.department,
                        money(value(&person.ytd, "gross")),
                        money(value(&person.ytd, "net"))), 2);
                }
                if people.is_empty() {
                    self.emit("(none)".into(), 2);
                }
            }
            "EMPLOYEES" => {
                self.emit("EMPLOYEES".into(), 0);
                let people: Vec<Employee> = self.employees.values().cloned().collect();
                for person in &people {
                    self.emit(format!(
                        "{} {} {} {} {} retirement {} health {} allowances {} extra {} bonus {}",
                        person.id, person.department, person.kind, money(person.base),
                        if person.active { "active" } else { "terminated" },
                        rate_text(person.retirement), money(person.health),
                        person.allowances, money(person.extra), money(person.bonus)
                    ), 2);
                    for (index, order) in person.garnishments.iter().enumerate() {
                        self.emit(format!("garnish {} {} balance {}",
                            index + 1, rate_text(order.rate), money(order.balance)), 4);
                    }
                }
                if people.is_empty() {
                    self.emit("(none)".into(), 2);
                }
            }
            "CONFIG" => {
                self.emit("CONFIG".into(), 0);
                for (index, (name, _)) in SETTINGS.iter().enumerate() {
                    let amount = self.setting(name);
                    self.emit(format!("{name} {}", if index < 9 { rate_text(amount) }
                                                        else { money(amount) }), 2);
                }
                let brackets: Vec<(i64, i64)> =
                    self.brackets.iter().map(|(a, b)| (*a, *b)).collect();
                let tiers: Vec<(i64, i64)> =
                    self.tiers.iter().map(|(a, b)| (*a, *b)).collect();
                for (lower, rate) in brackets {
                    self.emit(format!("bracket {} {}", money(lower), rate_text(rate)), 2);
                }
                for (lower, rate) in tiers {
                    self.emit(format!("tier {} {}", money(lower), rate_text(rate)), 2);
                }
            }
            _ => unreachable!("command names are guaranteed valid"),
        }
        Ok(())
    }

    fn execute(&mut self, line: &str) {
        let parts: Vec<&str> = line.split_ascii_whitespace().collect();
        if let Err(error) = self.command(&parts) {
            self.emit(format!("ERROR {error}"), 0);
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut payroll = Payroll::new();
    for line in lines.take(count) {
        payroll.execute(line);
    }
    if !payroll.output.is_empty() {
        println!("{}", payroll.output.join("\n"));
    }
}
