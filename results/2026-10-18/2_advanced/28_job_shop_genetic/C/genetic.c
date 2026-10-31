#include "scheduler.h"
Schedule decode(const Instance *data, const Chromosome *genes) {
    int next[14] = {0}, ready[14] = {0}, free_time[10] = {0}, starts[100] = {0};
    for (int i = 0; i < genes->count; ++i)
        for (int j = 0; j < data->job_count; ++j) {
            const Job *job = &data->jobs[j];
            int number = genes->ids[i];
            if (job->number != number)
                continue;
            int id = job->operations.ids[next[number]++];
            Operation op = data->operations[id];
            starts[id] = ready[number] > free_time[op.machine] ? ready[number] : free_time[op.machine];
            ready[number] = free_time[op.machine] = starts[id] + op.duration;
            break;
        }
    return from_starts(data, starts);
}
int tournament(Minstd *random, const int *values, int count, int size) {
    int best = -1;
    for (int i = 0; i < size; ++i) {
        int index = below(random, count);
        if (best < 0 || values[index] < values[best] || (values[index] == values[best] && index < best))
            best = index;
    }
    return best;
}
static Chromosome child(const Chromosome *first, const Chromosome *second, const bool *selected) {
    Chromosome result = {.count = first->count};
    for (int i = 0; i < first->count; ++i)
        if (selected[first->ids[i]])
            result.ids[i] = first->ids[i];
    int next = 0;
    for (int i = 0; i < second->count; ++i)
        if (!selected[second->ids[i]]) {
            while (result.ids[next])
                ++next;
            result.ids[next++] = second->ids[i];
        }
    return result;
}
void crossover(Minstd *random, const Instance *data, const Chromosome *first, const Chromosome *second,
               Chromosome *a, Chromosome *b) {
    bool selected[14] = {0};
    for (int j = 0; j < data->job_count; ++j)
        selected[data->jobs[j].number] = below(random, 2) == 0;
    *a = child(first, second, selected);
    *b = child(second, first, selected);
}
void swap_mutation(Minstd *random, Chromosome *genes) {
    int a = below(random, genes->count), b = below(random, genes->count), value = genes->ids[a];
    genes->ids[a] = genes->ids[b];
    genes->ids[b] = value;
}
void insertion_mutation(Minstd *random, Chromosome *genes) {
    int a = below(random, genes->count), b = below(random, genes->count), value = genes->ids[a];
    if (a < b)
        memmove(genes->ids + a, genes->ids + a + 1, (size_t)(b - a) * sizeof(int));
    else if (a > b)
        memmove(genes->ids + b + 1, genes->ids + b, (size_t)(a - b) * sizeof(int));
    genes->ids[b] = value;
}
