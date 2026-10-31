#include "scheduler.hpp"
std::string notation(const Operation &op) {
    return "J" + std::to_string(op.job) + "-" + std::to_string(op.index);
}
Instance read_instance() {
    Instance data;
    std::ifstream input("input/instance.txt");
    int count;
    input >> count >> data.machines;
    std::string line;
    std::getline(input, line);
    data.machine.resize(data.machines);
    for (int number = 1; number <= count; ++number) {
        std::getline(input, line);
        std::istringstream fields(line);
        std::string token, error;
        std::set<int> seen;
        std::vector<std::pair<int, int>> route;
        int position = 0;
        while (fields >> token) {
            ++position;
            const std::size_t colon = token.find(':');
            const int machine = std::stoi(token.substr(0, colon)),
                      duration = std::stoi(token.substr(colon + 1));
            if (machine < 1 || machine > data.machines)
                error = "unknown machine " + std::to_string(machine);
            else if (duration < 1 || duration > 99)
                error = "bad duration " + std::to_string(duration);
            else if (seen.count(machine))
                error = "repeated machine " + std::to_string(machine);
            if (!error.empty()) {
                data.errors.push_back("job " + std::to_string(number) + " operation " +
                                      std::to_string(position) + ": " + error);
                break;
            }
            seen.insert(machine);
            route.emplace_back(machine - 1, duration);
        }
        if (!error.empty())
            continue;
        Job job{number, 0, {}};
        for (const auto &pair : route)
            job.work += pair.second;
        int head = 0;
        for (std::size_t i = 0; i < route.size(); ++i) {
            const int id = int(data.operations.size());
            Operation op{number,
                         int(i + 1),
                         route[i].first,
                         route[i].second,
                         head,
                         job.work - head - route[i].second,
                         i ? id - 1 : -1,
                         i + 1 < route.size() ? id + 1 : -1};
            data.operations.push_back(op);
            job.operations.push_back(id);
            head += op.duration;
            Machine &machine = data.machine[op.machine];
            ++machine.count;
            machine.load += op.duration;
            machine.head = std::min(machine.head, op.head);
            machine.tail = std::min(machine.tail, op.tail);
        }
        data.work += job.work;
        data.jobs.push_back(std::move(job));
    }
    for (Machine &machine : data.machine)
        machine.bound = machine.head + machine.load + machine.tail;
    return data;
}
