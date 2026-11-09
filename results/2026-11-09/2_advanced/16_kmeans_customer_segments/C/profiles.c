#include "segments.h"

Rules read_rules(void) {
    Lines lines = read_lines("input/segment_rules.txt");
    Rules result = {.items = allocate((size_t)lines.count * sizeof(Rule)), .count = lines.count};
    for (int r = 0; r < lines.count; ++r) {
        char **parts = allocate((strlen(lines.items[r]) + 1) * sizeof(char *));
        int count = split_fields(lines.items[r], " ", parts);
        Rule *rule = &result.items[r];
        rule->name = parts[0]; rule->count = (count - 1) / 3;
        rule->conditions = allocate((size_t)rule->count * sizeof(Condition));
        for (int c = 0; c < rule->count; ++c) {
            int f = 0;
            while (strcmp(feature_names[f], parts[1 + 3 * c])) ++f;
            rule->conditions[c] = (Condition){f, !strcmp(parts[2 + 3 * c], ">"), atof(parts[3 + 3 * c])};
        }
    }
    return result;
}
int matching_rule(Rules rules, const double *center) {
    for (int r = 0; r < rules.count; ++r) {
        bool holds = true;
        for (int c = 0; c < rules.items[r].count; ++c) {
            Condition condition = rules.items[r].conditions[c];
            if (!(condition.greater ? center[condition.feature] > condition.threshold : center[condition.feature] < condition.threshold)) { holds = false; break; }
        }
        if (holds) return r;
    }
    exit(EXIT_FAILURE);
}
void original_scale(const double *center, const Scaling *scaling, double *result) {
    for (int f = 0; f < 6; ++f) { double value = scaling->mean[f] + scaling->sd[f] * center[f]; result[f] = f >= 1 && f <= 3 ? value * value : value; }
}
