#include "simulation.hpp"
#include <filesystem>
struct Params {
    I seed = 0;
    int end = 0, cutcount = 0;
    std::vector<std::pair<std::string, std::string>> compare;
    std::vector<Vector> cuts;
    Vector predicates;
};
static Params parameters() {
    Params out;
    std::ifstream input("input/params.txt");
    std::string text;
    while (std::getline(input, text)) {
        std::istringstream row(text);
        std::string key;
        row >> key;
        if (key == "SEED")
            row >> out.seed;
        else if (key == "END")
            row >> out.end;
        else if (key == "CUTCOUNT")
            row >> out.cutcount;
        else if (key == "COMPARE") {
            std::string a, b;
            row >> a >> b;
            out.compare.emplace_back(a, b);
        } else if (key == "CUT") {
            Vector cut;
            I value;
            while (row >> value)
                cut.push_back(value);
            out.cuts.push_back(cut);
        } else if (key == "PREDICATE") {
            I value;
            row >> value;
            out.predicates.push_back(value);
        }
    }
    return out;
}
struct Item {
    int time, process;
    I creation;
    int packet = -1;
    Action action;
};
struct Later {
    bool operator()(const Item &a, const Item &b) const {
        return std::tie(a.time, a.process, a.creation) > std::tie(b.time, b.process, b.creation);
    }
};
struct Timeline {
    bool snapshot;
    int process, index, time;
};
class Simulation {
  public:
    Topology topology;
    std::vector<Script> scripts;
    Params params;
    bool raw;
    int n, time = 0;
    I creation = 0;
    Random random;
    std::vector<Process> processes;
    std::deque<Event> events;
    std::deque<Message> messages;
    std::deque<Copy> copies;
    std::deque<Packet> packets;
    std::deque<Snapshot> snapshots;
    std::map<std::string, int> snapshot_names;
    std::vector<Timeline> timeline;
    std::priority_queue<Item, std::vector<Item>, Later> queue;
    Simulation(Topology network, std::vector<Script> program, Params settings,
               bool comparison = false)
        : topology(std::move(network)), scripts(std::move(program)), params(std::move(settings)),
          raw(comparison), n(int(topology.names.size())), random{params.seed},
          processes(initialize(scripts)) {
        for (const Scheduled &scheduled : expand(scripts, params.end))
            queue.push({scheduled.time, scheduled.process, ++creation, -1, scheduled.action});
    }
    int record(int p, int type, int peer = -1, int message = -1, int copy = -1,
               const std::string &label = "", I amount = 0) {
        Process &state = processes[p];
        if (type == 4) {
            const Event &sent = events[messages[copies[copy].message].send];
            receive_clock(state.lamport, state.clock, p, sent.lamport, sent.clock);
        } else
            local_clock(state.lamport, state.clock, p);
        Event event{p,
                    int(state.events.size()) + 1,
                    time,
                    type,
                    peer,
                    message,
                    copy,
                    state.lamport,
                    state.balance,
                    amount,
                    state.clock,
                    label};
        const int index = int(events.size());
        events.push_back(event);
        state.events.push_back(index);
        ++state.counts[type];
        state.minimum = std::min(state.minimum, state.balance);
        timeline.push_back({false, p, index, time});
        return index;
    }
    void packet(int source, int destination, int copy, int snapshot) {
        const bool marker = snapshot >= 0;
        const Vector clock =
            marker ? Vector(n, 0) : events[messages[copies[copy].message].send].clock;
        const auto [sequence, arrival] =
            dispatch(topology.channels[source * n + destination], time, marker, clock, random);
        const int index = int(packets.size());
        packets.push_back({source, destination, sequence, time, arrival, copy, snapshot});
        if (!marker)
            copies[copy].packet = index;
        queue.push({arrival, destination, ++creation, index, {}});
    }
    void record_snapshot(int index, int p, const std::string &reason) {
        Snapshot &snapshot = snapshots[index];
        record_state(snapshot, p, processes[p], time, reason);
        timeline.push_back({true, p, index, time});
        for (int destination = 0; destination < n; ++destination)
            if (destination != p) {
                packet(p, destination, -1, index);
                snapshot.channels[p * n + destination].sent = time;
            }
    }
    void initiate(int p, const std::string &name) {
        auto found = snapshot_names.find(name);
        int index;
        if (found == snapshot_names.end()) {
            index = int(snapshots.size());
            snapshot_names[name] = index;
            snapshots.push_back(new_snapshot(name, time, n));
        } else
            index = found->second;
        if (snapshots[index].records[p].present)
            snapshots[index].ignored.emplace_back(p, time);
        else
            record_snapshot(index, p, "initiate");
    }
    void action(int p, const Action &action, int sender = -1) {
        Process &state = processes[p];
        const std::string &kind = action.kind;
        if (kind == "LOCAL") {
            record(p, 0, -1, -1, -1, action.argument);
            return;
        }
        if (kind == "SNAPSHOT") {
            initiate(p, action.argument);
            return;
        }
        const bool broadcast = kind == "BROADCAST";
        const int destination = broadcast                     ? -1
                                : action.argument == "SENDER" ? sender
                                                              : topology.index(action.argument);
        const I amount = kind == "TRANSFER" ? action.amount : 0;
        if (kind == "TRANSFER" && amount > state.balance) {
            ++state.refused;
            record(p, 1, destination, -1, -1, "", amount);
            return;
        }
        state.balance -= amount;
        state.out += amount;
        if (broadcast)
            ++state.broadcast[p];
        const int message = int(messages.size());
        messages.push_back({p,
                            -1,
                            broadcast            ? action.argument
                            : kind == "TRANSFER" ? "transfer"
                                                 : action.tag,
                            amount,
                            broadcast,
                            broadcast ? state.broadcast : Vector{},
                            {}});
        messages[message].send = record(p, broadcast ? 3 : 2, destination, message);
        for (int target = 0; target < n; ++target)
            if (broadcast ? target != p : target == destination) {
                const int index = int(copies.size());
                copies.push_back({message, p, target});
                messages[message].copies.push_back(index);
                packet(p, target, index, -1);
            }
    }
    void deliver(int index) {
        Copy &copy = copies[index];
        const Message &message = messages[copy.message];
        Process &state = processes[copy.destination];
        if (message.broadcast)
            ++state.broadcast[copy.source];
        state.balance += message.amount;
        state.in += message.amount;
        copy.delivery = time;
        copy.received = record(copy.destination, 4, copy.source, copy.message, index);
        state.delivered.push_back(index);
        for (const Rule &rule : scripts[copy.destination].on)
            if (rule.tag == message.tag)
                action(copy.destination, rule.action, copy.source);
    }
    bool can_deliver(int index) const {
        const Copy &copy = copies[index];
        return deliverable(messages[copy.message].stamp, processes[copy.destination].broadcast,
                           copy.source);
    }
    void accept(int index) {
        const Packet packet = packets[index];
        Process &state = processes[packet.destination];
        ++state.next[packet.source];
        if (packet.snapshot >= 0) {
            if (!snapshots[packet.snapshot].records[packet.destination].present)
                record_snapshot(packet.snapshot, packet.destination,
                                "marker " + topology.names[packet.source]);
            accept_marker(snapshots[packet.snapshot], packet.source, packet.destination, time, n);
            return;
        }
        for (Snapshot &snapshot : snapshots)
            if (snapshot.records[packet.destination].present &&
                snapshot.channels[packet.source * n + packet.destination].accepted < 0)
                snapshot.channels[packet.source * n + packet.destination].copies.push_back(
                    packet.copy);
        Copy &copy = copies[packet.copy];
        const Message &message = messages[copy.message];
        if (raw || !message.broadcast) {
            deliver(packet.copy);
            return;
        }
        if (can_deliver(packet.copy)) {
            deliver(packet.copy);
            while (true) {
                auto &hold = state.hold;
                const auto ready = std::find_if(hold.begin(), hold.end(), [&](int candidate) {
                    return can_deliver(candidate);
                });
                if (ready == hold.end())
                    break;
                const int candidate = *ready;
                hold.erase(ready);
                deliver(candidate);
            }
        } else {
            copy.causal_wait = true;
            copy.missing = missing(message.stamp, state.broadcast, copy.source);
            state.hold.push_back(packet.copy);
        }
    }
    void arrival(int index) {
        const Packet packet = packets[index];
        Process &state = processes[packet.destination];
        if (raw)
            accept(index);
        else if (packet.sequence != state.next[packet.source]) {
            state.reorder[packet.source][packet.sequence] = index;
            ++topology.channels[packet.source * n + packet.destination].buffered;
            if (packet.copy >= 0)
                copies[packet.copy].fifo_wait = true;
        } else {
            accept(index);
            while (true) {
                auto &buffer = state.reorder[packet.source];
                const auto found = buffer.find(state.next[packet.source]);
                if (found == buffer.end())
                    break;
                const int following = found->second;
                buffer.erase(found);
                accept(following);
            }
        }
        int held = int(state.hold.size());
        for (const auto &buffer : state.reorder)
            held += int(buffer.size());
        state.max_held = std::max(state.max_held, held);
    }
    void run() {
        while (!queue.empty() && queue.top().time <= params.end) {
            const Item item = queue.top();
            queue.pop();
            time = item.time;
            if (item.packet < 0)
                action(item.process, item.action);
            else
                arrival(item.packet);
        }
    }
    std::string event_name(int index) const {
        const Event &event = events[index];
        return topology.names[event.process] + "." + std::to_string(event.local);
    }
    std::string copy_name(int index) const {
        const Copy &copy = copies[index];
        return "m" + std::to_string(copy.message + 1) + "->" + topology.names[copy.destination];
    }
    std::string process_names(const Ids &indices) const {
        std::string out;
        for (int p : indices) {
            if (!out.empty())
                out += ',';
            out += topology.names[p];
        }
        return out;
    }
    I initial() const {
        I out = 0;
        for (const Process &process : processes)
            out += process.initial;
        return out;
    }
    int delivered() const {
        int out = 0;
        for (const Copy &copy : copies)
            out += copy.received >= 0;
        return out;
    }
};
static const char *yes(bool value) { return value ? "yes" : "no"; }
static const char *relation_name(int value) { return value > 0 ? "->" : value < 0 ? "<-" : "||"; }
static std::string message_name(int index) { return "m" + std::to_string(index + 1); }
static void save(const std::string &name, const Lines &lines) {
    std::ofstream output("output/" + name);
    for (const std::string &text : lines)
        output << text << '\n';
}
static std::string ranges(const Simulation &simulation, const Ids &path) {
    std::string out;
    for (std::size_t i = 0; i < path.size();) {
        std::size_t j = i;
        while (j + 1 < path.size() &&
               simulation.events[path[j + 1]].process == simulation.events[path[j]].process &&
               simulation.events[path[j + 1]].local == simulation.events[path[j]].local + 1)
            ++j;
        if (!out.empty())
            out += ' ';
        out += simulation.event_name(path[i]);
        if (j > i)
            out += "-" + std::to_string(simulation.events[path[j]].local);
        i = j + 1;
    }
    return out;
}
static Lines trace_report(const Simulation &s) {
    static const char *types[] = {"LOCAL", "NOFUNDS", "SEND", "BCAST", "RECV"};
    Lines out;
    for (int i = 0; i < int(s.events.size()); ++i) {
        const Event &event = s.events[i];
        std::ostringstream detail;
        if (event.type == 0)
            detail << event.label;
        else if (event.type == 1)
            detail << "to " << s.topology.names[event.peer] << " amount " << event.amount
                   << " balance " << event.balance;
        else {
            const Message &message = s.messages[event.message];
            detail << message_name(event.message);
            if (event.type == 2)
                detail << " to " << s.topology.names[event.peer];
            else if (event.type == 4)
                detail << " from " << s.topology.names[event.peer];
            detail << " tag " << message.tag;
            if (message.tag == "transfer")
                detail << " amount " << message.amount << " balance " << event.balance;
        }
        line(out, i + 1, " t=", event.time, " ", s.event_name(i), " ", types[event.type], " ",
             detail.str(), " L=", event.lamport, " V=", vector_text(event.clock));
    }
    line(out, "SUMMARY events ", s.events.size(), " messages ", s.messages.size(), " copies ",
         s.copies.size(), " delivered ", s.delivered(), " undelivered ",
         int(s.copies.size()) - s.delivered(), " draws ", s.random.draws);
    for (int p = 0; p < s.n; ++p) {
        const Process &state = s.processes[p];
        line(out, "FINAL ", s.topology.names[p], " events ", state.events.size(),
             " L=", state.lamport, " V=", vector_text(state.clock),
             " B=", vector_text(state.broadcast), " balance ", state.balance, " in ", state.in,
             " out ", state.out, " refused ", state.refused, " min ", state.minimum);
    }
    for (int p = 0; p < s.n; ++p) {
        const auto &count = s.processes[p].counts;
        line(out, "COUNTS ", s.topology.names[p], " local ", count[0], " nofunds ", count[1],
             " send ", count[2], " bcast ", count[3], " recv ", count[4]);
    }
    return out;
}
static std::string copy_details(const Simulation &s, int index) {
    const Copy &copy = s.copies[index];
    const Message &message = s.messages[copy.message];
    std::ostringstream out;
    out << message_name(copy.message) << " from " << s.topology.names[copy.source] << ' '
        << (message.broadcast ? "BCAST" : "P2P") << " tag " << message.tag << " sent "
        << s.events[message.send].time;
    return out.str();
}
static Ids broadcast_list(const Simulation &s, int p) {
    Ids out;
    for (int index : s.processes[p].events) {
        const Event &event = s.events[index];
        if (event.type == 3 || (event.type == 4 && s.messages[event.message].broadcast))
            out.push_back(event.message);
    }
    return out;
}
static Lines delivery_report(const Simulation &s) {
    Lines out;
    std::vector<Ids> broadcasts;
    for (int p = 0; p < s.n; ++p) {
        line(out, "PROCESS ", s.topology.names[p]);
        const Process &state = s.processes[p];
        std::array<I, 4> counts{};
        I total_wait = 0, max_wait = 0;
        for (int i = 0; i < int(state.delivered.size()); ++i) {
            const int index = state.delivered[i];
            const Copy &copy = s.copies[index];
            const Packet &packet = s.packets[copy.packet];
            const int mode = int(copy.fifo_wait) + 2 * int(copy.causal_wait);
            ++counts[mode];
            const I wait = copy.delivery - packet.arrival;
            total_wait += wait;
            max_wait = std::max(max_wait, wait);
            const std::string mode_text =
                mode == 0   ? "direct"
                : mode == 1 ? "fifo"
                            : std::string(mode == 2 ? "causal " : "fifo+causal ") +
                                  s.process_names(copy.missing);
            line(out, i + 1, " ", copy_details(s, index), " arrived ", packet.arrival,
                 " delivered ", copy.delivery, " wait ", wait, " ", mode_text);
        }
        for (int i = 0; i < int(s.copies.size()); ++i) {
            const Copy &copy = s.copies[i];
            if (copy.destination != p || copy.received >= 0 ||
                s.packets[copy.packet].arrival > s.params.end)
                continue;
            line(out, "HELD ", copy_details(s, i), " arrived ", s.packets[copy.packet].arrival, " ",
                 copy.causal_wait ? "causal " + s.process_names(copy.missing) : "fifo");
        }
        for (int i = 0; i < int(s.copies.size()); ++i) {
            const Copy &copy = s.copies[i];
            if (copy.destination == p && s.packets[copy.packet].arrival > s.params.end)
                line(out, "TRANSIT ", copy_details(s, i), " arrival ",
                     s.packets[copy.packet].arrival);
        }
        line(out, "TOTAL delivered ", state.delivered.size(), " direct ", counts[0], " fifo ",
             counts[1], " causal ", counts[2], " both ", counts[3], " wait ", total_wait,
             " max_wait ", max_wait, " max_held ", state.max_held);
        broadcasts.push_back(broadcast_list(s, p));
        std::string list;
        for (int message : broadcasts.back())
            list += " " + message_name(message);
        line(out, "BCASTS", list.empty() ? " none" : list);
    }
    for (int source = 0; source < s.n; ++source)
        for (int destination = 0; destination < s.n; ++destination)
            if (source != destination) {
                const Channel &channel = s.topology.channels[source * s.n + destination];
                line(out, "CHANNEL ", s.topology.names[source], "->", s.topology.names[destination],
                     " ", channel.fifo ? "FIFO" : "NONFIFO", " ", delay_text(channel), " messages ",
                     channel.messages, " markers ", channel.markers, " buffered ", channel.buffered,
                     " max_delay ", channel.max_delay, " entries ", channel.entries);
            }
    struct Tag {
        I copies = 0, delivered = 0, latency = 0, maximum = 0;
    };
    std::map<std::string, Tag> tags;
    for (const Copy &copy : s.copies) {
        const Message &message = s.messages[copy.message];
        Tag &tag = tags[message.tag];
        ++tag.copies;
        if (copy.received >= 0) {
            ++tag.delivered;
            const I latency = copy.delivery - s.events[message.send].time;
            tag.latency += latency;
            tag.maximum = std::max(tag.maximum, latency);
        }
    }
    for (const auto &[name, value] : tags)
        line(out, "TAG ", name, " copies ", value.copies, " delivered ", value.delivered,
             " latency ", value.latency, " max ", value.maximum);
    Ids broadcast_messages;
    for (int i = 0; i < int(s.messages.size()); ++i) {
        const Message &message = s.messages[i];
        if (!message.broadcast)
            continue;
        broadcast_messages.push_back(i);
        bool stable = true;
        int time = 0;
        for (int index : message.copies) {
            stable &= s.copies[index].received >= 0;
            time = std::max(time, s.copies[index].delivery);
        }
        line(out, "STABLE ", message_name(i), " ", s.topology.names[message.source], " tag ",
             message.tag, " sent ", s.events[message.send].time, " stable ",
             stable ? std::to_string(time) : "none");
    }
    I disagreements = 0;
    for (int i = 0; i < int(broadcast_messages.size()); ++i)
        for (int j = i + 1; j < int(broadcast_messages.size()); ++j) {
            const int a = broadcast_messages[i], b = broadcast_messages[j];
            Ids earlier, later;
            for (int p = 0; p < s.n; ++p) {
                const Ids &list = broadcasts[p];
                const auto x = std::find(list.begin(), list.end(), a),
                           y = std::find(list.begin(), list.end(), b);
                if (x != list.end() && y != list.end())
                    (x < y ? earlier : later).push_back(p);
            }
            if (!earlier.empty() && !later.empty()) {
                ++disagreements;
                line(out, "DISAGREE ", message_name(a), " ", message_name(b), " ",
                     s.process_names(earlier), " ", s.process_names(later));
            }
        }
    line(out, "DISAGREEMENTS ", disagreements);
    return out;
}
static std::string verdict(const Simulation &s, const CutDetails &details) {
    std::string out = yes(details.orphans.empty());
    for (int index : details.orphans)
        out += " " + s.copy_name(index);
    return out;
}
static Lines snapshot_report(const Simulation &s, const Simulation &raw) {
    Lines out;
    for (const Snapshot &snapshot : s.snapshots) {
        line(out, "SNAPSHOT ", snapshot.name, " started ", snapshot.start, " completed ",
             snapshot.complete);
        I balances = 0, channel_money = 0;
        Ids recorded, pending;
        for (int p = 0; p < s.n; ++p) {
            const SnapshotRecord &record = snapshot.records[p];
            balances += record.balance;
            std::string list;
            for (int index : record.pending) {
                list += " " + message_name(s.copies[index].message);
                pending.push_back(index);
            }
            line(out, "RECORD ", s.topology.names[p], " t=", record.time, " ", record.reason,
                 " balance ", record.balance, " L=", record.lamport,
                 " V=", vector_text(record.clock), " pending", list.empty() ? " none" : list);
        }
        for (int source = 0; source < s.n; ++source)
            for (int destination = 0; destination < s.n; ++destination)
                if (source != destination) {
                    const SnapshotChannel &channel = snapshot.channels[source * s.n + destination];
                    std::string list;
                    for (int index : channel.copies) {
                        const Message &message = s.messages[s.copies[index].message];
                        recorded.push_back(index);
                        channel_money += message.amount;
                        list += " " + message_name(s.copies[index].message);
                        if (message.amount > 0)
                            list += ":" + std::to_string(message.amount);
                    }
                    line(out, "CHANNEL ", s.topology.names[source], "->",
                         s.topology.names[destination], " marker ", channel.sent, " ",
                         channel.accepted, " state", list.empty() ? " empty" : list);
                }
        for (const auto &[p, time] : snapshot.ignored)
            line(out, "IGNORED ", s.topology.names[p], " t=", time);
        const Vector cut = snapshot_cut(snapshot);
        const CutDetails details = cut_details(cut, s.processes, s.events, s.messages, s.copies);
        bool vector_good = true;
        for (const SnapshotRecord &record : snapshot.records)
            vector_good &= less_equal(record.clock, cut);
        line(out, "CUT ", vector_text(cut), " consistent ", verdict(s, details), " vector ",
             yes(vector_good));
        Ids all = recorded;
        all.insert(all.end(), pending.begin(), pending.end());
        Ids transit = details.transit;
        std::sort(all.begin(), all.end());
        std::sort(transit.begin(), transit.end());
        line(out, "TRANSIT channels ", recorded.size(), " pending ", pending.size(), " cut ",
             transit.size(), " match ", yes(all == transit));
        line(out, "MONEY balances ", balances, " channels ", channel_money, " total ",
             balances + channel_money, " initial ", s.initial(), " conserved ",
             yes(balances + channel_money == s.initial()));
    }
    for (const Snapshot &snapshot : raw.snapshots) {
        const Vector cut = snapshot_cut(snapshot);
        const CutDetails details =
            cut_details(cut, raw.processes, raw.events, raw.messages, raw.copies);
        I money = 0;
        for (const SnapshotRecord &record : snapshot.records)
            money += record.balance;
        for (const SnapshotChannel &channel : snapshot.channels)
            for (int index : channel.copies)
                money += raw.messages[raw.copies[index].message].amount;
        line(out, "RAW ", snapshot.name, " completed ", snapshot.complete, " cut ",
             vector_text(cut), " consistent ", verdict(raw, details), " money ", money,
             " conserved ", yes(money == raw.initial()));
    }
    return out;
}
static int find_event(const Simulation &s, const std::string &name) {
    const auto dot = name.find('.');
    const int p = s.topology.index(name.substr(0, dot)), local = std::stoi(name.substr(dot + 1));
    return s.processes[p].events[local - 1];
}
static Ids longest_chain(const Simulation &s) {
    if (s.events.empty())
        return {};
    int current = 0;
    for (int i = 1; i < int(s.events.size()); ++i)
        if (s.events[i].lamport > s.events[current].lamport)
            current = i;
    Ids path;
    while (true) {
        path.push_back(current);
        const Event &event = s.events[current];
        if (event.lamport <= 1)
            break;
        const int sender = event.type == 4 ? s.messages[s.copies[event.copy].message].send : -1;
        if (sender >= 0 && s.events[sender].lamport == event.lamport - 1)
            current = sender;
        else
            current = s.processes[event.process].events[event.local - 2];
    }
    std::reverse(path.begin(), path.end());
    return path;
}
static Lines analysis_report(const Simulation &s, const Simulation &raw) {
    Lines out;
    const Graph graph = graph_edges(s.events, s.copies, s.messages, s.processes);
    for (const auto &[first, second] : s.params.compare) {
        const int a = find_event(s, first), b = find_event(s, second);
        const Event &e = s.events[a], &f = s.events[b];
        const int rel = relation(e.clock, f.clock);
        Ids path = graph_path(a, b, graph);
        int graph_relation = path.empty() ? 0 : 1;
        if (path.empty()) {
            path = graph_path(b, a, graph);
            if (!path.empty())
                graph_relation = -1;
        }
        line(out, "COMPARE ", first, " ", relation_name(rel), " ", second, " L=", e.lamport, ",",
             f.lamport, " graph ", relation_name(graph_relation), " agree ",
             yes(rel == graph_relation));
        if (!path.empty()) {
            int messages = 0;
            for (int i = 1; i < int(path.size()); ++i)
                messages += s.events[path[i]].process != s.events[path[i - 1]].process;
            line(out, "PATH length ", path.size(), " messages ", messages, " ", ranges(s, path));
        }
        for (int index : {a, b}) {
            const Event &event = s.events[index];
            Vector future(s.n, 0);
            for (const Event &candidate : s.events)
                if (candidate.clock[event.process] < event.local)
                    ++future[candidate.process];
            line(out, "WINDOW ", s.event_name(index), " past ", vector_text(event.clock),
                 " future ", vector_text(future));
        }
    }
    const Concurrency counts = concurrency(s.events, s.n);
    const I event_count = I(s.events.size());
    line(out, "CONCURRENCY events ", event_count, " pairs ", event_count * (event_count - 1) / 2,
         " ordered ", counts.ordered, " concurrent ", counts.concurrent, " same_lamport ",
         counts.same, " inversions ", counts.inversions);
    for (int a = 0; a < s.n; ++a)
        for (int b = a + 1; b < s.n; ++b)
            line(out, "PAIR ", s.topology.names[a], " ", s.topology.names[b], " ",
                 counts.pairs[a][b]);
    const Ids chain = longest_chain(s);
    line(out, "CHAIN length ", chain.size(), " ", ranges(s, chain));
    const Orders ordered = orders(s.processes, s.copies, s.messages, s.events);
    for (const Violation &race : ordered.races)
        line(out, "RACE ", s.topology.names[race.process], " ",
             message_name(s.copies[race.first].message), " ",
             s.topology.names[s.copies[race.first].source], " ",
             message_name(s.copies[race.second].message), " ",
             s.topology.names[s.copies[race.second].source]);
    line(out, "RACES ", ordered.races.size());
    for (const Violation &violation : ordered.violations)
        line(out, "VIOLATION ", s.topology.names[violation.process], " ",
             message_name(s.copies[violation.first].message), " ",
             s.topology.names[s.copies[violation.first].source], " overtook ",
             message_name(s.copies[violation.second].message), " ",
             s.topology.names[s.copies[violation.second].source]);
    line(out, "VIOLATIONS causal ", ordered.violations.size(), " fifo ", ordered.fifo);
    const Orders raw_ordered = orders(raw.processes, raw.copies, raw.messages, raw.events);
    line(out, "RAW events ", raw.events.size(), " delivered ", raw.delivered(), " causal ",
         raw_ordered.violations.size(), " fifo ", raw_ordered.fifo);
    for (const Vector &cut : s.params.cuts) {
        const CutDetails details = cut_details(cut, s.processes, s.events, s.messages, s.copies);
        std::string status = "consistent";
        if (!details.orphans.empty()) {
            status = "inconsistent orphans";
            for (int index : details.orphans)
                status += " " + s.copy_name(index);
        }
        line(out, "CUT ", vector_text(cut), " ", status, " transit ", details.transit.size(),
             " money ", details.money, " initial ", s.initial());
    }
    const Enumeration cuts =
        enumerate(s.processes, s.events, s.params.cutcount, s.params.predicates);
    line(out, "CUTCOUNT t=", s.params.cutcount, " events ", vector_text(cuts.limits), " product ",
         cuts.product, " consistent ", cuts.consistent);
    std::string levels = "LEVELS";
    for (I count : cuts.levels)
        levels += " " + std::to_string(count);
    out.push_back(levels);
    for (int i = 0; i < int(s.params.predicates.size()); ++i)
        line(out, "PREDICATE transit>=", s.params.predicates[i], " cuts ", cuts.predicates[i].cuts,
             " possibly ", yes(cuts.predicates[i].cuts > 0), " definitely ",
             yes(cuts.predicates[i].definite));
    return out;
}
static void write_at(std::string &row, int position, const std::string &text) {
    if (position + int(text.size()) > int(row.size()))
        row.resize(std::size_t(position) + text.size(), ' ');
    row.replace(std::size_t(position), text.size(), text);
}
static std::string diagram_header(const Simulation &s, char kind) {
    std::string row = "    ";
    row += kind;
    for (int p = 0; p < s.n; ++p)
        write_at(row, 6 + 8 * p, s.topology.names[p]);
    while (!row.empty() && row.back() == ' ')
        row.pop_back();
    return row;
}
static std::string diagram_line(const Simulation &s, int process, int value, int type, int message,
                                int source, const std::string &snapshot = "") {
    std::ostringstream prefix;
    prefix << std::setw(5) << value << ' ';
    std::string row = prefix.str();
    row.resize(std::size_t(7 + 8 * (s.n - 1)), ' ');
    for (int p = 0; p < s.n; ++p)
        row[6 + 8 * p] = '|';
    const int own = 6 + 8 * process;
    if (!snapshot.empty()) {
        row[own] = '#';
        write_at(row, own + 1, snapshot);
    } else if (type == 0)
        row[own] = '*';
    else if (type == 1)
        row[own] = 'x';
    else if (type == 2 || type == 3) {
        row[own] = type == 2 ? 'S' : 'B';
        write_at(row, own + 1, message_name(message));
    } else {
        row[own] = 'R';
        const int origin = 6 + 8 * source, a = std::min(origin, own), z = std::max(origin, own);
        for (int position = a + 1; position < z; ++position)
            row[position] = (position >= 6 && (position - 6) % 8 == 0) ? '+' : '-';
        if (origin < own)
            row[z - 1] = '>';
        else
            row[a + 1] = '<';
        write_at(row, a + 2, message_name(message));
    }
    while (!row.empty() && row.back() == ' ')
        row.pop_back();
    return row;
}
static Lines diagram_report(const Simulation &s) {
    Lines out{diagram_header(s, 't')};
    for (const Timeline &item : s.timeline)
        if (item.snapshot)
            out.push_back(
                diagram_line(s, item.process, item.time, 0, -1, -1, s.snapshots[item.index].name));
        else {
            const Event &event = s.events[item.index];
            out.push_back(
                diagram_line(s, event.process, event.time, event.type, event.message, event.peer));
        }
    out.push_back(diagram_header(s, 'L'));
    Ids ordered(s.events.size());
    std::iota(ordered.begin(), ordered.end(), 0);
    std::sort(ordered.begin(), ordered.end(), [&](int a, int b) {
        return std::tie(s.events[a].lamport, s.events[a].process) <
               std::tie(s.events[b].lamport, s.events[b].process);
    });
    for (int index : ordered) {
        const Event &event = s.events[index];
        out.push_back(diagram_line(s, event.process, int(event.lamport), event.type, event.message,
                                   event.peer));
    }
    return out;
}
int main() {
    const Topology topology = read_topology();
    const std::vector<Script> scripts = read_scripts(topology);
    const Params params = parameters();
    Simulation main_run(topology, scripts, params), raw_run(topology, scripts, params, true);
    main_run.run();
    raw_run.run();
    std::filesystem::create_directories("output");
    save("trace.txt", trace_report(main_run));
    save("deliveries.txt", delivery_report(main_run));
    save("snapshots.txt", snapshot_report(main_run, raw_run));
    save("analysis.txt", analysis_report(main_run, raw_run));
    save("diagram.txt", diagram_report(main_run));
}
