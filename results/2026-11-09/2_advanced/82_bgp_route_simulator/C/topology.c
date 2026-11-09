#include "bgp.h"
#include <stdlib.h>
#include <string.h>
uint64_t ip(const char *text) {
    uint64_t value = 0;
    for (int i = 0; i < 4; ++i) {
        char *end;
        value = value * 256 + strtoul(text, &end, 10);
        text = *end ? end + 1 : end;
    }
    return value;
}
char *ip_text(uint64_t value) {
    return format_text("%llu.%llu.%llu.%llu", (unsigned long long)(value >> 24),
                       (unsigned long long)((value >> 16) & 255),
                       (unsigned long long)((value >> 8) & 255), (unsigned long long)(value & 255));
}
Prefix parse_prefix(const char *text) { return (Prefix){ip(text), atoi(strchr(text, '/') + 1)}; }
char *prefix_text(Prefix prefix) {
    char *address = ip_text(prefix.address), *result = format_text("%s/%d", address, prefix.length);
    free(address);
    return result;
}
bool contains(Prefix prefix, uint64_t address) {
    return (prefix.address >> (32 - prefix.length)) == (address >> (32 - prefix.length));
}
int prefix_compare(Prefix a, Prefix b) {
    if (a.address != b.address)
        return a.address < b.address ? -1 : 1;
    return (a.length > b.length) - (a.length < b.length);
}
Node *node_named(Topology *t, int number) {
    for (int i = 0; i < t->node_count; ++i)
        if (t->nodes[i].number == number)
            return &t->nodes[i];
    abort();
}
Link *link_named(Topology *t, const char *name) {
    for (int i = 0; i < t->link_count; ++i)
        if (strcmp(t->links[i].name, name) == 0)
            return &t->links[i];
    abort();
}
Node *other(const Link *link, const Node *node) { return node == link->a ? link->b : link->a; }
int role(const Link *link, const Node *node) { return link->peer ? 1 : node == link->a ? 0 : 2; }
Session *session_at(const Link *link, const Node *node) {
    return link->sessions[node == link->a ? 0 : 1];
}
const char *role_name(int role) {
    static const char *names[] = {"customer", "peer", "provider"};
    return names[role];
}
char direction_symbol(int role) { return "DPU"[role]; }
Link *between(Topology *t, int a, int b) {
    Node *node = node_named(t, a);
    for (int i = 0; i < node->session_count; ++i)
        if (other(node->sessions[i]->link, node)->number == b)
            return node->sessions[i]->link;
    abort();
}
int register_prefix(Topology *t, Prefix prefix) {
    for (int i = 0; i < t->prefix_count; ++i)
        if (prefix_compare(t->prefixes[i], prefix) == 0)
            return i;
    int index = t->prefix_count++;
    t->prefixes[index] = prefix;
    return index;
}
void order_prefixes(Topology *t) {
    for (int i = 0; i < t->prefix_count; ++i) {
        int j = i;
        while (j > 0 && prefix_compare(t->prefixes[t->prefix_order[j - 1]], t->prefixes[i]) > 0) {
            t->prefix_order[j] = t->prefix_order[j - 1];
            --j;
        }
        t->prefix_order[j] = i;
    }
}
void read_topology(Topology *t) {
    memset(t, 0, sizeof(*t));
    FILE *file = open_file("input/topology.txt", "r");
    char *line;
    while ((line = read_line(file))) {
        Words a = words(line);
        if (strcmp(a.items[0], "AS") == 0) {
            int index = t->node_count++;
            Node *node = &t->nodes[index];
            node->number = atoi(a.items[1]);
            node->index = index;
            node->router = ip(a.items[2]);
        } else if (strcmp(a.items[0], "LINK") == 0) {
            Link *link = &t->links[t->link_count];
            strcpy(link->name, a.items[1]);
            link->a = node_named(t, atoi(a.items[2]));
            link->b = node_named(t, atoi(a.items[3]));
            link->peer = strcmp(a.items[4], "P2P") == 0;
            link->delay = atoi(a.items[5]);
            link->mrai = atoi(a.items[6]);
            link->number = t->link_count++;
            link->up = true;
            for (int side = 0; side < 2; ++side) {
                Session *session = &t->session_storage[2 * link->number + side];
                session->owner = side == 0 ? link->a : link->b;
                session->link = link;
                session->timer = -1;
                link->sessions[side] = session;
                session->owner->sessions[session->owner->session_count++] = session;
            }
        } else {
            Attribute *attribute = attribute_new();
            attribute->origin = origin_rank(a.items[3]);
            attribute->communities = parse_communities(&a, 4);
            t->initial[t->initial_count++] =
                (Initial){node_named(t, atoi(a.items[1])),
                          register_prefix(t, parse_prefix(a.items[2])), attribute};
        }
        words_free(&a);
        free(line);
    }
    fclose(file);
    for (int i = 0; i < t->node_count; ++i) {
        int j = i;
        while (j > 0 && t->nodes[t->node_order[j - 1]].number > t->nodes[i].number) {
            t->node_order[j] = t->node_order[j - 1];
            --j;
        }
        t->node_order[j] = i;
    }
    for (int i = 0; i < t->node_count; ++i) {
        Node *node = &t->nodes[t->node_order[i]];
        for (int j = 0; j < node->session_count; ++j)
            t->sessions[t->session_count++] = node->sessions[j];
    }
}
