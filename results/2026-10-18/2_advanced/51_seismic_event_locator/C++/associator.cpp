#include "seismic.hpp"
std::vector<Candidate> associate(std::vector<Pick> &picks, const Params &p) {
    std::vector<Candidate> candidates;
    for (int i = 0; i < int(picks.size()); ++i) {
        if (picks[i].assigned)
            continue;
        std::array<bool, 12> seen{};
        Candidate c;
        c.first = i;
        for (int j = i; j < int(picks.size()) && picks[j].sample <= picks[i].sample + p.window; ++j)
            if (!picks[j].assigned && !seen[picks[j].station]) {
                seen[picks[j].station] = true;
                c.picks.push_back(j);
            }
        if (c.picks.size() < std::size_t(p.minimum))
            continue;
        for (int j : c.picks)
            picks[j].assigned = true;
        candidates.push_back(std::move(c));
    }
    return candidates;
}
