# Task B selection: 94_league_standings / TypeScript

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.ts`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31.

- L1: `const teams = "Lions Tigers Eagles Sharks Wolves Bears".split(" ");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `const matches = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  "Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  "Wolves 2-1 Eagles", "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  "Sharks 2-2 Wolves", "Bears 3-1 Wolves", "Lions 2-0 Sharks", "Tigers 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `  "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L8: `const stats = new Map(teams.map(name => [name, {played: 0, wins: 0, draws: 0, losses: 0, gf: 0, ga: 0, points: 0}]));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `for (const match of matches) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  const [home, score, away] = match.split(" ");` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  const [h, a] = score.split("-").map(Number);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `  for (const {name, goals, conceded} of [{name: home, goals: h, conceded: a}, {name: away, goals: a, conceded: h}]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    const s = stats.get(name)!;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    s.played++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    s.gf += goals;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    s.ga += conceded;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    if (goals > conceded) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `      s.wins++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `      s.points += 3;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    } else if (goals === conceded) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `      s.draws++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `      s.points++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `      s.losses++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `teams.sort((a, b) => {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `  const x = stats.get(a)!, y = stats.get(b)!;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `  return y.points - x.points || (y.gf - y.ga) - (x.gf - x.ga) || y.gf - x.gf || (a < b ? -1 : a > b ? 1 : 0);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `});` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **668 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 645 tokens. The contiguous original span L1–L31 costs 668 tokens; the complete original source costs 853 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 640 tokens; removes `const teams = "Lions Tigers Eagles Sharks Wolves Bears".split(" ");` from the dependency chain described above.
- Without L2: 660 tokens; removes `const matches = [` from the dependency chain described above.
- Without L3: 623 tokens; removes `"Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks",` from the dependency chain described above.
- Without L4: 623 tokens; removes `"Wolves 2-1 Eagles", "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions",` from the dependency chain described above.
- Without L5: 623 tokens; removes `"Sharks 2-2 Wolves", "Bears 3-1 Wolves", "Lions 2-0 Sharks", "Tigers 2-1 Eagles",` from the dependency chain described above.
- Without L6: 635 tokens; removes `"Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions"` from the dependency chain described above.
- Without L7: 665 tokens; removes `];` from the dependency chain described above.
- Without L8: 599 tokens; removes `const stats = new Map(teams.map(name => [name, {played: 0, wins: 0, draws: 0, losses: 0, gf: 0, ga: 0, points: 0}]));` from the dependency chain described above.
- Without L9: 654 tokens; removes `for (const match of matches) {` from the dependency chain described above.
- Without L10: 643 tokens; removes `const [home, score, away] = match.split(" ");` from the dependency chain described above.
- Without L11: 641 tokens; removes `const [h, a] = score.split("-").map(Number);` from the dependency chain described above.
- Without L12: 606 tokens; removes `for (const {name, goals, conceded} of [{name: home, goals: h, conceded: a}, {name: away, goals: a, conceded: h}]) {` from the dependency chain described above.
- Without L13: 652 tokens; removes `const s = stats.get(name)!;` from the dependency chain described above.
- Without L14: 661 tokens; removes `s.played++;` from the dependency chain described above.
- Without L15: 658 tokens; removes `s.gf += goals;` from the dependency chain described above.
- Without L16: 658 tokens; removes `s.ga += conceded;` from the dependency chain described above.
- Without L17: 655 tokens; removes `if (goals > conceded) {` from the dependency chain described above.
- Without L18: 660 tokens; removes `s.wins++;` from the dependency chain described above.
- Without L19: 657 tokens; removes `s.points += 3;` from the dependency chain described above.
- Without L20: 651 tokens; removes `} else if (goals === conceded) {` from the dependency chain described above.
- Without L21: 660 tokens; removes `s.draws++;` from the dependency chain described above.
- Without L22: 660 tokens; removes `s.points++;` from the dependency chain described above.
- Without L23: 661 tokens; removes `} else {` from the dependency chain described above.
- Without L24: 660 tokens; removes `s.losses++;` from the dependency chain described above.
- Without L25: 665 tokens; removes `}` from the dependency chain described above.
- Without L26: 665 tokens; removes `}` from the dependency chain described above.
- Without L27: 666 tokens; removes `}` from the dependency chain described above.
- Without L28: 653 tokens; removes `teams.sort((a, b) => {` from the dependency chain described above.
- Without L29: 639 tokens; removes `const x = stats.get(a)!, y = stats.get(b)!;` from the dependency chain described above.
- Without L30: 583 tokens; removes `return y.points - x.points || (y.gf - y.ga) - (x.gf - x.ga) || y.gf - x.gf || (a < b ? -1 : a > b ? 1 : 0);` from the dependency chain described above.
- Without L31: 664 tokens; removes `});` from the dependency chain described above.
