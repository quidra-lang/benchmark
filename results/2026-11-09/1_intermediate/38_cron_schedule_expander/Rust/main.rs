use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::io::{self, BufRead, Write};

type Checked<T> = Result<T, String>;
const FIELD_NAMES: [&str; 5] = ["minute", "hour", "day-of-month", "month", "day-of-week"];
const MINIMUM: [i32; 5] = [0, 0, 1, 1, 0];
const MAXIMUM: [i32; 5] = [59, 23, 31, 12, 7];
const MONTHS: [&str; 12] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const WEEKDAYS: [&str; 7] = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

fn digits(text: &str, minimum: usize, maximum: usize) -> bool {
    (minimum..=maximum).contains(&text.len()) && text.bytes().all(|c| c.is_ascii_digit())
}
fn integer(text: &str) -> i32 { text.parse().unwrap() }
fn leap(year: i32) -> bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }
fn month_length(year: i32, month: i32) -> i32 {
    [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month as usize - 1] + (month == 2 && leap(year)) as i32
}
#[derive(Clone, Copy)]
struct Date { year: i32, month: i32, day: i32 }
impl Date {
    fn number(self) -> i32 {
        let years: i32 = (2000..self.year).map(|y| if leap(y) { 366 } else { 365 }).sum();
        years + (1..self.month).map(|m| month_length(self.year, m)).sum::<i32>() + self.day - 1
    }
    fn from_number(mut number: i32) -> Self {
        let mut year = 2000;
        loop {
            let days = if leap(year) { 366 } else { 365 };
            if number < days { break; }
            number -= days; year += 1;
        }
        let mut month = 1;
        while number >= month_length(year, month) { number -= month_length(year, month); month += 1; }
        Self { year, month, day: number + 1 }
    }
    fn weekday(self) -> i32 { (self.number() + 6) % 7 }
}
impl fmt::Display for Date {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:04}-{:02}-{:02} {}", self.year, self.month, self.day, &WEEKDAYS[self.weekday() as usize][..3])
    }
}
fn pattern(text: &str, pattern: &str) -> bool {
    text.len() == pattern.len() && text.bytes().zip(pattern.bytes()).all(|(a, b)| if b == b'#' { a.is_ascii_digit() } else { a == b })
}
fn read_date(text: &str, reason: &str) -> Checked<Date> {
    if !pattern(text, "####-##-##") { return Err(reason.into()); }
    let date = Date { year: integer(&text[..4]), month: integer(&text[5..7]), day: integer(&text[8..]) };
    if !(2001..=2098).contains(&date.year) || !(1..=12).contains(&date.month) || date.day < 1 || date.day > month_length(date.year, date.month) {
        return Err(reason.into());
    }
    Ok(date)
}
fn read_datetime(words: &[&str], at: usize) -> Checked<i32> {
    let date = read_date(words[at], "invalid datetime")?;
    let time = words[at + 1];
    if !pattern(time, "##:##") { return Err("invalid datetime".into()); }
    let hour = integer(&time[..2]); let minute = integer(&time[3..]);
    if hour > 23 || minute > 59 { return Err("invalid datetime".into()); }
    Ok(date.number() * 1440 + hour * 60 + minute)
}
fn read_month(text: &str) -> Checked<Date> {
    if !pattern(text, "####-##") { return Err("invalid month".into()); }
    let date = Date { year: integer(&text[..4]), month: integer(&text[5..]), day: 1 };
    if !(2001..=2098).contains(&date.year) || !(1..=12).contains(&date.month) { return Err("invalid month".into()); }
    Ok(date)
}
fn datetime_text(time: i32) -> String {
    let date = Date::from_number(time / 1440);
    format!("{:04}-{:02}-{:02} {:02}:{:02} {}", date.year, date.month, date.day, time % 1440 / 60, time % 60, &WEEKDAYS[date.weekday() as usize][..3])
}
fn span(minutes: i32) -> String { format!("{}d{:02}h{:02}m", minutes / 1440, minutes % 1440 / 60, minutes % 60) }
fn positive(text: &str, width: usize, maximum: i32, reason: &str) -> Checked<i32> {
    if !digits(text, 1, width) || text.starts_with('0') || integer(text) > maximum { Err(reason.into()) } else { Ok(integer(text)) }
}
fn window(words: &[&str], at: usize) -> Checked<(i32, i32)> {
    let low = read_datetime(words, at)?;
    let high = read_datetime(words, at + 2)?;
    if low > high { return Err("invalid window".into()); }
    if high - low > 44640 { return Err("window too long".into()); }
    Ok((low, high))
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Special { Last, LastWorkday, BeforeLast(i32), Nearest(i32), Nth(i32, i32), LastWeekday(i32) }
impl fmt::Display for Special {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Last => write!(f, "L"), Self::LastWorkday => write!(f, "LW"), Self::BeforeLast(n) => write!(f, "L-{n}"),
            Self::Nearest(n) => write!(f, "{n}W"), Self::Nth(v, n) => write!(f, "{v}#{n}"), Self::LastWeekday(v) => write!(f, "{v}L"),
        }
    }
}
struct Field { values: BTreeSet<i32>, specials: Vec<Special>, restricted: bool }
fn read_value(text: &str, index: usize) -> Checked<i32> {
    let names: &[&str] = match index {
        3 => &["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"],
        4 => &["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], _ => &[],
    };
    if let Some(position) = names.iter().position(|&name| name == text) { return Ok(position as i32 + (index == 3) as i32); }
    if !digits(text, 1, 2) { return Err("invalid value".into()); }
    let value = integer(text);
    if !(MINIMUM[index]..=MAXIMUM[index]).contains(&value) { return Err("out of range".into()); }
    Ok(value)
}
fn special_number(text: &str, maximum: i32, width: usize) -> Checked<i32> {
    if !digits(text, 1, width) { return Err("invalid value".into()); }
    let value = integer(text);
    if !(1..=maximum).contains(&value) { return Err("out of range".into()); }
    Ok(value)
}
impl Field {
    fn parse(text: &str, index: usize) -> Checked<Self> {
        let mut field = Self { values: BTreeSet::new(), specials: Vec::new(), restricted: !text.starts_with('*') };
        for item in text.split(',') { field.add_item(item, index).map_err(|reason| format!("{} {reason}", FIELD_NAMES[index]))?; }
        Ok(field)
    }
    fn add_item(&mut self, item: &str, index: usize) -> Checked<()> {
        if item.is_empty() { return Err("empty item".into()); }
        let special = if index == 2 && (item.starts_with('L') || item.ends_with('W')) {
            Some(match item {
                "L" => Special::Last, "LW" => Special::LastWorkday,
                _ if item.starts_with("L-") => Special::BeforeLast(special_number(&item[2..], 30, 2)?),
                _ if item.ends_with('W') => Special::Nearest(special_number(&item[..item.len() - 1], 31, 2)?),
                _ => return Err("invalid value".into()),
            })
        } else if index == 4 && item.contains('#') {
            let (value, n) = item.split_once('#').unwrap();
            let weekday = read_value(value, index)?;
            Some(Special::Nth(weekday % 7, special_number(n, 5, 1)?))
        } else if index == 4 && item.len() >= 2 && item.ends_with('L') {
            Some(Special::LastWeekday(read_value(&item[..item.len() - 1], index)? % 7))
        } else { None };
        if let Some(special) = special {
            if !self.specials.contains(&special) { self.specials.push(special); }
            return Ok(());
        }
        let (base, step) = item.split_once('/').map_or((item, None), |(base, step)| (base, Some(step)));
        let (first, last) = if base == "*" { (MINIMUM[index], MAXIMUM[index]) }
        else if let Some((a, b)) = base.split_once('-') {
            let a = read_value(a, index)?; let b = read_value(b, index)?;
            if a > b { return Err("invalid range".into()); }
            (a, b)
        } else {
            let a = read_value(base, index)?;
            (a, if step.is_some() { MAXIMUM[index] } else { a })
        };
        let step = match step {
            Some(text) if !digits(text, 1, 2) || integer(text) == 0 => return Err("invalid step".into()),
            Some(text) => integer(text), None => 1,
        };
        for value in (first..=last).step_by(step as usize) { self.values.insert(if index == 4 { value % 7 } else { value }); }
        Ok(())
    }
    fn stepped(&self, maximum: i32) -> i32 {
        let values: Vec<i32> = self.values.iter().copied().collect();
        if values.len() < 2 || values[0] != 0 || values[1] < 2 { return 0; }
        let step = values[1];
        if (0..=maximum).step_by(step as usize).eq(values) { step } else { 0 }
    }
    fn value_list(&self, index: usize, either: bool) -> String {
        let name = |value: i32| match index { 3 => MONTHS[value as usize - 1].to_string(), 4 => WEEKDAYS[value as usize].to_string(), _ => value.to_string() };
        let values: Vec<i32> = self.values.iter().copied().collect();
        let mut parts = Vec::new(); let mut first = 0;
        while first < values.len() {
            let mut last = first;
            while last + 1 < values.len() && values[last + 1] == values[last] + 1 { last += 1; }
            if last - first >= 2 { parts.push(format!("{} through {}", name(values[first]), name(values[last]))); }
            else { parts.extend(values[first..=last].iter().map(|&v| name(v))); }
            first = last + 1;
        }
        word_list(&parts, either)
    }
    fn day_phrase(&self, weekday: bool, either: bool) -> String {
        let mut parts = Vec::new();
        if !self.values.is_empty() {
            parts.push(if weekday { self.value_list(4, either) }
                else { format!("{} {}", if self.values.len() == 1 { "day" } else { "days" }, self.value_list(2, false)) });
        }
        for &item in &self.specials {
            parts.push(match item {
                Special::Last => "the last day".into(), Special::LastWorkday => "the last weekday".into(),
                Special::BeforeLast(n) => format!("{n} {} before the last day", if n == 1 { "day" } else { "days" }),
                Special::Nearest(n) => format!("the weekday nearest day {n}"),
                Special::Nth(v, n) => format!("the {} {}", ["1st", "2nd", "3rd", "4th", "5th"][n as usize - 1], WEEKDAYS[v as usize]),
                Special::LastWeekday(v) => format!("the last {}", WEEKDAYS[v as usize]),
            });
        }
        format!("{}{}", word_list(&parts, either), if !weekday || !self.specials.is_empty() { " of the month" } else { "" })
    }
}
fn word_list(parts: &[String], either: bool) -> String {
    if parts.len() < 2 { return parts.join(""); }
    format!("{} {} {}", parts[..parts.len() - 1].join(", "), if either { "or" } else { "and" }, parts.last().unwrap())
}
struct Cron { fields: [Field; 5], daily: Vec<i32>, text: String, expanded: String }
impl Cron {
    fn parse(words: &[&str]) -> Checked<Self> {
        let text = words.join(" ");
        let macro_text = if words.len() == 1 && words[0].starts_with('@') {
            Some(match words[0] {
                "@yearly" | "@annually" => "0 0 1 1 *", "@monthly" => "0 0 1 * *", "@weekly" => "0 0 * * 0",
                "@daily" | "@midnight" => "0 0 * * *", "@hourly" => "0 * * * *", _ => return Err("unknown macro".into()),
            })
        } else { None };
        let expanded_words: Vec<&str> = macro_text.map_or_else(|| words.to_vec(), |m| m.split(' ').collect());
        if expanded_words.len() != 5 { return Err("field count".into()); }
        let mut parsed = Vec::new();
        for (i, word) in expanded_words.iter().enumerate() { parsed.push(Field::parse(word, i)?); }
        let fields: [Field; 5] = parsed.try_into().ok().unwrap();
        let daily = fields[1].values.iter().flat_map(|&h| fields[0].values.iter().map(move |&m| h * 60 + m)).collect();
        Ok(Self { fields, daily, text, expanded: expanded_words.join(" ") })
    }
    fn or_rule(&self) -> bool { self.fields[2].restricted && self.fields[4].restricted }
    fn match_day(&self, date: Date) -> (bool, bool, bool) {
        let last = month_length(date.year, date.month); let weekday = date.weekday();
        let nearest = |day: i32| match (date.number() - date.day + day + 6) % 7 {
            6 => if day == 1 { 3 } else { day - 1 }, 0 => if day == last { day - 2 } else { day + 1 }, _ => day,
        };
        let dom = self.fields[2].values.contains(&date.day) || self.fields[2].specials.iter().any(|&item| match item {
            Special::Last => date.day == last, Special::LastWorkday => date.day == nearest(last),
            Special::BeforeLast(n) => date.day == last - n, Special::Nearest(n) => n <= last && date.day == nearest(n), _ => false,
        });
        let dow = self.fields[4].values.contains(&weekday) || self.fields[4].specials.iter().any(|&item| match item {
            Special::Nth(v, n) => weekday == v && (date.day - 1) / 7 + 1 == n,
            Special::LastWeekday(v) => weekday == v && date.day + 7 > last, _ => false,
        });
        (dom, dow, if self.or_rule() { dom || dow } else { dom && dow })
    }
    fn scheduled(&self, date: Date) -> bool { self.fields[3].values.contains(&date.month) && self.match_day(date).2 }
    fn fires(&self, low: i32, high: i32, holidays: &BTreeSet<i32>, reverse: bool, limit: Option<usize>) -> Vec<i32> {
        let first = low / 1440; let last = high / 1440; let step = if reverse { -1 } else { 1 };
        let mut result = Vec::new(); let mut day = if reverse { last } else { first };
        while day >= first && day <= last {
            if !holidays.contains(&day) && self.scheduled(Date::from_number(day)) {
                let mut i = if reverse { self.daily.len() as i32 - 1 } else { 0 };
                while i >= 0 && i < self.daily.len() as i32 {
                    let time = day * 1440 + self.daily[i as usize];
                    if low <= time && time <= high {
                        result.push(time);
                        if limit == Some(result.len()) { return result; }
                    }
                    i += step;
                }
            }
            day += step;
        }
        result
    }
    fn description(&self) -> String {
        let [minute, hour, dom, month, dow] = &self.fields;
        let mut text = if self.daily.len() <= 4 {
            let times: Vec<String> = self.daily.iter().map(|t| format!("{:02}:{:02}", t / 60, t % 60)).collect();
            format!("At {}", word_list(&times, false))
        } else {
            let ms = minute.stepped(59); let hs = hour.stepped(23);
            let mut text = if minute.values.len() == 60 { "Every minute".into() }
                else if ms > 0 { format!("Every {ms} minutes") }
                else { format!("At {} {}", if minute.values.len() == 1 { "minute" } else { "minutes" }, minute.value_list(0, false)) };
            if hour.values.len() == 24 { if text.starts_with("At minute") { text.push_str(" of every hour"); } }
            else if hs > 0 { text.push_str(&format!(", every {hs} hours")); }
            else if hour.values.last().unwrap() - hour.values.first().unwrap() + 1 == hour.values.len() as i32 {
                text.push_str(&format!(", between {:02}:00 and {:02}:59", hour.values.first().unwrap(), hour.values.last().unwrap()));
            } else { text.push_str(&format!(", during hours {}", hour.value_list(1, false))); }
            text
        };
        let d_full = dom.values.len() == 31; let w_full = dow.values.len() == 7;
        if self.or_rule() {
            if !d_full && !w_full { text.push_str(&format!(", on {} or on {}", dom.day_phrase(false, false), dow.day_phrase(true, false))); }
        } else if !d_full && !w_full { text.push_str(&format!(", on {} if it is {}", dom.day_phrase(false, false), dow.day_phrase(true, true))); }
        else if !d_full { text.push_str(&format!(", on {}", dom.day_phrase(false, false))); }
        else if !w_full { text.push_str(&format!(", on {}", dow.day_phrase(true, false))); }
        if month.values.len() != 12 { text.push_str(&format!(", in {}", month.value_list(3, false))); }
        text
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Policy { Allow, Forbid, Replace }
impl fmt::Display for Policy {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result { write!(f, "{}", match self { Self::Allow => "ALLOW", Self::Forbid => "FORBID", Self::Replace => "REPLACE" }) }
}
struct Job { cron: Cron, enabled: bool, duration: i32, policy: Policy }
#[derive(Default)]
struct Scheduler { jobs: BTreeMap<String, Job>, holidays: BTreeSet<i32> }
impl Scheduler {
    fn job(&self, id: &str) -> Checked<&Job> { self.jobs.get(id).ok_or_else(|| "unknown job".into()) }
    fn new_id(&self, id: &str) -> Checked<()> {
        if !(1..=16).contains(&id.len()) || !id.as_bytes()[0].is_ascii_lowercase() || !id.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_') {
            return Err("invalid id".into());
        }
        if self.jobs.contains_key(id) { return Err("duplicate job".into()); }
        Ok(())
    }
    fn enabled(&self) -> Vec<(&str, &Job)> { self.jobs.iter().filter(|(_, j)| j.enabled).map(|(id, j)| (id.as_str(), j)).collect() }
    fn timeline(&self, low: i32, high: i32, conflicts: bool) -> Vec<String> {
        let enabled = self.enabled();
        let mut masks = vec![0_u64; (high - low + 1) as usize];
        for (i, (_, job)) in enabled.iter().enumerate() {
            for time in job.cron.fires(low, high, &self.holidays, false, None) { masks[(time - low) as usize] |= 1 << i; }
        }
        let total: usize = masks.iter().map(|m| if conflicts { (m.count_ones() >= 2) as usize } else { m.count_ones() as usize }).sum();
        let peak = masks.iter().map(|m| m.count_ones()).filter(|&n| n >= 2).max().unwrap_or(0);
        let mut rows = vec![if conflicts { format!("CONFLICTS {total} peak {peak}") } else { format!("TIMELINE {total}") }];
        for (offset, &mask) in masks.iter().enumerate() {
            if rows.len() == 101 { break; }
            if conflicts {
                if mask.count_ones() < 2 { continue; }
                let ids: Vec<&str> = enabled.iter().enumerate().filter(|(i, _)| mask & (1_u64 << *i) != 0).map(|(_, (id, _))| *id).collect();
                rows.push(format!("{} {} {}", datetime_text(low + offset as i32), ids.len(), ids.join(" ")));
            } else {
                for (i, (id, _)) in enabled.iter().enumerate() {
                    if rows.len() == 101 { break; }
                    if mask & (1 << i) != 0 { rows.push(format!("{} {id}", datetime_text(low + offset as i32))); }
                }
            }
        }
        if total > 100 { rows.push(format!("... {} more", total - 100)); }
        rows
    }
    fn simulate(&self, low: i32, high: i32) -> Vec<String> {
        let enabled = self.enabled();
        let mut events = vec![0; (high - low + 1441) as usize];
        let mut rows = Vec::new();
        for &(id, job) in &enabled {
            let (mut started, mut skipped, mut replaced, mut busy) = (0, 0, 0, 0);
            let mut last_end = -1;
            for time in job.cron.fires(low, high, &self.holidays, false, None) {
                if last_end > time && job.policy == Policy::Forbid { skipped += 1; continue; }
                if last_end > time && job.policy == Policy::Replace {
                    events[(last_end - low) as usize] += 1; events[(time - low) as usize] -= 1;
                    busy -= last_end - time; replaced += 1;
                }
                last_end = time + job.duration;
                events[(time - low) as usize] += 1; events[(last_end - low) as usize] -= 1;
                started += 1; busy += job.duration;
            }
            rows.push(format!("{id} {} started {started} skipped {skipped} replaced {replaced} busy {busy}", job.policy));
        }
        let (mut running, mut peak, mut at) = (0, 0, 0);
        for (i, change) in events.into_iter().enumerate() { running += change; if running > peak { peak = running; at = low + i as i32; } }
        rows.insert(0, format!("SIMULATE {} peak {peak}{}", enabled.len(), if peak == 0 { String::new() } else { format!(" at {}", datetime_text(at)) }));
        rows
    }
    fn execute(&mut self, words: &[&str]) -> Checked<Vec<String>> {
        let command = words[0];
        let expected: i32 = match command {
            "JOB" => -3, "VALIDATE" => -2, "REMOVE" | "ENABLE" | "DISABLE" | "DESCRIBE" | "WEEK" | "EXCLUDE" | "INCLUDE" => 2,
            "RENAME" | "EXPAND" | "CALENDAR" => 3, "RUNTIME" | "MATCH" | "GAP" => 4,
            "NEXT" | "PREV" | "TIMELINE" | "CONFLICTS" | "SIMULATE" => 5, "COUNT" => 6, "OVERLAP" => 7,
            "LIST" | "HOLIDAYS" => 1, _ => return Err("unknown command".into()),
        };
        let wrong_count = if expected < 0 { words.len() < (-expected) as usize } else { words.len() != expected as usize };
        if wrong_count { return Err("wrong arguments".into()); }
        match command {
            "JOB" => {
                self.new_id(words[1])?;
                let cron = Cron::parse(&words[2..])?;
                self.jobs.insert(words[1].into(), Job { cron, enabled: true, duration: 1, policy: Policy::Allow });
                Ok(vec![format!("JOB {} added", words[1])])
            }
            "VALIDATE" => { let cron = Cron::parse(&words[1..])?; Ok(vec![format!("VALID {} {} {}", cron.expanded, if cron.or_rule() { "OR" } else { "AND" }, cron.daily.len())]) }
            "REMOVE" => { self.job(words[1])?; self.jobs.remove(words[1]); Ok(vec![format!("REMOVE {}", words[1])]) }
            "RENAME" => {
                self.job(words[1])?; self.new_id(words[2])?;
                let job = self.jobs.remove(words[1]).unwrap(); self.jobs.insert(words[2].into(), job);
                Ok(vec![format!("RENAME {} {}", words[1], words[2])])
            }
            "ENABLE" | "DISABLE" => {
                let job = self.jobs.get_mut(words[1]).ok_or("unknown job")?;
                let enabled = command == "ENABLE";
                if job.enabled == enabled { return Err(format!("already {}", if enabled { "enabled" } else { "disabled" })); }
                job.enabled = enabled;
                Ok(vec![format!("{command} {}", words[1])])
            }
            "RUNTIME" => {
                self.job(words[1])?;
                let duration = positive(words[2], 4, 1440, "invalid duration")?;
                let policy = match words[3] { "ALLOW" => Policy::Allow, "FORBID" => Policy::Forbid, "REPLACE" => Policy::Replace, _ => return Err("invalid policy".into()) };
                let job = self.jobs.get_mut(words[1]).unwrap(); job.duration = duration; job.policy = policy;
                Ok(vec![format!("RUNTIME {} {duration} {policy}", words[1])])
            }
            "LIST" => {
                let mut rows = vec![format!("LIST {}", self.jobs.len())];
                rows.extend(self.jobs.iter().map(|(id, job)| format!("{id} {} {} {} {}", if job.enabled { "on" } else { "off" }, job.duration, job.policy, job.cron.text)));
                Ok(rows)
            }
            "EXPAND" => {
                let job = self.job(words[1])?;
                let index = FIELD_NAMES.iter().position(|&name| name == words[2]).ok_or("invalid field")?;
                let field = &job.cron.fields[index];
                let mut items: Vec<String> = field.values.iter().map(ToString::to_string).collect();
                items.extend(field.specials.iter().map(ToString::to_string));
                Ok(vec![format!("EXPAND {} {} {}{}", words[1], words[2], field.values.len(), if items.is_empty() { String::new() } else { format!(" {}", items.join(" ")) })])
            }
            "DESCRIBE" => Ok(vec![format!("DESCRIBE {} {}", words[1], self.job(words[1])?.cron.description())]),
            "MATCH" => {
                let job = self.job(words[1])?; let time = read_datetime(words, 2)?;
                let date = Date::from_number(time / 1440); let (dom, dow, condition) = job.cron.match_day(date);
                let mut reasons = Vec::new();
                if !job.cron.fields[0].values.contains(&(time % 60)) { reasons.push("minute"); }
                if !job.cron.fields[1].values.contains(&(time % 1440 / 60)) { reasons.push("hour"); }
                if !condition && !dom { reasons.push("day-of-month"); }
                if !job.cron.fields[3].values.contains(&date.month) { reasons.push("month"); }
                if !condition && !dow { reasons.push("day-of-week"); }
                if self.holidays.contains(&(time / 1440)) { reasons.push("excluded"); }
                Ok(vec![format!("MATCH {} {} {}", words[1], datetime_text(time), if reasons.is_empty() { "yes".into() } else { format!("no {}", reasons.join(" ")) })])
            }
            "NEXT" | "PREV" => {
                let job = self.job(words[1])?; let base = read_datetime(words, 2)?;
                let limit = positive(words[4], 2, 50, "invalid count")? as usize; let reverse = command == "PREV";
                let times = job.cron.fires(if reverse { base - 527040 } else { base + 1 }, if reverse { base - 1 } else { base + 527040 }, &self.holidays, reverse, Some(limit));
                let mut rows = vec![format!("{command} {} {}", words[1], times.len())];
                rows.extend(times.iter().map(|&t| format!("{} {}{}", datetime_text(t), if reverse { '-' } else { '+' }, span((t - base).abs()))));
                if times.len() < limit { rows.push("NONE".into()); }
                Ok(rows)
            }
            "COUNT" => {
                let job = self.job(words[1])?; let (low, high) = window(words, 2)?;
                let times = job.cron.fires(low, high, &self.holidays, false, None);
                let days: BTreeSet<i32> = times.iter().map(|t| t / 1440).collect();
                Ok(vec![format!("COUNT {} runs {} days {}", words[1], times.len(), days.len())])
            }
            "GAP" => {
                let job = self.job(words[1])?; let base = read_datetime(words, 2)?;
                let times = job.cron.fires(base, base + 44640, &self.holidays, false, None);
                if times.len() < 2 { return Ok(vec![format!("GAP {} runs {} none", words[1], times.len())]); }
                let mut histogram = BTreeMap::new(); let mut longest = 0; let mut first = 0;
                for (i, pair) in times.windows(2).enumerate() {
                    let gap = pair[1] - pair[0]; *histogram.entry(gap).or_insert(0) += 1;
                    if gap > longest { longest = gap; first = i; }
                }
                let shortest = *histogram.keys().next().unwrap();
                let mut rows = vec![format!("GAP {} runs {} shortest {} longest {} from {} to {}", words[1], times.len(), span(shortest), span(longest), datetime_text(times[first]), datetime_text(times[first + 1]))];
                rows.extend(histogram.iter().map(|(&gap, count)| format!("{} {count}", span(gap))));
                Ok(rows)
            }
            "OVERLAP" => {
                let a = self.job(words[1])?; let b = self.job(words[2])?; let (low, high) = window(words, 3)?;
                let other: BTreeSet<i32> = b.cron.fires(low, high, &self.holidays, false, None).into_iter().collect();
                let times: Vec<i32> = a.cron.fires(low, high, &self.holidays, false, None).into_iter().filter(|t| other.contains(t)).collect();
                Ok(vec![format!("OVERLAP {} {} {}{}", words[1], words[2], times.len(), if times.is_empty() { String::new() } else { format!(" first {} last {}", datetime_text(times[0]), datetime_text(*times.last().unwrap())) })])
            }
            "TIMELINE" | "CONFLICTS" | "SIMULATE" => {
                let (low, high) = window(words, 1)?;
                Ok(if command == "SIMULATE" { self.simulate(low, high) } else { self.timeline(low, high, command == "CONFLICTS") })
            }
            "WEEK" => {
                let first = read_date(words[1], "invalid date")?.number(); let mut counts = [[0; 24]; 7];
                for (_, job) in self.enabled() {
                    for time in job.cron.fires(first * 1440, (first + 7) * 1440 - 1, &self.holidays, false, None) { counts[(time / 1440 - first) as usize][(time % 1440 / 60) as usize] += 1; }
                }
                let total: i32 = counts.iter().flatten().sum(); let mut rows = vec![format!("WEEK {} {total}", words[1])];
                for (d, hours) in counts.iter().enumerate() {
                    let heat: String = hours.iter().map(|&n| if n == 0 { '.' } else if n >= 10 { '+' } else { (b'0' + n as u8) as char }).collect();
                    rows.push(format!("{} {heat} {}", Date::from_number(first + d as i32), hours.iter().sum::<i32>()));
                }
                Ok(rows)
            }
            "CALENDAR" => {
                let job = self.job(words[1])?; let first = read_month(words[2])?;
                let mut cells = vec!["...".to_string(); first.weekday() as usize]; let mut days = 0;
                for d in 1..=month_length(first.year, first.month) {
                    let date = Date { day: d, ..first };
                    let mark = if !job.cron.scheduled(date) { '-' } else if self.holidays.contains(&date.number()) { 'x' } else { '*' };
                    if mark == '*' { days += 1; }
                    cells.push(format!("{d:02}{mark}"));
                }
                while cells.len() % 7 != 0 { cells.push("...".into()); }
                let mut rows = vec![format!("CALENDAR {} {} days {days} runs {}", words[1], words[2], days * job.cron.daily.len()), "Sun Mon Tue Wed Thu Fri Sat".into()];
                rows.extend(cells.chunks(7).map(|week| week.join(" "))); Ok(rows)
            }
            "EXCLUDE" | "INCLUDE" => {
                let date = read_date(words[1], "invalid date")?;
                if command == "EXCLUDE" { if !self.holidays.insert(date.number()) { return Err("already excluded".into()); } }
                else if !self.holidays.remove(&date.number()) { return Err("not excluded".into()); }
                Ok(vec![format!("{command} {date} holidays {}", self.holidays.len())])
            }
            "HOLIDAYS" => {
                let mut rows = vec![format!("HOLIDAYS {}", self.holidays.len())];
                rows.extend(self.holidays.iter().map(|&day| Date::from_number(day).to_string())); Ok(rows)
            }
            _ => unreachable!(),
        }
    }
}

fn main() {
    let stdin = io::stdin(); let mut lines = stdin.lock().lines();
    let Some(Ok(first)) = lines.next() else { return; };
    let count: usize = first.parse().unwrap();
    let mut scheduler = Scheduler::default(); let mut output = io::BufWriter::new(io::stdout().lock());
    for _ in 0..count {
        let line = lines.next().unwrap().unwrap();
        let words: Vec<&str> = line.split(' ').filter(|word| !word.is_empty()).collect();
        match scheduler.execute(&words) {
            Ok(rows) => for row in rows { writeln!(output, "{row}").unwrap(); },
            Err(reason) => writeln!(output, "ERROR {reason}").unwrap(),
        }
    }
}
