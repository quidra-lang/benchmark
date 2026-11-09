#include "simulation.h"
Snapshot *new_snapshot(const char *name, int time) {
    Snapshot *out = allocate(1, sizeof(Snapshot));
    strcpy(out->name, name);
    out->start = time;
    out->complete = -1;
    for (int p = 0; p < 6; ++p)
        for (int q = 0; q < 6; ++q)
            out->channels[p][q].sent = out->channels[p][q].accepted = -1;
    return out;
}
void record_state(Snapshot *snapshot, int process, const Process *state, int time,
                  const char *reason) {
    SnapshotRecord *record = &snapshot->records[process];
    record->present = true;
    record->time = time;
    record->reason = format("%s", reason);
    record->balance = state->balance;
    record->lamport = state->lamport;
    memcpy(record->clock, state->clock, sizeof(record->clock));
    for (int i = 0; i < state->hold.count; ++i)
        append_id(&record->pending, state->hold.data[i]);
}
void accept_marker(Snapshot *snapshot, int source, int destination, int time, int count) {
    snapshot->channels[source][destination].accepted = time;
    if (++snapshot->accepted == count * (count - 1))
        snapshot->complete = time;
}
void snapshot_cut(const Snapshot *snapshot, I *cut, int count) {
    for (int p = 0; p < count; ++p)
        cut[p] = snapshot->records[p].clock[p];
}
CutDetails cut_details(const Simulation *simulation, const I *cut) {
    CutDetails out = {0};
    for (int i = 0; i < simulation->copy_count; ++i) {
        Copy copy = simulation->copies[i];
        Message message = simulation->messages[copy.message];
        bool sent = simulation->events[message.send].local <= cut[copy.source],
             received = copy.received >= 0 &&
                        simulation->events[copy.received].local <= cut[copy.destination];
        if (received && !sent)
            append_id(&out.orphans, i);
        if (sent && !received) {
            append_id(&out.transit, i);
            out.money += message.amount;
        }
    }
    for (int p = 0; p < simulation->topology.count; ++p)
        out.balances += balance_at_cut(simulation, p, cut[p]);
    out.money += out.balances;
    return out;
}
