#ifndef RAFT_HPP
#define RAFT_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <map>
#include <optional>
#include <queue>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Lines = std::vector<std::string>;
using Store = std::map<std::string, int>;
template <class... T> void line(Lines &out, const T &...values) {
    std::ostringstream stream;
    (stream << ... << values);
    out.push_back(stream.str());
}
struct Minstd {
    std::int64_t state;
    int draws = 0;
    int draw();
    int between(int minimum, int maximum);
};
enum class Operation { Noop, Set, Add, Delete, Get };
struct Command {
    Operation kind = Operation::Noop;
    std::string key;
    int value = 0;
    bool operator==(const Command &other) const;
};
std::string command_text(const Command &command),
    apply_command(Store &store, const Command &command);
struct Entry {
    int term;
    Command command;
    int request;
    bool operator==(const Entry &other) const;
};
enum class Role { Follower, Candidate, Leader };
std::string role_name(Role role);
struct Statistics {
    int elections = 0, leader_terms = 0, votes_granted = 0, leader_ticks = 0, ae_ok = 0,
        ae_fail = 0, appended = 0, truncated = 0, applies = 0;
};
struct Node {
    int number, term = 0;
    std::optional<int> voted_for;
    std::vector<Entry> log;
    bool up = true;
    Statistics stats;
    Role role = Role::Follower;
    int commit = 0, applied = 0;
    Store store;
    std::optional<int> known_leader;
    std::set<int> votes;
    std::optional<int> election_deadline, election_record;
    std::array<int, 8> next{}, match{};
    std::optional<int> heartbeat_deadline, quorum_deadline;
    std::set<int> heard;
    std::optional<int> transfer_target, transfer_deadline;
    bool transfer_sent = false;
    explicit Node(int number) : number(number) {};
    void cancel_transfer(), reset_volatile(), crash();
    int last_index() const, last_term() const, term_at(int index) const;
    bool accepts_log(int last_index, int last_term) const;
};
struct Settings {
    int nodes, election_min, election_max, heartbeat, batch, quorum, seed, end, retry, attempts,
        sample;
};
enum class ControlKind { Crash, Restart, Partition, Heal, Transfer };
struct Control {
    int time;
    ControlKind kind;
    int first = 0, second = 0;
    std::vector<std::vector<int>> groups;
};
enum class RequestStatus { Committed, Uncommitted, Lost, Failed, Waiting };
std::string status_name(RequestStatus status);
struct Request {
    int number, time, initial_destination;
    Command command;
    std::optional<int> scheduled;
    int destination, attempts = 0, redirects = 0;
    std::optional<std::pair<int, int>> accepted;
    bool abandoned = false;
    RequestStatus status = RequestStatus::Waiting;
    int latency = 0;
    std::string result;
};
struct Input {
    Settings settings;
    std::vector<Control> controls;
    std::vector<Request> requests;
};
Input read_cluster();
enum class Type { RV, RVR, AE, AER, TN };
std::string type_name(Type type);
struct Message {
    Type type;
    int source, destination, term;
    int last_index = 0, last_term = 0, previous = 0, previous_term = 0;
    std::vector<Entry> entries;
    int commit = 0;
    bool granted = false, success = false;
    int confirmed = 0;
};
enum Counter { Sent, Delivered, Inflight, Partitioned, RuleLost, PeriodicLost, DownLost };
using Counters = std::array<int, 7>;
extern const std::array<std::string, 7> counter_names;
struct Drop {
    std::optional<Type> type;
    int first, last;
};
struct Link {
    int delay = 0, loss = 0, passed = 0;
    std::vector<Drop> drops;
    Counters stats{};
};
struct Envelope {
    int arrival, source, serial;
    Message message;
};
struct Later {
    bool operator()(const Envelope &a, const Envelope &b) const;
};
struct Network {
    int nodes, serial = 0;
    std::array<std::array<Link, 8>, 8> links;
    std::array<int, 8> groups{};
    Counters total{};
    std::array<Counters, 5> by_type{};
    std::priority_queue<Envelope, std::vector<Envelope>, Later> queue;
    explicit Network(int count);
    void partition(const std::vector<std::vector<int>> &groups), heal();
    bool separated(int first, int second) const;
    void count(const Message &message, Counter field, int amount = 1),
        send(int time, Message message);
    std::optional<Message> arrival(int time);
    bool deliver(const Message &message, bool destination_up);
};
struct Applied {
    Entry entry;
    std::string result;
};
struct Checker {
    std::array<int, 5> violations{};
    std::map<int, int> leaders;
    std::map<int, std::pair<int, int>> committed;
    std::map<int, Applied> applied;
    int elected = 0, log_checks = 0, pair_checks = 0, applies = 0, truncations = 0, removed = 0;
    void leader(const Node &node), commit(int index, int term, int time),
        apply(int index, const Entry &entry, const std::string &result),
        truncate(int first, const std::vector<Entry> &entries),
        check_logs(const std::vector<Node> &nodes);
    Lines lines(int maximum_term) const;
};
#endif
