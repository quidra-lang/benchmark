# Task B selection: 94_league_standings / Swift

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.swift`. Selected original locations: L1,L2,L3,L4,L5,L6,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39.

- L1: `struct TeamStats {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    var played = 0, wins = 0, draws = 0, losses = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    var goalsFor = 0, goalsAgainst = 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    var points: Int { 3 * wins + draws }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    var goalDifference: Int { goalsFor - goalsAgainst }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L8: `let matches = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    "Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    "Lions 2-0 Sharks", "Tigers 2-1 Eagles", "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `let names = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `var stats = [TeamStats](repeating: TeamStats(), count: names.count)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `for match in matches {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    let parts = match.split(separator: " ").map(String.init)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    let goals = parts[1].split(separator: "-").map { Int($0)! }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    let home = names.firstIndex(of: parts[0])!, away = names.firstIndex(of: parts[2])!` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    let h = goals[0], a = goals[1]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    stats[home].played += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    stats[away].played += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    stats[home].goalsFor += h` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    stats[home].goalsAgainst += a` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    stats[away].goalsFor += a` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    stats[away].goalsAgainst += h` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    if h == a {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        stats[home].draws += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        stats[away].draws += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        stats[h > a ? home : away].wins += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        stats[h > a ? away : home].losses += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L34: `let order = names.indices.sorted { a, b in` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    if stats[a].points != stats[b].points { return stats[a].points > stats[b].points }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    if stats[a].goalDifference != stats[b].goalDifference { return stats[a].goalDifference > stats[b].goalDifference }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    if stats[a].goalsFor != stats[b].goalsFor { return stats[a].goalsFor > stats[b].goalsFor }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    return names[a] < names[b]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **799 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 780 tokens. The contiguous original span L1–L39 costs 800 tokens; the complete original source costs 973 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 792 tokens; removes `struct TeamStats {` from the dependency chain described above.
- Without L2: 769 tokens; removes `var played = 0, wins = 0, draws = 0, losses = 0` from the dependency chain described above.
- Without L3: 781 tokens; removes `var goalsFor = 0, goalsAgainst = 0` from the dependency chain described above.
- Without L4: 777 tokens; removes `var points: Int { 3 * wins + draws }` from the dependency chain described above.
- Without L5: 778 tokens; removes `var goalDifference: Int { goalsFor - goalsAgainst }` from the dependency chain described above.
- Without L6: 797 tokens; removes `}` from the dependency chain described above.
- Without L8: 791 tokens; removes `let matches = [` from the dependency chain described above.
- Without L9: 743 tokens; removes `"Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles",` from the dependency chain described above.
- Without L10: 743 tokens; removes `"Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves",` from the dependency chain described above.
- Without L11: 743 tokens; removes `"Lions 2-0 Sharks", "Tigers 2-1 Eagles", "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions",` from the dependency chain described above.
- Without L12: 797 tokens; removes `]` from the dependency chain described above.
- Without L13: 762 tokens; removes `let names = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]` from the dependency chain described above.
- Without L14: 771 tokens; removes `var stats = [TeamStats](repeating: TeamStats(), count: names.count)` from the dependency chain described above.
- Without L15: 789 tokens; removes `for match in matches {` from the dependency chain described above.
- Without L16: 773 tokens; removes `let parts = match.split(separator: " ").map(String.init)` from the dependency chain described above.
- Without L17: 765 tokens; removes `let goals = parts[1].split(separator: "-").map { Int($0)! }` from the dependency chain described above.
- Without L18: 757 tokens; removes `let home = names.firstIndex(of: parts[0])!, away = names.firstIndex(of: parts[2])!` from the dependency chain described above.
- Without L19: 777 tokens; removes `let h = goals[0], a = goals[1]` from the dependency chain described above.
- Without L20: 788 tokens; removes `stats[home].played += 1` from the dependency chain described above.
- Without L21: 788 tokens; removes `stats[away].played += 1` from the dependency chain described above.
- Without L22: 787 tokens; removes `stats[home].goalsFor += h` from the dependency chain described above.
- Without L23: 787 tokens; removes `stats[home].goalsAgainst += a` from the dependency chain described above.
- Without L24: 787 tokens; removes `stats[away].goalsFor += a` from the dependency chain described above.
- Without L25: 787 tokens; removes `stats[away].goalsAgainst += h` from the dependency chain described above.
- Without L26: 788 tokens; removes `if h == a {` from the dependency chain described above.
- Without L27: 787 tokens; removes `stats[home].draws += 1` from the dependency chain described above.
- Without L28: 787 tokens; removes `stats[away].draws += 1` from the dependency chain described above.
- Without L29: 792 tokens; removes `} else {` from the dependency chain described above.
- Without L30: 775 tokens; removes `stats[h > a ? home : away].wins += 1` from the dependency chain described above.
- Without L31: 775 tokens; removes `stats[h > a ? away : home].losses += 1` from the dependency chain described above.
- Without L32: 796 tokens; removes `}` from the dependency chain described above.
- Without L33: 797 tokens; removes `}` from the dependency chain described above.
- Without L34: 778 tokens; removes `let order = names.indices.sorted { a, b in` from the dependency chain described above.
- Without L35: 762 tokens; removes `if stats[a].points != stats[b].points { return stats[a].points > stats[b].points }` from the dependency chain described above.
- Without L36: 758 tokens; removes `if stats[a].goalDifference != stats[b].goalDifference { return stats[a].goalDifference > stats[b].goalDifference }` from the dependency chain described above.
- Without L37: 758 tokens; removes `if stats[a].goalsFor != stats[b].goalsFor { return stats[a].goalsFor > stats[b].goalsFor }` from the dependency chain described above.
- Without L38: 784 tokens; removes `return names[a] < names[b]` from the dependency chain described above.
- Without L39: 797 tokens; removes `}` from the dependency chain described above.
