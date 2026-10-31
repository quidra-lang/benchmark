#include "segments.hpp"

std::vector<NamingRule> readRules(const std::string& path) {
    std::vector<NamingRule> rules;
    for (const std::string& line : readLines(path)) {
        Lines fields = split(line, ' ');
        NamingRule rule{fields.front(), {}};
        for (std::size_t i = 1; i < fields.size(); i += 3) {
            std::size_t feature = static_cast<std::size_t>(std::find(featureNames.begin(), featureNames.end(), fields[i]) - featureNames.begin());
            rule.conditions.push_back({feature, fields[i + 1] == ">", std::stod(fields[i + 2])});
        }
        rules.push_back(std::move(rule));
    }
    return rules;
}
int ruleNumber(const std::vector<NamingRule>& rules, const Point& center) {
    for (int i = 0; i < static_cast<int>(rules.size()); ++i) {
        bool accepted = true;
        for (const NamingCondition& condition : rules[i].conditions) {
            bool holds = condition.greater ? center[condition.feature] > condition.threshold : center[condition.feature] < condition.threshold;
            if (!holds) accepted = false;
        }
        if (accepted) return i;
    }
    return -1;
}
Point originalScale(const Point& center, const Point& means, const Point& deviations) {
    Point result;
    for (std::size_t f = 0; f < center.size(); ++f) { double value = means[f] + deviations[f] * center[f]; result.push_back(sqrtFeatures[f] ? value * value : value); }
    return result;
}
