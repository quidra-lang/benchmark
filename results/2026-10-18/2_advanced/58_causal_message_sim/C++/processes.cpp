#include "simulation.hpp"
static Action action(std::istringstream &row, std::string kind = "") {
    Action out;
    if (kind.empty())
        row >> kind;
    out.kind = kind;
    row >> out.argument;
    if (kind == "TRANSFER")
        row >> out.amount;
    else if (kind == "SEND")
        row >> out.tag;
    return out;
}
std::vector<Script> read_scripts(const Topology &topology) {
    std::vector<Script> out(topology.names.size());
    std::ifstream input("input/programs.txt");
    std::string text;
    int current = 0;
    while (std::getline(input, text)) {
        std::istringstream row(text);
        std::string key;
        row >> key;
        if (key == "PROCESS") {
            std::string name, balance;
            row >> name >> balance;
            current = topology.index(name);
            row >> out[current].balance;
        } else if (key == "AT") {
            Timed item{};
            std::string next;
            row >> item.start >> next;
            if (next == "EVERY") {
                row >> item.period;
                item.action = action(row);
            } else
                item.action = action(row, next);
            out[current].at.push_back(item);
        } else if (key == "ON") {
            Rule rule;
            row >> rule.tag;
            rule.action = action(row);
            out[current].on.push_back(rule);
        }
    }
    return out;
}
std::vector<Process> initialize(const std::vector<Script> &scripts) {
    std::vector<Process> out(scripts.size());
    for (int i = 0; i < int(scripts.size()); ++i) {
        Process &p = out[i];
        p.initial = p.balance = p.minimum = scripts[i].balance;
        p.clock.assign(scripts.size(), 0);
        p.broadcast.assign(scripts.size(), 0);
        p.next.assign(scripts.size(), 1);
        p.reorder.resize(scripts.size());
    }
    return out;
}
std::vector<Scheduled> expand(const std::vector<Script> &scripts, int end) {
    std::vector<Scheduled> out;
    for (int p = 0; p < int(scripts.size()); ++p)
        for (const Timed &item : scripts[p].at)
            for (int time = item.start; time <= end; time += item.period) {
                out.push_back({time, p, item.action});
                if (item.period == 0)
                    break;
            }
    return out;
}
I balance_at_cut(const Process &process, const std::deque<Event> &events, I count) {
    return count ? events[process.events[std::size_t(count - 1)]].balance : process.initial;
}
