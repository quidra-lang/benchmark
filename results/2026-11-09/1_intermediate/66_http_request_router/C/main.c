#include <ctype.h>
#include <regex.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define APPEND(array, count, item) do { (array) = grow((array), ((count) + 1) * sizeof(*(array))); (array)[(count)++] = (item); } while (0)
#define GET (1u << 1)
#define HEAD (1u << 2)
#define OPTIONS (1u << 3)
typedef struct {
    char *data;
    size_t length, capacity;
} Buffer;
typedef struct {
    char *name, *value;
} Pair;
typedef struct {
    Pair *items;
    size_t count;
} Pairs;
typedef struct {
    char kind;
    char *text;
} Piece;
typedef struct {
    char *name, *pattern, *role;
    unsigned methods;
    Piece *pieces;
    size_t count;
    char **types;
    size_t type_count;
    int literals, typed, number, selections;
    bool wildcard;
} Route;
typedef struct {
    char *from, *to;
    bool prefix;
    int code;
} Redirect;
typedef struct {
    char *name;
    int level, last, allowed, limited;
} Client;
enum { LOCATION, ALLOW, RETRY_AFTER, AUTHENTICATE, CORS_ORIGIN, CORS_METHODS, VARY, ETAG, CONTENT_TYPE, CONTENT_LENGTH, HEADER_COUNT };
typedef struct {
    int status;
    char *body, *type, *headers[HEADER_COUNT];
} Response;
typedef struct {
    char *line, **header_lines;
    size_t header_count;
    Pairs headers;
    bool head, headers_valid;
} Request;
static Route **routes, **priority;
static size_t route_count;
static Redirect **redirects;
static size_t redirect_count;
static Pairs tokens;
static char **origins;
static size_t origin_count;
static Client **clients;
static size_t client_count;
static int capacity, period, config_errors, requests, url_ok, url_errors, statuses[502];
static jmp_buf failure;
static char *error_message;
static const char *method_names[] = {"DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"};
static const char *header_names[] = {"Location", "Allow", "Retry-After", "WWW-Authenticate", "Access-Control-Allow-Origin", "Access-Control-Allow-Methods", "Vary", "ETag", "Content-Type", "Content-Length"};
static void *allocate(size_t n) {
    void *p = calloc(1, n ? n : 1);
    if (!p) exit(EXIT_FAILURE);
    return p;
}

static void *grow(void *p, size_t n) {
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

static void invalid(const char *pattern, ...) {
    va_list args, saved;
    va_start(args, pattern);
    va_copy(saved, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    error_message = allocate((size_t)n + 1);
    vsnprintf(error_message, (size_t)n + 1, pattern, saved);
    va_end(saved);
    longjmp(failure, 1);
}

static void append_n(Buffer *b, const char *text, size_t n) {
    if (b->length + n + 1 > b->capacity) {
        b->capacity = (b->length + n + 1) * 2;
        b->data = grow(b->data, b->capacity);
    }
    memcpy(b->data + b->length, text, n);
    b->length += n;
    b->data[b->length] = 0;
}

static void append(Buffer *b, const char *text) {
    append_n(b, text, strlen(text));
}

static void character(Buffer *b, char c) {
    append_n(b, &c, 1);
}

static char *finish(Buffer *b) {
    return b->data ? b->data : copy("");
}

static char *trim(const char *s) {
    while (*s == ' ') s++;
    size_t n = strlen(s);
    while (n && s[n - 1] == ' ') n--;
    return slice(s, n);
}

static char *lower(const char *s) {
    char *result = copy(s);
    for (size_t i = 0; result[i]; i++) if (result[i] >= 'A' && result[i] <= 'Z') result[i] += 'a' - 'A';
    return result;
}

static bool starts(const char *s, const char *prefix) {
    return !strncmp(s, prefix, strlen(prefix));
}

static bool ends(const char *s, const char *suffix) {
    size_t n = strlen(s), m = strlen(suffix);
    return n >= m && !strcmp(s + n - m, suffix);
}

static char **split(const char *s, char delimiter, size_t *count) {
    char **parts = NULL;
    size_t start = 0;
    *count = 0;
    for (size_t i = 0;; i++) if (!s[i] || s[i] == delimiter) {
        APPEND(parts, *count, slice(s + start, i - start));
        start = i + 1;
        if (!s[i]) break;
    }
    return parts;
}

static char *join(char **parts, size_t count, const char *separator) {
    Buffer b = {0};
    for (size_t i = 0; i < count; i++) {
        if (i) append(&b, separator);
        append(&b, parts[i]);
    }
    return finish(&b);
}

static bool matches(const char *s, const char *pattern) {
    regex_t regex;
    char *full = format("^(%s)$", pattern);
    if (regcomp(&regex, full, REG_EXTENDED | REG_NOSUB)) exit(EXIT_FAILURE);
    bool result = !regexec(&regex, s, 0, NULL, 0);
    regfree(&regex);
    free(full);
    return result;
}

static bool valid_name(const char *s) {
    return matches(s, "[a-z][a-z0-9_]{0,19}");
}

static bool media(const char *s) {
    return matches(s, "[a-z0-9.+-]+/[a-z0-9.+-]+");
}

static bool unreserved(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || (c && strchr("-._~", c));
}

static bool segment(const char *s) {
    if (!*s || !strcmp(s, ".") || !strcmp(s, "..")) return false;
    for (; *s; s++) if (!unreserved(*s)) return false;
    return true;
}

static bool canonical(const char *s) {
    if (!strcmp(s, "/")) return true;
    if (*s != '/') return false;
    size_t count;
    char **parts = split(s + 1, '/', &count);
    for (size_t i = 0; i < count; i++) if (!segment(parts[i])) return false;
    return true;
}

static bool rule_path(const char *s) {
    return canonical(s) || (ends(s, "/*") && strlen(s) > 3 && canonical(slice(s, strlen(s) - 2)));
}

static char *base(const char *s) {
    return ends(s, "/*") ? slice(s, strlen(s) - 2) : copy(s);
}

static unsigned method_bit(const char *s) {
    for (unsigned i = 0; i < 7; i++) if (!strcmp(s, method_names[i])) return 1u << i;
    return 0;
}

static char *method_list(unsigned methods, const char *separator) {
    char **parts = NULL;
    size_t count = 0;
    for (unsigned i = 0; i < 7; i++) if (methods & (1u << i)) APPEND(parts, count, (char *)method_names[i]);
    return join(parts, count, separator);
}

static int pair_index(Pairs pairs, const char *name) {
    for (size_t i = 0; i < pairs.count; i++) if (!strcmp(pairs.items[i].name, name)) return (int)i;
    return -1;
}

static char *pair_get(Pairs pairs, const char *name) {
    int i = pair_index(pairs, name);
    return i < 0 ? NULL : pairs.items[i].value;
}

static void pair_add(Pairs *pairs, char *name, char *value) {
    APPEND(pairs->items, pairs->count, ((Pair){name, value}));
}

static int pair_compare(const void *a, const void *b) {
    return strcmp(((const Pair *)a)->name, ((const Pair *)b)->name);
}

static Route *find_route(const char *name) {
    for (size_t i = 0; i < route_count; i++) if (!strcmp(routes[i]->name, name)) return routes[i];
    return NULL;
}

static bool parse_pattern(Route *r, const char *text) {
    if (*text != '/') return false;
    if (!strcmp(text, "/")) return true;
    size_t count;
    char **fields = split(text + 1, '/', &count);
    for (size_t i = 0; i < count; i++) {
        char *field = fields[i];
        Piece p = {'L', field};
        if (!segment(field)) {
            size_t n = strlen(field);
            if (n < 3 || *field != '{' || field[n - 1] != '}') return false;
            char *inside = slice(field + 1, n - 2);
            p.kind = 'U';
            p.text = inside;
            if (*inside == '*') {
                p.kind = 'W';
                p.text++;
                if (i + 1 != count) return false;
            } else {
                char *colon = strchr(inside, ':');
                if (colon) {
                    p.text = slice(inside, (size_t)(colon - inside));
                    if (!strcmp(colon + 1, "int")) p.kind = 'I';
                    else if (!strcmp(colon + 1, "slug")) p.kind = 'S';
                    else return false;
                }
            }
            if (!valid_name(p.text)) return false;
            for (size_t j = 0; j < r->count; j++) if (r->pieces[j].kind != 'L' && !strcmp(r->pieces[j].text, p.text)) return false;
        }
        if (p.kind == 'L') r->literals++;
        if (p.kind == 'I' || p.kind == 'S') r->typed++;
        if (p.kind == 'W') r->wildcard = true;
        APPEND(r->pieces, r->count, p);
    }
    return true;
}

static bool decimal(const char *s, int maximum) {
    if (!matches(s, "[1-9][0-9]*") || strlen(s) > strlen(format("%d", maximum))) return false;
    return atoi(s) <= maximum;
}

static void configure(char **a, size_t argc) {
    char *command = a[0];
    size_t n = argc - 1;
    if (strcmp(command, "ROUTE") && strcmp(command, "TOKEN") && strcmp(command, "REDIRECT") && strcmp(command, "ORIGIN") && strcmp(command, "LIMIT") && strcmp(command, "TYPES")) invalid("unknown command %s", command);
    bool correct = !strcmp(command, "ROUTE") ? n == 3 || n == 5 : !strcmp(command, "TOKEN") || !strcmp(command, "LIMIT") ? n == 2 : !strcmp(command, "REDIRECT") ? n == 3 : !strcmp(command, "ORIGIN") ? n == 1 : n >= 2;
    if (!correct) invalid("wrong number of arguments");
    if (!strcmp(command, "ROUTE")) {
        if (!valid_name(a[1])) invalid("bad route name %s", a[1]);
        if (find_route(a[1])) invalid("duplicate route %s", a[1]);
        Route *r = allocate(sizeof(*r));
        size_t count;
        char **methods = split(a[2], ',', &count);
        for (size_t i = 0; i < count; i++) {
            unsigned bit = method_bit(methods[i]);
            if (!bit || bit == HEAD || bit == OPTIONS || (r->methods & bit)) invalid("bad methods %s", a[2]);
            r->methods |= bit;
        }
        if (!parse_pattern(r, a[3])) invalid("bad pattern %s", a[3]);
        if (n == 5 && strcmp(a[4], "ROLE")) invalid("unknown option %s", a[4]);
        if (n == 5 && !matches(a[5], "[a-z]{1,16}")) invalid("bad role %s", a[5]);
        r->name = a[1];
        r->pattern = a[3];
        r->role = n == 5 ? a[5] : "none";
        r->number = (int)route_count;
        APPEND(routes, route_count, r);
    } else if (!strcmp(command, "TOKEN")) {
        if (!matches(a[1], "[A-Za-z0-9._-]{1,32}")) invalid("bad token %s", a[1]);
        if (pair_get(tokens, a[1])) invalid("duplicate token %s", a[1]);
        if (!matches(a[2], "[a-z]{1,16}")) invalid("bad role %s", a[2]);
        pair_add(&tokens, a[1], a[2]);
    } else if (!strcmp(command, "REDIRECT")) {
        if (!rule_path(a[1])) invalid("bad path %s", a[1]);
        if (!rule_path(a[2])) invalid("bad path %s", a[2]);
        bool prefix = ends(a[1], "/*");
        if (prefix != ends(a[2], "/*")) invalid("wildcard mismatch");
        if (strcmp(a[3], "301") && strcmp(a[3], "302") && strcmp(a[3], "307") && strcmp(a[3], "308")) invalid("bad redirect code %s", a[3]);
        char *from = base(a[1]);
        for (size_t i = 0; i < redirect_count; i++) if (redirects[i]->prefix == prefix && !strcmp(redirects[i]->from, from)) invalid("duplicate redirect %s", a[1]);
        Redirect *r = allocate(sizeof(*r));
        *r = (Redirect){from, base(a[2]), prefix, atoi(a[3])};
        APPEND(redirects, redirect_count, r);
    } else if (!strcmp(command, "ORIGIN")) {
        if (!matches(a[1], "https?://[a-z0-9.:-]+")) invalid("bad origin %s", a[1]);
        for (size_t i = 0; i < origin_count; i++) if (!strcmp(origins[i], a[1])) invalid("duplicate origin %s", a[1]);
        APPEND(origins, origin_count, a[1]);
    } else if (!strcmp(command, "LIMIT")) {
        if (!decimal(a[1], 100) || !decimal(a[2], 3600)) invalid("bad limit");
        if (capacity) invalid("duplicate limit");
        capacity = atoi(a[1]);
        period = atoi(a[2]);
    } else {
        Route *r = find_route(a[1]);
        if (!r) invalid("unknown route %s", a[1]);
        if (r->types) invalid("duplicate types %s", a[1]);
        for (size_t i = 2; i < argc; i++) {
            if (!media(a[i])) invalid("bad media type %s", a[i]);
            for (size_t j = 2; j < i; j++) if (!strcmp(a[i], a[j])) invalid("duplicate media type %s", a[i]);
        }
        for (size_t i = 2; i < argc; i++) APPEND(r->types, r->type_count, a[i]);
    }
}

static int route_compare(const void *a, const void *b) {
    const Route *x = *(Route *const *)a, *y = *(Route *const *)b;
    if (x->literals != y->literals) return y->literals - x->literals;
    if (x->typed != y->typed) return y->typed - x->typed;
    if (x->wildcard != y->wildcard) return x->wildcard ? 1 : -1;
    return x->number - y->number;
}

static void table(void) {
    printf("CONFIG routes=%zu tokens=%zu redirects=%zu origins=%zu limit=%s errors=%d\n", route_count, tokens.count, redirect_count, origin_count, capacity ? format("%d/%d", capacity, period) : "none", config_errors);
    priority = allocate(route_count * sizeof(*priority));
    if (route_count) memcpy(priority, routes, route_count * sizeof(*priority));
    qsort(priority, route_count, sizeof(*priority), route_compare);
    for (size_t i = 0; i < route_count; i++) {
        Route *r = priority[i];
        if (!r->types) APPEND(r->types, r->type_count, "application/json");
        printf("TABLE %zu %s %s %s role=%s types=%s\n", i + 1, r->name, method_list(r->methods | ((r->methods & GET) ? HEAD : 0), ","), r->pattern, !strcmp(r->role, "none") ? "-" : r->role, join(r->types, r->type_count, ","));
    }
}

static int hex(char c) {
    return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
}

static char *decode(const char *s) {
    Buffer b = {0};
    for (size_t i = 0; s[i]; i++) if (s[i] == '%') {
        character(&b, (char)(hex(s[i + 1]) * 16 + hex(s[i + 2])));
        i += 2;
    } else character(&b, s[i]);
    return finish(&b);
}

static char *encode(const char *s) {
    Buffer b = {0};
    for (; *s; s++) if (unreserved(*s)) character(&b, *s);
    else append(&b, format("%%%02X", (unsigned char)*s));
    return finish(&b);
}

static char *query_decode(const char *s) {
    char *text = copy(s);
    for (size_t i = 0; text[i]; i++) if (text[i] == '+') text[i] = ' ';
    return decode(text);
}

static char *normalize(const char *path) {
    Buffer text = {0};
    for (size_t i = 0; path[i]; i++) if (path[i] == '%') {
        char c = (char)(hex(path[i + 1]) * 16 + hex(path[i + 2]));
        if (unreserved(c)) character(&text, c);
        else append(&text, format("%%%02X", (unsigned char)c));
        i += 2;
    } else character(&text, path[i]);
    size_t count, used = 0;
    char **parts = split(finish(&text) + 1, '/', &count), **segments = NULL;
    for (size_t i = 0; i < count; i++) if (!strcmp(parts[i], "..")) {
        if (used) used--;
    } else if (*parts[i] && strcmp(parts[i], ".")) APPEND(segments, used, parts[i]);
    return format("/%s", join(segments, used, "/"));
}

static bool route_matches(Route *r, char **segments, size_t count) {
    size_t m = r->count - (r->wildcard ? 1 : 0);
    if (r->wildcard ? count < m : count != m) return false;
    for (size_t i = 0; i < m; i++) {
        Piece p = r->pieces[i];
        if ((p.kind == 'L' && strcmp(p.text, segments[i])) || (p.kind == 'I' && !matches(segments[i], "[0-9]{1,9}")) || (p.kind == 'S' && !matches(segments[i], "[a-z0-9-]+"))) return false;
    }
    return true;
}

static char *negotiate(Route *r, const char *accept) {
    if (!accept) return r->types[0];
    char *selected = NULL;
    int best_weight = 0;
    size_t count;
    char **elements = split(accept, ',', &count);
    for (size_t t = 0; t < r->type_count; t++) {
        int specificity = 0, weight = 0;
        for (size_t i = 0; i < count; i++) {
            size_t fields;
            char **parts = split(elements[i], ';', &fields);
            char *range = lower(trim(parts[0]));
            int spec = !strcmp(range, "*/*") ? 1 : matches(range, "[a-z0-9.+-]+/\\*") ? 2 : media(range) ? 3 : 0;
            if (!spec) continue;
            char *q = NULL;
            for (size_t j = 1; j < fields; j++) {
                char *eq = strchr(parts[j], '=');
                if (eq && !strcmp(lower(trim(slice(parts[j], (size_t)(eq - parts[j])))), "q")) {
                    q = trim(eq + 1);
                    break;
                }
            }
            int value = 1000;
            if (q) {
                if (!matches(q, "[01](\\.[0-9]{0,3})?")) continue;
                bool valid = true;
                for (size_t j = 2; q[1] && q[j]; j++) if (q[0] == '1' && q[j] != '0') valid = false;
                if (!valid) continue;
                value = (q[0] - '0') * 1000;
                if (q[1]) {
                    int factor = 100;
                    for (size_t j = 2; q[j]; j++, factor /= 10) value += (q[j] - '0') * factor;
                }
            }
            bool fits = spec == 1 || (spec == 2 && starts(r->types[t], slice(range, strlen(range) - 1))) || (spec == 3 && !strcmp(range, r->types[t]));
            if (fits && spec > specificity) {
                specificity = spec;
                weight = value;
            }
        }
        if (weight > best_weight) {
            best_weight = weight;
            selected = r->types[t];
        }
    }
    return selected;
}

static char *json(const char *s) {
    Buffer b = {0};
    character(&b, '"');
    for (; *s; s++) {
        if (*s == '\\' || *s == '"') character(&b, '\\');
        character(&b, *s);
    }
    character(&b, '"');
    return finish(&b);
}

static char *html(const char *s) {
    Buffer b = {0};
    for (; *s; s++) switch (*s) {
        case '&': append(&b, "&amp;");
        break;
        case '<': append(&b, "&lt;");
        break;
        case '>': append(&b, "&gt;");
        break;
        case '"': append(&b, "&quot;");
        break;
        default: character(&b, *s);
    }
    return finish(&b);
}

static char *json_pairs(Pairs pairs, bool query) {
    Buffer b = {0};
    character(&b, query ? '[' : '{');
    for (size_t i = 0; i < pairs.count; i++) {
        if (i) character(&b, ',');
        Pair p = pairs.items[i];
        append(&b, query ? format("[%s,%s]", json(p.name), json(p.value)) : format("%s:%s", json(p.name), json(p.value)));
    }
    character(&b, query ? ']' : '}');
    return finish(&b);
}

static char *encoded_pairs(Pairs pairs) {
    if (!pairs.count) return "-";
    Buffer b = {0};
    for (size_t i = 0; i < pairs.count; i++) {
        if (i) character(&b, '&');
        append(&b, format("%s=%s", encode(pairs.items[i].name), encode(pairs.items[i].value)));
    }
    return finish(&b);
}

static char *body(Route *r, char **segments, size_t segment_count, const char *query, Pairs headers, const char *type) {
    Pairs parameters = {0}, queries = {0}, cookies = {0};
    for (size_t i = 0; i < r->count; i++) {
        Piece p = r->pieces[i];
        if (p.kind == 'L') continue;
        char *value;
        if (p.kind == 'W') {
            Buffer b = {0};
            for (size_t j = i; j < segment_count; j++) {
                if (j > i) character(&b, '/');
                append(&b, decode(segments[j]));
            }
            value = finish(&b);
        } else value = p.kind == 'I' ? format("%d", atoi(segments[i])) : p.kind == 'U' ? decode(segments[i]) : segments[i];
        pair_add(&parameters, p.text, value);
    }
    if (parameters.count) qsort(parameters.items, parameters.count, sizeof(*parameters.items), pair_compare);
    if (query) {
        size_t count;
        char **parts = split(query, '&', &count);
        for (size_t i = 0; i < count; i++) if (*parts[i]) {
            char *eq = strchr(parts[i], '=');
            pair_add(&queries, query_decode(eq ? slice(parts[i], (size_t)(eq - parts[i])) : parts[i]), query_decode(eq ? eq + 1 : ""));
        }
    }
    char *cookie = pair_get(headers, "cookie");
    if (cookie) {
        size_t count;
        char **parts = split(cookie, ';', &count);
        for (size_t i = 0; i < count; i++) {
            char *part = trim(parts[i]), *eq = strchr(part, '=');
            if (eq && eq != part) {
                char *name = slice(part, (size_t)(eq - part));
                if (pair_index(cookies, name) < 0) pair_add(&cookies, name, eq + 1);
            }
        }
    }
    if (cookies.count) qsort(cookies.items, cookies.count, sizeof(*cookies.items), pair_compare);
    if (!strcmp(type, "application/json")) return format("{\"route\":%s,\"params\":%s,\"query\":%s,\"cookies\":%s}", json(r->name), json_pairs(parameters, false), json_pairs(queries, true), json_pairs(cookies, false));
    if (!strcmp(type, "text/html")) {
        Buffer b = {0};
        append(&b, format("<dl><dt>route</dt><dd>%s</dd>", html(r->name)));
        Pairs groups[] = {parameters, queries, cookies};
        char *labels[] = {"param", "query", "cookie"};
        for (int i = 0; i < 3; i++) for (size_t j = 0; j < groups[i].count; j++) {
            Pair p = groups[i].items[j];
            append(&b, format("<dt>%s %s</dt><dd>%s</dd>", labels[i], html(p.name), html(p.value)));
        }
        append(&b, "</dl>");
        return finish(&b);
    }
    return format("route=%s params=%s query=%s cookies=%s", r->name, encoded_pairs(parameters), encoded_pairs(queries), encoded_pairs(cookies));
}

static char *etag(const char *s) {
    unsigned a = 1, b = 0;
    for (; *s; s++) {
        a = (a + (unsigned char)*s) % 65521;
        b = (b + a) % 65521;
    }
    return format("\"%04x%04x\"", b, a);
}

static Response *response(int status, char *body) {
    Response *r = allocate(sizeof(*r));
    r->status = status;
    r->body = body;
    r->type = "text/plain";
    return r;
}

static Response *with_header(Response *r, int header, char *value) {
    r->headers[header] = value;
    return r;
}

static Response *process(Request *request) {
    size_t count;
    char **line = split(request->line, ' ', &count);
    if (count != 3 || !matches(line[0], "[A-Z]{1,16}") || *line[1] != '/' || strchr(line[1], '#') || strcmp(line[2], "HTTP/1.1")) return response(400, "bad request: request line");
    char *method = line[0], *target = line[1];
    request->head = !strcmp(method, "HEAD");
    for (size_t i = 0; target[i]; i++) if (target[i] == '%') {
        if (!target[i + 1] || !target[i + 2] || hex(target[i + 1]) < 0 || hex(target[i + 2]) < 0) return response(400, "bad request: percent escape");
        int value = hex(target[i + 1]) * 16 + hex(target[i + 2]);
        if (value < 32 || value > 126) return response(400, "bad request: percent escape");
        i += 2;
    }
    for (size_t i = 0; i < request->header_count; i++) {
        char *header = request->header_lines[i], *colon = strchr(header, ':');
        if (!colon || !matches(slice(header, (size_t)(colon - header)), "[A-Za-z0-9-]+")) return response(400, format("bad request: header line %zu", i + 1));
        char *name = lower(slice(header, (size_t)(colon - header)));
        if (pair_index(request->headers, name) >= 0) return response(400, format("bad request: duplicate header %s", name));
        pair_add(&request->headers, name, trim(colon + 1));
    }
    request->headers_valid = true;
    Pairs headers = request->headers;
    if (!method_bit(method)) return response(501, format("not implemented: %s", method));
    char *host = pair_get(headers, "host");
    if (!host || !*host) return response(400, "bad request: missing host");
    char *effective = method, *override = pair_get(headers, "x-http-method-override");
    if (override) {
        if (strcmp(method, "POST") || (strcmp(override, "PUT") && strcmp(override, "PATCH") && strcmp(override, "DELETE"))) return response(400, "bad request: method override");
        effective = override;
    }
    char *client_name = pair_get(headers, "x-client");
    if (client_name && *client_name) {
        int time = atoi(pair_get(headers, "x-time"));
        Client *client = NULL;
        for (size_t i = 0; i < client_count; i++) if (!strcmp(clients[i]->name, client_name)) {
            client = clients[i];
            break;
        }
        if (!client) {
            client = allocate(sizeof(*client));
            client->name = client_name;
            client->level = capacity * period;
            client->last = time;
            APPEND(clients, client_count, client);
        }
        if (capacity) {
            int level = client->level + (time - client->last) * capacity;
            client->level = level < capacity * period ? level : capacity * period;
            client->last = time;
            if (client->level < period) {
                client->limited++;
                return with_header(response(429, format("too many requests: client %s", client_name)), RETRY_AFTER, format("%d", (period - client->level + capacity - 1) / capacity));
            }
            client->level -= period;
        }
        client->allowed++;
    }
    char *question = strchr(target, '?'), *path = question ? slice(target, (size_t)(question - target)) : target, *query = question ? question + 1 : NULL, *suffix = question ? question : "";
    char *normal = normalize(path);
    if (strcmp(normal, path)) {
        char *location = format("%s%s", normal, suffix);
        return with_header(response(308, format("redirect to %s", location)), LOCATION, location);
    }
    for (size_t i = 0; i < redirect_count; i++) {
        Redirect *r = redirects[i];
        if (!strcmp(path, r->from) || (r->prefix && starts(path, format("%s/", r->from)))) {
            char *location = format("%s%s%s", r->to, path + strlen(r->from), suffix);
            return with_header(response(r->code, format("redirect to %s", location)), LOCATION, location);
        }
    }
    size_t segment_count = 0;
    char **segments = !strcmp(path, "/") ? NULL : split(path + 1, '/', &segment_count);
    unsigned allowed = OPTIONS;
    Route *selected = NULL;
    bool any = false;
    char *lookup = !strcmp(effective, "HEAD") ? "GET" : effective;
    for (size_t i = 0; i < route_count; i++) if (route_matches(priority[i], segments, segment_count)) {
        any = true;
        allowed |= priority[i]->methods;
        if (!selected && (priority[i]->methods & method_bit(lookup))) selected = priority[i];
    }
    if (!any) return response(404, format("not found: %s", path));
    if (allowed & GET) allowed |= HEAD;
    char *allow = method_list(allowed, ", ");
    if (!strcmp(effective, "OPTIONS")) return with_header(response(204, ""), ALLOW, allow);
    if (!selected) return with_header(response(405, format("method not allowed: %s", effective)), ALLOW, allow);
    selected->selections++;
    if (strcmp(selected->role, "none")) {
        char *auth = pair_get(headers, "authorization");
        if (!auth) return with_header(response(401, "unauthorized: missing token"), AUTHENTICATE, "Bearer realm=\"api\"");
        char *space = strchr(auth, ' '), *scheme = space ? slice(auth, (size_t)(space - auth)) : auth, *token = space ? space + 1 : "", *role = pair_get(tokens, token);
        if (strcmp(lower(scheme), "bearer") || !role) return with_header(response(401, "unauthorized: invalid token"), AUTHENTICATE, "Bearer realm=\"api\", error=\"invalid_token\"");
        if (strcmp(role, selected->role) && strcmp(role, "admin")) return response(403, format("forbidden: requires role %s", selected->role));
    }
    char *type = negotiate(selected, pair_get(headers, "accept"));
    Response *result;
    if (!type) result = response(406, format("not acceptable: %s", join(selected->types, selected->type_count, ", ")));
    else {
        char *text = body(selected, segments, segment_count, query, headers, type), *tag = etag(text), *condition = pair_get(headers, "if-none-match");
        bool matched = false;
        if (condition) {
            size_t n;
            char **parts = split(condition, ',', &n);
            for (size_t i = 0; i < n; i++) {
                char *value = trim(parts[i]);
                if (starts(value, "W/")) value += 2;
                if (!strcmp(value, "*") || !strcmp(value, tag)) matched = true;
            }
        }
        if (matched && !strcmp(lookup, "GET")) result = with_header(response(304, ""), ETAG, tag);
        else if (matched) result = response(412, format("precondition failed: %s", tag));
        else {
            result = with_header(response(200, text), ETAG, tag);
            result->type = type;
        }
    }
    if (selected->type_count >= 2) result->headers[VARY] = "Accept";
    return result;
}

static char *phrase(int status) {
    switch (status) {
        case 200: return "OK";
        case 204: return "No Content";
        case 301: return "Moved Permanently";
        case 302: return "Found";
        case 304: return "Not Modified";
        case 307: return "Temporary Redirect";
        case 308: return "Permanent Redirect";
        case 400: return "Bad Request";
        case 401: return "Unauthorized";
        case 403: return "Forbidden";
        case 404: return "Not Found";
        case 405: return "Method Not Allowed";
        case 406: return "Not Acceptable";
        case 412: return "Precondition Failed";
        case 429: return "Too Many Requests";
        default: return "Not Implemented";
    }
}

static void respond(Request request) {
    Response *r = process(&request);
    char *origin = pair_get(request.headers, "origin");
    bool permitted = false;
    if (origin) for (size_t i = 0; i < origin_count; i++) if (!strcmp(origins[i], origin)) permitted = true;
    if (request.headers_valid && permitted) {
        r->headers[CORS_ORIGIN] = origin;
        if (r->status == 204 && pair_get(request.headers, "access-control-request-method")) r->headers[CORS_METHODS] = r->headers[ALLOW];
    }
    if (r->status != 204 && r->status != 304) {
        r->headers[CONTENT_TYPE] = r->status == 200 ? r->type : "text/plain";
        r->headers[CONTENT_LENGTH] = format("%zu", strlen(r->body));
    }
    statuses[r->status]++;
    printf("REQUEST %d\nHTTP/1.1 %d %s\n", ++requests, r->status, phrase(r->status));
    for (int i = 0; i < HEADER_COUNT; i++) if (r->headers[i]) printf("%s: %s\n", header_names[i], r->headers[i]);
    if (r->status != 204 && r->status != 304 && !request.head) puts(r->body);
}

static bool valid_parameter(Piece p, const char *value) {
    if (p.kind == 'I') return matches(value, "[0-9]{1,9}");
    if (p.kind == 'S') return matches(value, "[a-z0-9-]+");
    if (p.kind == 'W' && *value) {
        size_t count;
        char **parts = split(value, '/', &count);
        for (size_t i = 0; i < count; i++) if (!*parts[i] || !strcmp(parts[i], ".") || !strcmp(parts[i], "..")) return false;
        return true;
    }
    return p.kind == 'W' || (*value && strcmp(value, ".") && strcmp(value, ".."));
}

static bool parameter_name(Route *r, const char *name) {
    for (size_t i = 0; i < r->count; i++) if (r->pieces[i].kind != 'L' && !strcmp(r->pieces[i].text, name)) return true;
    return false;
}

static void urlfor(char **a, size_t argc) {
    if (setjmp(failure)) {
        url_errors++;
        printf("URLFOR ERROR %s\n", error_message);
        return;
    }
    Route *r = find_route(a[1]);
    if (!r) invalid("unknown route %s", a[1]);
    Pairs parameters = {0}, query = {0};
    for (size_t i = 2; i < argc; i++) {
        char *eq = strchr(a[i], '=');
        if (!eq || eq == a[i]) invalid("bad argument %s", a[i]);
        char *name = slice(a[i], (size_t)(eq - a[i]));
        if (parameter_name(r, name)) {
            if (pair_index(parameters, name) >= 0) invalid("duplicate parameter %s", name);
            pair_add(&parameters, name, eq + 1);
        } else pair_add(&query, name, eq + 1);
    }
    for (size_t i = 0; i < r->count; i++) {
        Piece p = r->pieces[i];
        if (p.kind == 'L') continue;
        char *value = pair_get(parameters, p.text);
        if (!value && p.kind != 'W') invalid("missing parameter %s", p.text);
        if (!valid_parameter(p, value ? value : "")) invalid("bad value for %s", p.text);
    }
    Buffer path = {0};
    for (size_t i = 0; i < r->count; i++) {
        Piece p = r->pieces[i];
        char *value = p.kind == 'L' ? p.text : pair_get(parameters, p.text);
        if (p.kind == 'W') {
            if (value && *value) {
                size_t count;
                char **parts = split(value, '/', &count);
                for (size_t j = 0; j < count; j++) {
                    character(&path, '/');
                    append(&path, encode(parts[j]));
                }
            }
        } else {
            character(&path, '/');
            append(&path, p.kind == 'L' ? value : encode(value));
        }
    }
    if (!path.length) character(&path, '/');
    if (query.count) {
        character(&path, '?');
        append(&path, encoded_pairs(query));
    }
    url_ok++;
    printf("URLFOR %s %s\n", a[1], finish(&path));
}

static char *read_line(void) {
    Buffer b = {0};
    int c;
    while ((c = getchar()) != EOF && c != '\n') character(&b, (char)c);
    if (c == EOF && !b.length) return NULL;
    return finish(&b);
}

static int client_compare(const void *a, const void *b) {
    return strcmp((*(Client *const *)a)->name, (*(Client *const *)b)->name);
}

int main(void) {
    char *line;
    int number = 0;
    while ((line = read_line()) && strcmp(line, "REQUESTS")) {
        number++;
        size_t argc;
        char **words = split(line, ' ', &argc);
        if (setjmp(failure)) {
            config_errors++;
            printf("CONFIG ERROR %d: %s\n", number, error_message);
        } else configure(words, argc);
    }
    table();
    while ((line = read_line()) && strcmp(line, "END")) {
        if (starts(line, "URLFOR ")) {
            size_t argc;
            char **words = split(line, ' ', &argc);
            urlfor(words, argc);
        } else {
            Request request = { .line = line };
            char *header;
            while ((header = read_line()) && *header) APPEND(request.header_lines, request.header_count, header);
            respond(request);
        }
    }
    printf("SUMMARY requests=%d urlfor_ok=%d urlfor_error=%d\n", requests, url_ok, url_errors);
    for (int i = 0; i < 502; i++) if (statuses[i]) printf("STATUS %d %d\n", i, statuses[i]);
    for (size_t i = 0; i < route_count; i++) printf("ROUTE %s %d\n", routes[i]->name, routes[i]->selections);
    if (client_count) qsort(clients, client_count, sizeof(*clients), client_compare);
    for (size_t i = 0; i < client_count; i++) printf("CLIENT %s allowed=%d limited=%d\n", clients[i]->name, clients[i]->allowed, clients[i]->limited);
    return 0;
}
