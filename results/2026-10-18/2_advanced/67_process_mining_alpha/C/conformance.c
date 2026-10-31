#include "mining.h"
static int name_order(const void *left, const void *right) { return strcmp(left, right); }
Net net_create(char (*places)[21], int np, char transitions[12][21], int nt, const char *initial,
               const char *final) {
    Net net = {0};
    net.place_count = np;
    net.transition_count = nt;
    net.places = malloc((size_t)np * sizeof(*places));
    memcpy(net.places, places, (size_t)np * sizeof(*places));
    memcpy(net.transitions, transitions, (size_t)nt * sizeof(transitions[0]));
    qsort(net.transitions, (size_t)nt, sizeof(transitions[0]), name_order);
    net.inputs = calloc((size_t)np * nt, 1);
    net.outputs = calloc((size_t)np * nt, 1);
    for (int p = 0; p < np; ++p) {
        if (!strcmp(net.places[p], initial))
            net.initial = p;
        if (!strcmp(net.places[p], final))
            net.final = p;
    }
    return net;
}
int transition_index(const Net *net, const char *name) {
    for (int t = 0; t < net->transition_count; ++t)
        if (!strcmp(net->transitions[t], name))
            return t;
    return -1;
}
void net_arc(Net *net, const char *from, const char *to) {
    int t = transition_index(net, from), input = t < 0;
    const char *place = input ? from : to;
    if (input)
        t = transition_index(net, to);
    for (int p = 0; p < net->place_count; ++p)
        if (!strcmp(net->places[p], place)) {
            unsigned char *arc = (input ? net->inputs : net->outputs) + t * net->place_count + p;
            if (!*arc) {
                *arc = 1;
                ++net->arc_count;
            }
            return;
        }
}
Net read_model(void) {
    FILE *in = fopen("input/model.txt", "r");
    char buffer[100], key[24], a[21], b[21], places[20][21], transitions[12][21], from[480][21],
        to[480][21], initial[21], final[21];
    int np = 0, nt = 0, na = 0;
    while (fgets(buffer, sizeof buffer, in)) {
        sscanf(buffer, "%23s %20s %20s", key, a, b);
        if (!strcmp(key, "PLACE"))
            strcpy(places[np++], a);
        else if (!strcmp(key, "TRANSITION"))
            strcpy(transitions[nt++], a);
        else if (!strcmp(key, "ARC")) {
            strcpy(from[na], a);
            strcpy(to[na++], b);
        } else if (!strcmp(key, "INITIAL"))
            strcpy(initial, a);
        else
            strcpy(final, a);
    }
    fclose(in);
    Net net = net_create(places, np, transitions, nt, initial, final);
    for (int i = 0; i < na; ++i)
        net_arc(&net, from[i], to[i]);
    return net;
}
int enabled(const Net *net, const unsigned char *marking, int t) {
    for (int p = 0; p < net->place_count; ++p)
        if (net->inputs[t * net->place_count + p] && !marking[p])
            return 0;
    return 1;
}
void fire(const Net *net, const unsigned char *before, int t, unsigned char *after) {
    for (int p = 0; p < net->place_count; ++p)
        after[p] = (unsigned char)(before[p] - net->inputs[t * net->place_count + p] +
                                   net->outputs[t * net->place_count + p]);
}
unsigned char *initial_marking(const Net *net) {
    unsigned char *out = calloc((size_t)net->place_count, 1);
    out[net->initial] = 1;
    return out;
}
unsigned char *final_marking(const Net *net) {
    unsigned char *out = calloc((size_t)net->place_count, 1);
    out[net->final] = 1;
    return out;
}
Replay replay_create(const Net *net) {
    Replay out = {0};
    size_t n = (size_t)net->place_count;
    out.place_missing = calloc(n, sizeof(I));
    out.place_remaining = calloc(n, sizeof(I));
    out.deviating = calloc(n, sizeof(I));
    out.wait_count = calloc(n, sizeof(I));
    out.wait_sum = calloc(n, sizeof(I));
    out.wait_max = calloc(n, sizeof(I));
    out.routes = calloc(n * (size_t)net->transition_count, sizeof(I));
    return out;
}
void replay_free(Replay *r) {
    free(r->place_missing);
    free(r->place_remaining);
    free(r->deviating);
    free(r->wait_count);
    free(r->wait_sum);
    free(r->wait_max);
    free(r->routes);
}
Fraction fitness(const Replay *r) {
    return plus(times(ratio(1, 2), minus(ratio(1, 1), ratio(r->missing, r->consumed))),
                times(ratio(1, 2), minus(ratio(1, 1), ratio(r->remaining, r->produced))));
}
