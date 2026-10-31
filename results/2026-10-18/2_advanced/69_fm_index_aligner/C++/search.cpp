#include "aligner.hpp"
std::vector<int> lower_bounds(const std::string &sequence, const Index &reverse) {
    std::vector<int> out;
    Interval interval{0, reverse.size};
    int mismatches = 0;
    for (char base : sequence) {
        interval = reverse.extend(interval, base);
        if (interval.empty()) {
            ++mismatches;
            interval = {0, reverse.size};
        }
        out.push_back(mismatches);
    }
    return out;
}
Search backtrack(const std::string &sequence, int maximum, const Index &forward,
                 const Index &reverse) {
    struct State {
        int position, remaining;
        Interval interval;
    };
    std::vector<int> bounds = lower_bounds(sequence, reverse);
    std::vector<State> stack = {{int(sequence.size()) - 1, maximum, {0, forward.size}}};
    Search out;
    while (!stack.empty()) {
        State state = stack.back();
        stack.pop_back();
        ++out.nodes;
        if (state.remaining < (state.position < 0 ? 0 : bounds[state.position]))
            continue;
        if (state.position == -1) {
            out.leaves.push_back(
                {state.interval.lower, state.interval.upper, maximum - state.remaining});
            out.positions += state.interval.upper - state.interval.lower;
            continue;
        }
        for (char base : std::string("TGCA")) {
            Interval next = forward.extend(state.interval, base);
            if (next.empty())
                continue;
            int mismatch = base != sequence[state.position];
            if (!mismatch || state.remaining >= 1)
                stack.push_back({state.position - 1, state.remaining - mismatch, next});
        }
    }
    return out;
}
