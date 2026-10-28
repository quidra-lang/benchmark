use crate::Packet;
use std::fs;

pub fn read_capture(path: &str) -> Vec<Packet> {
    let input = fs::read_to_string(path).unwrap();
    let mut packets: Vec<Packet> = Vec::new();
    for (line_index, line) in input.lines().enumerate() {
        if line.starts_with("PACKET ") {
            if let Some(packet) = packets.last_mut() {
                finish(packet);
            }
            let parts: Vec<_> = line.split(' ').collect();
            packets.push(Packet::new(parts[1].parse().unwrap(), parts[2].parse().unwrap(), parts[3].parse().unwrap()));
        } else if !line.is_empty() {
            let packet = packets.last_mut().unwrap();
            if packet.reason.is_some() {
                continue;
            }
            let bytes = line.as_bytes();
            let hex = |b: u8| b.is_ascii_digit() || (b'a'..=b'f').contains(&b);
            let valid_prefix = bytes.len() >= 8 && bytes[..4].iter().all(|&b| hex(b)) && &bytes[4..6] == b"  ";
            let parts: Vec<_> = if valid_prefix { line[6..].split(' ').collect() } else { Vec::new() };
            if !valid_prefix || parts.is_empty() || parts.len() > 16 || parts.iter().any(|p| p.len() != 2 || !p.bytes().all(hex)) {
                packet.reason = Some(format!("dump: bad line {}", line_index + 1));
            } else if usize::from_str_radix(&line[..4], 16).unwrap() != packet.bytes.len() {
                packet.reason = Some(format!("dump: offset mismatch at line {}", line_index + 1));
            } else {
                packet.bytes.extend(parts.iter().map(|p| u8::from_str_radix(p, 16).unwrap()));
            }
        }
    }
    finish(packets.last_mut().unwrap());
    packets
}

fn finish(packet: &mut Packet) {
    if packet.reason.is_none() && packet.bytes.len() as i64 != packet.length {
        packet.reason = Some(format!("dump: length mismatch (header {}, data {})", packet.length, packet.bytes.len()));
    }
}

pub fn dump(data: &[u8]) -> Vec<String> {
    data.chunks(16).enumerate().map(|(i, row)| {
        let hex = row.iter().map(|b| format!("{b:02x}")).collect::<Vec<_>>().join(" ");
        let ascii: String = row.iter().map(|&b| if (32..=126).contains(&b) { b as char } else { '.' }).collect();
        format!("{:04x}  {:47}  |{}|", i * 16, hex, ascii)
    }).collect()
}
