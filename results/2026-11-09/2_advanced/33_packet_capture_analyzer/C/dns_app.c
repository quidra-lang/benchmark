#include "capture.h"
char *type_name(Integer type) {
    switch (type) {
    case 1:
        return "A";
    case 2:
        return "NS";
    case 5:
        return "CNAME";
    case 6:
        return "SOA";
    case 12:
        return "PTR";
    case 15:
        return "MX";
    case 16:
        return "TXT";
    case 28:
        return "AAAA";
    default:
        return format("TYPE%" PRId64, type);
    }
}
char *rcode_name(Integer code) {
    const char *names[6] = {"NoError", "FormErr", "ServFail", "NXDomain", "NotImp", "Refused"};
    return code < 6 ? (char *)names[code] : format("RCODE%" PRId64, code);
}
typedef struct {
    Packet *packet;
    Bytes data;
    jmp_buf abort;
} DnsReader;
static void fail(DnsReader *r, const char *reason) {
    packet_error(r->packet, "%s", reason);
    longjmp(r->abort, 1);
}
static void need(DnsReader *r, size_t position, size_t count) {
    if (position > r->data.len || count > r->data.len - position)
        fail(r, "dns: truncated");
}
static Integer integer(DnsReader *r, size_t *position, size_t count) {
    need(r, *position, count);
    Integer value = read_integer(r->data, *position, count);
    *position += count;
    return value;
}
static char *name(DnsReader *r, size_t *position) {
    size_t cursor = *position, end = 0;
    int pointers = 0;
    Text text = {0};
    bool first = true;
    for (;;) {
        need(r, cursor, 1);
        int count = r->data.data[cursor];
        if (count == 0) {
            if (!end)
                end = cursor + 1;
            break;
        }
        if (count >= 192) {
            need(r, cursor + 1, 1);
            if (!end)
                end = cursor + 2;
            if (++pointers > 16)
                fail(r, "dns: compression loop");
            size_t target = (size_t)(count - 192) * 256 + r->data.data[cursor + 1];
            if (target >= r->data.len)
                fail(r, "dns: pointer out of range");
            cursor = target;
            continue;
        }
        if (count >= 64)
            fail(r, "dns: bad label type");
        need(r, cursor + 1, count);
        if (!first)
            text_add(&text, ".");
        first = false;
        for (int j = 0; j < count; ++j) {
            unsigned char c = r->data.data[cursor + 1 + j];
            if (c >= 33 && c <= 126 && c != 46 && c != 92)
                text_add(&text, "%c", c);
            else
                text_add(&text, "\\%03u", c);
        }
        cursor += (size_t)count + 1;
    }
    *position = end;
    return first ? "<root>" : text.data;
}
static char *ipv6(DnsReader *r, size_t *position) {
    Integer values[8];
    char *groups[8];
    for (int i = 0; i < 8; ++i) {
        values[i] = integer(r, position, 2);
        groups[i] = hexadecimal(values[i], 0);
    }
    int start = -1, length = 1;
    for (int i = 0; i < 8;) {
        if (values[i]) {
            ++i;
            continue;
        }
        int end = i;
        while (end < 8 && !values[end])
            ++end;
        if (end - i > length) {
            start = i;
            length = end - i;
        }
        i = end;
    }
    Text text = {0};
    if (start < 0) {
        for (int i = 0; i < 8; ++i)
            text_add(&text, "%s%s", i ? ":" : "", groups[i]);
        return text.data;
    }
    for (int i = 0; i < start; ++i)
        text_add(&text, "%s%s", i ? ":" : "", groups[i]);
    text_add(&text, "::");
    for (int i = start + length; i < 8; ++i)
        text_add(&text, "%s%s", i == start + length ? "" : ":", groups[i]);
    return text.data;
}
void dns(Packet *p, Bytes b) {
    DnsReader *r = allocate(1, sizeof *r);
    r->packet = p;
    r->data = b;
    if (setjmp(r->abort))
        return;
    need(r, 0, 12);
    size_t position = 0;
    pn(p, F_DNS_ID, integer(r, &position, 2), false);
    Integer flags = integer(r, &position, 2);
    pn(p, F_DNS_FLAGS, flags, false);
    pn(p, F_DNS_FLAGS_RESPONSE, (flags >> 15) & 1, false);
    pn(p, F_DNS_FLAGS_OPCODE, (flags >> 11) & 15, false);
    pn(p, F_DNS_FLAGS_RCODE, flags & 15, false);
    Field fields[4] = {F_DNS_COUNT_QUERIES, F_DNS_COUNT_ANSWERS, F_DNS_COUNT_AUTH_RR, F_DNS_COUNT_ADD_RR};
    Integer counts[4];
    for (int i = 0; i < 4; ++i) {
        counts[i] = integer(r, &position, 2);
        pn(p, fields[i], counts[i], false);
    }
    for (Integer q = 0; q < counts[0]; ++q) {
        char *question = name(r, &position);
        need(r, position, 4);
        Integer type = integer(r, &position, 2);
        position += 2;
        ps(p, F_DNS_QRY_NAME, question, true);
        pn(p, F_DNS_QRY_TYPE, type, true);
    }
    Field sections[3] = {F_DNS_ANSWER, F_DNS_AUTHORITY, F_DNS_ADDITIONAL};
    for (int section = 0; section < 3; ++section)
        for (Integer record = 0; record < counts[section + 1]; ++record) {
            char *owner = name(r, &position);
            need(r, position, 10);
            Integer type = integer(r, &position, 2);
            Integer klass = integer(r, &position, 2);
            Integer ttl = integer(r, &position, 4);
            Integer length = integer(r, &position, 2);
            need(r, position, length);
            size_t end = position + (size_t)length;
            char *body;
            Integer address = 0;
            if (type == 1) {
                address = integer(r, &position, 4);
                body = ipv4(address);
            } else if (type == 28)
                body = ipv6(r, &position);
            else if (type == 2 || type == 5 || type == 12)
                body = name(r, &position);
            else if (type == 15) {
                Integer preference = integer(r, &position, 2);
                body = format("%" PRId64 " %s", preference, name(r, &position));
            } else if (type == 6) {
                Text text = {0};
                char *m = name(r, &position);
                char *n = name(r, &position);
                text_add(&text, "%s %s", m, n);
                for (int i = 0; i < 5; ++i)
                    text_add(&text, " %" PRId64, integer(r, &position, 4));
                body = text.data;
            } else {
                body = format("%" PRId64 " bytes", length);
                position = end;
            }
            if (position != end)
                fail(r, "dns: bad rdata length");
            ps(p, sections[section],
               format("%s %s %s %" PRId64 " %s", owner, type_name(type),
                      klass == 1 ? "IN" : format("CLASS%" PRId64, klass), ttl, body),
               true);
            if (section == 0) {
                grow((void **)&p->answers, &p->answer_cap, p->answer_count + 1, sizeof *p->answers);
                p->answers[p->answer_count++] = (Answer){type, body};
                if (type == 1)
                    pn(p, F_DNS_A, address, true);
            }
        }
}
