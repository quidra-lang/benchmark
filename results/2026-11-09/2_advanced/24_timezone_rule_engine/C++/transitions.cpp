#include "timezone.hpp"

std::vector<RuleInstance> instanceSequence(const std::vector<Rule>& rules, const std::vector<std::size_t>& members) {
    std::vector<RuleInstance> instances;
    for (std::size_t index : members) {
        const Rule& rule = rules[index];
        for (int year = rule.from; year <= rule.to; ++year) instances.push_back({index, rule.day.value(year, rule.month) * DaySeconds + rule.at});
    }
    std::sort(instances.begin(), instances.end(), [&rules](const RuleInstance& first, const RuleInstance& second) {
        if (first.nominal != second.nominal) return first.nominal < second.nominal;
        return rules[first.rule].number < rules[second.rule].number;
    });
    return instances;
}
Time adjustment(char type, Time standardOffset, Time save) {
    if (type == 'u') return 0;
    if (type == 's') return standardOffset;
    return standardOffset + save;
}
LineRun runInstances(const std::vector<Rule>& rules, const std::vector<RuleInstance>& instances, Time standardOffset, Time start, const std::optional<Until>& until) {
    LineRun run;
    Time save = 0;
    for (const RuleInstance& instance : instances) {
        const Rule& rule = rules[instance.rule];
        Time time = instance.nominal - adjustment(rule.atType, standardOffset, save);
        if (until && time >= until->value - adjustment(until->type, standardOffset, save)) break;
        if (time <= start) run.preStart.push_back(instance.rule);
        else run.applied.emplace_back(time, instance.rule);
        save = rule.save;
    }
    if (until) run.end = until->value - adjustment(until->type, standardOffset, save);
    return run;
}
std::string abbreviation(const std::string& format, Time save, const std::string& letter) {
    std::size_t slash = format.find('/');
    if (slash != std::string::npos) return save == 0 ? format.substr(0, slash) : format.substr(slash + 1);
    std::string result = format;
    std::size_t position = result.find("%s");
    if (position != std::string::npos) result.replace(position, 2, letter);
    return result;
}
