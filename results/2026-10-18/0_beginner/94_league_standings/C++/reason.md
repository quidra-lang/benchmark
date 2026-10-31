# Task B selection: 94_league_standings / C++

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.cpp`. Selected original locations: L8,L9,L10,L11,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L30,L31,L32,L33,L34,L35,L36,L37,L38,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59.

- L8: `struct Team {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    std::string name;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    int played = 0, wins = 0, draws = 0, losses = 0, gf = 0, ga = 0, points = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `};` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `void record(Team &t, int gf, int ga) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    ++t.played;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    t.gf += gf;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    t.ga += ga;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    if (gf > ga) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        ++t.wins;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        t.points += 3;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    } else if (gf == ga) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        ++t.draws;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        ++t.points;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        ++t.losses;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `    const std::array<std::string, 6> names = {"Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    const std::array<std::string, 15> matches = {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        "Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        "Lions 2-0 Sharks", "Tigers 2-1 Eagles", "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions"};` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    for (const std::string &name : names)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        teams.push_back({name});` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    for (const std::string &match : matches) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        std::istringstream input(match);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `        input >> home >> h >> dash >> a >> away;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `        int x = 0, y = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `        while (teams[x].name != home)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `            ++x;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `        while (teams[y].name != away)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `            ++y;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        record(teams[x], h, a);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        record(teams[y], a, h);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L51: `    std::sort(teams.begin(), teams.end(), [](const Team &a, const Team &b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `        if (a.points != b.points)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `            return a.points > b.points;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `        if (a.gf - a.ga != b.gf - b.ga)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `            return a.gf - a.ga > b.gf - b.ga;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `        if (a.gf != b.gf)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `            return a.gf > b.gf;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `        return a.name < b.name;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `    });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **817 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 765 tokens. The contiguous original span L8–L59 costs 867 tokens; the complete original source costs 1157 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L8: 811 tokens; removes `struct Team {` from the dependency chain described above.
- Without L9: 809 tokens; removes `std::string name;` from the dependency chain described above.
- Without L10: 765 tokens; removes `int played = 0, wins = 0, draws = 0, losses = 0, gf = 0, ga = 0, points = 0;` from the dependency chain described above.
- Without L11: 814 tokens; removes `};` from the dependency chain described above.
- Without L13: 795 tokens; removes `void record(Team &t, int gf, int ga) {` from the dependency chain described above.
- Without L14: 810 tokens; removes `++t.played;` from the dependency chain described above.
- Without L15: 807 tokens; removes `t.gf += gf;` from the dependency chain described above.
- Without L16: 807 tokens; removes `t.ga += ga;` from the dependency chain described above.
- Without L17: 804 tokens; removes `if (gf > ga) {` from the dependency chain described above.
- Without L18: 809 tokens; removes `++t.wins;` from the dependency chain described above.
- Without L19: 806 tokens; removes `t.points += 3;` from the dependency chain described above.
- Without L20: 800 tokens; removes `} else if (gf == ga) {` from the dependency chain described above.
- Without L21: 809 tokens; removes `++t.draws;` from the dependency chain described above.
- Without L22: 809 tokens; removes `++t.points;` from the dependency chain described above.
- Without L23: 810 tokens; removes `} else {` from the dependency chain described above.
- Without L24: 809 tokens; removes `++t.losses;` from the dependency chain described above.
- Without L25: 814 tokens; removes `}` from the dependency chain described above.
- Without L26: 815 tokens; removes `}` from the dependency chain described above.
- Without L30: 766 tokens; removes `const std::array<std::string, 6> names = {"Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"};` from the dependency chain described above.
- Without L31: 795 tokens; removes `const std::array<std::string, 15> matches = {` from the dependency chain described above.
- Without L32: 760 tokens; removes `"Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles",` from the dependency chain described above.
- Without L33: 760 tokens; removes `"Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves",` from the dependency chain described above.
- Without L34: 759 tokens; removes `"Lions 2-0 Sharks", "Tigers 2-1 Eagles", "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions"};` from the dependency chain described above.
- Without L35: 799 tokens; removes `for (const std::string &name : names)` from the dependency chain described above.
- Without L36: 803 tokens; removes `teams.push_back({name});` from the dependency chain described above.
- Without L37: 797 tokens; removes `for (const std::string &match : matches) {` from the dependency chain described above.
- Without L38: 805 tokens; removes `std::istringstream input(match);` from the dependency chain described above.
- Without L42: 792 tokens; removes `input >> home >> h >> dash >> a >> away;` from the dependency chain described above.
- Without L43: 799 tokens; removes `int x = 0, y = 0;` from the dependency chain described above.
- Without L44: 801 tokens; removes `while (teams[x].name != home)` from the dependency chain described above.
- Without L45: 810 tokens; removes `++x;` from the dependency chain described above.
- Without L46: 801 tokens; removes `while (teams[y].name != away)` from the dependency chain described above.
- Without L47: 810 tokens; removes `++y;` from the dependency chain described above.
- Without L48: 800 tokens; removes `record(teams[x], h, a);` from the dependency chain described above.
- Without L49: 800 tokens; removes `record(teams[y], a, h);` from the dependency chain described above.
- Without L50: 814 tokens; removes `}` from the dependency chain described above.
- Without L51: 778 tokens; removes `std::sort(teams.begin(), teams.end(), [](const Team &a, const Team &b) {` from the dependency chain described above.
- Without L52: 801 tokens; removes `if (a.points != b.points)` from the dependency chain described above.
- Without L53: 801 tokens; removes `return a.points > b.points;` from the dependency chain described above.
- Without L54: 789 tokens; removes `if (a.gf - a.ga != b.gf - b.ga)` from the dependency chain described above.
- Without L55: 789 tokens; removes `return a.gf - a.ga > b.gf - b.ga;` from the dependency chain described above.
- Without L56: 801 tokens; removes `if (a.gf != b.gf)` from the dependency chain described above.
- Without L57: 801 tokens; removes `return a.gf > b.gf;` from the dependency chain described above.
- Without L58: 802 tokens; removes `return a.name < b.name;` from the dependency chain described above.
- Without L59: 812 tokens; removes `});` from the dependency chain described above.
