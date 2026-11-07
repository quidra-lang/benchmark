#include "raft.h"
const char *counter_names[7] = {"sent", "delivered", "inflight", "partition",
                                "rule", "loss",      "down"};
const char *type_name(Type type) {
    const char *names[5] = {"RV", "RVR", "AE", "AER", "TN"};
    return names[type];
}
static bool matches(const char *pattern, int node) {
    return pattern[0] == '*' || atoi(pattern) == node;
}
void network_init(Network *network, int nodes) {
    memset(network, 0, sizeof *network);
    network->nodes = nodes;
    FILE *file = fopen("input/network.txt", "r");
    char line[256], kind[16], first[8], second[8], type[8];
    int value, start, last;
    fgets(line, sizeof line, file);
    sscanf(line, "DEFAULT %d", &value);
    for (int a = 1; a <= nodes; ++a)
        for (int b = 1; b <= nodes; ++b)
            if (a != b)
                network->links[a][b].delay = value;
    while (fgets(line, sizeof line, file)) {
        sscanf(line, "%15s %7s %7s", kind, first, second);
        if (!strcmp(kind, "DELAY") || !strcmp(kind, "LOSS")) {
            sscanf(line, "%15s %7s %7s %d", kind, first, second, &value);
            for (int a = 1; a <= nodes; ++a)
                for (int b = 1; b <= nodes; ++b)
                    if (a != b && matches(first, a) && matches(second, b)) {
                        if (!strcmp(kind, "DELAY"))
                            network->links[a][b].delay = value;
                        else
                            network->links[a][b].loss = value;
                    }
        } else {
            sscanf(line, "%15s %7s %7s %7s %d %d", kind, first, second, type, &start, &last);
            int parsed = -1;
            for (int i = 0; i < 5; ++i)
                if (!strcmp(type, type_name((Type)i)))
                    parsed = i;
            for (int a = 1; a <= nodes; ++a)
                for (int b = 1; b <= nodes; ++b)
                    if (a != b && matches(first, a) && matches(second, b))
                        Drops_append(&network->links[a][b].drops, (Drop){parsed, start, last});
        }
    }
    fclose(file);
}
void network_partition(Network *network, const Group *groups, int count) {
    for (int i = 0; i < count; ++i)
        for (int j = 0; j < groups[i].count; ++j)
            network->groups[groups[i].nodes[j]] = i;
}
void network_heal(Network *network) { memset(network->groups, 0, sizeof network->groups); }
bool network_separated(const Network *network, int first, int second) {
    return network->groups[first] != network->groups[second];
}
void network_count(Network *network, const Message *message, Counter field, int amount) {
    network->total[field] += amount;
    network->by_type[message->type][field] += amount;
    network->links[message->source][message->destination].stats[field] += amount;
}
static bool before(const Envelope *a, const Envelope *b) {
    return a->arrival < b->arrival ||
           (a->arrival == b->arrival &&
            (a->source < b->source || (a->source == b->source && a->serial < b->serial)));
}
static void push(Network *network, Envelope value) {
    Queue_append(&network->queue, value);
    size_t i = network->queue.count - 1;
    while (i > 0) {
        size_t parent = (i - 1) / 2;
        if (!before(&value, &network->queue.items[parent]))
            break;
        network->queue.items[i] = network->queue.items[parent];
        i = parent;
    }
    network->queue.items[i] = value;
}
void network_send(Network *network, int time, Message message) {
    ++network->serial;
    network_count(network, &message, SENT, 1);
    Link *link = &network->links[message.source][message.destination];
    if (network_separated(network, message.source, message.destination)) {
        network_count(network, &message, PARTITIONED, 1);
        free(message.entries);
        return;
    }
    for (size_t i = 0; i < link->drops.count; ++i) {
        Drop drop = link->drops.items[i];
        if ((drop.type < 0 || drop.type == (int)message.type) && drop.first <= time &&
            time <= drop.last) {
            network_count(network, &message, RULE_LOST, 1);
            free(message.entries);
            return;
        }
    }
    ++link->passed;
    if (link->loss > 0 && link->passed % link->loss == 0) {
        network_count(network, &message, PERIODIC_LOST, 1);
        free(message.entries);
        return;
    }
    network_count(network, &message, INFLIGHT, 1);
    push(network, (Envelope){time + link->delay, message.source, network->serial, message});
}
bool network_arrival(Network *network, int time, Message *out) {
    Queue *q = &network->queue;
    if (q->count == 0 || q->items[0].arrival != time)
        return false;
    *out = q->items[0].message;
    Envelope value = q->items[--q->count];
    if (q->count > 0) {
        size_t i = 0;
        while (2 * i + 1 < q->count) {
            size_t child = 2 * i + 1;
            if (child + 1 < q->count && before(&q->items[child + 1], &q->items[child]))
                ++child;
            if (!before(&q->items[child], &value))
                break;
            q->items[i] = q->items[child];
            i = child;
        }
        q->items[i] = value;
    }
    network_count(network, out, INFLIGHT, -1);
    return true;
}
bool network_deliver(Network *network, const Message *message, bool destination_up) {
    if (!destination_up) {
        network_count(network, message, DOWN_LOST, 1);
        return false;
    }
    if (network_separated(network, message->source, message->destination)) {
        network_count(network, message, PARTITIONED, 1);
        return false;
    }
    network_count(network, message, DELIVERED, 1);
    return true;
}
void network_free(Network *network) {
    for (size_t i = 0; i < network->queue.count; ++i)
        free(network->queue.items[i].message.entries);
    free(network->queue.items);
    for (int a = 1; a <= network->nodes; ++a)
        for (int b = 1; b <= network->nodes; ++b)
            if (a != b)
                free(network->links[a][b].drops.items);
}
