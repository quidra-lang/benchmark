#include "capture.hpp"
const std::array<std::string, 4> mark_names = {"retransmission", "out_of_order", "lost_segment",
                                               "duplicate_ack"};
static Integer mod32(Integer value) {
    return (value + (Integer(1) << 32)) % (Integer(1) << 32);
}
static void record_syn(Stream &stream, const Packet &packet, int side) {
    Side &s = stream.sides[side];
    s.isn = packet.num("tcp.seq_raw");
    s.mss =
        packet.has("tcp.options.mss") ? std::optional<Integer>(packet.num("tcp.options.mss")) : std::nullopt;
    s.ws = packet.has("tcp.options.wscale") ? std::optional<Integer>(packet.num("tcp.options.wscale"))
                                            : std::nullopt;
    stream.handshake[side == 0 ? 0 : 1] = packet.number;
}
void track(Packet &p, std::vector<Stream> &streams) {
    if (!p.has("tcp.srcport"))
        return;
    const Endpoint source{p.num("ip.src"), p.num("tcp.srcport")},
        destination{p.num("ip.dst"), p.num("tcp.dstport")};
    const bool syn = p.num("tcp.flags.syn"), ack_set = p.num("tcp.flags.ack"), fin = p.num("tcp.flags.fin"),
               rst = p.num("tcp.flags.rst");
    int index = -1;
    for (int i = int(streams.size()) - 1; i >= 0; --i)
        if ((streams[i].client == source && streams[i].server == destination) ||
            (streams[i].client == destination && streams[i].server == source)) {
            index = i;
            break;
        }
    if (index < 0 ||
        ((streams[index].state == "CLOSED" || streams[index].state == "RESET") && syn && !ack_set)) {
        Stream stream;
        stream.start = p.time;
        if (syn && ack_set) {
            stream.client = destination;
            stream.server = source;
            stream.state = "SYN_RECEIVED";
            record_syn(stream, p, 1);
        } else {
            stream.client = source;
            stream.server = destination;
            stream.state = syn ? "SYN_SENT" : "ESTABLISHED";
            if (syn)
                record_syn(stream, p, 0);
        }
        stream.history.emplace_back(stream.state, p.number);
        index = streams.size();
        streams.push_back(std::move(stream));
    }
    Stream &stream = streams[index];
    p.n("tcp.stream", index);
    const int side = source == stream.client ? 0 : 1;
    Side &s = stream.sides[side], &other = stream.sides[1 - side];
    const Integer seq = p.num("tcp.seq_raw"), ack = p.num("tcp.ack_raw");
    if (!s.base)
        s.base = seq;
    if (ack_set && !other.base)
        other.base = ack;
    const Integer r = mod32(seq - *s.base), length = p.num("tcp.len") + Integer(syn) + Integer(fin);
    p.n("tcp.seq", r);
    if (ack_set)
        p.n("tcp.ack", mod32(ack - *other.base));
    int mark = -1;
    if (length > 0) {
        if (s.expected && r > *s.expected)
            mark = 2;
        else if (s.expected && r < *s.expected)
            mark = s.intervals.count({r, length}) || p.time - s.advanced >= 3000 ? 0 : 1;
        s.intervals.emplace(r, length);
        if (!s.expected || r + length > *s.expected) {
            s.expected = r + length;
            s.advanced = p.time;
        }
    } else if (ack_set && !rst && s.previous_ack && (*s.previous_ack)[0] == ack &&
               (*s.previous_ack)[1] == p.num("tcp.window")) {
        mark = 3;
        ++(*s.previous_ack)[3];
        p.duplicate_origin = (*s.previous_ack)[2];
        p.duplicate_count = (*s.previous_ack)[3];
    }
    if (ack_set && mark != 3)
        s.previous_ack = std::array<Integer, 4>{ack, p.num("tcp.window"), p.number, 0};
    if (mark >= 0) {
        p.flag("tcp.analysis." + mark_names[mark]);
        ++s.marks[mark];
        stream.events.push_back({p.number, side, mark, r, length});
    }
    p.n("tcp.window.calc",
        p.num("tcp.window") * (stream.sides[0].ws && stream.sides[1].ws && !syn ? (Integer(1) << *s.ws) : 1));
    const std::string previous = stream.state;
    if (rst) {
        if (previous != "CLOSED" && previous != "RESET")
            stream.state = "RESET";
    } else if (previous == "SYN_SENT" && side == 1 && syn && ack_set && stream.sides[0].isn &&
               ack == mod32(*stream.sides[0].isn + 1)) {
        stream.state = "SYN_RECEIVED";
        record_syn(stream, p, 1);
    } else if (previous == "SYN_RECEIVED" && side == 0 && ack_set && !syn && stream.sides[1].isn &&
               ack == mod32(*stream.sides[1].isn + 1)) {
        stream.state = "ESTABLISHED";
        stream.handshake[2] = p.number;
    } else if (previous == "ESTABLISHED" && fin) {
        stream.state = "FIN_WAIT";
        stream.first_close = side;
    } else if (previous == "FIN_WAIT" && fin && side != stream.first_close) {
        stream.state = "CLOSING";
        stream.f2 = mod32(seq + p.num("tcp.len") + 1);
    } else if (previous == "CLOSING" && side == stream.first_close && ack_set && ack == stream.f2)
        stream.state = "CLOSED";
    if (stream.state != previous)
        stream.history.emplace_back(stream.state, p.number);
    ++s.packets;
    s.payload += p.num("tcp.len");
    ++stream.packets;
    stream.bytes += p.length;
    stream.end = p.time;
}
std::string endpoint(Endpoint value, bool port) {
    return ipv4(value.address) + (port ? ":" + decimal(value.port) : "");
}
std::vector<Conversation> conversations(const std::vector<Packet> &packets) {
    std::vector<Conversation> result;
    std::map<std::tuple<int, Endpoint, Endpoint, Integer>, std::size_t> positions;
    for (const Packet &p : packets)
        for (int kind = 0; kind < 3; ++kind) {
            if (!p.has(kind == 0 ? "ip.src" : kind == 1 ? "tcp.stream" : "udp.srcport"))
                continue;
            const std::string protocol = kind == 1 ? "tcp" : "udp";
            const Endpoint source{p.num("ip.src"), kind == 0 ? 0 : p.num(protocol + ".srcport")},
                destination{p.num("ip.dst"), kind == 0 ? 0 : p.num(protocol + ".dstport")};
            const auto key =
                std::make_tuple(kind, std::min(source, destination), std::max(source, destination),
                                kind == 1 ? p.num("tcp.stream") : 0);
            auto found = positions.find(key);
            if (found == positions.end()) {
                const std::size_t index = result.size();
                positions[key] = index;
                result.push_back({kind, source, destination, p.number, p.time, p.time});
                found = positions.find(key);
            }
            Conversation &c = result[found->second];
            const int direction = source == c.a ? 0 : 1;
            ++c.packets[direction];
            c.bytes[direction] += p.length;
            c.end = p.time;
        }
    std::sort(result.begin(), result.end(), [](const Conversation &a, const Conversation &b) {
        const Integer ab = a.bytes[0] + a.bytes[1], bb = b.bytes[0] + b.bytes[1],
                      ap = a.packets[0] + a.packets[1], bp = b.packets[0] + b.packets[1];
        if (ab != bb)
            return ab > bb;
        if (ap != bp)
            return ap > bp;
        return std::tie(a.kind, a.first) < std::tie(b.kind, b.first);
    });
    return result;
}
std::vector<EndpointTotals> endpoints(const std::vector<Packet> &packets) {
    std::map<Integer, EndpointTotals> values;
    for (const Packet &p : packets)
        if (p.has("ip.src"))
            for (int side = 0; side < 2; ++side) {
                const Integer address = p.num(side == 0 ? "ip.src" : "ip.dst");
                EndpointTotals &value = values[address];
                value.address = address;
                ++value.packets[side];
                value.bytes[side] += p.length;
            }
    std::vector<EndpointTotals> result;
    for (const auto &entry : values)
        result.push_back(entry.second);
    std::sort(result.begin(), result.end(), [](const EndpointTotals &a, const EndpointTotals &b) {
        const Integer ab = a.bytes[0] + a.bytes[1], bb = b.bytes[0] + b.bytes[1],
                      ap = a.packets[0] + a.packets[1], bp = b.packets[0] + b.packets[1];
        if (ab != bb)
            return ab > bb;
        if (ap != bp)
            return ap > bp;
        return a.address < b.address;
    });
    return result;
}
