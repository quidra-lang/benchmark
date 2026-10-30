#include "raft.h"
static void ensure_entries(Checker *c, int index) {
    if ((size_t)index < c->entry_capacity)
        return;
    size_t old = c->entry_capacity, capacity = old ? old : 16;
    while (capacity <= (size_t)index)
        capacity *= 2;
    c->committed = realloc(c->committed, capacity * sizeof *c->committed);
    c->applied = realloc(c->applied, capacity * sizeof *c->applied);
    memset(c->committed + old, 0, (capacity - old) * sizeof *c->committed);
    memset(c->applied + old, 0, (capacity - old) * sizeof *c->applied);
    c->entry_capacity = capacity;
}
void checker_leader(Checker *c, const Node *node) {
    ++c->elected;
    if ((size_t)node->term >= c->leader_capacity) {
        size_t old = c->leader_capacity, capacity = old ? old : 16;
        while (capacity <= (size_t)node->term)
            capacity *= 2;
        c->leaders = realloc(c->leaders, capacity * sizeof *c->leaders);
        memset(c->leaders + old, 0, (capacity - old) * sizeof *c->leaders);
        c->leader_capacity = capacity;
    }
    if (c->leaders[node->term] == 0) {
        c->leaders[node->term] = node->number;
        ++c->leader_count;
    } else if (c->leaders[node->term] != node->number)
        ++c->violations[0];
    for (size_t i = 1; i < c->entry_capacity; ++i)
        if (c->committed[i].valid &&
            (i > (size_t)last_index(node) || term_at(node, (int)i) != c->committed[i].term)) {
            ++c->violations[1];
            break;
        }
}
void checker_commit(Checker *c, int index, int term, int time) {
    ensure_entries(c, index);
    if (!c->committed[index].valid) {
        c->committed[index] = (CommittedRecord){true, term, time};
        ++c->committed_count;
    }
}
void checker_apply(Checker *c, int index, const Entry *entry, const char *result) {
    ++c->applies;
    ensure_entries(c, index);
    AppliedRecord *record = &c->applied[index];
    if (!record->valid) {
        record->valid = true;
        record->entry = *entry;
        strcpy(record->result, result);
        ++c->applied_count;
    } else if (!entry_equal(&record->entry, entry))
        ++c->violations[3];
}
void checker_truncate(Checker *c, int first, const Entry *entries, int count) {
    ++c->truncations;
    c->removed += count;
    for (int i = 0; i < count; ++i) {
        int index = first + i;
        if ((size_t)index < c->entry_capacity && c->committed[index].valid &&
            c->committed[index].term == entries[i].term)
            ++c->violations[4];
    }
}
void checker_logs(Checker *c, const Node *nodes, int count) {
    ++c->log_checks;
    for (int a = 1; a <= count; ++a)
        for (int b = a + 1; b <= count; ++b) {
            ++c->pair_checks;
            int limit = last_index(&nodes[a]) < last_index(&nodes[b]) ? last_index(&nodes[a])
                                                                      : last_index(&nodes[b]),
                greatest = 0;
            for (int k = limit; k >= 1; --k)
                if (term_at(&nodes[a], k) == term_at(&nodes[b], k)) {
                    greatest = k;
                    break;
                }
            for (int k = 1; k <= greatest; ++k)
                if (!entry_equal(&nodes[a].log.items[k - 1], &nodes[b].log.items[k - 1])) {
                    ++c->violations[2];
                    break;
                }
        }
}
Lines checker_lines(const Checker *c, int maximum_term) {
    const char *names[5] = {"ELECTION_SAFETY", "LEADER_COMPLETENESS", "LOG_MATCHING",
                            "STATE_MACHINE_SAFETY", "COMMITTED_KEPT"};
    char details[5][128];
    snprintf(details[0], 128, "terms %d leaders %d elected %d", maximum_term, c->leader_count,
             c->elected);
    snprintf(details[1], 128, "checks %d committed %d", c->elected, c->committed_count);
    snprintf(details[2], 128, "checks %d pairs %d", c->log_checks, c->pair_checks);
    snprintf(details[3], 128, "applies %d indices %d", c->applies, c->applied_count);
    snprintf(details[4], 128, "truncations %d removed %d", c->truncations, c->removed);
    Lines out = {0};
    for (int i = 0; i < 5; ++i)
        add_line(&out, "%s %s violations %d %s", names[i], c->violations[i] ? "FAIL" : "OK",
                 c->violations[i], details[i]);
    return out;
}
void checker_free(Checker *c) {
    free(c->leaders);
    free(c->committed);
    free(c->applied);
}
