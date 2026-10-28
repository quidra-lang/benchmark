#include "scheduler.hpp"
Schedule dispatch(const Instance &data, const std::string &rule, const Chromosome &genes) {
    std::vector<int> next(14), ready(14), free(data.machines), rank(data.operations.size());
    if (rule == "GENES") {
        std::vector<int> count(14);
        for (std::size_t i = 0; i < genes.size(); ++i)
            for (const Job &job : data.jobs)
                if (job.number == genes[i]) {
                    rank[job.operations[count[job.number]++]] = int(i + 1);
                    break;
                }
    }
    std::vector<int> starts(data.operations.size());
    int decisions = 0, ties = 0;
    for (std::size_t step = 0; step < data.operations.size(); ++step) {
        std::vector<std::pair<int, int>> candidates;
        int completion = std::numeric_limits<int>::max(), chosen_machine = data.machines;
        for (const Job &job : data.jobs) {
            if (next[job.number] >= int(job.operations.size()))
                continue;
            const int id = job.operations[next[job.number]];
            const Operation &op = data.operations[id];
            const int start = std::max(ready[job.number], free[op.machine]), end = start + op.duration;
            candidates.emplace_back(id, start);
            if (std::tie(end, op.machine) < std::tie(completion, chosen_machine)) {
                completion = end;
                chosen_machine = op.machine;
            }
        }
        int selected = -1, best = std::numeric_limits<int>::max(), count = 0, equal = 0, start = 0;
        for (const auto &item : candidates) {
            const Operation &op = data.operations[item.first];
            if (op.machine != chosen_machine || item.second >= completion)
                continue;
            ++count;
            const int value = rule == "SPT"    ? op.duration
                              : rule == "LPT"  ? -op.duration
                              : rule == "MWKR" ? -(op.duration + op.tail)
                              : rule == "FIFO" ? ready[op.job]
                                               : rank[item.first];
            if (value < best) {
                selected = item.first;
                best = value;
                equal = 1;
                start = item.second;
            } else if (value == best) {
                ++equal;
                if (op.job < data.operations[selected].job) {
                    selected = item.first;
                    start = item.second;
                }
            }
        }
        if (count >= 2)
            ++decisions;
        if (equal >= 2)
            ++ties;
        const Operation &op = data.operations[selected];
        starts[selected] = start;
        ready[op.job] = free[op.machine] = start + op.duration;
        ++next[op.job];
    }
    Schedule result = from_starts(data, starts);
    result.decisions = decisions;
    result.ties = ties;
    return result;
}
