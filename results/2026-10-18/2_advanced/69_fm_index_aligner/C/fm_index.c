#include "aligner.h"
Index build_index(const char *text, const int *suffixes, int occurrence_interval,
                  int sample_interval) {
    Index out = {0};
    out.size = (int)strlen(text);
    out.interval = occurrence_interval;
    out.bwt = malloc((size_t)out.size + 1);
    out.samples = malloc((size_t)out.size * sizeof(int));
    int frequencies[6] = {0};
    for (int i = 0; i < out.size; ++i)
        ++frequencies[symbol_number(text[i])];
    int offset = 0;
    for (int i = 0; i < 6; ++i) {
        out.C[i] = offset;
        offset += frequencies[i];
    }
    for (int row = 0; row < out.size; ++row) {
        int position = suffixes[row];
        out.bwt[row] = text[position ? position - 1 : out.size - 1];
        out.samples[row] = -1;
        if (sample_interval && position % sample_interval == 0) {
            out.samples[row] = position;
            ++out.sample_count;
        }
    }
    out.bwt[out.size] = 0;
    out.checkpoint_count = out.size / occurrence_interval + 1;
    out.checkpoints = calloc((size_t)out.checkpoint_count, sizeof(*out.checkpoints));
    int counts[6] = {0}, checkpoint = 1;
    for (int i = 0; i < out.size; ++i) {
        ++counts[symbol_number(out.bwt[i])];
        if ((i + 1) % occurrence_interval == 0)
            memcpy(out.checkpoints[checkpoint++], counts, sizeof counts);
    }
    return out;
}
int occurrence(const Index *index, char symbol, int position) {
    int checkpoint = position / index->interval,
        count = index->checkpoints[checkpoint][symbol_number(symbol)];
    for (int i = checkpoint * index->interval; i < position; ++i)
        count += index->bwt[i] == symbol;
    return count;
}
int lf(const Index *index, int row) {
    char symbol = index->bwt[row];
    return index->C[symbol_number(symbol)] + occurrence(index, symbol, row);
}
Interval extend(const Index *index, Interval interval, char base) {
    if (base == 'N')
        return (Interval){0, 0};
    int start = index->C[symbol_number(base)];
    return (Interval){start + occurrence(index, base, interval.lower),
                      start + occurrence(index, base, interval.upper)};
}
Interval backward_search(const Index *index, const char *sequence) {
    Interval out = {0, index->size};
    for (int i = (int)strlen(sequence) - 1; i >= 0; --i) {
        out = extend(index, out, sequence[i]);
        if (out.lower >= out.upper)
            break;
    }
    return out;
}
int locate(const Index *index, int row, int *steps) {
    *steps = 0;
    while (index->samples[row] < 0) {
        row = lf(index, row);
        ++*steps;
    }
    return index->samples[row] + *steps;
}
char *inverse(const Index *index) {
    char *out = malloc((size_t)index->size + 1);
    out[index->size] = 0;
    out[index->size - 1] = '$';
    int row = 0;
    for (int p = index->size - 2; p >= 0; --p) {
        out[p] = index->bwt[row];
        row = lf(index, row);
    }
    return out;
}
