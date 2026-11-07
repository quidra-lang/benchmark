#include "capture.h"
static Bytes pseudo(const Packet *p, Bytes data, int protocol) {
    Bytes out = {allocate(data.len + 12, 1), data.len + 12};
    Field names[2] = {F_IP_SRC, F_IP_DST};
    size_t cursor = 0;
    for (int a = 0; a < 2; ++a)
        for (int i = 3; i >= 0; --i)
            out.data[cursor++] = (unsigned char)((num(p, names[a]) >> (8 * i)) & 255);
    out.data[cursor++] = 0;
    out.data[cursor++] = (unsigned char)protocol;
    out.data[cursor++] = (unsigned char)(data.len / 256);
    out.data[cursor++] = (unsigned char)(data.len % 256);
    memcpy(out.data + 12, data.data, data.len);
    return out;
}
Bytes icmp(Packet *p, Bytes b) {
    if (b.len < 8) {
        packet_error(p, "icmp: truncated");
        return (Bytes){0};
    }
    pn(p, F_ICMP_TYPE, b.data[0], false);
    pn(p, F_ICMP_CODE, b.data[1], false);
    pn(p, F_ICMP_CHECKSUM, read_integer(b, 2, 2), false);
    ps(p, F_ICMP_CHECKSUM_STATUS, checksum(b), false);
    if (b.data[0] == 0 || b.data[0] == 8) {
        pn(p, F_ICMP_ID, read_integer(b, 4, 2), false);
        pn(p, F_ICMP_SEQ, read_integer(b, 6, 2), false);
    }
    return slice(b, 8, b.len);
}
Bytes udp(Packet *p, Bytes b) {
    if (b.len < 8) {
        packet_error(p, "udp: truncated");
        return (Bytes){0};
    }
    Integer length = read_integer(b, 4, 2);
    if (length < 8 || length > (Integer)b.len) {
        packet_error(p, "udp: bad length %" PRId64, length);
        return (Bytes){0};
    }
    pn(p, F_UDP_SRCPORT, read_integer(b, 0, 2), false);
    pn(p, F_UDP_DSTPORT, read_integer(b, 2, 2), false);
    pn(p, F_UDP_LENGTH, length, false);
    pn(p, F_UDP_CHECKSUM, read_integer(b, 6, 2), false);
    ps(p, F_UDP_CHECKSUM_STATUS,
       num(p, F_UDP_CHECKSUM) == 0 ? "none" : checksum(pseudo(p, slice(b, 0, length), 17)), false);
    return slice(b, 8, length);
}
Bytes tcp(Packet *p, Bytes b) {
    if (b.len < 20) {
        packet_error(p, "tcp: truncated header");
        return (Bytes){0};
    }
    int h = (b.data[12] / 16) * 4;
    if (h < 20) {
        packet_error(p, "tcp: bad header length %d", h);
        return (Bytes){0};
    }
    if ((size_t)h > b.len) {
        packet_error(p, "tcp: truncated header");
        return (Bytes){0};
    }
    pn(p, F_TCP_SRCPORT, read_integer(b, 0, 2), false);
    pn(p, F_TCP_DSTPORT, read_integer(b, 2, 2), false);
    pn(p, F_TCP_SEQ_RAW, read_integer(b, 4, 4), false);
    pn(p, F_TCP_HDR_LEN, h, false);
    pn(p, F_TCP_FLAGS, b.data[13], false);
    Field flags[6] = {F_TCP_FLAGS_FIN, F_TCP_FLAGS_SYN, F_TCP_FLAGS_RST,
                      F_TCP_FLAGS_PSH, F_TCP_FLAGS_ACK, F_TCP_FLAGS_URG};
    for (int i = 0; i < 6; ++i)
        pn(p, flags[i], (b.data[13] >> i) & 1, false);
    if (b.data[13] & 16)
        pn(p, F_TCP_ACK_RAW, read_integer(b, 8, 4), false);
    pn(p, F_TCP_WINDOW, read_integer(b, 14, 2), false);
    pn(p, F_TCP_CHECKSUM, read_integer(b, 16, 2), false);
    ps(p, F_TCP_CHECKSUM_STATUS, checksum(pseudo(p, b, 6)), false);
    pn(p, F_TCP_URGENT, read_integer(b, 18, 2), false);
    pn(p, F_TCP_LEN, b.len - h, false);
    for (int i = 20; i < h;) {
        int kind = b.data[i];
        if (kind == 0) {
            ps(p, F_TCP_OPTION, "EOL", true);
            break;
        }
        if (kind == 1) {
            ps(p, F_TCP_OPTION, "NOP", true);
            ++i;
            continue;
        }
        int length = i + 1 < h ? b.data[i + 1] : 0;
        if (length < 2 || i + length > h || (kind == 2 && length != 4) || (kind == 3 && length != 3) ||
            (kind == 4 && length != 2) ||
            (kind == 5 && length != 10 && length != 18 && length != 26 && length != 34) ||
            (kind == 8 && length != 10)) {
            flag(p, F_TCP_OPTIONS_MALFORMED);
            break;
        }
        char *option;
        if (kind == 2) {
            Integer value = read_integer(b, i + 2, 2);
            option = format("MSS %" PRId64, value);
            pn(p, F_TCP_OPTIONS_MSS, value, false);
        } else if (kind == 3) {
            option = format("WS %u", b.data[i + 2]);
            pn(p, F_TCP_OPTIONS_WSCALE, b.data[i + 2], false);
        } else if (kind == 4)
            option = "SACK_PERM";
        else if (kind == 5) {
            Text text = {0};
            text_add(&text, "SACK");
            for (int j = i + 2; j < i + length; j += 8)
                text_add(&text, " %" PRId64 "-%" PRId64, read_integer(b, j, 4), read_integer(b, j + 4, 4));
            option = text.data;
        } else if (kind == 8)
            option = format("TS %" PRId64 " %" PRId64, read_integer(b, i + 2, 4), read_integer(b, i + 6, 4));
        else
            option = format("kind %d len %d", kind, length);
        ps(p, F_TCP_OPTION, option, true);
        i += length;
    }
    return slice(b, h, b.len);
}
