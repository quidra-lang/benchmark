#include "simulator.hpp"
Run simulate(const std::vector<Instruction> &instructions, const Sources &sources,
             const Variant &variant, const std::vector<bool> &mispredicted) {
    Run out;
    out.timings.resize(instructions.size());
    for (int i = 0; i < int(instructions.size()); ++i) {
        Timing &time = out.timings[i];
        const int execute = instructions[i].kind == multiply ? variant.latency : 1;
        if (i == 0) {
            time.f = 1;
            time.d = 2;
            time.x = 3;
        } else {
            const Timing &previous = out.timings[i - 1];
            time.f = mispredicted[i - 1] ? previous.x + !id_resolved(instructions[i - 1], variant)
                                         : previous.d;
            time.d = std::max(time.f + 1, previous.x);
            const int ideal = previous.x + 1;
            std::array<int, 4> bound{time.d + 1, previous.m, ideal, ideal},
                producer{-1, -1, -1, -1};
            for (int p : sources[i])
                if (p >= 0) {
                    const int cause = instructions[p].kind == load ? 2 : 3;
                    const int ready =
                        ready_cycle(instructions[i], instructions[p], out.timings[p], variant);
                    if (ready > bound[cause]) {
                        bound[cause] = ready;
                        producer[cause] = p;
                    }
                }
            time.x = ideal;
            for (int cause = 0; cause < 4; ++cause)
                if (bound[cause] > time.x) {
                    out.records.push_back(
                        {cause, bound[cause] - time.x, cause < 2 ? i - 1 : i, i, producer[cause]});
                    time.x = bound[cause];
                }
        }
        time.m = time.x + execute;
        time.w = time.m + 1;
    }
    if (instructions.back().kind == multiply && variant.latency >= 2)
        out.records.push_back({1, variant.latency - 1, int(instructions.size()) - 1, -1, -1});
    for (const Record &record : out.records) {
        out.stalls[record.cause] += record.cycles;
        ++out.events[record.cause];
    }
    out.cycles = out.timings.back().w;
    return out;
}
