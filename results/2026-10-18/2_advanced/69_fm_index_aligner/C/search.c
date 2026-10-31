#include "aligner.h"
int *lower_bounds(const char *sequence, const Index *reverse) {
    int length = (int)strlen(sequence), *out = malloc((size_t)length * sizeof(int)), mismatches = 0;
    Interval interval = {0, reverse->size};
    for (int i = 0; i < length; ++i) {
        interval = extend(reverse, interval, sequence[i]);
        if (interval.lower >= interval.upper) {
            ++mismatches;
            interval = (Interval){0, reverse->size};
        }
        out[i] = mismatches;
    }
    return out;
}
Search backtrack(const char *sequence, int maximum, const Index *forward, const Index *reverse) {
    typedef struct {
        int position, remaining;
        Interval interval;
    } State;
    int *bounds = lower_bounds(sequence, reverse);
    int count = 1, capacity = 128;
    State *stack = malloc((size_t)capacity * sizeof(State));
    stack[0] = (State){(int)strlen(sequence) - 1, maximum, {0, forward->size}};
    Search out = {0};
    while (count) {
        State state = stack[--count];
        ++out.nodes;
        if (state.remaining < (state.position < 0 ? 0 : bounds[state.position]))
            continue;
        if (state.position == -1) {
            if (out.leaf_count == out.capacity) {
                out.capacity = out.capacity ? out.capacity * 2 : 16;
                out.leaves = realloc(out.leaves, (size_t)out.capacity * sizeof(Leaf));
            }
            out.leaves[out.leaf_count++] =
                (Leaf){state.interval.lower, state.interval.upper, maximum - state.remaining};
            out.positions += state.interval.upper - state.interval.lower;
            continue;
        }
        for (int b = 0; b < 4; ++b) {
            char base = "TGCA"[b];
            Interval next = extend(forward, state.interval, base);
            if (next.lower >= next.upper)
                continue;
            int mismatch = base != sequence[state.position];
            if (!mismatch || state.remaining >= 1) {
                if (count == capacity) {
                    capacity *= 2;
                    stack = realloc(stack, (size_t)capacity * sizeof(State));
                }
                stack[count++] = (State){state.position - 1, state.remaining - mismatch, next};
            }
        }
    }
    free(bounds);
    free(stack);
    return out;
}
