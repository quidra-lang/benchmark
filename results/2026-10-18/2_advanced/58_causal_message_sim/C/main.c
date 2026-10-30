#include "simulation.h"
typedef struct Allocation {
    void *pointer;
    struct Allocation *next;
} Allocation;
static Allocation *allocations;
static void release(void) {
    while (allocations) {
        Allocation *next = allocations->next;
        free(allocations->pointer);
        free(allocations);
        allocations = next;
    }
}
void *allocate(size_t count, size_t size) {
    void *pointer = calloc(count ? count : 1, size);
    Allocation *item = malloc(sizeof(*item));
    if (!pointer || !item)
        exit(EXIT_FAILURE);
    if (!allocations)
        atexit(release);
    item->pointer = pointer;
    item->next = allocations;
    allocations = item;
    return pointer;
}
void grow(void **data, int *capacity, size_t size) {
    int next = *capacity ? *capacity * 2 : 16;
    void *replacement = allocate((size_t)next, size);
    if (*data)
        memcpy(replacement, *data, (size_t)*capacity * size);
    *data = replacement;
    *capacity = next;
}
void append_id(Ids *ids, int value) {
    if (ids->count == ids->capacity)
        grow((void **)&ids->data, &ids->capacity, sizeof(int));
    ids->data[ids->count++] = value;
}
void remove_id(Ids *ids, int index) {
    memmove(ids->data + index, ids->data + index + 1,
            (size_t)(ids->count - index - 1) * sizeof(int));
    --ids->count;
}
static char *formatted(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int length = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = allocate((size_t)length + 1, 1);
    vsnprintf(out, (size_t)length + 1, pattern, args);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *out = formatted(pattern, args);
    va_end(args);
    return out;
}
void line(Lines *lines, const char *pattern, ...) {
    if (lines->count == lines->capacity)
        grow((void **)&lines->data, &lines->capacity, sizeof(char *));
    va_list args;
    va_start(args, pattern);
    lines->data[lines->count++] = formatted(pattern, args);
    va_end(args);
}
char *joined(const char *first, const char *second) { return format("%s%s", first, second); }
Lines read_lines(const char *path) {
    FILE *input = fopen(path, "rb");
    fseek(input, 0, SEEK_END);
    long size = ftell(input);
    rewind(input);
    char *text = allocate((size_t)size + 1, 1);
    fread(text, 1, (size_t)size, input);
    fclose(input);
    Lines out = {0};
    char *start = text;
    for (long i = 0; i < size; ++i)
        if (text[i] == '\n') {
            text[i] = '\0';
            line(&out, "%s", start);
            start = text + i + 1;
        }
    return out;
}
static Params parameters(void) {
    Params out = {0};
    Lines rows = read_lines("input/params.txt");
    for (int i = 0; i < rows.count; ++i) {
        char key[12];
        sscanf(rows.data[i], "%11s", key);
        const char *text = rows.data[i] + strlen(key) + 1;
        if (strcmp(key, "SEED") == 0)
            sscanf(text, "%lld", &out.seed);
        else if (strcmp(key, "END") == 0)
            sscanf(text, "%d", &out.end);
        else if (strcmp(key, "CUTCOUNT") == 0)
            sscanf(text, "%d", &out.cutcount);
        else if (strcmp(key, "COMPARE") == 0) {
            Compare value;
            sscanf(text, "%15s %15s", value.first, value.second);
            if (out.compare_count == out.compare_capacity)
                grow((void **)&out.compare, &out.compare_capacity, sizeof(Compare));
            out.compare[out.compare_count++] = value;
        } else if (strcmp(key, "CUT") == 0) {
            Cut value = {0};
            int n = 0, offset = 0, used;
            while (sscanf(text + offset, "%lld %n", &value.cut[n], &used) == 1) {
                offset += used;
                if (++n == 6)
                    break;
            }
            if (out.cut_count == out.cut_capacity)
                grow((void **)&out.cuts, &out.cut_capacity, sizeof(Cut));
            out.cuts[out.cut_count++] = value;
        } else if (strcmp(key, "PREDICATE") == 0) {
            I value;
            sscanf(text, "%lld", &value);
            if (out.predicate_count == out.predicate_capacity)
                grow((void **)&out.predicates, &out.predicate_capacity, sizeof(I));
            out.predicates[out.predicate_count++] = value;
        }
    }
    return out;
}
static bool earlier(Item a, Item b) {
    return a.time != b.time         ? a.time < b.time
           : a.process != b.process ? a.process < b.process
                                    : a.creation < b.creation;
}
void enqueue(Simulation *simulation, Item item) {
    item.creation = ++simulation->creation;
    if (simulation->queue_count == simulation->queue_capacity)
        grow((void **)&simulation->queue, &simulation->queue_capacity, sizeof(Item));
    int index = simulation->queue_count++;
    while (index > 0) {
        int parent = (index - 1) / 2;
        if (!earlier(item, simulation->queue[parent]))
            break;
        simulation->queue[index] = simulation->queue[parent];
        index = parent;
    }
    simulation->queue[index] = item;
}
static Item dequeue(Simulation *simulation) {
    Item first = simulation->queue[0], last = simulation->queue[--simulation->queue_count];
    if (simulation->queue_count) {
        int index = 0;
        while (2 * index + 1 < simulation->queue_count) {
            int child = 2 * index + 1;
            if (child + 1 < simulation->queue_count &&
                earlier(simulation->queue[child + 1], simulation->queue[child]))
                ++child;
            if (!earlier(simulation->queue[child], last))
                break;
            simulation->queue[index] = simulation->queue[child];
            index = child;
        }
        simulation->queue[index] = last;
    }
    return first;
}
static void timeline(Simulation *simulation, bool snapshot, int process, int index) {
    if (simulation->timeline_count == simulation->timeline_capacity)
        grow((void **)&simulation->timeline, &simulation->timeline_capacity, sizeof(Timeline));
    simulation->timeline[simulation->timeline_count++] =
        (Timeline){snapshot, process, index, simulation->time};
}
static int record_event(Simulation *simulation, int process, int type, int peer, int message,
                        int copy, const char *label, I amount) {
    Process *state = &simulation->processes[process];
    if (type == 4)
        receive_clock(
            state, process,
            &simulation->events[simulation->messages[simulation->copies[copy].message].send],
            simulation->topology.count);
    else
        local_clock(state, process);
    int index = simulation->event_count++;
    Event *event = &simulation->events[index];
    event->process = process;
    event->local = state->events.count + 1;
    event->time = simulation->time;
    event->type = type;
    event->peer = peer;
    event->message = message;
    event->copy = copy;
    event->lamport = state->lamport;
    event->balance = state->balance;
    event->amount = amount;
    memcpy(event->clock, state->clock, sizeof(event->clock));
    strcpy(event->label, label);
    append_id(&state->events, index);
    ++state->counts[type];
    if (state->balance < state->minimum)
        state->minimum = state->balance;
    timeline(simulation, false, process, index);
    return index;
}
static void send_packet(Simulation *simulation, int source, int destination, int copy,
                        int snapshot) {
    Packet packet = {0};
    packet.source = source;
    packet.destination = destination;
    packet.copy = copy;
    packet.snapshot = snapshot;
    packet.dispatch = simulation->time;
    const I *clock =
        snapshot >= 0
            ? NULL
            : simulation->events[simulation->messages[simulation->copies[copy].message].send].clock;
    dispatch(&simulation->topology.channels[source][destination], simulation->time, snapshot >= 0,
             clock, simulation->topology.count, &simulation->random, &packet.sequence,
             &packet.arrival);
    if (simulation->packet_count == simulation->packet_capacity)
        grow((void **)&simulation->packets, &simulation->packet_capacity, sizeof(Packet));
    int index = simulation->packet_count++;
    simulation->packets[index] = packet;
    if (copy >= 0)
        simulation->copies[copy].packet = index;
    Item item = {0};
    item.time = packet.arrival;
    item.process = destination;
    item.packet = index;
    enqueue(simulation, item);
}
static void record_snapshot(Simulation *simulation, int index, int process, const char *reason) {
    Snapshot *snapshot = simulation->snapshots[index];
    record_state(snapshot, process, &simulation->processes[process], simulation->time, reason);
    timeline(simulation, true, process, index);
    for (int destination = 0; destination < simulation->topology.count; ++destination)
        if (destination != process) {
            send_packet(simulation, process, destination, -1, index);
            snapshot->channels[process][destination].sent = simulation->time;
        }
}
static void initiate(Simulation *simulation, int process, const char *name) {
    int index = 0;
    while (index < simulation->snapshot_count && strcmp(simulation->snapshots[index]->name, name))
        ++index;
    if (index == simulation->snapshot_count) {
        if (simulation->snapshot_count == simulation->snapshot_capacity)
            grow((void **)&simulation->snapshots, &simulation->snapshot_capacity,
                 sizeof(Snapshot *));
        simulation->snapshots[simulation->snapshot_count++] = new_snapshot(name, simulation->time);
    }
    Snapshot *snapshot = simulation->snapshots[index];
    if (snapshot->records[process].present) {
        if (snapshot->ignored_count == snapshot->ignored_capacity)
            grow((void **)&snapshot->ignored, &snapshot->ignored_capacity, sizeof(Ignored));
        snapshot->ignored[snapshot->ignored_count++] = (Ignored){process, simulation->time};
    } else
        record_snapshot(simulation, index, process, "initiate");
}
static void perform(Simulation *simulation, int process, Action action, int sender) {
    Process *state = &simulation->processes[process];
    if (action.kind == A_LOCAL) {
        record_event(simulation, process, 0, -1, -1, -1, action.argument, 0);
        return;
    }
    if (action.kind == A_SNAPSHOT) {
        initiate(simulation, process, action.argument);
        return;
    }
    bool broadcast = action.kind == A_BROADCAST;
    int destination = broadcast ? -1 : action.destination == -2 ? sender : action.destination;
    I amount = action.kind == A_TRANSFER ? action.amount : 0;
    if (action.kind == A_TRANSFER && amount > state->balance) {
        ++state->refused;
        record_event(simulation, process, 1, destination, -1, -1, "", amount);
        return;
    }
    state->balance -= amount;
    state->out += amount;
    if (broadcast)
        ++state->broadcast[process];
    int index = simulation->message_count++;
    Message *message = &simulation->messages[index];
    message->source = process;
    message->amount = amount;
    message->broadcast = broadcast;
    strcpy(message->tag, broadcast                   ? action.argument
                         : action.kind == A_TRANSFER ? "transfer"
                                                     : action.tag);
    if (broadcast)
        memcpy(message->stamp, state->broadcast, sizeof(message->stamp));
    message->send =
        record_event(simulation, process, broadcast ? 3 : 2, destination, index, -1, "", 0);
    for (int target = 0; target < simulation->topology.count; ++target)
        if (broadcast ? target != process : target == destination) {
            int copy = simulation->copy_count++;
            simulation->copies[copy] = (Copy){.message = index,
                                              .source = process,
                                              .destination = target,
                                              .packet = -1,
                                              .received = -1,
                                              .delivery = -1};
            append_id(&message->copies, copy);
            send_packet(simulation, process, target, copy, -1);
        }
}
static void deliver(Simulation *simulation, int index) {
    Copy *copy = &simulation->copies[index];
    Message *message = &simulation->messages[copy->message];
    Process *state = &simulation->processes[copy->destination];
    if (message->broadcast)
        ++state->broadcast[copy->source];
    state->balance += message->amount;
    state->in += message->amount;
    copy->delivery = simulation->time;
    copy->received =
        record_event(simulation, copy->destination, 4, copy->source, copy->message, index, "", 0);
    append_id(&state->delivered, index);
    Script script = simulation->scripts[copy->destination];
    for (int i = 0; i < script.on_count; ++i)
        if (strcmp(script.on[i].tag, message->tag) == 0)
            perform(simulation, copy->destination, script.on[i].action, copy->source);
}
static bool can_deliver(const Simulation *simulation, int index) {
    Copy copy = simulation->copies[index];
    return deliverable(simulation->messages[copy.message].stamp,
                       simulation->processes[copy.destination].broadcast, copy.source,
                       simulation->topology.count);
}
static void accept(Simulation *simulation, int index) {
    Packet packet = simulation->packets[index];
    Process *state = &simulation->processes[packet.destination];
    ++state->next[packet.source];
    if (packet.snapshot >= 0) {
        Snapshot *snapshot = simulation->snapshots[packet.snapshot];
        if (!snapshot->records[packet.destination].present)
            record_snapshot(simulation, packet.snapshot, packet.destination,
                            format("marker %s", simulation->topology.names[packet.source]));
        accept_marker(snapshot, packet.source, packet.destination, simulation->time,
                      simulation->topology.count);
        return;
    }
    for (int i = 0; i < simulation->snapshot_count; ++i) {
        Snapshot *snapshot = simulation->snapshots[i];
        if (snapshot->records[packet.destination].present &&
            snapshot->channels[packet.source][packet.destination].accepted < 0)
            append_id(&snapshot->channels[packet.source][packet.destination].copies, packet.copy);
    }
    Copy *copy = &simulation->copies[packet.copy];
    Message *message = &simulation->messages[copy->message];
    if (simulation->raw || !message->broadcast) {
        deliver(simulation, packet.copy);
        return;
    }
    if (can_deliver(simulation, packet.copy)) {
        deliver(simulation, packet.copy);
        while (true) {
            int ready = -1;
            for (int i = 0; i < state->hold.count; ++i)
                if (can_deliver(simulation, state->hold.data[i])) {
                    ready = i;
                    break;
                }
            if (ready < 0)
                break;
            int candidate = state->hold.data[ready];
            remove_id(&state->hold, ready);
            deliver(simulation, candidate);
        }
    } else {
        copy->causal_wait = true;
        copy->missing =
            missing(message->stamp, state->broadcast, copy->source, simulation->topology.count);
        append_id(&state->hold, packet.copy);
    }
}
static void arrival(Simulation *simulation, int index) {
    Packet packet = simulation->packets[index];
    Process *state = &simulation->processes[packet.destination];
    if (simulation->raw)
        accept(simulation, index);
    else if (packet.sequence != state->next[packet.source]) {
        append_id(&state->reorder[packet.source], index);
        ++simulation->topology.channels[packet.source][packet.destination].buffered;
        if (packet.copy >= 0)
            simulation->copies[packet.copy].fifo_wait = true;
    } else {
        accept(simulation, index);
        while (true) {
            Ids *buffer = &state->reorder[packet.source];
            int found = -1;
            for (int i = 0; i < buffer->count; ++i)
                if (simulation->packets[buffer->data[i]].sequence == state->next[packet.source]) {
                    found = i;
                    break;
                }
            if (found < 0)
                break;
            int following = buffer->data[found];
            remove_id(buffer, found);
            accept(simulation, following);
        }
    }
    int held = state->hold.count;
    for (int p = 0; p < simulation->topology.count; ++p)
        held += state->reorder[p].count;
    if (held > state->max_held)
        state->max_held = held;
}
static Simulation *simulate(Topology topology, Script *scripts, Params *params, bool raw) {
    Simulation *out = allocate(1, sizeof(Simulation));
    out->topology = topology;
    out->scripts = scripts;
    out->params = params;
    out->raw = raw;
    out->random.state = params->seed;
    out->events = allocate(1000, sizeof(Event));
    out->messages = allocate(1000, sizeof(Message));
    out->copies = allocate(5000, sizeof(Copy));
    initialize(out);
    schedule_actions(out);
    while (out->queue_count && out->queue[0].time <= params->end) {
        Item item = dequeue(out);
        out->time = item.time;
        if (item.packet < 0)
            perform(out, item.process, item.action, -1);
        else
            arrival(out, item.packet);
    }
    return out;
}
static const char *yes(bool value) { return value ? "yes" : "no"; }
static const char *relation_name(int value) { return value > 0 ? "->" : value < 0 ? "<-" : "||"; }
static char *message_name(int index) { return format("m%d", index + 1); }
static char *event_name(const Simulation *s, int index) {
    Event event = s->events[index];
    return format("%s.%d", s->topology.names[event.process], event.local);
}
static char *copy_name(const Simulation *s, int index) {
    Copy copy = s->copies[index];
    return format("m%d->%s", copy.message + 1, s->topology.names[copy.destination]);
}
static char *process_names(const Simulation *s, Ids indices) {
    char *out = "";
    for (int i = 0; i < indices.count; ++i)
        out = joined(out, format("%s%s", i ? "," : "", s->topology.names[indices.data[i]]));
    return out;
}
static I initial(const Simulation *s) {
    I out = 0;
    for (int p = 0; p < s->topology.count; ++p)
        out += s->processes[p].initial;
    return out;
}
static int delivered_count(const Simulation *s) {
    int out = 0;
    for (int i = 0; i < s->copy_count; ++i)
        out += s->copies[i].received >= 0;
    return out;
}
static void save(const char *name, Lines lines) {
    FILE *output = fopen(format("output/%s", name), "wb");
    for (int i = 0; i < lines.count; ++i)
        fprintf(output, "%s\n", lines.data[i]);
    fclose(output);
}
static char *ranges(const Simulation *s, Ids path) {
    char *out = "";
    for (int i = 0; i < path.count;) {
        int j = i;
        while (j + 1 < path.count &&
               s->events[path.data[j + 1]].process == s->events[path.data[j]].process &&
               s->events[path.data[j + 1]].local == s->events[path.data[j]].local + 1)
            ++j;
        out = joined(out, format("%s%s", i ? " " : "", event_name(s, path.data[i])));
        if (j > i)
            out = joined(out, format("-%d", s->events[path.data[j]].local));
        i = j + 1;
    }
    return out;
}
static Lines trace_report(const Simulation *s) {
    static const char *types[] = {"LOCAL", "NOFUNDS", "SEND", "BCAST", "RECV"};
    Lines out = {0};
    int n = s->topology.count;
    for (int i = 0; i < s->event_count; ++i) {
        Event e = s->events[i];
        char *detail;
        if (e.type == 0)
            detail = e.label;
        else if (e.type == 1)
            detail = format("to %s amount %lld balance %lld", s->topology.names[e.peer], e.amount,
                            e.balance);
        else {
            Message m = s->messages[e.message];
            detail = message_name(e.message);
            if (e.type == 2)
                detail = joined(detail, format(" to %s", s->topology.names[e.peer]));
            else if (e.type == 4)
                detail = joined(detail, format(" from %s", s->topology.names[e.peer]));
            detail = joined(detail, format(" tag %s", m.tag));
            if (strcmp(m.tag, "transfer") == 0)
                detail = joined(detail, format(" amount %lld balance %lld", m.amount, e.balance));
        }
        line(&out, "%d t=%d %s %s %s L=%lld V=%s", i + 1, e.time, event_name(s, i), types[e.type],
             detail, e.lamport, vector_text(e.clock, n));
    }
    int delivered = delivered_count(s);
    line(&out, "SUMMARY events %d messages %d copies %d delivered %d undelivered %d draws %lld",
         s->event_count, s->message_count, s->copy_count, delivered, s->copy_count - delivered,
         s->random.draws);
    for (int p = 0; p < n; ++p) {
        Process state = s->processes[p];
        line(
            &out,
            "FINAL %s events %d L=%lld V=%s B=%s balance %lld in %lld out %lld refused %lld min %lld",
            s->topology.names[p], state.events.count, state.lamport, vector_text(state.clock, n),
            vector_text(state.broadcast, n), state.balance, state.in, state.out, state.refused,
            state.minimum);
    }
    for (int p = 0; p < n; ++p) {
        const int *count = s->processes[p].counts;
        line(&out, "COUNTS %s local %d nofunds %d send %d bcast %d recv %d", s->topology.names[p],
             count[0], count[1], count[2], count[3], count[4]);
    }
    return out;
}
static char *copy_details(const Simulation *s, int index) {
    Copy c = s->copies[index];
    Message m = s->messages[c.message];
    return format("m%d from %s %s tag %s sent %d", c.message + 1, s->topology.names[c.source],
                  m.broadcast ? "BCAST" : "P2P", m.tag, s->events[m.send].time);
}
static Ids broadcast_list(const Simulation *s, int process) {
    Ids out = {0};
    Ids events = s->processes[process].events;
    for (int i = 0; i < events.count; ++i) {
        Event e = s->events[events.data[i]];
        if (e.type == 3 || (e.type == 4 && s->messages[e.message].broadcast))
            append_id(&out, e.message);
    }
    return out;
}
typedef struct {
    char tag[9];
    I copies, delivered, latency, maximum;
} Tag;
static int compare_tag(const void *a, const void *b) {
    return strcmp(((const Tag *)a)->tag, ((const Tag *)b)->tag);
}
static Lines delivery_report(const Simulation *s) {
    Lines out = {0};
    int n = s->topology.count;
    Ids broadcasts[6] = {0};
    for (int p = 0; p < n; ++p) {
        line(&out, "PROCESS %s", s->topology.names[p]);
        Process state = s->processes[p];
        I counts[4] = {0}, total_wait = 0, max_wait = 0;
        for (int i = 0; i < state.delivered.count; ++i) {
            int index = state.delivered.data[i];
            Copy c = s->copies[index];
            Packet packet = s->packets[c.packet];
            int mode = c.fifo_wait + 2 * c.causal_wait;
            ++counts[mode];
            I wait = c.delivery - packet.arrival;
            total_wait += wait;
            if (wait > max_wait)
                max_wait = wait;
            char *mode_text = mode == 0   ? "direct"
                              : mode == 1 ? "fifo"
                                          : format("%s %s", mode == 2 ? "causal" : "fifo+causal",
                                                   process_names(s, c.missing));
            line(&out, "%d %s arrived %d delivered %d wait %lld %s", i + 1, copy_details(s, index),
                 packet.arrival, c.delivery, wait, mode_text);
        }
        for (int i = 0; i < s->copy_count; ++i) {
            Copy c = s->copies[i];
            if (c.destination == p && c.received < 0 &&
                s->packets[c.packet].arrival <= s->params->end)
                line(&out, "HELD %s arrived %d %s", copy_details(s, i),
                     s->packets[c.packet].arrival,
                     c.causal_wait ? format("causal %s", process_names(s, c.missing)) : "fifo");
        }
        for (int i = 0; i < s->copy_count; ++i) {
            Copy c = s->copies[i];
            if (c.destination == p && s->packets[c.packet].arrival > s->params->end)
                line(&out, "TRANSIT %s arrival %d", copy_details(s, i),
                     s->packets[c.packet].arrival);
        }
        line(
            &out,
            "TOTAL delivered %d direct %lld fifo %lld causal %lld both %lld wait %lld max_wait %lld max_held %d",
            state.delivered.count, counts[0], counts[1], counts[2], counts[3], total_wait, max_wait,
            state.max_held);
        broadcasts[p] = broadcast_list(s, p);
        char *list = "";
        for (int i = 0; i < broadcasts[p].count; ++i)
            list = joined(list, format(" m%d", broadcasts[p].data[i] + 1));
        line(&out, "BCASTS%s", *list ? list : " none");
    }
    for (int source = 0; source < n; ++source)
        for (int destination = 0; destination < n; ++destination)
            if (source != destination) {
                Channel c = s->topology.channels[source][destination];
                line(
                    &out,
                    "CHANNEL %s->%s %s %s messages %d markers %d buffered %d max_delay %d entries %d",
                    s->topology.names[source], s->topology.names[destination],
                    c.fifo ? "FIFO" : "NONFIFO", delay_text(c), c.messages, c.markers, c.buffered,
                    c.max_delay, c.entries);
            }
    Tag *tags = allocate((size_t)s->message_count, sizeof(Tag));
    int tag_count = 0;
    for (int i = 0; i < s->copy_count; ++i) {
        Copy c = s->copies[i];
        Message m = s->messages[c.message];
        int t = 0;
        while (t < tag_count && strcmp(tags[t].tag, m.tag))
            ++t;
        if (t == tag_count)
            strcpy(tags[tag_count++].tag, m.tag);
        Tag *tag = &tags[t];
        ++tag->copies;
        if (c.received >= 0) {
            ++tag->delivered;
            I latency = c.delivery - s->events[m.send].time;
            tag->latency += latency;
            if (latency > tag->maximum)
                tag->maximum = latency;
        }
    }
    qsort(tags, (size_t)tag_count, sizeof(Tag), compare_tag);
    for (int i = 0; i < tag_count; ++i) {
        Tag t = tags[i];
        line(&out, "TAG %s copies %lld delivered %lld latency %lld max %lld", t.tag, t.copies,
             t.delivered, t.latency, t.maximum);
    }
    Ids messages = {0};
    for (int i = 0; i < s->message_count; ++i) {
        Message m = s->messages[i];
        if (!m.broadcast)
            continue;
        append_id(&messages, i);
        bool stable = true;
        int time = 0;
        for (int j = 0; j < m.copies.count; ++j) {
            Copy c = s->copies[m.copies.data[j]];
            stable = stable && c.received >= 0;
            if (c.delivery > time)
                time = c.delivery;
        }
        line(&out, "STABLE m%d %s tag %s sent %d stable %s", i + 1, s->topology.names[m.source],
             m.tag, s->events[m.send].time, stable ? format("%d", time) : "none");
    }
    I disagreements = 0;
    for (int i = 0; i < messages.count; ++i)
        for (int j = i + 1; j < messages.count; ++j) {
            int a = messages.data[i], b = messages.data[j];
            Ids earlier = {0}, later = {0};
            for (int p = 0; p < n; ++p) {
                int x = -1, y = -1;
                for (int k = 0; k < broadcasts[p].count; ++k) {
                    if (broadcasts[p].data[k] == a)
                        x = k;
                    if (broadcasts[p].data[k] == b)
                        y = k;
                }
                if (x >= 0 && y >= 0)
                    append_id(x < y ? &earlier : &later, p);
            }
            if (earlier.count && later.count) {
                ++disagreements;
                line(&out, "DISAGREE m%d m%d %s %s", a + 1, b + 1, process_names(s, earlier),
                     process_names(s, later));
            }
        }
    line(&out, "DISAGREEMENTS %lld", disagreements);
    return out;
}
static char *verdict(const Simulation *s, CutDetails details) {
    char *out = (char *)yes(details.orphans.count == 0);
    for (int i = 0; i < details.orphans.count; ++i)
        out = joined(out, format(" %s", copy_name(s, details.orphans.data[i])));
    return out;
}
static int compare_int(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b;
    return (x > y) - (x < y);
}
static Lines snapshot_report(const Simulation *s, const Simulation *raw) {
    Lines out = {0};
    int n = s->topology.count;
    for (int index = 0; index < s->snapshot_count; ++index) {
        Snapshot *snapshot = s->snapshots[index];
        line(&out, "SNAPSHOT %s started %d completed %d", snapshot->name, snapshot->start,
             snapshot->complete);
        I balances = 0, channel_money = 0;
        Ids recorded = {0}, pending = {0};
        for (int p = 0; p < n; ++p) {
            SnapshotRecord record = snapshot->records[p];
            balances += record.balance;
            char *list = "";
            for (int i = 0; i < record.pending.count; ++i) {
                int copy = record.pending.data[i];
                list = joined(list, format(" m%d", s->copies[copy].message + 1));
                append_id(&pending, copy);
            }
            line(&out, "RECORD %s t=%d %s balance %lld L=%lld V=%s pending%s", s->topology.names[p],
                 record.time, record.reason, record.balance, record.lamport,
                 vector_text(record.clock, n), *list ? list : " none");
        }
        for (int source = 0; source < n; ++source)
            for (int destination = 0; destination < n; ++destination)
                if (source != destination) {
                    SnapshotChannel channel = snapshot->channels[source][destination];
                    char *list = "";
                    for (int i = 0; i < channel.copies.count; ++i) {
                        int copy = channel.copies.data[i];
                        Message message = s->messages[s->copies[copy].message];
                        append_id(&recorded, copy);
                        channel_money += message.amount;
                        list = joined(list, format(" m%d", s->copies[copy].message + 1));
                        if (message.amount)
                            list = joined(list, format(":%lld", message.amount));
                    }
                    line(&out, "CHANNEL %s->%s marker %d %d state%s", s->topology.names[source],
                         s->topology.names[destination], channel.sent, channel.accepted,
                         *list ? list : " empty");
                }
        for (int i = 0; i < snapshot->ignored_count; ++i)
            line(&out, "IGNORED %s t=%d", s->topology.names[snapshot->ignored[i].process],
                 snapshot->ignored[i].time);
        I cut[6];
        snapshot_cut(snapshot, cut, n);
        CutDetails details = cut_details(s, cut);
        bool good = true;
        for (int p = 0; p < n; ++p)
            if (!less_equal(snapshot->records[p].clock, cut, n))
                good = false;
        line(&out, "CUT %s consistent %s vector %s", vector_text(cut, n), verdict(s, details),
             yes(good));
        Ids all = {0};
        for (int i = 0; i < recorded.count; ++i)
            append_id(&all, recorded.data[i]);
        for (int i = 0; i < pending.count; ++i)
            append_id(&all, pending.data[i]);
        qsort(all.data, (size_t)all.count, sizeof(int), compare_int);
        qsort(details.transit.data, (size_t)details.transit.count, sizeof(int), compare_int);
        bool match = all.count == details.transit.count;
        for (int i = 0; match && i < all.count; ++i)
            if (all.data[i] != details.transit.data[i])
                match = false;
        line(&out, "TRANSIT channels %d pending %d cut %d match %s", recorded.count, pending.count,
             details.transit.count, yes(match));
        line(&out, "MONEY balances %lld channels %lld total %lld initial %lld conserved %s",
             balances, channel_money, balances + channel_money, initial(s),
             yes(balances + channel_money == initial(s)));
    }
    for (int index = 0; index < raw->snapshot_count; ++index) {
        Snapshot *snapshot = raw->snapshots[index];
        I cut[6], money = 0;
        snapshot_cut(snapshot, cut, n);
        CutDetails details = cut_details(raw, cut);
        for (int p = 0; p < n; ++p) {
            money += snapshot->records[p].balance;
            for (int q = 0; q < n; ++q) {
                Ids channel = snapshot->channels[p][q].copies;
                for (int i = 0; i < channel.count; ++i)
                    money += raw->messages[raw->copies[channel.data[i]].message].amount;
            }
        }
        line(&out, "RAW %s completed %d cut %s consistent %s money %lld conserved %s",
             snapshot->name, snapshot->complete, vector_text(cut, n), verdict(raw, details), money,
             yes(money == initial(raw)));
    }
    return out;
}
static int find_event(const Simulation *s, const char *name) {
    char process[7];
    int local;
    const char *dot = strchr(name, '.');
    memcpy(process, name, (size_t)(dot - name));
    process[dot - name] = '\0';
    sscanf(dot + 1, "%d", &local);
    return s->processes[process_index(&s->topology, process)].events.data[local - 1];
}
static Ids longest_chain(const Simulation *s) {
    Ids out = {0};
    if (!s->event_count)
        return out;
    int current = 0;
    for (int i = 1; i < s->event_count; ++i)
        if (s->events[i].lamport > s->events[current].lamport)
            current = i;
    while (true) {
        append_id(&out, current);
        Event e = s->events[current];
        if (e.lamport <= 1)
            break;
        int sender = e.type == 4 ? s->messages[s->copies[e.copy].message].send : -1;
        current = sender >= 0 && s->events[sender].lamport == e.lamport - 1
                      ? sender
                      : s->processes[e.process].events.data[e.local - 2];
    }
    for (int i = 0; i < out.count / 2; ++i) {
        int value = out.data[i];
        out.data[i] = out.data[out.count - 1 - i];
        out.data[out.count - 1 - i] = value;
    }
    return out;
}
static Lines analysis_report(const Simulation *s, const Simulation *raw) {
    Lines out = {0};
    int n = s->topology.count;
    Ids *graph = graph_edges(s);
    for (int i = 0; i < s->params->compare_count; ++i) {
        Compare comparison = s->params->compare[i];
        int a = find_event(s, comparison.first), b = find_event(s, comparison.second);
        Event e = s->events[a], f = s->events[b];
        int rel = relation(e.clock, f.clock, n);
        Ids path = graph_path(a, b, graph, s->event_count);
        int graph_relation = path.count ? 1 : 0;
        if (!path.count) {
            path = graph_path(b, a, graph, s->event_count);
            if (path.count)
                graph_relation = -1;
        }
        line(&out, "COMPARE %s %s %s L=%lld,%lld graph %s agree %s", comparison.first,
             relation_name(rel), comparison.second, e.lamport, f.lamport,
             relation_name(graph_relation), yes(rel == graph_relation));
        if (path.count) {
            int messages = 0;
            for (int k = 1; k < path.count; ++k)
                messages += s->events[path.data[k]].process != s->events[path.data[k - 1]].process;
            line(&out, "PATH length %d messages %d %s", path.count, messages, ranges(s, path));
        }
        int indices[2] = {a, b};
        for (int k = 0; k < 2; ++k) {
            Event event = s->events[indices[k]];
            I future[6] = {0};
            for (int j = 0; j < s->event_count; ++j)
                if (s->events[j].clock[event.process] < event.local)
                    ++future[s->events[j].process];
            line(&out, "WINDOW %s past %s future %s", event_name(s, indices[k]),
                 vector_text(event.clock, n), vector_text(future, n));
        }
    }
    Concurrency counts = concurrency(s);
    I event_count = s->event_count;
    line(
        &out,
        "CONCURRENCY events %lld pairs %lld ordered %lld concurrent %lld same_lamport %lld inversions %lld",
        event_count, event_count * (event_count - 1) / 2, counts.ordered, counts.concurrent,
        counts.same, counts.inversions);
    for (int a = 0; a < n; ++a)
        for (int b = a + 1; b < n; ++b)
            line(&out, "PAIR %s %s %lld", s->topology.names[a], s->topology.names[b],
                 counts.pairs[a][b]);
    Ids chain = longest_chain(s);
    line(&out, "CHAIN length %d %s", chain.count, ranges(s, chain));
    Orders ordered = orders(s);
    for (int i = 0; i < ordered.race_count; ++i) {
        Violation v = ordered.races[i];
        Copy a = s->copies[v.first], b = s->copies[v.second];
        line(&out, "RACE %s m%d %s m%d %s", s->topology.names[v.process], a.message + 1,
             s->topology.names[a.source], b.message + 1, s->topology.names[b.source]);
    }
    line(&out, "RACES %d", ordered.race_count);
    for (int i = 0; i < ordered.violation_count; ++i) {
        Violation v = ordered.violations[i];
        Copy a = s->copies[v.first], b = s->copies[v.second];
        line(&out, "VIOLATION %s m%d %s overtook m%d %s", s->topology.names[v.process],
             a.message + 1, s->topology.names[a.source], b.message + 1,
             s->topology.names[b.source]);
    }
    line(&out, "VIOLATIONS causal %d fifo %lld", ordered.violation_count, ordered.fifo);
    Orders raw_ordered = orders(raw);
    line(&out, "RAW events %d delivered %d causal %d fifo %lld", raw->event_count,
         delivered_count(raw), raw_ordered.violation_count, raw_ordered.fifo);
    for (int i = 0; i < s->params->cut_count; ++i) {
        const I *cut = s->params->cuts[i].cut;
        CutDetails details = cut_details(s, cut);
        char *status = "consistent";
        if (details.orphans.count) {
            status = "inconsistent orphans";
            for (int j = 0; j < details.orphans.count; ++j)
                status = joined(status, format(" %s", copy_name(s, details.orphans.data[j])));
        }
        line(&out, "CUT %s %s transit %d money %lld initial %lld", vector_text(cut, n), status,
             details.transit.count, details.money, initial(s));
    }
    Enumeration cuts = enumerate_cuts(s);
    line(&out, "CUTCOUNT t=%d events %s product %lld consistent %lld", s->params->cutcount,
         vector_text(cuts.limits, n), cuts.product, cuts.consistent);
    char *levels = "LEVELS";
    for (int i = 0; i < cuts.level_count; ++i)
        levels = joined(levels, format(" %lld", cuts.levels[i]));
    line(&out, "%s", levels);
    for (int i = 0; i < s->params->predicate_count; ++i)
        line(&out, "PREDICATE transit>=%lld cuts %lld possibly %s definitely %s",
             s->params->predicates[i], cuts.predicates[i].cuts, yes(cuts.predicates[i].cuts > 0),
             yes(cuts.predicates[i].definite));
    return out;
}
static void write_at(char *row, int position, const char *text) {
    memcpy(row + position, text, strlen(text));
}
static char *trim_diagram(char *row, int length) {
    while (length > 0 && row[length - 1] == ' ')
        --length;
    row[length] = '\0';
    return row;
}
static char *diagram_header(const Simulation *s, char kind) {
    char *row = allocate(80, 1);
    memset(row, ' ', 79);
    row[4] = kind;
    int end = 5;
    for (int p = 0; p < s->topology.count; ++p) {
        int position = 6 + 8 * p;
        write_at(row, position, s->topology.names[p]);
        end = position + (int)strlen(s->topology.names[p]);
    }
    return trim_diagram(row, end);
}
static char *diagram_line(const Simulation *s, int process, int value, int type, int message,
                          int source, const char *snapshot) {
    char *row = allocate(80, 1);
    memset(row, ' ', 79);
    char *prefix = format("%5d ", value);
    write_at(row, 0, prefix);
    int end = 7 + 8 * (s->topology.count - 1);
    for (int p = 0; p < s->topology.count; ++p)
        row[6 + 8 * p] = '|';
    int own = 6 + 8 * process;
    if (*snapshot) {
        row[own] = '#';
        write_at(row, own + 1, snapshot);
        int length = own + 1 + (int)strlen(snapshot);
        if (length > end)
            end = length;
    } else if (type == 0)
        row[own] = '*';
    else if (type == 1)
        row[own] = 'x';
    else if (type == 2 || type == 3) {
        row[own] = type == 2 ? 'S' : 'B';
        char *label = message_name(message);
        write_at(row, own + 1, label);
        int length = own + 1 + (int)strlen(label);
        if (length > end)
            end = length;
    } else {
        row[own] = 'R';
        int origin = 6 + 8 * source, a = origin < own ? origin : own,
            z = origin > own ? origin : own;
        for (int position = a + 1; position < z; ++position)
            row[position] = (position - 6) % 8 == 0 ? '+' : '-';
        if (origin < own)
            row[z - 1] = '>';
        else
            row[a + 1] = '<';
        char *label = message_name(message);
        write_at(row, a + 2, label);
        int length = a + 2 + (int)strlen(label);
        if (length > end)
            end = length;
    }
    return trim_diagram(row, end);
}
static const Simulation *diagram_sort;
static int compare_event(const void *a, const void *b) {
    Event x = diagram_sort->events[*(const int *)a], y = diagram_sort->events[*(const int *)b];
    if (x.lamport != y.lamport)
        return x.lamport < y.lamport ? -1 : 1;
    return x.process - y.process;
}
static Lines diagram_report(const Simulation *s) {
    Lines out = {0};
    line(&out, "%s", diagram_header(s, 't'));
    for (int i = 0; i < s->timeline_count; ++i) {
        Timeline t = s->timeline[i];
        if (t.snapshot)
            line(&out, "%s",
                 diagram_line(s, t.process, t.time, 0, -1, -1, s->snapshots[t.index]->name));
        else {
            Event e = s->events[t.index];
            line(&out, "%s", diagram_line(s, e.process, e.time, e.type, e.message, e.peer, ""));
        }
    }
    line(&out, "%s", diagram_header(s, 'L'));
    Ids ordered = {0};
    for (int i = 0; i < s->event_count; ++i)
        append_id(&ordered, i);
    diagram_sort = s;
    qsort(ordered.data, (size_t)ordered.count, sizeof(int), compare_event);
    for (int i = 0; i < ordered.count; ++i) {
        Event e = s->events[ordered.data[i]];
        line(&out, "%s", diagram_line(s, e.process, (int)e.lamport, e.type, e.message, e.peer, ""));
    }
    return out;
}
int main(void) {
    Topology topology = read_topology();
    Script *scripts = read_scripts(&topology);
    Params params = parameters();
    Simulation *main_run = simulate(topology, scripts, &params, false),
               *raw_run = simulate(topology, scripts, &params, true);
    mkdir("output", 0777);
    save("trace.txt", trace_report(main_run));
    save("deliveries.txt", delivery_report(main_run));
    save("snapshots.txt", snapshot_report(main_run, raw_run));
    save("analysis.txt", analysis_report(main_run, raw_run));
    save("diagram.txt", diagram_report(main_run));
    return 0;
}
