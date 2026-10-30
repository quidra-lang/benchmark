#include "policy.h"
int point_count(Domains domains) {
    int count = 1;
    for (size_t i = 0; i < domains.count; ++i)
        count *= (int)domains.items[i].candidates.count;
    return count;
}
Attributes domain_point(Domains domains, int ordinal) {
    Attributes values = {0};
    int divisor = point_count(domains);
    for (size_t i = 0; i < domains.count; ++i) {
        Domain d = domains.items[i];
        divisor /= (int)d.candidates.count;
        int index = ordinal / divisor % (int)d.candidates.count;
        set_attribute(&values, d.reference, d.candidates.items[index]);
    }
    return values;
}
char *day_notation(Days days) {
    Names runs = {0};
    for (int day = 1; day <= 365; ++day)
        if (days.days[day]) {
            int first = day;
            while (day < 365 && days.days[day + 1])
                ++day;
            Names_add(&runs, format("%d-%d", first, day));
        }
    return join(runs, ",");
}
Element *blocker(Element *rule, const Decision standalone[100]) {
    for (size_t i = 0; i < rule->parent->children.count; ++i) {
        Element *earlier = rule->parent->children.items[i];
        if (earlier == rule)
            break;
        if (standalone[earlier->index] != D_NA)
            return earlier;
    }
    return NULL;
}
Element *conflict_winner(Element *policy, Element *earlier, Element *later) {
    if (!strcmp(policy->behavior, "first-applicable"))
        return earlier;
    char *effect = !strcmp(policy->behavior, "deny-overrides") ||
                           !strcmp(policy->behavior, "permit-unless-deny")
                       ? "DENY"
                       : "PERMIT";
    return !strcmp(earlier->behavior, effect) ? earlier : later;
}
