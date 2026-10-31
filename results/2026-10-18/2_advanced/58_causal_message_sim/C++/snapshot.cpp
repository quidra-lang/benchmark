#include "simulation.hpp"
Snapshot new_snapshot(const std::string &name, int time, int count) {
    Snapshot out;
    out.name = name;
    out.start = time;
    out.records.resize(count);
    out.channels.resize(count * count);
    return out;
}
void record_state(Snapshot &snapshot, int process, const Process &state, int time,
                  const std::string &reason) {
    snapshot.records[process] = {true,          time,        reason,    state.balance,
                                 state.lamport, state.clock, state.hold};
}
void accept_marker(Snapshot &snapshot, int source, int destination, int time, int count) {
    snapshot.channels[source * count + destination].accepted = time;
    ++snapshot.accepted;
    if (snapshot.accepted == count * (count - 1))
        snapshot.complete = time;
}
Vector snapshot_cut(const Snapshot &snapshot) {
    Vector out;
    for (int p = 0; p < int(snapshot.records.size()); ++p)
        out.push_back(snapshot.records[p].clock[p]);
    return out;
}
CutDetails cut_details(const Vector &cut, const std::vector<Process> &processes,
                       const std::deque<Event> &events, const std::deque<Message> &messages,
                       const std::deque<Copy> &copies) {
    CutDetails out;
    for (int i = 0; i < int(copies.size()); ++i) {
        const Copy &copy = copies[i];
        const Message &message = messages[copy.message];
        const bool sent = events[message.send].local <= cut[copy.source],
                   received =
                       copy.received >= 0 && events[copy.received].local <= cut[copy.destination];
        if (received && !sent)
            out.orphans.push_back(i);
        if (sent && !received) {
            out.transit.push_back(i);
            out.money += message.amount;
        }
    }
    for (int p = 0; p < int(processes.size()); ++p)
        out.balances += balance_at_cut(processes[p], events, cut[p]);
    out.money += out.balances;
    return out;
}
