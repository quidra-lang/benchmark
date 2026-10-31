#include "mining.hpp"
Input read_inputs() {
    Input out;
    std::ifstream events("input/eventlog.csv");
    std::string text;
    std::getline(events, text);
    int number = 2;
    while (std::getline(events, text)) {
        std::istringstream row(text);
        Row value;
        value.line = number++;
        std::getline(row, value.case_id, ',');
        std::getline(row, value.activity, ',');
        std::getline(row, value.timestamp, ',');
        std::getline(row, value.resource);
        out.rows.push_back(value);
    }
    std::ifstream parameters("input/params.txt");
    std::string key, value;
    while (parameters >> key >> value)
        out.parameters[key] = value;
    return out;
}
std::optional<I> timestamp_minutes(const std::string &timestamp) {
    const std::array<int, 12> days{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    int month = std::stoi(timestamp.substr(5, 2)), day = std::stoi(timestamp.substr(8, 2)),
        hour = std::stoi(timestamp.substr(11, 2)), minute = std::stoi(timestamp.substr(14, 2));
    if (month < 1 || month > 12 || day < 1 || day > days[month - 1] || hour > 23 || minute > 59)
        return {};
    I before = 0;
    for (int i = 0; i < month - 1; ++i)
        before += days[i];
    return ((before + day - 1) * 24 + hour) * 60 + minute;
}
std::vector<Case> group_cases(const std::vector<Event> &events) {
    std::map<std::string, std::vector<Event>> grouped;
    for (const Event &event : events)
        grouped[event.case_id].push_back(event);
    std::vector<Case> out;
    for (auto &entry : grouped) {
        Case item;
        item.id = entry.first;
        item.events = std::move(entry.second);
        std::sort(item.events.begin(), item.events.end(), [](const Event &a, const Event &b) {
            return std::tie(a.time, a.line) < std::tie(b.time, b.line);
        });
        for (const Event &event : item.events)
            item.trace.push_back(event.activity);
        item.duration = item.events.back().time - item.events.front().time;
        out.push_back(std::move(item));
    }
    return out;
}
Fraction median(std::vector<I> values) {
    std::sort(values.begin(), values.end());
    int size = int(values.size());
    return size % 2 ? Fraction(values[size / 2])
                    : Fraction(values[size / 2 - 1] + values[size / 2], 2);
}
