#include "capture.hpp"
static Bytes pseudo(const Packet &p, const Bytes &data, int protocol) {
    Bytes result;
    for (const auto &field : {"ip.src", "ip.dst"})
        for (int i = 3; i >= 0; --i)
            result.push_back(static_cast<unsigned char>((p.num(field) >> (8 * i)) & 255));
    result.push_back(0);
    result.push_back(protocol);
    result.push_back(data.size() / 256);
    result.push_back(data.size() % 256);
    result.insert(result.end(), data.begin(), data.end());
    return result;
}
Bytes icmp(Packet &p, const Bytes &b) {
    if (b.size() < 8)
        throw std::string("icmp: truncated");
    p.n("icmp.type", b[0]);
    p.n("icmp.code", b[1]);
    p.n("icmp.checksum", read_integer(b, 2, 2));
    p.s("icmp.checksum.status", checksum(b));
    if (b[0] == 0 || b[0] == 8) {
        p.n("icmp.id", read_integer(b, 4, 2));
        p.n("icmp.seq", read_integer(b, 6, 2));
    }
    return slice(b, 8, b.size());
}
Bytes udp(Packet &p, const Bytes &b) {
    if (b.size() < 8)
        throw std::string("udp: truncated");
    const Integer length = read_integer(b, 4, 2);
    if (length < 8 || length > Integer(b.size()))
        throw "udp: bad length " + decimal(length);
    p.n("udp.srcport", read_integer(b, 0, 2));
    p.n("udp.dstport", read_integer(b, 2, 2));
    p.n("udp.length", length);
    p.n("udp.checksum", read_integer(b, 6, 2));
    p.s("udp.checksum.status",
        p.num("udp.checksum") == 0 ? "none" : checksum(pseudo(p, slice(b, 0, length), 17)));
    return slice(b, 8, length);
}
Bytes tcp(Packet &p, const Bytes &b) {
    if (b.size() < 20)
        throw std::string("tcp: truncated header");
    const int h = (b[12] / 16) * 4;
    if (h < 20)
        throw "tcp: bad header length " + decimal(h);
    if (std::size_t(h) > b.size())
        throw std::string("tcp: truncated header");
    p.n("tcp.srcport", read_integer(b, 0, 2));
    p.n("tcp.dstport", read_integer(b, 2, 2));
    p.n("tcp.seq_raw", read_integer(b, 4, 4));
    p.n("tcp.hdr_len", h);
    p.n("tcp.flags", b[13]);
    const std::array<std::string, 6> names = {"fin", "syn", "rst", "psh", "ack", "urg"};
    for (int i = 0; i < 6; ++i)
        p.n("tcp.flags." + names[i], (b[13] >> i) & 1);
    if (b[13] & 16)
        p.n("tcp.ack_raw", read_integer(b, 8, 4));
    p.n("tcp.window", read_integer(b, 14, 2));
    p.n("tcp.checksum", read_integer(b, 16, 2));
    p.s("tcp.checksum.status", checksum(pseudo(p, b, 6)));
    p.n("tcp.urgent", read_integer(b, 18, 2));
    p.n("tcp.len", b.size() - h);
    for (int i = 20; i < h;) {
        const int kind = b[i];
        if (kind == 0) {
            p.s("tcp.option", "EOL", true);
            break;
        }
        if (kind == 1) {
            p.s("tcp.option", "NOP", true);
            ++i;
            continue;
        }
        const int length = i + 1 < h ? b[i + 1] : 0;
        if (length < 2 || i + length > h || (kind == 2 && length != 4) || (kind == 3 && length != 3) ||
            (kind == 4 && length != 2) ||
            (kind == 5 && length != 10 && length != 18 && length != 26 && length != 34) ||
            (kind == 8 && length != 10)) {
            p.flag("tcp.options.malformed");
            break;
        }
        std::string option;
        if (kind == 2) {
            const Integer value = read_integer(b, i + 2, 2);
            option = "MSS " + decimal(value);
            p.n("tcp.options.mss", value);
        } else if (kind == 3) {
            option = "WS " + decimal(b[i + 2]);
            p.n("tcp.options.wscale", b[i + 2]);
        } else if (kind == 4)
            option = "SACK_PERM";
        else if (kind == 5) {
            option = "SACK";
            for (int j = i + 2; j < i + length; j += 8)
                option += " " + decimal(read_integer(b, j, 4)) + "-" + decimal(read_integer(b, j + 4, 4));
        } else if (kind == 8)
            option = "TS " + decimal(read_integer(b, i + 2, 4)) + " " + decimal(read_integer(b, i + 6, 4));
        else
            option = "kind " + decimal(kind) + " len " + decimal(length);
        p.s("tcp.option", option, true);
        i += length;
    }
    return slice(b, h, b.size());
}
