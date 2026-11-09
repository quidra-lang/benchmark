#include "raft.h"

void add_line(Lines *out, const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    char *text = malloc((size_t)length + 1);
    vsnprintf(text, (size_t)length + 1, format, args);
    va_end(args);
    Lines_append(out, text);
}
static void free_lines(Lines *lines) {
    for (size_t i = 0; i < lines->count; ++i)
        free(lines->items[i]);
    free(lines->items);
}
static uint8_t node_bit(int node) { return (uint8_t)(1u << (node - 1)); }
static int mask_count(uint8_t mask) {
    int count = 0;
    while (mask) {
        count += mask & 1;
        mask >>= 1;
    }
    return count;
}
static const char *node_set(uint8_t mask) {
    static char buffers[32][32];
    static unsigned index;
    char *out = buffers[index++ % 32];
    int count = 0;
    for (int node = 1; node <= 7; ++node)
        if (mask & node_bit(node)) {
            if (count)
                out[count++] = ',';
            count += snprintf(out + count, 32 - (size_t)count, "n%d", node);
        }
    if (count == 0)
        out[count++] = '-';
    out[count] = 0;
    return out;
}
static const char *node_name(int node) {
    static char buffers[16][8];
    static unsigned index;
    char *out = buffers[index++ % 16];
    if (node)
        snprintf(out, 8, "n%d", node);
    else
        strcpy(out, "-");
    return out;
}
typedef struct {
    int time, node, term;
    bool transfer;
    uint8_t votes;
    int won;
} Election;
DEFINE_VECTOR(Elections, Election)
typedef enum { END_ACTIVE, END_CRASH, END_STEPDOWN, END_QUORUM } EndReason;
typedef struct {
    int node, elected;
    uint8_t votes;
    int appended, ended;
    EndReason reason;
    int commit;
} Leader;
typedef struct {
    bool election, leader;
    uint8_t candidates;
    int started;
    Leader record;
} TermRecord;
typedef struct {
    int first, last;
} Gap;
DEFINE_VECTOR(Gaps, Gap)
typedef struct {
    int index;
    Store store;
} Snapshot;
typedef struct {
    char key[9];
    int requests, committed;
} KeyCount;
typedef struct {
    Input input;
    Node nodes[8];
    Network network;
    Minstd random;
    Checker checker;
    int time;
    FILE *trace;
    Elections elections;
    TermRecord *terms;
    size_t term_capacity;
    int leader_count;
    Lines timelines;
    Gaps gaps;
    int gap_start, leader_ticks, multi_ticks, maximum_term, committed_count;
    Store reference;
    Snapshot snapshots[8];
    int snapshot_count;
    int status_counts[5], latencies[1000], latency_count;
    KeyCount keys[1000];
    int key_count;
} Simulator;
static bool majority(const Simulator *s, int count) { return 2 * count > s->input.settings.nodes; }
static void trace(Simulator *s, const char *format, ...) {
    fprintf(s->trace, "%d ", s->time);
    va_list args;
    va_start(args, format);
    vfprintf(s->trace, format, args);
    va_end(args);
    fputc('\n', s->trace);
}
static void ensure_term(Simulator *s, int term) {
    if ((size_t)term < s->term_capacity)
        return;
    size_t old = s->term_capacity, capacity = old ? old : 16;
    while (capacity <= (size_t)term)
        capacity *= 2;
    s->terms = realloc(s->terms, capacity * sizeof *s->terms);
    memset(s->terms + old, 0, (capacity - old) * sizeof *s->terms);
    s->term_capacity = capacity;
}
static void set_timer(Simulator *s, Node *node) {
    node->election_deadline = s->time + random_between(&s->random, s->input.settings.election_min,
                                                       s->input.settings.election_max);
}
static Message message(const Node *node, int destination, Type type) {
    Message out = {0};
    out.type = type;
    out.source = node->number;
    out.destination = destination;
    out.term = node->term;
    return out;
}
static void send_append(Simulator *s, Node *node, int destination) {
    Message out = message(node, destination, AE);
    out.previous = node->next[destination] - 1;
    out.previous_term = term_at(node, out.previous);
    int last = out.previous + s->input.settings.batch;
    if (last > last_index(node))
        last = last_index(node);
    out.entry_count = last - out.previous;
    if (out.entry_count > 0) {
        out.entries = malloc((size_t)out.entry_count * sizeof *out.entries);
        memcpy(out.entries, node->log.items + out.previous,
               (size_t)out.entry_count * sizeof *out.entries);
    }
    out.commit = node->commit;
    network_send(&s->network, s->time, out);
}
static void broadcast_append(Simulator *s, Node *node) {
    for (int other = 1; other <= s->input.settings.nodes; ++other)
        if (other != node->number)
            send_append(s, node, other);
}
static void end_leadership(Simulator *s, Node *node, EndReason reason) {
    Leader *record = &s->terms[node->term].record;
    record->ended = s->time;
    record->reason = reason;
    record->commit = node->commit;
    cancel_transfer(node);
}
static void send_timeout_now(Simulator *s, Node *node) {
    int destination = node->transfer_target;
    trace(s, "TIMEOUTNOW n%d n%d term %d index %d", node->number, destination, node->term,
          last_index(node));
    node->transfer_sent = true;
    network_send(&s->network, s->time, message(node, destination, TN));
}
static void start_transfer(Simulator *s, Node *node, int destination) {
    if (!node->up || node->role != LEADER || node->transfer_target || node->number == destination) {
        trace(s, "TRANSFER n%d n%d ignored", node->number, destination);
        return;
    }
    trace(s, "TRANSFER n%d n%d start match %d/%d", node->number, destination,
          node->match[destination], last_index(node));
    node->transfer_target = destination;
    node->transfer_sent = false;
    node->transfer_deadline = s->time + s->input.settings.election_min;
    if (node->match[destination] == last_index(node))
        send_timeout_now(s, node);
    else
        send_append(s, node, destination);
}
static void control(Simulator *s, const Control *event) {
    Node *node = &s->nodes[event->first];
    switch (event->kind) {
    case CONTROL_CRASH:
        trace(s, "CRASH n%d %s term %d", node->number, role_name(node->role), node->term);
        if (node->role == LEADER)
            end_leadership(s, node, END_CRASH);
        node_crash(node);
        break;
    case CONTROL_RESTART:
        node->up = true;
        set_timer(s, node);
        trace(s, "RESTART n%d term %d length %d deadline %d", node->number, node->term,
              last_index(node), node->election_deadline);
        break;
    case CONTROL_PARTITION: {
        network_partition(&s->network, event->groups, event->group_count);
        fprintf(s->trace, "%d PARTITION", s->time);
        for (int i = 0; i < event->group_count; ++i) {
            uint8_t mask = 0;
            for (int j = 0; j < event->groups[i].count; ++j)
                mask |= node_bit(event->groups[i].nodes[j]);
            fprintf(s->trace, " %s", node_set(mask));
        }
        fputc('\n', s->trace);
        break;
    }
    case CONTROL_HEAL:
        network_heal(&s->network);
        trace(s, "HEAL");
        break;
    case CONTROL_TRANSFER:
        start_transfer(s, node, event->second);
        break;
    }
}
static void attempt(Simulator *s, Request *request) {
    ++request->attempts;
    int destination = request->destination, redirected = 0;
    const char *reason;
    for (;;) {
        Node *node = &s->nodes[destination];
        if (!node->up) {
            reason = "down";
            break;
        }
        if (node->role == LEADER) {
            if (node->transfer_target) {
                reason = "transfer";
                break;
            }
            Entries_append(&node->log, (Entry){node->term, request->command, request->number});
            ++s->terms[node->term].record.appended;
            request->accepted = true;
            request->index = last_index(node);
            request->term = node->term;
            request->scheduled = -1;
            trace(s, "ACCEPT r%d n%d index %d term %d", request->number, node->number,
                  request->index, node->term);
            return;
        }
        if (!node->known_leader || redirected >= s->input.settings.nodes - 1) {
            reason = "noleader";
            break;
        }
        destination = node->known_leader;
        trace(s, "REDIRECT r%d n%d n%d", request->number, node->number, destination);
        ++redirected;
        ++request->redirects;
    }
    if (request->attempts < s->input.settings.attempts) {
        request->destination = destination % s->input.settings.nodes + 1;
        request->scheduled = s->time + s->input.settings.retry;
        trace(s, "REJECT r%d n%d %s retry n%d at %d", request->number, destination, reason,
              request->destination, request->scheduled);
    } else {
        request->abandoned = true;
        request->scheduled = -1;
        trace(s, "REJECT r%d n%d %s giveup", request->number, destination, reason);
    }
}
static void start_election(Simulator *s, Node *node, bool transfer) {
    ++node->term;
    node->role = CANDIDATE;
    node->voted_for = node->number;
    node->votes = node_bit(node->number);
    node->known_leader = 0;
    set_timer(s, node);
    ++node->stats.elections;
    node->election_record = (int)s->elections.count;
    Elections_append(&s->elections,
                     (Election){s->time, node->number, node->term, transfer, node->votes, -1});
    ensure_term(s, node->term);
    TermRecord *record = &s->terms[node->term];
    if (!record->election) {
        record->election = true;
        record->started = s->time;
    }
    record->candidates |= node_bit(node->number);
    trace(s, "ELECTION n%d term %d last %d/%d deadline %d", node->number, node->term,
          last_index(node), last_term(node), node->election_deadline);
    for (int other = 1; other <= s->input.settings.nodes; ++other)
        if (other != node->number) {
            Message out = message(node, other, RV);
            out.last_index = last_index(node);
            out.last_term = last_term(node);
            network_send(&s->network, s->time, out);
        }
}
static void become_leader(Simulator *s, Node *node) {
    node->role = LEADER;
    node->known_leader = node->number;
    for (int other = 1; other <= s->input.settings.nodes; ++other)
        if (other != node->number) {
            node->next[other] = last_index(node) + 1;
            node->match[other] = 0;
        }
    Command noop = {0};
    Entries_append(&node->log, (Entry){node->term, noop, 0});
    ++node->stats.leader_terms;
    s->elections.items[node->election_record].won = s->time;
    checker_leader(&s->checker, node);
    ensure_term(s, node->term);
    TermRecord *term = &s->terms[node->term];
    if (!term->leader)
        ++s->leader_count;
    term->leader = true;
    term->record = (Leader){node->number, s->time, node->votes, 1, -1, END_ACTIVE, 0};
    trace(s, "LEADER n%d term %d votes %s noop %d", node->number, node->term, node_set(node->votes),
          last_index(node));
    broadcast_append(s, node);
    node->heartbeat_deadline = s->time + s->input.settings.heartbeat;
    node->quorum_deadline = s->time + s->input.settings.quorum;
    node->heard = 0;
}
static void vote_request(Simulator *s, Node *node, const Message *incoming) {
    const char *reason = NULL;
    if (incoming->term < node->term)
        reason = "term";
    else if (node->voted_for && node->voted_for != incoming->source)
        reason = "voted";
    else if (!accepts_log(node, incoming->last_index, incoming->last_term))
        reason = "log";
    if (reason == NULL) {
        node->voted_for = incoming->source;
        ++node->stats.votes_granted;
        set_timer(s, node);
        trace(s, "VOTE n%d n%d term %d deadline %d", node->number, incoming->source, node->term,
              node->election_deadline);
    } else
        trace(s, "DENY n%d n%d term %d %s", node->number, incoming->source, node->term, reason);
    Message out = message(node, incoming->source, RVR);
    out.granted = reason == NULL;
    network_send(&s->network, s->time, out);
}
static void vote_response(Simulator *s, Node *node, const Message *incoming) {
    if (node->role != CANDIDATE || incoming->term != node->term || !incoming->granted)
        return;
    node->votes |= node_bit(incoming->source);
    s->elections.items[node->election_record].votes = node->votes;
    if (majority(s, mask_count(node->votes)))
        become_leader(s, node);
}
static void truncate_log(Simulator *s, Node *node, int first) {
    int removed = last_index(node) - first + 1;
    checker_truncate(&s->checker, first, node->log.items + first - 1, removed);
    node->log.count = (size_t)first - 1;
    node->stats.truncated += removed;
    trace(s, "TRUNCATE n%d from %d removed %d", node->number, first, removed);
}
static void advance_commit(Simulator *s, Node *node, int index) {
    for (int k = node->commit + 1; k <= index; ++k)
        checker_commit(&s->checker, k, term_at(node, k), s->time);
    node->commit = index;
    int first = node->applied + 1;
    for (int k = first; k <= index; ++k) {
        const Entry *entry = &node->log.items[k - 1];
        char result[32];
        apply_command(&node->store, &entry->command, result);
        ++node->stats.applies;
        checker_apply(&s->checker, k, entry, result);
    }
    node->applied = index;
    trace(s, "APPLY n%d %d-%d", node->number, first, index);
}
static void check_commit(Simulator *s, Node *node) {
    for (int index = last_index(node); index > node->commit; --index) {
        if (term_at(node, index) != node->term)
            return;
        int count = 1;
        for (int other = 1; other <= s->input.settings.nodes; ++other)
            if (other != node->number && node->match[other] >= index)
                ++count;
        if (majority(s, count)) {
            trace(s, "COMMIT n%d %d-%d term %d", node->number, node->commit + 1, index, node->term);
            advance_commit(s, node, index);
            return;
        }
    }
}
static void append_request(Simulator *s, Node *node, const Message *incoming) {
    Message out = message(node, incoming->source, AER);
    if (incoming->term < node->term) {
        network_send(&s->network, s->time, out);
        return;
    }
    if (node->role == CANDIDATE) {
        node->role = FOLLOWER;
        trace(s, "YIELD n%d term %d n%d", node->number, node->term, incoming->source);
    }
    node->known_leader = incoming->source;
    set_timer(s, node);
    int previous = incoming->previous;
    if (previous > last_index(node) || term_at(node, previous) != incoming->previous_term) {
        ++node->stats.ae_fail;
        out.confirmed = previous > last_index(node) ? last_index(node) : previous - 1;
        network_send(&s->network, s->time, out);
        return;
    }
    ++node->stats.ae_ok;
    for (int i = 0; i < incoming->entry_count; ++i) {
        int index = previous + i + 1;
        const Entry *entry = &incoming->entries[i];
        if (index <= last_index(node) && term_at(node, index) != entry->term)
            truncate_log(s, node, index);
        if (index > last_index(node)) {
            Entries_append(&node->log, *entry);
            ++node->stats.appended;
        }
    }
    int confirmed = previous + incoming->entry_count,
        commit = incoming->commit < confirmed ? incoming->commit : confirmed;
    if (commit > node->commit)
        advance_commit(s, node, commit);
    out.success = true;
    out.confirmed = confirmed;
    network_send(&s->network, s->time, out);
}
static void append_response(Simulator *s, Node *node, const Message *incoming) {
    if (node->role != LEADER || incoming->term != node->term)
        return;
    int source = incoming->source;
    node->heard |= node_bit(source);
    if (incoming->success) {
        if (incoming->confirmed > node->match[source])
            node->match[source] = incoming->confirmed;
        if (incoming->confirmed + 1 > node->next[source])
            node->next[source] = incoming->confirmed + 1;
        check_commit(s, node);
        if (node->transfer_target == source && !node->transfer_sent &&
            node->match[source] == last_index(node))
            send_timeout_now(s, node);
        else if (node->next[source] <= last_index(node))
            send_append(s, node, source);
    } else {
        int next = node->next[source] - 1;
        if (incoming->confirmed + 1 < next)
            next = incoming->confirmed + 1;
        if (node->match[source] + 1 > next)
            next = node->match[source] + 1;
        node->next[source] = next;
        trace(s, "BACKTRACK n%d n%d next %d", node->number, source, next);
        send_append(s, node, source);
    }
}
static void receive(Simulator *s, const Message *incoming) {
    Node *node = &s->nodes[incoming->destination];
    if (incoming->term > node->term) {
        Role previous = node->role;
        trace(s, "TERM n%d %d->%d %s n%d %s", node->number, node->term, incoming->term,
              type_name(incoming->type), incoming->source, role_name(previous));
        if (previous == LEADER)
            end_leadership(s, node, END_STEPDOWN);
        node->term = incoming->term;
        node->voted_for = 0;
        node->known_leader = 0;
        node->role = FOLLOWER;
        if (previous == LEADER)
            set_timer(s, node);
    }
    switch (incoming->type) {
    case RV:
        vote_request(s, node, incoming);
        break;
    case RVR:
        vote_response(s, node, incoming);
        break;
    case AE:
        append_request(s, node, incoming);
        break;
    case AER:
        append_response(s, node, incoming);
        break;
    case TN:
        if (incoming->term != node->term || node->role != FOLLOWER)
            trace(s, "IGNORE n%d TN n%d term %d", node->number, incoming->source, incoming->term);
        else
            start_election(s, node, true);
        break;
    }
}
static void timers(Simulator *s, Node *node) {
    if (node->role == LEADER) {
        if (node->quorum_deadline == s->time) {
            if (!majority(s, 1 + mask_count(node->heard))) {
                trace(s, "STEPDOWN n%d term %d heard %s", node->number, node->term,
                      node_set(node->heard));
                end_leadership(s, node, END_QUORUM);
                node->role = FOLLOWER;
                node->known_leader = 0;
                set_timer(s, node);
                return;
            }
            node->heard = 0;
            node->quorum_deadline = s->time + s->input.settings.quorum;
        }
        if (node->transfer_target && node->transfer_deadline == s->time) {
            trace(s, "TRANSFER n%d n%d abort", node->number, node->transfer_target);
            cancel_transfer(node);
        }
        if (node->heartbeat_deadline == s->time) {
            broadcast_append(s, node);
            node->heartbeat_deadline = s->time + s->input.settings.heartbeat;
        }
    } else if (node->election_deadline == s->time)
        start_election(s, node, false);
}
static void end_tick(Simulator *s) {
    checker_logs(&s->checker, s->nodes, s->input.settings.nodes);
    int count = 0;
    for (int i = 1; i <= s->input.settings.nodes; ++i)
        if (s->nodes[i].up && s->nodes[i].role == LEADER) {
            ++s->nodes[i].stats.leader_ticks;
            ++count;
        }
    if (count) {
        ++s->leader_ticks;
        s->multi_ticks += count >= 2;
        if (s->gap_start >= 0) {
            Gaps_append(&s->gaps, (Gap){s->gap_start, s->time - 1});
            s->gap_start = -1;
        }
    } else if (s->gap_start < 0)
        s->gap_start = s->time;
    if (s->time % s->input.settings.sample == 0) {
        char text[128];
        int p = snprintf(text, sizeof text, "TIMELINE %d", s->time);
        for (int i = 1; i <= s->input.settings.nodes; ++i)
            p += snprintf(text + p, sizeof text - (size_t)p, " %c%d",
                          s->nodes[i].up ? role_name(s->nodes[i].role)[0] : 'D', s->nodes[i].term);
        add_line(&s->timelines, "%s", text);
    }
}
static int key_index(Simulator *s, const char *key) {
    int position = 0;
    while (position < s->key_count && strcmp(s->keys[position].key, key) < 0)
        ++position;
    if (position < s->key_count && !strcmp(s->keys[position].key, key))
        return position;
    memmove(s->keys + position + 1, s->keys + position,
            (size_t)(s->key_count - position) * sizeof *s->keys);
    ++s->key_count;
    memset(&s->keys[position], 0, sizeof s->keys[position]);
    strcpy(s->keys[position].key, key);
    return position;
}
static void finish_statistics(Simulator *s) {
    for (int i = 1; i <= s->input.settings.nodes; ++i)
        if (s->nodes[i].term > s->maximum_term)
            s->maximum_term = s->nodes[i].term;
    s->committed_count = s->checker.committed_count;
    s->snapshots[0].index = 0;
    s->snapshot_count = 1;
    for (int index = 1; index <= s->committed_count; ++index) {
        char result[32];
        apply_command(&s->reference, &s->checker.applied[index].entry.command, result);
        bool needed = false;
        for (int i = 1; i <= s->input.settings.nodes; ++i)
            if (s->nodes[i].applied == index)
                needed = true;
        if (needed)
            s->snapshots[s->snapshot_count++] = (Snapshot){index, s->reference};
    }
    for (int i = 0; i < s->input.request_count; ++i) {
        Request *r = &s->input.requests[i];
        int key = key_index(s, r->command.key);
        ++s->keys[key].requests;
        if (r->accepted) {
            if ((size_t)r->index < s->checker.entry_capacity &&
                s->checker.committed[r->index].valid &&
                s->checker.committed[r->index].term == r->term) {
                r->status = COMMITTED;
                r->latency = s->checker.committed[r->index].time - r->time;
                strcpy(r->result, s->checker.applied[r->index].result);
                s->latencies[s->latency_count++] = r->latency;
                ++s->keys[key].committed;
            } else {
                bool retained = false;
                for (int node = 1; node <= s->input.settings.nodes; ++node)
                    if (last_index(&s->nodes[node]) >= r->index &&
                        term_at(&s->nodes[node], r->index) == r->term)
                        retained = true;
                r->status = retained ? UNCOMMITTED : LOST;
            }
        } else
            r->status = r->abandoned ? FAILED : WAITING;
        ++s->status_counts[r->status];
    }
}
static FILE *output(const char *name) {
    char path[128];
    snprintf(path, sizeof path, "output/%s", name);
    return fopen(path, "w");
}
static void leader_lines(const Simulator *s, FILE *out) {
    const char *reasons[4] = {"ACTIVE", "CRASH", "STEPDOWN", "QUORUM"};
    for (size_t i = 0; i < s->elections.count; ++i) {
        const Election *e = &s->elections.items[i];
        fprintf(out, "ELECTION %d n%d term %d trigger %s votes %d ", e->time, e->node, e->term,
                e->transfer ? "transfer" : "timeout", mask_count(e->votes));
        if (e->won >= 0)
            fprintf(out, "WON %d\n", e->won);
        else
            fputs("LOST\n", out);
    }
    for (int term = 1; term <= s->maximum_term; ++term) {
        const TermRecord *record = (size_t)term < s->term_capacity ? &s->terms[term] : NULL;
        if (!record || !record->leader) {
            fprintf(out, "TERM %d NONE candidates %s\n", term,
                    node_set(record ? record->candidates : 0));
            continue;
        }
        const Leader *leader = &record->record;
        fprintf(out, "TERM %d LEADER n%d elected %d votes %s ended ", term, leader->node,
                leader->elected, node_set(leader->votes));
        if (leader->ended < 0)
            fputc('-', out);
        else
            fprintf(out, "%d", leader->ended);
        fprintf(out, " %s appended %d commit %d candidates %s started %d wait %d\n",
                reasons[leader->reason], leader->appended,
                leader->ended < 0 ? s->nodes[leader->node].commit : leader->commit,
                node_set(record->candidates), record->started, leader->elected - record->started);
    }
    for (int i = 1; i <= s->input.settings.nodes; ++i) {
        const Statistics *p = &s->nodes[i].stats;
        fprintf(out, "NODE n%d elections %d leader_terms %d leader_ticks %d votes_granted %d\n", i,
                p->elections, p->leader_terms, p->leader_ticks, p->votes_granted);
    }
    for (size_t i = 0; i < s->timelines.count; ++i)
        fprintf(out, "%s\n", s->timelines.items[i]);
    int longest = 0;
    for (size_t i = 0; i < s->gaps.count; ++i) {
        Gap gap = s->gaps.items[i];
        int length = gap.last - gap.first + 1;
        if (length > longest)
            longest = length;
        fprintf(out, "GAP %d-%d length %d\n", gap.first, gap.last, length);
    }
    fprintf(
        out,
        "SUMMARY terms %d leaders %d elections %zu leader_ticks %d multi_ticks %d ticks %d gaps %zu longest %d\n",
        s->maximum_term, s->leader_count, s->elections.count, s->leader_ticks, s->multi_ticks,
        s->input.settings.end + 1, s->gaps.count, longest);
}
static void log_lines(const Simulator *s, FILE *out) {
    int limit = last_index(&s->nodes[1]), prefix = 0;
    for (int i = 1; i <= s->input.settings.nodes; ++i) {
        const Node *node = &s->nodes[i];
        if (last_index(node) < limit)
            limit = last_index(node);
        fprintf(out, "NODE n%d %s term %d voted %s commit %d applied %d length %d\n", i,
                node->up ? role_name(node->role) : "DOWN", node->term, node_name(node->voted_for),
                node->commit, node->applied, last_index(node));
        for (int k = 1; k <= last_index(node); ++k) {
            const Entry *entry = &node->log.items[k - 1];
            fprintf(out, "%d %d %s", k, entry->term, command_text(&entry->command));
            if (entry->request)
                fprintf(out, " r%d", entry->request);
            fputc('\n', out);
        }
    }
    for (int k = 1; k <= limit; ++k) {
        bool agree = true;
        for (int i = 2; i <= s->input.settings.nodes; ++i)
            if (!entry_equal(&s->nodes[i].log.items[k - 1], &s->nodes[1].log.items[k - 1]))
                agree = false;
        if (!agree)
            break;
        prefix = k;
    }
    fprintf(out, "AGREE prefix %d committed %d\n", prefix, s->committed_count);
    for (int i = 1; i <= s->input.settings.nodes; ++i) {
        const Node *node = &s->nodes[i];
        int common = 0;
        for (int k = 1; k <= last_index(node) && k <= s->committed_count; ++k) {
            if (term_at(node, k) != s->checker.committed[k].term)
                break;
            common = k;
        }
        const Statistics *p = &node->stats;
        fprintf(
            out,
            "DIFF n%d common %d behind %d extra %d ae_ok %d ae_fail %d appended %d truncated %d applies %d\n",
            i, common, s->committed_count - common, last_index(node) - common, p->ae_ok, p->ae_fail,
            p->appended, p->truncated, p->applies);
    }
}
static void state_lines(const Simulator *s, FILE *out) {
    for (int i = 1; i <= s->input.settings.nodes; ++i) {
        const Node *node = &s->nodes[i];
        const Store *reference = NULL;
        for (int j = 0; j < s->snapshot_count; ++j)
            if (s->snapshots[j].index == node->applied)
                reference = &s->snapshots[j].store;
        fprintf(out, "NODE n%d %s applied %d keys %d replay %s\n", i, node->up ? "UP" : "DOWN",
                node->applied, node->store.count,
                store_equal(&node->store, reference) ? "match" : "mismatch");
        for (int j = 0; j < node->store.count; ++j)
            fprintf(out, "%s %d\n", node->store.items[j].key, node->store.items[j].value);
    }
    for (int i = 0; i < s->input.request_count; ++i) {
        const Request *r = &s->input.requests[i];
        fprintf(out, "REQUEST r%d at %d n%d %s attempts %d redirects %d %s", r->number, r->time,
                r->initial_destination, command_text(&r->command), r->attempts, r->redirects,
                status_name(r->status));
        if (r->accepted) {
            fprintf(out, " index %d term %d", r->index, r->term);
            if (r->status == COMMITTED)
                fprintf(out, " latency %d result %s", r->latency, r->result);
        } else if (r->status == WAITING)
            fprintf(out, " next %d", r->scheduled);
        fputc('\n', out);
    }
    for (int i = 0; i < s->key_count; ++i) {
        const KeyCount *key = &s->keys[i];
        int index = store_find(&s->reference, key->key);
        fprintf(out, "KEY %s requests %d committed %d final ", key->key, key->requests,
                key->committed);
        if (index < 0)
            fputs("missing\n", out);
        else
            fprintf(out, "%d\n", s->reference.items[index].value);
    }
    fprintf(out, "REQUESTS total %d committed %d uncommitted %d lost %d failed %d waiting %d\n",
            s->input.request_count, s->status_counts[0], s->status_counts[1], s->status_counts[2],
            s->status_counts[3], s->status_counts[4]);
    int total = 0, minimum = 0, maximum = 0;
    for (int i = 0; i < s->latency_count; ++i) {
        int latency = s->latencies[i];
        total += latency;
        if (i == 0 || latency < minimum)
            minimum = latency;
        if (i == 0 || latency > maximum)
            maximum = latency;
    }
    fprintf(out, "LATENCY count %d total %d min %d max %d\n", s->latency_count, total, minimum,
            maximum);
}
static void print_counters(FILE *out, const Counters values) {
    for (int i = 0; i < 7; ++i)
        fprintf(out, " %s %d", counter_names[i], values[i]);
    fputc('\n', out);
}
static void safety_lines(const Simulator *s, FILE *out) {
    Lines properties = checker_lines(&s->checker, s->maximum_term);
    for (size_t i = 0; i < properties.count; ++i)
        fprintf(out, "%s\n", properties.items[i]);
    free_lines(&properties);
    fputs("MESSAGES", out);
    print_counters(out, s->network.total);
    for (int i = 0; i < 5; ++i) {
        fprintf(out, "TYPE %s", type_name((Type)i));
        print_counters(out, s->network.by_type[i]);
    }
    for (int a = 1; a <= s->input.settings.nodes; ++a)
        for (int b = 1; b <= s->input.settings.nodes; ++b)
            if (a != b) {
                const Link *link = &s->network.links[a][b];
                int dropped = 0;
                for (int field = PARTITIONED; field <= DOWN_LOST; ++field)
                    dropped += link->stats[field];
                fprintf(out, "LINK n%d->n%d delay %d loss %d sent %d delivered %d dropped %d\n", a,
                        b, link->delay, link->loss, link->stats[SENT], link->stats[DELIVERED],
                        dropped);
            }
    fprintf(out, "DRAWS %d\n", s->random.draws);
    bool unsafe = false;
    for (int i = 0; i < 5; ++i)
        if (s->checker.violations[i])
            unsafe = true;
    fprintf(out, "RESULT %s\n", unsafe ? "UNSAFE" : "SAFE");
}
int main(void) {
    Simulator *s = calloc(1, sizeof *s);
    read_cluster(&s->input);
    network_init(&s->network, s->input.settings.nodes);
    s->random.state = s->input.settings.seed;
    s->gap_start = -1;
    mkdir("output", 0777);
    s->trace = output("trace.txt");
    for (int i = 1; i <= s->input.settings.nodes; ++i) {
        node_init(&s->nodes[i], i);
        set_timer(s, &s->nodes[i]);
        trace(s, "START n%d deadline %d", i, s->nodes[i].election_deadline);
    }
    for (s->time = 0; s->time <= s->input.settings.end; ++s->time) {
        for (int i = 0; i < s->input.control_count; ++i)
            if (s->input.controls[i].time == s->time)
                control(s, &s->input.controls[i]);
        for (int i = 0; i < s->input.request_count; ++i)
            if (s->input.requests[i].scheduled == s->time)
                attempt(s, &s->input.requests[i]);
        Message incoming;
        while (network_arrival(&s->network, s->time, &incoming)) {
            if (network_deliver(&s->network, &incoming, s->nodes[incoming.destination].up))
                receive(s, &incoming);
            free(incoming.entries);
        }
        for (int i = 1; i <= s->input.settings.nodes; ++i)
            if (s->nodes[i].up)
                timers(s, &s->nodes[i]);
        end_tick(s);
    }
    if (s->gap_start >= 0)
        Gaps_append(&s->gaps, (Gap){s->gap_start, s->input.settings.end});
    fclose(s->trace);
    finish_statistics(s);
    FILE *file = output("leaders.txt");
    leader_lines(s, file);
    fclose(file);
    file = output("logs.txt");
    log_lines(s, file);
    fclose(file);
    file = output("state.txt");
    state_lines(s, file);
    fclose(file);
    file = output("safety.txt");
    safety_lines(s, file);
    fclose(file);
    for (int i = 1; i <= s->input.settings.nodes; ++i)
        free(s->nodes[i].log.items);
    network_free(&s->network);
    checker_free(&s->checker);
    free(s->elections.items);
    free(s->terms);
    free_lines(&s->timelines);
    free(s->gaps.items);
    free(s);
    return 0;
}
