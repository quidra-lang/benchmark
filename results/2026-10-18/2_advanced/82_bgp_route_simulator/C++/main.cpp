#include "bgp.hpp"
#include <algorithm>
#include <filesystem>
#include <sstream>

using Pair = std::pair<int, Prefix>;
struct BestChange {
    int time, asn;
    Prefix prefix;
    std::string text;
};
struct EventStatistics {
    Event event;
    std::string status;
    int convergence = 0, updates = 0, withdrawals = 0, drops = 0, bestChanges = 0,
        routesChanged = 0, maxExploration = 0, first = -1, repeat = -1;
    std::map<Pair, int> exploration;
    std::vector<BestChange> changes, cycle;
};
struct Hop {
    Node *node;
    Prefix prefix;
    Link *link;
};
struct Forwarding {
    std::string result;
    std::vector<int> visits;
    std::vector<Hop> hops;
    int count = 0;
};
struct TraceRecord {
    int trace, start, end = -1;
    std::string result;
    std::vector<int> visits;
};
struct RingRecord {
    Prefix prefix;
    int start, end;
    std::vector<int> path;
};
static std::vector<int> mergePath(const std::vector<int> &path) {
    std::vector<int> result;
    for (int asn : path)
        if (result.empty() || result.back() != asn)
            result.push_back(asn);
    return result;
}
static int valleyPosition(const std::string &pattern) {
    int i = 0, length = static_cast<int>(pattern.size());
    while (i < length && pattern[i] == 'U')
        ++i;
    if (i < length && pattern[i] == 'P')
        ++i;
    while (i < length && pattern[i] == 'D')
        ++i;
    return i;
}
static std::string endText(int value) { return value < 0 ? "END" : std::to_string(value); }
class Simulator {
    Topology topology = readTopology();
    Policies policies = readPolicies();
    Parameters parameters = readParameters(topology);
    std::vector<Event> events = readEvents();
    MessageQueue messages;
    int time = 0, end = 0;
    std::vector<std::string> updates;
    std::vector<EventStatistics> statistics;
    EventStatistics current;
    std::set<Prefix> changed;
    std::vector<TraceRecord> traceRecords;
    std::vector<int> ongoingTraces;
    std::vector<RingRecord> ringRecords;
    std::map<std::pair<Prefix, std::vector<int>>, std::size_t> ongoingRings;
    void log(const std::string &text) { updates.push_back(std::to_string(time) + " " + text); }
    std::pair<std::optional<Route>, Rule *> import(Session *session, Prefix prefix,
                                                   const Attribute &attribute) {
        Rule *rule = policies.applied("IMPORT", session, prefix, attribute);
        if (rule && rule->deny)
            return {std::nullopt, rule};
        Route route;
        route.attribute = attribute;
        route.link = session->link;
        int role = session->link->role(session->owner);
        route.preference = role == 0   ? parameters.customer
                           : role == 1 ? parameters.peer
                                       : parameters.provider;
        if (rule) {
            if (rule->hasPreference)
                route.preference = rule->preference;
            if (rule->hasMed)
                route.attribute.med = rule->med;
            route.attribute.communities = rule->edit(route.attribute.communities);
        }
        return {std::move(route), rule};
    }
    std::vector<Route> candidates(Node *node, Prefix prefix) {
        std::vector<Route> result;
        for (Session *session : node->sessions) {
            auto found = session->incoming.find(prefix);
            if (found == session->incoming.end())
                continue;
            std::optional<Route> route = import(session, prefix, found->second).first;
            if (route)
                result.push_back(std::move(*route));
        }
        return result;
    }
    static std::optional<Route> lookup(const Node *node, Prefix prefix) {
        auto found = node->rib.find(prefix);
        return found == node->rib.end() ? std::nullopt : std::optional<Route>(found->second);
    }
    void redecide(Node *node, Prefix prefix) {
        std::optional<Route> route;
        auto origin = node->origins.find(prefix);
        if (origin != node->origins.end()) {
            Route local;
            local.attribute = origin->second;
            local.local = true;
            route = std::move(local);
        } else {
            std::vector<Route> choices = candidates(node, prefix);
            if (!choices.empty())
                route = bestRoute(choices, topology).first;
        }
        if (route == lookup(node, prefix))
            return;
        if (route)
            node->rib[prefix] = *route;
        else
            node->rib.erase(prefix);
        std::string text = routeText(route);
        log("BEST " + std::to_string(node->number) + " " + prefix.text() + " " + text);
        ++node->changes;
        ++current.bestChanges;
        int count = ++current.exploration[{node->number, prefix}];
        current.maxExploration = std::max(current.maxExploration, count);
        current.changes.push_back({time, node->number, prefix, text});
        changed.insert(prefix);
        for (Session *session : node->sessions)
            if (session->link->up) {
                session->pending.insert(prefix);
                if (session->timer < 0)
                    processPending(session);
            }
    }
    std::pair<std::optional<Attribute>, Rule *> advertised(Session *session, Prefix prefix) {
        auto found = session->owner->rib.find(prefix);
        if (found == session->owner->rib.end())
            return {std::nullopt, nullptr};
        const Route &route = found->second;
        const Attribute &attribute = route.attribute;
        if (!route.local && attribute.path.front() == session->link->other(session->owner)->number)
            return {std::nullopt, nullptr};
        if (attribute.communities.count(noExport))
            return {std::nullopt, nullptr};
        Rule *rule = policies.applied("EXPORT", session, prefix, attribute);
        if (rule && rule->deny)
            return {std::nullopt, rule};
        if (!(rule && rule->allow) && !route.local && route.link->role(session->owner) != 0 &&
            session->link->role(session->owner) != 0)
            return {std::nullopt, rule};
        Attribute result = attribute;
        result.path.assign(1 + (rule ? rule->prepend : 0), session->owner->number);
        result.path.insert(result.path.end(), attribute.path.begin(), attribute.path.end());
        result.med = rule && rule->hasMed ? rule->med : 0;
        if (rule)
            result.communities = rule->edit(result.communities);
        return {std::move(result), rule};
    }
    void processPending(Session *session) {
        int sent = 0;
        for (Prefix prefix : session->pending) {
            auto decision = advertised(session, prefix);
            const std::optional<Attribute> &attribute = decision.first;
            auto old = session->outgoing.find(prefix);
            std::optional<Attribute> previous = old == session->outgoing.end()
                                                    ? std::nullopt
                                                    : std::optional<Attribute>(old->second);
            if (attribute == previous)
                continue;
            if (attribute)
                session->outgoing[prefix] = *attribute;
            else
                session->outgoing.erase(prefix);
            Message message = messages.send(time, session, prefix, attribute);
            ++sent;
            ++session->sent;
            ++current.updates;
            std::string base = "SEND #" + std::to_string(message.serial) + " " +
                               std::to_string(message.sender()->number) + "->" +
                               std::to_string(message.receiver()->number) + " " +
                               message.link()->name + " " + prefix.text();
            if (attribute)
                log(base + " ANNOUNCE " + attributeText(*attribute));
            else {
                ++current.withdrawals;
                log(base + " WITHDRAW");
            }
            if (decision.second)
                ++decision.second->hits;
        }
        session->pending.clear();
        session->timer = sent && session->link->mrai > 0 ? time + session->link->mrai : -1;
    }
    void receive(const Message &message) {
        Session *session = message.link()->session(message.receiver());
        ++session->received;
        std::string result = "WITHDRAW";
        if (!message.attribute)
            session->incoming.erase(message.prefix);
        else if (std::find(message.attribute->path.begin(), message.attribute->path.end(),
                           message.receiver()->number) != message.attribute->path.end()) {
            session->incoming.erase(message.prefix);
            result = "ANNOUNCE loop";
        } else {
            session->incoming[message.prefix] = *message.attribute;
            auto evaluation = import(session, message.prefix, *message.attribute);
            result = "ANNOUNCE accept";
            if (evaluation.second) {
                ++evaluation.second->hits;
                result = evaluation.first ? result + " " + evaluation.second->name
                                          : "ANNOUNCE deny " + evaluation.second->name;
            }
        }
        log("RECV #" + std::to_string(message.serial) + " " +
            std::to_string(message.sender()->number) + "->" +
            std::to_string(message.receiver()->number) + " " + message.link()->name + " " +
            message.prefix.text() + " " + result);
        redecide(message.receiver(), message.prefix);
    }
    void execute(const Event &event) {
        log("EVENT " + std::to_string(event.number) + " " + event.text);
        const std::vector<std::string> &a = event.args;
        if (event.kind == "INITIAL") {
            for (const Initial &initial : topology.initial) {
                initial.node->origins[initial.prefix] = initial.attribute;
                redecide(initial.node, initial.prefix);
            }
        } else if (event.kind == "ANNOUNCE") {
            Node *node = &topology.nodes.at(std::stoi(a[1]));
            Prefix value = prefix(a[2]);
            Attribute attribute;
            attribute.origin = originRank(a[3]);
            attribute.communities = communities(a, 4);
            node->origins[value] = std::move(attribute);
            redecide(node, value);
        } else if (event.kind == "WITHDRAW") {
            Node *node = &topology.nodes.at(std::stoi(a[1]));
            Prefix value = prefix(a[2]);
            node->origins.erase(value);
            redecide(node, value);
        } else if (event.kind == "LINK_DOWN" || event.kind == "LINK_UP") {
            Link *link = topology.named(a[2]);
            std::array<Node *, 2> endpoints = {link->a, link->b};
            if (endpoints[0]->number > endpoints[1]->number)
                std::swap(endpoints[0], endpoints[1]);
            link->up = event.kind == "LINK_UP";
            if (!link->up) {
                ++link->downs;
                for (const Message &message : messages.remove(link)) {
                    ++current.drops;
                    log("DROP #" + std::to_string(message.serial) + " " +
                        std::to_string(message.sender()->number) + "->" +
                        std::to_string(message.receiver()->number) + " " + link->name + " " +
                        message.prefix.text());
                }
                std::array<std::vector<Prefix>, 2> remembered;
                for (int i = 0; i < 2; ++i) {
                    Session *session = link->session(endpoints[i]);
                    for (const std::pair<const Prefix, Attribute> &entry : session->incoming)
                        remembered[i].push_back(entry.first);
                    session->incoming.clear();
                    session->outgoing.clear();
                    session->pending.clear();
                    session->timer = -1;
                }
                for (int i = 0; i < 2; ++i)
                    for (Prefix value : remembered[i])
                        redecide(endpoints[i], value);
            } else
                for (Node *node : endpoints) {
                    Session *session = link->session(node);
                    session->pending.clear();
                    for (const std::pair<const Prefix, Route> &entry : node->rib)
                        session->pending.insert(entry.first);
                    processPending(session);
                }
        } else {
            Rule *rule = policies.named(a[2]);
            rule->active = event.kind == "POLICY_ON";
            Node *node = &topology.nodes.at(rule->owner);
            if (rule->direction == "IMPORT") {
                std::set<Prefix> prefixes;
                for (Session *session : node->sessions)
                    for (const std::pair<const Prefix, Attribute> &entry : session->incoming)
                        prefixes.insert(entry.first);
                for (Prefix value : prefixes)
                    redecide(node, value);
            } else
                for (Session *session : node->sessions)
                    if (session->link->up) {
                        for (const std::pair<const Prefix, Route> &entry : node->rib)
                            session->pending.insert(entry.first);
                        for (const std::pair<const Prefix, Attribute> &entry : session->outgoing)
                            session->pending.insert(entry.first);
                        if (session->timer < 0)
                            processPending(session);
                    }
        }
    }
    bool quiet() const {
        if (!messages.heap.empty())
            return false;
        for (const Session *session : topology.sessions)
            if (!session->pending.empty())
                return false;
        return true;
    }
    std::string state() const {
        std::ostringstream output;
        const auto table = [&](char tag, const std::map<Prefix, Attribute> &values) {
            output << tag << '{';
            for (const std::pair<const Prefix, Attribute> &entry : values)
                output << entry.first.text() << '=' << attributeText(entry.second) << ';';
            output << '}';
        };
        for (const Session *session : topology.sessions) {
            output << 'S' << session->owner->number << ':' << session->link->number;
            table('I', session->incoming);
            table('O', session->outgoing);
            output << "P{";
            for (Prefix value : session->pending)
                output << value.text() << ';';
            output << "}T" << (session->timer < 0 ? -1 : session->timer - time) << ';';
        }
        output << "Q{";
        for (const Message &message : messages.ordered()) {
            output << message.time - time << ':' << message.receiver()->number << ':'
                   << message.sender()->number << ':' << message.link()->number << ':'
                   << message.prefix.text() << ':';
            if (message.attribute)
                output << 'A' << attributeText(*message.attribute) << ';';
            else
                output << "W;";
        }
        output << '}';
        return output.str();
    }
    std::map<Pair, Route> snapshot() const {
        std::map<Pair, Route> result;
        for (const std::pair<const int, Node> &entry : topology.nodes)
            for (const std::pair<const Prefix, Route> &route : entry.second.rib)
                result.emplace(Pair{entry.first, route.first}, route.second);
        return result;
    }
    Forwarding forward(Node *source, std::uint64_t address) const {
        Forwarding result;
        result.visits.push_back(source->number);
        std::set<int> visited = {source->number};
        Node *node = source;
        for (;;) {
            const Route *route = nullptr;
            Prefix selected;
            for (const std::pair<const Prefix, Route> &entry : node->rib)
                if (entry.first.contains(address) &&
                    (!route || entry.first.length > selected.length)) {
                    route = &entry.second;
                    selected = entry.first;
                }
            if (!route) {
                result.result = result.hops.empty() ? "UNREACHABLE" : "BLACKHOLE";
                return result;
            }
            if (route->local) {
                result.hops.push_back({node, selected, nullptr});
                result.result = "DELIVERED";
                return result;
            }
            result.hops.push_back({node, selected, route->link});
            ++result.count;
            node = route->link->other(node);
            result.visits.push_back(node->number);
            if (visited.count(node->number)) {
                result.result = "LOOP";
                return result;
            }
            visited.insert(node->number);
        }
    }
    std::string pattern(const std::vector<int> &path) {
        std::string result;
        for (std::size_t i = 0; i + 1 < path.size(); ++i)
            result += directionSymbol(
                topology.between(path[i], path[i + 1])->role(&topology.nodes.at(path[i])));
        return result;
    }
    std::vector<std::vector<int>> loops(Prefix prefix) const {
        std::set<int> done;
        std::vector<std::vector<int>> result;
        for (const std::pair<const int, Node> &entry : topology.nodes) {
            const Node *node = &entry.second;
            if (done.count(node->number))
                continue;
            std::map<int, std::size_t> positions;
            std::vector<int> path;
            for (;;) {
                if (done.count(node->number))
                    break;
                auto found = positions.find(node->number);
                if (found != positions.end()) {
                    std::vector<int> cycle(path.begin() + found->second, path.end());
                    std::rotate(cycle.begin(), std::min_element(cycle.begin(), cycle.end()),
                                cycle.end());
                    result.push_back(std::move(cycle));
                    break;
                }
                positions[node->number] = path.size();
                path.push_back(node->number);
                auto route = node->rib.find(prefix);
                if (route == node->rib.end() || route->second.local)
                    break;
                node = route->second.link->other(node);
            }
            done.insert(path.begin(), path.end());
        }
        std::sort(result.begin(), result.end());
        return result;
    }
    void forwardingCheck() {
        for (Prefix prefix : changed) {
            std::vector<std::vector<int>> paths = loops(prefix);
            std::set<std::vector<int>> found(paths.begin(), paths.end());
            for (auto record = ongoingRings.begin(); record != ongoingRings.end();) {
                if (record->first.first == prefix && !found.count(record->first.second)) {
                    ringRecords[record->second].end = time;
                    record = ongoingRings.erase(record);
                } else
                    ++record;
            }
            for (const std::vector<int> &path : paths) {
                std::pair<Prefix, std::vector<int>> key{prefix, path};
                if (!ongoingRings.count(key)) {
                    ongoingRings[key] = ringRecords.size();
                    ringRecords.push_back({prefix, time, -1, path});
                }
            }
        }
        for (std::size_t i = 0; i < parameters.traces.size(); ++i) {
            const Trace &trace = parameters.traces[i];
            Forwarding path = forward(trace.source, trace.address);
            std::string status =
                (path.result == "LOOP" || path.result == "BLACKHOLE") ? path.result : "";
            int old = ongoingTraces[i];
            if (old >= 0 &&
                (traceRecords[old].result != status || traceRecords[old].visits != path.visits)) {
                traceRecords[old].end = time;
                ongoingTraces[i] = -1;
            }
            if (!status.empty() && ongoingTraces[i] < 0) {
                ongoingTraces[i] = static_cast<int>(traceRecords.size());
                traceRecords.push_back({static_cast<int>(i), time, -1, status, path.visits});
            }
        }
    }
    std::vector<std::string> convergenceLines() const {
        std::vector<std::string> result = {
            "event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration"};
        for (const EventStatistics &s : statistics)
            result.push_back(std::to_string(s.event.number) + "," + std::to_string(s.event.time) +
                             "," + s.event.kind + "," + s.status + "," +
                             std::to_string(s.convergence) + "," + std::to_string(s.updates) + "," +
                             std::to_string(s.withdrawals) + "," + std::to_string(s.drops) + "," +
                             std::to_string(s.bestChanges) + "," + std::to_string(s.routesChanged) +
                             "," + std::to_string(s.maxExploration));
        return result;
    }
    std::vector<std::string> ribLines() {
        std::vector<std::string> result;
        for (std::pair<const int, Node> &entry : topology.nodes) {
            Node *node = &entry.second;
            int sent = 0, received = 0, local = 0;
            for (const Session *session : node->sessions) {
                sent += session->sent;
                received += session->received;
            }
            for (const std::pair<const Prefix, Route> &route : node->rib)
                if (route.second.local)
                    ++local;
            result.push_back("AS " + std::to_string(node->number) + " routes " +
                             std::to_string(node->rib.size()) + " local " + std::to_string(local) +
                             " sent " + std::to_string(sent) + " received " +
                             std::to_string(received) + " changes " +
                             std::to_string(node->changes));
            for (Session *session : node->sessions) {
                int accepted = 0;
                for (const std::pair<const Prefix, Attribute> &route : session->incoming)
                    if (import(session, route.first, route.second).first)
                        ++accepted;
                result.push_back("SESSION " + session->link->name + " " +
                                 std::to_string(session->link->other(node)->number) + " " +
                                 roleName(session->link->role(node)) + " " +
                                 (session->link->up ? "UP" : "DOWN") + " in " +
                                 std::to_string(session->incoming.size()) + " accepted " +
                                 std::to_string(accepted) + " out " +
                                 std::to_string(session->outgoing.size()) + " sent " +
                                 std::to_string(session->sent) + " received " +
                                 std::to_string(session->received) + " flaps " +
                                 std::to_string(session->link->downs));
            }
            for (const std::pair<const Prefix, Route> &route : node->rib) {
                std::vector<Route> choices = candidates(node, route.first);
                std::string text = route.first.text() + " " + routeText(route.second) +
                                   " candidates " + std::to_string(choices.size());
                if (!route.second.local)
                    text += " reason " + bestRoute(choices, topology).second;
                result.push_back(text);
                choices.erase(std::remove_if(choices.begin(), choices.end(),
                                             [&](const Route &candidate) {
                                                 return candidate == route.second;
                                             }),
                              choices.end());
                while (!choices.empty()) {
                    Route best = bestRoute(choices, topology).first;
                    result.push_back("ALT " + routeText(best));
                    auto found = std::find(choices.begin(), choices.end(), best);
                    choices.erase(found);
                }
            }
        }
        return result;
    }
    std::vector<std::string> pathLines() {
        std::vector<std::string> result;
        for (const Trace &trace : parameters.traces) {
            Forwarding path = forward(trace.source, trace.address);
            std::string directions;
            result.push_back("TRACE " + std::to_string(trace.source->number) + " " + trace.text +
                             " " + path.result + " hops " + std::to_string(path.count));
            for (const Hop &hop : path.hops) {
                std::string text =
                    "HOP " + std::to_string(hop.node->number) + " " + hop.prefix.text();
                if (!hop.link)
                    text += " LOCAL";
                else {
                    text += " next " + std::to_string(hop.link->other(hop.node)->number) +
                            " link " + hop.link->name;
                    directions += directionSymbol(hop.link->role(hop.node));
                }
                result.push_back(text);
            }
            if (path.result == "LOOP")
                result.push_back("HOP " + std::to_string(path.visits.back()) + " REVISIT");
            else if (path.result == "BLACKHOLE" || path.result == "UNREACHABLE")
                result.push_back("HOP " + std::to_string(path.visits.back()) + " NOROUTE");
            if (path.hops.empty())
                result.push_back("CONTROL NONE");
            else {
                const Route &route = trace.source->rib.at(path.hops.front().prefix);
                std::vector<int> visits(path.visits.begin() + 1, path.visits.end());
                bool match =
                    path.result == "DELIVERED" && mergePath(route.attribute.path) == visits;
                result.push_back("CONTROL " +
                                 (route.local ? "LOCAL" : pathText(route.attribute.path)) + " " +
                                 (match ? "MATCH" : "MISMATCH"));
            }
            if (path.count)
                result.push_back("PATTERN " + directions + " " +
                                 (valleyPosition(directions) == static_cast<int>(directions.size())
                                      ? "VALLEYFREE"
                                      : "VALLEY"));
        }
        std::set<Prefix> prefixes;
        for (const std::pair<const int, Node> &entry : topology.nodes)
            for (const std::pair<const Prefix, Attribute> &origin : entry.second.origins)
                prefixes.insert(origin.first);
        std::vector<std::string> names;
        for (Prefix prefix : prefixes)
            names.push_back(prefix.text());
        result.push_back(names.empty() ? "PREFIXES" : "PREFIXES " + join(names, ","));
        for (std::pair<const int, Node> &entry : topology.nodes) {
            std::string symbols;
            for (Prefix prefix : prefixes) {
                Forwarding path = forward(&entry.second, prefix.address);
                char symbol = 'U';
                if (path.result == "LOOP")
                    symbol = 'L';
                else if (path.result == "BLACKHOLE")
                    symbol = 'B';
                else if (path.result == "DELIVERED")
                    symbol = path.count == 0                                ? '*'
                             : path.hops.back().node->origins.count(prefix) ? '+'
                                                                            : 'X';
                symbols += symbol;
            }
            result.push_back("REACH " + std::to_string(entry.first) +
                             (symbols.empty() ? "" : " " + symbols));
        }
        return result;
    }
    std::vector<std::string> auditLines() {
        std::vector<std::string> result;
        int loopCount = 0, blackholes = 0, valleys = 0, learned = 0, divergent = 0;
        std::vector<TraceRecord> traces = traceRecords;
        std::sort(traces.begin(), traces.end(), [](const TraceRecord &a, const TraceRecord &b) {
            return std::tie(a.start, a.trace) < std::tie(b.start, b.trace);
        });
        for (const TraceRecord &record : traces) {
            const Trace &trace = parameters.traces[record.trace];
            std::string text = record.result + " " + std::to_string(trace.source->number) + " " +
                               trace.text + " from " + std::to_string(record.start) + " to " +
                               endText(record.end);
            if (record.result == "BLACKHOLE") {
                ++blackholes;
                text += " at " + std::to_string(record.visits.back());
            } else
                ++loopCount;
            result.push_back(text + " path " + pathText(record.visits));
        }
        std::vector<RingRecord> rings = ringRecords;
        std::sort(rings.begin(), rings.end(), [](const RingRecord &a, const RingRecord &b) {
            return std::make_tuple(a.start, a.prefix, a.path.front()) <
                   std::make_tuple(b.start, b.prefix, b.path.front());
        });
        for (const RingRecord &record : rings)
            result.push_back("RING " + record.prefix.text() + " from " +
                             std::to_string(record.start) + " to " + endText(record.end) +
                             " path " + pathText(record.path));
        for (const std::pair<const int, Node> &entry : topology.nodes)
            for (const std::pair<const Prefix, Route> &route : entry.second.rib) {
                if (route.second.local)
                    continue;
                ++learned;
                std::vector<int> path = {entry.first};
                path.insert(path.end(), route.second.attribute.path.begin(),
                            route.second.attribute.path.end());
                path = mergePath(path);
                std::string directions = pattern(path);
                int position = valleyPosition(directions);
                if (position < static_cast<int>(directions.size())) {
                    ++valleys;
                    result.push_back("VALLEY " + std::to_string(entry.first) + " " +
                                     route.first.text() + " path " +
                                     pathText(route.second.attribute.path) + " pattern " +
                                     directions + " leaker " + std::to_string(path[position]));
                }
            }
        for (const Rule &rule : policies.rules)
            result.push_back("RULE " + rule.name + " " + rule.direction + " " +
                             (rule.active ? "ON" : "OFF") + " hits " + std::to_string(rule.hits));
        for (const EventStatistics &s : statistics) {
            if (s.first < 0)
                continue;
            ++divergent;
            result.push_back("DIVERGENT event " + std::to_string(s.event.number) + " first " +
                             std::to_string(s.first) + " repeat " + std::to_string(s.repeat) +
                             " period " + std::to_string(s.repeat - s.first));
            std::map<Pair, int> counts;
            for (const BestChange &change : s.cycle) {
                result.push_back("CYCLE " + std::to_string(change.time) + " " +
                                 std::to_string(change.asn) + " " + change.prefix.text() + " " +
                                 change.text);
                ++counts[{change.asn, change.prefix}];
            }
            for (const std::pair<const Pair, int> &count : counts)
                result.push_back("OSCILLATE " + std::to_string(count.first.first) + " " +
                                 count.first.second.text() + " changes " +
                                 std::to_string(count.second));
        }
        result.push_back("SUMMARY loops " + std::to_string(loopCount) + " blackholes " +
                         std::to_string(blackholes) + " rings " + std::to_string(rings.size()) +
                         " routes " + std::to_string(learned) + " valleys " +
                         std::to_string(valleys) + " divergent " + std::to_string(divergent) +
                         " end " + std::to_string(end));
        return result;
    }

  public:
    void run() {
        ongoingTraces.assign(parameters.traces.size(), -1);
        for (std::size_t k = 0; k < events.size(); ++k) {
            const Event &event = events[k];
            current = EventStatistics{};
            current.event = event;
            std::map<Pair, Route> before = snapshot();
            std::map<std::string, int> seen;
            int deliveries = 0;
            time = event.time;
            changed.clear();
            execute(event);
            for (int t = event.time;; ++t) {
                time = t;
                if (t > event.time)
                    changed.clear();
                std::vector<Message> arrived = messages.arrivals(t);
                for (const Message &message : arrived)
                    receive(message);
                if (!arrived.empty())
                    current.convergence = t - event.time;
                for (Session *session : topology.sessions)
                    if (session->timer == t) {
                        session->timer = -1;
                        if (!session->pending.empty())
                            processPending(session);
                    }
                if (!changed.empty())
                    forwardingCheck();
                if (!arrived.empty()) {
                    ++deliveries;
                    if (current.first < 0 && deliveries <= parameters.stepcap) {
                        std::string key = state();
                        auto found = seen.find(key);
                        if (found != seen.end()) {
                            current.first = found->second;
                            current.repeat = t;
                            for (const BestChange &change : current.changes)
                                if (change.time > current.first && change.time <= t)
                                    current.cycle.push_back(change);
                        } else
                            seen.emplace(std::move(key), t);
                    }
                }
                bool last = k + 1 == events.size();
                bool stop =
                    last ? (quiet() || current.first >= 0 || deliveries >= parameters.stepcap)
                         : t == events[k + 1].time - 1;
                if (stop) {
                    end = t;
                    break;
                }
            }
            current.status = current.first >= 0       ? "DIVERGENT"
                             : quiet()                ? "CONVERGED"
                             : k + 1 == events.size() ? "CAPPED"
                                                      : "UNSETTLED";
            std::map<Pair, Route> after = snapshot();
            std::set<Pair> pairs;
            for (const std::pair<const Pair, Route> &entry : before)
                pairs.insert(entry.first);
            for (const std::pair<const Pair, Route> &entry : after)
                pairs.insert(entry.first);
            for (const Pair &pair : pairs) {
                auto a = before.find(pair), b = after.find(pair);
                if (a == before.end() || b == after.end() || !(a->second == b->second))
                    ++current.routesChanged;
            }
            statistics.push_back(std::move(current));
        }
        std::filesystem::create_directories("output");
        writeLines("updates.txt", updates);
        writeLines("convergence.csv", convergenceLines());
        writeLines("ribs.txt", ribLines());
        writeLines("paths.txt", pathLines());
        writeLines("audit.txt", auditLines());
    }
};
int main() {
    Simulator simulator;
    simulator.run();
}
