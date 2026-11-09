mod lexer;
mod ini_parser;
mod interpolate;
mod schema;
mod emitter;

use std::collections::{BTreeMap, BTreeSet};
use std::{fs, io};
use ini_parser::{Document, StatementKind, parse_document};
use schema::{Kind, Schema, Spec};

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Origin { pub document: String, pub line: usize }
impl Origin {
    pub fn new(document: &str, line: usize) -> Self { Self { document: document.into(), line } }
    pub fn text(&self) -> String { format!("{}:{}", self.document, self.line) }
}

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Diagnostic { pub origin: Origin, pub code: &'static str, pub message: String }

#[derive(Clone)]
pub struct Definition { pub value: String, pub origin: Origin, pub number: usize, pub history: Vec<Origin> }

#[derive(Clone)]
pub enum Value { Text(String), Integer(i64), Boolean(bool), List(Vec<Value>) }

pub struct OutputKey {
    pub definition: Definition,
    pub spec: Option<usize>,
    pub value: Value,
    pub notation: String,
    pub secret: bool,
}

pub struct Profile {
    pub name: String,
    root: String,
    configuration: BTreeMap<String, Definition>,
    definitions: usize,
    parents: BTreeMap<String, (String, Origin)>,
    pub tree: Vec<(usize, String)>,
    pub diagnostics: BTreeSet<Diagnostic>,
    pub outputs: BTreeMap<String, OutputKey>,
    pub overridden: Vec<(String, Vec<Origin>)>,
    pub document_keys: usize,
    pub manifest_keys: usize,
    pub default_keys: usize,
    pub dropped: usize,
    pub errors: usize,
    pub warnings: usize,
}

pub struct Difference {
    pub first: String, pub second: String,
    pub added: usize, pub removed: usize, pub changed: usize,
    pub entries: Vec<(String, Option<String>, Option<String>)>,
}

pub fn key_parts(key: &str) -> (&str, &str) { key.rsplit_once('.').unwrap() }
pub fn ordered_keys<T>(map: &BTreeMap<String, T>) -> Vec<String> {
    let mut keys: Vec<String> = map.keys().cloned().collect();
    keys.sort_by(|a, b| key_parts(a).cmp(&key_parts(b)));
    keys
}
fn digits(text: &str, minimum: usize, maximum: usize) -> bool {
    (minimum..=maximum).contains(&text.len()) && text.bytes().all(|b| b.is_ascii_digit())
}
fn decimal(text: &str) -> i64 { text.parse().unwrap() }

fn parse_int(text: &str) -> Option<i64> {
    let (negative, number) = match text.as_bytes().first() {
        Some(b'-') => (true, &text[1..]), Some(b'+') => (false, &text[1..]), _ => (false, text),
    };
    let value = if number.starts_with("0x") || number.starts_with("0X") {
        let hex = &number[2..];
        if !(1..=10).contains(&hex.len()) || !hex.bytes().all(|c| c.is_ascii_hexdigit()) { return None; }
        i64::from_str_radix(hex, 16).ok()?
    } else {
        if number.is_empty() { return None; }
        let bytes = number.as_bytes();
        let mut count = 0;
        let mut value = 0;
        for (i, &byte) in bytes.iter().enumerate() {
            if byte == b'_' {
                if i == 0 || i + 1 == bytes.len() || !bytes[i - 1].is_ascii_digit() || !bytes[i + 1].is_ascii_digit() { return None; }
            } else if byte.is_ascii_digit() {
                count += 1;
                if count > 12 { return None; }
                value = value * 10 + i64::from(byte - b'0');
            } else { return None; }
        }
        value
    };
    Some(if negative { -value } else { value })
}

fn parse_size(text: &str) -> Option<i64> {
    let unit_start = text.bytes().position(|c| !c.is_ascii_digit() && c != b'.').unwrap_or(text.len());
    let factor = match text[unit_start..].to_ascii_lowercase().as_str() {
        "" | "b" => 1, "kb" => 1024, "mb" => 1048576, "gb" => 1073741824, _ => return None,
    };
    let number = &text[..unit_start];
    let (whole, fraction) = number.split_once('.').map_or((number, None), |(a, b)| (a, Some(b)));
    if !digits(whole, 1, 6) { return None; }
    let mut value = decimal(whole) * factor;
    if let Some(fraction) = fraction {
        if !digits(fraction, 1, 3) { return None; }
        let divisor = 10_i64.pow(fraction.len() as u32);
        let scaled = decimal(fraction) * factor;
        if scaled % divisor != 0 { return None; }
        value += scaled / divisor;
    }
    Some(value)
}

fn parse_duration(text: &str) -> Option<i64> {
    if digits(text, 1, 6) { return Some(decimal(text)); }
    let mut position = 0;
    let mut previous = 0;
    let mut value = 0;
    while position < text.len() {
        let start = position;
        while position < text.len() && text.as_bytes()[position].is_ascii_digit() { position += 1; }
        if !digits(&text[start..position], 1, 6) || position == text.len() { return None; }
        let (order, factor) = match text.as_bytes()[position] { b'h' => (1, 3600), b'm' => (2, 60), b's' => (3, 1), _ => return None };
        if order <= previous { return None; }
        previous = order;
        value += decimal(&text[start..position]) * factor;
        position += 1;
    }
    if previous == 0 { None } else { Some(value) }
}

fn parse_host(text: &str) -> Option<String> {
    if text.bytes().all(|c| c.is_ascii_digit() || c == b'.') {
        let parts: Vec<&str> = text.split('.').collect();
        if parts.len() != 4 || parts.iter().any(|s| !digits(s, 1, 3) || (s.len() > 1 && s.starts_with('0')) || decimal(s) > 255) { return None; }
    } else {
        if text.len() > 253 { return None; }
        for label in text.split('.') {
            if !(1..=63).contains(&label.len()) || label.starts_with('-') || label.ends_with('-')
                || !label.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-') { return None; }
        }
    }
    Some(text.to_ascii_lowercase())
}

fn parse_path(text: &str) -> Option<String> {
    if text.is_empty() || text.bytes().any(|c| b" \n\t".contains(&c)) { return None; }
    let absolute = text.starts_with('/');
    let mut parts = Vec::new();
    for part in text.split('/') {
        match part {
            "" | "." => (),
            ".." if parts.last().is_some_and(|p| *p != "..") => { parts.pop(); }
            ".." if absolute => return None,
            _ => parts.push(part),
        }
    }
    let joined = parts.join("/");
    Some(if absolute { format!("/{joined}") } else if joined.is_empty() { ".".into() } else { joined })
}

fn parse_url(text: &str) -> Option<String> {
    let (scheme, rest) = text.split_once("://")?;
    if scheme.is_empty() || !scheme.as_bytes()[0].is_ascii_alphabetic()
        || !scheme.bytes().all(|c| c.is_ascii_alphanumeric() || b"+-.".contains(&c)) || rest.contains('?') || rest.contains('#') { return None; }
    let (authority, path) = rest.split_once('/').unwrap_or((rest, ""));
    let (host, port) = authority.split_once(':').map_or((authority, None), |(h, p)| (h, Some(p)));
    let host = parse_host(host)?;
    let path = parse_path(&format!("/{path}"))?;
    let scheme = scheme.to_ascii_lowercase();
    let mut result = format!("{scheme}://{host}");
    if let Some(port) = port {
        if !digits(port, 1, 5) || port.starts_with('0') || decimal(port) > 65535 { return None; }
        if !((scheme == "http" && decimal(port) == 80) || (scheme == "https" && decimal(port) == 443)) {
            result.push(':'); result.push_str(port);
        }
    }
    result.push_str(&path);
    Some(result)
}

fn parse_date(text: &str) -> Option<String> {
    if text.len() != 10 || &text[4..5] != "-" || &text[7..8] != "-"
        || !digits(&text[..4], 4, 4) || !digits(&text[5..7], 2, 2) || !digits(&text[8..], 2, 2) { return None; }
    let (year, month, day) = (decimal(&text[..4]), decimal(&text[5..7]), decimal(&text[8..]));
    if year == 0 || !(1..=12).contains(&month) { return None; }
    let mut days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month as usize - 1];
    if month == 2 && ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) { days = 29; }
    if (1..=days).contains(&day) { Some(text.into()) } else { None }
}

fn scalar(kind: Kind, text: &str, choices: &[String]) -> Option<Value> {
    match kind {
        Kind::String => Some(Value::Text(text.into())),
        Kind::Int => parse_int(text).map(Value::Integer),
        Kind::Size => parse_size(text).map(Value::Integer),
        Kind::Duration => parse_duration(text).map(Value::Integer),
        Kind::Bool => match text.to_ascii_lowercase().as_str() {
            "true" | "yes" | "on" | "1" => Some(Value::Boolean(true)),
            "false" | "no" | "off" | "0" => Some(Value::Boolean(false)), _ => None,
        },
        Kind::Enum => choices.iter().find(|s| s.eq_ignore_ascii_case(text)).cloned().map(Value::Text),
        Kind::Host => parse_host(text).map(Value::Text), Kind::Path => parse_path(text).map(Value::Text),
        Kind::Url => parse_url(text).map(Value::Text), Kind::Date => parse_date(text).map(Value::Text), Kind::List => None,
    }
}

type CheckError = (&'static str, String);
fn invalid(key: &str, kind: Kind, choices: &[String], text: &str, secret: bool, item: bool) -> CheckError {
    let checked = if secret { emitter::MASK.into() } else { emitter::string_notation(text) };
    let display = if item { format!("item {checked}") } else { checked };
    if kind == Kind::Enum { ("E_ENUM", format!("{key}: {display} is not one of {}", choices.join(","))) }
    else { ("E_TYPE", format!("{key}: {display} is not a valid {}", kind.name())) }
}

#[derive(PartialEq, PartialOrd)]
enum Measure { Number(i64), Date(String) }
fn bound(kind: Kind, text: &str) -> Option<Measure> {
    if text.is_empty() { return None; }
    if kind == Kind::Date { Some(Measure::Date(text.into())) }
    else if kind == Kind::String || kind == Kind::List { Some(Measure::Number(decimal(text))) }
    else if let Some(Value::Integer(value)) = scalar(kind, text, &[]) { Some(Measure::Number(value)) }
    else { unreachable!() }
}
fn bound_text(bound: &Option<Measure>) -> String {
    match bound { None => String::new(), Some(Measure::Number(n)) => n.to_string(), Some(Measure::Date(s)) => s.clone() }
}
fn check_range(key: &str, spec: &Spec, value: &Value) -> Result<(), CheckError> {
    let Some((lower, upper)) = &spec.range else { return Ok(()); };
    let (measure, display) = match value {
        Value::Text(s) if spec.kind == Kind::String => (Measure::Number(s.len() as i64), format!("length {}", s.len())),
        Value::List(items) => (Measure::Number(items.len() as i64), format!("count {}", items.len())),
        Value::Text(s) => (Measure::Date(s.clone()), if spec.secret { emitter::MASK.into() } else { s.clone() }),
        Value::Integer(n) => (Measure::Number(*n), if spec.secret { emitter::MASK.into() } else { n.to_string() }),
        Value::Boolean(_) => unreachable!(),
    };
    let (lower, upper) = (bound(spec.kind, lower), bound(spec.kind, upper));
    if lower.as_ref().is_some_and(|b| measure < *b) || upper.as_ref().is_some_and(|b| measure > *b) {
        Err(("E_RANGE", format!("{key}: {display} is out of range {}..{}", bound_text(&lower), bound_text(&upper))))
    } else { Ok(()) }
}

struct Library { documents: BTreeMap<String, Option<Document>> }
impl Library {
    fn find(&mut self, name: &str) -> io::Result<Option<Document>> {
        if !self.documents.contains_key(name) {
            let document = match fs::read_to_string(format!("input/conf/{name}.ini")) {
                Ok(source) => Some(parse_document(name, &source)),
                Err(error) if error.kind() == io::ErrorKind::NotFound => None,
                Err(error) => return Err(error),
            };
            self.documents.insert(name.into(), document);
        }
        Ok(self.documents[name].clone())
    }
}

impl Profile {
    fn new(name: &str, root: &str) -> Self {
        Self { name: name.into(), root: root.into(), configuration: BTreeMap::new(), definitions: 0,
            parents: BTreeMap::new(), tree: Vec::new(), diagnostics: BTreeSet::new(), outputs: BTreeMap::new(),
            overridden: Vec::new(), document_keys: 0, manifest_keys: 0, default_keys: 0, dropped: 0, errors: 0, warnings: 0 }
    }
    fn report(&mut self, origin: &Origin, code: &'static str, message: String) {
        self.diagnostics.insert(Diagnostic { origin: origin.clone(), code, message });
    }
    fn define(&mut self, key: String, value: String, origin: Origin) {
        self.definitions += 1;
        let mut history = self.configuration.get(&key).map_or_else(Vec::new, |d| d.history.clone());
        if history.last() != Some(&origin) { history.push(origin.clone()); }
        self.configuration.insert(key, Definition { value, origin, number: self.definitions, history });
    }
    fn apply(&mut self, library: &mut Library, name: &str, chain: &mut Vec<String>) -> io::Result<()> {
        let document = library.find(name)?.unwrap();
        self.tree.push((chain.len() - 1, name.into()));
        self.diagnostics.extend(document.diagnostics);
        for statement in document.statements {
            let origin = Origin::new(name, statement.line);
            match statement.kind {
                StatementKind::Assign => self.define(statement.target, statement.value, origin),
                StatementKind::Append => {
                    let value = match self.configuration.get(&statement.target) {
                        Some(old) if !old.value.is_empty() => format!("{},{}", old.value, statement.value), _ => statement.value,
                    };
                    self.define(statement.target, value, origin);
                }
                StatementKind::Unset => {
                    if self.configuration.remove(&statement.target).is_none() { self.report(&origin, "W_UNSET", format!("{} is not set", statement.target)); }
                }
                StatementKind::Inherit => { self.parents.insert(statement.target, (statement.value, origin)); }
                StatementKind::Include => {
                    let target = statement.target;
                    if let Some(start) = chain.iter().position(|s| s == &target) {
                        let mut path = chain[start..].to_vec(); path.push(target.clone());
                        self.report(&origin, "E_INCLUDE_CYCLE", format!("include cycle {}", path.join(" -> ")));
                        self.tree.push((chain.len(), format!("{target} (cycle)")));
                    } else if library.find(&target)?.is_none() {
                        self.report(&origin, "E_INCLUDE_MISSING", format!("missing document {target}"));
                        self.tree.push((chain.len(), format!("{target} (missing)")));
                    } else {
                        chain.push(target.clone()); self.apply(library, &target, chain)?; chain.pop();
                    }
                }
            }
        }
        Ok(())
    }
    fn inherit(&mut self) {
        let own = self.configuration.clone();
        for (section, (parent, origin)) in self.parents.clone() {
            let mut chain = vec![section.clone()];
            while let Some((next, _)) = self.parents.get(chain.last().unwrap()) {
                if chain.contains(next) { break; }
                chain.push(next.clone());
            }
            if let Some((next, _)) = self.parents.get(chain.last().unwrap()) {
                chain.push(next.clone());
                self.report(&origin, "E_INHERIT_CYCLE", format!("inheritance cycle {}", chain.join(" -> ")));
                continue;
            }
            if !self.parents.contains_key(&parent) && !own.keys().any(|k| key_parts(k).0 == parent) {
                self.report(&origin, "W_PARENT_EMPTY", format!("section {section} inherits from empty section {parent}"));
            }
            for ancestor in &chain[1..] {
                for (key, definition) in &own {
                    let (source, name) = key_parts(key);
                    if source == ancestor { self.configuration.entry(format!("{section}.{name}")).or_insert_with(|| definition.clone()); }
                }
            }
        }
    }
    fn aliases(&mut self, schema: &Schema) {
        for spec in &schema.specs {
            let aliases: Vec<String> = spec.aliases.iter().filter(|k| self.configuration.contains_key(*k)).cloned().collect();
            if aliases.is_empty() { continue; }
            let mut candidates = Vec::new();
            if self.configuration.contains_key(&spec.pattern) { candidates.push(spec.pattern.clone()); }
            candidates.extend(aliases.iter().cloned());
            let mut winner = candidates[0].clone();
            for candidate in &candidates[1..] {
                if self.configuration[candidate].number > self.configuration[&winner].number { winner = candidate.clone(); }
            }
            let chosen = self.configuration[&winner].clone();
            for candidate in &candidates {
                let origin = self.configuration[candidate].origin.clone();
                if candidate != &spec.pattern { self.report(&origin, "W_DEPRECATED", format!("{candidate} is deprecated, use {}", spec.pattern)); }
                if candidate != &winner { self.report(&origin, "W_SHADOWED", format!("{candidate} is superseded by {winner} at {}", chosen.origin.text())); }
            }
            self.configuration.insert(spec.pattern.clone(), chosen);
            for alias in aliases { self.configuration.remove(&alias); }
        }
    }
    fn normalize(&mut self, key: &str, spec: &Spec, text: &str, origin: &Origin) -> Result<Value, CheckError> {
        let value = if spec.kind != Kind::List {
            scalar(spec.kind, text, &spec.values).ok_or_else(|| invalid(key, spec.kind, &spec.values, text, spec.secret, false))?
        } else {
            let mut values = Vec::new();
            if !text.trim_matches(' ').is_empty() {
                let items: Vec<&str> = text.split(',').map(|s| s.trim_matches(' ')).collect();
                if items.contains(&"") { self.report(origin, "W_EMPTY_ITEM", format!("{key}: empty list item ignored")); }
                for item in items.into_iter().filter(|s| !s.is_empty()) {
                    let value = scalar(spec.item, item, &spec.values).ok_or_else(|| invalid(key, spec.item, &spec.values, item, spec.secret, true))?;
                    values.push(value);
                }
            }
            if spec.unique {
                let mut seen = BTreeSet::new();
                let before = values.len();
                values.retain(|v| seen.insert(emitter::value_notation(spec.item, Kind::String, v)));
                if before != values.len() { self.report(origin, "W_DUPLICATE_ITEM", format!("{key}: duplicate items removed")); }
            }
            Value::List(values)
        };
        check_range(key, spec, &value)?;
        Ok(value)
    }
    fn process(&mut self, number: usize, overrides: &[&str], schema: &Schema, library: &mut Library, earlier: &[Profile]) -> io::Result<()> {
        let root = self.root.clone();
        self.apply(library, &root, &mut vec![root.clone()])?;
        for entry in overrides {
            let (key, value) = entry.split_once('=').unwrap();
            self.define(key.into(), value.into(), Origin::new("manifest", number));
        }
        self.inherit(); self.aliases(schema);
        let sections: BTreeSet<String> = self.configuration.keys().map(|key| key_parts(key).0.to_owned()).collect();
        for (index, spec) in schema.specs.iter().enumerate() {
            if let Some(default) = &spec.default {
                for key in schema.target_keys(index, &sections) {
                    if !self.configuration.contains_key(&key) { self.define(key, default.clone(), Origin::new("schema", spec.line)); }
                }
            }
        }
        let expansion = interpolate::expand(&self.configuration);
        self.diagnostics.extend(expansion.diagnostics);
        for key in ordered_keys(&self.configuration) {
            let Some(text) = expansion.results[&key].as_ref() else { continue; };
            let definition = self.configuration[&key].clone();
            let spec_index = schema.spec_for(&key);
            let (kind, item, secret, value) = if let Some(index) = spec_index {
                let spec = &schema.specs[index];
                match self.normalize(&key, spec, text, &definition.origin) {
                    Ok(value) => (spec.kind, spec.item, spec.secret, value),
                    Err((code, message)) => { self.report(&definition.origin, code, message); continue; }
                }
            } else {
                self.report(&definition.origin, "W_UNKNOWN", format!("{key} is not in the schema"));
                (Kind::String, Kind::String, false, Value::Text(text.clone()))
            };
            let notation = emitter::value_notation(kind, item, &value);
            self.outputs.insert(key, OutputKey { definition, spec: spec_index, value, notation, secret });
        }
        let mut rejected = Vec::new();
        for key in ordered_keys(&self.outputs) {
            let output = &self.outputs[&key];
            let Some(limit) = output.spec.and_then(|i| schema.specs[i].le.as_ref()) else { continue; };
            let limit_key = format!("{}.{limit}", key_parts(&key).0);
            if let Some(other) = self.outputs.get(&limit_key) {
                if let (Value::Integer(a), Value::Integer(b)) = (&output.value, &other.value) {
                    if a > b {
                        let origin = output.definition.origin.clone();
                        let message = format!("{key}: {} is greater than {limit_key} ({})", emitter::shown(output), emitter::shown(other));
                        self.report(&origin, "E_ORDER", message); rejected.push(key);
                    }
                }
            }
        }
        for key in rejected { self.outputs.remove(&key); }
        for (index, spec) in schema.specs.iter().enumerate().filter(|(_, s)| s.required) {
            for key in schema.target_keys(index, &sections) {
                if self.configuration.contains_key(&key) { continue; }
                let message = if let Some(condition) = &spec.when {
                    let condition_key = format!("{}.{condition}", key_parts(&key).0);
                    if !self.outputs.get(&condition_key).is_some_and(|o| matches!(o.value, Value::Boolean(true))) { continue; }
                    format!("{key} is required when {condition_key} is true")
                } else { format!("{key} is required") };
                self.report(&Origin::new(&root, 0), "E_REQUIRED", message);
            }
        }
        for key in ordered_keys(&self.outputs) {
            let output = &self.outputs[&key];
            if !output.spec.is_some_and(|i| schema.specs[i].fixed) { continue; }
            if let Some(reference) = earlier.iter().find(|p| p.outputs.contains_key(&key)) {
                if reference.outputs[&key].notation != output.notation {
                    let origin = output.definition.origin.clone();
                    self.report(&origin, "E_FIXED", format!("{key}: value differs from profile {}", reference.name));
                    self.outputs.remove(&key);
                }
            }
        }
        self.dropped = self.configuration.len() - self.outputs.len();
        self.errors = self.diagnostics.iter().filter(|d| d.code.starts_with("E_")).count();
        self.warnings = self.diagnostics.len() - self.errors;
        for key in ordered_keys(&self.outputs) {
            let definition = &self.outputs[&key].definition;
            if definition.history.len() >= 2 { self.overridden.push((key, definition.history.clone())); }
            match definition.origin.document.as_str() { "manifest" => self.manifest_keys += 1, "schema" => self.default_keys += 1, _ => self.document_keys += 1 }
        }
        Ok(())
    }
}

fn difference(first: &Profile, second: &Profile) -> Difference {
    let mut diff = Difference { first: first.name.clone(), second: second.name.clone(), added: 0, removed: 0, changed: 0, entries: Vec::new() };
    let mut keys: Vec<String> = first.outputs.keys().chain(second.outputs.keys()).cloned().collect();
    keys.sort_by(|a, b| key_parts(a).cmp(&key_parts(b))); keys.dedup();
    for key in keys {
        let (before, after) = (first.outputs.get(&key), second.outputs.get(&key));
        match (before, after) {
            (None, Some(_)) => diff.added += 1, (Some(_), None) => diff.removed += 1,
            (Some(a), Some(b)) if a.notation != b.notation => diff.changed += 1, _ => continue,
        }
        diff.entries.push((key, before.map(|o| emitter::shown(o).into()), after.map(|o| emitter::shown(o).into())));
    }
    diff
}

fn main() -> io::Result<()> {
    let schema = Schema::parse(&fs::read_to_string("input/schema.txt")?);
    let mut library = Library { documents: BTreeMap::new() };
    let mut profiles = Vec::new();
    for (index, line) in fs::read_to_string("input/manifest.txt")?.lines().enumerate() {
        let words: Vec<&str> = line.split(' ').collect();
        let mut profile = Profile::new(words[0], words[1]);
        profile.process(index + 1, &words[2..], &schema, &mut library, &profiles)?;
        profiles.push(profile);
    }
    let diffs: Vec<Difference> = profiles.windows(2).map(|pair| difference(&pair[0], &pair[1])).collect();
    emitter::write_outputs(&profiles, &diffs)
}
