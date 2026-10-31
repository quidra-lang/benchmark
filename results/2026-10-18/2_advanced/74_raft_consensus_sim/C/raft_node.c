#include "raft.h"
bool entry_equal(const Entry *a, const Entry *b) {
    return a->term == b->term && a->request == b->request && a->command.kind == b->command.kind &&
           a->command.value == b->command.value && !strcmp(a->command.key, b->command.key);
}
const char *command_text(const Command *command) {
    static char buffers[32][64];
    static unsigned index;
    char *out = buffers[index++ % 32];
    switch (command->kind) {
    case OP_NOOP:
        strcpy(out, "NOOP");
        break;
    case OP_SET:
        snprintf(out, 64, "SET %s %d", command->key, command->value);
        break;
    case OP_ADD:
        snprintf(out, 64, "ADD %s %d", command->key, command->value);
        break;
    case OP_DELETE:
        snprintf(out, 64, "DEL %s", command->key);
        break;
    case OP_GET:
        snprintf(out, 64, "GET %s", command->key);
        break;
    }
    return out;
}
int store_find(const Store *store, const char *key) {
    for (int i = 0; i < store->count; ++i)
        if (!strcmp(store->items[i].key, key))
            return i;
    return -1;
}
static int store_insert(Store *store, const char *key) {
    int index = 0;
    while (index < store->count && strcmp(store->items[index].key, key) < 0)
        ++index;
    memmove(store->items + index + 1, store->items + index,
            (size_t)(store->count - index) * sizeof *store->items);
    ++store->count;
    strcpy(store->items[index].key, key);
    store->items[index].value = 0;
    return index;
}
void apply_command(Store *store, const Command *command, char result[32]) {
    result[0] = 0;
    if (command->kind == OP_NOOP)
        return;
    int index = store_find(store, command->key);
    if (command->kind == OP_SET || command->kind == OP_ADD) {
        if (index < 0)
            index = store_insert(store, command->key);
        if (command->kind == OP_SET) {
            store->items[index].value = command->value;
            strcpy(result, "ok");
        } else {
            store->items[index].value += command->value;
            snprintf(result, 32, "%d", store->items[index].value);
        }
        return;
    }
    if (command->kind == OP_DELETE) {
        if (index < 0)
            strcpy(result, "missing");
        else {
            memmove(store->items + index, store->items + index + 1,
                    (size_t)(store->count - index - 1) * sizeof *store->items);
            --store->count;
            strcpy(result, "deleted");
        }
        return;
    }
    if (index < 0)
        strcpy(result, "missing");
    else
        snprintf(result, 32, "%d", store->items[index].value);
}
bool store_equal(const Store *a, const Store *b) {
    if (a->count != b->count)
        return false;
    for (int i = 0; i < a->count; ++i)
        if (strcmp(a->items[i].key, b->items[i].key) || a->items[i].value != b->items[i].value)
            return false;
    return true;
}
const char *role_name(Role role) {
    return role == LEADER ? "LEADER" : role == CANDIDATE ? "CANDIDATE" : "FOLLOWER";
}
void cancel_transfer(Node *node) {
    node->transfer_target = 0;
    node->transfer_deadline = -1;
    node->transfer_sent = false;
}
void reset_volatile(Node *node) {
    node->role = FOLLOWER;
    node->commit = node->applied = 0;
    node->store.count = 0;
    node->known_leader = 0;
    node->votes = 0;
    node->election_deadline = node->election_record = -1;
    memset(node->next, 0, sizeof node->next);
    memset(node->match, 0, sizeof node->match);
    node->heartbeat_deadline = node->quorum_deadline = -1;
    node->heard = 0;
    cancel_transfer(node);
}
void node_init(Node *node, int number) {
    memset(node, 0, sizeof *node);
    node->number = number;
    node->up = true;
    reset_volatile(node);
}
void node_crash(Node *node) {
    node->up = false;
    reset_volatile(node);
}
int last_index(const Node *node) { return (int)node->log.count; }
int last_term(const Node *node) {
    return node->log.count ? node->log.items[node->log.count - 1].term : 0;
}
int term_at(const Node *node, int index) { return index ? node->log.items[index - 1].term : 0; }
bool accepts_log(const Node *node, int index, int term) {
    int own_term = last_term(node);
    return term > own_term || (term == own_term && index >= last_index(node));
}
