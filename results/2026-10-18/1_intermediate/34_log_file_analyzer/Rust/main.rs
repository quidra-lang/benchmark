use std::collections::BTreeMap;
use std::io::{self, BufRead, Write};

const METHODS: [&str; 7] = ["GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"];
const REASONS: [&str; 9] = ["fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency"];
const CLASSES: [&str; 5] = ["1xx", "2xx", "3xx", "4xx", "5xx"];
const KEYS: [&str; 4] = ["METHOD", "STATUS", "IP", "PATH"];
const REQUIRE_RECORDS: [&str; 14] = [
    "STATUS", "METHODS", "TOP", "HOURLY", "TIMELINE", "BANDWIDTH", "VISITORS",
    "HISTOGRAM", "APDEX", "ERRORS", "SLOWEST", "BURST", "PEAK", "GAPS",
];
type QueryResult = Result<Vec<String>, &'static str>;

fn ensure(condition: bool, message: &'static str) -> Result<(), &'static str> {
    if condition { Ok(()) } else { Err(message) }
}

fn argument_kinds(name: &str) -> Option<&'static [&'static str]> {
    match name {
        "SUMMARY" | "MALFORMED" | "STATUS" | "METHODS" | "HOURLY" | "BANDWIDTH"
        | "VISITORS" | "ERRORS" | "RESET" | "STATE" => Some(&[]),
        "TOP" => Some(&["kind", "limit"]),
        "TIMELINE" => Some(&["minutes"]),
        "LATENCY" => Some(&["path"]),
        "HISTOGRAM" => Some(&["width"]),
        "APDEX" => Some(&["threshold"]),
        "SLOWEST" => Some(&["limit"]),
        "SESSIONS" => Some(&["ip", "minutes"]),
        "BURST" => Some(&["length", "times"]),
        "PEAK" | "GAPS" => Some(&["length"]),
        "IP" => Some(&["ip"]),
        "RANGE" => Some(&["date", "time", "date", "time"]),
        "FILTER" => Some(&["key", "value"]),
        "UNFILTER" => Some(&["subject"]),
        _ => None,
    }
}

fn digits(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|b| b.is_ascii_digit())
}

fn canonical(value: &str, limit: usize) -> bool {
    value.len() <= limit && digits(value) && (value.len() == 1 || !value.starts_with('0'))
}

fn leap(year: i32) -> bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

fn year_days(year: i32) -> i64 {
    if leap(year) { 366 } else { 365 }
}

fn month_days(year: i32, month: usize) -> i64 {
    if month == 2 && leap(year) { 29 }
    else { [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1] }
}

fn date_parts(value: &str) -> Option<(i32, usize, i64)> {
    let fields: Vec<&str> = value.split('-').collect();
    if fields.len() != 3 || fields[0].len() != 4 || fields[1].len() != 2
        || fields[2].len() != 2 || !fields.iter().all(|s| digits(s)) {
        return None;
    }
    let year = fields[0].parse().ok()?;
    let month = fields[1].parse().ok()?;
    let day = fields[2].parse().ok()?;
    if !(2000..=2059).contains(&year) || !(1..=12).contains(&month)
        || day < 1 || day > month_days(year, month) {
        None
    } else {
        Some((year, month, day))
    }
}

fn clock_parts(value: &str) -> Option<[i64; 3]> {
    let fields: Vec<&str> = value.split(':').collect();
    if fields.len() != 3 || !fields.iter().all(|s| s.len() == 2 && digits(s)) {
        return None;
    }
    let parts = [fields[0].parse().ok()?, fields[1].parse().ok()?, fields[2].parse().ok()?];
    if parts[0] < 24 && parts[1] < 60 && parts[2] < 60 { Some(parts) } else { None }
}

fn valid_ip(value: &str) -> bool {
    let parts: Vec<&str> = value.split('.').collect();
    parts.len() == 4 && parts.iter().all(|s| canonical(s, 3) && s.parse::<u16>().unwrap() <= 255)
}

fn valid_status(value: &str) -> bool {
    value.len() == 3 && digits(value) && (100..=599).contains(&value.parse::<u16>().unwrap())
}

fn valid_filter(key: &str, value: &str) -> bool {
    match key {
        "METHOD" => METHODS.contains(&value),
        "STATUS" => CLASSES.contains(&value) || valid_status(value),
        "IP" => valid_ip(value),
        _ => value.starts_with('/'),
    }
}

fn validate_argument(kind: &str, value: &str, args: &[&str]) -> Result<(), &'static str> {
    let bound = match kind {
        "limit" => Some(100), "minutes" => Some(1440),
        "width" | "threshold" => Some(100000), "length" => Some(86400),
        "times" => Some(1000), _ => None,
    };
    if let Some(maximum) = bound {
        return ensure(canonical(value, 6) && (1..=maximum).contains(&value.parse::<u32>().unwrap()), "invalid number");
    }
    let (valid, reason) = match kind {
        "kind" => (value == "PATHS" || value == "IPS", "invalid kind"),
        "path" => (value.starts_with('/'), "invalid path"),
        "ip" => (valid_ip(value), "invalid ip"),
        "date" => (date_parts(value).is_some(), "invalid timestamp"),
        "time" => (clock_parts(value).is_some(), "invalid timestamp"),
        "key" => (KEYS.contains(&value), "invalid key"),
        "subject" => (value == "RANGE" || KEYS.contains(&value), "invalid key"),
        _ => (valid_filter(args[0], value), "invalid value"),
    };
    ensure(valid, reason)
}

fn malformed_reason(fields: &[&str]) -> Option<&'static str> {
    if fields.len() != 8 { return Some("fields"); }
    if date_parts(fields[0]).is_none() { return Some("date"); }
    if clock_parts(fields[1]).is_none() { return Some("time"); }
    if !valid_ip(fields[2]) { return Some("ip"); }
    if !METHODS.contains(&fields[3]) { return Some("method"); }
    if !fields[4].starts_with('/') { return Some("path"); }
    if !valid_status(fields[5]) { return Some("status"); }
    if !canonical(fields[6], 8) { return Some("bytes"); }
    if !canonical(fields[7], 6) { return Some("latency"); }
    None
}

fn seconds_of(date: &str, clock: &str) -> i64 {
    let (year, month, day) = date_parts(date).unwrap();
    let [hour, minute, second] = clock_parts(clock).unwrap();
    let days = day - 1 + (2000..year).map(year_days).sum::<i64>()
        + (1..month).map(|m| month_days(year, m)).sum::<i64>();
    days * 86400 + hour * 3600 + minute * 60 + second
}

fn interval_label(seconds: i64) -> String {
    let mut days = seconds / 86400;
    let mut year = 2000;
    while days >= year_days(year) { days -= year_days(year); year += 1; }
    let mut month = 1;
    while days >= month_days(year, month) { days -= month_days(year, month); month += 1; }
    format!("{year:04}-{month:02}-{:02} {:02}:{:02}", days + 1, seconds % 86400 / 3600, seconds % 3600 / 60)
}

fn normalize_path(value: &str) -> String {
    let mut parts = Vec::new();
    for part in value.split('?').next().unwrap().split('/') {
        match part {
            ".." => { parts.pop(); }
            "" | "." => {}
            _ => parts.push(part),
        }
    }
    let parts: Vec<&str> = parts.into_iter().map(|part| {
        if digits(part) { "{id}" }
        else if part.len() >= 8 && part.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
            && part.bytes().any(|b| b.is_ascii_digit()) { "{hex}" }
        else { part }
    }).collect();
    format!("/{}", parts.join("/"))
}

fn ip_number(value: &str) -> u64 {
    value.split('.').fold(0, |n, part| n * 256 + part.parse::<u64>().unwrap())
}

fn status_matches(value: &str, status: u16) -> bool {
    if CLASSES.contains(&value) { status / 100 == (value.as_bytes()[0] - b'0') as u16 }
    else { status == value.parse::<u16>().unwrap() }
}

fn decimal(numerator: u64, denominator: u64, places: usize) -> String {
    let scale = 10_u64.pow(places as u32);
    let value = numerator * scale / denominator;
    format!("{}.{:0width$}", value / scale, value % scale, width = places)
}

fn percent(part: usize, whole: usize) -> String {
    format!("{}%", decimal(part as u64 * 100, whole as u64, 2))
}

fn bytes_text(value: u64) -> String {
    for (unit, suffix) in [(1073741824, "GB"), (1048576, "MB"), (1024, "KB")] {
        if value >= unit { return format!("{}{suffix}", decimal(value, unit, 1)); }
    }
    format!("{value}B")
}

struct Record {
    line: usize,
    date: String,
    timestamp: String,
    seconds: i64,
    hour: usize,
    ip: String,
    method: String,
    path: String,
    status: u16,
    bytes: u64,
    latency: u64,
}

impl Record {
    fn new(line: usize, f: &[&str]) -> Self {
        Self {
            line, date: f[0].into(), timestamp: format!("{} {}", f[0], f[1]),
            seconds: seconds_of(f[0], f[1]), hour: clock_parts(f[1]).unwrap()[0] as usize,
            ip: f[2].into(), method: f[3].into(), path: normalize_path(f[4]),
            status: f[5].parse().unwrap(), bytes: f[6].parse().unwrap(), latency: f[7].parse().unwrap(),
        }
    }
}

fn groups<'a, K: Ord>(rows: &[&'a Record], key: impl Fn(&'a Record) -> K) -> BTreeMap<K, Vec<&'a Record>> {
    let mut result: BTreeMap<K, Vec<&Record>> = BTreeMap::new();
    for &row in rows { result.entry(key(row)).or_default().push(row); }
    result
}

fn counts<'a>(values: impl Iterator<Item = &'a str>) -> BTreeMap<&'a str, usize> {
    let mut result = BTreeMap::new();
    for value in values { *result.entry(value).or_insert(0) += 1; }
    result
}

fn ranked<'a>(counts: &BTreeMap<&'a str, usize>, ip: bool) -> Vec<&'a str> {
    let mut names: Vec<&str> = counts.keys().copied().collect();
    names.sort_by(|a, b| {
        counts.get(*b).unwrap().cmp(counts.get(*a).unwrap()).then_with(|| {
            if ip { ip_number(a).cmp(&ip_number(b)) } else { a.cmp(b) }
        })
    });
    names
}

fn class_counts(rows: &[&Record]) -> [usize; 5] {
    let mut result = [0; 5];
    for row in rows { result[(row.status / 100 - 1) as usize] += 1; }
    result
}

fn buckets(values: impl Iterator<Item = i64>) -> Result<(i64, Vec<usize>), &'static str> {
    let values: Vec<i64> = values.collect();
    let first = *values.iter().min().unwrap();
    let width = values.iter().max().unwrap() - first + 1;
    ensure(width <= 60, "too many buckets")?;
    let mut counts = vec![0; width as usize];
    for value in values { counts[(value - first) as usize] += 1; }
    Ok((first, counts))
}

fn percentile(values: &[u64], rank: usize) -> u64 {
    values[(rank * values.len() + 99) / 100 - 1]
}

struct Peak<'a> {
    count: usize,
    first: &'a Record,
    last: &'a Record,
}

fn peak<'a>(rows: &[&'a Record], width: i64) -> Peak<'a> {
    let mut first = 0;
    let mut result = Peak { count: 0, first: rows[0], last: rows[0] };
    for last in 0..rows.len() {
        while rows[last].seconds - rows[first].seconds >= width { first += 1; }
        if last - first + 1 > result.count {
            result = Peak { count: last - first + 1, first: rows[first], last: rows[last] };
        }
    }
    result
}

struct Apdex {
    count: usize,
    satisfied: usize,
    tolerating: usize,
}

impl Apdex {
    fn new(rows: &[&Record], threshold: u64) -> Self {
        Self {
            count: rows.len(),
            satisfied: rows.iter().filter(|r| r.status < 500 && r.latency <= threshold).count(),
            tolerating: rows.iter().filter(|r| r.status < 500 && r.latency > threshold && r.latency <= 4 * threshold).count(),
        }
    }
    fn points(&self) -> u64 { (2 * self.satisfied + self.tolerating) as u64 }
    fn total(&self) -> u64 { (2 * self.count) as u64 }
    fn text(&self) -> String { decimal(self.points(), self.total(), 3) }
    fn rating(&self) -> &'static str {
        for (limit, rating) in [(94, "excellent"), (85, "good"), (70, "fair"), (50, "poor")] {
            if self.points() * 100 >= self.total() * limit { return rating; }
        }
        "unacceptable"
    }
}

struct TimeRange {
    start: i64,
    end: i64,
    start_text: String,
    end_text: String,
}

struct Analyzer {
    line_count: usize,
    records: Vec<Record>,
    malformed: Vec<(usize, &'static str)>,
    conditions: BTreeMap<String, String>,
    range: Option<TimeRange>,
}

impl Analyzer {
    fn new(lines: &[String]) -> Self {
        let mut analyzer = Self {
            line_count: lines.len(), records: Vec::new(), malformed: Vec::new(),
            conditions: BTreeMap::new(), range: None,
        };
        for (i, line) in lines.iter().enumerate() {
            let fields: Vec<&str> = line.split_ascii_whitespace().collect();
            if let Some(reason) = malformed_reason(&fields) { analyzer.malformed.push((i + 1, reason)); }
            else { analyzer.records.push(Record::new(i + 1, &fields)); }
        }
        analyzer.records.sort_by_key(|r| (r.seconds, r.line));
        analyzer
    }

    fn selected(&self) -> Vec<&Record> {
        self.records.iter().filter(|row| {
            if let Some(range) = &self.range {
                if row.seconds < range.start || row.seconds > range.end { return false; }
            }
            for (key, value) in &self.conditions {
                let matches = match key.as_str() {
                    "METHOD" => row.method == *value,
                    "STATUS" => status_matches(value, row.status),
                    "IP" => row.ip == *value,
                    _ => row.path == *value,
                };
                if !matches { return false; }
            }
            true
        }).collect()
    }

    fn execute(&mut self, line: &str) -> Vec<String> {
        self.command(line).unwrap_or_else(|error| vec![format!("ERROR {error}")])
    }

    fn command(&mut self, line: &str) -> QueryResult {
        let fields: Vec<&str> = line.split_ascii_whitespace().collect();
        let name = fields.first().copied().unwrap_or("");
        let args = fields.get(1..).unwrap_or(&[]);
        let form = argument_kinds(name).ok_or("unknown query")?;
        let optional = matches!(name, "LATENCY" | "SESSIONS") && args.len() + 1 == form.len();
        ensure(args.len() == form.len() || optional, "wrong arguments")?;
        for (i, argument) in args.iter().enumerate() { validate_argument(form[i], argument, args)?; }
        match name {
            "RANGE" => {
                let start = seconds_of(args[0], args[1]);
                let end = seconds_of(args[2], args[3]);
                ensure(start <= end, "invalid range")?;
                let start_text = format!("{} {}", args[0], args[1]);
                let end_text = format!("{} {}", args[2], args[3]);
                self.range = Some(TimeRange { start, end, start_text: start_text.clone(), end_text: end_text.clone() });
                Ok(vec![format!("RANGE {start_text} {end_text} active {}", self.selected().len())])
            }
            "FILTER" => {
                let value = if args[0] == "PATH" { normalize_path(args[1]) } else { args[1].to_string() };
                self.conditions.insert(args[0].to_string(), value.clone());
                Ok(vec![format!("FILTER {} {value} active {}", args[0], self.selected().len())])
            }
            "UNFILTER" => {
                if args[0] == "RANGE" {
                    ensure(self.range.is_some(), "not filtered")?;
                    self.range = None;
                } else {
                    ensure(self.conditions.contains_key(args[0]), "not filtered")?;
                    self.conditions.remove(args[0]);
                }
                Ok(vec![format!("UNFILTER {} active {}", args[0], self.selected().len())])
            }
            "RESET" => {
                self.range = None;
                self.conditions.clear();
                Ok(vec![format!("RESET active {}", self.selected().len())])
            }
            _ => self.query(name, args),
        }
    }

    fn query(&self, name: &str, args: &[&str]) -> QueryResult {
        let rows = self.selected();
        let n = rows.len();
        if REQUIRE_RECORDS.contains(&name) && n == 0 { return Ok(vec![format!("{name} no records")]); }
        let mut output = Vec::new();
        match name {
            "SUMMARY" => {
                output.push(format!("SUMMARY lines {} valid {} malformed {}", self.line_count, self.records.len(), self.malformed.len()));
                output.push(format!("requests {n} bytes {} ips {} paths {}",
                    rows.iter().map(|r| r.bytes).sum::<u64>(), counts(rows.iter().map(|r| r.ip.as_str())).len(),
                    counts(rows.iter().map(|r| r.path.as_str())).len()));
                if n == 0 { output.push("span none".into()); }
                else { output.push(format!("span {} {} {}", rows[0].timestamp, rows[n - 1].timestamp, rows[n - 1].seconds - rows[0].seconds)); }
            }
            "MALFORMED" => {
                output.push(format!("MALFORMED {}", self.malformed.len()));
                for reason in REASONS {
                    let numbers: Vec<String> = self.malformed.iter().filter(|(_, why)| *why == reason).map(|(line, _)| line.to_string()).collect();
                    if !numbers.is_empty() { output.push(format!("{reason} {} {}", numbers.len(), numbers.join(" "))); }
                }
            }
            "STATUS" => {
                output.push(format!("STATUS {n}"));
                for (i, count) in class_counts(&rows).iter().enumerate() {
                    output.push(format!("{} {count} {}", CLASSES[i], percent(*count, n)));
                }
                let mut statuses = BTreeMap::new();
                for row in &rows { *statuses.entry(row.status).or_insert(0) += 1; }
                for (status, count) in statuses { output.push(format!("{status} {count} {}", percent(count, n))); }
            }
            "METHODS" => {
                output.push(format!("METHODS {n}"));
                let counts = counts(rows.iter().map(|r| r.method.as_str()));
                for key in ranked(&counts, false) { output.push(format!("{key} {} {}", counts[key], percent(counts[key], n))); }
            }
            "TOP" => {
                let kind = args[0];
                let counts = counts(rows.iter().map(|r| if kind == "PATHS" { r.path.as_str() } else { r.ip.as_str() }));
                let keys = ranked(&counts, kind == "IPS");
                let shown = args[1].parse::<usize>().unwrap().min(keys.len());
                output.push(format!("TOP {kind} {shown} of {}", keys.len()));
                let mut rank = 0;
                for i in 0..shown {
                    if i == 0 || counts[keys[i]] != counts[keys[i - 1]] { rank = i + 1; }
                    output.push(format!("{rank} {} {} {}", keys[i], counts[keys[i]], percent(counts[keys[i]], n)));
                }
            }
            "HOURLY" => {
                let mut counts = [0; 24];
                for row in &rows { counts[row.hour] += 1; }
                let maximum = *counts.iter().max().unwrap();
                let first = counts.iter().position(|&c| c == maximum).unwrap();
                output.push(format!("HOURLY {n} peak {first:02} {maximum}"));
                for (hour, &count) in counts.iter().enumerate() { output.push(bar_line(&format!("{hour:02}"), count, maximum)); }
            }
            "TIMELINE" => {
                let minutes = args[0].parse::<i64>().unwrap();
                let width = minutes * 60;
                let (first, counts) = buckets(rows.iter().map(|r| r.seconds / width))?;
                output.push(format!("TIMELINE {minutes} {}", counts.len()));
                let maximum = *counts.iter().max().unwrap();
                for (i, &count) in counts.iter().enumerate() {
                    output.push(bar_line(&interval_label((first + i as i64) * width), count, maximum));
                }
            }
            "BANDWIDTH" => {
                let days = groups(&rows, |r| r.date.as_str());
                let total: u64 = rows.iter().map(|r| r.bytes).sum();
                output.push(format!("BANDWIDTH {} {total} {}", days.len(), bytes_text(total)));
                for (date, group) in days {
                    let bytes: u64 = group.iter().map(|r| r.bytes).sum();
                    output.push(format!("{date} {} {bytes} {}", group.len(), bytes_text(bytes)));
                }
            }
            "VISITORS" => {
                let mut first = BTreeMap::new();
                for row in &rows { first.entry(row.ip.as_str()).or_insert(row.date.as_str()); }
                let days = groups(&rows, |r| r.date.as_str());
                output.push(format!("VISITORS {} {}", days.len(), first.len()));
                for (date, group) in days {
                    let ips = counts(group.iter().map(|r| r.ip.as_str()));
                    let fresh = ips.keys().filter(|&&ip| first[ip] == date).count();
                    output.push(format!("{date} unique {} new {fresh} returning {}", ips.len(), ips.len() - fresh));
                }
            }
            "LATENCY" => {
                let label = args.first().map(|p| normalize_path(p)).unwrap_or_else(|| "all".into());
                let mut values: Vec<u64> = rows.iter().filter(|r| args.is_empty() || r.path == label).map(|r| r.latency).collect();
                if values.is_empty() { output.push("LATENCY no records".into()); }
                else {
                    values.sort_unstable();
                    let count = values.len();
                    let trim = count / 10;
                    let trimmed = &values[trim..count - trim];
                    output.push(format!("LATENCY {label} count {count} min {} p50 {} p90 {} p99 {} max {} mean {} trimmed {}",
                        values[0], percentile(&values, 50), percentile(&values, 90), percentile(&values, 99), values[count - 1],
                        decimal(values.iter().sum(), count as u64, 2), decimal(trimmed.iter().sum(), trimmed.len() as u64, 2)));
                }
            }
            "HISTOGRAM" => {
                let width = args[0].parse::<i64>().unwrap();
                let (first, counts) = buckets(rows.iter().map(|r| r.latency as i64 / width))?;
                output.push(format!("HISTOGRAM {width} {}", counts.len()));
                let maximum = *counts.iter().max().unwrap();
                for (i, &count) in counts.iter().enumerate() {
                    let low = (first + i as i64) * width;
                    output.push(bar_line(&format!("{low}-{}", low + width - 1), count, maximum));
                }
            }
            "APDEX" => {
                let threshold = args[0].parse().unwrap();
                let total = Apdex::new(&rows, threshold);
                output.push(format!("APDEX {threshold} {} {} satisfied {} tolerating {} frustrated {}",
                    total.text(), total.rating(), total.satisfied, total.tolerating, total.count - total.satisfied - total.tolerating));
                let mut paths: Vec<(&str, Apdex)> = groups(&rows, |r| r.path.as_str()).into_iter()
                    .map(|(path, group)| (path, Apdex::new(&group, threshold))).collect();
                paths.sort_by(|(xp, x), (yp, y)| (x.points() * y.total()).cmp(&(y.points() * x.total()))
                    .then_with(|| y.count.cmp(&x.count)).then_with(|| xp.cmp(yp)));
                for (path, score) in paths { output.push(format!("{path} {} {} {}", score.text(), score.rating(), score.count)); }
            }
            "ERRORS" => {
                let failed = rows.iter().filter(|r| r.status >= 400).count();
                output.push(format!("ERRORS {failed} of {n} {}", percent(failed, n)));
                struct Path<'a> { name: &'a str, count: usize, client: usize, server: usize }
                let mut paths: Vec<Path> = groups(&rows, |r| r.path.as_str()).into_iter().map(|(name, group)| Path {
                    name, count: group.len(), client: group.iter().filter(|r| r.status / 100 == 4).count(),
                    server: group.iter().filter(|r| r.status / 100 == 5).count(),
                }).filter(|p| p.client + p.server > 0).collect();
                paths.sort_by(|x, y| {
                    let xf = x.client + x.server;
                    let yf = y.client + y.server;
                    (yf as u64 * x.count as u64).cmp(&(xf as u64 * y.count as u64))
                        .then_with(|| yf.cmp(&xf)).then_with(|| x.name.cmp(y.name))
                });
                for p in paths { output.push(format!("{} {} {} {} {}", p.name, p.count, p.client, p.server, percent(p.client + p.server, p.count))); }
            }
            "SLOWEST" => {
                struct Endpoint<'a> { method: &'a str, path: &'a str, count: usize, total: u64, maximum: u64 }
                let mut endpoints: Vec<Endpoint> = groups(&rows, |r| (r.method.as_str(), r.path.as_str())).into_iter()
                    .map(|((method, path), group)| Endpoint {
                        method, path, count: group.len(), total: group.iter().map(|r| r.latency).sum(),
                        maximum: group.iter().map(|r| r.latency).max().unwrap(),
                    }).collect();
                endpoints.sort_by(|x, y| (y.total * x.count as u64).cmp(&(x.total * y.count as u64))
                    .then_with(|| y.maximum.cmp(&x.maximum)).then_with(|| x.path.cmp(y.path)).then_with(|| x.method.cmp(y.method)));
                let shown = args[0].parse::<usize>().unwrap().min(endpoints.len());
                output.push(format!("SLOWEST {shown} of {}", endpoints.len()));
                for (i, e) in endpoints.iter().take(shown).enumerate() {
                    output.push(format!("{} {} {} count {} avg {} max {}", i + 1, e.method, e.path, e.count, decimal(e.total, e.count as u64, 2), e.maximum));
                }
            }
            "SESSIONS" => {
                let ip = args[0];
                let minutes = args.get(1).map(|s| s.parse::<i64>().unwrap()).unwrap_or(30);
                let found: Vec<&Record> = rows.iter().copied().filter(|r| r.ip == ip).collect();
                if found.is_empty() { output.push("SESSIONS no records".into()); }
                else {
                    let mut sessions = vec![vec![found[0]]];
                    for i in 1..found.len() {
                        if found[i].seconds - found[i - 1].seconds <= minutes * 60 { sessions.last_mut().unwrap().push(found[i]); }
                        else { sessions.push(vec![found[i]]); }
                    }
                    let duration: u64 = sessions.iter().map(|s| (s.last().unwrap().seconds - s[0].seconds) as u64).sum();
                    output.push(format!("SESSIONS {ip} timeout {minutes} count {} requests {} avg_duration {} avg_requests {}",
                        sessions.len(), found.len(), decimal(duration, sessions.len() as u64, 1), decimal(found.len() as u64, sessions.len() as u64, 1)));
                    for (i, session) in sessions.iter().enumerate() {
                        let last = session.last().unwrap();
                        output.push(format!("{} {} {} {} {} {}", i + 1, session[0].timestamp, last.timestamp, last.seconds - session[0].seconds,
                            session.len(), counts(session.iter().map(|r| r.path.as_str())).len()));
                    }
                }
            }
            "BURST" => {
                let width = args[0].parse().unwrap();
                let threshold = args[1].parse::<usize>().unwrap();
                let failed: Vec<&Record> = rows.iter().copied().filter(|r| r.status >= 400).collect();
                let mut peaks: Vec<(&str, Peak)> = groups(&failed, |r| r.ip.as_str()).into_iter().map(|(ip, group)| (ip, peak(&group, width)))
                    .filter(|(_, p)| p.count >= threshold).collect();
                peaks.sort_by(|(xi, x), (yi, y)| y.count.cmp(&x.count).then_with(|| ip_number(xi).cmp(&ip_number(yi))));
                output.push(format!("BURST {width} {threshold} {}", peaks.len()));
                for (ip, p) in peaks { output.push(format!("{ip} {} {} {}", p.count, p.first.timestamp, p.last.timestamp)); }
            }
            "PEAK" => {
                let width = args[0].parse().unwrap();
                let p = peak(&rows, width);
                output.push(format!("PEAK {width} {} {} {}", p.count, p.first.timestamp, p.last.timestamp));
            }
            "GAPS" => {
                let width = args[0].parse::<i64>().unwrap();
                let gaps: Vec<_> = rows.windows(2).filter(|p| p[1].seconds - p[0].seconds >= width).collect();
                output.push(format!("GAPS {width} {}", gaps.len()));
                for gap in gaps { output.push(format!("{} {} {}", gap[0].timestamp, gap[1].timestamp, gap[1].seconds - gap[0].seconds)); }
            }
            "IP" => {
                let ip = args[0];
                let found: Vec<&Record> = rows.iter().copied().filter(|r| r.ip == ip).collect();
                if found.is_empty() { output.push("IP no records".into()); }
                else {
                    let paths = counts(found.iter().map(|r| r.path.as_str()));
                    output.push(format!("IP {ip} requests {} bytes {} errors {} paths {}", found.len(), found.iter().map(|r| r.bytes).sum::<u64>(),
                        found.iter().filter(|r| r.status >= 400).count(), paths.len()));
                    output.push(format!("first {} last {}", found[0].timestamp, found.last().unwrap().timestamp));
                    let methods = counts(found.iter().map(|r| r.method.as_str()));
                    let method_parts: Vec<String> = ranked(&methods, false).iter().map(|m| format!("{m} {}", methods[*m])).collect();
                    output.push(format!("methods {}", method_parts.join(" ")));
                    let category_parts: Vec<String> = class_counts(&found).iter().enumerate().map(|(i, count)| format!("{} {count}", CLASSES[i])).collect();
                    output.push(format!("classes {}", category_parts.join(" ")));
                    for path in ranked(&paths, false).into_iter().take(3) { output.push(format!("path {path} {}", paths[path])); }
                }
            }
            "STATE" => {
                let range = self.range.as_ref().map(|r| format!("{} {}", r.start_text, r.end_text)).unwrap_or_else(|| "-".into());
                let conditions: Vec<String> = KEYS.iter().map(|key| format!("{} {}", key.to_ascii_lowercase(),
                    self.conditions.get(*key).map(String::as_str).unwrap_or("-"))).collect();
                output.push(format!("STATE active {n} range {range} {}", conditions.join(" ")));
            }
            _ => unreachable!("Only validated query names are dispatched"),
        }
        Ok(output)
    }
}

fn bar_line(label: &str, count: usize, maximum: usize) -> String {
    if count == 0 { format!("{label} 0") }
    else { format!("{label} {count} {}", "#".repeat((count * 30 + maximum - 1) / maximum)) }
}

fn main() -> io::Result<()> {
    let stdin = io::stdin();
    let mut input = stdin.lock().lines();
    let mut logs = Vec::new();
    for line in input.by_ref() {
        let line = line?;
        if line == "---" { break; }
        logs.push(line);
    }
    let mut analyzer = Analyzer::new(&logs);
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    for line in input {
        let line = line?;
        if line == "END" { break; }
        for result in analyzer.execute(&line) { writeln!(output, "{result}")?; }
    }
    output.flush()
}
