#include "capture.hpp"
Integer read_integer(const Bytes &data, std::size_t position, std::size_t count) {
    Integer value = 0;
    for (std::size_t i = 0; i < count; ++i)
        value = value * 256 + data.at(position + i);
    return value;
}
Bytes slice(const Bytes &data, std::size_t first, std::size_t last) {
    return Bytes(data.begin() + first, data.begin() + last);
}
std::string checksum(const Bytes &data) {
    Integer sum = 0;
    for (std::size_t i = 0; i < data.size(); i += 2)
        sum += Integer(data[i]) * 256 + (i + 1 < data.size() ? data[i + 1] : 0);
    while (sum > 65535)
        sum = (sum & 65535) + (sum >> 16);
    return sum == 65535 ? "good" : "bad";
}
std::string mac(Integer address) {
    std::vector<std::string> parts;
    for (int i = 5; i >= 0; --i)
        parts.push_back(hex((address >> (8 * i)) & 255, 2));
    return join(parts, ":");
}
std::string ipv4(Integer address) {
    std::vector<std::string> parts;
    for (int i = 3; i >= 0; --i)
        parts.push_back(decimal((address >> (8 * i)) & 255));
    return join(parts, ".");
}
Bytes ethernet(Packet &p, const Bytes &b) {
    if (b.size() < 14)
        throw std::string("eth: truncated");
    p.n("eth.dst", read_integer(b, 0, 6));
    p.n("eth.src", read_integer(b, 6, 6));
    p.n("eth.type", read_integer(b, 12, 2));
    return slice(b, 14, b.size());
}
void arp(Packet &p, const Bytes &b) {
    if (b.size() < 28)
        throw std::string("arp: truncated");
    if (read_integer(b, 0, 2) != 1 || read_integer(b, 2, 2) != 2048 || b[4] != 6 || b[5] != 4)
        throw std::string("arp: unsupported format");
    p.n("arp.opcode", read_integer(b, 6, 2));
    p.n("arp.src.hw", read_integer(b, 8, 6));
    p.n("arp.src.ip", read_integer(b, 14, 4));
    p.n("arp.dst.hw", read_integer(b, 18, 6));
    p.n("arp.dst.ip", read_integer(b, 24, 4));
}
Bytes internet(Packet &p, const Bytes &b) {
    if (b.size() < 20)
        throw std::string("ip: truncated header");
    const int version = b[0] / 16, h = (b[0] % 16) * 4;
    if (version != 4)
        throw "ip: bad version " + decimal(version);
    if (h < 20)
        throw "ip: bad header length " + decimal(h);
    if (b.size() < std::size_t(h))
        throw std::string("ip: truncated header");
    const Integer total = read_integer(b, 2, 2), flags = read_integer(b, 6, 2);
    if (total < h)
        throw "ip: bad total length " + decimal(total);
    if (total > Integer(b.size()))
        throw "ip: truncated (total length " + decimal(total) + ", available " + decimal(b.size()) + ")";
    p.n("ip.hdr_len", h);
    p.n("ip.tos", b[1]);
    p.n("ip.len", total);
    p.n("ip.id", read_integer(b, 4, 2));
    p.n("ip.flags.df", (flags >> 14) & 1);
    p.n("ip.flags.mf", (flags >> 13) & 1);
    p.n("ip.frag_offset", (flags % 8192) * 8);
    p.n("ip.ttl", b[8]);
    p.n("ip.proto", b[9]);
    p.n("ip.checksum", read_integer(b, 10, 2));
    p.s("ip.checksum.status", checksum(slice(b, 0, h)));
    p.n("ip.src", read_integer(b, 12, 4));
    p.n("ip.dst", read_integer(b, 16, 4));
    if (p.num("ip.flags.mf") || p.num("ip.frag_offset"))
        p.flag("ip.fragment");
    return slice(b, h, total);
}
