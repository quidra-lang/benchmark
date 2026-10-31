#include "mining.hpp"
I count(const Counts &counts, const std::string &a, const std::string &b) {
    auto entry = counts.find({a, b});
    return entry == counts.end() ? 0 : entry->second;
}
Counts directly_follows(const Log &log) {
    Counts out;
    for (const auto &entry : log)
        for (int i = 1; i < int(entry.first.size()); ++i)
            out[{entry.first[i - 1], entry.first[i]}] += entry.second;
    return out;
}
std::string basic_relation(const Counts &counts, const std::string &a, const std::string &b) {
    bool forward = count(counts, a, b) > 0, backward = count(counts, b, a) > 0;
    if (forward && !backward)
        return "->";
    if (backward && !forward)
        return "<-";
    return forward ? "||" : "#";
}
Lines table(const std::vector<Names> &rows, int width) {
    Lines out;
    std::ostringstream heading;
    heading << "    ";
    for (int i = 1; i <= int(rows.size()); ++i)
        heading << std::setw(width) << i;
    out.push_back(heading.str());
    for (int i = 0; i < int(rows.size()); ++i) {
        std::ostringstream row;
        row << std::setw(4) << i + 1;
        for (const std::string &value : rows[i])
            row << std::setw(width) << value;
        out.push_back(row.str());
    }
    return out;
}
Lines footprint(const Names &activities, const Relation &relation) {
    Lines out;
    std::vector<Names> rows;
    for (int i = 0; i < int(activities.size()); ++i) {
        line(out, "ACTIVITY ", i + 1, " ", activities[i]);
        Names row;
        for (const std::string &activity : activities)
            row.push_back(relation(activities[i], activity));
        rows.push_back(row);
    }
    Lines cells = table(rows, 4);
    out.insert(out.end(), cells.begin(), cells.end());
    return out;
}
