use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::io::{self, BufRead};

type Result<T> = std::result::Result<T, String>;
const CHANNEL_TYPES: [&str; 7] = ["NOTE_OFF", "NOTE_ON", "POLY_PRESSURE", "CONTROL", "PROGRAM", "CHANNEL_PRESSURE", "PITCH_BEND"];
const TEXT_TYPES: [&str; 7] = ["TEXT_EVENT", "COPYRIGHT", "TRACK_NAME", "INSTRUMENT_NAME", "LYRIC", "MARKER", "CUE_POINT"];
const PITCHES: [&str; 12] = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const KEYS: [[&str; 15]; 2] = [
    ["Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"],
    ["Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#"],
];
fn meta_type(meta: i32) -> &'static str {
    match meta {
        0 => "SEQUENCE_NUMBER", 32 => "CHANNEL_PREFIX", 47 => "END_OF_TRACK", 81 => "TEMPO",
        84 => "SMPTE_OFFSET", 88 => "TIME_SIGNATURE", 89 => "KEY_SIGNATURE", 127 => "SEQUENCER_SPECIFIC", _ => "META",
    }
}
fn inside(n: i64, low: i64, high: i64) -> bool { low <= n && n <= high }
fn require(ok: bool) -> Result<()> { if ok { Ok(()) } else { Err("bad value".into()) } }
fn pitch(p: u8) -> String { format!("{}{}", PITCHES[(p % 12) as usize], p as i32 / 12 - 1) }
fn parse_pitch(name: &str) -> Option<u8> { (0..128).find(|p| pitch(*p) == name) }
fn bytes(value: i64, count: usize) -> Vec<u8> { (0..count).map(|i| ((value >> (8 * (count - 1 - i))) & 255) as u8).collect() }
fn blob_text(data: &[u8]) -> String {
    format!("{}{}", data.len(), if data.is_empty() { String::new() } else { format!(" {}", data.iter().map(|x| format!("{x:02X}")).collect::<String>()) })
}
#[derive(Clone)]
struct Event { tick: i64, status: u8, meta: i32, data: Vec<u8> }
impl Event {
    fn channel(&self) -> bool { self.status < 240 }
    fn ch(&self) -> u8 { (self.status & 15) + 1 }
    fn code(&self) -> u8 { self.status >> 4 }
    fn on(&self) -> bool { self.channel() && self.code() == 9 && self.data[1] > 0 }
    fn off(&self) -> bool { self.channel() && (self.code() == 8 || self.code() == 9 && self.data[1] == 0) }
    fn end(&self) -> bool { self.status == 255 && self.meta == 47 }
    fn number(&self) -> i64 { self.data.iter().fold(0, |a, b| a * 256 + *b as i64) }
    fn kind(&self) -> &'static str {
        if self.channel() { CHANNEL_TYPES[(self.code() - 8) as usize] }
        else if self.status == 240 { "SYSEX" }
        else if self.status == 247 { "SYSEX_ESCAPE" }
        else if inside(self.meta as i64, 1, 7) { TEXT_TYPES[(self.meta - 1) as usize] }
        else { meta_type(self.meta) }
    }
    fn fields(&self) -> String {
        let d = &self.data;
        if self.channel() {
            let value = match self.code() {
                8..=10 => format!("{} {}", pitch(d[0]), d[1]),
                11 => format!("{} {}", d[0], d[1]),
                14 => (d[0] as i32 + 128 * d[1] as i32 - 8192).to_string(),
                _ => d[0].to_string(),
            };
            return format!("{} {value}", self.ch());
        }
        if self.status != 255 { return blob_text(d); }
        if inside(self.meta as i64, 1, 7) { return format!("\"{}\"", String::from_utf8_lossy(d)); }
        match self.meta {
            0 | 81 => self.number().to_string(),
            32 => (d[0] + 1).to_string(),
            47 => String::new(),
            84 => d.iter().map(u8::to_string).collect::<Vec<_>>().join(" "),
            88 => format!("{}/{} {} {}", d[0], 1u32 << d[1], d[2], d[3]),
            89 => format!("{} {}", KEYS[d[1] as usize][(d[0] as i8 as i32 + 7) as usize], if d[1] == 0 { "major" } else { "minor" }),
            127 => blob_text(d),
            _ => format!("{:02X} {}", self.meta, blob_text(d)),
        }
    }
    fn line(&self, track: usize) -> String {
        let fields = self.fields();
        format!("{} {track} {}{}", self.tick, self.kind(), if fields.is_empty() { fields } else { format!(" {fields}") })
    }
}
fn end_event(tick: i64) -> Event { Event { tick, status: 255, meta: 47, data: vec![] } }
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct Location { track: usize, index: usize }
#[derive(Clone)]
struct Reference { event: Event, location: Location, order: usize }
#[derive(Clone)]
struct Note { on: Reference, off: Reference }
#[derive(Clone)]
struct Song { format: i32, division: i64, tracks: Vec<Vec<Event>> }
impl Song {
    fn count(&self) -> usize { self.tracks.iter().map(Vec::len).sum() }
    fn length(&self) -> i64 { self.tracks.iter().map(|t| t.last().unwrap().tick).max().unwrap() }
    fn summary(&self) -> String { format!("format {} tracks {} division {} events {}", self.format, self.tracks.len(), self.division, self.count()) }
    fn global(&self) -> Vec<Reference> {
        let mut all: Vec<Reference> = self.tracks.iter().enumerate().flat_map(|(track, events)| events.iter().enumerate().map(move |(index, event)| Reference { event: event.clone(), location: Location { track, index }, order: 0 })).collect();
        all.sort_by_key(|r| (r.event.tick, r.location));
        for (i, r) in all.iter_mut().enumerate() { r.order = i; }
        all
    }
    fn pair(&self) -> (Vec<Note>, Vec<Reference>) {
        let all = self.global();
        let mut queues: BTreeMap<(u8, u8), VecDeque<Reference>> = BTreeMap::new();
        let mut matched = BTreeSet::new();
        let mut notes = vec![];
        for reference in &all {
            let e = &reference.event;
            if !e.on() && !e.off() { continue; }
            let queue = queues.entry((e.ch(), e.data[0])).or_default();
            if e.on() { queue.push_back(reference.clone()); }
            else if let Some(on) = queue.pop_front() {
                matched.insert(on.location); matched.insert(reference.location);
                notes.push(Note { on, off: reference.clone() });
            }
        }
        notes.sort_by_key(|n| (n.on.event.tick, n.on.event.ch(), n.on.event.data[0], n.on.order));
        let unmatched = all.into_iter().filter(|r| (r.event.on() || r.event.off()) && !matched.contains(&r.location)).collect();
        (notes, unmatched)
    }
    fn position(&self, tick: i64, bars: bool) -> (String, String) {
        let (mut sum, mut last, mut tempo) = (0, 0, 500000);
        let (mut start, mut bar, mut nn, mut beat) = (0, 1, 4, self.division);
        for reference in self.global().iter().filter(|r| r.event.tick <= tick) {
            let e = &reference.event;
            if e.status != 255 { continue; }
            if e.meta == 81 { sum += (e.tick - last) * tempo; last = e.tick; tempo = e.number(); }
            if e.meta == 88 && bars {
                let size = nn * beat;
                bar += (e.tick - start + size - 1) / size; start = e.tick;
                nn = e.data[0] as i64; beat = self.division * 4 / (1 << e.data[1]);
            }
        }
        let micro = (sum + (tick - last) * tempo) / self.division;
        let time = format!("{}.{:03}", micro / 1000, micro % 1000);
        let x = tick - start;
        let bar = if bars { format!("{}:{}:{}", bar + x / (nn * beat), x % (nn * beat) / beat + 1, x % beat) } else { String::new() };
        (time, bar)
    }
}
struct Reader<'a> { data: &'a [u8], p: usize, end: usize, start: usize }
impl Reader<'_> {
    fn big(&self, p: usize, n: usize) -> i64 { self.data[p..p + n].iter().fold(0, |a, b| a * 256 + *b as i64) }
    fn chunk(&self, p: usize, id: &[u8]) -> Result<usize> {
        if self.data.len() - p < 8 { return Err(format!("byte {p}: truncated chunk")); }
        if &self.data[p..p + 4] != id { return Err(format!("byte {p}: bad chunk id")); }
        let end = p as i64 + 8 + self.big(p + 4, 4);
        if end > self.data.len() as i64 { return Err(format!("byte {p}: truncated chunk")); }
        Ok(end as usize)
    }
    fn byte(&mut self) -> Result<u8> {
        if self.p >= self.end { return Err(format!("byte {}: truncated event", self.start)); }
        let b = self.data[self.p]; self.p += 1; Ok(b)
    }
    fn variable(&mut self) -> Result<i64> {
        let at = self.p;
        let mut result = 0;
        for _ in 0..4 {
            let b = self.byte()?; result = result * 128 + (b & 127) as i64;
            if b < 128 { return Ok(result); }
        }
        Err(format!("byte {at}: variable-length value too long"))
    }
}
fn validate_meta(e: &Event, at: usize) -> Result<()> {
    let length = match e.meta { 0 => Some(2), 32 => Some(1), 47 => Some(0), 81 => Some(3), 84 => Some(5), 88 => Some(4), 89 => Some(2), _ => None };
    if length.is_some_and(|n| n != e.data.len()) { return Err(format!("byte {at}: bad meta length")); }
    let d = &e.data;
    let bad = match e.meta {
        81 => e.number() == 0, 32 => d[0] > 15, 88 => d[0] == 0 || d[1] > 6,
        89 => !inside(d[0] as i8 as i64, -7, 7) || d[1] > 1, _ => false,
    };
    if bad { Err(format!("byte {at}: bad meta data")) } else { Ok(()) }
}
fn parse_hex(data: &[u8]) -> Result<Song> {
    let mut r = Reader { data, p: 0, end: 0, start: 0 };
    if r.chunk(0, b"MThd")? != 14 { return Err("byte 4: bad header length".into()); }
    let (format, tracks, division) = (r.big(8, 2), r.big(10, 2), r.big(12, 2));
    if format > 2 { return Err("byte 8: bad format".into()); }
    if tracks == 0 || format == 0 && tracks != 1 { return Err("byte 10: bad track count".into()); }
    if division & 32768 != 0 { return Err("byte 12: smpte timing not supported".into()); }
    if division == 0 { return Err("byte 12: bad division".into()); }
    let mut song = Song { format: format as i32, division, tracks: vec![] };
    r.p = 14;
    for _ in 0..tracks {
        if r.p == data.len() { return Err(format!("byte {}: missing track", r.p)); }
        r.end = r.chunk(r.p, b"MTrk")?; r.p += 8;
        let mut events: Vec<Event> = vec![];
        let (mut tick, mut running) = (0, 0);
        while r.p < r.end {
            if events.last().is_some_and(Event::end) { return Err(format!("byte {}: event after end of track", r.p)); }
            r.start = r.p; tick += r.variable()?;
            if r.p >= r.end { return Err(format!("byte {}: truncated event", r.start)); }
            let at = r.p;
            let mut status = data[r.p];
            if status < 128 {
                if running == 0 { return Err(format!("byte {}: data byte without running status", r.p)); }
                status = running;
            } else { r.p += 1; }
            let mut e = Event { tick, status, meta: -1, data: vec![] };
            if status < 240 {
                running = status;
                let count = if status >> 4 == 12 || status >> 4 == 13 { 1 } else { 2 };
                for _ in 0..count {
                    let position = r.p;
                    let b = r.byte()?;
                    if b >= 128 { return Err(format!("byte {position}: bad data byte")); }
                    e.data.push(b);
                }
            } else if matches!(status, 240 | 247 | 255) {
                running = 0;
                if status == 255 { e.meta = r.byte()? as i32; }
                let count = r.variable()? as usize;
                if count > r.end - r.p { return Err(format!("byte {}: truncated event", r.start)); }
                e.data = data[r.p..r.p + count].to_vec(); r.p += count;
                if status == 255 { validate_meta(&e, at)?; }
            } else { return Err(format!("byte {at}: unknown status byte")); }
            events.push(e);
        }
        if !events.last().is_some_and(Event::end) { return Err(format!("byte {}: missing end of track", r.end)); }
        song.tracks.push(events);
    }
    if r.p != data.len() { return Err(format!("byte {}: extra data", r.p)); }
    Ok(song)
}
fn num(a: &[&str], i: usize, low: i64, high: i64) -> Result<i64> {
    a.get(i).and_then(|s| s.parse::<i64>().ok()).filter(|n| inside(*n, low, high)).ok_or_else(|| "bad value".into())
}
fn hex_text(s: &str) -> bool { s.bytes().all(|c| c.is_ascii_digit() || (b'A'..=b'F').contains(&c)) }
fn blob(a: &[&str], index: usize) -> Result<Vec<u8>> {
    let count = num(a, index, 0, 1000000)? as usize;
    require(a.len() == index + if count == 0 { 1 } else { 2 })?;
    if count == 0 { return Ok(vec![]); }
    let text = a[index + 1];
    require(text.len() == count * 2 && hex_text(text))?;
    Ok((0..text.len()).step_by(2).map(|i| u8::from_str_radix(&text[i..i + 2], 16).unwrap()).collect())
}
fn text_event(tick: i64, kind: &str, fields: &str) -> Result<Event> {
    let code = CHANNEL_TYPES.iter().position(|s| *s == kind).map(|i| i as u8 + 8);
    let text = TEXT_TYPES.iter().position(|s| *s == kind);
    let known_meta = (0..256).find(|m| meta_type(*m) != "META" && meta_type(*m) == kind);
    if code.is_none() && text.is_none() && known_meta.is_none() && !matches!(kind, "META" | "SYSEX" | "SYSEX_ESCAPE") { return Err("unknown event type".into()); }
    let a: Vec<&str> = if fields.is_empty() { vec![] } else { fields.split(' ').collect() };
    if let Some(code) = code {
        require(a.len() == if matches!(code, 12 | 13 | 14) { 2 } else { 3 })?;
        let ch = num(&a, 0, 1, 16)? as u8;
        let data = match code {
            8..=10 => vec![parse_pitch(a[1]).ok_or("bad value")?, num(&a, 2, 0, 127)? as u8],
            11 => vec![num(&a, 1, 0, 127)? as u8, num(&a, 2, 0, 127)? as u8],
            14 => { let value = num(&a, 1, -8192, 8191)? + 8192; vec![(value & 127) as u8, (value >> 7) as u8] },
            _ => vec![num(&a, 1, 0, 127)? as u8],
        };
        return Ok(Event { tick, status: code * 16 + ch - 1, meta: -1, data });
    }
    if matches!(kind, "SYSEX" | "SYSEX_ESCAPE") { return Ok(Event { tick, status: if kind == "SYSEX" { 240 } else { 247 }, meta: -1, data: blob(&a, 0)? }); }
    if let Some(text) = text {
        require(fields.len() >= 2 && fields.starts_with('"') && fields.ends_with('"') && !fields[1..fields.len() - 1].contains('"'))?;
        return Ok(Event { tick, status: 255, meta: text as i32 + 1, data: fields.as_bytes()[1..fields.len() - 1].to_vec() });
    }
    if kind == "META" {
        require(a.len() >= 2 && a[0].len() == 2 && hex_text(a[0]))?;
        let meta = i32::from_str_radix(a[0], 16).unwrap();
        require(meta_type(meta) == "META" && !inside(meta as i64, 1, 7))?;
        return Ok(Event { tick, status: 255, meta, data: blob(&a, 1)? });
    }
    let meta = known_meta.unwrap();
    if meta == 127 { return Ok(Event { tick, status: 255, meta, data: blob(&a, 0)? }); }
    let count = match meta { 47 => 0, 84 => 5, 88 => 3, 89 => 2, _ => 1 };
    require(a.len() == count)?;
    let data = match meta {
        0 => bytes(num(&a, 0, 0, 65535)?, 2),
        32 => vec![(num(&a, 0, 1, 16)? - 1) as u8],
        47 => vec![],
        81 => bytes(num(&a, 0, 1, 16777215)?, 3),
        84 => (0..5).map(|i| num(&a, i, 0, 255).map(|x| x as u8)).collect::<Result<Vec<_>>>()?,
        88 => {
            let signature: Vec<&str> = a[0].split('/').collect();
            require(signature.len() == 2)?;
            let nn = num(&signature, 0, 1, 255)?;
            let dd = num(&signature, 1, 1, 64)?;
            let exponent = (0..=6).find(|e| (1 << e) == dd).ok_or("bad value")?;
            vec![nn as u8, exponent, num(&a, 1, 0, 255)? as u8, num(&a, 2, 0, 255)? as u8]
        }
        89 => {
            require(matches!(a[1], "major" | "minor"))?;
            let minor = usize::from(a[1] == "minor");
            let key = KEYS[minor].iter().position(|s| *s == a[0]).ok_or("bad value")?;
            vec![(key as i32 - 7) as u8, minor as u8]
        }
        _ => unreachable!(),
    };
    Ok(Event { tick, status: 255, meta, data })
}
fn parse_text(lines: &[String]) -> Result<Song> {
    let h: Vec<&str> = lines[0].split(' ').collect();
    if h.len() != 4 || h[0] != "HEADER" { return Err("line 1: bad header".into()); }
    let header = || -> Result<(i64, i64, i64)> {
        let f = num(&h, 1, 0, 2)?; let t = num(&h, 2, 1, 65535)?; let d = num(&h, 3, 1, 32767)?;
        require(f != 0 || t == 1)?; Ok((f, t, d))
    };
    let (format, tracks, division) = header().map_err(|_| "line 1: bad header".to_string())?;
    let mut song = Song { format: format as i32, division, tracks: vec![vec![]] };
    let mut current = 0;
    for (i, line) in lines.iter().enumerate().skip(1) {
        let a: Vec<&str> = line.splitn(4, ' ').collect();
        let tick: i64 = a[0].parse().unwrap(); let track: usize = a[1].parse().unwrap();
        let e = text_event(tick, a[2], a.get(3).copied().unwrap_or("")).map_err(|reason| format!("line {}: {reason}", i + 1))?;
        let bad = |reason: &str| format!("line {}: {reason}", i + 1);
        if track >= tracks as usize { return Err(bad("bad track")); }
        let ended = song.tracks[current].last().is_some_and(Event::end);
        if track < current { return Err(bad("out of order")); }
        if track > current && (!ended || track > current + 1) { return Err(bad("missing end of track")); }
        if track == current && ended { return Err(bad("event after end of track")); }
        if track == current + 1 { current += 1; song.tracks.push(vec![]); }
        if song.tracks[current].last().is_some_and(|previous| tick < previous.tick) { return Err(bad("out of order")); }
        song.tracks[current].push(e);
    }
    if current + 1 < tracks as usize || !song.tracks[current].last().is_some_and(Event::end) { return Err(format!("line {}: missing end of track", lines.len() + 1)); }
    Ok(song)
}
fn variable(mut value: i64) -> Vec<u8> {
    let mut result = vec![(value & 127) as u8]; value >>= 7;
    while value > 0 { result.insert(0, ((value & 127) | 128) as u8); value >>= 7; }
    result
}
fn encode(song: &Song, running: bool, zero_off: bool) {
    let mut all = b"MThd".to_vec();
    all.extend(bytes(6, 4)); all.extend(bytes(song.format as i64, 2)); all.extend(bytes(song.tracks.len() as i64, 2)); all.extend(bytes(song.division, 2));
    for track in &song.tracks {
        let mut data = vec![]; let mut previous = 0; let mut last = None;
        for e in track {
            data.extend(variable(e.tick - previous)); previous = e.tick;
            if e.channel() {
                let rewrite = zero_off && e.code() == 8;
                let status = if rewrite { 0x90 + e.ch() - 1 } else { e.status };
                if !running || last != Some(status) { data.push(status); }
                if rewrite { data.extend([e.data[0], 0]); } else { data.extend(&e.data); }
                last = Some(status);
            } else {
                last = None; data.push(e.status);
                if e.status == 255 { data.push(e.meta as u8); }
                data.extend(variable(e.data.len() as i64)); data.extend(&e.data);
            }
        }
        all.extend(b"MTrk"); all.extend(bytes(data.len() as i64, 4)); all.extend(data);
    }
    for (i, part) in all.chunks(16).enumerate() { println!("{:04X}: {}", i * 16, part.iter().map(|x| format!("{x:02X}")).collect::<Vec<_>>().join(" ")); }
    println!("{} bytes", all.len());
}
fn print_notes(song: &Song) {
    let (notes, unmatched) = song.pair();
    println!("notes {} unmatched {}", notes.len(), unmatched.len());
    for note in notes { let e = note.on.event; println!("{} {} {} {} {}", e.tick, note.off.event.tick - e.tick, e.ch(), pitch(e.data[0]), e.data[1]); }
    for r in unmatched { let e = r.event; println!("unmatched {} {} {} {} {}", if e.on() { "on" } else { "off" }, e.tick, r.location.track, e.ch(), pitch(e.data[0])); }
}
fn stats(song: &Song) {
    let (notes, unmatched) = song.pair();
    println!("{}", song.summary()); println!("notes {} unmatched {}", notes.len(), unmatched.len());
    for ch in 1..=16 {
        let pitches: Vec<u8> = notes.iter().filter(|n| n.on.event.ch() == ch).map(|n| n.on.event.data[0]).collect();
        if !pitches.is_empty() { println!("channel {ch} notes {} range {} {}", pitches.len(), pitch(*pitches.iter().min().unwrap()), pitch(*pitches.iter().max().unwrap())); }
    }
    let pitches: Vec<u8> = notes.iter().map(|n| n.on.event.data[0]).collect();
    if pitches.is_empty() { println!("range none"); } else { println!("range {} {}", pitch(*pitches.iter().min().unwrap()), pitch(*pitches.iter().max().unwrap())); }
    println!("length {} ticks {} ms", song.length(), song.position(song.length(), false).0);
    let mut changes: BTreeMap<i64, i32> = BTreeMap::new();
    for note in notes.iter().filter(|n| n.off.event.tick > n.on.event.tick) {
        *changes.entry(note.on.event.tick).or_default() += 1; *changes.entry(note.off.event.tick).or_default() -= 1;
    }
    let (mut current, mut maximum, mut at) = (0, 0, 0);
    for (tick, change) in changes { current += change; if current > maximum { maximum = current; at = tick; } }
    if maximum == 0 { println!("polyphony 0"); } else { println!("polyphony {maximum} at {at}"); }
}
struct Codec { songs: BTreeMap<String, Song>, running: bool, zero_off: bool }
impl Codec {
    fn execute(&mut self, a: &[&str]) -> Result<()> {
        let cmd = a[0];
        let known = ["DECODE", "ENCODE", "TIMING", "NOTES", "STATS", "ROLL", "TRANSPOSE", "QUANTIZE", "VELOCITY", "TEMPO", "FILTER", "MERGE", "SPLIT", "COPY", "LIST", "RUNNING", "NOTEOFF"];
        if !known.contains(&cmd) { return Err("unknown command".into()); }
        if cmd == "LIST" {
            if self.songs.is_empty() { println!("no songs"); }
            for (name, song) in &self.songs { println!("{name} {}", song.summary()); }
            return Ok(());
        }
        if matches!(cmd, "RUNNING" | "NOTEOFF") {
            if cmd == "RUNNING" {
                if !matches!(a[1], "ON" | "OFF") { return Err("bad argument".into()); }
                self.running = a[1] == "ON";
            } else {
                if !matches!(a[1], "ZERO" | "KEEP") { return Err("bad argument".into()); }
                self.zero_off = a[1] == "ZERO";
            }
            println!("{} {}", cmd.to_lowercase(), a[1].to_lowercase());
            return Ok(());
        }
        let mut song = self.songs.get(a[1]).ok_or_else(|| format!("no song {}", a[1]))?.clone();
        let first = a.get(2).and_then(|s| s.parse::<i64>().ok()).unwrap_or(0);
        let second = a.get(3).and_then(|s| s.parse::<i64>().ok()).unwrap_or(0);
        let third = a.get(4).and_then(|s| s.parse::<i64>().ok()).unwrap_or(0);
        let bad = match cmd {
            "TRANSPOSE" => !inside(first, -127, 127) || a.len() == 4 && !inside(second, 1, 16),
            "QUANTIZE" => !inside(first, 1, 1000000) || !inside(second, 0, 100),
            "VELOCITY" => !inside(first, 0, 1000) || !inside(second, -127, 127),
            "TEMPO" => !inside(first, 1, 1000) || !inside(second, 1, 1000),
            "FILTER" => a[2..].iter().any(|s| !inside(s.parse().unwrap(), 1, 16)),
            "ROLL" => !inside(first, 0, 10000000) || !inside(second, 1, 10000000) || !inside(third, 1, 10000000) || second <= first || (second - first + third - 1) / third > 64,
            _ => false,
        };
        if bad { return Err("bad argument".into()); }
        if matches!(cmd, "TIMING" | "STATS") && song.format == 2 { return Err("format 2 not supported".into()); }
        match cmd {
            "DECODE" => {
                println!("HEADER {} {} {}", song.format, song.tracks.len(), song.division);
                for (tr, track) in song.tracks.iter().enumerate() { for e in track { println!("{}", e.line(tr)); } }
            }
            "ENCODE" => encode(&song, self.running, self.zero_off),
            "TIMING" => {
                for r in song.global() { let e = r.event; let p = song.position(e.tick, true); println!("{} {} {} {} {}", e.tick, r.location.track, e.kind(), p.0, p.1); }
                let p = song.position(song.length(), true); println!("end {} {} {}", song.length(), p.0, p.1);
            }
            "NOTES" => print_notes(&song),
            "COPY" => { self.songs.insert(a[2].into(), song); println!("copied {} to {}", a[1], a[2]); return Ok(()); }
            "TRANSPOSE" => {
                let mut kept = 0; let mut dropped = vec![];
                for (tr, track) in song.tracks.iter_mut().enumerate() {
                    let mut result = vec![];
                    for mut e in std::mem::take(track) {
                        if e.channel() && (8..=10).contains(&e.code()) && (a.len() == 3 || e.ch() as i64 == second) {
                            let value = e.data[0] as i64 + first;
                            if !inside(value, 0, 127) { dropped.push(format!("dropped {} {tr} {} {} {}", e.tick, e.kind(), e.ch(), pitch(e.data[0]))); continue; }
                            e.data[0] = value as u8; kept += 1;
                        }
                        result.push(e);
                    }
                    *track = result;
                }
                println!("transposed {kept} dropped {}", dropped.len()); for line in dropped { println!("{line}"); }
            }
            "QUANTIZE" => {
                let (notes, unmatched) = song.pair();
                let mut shifts = BTreeMap::new(); let (mut targets, mut moved) = (0, 0);
                let mut shift = |on: &Reference, off: Option<&Reference>| {
                    let t = on.event.tick; let low = t / first * first;
                    let g = if t - low <= low + first - t { low } else { low + first };
                    let delta = (2 * (g - t) * second + 100).div_euclid(200);
                    targets += 1; if delta != 0 { moved += 1; }
                    shifts.insert(on.location, delta); if let Some(off) = off { shifts.insert(off.location, delta); }
                };
                for note in &notes { shift(&note.on, Some(&note.off)); }
                for r in unmatched.iter().filter(|r| r.event.on()) { shift(r, None); }
                for (tr, track) in song.tracks.iter_mut().enumerate() {
                    let mut eot = track.pop().unwrap();
                    for (i, e) in track.iter_mut().enumerate() { e.tick += shifts.get(&Location { track: tr, index: i }).copied().unwrap_or(0); }
                    track.sort_by_key(|e| e.tick);
                    eot.tick = eot.tick.max(track.last().map_or(0, |e| e.tick)); track.push(eot);
                }
                println!("quantized {targets} moved {moved}");
            }
            "VELOCITY" => {
                let (mut count, mut clamped) = (0, 0);
                for e in song.tracks.iter_mut().flatten().filter(|e| e.on()) {
                    let value = (e.data[1] as i64 * first + 50) / 100 + second;
                    count += 1; if !inside(value, 1, 127) { clamped += 1; }
                    e.data[1] = value.clamp(1, 127) as u8;
                }
                println!("velocity {count} clamped {clamped}");
            }
            "TEMPO" => {
                let (mut scaled, mut at_zero) = (0, false);
                let scale = |value: i64| -> Result<i64> {
                    let result = (2 * value * second + first) / (2 * first);
                    if inside(result, 1, 16777215) { Ok(result) } else { Err("tempo out of range".into()) }
                };
                for e in song.tracks.iter_mut().flatten().filter(|e| e.status == 255 && e.meta == 81) {
                    if e.tick == 0 { at_zero = true; } scaled += 1; e.data = bytes(scale(e.number())?, 3);
                }
                let inserted = if !at_zero { Some(Event { tick: 0, status: 255, meta: 81, data: bytes(scale(500000)?, 3) }) } else { None };
                if let Some(e) = &inserted { song.tracks[0].insert(0, e.clone()); }
                println!("scaled {scaled}"); if let Some(e) = inserted { println!("inserted {}", e.line(0)); }
            }
            "FILTER" => {
                let channels: BTreeSet<u8> = a[2..].iter().map(|s| s.parse().unwrap()).collect();
                let mut removed = 0;
                for track in &mut song.tracks { let count = track.len(); track.retain(|e| !e.channel() || channels.contains(&e.ch())); removed += count - track.len(); }
                println!("removed {removed}");
            }
            "MERGE" => {
                if song.format != 1 { return Err("not format 1".into()); }
                let old = song.tracks.len(); let length = song.length();
                let mut track: Vec<Event> = song.global().into_iter().filter(|r| !r.event.end()).map(|r| r.event).collect();
                track.push(end_event(length)); song.tracks = vec![track]; song.format = 0;
                println!("merged {old} tracks events {}", song.count());
            }
            "SPLIT" => {
                if song.format != 0 { return Err("not format 0".into()); }
                let length = song.length(); let original = song.tracks.remove(0);
                let channels: BTreeSet<u8> = original.iter().filter(|e| e.channel()).map(Event::ch).collect();
                let mut tracks = vec![original.iter().filter(|e| !e.channel() && !e.end()).cloned().collect::<Vec<_>>()];
                for ch in channels { tracks.push(original.iter().filter(|e| e.channel() && e.ch() == ch).cloned().collect()); }
                for track in &mut tracks { track.push(end_event(length)); }
                song.tracks = tracks; song.format = 1;
                println!("split tracks {} events {}", song.tracks.len(), song.count());
            }
            "STATS" => stats(&song),
            "ROLL" => {
                let notes = song.pair().0; let mut any = false;
                for number in (0..128u8).rev() {
                    let mut row = String::new(); let mut at = first;
                    while at < second {
                        let onset = notes.iter().any(|n| n.on.event.data[0] == number && at <= n.on.event.tick && n.on.event.tick < at + third);
                        let held = notes.iter().any(|n| n.on.event.data[0] == number && n.on.event.tick <= at && at < n.off.event.tick);
                        row.push(if onset { '#' } else if held { '=' } else { '.' }); at += third;
                    }
                    if row.bytes().any(|c| c != b'.') { any = true; println!("{:<4} {row}", pitch(number)); }
                }
                if !any { println!("empty"); }
            }
            _ => unreachable!(),
        }
        self.songs.insert(a[1].into(), song);
        Ok(())
    }
}
fn main() {
    let stdin = io::stdin(); let mut lines = stdin.lock().lines();
    let count: usize = lines.next().unwrap().unwrap().parse().unwrap();
    let mut codec = Codec { songs: BTreeMap::new(), running: true, zero_off: false };
    for _ in 0..count {
        let line = lines.next().unwrap().unwrap(); let a: Vec<&str> = line.split(' ').collect();
        let result = if matches!(a[0], "HEX" | "TEXT") {
            let count: usize = a[2].parse().unwrap();
            let data_lines: Vec<String> = (0..count).map(|_| lines.next().unwrap().unwrap()).collect();
            let parsed = if a[0] == "TEXT" { parse_text(&data_lines) }
            else {
                let data: Vec<u8> = data_lines.iter().flat_map(|s| s.split(' ').map(|b| u8::from_str_radix(b, 16).unwrap())).collect();
                parse_hex(&data)
            };
            parsed.map(|song| { println!("loaded {} {}", a[1], song.summary()); codec.songs.insert(a[1].into(), song); })
        } else { codec.execute(&a) };
        if let Err(reason) = result { println!("error: {reason}"); }
    }
}
