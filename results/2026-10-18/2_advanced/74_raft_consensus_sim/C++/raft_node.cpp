#include "raft.hpp"
bool Command::operator==(const Command &other) const {
    return kind == other.kind && key == other.key && value == other.value;
}
bool Entry::operator==(const Entry &other) const {
    return term == other.term && command == other.command && request == other.request;
}
std::string command_text(const Command &command) {
    switch (command.kind) {
    case Operation::Noop:
        return "NOOP";
    case Operation::Set:
        return "SET " + command.key + " " + std::to_string(command.value);
    case Operation::Add:
        return "ADD " + command.key + " " + std::to_string(command.value);
    case Operation::Delete:
        return "DEL " + command.key;
    case Operation::Get:
        return "GET " + command.key;
    }
    return "";
}
std::string apply_command(Store &store, const Command &command) {
    if (command.kind == Operation::Noop)
        return "";
    if (command.kind == Operation::Set) {
        store[command.key] = command.value;
        return "ok";
    }
    if (command.kind == Operation::Add) {
        store[command.key] += command.value;
        return std::to_string(store[command.key]);
    }
    auto found = store.find(command.key);
    if (command.kind == Operation::Delete) {
        if (found == store.end())
            return "missing";
        store.erase(found);
        return "deleted";
    }
    return found == store.end() ? "missing" : std::to_string(found->second);
}
std::string role_name(Role role) {
    return role == Role::Leader ? "LEADER" : role == Role::Candidate ? "CANDIDATE" : "FOLLOWER";
}
void Node::cancel_transfer() {
    transfer_target.reset();
    transfer_deadline.reset();
    transfer_sent = false;
}
void Node::reset_volatile() {
    role = Role::Follower;
    commit = applied = 0;
    store.clear();
    known_leader.reset();
    votes.clear();
    election_deadline.reset();
    election_record.reset();
    next.fill(0);
    match.fill(0);
    heartbeat_deadline.reset();
    quorum_deadline.reset();
    heard.clear();
    cancel_transfer();
}
void Node::crash() {
    up = false;
    reset_volatile();
}
int Node::last_index() const { return int(log.size()); }
int Node::last_term() const { return log.empty() ? 0 : log.back().term; }
int Node::term_at(int index) const { return index == 0 ? 0 : log[index - 1].term; }
bool Node::accepts_log(int index, int term) const {
    return std::make_pair(term, index) >= std::make_pair(last_term(), last_index());
}
