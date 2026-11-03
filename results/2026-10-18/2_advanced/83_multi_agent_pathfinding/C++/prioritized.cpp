#include "mapf.hpp"
PriorityResult prioritized(const Grid &grid, const Parameters &parameters,
                           const std::vector<int> &order, int number, Run &run) {
    Prohibitions bans;
    PriorityResult result{Plan(grid.agents.size()), 0, -1};
    for (int agent : order) {
        int before = run.counter.expansions;
        Path path = lowLevel(grid, agent, grid.agents[agent].start, 0, parameters.horizon, bans,
                             false, run.counter);
        if (run.counter.aborted) {
            result.paths.clear();
            result.failed = agent;
            return result;
        }
        std::string text =
            "order " + std::to_string(number) + " agent " + static_cast<char>('A' + agent);
        if (path.empty()) {
            run.trace.push_back(text + " failed expansions " +
                                std::to_string(run.counter.expansions - before));
            result.paths.clear();
            result.failed = agent;
            return result;
        }
        run.trace.push_back(text + " cost " + std::to_string(path.size() - 1) + " expansions " +
                            std::to_string(run.counter.expansions - before));
        bans.reserve(path, 0, true);
        result.paths[agent] = std::make_shared<const Path>(std::move(path));
        ++result.planned;
    }
    return result;
}
