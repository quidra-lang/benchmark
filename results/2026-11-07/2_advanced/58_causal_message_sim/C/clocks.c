#include "simulation.h"
void local_clock(Process *process, int own) {
    ++process->lamport;
    ++process->clock[own];
}
void receive_clock(Process *process, int own, const Event *sent, int count) {
    process->lamport = (process->lamport > sent->lamport ? process->lamport : sent->lamport) + 1;
    for (int i = 0; i < count; ++i)
        if (sent->clock[i] > process->clock[i])
            process->clock[i] = sent->clock[i];
    ++process->clock[own];
}
bool less_equal(const I *first, const I *second, int count) {
    for (int i = 0; i < count; ++i)
        if (first[i] > second[i])
            return false;
    return true;
}
int relation(const I *first, const I *second, int count) {
    bool equal = true;
    for (int i = 0; i < count; ++i)
        if (first[i] != second[i])
            equal = false;
    if (equal)
        return 0;
    return less_equal(first, second, count) ? 1 : less_equal(second, first, count) ? -1 : 0;
}
bool deliverable(const I *stamp, const I *received, int source, int count) {
    for (int i = 0; i < count; ++i)
        if (i == source ? stamp[i] != received[i] + 1 : stamp[i] > received[i])
            return false;
    return true;
}
Ids missing(const I *stamp, const I *received, int source, int count) {
    Ids out = {0};
    for (int i = 0; i < count; ++i)
        if (stamp[i] > received[i] + (i == source))
            append_id(&out, i);
    return out;
}
char *vector_text(const I *value, int count) {
    char *out = "";
    for (int i = 0; i < count; ++i)
        out = joined(out, format("%s%lld", i ? "," : "", value[i]));
    return out;
}
