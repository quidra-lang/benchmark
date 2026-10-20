use std::collections::{BTreeMap, BTreeSet};
use std::fmt::{self, Display};
use std::io::{self, Read, Write};
use std::ops::Range;

type CommandResult<T> = Result<T, String>;
const WRONG_TYPE: &str = "WRONGTYPE Operation against a key holding the wrong kind of value";
const NOT_INTEGER: &str = "ERR value is not an integer or out of range";
const POSITIVE: &str = "ERR value is out of range, must be positive";

#[derive(Clone)]
enum Value {
    Text(String),
    List(Vec<String>),
    Hash(BTreeMap<String, String>),
    Set(BTreeSet<String>),
    SortedSet(BTreeMap<String, i32>),
}
impl Value {
    fn kind(&self) -> &'static str {
        match self {
            Self::Text(_) => "string", Self::List(_) => "list", Self::Hash(_) => "hash",
            Self::Set(_) => "set", Self::SortedSet(_) => "zset",
        }
    }
    fn empty(&self) -> bool {
        match self {
            Self::Text(_) => false, Self::List(v) => v.is_empty(), Self::Hash(v) => v.is_empty(),
            Self::Set(v) => v.is_empty(), Self::SortedSet(v) => v.is_empty(),
        }
    }
}
#[derive(Clone)]
struct Entry { value: Value, expiry: Option<i32> }
type Database = BTreeMap<String, Entry>;

enum Reply { Status(String), Integer(i32), Text(Option<String>), Array(Vec<Option<String>>) }
fn quote(text: &str) -> String { format!("\"{}\"", text.replace('\\', "\\\\").replace('"', "\\\"")) }
impl Display for Reply {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Status(text) => f.write_str(text),
            Self::Integer(value) => write!(f, "(integer) {value}"),
            Self::Text(value) => f.write_str(&value.as_deref().map(quote).unwrap_or_else(|| "(nil)".into())),
            Self::Array(values) => {
                if values.is_empty() { return f.write_str("(empty array)"); }
                let width = values.len().to_string().len();
                for (index, value) in values.iter().enumerate() {
                    if index > 0 { writeln!(f)?; }
                    let item = value.as_deref().map(quote).unwrap_or_else(|| "(nil)".into());
                    write!(f, "{:>width$}) {item}", index + 1)?;
                }
                Ok(())
            }
        }
    }
}
fn status(text: &str) -> Reply { Reply::Status(text.into()) }
fn array(values: impl IntoIterator<Item = String>) -> Reply { Reply::Array(values.into_iter().map(Some).collect()) }

fn split_line(line: &str) -> Option<Vec<String>> {
    let bytes = line.as_bytes();
    let mut args = Vec::new();
    let mut position = 0;
    while position < bytes.len() {
        if bytes[position] == b' ' { position += 1; continue; }
        if bytes[position] != b'"' {
            let start = position;
            while position < bytes.len() && bytes[position] != b' ' { position += 1; }
            args.push(line[start..position].to_owned());
            continue;
        }
        position += 1;
        let mut text = Vec::new();
        while position < bytes.len() && bytes[position] != b'"' {
            if bytes[position] == b'\\' {
                position += 1;
                if position == bytes.len() || !matches!(bytes[position], b'\\' | b'"') { return None; }
            }
            text.push(bytes[position]);
            position += 1;
        }
        if position == bytes.len() { return None; }
        position += 1;
        if position < bytes.len() && bytes[position] != b' ' { return None; }
        args.push(String::from_utf8(text).unwrap());
    }
    Some(args)
}
fn parse_integer(text: &str) -> Option<i32> {
    if text == "0" { return Some(0); }
    let digits = text.strip_prefix('-').unwrap_or(text).as_bytes();
    if !(1..=9).contains(&digits.len()) || !(b'1'..=b'9').contains(&digits[0]) || !digits.iter().all(u8::is_ascii_digit) {
        return None;
    }
    text.parse().ok()
}
fn integer(text: &str) -> CommandResult<i32> { parse_integer(text).ok_or_else(|| NOT_INTEGER.into()) }
fn add(old: i32, delta: i32) -> CommandResult<i32> {
    let result = old + delta;
    if !(-999_999_999..=999_999_999).contains(&result) { return Err("ERR increment or decrement would overflow".into()); }
    Ok(result)
}
fn range(length: usize, mut start: i32, mut stop: i32) -> Range<usize> {
    if start < 0 { start += length as i32; }
    if stop < 0 { stop += length as i32; }
    start = start.max(0);
    stop = stop.min(length as i32 - 1);
    if start > stop { 0..0 } else { start as usize..stop as usize + 1 }
}

enum Bound { NegativeInfinity, Finite(i32, bool), PositiveInfinity }
impl Bound {
    fn parse(text: &str) -> CommandResult<Self> {
        match text {
            "-inf" => Ok(Self::NegativeInfinity), "+inf" => Ok(Self::PositiveInfinity),
            _ => {
                let exclusive = text.starts_with('(');
                let value = parse_integer(if exclusive { &text[1..] } else { text })
                    .ok_or_else(|| "ERR min or max is not a float".to_owned())?;
                Ok(Self::Finite(value, exclusive))
            }
        }
    }
    fn accepts(&self, score: i32, lower: bool) -> bool {
        match *self {
            Self::NegativeInfinity => lower, Self::PositiveInfinity => !lower,
            Self::Finite(value, exclusive) => if lower { score > value || (!exclusive && score == value) }
                else { score < value || (!exclusive && score == value) },
        }
    }
}
enum Part { Literal(u8), Any, Star, Class([bool; 128], bool) }
fn pattern(text: &str) -> CommandResult<Vec<Part>> {
    let bytes = text.as_bytes();
    let mut parts = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'\\' => {
                i += 1;
                if i == bytes.len() { return Err("ERR invalid pattern".into()); }
                parts.push(Part::Literal(bytes[i]));
            }
            b'[' => {
                let end = (i + 1..bytes.len()).find(|&j| bytes[j] == b']').ok_or_else(|| "ERR invalid pattern".to_owned())?;
                i += 1;
                let negated = i < end && bytes[i] == b'^';
                if negated { i += 1; }
                if i == end { return Err("ERR invalid pattern".into()); }
                let mut characters = [false; 128];
                while i < end {
                    let first = bytes[i] as usize;
                    if i + 2 < end && bytes[i + 1] == b'-' {
                        let last = bytes[i + 2] as usize;
                        characters[first.min(last)..=first.max(last)].fill(true);
                        i += 3;
                    } else { characters[first] = true; i += 1; }
                }
                parts.push(Part::Class(characters, negated));
            }
            b'*' => parts.push(Part::Star), b'?' => parts.push(Part::Any), c => parts.push(Part::Literal(c)),
        }
        i += 1;
    }
    Ok(parts)
}
fn matches_pattern(parts: &[Part], text: &str) -> bool {
    let mut previous = vec![false; text.len() + 1];
    previous[0] = true;
    for part in parts {
        let mut next = vec![false; previous.len()];
        if matches!(part, Part::Star) {
            next[0] = previous[0];
            for i in 1..next.len() { next[i] = previous[i] || next[i - 1]; }
        } else {
            for (i, byte) in text.bytes().enumerate() {
                let accepts = match part {
                    Part::Any => true, Part::Literal(c) => *c == byte,
                    Part::Class(characters, negated) => characters[byte as usize] != *negated, Part::Star => unreachable!(),
                };
                next[i + 1] = previous[i] && accepts;
            }
        }
        previous = next;
    }
    previous[text.len()]
}

enum Arity { Exact(usize), Between(usize, usize), AtLeast(usize), Parity(usize, usize) }
impl Arity {
    fn accepts(&self, count: usize) -> bool {
        match *self {
            Self::Exact(n) => count == n, Self::Between(a, b) => (a..=b).contains(&count),
            Self::AtLeast(n) => count >= n, Self::Parity(n, parity) => count >= n && count % 2 == parity,
        }
    }
}
fn arity(command: &str) -> Option<Arity> {
    Some(match command {
        "TIME" | "DBSIZE" | "FLUSH" | "INFO" | "BEGIN" | "COMMIT" | "ROLLBACK" => Arity::Exact(0),
        "GET" | "INCR" | "DECR" | "STRLEN" | "LLEN" | "HGETALL" | "HLEN" | "HKEYS" | "HVALS" |
        "SMEMBERS" | "SCARD" | "ZCARD" | "TYPE" | "KEYS" | "TTL" | "PERSIST" | "TICK" | "SNAPSHOT" | "RESTORE" => Arity::Exact(1),
        "INCRBY" | "DECRBY" | "APPEND" | "LINDEX" | "HGET" | "HEXISTS" | "SISMEMBER" | "ZSCORE" | "ZRANK" | "RENAME" | "RENAMENX" => Arity::Exact(2),
        "GETRANGE" | "LRANGE" | "LSET" | "LREM" | "LTRIM" | "HINCRBY" | "ZINCRBY" => Arity::Exact(3),
        "LINSERT" => Arity::Exact(4), "LPOP" | "RPOP" => Arity::Between(1, 2), "EXPIRE" => Arity::Between(2, 3),
        "ZRANGE" | "ZRANGEBYSCORE" => Arity::Between(3, 4),
        "MGET" | "SINTER" | "SUNION" | "SDIFF" | "DEL" | "EXISTS" => Arity::AtLeast(1),
        "SET" | "LPUSH" | "RPUSH" | "HDEL" | "SADD" | "SREM" | "ZREM" | "SINTERSTORE" | "SUNIONSTORE" | "SDIFFSTORE" => Arity::AtLeast(2),
        "MSET" => Arity::Parity(2, 0), "HSET" | "ZADD" => Arity::Parity(3, 1), _ => return None,
    })
}

#[derive(Default)]
struct Store { database: Database, time: i32, stack: Vec<Database>, snapshots: BTreeMap<String, Database> }
impl Store {
    fn text(&self, key: &str) -> CommandResult<String> {
        match self.database.get(key).map(|entry| &entry.value) {
            None => Ok(String::new()), Some(Value::Text(text)) => Ok(text.clone()), _ => Err(WRONG_TYPE.into()),
        }
    }
    fn list(&self, key: &str) -> CommandResult<Vec<String>> {
        match self.database.get(key).map(|entry| &entry.value) {
            None => Ok(Vec::new()), Some(Value::List(items)) => Ok(items.clone()), _ => Err(WRONG_TYPE.into()),
        }
    }
    fn hash(&self, key: &str) -> CommandResult<BTreeMap<String, String>> {
        match self.database.get(key).map(|entry| &entry.value) {
            None => Ok(BTreeMap::new()), Some(Value::Hash(fields)) => Ok(fields.clone()), _ => Err(WRONG_TYPE.into()),
        }
    }
    fn set(&self, key: &str) -> CommandResult<BTreeSet<String>> {
        match self.database.get(key).map(|entry| &entry.value) {
            None => Ok(BTreeSet::new()), Some(Value::Set(members)) => Ok(members.clone()), _ => Err(WRONG_TYPE.into()),
        }
    }
    fn sorted_set(&self, key: &str) -> CommandResult<BTreeMap<String, i32>> {
        match self.database.get(key).map(|entry| &entry.value) {
            None => Ok(BTreeMap::new()), Some(Value::SortedSet(scores)) => Ok(scores.clone()), _ => Err(WRONG_TYPE.into()),
        }
    }
    fn replace(&mut self, key: &str, value: Value, expiry: Option<i32>) {
        if value.empty() { self.database.remove(key); }
        else { self.database.insert(key.to_owned(), Entry { value, expiry }); }
    }
    fn update(&mut self, key: &str, value: Value) {
        let expiry = self.database.get(key).and_then(|entry| entry.expiry);
        self.replace(key, value, expiry);
    }
    fn purge(&mut self) -> i32 {
        let before = self.database.len();
        let time = self.time;
        self.database.retain(|_, entry| entry.expiry.is_none_or(|expiry| expiry > time));
        (before - self.database.len()) as i32
    }
    fn execute(&mut self, command: &str, a: &[String]) -> CommandResult<Reply> {
        Ok(match command {
            "SET" => {
                let mut options = BTreeSet::new();
                let mut seconds_text = None;
                let mut i = 2;
                while i < a.len() {
                    let option = a[i].to_ascii_uppercase();
                    if !matches!(option.as_str(), "NX" | "XX" | "EX" | "KEEPTTL" | "GET") || !options.insert(option.clone()) {
                        return Err("ERR syntax error".into());
                    }
                    if option == "EX" {
                        i += 1;
                        if i == a.len() { return Err("ERR syntax error".into()); }
                        seconds_text = Some(&a[i]);
                    }
                    i += 1;
                }
                if (options.contains("NX") && options.contains("XX")) || (options.contains("EX") && options.contains("KEEPTTL")) {
                    return Err("ERR syntax error".into());
                }
                let mut expiry = None;
                if let Some(text) = seconds_text {
                    let seconds = integer(text)?;
                    if seconds <= 0 { return Err("ERR invalid expire time in 'set' command".into()); }
                    expiry = Some(self.time + seconds);
                }
                let exists = self.database.contains_key(&a[0]);
                let old = if options.contains("GET") { let text = self.text(&a[0])?; exists.then_some(text) } else { None };
                if options.contains("KEEPTTL") { expiry = self.database.get(&a[0]).and_then(|entry| entry.expiry); }
                let changed = !(options.contains("NX") && exists) && !(options.contains("XX") && !exists);
                if changed { self.replace(&a[0], Value::Text(a[1].clone()), expiry); }
                if options.contains("GET") { Reply::Text(old) } else if changed { status("OK") } else { Reply::Text(None) }
            }
            "GET" | "STRLEN" => {
                let text = self.text(&a[0])?;
                if command == "GET" { Reply::Text(self.database.contains_key(&a[0]).then_some(text)) }
                else { Reply::Integer(text.len() as i32) }
            }
            "MSET" => {
                for pair in a.chunks_exact(2) { self.replace(&pair[0], Value::Text(pair[1].clone()), None); }
                status("OK")
            }
            "MGET" => Reply::Array(a.iter().map(|key| match self.database.get(key).map(|entry| &entry.value) {
                Some(Value::Text(text)) => Some(text.clone()), _ => None,
            }).collect()),
            "INCR" | "DECR" | "INCRBY" | "DECRBY" => {
                let mut delta = if a.len() == 2 { integer(&a[1])? } else { 1 };
                if matches!(command, "DECR" | "DECRBY") { delta = -delta; }
                let text = self.text(&a[0])?;
                let old = if self.database.contains_key(&a[0]) { integer(&text)? } else { 0 };
                let result = add(old, delta)?;
                self.update(&a[0], Value::Text(result.to_string()));
                Reply::Integer(result)
            }
            "APPEND" => {
                let mut text = self.text(&a[0])?;
                text.push_str(&a[1]);
                let length = text.len();
                self.update(&a[0], Value::Text(text));
                Reply::Integer(length as i32)
            }
            "GETRANGE" => {
                let start = integer(&a[1])?;
                let stop = integer(&a[2])?;
                let text = self.text(&a[0])?;
                Reply::Text(Some(text[range(text.len(), start, stop)].to_owned()))
            }
            "LPUSH" | "RPUSH" => {
                let mut list = self.list(&a[0])?;
                for element in &a[1..] {
                    if command == "LPUSH" { list.insert(0, element.clone()); } else { list.push(element.clone()); }
                }
                let length = list.len();
                self.update(&a[0], Value::List(list));
                Reply::Integer(length as i32)
            }
            "LPOP" | "RPOP" => {
                let count = if a.len() == 2 { parse_integer(&a[1]).filter(|&n| n >= 0).ok_or_else(|| POSITIVE.to_owned())? } else { 1 };
                let mut list = self.list(&a[0])?;
                if !self.database.contains_key(&a[0]) { return Ok(Reply::Text(None)); }
                let mut removed = Vec::new();
                for _ in 0..(count as usize).min(list.len()) {
                    removed.push(if command == "LPOP" { list.remove(0) } else { list.pop().unwrap() });
                }
                self.update(&a[0], Value::List(list));
                if a.len() == 1 { Reply::Text(removed.pop()) } else { array(removed) }
            }
            "LRANGE" | "LTRIM" => {
                let start = integer(&a[1])?;
                let stop = integer(&a[2])?;
                let list = self.list(&a[0])?;
                let kept = list[range(list.len(), start, stop)].to_vec();
                if command == "LRANGE" { array(kept) }
                else { self.update(&a[0], Value::List(kept)); status("OK") }
            }
            "LLEN" => Reply::Integer(self.list(&a[0])?.len() as i32),
            "LINDEX" | "LSET" => {
                let mut index = integer(&a[1])?;
                let mut list = self.list(&a[0])?;
                if command == "LSET" && !self.database.contains_key(&a[0]) { return Err("ERR no such key".into()); }
                if index < 0 { index += list.len() as i32; }
                let valid = (0..list.len() as i32).contains(&index);
                if command == "LINDEX" { Reply::Text(if valid { Some(list[index as usize].clone()) } else { None }) }
                else {
                    if !valid { return Err("ERR index out of range".into()); }
                    list[index as usize] = a[2].clone();
                    self.update(&a[0], Value::List(list));
                    status("OK")
                }
            }
            "LREM" => {
                let count = integer(&a[1])?;
                let mut list = self.list(&a[0])?;
                if count < 0 { list.reverse(); }
                let limit = if count == 0 { list.len() } else { count.unsigned_abs() as usize };
                let mut removed = 0;
                list.retain(|element| {
                    if element == &a[2] && removed < limit { removed += 1; false } else { true }
                });
                if count < 0 { list.reverse(); }
                self.update(&a[0], Value::List(list));
                Reply::Integer(removed as i32)
            }
            "LINSERT" => {
                let after = a[1].eq_ignore_ascii_case("AFTER");
                if !after && !a[1].eq_ignore_ascii_case("BEFORE") { return Err("ERR syntax error".into()); }
                let mut list = self.list(&a[0])?;
                if !self.database.contains_key(&a[0]) { Reply::Integer(0) }
                else if let Some(index) = list.iter().position(|element| element == &a[2]) {
                    list.insert(index + usize::from(after), a[3].clone());
                    let length = list.len();
                    self.update(&a[0], Value::List(list));
                    Reply::Integer(length as i32)
                } else { Reply::Integer(-1) }
            }
            "HSET" | "HGET" | "HDEL" | "HGETALL" | "HLEN" | "HEXISTS" | "HKEYS" | "HVALS" | "HINCRBY" => {
                let delta = if command == "HINCRBY" { integer(&a[2])? } else { 0 };
                let mut fields = self.hash(&a[0])?;
                match command {
                    "HSET" => {
                        let mut added = 0;
                        for pair in a[1..].chunks_exact(2) { added += i32::from(fields.insert(pair[0].clone(), pair[1].clone()).is_none()); }
                        self.update(&a[0], Value::Hash(fields));
                        Reply::Integer(added)
                    }
                    "HGET" => Reply::Text(fields.get(&a[1]).cloned()),
                    "HDEL" => {
                        let removed = a[1..].iter().filter(|field| fields.remove(*field).is_some()).count();
                        self.update(&a[0], Value::Hash(fields));
                        Reply::Integer(removed as i32)
                    }
                    "HLEN" => Reply::Integer(fields.len() as i32),
                    "HEXISTS" => Reply::Integer(i32::from(fields.contains_key(&a[1]))),
                    "HINCRBY" => {
                        let old = if let Some(text) = fields.get(&a[1]) {
                            parse_integer(text).ok_or_else(|| "ERR hash value is not an integer".to_owned())?
                        } else { 0 };
                        let result = add(old, delta)?;
                        fields.insert(a[1].clone(), result.to_string());
                        self.update(&a[0], Value::Hash(fields));
                        Reply::Integer(result)
                    }
                    _ => {
                        let mut result = Vec::new();
                        for (field, value) in fields {
                            if command != "HVALS" { result.push(field); }
                            if command != "HKEYS" { result.push(value); }
                        }
                        array(result)
                    }
                }
            }
            "SINTER" | "SUNION" | "SDIFF" | "SINTERSTORE" | "SUNIONSTORE" | "SDIFFSTORE" => {
                let storing = command.ends_with("STORE");
                let operation = command.strip_suffix("STORE").unwrap_or(command);
                let sources: Vec<BTreeSet<String>> = a[usize::from(storing)..].iter().map(|key| self.set(key)).collect::<CommandResult<_>>()?;
                let mut result = sources[0].clone();
                for source in &sources[1..] {
                    match operation {
                        "SINTER" => result.retain(|member| source.contains(member)),
                        "SUNION" => result.extend(source.iter().cloned()),
                        _ => result.retain(|member| !source.contains(member)),
                    }
                }
                if storing {
                    let length = result.len();
                    self.replace(&a[0], Value::Set(result), None);
                    Reply::Integer(length as i32)
                } else { array(result) }
            }
            "SADD" | "SREM" | "SISMEMBER" | "SMEMBERS" | "SCARD" => {
                let mut members = self.set(&a[0])?;
                match command {
                    "SISMEMBER" => Reply::Integer(i32::from(members.contains(&a[1]))),
                    "SMEMBERS" => array(members), "SCARD" => Reply::Integer(members.len() as i32),
                    _ => {
                        let mut changed = 0;
                        for member in &a[1..] { changed += i32::from(if command == "SADD" { members.insert(member.clone()) } else { members.remove(member) }); }
                        self.update(&a[0], Value::Set(members));
                        Reply::Integer(changed)
                    }
                }
            }
            "ZADD" => {
                let scores: Vec<i32> = a[1..].chunks_exact(2).map(|pair| integer(&pair[0])).collect::<CommandResult<_>>()?;
                let mut members = self.sorted_set(&a[0])?;
                let mut added = 0;
                for (pair, score) in a[1..].chunks_exact(2).zip(scores) {
                    added += i32::from(members.insert(pair[1].clone(), score).is_none());
                }
                self.update(&a[0], Value::SortedSet(members));
                Reply::Integer(added)
            }
            "ZINCRBY" => {
                let delta = integer(&a[1])?;
                let mut members = self.sorted_set(&a[0])?;
                let result = add(members.get(&a[2]).copied().unwrap_or(0), delta)?;
                members.insert(a[2].clone(), result);
                self.update(&a[0], Value::SortedSet(members));
                Reply::Text(Some(result.to_string()))
            }
            "ZSCORE" | "ZREM" | "ZCARD" | "ZRANK" | "ZRANGE" | "ZRANGEBYSCORE" => {
                let by_index = command == "ZRANGE";
                let by_score = command == "ZRANGEBYSCORE";
                let with_scores = a.len() == 4;
                let (mut start, mut stop) = (0, 0);
                let (mut minimum, mut maximum) = (Bound::NegativeInfinity, Bound::PositiveInfinity);
                if by_index || by_score {
                    if with_scores && !a[3].eq_ignore_ascii_case("WITHSCORES") { return Err("ERR syntax error".into()); }
                    if by_index { start = integer(&a[1])?; stop = integer(&a[2])?; }
                    else { minimum = Bound::parse(&a[1])?; maximum = Bound::parse(&a[2])?; }
                }
                let mut members = self.sorted_set(&a[0])?;
                match command {
                    "ZSCORE" => Reply::Text(members.get(&a[1]).map(i32::to_string)),
                    "ZREM" => {
                        let removed = a[1..].iter().filter(|member| members.remove(*member).is_some()).count();
                        self.update(&a[0], Value::SortedSet(members));
                        Reply::Integer(removed as i32)
                    }
                    "ZCARD" => Reply::Integer(members.len() as i32),
                    _ => {
                        let mut ordered: Vec<_> = members.into_iter().collect();
                        ordered.sort_by(|(a, x), (b, y)| x.cmp(y).then_with(|| a.cmp(b)));
                        if command == "ZRANK" {
                            match ordered.iter().position(|(member, _)| member == &a[1]) {
                                Some(rank) => Reply::Integer(rank as i32), None => Reply::Text(None),
                            }
                        } else {
                            let selection = if by_index { range(ordered.len(), start, stop) } else { 0..ordered.len() };
                            let mut result = Vec::new();
                            for (member, score) in &ordered[selection] {
                                if by_score && (!minimum.accepts(*score, true) || !maximum.accepts(*score, false)) { continue; }
                                result.push(member.clone());
                                if with_scores { result.push(score.to_string()); }
                            }
                            array(result)
                        }
                    }
                }
            }
            "DEL" | "EXISTS" => {
                let mut count = 0;
                for key in a { count += i32::from(if command == "DEL" { self.database.remove(key).is_some() } else { self.database.contains_key(key) }); }
                Reply::Integer(count)
            }
            "TYPE" => status(self.database.get(&a[0]).map_or("none", |entry| entry.value.kind())),
            "RENAME" | "RENAMENX" => {
                if !self.database.contains_key(&a[0]) { return Err("ERR no such key".into()); }
                if command == "RENAMENX" && self.database.contains_key(&a[1]) { Reply::Integer(0) }
                else {
                    if a[0] != a[1] { let entry = self.database.remove(&a[0]).unwrap(); self.database.insert(a[1].clone(), entry); }
                    if command == "RENAME" { status("OK") } else { Reply::Integer(1) }
                }
            }
            "KEYS" => {
                let parts = pattern(&a[0])?;
                array(self.database.keys().filter(|key| matches_pattern(&parts, key)).cloned())
            }
            "EXPIRE" => {
                let condition = a.get(2).map(|text| text.to_ascii_uppercase());
                if condition.as_deref().is_some_and(|text| !matches!(text, "NX" | "XX" | "GT" | "LT")) {
                    return Err(format!("ERR Unsupported option {}", a[2]));
                }
                let seconds = integer(&a[1])?;
                let expiry = self.time + seconds;
                if let Some(entry) = self.database.get_mut(&a[0]) {
                    let rejected = match condition.as_deref() {
                        Some("NX") => entry.expiry.is_some(), Some("XX") => entry.expiry.is_none(),
                        Some("GT") => entry.expiry.is_none_or(|old| expiry <= old),
                        Some("LT") => entry.expiry.is_some_and(|old| expiry >= old), _ => false,
                    };
                    if rejected { Reply::Integer(0) }
                    else {
                        if seconds <= 0 { self.database.remove(&a[0]); } else { entry.expiry = Some(expiry); }
                        Reply::Integer(1)
                    }
                } else { Reply::Integer(0) }
            }
            "TTL" => Reply::Integer(self.database.get(&a[0]).map_or(-2, |entry| entry.expiry.map_or(-1, |expiry| expiry - self.time))),
            "PERSIST" => {
                let changed = self.database.get_mut(&a[0]).is_some_and(|entry| entry.expiry.take().is_some());
                Reply::Integer(i32::from(changed))
            }
            "TICK" => {
                let ticks = integer(&a[0])?;
                if ticks <= 0 { return Err(POSITIVE.into()); }
                self.time += ticks;
                Reply::Integer(self.purge())
            }
            "TIME" => Reply::Integer(self.time), "DBSIZE" => Reply::Integer(self.database.len() as i32),
            "FLUSH" => { self.database.clear(); status("OK") }
            "INFO" => {
                let count = |kind: &str| self.database.values().filter(|entry| entry.value.kind() == kind).count();
                Reply::Status(format!("keys={},expires={},string={},list={},hash={},set={},zset={},time={},depth={},snapshots={}",
                    self.database.len(), self.database.values().filter(|entry| entry.expiry.is_some()).count(),
                    count("string"), count("list"), count("hash"), count("set"), count("zset"), self.time, self.stack.len(), self.snapshots.len()))
            }
            "BEGIN" => { self.stack.push(self.database.clone()); status("OK") }
            "COMMIT" | "ROLLBACK" => {
                let saved = self.stack.pop().ok_or_else(|| "ERR no transaction".to_owned())?;
                if command == "ROLLBACK" { self.database = saved; self.purge(); }
                status("OK")
            }
            "SNAPSHOT" => { self.snapshots.insert(a[0].clone(), self.database.clone()); status("OK") }
            "RESTORE" => {
                let saved = self.snapshots.get(&a[0]).ok_or_else(|| "ERR no such snapshot".to_owned())?;
                self.database = saved.clone();
                self.purge();
                status("OK")
            }
            _ => unreachable!(),
        })
    }
    fn process(&mut self, line: &str) -> CommandResult<Reply> {
        let Some(words) = split_line(line) else { return Ok(status("Invalid argument(s)")); };
        let command = words[0].to_ascii_uppercase();
        let spec = arity(&command).ok_or_else(|| format!("ERR unknown command '{}'", words[0]))?;
        if !spec.accepts(words.len() - 1) {
            return Err(format!("ERR wrong number of arguments for '{}' command", command.to_ascii_lowercase()));
        }
        self.execute(&command, &words[1..])
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let Some(first) = lines.next() else { return; };
    let count: usize = first.parse().unwrap();
    let mut store = Store::default();
    let mut output = io::BufWriter::new(io::stdout().lock());
    for line in lines.take(count) {
        match store.process(line) {
            Ok(reply) => writeln!(output, "{reply}").unwrap(),
            Err(message) => writeln!(output, "(error) {message}").unwrap(),
        }
    }
}
