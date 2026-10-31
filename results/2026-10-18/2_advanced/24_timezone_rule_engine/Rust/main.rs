mod day_rules;
mod tz_parser;
mod transitions;
mod resolver;
mod report;

use std::collections::{BTreeMap, HashMap, HashSet};
use std::{fs, io};
use day_rules::{DAY, NEG_INFINITY, POS_INFINITY, day_number, days_in_month, split_time, time_value};
use report::{change_text, clock_text, duration_text, local_text, offset_text, state_text, ut_text, write_blocks, write_lines};
use resolver::{Period, Timeline};
use transitions::{Rule, RuleInstance, abbreviation, adjustment, instance_sequence, run_instances};
use tz_parser::{MAX_YEAR, MIN_YEAR, Until};

fn read_lines(name: &str) -> io::Result<Vec<String>> { Ok(fs::read_to_string(format!("input/{name}"))?.lines().map(str::to_owned).collect()) }
fn year_start(year: i64) -> i64 { day_number(year, 1, 1) * DAY }
fn clock_seconds(text: &str) -> i64 { text[..2].parse::<i64>().unwrap() * 3600 + text[3..5].parse::<i64>().unwrap() * 60 }
fn names_or_none(names: &[String], separator: &str) -> String { if names.is_empty() { "none".to_owned() } else { names.join(separator) } }
fn indented(lines: Vec<String>) -> Vec<String> { lines.into_iter().enumerate().map(|(i, line)| if i == 0 { line } else { format!("  {line}") }).collect() }
fn merge_intervals(mut intervals: Vec<(i64, i64)>) -> Vec<(i64, i64)> {
    intervals.sort();
    let mut merged = Vec::<(i64, i64)>::new();
    for (low, high) in intervals {
        if let Some(last) = merged.last_mut() { if low <= last.1 { last.1 = last.1.max(high); continue; } }
        merged.push((low, high));
    }
    merged
}
fn intersect_intervals(first: &[(i64, i64)], second: &[(i64, i64)]) -> Vec<(i64, i64)> {
    let mut pieces = Vec::new();
    for &(a, b) in first { for &(c, d) in second { let low = a.max(c); let high = b.min(d); if low < high { pieces.push((low, high)); } } }
    merge_intervals(pieces)
}
#[derive(Clone, Copy, PartialEq)]
enum LineKind { Rule, Zone, Continuation, Link, Unknown }
struct SourceLine {
    number: usize, fields: Vec<String>, kind: LineKind, block: Option<usize>, position: usize,
    zone_line: Option<ZoneLine>, field_error: bool, error: Option<String>,
}
impl SourceLine {
    fn new(number: usize, content: &str) -> Self {
        let fields = tz_parser::split_fields(content);
        let kind = if content.starts_with(' ') { LineKind::Continuation } else { match fields[0].as_str() { "Rule" => LineKind::Rule, "Zone" => LineKind::Zone, "Link" => LineKind::Link, _ => LineKind::Unknown } };
        Self { number, fields, kind, block: None, position: 0, zone_line: None, field_error: false, error: None }
    }
    fn accepts_continuation(&self) -> bool { self.kind == LineKind::Zone && self.fields.len() >= 6 || self.kind == LineKind::Continuation && self.fields.len() >= 4 }
}
struct Block { name: String, number: usize, lines: Vec<usize>, defined: bool }
#[derive(Clone)]
struct ZoneLine { stdoff: i64, rules_text: String, rule_set: Option<String>, save: i64, format: String, until: Option<Until>, start: i64, end: i64 }
impl ZoneLine {
    fn parse(fields: &[String]) -> Result<Self, String> {
        let stdoff = tz_parser::parse_stdoff(&fields[0])?;
        let rules_text = fields[1].clone();
        let mut rule_set = None;
        let mut save = 0;
        if rules_text.as_bytes()[0].is_ascii_digit() { save = tz_parser::parse_save(&rules_text)?; }
        else if rules_text != "-" { rule_set = Some(rules_text.clone()); }
        let format = fields[2].clone();
        tz_parser::check_format(&format, rule_set.is_some())?;
        let until = if fields.len() > 3 { Some(tz_parser::parse_until(&fields[3..])?) } else { None };
        Ok(Self { stdoff, rules_text, rule_set, save, format, until, start: NEG_INFINITY, end: POS_INFINITY })
    }
    fn rules_notation(&self) -> String { if let Some(name) = &self.rule_set { name.clone() } else if self.rules_text == "-" { "-".to_owned() } else { clock_text(self.save) } }
    fn until_notation(&self) -> String { let until = self.until.as_ref().unwrap(); format!("{} {} {} {}{}", until.year_text, until.month_text, until.day_text, clock_text(until.time), until.time_type as char) }
}
struct Zone { name: String, lines: Vec<ZoneLine>, aliases: Vec<String>, applied: HashMap<usize, usize>, timeline: Timeline }
impl Zone {
    fn rule_sets(&self) -> Vec<String> {
        let mut names = Vec::new();
        for line in &self.lines { if let Some(name) = &line.rule_set { if !names.contains(name) { names.push(name.clone()); } } }
        names
    }
    fn line_number_at(&self, time: i64) -> usize { self.lines.iter().position(|line| line.start <= time && time < line.end).unwrap() + 1 }
}
fn parse_rule(line: &SourceLine) -> Result<Rule, String> {
    let fields = &line.fields;
    let from_year = tz_parser::parse_year(&fields[2])?;
    let to_year = tz_parser::parse_to(&fields[3], from_year)?;
    if fields[4] != "-" { return Err("syntax error".to_owned()); }
    let month = tz_parser::parse_month(&fields[5])?;
    let day = tz_parser::parse_day_spec(&fields[6], month)?;
    let (at, at_type) = tz_parser::parse_time(&fields[7])?;
    let save = tz_parser::parse_save(&fields[8])?;
    let letter = tz_parser::parse_letter(&fields[9])?;
    Ok(Rule { number: line.number, name: fields[1].clone(), fields: fields.clone(), from_year, to_year, month, day, at, at_type, save, letter })
}
struct Database {
    lines: Vec<SourceLine>, blocks: Vec<Block>, rules: Vec<Rule>, rule_sets: HashMap<String, Vec<usize>>,
    rule_order: Vec<String>, sequences: HashMap<String, Vec<RuleInstance>>, zones: BTreeMap<String, Zone>, aliases: HashMap<String, String>,
}
impl Database {
    fn new(raw_lines: &[String]) -> Self {
        let lines = raw_lines.iter().enumerate().filter_map(|(i, raw)| { let content = tz_parser::line_content(raw); if content.is_empty() { None } else { Some(SourceLine::new(i + 1, content)) } }).collect();
        let mut database = Self { lines, blocks: Vec::new(), rules: Vec::new(), rule_sets: HashMap::new(), rule_order: Vec::new(), sequences: HashMap::new(), zones: BTreeMap::new(), aliases: HashMap::new() };
        database.assemble_blocks();
        for index in 0..database.lines.len() {
            if let Err(error) = database.parse_fields(index) { database.lines[index].field_error = true; database.lines[index].error = Some(error); }
        }
        let mut names = HashSet::new();
        for index in 0..database.lines.len() { if database.lines[index].zone_line.is_some() { database.lines[index].error = database.structural_error(index, &mut names); } }
        for name in &database.rule_order { database.sequences.insert(name.clone(), instance_sequence(&database.rules, &database.rule_sets[name])); }
        for block in 0..database.blocks.len() {
            let defined = database.blocks[block].lines.iter().all(|&index| database.lines[index].error.is_none());
            database.blocks[block].defined = defined;
            if defined { let zone = database.define_zone(block); database.zones.insert(zone.name.clone(), zone); }
        }
        for index in 0..database.lines.len() { if database.lines[index].kind == LineKind::Link && database.lines[index].error.is_none() { database.register_link(index); } }
        database
    }
    fn assemble_blocks(&mut self) {
        let mut previous: Option<usize> = None;
        for index in 0..self.lines.len() {
            let block = if self.lines[index].kind == LineKind::Zone {
                self.blocks.push(Block { name: self.lines[index].fields[1].clone(), number: self.lines[index].number, lines: Vec::new(), defined: false });
                Some(self.blocks.len() - 1)
            } else if self.lines[index].kind == LineKind::Continuation {
                previous.and_then(|before| if self.lines[before].accepts_continuation() { self.lines[before].block } else { None })
            } else { None };
            if let Some(block) = block { self.lines[index].block = Some(block); self.lines[index].position = self.blocks[block].lines.len(); self.blocks[block].lines.push(index); }
            previous = Some(index);
        }
    }
    fn parse_fields(&mut self, index: usize) -> Result<(), String> {
        let line = &self.lines[index];
        if line.kind == LineKind::Unknown || line.kind == LineKind::Continuation && line.block.is_none() { return Err("syntax error".to_owned()); }
        let (low, high) = match line.kind { LineKind::Rule => (10, 10), LineKind::Zone => (5, 9), LineKind::Continuation => (3, 7), LineKind::Link => (3, 3), _ => unreachable!() };
        if !(low..=high).contains(&line.fields.len()) { return Err("syntax error".to_owned()); }
        match line.kind {
            LineKind::Rule => {
                let rule = parse_rule(line)?;
                if !self.rule_sets.contains_key(&rule.name) { self.rule_order.push(rule.name.clone()); }
                self.rule_sets.entry(rule.name.clone()).or_default().push(self.rules.len()); self.rules.push(rule);
            }
            LineKind::Zone => { let parsed = ZoneLine::parse(&line.fields[2..])?; self.lines[index].zone_line = Some(parsed); }
            LineKind::Continuation => { let parsed = ZoneLine::parse(&line.fields)?; self.lines[index].zone_line = Some(parsed); }
            _ => {}
        }
        Ok(())
    }
    fn structural_error(&self, index: usize, names: &mut HashSet<String>) -> Option<String> {
        let line = &self.lines[index];
        let zone_line = line.zone_line.as_ref().unwrap();
        if line.kind == LineKind::Zone && !names.insert(line.fields[1].clone()) { return Some(format!("duplicate zone {}", line.fields[1])); }
        if let Some(name) = &zone_line.rule_set { if !self.rule_sets.contains_key(name) { return Some(format!("unknown rule {name}")); } }
        let until = zone_line.until.as_ref()?;
        let block = &self.blocks[line.block.unwrap()];
        if line.kind == LineKind::Continuation {
            let previous = &self.lines[block.lines[line.position - 1]];
            if !previous.field_error && until.value <= previous.zone_line.as_ref().unwrap().until.as_ref().unwrap().value { return Some("until not increasing".to_owned()); }
        }
        if line.position + 1 == block.lines.len() { return Some("missing continuation".to_owned()); }
        None
    }
    fn define_zone(&self, block_index: usize) -> Zone {
        let block = &self.blocks[block_index];
        let mut zone = Zone { name: block.name.clone(), lines: block.lines.iter().map(|&index| self.lines[index].zone_line.as_ref().unwrap().clone()).collect(), aliases: Vec::new(), applied: HashMap::new(), timeline: Timeline { periods: Vec::new() } };
        let mut switches = Vec::new();
        let mut start = NEG_INFINITY;
        for line in &mut zone.lines {
            line.start = start;
            let mut line_switches = Vec::new();
            if let Some(name) = &line.rule_set {
                let instances = &self.sequences[name];
                let run = run_instances(instances, &self.rules, line.stdoff, start, line.until.as_ref());
                line.end = run.end;
                let (save, letter) = if let Some(index) = run.last_pre_start { (self.rules[index].save, self.rules[index].letter.clone()) }
                    else { (0, instances.iter().find_map(|instance| { let rule = &self.rules[instance.rule]; if rule.save == 0 { Some(rule.letter.clone()) } else { None } }).unwrap_or_default()) };
                line_switches.push((start, save, letter));
                for (time, index) in run.applied {
                    let rule = &self.rules[index]; line_switches.push((time, rule.save, rule.letter.clone()));
                    *zone.applied.entry(rule.number).or_default() += 1;
                }
            } else {
                if let Some(until) = &line.until { line.end = until.value - adjustment(until.time_type, line.stdoff, line.save); }
                line_switches.push((start, line.save, String::new()));
            }
            for (time, save, letter) in line_switches { switches.push(Period { start: time, offset: line.stdoff + save, dst: save != 0, abbreviation: abbreviation(&line.format, save, &letter) }); }
            start = line.end;
        }
        let mut periods: Vec<Period> = Vec::new();
        for period in switches { if periods.last().map(|before| !before.same_state(&period)).unwrap_or(true) { periods.push(period); } }
        zone.timeline = Timeline { periods };
        zone
    }
    fn register_link(&mut self, index: usize) {
        let target = self.lines[index].fields[1].clone(); let alias = self.lines[index].fields[2].clone();
        if !self.zones.contains_key(&target) { self.lines[index].error = Some(format!("unknown link target {target}")); }
        else if self.zones.contains_key(&alias) || self.aliases.contains_key(&alias) { self.lines[index].error = Some(format!("duplicate link {alias}")); }
        else { self.aliases.insert(alias.clone(), target.clone()); self.zones.get_mut(&target).unwrap().aliases.push(alias); }
    }
    fn find_zone(&self, word: &str) -> Option<&Zone> { self.zones.get(word).or_else(|| self.aliases.get(word).and_then(|name| self.zones.get(name))) }
    fn error_lines(&self) -> Vec<String> { self.lines.iter().filter_map(|line| line.error.as_ref().map(|error| format!("line {}: {error}", line.number))).collect() }
}
fn offset_shift(timeline: &Timeline, index: usize) -> i64 { timeline.periods[index].offset - timeline.periods[index - 1].offset }
fn transitions_between(timeline: &Timeline, low: i64, high: i64) -> Vec<usize> { (1..timeline.periods.len()).filter(|&i| low <= timeline.periods[i].start && timeline.periods[i].start < high).collect() }
fn change_at(timeline: &Timeline, index: usize) -> String { change_text(timeline.periods[index].start, &timeline.periods[index - 1], &timeline.periods[index]) }
fn transition_line(timeline: &Timeline, index: usize) -> String {
    let time = timeline.periods[index].start;
    let shift = offset_shift(timeline, index);
    let kind = if shift > 0 { format!("gap {}", duration_text(shift)) } else if shift < 0 { format!("overlap {}", duration_text(-shift)) } else { "no shift".to_owned() };
    format!("{} (local {} -> {}, {kind})", change_at(timeline, index), local_text(time + timeline.periods[index - 1].offset), local_text(time + timeline.periods[index].offset))
}
fn shifts_text(timeline: &Timeline, indices: &[usize]) -> String {
    let (mut gaps, mut overlaps, mut unchanged) = (0, 0, 0);
    for &index in indices { let shift = offset_shift(timeline, index); if shift > 0 { gaps += 1; } else if shift < 0 { overlaps += 1; } else { unchanged += 1; } }
    format!("gaps {gaps}, overlaps {overlaps}, no shift {unchanged}")
}
fn candidate_text(timeline: &Timeline, local: i64, index: usize) -> String { let period = &timeline.periods[index]; format!("{} ({})", ut_text(local - period.offset), state_text(period)) }
fn chosen_candidate(candidates: &[usize], option: Option<&str>) -> Option<usize> {
    match (candidates.len(), option) { (1, _) | (2, Some("EARLIER")) => Some(candidates[0]), (2, Some("LATER")) => Some(candidates[1]), _ => None }
}
fn unresolved_text(timeline: &Timeline, local: i64, candidates: &[usize]) -> String {
    if !candidates.is_empty() { return format!("AMBIGUOUS {}", candidates.iter().map(|&index| candidate_text(timeline, local, index)).collect::<Vec<_>>().join(" or ")); }
    let index = timeline.skipping_transition(local); let time = timeline.periods[index].start;
    format!("NONEXISTENT gap {} to {} at {}", local_text(time + timeline.periods[index - 1].offset), local_text(time + timeline.periods[index].offset), ut_text(time))
}
fn working_hours(timeline: &Timeline, start: i64, end: i64) -> Vec<(i64, i64)> {
    let mut pieces = Vec::new();
    for index in timeline.nearby(start, end) {
        let period = &timeline.periods[index]; let low = (start - period.offset).max(period.start); let high = (end - period.offset).min(timeline.end_of(index));
        if low < high { pieces.push((low, high)); }
    }
    merge_intervals(pieces)
}
fn parse_value(kind: &str, word: &str) -> Option<i64> {
    let year = word[..4].parse().ok()?;
    if !(MIN_YEAR..=MAX_YEAR).contains(&year) { return None; }
    if kind == "year" { return Some(year); }
    let month: usize = word[5..7].parse().ok()?; let day = word[8..10].parse().ok()?;
    if !(1..=12).contains(&month) || day < 1 || day > days_in_month(year, month) { return None; }
    if kind == "date" { return Some(day_number(year, month, day)); }
    let hour = word[11..13].parse().ok()?; let minute = word[14..16].parse().ok()?; let second = word[17..19].parse().ok()?;
    if hour > 23 || minute > 59 || second > 59 { return None; }
    Some(time_value(year, month, day, hour, minute, second))
}
enum Argument { Zone(String), Number(i64) }
impl Argument {
    fn number(&self) -> i64 { if let Self::Number(value) = self { *value } else { unreachable!() } }
    fn zone<'a>(&self, database: &'a Database) -> &'a Zone { if let Self::Zone(name) = self { &database.zones[name] } else { unreachable!() } }
}
fn query_kinds(command: &str, count: usize) -> Vec<&'static str> {
    match command {
        "TOUTC" => vec!["zone", "local"], "TOLOCAL" | "OFFSET" => vec!["zone", "ut"],
        "CONVERT" => vec!["zone", "zone", "local"], "TRANSITIONS" => vec!["zone", "year", "year"],
        "DURATION" => vec!["zone", "local", "local"], _ => std::iter::once("date").chain(std::iter::repeat("zone").take(count - 1)).collect(),
    }
}
fn process_query(database: &Database, line: &str, work_start: i64, work_end: i64) -> Result<(String, Option<Vec<String>>), String> {
    let mut words: Vec<&str> = line.split(' ').collect(); let command = words.remove(0);
    let option = if (command == "TOUTC" || command == "CONVERT") && matches!(words.last(), Some(&"EARLIER") | Some(&"LATER")) { words.pop() } else { None };
    let mut values = Vec::new();
    for (kind, &word) in query_kinds(command, words.len()).iter().zip(&words) {
        if *kind == "zone" { let zone = database.find_zone(word).ok_or_else(|| format!("unknown zone {word}"))?; values.push(Argument::Zone(zone.name.clone())); }
        else { values.push(Argument::Number(parse_value(kind, word).ok_or_else(|| format!("invalid value {word}"))?)); }
    }
    if command == "MEETING" {
        let day = values[0].number(); let start = day * DAY + work_start; let end = day * DAY + work_end;
        let zones: Vec<&Zone> = values[1..].iter().map(|value| value.zone(database)).collect();
        let mut common = working_hours(&zones[0].timeline, start, end);
        for zone in &zones[1..] { common = intersect_intervals(&common, &working_hours(&zone.timeline, start, end)); }
        let mut parts = Vec::new();
        for (low, high) in common {
            let members = words[1..].iter().zip(&zones).map(|(word, zone)| { let period = zone.timeline.period_at(low); format!("{word} {} {}", local_text(low + period.offset), period.abbreviation) }).collect::<Vec<_>>();
            parts.push(format!("{} to {} ({}) [{}]", ut_text(low), ut_text(high), duration_text(high - low), members.join(", ")));
        }
        return Ok((if parts.is_empty() { "NONE".to_owned() } else { parts.join("; ") }, None));
    }
    if command == "CONVERT" {
        let source = values[0].zone(database); let target = values[1].zone(database); let local = values[2].number();
        let candidates = source.timeline.candidates(local);
        let Some(index) = chosen_candidate(&candidates, option) else { return Ok((unresolved_text(&source.timeline, local, &candidates), None)); };
        let time = local - source.timeline.periods[index].offset; let period = target.timeline.period_at(time);
        let target_local = time + period.offset; let shift = target_local.div_euclid(DAY) - local.div_euclid(DAY);
        let shift_text = if shift > 0 { format!("+{shift}") } else { shift.to_string() };
        return Ok((format!("{} ({}) at {}, day shift {shift_text}", local_text(target_local), state_text(period), ut_text(time)), None));
    }
    let zone = values[0].zone(database); let timeline = &zone.timeline;
    let first = values[1].number();
    let result = match command {
        "TOUTC" => {
            let candidates = timeline.candidates(first);
            if let Some(index) = chosen_candidate(&candidates, option) { candidate_text(timeline, first, index) } else { unresolved_text(timeline, first, &candidates) }
        }
        "TOLOCAL" => { let period = timeline.period_at(first); format!("{} ({})", local_text(first + period.offset), state_text(period)) }
        "OFFSET" => {
            let index = timeline.index_at(first); let mut text = state_text(&timeline.periods[index]);
            if index > 0 { text += &format!(" since {}", ut_text(timeline.periods[index].start)); }
            if index + 1 < timeline.periods.len() { text += &format!(" until {}", ut_text(timeline.periods[index + 1].start)); }
            text
        }
        "TRANSITIONS" => {
            let last = values[2].number(); if first > last { return Err("invalid range".to_owned()); }
            let selected = transitions_between(timeline, year_start(first), year_start(last + 1));
            let mut block = vec![line.to_owned()]; block.extend(selected.iter().map(|&index| transition_line(timeline, index))); block.push(shifts_text(timeline, &selected));
            return Ok((format!("transitions: {}", selected.len()), Some(block)));
        }
        "DURATION" => {
            let locals = [first, values[2].number()]; let mut offsets = Vec::new();
            for (position, &local) in locals.iter().enumerate() {
                let candidates = timeline.candidates(local);
                if candidates.len() == 2 { return Ok((format!("AMBIGUOUS {}", words[position + 1]), None)); }
                if candidates.is_empty() { return Ok((format!("NONEXISTENT {}", words[position + 1]), None)); }
                offsets.push(timeline.periods[candidates[0]].offset);
            }
            let elapsed = (locals[1] - offsets[1]) - (locals[0] - offsets[0]);
            format!("{elapsed} s ({}), wall clock {}, offset change {}", duration_text(elapsed), duration_text(locals[1] - locals[0]), offset_text(offsets[1] - offsets[0]))
        }
        _ => unreachable!(),
    };
    Ok((result, None))
}
fn rule_text(rule: &Rule) -> String { format!("rule {} {} {} {} {} {}{} {} {}", rule.name, rule.fields[2], rule.fields[3], rule.fields[5], rule.fields[6], clock_text(rule.at), rule.at_type as char, clock_text(rule.save), rule.fields[9]) }
fn database_block(database: &Database) -> Vec<String> {
    let rule_lines: Vec<&SourceLine> = database.lines.iter().filter(|line| line.kind == LineKind::Rule).collect();
    let link_lines: Vec<&SourceLine> = database.lines.iter().filter(|line| line.kind == LineKind::Link).collect();
    let valid_rules = rule_lines.iter().filter(|line| line.error.is_none()).count(); let valid_links = link_lines.iter().filter(|line| line.error.is_none()).count();
    let used: HashSet<String> = database.zones.values().flat_map(Zone::rule_sets).collect();
    let unused: Vec<String> = database.rule_order.iter().filter(|name| !used.contains(*name)).cloned().collect();
    let invalid: Vec<String> = database.blocks.iter().filter(|block| !block.defined).map(|block| format!("{} (line {})", block.name, block.number)).collect();
    let zone_lines: usize = database.zones.values().map(|zone| zone.lines.len()).sum();
    let mut lines = vec!["DATABASE".to_owned(), format!("rule lines: {valid_rules} valid, {} invalid", rule_lines.len() - valid_rules), format!("zones: {} defined, {} invalid", database.zones.len(), database.blocks.len() - database.zones.len()), format!("zone lines: {zone_lines} in defined zones"), format!("links: {valid_links} defined, {} invalid", link_lines.len() - valid_links), format!("errors: {}", database.error_lines().len()), format!("unused rules: {}", names_or_none(&unused, " ")), format!("invalid zones: {}", names_or_none(&invalid, ", "))];
    for name in &database.rule_order {
        let rules: Vec<&Rule> = database.rule_sets[name].iter().map(|&index| &database.rules[index]).collect();
        let first = rules.iter().map(|rule| rule.from_year).min().unwrap();
        let last = if rules.iter().any(|rule| rule.fields[3] == "max") { "max".to_owned() } else { rules.iter().map(|rule| rule.to_year).max().unwrap().to_string() };
        let count = database.zones.values().filter(|zone| zone.rule_sets().contains(name)).count();
        lines.push(format!("rule set {name}: lines {}, years {first}-{last}, zones {count}", rules.len()));
    }
    lines
}
fn dst_lines(timeline: &Timeline, reference: i64) -> Vec<String> {
    let indices: Vec<usize> = timeline.periods.iter().enumerate().filter(|(_, period)| period.dst).map(|(index, _)| index).collect();
    let mut lines = if indices.is_empty() { vec!["dst years: none".to_owned()] } else {
        let years: Vec<i64> = indices.iter().map(|&index| split_time(timeline.periods[index].start).0).collect();
        vec![format!("dst years: {}-{}", years.iter().min().unwrap(), years.iter().max().unwrap())]
    };
    let year = split_time(reference).0; let low = year_start(year); let high = year_start(year + 1);
    let pieces: Vec<(i64, i64)> = indices.iter().filter_map(|&index| { let start = low.max(timeline.periods[index].start); let end = high.min(timeline.end_of(index)); if start < end { Some((start, end)) } else { None } }).collect();
    let mut total = 0;
    for (start, end) in merge_intervals(pieces) { lines.push(format!("dst period: {} to {} ({})", ut_text(start), ut_text(end), duration_text(end - start))); total += end - start; }
    lines.push(format!("dst total {year}: {}", duration_text(total)));
    lines
}
fn zone_block(database: &Database, zone: &Zone, reference: i64) -> Vec<String> {
    let timeline = &zone.timeline; let periods = &timeline.periods;
    let mut lines = vec![format!("ZONE {}", zone.name), format!("aliases: {}", names_or_none(&zone.aliases, " "))];
    for (index, line) in zone.lines.iter().enumerate() {
        let mut text = format!("line {}: {} {} {}", index + 1, offset_text(line.stdoff), line.rules_notation(), line.format);
        if index > 0 { text += &format!(" from {}", ut_text(line.start)); }
        if line.until.is_some() { text += &format!(" until {} = {}", line.until_notation(), ut_text(line.end)); }
        lines.push(format!("{text}, transitions {}", transitions_between(timeline, line.start, line.end).len()));
    }
    for name in zone.rule_sets() { for &index in &database.rule_sets[&name] { let rule = &database.rules[index]; lines.push(format!("{}, applied {}", rule_text(rule), zone.applied.get(&rule.number).copied().unwrap_or(0))); } }
    lines.push(format!("offset range: {} to {}", offset_text(periods.iter().map(|period| period.offset).min().unwrap()), offset_text(periods.iter().map(|period| period.offset).max().unwrap())));
    let mut state_counts = Vec::<(String, usize)>::new();
    for period in periods { let state = state_text(period); if let Some(entry) = state_counts.iter_mut().find(|entry| entry.0 == state) { entry.1 += 1; } else { state_counts.push((state, 1)); } }
    for (state, count) in state_counts { lines.push(format!("state {state}, periods {count}")); }
    let index = timeline.index_at(reference); let period = &periods[index];
    lines.push(format!("reference: {} ({}), line {}", local_text(reference + period.offset), state_text(period), zone.line_number_at(reference)));
    lines.push(format!("previous transition: {}", if index > 0 { change_at(timeline, index) } else { "none".to_owned() }));
    lines.push(format!("next transition: {}", if index + 1 < periods.len() { change_at(timeline, index + 1) } else { "none".to_owned() }));
    let every: Vec<usize> = (1..periods.len()).collect();
    lines.push(format!("transitions: {}, {}", every.len(), shifts_text(timeline, &every)));
    lines.extend(dst_lines(timeline, reference));
    lines
}
fn main() -> io::Result<()> {
    let database = Database::new(&read_lines("tzdata.txt")?); let params = read_lines("params.txt")?;
    let reference = parse_value("ut", params[0].split(' ').nth(1).unwrap()).unwrap();
    let work: Vec<&str> = params[1].split(' ').collect(); let work_start = clock_seconds(work[1]); let work_end = clock_seconds(work[2]);
    let mut answers = Vec::new(); let mut transition_blocks = Vec::new();
    for line in read_lines("queries.txt")? {
        let outcome = process_query(&database, &line, work_start, work_end);
        let result = match outcome { Ok((result, block)) => { if let Some(block) = block { transition_blocks.push(block); } result }, Err(error) => format!("ERROR {error}") };
        answers.push(format!("{line} => {result}"));
    }
    let mut blocks = vec![indented(database_block(&database))];
    for zone in database.zones.values() { blocks.push(indented(zone_block(&database, zone, reference))); }
    fs::create_dir_all("output")?;
    write_lines("output/answers.txt", &answers)?; write_lines("output/errors.txt", &database.error_lines())?;
    write_blocks("output/transitions.txt", &transition_blocks)?; write_blocks("output/zone_summary.txt", &blocks)
}
