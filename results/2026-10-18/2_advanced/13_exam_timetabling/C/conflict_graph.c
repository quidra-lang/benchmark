#include "timetable.h"

void build_graph(Scheduler *scheduler) {
    for (int s = 0; s < scheduler->student_count; ++s) {
        const Student *student = &scheduler->students[s];
        for (int i = 0; i < student->count; ++i)
            for (int j = i + 1; j < student->count; ++j) {
                int a = student->courses[i], b = student->courses[j];
                ++scheduler->shared[a][b]; ++scheduler->shared[b][a];
            }
    }
    for (int a = 0; a < scheduler->course_count; ++a)
        for (int b = 0; b < scheduler->course_count; ++b)
            if (scheduler->shared[a][b]) ++scheduler->degree[a];
}
int components(const Scheduler *scheduler, Component *result) {
    bool seen[MAX_COURSES] = {false}; int count = 0;
    for (int v = 0; v < scheduler->course_count; ++v) {
        if (!scheduler->courses[v].size || seen[v]) continue;
        Courses group = { .items = {v}, .count = 1 }; seen[v] = true;
        for (int index = 0; index < group.count; ++index)
            for (int n = 0; n < scheduler->course_count; ++n)
                if (scheduler->shared[group.items[index]][n] && !seen[n]) {
                    seen[n] = true; group.items[group.count++] = n;
                }
        for (int i = 1; i < group.count; ++i) {
            int item = group.items[i], j = i;
            while (j > 0 && group.items[j - 1] > item) { group.items[j] = group.items[j - 1]; --j; }
            group.items[j] = item;
        }
        int j = count++;
        while (j > 0 && (result[j - 1].members.count < group.count ||
               (result[j - 1].members.count == group.count && result[j - 1].members.items[0] > group.items[0]))) {
            result[j] = result[j - 1]; --j;
        }
        result[j].members = group;
    }
    return count;
}
Courses greedy_clique(const Scheduler *scheduler) {
    Courses candidates = scheduler->schedulable, result = {0};
    while (candidates.count) {
        sort_courses(scheduler, &candidates, scheduler->degree);
        int chosen = candidates.items[0]; result.items[result.count++] = chosen;
        int count = 0;
        for (int i = 0; i < candidates.count; ++i)
            if (scheduler->shared[chosen][candidates.items[i]]) candidates.items[count++] = candidates.items[i];
        candidates.count = count;
    }
    return result;
}
Courses kempe_chain(const Scheduler *scheduler, int start, int home, int target) {
    bool seen[MAX_COURSES] = {false}; Courses result = { .items = {start}, .count = 1 }; seen[start] = true;
    for (int i = 0; i < result.count; ++i)
        for (int n = 0; n < scheduler->course_count; ++n)
            if (!seen[n] && scheduler->shared[result.items[i]][n] &&
                (scheduler->assignment[n] == home || scheduler->assignment[n] == target)) {
                seen[n] = true; result.items[result.count++] = n;
            }
    result.count = 0;
    for (int c = 0; c < scheduler->course_count; ++c) if (seen[c]) result.items[result.count++] = c;
    return result;
}
bool reachable(const Scheduler *scheduler, int source, int target) {
    bool seen[MAX_COURSES] = {false}; int stack[MAX_COURSES], count = 1; stack[0] = source; seen[source] = true;
    while (count) {
        int current = stack[--count];
        if (current == target) return true;
        for (int i = 0; i < scheduler->order_count; ++i) {
            Order order = scheduler->orders[i];
            if (order.later == current && !seen[order.earlier]) {
                seen[order.earlier] = true; stack[count++] = order.earlier;
            }
        }
    }
    return false;
}
