#include "capture.h"
Integer read_integer(Bytes data, size_t position, size_t count) {
    Integer value = 0;
    for (size_t i = 0; i < count; ++i)
        value = value * 256 + data.data[position + i];
    return value;
}
Bytes slice(Bytes data, size_t first, size_t last) {
    return (Bytes){data.data + first, last - first};
}
const char *checksum(Bytes data) {
    Integer sum = 0;
    for (size_t i = 0; i < data.len; i += 2)
        sum += (Integer)data.data[i] * 256 + (i + 1 < data.len ? data.data[i + 1] : 0);
    while (sum > 65535)
        sum = (sum & 65535) + (sum >> 16);
    return sum == 65535 ? "good" : "bad";
}
char *mac(Integer value) {
    Text out = {0};
    for (int i = 5; i >= 0; --i)
        text_add(&out, "%s%02" PRIx64, i == 5 ? "" : ":", (uint64_t)((value >> (8 * i)) & 255));
    return out.data;
}
char *ipv4(Integer value) {
    return format("%" PRId64 ".%" PRId64 ".%" PRId64 ".%" PRId64, (value >> 24) & 255, (value >> 16) & 255,
                  (value >> 8) & 255, value & 255);
}
Bytes ethernet(Packet *p, Bytes b) {
    if (b.len < 14) {
        packet_error(p, "eth: truncated");
        return (Bytes){0};
    }
    pn(p, F_ETH_DST, read_integer(b, 0, 6), false);
    pn(p, F_ETH_SRC, read_integer(b, 6, 6), false);
    pn(p, F_ETH_TYPE, read_integer(b, 12, 2), false);
    return slice(b, 14, b.len);
}
void arp(Packet *p, Bytes b) {
    if (b.len < 28) {
        packet_error(p, "arp: truncated");
        return;
    }
    if (read_integer(b, 0, 2) != 1 || read_integer(b, 2, 2) != 2048 || b.data[4] != 6 || b.data[5] != 4) {
        packet_error(p, "arp: unsupported format");
        return;
    }
    pn(p, F_ARP_OPCODE, read_integer(b, 6, 2), false);
    pn(p, F_ARP_SRC_HW, read_integer(b, 8, 6), false);
    pn(p, F_ARP_SRC_IP, read_integer(b, 14, 4), false);
    pn(p, F_ARP_DST_HW, read_integer(b, 18, 6), false);
    pn(p, F_ARP_DST_IP, read_integer(b, 24, 4), false);
}
Bytes internet(Packet *p, Bytes b) {
    if (b.len < 20) {
        packet_error(p, "ip: truncated header");
        return (Bytes){0};
    }
    int version = b.data[0] / 16, h = (b.data[0] % 16) * 4;
    if (version != 4) {
        packet_error(p, "ip: bad version %d", version);
        return (Bytes){0};
    }
    if (h < 20) {
        packet_error(p, "ip: bad header length %d", h);
        return (Bytes){0};
    }
    if (b.len < (size_t)h) {
        packet_error(p, "ip: truncated header");
        return (Bytes){0};
    }
    Integer total = read_integer(b, 2, 2), flags = read_integer(b, 6, 2);
    if (total < h) {
        packet_error(p, "ip: bad total length %" PRId64, total);
        return (Bytes){0};
    }
    if (total > (Integer)b.len) {
        packet_error(p, "ip: truncated (total length %" PRId64 ", available %zu)", total, b.len);
        return (Bytes){0};
    }
    pn(p, F_IP_HDR_LEN, h, false);
    pn(p, F_IP_TOS, b.data[1], false);
    pn(p, F_IP_LEN, total, false);
    pn(p, F_IP_ID, read_integer(b, 4, 2), false);
    pn(p, F_IP_FLAGS_DF, (flags >> 14) & 1, false);
    pn(p, F_IP_FLAGS_MF, (flags >> 13) & 1, false);
    pn(p, F_IP_FRAG_OFFSET, (flags % 8192) * 8, false);
    pn(p, F_IP_TTL, b.data[8], false);
    pn(p, F_IP_PROTO, b.data[9], false);
    pn(p, F_IP_CHECKSUM, read_integer(b, 10, 2), false);
    ps(p, F_IP_CHECKSUM_STATUS, checksum(slice(b, 0, h)), false);
    pn(p, F_IP_SRC, read_integer(b, 12, 4), false);
    pn(p, F_IP_DST, read_integer(b, 16, 4), false);
    if (num(p, F_IP_FLAGS_MF) || num(p, F_IP_FRAG_OFFSET))
        flag(p, F_IP_FRAGMENT);
    return slice(b, h, total);
}
