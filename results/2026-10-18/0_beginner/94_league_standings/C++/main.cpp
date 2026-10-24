#include <iostream>
#include <string>
#include <vector>
#include <array>
#include <algorithm>
#include <sstream>

struct Team {
    std::string name;
    int played = 0, wins = 0, draws = 0, losses = 0, gf = 0, ga = 0, points = 0;
};
void record(Team &t, int gf, int ga) {
    ++t.played;
    t.gf += gf;
    t.ga += ga;
    if (gf > ga) {
        ++t.wins;
        t.points += 3;
    } else if (gf == ga) {
        ++t.draws;
        ++t.points;
    } else
        ++t.losses;
}

int main() {
    std::vector<Team> teams;
    for (const std::string &name : std::array<std::string, 6>{"Lions", "Tigers", "Eagles", "Sharks",
        "Wolves", "Bears"})
        teams.push_back({name});
    for (const std::string &match : std::array<std::string, 15>{"Lions 0-3 Bears", "Tigers 2-2 Wolves",
        "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles", "Lions 0-1 Tigers", "Tigers 3-3 Bears",
        "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves", "Lions 2-0 Sharks", "Tigers 2-1 Eagles",
        "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions"}) {
        std::istringstream input(match);
        std::string home, away;
        char dash;
        int h, a;
        input >> home >> h >> dash >> a >> away;
        int x = 0, y = 0;
        while (teams[x].name != home)
            ++x;
        while (teams[y].name != away)
            ++y;
        record(teams[x], h, a);
        record(teams[y], a, h);
    }
    std::sort(teams.begin(), teams.end(), [](const Team &a, const Team &b) {
        if (a.points != b.points)
            return a.points > b.points;
        if (a.gf - a.ga != b.gf - b.ga)
            return a.gf - a.ga > b.gf - b.ga;
        if (a.gf != b.gf)
            return a.gf > b.gf;
        return a.name < b.name;
    });
    for (std::size_t i = 0; i < teams.size(); i++) {
        const Team &t = teams[i];
        int gd = t.gf - t.ga;
        std::cout << i + 1 << ". " << t.name << " P=" << t.played << " W=" << t.wins << " D=" << t.draws
            << " L=" << t.losses << " GF=" << t.gf << " GA=" << t.ga << " GD=" << (gd > 0 ? "+" : "") << gd
            << " Pts=" << t.points << '\n';
    }
}
