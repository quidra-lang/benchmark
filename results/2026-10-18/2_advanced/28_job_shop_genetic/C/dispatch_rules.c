#include "scheduler.h"
Schedule dispatch(const Instance *data, const char *rule, const Chromosome *genes) {
    int next[14] = {0}, ready[14] = {0}, free_time[10] = {0}, rank[100] = {0}, starts[100] = {0},
        decisions = 0, ties = 0;
    if (!strcmp(rule, "GENES")) {
        int count[14] = {0};
        for (int i = 0; i < genes->count; ++i)
            for (int j = 0; j < data->job_count; ++j)
                if (data->jobs[j].number == genes->ids[i]) {
                    int number = genes->ids[i];
                    rank[data->jobs[j].operations.ids[count[number]++]] = i + 1;
                    break;
                }
    }
    for (int step = 0; step < data->count; ++step) {
        int candidates[13], earliest[13], count = 0, completion = INT_MAX, machine = INT_MAX;
        for (int j = 0; j < data->job_count; ++j) {
            const Job *job = &data->jobs[j];
            if (next[job->number] >= job->operations.count)
                continue;
            int id = job->operations.ids[next[job->number]];
            Operation op = data->operations[id];
            int start =
                    ready[job->number] > free_time[op.machine] ? ready[job->number] : free_time[op.machine],
                end = start + op.duration;
            candidates[count] = id;
            earliest[count++] = start;
            if (end < completion || (end == completion && op.machine < machine)) {
                completion = end;
                machine = op.machine;
            }
        }
        int selected = -1, best = INT_MAX, conflicts = 0, equal = 0, start = 0;
        for (int i = 0; i < count; ++i) {
            int id = candidates[i];
            Operation op = data->operations[id];
            if (op.machine != machine || earliest[i] >= completion)
                continue;
            ++conflicts;
            int value = !strcmp(rule, "SPT")    ? op.duration
                        : !strcmp(rule, "LPT")  ? -op.duration
                        : !strcmp(rule, "MWKR") ? -(op.duration + op.tail)
                        : !strcmp(rule, "FIFO") ? ready[op.job]
                                                : rank[id];
            if (value < best) {
                selected = id;
                best = value;
                equal = 1;
                start = earliest[i];
            } else if (value == best) {
                ++equal;
                if (op.job < data->operations[selected].job) {
                    selected = id;
                    start = earliest[i];
                }
            }
        }
        if (conflicts >= 2)
            ++decisions;
        if (equal >= 2)
            ++ties;
        Operation op = data->operations[selected];
        starts[selected] = start;
        ready[op.job] = free_time[op.machine] = start + op.duration;
        ++next[op.job];
    }
    Schedule result = from_starts(data, starts);
    result.decisions = decisions;
    result.ties = ties;
    return result;
}
