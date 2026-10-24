#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static const char *keys[] = {"PROTOCOL", "FRAMES", "WINDOW", "SEQBITS", "TIMEOUT", "DELAY", "INTERVAL", "MAXTICKS", "DUPACK", "NAK", "BACKOFF", "CONGESTION", "UNSAFE", "TRACE", "RANDOM", "LOSEDATA", "LOSECTRL", "CORRUPTDATA", "CORRUPTCTRL", "DELAYDATA", "DELAYCTRL", "SNAPSHOT"};
typedef struct {
    char name[17], protocol[4], trace[9];
    int n, w, k, timeout, delay, interval, limit, dupack, nak, backoff, congestion, unsafe_window, random;
    int64_t seed; int loss, corruption;
    unsigned char lost_data[10000], lost_control[10000], corrupt_data[10000], corrupt_control[10000], snapshots[2001];
    int delay_data[10000], delay_control[10000];
} Config;
typedef struct { int arrival, number, value, outcome, nak; } Event;
typedef struct { char name[17], protocol[4], status[9]; int64_t delivered, data, completion; int order; } Result;
typedef struct {
    Config *c;
    int sr, modulus, tick, base, high, next, duration, timer, duplicates, receiver, cwnd, threshold, credit, nak_sent;
    int acknowledged[60], timers[60], tx[60], first[60], delivered_at[60], acked_at[60];
    int queue[60], queued, positions[64], payloads[64], buffered;
    Event data_events[2002], control_events[5000]; int data_count, control_count;
    int data, control, resent, naks, timeouts, fast, lost_data, lost_control, corrupt_data, corrupt_control;
    int delivered, errors, discarded, max_buffer, latency;
    int64_t random;
} Simulation;
static int mod(int a, int b) { int r = a % b; return r < 0 ? r + b : r; }
static int minimum(int a, int b) { return a < b ? a : b; }
static int maximum(int a, int b) { return a > b ? a : b; }
static void fixed(char *out, int64_t numerator, int64_t denominator, int digits) {
    int scale = digits == 2 ? 100 : 10;
    int64_t value = denominator ? numerator * scale / denominator : 0;
    sprintf(out, "%lld.%0*lld", (long long)(value / scale), digits, (long long)(value % scale));
}
static const char *stamp(int tick, char *out) { if (tick < 0) return "-"; sprintf(out, "%d", tick); return out; }
static int validate(Config *c, char raw[22][201], int *present, char *error) {
    for (int i = 0; i < 6; ++i) if (!present[i]) { sprintf(error, "missing key %s", keys[i]); return 0; }
    for (int i = 0; i < 22; ++i) {
        if (!present[i]) continue;
        char copy[201]; strcpy(copy, raw[i]);
        int valid = 1;
        if (i == 0) valid = !strcmp(copy, "SW") || !strcmp(copy, "GBN") || !strcmp(copy, "SR");
        else if (i >= 9 && i <= 12) valid = !strcmp(copy, "ON") || !strcmp(copy, "OFF");
        else if (i == 13) valid = !strcmp(copy, "ALL") || !strcmp(copy, "SENDER") || !strcmp(copy, "RECEIVER") || !strcmp(copy, "NONE");
        else if (i == 14) {
            long long seed, loss, corruption; sscanf(copy, "%lld %lld %lld", &seed, &loss, &corruption);
            valid = seed >= 1 && seed <= 2147483646LL && loss >= 0 && corruption >= 0 && loss + corruption <= 100;
        } else if (i >= 15) {
            unsigned char seen[10000] = {0};
            for (char *p = strtok(copy, " "); p; p = strtok(NULL, " ")) {
                int number = atoi(p), lower = i == 21 ? 0 : 1, upper = i == 21 ? 2000 : 9999;
                if (number < lower || number > upper) valid = 0;
                else if (seen[number]) valid = 0;
                else seen[number] = 1;
                if (i == 19 || i == 20) { int extra = atoi(strchr(p, ':') + 1); if (extra < 1 || extra > 50) valid = 0; }
            }
        } else {
            int number = atoi(copy), lower = i == 6 ? 0 : 1;
            int upper = i == 1 ? 60 : i == 2 ? 32 : i == 3 ? 6 : i == 4 ? 50 : i == 7 ? 2000 : 10;
            valid = number >= lower && number <= upper;
        }
        if (!valid) { sprintf(error, "bad value for %s", keys[i]); return 0; }
    }
    strcpy(c->protocol, raw[0]); strcpy(c->trace, present[13] ? raw[13] : "ALL");
    c->n = atoi(raw[1]); c->w = atoi(raw[2]); c->k = atoi(raw[3]); c->timeout = atoi(raw[4]); c->delay = atoi(raw[5]);
    c->interval = present[6] ? atoi(raw[6]) : 0; c->limit = present[7] ? atoi(raw[7]) : 1000; c->dupack = present[8] ? atoi(raw[8]) : 0;
    c->nak = present[9] && !strcmp(raw[9], "ON"); c->backoff = present[10] && !strcmp(raw[10], "ON");
    c->congestion = present[11] && !strcmp(raw[11], "ON"); c->unsafe_window = present[12] && !strcmp(raw[12], "ON");
    if (!strcmp(c->protocol, "SR") && present[8]) { strcpy(error, "DUPACK not supported for SR"); return 0; }
    int limit = !strcmp(c->protocol, "SW") ? 1 : !strcmp(c->protocol, "GBN") ? (1 << c->k) - 1 : 1 << (c->k - 1);
    if (c->w > limit && !(c->unsafe_window && strcmp(c->protocol, "SW"))) { sprintf(error, "window %d exceeds limit %d for %s", c->w, limit, c->protocol); return 0; }
    if (present[14]) {
        long long seed; sscanf(raw[14], "%lld %d %d", &seed, &c->loss, &c->corruption); c->seed = seed; c->random = 1;
    }
    for (int i = 15; i < 22; ++i) if (present[i]) {
        char copy[201]; strcpy(copy, raw[i]);
        for (char *p = strtok(copy, " "); p; p = strtok(NULL, " ")) {
            int number = atoi(p);
            if (i == 15) c->lost_data[number] = 1;
            if (i == 16) c->lost_control[number] = 1;
            if (i == 17) c->corrupt_data[number] = 1;
            if (i == 18) c->corrupt_control[number] = 1;
            if (i == 19) c->delay_data[number] = atoi(strchr(p, ':') + 1);
            if (i == 20) c->delay_control[number] = atoi(strchr(p, ':') + 1);
            if (i == 21) c->snapshots[number] = 1;
        }
    }
    for (int i = 1; i <= 9999; ++i) if (c->lost_data[i] && c->corrupt_data[i]) { sprintf(error, "data #%d both lost and corrupted", i); return 0; }
    for (int i = 1; i <= 9999; ++i) if (c->lost_control[i] && c->corrupt_control[i]) { sprintf(error, "control #%d both lost and corrupted", i); return 0; }
    return 1;
}
static int visible(const Simulation *s, const char *side) {
    return !strcmp(s->c->trace, "ALL") || !strcmp(s->c->trace, side) || !strcmp(side, "ALWAYS");
}
static int effective(const Simulation *s) { return s->c->congestion ? minimum(s->c->w, s->cwnd) : s->c->w; }
static int outcome(Simulation *s, int data, int number) {
    int result = 0; Config *c = s->c;
    if (c->random) {
        s->random = s->random * 48271 % 2147483647; int value = (int)(s->random % 100);
        result = value < c->loss ? 1 : value < c->loss + c->corruption ? 2 : 0;
    }
    if ((data ? c->lost_data : c->lost_control)[number]) result = 1;
    if ((data ? c->corrupt_data : c->corrupt_control)[number]) result = 2;
    return result;
}
static void send_control(Simulation *s, int nak, int value) {
    ++s->control; if (nak) ++s->naks;
    if (visible(s, "RECEIVER")) printf("%d %s a=%d #%d\n", s->tick, nak ? "NAK" : "ACK", value, s->control);
    Event e = {s->tick + s->c->delay + s->c->delay_control[s->control], s->control, value, outcome(s, 0, s->control), nak};
    s->control_events[s->control_count++] = e;
}
static void deliver(Simulation *s, int payload) {
    if (payload == s->receiver) {
        if (visible(s, "RECEIVER")) printf("%d DELIVER f=%d\n", s->tick, s->receiver);
        ++s->delivered;
        if (s->delivered_at[payload] < 0) s->delivered_at[payload] = s->tick;
        s->latency += s->tick - s->first[payload];
    } else {
        if (visible(s, "RECEIVER")) printf("%d DELIVER f=%d wrong=%d\n", s->tick, s->receiver, payload);
        ++s->errors;
    }
    ++s->receiver; s->nak_sent = 0;
}
static void discard(Simulation *s, int sequence) {
    ++s->discarded;
    if (visible(s, "RECEIVER")) printf("%d DISCARD seq=%d\n", s->tick, sequence);
}
static int buffered(const Simulation *s, int position) {
    for (int i = 0; i < s->buffered; ++i) if (s->positions[i] == position) return i;
    return -1;
}
static void receive(Simulation *s, Event e) {
    if (e.outcome) {
        if (e.outcome == 1) ++s->lost_data; else ++s->corrupt_data;
        if (visible(s, "RECEIVER")) printf("%d %s data #%d\n", s->tick, e.outcome == 1 ? "LOST" : "CORRUPT", e.number);
        return;
    }
    int sequence = e.value % s->modulus;
    if (visible(s, "RECEIVER")) printf("%d RECV seq=%d #%d\n", s->tick, sequence, e.number);
    if (!s->sr) {
        if (sequence == s->receiver % s->modulus) { deliver(s, e.value); send_control(s, 0, sequence); }
        else {
            discard(s, sequence);
            if (s->c->nak && !s->nak_sent) { send_control(s, 1, s->receiver % s->modulus); s->nak_sent = 1; }
            else if (s->receiver > 0) send_control(s, 0, (s->receiver - 1) % s->modulus);
        }
        return;
    }
    int offset = mod(sequence - s->receiver, s->modulus), position = s->receiver + offset;
    if (offset < s->c->w) {
        if (buffered(s, position) >= 0) { discard(s, sequence); send_control(s, 0, sequence); }
        else if (offset == 0) {
            deliver(s, e.value);
            int i;
            while ((i = buffered(s, s->receiver)) >= 0) {
                int payload = s->payloads[i]; --s->buffered;
                s->positions[i] = s->positions[s->buffered]; s->payloads[i] = s->payloads[s->buffered]; deliver(s, payload);
            }
            send_control(s, 0, sequence);
        } else {
            s->positions[s->buffered] = position; s->payloads[s->buffered++] = e.value;
            s->max_buffer = maximum(s->max_buffer, s->buffered);
            if (visible(s, "RECEIVER")) printf("%d BUFFER f=%d\n", s->tick, position);
            send_control(s, 0, sequence);
            if (s->c->nak && !s->nak_sent) { send_control(s, 1, s->receiver % s->modulus); s->nak_sent = 1; }
        }
    } else {
        discard(s, sequence);
        if (mod(s->receiver - sequence, s->modulus) <= s->c->w) send_control(s, 0, sequence);
    }
}
static int queued(const Simulation *s, int frame) {
    for (int i = 0; i < s->queued; ++i) if (s->queue[i] == frame) return i;
    return -1;
}
static void dequeue(Simulation *s, int index) {
    --s->queued; memmove(s->queue + index, s->queue + index + 1, (size_t)(s->queued - index) * sizeof(int));
}
static void go_back(Simulation *s) { s->next = s->base; s->timer = -1; s->duplicates = 0; }
static void increase(Simulation *s, int count) {
    if (!s->c->congestion) return;
    for (int i = 0; i < count && s->cwnd < s->c->w; ++i) {
        if (s->cwnd < s->threshold) ++s->cwnd;
        else if (++s->credit == s->cwnd) { ++s->cwnd; s->credit = 0; }
    }
}
static void decrease(Simulation *s, int timeout) {
    if (!s->c->congestion) return;
    s->threshold = maximum(s->cwnd / 2, 1); s->cwnd = timeout ? 1 : s->threshold; s->credit = 0;
}
static void cwnd_line(Simulation *s, int old_window, int old_threshold) {
    if (s->c->congestion && (old_window != s->cwnd || old_threshold != s->threshold) && visible(s, "SENDER"))
        printf("%d CWND %d ssthresh=%d\n", s->tick, s->cwnd, s->threshold);
}
static void control(Simulation *s, Event e) {
    const char *kind = e.nak ? "NAK" : "ACK";
    if (e.outcome) {
        if (e.outcome == 1) ++s->lost_control; else ++s->corrupt_control;
        if (visible(s, "SENDER")) printf("%d %s %s #%d\n", s->tick, e.outcome == 1 ? "LOST" : "CORRUPT", e.nak ? "nak" : "ack", e.number);
        return;
    }
    int old_window = s->cwnd, old_threshold = s->threshold, old_base = s->base;
    int frame = s->base + mod(e.value - s->base, s->modulus);
    int accepted = s->sr ? frame < s->high && !s->acknowledged[frame] : e.nak ? frame <= s->high : frame < s->high;
    if (accepted) {
        if (s->sr) {
            s->timers[frame] = -1;
            int at = queued(s, frame);
            if (e.nak) { if (at < 0) s->queue[s->queued++] = frame; }
            else {
                s->acknowledged[frame] = 1; if (at >= 0) dequeue(s, at);
                if (s->acked_at[frame] < 0) s->acked_at[frame] = s->tick;
                while (s->base < s->high && s->acknowledged[s->base]) ++s->base;
                increase(s, 1);
            }
        } else {
            s->base = frame + !e.nak; increase(s, s->base - old_base);
            for (int f = old_base; f < s->base; ++f) if (s->acked_at[f] < 0) s->acked_at[f] = s->tick;
        }
        if (s->base > old_base) { s->duration = s->c->timeout; s->duplicates = 0; }
        if (!s->sr) {
            if (e.nak) go_back(s);
            else { s->next = maximum(s->next, s->base); s->timer = s->base == s->next ? -1 : s->tick + s->duration; }
        }
        if (e.nak) decrease(s, 0);
        if (visible(s, "SENDER")) printf("%d GOT%s a=%d #%d base=%d\n", s->tick, kind, e.value, e.number, s->base);
    } else {
        if (visible(s, "SENDER")) printf("%d OLD%s a=%d #%d\n", s->tick, kind, e.value, e.number);
        if (!s->sr && !e.nak && s->c->dupack && s->base >= 1 && e.value == (s->base - 1) % s->modulus) {
            if (++s->duplicates == s->c->dupack) {
                ++s->fast;
                if (visible(s, "SENDER")) printf("%d FASTRETX f=%d\n", s->tick, s->base);
                go_back(s); decrease(s, 0);
            }
        }
    }
    cwnd_line(s, old_window, old_threshold);
}
static void timeout(Simulation *s, int frame) {
    int old_window = s->cwnd, old_threshold = s->threshold;
    ++s->timeouts;
    if (visible(s, "SENDER")) printf("%d TIMEOUT f=%d\n", s->tick, frame);
    if (s->sr) { s->timers[frame] = -1; if (queued(s, frame) < 0) s->queue[s->queued++] = frame; } else go_back(s);
    if (s->c->backoff) s->duration = minimum(s->duration * 2, s->c->timeout * 8);
    decrease(s, 1); cwnd_line(s, old_window, old_threshold);
}
static void send_data(Simulation *s, int frame) {
    ++s->data; int retry = s->tx[frame] > 0;
    if (retry) ++s->resent; else s->first[frame] = s->tick;
    ++s->tx[frame];
    if (visible(s, "SENDER")) printf("%d %s f=%d seq=%d #%d\n", s->tick, retry ? "RESEND" : "SEND", frame, frame % s->modulus, s->data);
    Event e = {s->tick + s->c->delay + s->c->delay_data[s->data], s->data, frame, outcome(s, 1, s->data), 0};
    s->data_events[s->data_count++] = e;
    if (s->sr) s->timers[frame] = s->tick + s->duration; else if (s->timer < 0) s->timer = s->tick + s->duration;
}
static void snapshot(Simulation *s) {
    char sender[61], receiver[61];
    for (int f = 0; f < s->c->n; ++f) {
        sender[f] = (s->sr ? s->acknowledged[f] : f < s->base) ? 'A' : (s->sr ? queued(s, f) >= 0 : s->next <= f && f < s->high) ? 'R' : (s->sr ? f < s->high : f < s->next) ? 'O' : f < s->base + effective(s) ? 'W' : '.';
        receiver[f] = f < s->receiver ? 'D' : s->sr && buffered(s, f) >= 0 ? 'B' : (s->sr ? f < s->receiver + s->c->w : f == s->receiver) ? 'W' : '.';
    }
    sender[s->c->n] = receiver[s->c->n] = 0;
    printf("%d SNAPSHOT sender=%s receiver=%s\n", s->tick, sender, receiver);
}
static Result simulate(Config *c, int order) {
    Simulation *s = calloc(1, sizeof(Simulation)); s->c = c; s->sr = !strcmp(c->protocol, "SR"); s->modulus = 1 << c->k;
    s->duration = c->timeout; s->timer = -1; s->cwnd = 1; s->threshold = c->w; s->random = c->seed;
    for (int f = 0; f < c->n; ++f) s->timers[f] = s->first[f] = s->delivered_at[f] = s->acked_at[f] = -1;
    printf("config: %s n=%d w=%d k=%d T=%d d=%d\n", c->protocol, c->n, c->w, c->k, c->timeout, c->delay);
    char dupack[20], random[64], trace[9];
    if (c->dupack) sprintf(dupack, "%d", c->dupack); else strcpy(dupack, "off");
    if (c->random) sprintf(random, "%lld/%d/%d", (long long)c->seed, c->loss, c->corruption); else strcpy(random, "off");
    strcpy(trace, c->trace); for (int i = 0; trace[i]; ++i) if (trace[i] >= 'A' && trace[i] <= 'Z') trace[i] += 'a' - 'A';
    printf("options: interval=%d limit=%d dupack=%s nak=%s backoff=%s congestion=%s unsafe=%s trace=%s random=%s\n", c->interval, c->limit, dupack, c->nak ? "on" : "off", c->backoff ? "on" : "off", c->congestion ? "on" : "off", c->unsafe_window ? "on" : "off", trace, random);
    int complete = 0;
    for (s->tick = 0; s->tick <= c->limit; ++s->tick) {
        for (int i = 0; i < s->data_count; ++i) if (s->data_events[i].arrival == s->tick) receive(s, s->data_events[i]);
        for (int i = 0; i < s->control_count; ++i) if (s->control_events[i].arrival == s->tick) control(s, s->control_events[i]);
        complete = s->base == c->n;
        if (!complete) {
            if (s->sr) { for (int f = s->base; f < s->high; ++f) if (s->timers[f] == s->tick) timeout(s, f); }
            else if (s->timer == s->tick) timeout(s, s->base);
            if (s->sr) {
                if (s->queued) { int frame = s->queue[0]; dequeue(s, 0); send_data(s, frame); }
                else if (s->high < c->n && s->high < s->base + effective(s) && s->high * c->interval <= s->tick) { int frame = s->high++; send_data(s, frame); }
            } else if (s->next < c->n && s->next < s->base + effective(s) && (s->next < s->high || s->next * c->interval <= s->tick)) {
                int frame = s->next++; s->high = maximum(s->high, s->next); send_data(s, frame);
            }
        }
        if (c->snapshots[s->tick]) snapshot(s);
        if (complete || s->tick == c->limit) { printf("%d %s\n", s->tick, complete ? "DONE" : "ABORT"); break; }
    }
    for (int f = 0; f < c->n; ++f) {
        char a[20], b[20], d[20];
        printf("frame %d: seq=%d tx=%d first=%s delivered=%s acked=%s\n", f, f % s->modulus, s->tx[f], stamp(s->first[f], a), stamp(s->delivered_at[f], b), stamp(s->acked_at[f], d));
    }
    printf("totals: data=%d resent=%d control=%d nak=%d timeouts=%d fastretx=%d\n", s->data, s->resent, s->control, s->naks, s->timeouts, s->fast);
    printf("channel: lost_data=%d lost_ctrl=%d corrupt_data=%d corrupt_ctrl=%d\n", s->lost_data, s->lost_control, s->corrupt_data, s->corrupt_control);
    printf("receiver: delivered=%d errors=%d discarded=%d max_buffer=%d\n", s->delivered, s->errors, s->discarded, s->max_buffer);
    char completion[30], goodput[40], efficiency[40], utilization[40], latency[40];
    if (complete) { sprintf(completion, "%d", s->tick); fixed(goodput, s->delivered, s->tick, 2); } else { strcpy(completion, "-"); strcpy(goodput, "-"); }
    fixed(efficiency, s->delivered * 100LL, s->data, 1); fixed(utilization, s->data * 100LL, s->tick + 1, 1);
    if (s->delivered) fixed(latency, s->latency, s->delivered, 2); else strcpy(latency, "-");
    printf("result: completion=%s goodput=%s efficiency=%s%% utilization=%s%% latency=%s\n", completion, goodput, efficiency, utilization, latency);
    Result result = {0}; strcpy(result.name, c->name); strcpy(result.protocol, c->protocol); strcpy(result.status, complete ? "complete" : "aborted");
    result.delivered = s->delivered; result.data = s->data; result.completion = s->tick; result.order = order;
    free(s); return result;
}
static int compare(const Result *a, const Result *b) {
    int64_t left = a->delivered * b->completion, right = b->delivered * a->completion;
    if (left != right) return left > right ? -1 : 1;
    left = a->delivered * b->data; right = b->delivered * a->data;
    if (left != right) return left > right ? -1 : 1;
    return a->order - b->order;
}
int main(void) {
    char line[256]; if (!fgets(line, sizeof(line), stdin)) return 0;
    int count = atoi(line); Result results[60];
    for (int scenario = 0; scenario < count; ++scenario) {
        Config *c = calloc(1, sizeof(Config));
        fgets(line, sizeof(line), stdin); sscanf(line, "SCENARIO %16s", c->name);
        char raw[22][201] = {{0}}, error[256] = ""; int present[22] = {0};
        while (fgets(line, sizeof(line), stdin)) {
            line[strcspn(line, "\r\n")] = 0; if (!strcmp(line, "END")) break;
            char *space = strchr(line, ' '); char *value = space ? space + 1 : line + strlen(line);
            if (space) *space = 0;
            int key = -1; for (int i = 0; i < 22; ++i) if (!strcmp(keys[i], line)) key = i;
            int values = *value ? 1 : 0; for (char *p = value; *p; ++p) if (*p == ' ') ++values;
            if (!*error) {
                if (key < 0) sprintf(error, "unknown key %s", line);
                else if (present[key]) sprintf(error, "duplicate key %s", line);
                else if (key == 14 ? values != 3 : key >= 15 ? values < 1 : values != 1) sprintf(error, "wrong number of values for %s", line);
            }
            if (key >= 0 && !present[key]) { present[key] = 1; strcpy(raw[key], value); }
        }
        printf("== %s ==\n", c->name);
        if (*error || !validate(c, raw, present, error)) {
            printf("error: %s\n", error); memset(&results[scenario], 0, sizeof(Result)); strcpy(results[scenario].name, c->name); strcpy(results[scenario].status, "invalid"); results[scenario].order = scenario;
        } else results[scenario] = simulate(c, scenario);
        free(c);
    }
    puts("== ranking =="); int order[60], completed = 0;
    for (int i = 0; i < count; ++i) if (!strcmp(results[i].status, "complete")) order[completed++] = i;
    for (int i = 0; i < completed; ++i) for (int j = i + 1; j < completed; ++j) if (compare(&results[order[j]], &results[order[i]]) < 0) { int t = order[i]; order[i] = order[j]; order[j] = t; }
    for (int i = 0; i < completed; ++i) {
        Result *r = &results[order[i]]; char goodput[40], efficiency[40]; fixed(goodput, r->delivered, r->completion, 2); fixed(efficiency, r->delivered * 100, r->data, 1);
        printf("%d. %s %s goodput=%s efficiency=%s%%\n", i + 1, r->name, r->protocol, goodput, efficiency);
    }
    for (int i = 0; i < count; ++i) if (strcmp(results[i].status, "complete")) printf("- %s %s\n", results[i].name, results[i].status);
    puts("== protocols =="); const char *protocols[] = {"SW", "GBN", "SR"};
    for (int p = 0; p < 3; ++p) {
        int runs = 0; int64_t delivered = 0, ticks = 0, data = 0;
        for (int i = 0; i < completed; ++i) {
            Result *r = &results[order[i]];
            if (!strcmp(r->protocol, protocols[p])) { ++runs; delivered += r->delivered; ticks += r->completion; data += r->data; }
        }
        if (runs) { char goodput[40], efficiency[40]; fixed(goodput, delivered, ticks, 2); fixed(efficiency, delivered * 100, data, 1); printf("%s: runs=%d goodput=%s efficiency=%s%%\n", protocols[p], runs, goodput, efficiency); }
    }
    return 0;
}
