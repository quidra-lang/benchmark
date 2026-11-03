#include "bgp.h"
#include <stdlib.h>
#include <string.h>
Node *message_sender(const Message *m) { return m->source->owner; }
Node *message_receiver(const Message *m) { return other(m->source->link, m->source->owner); }
int message_compare(const void *left, const void *right) {
    const Message *a = left, *b = right;
    int x[4] = {a->time, message_receiver(a)->number, message_sender(a)->number, a->serial},
        y[4] = {b->time, message_receiver(b)->number, message_sender(b)->number, b->serial};
    for (int i = 0; i < 4; ++i)
        if (x[i] != y[i])
            return x[i] < y[i] ? -1 : 1;
    return 0;
}
static void heap_push(MessageQueue *q, Message message) {
    if (q->count == q->capacity) {
        q->capacity = q->capacity ? 2 * q->capacity : 64;
        q->items = resize(q->items, q->capacity * sizeof(Message));
    }
    size_t at = q->count++;
    while (at) {
        size_t parent = (at - 1) / 2;
        if (message_compare(&q->items[parent], &message) <= 0)
            break;
        q->items[at] = q->items[parent];
        at = parent;
    }
    q->items[at] = message;
}
static Message heap_pop(MessageQueue *q) {
    Message result = q->items[0], last = q->items[--q->count];
    if (q->count) {
        size_t at = 0;
        while (at * 2 + 1 < q->count) {
            size_t child = at * 2 + 1;
            if (child + 1 < q->count && message_compare(&q->items[child + 1], &q->items[child]) < 0)
                ++child;
            if (message_compare(&last, &q->items[child]) <= 0)
                break;
            q->items[at] = q->items[child];
            at = child;
        }
        q->items[at] = last;
    }
    return result;
}
Message queue_send(MessageQueue *q, int time, Session *session, int prefix, Attribute *attribute) {
    Message message = {++q->serial, time + session->link->delay, prefix, session,
                       attribute_retain(attribute)};
    heap_push(q, message);
    return message;
}
MessageList queue_arrivals(MessageQueue *q, int time) {
    MessageList result = {0};
    while (q->count && q->items[0].time == time) {
        result.items = resize(result.items, (result.count + 1) * sizeof(Message));
        result.items[result.count++] = heap_pop(q);
    }
    return result;
}
MessageList queue_ordered(const MessageQueue *q) {
    MessageList result = {.count = q->count};
    if (q->count) {
        result.items = allocate(q->count * sizeof(Message));
        memcpy(result.items, q->items, q->count * sizeof(Message));
        qsort(result.items, result.count, sizeof(Message), message_compare);
    }
    return result;
}
MessageList queue_remove(MessageQueue *q, Link *link) {
    MessageList ordered = queue_ordered(q), result = {0};
    q->count = 0;
    for (size_t i = 0; i < ordered.count; ++i) {
        Message m = ordered.items[i];
        if (m.source->link == link) {
            result.items = resize(result.items, (result.count + 1) * sizeof(Message));
            result.items[result.count++] = m;
        } else
            heap_push(q, m);
    }
    free(ordered.items);
    return result;
}
const char *event_kind_name(EventKind kind) {
    static const char *names[] = {"INITIAL", "ANNOUNCE",  "WITHDRAW",  "LINK_DOWN",
                                  "LINK_UP", "POLICY_ON", "POLICY_OFF"};
    return names[kind];
}
int read_events(Topology *t, Policies *p, Event events[51]) {
    int count = 1;
    events[0] = (Event){.kind = EVENT_INITIAL, .text = copy_text("INITIAL")};
    FILE *file = open_file("input/events.txt", "r");
    char *line;
    while ((line = read_line(file))) {
        char *space = strchr(line, ' ');
        Event *e = &events[count];
        *e = (Event){.number = count, .time = atoi(line), .text = copy_text(space + 1)};
        ++count;
        Words a = words(space + 1);
        if (strcmp(a.items[0], "ANNOUNCE") == 0 || strcmp(a.items[0], "WITHDRAW") == 0) {
            e->kind = strcmp(a.items[0], "ANNOUNCE") == 0 ? EVENT_ANNOUNCE : EVENT_WITHDRAW;
            e->node = node_named(t, atoi(a.items[1]));
            e->prefix = register_prefix(t, parse_prefix(a.items[2]));
            if (e->kind == EVENT_ANNOUNCE) {
                e->attribute = attribute_new();
                e->attribute->origin = origin_rank(a.items[3]);
                e->attribute->communities = parse_communities(&a, 4);
            }
        } else if (strcmp(a.items[0], "LINK") == 0) {
            e->kind = strcmp(a.items[1], "DOWN") == 0 ? EVENT_LINK_DOWN : EVENT_LINK_UP;
            e->link = link_named(t, a.items[2]);
        } else {
            e->kind = strcmp(a.items[1], "ON") == 0 ? EVENT_POLICY_ON : EVENT_POLICY_OFF;
            e->rule = rule_named(p, a.items[2]);
        }
        words_free(&a);
        free(line);
    }
    fclose(file);
    order_prefixes(t);
    return count;
}
void read_parameters(Topology *t, Parameters *p) {
    *p = (Parameters){0};
    FILE *file = open_file("input/params.txt", "r");
    char *line = read_line(file);
    Words a = words(line);
    p->customer = atoi(a.items[1]);
    p->peer = atoi(a.items[2]);
    p->provider = atoi(a.items[3]);
    words_free(&a);
    free(line);
    line = read_line(file);
    a = words(line);
    p->stepcap = atoi(a.items[1]);
    words_free(&a);
    free(line);
    while ((line = read_line(file))) {
        a = words(line);
        Trace *trace = &p->traces[p->trace_count++];
        trace->source = node_named(t, atoi(a.items[1]));
        trace->address = ip(a.items[2]);
        strcpy(trace->text, a.items[2]);
        words_free(&a);
        free(line);
    }
    fclose(file);
}
