#include "raft.hpp"
const std::array<std::string, 7> counter_names = {"sent", "delivered", "inflight", "partition",
                                                  "rule", "loss",      "down"};
std::string type_name(Type type) {
    return std::array<std::string, 5>{"RV", "RVR", "AE", "AER", "TN"}[int(type)];
}
bool Later::operator()(const Envelope &a, const Envelope &b) const {
    return std::tie(a.arrival, a.source, a.serial) > std::tie(b.arrival, b.source, b.serial);
}
Network::Network(int count) : nodes(count) {
    std::ifstream input("input/network.txt");
    std::string key, text;
    int delay;
    input >> key >> delay;
    std::getline(input, text);
    for (int a = 1; a <= nodes; ++a)
        for (int b = 1; b <= nodes; ++b)
            if (a != b)
                links[a][b].delay = delay;
    while (std::getline(input, text)) {
        std::istringstream row(text);
        std::string kind, first, second;
        row >> kind >> first >> second;
        if (kind == "DELAY" || kind == "LOSS") {
            int value;
            row >> value;
            for (int a = 1; a <= nodes; ++a)
                for (int b = 1; b <= nodes; ++b)
                    if (a != b && (first == "*" || std::stoi(first) == a) &&
                        (second == "*" || std::stoi(second) == b)) {
                        if (kind == "DELAY")
                            links[a][b].delay = value;
                        else
                            links[a][b].loss = value;
                    }
        } else {
            std::string type;
            int start, last;
            row >> type >> start >> last;
            std::optional<Type> parsed;
            for (int i = 0; i < 5; ++i)
                if (type_name(Type(i)) == type)
                    parsed = Type(i);
            for (int a = 1; a <= nodes; ++a)
                for (int b = 1; b <= nodes; ++b)
                    if (a != b && (first == "*" || std::stoi(first) == a) &&
                        (second == "*" || std::stoi(second) == b))
                        links[a][b].drops.push_back({parsed, start, last});
        }
    }
}
void Network::partition(const std::vector<std::vector<int>> &partition_groups) {
    for (int i = 0; i < int(partition_groups.size()); ++i)
        for (int node : partition_groups[i])
            groups[node] = i;
}
void Network::heal() { groups.fill(0); }
bool Network::separated(int first, int second) const { return groups[first] != groups[second]; }
void Network::count(const Message &message, Counter field, int amount) {
    total[field] += amount;
    by_type[int(message.type)][field] += amount;
    links[message.source][message.destination].stats[field] += amount;
}
void Network::send(int time, Message message) {
    ++serial;
    count(message, Sent);
    Link &link = links[message.source][message.destination];
    if (separated(message.source, message.destination)) {
        count(message, Partitioned);
        return;
    }
    for (const Drop &drop : link.drops)
        if ((!drop.type || *drop.type == message.type) && drop.first <= time && time <= drop.last) {
            count(message, RuleLost);
            return;
        }
    ++link.passed;
    if (link.loss > 0 && link.passed % link.loss == 0) {
        count(message, PeriodicLost);
        return;
    }
    count(message, Inflight);
    queue.push({time + link.delay, message.source, serial, std::move(message)});
}
std::optional<Message> Network::arrival(int time) {
    if (queue.empty() || queue.top().arrival != time)
        return {};
    Message message = queue.top().message;
    queue.pop();
    count(message, Inflight, -1);
    return message;
}
bool Network::deliver(const Message &message, bool destination_up) {
    if (!destination_up) {
        count(message, DownLost);
        return false;
    }
    if (separated(message.source, message.destination)) {
        count(message, Partitioned);
        return false;
    }
    count(message, Delivered);
    return true;
}
