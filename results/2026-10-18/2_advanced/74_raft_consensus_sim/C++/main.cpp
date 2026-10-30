#include "raft.hpp"

struct Election {
    int time, node, term;
    std::string trigger;
    std::set<int> votes;
    std::optional<int> won;
};
struct Leader {
    int node, elected;
    std::set<int> votes;
    int appended = 1;
    std::optional<int> ended;
    std::string reason = "ACTIVE";
    int commit = 0;
};
static std::string node_name(std::optional<int> number) {
    return number ? "n" + std::to_string(*number) : "-";
}
static std::string node_set(const std::set<int> &nodes) {
    std::string out;
    for (int node : nodes) {
        if (!out.empty())
            out += ',';
        out += "n" + std::to_string(node);
    }
    return out.empty() ? "-" : out;
}
class Simulator {
    Input input;
    Settings settings;
    std::vector<Node> nodes;
    Network network;
    Minstd random;
    Checker checker;
    int time = 0;
    Lines trace, timelines;
    std::vector<Election> elections;
    std::map<int, Leader> leaders;
    std::vector<std::pair<int, int>> gaps;
    std::optional<int> gap_start;
    int leader_ticks = 0, multi_ticks = 0, maximum_term = 0, committed_count = 0;
    Store reference_state;
    std::map<int, Store> reference_states;
    std::array<int, 5> status_counts{};
    std::vector<int> latencies;
    std::map<std::string, std::pair<int, int>> key_counts;

    template <class... T> void log(const T &...values) {
        std::ostringstream stream;
        stream << time << ' ';
        (stream << ... << values);
        trace.push_back(stream.str());
    }
    bool majority(int count) const { return 2 * count > settings.nodes; }
    void set_timer(Node &node) {
        node.election_deadline =
            time + random.between(settings.election_min, settings.election_max);
    }
    Message message(const Node &node, int destination, Type type) const {
        return {type, node.number, destination, node.term};
    }
    void send_append(Node &node, int destination) {
        Message out = message(node, destination, Type::AE);
        out.previous = node.next[destination] - 1;
        out.previous_term = node.term_at(out.previous);
        int last = std::min(out.previous + settings.batch, node.last_index());
        out.entries.assign(node.log.begin() + out.previous, node.log.begin() + last);
        out.commit = node.commit;
        network.send(time, std::move(out));
    }
    void broadcast_append(Node &node) {
        for (int other = 1; other <= settings.nodes; ++other)
            if (other != node.number)
                send_append(node, other);
    }
    void end_leadership(Node &node, const std::string &reason) {
        Leader &record = leaders.at(node.term);
        record.ended = time;
        record.reason = reason;
        record.commit = node.commit;
        node.cancel_transfer();
    }
    void send_timeout_now(Node &node) {
        int destination = *node.transfer_target;
        log("TIMEOUTNOW n", node.number, " n", destination, " term ", node.term, " index ",
            node.last_index());
        node.transfer_sent = true;
        network.send(time, message(node, destination, Type::TN));
    }
    void start_transfer(Node &node, int destination) {
        if (!node.up || node.role != Role::Leader || node.transfer_target ||
            node.number == destination) {
            log("TRANSFER n", node.number, " n", destination, " ignored");
            return;
        }
        log("TRANSFER n", node.number, " n", destination, " start match ", node.match[destination],
            "/", node.last_index());
        node.transfer_target = destination;
        node.transfer_sent = false;
        node.transfer_deadline = time + settings.election_min;
        if (node.match[destination] == node.last_index())
            send_timeout_now(node);
        else
            send_append(node, destination);
    }
    void control(const Control &event) {
        if (event.kind == ControlKind::Crash) {
            Node &node = nodes[event.first];
            log("CRASH n", node.number, " ", role_name(node.role), " term ", node.term);
            if (node.role == Role::Leader)
                end_leadership(node, "CRASH");
            node.crash();
        } else if (event.kind == ControlKind::Restart) {
            Node &node = nodes[event.first];
            node.up = true;
            set_timer(node);
            log("RESTART n", node.number, " term ", node.term, " length ", node.last_index(),
                " deadline ", *node.election_deadline);
        } else if (event.kind == ControlKind::Partition) {
            network.partition(event.groups);
            std::ostringstream text;
            text << "PARTITION";
            for (const auto &group : event.groups)
                text << ' ' << node_set(std::set<int>(group.begin(), group.end()));
            log(text.str());
        } else if (event.kind == ControlKind::Heal) {
            network.heal();
            log("HEAL");
        } else
            start_transfer(nodes[event.first], event.second);
    }
    void attempt(Request &request) {
        ++request.attempts;
        int destination = request.destination, redirected = 0;
        std::string reason;
        for (;;) {
            Node &node = nodes[destination];
            if (!node.up) {
                reason = "down";
                break;
            }
            if (node.role == Role::Leader) {
                if (node.transfer_target) {
                    reason = "transfer";
                    break;
                }
                node.log.push_back({node.term, request.command, request.number});
                ++leaders.at(node.term).appended;
                request.accepted = std::make_pair(node.last_index(), node.term);
                request.scheduled.reset();
                log("ACCEPT r", request.number, " n", node.number, " index ", node.last_index(),
                    " term ", node.term);
                return;
            }
            if (!node.known_leader || redirected >= settings.nodes - 1) {
                reason = "noleader";
                break;
            }
            destination = *node.known_leader;
            log("REDIRECT r", request.number, " n", node.number, " n", destination);
            ++redirected;
            ++request.redirects;
        }
        if (request.attempts < settings.attempts) {
            request.destination = destination % settings.nodes + 1;
            request.scheduled = time + settings.retry;
            log("REJECT r", request.number, " n", destination, " ", reason, " retry n",
                request.destination, " at ", *request.scheduled);
        } else {
            request.abandoned = true;
            request.scheduled.reset();
            log("REJECT r", request.number, " n", destination, " ", reason, " giveup");
        }
    }
    void start_election(Node &node, const std::string &trigger) {
        ++node.term;
        node.role = Role::Candidate;
        node.voted_for = node.number;
        node.votes = {node.number};
        node.known_leader.reset();
        set_timer(node);
        ++node.stats.elections;
        node.election_record = int(elections.size());
        elections.push_back({time, node.number, node.term, trigger, node.votes, {}});
        log("ELECTION n", node.number, " term ", node.term, " last ", node.last_index(), "/",
            node.last_term(), " deadline ", *node.election_deadline);
        for (int other = 1; other <= settings.nodes; ++other)
            if (other != node.number) {
                Message out = message(node, other, Type::RV);
                out.last_index = node.last_index();
                out.last_term = node.last_term();
                network.send(time, std::move(out));
            }
    }
    void become_leader(Node &node) {
        node.role = Role::Leader;
        node.known_leader = node.number;
        for (int other = 1; other <= settings.nodes; ++other)
            if (other != node.number) {
                node.next[other] = node.last_index() + 1;
                node.match[other] = 0;
            }
        node.log.push_back({node.term, Command{}, 0});
        ++node.stats.leader_terms;
        elections[*node.election_record].won = time;
        checker.leader(node);
        leaders[node.term] = {node.number, time, node.votes};
        log("LEADER n", node.number, " term ", node.term, " votes ", node_set(node.votes), " noop ",
            node.last_index());
        broadcast_append(node);
        node.heartbeat_deadline = time + settings.heartbeat;
        node.quorum_deadline = time + settings.quorum;
        node.heard.clear();
    }
    void vote_request(Node &node, const Message &incoming) {
        std::string reason;
        if (incoming.term < node.term)
            reason = "term";
        else if (node.voted_for && *node.voted_for != incoming.source)
            reason = "voted";
        else if (!node.accepts_log(incoming.last_index, incoming.last_term))
            reason = "log";
        if (reason.empty()) {
            node.voted_for = incoming.source;
            ++node.stats.votes_granted;
            set_timer(node);
            log("VOTE n", node.number, " n", incoming.source, " term ", node.term, " deadline ",
                *node.election_deadline);
        } else
            log("DENY n", node.number, " n", incoming.source, " term ", node.term, " ", reason);
        Message out = message(node, incoming.source, Type::RVR);
        out.granted = reason.empty();
        network.send(time, std::move(out));
    }
    void vote_response(Node &node, const Message &incoming) {
        if (node.role != Role::Candidate || incoming.term != node.term || !incoming.granted)
            return;
        node.votes.insert(incoming.source);
        elections[*node.election_record].votes = node.votes;
        if (majority(int(node.votes.size())))
            become_leader(node);
    }
    void truncate(Node &node, int first) {
        std::vector<Entry> removed(node.log.begin() + first - 1, node.log.end());
        node.log.resize(first - 1);
        node.stats.truncated += int(removed.size());
        checker.truncate(first, removed);
        log("TRUNCATE n", node.number, " from ", first, " removed ", removed.size());
    }
    void advance_commit(Node &node, int index) {
        for (int k = node.commit + 1; k <= index; ++k)
            checker.commit(k, node.term_at(k), time);
        node.commit = index;
        int first = node.applied + 1;
        for (int k = first; k <= index; ++k) {
            const Entry &entry = node.log[k - 1];
            std::string result = apply_command(node.store, entry.command);
            ++node.stats.applies;
            checker.apply(k, entry, result);
        }
        node.applied = index;
        log("APPLY n", node.number, " ", first, "-", index);
    }
    void check_commit(Node &node) {
        for (int index = node.last_index(); index > node.commit; --index) {
            if (node.term_at(index) != node.term)
                return;
            int count = 1;
            for (int other = 1; other <= settings.nodes; ++other)
                if (other != node.number && node.match[other] >= index)
                    ++count;
            if (majority(count)) {
                log("COMMIT n", node.number, " ", node.commit + 1, "-", index, " term ", node.term);
                advance_commit(node, index);
                return;
            }
        }
    }
    void append_request(Node &node, const Message &incoming) {
        Message out = message(node, incoming.source, Type::AER);
        if (incoming.term < node.term) {
            network.send(time, std::move(out));
            return;
        }
        if (node.role == Role::Candidate) {
            node.role = Role::Follower;
            log("YIELD n", node.number, " term ", node.term, " n", incoming.source);
        }
        node.known_leader = incoming.source;
        set_timer(node);
        int previous = incoming.previous;
        if (previous > node.last_index() || node.term_at(previous) != incoming.previous_term) {
            ++node.stats.ae_fail;
            out.confirmed = previous > node.last_index() ? node.last_index() : previous - 1;
            network.send(time, std::move(out));
            return;
        }
        ++node.stats.ae_ok;
        for (int i = 0; i < int(incoming.entries.size()); ++i) {
            int index = previous + i + 1;
            const Entry &entry = incoming.entries[i];
            if (index <= node.last_index() && node.term_at(index) != entry.term)
                truncate(node, index);
            if (index > node.last_index()) {
                node.log.push_back(entry);
                ++node.stats.appended;
            }
        }
        int confirmed = previous + int(incoming.entries.size()),
            commit = std::min(incoming.commit, confirmed);
        if (commit > node.commit)
            advance_commit(node, commit);
        out.success = true;
        out.confirmed = confirmed;
        network.send(time, std::move(out));
    }
    void append_response(Node &node, const Message &incoming) {
        if (node.role != Role::Leader || incoming.term != node.term)
            return;
        int source = incoming.source;
        node.heard.insert(source);
        if (incoming.success) {
            node.match[source] = std::max(node.match[source], incoming.confirmed);
            node.next[source] = std::max(node.next[source], incoming.confirmed + 1);
            check_commit(node);
            if (node.transfer_target == source && !node.transfer_sent &&
                node.match[source] == node.last_index())
                send_timeout_now(node);
            else if (node.next[source] <= node.last_index())
                send_append(node, source);
        } else {
            node.next[source] = std::max(node.match[source] + 1,
                                         std::min(node.next[source] - 1, incoming.confirmed + 1));
            log("BACKTRACK n", node.number, " n", source, " next ", node.next[source]);
            send_append(node, source);
        }
    }
    void receive(const Message &incoming) {
        Node &node = nodes[incoming.destination];
        if (incoming.term > node.term) {
            Role previous = node.role;
            log("TERM n", node.number, " ", node.term, "->", incoming.term, " ",
                type_name(incoming.type), " n", incoming.source, " ", role_name(previous));
            if (previous == Role::Leader)
                end_leadership(node, "STEPDOWN");
            node.term = incoming.term;
            node.voted_for.reset();
            node.known_leader.reset();
            node.role = Role::Follower;
            if (previous == Role::Leader)
                set_timer(node);
        }
        switch (incoming.type) {
        case Type::RV:
            vote_request(node, incoming);
            break;
        case Type::RVR:
            vote_response(node, incoming);
            break;
        case Type::AE:
            append_request(node, incoming);
            break;
        case Type::AER:
            append_response(node, incoming);
            break;
        case Type::TN:
            if (incoming.term != node.term || node.role != Role::Follower)
                log("IGNORE n", node.number, " TN n", incoming.source, " term ", incoming.term);
            else
                start_election(node, "transfer");
            break;
        }
    }
    void timers(Node &node) {
        if (node.role == Role::Leader) {
            if (node.quorum_deadline == time) {
                if (!majority(1 + int(node.heard.size()))) {
                    log("STEPDOWN n", node.number, " term ", node.term, " heard ",
                        node_set(node.heard));
                    end_leadership(node, "QUORUM");
                    node.role = Role::Follower;
                    node.known_leader.reset();
                    set_timer(node);
                    return;
                }
                node.heard.clear();
                node.quorum_deadline = time + settings.quorum;
            }
            if (node.transfer_target && node.transfer_deadline == time) {
                log("TRANSFER n", node.number, " n", *node.transfer_target, " abort");
                node.cancel_transfer();
            }
            if (node.heartbeat_deadline == time) {
                broadcast_append(node);
                node.heartbeat_deadline = time + settings.heartbeat;
            }
        } else if (node.election_deadline == time)
            start_election(node, "timeout");
    }
    void end_tick() {
        checker.check_logs(nodes);
        int count = 0;
        for (int i = 1; i <= settings.nodes; ++i)
            if (nodes[i].up && nodes[i].role == Role::Leader) {
                ++nodes[i].stats.leader_ticks;
                ++count;
            }
        if (count > 0) {
            ++leader_ticks;
            multi_ticks += count >= 2;
            if (gap_start) {
                gaps.push_back({*gap_start, time - 1});
                gap_start.reset();
            }
        } else if (!gap_start)
            gap_start = time;
        if (time % settings.sample == 0) {
            std::ostringstream text;
            text << "TIMELINE " << time;
            for (int i = 1; i <= settings.nodes; ++i)
                text << ' ' << (nodes[i].up ? role_name(nodes[i].role)[0] : 'D') << nodes[i].term;
            timelines.push_back(text.str());
        }
    }
    void finish_statistics() {
        std::set<int> needed;
        for (int i = 1; i <= settings.nodes; ++i) {
            maximum_term = std::max(maximum_term, nodes[i].term);
            needed.insert(nodes[i].applied);
        }
        committed_count = int(checker.committed.size());
        reference_states[0] = {};
        for (int index = 1; index <= committed_count; ++index) {
            apply_command(reference_state, checker.applied.at(index).entry.command);
            if (needed.count(index))
                reference_states[index] = reference_state;
        }
        for (Request &request : input.requests) {
            ++key_counts[request.command.key].first;
            if (request.accepted) {
                auto [index, term] = *request.accepted;
                auto committed = checker.committed.find(index);
                if (committed != checker.committed.end() && committed->second.first == term) {
                    request.status = RequestStatus::Committed;
                    request.latency = committed->second.second - request.time;
                    request.result = checker.applied.at(index).result;
                    latencies.push_back(request.latency);
                    ++key_counts[request.command.key].second;
                } else {
                    bool retained = false;
                    for (int i = 1; i <= settings.nodes; ++i)
                        if (nodes[i].last_index() >= index && nodes[i].term_at(index) == term)
                            retained = true;
                    request.status = retained ? RequestStatus::Uncommitted : RequestStatus::Lost;
                }
            } else
                request.status = request.abandoned ? RequestStatus::Failed : RequestStatus::Waiting;
            ++status_counts[int(request.status)];
        }
    }
    Lines leader_lines() const {
        Lines out;
        std::map<int, std::vector<const Election *>> by_term;
        for (const Election &record : elections) {
            line(out, "ELECTION ", record.time, " n", record.node, " term ", record.term,
                 " trigger ", record.trigger, " votes ", record.votes.size(), " ",
                 record.won ? "WON " + std::to_string(*record.won) : "LOST");
            by_term[record.term].push_back(&record);
        }
        for (int term = 1; term <= maximum_term; ++term) {
            std::set<int> candidates;
            for (const Election *record : by_term[term])
                candidates.insert(record->node);
            auto found = leaders.find(term);
            if (found == leaders.end()) {
                line(out, "TERM ", term, " NONE candidates ", node_set(candidates));
                continue;
            }
            const Leader &record = found->second;
            int started = by_term[term][0]->time;
            int commit = record.ended ? record.commit : nodes[record.node].commit;
            line(out, "TERM ", term, " LEADER n", record.node, " elected ", record.elected,
                 " votes ", node_set(record.votes), " ended ",
                 record.ended ? std::to_string(*record.ended) : "-", " ", record.reason,
                 " appended ", record.appended, " commit ", commit, " candidates ",
                 node_set(candidates), " started ", started, " wait ", record.elected - started);
        }
        for (int i = 1; i <= settings.nodes; ++i) {
            const Statistics &s = nodes[i].stats;
            line(out, "NODE n", i, " elections ", s.elections, " leader_terms ", s.leader_terms,
                 " leader_ticks ", s.leader_ticks, " votes_granted ", s.votes_granted);
        }
        out.insert(out.end(), timelines.begin(), timelines.end());
        int longest = 0;
        for (auto gap : gaps) {
            int length = gap.second - gap.first + 1;
            longest = std::max(longest, length);
            line(out, "GAP ", gap.first, "-", gap.second, " length ", length);
        }
        line(out, "SUMMARY terms ", maximum_term, " leaders ", leaders.size(), " elections ",
             elections.size(), " leader_ticks ", leader_ticks, " multi_ticks ", multi_ticks,
             " ticks ", settings.end + 1, " gaps ", gaps.size(), " longest ", longest);
        return out;
    }
    Lines log_lines() const {
        Lines out;
        for (int i = 1; i <= settings.nodes; ++i) {
            const Node &node = nodes[i];
            line(out, "NODE n", i, " ", node.up ? role_name(node.role) : "DOWN", " term ",
                 node.term, " voted ", node_name(node.voted_for), " commit ", node.commit,
                 " applied ", node.applied, " length ", node.last_index());
            for (int k = 1; k <= node.last_index(); ++k) {
                const Entry &entry = node.log[k - 1];
                std::ostringstream text;
                text << k << ' ' << entry.term << ' ' << command_text(entry.command);
                if (entry.request)
                    text << " r" << entry.request;
                out.push_back(text.str());
            }
        }
        int limit = nodes[1].last_index(), prefix = 0;
        for (int i = 2; i <= settings.nodes; ++i)
            limit = std::min(limit, nodes[i].last_index());
        for (int k = 1; k <= limit; ++k) {
            bool agree = true;
            for (int i = 2; i <= settings.nodes; ++i)
                if (!(nodes[i].log[k - 1] == nodes[1].log[k - 1]))
                    agree = false;
            if (!agree)
                break;
            prefix = k;
        }
        line(out, "AGREE prefix ", prefix, " committed ", committed_count);
        for (int i = 1; i <= settings.nodes; ++i) {
            const Node &node = nodes[i];
            int common = 0;
            for (int k = 1; k <= std::min(node.last_index(), committed_count); ++k) {
                if (node.term_at(k) != checker.committed.at(k).first)
                    break;
                common = k;
            }
            const Statistics &s = node.stats;
            line(out, "DIFF n", i, " common ", common, " behind ", committed_count - common,
                 " extra ", node.last_index() - common, " ae_ok ", s.ae_ok, " ae_fail ", s.ae_fail,
                 " appended ", s.appended, " truncated ", s.truncated, " applies ", s.applies);
        }
        return out;
    }
    Lines state_lines() const {
        Lines out;
        for (int i = 1; i <= settings.nodes; ++i) {
            const Node &node = nodes[i];
            line(out, "NODE n", i, " ", node.up ? "UP" : "DOWN", " applied ", node.applied,
                 " keys ", node.store.size(), " replay ",
                 node.store == reference_states.at(node.applied) ? "match" : "mismatch");
            for (const auto &entry : node.store)
                line(out, entry.first, " ", entry.second);
        }
        for (const Request &request : input.requests) {
            std::ostringstream text;
            text << "REQUEST r" << request.number << " at " << request.time << " n"
                 << request.initial_destination << ' ' << command_text(request.command)
                 << " attempts " << request.attempts << " redirects " << request.redirects << ' '
                 << status_name(request.status);
            if (request.accepted) {
                text << " index " << request.accepted->first << " term "
                     << request.accepted->second;
                if (request.status == RequestStatus::Committed)
                    text << " latency " << request.latency << " result " << request.result;
            } else if (request.status == RequestStatus::Waiting)
                text << " next " << *request.scheduled;
            out.push_back(text.str());
        }
        for (const auto &entry : key_counts) {
            auto found = reference_state.find(entry.first);
            line(out, "KEY ", entry.first, " requests ", entry.second.first, " committed ",
                 entry.second.second, " final ",
                 found == reference_state.end() ? "missing" : std::to_string(found->second));
        }
        line(out, "REQUESTS total ", input.requests.size(), " committed ", status_counts[0],
             " uncommitted ", status_counts[1], " lost ", status_counts[2], " failed ",
             status_counts[3], " waiting ", status_counts[4]);
        int sum = 0, minimum = 0, maximum = 0;
        for (int latency : latencies)
            sum += latency;
        if (!latencies.empty()) {
            minimum = *std::min_element(latencies.begin(), latencies.end());
            maximum = *std::max_element(latencies.begin(), latencies.end());
        }
        line(out, "LATENCY count ", latencies.size(), " total ", sum, " min ", minimum, " max ",
             maximum);
        return out;
    }
    Lines safety_lines() const {
        Lines out = checker.lines(maximum_term);
        auto counters = [&](const std::string &prefix, const Counters &values) {
            std::ostringstream text;
            text << prefix;
            for (int i = 0; i < 7; ++i)
                text << ' ' << counter_names[i] << ' ' << values[i];
            out.push_back(text.str());
        };
        counters("MESSAGES", network.total);
        for (int i = 0; i < 5; ++i)
            counters("TYPE " + type_name(Type(i)), network.by_type[i]);
        for (int a = 1; a <= settings.nodes; ++a)
            for (int b = 1; b <= settings.nodes; ++b)
                if (a != b) {
                    const Link &link = network.links[a][b];
                    int dropped = 0;
                    for (int field = Partitioned; field <= DownLost; ++field)
                        dropped += link.stats[field];
                    line(out, "LINK n", a, "->n", b, " delay ", link.delay, " loss ", link.loss,
                         " sent ", link.stats[Sent], " delivered ", link.stats[Delivered],
                         " dropped ", dropped);
                }
        line(out, "DRAWS ", random.draws);
        out.push_back(std::any_of(checker.violations.begin(), checker.violations.end(),
                                  [](int count) { return count != 0; })
                          ? "RESULT UNSAFE"
                          : "RESULT SAFE");
        return out;
    }
    void write(const std::string &name, const Lines &lines) const {
        std::ofstream file("output/" + name);
        for (const std::string &text : lines)
            file << text << '\n';
    }

  public:
    explicit Simulator(Input data)
        : input(std::move(data)), settings(input.settings), network(settings.nodes),
          random{settings.seed} {
        for (int i = 0; i <= settings.nodes; ++i)
            nodes.emplace_back(i);
    }
    void run() {
        for (int i = 1; i <= settings.nodes; ++i) {
            set_timer(nodes[i]);
            log("START n", i, " deadline ", *nodes[i].election_deadline);
        }
        for (time = 0; time <= settings.end; ++time) {
            for (const Control &event : input.controls)
                if (event.time == time)
                    control(event);
            for (Request &request : input.requests)
                if (request.scheduled == time)
                    attempt(request);
            for (;;) {
                auto incoming = network.arrival(time);
                if (!incoming)
                    break;
                if (network.deliver(*incoming, nodes[incoming->destination].up))
                    receive(*incoming);
            }
            for (int i = 1; i <= settings.nodes; ++i)
                if (nodes[i].up)
                    timers(nodes[i]);
            end_tick();
        }
        if (gap_start)
            gaps.push_back({*gap_start, settings.end});
        finish_statistics();
        std::filesystem::create_directories("output");
        write("trace.txt", trace);
        write("leaders.txt", leader_lines());
        write("logs.txt", log_lines());
        write("state.txt", state_lines());
        write("safety.txt", safety_lines());
    }
};
int main() { Simulator(read_cluster()).run(); }
