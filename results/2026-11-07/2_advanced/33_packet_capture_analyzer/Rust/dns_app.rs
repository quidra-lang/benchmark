use crate::link_network::{integer, ipv4};
use crate::Packet;

pub fn type_name(kind: i64) -> String {
    match kind {
        1 => "A".into(), 2 => "NS".into(), 5 => "CNAME".into(), 6 => "SOA".into(),
        12 => "PTR".into(), 15 => "MX".into(), 16 => "TXT".into(), 28 => "AAAA".into(),
        _ => format!("TYPE{kind}"),
    }
}

pub fn rcode_name(code: i64) -> String {
    match code {
        0 => "NoError".into(), 1 => "FormErr".into(), 2 => "ServFail".into(),
        3 => "NXDomain".into(), 4 => "NotImp".into(), 5 => "Refused".into(),
        _ => format!("RCODE{code}"),
    }
}

struct Reader<'a> {
    bytes: &'a [u8],
}

impl Reader<'_> {
    fn need(&self, start: usize, length: usize) -> Result<(), String> {
        if start + length > self.bytes.len() { Err("dns: truncated".into()) } else { Ok(()) }
    }

    fn number(&self, start: usize, length: usize) -> Result<i64, String> {
        self.need(start, length)?;
        Ok(integer(self.bytes, start, length))
    }

    fn name(&self, mut position: usize) -> Result<(String, usize), String> {
        let mut labels = Vec::new();
        let mut after = None;
        let mut pointers = 0;
        loop {
            let c = self.number(position, 1)? as usize;
            if c == 0 {
                let end = after.unwrap_or(position + 1);
                return Ok((if labels.is_empty() { "<root>".into() } else { labels.join(".") }, end));
            }
            if c >= 192 {
                let d = self.number(position + 1, 1)? as usize;
                after.get_or_insert(position + 2);
                pointers += 1;
                if pointers > 16 {
                    return Err("dns: compression loop".into());
                }
                position = (c - 192) * 256 + d;
                if position >= self.bytes.len() {
                    return Err("dns: pointer out of range".into());
                }
            } else if c >= 64 {
                return Err("dns: bad label type".into());
            } else {
                self.need(position + 1, c)?;
                let label: String = self.bytes[position + 1..position + c + 1].iter().map(|&b| {
                    if (33..=126).contains(&b) && b != b'.' && b != b'\\' { (b as char).to_string() } else { format!("\\{b:03}") }
                }).collect();
                labels.push(label);
                position += c + 1;
            }
        }
    }

    fn rdata(&self, kind: i64, start: usize, length: usize) -> Result<(String, usize), String> {
        match kind {
            1 => Ok((ipv4(self.number(start, 4)?), start + 4)),
            28 => {
                self.need(start, 16)?;
                let groups: Vec<_> = (0..8).map(|i| integer(self.bytes, start + i * 2, 2)).collect();
                let mut best = (0, 0);
                let mut i = 0;
                while i < 8 {
                    if groups[i] != 0 {
                        i += 1;
                        continue;
                    }
                    let begin = i;
                    while i < 8 && groups[i] == 0 { i += 1; }
                    if i - begin >= 2 && i - begin > best.1 { best = (begin, i - begin); }
                }
                let join = |slice: &[i64]| slice.iter().map(|v| format!("{v:x}")).collect::<Vec<_>>().join(":");
                let text = if best.1 == 0 { join(&groups) } else { format!("{}::{}", join(&groups[..best.0]), join(&groups[best.0 + best.1..])) };
                Ok((text, start + 16))
            }
            2 | 5 | 12 => self.name(start),
            15 => {
                let preference = self.number(start, 2)?;
                let (name, end) = self.name(start + 2)?;
                Ok((format!("{preference} {name}"), end))
            }
            6 => {
                let (m, after_m) = self.name(start)?;
                let (n, after_n) = self.name(after_m)?;
                let mut text = format!("{m} {n}");
                for i in 0..5 {
                    text.push_str(&format!(" {}", self.number(after_n + i * 4, 4)?));
                }
                Ok((text, after_n + 20))
            }
            _ => Ok((format!("{length} bytes"), start + length)),
        }
    }
}

pub fn dissect(packet: &mut Packet, bytes: &[u8]) -> Result<Vec<u8>, String> {
    let reader = Reader { bytes };
    reader.need(0, 12)?;
    let mut staged = Packet::new(0, 0, 0);
    let flags = reader.number(2, 2)?;
    for (field, value) in [
        ("dns.id", reader.number(0, 2)?), ("dns.flags", flags), ("dns.flags.response", (flags >> 15) & 1),
        ("dns.flags.opcode", (flags / 2048) % 16), ("dns.flags.rcode", flags % 16),
        ("dns.count.queries", reader.number(4, 2)?), ("dns.count.answers", reader.number(6, 2)?),
        ("dns.count.auth_rr", reader.number(8, 2)?), ("dns.count.add_rr", reader.number(10, 2)?),
    ] {
        staged.set_num(field, value);
    }
    let mut position = 12;
    for _ in 0..staged.num("dns.count.queries") {
        let (name, after) = reader.name(position)?;
        reader.need(after, 4)?;
        staged.append_text("dns.qry.name", name);
        staged.append_num("dns.qry.type", reader.number(after, 2)?);
        position = after + 4;
    }
    for (count, field) in [("dns.count.answers", "dns.answer"), ("dns.count.auth_rr", "dns.authority"), ("dns.count.add_rr", "dns.additional")] {
        for _ in 0..staged.num(count) {
            let (name, after) = reader.name(position)?;
            reader.need(after, 10)?;
            let kind = reader.number(after, 2)?;
            let class = reader.number(after + 2, 2)?;
            let ttl = reader.number(after + 4, 4)?;
            let length = reader.number(after + 8, 2)? as usize;
            let start = after + 10;
            reader.need(start, length)?;
            let (data, end) = reader.rdata(kind, start, length)?;
            if end != start + length { return Err("dns: bad rdata length".into()); }
            let class_name = if class == 1 { "IN".into() } else { format!("CLASS{class}") };
            staged.append_text(field, format!("{} {} {} {} {}", name, type_name(kind), class_name, ttl, data));
            if field == "dns.answer" {
                staged.answers.push((kind, data));
                if kind == 1 { staged.append_num("dns.a", reader.number(start, 4)?); }
            }
            position = start + length;
        }
    }
    packet.fields.extend(staged.fields);
    packet.answers = staged.answers;
    Ok(Vec::new())
}
