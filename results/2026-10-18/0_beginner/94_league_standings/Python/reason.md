# Task B selection: 94_league_standings / Python

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.py`. Selected original locations: L1,L2,L4,L7,L8,L9,L11,L12,L14,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L39,L40,L41,L44.

- L1: `teams = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `matches = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    "Tigers 2-2 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    "Wolves 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    "Lions 0-1 Tigers",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    "Tigers 3-3 Bears",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    "Sharks 2-2 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    "Bears 3-1 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    "Tigers 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    "Sharks 2-0 Tigers",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    "Wolves 2-1 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `fields = ["played", "wins", "draws", "losses", "gf", "ga", "points"]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `stats = {name: dict.fromkeys(fields, 0) for name in teams}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `for match in matches:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    home, score, away = match.split()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    h, a = map(int, score.split("-"))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    for name, goals, conceded in [(home, h, a), (away, a, h)]:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        record = stats[name]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        record["played"] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        record["gf"] += goals` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        record["ga"] += conceded` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        if goals > conceded:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `            record["wins"] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `            record["points"] += 3` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        elif goals == conceded:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `            record["draws"] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `            record["points"] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        else:` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `            record["losses"] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `def ranking_key(name):` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    s = stats[name]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    return (-s["points"], s["ga"] - s["gf"], -s["gf"], name)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `ordered = sorted(teams, key=ranking_key)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **528 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 520 tokens. The contiguous original span L1–L44 costs 604 tokens; the complete original source costs 790 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 493 tokens; removes `teams = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]` from the dependency chain described above.
- Without L2: 522 tokens; removes `matches = [` from the dependency chain described above.
- Without L4: 516 tokens; removes `"Tigers 2-2 Wolves",` from the dependency chain described above.
- Without L7: 516 tokens; removes `"Wolves 2-1 Eagles",` from the dependency chain described above.
- Without L8: 516 tokens; removes `"Lions 0-1 Tigers",` from the dependency chain described above.
- Without L9: 516 tokens; removes `"Tigers 3-3 Bears",` from the dependency chain described above.
- Without L11: 516 tokens; removes `"Sharks 2-2 Wolves",` from the dependency chain described above.
- Without L12: 516 tokens; removes `"Bears 3-1 Wolves",` from the dependency chain described above.
- Without L14: 516 tokens; removes `"Tigers 2-1 Eagles",` from the dependency chain described above.
- Without L16: 516 tokens; removes `"Sharks 2-0 Tigers",` from the dependency chain described above.
- Without L17: 516 tokens; removes `"Wolves 2-1 Lions",` from the dependency chain described above.
- Without L18: 526 tokens; removes `]` from the dependency chain described above.
- Without L19: 488 tokens; removes `fields = ["played", "wins", "draws", "losses", "gf", "ga", "points"]` from the dependency chain described above.
- Without L20: 501 tokens; removes `stats = {name: dict.fromkeys(fields, 0) for name in teams}` from the dependency chain described above.
- Without L21: 519 tokens; removes `for match in matches:` from the dependency chain described above.
- Without L22: 511 tokens; removes `home, score, away = match.split()` from the dependency chain described above.
- Without L23: 505 tokens; removes `h, a = map(int, score.split("-"))` from the dependency chain described above.
- Without L24: 492 tokens; removes `for name, goals, conceded in [(home, h, a), (away, a, h)]:` from the dependency chain described above.
- Without L25: 517 tokens; removes `record = stats[name]` from the dependency chain described above.
- Without L26: 515 tokens; removes `record["played"] += 1` from the dependency chain described above.
- Without L27: 515 tokens; removes `record["gf"] += goals` from the dependency chain described above.
- Without L28: 515 tokens; removes `record["ga"] += conceded` from the dependency chain described above.
- Without L29: 517 tokens; removes `if goals > conceded:` from the dependency chain described above.
- Without L30: 514 tokens; removes `record["wins"] += 1` from the dependency chain described above.
- Without L31: 514 tokens; removes `record["points"] += 3` from the dependency chain described above.
- Without L32: 517 tokens; removes `elif goals == conceded:` from the dependency chain described above.
- Without L33: 514 tokens; removes `record["draws"] += 1` from the dependency chain described above.
- Without L34: 514 tokens; removes `record["points"] += 1` from the dependency chain described above.
- Without L35: 523 tokens; removes `else:` from the dependency chain described above.
- Without L36: 514 tokens; removes `record["losses"] += 1` from the dependency chain described above.
- Without L39: 518 tokens; removes `def ranking_key(name):` from the dependency chain described above.
- Without L40: 518 tokens; removes `s = stats[name]` from the dependency chain described above.
- Without L41: 486 tokens; removes `return (-s["points"], s["ga"] - s["gf"], -s["gf"], name)` from the dependency chain described above.
- Without L44: 512 tokens; removes `ordered = sorted(teams, key=ranking_key)` from the dependency chain described above.
