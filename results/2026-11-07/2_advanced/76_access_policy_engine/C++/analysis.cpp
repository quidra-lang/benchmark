#include "policy.hpp"
std::vector<Attributes> points(const std::vector<Domain> &domains) {
    std::vector<Attributes> result(1);
    for (const Domain &domain : domains) {
        std::vector<Attributes> expanded;
        for (const Attributes &point : result)
            for (const Value &value : domain.candidates) {
                Attributes next = point;
                next[domain.reference] = value;
                expanded.push_back(std::move(next));
            }
        result = std::move(expanded);
    }
    return result;
}
std::string day_notation(const Days &days) {
    Names runs;
    for (int day = 1; day <= 365; ++day)
        if (days[day]) {
            int first = day;
            while (day < 365 && days[day + 1])
                ++day;
            runs.push_back(text(first, "-", day));
        }
    return join(runs, ",");
}
Element *blocker(Element *rule, const std::array<Decision, 100> &standalone) {
    for (Element *earlier : rule->parent->children) {
        if (earlier == rule)
            break;
        if (standalone[earlier->index] != Decision::NA)
            return earlier;
    }
    return nullptr;
}
Element *conflict_winner(Element *policy, Element *earlier, Element *later) {
    if (policy->behavior == "first-applicable")
        return earlier;
    std::string effect =
        policy->behavior == "deny-overrides" || policy->behavior == "permit-unless-deny" ? "DENY"
                                                                                         : "PERMIT";
    return earlier->behavior == effect ? earlier : later;
}
