#include "raft.hpp"
void Checker::leader(const Node &node) {
    ++elected;
    auto found = leaders.find(node.term);
    if (found == leaders.end())
        leaders[node.term] = node.number;
    else if (found->second != node.number)
        ++violations[0];
    for (const auto &record : committed)
        if (record.first > node.last_index() || node.term_at(record.first) != record.second.first) {
            ++violations[1];
            break;
        }
}
void Checker::commit(int index, int term, int time) {
    committed.emplace(index, std::make_pair(term, time));
}
void Checker::apply(int index, const Entry &entry, const std::string &result) {
    ++applies;
    auto found = applied.find(index);
    if (found == applied.end())
        applied.emplace(index, Applied{entry, result});
    else if (!(found->second.entry == entry))
        ++violations[3];
}
void Checker::truncate(int first, const std::vector<Entry> &entries) {
    ++truncations;
    removed += int(entries.size());
    for (int i = 0; i < int(entries.size()); ++i) {
        auto found = committed.find(first + i);
        if (found != committed.end() && found->second.first == entries[i].term)
            ++violations[4];
    }
}
void Checker::check_logs(const std::vector<Node> &nodes) {
    ++log_checks;
    for (int a = 1; a < int(nodes.size()); ++a)
        for (int b = a + 1; b < int(nodes.size()); ++b) {
            ++pair_checks;
            int limit = std::min(nodes[a].last_index(), nodes[b].last_index()), greatest = 0;
            for (int k = limit; k >= 1; --k)
                if (nodes[a].term_at(k) == nodes[b].term_at(k)) {
                    greatest = k;
                    break;
                }
            for (int k = 1; k <= greatest; ++k)
                if (!(nodes[a].log[k - 1] == nodes[b].log[k - 1])) {
                    ++violations[2];
                    break;
                }
        }
}
Lines Checker::lines(int maximum_term) const {
    Lines out;
    const std::array<std::string, 5> names = {"ELECTION_SAFETY", "LEADER_COMPLETENESS",
                                              "LOG_MATCHING", "STATE_MACHINE_SAFETY",
                                              "COMMITTED_KEPT"};
    Lines details;
    line(details, "terms ", maximum_term, " leaders ", leaders.size(), " elected ", elected);
    line(details, "checks ", elected, " committed ", committed.size());
    line(details, "checks ", log_checks, " pairs ", pair_checks);
    line(details, "applies ", applies, " indices ", applied.size());
    line(details, "truncations ", truncations, " removed ", removed);
    for (int i = 0; i < 5; ++i)
        line(out, names[i], " ", violations[i] == 0 ? "OK" : "FAIL", " violations ", violations[i],
             " ", details[i]);
    return out;
}
