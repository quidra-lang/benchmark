#include "capture.h"
const struct FieldSpec field_specs[FIELD_COUNT] = {
    {"frame.number", TYPE_INTEGER},
    {"frame.time", TYPE_INTEGER},
    {"frame.len", TYPE_INTEGER},
    {"frame.protocols", TYPE_STRING},
    {"frame.malformed", TYPE_STRING},
    {"frame.bad_checksum", TYPE_PRESENCE},
    {"eth.dst", TYPE_MAC},
    {"eth.src", TYPE_MAC},
    {"eth.type", TYPE_HEX4},
    {"arp.opcode", TYPE_INTEGER},
    {"arp.src.hw", TYPE_MAC},
    {"arp.src.ip", TYPE_IPV4},
    {"arp.dst.hw", TYPE_MAC},
    {"arp.dst.ip", TYPE_IPV4},
    {"ip.hdr_len", TYPE_INTEGER},
    {"ip.tos", TYPE_HEX2},
    {"ip.len", TYPE_INTEGER},
    {"ip.id", TYPE_HEX4},
    {"ip.flags.df", TYPE_INTEGER},
    {"ip.flags.mf", TYPE_INTEGER},
    {"ip.frag_offset", TYPE_INTEGER},
    {"ip.ttl", TYPE_INTEGER},
    {"ip.proto", TYPE_INTEGER},
    {"ip.checksum", TYPE_HEX4},
    {"ip.checksum.status", TYPE_STRING},
    {"ip.src", TYPE_IPV4},
    {"ip.dst", TYPE_IPV4},
    {"ip.fragment", TYPE_PRESENCE},
    {"icmp.type", TYPE_INTEGER},
    {"icmp.code", TYPE_INTEGER},
    {"icmp.checksum", TYPE_HEX4},
    {"icmp.checksum.status", TYPE_STRING},
    {"icmp.id", TYPE_INTEGER},
    {"icmp.seq", TYPE_INTEGER},
    {"udp.srcport", TYPE_INTEGER},
    {"udp.dstport", TYPE_INTEGER},
    {"udp.length", TYPE_INTEGER},
    {"udp.checksum", TYPE_HEX4},
    {"udp.checksum.status", TYPE_STRING},
    {"tcp.srcport", TYPE_INTEGER},
    {"tcp.dstport", TYPE_INTEGER},
    {"tcp.stream", TYPE_INTEGER},
    {"tcp.seq", TYPE_INTEGER},
    {"tcp.seq_raw", TYPE_INTEGER},
    {"tcp.ack", TYPE_INTEGER},
    {"tcp.ack_raw", TYPE_INTEGER},
    {"tcp.hdr_len", TYPE_INTEGER},
    {"tcp.flags", TYPE_HEX2},
    {"tcp.flags.fin", TYPE_INTEGER},
    {"tcp.flags.syn", TYPE_INTEGER},
    {"tcp.flags.rst", TYPE_INTEGER},
    {"tcp.flags.psh", TYPE_INTEGER},
    {"tcp.flags.ack", TYPE_INTEGER},
    {"tcp.flags.urg", TYPE_INTEGER},
    {"tcp.window", TYPE_INTEGER},
    {"tcp.window.calc", TYPE_INTEGER},
    {"tcp.checksum", TYPE_HEX4},
    {"tcp.checksum.status", TYPE_STRING},
    {"tcp.urgent", TYPE_INTEGER},
    {"tcp.option", TYPE_STRING},
    {"tcp.options.mss", TYPE_INTEGER},
    {"tcp.options.wscale", TYPE_INTEGER},
    {"tcp.options.malformed", TYPE_PRESENCE},
    {"tcp.len", TYPE_INTEGER},
    {"tcp.analysis.retransmission", TYPE_PRESENCE},
    {"tcp.analysis.out_of_order", TYPE_PRESENCE},
    {"tcp.analysis.lost_segment", TYPE_PRESENCE},
    {"tcp.analysis.duplicate_ack", TYPE_PRESENCE},
    {"dns.id", TYPE_HEX4},
    {"dns.flags", TYPE_HEX4},
    {"dns.flags.response", TYPE_INTEGER},
    {"dns.flags.opcode", TYPE_INTEGER},
    {"dns.flags.rcode", TYPE_INTEGER},
    {"dns.count.queries", TYPE_INTEGER},
    {"dns.count.answers", TYPE_INTEGER},
    {"dns.count.auth_rr", TYPE_INTEGER},
    {"dns.count.add_rr", TYPE_INTEGER},
    {"dns.qry.name", TYPE_STRING},
    {"dns.qry.type", TYPE_INTEGER},
    {"dns.answer", TYPE_STRING},
    {"dns.authority", TYPE_STRING},
    {"dns.additional", TYPE_STRING},
    {"dns.a", TYPE_IPV4},
    {"data.len", TYPE_INTEGER},
    {"eth.addr", TYPE_MAC},
    {"ip.addr", TYPE_IPV4},
    {"udp.port", TYPE_INTEGER},
    {"tcp.port", TYPE_INTEGER},
    {"eth", TYPE_PRESENCE},
    {"arp", TYPE_PRESENCE},
    {"ip", TYPE_PRESENCE},
    {"icmp", TYPE_PRESENCE},
    {"udp", TYPE_PRESENCE},
    {"tcp", TYPE_PRESENCE},
    {"dns", TYPE_PRESENCE},
    {"data", TYPE_PRESENCE},
};
void *allocate(size_t count, size_t size) {
    void *value = calloc(count ? count : 1, size);
    if (!value)
        exit(EXIT_FAILURE);
    return value;
}
void grow(void **data, size_t *cap, size_t need, size_t size) {
    if (need <= *cap)
        return;
    size_t next = *cap ? *cap : 8;
    while (next < need)
        next *= 2;
    void *value = realloc(*data, next * size);
    if (!value)
        exit(EXIT_FAILURE);
    *data = value;
    *cap = next;
}
static char *vformat(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int count = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *text = allocate((size_t)count + 1, 1);
    vsnprintf(text, (size_t)count + 1, pattern, args);
    return text;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *text = vformat(pattern, args);
    va_end(args);
    return text;
}
char *copy_string(const char *text) {
    return part(text, strlen(text));
}
char *part(const char *text, size_t size) {
    char *out = allocate(size + 1, 1);
    memcpy(out, text, size);
    return out;
}
void text_add(Text *text, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *value = vformat(pattern, args);
    va_end(args);
    size_t count = strlen(value);
    grow((void **)&text->data, &text->cap, text->len + count + 1, 1);
    memcpy(text->data + text->len, value, count + 1);
    text->len += count;
    free(value);
}
void line_add(Lines *lines, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *value = vformat(pattern, args);
    va_end(args);
    grow((void **)&lines->data, &lines->cap, lines->len + 1, sizeof *lines->data);
    lines->data[lines->len++] = value;
}
Lines read_lines(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file)
        exit(EXIT_FAILURE);
    fseek(file, 0, SEEK_END);
    long length = ftell(file);
    rewind(file);
    char *data = allocate((size_t)length + 1, 1);
    size_t size = fread(data, 1, (size_t)length, file);
    fclose(file);
    Lines out = {0};
    size_t first = 0;
    for (size_t i = 0; i < size; ++i)
        if (data[i] == '\n') {
            data[i] = 0;
            line_add(&out, "%s", data + first);
            first = i + 1;
        }
    return out;
}
void write_lines(const char *name, Lines lines) {
    FILE *file = fopen(format("output/%s", name), "wb");
    if (!file)
        exit(EXIT_FAILURE);
    for (size_t i = 0; i < lines.len; ++i)
        fprintf(file, "%s\n", lines.data[i]);
    fclose(file);
}
void pn(Packet *p, Field field, Integer value, bool append) {
    Values *values = &p->fields[field];
    if (!append)
        values->len = 0;
    grow((void **)&values->data, &values->cap, values->len + 1, sizeof *values->data);
    values->data[values->len++] = (Value){value, NULL};
}
void ps(Packet *p, Field field, const char *value, bool append) {
    pn(p, field, 0, append);
    p->fields[field].data[p->fields[field].len - 1].text = copy_string(value);
}
void flag(Packet *p, Field field) {
    pn(p, field, 0, false);
}
bool has(const Packet *p, Field field) {
    return field < STORED_FIELDS && p->fields[field].len > 0;
}
Integer num(const Packet *p, Field field) {
    return has(p, field) ? p->fields[field].data[0].number : 0;
}
const char *str(const Packet *p, Field field) {
    return has(p, field) && p->fields[field].data[0].text ? p->fields[field].data[0].text : "";
}
void packet_error(Packet *p, const char *pattern, ...) {
    if (p->reason)
        return;
    va_list args;
    va_start(args, pattern);
    p->reason = vformat(pattern, args);
    va_end(args);
}
char *decimal(Integer value) {
    return format("%" PRId64, value);
}
char *hexadecimal(Integer value, int width) {
    return format("%0*" PRIx64, width, (uint64_t)value);
}
char *seconds(Integer value) {
    return format("%" PRId64 ".%06" PRId64, value / 1000000, value % 1000000);
}
static const char *protocols[8] = {"eth", "arp", "ip", "icmp", "udp", "tcp", "dns", "data"};
static char *notation(Type type, Value value) {
    switch (type) {
    case TYPE_HEX2:
        return format("0x%02" PRIx64, (uint64_t)value.number);
    case TYPE_HEX4:
        return format("0x%04" PRIx64, (uint64_t)value.number);
    case TYPE_IPV4:
        return ipv4(value.number);
    case TYPE_MAC:
        return mac(value.number);
    case TYPE_STRING:
        return value.text;
    case TYPE_PRESENCE:
        return "";
    default:
        return decimal(value.number);
    }
}
static char *value_text(const Packet *p, Field field) {
    return notation(field_specs[field].type, p->fields[field].data[0]);
}
static Values field_values(const Packet *p, Field field) {
    if (field < STORED_FIELDS)
        return p->fields[field];
    Values result = {0};
    if (field >= F_ETH) {
        int layer = (int)field - F_ETH;
        for (int i = 0; i < p->layer_count; ++i)
            if (p->layers[i] == layer) {
                result.data = allocate(1, sizeof *result.data);
                result.len = 1;
                break;
            }
        return result;
    }
    Field names[4][2] = {{F_ETH_DST, F_ETH_SRC},
                         {F_IP_SRC, F_IP_DST},
                         {F_UDP_SRCPORT, F_UDP_DSTPORT},
                         {F_TCP_SRCPORT, F_TCP_DSTPORT}};
    int alias = (int)field - F_ETH_ADDR;
    result.data = allocate(2, sizeof *result.data);
    for (int i = 0; i < 2; ++i)
        if (has(p, names[alias][i]))
            result.data[result.len++] = p->fields[names[alias][i]].data[0];
    return result;
}
typedef enum {
    T_WORD,
    T_STRING,
    T_LPAREN,
    T_RPAREN,
    T_NOT,
    T_LT,
    T_GT,
    T_EQ,
    T_NE,
    T_LE,
    T_GE,
    T_AND,
    T_OR
} TokenKind;
typedef struct {
    TokenKind kind;
    char *text;
    size_t column;
} Token;
typedef struct Expression {
    int kind;
    Field field;
    TokenKind op;
    bool compare;
    Value value;
    struct Expression *left, *right;
} Expression;
typedef struct {
    Token tokens[201];
    size_t count, position;
    Expression nodes[201];
    size_t used;
    char *error;
    jmp_buf abort;
} Parser;
static void parser_error(Parser *p, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    p->error = vformat(pattern, args);
    va_end(args);
    longjmp(p->abort, 1);
}
static bool word_character(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' ||
           c == '_' || c == ':';
}
static void tokenize(Parser *p, const char *text) {
    size_t n = strlen(text);
    for (size_t i = 0; i < n;) {
        if (text[i] == ' ') {
            ++i;
            continue;
        }
        size_t start = i;
        const char *pairs[6] = {"==", "!=", "<=", ">=", "&&", "||"};
        TokenKind kinds[6] = {T_EQ, T_NE, T_LE, T_GE, T_AND, T_OR};
        bool found = false;
        for (int j = 0; j < 6; ++j)
            if (i + 1 < n && text[i] == pairs[j][0] && text[i + 1] == pairs[j][1]) {
                p->tokens[p->count++] = (Token){kinds[j], part(text + i, 2), i + 1};
                i += 2;
                found = true;
                break;
            }
        if (found)
            continue;
        const char *single = "()!<>";
        const char *match = strchr(single, text[i]);
        if (match) {
            TokenKind singles[5] = {T_LPAREN, T_RPAREN, T_NOT, T_LT, T_GT};
            p->tokens[p->count++] = (Token){singles[match - single], part(text + i, 1), i + 1};
            ++i;
            continue;
        }
        if (text[i] == '"') {
            ++i;
            while (i < n && text[i] != '"')
                ++i;
            if (i == n)
                parser_error(p, "unterminated string at column %zu", start + 1);
            ++i;
            p->tokens[p->count++] = (Token){T_STRING, part(text + start, i - start), start + 1};
            continue;
        }
        if (word_character(text[i])) {
            while (i < n && word_character(text[i]))
                ++i;
            char *value = part(text + start, i - start);
            TokenKind kind = !strcmp(value, "and")   ? T_AND
                             : !strcmp(value, "or")  ? T_OR
                             : !strcmp(value, "not") ? T_NOT
                                                     : T_WORD;
            p->tokens[p->count++] = (Token){kind, value, start + 1};
            continue;
        }
        parser_error(p, "invalid character '%c' at column %zu", text[i], i + 1);
    }
}
static bool next(Parser *p, TokenKind kind) {
    return p->position < p->count && p->tokens[p->position].kind == kind;
}
static Token take(Parser *p) {
    if (p->position == p->count)
        parser_error(p, "unexpected end of filter");
    return p->tokens[p->position++];
}
static void unexpected(Parser *p, Token t) {
    parser_error(p, "unexpected '%s' at column %zu", t.text, t.column);
}
static bool digits(const char *text, size_t size, int base) {
    if (!size)
        return false;
    for (size_t i = 0; i < size; ++i) {
        char c = text[i];
        if (!((c >= '0' && c <= '9') || (base == 16 && ((c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))))
            return false;
    }
    return true;
}
static Value convert(Parser *p, Field field, Token token) {
    Type type = field_specs[field].type;
    size_t n = strlen(token.text);
    if (type == TYPE_STRING && token.kind == T_STRING)
        return (Value){0, part(token.text + 1, n - 2)};
    if (token.kind == T_WORD) {
        if (type == TYPE_INTEGER || type == TYPE_HEX2 || type == TYPE_HEX4) {
            if (n <= 15 && digits(token.text, n, 10))
                return (Value){strtoll(token.text, NULL, 10), NULL};
            if (n >= 3 && n <= 14 && !strncmp(token.text, "0x", 2) && digits(token.text + 2, n - 2, 16))
                return (Value){strtoll(token.text + 2, NULL, 16), NULL};
        }
        if (type == TYPE_IPV4 || type == TYPE_MAC) {
            bool ip = type == TYPE_IPV4, valid = true;
            char delimiter = ip ? '.' : ':';
            Integer value = 0;
            size_t first = 0;
            int count = 0;
            for (size_t i = 0; i <= n; ++i)
                if (i == n || token.text[i] == delimiter) {
                    size_t length = i - first;
                    if (!(ip ? length >= 1 && length <= 3 && digits(token.text + first, length, 10)
                             : length == 2 && digits(token.text + first, length, 16))) {
                        valid = false;
                        break;
                    }
                    Integer byte = strtoll(part(token.text + first, length), NULL, ip ? 10 : 16);
                    if (byte > 255) {
                        valid = false;
                        break;
                    }
                    value = value * 256 + byte;
                    ++count;
                    first = i + 1;
                }
            if (valid && count == (ip ? 4 : 6))
                return (Value){value, NULL};
        }
    }
    parser_error(p, "invalid value %s for %s", token.text, field_specs[field].name);
    return (Value){0};
}
static Expression *expression(Parser *p);
static Expression *node(Parser *p, int kind) {
    Expression *out = &p->nodes[p->used++];
    out->kind = kind;
    return out;
}
static Expression *negation(Parser *p) {
    if (next(p, T_NOT)) {
        take(p);
        Expression *out = node(p, 2);
        out->left = negation(p);
        return out;
    }
    Token token = take(p);
    if (token.kind == T_LPAREN) {
        Expression *out = expression(p);
        Token close = take(p);
        if (close.kind != T_RPAREN)
            unexpected(p, close);
        return out;
    }
    if (token.kind != T_WORD)
        unexpected(p, token);
    Field field = FIELD_COUNT;
    for (int i = 0; i < FIELD_COUNT; ++i)
        if (!strcmp(field_specs[i].name, token.text)) {
            field = (Field)i;
            break;
        }
    if (field == FIELD_COUNT)
        parser_error(p, "unknown field %s", token.text);
    Expression *out = node(p, 3);
    out->field = field;
    if (!(next(p, T_EQ) || next(p, T_NE) || next(p, T_LT) || next(p, T_GT) || next(p, T_LE) || next(p, T_GE)))
        return out;
    Token op = take(p);
    out->compare = true;
    out->op = op.kind;
    Type type = field_specs[field].type;
    if (type == TYPE_PRESENCE || (type == TYPE_STRING && op.kind != T_EQ && op.kind != T_NE))
        parser_error(p, "operator %s not allowed for %s", op.text, token.text);
    Token value = take(p);
    if (value.kind != T_WORD && value.kind != T_STRING)
        unexpected(p, value);
    out->value = convert(p, field, value);
    return out;
}
static Expression *product(Parser *p) {
    Expression *out = negation(p);
    while (next(p, T_AND)) {
        take(p);
        Expression *parent = node(p, 1);
        parent->left = out;
        parent->right = negation(p);
        out = parent;
    }
    return out;
}
static Expression *expression(Parser *p) {
    Expression *out = product(p);
    while (next(p, T_OR)) {
        take(p);
        Expression *parent = node(p, 0);
        parent->left = out;
        parent->right = product(p);
        out = parent;
    }
    return out;
}
static bool evaluate(const Expression *e, const Packet *p) {
    if (e->kind == 0)
        return evaluate(e->left, p) || evaluate(e->right, p);
    if (e->kind == 1)
        return evaluate(e->left, p) && evaluate(e->right, p);
    if (e->kind == 2)
        return !evaluate(e->left, p);
    Values values = field_values(p, e->field);
    if (!e->compare)
        return values.len > 0;
    if (!values.len)
        return false;
    for (size_t i = 0; i < values.len; ++i) {
        Value v = values.data[i];
        int comparison = field_specs[e->field].type == TYPE_STRING ? strcmp(v.text, e->value.text)
                         : v.number < e->value.number              ? -1
                         : v.number > e->value.number              ? 1
                                                                   : 0;
        if (e->op == T_NE) {
            if (comparison == 0)
                return false;
        } else if ((e->op == T_EQ && comparison == 0) || (e->op == T_LT && comparison < 0) ||
                   (e->op == T_GT && comparison > 0) || (e->op == T_LE && comparison <= 0) ||
                   (e->op == T_GE && comparison >= 0))
            return true;
    }
    return e->op == T_NE;
}
static Bytes arp_layer(Packet *p, Bytes b) {
    arp(p, b);
    return (Bytes){0};
}
static Bytes dns_layer(Packet *p, Bytes b) {
    dns(p, b);
    return (Bytes){0};
}
static Bytes layer(Packet *p, int name, Bytes (*function)(Packet *, Bytes), Bytes data) {
    p->layers[p->layer_count++] = name;
    Bytes result = function(p, data);
    if (p->reason) {
        char *prefix = format("%s.", protocols[name]);
        for (int f = 0; f < STORED_FIELDS; ++f)
            if (!strncmp(field_specs[f].name, prefix, strlen(prefix)))
                p->fields[f].len = 0;
        if (name == 6)
            p->answer_count = 0;
    }
    return result;
}
static void dissect(Packet *p) {
    if (p->reason)
        return;
    Bytes payload = layer(p, 0, ethernet, p->raw), remaining = {0};
    if (p->reason)
        return;
    if (num(p, F_ETH_TYPE) == 2054)
        layer(p, 1, arp_layer, payload);
    else if (num(p, F_ETH_TYPE) == 2048) {
        payload = layer(p, 2, internet, payload);
        if (p->reason)
            return;
        if (has(p, F_IP_FRAGMENT))
            remaining = payload;
        else if (num(p, F_IP_PROTO) == 1)
            remaining = layer(p, 3, icmp, payload);
        else if (num(p, F_IP_PROTO) == 17) {
            payload = layer(p, 4, udp, payload);
            if (!p->reason) {
                if (num(p, F_UDP_SRCPORT) == 53 || num(p, F_UDP_DSTPORT) == 53)
                    layer(p, 6, dns_layer, payload);
                else
                    remaining = payload;
            }
        } else if (num(p, F_IP_PROTO) == 6)
            remaining = layer(p, 5, tcp, payload);
        else
            remaining = payload;
    } else
        remaining = payload;
    if (!p->reason && remaining.len) {
        p->layers[p->layer_count++] = 7;
        p->remaining = remaining;
        pn(p, F_DATA_LEN, (Integer)remaining.len, false);
    }
}
static char *summary(const Packet *p, Integer origin) {
    char *source = has(p, F_IP_SRC)    ? ipv4(num(p, F_IP_SRC))
                   : has(p, F_ETH_SRC) ? mac(num(p, F_ETH_SRC))
                                       : "-",
         *destination = has(p, F_IP_DST)    ? ipv4(num(p, F_IP_DST))
                        : has(p, F_ETH_DST) ? mac(num(p, F_ETH_DST))
                                            : "-";
    int last = -1;
    for (int i = 0; i < p->layer_count; ++i)
        if (p->layers[i] != 7)
            last = p->layers[i];
    const char *names[7] = {"ETH", "ARP", "IPv4", "ICMP", "UDP", "TCP", "DNS"};
    Text info = {0};
    if (p->reason)
        text_add(&info, "%s", p->reason);
    else if (last == 0)
        text_add(&info, "EtherType %s", value_text(p, F_ETH_TYPE));
    else if (last == 1) {
        Integer op = num(p, F_ARP_OPCODE);
        if (op == 1)
            text_add(&info, "Who has %s? Tell %s", value_text(p, F_ARP_DST_IP), value_text(p, F_ARP_SRC_IP));
        else if (op == 2)
            text_add(&info, "%s is at %s", value_text(p, F_ARP_SRC_IP), value_text(p, F_ARP_SRC_HW));
        else
            text_add(&info, "Opcode %" PRId64, op);
    } else if (last == 2) {
        if (has(p, F_IP_FRAGMENT))
            text_add(&info, "Fragment id=%s off=%s%s", value_text(p, F_IP_ID),
                     value_text(p, F_IP_FRAG_OFFSET), num(p, F_IP_FLAGS_MF) ? " MF" : "");
        else
            text_add(&info, "Protocol %s", value_text(p, F_IP_PROTO));
    } else if (last == 3) {
        Integer type = num(p, F_ICMP_TYPE);
        if (type == 0 || type == 8)
            text_add(&info, "Echo %s id=%s seq=%s", type == 8 ? "request" : "reply", value_text(p, F_ICMP_ID),
                     value_text(p, F_ICMP_SEQ));
        else
            text_add(&info, "Type %" PRId64 " code %s", type, value_text(p, F_ICMP_CODE));
    } else if (last == 4)
        text_add(&info, "%s -> %s Len=%" PRId64, value_text(p, F_UDP_SRCPORT), value_text(p, F_UDP_DSTPORT),
                 num(p, F_UDP_LENGTH) - 8);
    else if (last == 5) {
        if (has(p, F_TCP_ANALYSIS_RETRANSMISSION))
            text_add(&info, "[TCP Retransmission] ");
        else if (has(p, F_TCP_ANALYSIS_OUT_OF_ORDER))
            text_add(&info, "[TCP Out-Of-Order] ");
        else if (has(p, F_TCP_ANALYSIS_LOST_SEGMENT))
            text_add(&info, "[TCP Previous segment not captured] ");
        else if (has(p, F_TCP_ANALYSIS_DUPLICATE_ACK))
            text_add(&info, "[TCP Dup ACK %" PRId64 "#%" PRId64 "] ", p->duplicate_origin,
                     p->duplicate_count);
        const char *flags[8] = {"FIN", "SYN", "RST", "PSH", "ACK", "URG", "ECE", "CWR"};
        Text enabled = {0};
        for (int i = 0; i < 8; ++i)
            if (num(p, F_TCP_FLAGS) & (INT64_C(1) << i))
                text_add(&enabled, "%s%s", enabled.len ? ", " : "", flags[i]);
        text_add(&info, "%s -> %s [%s] Seq=%s", value_text(p, F_TCP_SRCPORT), value_text(p, F_TCP_DSTPORT),
                 enabled.len ? enabled.data : "<None>", value_text(p, F_TCP_SEQ));
        if (num(p, F_TCP_FLAGS_ACK))
            text_add(&info, " Ack=%s", value_text(p, F_TCP_ACK));
        text_add(&info, " Win=%s Len=%s", value_text(p, F_TCP_WINDOW_CALC), value_text(p, F_TCP_LEN));
        Values options = p->fields[F_TCP_OPTION];
        for (size_t i = 0; i < options.len; ++i) {
            const char *option = options.data[i].text;
            Integer a, b;
            if (sscanf(option, "MSS %" SCNd64, &a) == 1)
                text_add(&info, " MSS=%" PRId64, a);
            else if (sscanf(option, "WS %" SCNd64, &a) == 1)
                text_add(&info, " WS=%" PRId64, INT64_C(1) << a);
            else if (!strcmp(option, "SACK_PERM"))
                text_add(&info, " SACK_PERM");
            else if (sscanf(option, "TS %" SCNd64 " %" SCNd64, &a, &b) == 2)
                text_add(&info, " TSval=%" PRId64 " TSecr=%" PRId64, a, b);
        }
    } else if (last == 6) {
        text_add(&info, "%s %s", num(p, F_DNS_FLAGS_RESPONSE) ? "Response" : "Query",
                 value_text(p, F_DNS_ID));
        if (num(p, F_DNS_FLAGS_RCODE))
            text_add(&info, " %s", rcode_name(num(p, F_DNS_FLAGS_RCODE)));
        for (size_t i = 0; i < p->fields[F_DNS_QRY_NAME].len; ++i)
            text_add(&info, " %s %s", type_name(p->fields[F_DNS_QRY_TYPE].data[i].number),
                     p->fields[F_DNS_QRY_NAME].data[i].text);
        for (size_t i = 0; i < p->answer_count; ++i)
            text_add(&info, " %s %s", type_name(p->answers[i].type), p->answers[i].body);
    }
    if (has(p, F_TCP_OPTIONS_MALFORMED))
        text_add(&info, " [bad TCP options]");
    Field checks[4] = {F_IP_CHECKSUM_STATUS, F_ICMP_CHECKSUM_STATUS, F_UDP_CHECKSUM_STATUS,
                       F_TCP_CHECKSUM_STATUS};
    const char *labels[4] = {"IPv4", "ICMP", "UDP", "TCP"};
    for (int i = 0; i < 4; ++i)
        if (!strcmp(str(p, checks[i]), "bad"))
            text_add(&info, " [bad %s checksum]", labels[i]);
    return format("%" PRId64 " %s %s -> %s %s %" PRId64 " %s", p->number, seconds(p->time - origin), source,
                  destination, last < 0 ? "DUMP" : names[last], p->length, info.data);
}
static char *optional(Integer value) {
    return value >= 0 ? decimal(value) : "-";
}
typedef struct {
    char *name;
    Integer count;
} NameCount;
static int name_compare(const void *pa, const void *pb) {
    const NameCount *a = pa, *b = pb;
    if (a->count != b->count)
        return a->count > b->count ? -1 : 1;
    return strcmp(a->name, b->name);
}
int main(void) {
    size_t count;
    Packet *packets = read_capture(&count);
    Stream *streams = allocate(count, sizeof *streams);
    size_t stream_count = 0;
    Integer origin = packets[0].time;
    Field checks[4] = {F_IP_CHECKSUM_STATUS, F_ICMP_CHECKSUM_STATUS, F_UDP_CHECKSUM_STATUS,
                       F_TCP_CHECKSUM_STATUS};
    Field marks[4] = {F_TCP_ANALYSIS_RETRANSMISSION, F_TCP_ANALYSIS_OUT_OF_ORDER, F_TCP_ANALYSIS_LOST_SEGMENT,
                      F_TCP_ANALYSIS_DUPLICATE_ACK};
    for (size_t i = 0; i < count; ++i) {
        Packet *p = &packets[i];
        dissect(p);
        track(p, streams, &stream_count);
        pn(p, F_FRAME_NUMBER, p->number, false);
        pn(p, F_FRAME_TIME, p->time - origin, false);
        pn(p, F_FRAME_LEN, p->length, false);
        Text layers = {0};
        for (int j = 0; j < p->layer_count; ++j)
            text_add(&layers, "%s%s", j ? ":" : "", protocols[p->layers[j]]);
        if (p->layer_count)
            ps(p, F_FRAME_PROTOCOLS, layers.data, false);
        if (p->reason)
            ps(p, F_FRAME_MALFORMED, p->reason, false);
        for (int j = 0; j < 4; ++j)
            if (!strcmp(str(p, checks[j]), "bad"))
                flag(p, F_FRAME_BAD_CHECKSUM);
    }
    Lines summaries = {0}, summary_lines = {0}, details = {0};
    for (size_t i = 0; i < count; ++i) {
        char *line = summary(&packets[i], origin);
        line_add(&summaries, "%s", line);
        line_add(&summary_lines, "%s", line);
    }
    bool first_detail = true;
    Lines requests = read_lines("input/filters.txt");
    for (size_t i = 0; i < requests.len; ++i) {
        char *request = requests.data[i];
        if (!*request || *request == '#')
            continue;
        if (!strncmp(request, "FILTER ", 7)) {
            line_add(&summary_lines, "");
            line_add(&summary_lines, "filter %s", request + 7);
            Parser *parser = allocate(1, sizeof *parser);
            if (setjmp(parser->abort)) {
                line_add(&summary_lines, "error: %s", parser->error);
                continue;
            }
            tokenize(parser, request + 7);
            Expression *filter = expression(parser);
            if (parser->position != parser->count)
                unexpected(parser, parser->tokens[parser->position]);
            size_t matched = 0;
            for (size_t j = 0; j < count; ++j)
                if (evaluate(filter, &packets[j])) {
                    line_add(&summary_lines, "%s", summaries.data[j]);
                    ++matched;
                }
            line_add(&summary_lines, "matched %zu of %zu", matched, count);
        } else {
            if (!first_detail)
                line_add(&details, "");
            first_detail = false;
            Integer number = strtoll(request + 7, NULL, 10);
            if (number < 1 || number > (Integer)count) {
                line_add(&details, "packet %" PRId64 " not found", number);
                continue;
            }
            const Packet *p = &packets[number - 1];
            line_add(&details, "packet %" PRId64, number);
            for (int j = -1; j < p->layer_count; ++j) {
                int layer_name = j < 0 ? -1 : p->layers[j];
                const char *layer_text = layer_name < 0 ? "frame" : protocols[layer_name];
                line_add(&details, "%s", layer_text);
                char *prefix = format("%s.", layer_text);
                for (int f = 0; f < STORED_FIELDS; ++f)
                    if (!strncmp(field_specs[f].name, prefix, strlen(prefix)))
                        for (size_t v = 0; v < p->fields[f].len; ++v)
                            line_add(&details, "  %s%s%s", field_specs[f].name,
                                     field_specs[f].type == TYPE_PRESENCE ? "" : " = ",
                                     field_specs[f].type == TYPE_PRESENCE
                                         ? ""
                                         : notation(field_specs[f].type, p->fields[f].data[v]));
                if (layer_name == 7) {
                    Lines dump = dump_lines(p->remaining);
                    for (size_t k = 0; k < dump.len; ++k)
                        line_add(&details, "  %s", dump.data[k]);
                }
            }
        }
    }
    Lines conversation_lines = {0}, endpoint_lines = {0};
    line_add(
        &conversation_lines,
        "type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration");
    size_t conversation_count;
    Conversation *cs = conversations(packets, count, &conversation_count);
    const char *kinds[3] = {"ipv4", "tcp", "udp"};
    for (size_t i = 0; i < conversation_count; ++i) {
        Conversation *c = &cs[i];
        line_add(&conversation_lines,
                 "%s,%s,%s,%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 ",%s,%s",
                 kinds[c->kind], endpoint(c->a, c->kind != 0), endpoint(c->b, c->kind != 0),
                 c->packets[0] + c->packets[1], c->bytes[0] + c->bytes[1], c->packets[0], c->bytes[0],
                 c->packets[1], c->bytes[1], seconds(c->start - origin), seconds(c->end - c->start));
    }
    line_add(&endpoint_lines, "address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes");
    size_t endpoint_count;
    EndpointTotals *es = endpoints(packets, count, &endpoint_count);
    for (size_t i = 0; i < endpoint_count; ++i) {
        EndpointTotals *e = &es[i];
        line_add(&endpoint_lines, "%s,%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64,
                 ipv4(e->address), e->packets[0] + e->packets[1], e->bytes[0] + e->bytes[1], e->packets[0],
                 e->bytes[0], e->packets[1], e->bytes[1]);
    }
    Integer total_bytes = 0, hierarchy[8][2] = {{0}}, checksum_counts[4][3] = {{0}}, malformed[8] = {0},
            mark_counts[4] = {0}, rcodes[16] = {0}, queries = 0, responses = 0;
    size_t *pending = allocate(count, sizeof *pending), pending_count = 0;
    Integer *response_times = allocate(count, sizeof *response_times);
    size_t response_count = 0;
    NameCount *names = NULL;
    size_t name_count = 0, name_cap = 0;
    for (size_t i = 0; i < count; ++i) {
        const Packet *p = &packets[i];
        total_bytes += p->length;
        for (int j = 0; j < p->layer_count; ++j) {
            ++hierarchy[p->layers[j]][0];
            hierarchy[p->layers[j]][1] += p->length;
        }
        for (int j = 0; j < 4; ++j)
            if (has(p, checks[j])) {
                const char *status = str(p, checks[j]);
                ++checksum_counts[j][!strcmp(status, "good") ? 0 : !strcmp(status, "bad") ? 1 : 2];
            }
        if (p->reason)
            ++malformed[p->layer_count ? p->layers[p->layer_count - 1] + 1 : 0];
        for (int j = 0; j < 4; ++j)
            if (has(p, marks[j]))
                ++mark_counts[j];
        if (!has(p, F_DNS_ID))
            continue;
        if (num(p, F_DNS_FLAGS_RESPONSE) == 0) {
            ++queries;
            pending[pending_count++] = i;
            for (size_t j = 0; j < p->fields[F_DNS_QRY_NAME].len; ++j) {
                char *name = p->fields[F_DNS_QRY_NAME].data[j].text;
                size_t k = 0;
                while (k < name_count && strcmp(names[k].name, name))
                    ++k;
                if (k == name_count) {
                    grow((void **)&names, &name_cap, name_count + 1, sizeof *names);
                    names[name_count++] = (NameCount){name, 0};
                }
                ++names[k].count;
            }
        } else {
            ++responses;
            ++rcodes[num(p, F_DNS_FLAGS_RCODE)];
            for (size_t j = 0; j < pending_count; ++j) {
                const Packet *q = &packets[pending[j]];
                if (num(q, F_DNS_ID) == num(p, F_DNS_ID) && num(q, F_IP_SRC) == num(p, F_IP_DST) &&
                    num(q, F_IP_DST) == num(p, F_IP_SRC) && num(q, F_UDP_SRCPORT) == num(p, F_UDP_DSTPORT) &&
                    num(q, F_UDP_DSTPORT) == num(p, F_UDP_SRCPORT)) {
                    response_times[response_count++] = p->time - q->time;
                    memmove(pending + j, pending + j + 1, (pending_count - j - 1) * sizeof *pending);
                    --pending_count;
                    break;
                }
            }
        }
    }
    Lines stats = {0};
    line_add(&stats, "packets %zu", count);
    line_add(&stats, "bytes %" PRId64, total_bytes);
    line_add(&stats, "duration %s", seconds(packets[count - 1].time - origin));
    line_add(&stats, "hierarchy");
    int order[7] = {0, 1, 2, 3, 4, 6, 5}, indent[7] = {0, 2, 2, 4, 4, 6, 4};
    for (int i = 0; i < 7; ++i)
        line_add(&stats, "%*s%s %" PRId64 " %" PRId64, indent[i], "", protocols[order[i]],
                 hierarchy[order[i]][0], hierarchy[order[i]][1]);
    line_add(&stats, "checksums");
    const char *check_names[4] = {"ip", "icmp", "udp", "tcp"};
    for (int i = 0; i < 4; ++i)
        line_add(&stats, "%s good %" PRId64 " bad %" PRId64 "%s", check_names[i], checksum_counts[i][0],
                 checksum_counts[i][1], i == 2 ? format(" none %" PRId64, checksum_counts[i][2]) : "");
    line_add(&stats, "malformed");
    const char *malformed_names[8] = {"dump", "eth", "arp", "ip", "icmp", "udp", "tcp", "dns"};
    for (int i = 0; i < 8; ++i)
        line_add(&stats, "%s %" PRId64, malformed_names[i], malformed[i]);
    line_add(&stats, "tcp analysis");
    for (int i = 0; i < 4; ++i)
        line_add(&stats, "%s %" PRId64, mark_names[i], mark_counts[i]);
    line_add(&stats, "dns");
    line_add(&stats, "queries %" PRId64, queries);
    line_add(&stats, "responses %" PRId64, responses);
    line_add(&stats, "transactions %zu", response_count);
    line_add(&stats, "unanswered %zu", pending_count);
    if (response_count) {
        Integer minimum = response_times[0], maximum = minimum;
        for (size_t i = 1; i < response_count; ++i) {
            if (response_times[i] < minimum)
                minimum = response_times[i];
            if (response_times[i] > maximum)
                maximum = response_times[i];
        }
        line_add(&stats, "response_time min %s max %s", seconds(minimum), seconds(maximum));
    } else
        line_add(&stats, "response_time -");
    for (int i = 0; i < 16; ++i)
        if (rcodes[i])
            line_add(&stats, "rcode %s %" PRId64, rcode_name(i), rcodes[i]);
    line_add(&stats, "names");
    qsort(names, name_count, sizeof *names, name_compare);
    for (size_t i = 0; i < name_count; ++i)
        line_add(&stats, "%s %" PRId64, names[i].name, names[i].count);
    Lines stream_lines = {0};
    for (size_t i = 0; i < stream_count; ++i) {
        Stream *s = &streams[i];
        if (i)
            line_add(&stream_lines, "");
        line_add(&stream_lines, "stream %zu %s -> %s", i, endpoint(s->client, true),
                 endpoint(s->server, true));
        line_add(&stream_lines, "packets %" PRId64 " bytes %" PRId64 " start %s duration %s", s->packets,
                 s->bytes, seconds(s->start - origin), seconds(s->end - s->start));
        Text history = {0};
        for (size_t j = 0; j < s->history_count; ++j)
            text_add(&history, "%s%s %" PRId64, j ? ", " : "", s->history[j].state, s->history[j].packet);
        line_add(&stream_lines, "states %s", history.data);
        line_add(&stream_lines, "handshake syn %s syn_ack %s ack %s rtt %s",
                 s->handshake[0] ? decimal(s->handshake[0]) : "-",
                 s->handshake[1] ? decimal(s->handshake[1]) : "-",
                 s->handshake[2] ? decimal(s->handshake[2]) : "-",
                 s->handshake[0] && s->handshake[2]
                     ? seconds(packets[s->handshake[2] - 1].time - packets[s->handshake[0] - 1].time)
                     : "-");
        line_add(&stream_lines, "options client mss %s wscale %s server mss %s wscale %s",
                 optional(s->sides[0].mss), optional(s->sides[0].ws), optional(s->sides[1].mss),
                 optional(s->sides[1].ws));
        for (int side = 0; side < 2; ++side) {
            Side *x = &s->sides[side];
            line_add(&stream_lines,
                     "%s packets %" PRId64 " payload %" PRId64 " retransmission %" PRId64
                     " out_of_order %" PRId64 " lost_segment %" PRId64 " duplicate_ack %" PRId64,
                     side == 0 ? "client" : "server", x->packets, x->payload, x->marks[0], x->marks[1],
                     x->marks[2], x->marks[3]);
        }
        for (size_t j = 0; j < s->event_count; ++j) {
            Event *e = &s->events[j];
            line_add(&stream_lines, "event %" PRId64 " %s %s seq %" PRId64 " len %" PRId64, e->packet,
                     e->side == 0 ? "client" : "server", mark_names[e->mark], e->seq, e->length);
        }
    }
    write_lines("summary.txt", summary_lines);
    write_lines("details.txt", details);
    write_lines("conversations.csv", conversation_lines);
    write_lines("endpoints.csv", endpoint_lines);
    write_lines("protocol_stats.txt", stats);
    write_lines("tcp_streams.txt", stream_lines);
    return 0;
}
