#include "timetable.h"

int saturation(const Scheduler *scheduler, int course, const int *assignment) {
    bool seen[MAX_SLOTS + 1] = {false}; int count = 0;
    for (int n = 0; n < scheduler->course_count; ++n)
        if (scheduler->shared[course][n] && assignment[n] && !seen[assignment[n]]) {
            seen[assignment[n]] = true; ++count;
        }
    return count;
}
bool search_attempt(Attempt *attempt) {
    Scheduler *scheduler = attempt->scheduler;
    int chosen = -1, best_saturation = -1;
    for (int i = 0; i < attempt->pending.count; ++i) {
        int c = attempt->pending.items[i];
        if (scheduler->assignment[c]) continue;
        int value = saturation(scheduler, c, scheduler->assignment);
        if (chosen < 0 || value > best_saturation ||
            (value == best_saturation && (scheduler->degree[c] > scheduler->degree[chosen] ||
             (scheduler->degree[c] == scheduler->degree[chosen] && c < chosen)))) {
            chosen = c; best_saturation = value;
        }
    }
    if (chosen < 0) return true;
    int depth = attempt->choice_count++;
    attempt->choices[depth] = (Choice){chosen, 0, best_saturation};
    Courses slots = candidate_slots(scheduler, chosen, scheduler->assignment);
    for (int i = 0; i < slots.count; ++i) {
        scheduler->assignment[chosen] = slots.items[i];
        attempt->choices[depth].slot = slots.items[i];
        if (search_attempt(attempt)) return true;
        scheduler->assignment[chosen] = 0;
        if (attempt->aborted) return false;
    }
    --attempt->choice_count;
    ++attempt->dead_ends; attempt->dead_end_course = chosen;
    attempt->aborted = attempt->dead_ends > scheduler->limit;
    return false;
}
int greedy_numbering(const Scheduler *scheduler, Courses order) {
    int numbers[MAX_COURSES] = {0}, maximum = 0;
    for (int i = 0; i < order.count; ++i) {
        int c = order.items[i], number = 1; bool taken[MAX_COURSES + 1] = {false};
        for (int n = 0; n < scheduler->course_count; ++n) if (scheduler->shared[c][n]) taken[numbers[n]] = true;
        while (taken[number]) ++number;
        numbers[c] = number;
        if (number > maximum) maximum = number;
    }
    return maximum;
}
