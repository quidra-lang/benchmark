#include "timezone.h"

int period_index(const Timeline *timeline, Integer time) {
    int low = 0, high = timeline->count;
    while (low < high) {
        int middle = low + (high - low) / 2;
        if (timeline->items[middle].start <= time) low = middle + 1; else high = middle;
    }
    return low - 1;
}
Integer period_end(const Timeline *timeline, int index) { return index + 1 < timeline->count ? timeline->items[index + 1].start : POS_INFINITY; }
Candidates candidates(const Timeline *timeline, Integer local) {
    Candidates result = {0};
    int first = period_index(timeline, local - 57600), last = period_index(timeline, local + 57600);
    for (int i = first; i <= last; ++i) {
        Integer time = local - timeline->items[i].offset;
        if (timeline->items[i].start <= time && time < period_end(timeline, i)) result.indices[result.count++] = i;
    }
    return result;
}
int skipping_transition(const Timeline *timeline, Integer local) {
    int first = period_index(timeline, local - 57600), last = period_index(timeline, local + 57600);
    for (int i = first; i <= last; ++i) if (i > 0) {
        Integer time = timeline->items[i].start;
        if (time + timeline->items[i - 1].offset <= local && local < time + timeline->items[i].offset) return i;
    }
    return -1;
}
