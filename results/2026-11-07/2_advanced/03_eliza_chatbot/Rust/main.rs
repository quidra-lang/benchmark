mod script_loader;
mod linter;
mod matcher;
mod responder;
mod memory;

use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::io;
use script_loader::{Script, Keyword};
use memory::MemoryQueue;

const SOURCES: [&str; 5] = ["keyword", "memory", "question", "default", "repeat"];
const NO_ARGUMENT: [&str; 9] = [":keys", ":why", ":history", ":memory", ":forget", ":reset", ":unused", ":stats", ":undo"];
const TEXT_ARGUMENT: [&str; 4] = [":prepare", ":reflect", ":say", ":explain"];
const ONE_ARGUMENT: [&str; 5] = [":groups", ":find", ":script", ":cycles", ":coverage"];

fn normalize(text: &str) -> Vec<Vec<String>> {
    text.to_ascii_lowercase().split([',', '.', '?', '!', ';']).filter_map(|part| {
        let words: Vec<String> = part.split(|character: char| !(character.is_ascii_lowercase() || character.is_ascii_digit() || character == '\''))
            .map(|word| word.trim_matches('\'')) .filter(|word| !word.is_empty()).map(str::to_owned).collect();
        (!words.is_empty()).then_some(words)
    }).collect()
}

fn grouped(values: &[String], size: usize) -> Vec<String> { values.chunks(size).map(|chunk| chunk.join(" ")).collect() }
fn count_line(turns: usize, sources: &[usize; 5]) -> String {
    format!("turns={turns} {}", SOURCES.iter().zip(sources).map(|(source, count)| format!("{source}={count}")).collect::<Vec<_>>().join(" "))
}
fn leaders(counts: &BTreeMap<String, usize>) -> String {
    let mut entries: Vec<_> = counts.iter().filter(|(_, count)| **count > 0).collect();
    entries.sort_by(|a, b| b.1.cmp(a.1).then_with(|| a.0.cmp(b.0)));
    let values: Vec<_> = entries.into_iter().take(5).map(|(word, count)| format!("{word} {count}")).collect();
    if values.is_empty() { "none".to_owned() } else { values.join(", ") }
}
fn rule_entries(keyword: &Keyword) -> Vec<(&str, usize, usize)> {
    keyword.memories.iter().enumerate().map(|(index, &id)| ("memory", index + 1, id))
        .chain(keyword.decomps.iter().enumerate().map(|(index, &id)| ("decomp", index + 1, id))).collect()
}

#[derive(Clone)]
struct Session {
    name: String, turns: usize, sources: [usize; 5], previous: Option<Vec<Vec<String>>>, history: Vec<String>,
    last_trace: Option<Vec<String>>, trace_on: bool, topics: BTreeMap<String, usize>, words: BTreeMap<String, usize>,
    stored: usize, recalled: usize, unrecognized: Vec<usize>, undo: Option<Box<State>>,
}
impl Session {
    fn new(name: String) -> Self {
        Self { name, turns: 0, sources: [0; 5], previous: None, history: Vec::new(), last_trace: None, trace_on: false,
            topics: BTreeMap::new(), words: BTreeMap::new(), stored: 0, recalled: 0, unrecognized: Vec::new(), undo: None }
    }
}
#[derive(Clone)]
struct State {
    positions: Vec<usize>, hits: Vec<usize>, item_uses: Vec<usize>, keyword_uses: Vec<usize>, keyword_replies: Vec<usize>,
    cycles: [usize; 3], memory: MemoryQueue, session: Session,
}
struct Chatbot { script: Script, state: State, transcript: Vec<String>, total_turns: usize, total_sources: [usize; 5], sessions: usize }

impl Chatbot {
    fn new(script: Script) -> Self {
        let state = State { positions: vec![0; script.rules.len()], hits: vec![0; script.rules.len()], item_uses: vec![0; script.items.len()],
            keyword_uses: vec![0; script.keywords.len()], keyword_replies: vec![0; script.keywords.len()], cycles: [0; 3],
            memory: MemoryQueue::new(script.capacity), session: Session::new(String::new()) };
        Self { script, state, transcript: Vec::new(), total_turns: 0, total_sources: [0; 5], sessions: 0 }
    }
    fn prefix(&self) -> String { format!("{} {}", self.state.session.name, self.state.session.turns) }
    fn reset_cycles(&mut self) { self.state.positions.fill(0); self.state.cycles.fill(0); }
    fn take_text(&mut self, name: &str) -> String {
        let index = ["DEFAULT", "QUESTION", "REPEAT"].iter().position(|&value| value == name).unwrap();
        let texts = &self.script.texts[name];
        let position = self.state.cycles[index];
        self.state.cycles[index] = (position + 1) % texts.len();
        texts[position].clone()
    }
    fn take_item(&mut self, rule: usize) -> (usize, usize) {
        let position = self.state.positions[rule];
        let items = &self.script.rules[rule].items;
        let item = items[position];
        self.state.item_uses[item] += 1;
        self.state.positions[rule] = (position + 1) % items.len();
        (position + 1, item)
    }
    fn prepared(&self, clauses: &[Vec<String>]) -> Vec<Vec<String>> {
        clauses.iter().map(|clause| clause.iter().flat_map(|word| self.script.pre.get(word).cloned().unwrap_or_else(|| vec![word.clone()])).collect()).collect()
    }
    fn is_quit(&self, clauses: &[Vec<String>]) -> bool {
        let words: Vec<_> = clauses.iter().flatten().collect();
        words.len() == 1 && self.script.quit.contains(words[0])
    }
    fn select_clause(&self, clauses: &[Vec<String>]) -> Option<(usize, Vec<String>, Vec<usize>)> {
        for (number, clause) in clauses.iter().enumerate() {
            let mut found = Vec::new();
            for word in clause {
                if let Some(&id) = self.script.keyword_map.get(word) { if !found.contains(&id) { found.push(id); } }
            }
            if !found.is_empty() {
                found.sort_by_key(|&id| std::cmp::Reverse(self.script.keywords[id].rank));
                return Some((number + 1, clause.clone(), found));
            }
        }
        None
    }
    fn find_rule(&self, rules: &[usize], words: &[String]) -> Option<(usize, usize, Vec<Vec<String>>)> {
        rules.iter().enumerate().find_map(|(number, &id)| matcher::match_pattern(&self.script.rules[id].pattern, words, &self.script.group_words).map(|bindings| (number + 1, id, bindings)))
    }
    fn apply_memory(&mut self, keyword: usize, words: &[String], trace: &mut Vec<String>) {
        let Some((number, rule, bindings)) = self.find_rule(&self.script.keywords[keyword].memories, words) else { return; };
        let word = self.script.keywords[keyword].word.clone();
        trace.push(format!("MEMORY {word} {number}"));
        self.state.hits[rule] += 1;
        if self.script.rules[rule].items.is_empty() { return; }
        let (_, item) = self.take_item(rule);
        let text = responder::build_reply(&self.script.items[item].text, &bindings, &self.script.post);
        if self.state.memory.store(&self.prefix(), &word, text) { self.state.session.stored += 1; }
    }
    fn keyword_reply(&mut self, clauses: &[Vec<String>], trace: &mut Vec<String>) -> Option<String> {
        let Some((number, words, keywords)) = self.select_clause(clauses) else { trace.push("CLAUSE none".to_owned()); return None; };
        trace.push(format!("CLAUSE {number} {}", words.join(" ")));
        trace.push(format!("KEYS {}", keywords.iter().map(|&id| self.script.keywords[id].word.as_str()).collect::<Vec<_>>().join(" ")));
        self.apply_memory(keywords[0], &words, trace);
        let mut entered = HashSet::new();
        for initial in keywords {
            if entered.contains(&initial) { continue; }
            trace.push(format!("ENTER {}", self.script.keywords[initial].word));
            let mut keyword = initial;
            let mut current = words.clone();
            loop {
                entered.insert(keyword);
                self.state.keyword_uses[keyword] += 1;
                let word = self.script.keywords[keyword].word.clone();
                let Some((number, rule, bindings)) = self.find_rule(&self.script.keywords[keyword].decomps, &current) else {
                    trace.push(format!("NOMATCH {word}")); break;
                };
                self.state.hits[rule] += 1;
                if self.script.rules[rule].items.is_empty() { trace.push(format!("DECOMP {word} {number} 0")); break; }
                let (item_number, item_id) = self.take_item(rule);
                let item = &self.script.items[item_id];
                trace.push(format!("DECOMP {word} {number} {item_number}"));
                if item.kind == "REASM" {
                    self.state.keyword_replies[keyword] += 1;
                    *self.state.session.topics.entry(word).or_default() += 1;
                    return Some(responder::build_reply(&item.text, &bindings, &self.script.post));
                }
                if item.kind == "NEWKEY" { break; }
                let target = &item.arguments[0];
                let next = self.script.keyword_map.get(target).copied();
                if next.is_none_or(|id| entered.contains(&id)) { trace.push(format!("BLOCKED {target}")); break; }
                if item.kind == "RESTATE" {
                    current = responder::restate(&item.arguments[1..], &bindings);
                    trace.push(if current.is_empty() { format!("RESTATE {target}") } else { format!("RESTATE {target} {}", current.join(" ")) });
                } else { trace.push(format!("GOTO {target}")); }
                keyword = next.unwrap();
            }
        }
        None
    }
    fn decide(&mut self, text: &str) -> (String, Vec<String>) {
        let clauses = normalize(text);
        let mut trace = Vec::new();
        let (reply, source) = if !self.script.texts["REPEAT"].is_empty() && !clauses.is_empty() && self.state.session.previous.as_ref() == Some(&clauses) {
            trace.push("REPEAT".to_owned());
            (self.take_text("REPEAT"), 4)
        } else {
            let prepared = self.prepared(&clauses);
            if let Some(reply) = self.keyword_reply(&prepared, &mut trace) { (reply, 0) }
            else if !self.state.memory.texts.is_empty() { self.state.session.recalled += 1; (self.state.memory.recall(&self.prefix()), 1) }
            else if text.ends_with('?') && !self.script.texts["QUESTION"].is_empty() { (self.take_text("QUESTION"), 2) }
            else { (self.take_text("DEFAULT"), 3) }
        };
        trace.push(format!("REPLY {}", SOURCES[source]));
        self.state.session.previous = Some(clauses);
        self.state.session.sources[source] += 1;
        if source == 2 || source == 3 { self.state.session.unrecognized.push(self.state.session.turns); }
        (reply, trace)
    }
    fn respond(&mut self, text: &str) {
        let mut snapshot = self.state.clone();
        snapshot.session.undo = None;
        self.state.session.undo = Some(Box::new(snapshot));
        self.state.session.turns += 1;
        for word in normalize(text).into_iter().flatten() {
            if !self.script.stop.contains(&word) { *self.state.session.words.entry(word).or_default() += 1; }
        }
        self.state.session.history.push(format!("{}: {text}", self.state.session.turns));
        let (reply, trace) = self.decide(text);
        self.transcript.extend(responder::wrap_reply(&reply));
        self.state.session.last_trace = Some(trace.clone());
        if self.state.session.trace_on { self.transcript.extend(trace.into_iter().map(|line| format!("  {line}"))); }
    }
    fn prepare(&self, text: &str) -> Vec<String> {
        let clauses = self.prepared(&normalize(text));
        let mut lines: Vec<String> = clauses.iter().enumerate().map(|(index, clause)| format!("clause {}: {}", index + 1, clause.join(" "))).collect();
        if clauses.is_empty() { lines.push("no words".to_owned()); }
        if let Some((number, _, keys)) = self.select_clause(&clauses) {
            lines.push(format!("selected {number}"));
            lines.push(format!("keys {}", keys.iter().map(|&id| format!("{}/{}", self.script.keywords[id].word, self.script.keywords[id].rank)).collect::<Vec<_>>().join(" ")));
        } else { lines.push("selected none".to_owned()); }
        lines
    }
    fn find_word(&self, word: &str) -> Vec<String> {
        let mut lines = Vec::new();
        if let Some(&id) = self.script.keyword_map.get(word) { lines.push(format!("keyword rank {}", self.script.keywords[id].rank)); }
        for (label, entries) in [("pre", &self.script.pres), ("post", &self.script.posts)] {
            for entry in entries {
                if entry.source == word || entry.replacement.iter().any(|value| value == word) { lines.push(format!("{label} {}: {} -> {}", entry.line, entry.source, entry.replacement.join(" "))); }
            }
        }
        for group in &self.script.groups { if group.members.contains(word) { lines.push(format!("group {} line {}", group.name, group.line)); } }
        for keyword in &self.script.keywords {
            for (label, number, id) in rule_entries(keyword) {
                if self.script.rules[id].pattern.iter().any(|element| element == word) { lines.push(format!("pattern {} {label} {number}", keyword.word)); }
            }
        }
        if self.script.stop.contains(word) { lines.push("stop word".to_owned()); }
        if self.script.quit.contains(word) { lines.push("quit word".to_owned()); }
        if lines.is_empty() { lines.push("not found".to_owned()); }
        lines
    }
    fn command(&mut self, line: &str) -> Vec<String> {
        let (name, text) = line.split_once(' ').unwrap_or((line, ""));
        let args: Vec<&str> = text.split_whitespace().collect();
        if !NO_ARGUMENT.contains(&name) && !TEXT_ARGUMENT.contains(&name) && !ONE_ARGUMENT.contains(&name) && !matches!(name, ":trace" | ":test") { return vec![format!("unknown command {name}")]; }
        if NO_ARGUMENT.contains(&name) && !args.is_empty() || TEXT_ARGUMENT.contains(&name) && text.is_empty()
            || ONE_ARGUMENT.contains(&name) && args.len() != 1 || name == ":trace" && (args.len() != 1 || !matches!(args[0], "on" | "off"))
            || name == ":test" && args.len() < 2 { return vec!["bad arguments".to_owned()]; }
        let keyword = args.first().and_then(|word| self.script.keyword_map.get(*word)).copied();
        if matches!(name, ":script" | ":cycles" | ":coverage" | ":test") && keyword.is_none() { return vec![format!("unknown keyword {}", args[0])]; }
        match name {
            ":prepare" => self.prepare(text),
            ":reflect" => {
                let clauses = self.prepared(&normalize(text));
                if clauses.is_empty() { vec!["no words".to_owned()] } else { clauses.iter().map(|clause| responder::reflect(clause, &self.script.post).join(" ")).collect() }
            }
            ":test" => {
                let words: Vec<String> = self.prepared(&normalize(text.split_once(' ').unwrap().1)).into_iter().flatten().collect();
                let mut lines = Vec::new();
                for (label, number, id) in rule_entries(&self.script.keywords[keyword.unwrap()]) {
                    let result = match matcher::match_pattern(&self.script.rules[id].pattern, &words, &self.script.group_words) {
                        None => "no match".to_owned(), Some(bindings) if bindings.is_empty() => "match".to_owned(),
                        Some(bindings) => bindings.iter().map(|binding| format!("[{}]", binding.join(" "))).collect::<Vec<_>>().join(" "),
                    };
                    lines.push(format!("{label} {number}: {result}"));
                }
                if lines.is_empty() { vec!["no rules".to_owned()] } else { lines }
            }
            ":keys" => {
                let mut keys: Vec<_> = self.script.keywords.iter().collect();
                keys.sort_by(|a, b| b.rank.cmp(&a.rank).then_with(|| a.word.cmp(&b.word)));
                grouped(&keys.iter().map(|key| format!("{}/{}", key.word, key.rank)).collect::<Vec<_>>(), 8)
            }
            ":groups" => {
                let mut groups: Vec<_> = self.script.groups.iter().filter(|group| group.members.contains(text)).map(|group| group.name.clone()).collect();
                groups.sort();
                vec![if groups.is_empty() { "none".to_owned() } else { groups.join(" ") }]
            }
            ":find" => self.find_word(text),
            ":script" => {
                let key = &self.script.keywords[keyword.unwrap()];
                let mut numbers = vec![key.line];
                for (_, _, id) in rule_entries(key) {
                    numbers.push(self.script.rules[id].line);
                    numbers.extend(self.script.rules[id].items.iter().map(|&item| self.script.items[item].line));
                }
                numbers.sort();
                numbers.into_iter().map(|number| format!("{number} {}", self.script.lines[number - 1])).collect()
            }
            ":why" => self.state.session.last_trace.clone().unwrap_or_else(|| vec!["no reply yet".to_owned()]),
            ":trace" => { self.state.session.trace_on = text == "on"; vec![format!("trace {text}")] }
            ":history" => { let history = &self.state.session.history; if history.is_empty() { vec!["no turns yet".to_owned()] } else { history[history.len().saturating_sub(5)..].to_vec() } }
            ":memory" => {
                let mut lines = vec![format!("memory {}/{}", self.state.memory.texts.len(), self.script.capacity)];
                lines.extend(self.state.memory.texts.iter().enumerate().map(|(index, text)| format!("{}: {text}", index + 1)));
                lines
            }
            ":forget" => { let prefix = self.prefix(); vec![format!("forgot {}", self.state.memory.clear(&prefix))] }
            ":cycles" | ":coverage" => {
                let mut lines = Vec::new();
                for (label, number, id) in rule_entries(&self.script.keywords[keyword.unwrap()]) {
                    let rule = &self.script.rules[id];
                    let detail = if name == ":coverage" {
                        let uses = rule.items.iter().map(|&item| self.state.item_uses[item].to_string()).collect::<Vec<_>>().join(" ");
                        format!("hits {} entries {}", self.state.hits[id], if uses.is_empty() { "-" } else { &uses })
                    } else if rule.items.is_empty() { "empty".to_owned() }
                    else { format!("next {}/{}", self.state.positions[id] + 1, rule.items.len()) };
                    lines.push(format!("{label} {number}: {detail}"));
                }
                if lines.is_empty() { vec!["no rules".to_owned()] } else { lines }
            }
            ":reset" => { self.reset_cycles(); vec!["cycles reset".to_owned()] }
            ":unused" => {
                let mut numbers: Vec<_> = self.script.items.iter().enumerate().filter(|(index, _)| self.state.item_uses[*index] == 0).map(|(_, item)| item.line).collect();
                numbers.sort();
                let mut lines = vec![format!("unused {}", numbers.len())];
                lines.extend(grouped(&numbers.iter().map(ToString::to_string).collect::<Vec<_>>(), 12));
                lines
            }
            ":stats" => vec![count_line(self.state.session.turns, &self.state.session.sources)],
            ":say" | ":explain" => {
                if self.is_quit(&normalize(text)) { return vec!["would quit".to_owned()]; }
                let saved = self.state.clone();
                let (reply, trace) = self.decide(text);
                self.state = saved;
                if name == ":say" { vec![reply] } else { trace }
            }
            _ => {
                if let Some(snapshot) = self.state.session.undo.take() { self.state = *snapshot; vec![format!("undone turn {}", self.state.session.turns + 1)] }
                else { vec!["nothing to undo".to_owned()] }
            }
        }
    }
    fn notes(&mut self) {
        let session = &self.state.session;
        self.transcript.extend([
            format!("NOTES {}", session.name), format!("  {}", count_line(session.turns, &session.sources)),
            format!("  topics: {}", leaders(&session.topics)), format!("  words: {}", leaders(&session.words)),
            format!("  memory: stored={} recalled={} pending={}", session.stored, session.recalled, self.state.memory.texts.len()),
            format!("  unrecognized: {}", if session.unrecognized.is_empty() { "none".to_owned() } else { session.unrecognized.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ") }),
        ]);
        self.total_turns += session.turns;
        for index in 0..5 { self.total_sources[index] += session.sources[index]; }
    }
    fn run(&mut self, lines: Vec<String>) {
        for line in lines {
            if let Some(name) = line.strip_prefix("SESSION ") {
                if self.sessions > 0 {
                    self.transcript.push(String::new());
                    if !self.script.persist.contains("cycles") { self.reset_cycles(); }
                    if !self.script.persist.contains("memory") { self.state.memory.clear(&format!("{name} 0")); }
                }
                self.sessions += 1;
                self.state.session = Session::new(name.to_owned());
                self.transcript.push(line.clone());
                let texts = &self.script.texts["INITIAL"];
                self.transcript.extend(responder::wrap_reply(&texts[(self.sessions - 1) % texts.len()]));
            } else if line.starts_with(':') {
                self.transcript.push(line.clone());
                let output = self.command(&line);
                self.transcript.extend(output.into_iter().map(|text| format!("  {text}")));
            } else {
                self.transcript.push(format!("YOU: {line}"));
                if self.is_quit(&normalize(&line)) {
                    let texts = &self.script.texts["FINAL"];
                    self.transcript.extend(responder::wrap_reply(&texts[(self.sessions - 1) % texts.len()]));
                    self.notes();
                } else { self.respond(&line); }
            }
        }
        self.transcript.push(String::new());
        self.transcript.push(format!("SUMMARY sessions={} {}", self.sessions, count_line(self.total_turns, &self.total_sources)));
    }
    fn keyword_stats(&self) -> Vec<String> {
        let mut indices: Vec<_> = (0..self.script.keywords.len()).collect();
        indices.sort_by(|&a, &b| self.state.keyword_uses[b].cmp(&self.state.keyword_uses[a]).then_with(|| self.script.keywords[a].word.cmp(&self.script.keywords[b].word)));
        let mut lines = vec!["keyword,rank,uses,replies,decomposition_hits".to_owned()];
        for id in indices {
            let keyword = &self.script.keywords[id];
            let hits = keyword.decomps.iter().map(|&rule| self.state.hits[rule].to_string()).collect::<Vec<_>>().join("/");
            lines.push(format!("{},{},{},{},{}", keyword.word, keyword.rank, self.state.keyword_uses[id], self.state.keyword_replies[id], if hits.is_empty() { "-" } else { &hits }));
        }
        lines
    }
}

fn read_lines(path: &str) -> io::Result<Vec<String>> { Ok(fs::read_to_string(path)?.split_terminator('\n').map(str::to_owned).collect()) }
fn write_lines(name: &str, lines: &[String]) -> io::Result<()> {
    fs::write(format!("output/{name}"), if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" })
}
fn main() -> io::Result<()> {
    let script = script_loader::load_script(read_lines("input/script.txt")?);
    fs::create_dir_all("output")?;
    write_lines("lint.txt", &linter::lint(&script))?;
    let mut chatbot = Chatbot::new(script);
    chatbot.run(read_lines("input/dialogue.txt")?);
    write_lines("transcript.txt", &chatbot.transcript)?;
    write_lines("keyword_stats.csv", &chatbot.keyword_stats())?;
    write_lines("memory_log.txt", &chatbot.state.memory.log)
}
