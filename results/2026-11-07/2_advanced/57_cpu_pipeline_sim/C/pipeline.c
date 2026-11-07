#include "simulator.h"
Run simulate(const Instruction *instructions, const Sources *sources, int count, Variant variant,
             const bool *flags) {
    Run out = {0};
    out.timings = allocate((size_t)count, sizeof(*out.timings));
    out.records = allocate((size_t)count * 4 + 1, sizeof(*out.records));
    for (int i = 0; i < count; ++i) {
        Timing *time = &out.timings[i];
        int execute = instructions[i].kind == MUL ? variant.latency : 1;
        if (i == 0) {
            time->f = 1;
            time->d = 2;
            time->x = 3;
        } else {
            Timing previous = out.timings[i - 1];
            time->f =
                flags[i - 1] ? previous.x + !id_resolved(instructions[i - 1], variant) : previous.d;
            time->d = time->f + 1 > previous.x ? time->f + 1 : previous.x;
            int ideal = previous.x + 1;
            int bound[4] = {time->d + 1, previous.m, ideal, ideal}, producer[4] = {-1, -1, -1, -1};
            for (int j = 0; j < 2; ++j) {
                int p = sources[i].producer[j];
                if (p < 0)
                    continue;
                int cause = instructions[p].kind == LOAD ? 2 : 3;
                int ready = ready_cycle(instructions[i], instructions[p], out.timings[p], variant);
                if (ready > bound[cause]) {
                    bound[cause] = ready;
                    producer[cause] = p;
                }
            }
            time->x = ideal;
            for (int cause = 0; cause < 4; ++cause)
                if (bound[cause] > time->x) {
                    out.records[out.count++] = (Record){cause, bound[cause] - time->x,
                                                        cause < 2 ? i - 1 : i, i, producer[cause]};
                    time->x = bound[cause];
                }
        }
        time->m = time->x + execute;
        time->w = time->m + 1;
    }
    if (instructions[count - 1].kind == MUL && variant.latency >= 2)
        out.records[out.count++] = (Record){1, variant.latency - 1, count - 1, -1, -1};
    for (int i = 0; i < out.count; ++i) {
        Record record = out.records[i];
        out.stalls[record.cause] += record.cycles;
        ++out.events[record.cause];
    }
    out.cycles = out.timings[count - 1].w;
    return out;
}
void free_run(Run *run) {
    free(run->timings);
    free(run->records);
}
