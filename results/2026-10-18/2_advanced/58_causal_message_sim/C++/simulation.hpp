#ifndef SIMULATION_HPP
#define SIMULATION_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <fstream>
#include <functional>
#include <iomanip>
#include <map>
#include <numeric>
#include <optional>
#include <queue>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>
using I = std::int64_t;
using Vector = std::vector<I>;
using Ids = std::vector<int>;
using Lines = std::vector<std::string>;
struct Random {
    I state, draws = 0;
    I draw();
};
struct Channel {
    int source = 0, destination = 0, minimum = 0, maximum = 0, sequence = 0, last_arrival = 0,
        messages = 0, markers = 0, buffered = 0, max_delay = 0, entries = 0;
    bool fifo = false;
    Vector previous;
};
struct Topology {
    std::vector<std::string> names;
    std::vector<Channel> channels;
    int index(const std::string &name) const;
};
Topology read_topology();
std::pair<int, int> dispatch(Channel &channel, int time, bool marker, const Vector &clock,
                             Random &random);
std::string delay_text(const Channel &channel);
bool less_equal(const Vector &a, const Vector &b), before(const Vector &a, const Vector &b),
    deliverable(const Vector &stamp, const Vector &received, int source);
int relation(const Vector &a, const Vector &b);
void local_clock(I &lamport, Vector &clock, int process);
void receive_clock(I &lamport, Vector &clock, int process, I sent_lamport,
                   const Vector &sent_clock);
Ids missing(const Vector &stamp, const Vector &received, int source);
std::string vector_text(const Vector &value);
struct Action {
    std::string kind, argument, tag;
    I amount = 0;
};
struct Timed {
    int start, period;
    Action action;
};
struct Rule {
    std::string tag;
    Action action;
};
struct Script {
    I balance = 0;
    std::vector<Timed> at;
    std::vector<Rule> on;
};
struct Process {
    I initial = 0, balance = 0, lamport = 0, in = 0, out = 0, refused = 0, minimum = 0;
    Vector clock, broadcast;
    Ids events, delivered, hold;
    std::vector<int> next;
    std::vector<std::map<int, int>> reorder;
    int max_held = 0;
    std::array<int, 5> counts{};
};
std::vector<Script> read_scripts(const Topology &topology);
std::vector<Process> initialize(const std::vector<Script> &scripts);
struct Scheduled {
    int time, process;
    Action action;
};
std::vector<Scheduled> expand(const std::vector<Script> &scripts, int end);
struct Event {
    int process, local, time, type, peer = -1, message = -1, copy = -1;
    I lamport, balance, amount = 0;
    Vector clock;
    std::string label;
};
struct Message {
    int source, send;
    std::string tag;
    I amount;
    bool broadcast;
    Vector stamp;
    Ids copies;
};
struct Copy {
    int message, source, destination, packet = -1, received = -1, delivery = -1;
    bool fifo_wait = false, causal_wait = false;
    Ids missing;
};
struct Packet {
    int source, destination, sequence, dispatch, arrival, copy = -1, snapshot = -1;
};
struct SnapshotRecord {
    bool present = false;
    int time = 0;
    std::string reason;
    I balance = 0, lamport = 0;
    Vector clock;
    Ids pending;
};
struct SnapshotChannel {
    int sent = -1, accepted = -1;
    Ids copies;
};
struct Snapshot {
    std::string name;
    int start = 0, complete = -1, accepted = 0;
    std::vector<SnapshotRecord> records;
    std::vector<SnapshotChannel> channels;
    std::vector<std::pair<int, int>> ignored;
};
Snapshot new_snapshot(const std::string &name, int time, int count);
void record_state(Snapshot &snapshot, int process, const Process &state, int time,
                  const std::string &reason);
void accept_marker(Snapshot &snapshot, int source, int destination, int time, int count);
Vector snapshot_cut(const Snapshot &snapshot);
I balance_at_cut(const Process &process, const std::deque<Event> &events, I count);
struct CutDetails {
    Ids orphans, transit;
    I balances = 0, money = 0;
};
CutDetails cut_details(const Vector &cut, const std::vector<Process> &processes,
                       const std::deque<Event> &events, const std::deque<Message> &messages,
                       const std::deque<Copy> &copies);
using Graph = std::vector<Ids>;
Graph graph_edges(const std::deque<Event> &events, const std::deque<Copy> &copies,
                  const std::deque<Message> &messages, const std::vector<Process> &processes);
Ids graph_path(int source, int target, const Graph &graph);
struct Concurrency {
    I ordered = 0, concurrent = 0, same = 0, inversions = 0;
    std::vector<Vector> pairs;
};
Concurrency concurrency(const std::deque<Event> &events, int count);
struct Violation {
    int process, first, second;
};
struct Orders {
    std::vector<Violation> races, violations;
    I fifo = 0;
};
Orders orders(const std::vector<Process> &processes, const std::deque<Copy> &copies,
              const std::deque<Message> &messages, const std::deque<Event> &events);
struct Predicate {
    I cuts = 0;
    bool definite = false;
};
struct Enumeration {
    Vector limits, levels;
    I product = 1, consistent = 0;
    std::vector<Predicate> predicates;
};
Enumeration enumerate(const std::vector<Process> &processes, const std::deque<Event> &events,
                      int time, const Vector &thresholds);
template <typename... T> void line(Lines &out, const T &...values) {
    std::ostringstream text;
    (text << ... << values);
    out.push_back(text.str());
}
#endif
