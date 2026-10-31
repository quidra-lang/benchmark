#include "bgp.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

typedef struct {
    int time, node, prefix;
    char *text;
} BestChange;
typedef struct {
    Event *event;
    const char *status;
    int convergence, updates, withdrawals, drops, best_changes, routes_changed, max_exploration,
        first, repeat;
    int exploration[50][100];
    BestChange *changes;
    size_t change_count, change_capacity;
} EventStatistics;
typedef struct {
    Node *node;
    int prefix;
    Link *link;
} Hop;
typedef enum {
    FORWARD_DELIVERED,
    FORWARD_LOOP,
    FORWARD_BLACKHOLE,
    FORWARD_UNREACHABLE
} ForwardResult;
typedef struct {
    ForwardResult result;
    int visits[51], visit_count;
    Hop hops[51];
    int hop_count, count;
} Forwarding;
typedef struct {
    int trace, start, end;
    ForwardResult result;
    int visits[51], visit_count;
} TraceRecord;
typedef struct {
    int prefix, start, end, path[50], count;
} RingRecord;
typedef struct {
    int path[50], count;
} Cycle;
typedef struct {
    Cycle items[50];
    int count;
} Cycles;
typedef struct {
    char *state;
    uint64_t hash;
    int time;
} SeenState;
typedef struct {
    SeenState *items;
    size_t capacity;
} SeenStates;
typedef struct {
    Topology topology;
    Policies policies;
    Parameters parameters;
    Event events[51];
    int event_count;
    MessageQueue messages;
    int time, end;
    Lines updates;
    EventStatistics statistics[51], *current;
    bool changed[100];
    TraceRecord *traces;
    size_t trace_count, trace_capacity;
    int ongoing_traces[20];
    RingRecord *rings;
    size_t ring_count, ring_capacity;
} Simulator;
static const char *forward_name(ForwardResult result) {
    static const char *names[] = {"DELIVERED", "LOOP", "BLACKHOLE", "UNREACHABLE"};
    return names[result];
}
static void log_line(Simulator *s, char *body) {
    lines_add(&s->updates, format_text("%d %s", s->time, body));
    free(body);
}
static bool path_has(const Attribute *a, int number) {
    for (size_t i = 0; i < a->path_count; ++i)
        if (a->path[i] == number)
            return true;
    return false;
}
static Route import_route(Simulator *s, Session *session, int prefix, const Attribute *a,
                          Rule **applied_rule) {
    Rule *r = applied(&s->policies, true, session, s->topology.prefixes[prefix], a);
    if (applied_rule)
        *applied_rule = r;
    if (r && r->deny)
        return (Route){0};
    int relationship = role(session->link, session->owner);
    Route result = {.attribute = attribute_copy(a),
                    .link = session->link,
                    .preference = relationship == 0   ? s->parameters.customer
                                  : relationship == 1 ? s->parameters.peer
                                                      : s->parameters.provider};
    if (r) {
        if (r->has_preference)
            result.preference = r->preference;
        if (r->has_med)
            result.attribute->med = r->med;
        edit_communities(&result.attribute->communities, r);
    }
    return result;
}
static int candidates(Simulator *s, Node *node, int prefix, Route result[100]) {
    int count = 0;
    for (int i = 0; i < node->session_count; ++i) {
        Session *session = node->sessions[i];
        if (!session->incoming[prefix])
            continue;
        Route route = import_route(s, session, prefix, session->incoming[prefix], NULL);
        if (route.attribute)
            result[count++] = route;
    }
    return count;
}
static void process_pending(Simulator *, Session *);
static void redecide(Simulator *s, Node *node, int prefix) {
    Route route = {0};
    if (node->origins[prefix]) {
        route.attribute = attribute_retain(node->origins[prefix]);
        route.local = true;
    } else {
        Route choices[100];
        int count = candidates(s, node, prefix, choices);
        if (count) {
            const char *reason;
            int best = best_route(choices, count, &s->topology, &reason);
            route = route_retain(choices[best]);
        }
        for (int i = 0; i < count; ++i)
            route_release(&choices[i]);
    }
    if (route_equal(route, node->rib[prefix])) {
        route_release(&route);
        return;
    }
    route_release(&node->rib[prefix]);
    node->rib[prefix] = route;
    char *text = route_text(route), *notation = prefix_text(s->topology.prefixes[prefix]);
    log_line(s, format_text("BEST %d %s %s", node->number, notation, text));
    free(notation);
    ++node->changes;
    EventStatistics *stats = s->current;
    ++stats->best_changes;
    int count = ++stats->exploration[node->index][prefix];
    if (count > stats->max_exploration)
        stats->max_exploration = count;
    if (stats->change_count == stats->change_capacity) {
        stats->change_capacity = stats->change_capacity ? stats->change_capacity * 2 : 64;
        stats->changes = resize(stats->changes, stats->change_capacity * sizeof(BestChange));
    }
    stats->changes[stats->change_count++] = (BestChange){s->time, node->number, prefix, text};
    s->changed[prefix] = true;
    for (int i = 0; i < node->session_count; ++i) {
        Session *session = node->sessions[i];
        if (session->link->up) {
            session->pending[prefix] = true;
            if (session->timer < 0)
                process_pending(s, session);
        }
    }
}
static Attribute *advertised(Simulator *s, Session *session, int prefix, Rule **applied_rule) {
    *applied_rule = NULL;
    Route route = session->owner->rib[prefix];
    if (!route.attribute)
        return NULL;
    Attribute *a = route.attribute;
    if (!route.local && a->path[0] == other(session->link, session->owner)->number)
        return NULL;
    if (community_has(&a->communities, NO_EXPORT))
        return NULL;
    Rule *r = applied(&s->policies, false, session, s->topology.prefixes[prefix], a);
    *applied_rule = r;
    if (r && r->deny)
        return NULL;
    if (!(r && r->allow) && !route.local && role(route.link, session->owner) != 0 &&
        role(session->link, session->owner) != 0)
        return NULL;
    Attribute *result = attribute_new();
    size_t prepend = (size_t)(1 + (r ? r->prepend : 0));
    result->path_count = prepend + a->path_count;
    result->path = allocate(result->path_count * sizeof(int));
    for (size_t i = 0; i < prepend; ++i)
        result->path[i] = session->owner->number;
    if (a->path_count)
        memcpy(result->path + prepend, a->path, a->path_count * sizeof(int));
    result->origin = a->origin;
    result->med = r && r->has_med ? r->med : 0;
    result->communities = communities_copy(&a->communities);
    if (r)
        edit_communities(&result->communities, r);
    return result;
}
static void process_pending(Simulator *s, Session *session) {
    int sent = 0;
    for (int i = 0; i < s->topology.prefix_count; ++i) {
        int prefix = s->topology.prefix_order[i];
        if (!session->pending[prefix])
            continue;
        Rule *rule;
        Attribute *a = advertised(s, session, prefix, &rule);
        if (attribute_equal(a, session->outgoing[prefix])) {
            attribute_release(a);
            continue;
        }
        attribute_release(session->outgoing[prefix]);
        session->outgoing[prefix] = attribute_retain(a);
        Message message = queue_send(&s->messages, s->time, session, prefix, a);
        ++sent;
        ++session->sent;
        ++s->current->updates;
        char *notation = prefix_text(s->topology.prefixes[prefix]);
        char *base =
            format_text("SEND #%d %d->%d %s %s", message.serial, message_sender(&message)->number,
                        message_receiver(&message)->number, session->link->name, notation);
        free(notation);
        if (a) {
            char *text = attribute_text(a);
            log_line(s, format_text("%s ANNOUNCE %s", base, text));
            free(text);
        } else {
            ++s->current->withdrawals;
            log_line(s, format_text("%s WITHDRAW", base));
        }
        free(base);
        if (rule)
            ++rule->hits;
        attribute_release(a);
    }
    memset(session->pending, 0, sizeof(session->pending));
    session->timer = sent && session->link->mrai > 0 ? s->time + session->link->mrai : -1;
}
static void receive_message(Simulator *s, const Message *m) {
    Node *receiver = message_receiver(m);
    Session *session = session_at(m->source->link, receiver);
    Attribute *a = m->attribute;
    ++session->received;
    char *result;
    if (!a) {
        attribute_release(session->incoming[m->prefix]);
        session->incoming[m->prefix] = NULL;
        result = copy_text("WITHDRAW");
    } else if (path_has(a, receiver->number)) {
        attribute_release(session->incoming[m->prefix]);
        session->incoming[m->prefix] = NULL;
        result = copy_text("ANNOUNCE loop");
    } else {
        attribute_release(session->incoming[m->prefix]);
        session->incoming[m->prefix] = attribute_retain(a);
        Rule *rule;
        Route route = import_route(s, session, m->prefix, a, &rule);
        if (rule) {
            ++rule->hits;
            result = format_text("ANNOUNCE %s %s", route.attribute ? "accept" : "deny", rule->name);
        } else
            result = copy_text("ANNOUNCE accept");
        route_release(&route);
    }
    char *notation = prefix_text(s->topology.prefixes[m->prefix]);
    log_line(s, format_text("RECV #%d %d->%d %s %s %s", m->serial, message_sender(m)->number,
                            receiver->number, m->source->link->name, notation, result));
    free(notation);
    free(result);
    redecide(s, receiver, m->prefix);
}
static bool has_pending(const Session *session, int count) {
    for (int i = 0; i < count; ++i)
        if (session->pending[i])
            return true;
    return false;
}
static void execute_event(Simulator *s, Event *event) {
    log_line(s, format_text("EVENT %d %s", event->number, event->text));
    Topology *t = &s->topology;
    if (event->kind == EVENT_INITIAL) {
        for (int i = 0; i < t->initial_count; ++i) {
            Initial initial = t->initial[i];
            attribute_release(initial.node->origins[initial.prefix]);
            initial.node->origins[initial.prefix] = attribute_retain(initial.attribute);
            redecide(s, initial.node, initial.prefix);
        }
    } else if (event->kind == EVENT_ANNOUNCE || event->kind == EVENT_WITHDRAW) {
        attribute_release(event->node->origins[event->prefix]);
        event->node->origins[event->prefix] = attribute_retain(event->attribute);
        redecide(s, event->node, event->prefix);
    } else if (event->kind == EVENT_LINK_DOWN || event->kind == EVENT_LINK_UP) {
        Link *link = event->link;
        Node *endpoints[2] = {link->a, link->b};
        if (endpoints[0]->number > endpoints[1]->number) {
            Node *temporary = endpoints[0];
            endpoints[0] = endpoints[1];
            endpoints[1] = temporary;
        }
        link->up = event->kind == EVENT_LINK_UP;
        if (!link->up) {
            ++link->downs;
            MessageList removed = queue_remove(&s->messages, link);
            for (size_t i = 0; i < removed.count; ++i) {
                Message *m = &removed.items[i];
                ++s->current->drops;
                char *notation = prefix_text(t->prefixes[m->prefix]);
                log_line(s,
                         format_text("DROP #%d %d->%d %s %s", m->serial, message_sender(m)->number,
                                     message_receiver(m)->number, link->name, notation));
                free(notation);
                attribute_release(m->attribute);
            }
            free(removed.items);
            bool remembered[2][100] = {{0}};
            for (int i = 0; i < 2; ++i) {
                Session *session = session_at(link, endpoints[i]);
                for (int p = 0; p < t->prefix_count; ++p) {
                    remembered[i][p] = session->incoming[p] != NULL;
                    attribute_release(session->incoming[p]);
                    attribute_release(session->outgoing[p]);
                    session->incoming[p] = session->outgoing[p] = NULL;
                    session->pending[p] = false;
                }
                session->timer = -1;
            }
            for (int i = 0; i < 2; ++i)
                for (int j = 0; j < t->prefix_count; ++j) {
                    int p = t->prefix_order[j];
                    if (remembered[i][p])
                        redecide(s, endpoints[i], p);
                }
        } else
            for (int i = 0; i < 2; ++i) {
                Session *session = session_at(link, endpoints[i]);
                for (int p = 0; p < t->prefix_count; ++p)
                    session->pending[p] = endpoints[i]->rib[p].attribute != NULL;
                process_pending(s, session);
            }
    } else {
        Rule *rule = event->rule;
        rule->active = event->kind == EVENT_POLICY_ON;
        Node *node = node_named(t, rule->owner);
        if (rule->importing) {
            bool prefixes[100] = {0};
            for (int i = 0; i < node->session_count; ++i)
                for (int p = 0; p < t->prefix_count; ++p)
                    prefixes[p] = prefixes[p] || node->sessions[i]->incoming[p] != NULL;
            for (int i = 0; i < t->prefix_count; ++i) {
                int p = t->prefix_order[i];
                if (prefixes[p])
                    redecide(s, node, p);
            }
        } else
            for (int i = 0; i < node->session_count; ++i) {
                Session *session = node->sessions[i];
                if (!session->link->up)
                    continue;
                for (int p = 0; p < t->prefix_count; ++p)
                    if (node->rib[p].attribute || session->outgoing[p])
                        session->pending[p] = true;
                if (session->timer < 0)
                    process_pending(s, session);
            }
    }
}
static bool quiet(const Simulator *s) {
    if (s->messages.count)
        return false;
    for (int i = 0; i < s->topology.session_count; ++i)
        if (has_pending(s->topology.sessions[i], s->topology.prefix_count))
            return false;
    return true;
}
static void state_table(Text *text, const Topology *t, const char *tag,
                        Attribute *const table[100]) {
    text_format(text, "%s{", tag);
    for (int i = 0; i < t->prefix_count; ++i) {
        int p = t->prefix_order[i];
        if (!table[p])
            continue;
        char *notation = prefix_text(t->prefixes[p]), *attribute = attribute_text(table[p]);
        text_format(text, "%s=%s;", notation, attribute);
        free(notation);
        free(attribute);
    }
    text_add(text, "}");
}
static char *global_state(const Simulator *s) {
    Text text = {0};
    const Topology *t = &s->topology;
    for (int i = 0; i < t->session_count; ++i) {
        const Session *session = t->sessions[i];
        text_format(&text, "S%d:%d", session->owner->number, session->link->number);
        state_table(&text, t, "I", session->incoming);
        state_table(&text, t, "O", session->outgoing);
        text_add(&text, "P{");
        for (int j = 0; j < t->prefix_count; ++j) {
            int p = t->prefix_order[j];
            if (session->pending[p]) {
                char *notation = prefix_text(t->prefixes[p]);
                text_format(&text, "%s;", notation);
                free(notation);
            }
        }
        text_format(&text, "}T%d;", session->timer < 0 ? -1 : session->timer - s->time);
    }
    text_add(&text, "Q{");
    MessageList messages = queue_ordered(&s->messages);
    for (size_t i = 0; i < messages.count; ++i) {
        const Message *m = &messages.items[i];
        char *notation = prefix_text(t->prefixes[m->prefix]);
        text_format(&text, "%d:%d:%d:%d:%s:", m->time - s->time, message_receiver(m)->number,
                    message_sender(m)->number, m->source->link->number, notation);
        free(notation);
        if (m->attribute) {
            char *attribute = attribute_text(m->attribute);
            text_format(&text, "A%s;", attribute);
            free(attribute);
        } else
            text_add(&text, "W;");
    }
    free(messages.items);
    text_add(&text, "}");
    return text_take(&text);
}
static int state_seen(SeenStates *seen, char *state, int time) {
    uint64_t hash = UINT64_C(14695981039346656037);
    for (const unsigned char *p = (const unsigned char *)state; *p; ++p) {
        hash ^= *p;
        hash *= UINT64_C(1099511628211);
    }
    size_t index = (size_t)hash & (seen->capacity - 1);
    while (seen->items[index].state) {
        SeenState *old = &seen->items[index];
        if (old->hash == hash && strcmp(old->state, state) == 0) {
            free(state);
            return old->time;
        }
        index = (index + 1) & (seen->capacity - 1);
    }
    seen->items[index] = (SeenState){state, hash, time};
    return -1;
}
static Forwarding forward(const Simulator *s, Node *source, uint64_t address) {
    Forwarding result = {.visits = {source->number}, .visit_count = 1};
    uint64_t visited = UINT64_C(1) << source->index;
    Node *node = source;
    for (;;) {
        Route *route = NULL;
        int prefix = -1;
        for (int p = 0; p < s->topology.prefix_count; ++p)
            if (node->rib[p].attribute && contains(s->topology.prefixes[p], address) &&
                (!route || s->topology.prefixes[p].length > s->topology.prefixes[prefix].length)) {
                route = &node->rib[p];
                prefix = p;
            }
        if (!route) {
            result.result = result.hop_count ? FORWARD_BLACKHOLE : FORWARD_UNREACHABLE;
            return result;
        }
        if (route->local) {
            result.hops[result.hop_count++] = (Hop){node, prefix, NULL};
            result.result = FORWARD_DELIVERED;
            return result;
        }
        result.hops[result.hop_count++] = (Hop){node, prefix, route->link};
        ++result.count;
        node = other(route->link, node);
        result.visits[result.visit_count++] = node->number;
        uint64_t bit = UINT64_C(1) << node->index;
        if (visited & bit) {
            result.result = FORWARD_LOOP;
            return result;
        }
        visited |= bit;
    }
}
static int merge_path(const int *path, size_t count, int *out) {
    int size = 0;
    for (size_t i = 0; i < count; ++i)
        if (!size || out[size - 1] != path[i])
            out[size++] = path[i];
    return size;
}
static int valley_position(const char *pattern) {
    int i = 0;
    while (pattern[i] == 'U')
        ++i;
    if (pattern[i] == 'P')
        ++i;
    while (pattern[i] == 'D')
        ++i;
    return i;
}
static char *pattern(Simulator *s, const int *path, int count) {
    char *result = allocate((size_t)count + 1);
    int size = 0;
    for (int i = 0; i + 1 < count; ++i)
        result[size++] = direction_symbol(
            role(between(&s->topology, path[i], path[i + 1]), node_named(&s->topology, path[i])));
    result[size] = 0;
    return result;
}
static Cycles loops(Simulator *s, int prefix) {
    Cycles result = {0};
    uint64_t done = 0;
    for (int i = 0; i < s->topology.node_count; ++i) {
        Node *node = &s->topology.nodes[s->topology.node_order[i]];
        if (done & (UINT64_C(1) << node->index))
            continue;
        int positions[50], path[50], count = 0;
        for (int j = 0; j < 50; ++j)
            positions[j] = -1;
        for (;;) {
            if (done & (UINT64_C(1) << node->index))
                break;
            if (positions[node->index] >= 0) {
                int start = positions[node->index], length = count - start, first = 0;
                for (int j = 1; j < length; ++j)
                    if (path[start + j] < path[start + first])
                        first = j;
                Cycle *cycle = &result.items[result.count++];
                cycle->count = length;
                for (int j = 0; j < length; ++j)
                    cycle->path[j] = path[start + (first + j) % length];
                break;
            }
            positions[node->index] = count;
            path[count++] = node->number;
            Route route = node->rib[prefix];
            if (!route.attribute || route.local)
                break;
            node = other(route.link, node);
        }
        for (int j = 0; j < count; ++j)
            done |= UINT64_C(1) << node_named(&s->topology, path[j])->index;
    }
    for (int i = 1; i < result.count; ++i) {
        Cycle cycle = result.items[i];
        int j = i;
        while (j > 0 && result.items[j - 1].path[0] > cycle.path[0]) {
            result.items[j] = result.items[j - 1];
            --j;
        }
        result.items[j] = cycle;
    }
    return result;
}
static bool equal_path(const int *a, int ac, const int *b, int bc) {
    return ac == bc && (!ac || memcmp(a, b, (size_t)ac * sizeof(int)) == 0);
}
static void forwarding_check(Simulator *s) {
    for (int i = 0; i < s->topology.prefix_count; ++i) {
        int prefix = s->topology.prefix_order[i];
        if (!s->changed[prefix])
            continue;
        Cycles found = loops(s, prefix);
        for (size_t j = 0; j < s->ring_count; ++j) {
            RingRecord *r = &s->rings[j];
            if (r->prefix != prefix || r->end >= 0)
                continue;
            bool exists = false;
            for (int k = 0; k < found.count; ++k)
                if (equal_path(r->path, r->count, found.items[k].path, found.items[k].count))
                    exists = true;
            if (!exists)
                r->end = s->time;
        }
        for (int j = 0; j < found.count; ++j) {
            Cycle cycle = found.items[j];
            bool exists = false;
            for (size_t k = 0; k < s->ring_count; ++k) {
                RingRecord *r = &s->rings[k];
                if (r->prefix == prefix && r->end < 0 &&
                    equal_path(r->path, r->count, cycle.path, cycle.count))
                    exists = true;
            }
            if (!exists) {
                if (s->ring_count == s->ring_capacity) {
                    s->ring_capacity = s->ring_capacity ? 2 * s->ring_capacity : 32;
                    s->rings = resize(s->rings, s->ring_capacity * sizeof(RingRecord));
                }
                RingRecord *r = &s->rings[s->ring_count++];
                *r = (RingRecord){
                    .prefix = prefix, .start = s->time, .end = -1, .count = cycle.count};
                memcpy(r->path, cycle.path, (size_t)cycle.count * sizeof(int));
            }
        }
    }
    for (int i = 0; i < s->parameters.trace_count; ++i) {
        Trace trace = s->parameters.traces[i];
        Forwarding path = forward(s, trace.source, trace.address);
        bool status = path.result == FORWARD_LOOP || path.result == FORWARD_BLACKHOLE;
        int index = s->ongoing_traces[i];
        if (index >= 0) {
            TraceRecord *r = &s->traces[index];
            if (!status || r->result != path.result ||
                !equal_path(r->visits, r->visit_count, path.visits, path.visit_count)) {
                r->end = s->time;
                s->ongoing_traces[i] = -1;
            }
        }
        if (status && s->ongoing_traces[i] < 0) {
            if (s->trace_count == s->trace_capacity) {
                s->trace_capacity = s->trace_capacity ? 2 * s->trace_capacity : 32;
                s->traces = resize(s->traces, s->trace_capacity * sizeof(TraceRecord));
            }
            s->ongoing_traces[i] = (int)s->trace_count;
            TraceRecord *r = &s->traces[s->trace_count++];
            *r = (TraceRecord){.trace = i,
                               .start = s->time,
                               .end = -1,
                               .result = path.result,
                               .visit_count = path.visit_count};
            memcpy(r->visits, path.visits, (size_t)path.visit_count * sizeof(int));
        }
    }
}
static Lines convergence_lines(const Simulator *s) {
    Lines result = {0};
    lines_add(
        &result,
        copy_text(
            "event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration"));
    for (int i = 0; i < s->event_count; ++i) {
        const EventStatistics *r = &s->statistics[i];
        lines_add(&result, format_text("%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%d", r->event->number,
                                       r->event->time, event_kind_name(r->event->kind), r->status,
                                       r->convergence, r->updates, r->withdrawals, r->drops,
                                       r->best_changes, r->routes_changed, r->max_exploration));
    }
    return result;
}
static Lines rib_lines(Simulator *s) {
    Lines result = {0};
    Topology *t = &s->topology;
    for (int i = 0; i < t->node_count; ++i) {
        Node *node = &t->nodes[t->node_order[i]];
        int sent = 0, received = 0, local = 0, routes = 0;
        for (int j = 0; j < node->session_count; ++j) {
            sent += node->sessions[j]->sent;
            received += node->sessions[j]->received;
        }
        for (int p = 0; p < t->prefix_count; ++p)
            if (node->rib[p].attribute) {
                ++routes;
                if (node->rib[p].local)
                    ++local;
            }
        lines_add(&result, format_text("AS %d routes %d local %d sent %d received %d changes %d",
                                       node->number, routes, local, sent, received, node->changes));
        for (int j = 0; j < node->session_count; ++j) {
            Session *session = node->sessions[j];
            int incoming = 0, accepted = 0, outgoing = 0;
            for (int p = 0; p < t->prefix_count; ++p) {
                if (session->incoming[p]) {
                    ++incoming;
                    Route route = import_route(s, session, p, session->incoming[p], NULL);
                    if (route.attribute)
                        ++accepted;
                    route_release(&route);
                }
                if (session->outgoing[p])
                    ++outgoing;
            }
            lines_add(
                &result,
                format_text(
                    "SESSION %s %d %s %s in %d accepted %d out %d sent %d received %d flaps %d",
                    session->link->name, other(session->link, node)->number,
                    role_name(role(session->link, node)), session->link->up ? "UP" : "DOWN",
                    incoming, accepted, outgoing, session->sent, session->received,
                    session->link->downs));
        }
        for (int j = 0; j < t->prefix_count; ++j) {
            int p = t->prefix_order[j];
            Route route = node->rib[p];
            if (!route.attribute)
                continue;
            Route choices[100];
            int count = candidates(s, node, p, choices);
            char *notation = prefix_text(t->prefixes[p]), *text = route_text(route);
            if (route.local)
                lines_add(&result, format_text("%s %s candidates %d", notation, text, count));
            else {
                const char *reason;
                best_route(choices, count, t, &reason);
                lines_add(&result, format_text("%s %s candidates %d reason %s", notation, text,
                                               count, reason));
            }
            free(notation);
            free(text);
            int remaining = 0;
            for (int k = 0; k < count; ++k) {
                if (route_equal(choices[k], route))
                    route_release(&choices[k]);
                else
                    choices[remaining++] = choices[k];
            }
            count = remaining;
            while (count) {
                const char *reason;
                int best = best_route(choices, count, t, &reason);
                text = route_text(choices[best]);
                lines_add(&result, format_text("ALT %s", text));
                free(text);
                route_release(&choices[best]);
                memmove(choices + best, choices + best + 1,
                        (size_t)(count - best - 1) * sizeof(Route));
                --count;
            }
        }
    }
    return result;
}
static Lines path_lines(Simulator *s) {
    Lines result = {0};
    Topology *t = &s->topology;
    for (int i = 0; i < s->parameters.trace_count; ++i) {
        Trace trace = s->parameters.traces[i];
        Forwarding path = forward(s, trace.source, trace.address);
        char directions[51];
        int direction_count = 0;
        lines_add(&result, format_text("TRACE %d %s %s hops %d", trace.source->number, trace.text,
                                       forward_name(path.result), path.count));
        for (int j = 0; j < path.hop_count; ++j) {
            Hop hop = path.hops[j];
            char *notation = prefix_text(t->prefixes[hop.prefix]);
            if (!hop.link)
                lines_add(&result, format_text("HOP %d %s LOCAL", hop.node->number, notation));
            else {
                lines_add(&result,
                          format_text("HOP %d %s next %d link %s", hop.node->number, notation,
                                      other(hop.link, hop.node)->number, hop.link->name));
                directions[direction_count++] = direction_symbol(role(hop.link, hop.node));
            }
            free(notation);
        }
        directions[direction_count] = 0;
        int last = path.visits[path.visit_count - 1];
        if (path.result == FORWARD_LOOP)
            lines_add(&result, format_text("HOP %d REVISIT", last));
        else if (path.result == FORWARD_BLACKHOLE || path.result == FORWARD_UNREACHABLE)
            lines_add(&result, format_text("HOP %d NOROUTE", last));
        if (!path.hop_count)
            lines_add(&result, copy_text("CONTROL NONE"));
        else {
            Route route = trace.source->rib[path.hops[0].prefix];
            int *merged = allocate((route.attribute->path_count + 1) * sizeof(int));
            int count = merge_path(route.attribute->path, route.attribute->path_count, merged);
            bool match = path.result == FORWARD_DELIVERED &&
                         equal_path(merged, count, path.visits + 1, path.visit_count - 1);
            char *notation = route.local
                                 ? copy_text("LOCAL")
                                 : path_text(route.attribute->path, route.attribute->path_count);
            lines_add(&result,
                      format_text("CONTROL %s %s", notation, match ? "MATCH" : "MISMATCH"));
            free(notation);
            free(merged);
        }
        if (path.count)
            lines_add(&result,
                      format_text("PATTERN %s %s", directions,
                                  valley_position(directions) == direction_count ? "VALLEYFREE"
                                                                                 : "VALLEY"));
    }
    bool originated[100] = {0};
    for (int i = 0; i < t->node_count; ++i)
        for (int p = 0; p < t->prefix_count; ++p)
            originated[p] = originated[p] || t->nodes[i].origins[p] != NULL;
    Text prefixes = {0};
    text_add(&prefixes, "PREFIXES");
    bool first = true;
    for (int i = 0; i < t->prefix_count; ++i) {
        int p = t->prefix_order[i];
        if (!originated[p])
            continue;
        char *notation = prefix_text(t->prefixes[p]);
        text_format(&prefixes, "%s%s", first ? " " : ",", notation);
        first = false;
        free(notation);
    }
    lines_add(&result, text_take(&prefixes));
    for (int i = 0; i < t->node_count; ++i) {
        Node *node = &t->nodes[t->node_order[i]];
        char symbols[101];
        int count = 0;
        for (int j = 0; j < t->prefix_count; ++j) {
            int p = t->prefix_order[j];
            if (!originated[p])
                continue;
            Forwarding path = forward(s, node, t->prefixes[p].address);
            char symbol = 'U';
            if (path.result == FORWARD_LOOP)
                symbol = 'L';
            else if (path.result == FORWARD_BLACKHOLE)
                symbol = 'B';
            else if (path.result == FORWARD_DELIVERED)
                symbol = path.count == 0                                  ? '*'
                         : path.hops[path.hop_count - 1].node->origins[p] ? '+'
                                                                          : 'X';
            symbols[count++] = symbol;
        }
        symbols[count] = 0;
        lines_add(&result, format_text("REACH %d%s%s", node->number, count ? " " : "", symbols));
    }
    return result;
}
static char *end_text(int value) { return value < 0 ? copy_text("END") : format_text("%d", value); }
static Lines audit_lines(Simulator *s) {
    Lines result = {0};
    int loops_count = 0, blackholes = 0, valleys = 0, learned = 0, divergent = 0;
    Topology *t = &s->topology;
    for (size_t i = 0; i < s->trace_count; ++i) {
        TraceRecord *r = &s->traces[i];
        Trace trace = s->parameters.traces[r->trace];
        char *end = end_text(r->end), *path = path_text(r->visits, (size_t)r->visit_count);
        if (r->result == FORWARD_BLACKHOLE) {
            ++blackholes;
            lines_add(&result, format_text("BLACKHOLE %d %s from %d to %s at %d path %s",
                                           trace.source->number, trace.text, r->start, end,
                                           r->visits[r->visit_count - 1], path));
        } else {
            ++loops_count;
            lines_add(&result, format_text("LOOP %d %s from %d to %s path %s", trace.source->number,
                                           trace.text, r->start, end, path));
        }
        free(end);
        free(path);
    }
    for (size_t i = 0; i < s->ring_count; ++i) {
        RingRecord *r = &s->rings[i];
        char *notation = prefix_text(t->prefixes[r->prefix]), *end = end_text(r->end),
             *path = path_text(r->path, (size_t)r->count);
        lines_add(&result,
                  format_text("RING %s from %d to %s path %s", notation, r->start, end, path));
        free(notation);
        free(end);
        free(path);
    }
    for (int i = 0; i < t->node_count; ++i) {
        Node *node = &t->nodes[t->node_order[i]];
        for (int j = 0; j < t->prefix_count; ++j) {
            int p = t->prefix_order[j];
            Route route = node->rib[p];
            if (!route.attribute || route.local)
                continue;
            ++learned;
            Attribute *a = route.attribute;
            int *full = allocate((a->path_count + 1) * sizeof(int)),
                *merged = allocate((a->path_count + 1) * sizeof(int));
            full[0] = node->number;
            if (a->path_count)
                memcpy(full + 1, a->path, a->path_count * sizeof(int));
            int count = merge_path(full, a->path_count + 1, merged);
            char *directions = pattern(s, merged, count);
            int position = valley_position(directions);
            if (position < (int)strlen(directions)) {
                ++valleys;
                char *notation = prefix_text(t->prefixes[p]),
                     *path = path_text(a->path, a->path_count);
                lines_add(&result,
                          format_text("VALLEY %d %s path %s pattern %s leaker %d", node->number,
                                      notation, path, directions, merged[position]));
                free(notation);
                free(path);
            }
            free(directions);
            free(full);
            free(merged);
        }
    }
    for (int i = 0; i < s->policies.rule_count; ++i) {
        Rule *r = &s->policies.rules[i];
        lines_add(&result,
                  format_text("RULE %s %s %s hits %d", r->name, r->importing ? "IMPORT" : "EXPORT",
                              r->active ? "ON" : "OFF", r->hits));
    }
    for (int i = 0; i < s->event_count; ++i) {
        EventStatistics *r = &s->statistics[i];
        if (r->first < 0)
            continue;
        ++divergent;
        lines_add(&result,
                  format_text("DIVERGENT event %d first %d repeat %d period %d", r->event->number,
                              r->first, r->repeat, r->repeat - r->first));
        int counts[50][100] = {{0}};
        for (size_t j = 0; j < r->change_count; ++j) {
            BestChange change = r->changes[j];
            if (change.time <= r->first || change.time > r->repeat)
                continue;
            char *notation = prefix_text(t->prefixes[change.prefix]);
            lines_add(&result, format_text("CYCLE %d %d %s %s", change.time, change.node, notation,
                                           change.text));
            free(notation);
            ++counts[node_named(t, change.node)->index][change.prefix];
        }
        for (int n = 0; n < t->node_count; ++n) {
            Node *node = &t->nodes[t->node_order[n]];
            for (int j = 0; j < t->prefix_count; ++j) {
                int p = t->prefix_order[j];
                if (counts[node->index][p]) {
                    char *notation = prefix_text(t->prefixes[p]);
                    lines_add(&result, format_text("OSCILLATE %d %s changes %d", node->number,
                                                   notation, counts[node->index][p]));
                    free(notation);
                }
            }
        }
    }
    lines_add(
        &result,
        format_text(
            "SUMMARY loops %d blackholes %d rings %zu routes %d valleys %d divergent %d end %d",
            loops_count, blackholes, s->ring_count, learned, valleys, divergent, s->end));
    return result;
}
static void run(Simulator *s) {
    for (int i = 0; i < 20; ++i)
        s->ongoing_traces[i] = -1;
    for (int k = 0; k < s->event_count; ++k) {
        Event *event = &s->events[k];
        EventStatistics *stats = &s->statistics[k];
        stats->event = event;
        stats->first = stats->repeat = -1;
        s->current = stats;
        Route(*before)[100] = allocate(50 * 100 * sizeof(Route));
        memset(before, 0, 50 * 100 * sizeof(Route));
        for (int i = 0; i < s->topology.node_count; ++i)
            for (int p = 0; p < s->topology.prefix_count; ++p)
                before[i][p] = route_retain(s->topology.nodes[i].rib[p]);
        SeenStates seen = {.capacity = 1};
        while (seen.capacity < (size_t)(2 * s->parameters.stepcap))
            seen.capacity *= 2;
        seen.items = allocate(seen.capacity * sizeof(SeenState));
        memset(seen.items, 0, seen.capacity * sizeof(SeenState));
        int deliveries = 0;
        s->time = event->time;
        memset(s->changed, 0, sizeof(s->changed));
        execute_event(s, event);
        for (int time = event->time;; ++time) {
            s->time = time;
            if (time > event->time)
                memset(s->changed, 0, sizeof(s->changed));
            MessageList arrived = queue_arrivals(&s->messages, time);
            for (size_t i = 0; i < arrived.count; ++i) {
                receive_message(s, &arrived.items[i]);
                attribute_release(arrived.items[i].attribute);
            }
            if (arrived.count)
                stats->convergence = time - event->time;
            for (int i = 0; i < s->topology.session_count; ++i) {
                Session *session = s->topology.sessions[i];
                if (session->timer == time) {
                    session->timer = -1;
                    if (has_pending(session, s->topology.prefix_count))
                        process_pending(s, session);
                }
            }
            bool changed = false;
            for (int p = 0; p < s->topology.prefix_count; ++p)
                changed = changed || s->changed[p];
            if (changed)
                forwarding_check(s);
            if (arrived.count) {
                ++deliveries;
                if (stats->first < 0 && deliveries <= s->parameters.stepcap) {
                    int first = state_seen(&seen, global_state(s), time);
                    if (first >= 0) {
                        stats->first = first;
                        stats->repeat = time;
                    }
                }
            }
            free(arrived.items);
            bool last = k + 1 == s->event_count;
            bool stop = last
                            ? (quiet(s) || stats->first >= 0 || deliveries >= s->parameters.stepcap)
                            : time == s->events[k + 1].time - 1;
            if (stop) {
                s->end = time;
                break;
            }
        }
        stats->status = stats->first >= 0         ? "DIVERGENT"
                        : quiet(s)                ? "CONVERGED"
                        : k + 1 == s->event_count ? "CAPPED"
                                                  : "UNSETTLED";
        for (int i = 0; i < s->topology.node_count; ++i)
            for (int p = 0; p < s->topology.prefix_count; ++p) {
                if (!route_equal(before[i][p], s->topology.nodes[i].rib[p]))
                    ++stats->routes_changed;
                route_release(&before[i][p]);
            }
        free(before);
        for (size_t i = 0; i < seen.capacity; ++i)
            free(seen.items[i].state);
        free(seen.items);
    }
}
static void save_report(const char *name, Lines lines) {
    write_lines(name, &lines);
    lines_free(&lines);
}
static void cleanup(Simulator *s) {
    Topology *t = &s->topology;
    for (int i = 0; i < t->node_count; ++i)
        for (int p = 0; p < t->prefix_count; ++p) {
            attribute_release(t->nodes[i].origins[p]);
            route_release(&t->nodes[i].rib[p]);
        }
    for (int i = 0; i < t->session_count; ++i)
        for (int p = 0; p < t->prefix_count; ++p) {
            attribute_release(t->sessions[i]->incoming[p]);
            attribute_release(t->sessions[i]->outgoing[p]);
        }
    for (int i = 0; i < t->initial_count; ++i)
        attribute_release(t->initial[i].attribute);
    for (size_t i = 0; i < s->messages.count; ++i)
        attribute_release(s->messages.items[i].attribute);
    free(s->messages.items);
    for (int i = 0; i < s->event_count; ++i) {
        attribute_release(s->events[i].attribute);
        free(s->events[i].text);
        for (size_t j = 0; j < s->statistics[i].change_count; ++j)
            free(s->statistics[i].changes[j].text);
        free(s->statistics[i].changes);
    }
    policies_free(&s->policies);
    lines_free(&s->updates);
    free(s->traces);
    free(s->rings);
    free(s);
}
int main(void) {
    Simulator *s = allocate(sizeof(*s));
    memset(s, 0, sizeof(*s));
    read_topology(&s->topology);
    read_policies(&s->policies);
    read_parameters(&s->topology, &s->parameters);
    s->event_count = read_events(&s->topology, &s->policies, s->events);
    run(s);
    if (mkdir("output", 0777) != 0 && errno != EEXIST) {
        perror("output");
        exit(EXIT_FAILURE);
    }
    write_lines("updates.txt", &s->updates);
    save_report("convergence.csv", convergence_lines(s));
    save_report("ribs.txt", rib_lines(s));
    save_report("paths.txt", path_lines(s));
    save_report("audit.txt", audit_lines(s));
    cleanup(s);
    return EXIT_SUCCESS;
}
