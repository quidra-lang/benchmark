use crate::Packet;

pub fn integer(bytes: &[u8], start: usize, length: usize) -> i64 {
    bytes[start..start + length].iter().fold(0, |value, &b| value * 256 + i64::from(b))
}

pub fn checksum(bytes: &[u8]) -> &'static str {
    let mut sum: i64 = bytes.chunks(2).map(|p| i64::from(p[0]) * 256 + i64::from(*p.get(1).unwrap_or(&0))).sum();
    while sum > 65535 {
        sum = sum % 65536 + sum / 65536;
    }
    if sum == 65535 { "good" } else { "bad" }
}

pub fn ipv4(value: i64) -> String {
    (0..4).rev().map(|i| ((value >> (i * 8)) & 255).to_string()).collect::<Vec<_>>().join(".")
}

pub fn mac(value: i64) -> String {
    (0..6).rev().map(|i| format!("{:02x}", (value >> (i * 8)) & 255)).collect::<Vec<_>>().join(":")
}

pub fn ethernet(packet: &mut Packet, bytes: &[u8]) -> Result<Vec<u8>, String> {
    if bytes.len() < 14 {
        return Err("eth: truncated".into());
    }
    packet.set_num("eth.dst", integer(bytes, 0, 6));
    packet.set_num("eth.src", integer(bytes, 6, 6));
    packet.set_num("eth.type", integer(bytes, 12, 2));
    Ok(bytes[14..].to_vec())
}

pub fn arp(packet: &mut Packet, bytes: &[u8]) -> Result<Vec<u8>, String> {
    if bytes.len() < 28 {
        return Err("arp: truncated".into());
    }
    if integer(bytes, 0, 2) != 1 || integer(bytes, 2, 2) != 2048 || bytes[4] != 6 || bytes[5] != 4 {
        return Err("arp: unsupported format".into());
    }
    for (field, offset, length) in [("arp.opcode", 6, 2), ("arp.src.hw", 8, 6), ("arp.src.ip", 14, 4), ("arp.dst.hw", 18, 6), ("arp.dst.ip", 24, 4)] {
        packet.set_num(field, integer(bytes, offset, length));
    }
    Ok(Vec::new())
}

pub fn ipv4_layer(packet: &mut Packet, bytes: &[u8]) -> Result<Vec<u8>, String> {
    if bytes.len() < 20 {
        return Err("ip: truncated header".into());
    }
    let version = bytes[0] / 16;
    if version != 4 {
        return Err(format!("ip: bad version {version}"));
    }
    let header = usize::from(bytes[0] % 16) * 4;
    if header < 20 {
        return Err(format!("ip: bad header length {header}"));
    }
    if bytes.len() < header {
        return Err("ip: truncated header".into());
    }
    let total = integer(bytes, 2, 2) as usize;
    if total < header {
        return Err(format!("ip: bad total length {total}"));
    }
    if total > bytes.len() {
        return Err(format!("ip: truncated (total length {total}, available {})", bytes.len()));
    }
    let flags = integer(bytes, 6, 2);
    for (field, value) in [
        ("ip.hdr_len", header as i64), ("ip.tos", i64::from(bytes[1])), ("ip.len", total as i64),
        ("ip.id", integer(bytes, 4, 2)), ("ip.flags.df", (flags >> 14) & 1),
        ("ip.flags.mf", (flags >> 13) & 1), ("ip.frag_offset", (flags % 8192) * 8),
        ("ip.ttl", i64::from(bytes[8])), ("ip.proto", i64::from(bytes[9])),
        ("ip.checksum", integer(bytes, 10, 2)), ("ip.src", integer(bytes, 12, 4)), ("ip.dst", integer(bytes, 16, 4)),
    ] {
        packet.set_num(field, value);
    }
    packet.set_text("ip.checksum.status", checksum(&bytes[..header]));
    if packet.num("ip.flags.mf") == 1 || packet.num("ip.frag_offset") != 0 {
        packet.present("ip.fragment");
    }
    Ok(bytes[header..total].to_vec())
}
