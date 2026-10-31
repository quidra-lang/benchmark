#include "survival.h"
void finalize_test(GroupTest *test) {
    int size = test->count - 1;
    Vector difference = {0};
    for (int g = 0; g < size; ++g)
        difference.v[g] = test->observed.v[g] - test->expected.v[g];
    Vector solution = solve(test->covariance, difference, size);
    test->statistic = 0;
    for (int g = 0; g < size; ++g)
        test->statistic += difference.v[g] * solution.v[g];
    test->degrees = size;
    test->p = p_value(test->statistic, size);
}
GroupTest weighted_test(const Subjects *subjects, const int *groups, int group_count, int kind,
                        int total_subjects) {
    GroupTest out = {.count = group_count};
    memcpy(out.groups, groups, (size_t)group_count * sizeof(int));
    IntList times = event_times(subjects);
    for (int i = 0; i < times.count; ++i) {
        int time = times.data[i], n[6] = {0}, d[6] = {0}, risk = 0, events = 0;
        for (int j = 0; j < subjects->count; ++j) {
            const Subject *subject = &subjects->data[j];
            int group = 0;
            while (groups[group] != subject->group)
                ++group;
            n[group] += subject->time >= time;
            d[group] += subject->time == time && subject->event == 1;
        }
        for (int g = 0; g < group_count; ++g) {
            risk += n[g];
            events += d[g];
        }
        double weight = kind == 0   ? 1
                        : kind == 1 ? (double)risk / total_subjects
                                    : sqrt((double)risk / total_subjects);
        for (int g = 0; g < group_count; ++g) {
            out.events[g] += d[g];
            out.observed.v[g] += weight * d[g];
            out.expected.v[g] += weight * ((double)(events * n[g]) / risk);
            if (risk >= 2)
                for (int h = 0; h < group_count; ++h) {
                    int multiplier = g == h ? n[g] * (risk - n[g]) : -(n[g] * n[h]);
                    out.covariance.v[g][h] +=
                        weight * weight * ((double)(events * (risk - events)) / ((risk - 1) * risk * risk)) *
                        multiplier;
                }
        }
    }
    free(times.data);
    finalize_test(&out);
    return out;
}
GroupTest combine_tests(const GroupTest *tests, int count) {
    GroupTest out = {.count = tests[0].count};
    memcpy(out.groups, tests[0].groups, (size_t)out.count * sizeof(int));
    for (int i = 0; i < count; ++i)
        for (int g = 0; g < out.count; ++g) {
            out.events[g] += tests[i].events[g];
            out.observed.v[g] += tests[i].observed.v[g];
            out.expected.v[g] += tests[i].expected.v[g];
            for (int h = 0; h < out.count; ++h)
                out.covariance.v[g][h] += tests[i].covariance.v[g][h];
        }
    finalize_test(&out);
    return out;
}
