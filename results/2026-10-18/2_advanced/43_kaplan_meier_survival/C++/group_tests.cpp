#include "survival.hpp"
void finalize_test(GroupTest &test) {
    const int size = test.groups.size() - 1;
    Vector difference{};
    for (int g = 0; g < size; ++g)
        difference[g] = test.observed[g] - test.expected[g];
    const Vector solution = solve(test.covariance, difference, size);
    test.statistic = 0;
    for (int g = 0; g < size; ++g)
        test.statistic += difference[g] * solution[g];
    test.degrees = size;
    test.p = p_value(test.statistic, size);
}
GroupTest weighted_test(const Subjects &subjects, const std::vector<int> &groups, int kind,
                        int total_subjects) {
    GroupTest out;
    out.groups = groups;
    for (int time : event_times(subjects)) {
        std::array<int, 6> n{}, d{};
        for (const Subject &subject : subjects) {
            const int group = std::find(groups.begin(), groups.end(), subject.group) - groups.begin();
            n[group] += subject.time >= time;
            d[group] += subject.time == time && subject.event == 1;
        }
        const int risk = std::accumulate(n.begin(), n.end(), 0),
                  events = std::accumulate(d.begin(), d.end(), 0);
        const double weight = kind == 0   ? 1
                              : kind == 1 ? double(risk) / total_subjects
                                          : std::sqrt(double(risk) / total_subjects);
        for (std::size_t g = 0; g < groups.size(); ++g) {
            out.events[g] += d[g];
            out.observed[g] += weight * d[g];
            out.expected[g] += weight * (double(events * n[g]) / risk);
            if (risk >= 2)
                for (std::size_t h = 0; h < groups.size(); ++h) {
                    const int multiplier = g == h ? n[g] * (risk - n[g]) : -(n[g] * n[h]);
                    out.covariance[g][h] += weight * weight *
                                            (double(events * (risk - events)) / ((risk - 1) * risk * risk)) *
                                            multiplier;
                }
        }
    }
    finalize_test(out);
    return out;
}
GroupTest combine_tests(const std::vector<GroupTest> &tests) {
    GroupTest out;
    out.groups = tests[0].groups;
    for (const GroupTest &test : tests)
        for (std::size_t g = 0; g < out.groups.size(); ++g) {
            out.events[g] += test.events[g];
            out.observed[g] += test.observed[g];
            out.expected[g] += test.expected[g];
            for (std::size_t h = 0; h < out.groups.size(); ++h)
                out.covariance[g][h] += test.covariance[g][h];
        }
    finalize_test(out);
    return out;
}
