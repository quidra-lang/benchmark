#include "mining.hpp"
Names mask_names(unsigned mask, const Names &activities) {
    Names out;
    for (int i = 0; i < int(activities.size()); ++i)
        if (mask & (1u << i))
            out.push_back(activities[i]);
    return out;
}
std::optional<Candidate> extend_pair(Candidate pair, int activity, int side,
                                     const Names &activities, const Relation &relation) {
    unsigned group = side == 0 ? pair.first : pair.second,
             other = side == 0 ? pair.second : pair.first, bit = 1u << activity;
    const std::string &name = activities[activity];
    if ((group & bit) || relation(name, name) != "#")
        return {};
    for (int i = 0; i < int(activities.size()); ++i) {
        if ((group & (1u << i)) && relation(name, activities[i]) != "#")
            return {};
        if (other & (1u << i)) {
            std::string value =
                side == 0 ? relation(name, activities[i]) : relation(activities[i], name);
            if (value != "->")
                return {};
        }
    }
    if (side == 0)
        pair.first |= bit;
    else
        pair.second |= bit;
    return pair;
}
static std::vector<int> sequence(unsigned mask) {
    std::vector<int> out;
    for (int i = 0; i < 12; ++i)
        if (mask & (1u << i))
            out.push_back(i);
    return out;
}
bool pair_order(Candidate a, Candidate b) {
    if (a.first != b.first)
        return sequence(a.first) < sequence(b.first);
    return sequence(a.second) < sequence(b.second);
}
Counts triangle_counts(const Log &log) {
    Counts out;
    for (const auto &entry : log)
        for (int i = 0; i + 2 < int(entry.first.size()); ++i)
            if (entry.first[i] == entry.first[i + 2] && entry.first[i] != entry.first[i + 1])
                out[{entry.first[i], entry.first[i + 1]}] += entry.second;
    return out;
}
std::string plus_relation(const Counts &counts, const Counts &triangles, const std::string &a,
                          const std::string &b) {
    bool forward = count(counts, a, b) > 0, backward = count(counts, b, a) > 0,
         loop = a != b && count(triangles, a, b) > 0 && count(triangles, b, a) > 0;
    if (forward && (!backward || loop))
        return "->";
    if (backward && (!forward || loop))
        return "<-";
    return forward && backward ? "||" : "#";
}
