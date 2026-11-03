#include "mining.h"
Counts directly_follows(const Log *log) {
    Counts out = {0};
    for (int i = 0; i < log->count; ++i) {
        const Trace *t = &log->entries[i];
        for (int j = 1; j < t->length; ++j)
            out.values[t->activity[j - 1]][t->activity[j]] += t->weight;
    }
    return out;
}
Relation basic_relation(const Counts *counts, int a, int b) {
    I forward = counts->values[a][b], backward = counts->values[b][a];
    return forward ? (backward ? PARALLEL : FORWARD) : (backward ? BACKWARD : UNRELATED);
}
const char *symbol(Relation r) {
    const char *values[4] = {"#", "->", "<-", "||"};
    return values[r];
}
void table(Lines *out, char ***rows, int count, int width) {
    Text heading = {0};
    text(&heading, "    ");
    for (int i = 1; i <= count; ++i)
        text(&heading, "%*d", width, i);
    line(out, "%s", heading.data);
    for (int i = 0; i < count; ++i) {
        Text row = {0};
        text(&row, "%4d", i + 1);
        for (int j = 0; j < count; ++j)
            text(&row, "%*s", width, rows[i][j]);
        line(out, "%s", row.data);
        free(row.data);
    }
    free(heading.data);
}
void footprint(Lines *out, char activities[12][21], const int *ids, int count, const Relations *r) {
    char ***rows = malloc((size_t)count * sizeof(char **));
    for (int i = 0; i < count; ++i) {
        line(out, "ACTIVITY %d %s", i + 1, activities[ids[i]]);
        rows[i] = malloc((size_t)count * sizeof(char *));
        for (int j = 0; j < count; ++j)
            rows[i][j] = (char *)symbol(r->values[ids[i]][ids[j]]);
    }
    table(out, rows, count, 4);
    for (int i = 0; i < count; ++i)
        free(rows[i]);
    free(rows);
}
