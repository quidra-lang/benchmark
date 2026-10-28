#include "typesetting.hpp"
int line_class(const Measure &line) {
    return line.last ? 1 : line.slack <= 1 ? 0 : line.slack <= 3 ? 1 : line.slack <= 6 ? 2 : 3;
}
Integer line_cost(const Measure &line, int previous_class, const Params &p) {
    Integer result = p.at("line_penalty") + (line.slack < 0 ? p.at("overfull_penalty")
                                             : line.last    ? 0
                                                            : Integer(line.slack) * line.slack);
    if (line.mid) {
        result += p.at("hyphen_penalty");
        if (line.previous_mid)
            result += p.at("double_hyphen_demerit");
    }
    if (line.last && line.previous_mid)
        result += p.at("final_hyphen_demerit");
    if (std::abs(line_class(line) - previous_class) >= 2)
        result += p.at("fitness_demerit");
    return result;
}
Breaking break_lines(int count, const MeasureLine &measure, const Params &p, bool greedy) {
    Breaking result;
    if (greedy) {
        int a = 0, previous = 1;
        while (a < count) {
            int b = a + 1;
            if (measure(a, b).slack >= 0) {
                for (int next = b + 1; next <= count; ++next)
                    if (measure(a, next).slack >= 0)
                        b = next;
            }
            const Measure line = measure(a, b);
            result.ends.push_back(b);
            result.cost += line_cost(line, previous, p);
            previous = line_class(line);
            a = b;
        }
        return result;
    }
    const Integer inf = std::numeric_limits<Integer>::max();
    std::vector<std::array<Integer, 4>> costs(count + 1);
    std::vector<std::array<std::pair<int, int>, 4>> previous(count + 1);
    for (auto &row : costs)
        row.fill(inf);
    costs[0][1] = 0;
    for (int b = 1; b <= count; ++b)
        for (int a = 0; a < b; ++a) {
            const Measure line = measure(a, b);
            if (line.slack < 0 && b != a + 1)
                continue;
            const int c = line_class(line);
            for (int pc = 0; pc < 4; ++pc) {
                if (costs[a][pc] == inf)
                    continue;
                const Integer value = costs[a][pc] + line_cost(line, pc, p);
                if (value < costs[b][c]) {
                    costs[b][c] = value;
                    previous[b][c] = {a, pc};
                }
            }
        }
    result.cost = costs[count][1];
    int b = count, c = 1;
    while (b > 0) {
        result.ends.push_back(b);
        const auto pair = previous[b][c];
        b = pair.first;
        c = pair.second;
    }
    std::reverse(result.ends.begin(), result.ends.end());
    return result;
}
