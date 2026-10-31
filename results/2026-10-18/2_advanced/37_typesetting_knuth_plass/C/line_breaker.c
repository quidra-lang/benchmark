#include "typesetting.h"
int line_class(Measure line) {
    return line.last ? 1 : line.slack <= 1 ? 0 : line.slack <= 3 ? 1 : line.slack <= 6 ? 2 : 3;
}
Integer line_cost(Measure line, int previous, const Params *p) {
    Integer result = p->line_penalty + (line.slack < 0 ? p->overfull_penalty
                                        : line.last    ? 0
                                                       : (Integer)line.slack * line.slack);
    if (line.mid) {
        result += p->hyphen_penalty;
        if (line.previous_mid)
            result += p->double_hyphen_demerit;
    }
    if (line.last && line.previous_mid)
        result += p->final_hyphen_demerit;
    if (abs(line_class(line) - previous) >= 2)
        result += p->fitness_demerit;
    return result;
}
Breaking break_lines(int count, MeasureLine measure, void *context, const Params *p, bool greedy) {
    Breaking out = {0};
    if (greedy) {
        int a = 0, previous = 1;
        while (a < count) {
            int b = a + 1;
            if (measure(context, a, b).slack >= 0)
                for (int next = b + 1; next <= count; ++next)
                    if (measure(context, a, next).slack >= 0)
                        b = next;
            Measure line = measure(context, a, b);
            int_add(&out.ends, b);
            out.cost += line_cost(line, previous, p);
            previous = line_class(line);
            a = b;
        }
        return out;
    }
    Integer(*costs)[4] = allocate((size_t)count + 1, sizeof *costs);
    int (*previous_a)[4] = allocate((size_t)count + 1, sizeof *previous_a),
        (*previous_class)[4] = allocate((size_t)count + 1, sizeof *previous_class);
    for (int b = 0; b <= count; ++b)
        for (int c = 0; c < 4; ++c)
            costs[b][c] = INT64_MAX;
    costs[0][1] = 0;
    for (int b = 1; b <= count; ++b)
        for (int a = 0; a < b; ++a) {
            Measure line = measure(context, a, b);
            if (line.slack < 0 && b != a + 1)
                continue;
            int c = line_class(line);
            for (int pc = 0; pc < 4; ++pc) {
                if (costs[a][pc] == INT64_MAX)
                    continue;
                Integer value = costs[a][pc] + line_cost(line, pc, p);
                if (value < costs[b][c]) {
                    costs[b][c] = value;
                    previous_a[b][c] = a;
                    previous_class[b][c] = pc;
                }
            }
        }
    out.cost = costs[count][1];
    int b = count, c = 1;
    while (b > 0) {
        int_add(&out.ends, b);
        int a = previous_a[b][c], pc = previous_class[b][c];
        b = a;
        c = pc;
    }
    for (size_t i = 0; i < out.ends.len / 2; ++i) {
        int value = out.ends.data[i];
        out.ends.data[i] = out.ends.data[out.ends.len - 1 - i];
        out.ends.data[out.ends.len - 1 - i] = value;
    }
    free(costs);
    free(previous_a);
    free(previous_class);
    return out;
}
