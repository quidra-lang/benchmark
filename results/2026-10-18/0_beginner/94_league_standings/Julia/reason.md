# Task B selection: 94_league_standings / Julia

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.jl`. Selected original locations: L4,L5,L6,L8,L11,L12,L13,L15,L16,L18,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50.

- L4: `    teams = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    records = Dict(team=>zeros(Int, 7) for team in teams)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    matches = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `        "Tigers 2-2 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        "Wolves 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        "Lions 0-1 Tigers",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        "Tigers 3-3 Bears",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        "Sharks 2-2 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        "Bears 3-1 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        "Tigers 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        "Sharks 2-0 Tigers",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        "Wolves 2-1 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    ]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L23: `    for match in matches` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        home, score, away = split(match)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        h, a = parse.(Int, split(score, '-'))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        for (team, gf, ga) in [(home, h, a), (away, a, h)]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `            record = records[team]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `            record[1] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `            record[5] += gf` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `            record[6] += ga` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `            if gf > ga` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `                record[2] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `                record[7] += 3` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `            elseif gf == ga` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `                record[3] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `                record[7] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L38: `                record[4] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `            end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L40: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L41: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L42: `    sort!(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `        teams;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `        by = team -> (` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `            -records[team][7],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `            -(records[team][5]-records[team][6]),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `            -records[team][5],` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `            team,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        ),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `    )` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **517 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 492 tokens. The contiguous original span L4–L50 costs 595 tokens; the complete original source costs 826 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L4: 481 tokens; removes `teams = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]` from the dependency chain described above.
- Without L5: 491 tokens; removes `records = Dict(team=>zeros(Int, 7) for team in teams)` from the dependency chain described above.
- Without L6: 510 tokens; removes `matches = [` from the dependency chain described above.
- Without L8: 504 tokens; removes `"Tigers 2-2 Wolves",` from the dependency chain described above.
- Without L11: 504 tokens; removes `"Wolves 2-1 Eagles",` from the dependency chain described above.
- Without L12: 504 tokens; removes `"Lions 0-1 Tigers",` from the dependency chain described above.
- Without L13: 504 tokens; removes `"Tigers 3-3 Bears",` from the dependency chain described above.
- Without L15: 504 tokens; removes `"Sharks 2-2 Wolves",` from the dependency chain described above.
- Without L16: 504 tokens; removes `"Bears 3-1 Wolves",` from the dependency chain described above.
- Without L18: 504 tokens; removes `"Tigers 2-1 Eagles",` from the dependency chain described above.
- Without L20: 504 tokens; removes `"Sharks 2-0 Tigers",` from the dependency chain described above.
- Without L21: 504 tokens; removes `"Wolves 2-1 Lions",` from the dependency chain described above.
- Without L22: 514 tokens; removes `]` from the dependency chain described above.
- Without L23: 508 tokens; removes `for match in matches` from the dependency chain described above.
- Without L24: 500 tokens; removes `home, score, away = split(match)` from the dependency chain described above.
- Without L25: 491 tokens; removes `h, a = parse.(Int, split(score, '-'))` from the dependency chain described above.
- Without L26: 478 tokens; removes `for (team, gf, ga) in [(home, h, a), (away, a, h)]` from the dependency chain described above.
- Without L27: 505 tokens; removes `record = records[team]` from the dependency chain described above.
- Without L28: 505 tokens; removes `record[1] += 1` from the dependency chain described above.
- Without L29: 505 tokens; removes `record[5] += gf` from the dependency chain described above.
- Without L30: 505 tokens; removes `record[6] += ga` from the dependency chain described above.
- Without L31: 506 tokens; removes `if gf > ga` from the dependency chain described above.
- Without L32: 504 tokens; removes `record[2] += 1` from the dependency chain described above.
- Without L33: 504 tokens; removes `record[7] += 3` from the dependency chain described above.
- Without L34: 506 tokens; removes `elseif gf == ga` from the dependency chain described above.
- Without L35: 504 tokens; removes `record[3] += 1` from the dependency chain described above.
- Without L36: 504 tokens; removes `record[7] += 1` from the dependency chain described above.
- Without L37: 512 tokens; removes `else` from the dependency chain described above.
- Without L38: 504 tokens; removes `record[4] += 1` from the dependency chain described above.
- Without L39: 512 tokens; removes `end` from the dependency chain described above.
- Without L40: 513 tokens; removes `end` from the dependency chain described above.
- Without L41: 514 tokens; removes `end` from the dependency chain described above.
- Without L42: 512 tokens; removes `sort!(` from the dependency chain described above.
- Without L43: 512 tokens; removes `teams;` from the dependency chain described above.
- Without L44: 505 tokens; removes `by = team -> (` from the dependency chain described above.
- Without L45: 504 tokens; removes `-records[team][7],` from the dependency chain described above.
- Without L46: 494 tokens; removes `-(records[team][5]-records[team][6]),` from the dependency chain described above.
- Without L47: 504 tokens; removes `-records[team][5],` from the dependency chain described above.
- Without L48: 511 tokens; removes `team,` from the dependency chain described above.
- Without L49: 512 tokens; removes `),` from the dependency chain described above.
- Without L50: 514 tokens; removes `)` from the dependency chain described above.
