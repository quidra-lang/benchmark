# Task B selection: 94_league_standings / Kotlin

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.kt`. Selected original locations: L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34.

- L2: `    val matches = listOf(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `        "Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `        "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `        "Lions 2-0 Sharks", "Tigers 2-1 Eagles", "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    )` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `    val names = listOf("Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    val stats = Array(6) { IntArray(6) }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    for (match in matches) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `        val parts = match.split(' ')` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `        val goals = parts[1].split('-').map { it.toInt() }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `        val home = names.indexOf(parts[0])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        val away = names.indexOf(parts[2])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        val (h, a) = goals` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        stats[home][0]++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        stats[away][0]++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        stats[home][4] += h` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        stats[home][5] += a` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        stats[away][4] += a` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        stats[away][5] += h` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        if (h == a) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `            stats[home][2]++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `            stats[away][2]++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `            stats[if (h > a) home else away][1]++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `            stats[if (h > a) away else home][3]++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `    val order = names.indices.sortedWith(` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        compareByDescending<Int> { 3 * stats[it][1] + stats[it][2] }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `            .thenByDescending { stats[it][4] - stats[it][5] }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `            .thenByDescending { stats[it][4] }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `            .thenBy { names[it] },` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    )` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **665 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 641 tokens. The contiguous original span L2–L34 costs 665 tokens; the complete original source costs 910 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L2: 654 tokens; removes `val matches = listOf(` from the dependency chain described above.
- Without L3: 608 tokens; removes `"Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles",` from the dependency chain described above.
- Without L4: 608 tokens; removes `"Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves",` from the dependency chain described above.
- Without L5: 608 tokens; removes `"Lions 2-0 Sharks", "Tigers 2-1 Eagles", "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions",` from the dependency chain described above.
- Without L6: 662 tokens; removes `)` from the dependency chain described above.
- Without L7: 625 tokens; removes `val names = listOf("Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears")` from the dependency chain described above.
- Without L8: 643 tokens; removes `val stats = Array(6) { IntArray(6) }` from the dependency chain described above.
- Without L9: 652 tokens; removes `for (match in matches) {` from the dependency chain described above.
- Without L10: 648 tokens; removes `val parts = match.split(' ')` from the dependency chain described above.
- Without L11: 633 tokens; removes `val goals = parts[1].split('-').map { it.toInt() }` from the dependency chain described above.
- Without L12: 646 tokens; removes `val home = names.indexOf(parts[0])` from the dependency chain described above.
- Without L13: 646 tokens; removes `val away = names.indexOf(parts[2])` from the dependency chain described above.
- Without L14: 650 tokens; removes `val (h, a) = goals` from the dependency chain described above.
- Without L15: 654 tokens; removes `stats[home][0]++` from the dependency chain described above.
- Without L16: 654 tokens; removes `stats[away][0]++` from the dependency chain described above.
- Without L17: 651 tokens; removes `stats[home][4] += h` from the dependency chain described above.
- Without L18: 651 tokens; removes `stats[home][5] += a` from the dependency chain described above.
- Without L19: 651 tokens; removes `stats[away][4] += a` from the dependency chain described above.
- Without L20: 651 tokens; removes `stats[away][5] += h` from the dependency chain described above.
- Without L21: 651 tokens; removes `if (h == a) {` from the dependency chain described above.
- Without L22: 653 tokens; removes `stats[home][2]++` from the dependency chain described above.
- Without L23: 653 tokens; removes `stats[away][2]++` from the dependency chain described above.
- Without L24: 657 tokens; removes `} else {` from the dependency chain described above.
- Without L25: 639 tokens; removes `stats[if (h > a) home else away][1]++` from the dependency chain described above.
- Without L26: 639 tokens; removes `stats[if (h > a) away else home][3]++` from the dependency chain described above.
- Without L27: 661 tokens; removes `}` from the dependency chain described above.
- Without L28: 662 tokens; removes `}` from the dependency chain described above.
- Without L29: 650 tokens; removes `val order = names.indices.sortedWith(` from the dependency chain described above.
- Without L30: 630 tokens; removes `compareByDescending<Int> { 3 * stats[it][1] + stats[it][2] }` from the dependency chain described above.
- Without L31: 635 tokens; removes `.thenByDescending { stats[it][4] - stats[it][5] }` from the dependency chain described above.
- Without L32: 645 tokens; removes `.thenByDescending { stats[it][4] }` from the dependency chain described above.
- Without L33: 648 tokens; removes `.thenBy { names[it] },` from the dependency chain described above.
- Without L34: 662 tokens; removes `)` from the dependency chain described above.
