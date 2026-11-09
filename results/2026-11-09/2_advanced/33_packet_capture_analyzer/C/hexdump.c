#include "capture.h"
static int lower_hex(char c) {
    return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1;
}
static bool well_formed(const char *text) {
    const size_t n = strlen(text);
    if (n < 8 || n > 53 || (n - 8) % 3 != 0 || text[4] != ' ' || text[5] != ' ')
        return false;
    for (int i = 0; i < 4; ++i)
        if (lower_hex(text[i]) < 0)
            return false;
    for (size_t i = 6; i < n; i += 3) {
        if (lower_hex(text[i]) < 0 || lower_hex(text[i + 1]) < 0 || (i + 2 < n && text[i + 2] != ' '))
            return false;
    }
    return true;
}
static void finish(Packet *p) {
    if (!p->reason && p->raw.len != (size_t)p->length)
        packet_error(p, "dump: length mismatch (header %" PRId64 ", data %zu)", p->length, p->raw.len);
}
Packet *read_capture(size_t *count) {
    Lines lines = read_lines("input/capture.txt");
    Packet *packets = allocate(2000, sizeof *packets);
    *count = 0;
    size_t raw_cap = 0;
    for (size_t line = 0; line < lines.len; ++line) {
        const char *text = lines.data[line];
        if (strncmp(text, "PACKET ", 7) == 0) {
            if (*count)
                finish(&packets[*count - 1]);
            Packet *p = &packets[(*count)++];
            sscanf(text + 7, "%" SCNd64 " %" SCNd64 " %" SCNd64, &p->number, &p->time, &p->length);
            raw_cap = 0;
            continue;
        }
        Packet *p = &packets[*count - 1];
        if (!*text || p->reason)
            continue;
        if (!well_formed(text)) {
            packet_error(p, "dump: bad line %zu", line + 1);
            continue;
        }
        size_t offset = 0;
        for (int i = 0; i < 4; ++i)
            offset = offset * 16 + lower_hex(text[i]);
        if (offset != p->raw.len) {
            packet_error(p, "dump: offset mismatch at line %zu", line + 1);
            continue;
        }
        for (size_t i = 6; text[i]; i += 3) {
            grow((void **)&p->raw.data, &raw_cap, p->raw.len + 1, 1);
            p->raw.data[p->raw.len++] = (unsigned char)(lower_hex(text[i]) * 16 + lower_hex(text[i + 1]));
            if (!text[i + 2])
                break;
        }
    }
    finish(&packets[*count - 1]);
    return packets;
}
Lines dump_lines(Bytes data) {
    Lines lines = {0};
    for (size_t start = 0; start < data.len; start += 16) {
        Text bytes = {0}, chars = {0};
        size_t end = start + 16 < data.len ? start + 16 : data.len;
        for (size_t i = start; i < end; ++i) {
            text_add(&bytes, "%s%02x", i == start ? "" : " ", data.data[i]);
            text_add(&chars, "%c", data.data[i] >= 32 && data.data[i] <= 126 ? data.data[i] : '.');
        }
        line_add(&lines, "%04zx  %-47s  |%s|", start, bytes.data, chars.data);
    }
    return lines;
}
