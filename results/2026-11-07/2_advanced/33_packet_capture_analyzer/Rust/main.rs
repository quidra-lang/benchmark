mod dns_app;
mod flows;
mod hexdump;
mod link_network;
mod transport;

use std::collections::BTreeMap;
use std::fs;

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum Value {
    Number(i64),
    Text(String),
    Present,
}

pub struct Packet {
    number: i64,
    time: i64,
    length: i64,
    bytes: Vec<u8>,
    layers: Vec<String>,
    fields: BTreeMap<String, Vec<Value>>,
    reason: Option<String>,
    remaining: Vec<u8>,
    duplicate: Option<(i64, i64)>,
    answers: Vec<(i64, String)>,
}

impl Packet {
    pub fn new(number: i64, time: i64, length: i64) -> Self {
        Self {
            number, time, length, bytes: Vec::new(), layers: Vec::new(), fields: BTreeMap::new(),
            reason: None, remaining: Vec::new(), duplicate: None, answers: Vec::new(),
        }
    }

    pub fn has(&self, name: &str) -> bool {
        self.fields.get(name).is_some_and(|values| !values.is_empty())
    }

    pub fn optional_num(&self, name: &str) -> Option<i64> {
        match self.fields.get(name)?.first()? { Value::Number(n) => Some(*n), _ => None }
    }

    pub fn num(&self, name: &str) -> i64 {
        self.optional_num(name).unwrap_or(0)
    }

    pub fn text(&self, name: &str) -> &str {
        match self.fields.get(name).and_then(|v| v.first()) { Some(Value::Text(text)) => text, _ => "" }
    }

    pub fn set_num(&mut self, name: &str, value: i64) {
        self.fields.insert(name.into(), vec![Value::Number(value)]);
    }

    pub fn set_text(&mut self, name: &str, value: &str) {
        self.fields.insert(name.into(), vec![Value::Text(value.into())]);
    }

    pub fn present(&mut self, name: &str) {
        self.fields.insert(name.into(), vec![Value::Present]);
    }

    pub fn append_text(&mut self, name: &str, value: String) {
        self.fields.entry(name.into()).or_default().push(Value::Text(value));
    }

    pub fn append_num(&mut self, name: &str, value: i64) {
        self.fields.entry(name.into()).or_default().push(Value::Number(value));
    }

    fn values(&self, name: &str) -> Vec<Value> {
        if ["eth", "arp", "ip", "icmp", "udp", "tcp", "dns", "data"].contains(&name) {
            return if self.layers.iter().any(|layer| layer == name) { vec![Value::Present] } else { Vec::new() };
        }
        let alias = match name {
            "eth.addr" => Some(("eth.dst", "eth.src")),
            "ip.addr" => Some(("ip.src", "ip.dst")),
            "udp.port" => Some(("udp.srcport", "udp.dstport")),
            "tcp.port" => Some(("tcp.srcport", "tcp.dstport")),
            _ => None,
        };
        if let Some((a, b)) = alias {
            let mut values = self.values(a);
            values.extend(self.values(b));
            values
        } else {
            self.fields.get(name).cloned().unwrap_or_default()
        }
    }
}

pub fn seconds(time: i64) -> String {
    format!("{}.{:06}", time / 1_000_000, time % 1_000_000)
}

fn fields() -> Vec<(&'static str, &'static str)> {
    concat!(
        "frame.number:n frame.time:n frame.len:n frame.protocols:s frame.malformed:s frame.bad_checksum:p ",
        "eth.dst:m eth.src:m eth.type:h4 ",
        "arp.opcode:n arp.src.hw:m arp.src.ip:i arp.dst.hw:m arp.dst.ip:i ",
        "ip.hdr_len:n ip.tos:h2 ip.len:n ip.id:h4 ip.flags.df:n ip.flags.mf:n ip.frag_offset:n ip.ttl:n ip.proto:n ip.checksum:h4 ip.checksum.status:s ip.src:i ip.dst:i ip.fragment:p ",
        "icmp.type:n icmp.code:n icmp.checksum:h4 icmp.checksum.status:s icmp.id:n icmp.seq:n ",
        "udp.srcport:n udp.dstport:n udp.length:n udp.checksum:h4 udp.checksum.status:s ",
        "tcp.srcport:n tcp.dstport:n tcp.stream:n tcp.seq:n tcp.seq_raw:n tcp.ack:n tcp.ack_raw:n tcp.hdr_len:n tcp.flags:h2 tcp.flags.fin:n tcp.flags.syn:n tcp.flags.rst:n tcp.flags.psh:n tcp.flags.ack:n tcp.flags.urg:n tcp.window:n tcp.window.calc:n tcp.checksum:h4 tcp.checksum.status:s tcp.urgent:n tcp.option:s tcp.options.mss:n tcp.options.wscale:n tcp.options.malformed:p tcp.len:n tcp.analysis.retransmission:p tcp.analysis.out_of_order:p tcp.analysis.lost_segment:p tcp.analysis.duplicate_ack:p ",
        "dns.id:h4 dns.flags:h4 dns.flags.response:n dns.flags.opcode:n dns.flags.rcode:n dns.count.queries:n dns.count.answers:n dns.count.auth_rr:n dns.count.add_rr:n dns.qry.name:s dns.qry.type:n dns.answer:s dns.authority:s dns.additional:s dns.a:i data.len:n"
    ).split_whitespace().map(|part| part.split_once(':').unwrap()).collect()
}

fn field_type(name: &str) -> Option<&'static str> {
    match name {
        "eth.addr" => Some("m"), "ip.addr" => Some("i"), "udp.port" | "tcp.port" => Some("n"),
        "eth" | "arp" | "ip" | "icmp" | "udp" | "tcp" | "dns" | "data" => Some("p"),
        _ => fields().into_iter().find(|&(field, _)| field == name).map(|(_, kind)| kind),
    }
}

fn notation(value: &Value, kind: &str) -> String {
    match value {
        Value::Text(text) => text.clone(),
        Value::Present => String::new(),
        Value::Number(n) => match kind {
            "h2" => format!("0x{n:02x}"), "h4" => format!("0x{n:04x}"),
            "i" => link_network::ipv4(*n), "m" => link_network::mac(*n), _ => n.to_string(),
        },
    }
}

fn shown(packet: &Packet, name: &str) -> String {
    packet.values(name).first().map(|v| notation(v, field_type(name).unwrap())).unwrap_or_default()
}

fn dissect(packet: &mut Packet, origin: i64) {
    if packet.reason.is_none() {
        let mut data = packet.bytes.clone();
        let mut layer = "eth";
        loop {
            packet.layers.push(layer.into());
            let result = match layer {
                "eth" => link_network::ethernet(packet, &data),
                "arp" => link_network::arp(packet, &data),
                "ip" => link_network::ipv4_layer(packet, &data),
                "icmp" => transport::icmp(packet, &data),
                "udp" => transport::udp(packet, &data),
                "tcp" => transport::tcp(packet, &data),
                "dns" => dns_app::dissect(packet, &data),
                _ => unreachable!(),
            };
            match result {
                Err(reason) => {
                    packet.reason = Some(reason);
                    break;
                }
                Ok(payload) => data = payload,
            }
            let next = match layer {
                "eth" => match packet.num("eth.type") { 2054 => Some("arp"), 2048 => Some("ip"), _ => None },
                "ip" if !packet.has("ip.fragment") => match packet.num("ip.proto") { 1 => Some("icmp"), 17 => Some("udp"), 6 => Some("tcp"), _ => None },
                "udp" if packet.num("udp.srcport") == 53 || packet.num("udp.dstport") == 53 => Some("dns"),
                _ => None,
            };
            if let Some(next) = next {
                layer = next;
            } else {
                if !data.is_empty() {
                    packet.layers.push("data".into());
                    packet.set_num("data.len", data.len() as i64);
                    packet.remaining = data;
                }
                break;
            }
        }
    }
    packet.set_num("frame.number", packet.number);
    packet.set_num("frame.time", packet.time - origin);
    packet.set_num("frame.len", packet.length);
    if !packet.layers.is_empty() { packet.set_text("frame.protocols", &packet.layers.join(":")); }
    if let Some(reason) = packet.reason.clone() { packet.set_text("frame.malformed", &reason); }
    if ["ip", "icmp", "udp", "tcp"].iter().any(|layer| packet.text(&format!("{layer}.checksum.status")) == "bad") {
        packet.present("frame.bad_checksum");
    }
}

fn summary(packet: &Packet) -> String {
    let (source, destination) = if packet.has("ip.src") { (shown(packet, "ip.src"), shown(packet, "ip.dst")) }
        else if packet.has("eth.src") { (shown(packet, "eth.src"), shown(packet, "eth.dst")) }
        else { ("-".into(), "-".into()) };
    let layer = packet.layers.iter().rev().find(|layer| layer.as_str() != "data").map(String::as_str).unwrap_or("");
    let protocol = match layer { "eth" => "ETH", "arp" => "ARP", "ip" => "IPv4", "icmp" => "ICMP", "udp" => "UDP", "tcp" => "TCP", "dns" => "DNS", _ => "DUMP" };
    let mut info = if let Some(reason) = &packet.reason { reason.clone() } else {
        match layer {
            "eth" => format!("EtherType {}", shown(packet, "eth.type")),
            "arp" => match packet.num("arp.opcode") {
                1 => format!("Who has {}? Tell {}", shown(packet, "arp.dst.ip"), shown(packet, "arp.src.ip")),
                2 => format!("{} is at {}", shown(packet, "arp.src.ip"), shown(packet, "arp.src.hw")),
                n => format!("Opcode {n}"),
            },
            "ip" if packet.has("ip.fragment") => format!("Fragment id={} off={}{}", shown(packet, "ip.id"), packet.num("ip.frag_offset"), if packet.num("ip.flags.mf") == 1 { " MF" } else { "" }),
            "ip" => format!("Protocol {}", packet.num("ip.proto")),
            "icmp" => match packet.num("icmp.type") {
                0 | 8 => format!("Echo {} id={} seq={}", if packet.num("icmp.type") == 8 { "request" } else { "reply" }, packet.num("icmp.id"), packet.num("icmp.seq")),
                n => format!("Type {n} code {}", packet.num("icmp.code")),
            },
            "udp" => format!("{} -> {} Len={}", packet.num("udp.srcport"), packet.num("udp.dstport"), packet.num("udp.length") - 8),
            "tcp" => tcp_summary(packet),
            "dns" => {
                let mut text = format!("{} {}", if packet.num("dns.flags.response") == 1 { "Response" } else { "Query" }, shown(packet, "dns.id"));
                if packet.num("dns.flags.rcode") != 0 { text.push_str(&format!(" {}", dns_app::rcode_name(packet.num("dns.flags.rcode")))); }
                for (name, kind) in packet.values("dns.qry.name").iter().zip(packet.values("dns.qry.type")) {
                    if let (Value::Text(name), Value::Number(kind)) = (name, kind) { text.push_str(&format!(" {} {}", dns_app::type_name(kind), name)); }
                }
                for (kind, data) in &packet.answers { text.push_str(&format!(" {} {}", dns_app::type_name(*kind), data)); }
                text
            }
            _ => String::new(),
        }
    };
    if packet.has("tcp.options.malformed") { info.push_str(" [bad TCP options]"); }
    for (layer, name) in [("ip", "IPv4"), ("icmp", "ICMP"), ("udp", "UDP"), ("tcp", "TCP")] {
        if packet.text(&format!("{layer}.checksum.status")) == "bad" { info.push_str(&format!(" [bad {name} checksum]")); }
    }
    format!("{} {} {} -> {} {} {} {}", packet.number, seconds(packet.num("frame.time")), source, destination, protocol, packet.length, info)
}

fn tcp_summary(packet: &Packet) -> String {
    let mark = if packet.has("tcp.analysis.retransmission") { "[TCP Retransmission] ".into() }
        else if packet.has("tcp.analysis.out_of_order") { "[TCP Out-Of-Order] ".into() }
        else if packet.has("tcp.analysis.lost_segment") { "[TCP Previous segment not captured] ".into() }
        else if let Some((number, count)) = packet.duplicate { format!("[TCP Dup ACK {number}#{count}] ") }
        else { String::new() };
    let flags = packet.num("tcp.flags");
    let names: Vec<_> = ["FIN", "SYN", "RST", "PSH", "ACK", "URG", "ECE", "CWR"].iter().enumerate().filter(|(bit, _)| flags & (1 << bit) != 0).map(|(_, &name)| name).collect();
    let names = if names.is_empty() { "<None>".into() } else { names.join(", ") };
    let mut text = format!("{mark}{} -> {} [{names}] Seq={}", packet.num("tcp.srcport"), packet.num("tcp.dstport"), packet.num("tcp.seq"));
    if flags & 16 != 0 { text.push_str(&format!(" Ack={}", packet.num("tcp.ack"))); }
    text.push_str(&format!(" Win={} Len={}", packet.num("tcp.window.calc"), packet.num("tcp.len")));
    for option in packet.values("tcp.option") {
        if let Value::Text(option) = option {
            let parts: Vec<_> = option.split(' ').collect();
            match parts[0] {
                "MSS" => text.push_str(&format!(" MSS={}", parts[1])),
                "WS" => text.push_str(&format!(" WS={}", 1_i64 << parts[1].parse::<u32>().unwrap())),
                "SACK_PERM" => text.push_str(" SACK_PERM"),
                "TS" => text.push_str(&format!(" TSval={} TSecr={}", parts[1], parts[2])),
                _ => (),
            }
        }
    }
    text
}

#[derive(Clone)]
struct Token {
    kind: String,
    text: String,
    column: usize,
}

fn tokenize(expression: &str) -> Result<Vec<Token>, String> {
    let bytes = expression.as_bytes();
    let mut i = 0;
    let mut tokens = Vec::new();
    while i < bytes.len() {
        if bytes[i] == b' ' { i += 1; continue; }
        let start = i;
        let two = expression.get(i..i + 2).unwrap_or("");
        let kind;
        if ["==", "!=", "<=", ">=", "&&", "||"].contains(&two) {
            kind = two.to_string();
            i += 2;
        } else if b"()!<>".contains(&bytes[i]) {
            kind = (bytes[i] as char).to_string();
            i += 1;
        } else if bytes[i] == b'"' {
            i += 1;
            while i < bytes.len() && bytes[i] != b'"' { i += 1; }
            if i == bytes.len() { return Err(format!("unterminated string at column {}", start + 1)); }
            i += 1;
            kind = "string".into();
        } else if bytes[i].is_ascii_alphanumeric() || b"._:".contains(&bytes[i]) {
            while i < bytes.len() && (bytes[i].is_ascii_alphanumeric() || b"._:".contains(&bytes[i])) { i += 1; }
            kind = match &expression[start..i] { "and" => "&&", "or" => "||", "not" => "!", _ => "word" }.into();
        } else {
            return Err(format!("invalid character '{}' at column {}", bytes[i] as char, i + 1));
        }
        tokens.push(Token { kind, text: expression[start..i].into(), column: start + 1 });
    }
    Ok(tokens)
}

enum Expression {
    Test(String, Option<(String, Value)>),
    Not(Box<Expression>),
    And(Box<Expression>, Box<Expression>),
    Or(Box<Expression>, Box<Expression>),
}

impl Expression {
    fn evaluate(&self, packet: &Packet) -> bool {
        match self {
            Self::Not(child) => !child.evaluate(packet),
            Self::And(a, b) => a.evaluate(packet) && b.evaluate(packet),
            Self::Or(a, b) => a.evaluate(packet) || b.evaluate(packet),
            Self::Test(field, comparison) => {
                let values = packet.values(field);
                let Some((operator, target)) = comparison else { return !values.is_empty(); };
                if values.is_empty() { return false; }
                if operator == "!=" { return values.iter().all(|value| value != target); }
                values.iter().any(|value| match operator.as_str() {
                    "==" => value == target, "<" => value < target, ">" => value > target,
                    "<=" => value <= target, ">=" => value >= target, _ => false,
                })
            }
        }
    }
}

struct Parser {
    tokens: Vec<Token>,
    position: usize,
}

fn unexpected(token: &Token) -> String {
    format!("unexpected '{}' at column {}", token.text, token.column)
}

impl Parser {
    fn next_is(&self, kind: &str) -> bool {
        self.tokens.get(self.position).is_some_and(|token| token.kind == kind)
    }

    fn take(&mut self) -> Result<Token, String> {
        let token = self.tokens.get(self.position).cloned().ok_or("unexpected end of filter")?;
        self.position += 1;
        Ok(token)
    }

    fn expression(&mut self) -> Result<Expression, String> {
        let mut result = self.product()?;
        while self.next_is("||") {
            self.take()?;
            result = Expression::Or(Box::new(result), Box::new(self.product()?));
        }
        Ok(result)
    }

    fn product(&mut self) -> Result<Expression, String> {
        let mut result = self.negation()?;
        while self.next_is("&&") {
            self.take()?;
            result = Expression::And(Box::new(result), Box::new(self.negation()?));
        }
        Ok(result)
    }

    fn negation(&mut self) -> Result<Expression, String> {
        if self.next_is("!") {
            self.take()?;
            return Ok(Expression::Not(Box::new(self.negation()?)));
        }
        let token = self.take()?;
        if token.kind == "(" {
            let result = self.expression()?;
            let close = self.take()?;
            if close.kind != ")" { return Err(unexpected(&close)); }
            return Ok(result);
        }
        if token.kind != "word" { return Err(unexpected(&token)); }
        let field = token.text;
        let kind = field_type(&field).ok_or_else(|| format!("unknown field {field}"))?;
        let comparison = self.tokens.get(self.position).filter(|t| ["==", "!=", "<", ">", "<=", ">="].contains(&t.kind.as_str()));
        if comparison.is_none() { return Ok(Expression::Test(field, None)); }
        let operator = self.take()?.text;
        if kind == "p" || (kind == "s" && operator != "==" && operator != "!=") {
            return Err(format!("operator {operator} not allowed for {field}"));
        }
        let value = self.take()?;
        if value.kind != "word" && value.kind != "string" { return Err(unexpected(&value)); }
        let converted = convert(&value, kind).ok_or_else(|| format!("invalid value {} for {field}", value.text))?;
        Ok(Expression::Test(field, Some((operator, converted))))
    }
}

fn convert(token: &Token, kind: &str) -> Option<Value> {
    let text = &token.text;
    if kind == "s" {
        return (token.kind == "string").then(|| Value::Text(text[1..text.len() - 1].into()));
    }
    if token.kind != "word" { return None; }
    let number = match kind {
        "n" | "h2" | "h4" => {
            if (1..=15).contains(&text.len()) && text.bytes().all(|b| b.is_ascii_digit()) { text.parse().ok() }
            else if let Some(hex) = text.strip_prefix("0x") {
                if (1..=12).contains(&hex.len()) && hex.bytes().all(|b| b.is_ascii_hexdigit()) { i64::from_str_radix(hex, 16).ok() } else { None }
            } else { None }
        }
        "i" | "m" => {
            let parts: Vec<_> = text.split(if kind == "i" { '.' } else { ':' }).collect();
            let expected = if kind == "i" { 4 } else { 6 };
            if parts.len() != expected { return None; }
            let mut value = 0_i64;
            for part in parts {
                let byte = if kind == "i" {
                    if part.is_empty() || part.len() > 3 || !part.bytes().all(|b| b.is_ascii_digit()) { return None; }
                    part.parse::<i64>().ok()?
                } else {
                    if part.len() != 2 || !part.bytes().all(|b| b.is_ascii_hexdigit()) { return None; }
                    i64::from_str_radix(part, 16).ok()?
                };
                if byte > 255 { return None; }
                value = value * 256 + byte;
            }
            Some(value)
        }
        _ => None,
    }?;
    Some(Value::Number(number))
}

fn parse_filter(text: &str) -> Result<Expression, String> {
    let mut parser = Parser { tokens: tokenize(text)?, position: 0 };
    let expression = parser.expression()?;
    if let Some(token) = parser.tokens.get(parser.position) { return Err(unexpected(token)); }
    Ok(expression)
}

fn details(packet: &Packet) -> Vec<String> {
    let mut lines = vec![format!("packet {}", packet.number)];
    let order = fields();
    for layer in std::iter::once("frame").chain(packet.layers.iter().map(String::as_str)) {
        lines.push(layer.into());
        let prefix = format!("{layer}.");
        for &(field, kind) in &order {
            if field.starts_with(&prefix) {
                for value in packet.values(field) {
                    lines.push(if kind == "p" { format!("  {field}") } else { format!("  {field} = {}", notation(&value, kind)) });
                }
            }
        }
        if layer == "data" { lines.extend(hexdump::dump(&packet.remaining).into_iter().map(|line| format!("  {line}"))); }
    }
    lines
}

fn statistics(packets: &[Packet]) -> Vec<String> {
    let mut lines = vec![format!("packets {}", packets.len()), format!("bytes {}", packets.iter().map(|p| p.length).sum::<i64>()), format!("duration {}", seconds(packets.last().unwrap().time - packets[0].time)), "hierarchy".into()];
    for (layer, indent) in [("eth", ""), ("arp", "  "), ("ip", "  "), ("icmp", "    "), ("udp", "    "), ("dns", "      "), ("tcp", "    ")] {
        let included: Vec<_> = packets.iter().filter(|p| p.layers.iter().any(|l| l == layer)).collect();
        lines.push(format!("{indent}{layer} {} {}", included.len(), included.iter().map(|p| p.length).sum::<i64>()));
    }
    lines.push("checksums".into());
    for layer in ["ip", "icmp", "udp", "tcp"] {
        let field = format!("{layer}.checksum.status");
        let count = |status| packets.iter().filter(|p| p.text(&field) == status).count();
        let mut line = format!("{layer} good {} bad {}", count("good"), count("bad"));
        if layer == "udp" { line.push_str(&format!(" none {}", count("none"))); }
        lines.push(line);
    }
    lines.push("malformed".into());
    for layer in ["dump", "eth", "arp", "ip", "icmp", "udp", "tcp", "dns"] {
        let count = packets.iter().filter(|p| p.reason.is_some() && p.layers.last().map(String::as_str).unwrap_or("dump") == layer).count();
        lines.push(format!("{layer} {count}"));
    }
    lines.push("tcp analysis".into());
    for mark in flows::MARKS {
        lines.push(format!("{mark} {}", packets.iter().filter(|p| p.has(&format!("tcp.analysis.{mark}"))).count()));
    }
    let mut pending: Vec<usize> = Vec::new();
    let mut queries = 0;
    let mut responses = 0;
    let mut times = Vec::new();
    let mut rcodes = [0; 16];
    let mut names: BTreeMap<String, i64> = BTreeMap::new();
    for (index, packet) in packets.iter().enumerate().filter(|(_, p)| p.has("dns.id")) {
        if packet.num("dns.flags.response") == 0 {
            queries += 1;
            pending.push(index);
            for name in packet.values("dns.qry.name") {
                if let Value::Text(name) = name { *names.entry(name).or_default() += 1; }
            }
        } else {
            responses += 1;
            rcodes[packet.num("dns.flags.rcode") as usize] += 1;
            let matched = pending.iter().position(|&i| {
                let query = &packets[i];
                query.num("dns.id") == packet.num("dns.id") && query.num("ip.src") == packet.num("ip.dst") && query.num("ip.dst") == packet.num("ip.src") && query.num("udp.srcport") == packet.num("udp.dstport") && query.num("udp.dstport") == packet.num("udp.srcport")
            });
            if let Some(position) = matched {
                let query = pending.remove(position);
                times.push(packet.time - packets[query].time);
            }
        }
    }
    lines.extend(["dns".into(), format!("queries {queries}"), format!("responses {responses}"), format!("transactions {}", times.len()), format!("unanswered {}", pending.len())]);
    if times.is_empty() { lines.push("response_time -".into()); }
    else { lines.push(format!("response_time min {} max {}", seconds(*times.iter().min().unwrap()), seconds(*times.iter().max().unwrap()))); }
    for (code, count) in rcodes.iter().enumerate().filter(|(_, count)| **count > 0) {
        lines.push(format!("rcode {} {count}", dns_app::rcode_name(code as i64)));
    }
    lines.push("names".into());
    let mut names: Vec<_> = names.into_iter().collect();
    names.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    lines.extend(names.into_iter().map(|(name, count)| format!("{name} {count}")));
    lines
}

fn write_lines(name: &str, lines: &[String]) {
    let content = if lines.is_empty() { String::new() } else { format!("{}\n", lines.join("\n")) };
    fs::write(format!("output/{name}"), content).unwrap();
}

fn main() {
    let mut packets = hexdump::read_capture("input/capture.txt");
    let origin = packets[0].time;
    for packet in &mut packets { dissect(packet, origin); }
    let streams = flows::track(&mut packets);
    let summaries: Vec<_> = packets.iter().map(summary).collect();
    let mut summary_lines = summaries.clone();
    let mut detail_lines = Vec::new();
    let mut detail_requests = 0;
    for line in fs::read_to_string("input/filters.txt").unwrap().lines() {
        if let Some(text) = line.strip_prefix("FILTER ") {
            summary_lines.extend([String::new(), format!("filter {text}")]);
            match parse_filter(text) {
                Err(error) => summary_lines.push(format!("error: {error}")),
                Ok(expression) => {
                    let mut count = 0;
                    for (packet, summary) in packets.iter().zip(&summaries) {
                        if expression.evaluate(packet) { summary_lines.push(summary.clone()); count += 1; }
                    }
                    summary_lines.push(format!("matched {count} of {}", packets.len()));
                }
            }
        } else if let Some(text) = line.strip_prefix("DETAIL ") {
            if detail_requests > 0 { detail_lines.push(String::new()); }
            detail_requests += 1;
            let number: usize = text.parse().unwrap();
            if number >= 1 && number <= packets.len() { detail_lines.extend(details(&packets[number - 1])); }
            else { detail_lines.push(format!("packet {number} not found")); }
        }
    }
    let (conversations, endpoints) = flows::tables(&packets);
    fs::create_dir_all("output").unwrap();
    write_lines("summary.txt", &summary_lines);
    write_lines("details.txt", &detail_lines);
    write_lines("conversations.csv", &conversations);
    write_lines("endpoints.csv", &endpoints);
    write_lines("protocol_stats.txt", &statistics(&packets));
    write_lines("tcp_streams.txt", &flows::stream_lines(&streams, &packets));
}
