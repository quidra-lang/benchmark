use std::io::{self, BufRead, Write};

type Integer = i64;
#[derive(Clone)]
struct Cue {
    index: Integer,
    start: Integer,
    end: Integer,
    text: Vec<String>,
}
struct Record { command: String, cues: Vec<Cue> }
#[derive(Default)]
struct Editor { cues: Vec<Cue>, history: Vec<Record> }
struct Arguments {
    name: String,
    raw: Vec<String>,
    values: Vec<Integer>,
    denominator: Integer,
}
struct Markup<'a> { kind: usize, text: &'a str, digit: usize }

fn unsigned(s: &str) -> Option<Integer> {
    if s.is_empty() || s.len() > 9 || !s.bytes().all(|c| c.is_ascii_digit()) { None }
    else { s.parse().ok() }
}
fn time_value(s: &str) -> Option<Integer> {
    let b = s.as_bytes();
    if b.len() != 12 || b[2] != b':' || b[5] != b':' || b[8] != b',' { return None; }
    if b.iter().enumerate().any(|(i, c)| ![2, 5, 8].contains(&i) && !c.is_ascii_digit()) { return None; }
    let h: Integer = s[..2].parse().ok()?;
    let m: Integer = s[3..5].parse().ok()?;
    let sec: Integer = s[6..8].parse().ok()?;
    let ms: Integer = s[9..].parse().ok()?;
    if m > 59 || sec > 59 { None } else { Some(h*3600000+m*60000+sec*1000+ms) }
}
fn time_text(t: Integer, kind: usize) -> String {
    if kind == 2 {
        let c = (t+5)/10;
        format!("{}:{:02}:{:02}.{:02}", c/360000, c/6000%60, c/100%60, c%100)
    } else {
        format!("{:02}:{:02}:{:02}{}{:03}", t/3600000, t/60000%60, t/1000%60, if kind == 1 { "." } else { "," }, t%1000)
    }
}
fn decimal(v: Integer) -> String { format!("{}.{:02}", v/100, v%100) }
fn floor_ratio(mut a: Integer, mut b: Integer) -> Integer {
    if b < 0 {
        a = -a;
        b = -b;
    }
    a.div_euclid(b)
}
fn half_up(mut a: Integer, mut b: Integer) -> Integer {
    if b < 0 {
        a = -a;
        b = -b;
    }
    floor_ratio(2*a+b, 2*b)
}
fn count_chars(c: &Cue) -> Integer { c.text.iter().map(|s| s.len() as Integer).sum() }
fn dialogue(c: &Cue) -> bool { c.text.iter().any(|line| line.starts_with("- ")) }
fn words(lines: &[String]) -> Vec<&str> {
    lines.iter().flat_map(|line| line.split(' ').filter(|s| !s.is_empty())).collect()
}
fn wrap(lines: &[String], width: usize) -> Vec<String> {
    let mut result: Vec<String> = Vec::new();
    for word in words(lines) {
        if result.last().is_none_or(|s| s.len()+1+word.len() > width) { result.push(word.to_owned()); }
        else {
            result.last_mut().unwrap().push(' ');
            result.last_mut().unwrap().push_str(&word);
        }
    }
    result
}
fn scan_markup(line: &str) -> Vec<Markup<'_>> {
    let tags = ["<i>", "</i>", "<b>", "</b>", "<u>", "</u>"];
    let mut result = Vec::new();
    let mut p = 0;
    let b = line.as_bytes();
    while p < line.len() {
        let (mut size, mut kind, mut digit) = (1, 0, 0);
        for tag in tags {
            if line[p..].starts_with(tag) {
                size = tag.len();
                kind = 1;
                break;
            }
        }
        if kind == 0 && line[p..].starts_with("</font>") {
            size = 7;
            kind = 2;
        }
        if kind == 0 && line[p..].starts_with("<font") && p+5 < line.len() && [b' ', b'>'].contains(&b[p+5]) {
            if let Some(end) = line[p+5..].find('>') {
                size = 6+end;
                kind = 2;
            }
        }
        if kind == 0 && p+6 <= line.len() && line[p..].starts_with("{\\an") && (b'1'..=b'9').contains(&b[p+4]) && b[p+5] == b'}' {
            size = 6;
            kind = 3;
            digit = (b[p+4]-b'0') as usize;
        }
        result.push(Markup { kind, text: &line[p..p+size], digit });
        p += size;
    }
    result
}
fn converted(lines: &[String], mode: usize) -> (Vec<String>, usize, usize) {
    let tags = ["<i>", "</i>", "<b>", "</b>", "<u>", "</u>"];
    let ass = ["{\\i1}", "{\\i0}", "{\\b1}", "{\\b0}", "{\\u1}", "{\\u0}"];
    let (mut first, mut removed) = (0, 0);
    let mut result = Vec::new();
    for line in lines {
        let mut output = String::new();
        for m in scan_markup(line) {
            if m.kind == 3 && first == 0 { first = m.digit; }
            match mode {
                0 => {
                    if m.kind == 0 { output.push_str(m.text); }
                    else { removed += 1; }
                }
                1 => {
                    if m.kind == 1 { output.push_str(m.text); }
                    if m.kind == 0 {
                        output.push_str(match m.text {
                            "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", _ => m.text,
                        });
                    }
                }
                _ => {
                    if m.kind == 1 { output.push_str(ass[tags.iter().position(|&s| s == m.text).unwrap()]); }
                    if m.kind == 0 || m.kind == 3 { output.push_str(m.text); }
                }
            }
        }
        if mode != 2 { output = output.trim_matches(' ').to_owned(); }
        if mode == 2 || !output.is_empty() { result.push(output); }
    }
    (result, first, removed)
}
fn normalize(line: &str) -> String {
    line.split(' ').filter(|s| !s.is_empty()).collect::<Vec<_>>().join(" ")
}
fn clean_hi(line: &str) -> (String, usize, usize) {
    let mut output = String::new();
    let (mut p, mut segments) = (0, 0);
    let b = line.as_bytes();
    while p < line.len() {
        let end = match b[p] {
            b'[' => line[p+1..].find(']'),
            b'(' => line[p+1..].find(')'),
            _ => None,
        };
        if let Some(end) = end {
            segments += 1;
            p += end+2;
        } else {
            output.push(b[p] as char);
            p += 1;
        }
    }
    let mut text = normalize(&output);
    let (prefix, body) = if text.starts_with("- ") { ("- ", &text[2..]) } else { ("", text.as_str()) };
    let mut labels = 0;
    if let Some(colon) = body.find(':') {
        let label = &body[..colon];
        if label.as_bytes().first().is_some_and(u8::is_ascii_uppercase)
            && label.bytes().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == b' ') {
            labels = 1;
            text = normalize(&format!("{prefix}{}", &body[colon+1..]));
        }
    }
    (text, segments, labels)
}
fn parse_arguments(line: &str, count: usize) -> Result<Arguments, String> {
    let names = ["LIST", "VALIDATE", "SEARCH", "AT", "GAPS", "STATS", "PRINT", "TOVTT", "TOASS", "FRAMES", "SHIFT", "SHIFTFROM", "SCALE", "SYNC", "SNAP", "FIXOVERLAP", "EXTEND", "TIME", "SORT", "RENUMBER", "MERGE", "SPLIT", "INSERT", "DELETE", "TEXT", "BALANCE", "STRIP", "CLEANHI", "REPLACE", "UNDO"];
    let schemas = ["", "", "S", "T", "U", "", "", "", "", "F", "I", "PI", "UU", "PTPT", "F", "U", "U", "PTT", "", "", "U", "U", "PTTX", "P", "PX", "", "", "", "R", ""];
    let (name, rest) = line.split_once(' ').map_or((line, None), |(a, b)| (a, Some(b)));
    let position = names.iter().position(|&s| s == name).ok_or("unknown command")?;
    let mut schema = schemas[position];
    let raw: Vec<String> = match rest {
        None => Vec::new(),
        Some(s) if schema.bytes().any(|c| b"SXR".contains(&c)) => s.splitn(schema.len(), ' ').map(str::to_owned).collect(),
        Some(s) => s.split(' ').map(str::to_owned).collect(),
    };
    if name == "DELETE" && raw.len() == 2 { schema = "PP"; }
    if raw.len() != schema.len() { return Err("bad arguments".to_owned()); }
    let mut a = Arguments { name: name.to_owned(), values: vec![0; raw.len()], raw, denominator: 1 };
    for (i, kind) in schema.bytes().enumerate() {
        let s = a.raw[i].as_str();
        let value = match kind {
            b'P' => unsigned(s).filter(|&v| v > 0),
            b'U' => unsigned(s),
            b'I' => if let Some(rest) = s.strip_prefix('-') { unsigned(rest).map(|v| -v) } else { unsigned(s) },
            b'T' => time_value(s),
            b'F' => {
                let parts: Vec<&str> = s.split('/').collect();
                if parts.len() > 2 { None } else {
                    a.denominator = if parts.len() == 2 { unsigned(parts[1]).unwrap_or(0) } else { 1 };
                    unsigned(parts[0]).filter(|&v| (1..=100000).contains(&v) && (1..=100000).contains(&a.denominator))
                }
            }
            b'X' => if s.split('|').all(|part| !part.is_empty()) { Some(0) } else { None },
            b'R' => s.split_once('|').filter(|(old, new)| !old.is_empty() && !new.is_empty() && !new.contains('|')).map(|_| 0),
            _ => if !s.is_empty() { Some(0) } else { None },
        };
        a.values[i] = value.ok_or("bad arguments")?;
    }
    let v = &a.values;
    if name == "SCALE" && (!(1..=100000).contains(&v[0]) || !(1..=100000).contains(&v[1])) { return Err("bad arguments".to_owned()); }
    if ["GAPS", "FIXOVERLAP", "MERGE", "EXTEND"].contains(&name) {
        let minimum = if name == "EXTEND" { 1 } else { 0 };
        if !(minimum..=60000).contains(&v[0]) { return Err("bad arguments".to_owned()); }
    }
    if name == "SPLIT" && !(10..=80).contains(&v[0]) { return Err("bad arguments".to_owned()); }
    if name == "DELETE" && v.len() == 2 && v[1] < v[0] { return Err("bad arguments".to_owned()); }
    let limit = count as Integer + Integer::from(name == "INSERT");
    for (i, kind) in schema.bytes().enumerate() {
        if kind == b'P' && v[i] > limit { return Err(format!("no cue {}", v[i])); }
    }
    Ok(a)
}
fn cue_line(position: usize, c: &Cue) -> String {
    format!("{position} {} {} {} {}", c.index, time_text(c.start, 0), time_text(c.end, 0), c.text.join("|"))
}
impl Editor {
    fn execute(&mut self, line: &str) -> Result<Vec<String>, String> {
        let a = parse_arguments(line, self.cues.len())?;
        let name = a.name.as_str();
        let v = &a.values;
        let n = self.cues.len();
        if name == "UNDO" {
            let previous = self.history.pop().ok_or("nothing to undo")?;
            self.cues = previous.cues;
            return Ok(vec![format!("UNDO command={}", previous.command)]);
        }
        if name == "SYNC" && self.cues[v[0] as usize-1].start == self.cues[v[2] as usize-1].start { return Err("sync points coincide".to_owned()); }
        let modifying = ["SHIFT", "SHIFTFROM", "SCALE", "SYNC", "SNAP", "FIXOVERLAP", "EXTEND", "TIME", "SORT", "RENUMBER", "MERGE", "SPLIT", "INSERT", "DELETE", "TEXT", "BALANCE", "STRIP", "CLEANHI", "REPLACE"];
        if modifying.contains(&name) { self.history.push(Record { command: name.to_owned(), cues: self.cues.clone() }); }
        let mut out = Vec::new();
        match name {
            "LIST" | "AT" => {
                let mut matches = 0;
                for (i, c) in self.cues.iter().enumerate() {
                    if name == "LIST" || c.start <= v[0] && v[0] < c.end {
                        out.push(cue_line(i+1, c));
                        matches += 1;
                    }
                }
                if name == "AT" { out.push(format!("AT active={matches}")); }
            }
            "VALIDATE" => {
                for (i, c) in self.cues.iter().enumerate() {
                    let prefix = format!("cue {}: ", i+1);
                    let d = c.end-c.start;
                    if c.index != (i+1) as Integer { out.push(format!("{prefix}index {} (expected {})", c.index, i+1)); }
                    if d <= 0 { out.push(format!("{prefix}end not after start")); }
                    if i > 0 && c.start < self.cues[i-1].end { out.push(format!("{prefix}overlaps previous by {} ms", self.cues[i-1].end-c.start)); }
                    if (1..700).contains(&d) { out.push(format!("{prefix}too short ({d} ms)")); }
                    if d > 7000 { out.push(format!("{prefix}too long ({d} ms)")); }
                    for (j, text) in c.text.iter().enumerate() {
                        if text.len() > 42 { out.push(format!("{prefix}line {} too long ({} chars)", j+1, text.len())); }
                    }
                    if c.text.len() >= 3 { out.push(format!("{prefix}too many lines ({})", c.text.len())); }
                    let chars = count_chars(c);
                    if d >= 1 && chars*1000 > 21*d { out.push(format!("{prefix}too fast ({} cps)", decimal(chars*100000/d))); }
                }
                out.push(format!("VALIDATE problems={}", out.len()));
            }
            "SEARCH" => {
                for (i, c) in self.cues.iter().enumerate() {
                    if let Some(line) = c.text.iter().find(|s| s.contains(a.raw[0].as_str())) {
                        out.push(format!("{} {} {line}", i+1, time_text(c.start, 0)));
                    }
                }
                out.push(format!("SEARCH found={}", out.len()));
            }
            "GAPS" => {
                for i in 0..n.saturating_sub(1) {
                    let gap = self.cues[i+1].start-self.cues[i].end;
                    if gap < v[0] { out.push(format!("{} {} {gap}", i+1, i+2)); }
                }
                out.push(format!("GAPS count={}", out.len()));
            }
            "STATS" => {
                out.push(format!("STATS cues={n}"));
                if n == 0 { return Ok(out); }
                let (mut total, mut chars, mut longest) = (0, 0, 0);
                let mut longest_position = 1;
                for (i, c) in self.cues.iter().enumerate() {
                    let d = (c.end-c.start).max(0);
                    total += d;
                    if d > 0 { chars += count_chars(c); }
                    if d > longest {
                        longest = d;
                        longest_position = i+1;
                    }
                }
                out.push(format!("duration total={} mean={}", time_text(total, 0), time_text(total/n as Integer, 0)));
                out.push(format!("speed {}", if total > 0 { decimal(chars*100000/total) } else { "-".to_owned() }));
                out.push(format!("longest cue={longest_position} duration={}", time_text(longest, 0)));
                if n == 1 { out.push("gap none".to_owned()); }
                else {
                    let (mut position, mut gap) = (1, self.cues[1].start-self.cues[0].end);
                    for i in 1..n-1 {
                        let candidate = self.cues[i+1].start-self.cues[i].end;
                        if candidate > gap {
                            position = i+1;
                            gap = candidate;
                        }
                    }
                    out.push(format!("gap cue={position} ms={gap}"));
                }
            }
            "PRINT" | "TOVTT" => {
                if name == "TOVTT" { out.extend(["WEBVTT".to_owned(), String::new()]); }
                for c in &self.cues {
                    let kind = usize::from(name == "TOVTT");
                    let (lines, code, _) = if kind == 1 { converted(&c.text, 1) } else { (c.text.clone(), 0, 0) };
                    if lines.is_empty() { continue; }
                    let mut setting = if code >= 7 { " line:0" } else if code >= 4 { " line:50%" } else { "" }.to_owned();
                    if code > 0 && code%3 == 1 { setting.push_str(" align:start"); }
                    if code > 0 && code%3 == 0 { setting.push_str(" align:end"); }
                    out.push(c.index.to_string());
                    out.push(format!("{} --> {}{setting}", time_text(c.start, kind), time_text(c.end, kind)));
                    out.extend(lines);
                    out.push(String::new());
                }
            }
            "TOASS" => {
                out.extend(["[Events]".to_owned(), "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text".to_owned()]);
                for c in &self.cues {
                    let (lines, _, _) = converted(&c.text, 2);
                    out.push(format!("Dialogue: 0,{},{},Default,,0,0,0,,{}", time_text(c.start, 2), time_text(c.end, 2), lines.join("\\N")));
                }
            }
            "FRAMES" => {
                for (i, c) in self.cues.iter().enumerate() {
                    out.push(format!("{} {} {}", i+1, c.start*v[0]/(1000*a.denominator), c.end*v[0]/(1000*a.denominator)));
                }
            }
            "SHIFT" | "SHIFTFROM" | "SYNC" | "SCALE" | "SNAP" => {
                let start = if name == "SHIFTFROM" { v[0] as usize-1 } else { 0 };
                let shift = if name == "SHIFT" { v[0] } else if name == "SHIFTFROM" { v[1] } else { 0 };
                let (s1, s2) = if name == "SYNC" { (self.cues[v[0] as usize-1].start, self.cues[v[2] as usize-1].start) } else { (0, 0) };
                let (mut clamped, mut changed) = (0, 0);
                for c in &mut self.cues[start..] {
                    let mut cue_clamped = false;
                    for t in [&mut c.start, &mut c.end] {
                        let old = *t;
                        let mut value = match name {
                            "SHIFT" | "SHIFTFROM" => old+shift,
                            "SCALE" => half_up(old*v[0], v[1]),
                            "SYNC" => half_up(v[1]*(s2-s1)+(old-s1)*(v[3]-v[1]), s2-s1),
                            _ => {
                                let frame = half_up(old*v[0], 1000*a.denominator);
                                half_up(frame*1000*a.denominator, v[0])
                            }
                        };
                        if value < 0 {
                            value = 0;
                            cue_clamped = true;
                        }
                        if old != value { changed += 1; }
                        *t = value;
                    }
                    if cue_clamped { clamped += 1; }
                }
                out.push(match name {
                    "SNAP" => format!("SNAP changed={changed}"),
                    "SCALE" => format!("SCALE cues={n}"),
                    _ => format!("{name} cues={} clamped={clamped}", n-start),
                });
            }
            "FIXOVERLAP" => {
                let (mut fixed, mut failed) = (0, 0);
                for i in 0..n.saturating_sub(1) {
                    let candidate = self.cues[i+1].start-v[0];
                    if self.cues[i].end > candidate {
                        if candidate > self.cues[i].start {
                            self.cues[i].end = candidate;
                            fixed += 1;
                        }
                        else {
                            failed += 1;
                            out.push(format!("cue {}: cannot fix", i+1));
                        }
                    }
                }
                out.push(format!("FIXOVERLAP fixed={fixed} failed={failed}"));
            }
            "EXTEND" => {
                let (mut extended, mut short) = (0, 0);
                for i in 0..n {
                    if self.cues[i].end-self.cues[i].start < v[0] {
                        let mut candidate = self.cues[i].start+v[0];
                        if i+1 < n { candidate = candidate.min(self.cues[i+1].start); }
                        if candidate > self.cues[i].end {
                            self.cues[i].end = candidate;
                            extended += 1;
                        }
                    }
                    if self.cues[i].end-self.cues[i].start < v[0] { short += 1; }
                }
                out.push(format!("EXTEND extended={extended} short={short}"));
            }
            "TIME" => {
                let c = &mut self.cues[v[0] as usize-1];
                c.start = v[1];
                c.end = v[2];
                out.push(format!("TIME cue={}", v[0]));
            }
            "SORT" => {
                let mut sorted: Vec<_> = std::mem::take(&mut self.cues).into_iter().enumerate().collect();
                sorted.sort_by_key(|(_, c)| (c.start, c.end));
                let moved = sorted.iter().enumerate().filter(|(i, (original, _))| i != original).count();
                self.cues = sorted.into_iter().map(|(_, c)| c).collect();
                out.push(format!("SORT moved={moved}"));
            }
            "RENUMBER" => {
                let mut changed = 0;
                for (i, c) in self.cues.iter_mut().enumerate() {
                    if c.index != (i+1) as Integer { changed += 1; }
                    c.index = (i+1) as Integer;
                }
                out.push(format!("RENUMBER changed={changed}"));
            }
            "MERGE" => {
                let mut result: Vec<Cue> = Vec::new();
                let mut merged = 0;
                for c in std::mem::take(&mut self.cues) {
                    if let Some(previous) = result.last_mut() {
                        if c.start-previous.end < v[0] && !dialogue(previous) && !dialogue(&c) {
                            let mut lines = previous.text.clone();
                            lines.extend(c.text.iter().cloned());
                            let wrapped = wrap(&lines, 42);
                            if wrapped.len() <= 2 {
                                previous.end = previous.end.max(c.end);
                                previous.text = wrapped;
                                merged += 1;
                                continue;
                            }
                        }
                    }
                    result.push(c);
                }
                self.cues = result;
                out.push(format!("MERGE merged={merged} cues={}", self.cues.len()));
            }
            "SPLIT" => {
                let mut result = Vec::new();
                let mut split = 0;
                for mut c in std::mem::take(&mut self.cues) {
                    let d = c.end-c.start;
                    if d < 1 || dialogue(&c) {
                        result.push(c);
                        continue;
                    }
                    let wrapped = wrap(&c.text, v[0] as usize);
                    if wrapped.len() <= 2 {
                        c.text = wrapped;
                        result.push(c);
                        continue;
                    }
                    split += 1;
                    let mut parts: Vec<Cue> = wrapped.chunks(2).map(|lines| Cue { index: c.index, start: 0, end: 0, text: lines.to_vec() }).collect();
                    let total: Integer = parts.iter().map(count_chars).sum();
                    let mut lengths: Vec<Integer> = parts.iter().map(|p| d*count_chars(p)/total).collect();
                    let remainders: Vec<Integer> = parts.iter().map(|p| d*count_chars(p)%total).collect();
                    let remaining = d-lengths.iter().sum::<Integer>();
                    let mut order: Vec<usize> = (0..parts.len()).collect();
                    order.sort_by(|&i, &j| remainders[j].cmp(&remainders[i]));
                    for &i in &order[..remaining as usize] { lengths[i] += 1; }
                    let mut start = c.start;
                    for (i, part) in parts.iter_mut().enumerate() {
                        part.start = start;
                        part.end = start+lengths[i];
                        start += lengths[i];
                    }
                    result.extend(parts);
                }
                self.cues = result;
                out.push(format!("SPLIT split={split} cues={}", self.cues.len()));
            }
            "INSERT" => {
                self.cues.insert(v[0] as usize-1, Cue { index: v[0], start: v[1], end: v[2], text: a.raw[3].split('|').map(str::to_owned).collect() });
                out.push(format!("INSERT cue={} cues={}", v[0], self.cues.len()));
            }
            "DELETE" => {
                let p = v[0] as usize-1;
                let q = if v.len() == 2 { v[1] } else { v[0] } as usize;
                self.cues.drain(p..q);
                out.push(format!("DELETE removed={} cues={}", q-p, self.cues.len()));
            }
            "TEXT" => {
                let c = &mut self.cues[v[0] as usize-1];
                c.text = a.raw[1].split('|').map(str::to_owned).collect();
                out.push(format!("TEXT cue={} lines={}", v[0], c.text.len()));
            }
            "BALANCE" => {
                let (mut changed, mut skipped, mut dialogues) = (0, 0, 0);
                for c in &mut self.cues {
                    if dialogue(c) {
                        dialogues += 1;
                        continue;
                    }
                    let w = words(&c.text);
                    let all = w.join(" ");
                    let mut candidate = None;
                    if all.len() <= 42 { candidate = Some(vec![all]); }
                    else if all.len() <= 85 {
                        let mut best = (usize::MAX, usize::MAX);
                        for j in 1..w.len() {
                            let first = w[..j].join(" ");
                            let second = w[j..].join(" ");
                            let score = (first.len().abs_diff(second.len()), first.len());
                            if first.len() <= 42 && second.len() <= 42 && score < best {
                                best = score;
                                candidate = Some(vec![first, second]);
                            }
                        }
                    }
                    if let Some(lines) = candidate {
                        if lines != c.text { changed += 1; }
                        c.text = lines;
                    } else { skipped += 1; }
                }
                out.push(format!("BALANCE changed={changed} skipped={skipped} dialogue={dialogues}"));
            }
            "STRIP" | "CLEANHI" => {
                let (mut removed_items, mut labels, mut removed_lines, mut removed_cues) = (0, 0, 0, 0);
                let mut result = Vec::new();
                for mut c in std::mem::take(&mut self.cues) {
                    let mut lines = Vec::new();
                    if name == "STRIP" {
                        let (converted, _, tags) = converted(&c.text, 0);
                        removed_items += tags;
                        removed_lines += c.text.len()-converted.len();
                        lines = converted;
                    } else {
                        for line in &c.text {
                            let (text, segments, names) = clean_hi(line);
                            removed_items += segments;
                            labels += names;
                            if text.is_empty() || text == "-" { removed_lines += 1; }
                            else { lines.push(text); }
                        }
                    }
                    if lines.is_empty() { removed_cues += 1; }
                    else {
                        c.text = lines;
                        result.push(c);
                    }
                }
                self.cues = result;
                if name == "STRIP" { out.push(format!("STRIP tags={removed_items} removed_lines={removed_lines} removed_cues={removed_cues}")); }
                else { out.push(format!("CLEANHI segments={removed_items} labels={labels} removed_lines={removed_lines} removed_cues={removed_cues}")); }
            }
            "REPLACE" => {
                let (old, replacement) = a.raw[0].split_once('|').unwrap();
                let (mut count, mut cues) = (0, 0);
                for c in &mut self.cues {
                    let mut matches = 0;
                    for line in &mut c.text {
                        matches += line.matches(old).count();
                        *line = line.replace(old, replacement);
                    }
                    count += matches;
                    if matches > 0 { cues += 1; }
                }
                out.push(format!("REPLACE count={count} cues={cues}"));
            }
            _ => unreachable!(),
        }
        Ok(out)
    }
}
fn load_block(block: &[String], position: usize, editor: &mut Editor) -> Option<String> {
    let index = unsigned(&block[0]).filter(|_| block[0].len() <= 6);
    if index.is_none() { return Some(format!("BAD CUE {position}: index")); }
    let times = block.get(1).filter(|s| s.len() == 29 && &s[12..17] == " --> ")
        .and_then(|s| Some((time_value(&s[..12])?, time_value(&s[17..])?)));
    let Some((start, end)) = times else { return Some(format!("BAD CUE {position}: time")); };
    if block.len() < 3 { return Some(format!("BAD CUE {position}: no text")); }
    editor.cues.push(Cue { index: index.unwrap(), start, end, text: block[2..].to_vec() });
    None
}
fn main() {
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    let mut editor = Editor::default();
    let mut block = Vec::new();
    let (mut blocks, mut bad) = (0, 0);
    for line in lines.by_ref() {
        let line = line.unwrap();
        if line.is_empty() || line == "###" {
            if !block.is_empty() {
                blocks += 1;
                if let Some(message) = load_block(&block, blocks, &mut editor) {
                    writeln!(output, "{message}").unwrap();
                    bad += 1;
                }
                block.clear();
            }
            if line == "###" { break; }
        } else { block.push(line); }
    }
    writeln!(output, "LOAD cues={} bad={bad}", editor.cues.len()).unwrap();
    let count: usize = lines.next().unwrap().unwrap().parse().unwrap();
    for line in lines.take(count) {
        let line = line.unwrap();
        let result = editor.execute(&line).unwrap_or_else(|message| vec![format!("ERROR {message}")]);
        for line in result { writeln!(output, "{line}").unwrap(); }
    }
}
