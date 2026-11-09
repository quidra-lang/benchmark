use crate::link_network::{checksum, integer};
use crate::Packet;

fn pseudo(packet: &Packet, protocol: u8, bytes: &[u8]) -> Vec<u8> {
    let mut result = Vec::new();
    result.extend_from_slice(&(packet.num("ip.src") as u32).to_be_bytes());
    result.extend_from_slice(&(packet.num("ip.dst") as u32).to_be_bytes());
    result.extend_from_slice(&[0, protocol]);
    result.extend_from_slice(&(bytes.len() as u16).to_be_bytes());
    result.extend_from_slice(bytes);
    result
}

pub fn icmp(packet: &mut Packet, bytes: &[u8]) -> Result<Vec<u8>, String> {
    if bytes.len() < 8 {
        return Err("icmp: truncated".into());
    }
    packet.set_num("icmp.type", i64::from(bytes[0]));
    packet.set_num("icmp.code", i64::from(bytes[1]));
    packet.set_num("icmp.checksum", integer(bytes, 2, 2));
    packet.set_text("icmp.checksum.status", checksum(bytes));
    if bytes[0] == 0 || bytes[0] == 8 {
        packet.set_num("icmp.id", integer(bytes, 4, 2));
        packet.set_num("icmp.seq", integer(bytes, 6, 2));
    }
    Ok(bytes[8..].to_vec())
}

pub fn udp(packet: &mut Packet, bytes: &[u8]) -> Result<Vec<u8>, String> {
    if bytes.len() < 8 {
        return Err("udp: truncated".into());
    }
    let length = integer(bytes, 4, 2) as usize;
    if length < 8 || length > bytes.len() {
        return Err(format!("udp: bad length {length}"));
    }
    for (field, offset) in [("udp.srcport", 0), ("udp.dstport", 2), ("udp.length", 4), ("udp.checksum", 6)] {
        packet.set_num(field, integer(bytes, offset, 2));
    }
    let status = if packet.num("udp.checksum") == 0 { "none" } else { checksum(&pseudo(packet, 17, &bytes[..length])) };
    packet.set_text("udp.checksum.status", status);
    Ok(bytes[8..length].to_vec())
}

pub fn tcp(packet: &mut Packet, bytes: &[u8]) -> Result<Vec<u8>, String> {
    if bytes.len() < 20 {
        return Err("tcp: truncated header".into());
    }
    let header = usize::from(bytes[12] / 16) * 4;
    if header < 20 {
        return Err(format!("tcp: bad header length {header}"));
    }
    if header > bytes.len() {
        return Err("tcp: truncated header".into());
    }
    for (field, offset, length) in [("tcp.srcport", 0, 2), ("tcp.dstport", 2, 2), ("tcp.seq_raw", 4, 4), ("tcp.window", 14, 2), ("tcp.checksum", 16, 2), ("tcp.urgent", 18, 2)] {
        packet.set_num(field, integer(bytes, offset, length));
    }
    packet.set_num("tcp.hdr_len", header as i64);
    packet.set_num("tcp.len", (bytes.len() - header) as i64);
    let flags = i64::from(bytes[13]);
    packet.set_num("tcp.flags", flags);
    for (bit, field) in ["fin", "syn", "rst", "psh", "ack", "urg"].iter().enumerate() {
        packet.set_num(&format!("tcp.flags.{field}"), (flags >> bit) & 1);
    }
    if flags & 16 != 0 {
        packet.set_num("tcp.ack_raw", integer(bytes, 8, 4));
    }
    packet.set_text("tcp.checksum.status", checksum(&pseudo(packet, 6, bytes)));
    let options = &bytes[20..header];
    let mut i = 0;
    while i < options.len() {
        let kind = options[i];
        if kind == 0 {
            packet.append_text("tcp.option", "EOL".into());
            break;
        }
        if kind == 1 {
            packet.append_text("tcp.option", "NOP".into());
            i += 1;
            continue;
        }
        let length = usize::from(*options.get(i + 1).unwrap_or(&0));
        let known_length = match kind {
            2 => length == 4,
            3 => length == 3,
            4 => length == 2,
            5 => [10, 18, 26, 34].contains(&length),
            8 => length == 10,
            _ => true,
        };
        if length < 2 || i + length > options.len() || !known_length {
            packet.present("tcp.options.malformed");
            break;
        }
        let body = &options[i + 2..i + length];
        let text = match kind {
            2 => {
                let value = integer(body, 0, 2);
                packet.set_num("tcp.options.mss", value);
                format!("MSS {value}")
            }
            3 => {
                packet.set_num("tcp.options.wscale", i64::from(body[0]));
                format!("WS {}", body[0])
            }
            4 => "SACK_PERM".into(),
            5 => {
                let blocks = body.chunks(8).map(|b| format!(" {}-{}", integer(b, 0, 4), integer(b, 4, 4))).collect::<String>();
                format!("SACK{blocks}")
            }
            8 => format!("TS {} {}", integer(body, 0, 4), integer(body, 4, 4)),
            _ => format!("kind {kind} len {length}"),
        };
        packet.append_text("tcp.option", text);
        i += length;
    }
    Ok(bytes[header..].to_vec())
}
