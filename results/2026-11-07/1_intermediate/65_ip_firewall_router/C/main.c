#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define APPEND(array, count, value) do { (array) = grow((array), ((count) + 1) * sizeof(*(array))); (array)[(count)++] = (value); } while (0)
typedef struct {
    uint32_t address;
    int length;
} Prefix;
typedef struct {
    int first, last;
    bool any;
} Ports;
typedef struct Rule Rule;
typedef struct {
    char *name, *rpf;
    Prefix prefix;
    bool up, outside;
    int pool, rx, tx, drop;
    Rule **acl[2];
    size_t acl_count[2];
    int defaults[2];
} Interface;
typedef struct {
    char type;
    Prefix prefix;
    Interface *output;
    bool via;
    uint32_t hop;
    int metric, hits;
    size_t order;
} Route;
struct Rule {
    int sequence, hits;
    char *action, *protocol;
    Prefix source, destination;
    Ports sports, dports;
    bool established;
};
typedef struct {
    uint32_t inside, outside;
} StaticNat;
typedef struct {
    Interface *interface;
    char *protocol;
    int port;
    uint32_t inside;
    int inport;
} Forward;
typedef struct {
    Interface *interface;
    char *protocol;
    uint32_t inside;
    int inport, port, last;
} Pat;
typedef struct {
    char *protocol;
    uint32_t source, destination;
    int sport, dport;
} Tuple;
typedef struct {
    int number, orig_packets, reply_packets, last;
    Tuple orig, reply;
    Interface *input, *output;
    char *state;
    bool orig_fin, reply_fin;
} Connection;
static Interface **interfaces;
static size_t interface_count;
static Route **routes;
static size_t route_count, route_order;
static StaticNat **statics;
static size_t static_count;
static Forward **forwards;
static size_t forward_count;
static Pat **pats;
static size_t pat_count;
static Connection **connections;
static size_t connection_count;
static const char *reasons[] = {"down", "martian", "rpf", "invalid", "acl_in", "ttl", "noroute", "acl_out", "exhausted"};
static int drops[9], timeouts[] = {300, 60, 30}, clock_time, packet_number, connection_number, forwarded, local, errors;
static jmp_buf failure;
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

static char *format(const char *pattern, ...) {
    va_list args, copy;
    va_start(args, pattern);
    va_copy(copy, args);
    int n = vsnprintf(NULL, 0, pattern, args);
    va_end(args);
    char *s = allocate((size_t)n + 1);
    vsnprintf(s, (size_t)n + 1, pattern, copy);
    va_end(copy);
    return s;
}

static void error(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    fputs("error: ", stdout);
    vprintf(pattern, args);
    putchar('\n');
    va_end(args);
    errors++;
    longjmp(failure, 1);
}

static uint32_t mask(int length) {
    return length ? UINT32_MAX << (32 - length) : 0;
}

static uint32_t network(Prefix p) {
    return p.address & mask(p.length);
}

static bool contains(Prefix p, uint32_t value) {
    return (value & mask(p.length)) == network(p);
}

static char *ip(uint32_t a) {
    return format("%u.%u.%u.%u", a >> 24, (a >> 16) & 255, (a >> 8) & 255, a & 255);
}

static char *prefix_text(Prefix p) {
    return format("%s/%d", ip(p.address), p.length);
}

static bool parse_address(const char *s, uint32_t *result) {
    uint32_t address = 0;
    for (int i = 0; i < 4; i++) {
        int value = 0, digits = 0;
        const char *start = s;
        while (*s >= '0' && *s <= '9') {
            value = value * 10 + *s++ - '0';
            if (++digits > 3) return false;
        }
        if (!digits || (digits > 1 && *start == '0') || value > 255) return false;
        address = (address << 8) | (uint32_t)value;
        if (i < 3) {
            if (*s++ != '.') return false;
        } else if (*s) return false;
    }
    *result = address;
    return true;
}

static uint32_t address(const char *text) {
    uint32_t value;
    if (!parse_address(text, &value)) error("bad address %s", text);
    return value;
}

static bool parse_prefix(const char *s, Prefix *result) {
    const char *slash = strchr(s, '/');
    if (!slash || strchr(slash + 1, '/')) return false;
    uint32_t value;
    if (!parse_address(slice(s, (size_t)(slash - s)), &value)) return false;
    const char *length = slash + 1;
    size_t n = strlen(length);
    if (!n || n > 2 || (n > 1 && *length == '0')) return false;
    for (size_t i = 0; i < n; i++) if (length[i] < '0' || length[i] > '9') return false;
    int bits = atoi(length);
    if (bits > 32) return false;
    *result = (Prefix){value, bits};
    return true;
}

static Prefix prefix(const char *s, bool any) {
    if (any && !strcmp(s, "ANY")) return (Prefix){0, 0};
    Prefix p;
    if (!parse_prefix(s, &p)) error("bad prefix %s", s);
    if (p.address != network(p)) error("host bits set in %s", s);
    return p;
}

static bool equal_prefix(Prefix a, Prefix b) {
    return a.address == b.address && a.length == b.length;
}

static Interface *find_interface(const char *name) {
    for (size_t i = 0; i < interface_count; i++) if (!strcmp(interfaces[i]->name, name)) return interfaces[i];
    error("no interface %s", name);
    return NULL;
}

static Interface *local_address(uint32_t a) {
    for (size_t i = 0; i < interface_count; i++) if (interfaces[i]->prefix.address == a) return interfaces[i];
    return NULL;
}

static int range(const char *s, int low, int high, const char *reason) {
    int n = atoi(s);
    if (n < low || n > high) error("%s %s", reason, s);
    return n;
}

static Ports ports(const char *s) {
    if (!strcmp(s, "ANY")) return (Ports){0, 65535, true};
    const char *dash = strchr(s, '-');
    int first = atoi(s), last = dash ? atoi(dash + 1) : first;
    if (first > 65535 || last > 65535 || first > last) error("bad port range %s", s);
    return (Ports){first, last, false};
}

static char *ports_text(Ports p) {
    return p.any ? "any" : p.first == p.last ? format("%d", p.first) : format("%d-%d", p.first, p.last);
}

static int protocol_index(const char *p) {
    return !strcmp(p, "TCP") ? 0 : !strcmp(p, "UDP") ? 1 : 2;
}

static Route *select_route(uint32_t value) {
    Route *best = NULL;
    for (size_t i = 0; i < route_count; i++) {
        Route *r = routes[i];
        if (r->output->up && contains(r->prefix, value) && (!best || r->prefix.length > best->prefix.length || (r->prefix.length == best->prefix.length && r->metric < best->metric))) best = r;
    }
    return best;
}

static Route *add_route(char type, Prefix p, Interface *output, bool via, uint32_t hop, int metric) {
    Route *r = allocate(sizeof(*r));
    *r = (Route){type, p, output, via, hop, metric, 0, route_order++};
    APPEND(routes, route_count, r);
    return r;
}

static char *route_text(Route *r) {
    return format("%c %s%s dev %s metric %d", r->type, prefix_text(r->prefix), r->via ? format(" via %s", ip(r->hop)) : "", r->output->name, r->metric);
}

static int rule_compare(const void *a, const void *b) {
    const Rule *x = *(Rule *const *)a, *y = *(Rule *const *)b;
    return (x->sequence > y->sequence) - (x->sequence < y->sequence);
}

static char *acl(Interface *iface, int direction, Tuple packet, uint32_t source, int sport, uint32_t destination, int dport, bool established) {
    if (!iface->acl_count[direction]) return NULL;
    const char *dir = direction ? "out" : "in";
    for (size_t i = 0; i < iface->acl_count[direction]; i++) {
        Rule *r = iface->acl[direction][i];
        if ((strcmp(r->protocol, "ANY") && strcmp(r->protocol, packet.protocol)) || !contains(r->source, source) || !contains(r->destination, destination) || (r->established && !established)) continue;
        if ((!strcmp(r->protocol, "TCP") || !strcmp(r->protocol, "UDP")) && (sport < r->sports.first || sport > r->sports.last || dport < r->dports.first || dport > r->dports.last)) continue;
        r->hits++;
        if (!strcmp(r->action, "PERMIT")) return NULL;
        bool reject = !strcmp(r->action, "REJECT");
        return format("%s acl %s %s %d%s", reject ? "REJECT" : "DROP", iface->name, dir, r->sequence, reject ? (!strcmp(packet.protocol, "TCP") ? " tcp-reset" : " icmp-prohibited") : "");
    }
    iface->defaults[direction]++;
    return format("DROP acl %s %s default", iface->name, dir);
}

static bool martian(uint32_t a) {
    return (a >> 24) == 0 || (a >> 24) == 127 || (a >> 29) == 7;
}

static bool tuple_equal(Tuple a, Tuple b) {
    return !strcmp(a.protocol, b.protocol) && a.source == b.source && a.sport == b.sport && a.destination == b.destination && a.dport == b.dport;
}

static char *drop(Interface *input, int reason, char *verdict) {
    drops[reason]++;
    input->drop++;
    return verdict;
}

static void remove_connection(size_t index) {
    memmove(connections + index, connections + index + 1, (connection_count - index - 1) * sizeof(*connections));
    connection_count--;
}

static char *packet(Interface *input, Tuple original, const char *flags, int ttl) {
    input->rx++;
    if (!input->up) return drop(input, 0, "DROP down");
    if (martian(original.source) || martian(original.destination) || local_address(original.source)) return drop(input, 1, "DROP martian");
    if (strcmp(input->rpf, "off")) {
        Route *r = select_route(original.source);
        if (!r || (!strcmp(input->rpf, "strict") && r->output != input)) return drop(input, 2, "DROP rpf");
    }
    bool pure_syn = !strcmp(original.protocol, "TCP") && !strcmp(flags, "S");
    Connection *connection = NULL;
    const char *direction = "new";
    for (size_t i = 0; i < connection_count; i++) {
        Connection *c = connections[i];
        bool orig = tuple_equal(c->orig, original), reply = !orig && tuple_equal(c->reply, original);
        if (!orig && !reply) continue;
        if (!strcmp(c->state, "CLOSED") && pure_syn) remove_connection(i);
        else {
            connection = c;
            direction = orig ? "orig" : "reply";
        }
        break;
    }
    if (!strcmp(original.protocol, "TCP") && !connection && !pure_syn) return drop(input, 3, "DROP invalid");
    char *verdict = acl(input, 0, original, original.source, original.sport, original.destination, original.dport, connection != NULL);
    if (verdict) return drop(input, 4, verdict);
    uint32_t source = original.source, destination = original.destination;
    int sport = original.sport, dport = original.dport;
    Pat *used = NULL;
    if (input->outside) {
        StaticNat *mapping = NULL;
        for (size_t i = 0; i < static_count; i++) if (statics[i]->outside == destination) {
            mapping = statics[i];
            break;
        }
        if (mapping) destination = mapping->inside;
        else if (destination == input->prefix.address) {
            Forward *f = NULL;
            for (size_t i = 0; i < forward_count; i++) if (forwards[i]->interface == input && !strcmp(forwards[i]->protocol, original.protocol) && forwards[i]->port == dport) {
                f = forwards[i];
                break;
            }
            if (f) {
                destination = f->inside;
                dport = f->inport;
            } else for (size_t i = 0; i < pat_count; i++) if (pats[i]->interface == input && !strcmp(pats[i]->protocol, original.protocol) && pats[i]->port == dport) {
                used = pats[i];
                destination = used->inside;
                dport = used->inport;
                break;
            }
        }
    }
    Interface *target = local_address(destination);
    if (target) {
        local++;
        return format("LOCAL %s", target->name);
    }
    if (ttl == 1) return drop(input, 5, "DROP ttl");
    Route *route = select_route(destination);
    if (!route) return drop(input, 6, "DROP noroute");
    Interface *output = route->output;
    verdict = acl(output, 1, original, source, sport, destination, dport, connection != NULL);
    if (verdict) return drop(input, 7, verdict);
    if (!input->outside && output->outside) {
        StaticNat *mapping = NULL;
        for (size_t i = 0; i < static_count; i++) if (statics[i]->inside == source) {
            mapping = statics[i];
            break;
        }
        if (mapping) source = mapping->outside;
        else {
            Forward *f = NULL;
            for (size_t i = 0; i < forward_count; i++) if (forwards[i]->interface == output && !strcmp(forwards[i]->protocol, original.protocol) && forwards[i]->inside == source && forwards[i]->inport == sport) {
                f = forwards[i];
                break;
            }
            if (f) {
                source = output->prefix.address;
                sport = f->port;
            } else if (output->pool) {
                for (size_t i = 0; i < pat_count; i++) if (pats[i]->interface == output && !strcmp(pats[i]->protocol, original.protocol) && pats[i]->inside == source && pats[i]->inport == sport) {
                    used = pats[i];
                    break;
                }
                if (!used) {
                    int port;
                    for (port = 20000; port < 20000 + output->pool; port++) {
                        bool occupied = false;
                        for (size_t i = 0; i < pat_count; i++) if (pats[i]->interface == output && pats[i]->port == port) occupied = true;
                        for (size_t i = 0; i < forward_count; i++) if (forwards[i]->interface == output && forwards[i]->port == port) occupied = true;
                        if (!occupied) break;
                    }
                    if (port == 20000 + output->pool) return drop(input, 8, "DROP exhausted");
                    used = allocate(sizeof(*used));
                    *used = (Pat){output, original.protocol, source, sport, port, clock_time};
                    APPEND(pats, pat_count, used);
                }
                source = output->prefix.address;
                sport = used->port;
            }
        }
    }
    if (used) used->last = clock_time;
    if (!connection) {
        connection = allocate(sizeof(*connection));
        connection->number = ++connection_number;
        connection->orig = original;
        connection->reply = (Tuple){original.protocol, destination, source, dport, sport};
        connection->input = input;
        connection->output = output;
        connection->state = !strcmp(original.protocol, "TCP") ? "SYN_SENT" : "UNREPLIED";
        APPEND(connections, connection_count, connection);
    }
    if (!strcmp(direction, "reply")) connection->reply_packets++;
    else connection->orig_packets++;
    connection->last = clock_time;
    if (strcmp(original.protocol, "TCP")) {
        if (!strcmp(direction, "reply")) connection->state = "REPLIED";
    } else if (strchr(flags, 'R')) connection->state = "CLOSED";
    else {
        if (!strcmp(connection->state, "SYN_SENT") && !strcmp(direction, "reply") && strchr(flags, 'S') && strchr(flags, 'A')) connection->state = "ESTABLISHED";
        if (strchr(flags, 'F') && (!strcmp(connection->state, "ESTABLISHED") || !strcmp(connection->state, "FIN_WAIT"))) {
            if (!strcmp(direction, "reply")) connection->reply_fin = true;
            else connection->orig_fin = true;
            connection->state = connection->orig_fin && connection->reply_fin ? "CLOSED" : "FIN_WAIT";
        }
    }
    output->tx++;
    route->hits++;
    forwarded++;
    return format("FORWARD %s %s ttl=%d%s%s conn=%d %s", output->name, route->via ? format("via %s", ip(route->hop)) : "direct", ttl - 1, destination != original.destination || dport != original.dport ? format(" dnat=%s:%d", ip(destination), dport) : "", source != original.source || sport != original.sport ? format(" snat=%s:%d", ip(source), sport) : "", connection->number, direction);
}

static int interface_compare(const void *a, const void *b) {
    return strcmp((*(Interface *const *)a)->name, (*(Interface *const *)b)->name);
}

static int route_compare(const void *a, const void *b) {
    const Route *x = *(Route *const *)a, *y = *(Route *const *)b;
    if (x->prefix.address != y->prefix.address) return x->prefix.address > y->prefix.address ? 1 : -1;
    if (x->prefix.length != y->prefix.length) return x->prefix.length - y->prefix.length;
    if (x->metric != y->metric) return x->metric - y->metric;
    return (x->order > y->order) - (x->order < y->order);
}

static int static_compare(const void *a, const void *b) {
    uint32_t x = (*(StaticNat *const *)a)->inside, y = (*(StaticNat *const *)b)->inside;
    return (x > y) - (x < y);
}

static int forward_compare(const void *a, const void *b) {
    const Forward *x = *(Forward *const *)a, *y = *(Forward *const *)b;
    int c = strcmp(x->interface->name, y->interface->name);
    if (c) return c;
    if (x->port != y->port) return x->port - y->port;
    return strcmp(x->protocol, y->protocol);
}

static int pat_compare(const void *a, const void *b) {
    const Pat *x = *(Pat *const *)a, *y = *(Pat *const *)b;
    int c = strcmp(x->interface->name, y->interface->name);
    return c ? c : x->port - y->port;
}

static void *sorted(void *array, size_t count, size_t size, int (*compare)(const void *, const void *)) {
    void *copy = allocate(count * size);
    if (count) memcpy(copy, array, count * size);
    qsort(copy, count, size, compare);
    return copy;
}

static void show(const char *what) {
    Interface **ordered = sorted(interfaces, interface_count, sizeof(*interfaces), interface_compare);
    if (!strcmp(what, "IFACES")) {
        printf("show ifaces count=%zu\n", interface_count);
        for (size_t i = 0; i < interface_count; i++) {
            Interface *f = ordered[i];
            printf("%s %s %s %s rpf=%s", f->name, prefix_text(f->prefix), f->up ? "up" : "down", f->outside ? "outside" : "inside", f->rpf);
            if (f->pool) {
                size_t count = 0;
                for (size_t j = 0; j < pat_count; j++) if (pats[j]->interface == f) count++;
                printf(" pat=%zu/%d", count, f->pool);
            }
            putchar('\n');
        }
    } else if (!strcmp(what, "ROUTES")) {
        printf("show routes count=%zu\n", route_count);
        Route **ordered_routes = sorted(routes, route_count, sizeof(*routes), route_compare);
        for (size_t i = 0; i < route_count; i++) printf("%s hits=%d%s\n", route_text(ordered_routes[i]), ordered_routes[i]->hits, ordered_routes[i]->output->up ? "" : " inactive");
    } else if (!strcmp(what, "ACL")) {
        size_t count = 0;
        for (size_t i = 0; i < interface_count; i++) count += interfaces[i]->acl_count[0] + interfaces[i]->acl_count[1];
        printf("show acl count=%zu\n", count);
        for (size_t i = 0; i < interface_count; i++) for (int d = 0; d < 2; d++) {
            Interface *f = ordered[i];
            if (!f->acl_count[d]) continue;
            char *dir = d ? "out" : "in";
            for (size_t j = 0; j < f->acl_count[d]; j++) {
                Rule *r = f->acl[d][j];
                printf("acl %s %s %d %s %s %s %s %s %s%s hits=%d\n", f->name, dir, r->sequence, r->action, r->protocol, r->source.length ? prefix_text(r->source) : "any", ports_text(r->sports), r->destination.length ? prefix_text(r->destination) : "any", ports_text(r->dports), r->established ? " established" : "", r->hits);
            }
            printf("acl %s %s default DENY hits=%d\n", f->name, dir, f->defaults[d]);
        }
    } else if (!strcmp(what, "NAT")) {
        printf("show nat static=%zu forward=%zu pat=%zu\n", static_count, forward_count, pat_count);
        StaticNat **ss = sorted(statics, static_count, sizeof(*statics), static_compare);
        Forward **ff = sorted(forwards, forward_count, sizeof(*forwards), forward_compare);
        Pat **pp = sorted(pats, pat_count, sizeof(*pats), pat_compare);
        for (size_t i = 0; i < static_count; i++) printf("static %s %s\n", ip(ss[i]->inside), ip(ss[i]->outside));
        for (size_t i = 0; i < forward_count; i++) {
            Forward *f = ff[i];
            printf("forward %s %s %d %s:%d\n", f->interface->name, f->protocol, f->port, ip(f->inside), f->inport);
        }
        for (size_t i = 0; i < pat_count; i++) {
            Pat *p = pp[i];
            printf("pat %s %d %s %s:%d idle=%d\n", p->interface->name, p->port, p->protocol, ip(p->inside), p->inport, clock_time - p->last);
        }
    } else if (!strcmp(what, "CONNS")) {
        printf("show conns count=%zu\n", connection_count);
        for (size_t i = 0; i < connection_count; i++) {
            Connection *c = connections[i];
            printf("conn %d %s %s:%d > %s:%d reply %s:%d > %s:%d in=%s out=%s state=%s pkts=%d/%d idle=%d\n", c->number, c->orig.protocol, ip(c->orig.source), c->orig.sport, ip(c->orig.destination), c->orig.dport, ip(c->reply.source), c->reply.sport, ip(c->reply.destination), c->reply.dport, c->input->name, c->output->name, c->state, c->orig_packets, c->reply_packets, clock_time - c->last);
        }
    } else {
        int dropped = 0;
        for (int i = 0; i < 9; i++) dropped += drops[i];
        printf("show counters packets=%d forwarded=%d local=%d dropped=%d errors=%d\n", forwarded + local + dropped, forwarded, local, dropped, errors);
        fputs("drops", stdout);
        for (int i = 0; i < 9; i++) printf(" %s=%d", reasons[i], drops[i]);
        putchar('\n');
        for (size_t i = 0; i < interface_count; i++) printf("iface %s rx=%d tx=%d drop=%d\n", ordered[i]->name, ordered[i]->rx, ordered[i]->tx, ordered[i]->drop);
    }
}

static void execute(char **a, size_t argc) {
    if (!strcmp(a[0], "IFACE")) {
        for (size_t i = 0; i < interface_count; i++) if (!strcmp(interfaces[i]->name, a[1])) error("duplicate interface %s", a[1]);
        Prefix p;
        if (!parse_prefix(a[2], &p) || p.length < 8 || p.length > 30) error("bad prefix %s", a[2]);
        uint32_t host = p.address & ~mask(p.length);
        if (!host || host == ~mask(p.length)) error("bad host address %s", a[2]);
        for (size_t i = 0; i < interface_count; i++) {
            Prefix other = interfaces[i]->prefix;
            int k = p.length < other.length ? p.length : other.length;
            if ((p.address & mask(k)) == (other.address & mask(k))) error("subnet overlaps %s", interfaces[i]->name);
        }
        Interface *f = allocate(sizeof(*f));
        f->name = a[1];
        f->prefix = p;
        f->up = true;
        f->rpf = "off";
        APPEND(interfaces, interface_count, f);
        add_route('C', (Prefix){network(p), p.length}, f, false, 0, 0);
        printf("ok iface %s %s network %s/%d\n", a[1], a[2], ip(network(p)), p.length);
    } else if (!strcmp(a[0], "UP") || !strcmp(a[0], "DOWN")) {
        Interface *f = find_interface(a[1]);
        bool up = !strcmp(a[0], "UP");
        if (f->up == up) error("interface %s already %s", a[1], up ? "up" : "down");
        f->up = up;
        printf("ok %s %s\n", up ? "up" : "down", a[1]);
    } else if (!strcmp(a[0], "ROUTE")) {
        Prefix p = prefix(a[1], false);
        bool via = !strcmp(a[2], "VIA");
        uint32_t hop = via ? address(a[3]) : 0;
        Interface *output = via ? NULL : find_interface(a[3]);
        int metric = range(a[4], 1, 255, "bad metric");
        if (via) {
            if (local_address(hop)) error("nexthop %s is local", a[3]);
            for (size_t i = 0; i < interface_count; i++) if (contains(interfaces[i]->prefix, hop)) {
                output = interfaces[i];
                break;
            }
            if (!output) error("nexthop %s unreachable", a[3]);
        }
        for (size_t i = 0; i < route_count; i++) {
            Route *r = routes[i];
            if (r->type == 'S' && equal_prefix(r->prefix, p) && r->output == output && r->via == via && (!via || r->hop == hop)) error("duplicate route %s", a[1]);
        }
        printf("ok route %s\n", route_text(add_route('S', p, output, via, hop, metric)));
    } else if (!strcmp(a[0], "NOROUTE")) {
        Prefix p = prefix(a[1], false);
        size_t count = 0;
        for (size_t i = 0; i < route_count; i++) if (routes[i]->type == 'S' && equal_prefix(routes[i]->prefix, p)) count++;
        if (!count) error("no static route %s", a[1]);
        size_t next = 0;
        for (size_t i = 0; i < route_count; i++) if (!(routes[i]->type == 'S' && equal_prefix(routes[i]->prefix, p))) routes[next++] = routes[i];
        route_count = next;
        printf("ok noroute %s removed=%zu\n", a[1], count);
    } else if (!strcmp(a[0], "LOOKUP")) {
        Route *r = select_route(address(a[1]));
        printf("lookup %s %s\n", a[1], r ? route_text(r) : "none");
    } else if (!strcmp(a[0], "ACL")) {
        Interface *f = find_interface(a[1]);
        int d = !strcmp(a[2], "IN") ? 0 : 1;
        Rule *r = allocate(sizeof(*r));
        r->sequence = range(a[3], 1, 9999, "bad sequence");
        r->action = a[4];
        r->protocol = a[5];
        r->source = prefix(a[6], true);
        r->sports = ports(a[7]);
        r->destination = prefix(a[8], true);
        r->dports = ports(a[9]);
        if ((!strcmp(a[5], "ICMP") || !strcmp(a[5], "ANY")) && (strcmp(a[7], "ANY") || strcmp(a[9], "ANY"))) error("ports not allowed for %s", a[5]);
        for (size_t i = 0; i < f->acl_count[d]; i++) if (f->acl[d][i]->sequence == r->sequence) error("duplicate sequence %s", a[3]);
        r->established = argc == 11;
        APPEND(f->acl[d], f->acl_count[d], r);
        qsort(f->acl[d], f->acl_count[d], sizeof(*f->acl[d]), rule_compare);
        printf("ok acl %s %s %s\n", a[1], d ? "out" : "in", a[3]);
    } else if (!strcmp(a[0], "NOACL")) {
        Interface *f = find_interface(a[1]);
        int d = !strcmp(a[2], "IN") ? 0 : 1;
        size_t i;
        for (i = 0; i < f->acl_count[d]; i++) if (f->acl[d][i]->sequence == atoi(a[3])) break;
        if (i == f->acl_count[d]) error("no rule %s on %s %s", a[3], a[1], d ? "out" : "in");
        int hits = f->acl[d][i]->hits;
        memmove(f->acl[d] + i, f->acl[d] + i + 1, (f->acl_count[d] - i - 1) * sizeof(*f->acl[d]));
        f->acl_count[d]--;
        printf("ok noacl %s %s %s hits=%d\n", a[1], d ? "out" : "in", a[3], hits);
    } else if (!strcmp(a[0], "NAT")) {
        if (!strcmp(a[1], "STATIC")) {
            uint32_t inside = address(a[2]);
            uint32_t outside = address(a[3]);
            if (local_address(inside)) error("address %s is local", a[2]);
            if (local_address(outside)) error("address %s is local", a[3]);
            for (size_t i = 0; i < static_count; i++) if (statics[i]->inside == inside) error("duplicate static %s", a[2]);
            for (size_t i = 0; i < static_count; i++) if (statics[i]->outside == outside) error("duplicate static %s", a[3]);
            StaticNat *n = allocate(sizeof(*n));
            *n = (StaticNat){inside, outside};
            APPEND(statics, static_count, n);
            printf("ok nat static %s %s\n", a[2], a[3]);
        } else {
            Interface *f = find_interface(a[2]);
            if (!strcmp(a[1], "OUTSIDE")) {
                if (f->outside) error("interface %s already outside", a[2]);
                f->outside = true;
                printf("ok nat outside %s\n", a[2]);
            } else if (!strcmp(a[1], "PAT")) {
                int count = range(a[3], 1, 1000, "bad pool size");
                if (f->pool) error("pat already on %s", a[2]);
                f->pool = count;
                f->outside = true;
                printf("ok nat pat %s %s 20000-%d\n", a[2], ip(f->prefix.address), 19999 + count);
            } else {
                int port = range(a[4], 1, 65535, "bad port");
                uint32_t inside = address(a[5]);
                int inport = range(a[6], 1, 65535, "bad port");
                if (!f->outside) error("interface %s not outside", a[2]);
                if (local_address(inside)) error("address %s is local", a[5]);
                for (size_t i = 0; i < forward_count; i++) if (forwards[i]->interface == f && !strcmp(forwards[i]->protocol, a[3]) && forwards[i]->port == port) error("duplicate forward %s %s %s", a[2], a[3], a[4]);
                Forward *n = allocate(sizeof(*n));
                *n = (Forward){f, a[3], port, inside, inport};
                APPEND(forwards, forward_count, n);
                printf("ok nat forward %s %s %s %s:%s\n", a[2], a[3], a[4], a[5], a[6]);
            }
        }
    } else if (!strcmp(a[0], "RPF")) {
        Interface *f = find_interface(a[1]);
        f->rpf = !strcmp(a[2], "STRICT") ? "strict" : !strcmp(a[2], "LOOSE") ? "loose" : "off";
        printf("ok rpf %s %s\n", a[1], f->rpf);
    } else if (!strcmp(a[0], "TIMEOUT")) {
        int sec = range(a[2], 1, 86400, "bad timeout");
        timeouts[protocol_index(a[1])] = sec;
        printf("ok timeout %s %s\n", a[1], a[2]);
    } else if (!strcmp(a[0], "TICK")) {
        clock_time += range(a[1], 1, 86400, "bad tick");
        size_t old = connection_count, old_pat = pat_count, next = 0;
        for (size_t i = 0; i < connection_count; i++) {
            Connection *c = connections[i];
            int timeout = timeouts[protocol_index(c->orig.protocol)];
            if (!strcmp(c->orig.protocol, "TCP")) {
                if (!strcmp(c->state, "SYN_SENT") || !strcmp(c->state, "FIN_WAIT")) timeout = 60;
                else if (!strcmp(c->state, "CLOSED")) timeout = 10;
            }
            if (clock_time - c->last < timeout) connections[next++] = c;
        }
        connection_count = next;
        next = 0;
        for (size_t i = 0; i < pat_count; i++) if (clock_time - pats[i]->last < timeouts[protocol_index(pats[i]->protocol)]) pats[next++] = pats[i];
        pat_count = next;
        printf("ok tick time=%d expired conns=%zu nat=%zu\n", clock_time, old - connection_count, old_pat - pat_count);
    } else if (!strcmp(a[0], "PACKET")) {
        Interface *f = find_interface(a[1]);
        if (strcmp(a[2], "TCP") && strcmp(a[3], "-")) error("flags not allowed for %s", a[2]);
        if (!strcmp(a[2], "TCP") && strcmp(a[3], "-")) for (size_t i = 0; a[3][i]; i++) if (!strchr("SAFR", a[3][i]) || strchr(a[3] + i + 1, a[3][i])) error("bad flags %s", a[3]);
        uint32_t source = address(a[4]);
        int sport = range(a[5], 0, 65535, "bad port");
        uint32_t destination = address(a[6]);
        int dport = range(a[7], 0, 65535, "bad port");
        int ttl = range(a[8], 1, 255, "bad ttl");
        packet_number++;
        char *verdict = packet(f, (Tuple){a[2], source, destination, sport, dport}, a[3], ttl);
        printf("#%d %s %s %s:%s > %s:%s %s\n", packet_number, a[2], a[3], a[4], a[5], a[6], a[7], verdict);
    } else if (!strcmp(a[0], "SHOW")) show(a[1]);
    else if (!strcmp(a[1], "CONNS")) {
        printf("ok clear conns=%zu nat=%zu\n", connection_count, pat_count);
        connection_count = pat_count = 0;
    } else {
        forwarded = local = errors = 0;
        memset(drops, 0, sizeof(drops));
        for (size_t i = 0; i < interface_count; i++) {
            Interface *f = interfaces[i];
            f->rx = f->tx = f->drop = f->defaults[0] = f->defaults[1] = 0;
            for (int d = 0; d < 2; d++) for (size_t j = 0; j < f->acl_count[d]; j++) f->acl[d][j]->hits = 0;
        }
        for (size_t i = 0; i < route_count; i++) routes[i]->hits = 0;
        puts("ok clear counters");
    }
}

static char *read_line(void) {
    char *s = NULL;
    size_t n = 0;
    int c;
    while ((c = getchar()) != EOF && c != '\n') {
        s = grow(s, n + 2);
        s[n++] = (char)c;
    }
    if (c == EOF && !n) return NULL;
    s = grow(s, n + 1);
    s[n] = 0;
    return s;
}

int main(void) {
    char *first = read_line();
    int count = atoi(first);
    for (int i = 0; i < count; i++) {
        char *line = read_line(), **words = NULL;
        size_t argc = 0, start = 0;
        for (size_t j = 0;; j++) if (!line[j] || line[j] == ' ') {
            APPEND(words, argc, slice(line + start, j - start));
            start = j + 1;
            if (!line[j]) break;
        }
        if (!setjmp(failure)) execute(words, argc);
    }
    return 0;
}
