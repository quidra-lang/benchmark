#include <ctype.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define APPEND(a, n, v) do { (a) = resize((a), ((n) + 1) * sizeof(*(a))); (a)[(n)++] = (v); } while (0)
typedef struct {
    char *data;
    size_t length, capacity;
} Buffer;
typedef struct {
    char *owner, *data;
    int ttl, type;
} Record;
typedef struct {
    Record **items;
    size_t count;
} Records;
typedef struct {
    char *origin;
    uint32_t server;
    int line;
    Records records;
} Zone;
typedef struct {
    char *name;
    int type;
} Key;
typedef struct {
    Key key;
    char *kind;
    Records records;
    int expiry;
} CacheEntry;
typedef struct {
    char *kind, *cut;
    Records answer, authority, additional;
} Response;
typedef struct {
    char *status;
    Records answer;
} Result;
typedef struct {
    uint32_t server;
    int counts[7];
} QueryCount;
static const char *types[] = {"A", "NS", "CNAME", "SOA", "PTR", "MX", "TXT", "AAAA"};
static const char *kinds[] = {"ANSWER", "CNAME", "REFERRAL", "NODATA", "NXDOMAIN", "LAME", "TIMEOUT"};
static uint32_t *roots, *down;
static size_t root_count, down_count;
static Zone **zones, *current;
static size_t zone_count;
static CacheEntry **cache;
static size_t cache_count;
static QueryCount **query_counts;
static size_t query_count;
static int now, min_ttl = 1, max_ttl = 86400, neg_ttl = 3600, hits, resolutions[4];
static jmp_buf failure;
static char *error_reason;
static void *allocate(size_t n) {
    void *p = calloc(1, n ? n : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static void *resize(void *p, size_t n) {
    p = realloc(p, n ? n : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static char *slice(const char *s, size_t n) {
    char *p = allocate(n + 1);
    memcpy(p, s, n);
    return p;
}

static char *copy(const char *s) {
    return slice(s, strlen(s));
}

static char *format(const char *pattern, ...) {
    va_list args, saved;
    va_start(args, pattern);
    va_copy(saved, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    char *s = allocate((size_t)n + 1);
    vsnprintf(s, (size_t)n + 1, pattern, saved);
    va_end(saved);
    return s;
}

static void error(const char *pattern, ...) {
    va_list args, saved;
    va_start(args, pattern);
    va_copy(saved, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    error_reason = allocate((size_t)n + 1);
    vsnprintf(error_reason, (size_t)n + 1, pattern, saved);
    va_end(saved);
    longjmp(failure, 1);
}

static void append(Buffer *b, const char *text) {
    size_t n = strlen(text);
    if (b->length + n + 1 > b->capacity) {
        b->capacity = (b->length + n + 1) * 2;
        b->data = resize(b->data, b->capacity);
    }
    memcpy(b->data + b->length, text, n);
    b->length += n;
    b->data[b->length] = 0;
}

static char *finish(Buffer *b) {
    return b->data ? b->data : copy("");
}

static char **split(const char *s, char delimiter, size_t *count) {
    char **out = NULL;
    size_t start = 0;
    *count = 0;
    for (size_t i = 0;; i++) if (!s[i] || s[i] == delimiter) {
        APPEND(out, *count, slice(s + start, i - start));
        start = i + 1;
        if (!s[i]) break;
    }
    return out;
}

static char *join(char **parts, size_t count, const char *separator) {
    Buffer b = {0};
    for (size_t i = 0; i < count; i++) {
        if (i) append(&b, separator);
        append(&b, parts[i]);
    }
    return finish(&b);
}

static bool digit(char c) {
    return c >= '0' && c <= '9';
}

static bool letter(char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

static bool ends(const char *s, const char *tail) {
    size_t n = strlen(s), m = strlen(tail);
    return n >= m && !strcmp(s + n - m, tail);
}

static char *name(const char *word, bool wildcard, const char *origin) {
    if (origin && !strcmp(word, "@")) return (char *)origin;
    if (!strcmp(word, ".")) return ".";
    size_t n = strlen(word);
    bool absolute = word[n - 1] == '.';
    char *text = slice(word, n - (absolute ? 1 : 0));
    size_t count;
    char **labels = split(text, '.', &count);
    for (size_t i = 0; i < count; i++) {
        if (wildcard && !i && !strcmp(labels[i], "*")) continue;
        size_t length = strlen(labels[i]);
        if (!length || length > 63 || labels[i][0] == '-' || labels[i][length - 1] == '-') error("bad name %s", word);
        for (size_t j = 0; j < length; j++) if (!letter(labels[i][j]) && !digit(labels[i][j]) && labels[i][j] != '-') error("bad name %s", word);
    }
    for (size_t i = 0; text[i]; i++) if (text[i] >= 'A' && text[i] <= 'Z') text[i] += 'a' - 'A';
    return format("%s.%s", text, origin && !absolute && strcmp(origin, ".") ? origin : "");
}

static int name_length(const char *name) {
    if (!strcmp(name, ".")) return 0;
    int count = 0;
    for (; *name; name++) if (*name == '.') count++;
    return count;
}

static bool below(const char *name, const char *ancestor) {
    return !strcmp(ancestor, ".") || !strcmp(name, ancestor) || ends(name, format(".%s", ancestor));
}

static char *parent(const char *name) {
    char *dot = strchr(name, '.');
    return dot[1] ? dot + 1 : ".";
}

static int compare_names(const char *left, const char *right) {
    if (!strcmp(left, ".")) return !strcmp(right, ".") ? 0 : -1;
    if (!strcmp(right, ".")) return 1;
    size_t a_count, b_count;
    char **a = split(slice(left, strlen(left) - 1), '.', &a_count), **b = split(slice(right, strlen(right) - 1), '.', &b_count);
    size_t n = a_count < b_count ? a_count : b_count;
    for (size_t i = 1; i <= n; i++) {
        int order = strcmp(a[a_count - i], b[b_count - i]);
        if (order) return order;
    }
    return (a_count > b_count) - (a_count < b_count);
}

static uint32_t ipv4(const char *word) {
    size_t count;
    char **fields = split(word, '.', &count);
    if (count != 4) error("bad address %s", word);
    uint32_t value = 0;
    for (size_t i = 0; i < 4; i++) {
        size_t n = strlen(fields[i]);
        if (!n || n > 3 || (n > 1 && fields[i][0] == '0')) error("bad address %s", word);
        for (size_t j = 0; j < n; j++) if (!digit(fields[i][j])) error("bad address %s", word);
        int part = atoi(fields[i]);
        if (part > 255) error("bad address %s", word);
        value = value * 256 + (uint32_t)part;
    }
    return value;
}

static char *address(uint32_t a) {
    return format("%u.%u.%u.%u", a >> 24, (a >> 16) & 255, (a >> 8) & 255, a & 255);
}

static int hex(char c) {
    return digit(c) ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
}

static int *ipv6(const char *word) {
    const char *colon = strstr(word, "::");
    char *left = colon ? slice(word, (size_t)(colon - word)) : copy(word), *right = colon ? copy(colon + 2) : "";
    if (colon && strstr(colon + 1, "::")) error("bad address %s", word);
    size_t a_count = 0, b_count = 0;
    char **a = *left ? split(left, ':', &a_count) : NULL, **b = *right ? split(right, ':', &b_count) : NULL;
    if (colon ? a_count + b_count > 7 : a_count != 8) error("bad address %s", word);
    int *groups = allocate(8 * sizeof(*groups));
    for (int side = 0; side < 2; side++) {
        size_t count = side ? b_count : a_count;
        char **parts = side ? b : a;
        for (size_t i = 0; i < count; i++) {
            size_t n = strlen(parts[i]);
            if (!n || n > 4) error("bad address %s", word);
            int value = 0;
            for (size_t j = 0; j < n; j++) {
                int h = hex(parts[i][j]);
                if (h < 0) error("bad address %s", word);
                value = value * 16 + h;
            }
            groups[side ? 8 - b_count + i : i] = value;
        }
    }
    return groups;
}

static char *address6(const int *groups) {
    int best = -1, count = 1;
    for (int i = 0; i < 8;) {
        if (groups[i]) {
            i++;
            continue;
        }
        int end = i;
        while (end < 8 && !groups[end]) end++;
        if (end - i > count) {
            best = i;
            count = end - i;
        }
        i = end;
    }
    char **left = NULL, **right = NULL;
    size_t left_count = 0, right_count = 0;
    if (best < 0) {
        for (int i = 0; i < 8; i++) APPEND(left, left_count, format("%x", groups[i]));
        return join(left, left_count, ":");
    }
    for (int i = 0; i < best; i++) APPEND(left, left_count, format("%x", groups[i]));
    for (int i = best + count; i < 8; i++) APPEND(right, right_count, format("%x", groups[i]));
    return format("%s::%s", join(left, left_count, ":"), join(right, right_count, ":"));
}

static int integer(const char *word) {
    size_t n = strlen(word);
    if (!n || n > 9 || (n > 1 && *word == '0')) return -1;
    for (size_t i = 0; i < n; i++) if (!digit(word[i])) return -1;
    return atoi(word);
}

static int type_index(const char *word) {
    for (int i = 0; i < 8; i++) if (!strcmp(word, types[i])) return i;
    error("bad type %s", word);
    return -1;
}

static int ttl(const char *word) {
    int plain = integer(word);
    int64_t total = plain >= 0 ? plain : 0;
    if (plain < 0) {
        size_t at = 0;
        int previous = -1;
        const char *units = "wdhms";
        int seconds[] = {604800, 86400, 3600, 60, 1};
        while (word[at]) {
            size_t start = at;
            while (digit(word[at])) at++;
            char *number = slice(word + start, at - start);
            if (!*number || strlen(number) > 3 || integer(number) < 0 || !word[at]) error("bad ttl %s", word);
            char c = (char)tolower((unsigned char)word[at++]);
            const char *unit = strchr(units, c);
            int index = unit ? (int)(unit - units) : -1;
            if (index <= previous) error("bad ttl %s", word);
            previous = index;
            total += (int64_t)atoi(number) * seconds[index];
        }
    }
    if (total < 1 || total > 604800) error("bad ttl %s", word);
    return (int)total;
}

static Record *record(char *owner, int ttl, int type, char *data) {
    Record *r = allocate(sizeof(*r));
    *r = (Record){owner, data, ttl, type};
    return r;
}

static Record *with_ttl(Record *r, int ttl) {
    return record(r->owner, ttl, r->type, r->data);
}

static char *record_text(Record *r) {
    return format("%s %d %s %s", r->owner, r->ttl, types[r->type], r->data);
}

static int compare_data(Record *a, Record *b) {
    if (a->type == 0) {
        uint32_t x = ipv4(a->data), y = ipv4(b->data);
        return (x > y) - (x < y);
    }
    if (a->type == 7) {
        int *x = ipv6(a->data), *y = ipv6(b->data);
        for (int i = 0; i < 8; i++) if (x[i] != y[i]) return x[i] - y[i];
        return 0;
    }
    if (a->type == 1 || a->type == 2 || a->type == 4) return compare_names(a->data, b->data);
    if (a->type == 5) {
        char *x = strchr(a->data, ' '), *y = strchr(b->data, ' ');
        int order = atoi(a->data) - atoi(b->data);
        return order ? order : compare_names(x + 1, y + 1);
    }
    return a->type == 6 ? strcmp(a->data, b->data) : 0;
}

static int data_compare(const void *a, const void *b) {
    return compare_data(*(Record *const *)a, *(Record *const *)b);
}

static Records sorted(Records input) {
    Records out = { .count = input.count };
    out.items = allocate(out.count * sizeof(*out.items));
    if (out.count) memcpy(out.items, input.items, out.count * sizeof(*out.items));
    qsort(out.items, out.count, sizeof(*out.items), data_compare);
    return out;
}

static Records records(Zone *zone, const char *owner, int type) {
    Records out = {0};
    for (size_t i = 0; i < zone->records.count; i++) {
        Record *r = zone->records.items[i];
        if (r->type == type && !strcmp(r->owner, owner)) APPEND(out.items, out.count, r);
    }
    return sorted(out);
}

static Record *soa(Zone *zone) {
    for (size_t i = 0; i < zone->records.count; i++) if (zone->records.items[i]->type == 3) return zone->records.items[i];
    return NULL;
}

static bool contains_address(uint32_t *values, size_t count, uint32_t value) {
    for (size_t i = 0; i < count; i++) if (values[i] == value) return true;
    return false;
}

static void zone_line(char **w, size_t argc, int line) {
    if (!strcmp(w[0], "ROOT")) {
        uint32_t *additions = NULL;
        size_t count = 0;
        for (size_t i = 1; i < argc; i++) {
            uint32_t value = ipv4(w[i]);
            if (contains_address(roots, root_count, value) || contains_address(additions, count, value)) error("duplicate root %s", w[i]);
            APPEND(additions, count, value);
        }
        for (size_t i = 0; i < count; i++) APPEND(roots, root_count, additions[i]);
        return;
    }
    if (!strcmp(w[0], "ZONE")) {
        current = NULL;
        char *origin = name(w[1], false, NULL);
        uint32_t server = ipv4(w[2]);
        for (size_t i = 0; i < zone_count; i++) if (!strcmp(zones[i]->origin, origin) && zones[i]->server == server) error("duplicate zone %s at %s", origin, w[2]);
        current = allocate(sizeof(*current));
        current->origin = origin;
        current->server = server;
        current->line = line;
        APPEND(zones, zone_count, current);
        return;
    }
    if (!current) error("no current zone");
    char *owner = name(w[0], true, current->origin);
    if (!below(owner, current->origin)) error("out of zone %s", owner);
    int seconds = ttl(w[1]);
    int type = type_index(w[2]);
    char **data = w + 3;
    size_t count = argc - 3;
    if (type != 6 && count != (size_t)(type == 5 ? 2 : type == 3 ? 7 : 1)) error("wrong field count");
    char *text;
    if (type == 0) text = address(ipv4(data[0]));
    else if (type == 7) text = address6(ipv6(data[0]));
    else if (type == 1 || type == 2 || type == 4) text = name(data[0], false, current->origin);
    else if (type == 5) {
        int preference = integer(data[0]);
        if (preference < 0 || preference > 65535) error("bad preference %s", data[0]);
        text = format("%d %s", preference, name(data[1], false, current->origin));
    } else if (type == 6) {
        text = join(data, count, " ");
        size_t n = strlen(text);
        if (n < 2 || *text != '"' || text[n - 1] != '"' || memchr(text + 1, '"', n - 2)) error("bad text %s", text);
    } else {
        char **fields = NULL;
        size_t fields_count = 0;
        APPEND(fields, fields_count, name(data[0], false, current->origin));
        APPEND(fields, fields_count, name(data[1], false, current->origin));
        for (int i = 2; i < 6; i++) {
            if (integer(data[i]) < 0) error("bad number %s", data[i]);
            APPEND(fields, fields_count, data[i]);
        }
        int minimum = integer(data[6]);
        if (minimum < 1 || minimum > 86400) error("bad minimum %s", data[6]);
        APPEND(fields, fields_count, data[6]);
        text = join(fields, fields_count, " ");
    }
    if (type == 1 && !strncmp(owner, "*.", 2)) error("ns at wildcard");
    if (type == 3 && strcmp(owner, current->origin)) error("soa not at origin");
    if (type == 3 && soa(current)) error("duplicate soa");
    for (size_t i = 0; i < current->records.count; i++) {
        Record *r = current->records.items[i];
        if (!strcmp(r->owner, owner) && r->type == type && !strcmp(r->data, text)) error("duplicate record");
    }
    for (size_t i = 0; i < current->records.count; i++) {
        Record *r = current->records.items[i];
        if (!strcmp(r->owner, owner) && (type == 2 || r->type == 2)) error("cname conflict %s", owner);
    }
    APPEND(current->records.items, current->records.count, record(owner, seconds, type, text));
}

static void finish_zones(void) {
    size_t next = 0, count = 0;
    for (size_t i = 0; i < zone_count; i++) {
        Zone *z = zones[i];
        if (!soa(z)) printf("error line %d: zone %s at %s has no soa\n", z->line, z->origin, address(z->server));
        else {
            printf("zone %s at %s records=%zu\n", z->origin, address(z->server), z->records.count);
            zones[next++] = z;
            count += z->records.count;
        }
    }
    zone_count = next;
    printf("loaded roots=%zu zones=%zu records=%zu\n", root_count, zone_count, count);
}

static bool known(uint32_t server) {
    for (size_t i = 0; i < zone_count; i++) if (zones[i]->server == server) return true;
    return false;
}

static bool exists(Zone *zone, const char *name) {
    for (size_t i = 0; i < zone->records.count; i++) if (below(zone->records.items[i]->owner, name)) return true;
    return false;
}

static Response *response(char *kind) {
    Response *r = allocate(sizeof(*r));
    r->kind = kind;
    return r;
}

static char *description(Response *r) {
    return !strcmp(r->kind, "REFERRAL") ? format("REFERRAL %s", r->cut) : !strcmp(r->kind, "CNAME") ? format("CNAME %s", r->answer.items[0]->data) : r->kind;
}

static Response *authoritative(uint32_t server, const char *name, int type, const char *cut) {
    if (contains_address(down, down_count, server) || !known(server)) return response("TIMEOUT");
    Zone *zone = NULL;
    for (size_t i = 0; i < zone_count; i++) if (zones[i]->server == server && below(name, zones[i]->origin) && (!zone || name_length(zones[i]->origin) > name_length(zone->origin))) zone = zones[i];
    if (!zone || name_length(zone->origin) < name_length(cut)) return response("LAME");
    char *delegation = NULL;
    for (size_t i = 0; i < zone->records.count; i++) {
        Record *r = zone->records.items[i];
        if (r->type == 1 && strcmp(r->owner, zone->origin) && below(name, r->owner) && (!delegation || name_length(r->owner) < name_length(delegation))) delegation = r->owner;
    }
    if (delegation) {
        Response *r = response("REFERRAL");
        r->cut = delegation;
        r->authority = records(zone, delegation, 1);
        for (size_t i = 0; i < r->authority.count; i++) {
            Records glue = records(zone, r->authority.items[i]->data, 0);
            for (size_t j = 0; j < glue.count; j++) APPEND(r->additional.items, r->additional.count, glue.items[j]);
        }
        return r;
    }
    Records chosen = {0};
    for (size_t i = 0; i < zone->records.count; i++) if (!strcmp(zone->records.items[i]->owner, name)) APPEND(chosen.items, chosen.count, zone->records.items[i]);
    if (!chosen.count && !exists(zone, name)) {
        char *ancestor = parent(name);
        while (!exists(zone, ancestor)) ancestor = parent(ancestor);
        char *wildcard = !strcmp(ancestor, ".") ? "*." : format("*.%s", ancestor);
        for (size_t i = 0; i < zone->records.count; i++) if (!strcmp(zone->records.items[i]->owner, wildcard)) APPEND(chosen.items, chosen.count, zone->records.items[i]);
    }
    Response *r;
    if (!chosen.count) r = response(exists(zone, name) ? "NODATA" : "NXDOMAIN");
    else {
        r = response("ANSWER");
        for (size_t i = 0; i < chosen.count; i++) if (chosen.items[i]->type == type) APPEND(r->answer.items, r->answer.count, record((char *)name, chosen.items[i]->ttl, type, chosen.items[i]->data));
        if (r->answer.count) {
            r->answer = sorted(r->answer);
            return r;
        }
        if (type != 2) for (size_t i = 0; i < chosen.count; i++) if (chosen.items[i]->type == 2) {
            r->kind = "CNAME";
            APPEND(r->answer.items, r->answer.count, record((char *)name, chosen.items[i]->ttl, 2, chosen.items[i]->data));
            return r;
        }
        r->kind = "NODATA";
    }
    APPEND(r->authority.items, r->authority.count, soa(zone));
    return r;
}

static Response *ask(uint32_t server, const char *name, int type, const char *cut) {
    Response *r = authoritative(server, name, type, cut);
    QueryCount *entry = NULL;
    for (size_t i = 0; i < query_count; i++) if (query_counts[i]->server == server) entry = query_counts[i];
    if (!entry) {
        entry = allocate(sizeof(*entry));
        entry->server = server;
        APPEND(query_counts, query_count, entry);
    }
    for (int i = 0; i < 7; i++) if (!strcmp(r->kind, kinds[i])) entry->counts[i]++;
    return r;
}

static void trace(int depth, const char *text) {
    printf("%*s%s\n", 2 * (depth + 1), "", text);
}

static CacheEntry *cached(const char *name, int type) {
    for (size_t i = 0; i < cache_count; i++) if (cache[i]->key.type == type && !strcmp(cache[i]->key.name, name)) return cache[i];
    return NULL;
}

static void cache_put(char *name, int type, char *kind, Records records, int expiry) {
    CacheEntry *entry = cached(name, type);
    if (!entry) {
        entry = allocate(sizeof(*entry));
        APPEND(cache, cache_count, entry);
    }
    *entry = (CacheEntry) {
        {name, type}, kind, records, expiry
    };
}

static int store(Records records) {
    int ttl = records.items[0]->ttl;
    for (size_t i = 1; i < records.count; i++) if (records.items[i]->ttl < ttl) ttl = records.items[i]->ttl;
    if (ttl < min_ttl) ttl = min_ttl;
    if (ttl > max_ttl) ttl = max_ttl;
    cache_put(records.items[0]->owner, records.items[0]->type, "POS", sorted(records), now + ttl);
    return ttl;
}

static Records cached_records(CacheEntry *entry) {
    Records out = {0};
    for (size_t i = 0; i < entry->records.count; i++) APPEND(out.items, out.count, with_ttl(entry->records.items[i], entry->expiry - now));
    return out;
}

static Result resolve(const char *name, int type, int depth, Key *resolving, size_t resolving_count);
static int name_compare(const void *a, const void *b) {
    return compare_names(*(char *const *)a, *(char *const *)b);
}

static int address_compare(const void *a, const void *b) {
    uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
    return (x > y) - (x < y);
}

static Response *query_servers(const char *name, int type, const char *cut, char **servers, size_t server_count, bool root_hints, int depth, Key *resolving, size_t resolving_count) {
    if (root_hints) {
        for (size_t i = 0; i < root_count; i++) {
            Response *r = ask(roots[i], name, type, cut);
            trace(depth, format("ASK %s %s %s -> %s", address(roots[i]), name, types[type], description(r)));
            if (strcmp(r->kind, "LAME") && strcmp(r->kind, "TIMEOUT")) return r;
        }
    } else {
        char **ordered = allocate(server_count * sizeof(*ordered));
        if (server_count) memcpy(ordered, servers, server_count * sizeof(*ordered));
        qsort(ordered, server_count, sizeof(*ordered), name_compare);
        for (size_t i = 0; i < server_count; i++) {
            char *host = ordered[i];
            if (i && !strcmp(host, ordered[i - 1])) continue;
            uint32_t *addresses = NULL;
            size_t count = 0;
            CacheEntry *entry = cached(host, 0);
            bool loop = false;
            for (size_t j = 0; j < resolving_count; j++) if (resolving[j].type == 0 && !strcmp(resolving[j].name, host)) loop = true;
            if (entry && !strcmp(entry->kind, "POS")) for (size_t j = 0; j < entry->records.count; j++) {
                uint32_t a = ipv4(entry->records.items[j]->data);
                if (!contains_address(addresses, count, a)) APPEND(addresses, count, a);
            } else if (loop) trace(depth, format("GLUELESS %s -> LOOP", host));
            else {
                trace(depth, format("GLUELESS %s", host));
                Result result = resolve(host, 0, depth + 1, resolving, resolving_count);
                if (!strcmp(result.status, "NOERROR")) for (size_t j = 0; j < result.answer.count; j++) if (result.answer.items[j]->type == 0) {
                    uint32_t a = ipv4(result.answer.items[j]->data);
                    if (!contains_address(addresses, count, a)) APPEND(addresses, count, a);
                }
            }
            if (count) qsort(addresses, count, sizeof(*addresses), address_compare);
            for (size_t j = 0; j < count; j++) {
                Response *r = ask(addresses[j], name, type, cut);
                trace(depth, format("ASK %s %s %s -> %s", address(addresses[j]), name, types[type], description(r)));
                if (strcmp(r->kind, "LAME") && strcmp(r->kind, "TIMEOUT")) return r;
            }
        }
    }
    return NULL;
}

static Response *lookup(const char *name, int type, int depth, Key *resolving, size_t resolving_count) {
    CacheEntry *entry = cached(name, type);
    Response *r = NULL;
    if (entry) {
        r = response(!strcmp(entry->kind, "POS") ? "ANSWER" : entry->kind);
        if (!strcmp(entry->kind, "POS")) r->answer = cached_records(entry);
    }
    if (!r) for (size_t i = 0; i < cache_count; i++) if (!strcmp(cache[i]->kind, "NXDOMAIN") && below(name, cache[i]->key.name)) {
        r = response("NXDOMAIN");
        break;
    }
    if (!r && type != 2) {
        entry = cached(name, 2);
        if (entry && !strcmp(entry->kind, "POS")) {
            r = response("CNAME");
            r->answer = cached_records(entry);
        }
    }
    if (r) {
        hits++;
        trace(depth, format("CACHE HIT %s %s -> %s", name, types[type], description(r)));
        return r;
    }
    char *cut = ".", **servers = NULL;
    size_t server_count = 0;
    bool hints = true;
    for (size_t i = 0; i < cache_count; i++) {
        entry = cache[i];
        if (entry->key.type == 1 && !strcmp(entry->kind, "POS") && below(name, entry->key.name) && (hints || name_length(entry->key.name) > name_length(cut))) {
            cut = entry->key.name;
            servers = NULL;
            server_count = 0;
            hints = false;
            for (size_t j = 0; j < entry->records.count; j++) APPEND(servers, server_count, entry->records.items[j]->data);
        }
    }
    if (!hints) {
        hits++;
        trace(depth, format("CACHE HIT %s %s -> REFERRAL %s", name, types[type], cut));
    }
    while (true) {
        r = query_servers(name, type, cut, servers, server_count, hints, depth, resolving, resolving_count);
        if (!r) return response(format("SERVFAIL no server for %s", cut));
        if (!strcmp(r->kind, "REFERRAL")) {
            store(r->authority);
            for (size_t i = 0; i < r->additional.count; i++) {
                Record *item = r->additional.items[i];
                bool earlier = false;
                for (size_t j = 0; j < i; j++) if (!strcmp(r->additional.items[j]->owner, item->owner)) earlier = true;
                if (earlier) continue;
                Records group = {0};
                for (size_t j = i; j < r->additional.count; j++) if (!strcmp(r->additional.items[j]->owner, item->owner)) APPEND(group.items, group.count, r->additional.items[j]);
                store(group);
            }
            cut = r->cut;
            servers = NULL;
            server_count = 0;
            hints = false;
            for (size_t i = 0; i < r->authority.count; i++) APPEND(servers, server_count, r->authority.items[i]->data);
            continue;
        }
        if (!strcmp(r->kind, "ANSWER") || !strcmp(r->kind, "CNAME")) {
            int ttl = store(r->answer);
            for (size_t i = 0; i < r->answer.count; i++) r->answer.items[i] = with_ttl(r->answer.items[i], ttl);
        } else {
            Record *soa_record = r->authority.items[0];
            size_t count;
            char **fields = split(soa_record->data, ' ', &count);
            int ttl = atoi(fields[6]);
            if (ttl > soa_record->ttl) ttl = soa_record->ttl;
            if (ttl > neg_ttl) ttl = neg_ttl;
            cache_put((char *)name, type, r->kind, (Records){0}, now + ttl);
        }
        return r;
    }
}

static Result resolve(const char *name, int type, int depth, Key *resolving, size_t resolving_count) {
    Key *stack = allocate((resolving_count + 1) * sizeof(*stack));
    if (resolving_count) memcpy(stack, resolving, resolving_count * sizeof(*stack));
    stack[resolving_count++] = (Key){(char *)name, type};
    Records aliases = {0};
    char **seen = NULL;
    size_t seen_count = 0;
    APPEND(seen, seen_count, (char *)name);
    const char *current_name = name;
    Result result = {0};
    while (true) {
        Response *r = lookup(current_name, type, depth, stack, resolving_count);
        if (!strcmp(r->kind, "CNAME")) {
            Record *alias = r->answer.items[0];
            APPEND(aliases.items, aliases.count, alias);
            bool loop = false;
            for (size_t i = 0; i < seen_count; i++) if (!strcmp(seen[i], alias->data)) loop = true;
            if (loop) {
                result.status = "SERVFAIL cname loop";
                break;
            }
            if (aliases.count == 9) {
                result.status = "SERVFAIL cname chain too long";
                break;
            }
            APPEND(seen, seen_count, alias->data);
            current_name = alias->data;
            continue;
        }
        if (!strcmp(r->kind, "ANSWER")) {
            result.status = "NOERROR";
            result.answer = aliases;
            for (size_t i = 0; i < r->answer.count; i++) APPEND(result.answer.items, result.answer.count, r->answer.items[i]);
        } else if (!strcmp(r->kind, "NODATA") || !strcmp(r->kind, "NXDOMAIN")) {
            result.status = r->kind;
            result.answer = aliases;
        } else result.status = r->kind;
        break;
    }
    resolutions[!strcmp(result.status, "NOERROR") ? 0 : !strcmp(result.status, "NODATA") ? 1 : !strcmp(result.status, "NXDOMAIN") ? 2 : 3]++;
    return result;
}

static Result resolve_root(const char *name, int type) {
    return resolve(name, type, 0, NULL, 0);
}

static void answer(Result result) {
    for (size_t i = 0; i < result.answer.count; i++) printf("answer %s\n", record_text(result.answer.items[i]));
    printf("status %s\n", result.status);
}

static void addresses(const char *host, const char *prefix) {
    Result a = resolve_root(host, 0);
    Result aaaa = resolve_root(host, 7);
    char **values = NULL;
    size_t count = 0;
    if (!strcmp(a.status, "NOERROR")) for (size_t i = 0; i < a.answer.count; i++) if (a.answer.items[i]->type == 0) APPEND(values, count, a.answer.items[i]->data);
    if (!strcmp(aaaa.status, "NOERROR")) for (size_t i = 0; i < aaaa.answer.count; i++) if (aaaa.answer.items[i]->type == 7) APPEND(values, count, aaaa.answer.items[i]->data);
    printf("%s%s -> %s\n", prefix, host, count ? join(values, count, " ") : "no address");
}

static int cache_compare(const void *a, const void *b) {
    CacheEntry *x = *(CacheEntry *const *)a, *y = *(CacheEntry *const *)b;
    int order = compare_names(x->key.name, y->key.name);
    return order ? order : x->key.type - y->key.type;
}

static int record_compare(const void *a, const void *b) {
    Record *x = *(Record *const *)a, *y = *(Record *const *)b;
    int order = compare_names(x->owner, y->owner);
    if (!order) order = x->type - y->type;
    return order ? order : compare_data(x, y);
}

static int query_compare(const void *a, const void *b) {
    uint32_t x = (*(QueryCount *const *)a)->server, y = (*(QueryCount *const *)b)->server;
    return (x > y) - (x < y);
}

static void command(char **w, size_t argc) {
    if (!strcmp(w[0], "RESOLVE")) {
        char *n = name(w[1], true, NULL);
        int t = type_index(w[2]);
        printf("resolve %s %s\n", n, types[t]);
        answer(resolve_root(n, t));
    } else if (!strcmp(w[0], "REVERSE")) {
        char *output, *reverse;
        if (strchr(w[1], ':')) {
            int *groups = ipv6(w[1]);
            output = address6(groups);
            Buffer digits = {0};
            for (int i = 0; i < 8; i++) append(&digits, format("%04x", groups[i]));
            Buffer n = {0};
            for (int i = 31; i >= 0; i--) append(&n, format("%c.", digits.data[i]));
            append(&n, "ip6.arpa.");
            reverse = finish(&n);
        } else {
            uint32_t a = ipv4(w[1]);
            output = address(a);
            reverse = format("%u.%u.%u.%u.in-addr.arpa.", a & 255, (a >> 8) & 255, (a >> 16) & 255, a >> 24);
        }
        printf("reverse %s %s\n", output, reverse);
        answer(resolve_root(reverse, 4));
    } else if (!strcmp(w[0], "MX")) {
        char *n = name(w[1], true, NULL);
        printf("mx %s\n", n);
        Result result = resolve_root(n, 5);
        answer(result);
        if (!strcmp(result.status, "NOERROR")) for (size_t i = 0; i < result.answer.count; i++) {
            Record *r = result.answer.items[i];
            if (r->type != 5) continue;
            char *space = strchr(r->data, ' ');
            char *preference = slice(r->data, (size_t)(space - r->data));
            if (!strcmp(space + 1, ".")) printf("exchange %s . -> null\n", preference);
            else addresses(space + 1, format("exchange %s ", preference));
        }
        if (!strcmp(result.status, "NODATA")) {
            char *host = n;
            for (size_t i = 0; i < result.answer.count; i++) if (result.answer.items[i]->type == 2) host = result.answer.items[i]->data;
            addresses(host, "implicit ");
        }
    } else if (!strcmp(w[0], "QUERY")) {
        uint32_t server = ipv4(w[1]);
        char *n = name(w[2], true, NULL);
        int t = type_index(w[3]);
        Response *r = ask(server, n, t, ".");
        printf("query %s %s %s -> %s\n", address(server), n, types[t], description(r));
        for (size_t i = 0; i < r->answer.count; i++) printf("answer %s\n", record_text(r->answer.items[i]));
        for (size_t i = 0; i < r->authority.count; i++) printf("authority %s\n", record_text(r->authority.items[i]));
        for (size_t i = 0; i < r->additional.count; i++) printf("additional %s\n", record_text(r->additional.items[i]));
    } else if (!strcmp(w[0], "DUMP")) {
        uint32_t server = ipv4(w[1]);
        char *n = name(w[2], false, NULL);
        if (contains_address(down, down_count, server) || !known(server)) {
            printf("dump %s %s -> TIMEOUT\n", address(server), n);
            return;
        }
        Zone *zone = NULL;
        for (size_t i = 0; i < zone_count; i++) if (zones[i]->server == server && !strcmp(zones[i]->origin, n)) zone = zones[i];
        if (!zone) printf("dump %s %s -> REFUSED\n", address(server), n);
        else {
            printf("dump %s %s records=%zu\n", address(server), n, zone->records.count);
            Records ordered = {.count = zone->records.count};
            ordered.items = allocate(ordered.count * sizeof(*ordered.items));
            if (ordered.count) memcpy(ordered.items, zone->records.items, ordered.count * sizeof(*ordered.items));
            qsort(ordered.items, ordered.count, sizeof(*ordered.items), record_compare);
            for (size_t i = 0; i < ordered.count; i++) printf("  %s\n", record_text(ordered.items[i]));
        }
    } else if (!strcmp(w[0], "DOWN") || !strcmp(w[0], "UP")) {
        uint32_t server = ipv4(w[1]);
        bool disable = !strcmp(w[0], "DOWN"), present = contains_address(down, down_count, server);
        if (disable ? present : !present) error("server %s %s", w[1], disable ? "already down" : "not down");
        if (disable) APPEND(down, down_count, server);
        else {
            size_t next = 0;
            for (size_t i = 0; i < down_count; i++) if (down[i] != server) down[next++] = down[i];
            down_count = next;
        }
        printf("%s %s\n", disable ? "down" : "up", address(server));
    } else if (!strcmp(w[0], "SET")) {
        if (strcmp(w[1], "MINTTL") && strcmp(w[1], "MAXTTL") && strcmp(w[1], "NEGTTL")) error("bad setting %s", w[1]);
        int value = integer(w[2]);
        if (value < 1 || value > 604800) error("bad value %s", w[2]);
        if ((!strcmp(w[1], "MINTTL") ? value : min_ttl) > (!strcmp(w[1], "MAXTTL") ? value : max_ttl)) error("minttl above maxttl");
        if (!strcmp(w[1], "MINTTL")) min_ttl = value;
        else if (!strcmp(w[1], "MAXTTL")) max_ttl = value;
        else neg_ttl = value;
        printf("set %s=%d\n", w[1], value);
    } else if (!strcmp(w[0], "TIME")) {
        int value = integer(w[1]);
        if (value < 1 || value > 1000000) error("bad time %s", w[1]);
        now += value;
        size_t old = cache_count, next = 0;
        for (size_t i = 0; i < cache_count; i++) if (cache[i]->expiry > now) cache[next++] = cache[i];
        cache_count = next;
        printf("time now=%d expired=%zu\n", now, old - cache_count);
    } else if (!strcmp(w[0], "CACHE") || !strcmp(w[0], "FLUSH")) {
        char *n = argc == 2 ? name(w[1], false, NULL) : NULL;
        CacheEntry **selected = NULL;
        size_t count = 0;
        for (size_t i = 0; i < cache_count; i++) if (!n || below(cache[i]->key.name, n)) APPEND(selected, count, cache[i]);
        if (!strcmp(w[0], "FLUSH")) {
            size_t next = 0;
            for (size_t i = 0; i < cache_count; i++) if (n && !below(cache[i]->key.name, n)) cache[next++] = cache[i];
            cache_count = next;
            printf("flush removed=%zu\n", count);
        } else {
            printf("cache entries=%zu\n", count);
            if (count) qsort(selected, count, sizeof(*selected), cache_compare);
            for (size_t i = 0; i < count; i++) {
                CacheEntry *e = selected[i];
                if (!strcmp(e->kind, "POS")) {
                    Records r = cached_records(e);
                    for (size_t j = 0; j < r.count; j++) printf("  %s\n", record_text(r.items[j]));
                } else printf("  %s %d %s %s\n", e->key.name, e->expiry - now, types[e->key.type], e->kind);
            }
        }
    } else {
        int total = 0;
        for (size_t i = 0; i < query_count; i++) for (int j = 0; j < 7; j++) total += query_counts[i]->counts[j];
        printf("stats queries=%d hits=%d\n", total, hits);
        if (query_count) qsort(query_counts, query_count, sizeof(*query_counts), query_compare);
        for (size_t i = 0; i < query_count; i++) {
            QueryCount *q = query_counts[i];
            int sent = 0;
            for (int j = 0; j < 7; j++) sent += q->counts[j];
            printf("  %s sent=%d", address(q->server), sent);
            for (int j = 0; j < 7; j++) {
                char *kind = copy(kinds[j]);
                for (size_t k = 0; kind[k]; k++) kind[k] = (char)tolower((unsigned char)kind[k]);
                printf(" %s=%d", kind, q->counts[j]);
            }
            putchar('\n');
        }
        printf("resolutions noerror=%d nodata=%d nxdomain=%d servfail=%d\n", resolutions[0], resolutions[1], resolutions[2], resolutions[3]);
    }
}

static char *read_line(void) {
    Buffer b = {0};
    int c;
    while ((c = getchar()) != EOF && c != '\n') append(&b, (char[]){(char)c, 0});
    if (c == EOF && !b.length) return NULL;
    return finish(&b);
}

int main(void) {
    char *line;
    int number = 0;
    while ((line = read_line()) && strcmp(line, "END ZONES")) {
        number++;
        size_t count;
        char **words = split(line, ' ', &count);
        if (setjmp(failure)) printf("error line %d: %s\n", number, error_reason);
        else zone_line(words, count, number);
    }
    number++;
    finish_zones();
    while ((line = read_line()) && strcmp(line, "END")) {
        number++;
        size_t count;
        char **words = split(line, ' ', &count);
        if (setjmp(failure)) printf("error line %d: %s\n", number, error_reason);
        else command(words, count);
    }
    return 0;
}
