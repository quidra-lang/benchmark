#include "simulation.hpp"
void local_clock(I &lamport, Vector &clock, int process) {
    ++lamport;
    ++clock[process];
}
void receive_clock(I &lamport, Vector &clock, int process, I sent_lamport,
                   const Vector &sent_clock) {
    lamport = std::max(lamport, sent_lamport) + 1;
    for (int i = 0; i < int(clock.size()); ++i)
        clock[i] = std::max(clock[i], sent_clock[i]);
    ++clock[process];
}
bool less_equal(const Vector &a, const Vector &b) {
    for (int i = 0; i < int(a.size()); ++i)
        if (a[i] > b[i])
            return false;
    return true;
}
bool before(const Vector &a, const Vector &b) { return a != b && less_equal(a, b); }
int relation(const Vector &a, const Vector &b) { return before(a, b) ? 1 : before(b, a) ? -1 : 0; }
bool deliverable(const Vector &stamp, const Vector &received, int source) {
    for (int i = 0; i < int(stamp.size()); ++i)
        if (i == source ? stamp[i] != received[i] + 1 : stamp[i] > received[i])
            return false;
    return true;
}
Ids missing(const Vector &stamp, const Vector &received, int source) {
    Ids out;
    for (int i = 0; i < int(stamp.size()); ++i)
        if (stamp[i] > received[i] + int(i == source))
            out.push_back(i);
    return out;
}
std::string vector_text(const Vector &value) {
    std::string out;
    for (I number : value) {
        if (!out.empty())
            out += ',';
        out += std::to_string(number);
    }
    return out;
}
