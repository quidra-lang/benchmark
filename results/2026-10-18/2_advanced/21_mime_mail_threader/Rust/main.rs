mod headers;
mod addresses;
mod mime;
mod dates;
mod threader;

use std::collections::{BTreeMap, BTreeSet};
use std::{fs, io};
use addresses::{Address, Mailbox, parse_address_list};
use dates::{format_utc, parse_date};
use headers::{Header, collapse_whitespace, decode_unstructured, parse_fields, parse_parameters, remove_comments, split_words};
use mime::{decode_base64_body, decode_quoted_printable};
use threader::{Threads, build_threads, root_subject};

const CHECKED_FIELDS: [&str; 12] = ["From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References", "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition"];
type Line = (usize, String);
fn read_lines(path: &str) -> io::Result<Vec<String>> {
    let text = fs::read_to_string(path)?;
    let mut lines: Vec<_> = text.split('\n').map(str::to_owned).collect();
    if lines.last().is_some_and(String::is_empty) { lines.pop(); }
    Ok(lines)
}
fn read_mailbox(lines: &[String]) -> Vec<Vec<Line>> {
    let mut messages: Vec<Vec<Line>> = Vec::new();
    for (number, line) in lines.iter().enumerate() {
        if line.starts_with("From ") { messages.push(Vec::new()); }
        else if let Some(message) = messages.last_mut() {
            let unquoted = line.trim_start_matches('>');
            let text = if unquoted.len() < line.len() && unquoted.starts_with("From ") { &line[1..] } else { line };
            message.push((number + 1, text.to_owned()));
        }
    }
    for message in &mut messages { if message.last().is_some_and(|(_, text)| text.is_empty()) { message.pop(); } }
    messages
}
fn split_sections(lines: &[Line]) -> (&[Line], &[Line]) {
    match lines.iter().position(|(_, text)| text.is_empty()) { Some(index) => (&lines[..index], &lines[index + 1..]), None => (lines, &[]) }
}
fn is_message_id(text: &str) -> bool {
    if text.len() < 3 || !text.starts_with('<') || !text.ends_with('>') { return false; }
    let inside = &text[1..text.len() - 1];
    inside.bytes().filter(|&byte| byte == b'@').count() == 1 && !inside.starts_with('@') && !inside.ends_with('@') &&
        inside.bytes().all(|byte| (33..=126).contains(&byte) && !b"<>()\"\\".contains(&byte))
}
fn extract_ids(value: &str) -> Vec<String> {
    let mut ids = Vec::new();
    let mut position = 0;
    while let Some(relative) = value[position..].find('<') {
        let start = position + relative;
        let Some(relative) = value[start + 1..].find('>') else { break; };
        let end = start + 1 + relative;
        if is_message_id(&value[start..=end]) { ids.push(value[start..=end].to_owned()); }
        position = end + 1;
    }
    ids
}
fn date_notation(seconds: Option<i64>) -> String { seconds.map(format_utc).unwrap_or_else(|| "invalid".to_owned()) }
fn subject_notation(subject: &str) -> &str { if subject.is_empty() { "(no subject)" } else { subject } }
struct Entity {
    number: String,
    main_type: String,
    subtype: String,
    parameters: BTreeMap<String, String>,
    disposition: Option<String>,
    filename: String,
    children: Option<Vec<Entity>>,
    content: String,
}
impl Entity {
    fn new(number: String) -> Self {
        Self { number, main_type: "text".to_owned(), subtype: "plain".to_owned(), parameters: BTreeMap::new(), disposition: None,
            filename: String::new(), children: None, content: String::new() }
    }
    fn parameter(&self, name: &str) -> &str { self.parameters.get(name).map_or("", String::as_str) }
}
pub struct Message {
    number: usize,
    problems: Vec<String>,
    sender: Option<Mailbox>,
    to: Vec<String>,
    cc: Vec<String>,
    subject: String,
    base_subject: String,
    reply: bool,
    date: Option<i64>,
    id: String,
    references: Vec<String>,
    body: Entity,
    thread: usize,
    depth: usize,
    parent: Option<usize>,
}
impl Message {
    fn new(number: usize) -> Self {
        Self { number, problems: Vec::new(), sender: None, to: Vec::new(), cc: Vec::new(), subject: String::new(), base_subject: String::new(),
            reply: false, date: None, id: String::new(), references: Vec::new(), body: Entity::new("1".to_owned()), thread: 0, depth: 0, parent: None }
    }
    fn sort_key(&self) -> (u8, i64, String, usize) { (u8::from(self.date.is_none()), self.date.unwrap_or(0), self.id.clone(), self.number) }
    fn process(&mut self, lines: &[Line], known_ids: &mut BTreeMap<String, usize>) {
        let (header_lines, body_lines) = split_sections(lines);
        let header = parse_fields(header_lines);
        for number in &header.invalid_lines { self.problems.push(format!("bad header line {number}")); }
        for name in CHECKED_FIELDS { if header.count(name) > 1 { self.problems.push(format!("duplicate {name}")); } }
        self.read_sender(header.value("From"));
        self.to = self.read_recipients(header.value("To"), "To");
        self.cc = self.read_recipients(header.value("Cc"), "Cc");
        let (subject, failed) = decode_unstructured(header.value("Subject").unwrap_or(""));
        self.subject = subject;
        if failed { self.problems.push("bad encoded word in Subject".to_owned()); }
        let mut base = self.subject.as_str();
        while base.len() >= 3 && base[..3].eq_ignore_ascii_case("re:") { base = base[3..].trim_start_matches(' '); self.reply = true; }
        self.base_subject = base.to_owned();
        match header.value("Date") {
            None => self.problems.push("missing Date".to_owned()),
            Some(value) => match parse_date(value) { Ok(date) => self.date = Some(date), Err(problem) => self.problems.push(problem.to_owned()) },
        }
        match header.value("Message-ID") {
            None => self.problems.push("missing Message-ID".to_owned()),
            Some(value) if !is_message_id(value) => self.problems.push("bad Message-ID".to_owned()),
            Some(value) => {
                if let Some(number) = known_ids.get(value) { self.problems.push(format!("Message-ID already used by message {number}")); }
                else { self.id = value.to_owned(); known_ids.insert(value.to_owned(), self.number); }
            }
        }
        self.references = extract_ids(header.value("References").unwrap_or(""));
        if let Some(first) = extract_ids(header.value("In-Reply-To").unwrap_or("")).first() {
            if self.references.last() != Some(first) { self.references.push(first.clone()); }
        }
        let enabled = if let Some(value) = header.value("MIME-Version") {
            let valid = remove_comments(value).is_some_and(|text| text.replace([' ', '\t'], "") == "1.0");
            if !valid { self.problems.push("bad MIME-Version".to_owned()); }
            valid
        } else { false };
        self.body = self.parse_entity("1".to_owned(), &header, body_lines, enabled);
    }
    fn read_sender(&mut self, value: Option<&str>) {
        let Some(value) = value else { self.problems.push("missing From".to_owned()); return; };
        if let Some((mut addresses, error)) = parse_address_list(value) {
            if addresses.len() == 1 {
                if let Address::Mailbox(mailbox) = addresses.remove(0) {
                    self.sender = Some(mailbox);
                    if error { self.problems.push("bad encoded word in From".to_owned()); }
                    return;
                }
            }
        }
        self.problems.push("bad From".to_owned());
    }
    fn read_recipients(&mut self, value: Option<&str>, name: &str) -> Vec<String> {
        let Some(value) = value else { return Vec::new(); };
        let Some((addresses, error)) = parse_address_list(value) else { self.problems.push(format!("bad {name}")); return Vec::new(); };
        let mut recipients = Vec::new();
        for address in addresses {
            match address { Address::Mailbox(mailbox) => recipients.push(mailbox.address), Address::Group(mailboxes) => recipients.extend(mailboxes.into_iter().map(|mailbox| mailbox.address)) }
        }
        if error { self.problems.push(format!("bad encoded word in {name}")); }
        recipients
    }
    fn parse_entity(&mut self, number: String, header: &Header, lines: &[Line], enabled: bool) -> Entity {
        let mut entity = Entity::new(number);
        if enabled {
            if let Some(value) = header.value("Content-Type") {
                if let Some(parsed) = parse_parameters(value, true) { entity.main_type = parsed.main_type; entity.subtype = parsed.subtype; entity.parameters = parsed.values; }
                else { self.problems.push(format!("bad Content-Type in part {}", entity.number)); }
            }
            if let Some(value) = header.value("Content-Disposition") {
                if let Some(parsed) = parse_parameters(value, false) { entity.disposition = Some(parsed.main_type); entity.filename = parsed.values.get("filename").cloned().unwrap_or_default(); }
                else { self.problems.push(format!("bad Content-Disposition in part {}", entity.number)); }
            }
        }
        if entity.filename.is_empty() { entity.filename = entity.parameter("name").to_owned(); }
        if entity.main_type == "text" {
            if let Some(charset) = entity.parameters.get("charset") {
                if !charset.eq_ignore_ascii_case("us-ascii") { self.problems.push(format!("unsupported charset \"{}\" in part {}", charset.to_ascii_lowercase(), entity.number)); }
            }
        }
        if enabled && entity.main_type == "multipart" {
            let boundary = entity.parameter("boundary").to_owned();
            if !boundary.is_empty() { self.split_multipart(&mut entity, lines, &boundary); return entity; }
            self.problems.push(format!("missing boundary in part {}", entity.number));
        }
        let original = lines.iter().map(|(_, text)| text.as_str()).collect::<Vec<_>>().join("\n");
        let encoding = if enabled { header.value("Content-Transfer-Encoding").unwrap_or("7bit").to_ascii_lowercase() } else { "7bit".to_owned() };
        entity.content = match encoding.as_str() {
            "base64" => decode_base64_body(&original).unwrap_or_else(|| { self.problems.push(format!("bad base64 in part {}", entity.number)); String::new() }),
            "quoted-printable" => {
                let (content, error) = decode_quoted_printable(&original);
                if error { self.problems.push(format!("bad quoted-printable in part {}", entity.number)); }
                content
            }
            _ => {
                if !["7bit", "8bit", "binary"].contains(&encoding.as_str()) { self.problems.push(format!("unknown encoding \"{encoding}\" in part {}", entity.number)); }
                original
            }
        };
        entity
    }
    fn split_multipart(&mut self, entity: &mut Entity, lines: &[Line], boundary: &str) {
        let mut parts: Vec<Vec<Line>> = Vec::new();
        let mut closed = false;
        for line in lines {
            let text = line.1.trim_end_matches([' ', '\t']);
            if text == format!("--{boundary}--") { closed = true; break; }
            if text == format!("--{boundary}") { parts.push(Vec::new()); }
            else if let Some(part) = parts.last_mut() { part.push(line.clone()); }
        }
        if parts.is_empty() { self.problems.push(format!("no parts in part {}", entity.number)); }
        else if !closed { self.problems.push(format!("unterminated multipart in part {}", entity.number)); }
        let mut children = Vec::new();
        for (index, part) in parts.iter().enumerate() {
            let (header_lines, body_lines) = split_sections(part);
            let header = parse_fields(header_lines);
            for number in &header.invalid_lines { self.problems.push(format!("bad header line {number}")); }
            children.push(self.parse_entity(format!("{}.{}", entity.number, index + 1), &header, body_lines, true));
        }
        entity.children = Some(children);
    }
}
fn collect_text_parts(entity: &Entity, allow_html: bool) -> Vec<&Entity> {
    let Some(children) = &entity.children else {
        if entity.disposition.as_deref() == Some("attachment") || entity.main_type != "text" { return Vec::new(); }
        return if entity.subtype == "plain" || entity.subtype == "html" && allow_html { vec![entity] } else { Vec::new() };
    };
    if entity.subtype == "alternative" {
        for pass in [false, true] { for child in children { let parts = collect_text_parts(child, pass); if !parts.is_empty() { return parts; } } }
        return Vec::new();
    }
    children.iter().flat_map(|child| collect_text_parts(child, allow_html)).collect()
}
fn quote_prefix(depth: usize) -> String { if depth == 0 { String::new() } else { ">".repeat(depth) + " " } }
fn wrap(text: &str, prefix: &str) -> Vec<String> {
    let mut lines = Vec::new();
    let mut current = String::new();
    for word in split_words(text) {
        if !current.is_empty() && current.len() + 1 + word.len() > 72 { lines.push(format!("{prefix}{current}")); current = word.to_owned(); }
        else { if !current.is_empty() { current.push(' '); } current.push_str(word); }
    }
    lines.push(format!("{prefix}{current}")); lines
}
struct LogicalLine { depth: usize, text: String, flowing: bool }
fn flowed_lines(content: &str, delete_space: bool) -> Vec<String> {
    if content.is_empty() { return Vec::new(); }
    let mut logical: Vec<LogicalLine> = Vec::new();
    for line in content.split('\n') {
        let text = line.trim_start_matches('>');
        let depth = line.len() - text.len();
        let text = text.strip_prefix(' ').unwrap_or(text);
        let flowing = text.ends_with(' ') && text != "-- ";
        if let Some(previous) = logical.last_mut().filter(|previous| previous.flowing && previous.depth == depth) {
            if delete_space { previous.text.pop(); }
            previous.text.push_str(text); previous.flowing = flowing;
        } else { logical.push(LogicalLine { depth, text: text.to_owned(), flowing }); }
    }
    logical.into_iter().flat_map(|line| wrap(&line.text, &quote_prefix(line.depth))).collect()
}
fn reference_value(name: &str) -> Option<char> {
    match name { "amp" => Some('&'), "lt" => Some('<'), "gt" => Some('>'), "quot" => Some('"'), "apos" => Some('\''), "nbsp" => Some(' '),
        _ => {
            let digits = name.strip_prefix('#')?;
            if !(1..=3).contains(&digits.len()) || !digits.bytes().all(|byte| byte.is_ascii_digit()) { return None; }
            let value: u8 = digits.parse::<u16>().ok()?.try_into().ok()?;
            (32..=126).contains(&value).then_some(value as char)
        }
    }
}
fn replace_references(text: &str) -> String {
    let mut result = String::new();
    let mut position = 0;
    while position < text.len() {
        if text.as_bytes()[position] == b'&' {
            if let Some(relative) = text[position + 1..].find(';') {
                let end = position + 1 + relative;
                if let Some(value) = reference_value(&text[position + 1..end]) { result.push(value); position = end + 1; continue; }
            }
        }
        result.push(text.as_bytes()[position] as char); position += 1;
    }
    result
}
fn html_blocks(content: &str) -> Vec<LogicalLine> {
    let mut blocks = Vec::new();
    let (mut depth, mut position) = (0usize, 0usize);
    let mut text = String::new();
    let mut hide: Option<String> = None;
    while position < content.len() {
        let close = if content.as_bytes()[position] == b'<' { content[position + 1..].find('>').map(|relative| position + 1 + relative) } else { None };
        let Some(close) = close else { if hide.is_none() { text.push(content.as_bytes()[position] as char); } position += 1; continue; };
        let inside = &content[position + 1..close];
        position = close + 1;
        let end_tag = inside.starts_with('/');
        let start = inside.strip_prefix('/').unwrap_or(inside);
        let length = start.bytes().take_while(u8::is_ascii_alphanumeric).count();
        let name = start[..length].to_ascii_lowercase();
        if let Some(hidden) = &hide { if end_tag && name == *hidden { hide = None; } }
        else if !end_tag && ["head", "style", "script"].contains(&name.as_str()) { hide = Some(name); }
        else if name == "br" || name == "li" && !end_tag {
            blocks.push(LogicalLine { depth, text: std::mem::take(&mut text), flowing: false });
            if name == "li" { text = "* ".to_owned(); }
        } else if ["p", "div", "ul", "ol", "table", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6"].contains(&name.as_str()) {
            blocks.push(LogicalLine { depth, text: std::mem::take(&mut text), flowing: false });
            blocks.push(LogicalLine { depth, text: String::new(), flowing: false });
            if name == "blockquote" { if end_tag { depth = depth.saturating_sub(1); } else { depth += 1; } }
        }
    }
    blocks.push(LogicalLine { depth, text, flowing: false }); blocks
}
fn html_lines(content: &str) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for block in html_blocks(content) {
        let normalized = collapse_whitespace(&block.text.replace('\n', " "));
        let text = replace_references(&normalized);
        let text = text.trim_matches(' ');
        if !text.is_empty() { lines.extend(wrap(text, &quote_prefix(block.depth))); }
        else if lines.last().is_some_and(|line| !line.is_empty()) { lines.push(String::new()); }
    }
    while lines.last().is_some_and(String::is_empty) { lines.pop(); }
    lines
}
fn display_lines(entity: &Entity) -> (&'static str, Vec<String>) {
    if entity.subtype == "html" { return ("html", html_lines(&entity.content)); }
    if entity.parameter("format").eq_ignore_ascii_case("flowed") { return ("flowed", flowed_lines(&entity.content, entity.parameter("delsp").eq_ignore_ascii_case("yes"))); }
    ("plain", if entity.content.is_empty() { Vec::new() } else { entity.content.split('\n').map(str::to_owned).collect() })
}
fn line_counts(lines: &[String]) -> (usize, usize) {
    let (mut quoted, mut signature) = (0, 0);
    for (index, line) in lines.iter().enumerate() {
        let stripped = line.trim_end_matches([' ', '\t']);
        if stripped.starts_with('>') { quoted += 1; }
        if stripped == "--" { signature = lines.len() - index - 1; }
    }
    (quoted, signature)
}
struct Thread { number: usize, root: usize, entries: Vec<(usize, String, usize)> }
impl Thread {
    fn walk(&mut self, threads: &Threads, node: usize, prefix: String, stem: String, depth: usize) {
        self.entries.push((node, prefix, depth));
        let children = &threads.containers[node].children;
        for (index, &child) in children.iter().enumerate() {
            let last = index + 1 == children.len();
            self.walk(threads, child, format!("{stem}{}", if last { "`- " } else { "+- " }), format!("{stem}{}", if last { "   " } else { "|  " }), depth + 1);
        }
    }
    fn place_messages(&self, threads: &Threads, messages: &mut [Message]) {
        for &(node, _, depth) in &self.entries {
            let container = &threads.containers[node];
            if let Some(index) = container.message {
                messages[index].thread = self.number; messages[index].depth = depth;
                messages[index].parent = container.parent.and_then(|parent| threads.containers[parent].message);
            }
        }
    }
    fn report(&self, threads: &Threads, messages: &[Message]) -> Vec<String> {
        let members: Vec<_> = self.entries.iter().filter_map(|(node, _, _)| threads.containers[*node].message.map(|index| &messages[index])).collect();
        let depth = self.entries.iter().map(|(_, _, depth)| depth).max().unwrap();
        let senders: BTreeSet<_> = members.iter().filter_map(|message| message.sender.as_ref().map(|sender| sender.address.as_str())).collect();
        let dates: Vec<_> = members.iter().filter_map(|message| message.date).collect();
        let mut lines = vec![format!("thread {} messages {} depth {depth} senders {}", self.number, members.len(), senders.len())];
        if let (Some(&first), Some(&last)) = (dates.iter().min(), dates.iter().max()) { lines.push(format!("span {} .. {}", format_utc(first), format_utc(last))); }
        else { lines.push("span -".to_owned()); }
        let subject = threads.containers[self.root].subject.as_deref().unwrap_or_else(|| root_subject(&threads.containers, messages, self.root));
        lines.push(format!("subject {}", subject_notation(subject)));
        for (node, prefix, _) in &self.entries {
            let container = &threads.containers[*node];
            let notation = if let Some(index) = container.message {
                let message = &messages[index];
                format!("[{}] {} {} {}", message.number, date_notation(message.date), message.sender.as_ref().map_or("-", |sender| sender.address.as_str()), subject_notation(&message.subject))
            } else if let Some(subject) = &container.subject { format!("[subject] {subject}") } else { format!("[missing] {}", container.id) };
            lines.push(format!("{prefix}{notation}"));
        }
        lines
    }
}
fn sender_notation(sender: Option<&Mailbox>) -> String {
    match sender { None => "-".to_owned(), Some(sender) if sender.name.is_empty() => sender.address.clone(), Some(sender) => format!("{} <{}>", sender.name, sender.address) }
}
fn entity_lines(entity: &Entity, lines: &mut Vec<String>) {
    let mut line = format!("part {} {}/{}", entity.number, entity.main_type, entity.subtype);
    if let Some(children) = &entity.children { lines.push(line); for child in children { entity_lines(child, lines); } return; }
    line.push_str(&format!(" {}", entity.content.len()));
    if let Some(disposition) = &entity.disposition { line.push_str(&format!(" {disposition}")); }
    if !entity.filename.is_empty() { line.push_str(&format!(" \"{}\"", entity.filename)); }
    lines.push(line);
}
fn message_report(message: &Message, messages: &[Message]) -> Vec<String> {
    let parent = message.parent.map(|parent| messages[parent].number.to_string()).unwrap_or_else(|| "-".to_owned());
    let mut lines = vec![format!("message {}", message.number), format!("id {}", if message.id.is_empty() { "-" } else { &message.id }),
        format!("date {}", date_notation(message.date)), format!("from {}", sender_notation(message.sender.as_ref())),
        format!("to {}", if message.to.is_empty() { "-".to_owned() } else { message.to.join(", ") }),
        format!("cc {}", if message.cc.is_empty() { "-".to_owned() } else { message.cc.join(", ") }),
        format!("subject {}", subject_notation(&message.subject)), format!("refs {}", if message.references.is_empty() { "-".to_owned() } else { message.references.join(" ") }),
        format!("thread {} depth {} parent {parent}", message.thread, message.depth)];
    entity_lines(&message.body, &mut lines); lines
}
fn body_report(request: &str, lookup: &BTreeMap<String, usize>, messages: &[Message]) -> Vec<String> {
    let mut lines = vec![format!("request {request}")];
    let Some(&index) = lookup.get(request) else { lines.push("not found".to_owned()); return lines; };
    let message = &messages[index];
    let parts = collect_text_parts(&message.body, true);
    lines.push(format!("message {} text parts {}", message.number, parts.len()));
    for part in parts {
        let (format, display) = display_lines(part);
        let (quoted, signature) = line_counts(&display);
        lines.push(format!("part {} {format} lines {} quoted {quoted} signature {signature}", part.number, display.len()));
        for line in display { let line = line.trim_end_matches([' ', '\t']); lines.push(if line.is_empty() { "|".to_owned() } else { format!("| {line}") }); }
    }
    lines
}
#[derive(Default)]
struct SenderStats { count: usize, threads: BTreeSet<usize>, first: Option<i64>, last: Option<i64>, name: String }
fn senders_report(messages: &[Message]) -> Vec<String> {
    let mut stats: BTreeMap<String, SenderStats> = BTreeMap::new();
    for message in messages {
        let Some(sender) = &message.sender else { continue; };
        let entry = stats.entry(sender.address.clone()).or_default();
        entry.count += 1; entry.threads.insert(message.thread);
        if let Some(date) = message.date { entry.first = Some(entry.first.map_or(date, |first| first.min(date))); entry.last = Some(entry.last.map_or(date, |last| last.max(date))); }
        if !sender.name.is_empty() { entry.name.clone_from(&sender.name); }
    }
    let mut entries: Vec<_> = stats.into_iter().collect();
    entries.sort_by(|(a, first), (b, second)| second.count.cmp(&first.count).then_with(|| a.cmp(b)));
    let mut lines = vec!["address,name,messages,threads,first,last".to_owned()];
    for (address, entry) in entries {
        let name = if entry.name.contains([',', '"']) { format!("\"{}\"", entry.name.replace('"', "\"\"")) } else { entry.name };
        let first = entry.first.map(format_utc).unwrap_or_else(|| "-".to_owned());
        let last = entry.last.map(format_utc).unwrap_or_else(|| "-".to_owned());
        lines.push(format!("{address},{name},{},{},{first},{last}", entry.count, entry.threads.len()));
    }
    lines
}
fn malformed_report(messages: &[Message]) -> Vec<String> {
    let flagged = messages.iter().filter(|message| !message.problems.is_empty()).count();
    let total: usize = messages.iter().map(|message| message.problems.len()).sum();
    let mut lines = vec![format!("messages {} malformed {flagged} problems {total}", messages.len())];
    for message in messages { for problem in &message.problems { lines.push(format!("message {}: {problem}", message.number)); } }
    lines
}
fn join_blocks(blocks: impl IntoIterator<Item = Vec<String>>) -> Vec<String> {
    let mut lines = Vec::new();
    for block in blocks { if !lines.is_empty() { lines.push(String::new()); } lines.extend(block); }
    lines
}
fn main() -> io::Result<()> {
    let mut messages = Vec::new();
    let mut known_ids = BTreeMap::new();
    for (index, lines) in read_mailbox(&read_lines("input/mailbox.mbox")?).iter().enumerate() {
        let mut message = Message::new(index + 1); message.process(lines, &mut known_ids); messages.push(message);
    }
    let structure = build_threads(&messages);
    let mut threads = Vec::new();
    for (index, &root) in structure.roots.iter().enumerate() {
        let mut thread = Thread { number: index + 1, root, entries: Vec::new() };
        thread.walk(&structure, root, String::new(), String::new(), 0); thread.place_messages(&structure, &mut messages); threads.push(thread);
    }
    for index in 0..messages.len() {
        let Some(parent) = messages[index].parent else { continue; };
        if let (Some(date), Some(parent_date)) = (messages[index].date, messages[parent].date) {
            if date < parent_date { let number = messages[parent].number; messages[index].problems.push(format!("dated before parent message {number}")); }
        }
    }
    let lookup = messages.iter().enumerate().filter(|(_, message)| !message.id.is_empty()).map(|(index, message)| (message.id.clone(), index)).collect();
    let requests = read_lines("input/requests.txt")?;
    let files = [("threads.txt", join_blocks(threads.iter().map(|thread| thread.report(&structure, &messages)))),
        ("messages.txt", join_blocks(messages.iter().map(|message| message_report(message, &messages)))),
        ("bodies.txt", join_blocks(requests.iter().map(|request| body_report(request, &lookup, &messages)))),
        ("senders.csv", senders_report(&messages)), ("malformed.txt", malformed_report(&messages))];
    fs::create_dir_all("output")?;
    for (name, lines) in files { fs::write(format!("output/{name}"), lines.join("\n") + "\n")?; }
    Ok(())
}
