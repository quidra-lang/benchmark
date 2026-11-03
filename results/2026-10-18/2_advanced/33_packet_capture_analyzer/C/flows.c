#include "capture.h"
const char *mark_names[4] = {"retransmission", "out_of_order", "lost_segment", "duplicate_ack"};
static Integer mod32(Integer value) {
    return (value + (INT64_C(1) << 32)) % (INT64_C(1) << 32);
}
static bool equal(Endpoint a, Endpoint b) {
    return a.address == b.address && a.port == b.port;
}
static void record_syn(Stream *s, Packet *p, int side) {
    Side *x = &s->sides[side];
    x->isn = num(p, F_TCP_SEQ_RAW);
    x->mss = has(p, F_TCP_OPTIONS_MSS) ? num(p, F_TCP_OPTIONS_MSS) : -1;
    x->ws = has(p, F_TCP_OPTIONS_WSCALE) ? num(p, F_TCP_OPTIONS_WSCALE) : -1;
    s->handshake[side == 0 ? 0 : 1] = p->number;
}
static void state_add(Stream *s, Integer packet) {
    grow((void **)&s->history, &s->history_cap, s->history_count + 1, sizeof *s->history);
    s->history[s->history_count++] = (State){s->state, packet};
}
void track(Packet *p, Stream *streams, size_t *count) {
    if (!has(p, F_TCP_SRCPORT))
        return;
    Endpoint source = {num(p, F_IP_SRC), num(p, F_TCP_SRCPORT)},
             destination = {num(p, F_IP_DST), num(p, F_TCP_DSTPORT)};
    bool syn = num(p, F_TCP_FLAGS_SYN) != 0, ack_set = num(p, F_TCP_FLAGS_ACK) != 0,
         fin = num(p, F_TCP_FLAGS_FIN) != 0, rst = num(p, F_TCP_FLAGS_RST) != 0;
    int index = -1;
    for (size_t i = *count; i > 0; --i)
        if ((equal(streams[i - 1].client, source) && equal(streams[i - 1].server, destination)) ||
            (equal(streams[i - 1].client, destination) && equal(streams[i - 1].server, source))) {
            index = (int)i - 1;
            break;
        }
    if (index < 0 ||
        ((strcmp(streams[index].state, "CLOSED") == 0 || strcmp(streams[index].state, "RESET") == 0) && syn &&
         !ack_set)) {
        index = (int)(*count)++;
        Stream *s = &streams[index];
        s->start = p->time;
        s->first_close = -1;
        for (int i = 0; i < 2; ++i) {
            s->sides[i].isn = -1;
            s->sides[i].mss = -1;
            s->sides[i].ws = -1;
        }
        if (syn && ack_set) {
            s->client = destination;
            s->server = source;
            s->state = "SYN_RECEIVED";
            record_syn(s, p, 1);
        } else {
            s->client = source;
            s->server = destination;
            s->state = syn ? "SYN_SENT" : "ESTABLISHED";
            if (syn)
                record_syn(s, p, 0);
        }
        state_add(s, p->number);
    }
    Stream *stream = &streams[index];
    pn(p, F_TCP_STREAM, index, false);
    int side = equal(source, stream->client) ? 0 : 1;
    Side *s = &stream->sides[side], *other = &stream->sides[1 - side];
    Integer seq = num(p, F_TCP_SEQ_RAW), ack = num(p, F_TCP_ACK_RAW);
    if (!s->base_set) {
        s->base = seq;
        s->base_set = true;
    }
    if (ack_set && !other->base_set) {
        other->base = ack;
        other->base_set = true;
    }
    Integer r = mod32(seq - s->base), length = num(p, F_TCP_LEN) + (Integer)syn + (Integer)fin;
    pn(p, F_TCP_SEQ, r, false);
    if (ack_set)
        pn(p, F_TCP_ACK, mod32(ack - other->base), false);
    int mark = -1;
    if (length > 0) {
        if (s->expected_set && r > s->expected)
            mark = 2;
        else if (s->expected_set && r < s->expected) {
            bool received = false;
            for (size_t i = 0; i < s->interval_count; ++i)
                if (s->intervals[i].first == r && s->intervals[i].length == length)
                    received = true;
            mark = received || p->time - s->advanced >= 3000 ? 0 : 1;
        }
        bool duplicate = false;
        for (size_t i = 0; i < s->interval_count; ++i)
            if (s->intervals[i].first == r && s->intervals[i].length == length)
                duplicate = true;
        if (!duplicate) {
            grow((void **)&s->intervals, &s->interval_cap, s->interval_count + 1, sizeof *s->intervals);
            s->intervals[s->interval_count++] = (Interval){r, length};
        }
        if (!s->expected_set || r + length > s->expected) {
            s->expected = r + length;
            s->expected_set = true;
            s->advanced = p->time;
        }
    } else if (ack_set && !rst && s->previous_ack_set && s->previous_ack[0] == ack &&
               s->previous_ack[1] == num(p, F_TCP_WINDOW)) {
        mark = 3;
        ++s->previous_ack[3];
        p->duplicate_origin = s->previous_ack[2];
        p->duplicate_count = s->previous_ack[3];
    }
    if (ack_set && mark != 3) {
        s->previous_ack_set = true;
        s->previous_ack[0] = ack;
        s->previous_ack[1] = num(p, F_TCP_WINDOW);
        s->previous_ack[2] = p->number;
        s->previous_ack[3] = 0;
    }
    if (mark >= 0) {
        Field marks[4] = {F_TCP_ANALYSIS_RETRANSMISSION, F_TCP_ANALYSIS_OUT_OF_ORDER,
                          F_TCP_ANALYSIS_LOST_SEGMENT, F_TCP_ANALYSIS_DUPLICATE_ACK};
        flag(p, marks[mark]);
        ++s->marks[mark];
        grow((void **)&stream->events, &stream->event_cap, stream->event_count + 1, sizeof *stream->events);
        stream->events[stream->event_count++] = (Event){p->number, side, mark, r, length};
    }
    pn(p, F_TCP_WINDOW_CALC,
       num(p, F_TCP_WINDOW) *
           (stream->sides[0].ws >= 0 && stream->sides[1].ws >= 0 && !syn ? (INT64_C(1) << s->ws) : 1),
       false);
    const char *previous = stream->state;
    if (rst) {
        if (strcmp(previous, "CLOSED") && strcmp(previous, "RESET"))
            stream->state = "RESET";
    } else if (!strcmp(previous, "SYN_SENT") && side == 1 && syn && ack_set && stream->sides[0].isn >= 0 &&
               ack == mod32(stream->sides[0].isn + 1)) {
        stream->state = "SYN_RECEIVED";
        record_syn(stream, p, 1);
    } else if (!strcmp(previous, "SYN_RECEIVED") && side == 0 && ack_set && !syn &&
               stream->sides[1].isn >= 0 && ack == mod32(stream->sides[1].isn + 1)) {
        stream->state = "ESTABLISHED";
        stream->handshake[2] = p->number;
    } else if (!strcmp(previous, "ESTABLISHED") && fin) {
        stream->state = "FIN_WAIT";
        stream->first_close = side;
    } else if (!strcmp(previous, "FIN_WAIT") && fin && side != stream->first_close) {
        stream->state = "CLOSING";
        stream->f2 = mod32(seq + num(p, F_TCP_LEN) + 1);
    } else if (!strcmp(previous, "CLOSING") && side == stream->first_close && ack_set && ack == stream->f2)
        stream->state = "CLOSED";
    if (strcmp(stream->state, previous))
        state_add(stream, p->number);
    ++s->packets;
    s->payload += num(p, F_TCP_LEN);
    ++stream->packets;
    stream->bytes += p->length;
    stream->end = p->time;
}
char *endpoint(Endpoint value, bool port) {
    return port ? format("%s:%" PRId64, ipv4(value.address), value.port) : ipv4(value.address);
}
static int conversation_compare(const void *pa, const void *pb) {
    const Conversation *a = pa, *b = pb;
    Integer ab = a->bytes[0] + a->bytes[1], bb = b->bytes[0] + b->bytes[1],
            ap = a->packets[0] + a->packets[1], bp = b->packets[0] + b->packets[1];
    if (ab != bb)
        return ab > bb ? -1 : 1;
    if (ap != bp)
        return ap > bp ? -1 : 1;
    if (a->kind != b->kind)
        return a->kind < b->kind ? -1 : 1;
    return a->first < b->first ? -1 : a->first > b->first;
}
Conversation *conversations(const Packet *packets, size_t count, size_t *result_count) {
    Conversation *result = allocate(count * 3, sizeof *result);
    *result_count = 0;
    for (size_t i = 0; i < count; ++i) {
        const Packet *p = &packets[i];
        for (int kind = 0; kind < 3; ++kind) {
            if (!has(p, kind == 0 ? F_IP_SRC : kind == 1 ? F_TCP_STREAM : F_UDP_SRCPORT))
                continue;
            Endpoint source = {num(p, F_IP_SRC),
                               kind == 0 ? 0 : num(p, kind == 1 ? F_TCP_SRCPORT : F_UDP_SRCPORT)},
                     destination = {num(p, F_IP_DST),
                                    kind == 0 ? 0 : num(p, kind == 1 ? F_TCP_DSTPORT : F_UDP_DSTPORT)};
            size_t index = 0;
            for (; index < *result_count; ++index) {
                Conversation *c = &result[index];
                if (c->kind == kind && ((equal(c->a, source) && equal(c->b, destination)) ||
                                        (equal(c->a, destination) && equal(c->b, source)))) {
                    if (kind != 1 || num(&packets[c->first - 1], F_TCP_STREAM) == num(p, F_TCP_STREAM))
                        break;
                }
            }
            if (index == *result_count) {
                Conversation *c = &result[(*result_count)++];
                c->kind = kind;
                c->a = source;
                c->b = destination;
                c->first = p->number;
                c->start = p->time;
            }
            Conversation *c = &result[index];
            int side = equal(source, c->a) ? 0 : 1;
            ++c->packets[side];
            c->bytes[side] += p->length;
            c->end = p->time;
        }
    }
    qsort(result, *result_count, sizeof *result, conversation_compare);
    return result;
}
static int endpoint_compare(const void *pa, const void *pb) {
    const EndpointTotals *a = pa, *b = pb;
    Integer ab = a->bytes[0] + a->bytes[1], bb = b->bytes[0] + b->bytes[1],
            ap = a->packets[0] + a->packets[1], bp = b->packets[0] + b->packets[1];
    if (ab != bb)
        return ab > bb ? -1 : 1;
    if (ap != bp)
        return ap > bp ? -1 : 1;
    return a->address < b->address ? -1 : a->address > b->address;
}
EndpointTotals *endpoints(const Packet *packets, size_t count, size_t *result_count) {
    EndpointTotals *result = allocate(count * 2, sizeof *result);
    *result_count = 0;
    for (size_t i = 0; i < count; ++i)
        if (has(&packets[i], F_IP_SRC))
            for (int side = 0; side < 2; ++side) {
                Integer address = num(&packets[i], side == 0 ? F_IP_SRC : F_IP_DST);
                size_t index = 0;
                while (index < *result_count && result[index].address != address)
                    ++index;
                if (index == *result_count)
                    result[(*result_count)++].address = address;
                ++result[index].packets[side];
                result[index].bytes[side] += packets[i].length;
            }
    qsort(result, *result_count, sizeof *result, endpoint_compare);
    return result;
}
