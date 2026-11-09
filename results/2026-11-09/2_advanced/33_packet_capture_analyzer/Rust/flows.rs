use crate::link_network::ipv4;
use crate::{seconds, Packet};
use std::collections::{BTreeMap, BTreeSet};

type Endpoint = (i64, i64);
pub const MARKS: [&str; 4] = ["retransmission", "out_of_order", "lost_segment", "duplicate_ack"];

#[derive(Default)]
struct Side {
    isn: Option<i64>,
    mss: Option<i64>,
    ws: Option<i64>,
    base: Option<i64>,
    expected: Option<i64>,
    advanced: i64,
    intervals: BTreeSet<(i64, i64)>,
    previous_ack: Option<(i64, i64, i64, i64)>,
    packets: i64,
    payload: i64,
    marks: [i64; 4],
}

pub struct Stream {
    client: Endpoint,
    server: Endpoint,
    state: &'static str,
    history: Vec<(&'static str, i64)>,
    start: i64,
    end: i64,
    packets: i64,
    bytes: i64,
    handshake: [Option<i64>; 3],
    events: Vec<(i64, usize, usize, i64, i64)>,
    closed_first: Option<usize>,
    f2: i64,
    sides: [Side; 2],
}

fn record_syn(stream: &mut Stream, side: usize, packet: &Packet) {
    stream.sides[side].isn = Some(packet.num("tcp.seq_raw"));
    stream.sides[side].mss = packet.optional_num("tcp.options.mss");
    stream.sides[side].ws = packet.optional_num("tcp.options.wscale");
    stream.handshake[side] = Some(packet.number);
}

pub fn track(packets: &mut [Packet]) -> Vec<Stream> {
    let mut streams: Vec<Stream> = Vec::new();
    for packet in packets.iter_mut().filter(|p| p.has("tcp.srcport")) {
        let source = (packet.num("ip.src"), packet.num("tcp.srcport"));
        let destination = (packet.num("ip.dst"), packet.num("tcp.dstport"));
        let flags = packet.num("tcp.flags");
        let syn = flags & 2 != 0;
        let ack_set = flags & 16 != 0;
        let fin = flags & 1 != 0;
        let rst = flags & 4 != 0;
        let seq = packet.num("tcp.seq_raw");
        let ack = packet.num("tcp.ack_raw");
        let existing = streams.iter().rposition(|s| (s.client == source && s.server == destination) || (s.client == destination && s.server == source));
        let create = existing.is_none_or(|i| ["CLOSED", "RESET"].contains(&streams[i].state) && syn && !ack_set);
        let index = if create {
            let reverse = syn && ack_set;
            let state = if reverse { "SYN_RECEIVED" } else if syn { "SYN_SENT" } else { "ESTABLISHED" };
            let mut stream = Stream {
                client: if reverse { destination } else { source },
                server: if reverse { source } else { destination },
                state, history: vec![(state, packet.number)], start: packet.time, end: packet.time,
                packets: 0, bytes: 0, handshake: [None; 3], events: Vec::new(),
                closed_first: None, f2: 0, sides: [Side::default(), Side::default()],
            };
            if syn { record_syn(&mut stream, usize::from(reverse), packet); }
            streams.push(stream);
            streams.len() - 1
        } else { existing.unwrap() };
        packet.set_num("tcp.stream", index as i64);
        let stream = &mut streams[index];
        let side_index = usize::from(source != stream.client);
        let other = 1 - side_index;
        let base = *stream.sides[side_index].base.get_or_insert(seq);
        let relative = (seq - base).rem_euclid(1_i64 << 32);
        packet.set_num("tcp.seq", relative);
        if ack_set {
            let other_base = *stream.sides[other].base.get_or_insert(ack);
            packet.set_num("tcp.ack", (ack - other_base).rem_euclid(1_i64 << 32));
        }
        let length = packet.num("tcp.len") + i64::from(syn) + i64::from(fin);
        let side = &mut stream.sides[side_index];
        let mut mark = None;
        if length > 0 {
            if let Some(expected) = side.expected {
                if relative > expected {
                    mark = Some(2);
                } else if relative < expected {
                    mark = Some(if side.intervals.contains(&(relative, length)) || packet.time - side.advanced >= 3000 { 0 } else { 1 });
                }
            }
            side.intervals.insert((relative, length));
            if side.expected.is_none_or(|e| relative + length > e) {
                side.expected = Some(relative + length);
                side.advanced = packet.time;
            }
        } else if ack_set && !rst {
            if let Some(previous) = side.previous_ack.as_mut() {
                if previous.0 == ack && previous.1 == packet.num("tcp.window") {
                    mark = Some(3);
                    previous.3 += 1;
                    packet.duplicate = Some((previous.2, previous.3));
                }
            }
        }
        if ack_set && mark != Some(3) {
            side.previous_ack = Some((ack, packet.num("tcp.window"), packet.number, 0));
        }
        if let Some(mark) = mark {
            side.marks[mark] += 1;
            packet.present(&format!("tcp.analysis.{}", MARKS[mark]));
            stream.events.push((packet.number, side_index, mark, relative, length));
        }
        let window = packet.num("tcp.window");
        let calculated = if !syn && stream.sides.iter().all(|s| s.ws.is_some()) {
            window * (1_i64 << stream.sides[side_index].ws.unwrap())
        } else { window };
        packet.set_num("tcp.window.calc", calculated);
        let old_state = stream.state;
        if rst {
            if !["CLOSED", "RESET"].contains(&stream.state) { stream.state = "RESET"; }
        } else if stream.state == "SYN_SENT" && side_index == 1 && syn && ack_set && stream.sides[0].isn.is_some_and(|isn| ack == (isn + 1) % (1_i64 << 32)) {
            stream.state = "SYN_RECEIVED";
            record_syn(stream, 1, packet);
        } else if stream.state == "SYN_RECEIVED" && side_index == 0 && ack_set && !syn && stream.sides[1].isn.is_some_and(|isn| ack == (isn + 1) % (1_i64 << 32)) {
            stream.state = "ESTABLISHED";
            stream.handshake[2] = Some(packet.number);
        } else if stream.state == "ESTABLISHED" && fin {
            stream.state = "FIN_WAIT";
            stream.closed_first = Some(side_index);
        } else if stream.state == "FIN_WAIT" && fin && stream.closed_first != Some(side_index) {
            stream.state = "CLOSING";
            stream.f2 = (seq + packet.num("tcp.len") + 1) % (1_i64 << 32);
        } else if stream.state == "CLOSING" && stream.closed_first == Some(side_index) && ack_set && ack == stream.f2 {
            stream.state = "CLOSED";
        }
        if stream.state != old_state { stream.history.push((stream.state, packet.number)); }
        stream.sides[side_index].packets += 1;
        stream.sides[side_index].payload += packet.num("tcp.len");
        stream.packets += 1;
        stream.bytes += packet.length;
        stream.end = packet.time;
    }
    streams
}

fn endpoint_text(endpoint: Endpoint) -> String {
    if endpoint.1 < 0 { ipv4(endpoint.0) } else { format!("{}:{}", ipv4(endpoint.0), endpoint.1) }
}

fn optional(value: Option<i64>) -> String {
    value.map_or_else(|| "-".into(), |v| v.to_string())
}

pub fn stream_lines(streams: &[Stream], packets: &[Packet]) -> Vec<String> {
    let mut lines = Vec::new();
    for (index, stream) in streams.iter().enumerate() {
        if index != 0 { lines.push(String::new()); }
        lines.push(format!("stream {index} {} -> {}", endpoint_text(stream.client), endpoint_text(stream.server)));
        lines.push(format!("packets {} bytes {} start {} duration {}", stream.packets, stream.bytes, seconds(stream.start - packets[0].time), seconds(stream.end - stream.start)));
        lines.push(format!("states {}", stream.history.iter().map(|(state, n)| format!("{state} {n}")).collect::<Vec<_>>().join(", ")));
        let rtt = match (stream.handshake[0], stream.handshake[2]) {
            (Some(syn), Some(ack)) => seconds(packets[ack as usize - 1].time - packets[syn as usize - 1].time),
            _ => "-".into(),
        };
        lines.push(format!("handshake syn {} syn_ack {} ack {} rtt {}", optional(stream.handshake[0]), optional(stream.handshake[1]), optional(stream.handshake[2]), rtt));
        lines.push(format!("options client mss {} wscale {} server mss {} wscale {}", optional(stream.sides[0].mss), optional(stream.sides[0].ws), optional(stream.sides[1].mss), optional(stream.sides[1].ws)));
        for (name, side) in ["client", "server"].iter().zip(&stream.sides) {
            lines.push(format!("{} packets {} payload {} retransmission {} out_of_order {} lost_segment {} duplicate_ack {}", name, side.packets, side.payload, side.marks[0], side.marks[1], side.marks[2], side.marks[3]));
        }
        for &(n, side, mark, relative, length) in &stream.events {
            lines.push(format!("event {} {} {} seq {} len {}", n, ["client", "server"][side], MARKS[mark], relative, length));
        }
    }
    lines
}

struct Conversation {
    kind: usize,
    a: Endpoint,
    b: Endpoint,
    counts: [i64; 4],
    start: i64,
    end: i64,
    first: i64,
}

pub fn tables(packets: &[Packet]) -> (Vec<String>, Vec<String>) {
    let mut conversations: BTreeMap<(usize, i64, Endpoint, Endpoint), Conversation> = BTreeMap::new();
    let mut endpoints: BTreeMap<i64, [i64; 4]> = BTreeMap::new();
    for packet in packets.iter().filter(|p| p.has("ip.src")) {
        let source = packet.num("ip.src");
        let destination = packet.num("ip.dst");
        let tx = endpoints.entry(source).or_default();
        tx[0] += 1;
        tx[1] += packet.length;
        let rx = endpoints.entry(destination).or_default();
        rx[2] += 1;
        rx[3] += packet.length;
        let mut kinds = vec![(0, -1, (source, -1), (destination, -1))];
        if packet.has("tcp.stream") { kinds.push((1, packet.num("tcp.stream"), (source, packet.num("tcp.srcport")), (destination, packet.num("tcp.dstport")))); }
        if packet.has("udp.srcport") { kinds.push((2, -1, (source, packet.num("udp.srcport")), (destination, packet.num("udp.dstport")))); }
        for (kind, stream, a, b) in kinds {
            let key = (kind, stream, a.min(b), a.max(b));
            let conversation = conversations.entry(key).or_insert(Conversation {
                kind, a, b, counts: [0; 4], start: packet.time, end: packet.time, first: packet.number,
            });
            let direction = if a == conversation.a { 0 } else { 2 };
            conversation.counts[direction] += 1;
            conversation.counts[direction + 1] += packet.length;
            conversation.end = packet.time;
        }
    }
    let mut conversations: Vec<_> = conversations.into_values().collect();
    conversations.sort_by_key(|c| (-(c.counts[1] + c.counts[3]), -(c.counts[0] + c.counts[2]), c.kind, c.first));
    let mut conversation_lines = vec!["type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration".into()];
    for c in conversations {
        conversation_lines.push(format!("{},{},{},{},{},{},{},{},{},{},{}", ["ipv4", "tcp", "udp"][c.kind], endpoint_text(c.a), endpoint_text(c.b), c.counts[0] + c.counts[2], c.counts[1] + c.counts[3], c.counts[0], c.counts[1], c.counts[2], c.counts[3], seconds(c.start - packets[0].time), seconds(c.end - c.start)));
    }
    let mut endpoints: Vec<_> = endpoints.into_iter().collect();
    endpoints.sort_by_key(|&(address, c)| (-(c[1] + c[3]), -(c[0] + c[2]), address));
    let mut endpoint_lines = vec!["address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes".into()];
    for (address, c) in endpoints {
        endpoint_lines.push(format!("{},{},{},{},{},{},{}", ipv4(address), c[0] + c[2], c[1] + c[3], c[0], c[1], c[2], c[3]));
    }
    (conversation_lines, endpoint_lines)
}
