# Task B selection: 94_league_standings / R

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.R`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31.

- L1: `teams <- c("Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `records <- matrix(0, 6, 7, dimnames = list(teams, c("played", "wins", "draws", "losses", "gf", "ga", "points")))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `matches <- c(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  "Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  "Wolves 2-1 Eagles", "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `  "Sharks 2-2 Wolves", "Bears 3-1 Wolves", "Lions 2-0 Sharks", "Tigers 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions"` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `)` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `for (match in matches) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  parts <- strsplit(match, " ", fixed = TRUE)[[1]]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  goals <- as.integer(strsplit(parts[2], "-", fixed = TRUE)[[1]])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `  for (side in 1:2) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    team <- if (side == 1) parts[1] else parts[3]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    gf <- goals[side]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    ga <- goals[3 - side]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    records[team, "played"] <- records[team, "played"] + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    records[team, "gf"] <- records[team, "gf"] + gf` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    records[team, "ga"] <- records[team, "ga"] + ga` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    if (gf > ga) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `      records[team, "wins"] <- records[team, "wins"] + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `      records[team, "points"] <- records[team, "points"] + 3` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    } else if (gf == ga) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `      records[team, "draws"] <- records[team, "draws"] + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `      records[team, "points"] <- records[team, "points"] + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `      records[team, "losses"] <- records[team, "losses"] + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `differences <- records[, "gf"] - records[, "ga"]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `ordered <- order(-records[, "points"], -differences, -records[, "gf"], teams, method = "radix")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **746 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 729 tokens. The contiguous original span L1–L31 costs 746 tokens; the complete original source costs 951 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 710 tokens; removes `teams <- c("Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears")` from the dependency chain described above.
- Without L2: 683 tokens; removes `records <- matrix(0, 6, 7, dimnames = list(teams, c("played", "wins", "draws", "losses", "gf", "ga", "points")))` from the dependency chain described above.
- Without L3: 739 tokens; removes `matches <- c(` from the dependency chain described above.
- Without L4: 701 tokens; removes `"Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks",` from the dependency chain described above.
- Without L5: 701 tokens; removes `"Wolves 2-1 Eagles", "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions",` from the dependency chain described above.
- Without L6: 701 tokens; removes `"Sharks 2-2 Wolves", "Bears 3-1 Wolves", "Lions 2-0 Sharks", "Tigers 2-1 Eagles",` from the dependency chain described above.
- Without L7: 713 tokens; removes `"Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions"` from the dependency chain described above.
- Without L8: 744 tokens; removes `)` from the dependency chain described above.
- Without L9: 734 tokens; removes `for (match in matches) {` from the dependency chain described above.
- Without L10: 721 tokens; removes `parts <- strsplit(match, " ", fixed = TRUE)[[1]]` from the dependency chain described above.
- Without L11: 713 tokens; removes `goals <- as.integer(strsplit(parts[2], "-", fixed = TRUE)[[1]])` from the dependency chain described above.
- Without L12: 731 tokens; removes `for (side in 1:2) {` from the dependency chain described above.
- Without L13: 719 tokens; removes `team <- if (side == 1) parts[1] else parts[3]` from the dependency chain described above.
- Without L14: 736 tokens; removes `gf <- goals[side]` from the dependency chain described above.
- Without L15: 732 tokens; removes `ga <- goals[3 - side]` from the dependency chain described above.
- Without L16: 719 tokens; removes `records[team, "played"] <- records[team, "played"] + 1` from the dependency chain described above.
- Without L17: 719 tokens; removes `records[team, "gf"] <- records[team, "gf"] + gf` from the dependency chain described above.
- Without L18: 719 tokens; removes `records[team, "ga"] <- records[team, "ga"] + ga` from the dependency chain described above.
- Without L19: 733 tokens; removes `if (gf > ga) {` from the dependency chain described above.
- Without L20: 718 tokens; removes `records[team, "wins"] <- records[team, "wins"] + 1` from the dependency chain described above.
- Without L21: 718 tokens; removes `records[team, "points"] <- records[team, "points"] + 3` from the dependency chain described above.
- Without L22: 729 tokens; removes `} else if (gf == ga) {` from the dependency chain described above.
- Without L23: 718 tokens; removes `records[team, "draws"] <- records[team, "draws"] + 1` from the dependency chain described above.
- Without L24: 718 tokens; removes `records[team, "points"] <- records[team, "points"] + 1` from the dependency chain described above.
- Without L25: 739 tokens; removes `} else {` from the dependency chain described above.
- Without L26: 718 tokens; removes `records[team, "losses"] <- records[team, "losses"] + 1` from the dependency chain described above.
- Without L27: 743 tokens; removes `}` from the dependency chain described above.
- Without L28: 743 tokens; removes `}` from the dependency chain described above.
- Without L29: 744 tokens; removes `}` from the dependency chain described above.
- Without L30: 722 tokens; removes `differences <- records[, "gf"] - records[, "ga"]` from the dependency chain described above.
- Without L31: 702 tokens; removes `ordered <- order(-records[, "points"], -differences, -records[, "gf"], teams, method = "radix")` from the dependency chain described above.
