# Task B selection: 94_league_standings / PHP

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.php`. Selected original locations: L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33.

- L3: `$teams = ['Lions', 'Tigers', 'Eagles', 'Sharks', 'Wolves', 'Bears'];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `$records = array_fill_keys($teams, array_fill(0, 7, 0));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `$matches = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    'Lions 0-3 Bears', 'Tigers 2-2 Wolves', 'Eagles 4-0 Sharks', 'Bears 0-1 Sharks',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    'Wolves 2-1 Eagles', 'Lions 0-1 Tigers', 'Tigers 3-3 Bears', 'Eagles 2-2 Lions',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    'Sharks 2-2 Wolves', 'Bears 3-1 Wolves', 'Lions 2-0 Sharks', 'Tigers 2-1 Eagles',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    'Eagles 1-0 Bears', 'Sharks 2-0 Tigers', 'Wolves 2-1 Lions',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L11: `foreach ($matches as $match) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    [$home, $score, $away] = explode(' ', $match);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    [$h, $a] = array_map('intval', explode('-', $score));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    foreach ([[$home, $h, $a], [$away, $a, $h]] as [$team, $gf, $ga]) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        $records[$team][0]++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        $records[$team][4] += $gf;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        $records[$team][5] += $ga;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        if ($gf > $ga) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `            $records[$team][1]++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `            $records[$team][6] += 3;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        } elseif ($gf === $ga) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `            $records[$team][2]++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `            $records[$team][6]++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `            $records[$team][3]++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `usort($teams, function ($a, $b) use ($records) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    $x = $records[$a];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    $y = $records[$b];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    return ($y[6] <=> $x[6]) ?: (($y[4] - $y[5]) <=> ($x[4] - $x[5])) ?: ($y[4] <=> $x[4]) ?: strcmp($a, $b);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `});` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **696 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 673 tokens. The contiguous original span L3–L33 costs 696 tokens; the complete original source costs 936 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 659 tokens; removes `$teams = ['Lions', 'Tigers', 'Eagles', 'Sharks', 'Wolves', 'Bears'];` from the dependency chain described above.
- Without L4: 666 tokens; removes `$records = array_fill_keys($teams, array_fill(0, 7, 0));` from the dependency chain described above.
- Without L5: 689 tokens; removes `$matches = [` from the dependency chain described above.
- Without L6: 651 tokens; removes `'Lions 0-3 Bears', 'Tigers 2-2 Wolves', 'Eagles 4-0 Sharks', 'Bears 0-1 Sharks',` from the dependency chain described above.
- Without L7: 651 tokens; removes `'Wolves 2-1 Eagles', 'Lions 0-1 Tigers', 'Tigers 3-3 Bears', 'Eagles 2-2 Lions',` from the dependency chain described above.
- Without L8: 651 tokens; removes `'Sharks 2-2 Wolves', 'Bears 3-1 Wolves', 'Lions 2-0 Sharks', 'Tigers 2-1 Eagles',` from the dependency chain described above.
- Without L9: 662 tokens; removes `'Eagles 1-0 Bears', 'Sharks 2-0 Tigers', 'Wolves 2-1 Lions',` from the dependency chain described above.
- Without L10: 693 tokens; removes `];` from the dependency chain described above.
- Without L11: 682 tokens; removes `foreach ($matches as $match) {` from the dependency chain described above.
- Without L12: 668 tokens; removes `[$home, $score, $away] = explode(' ', $match);` from the dependency chain described above.
- Without L13: 662 tokens; removes `[$h, $a] = array_map('intval', explode('-', $score));` from the dependency chain described above.
- Without L14: 647 tokens; removes `foreach ([[$home, $h, $a], [$away, $a, $h]] as [$team, $gf, $ga]) {` from the dependency chain described above.
- Without L15: 682 tokens; removes `$records[$team][0]++;` from the dependency chain described above.
- Without L16: 678 tokens; removes `$records[$team][4] += $gf;` from the dependency chain described above.
- Without L17: 678 tokens; removes `$records[$team][5] += $ga;` from the dependency chain described above.
- Without L18: 680 tokens; removes `if ($gf > $ga) {` from the dependency chain described above.
- Without L19: 681 tokens; removes `$records[$team][1]++;` from the dependency chain described above.
- Without L20: 678 tokens; removes `$records[$team][6] += 3;` from the dependency chain described above.
- Without L21: 678 tokens; removes `} elseif ($gf === $ga) {` from the dependency chain described above.
- Without L22: 681 tokens; removes `$records[$team][2]++;` from the dependency chain described above.
- Without L23: 681 tokens; removes `$records[$team][6]++;` from the dependency chain described above.
- Without L24: 688 tokens; removes `} else {` from the dependency chain described above.
- Without L25: 681 tokens; removes `$records[$team][3]++;` from the dependency chain described above.
- Without L26: 692 tokens; removes `}` from the dependency chain described above.
- Without L27: 693 tokens; removes `}` from the dependency chain described above.
- Without L28: 694 tokens; removes `}` from the dependency chain described above.
- Without L29: 670 tokens; removes `usort($teams, function ($a, $b) use ($records) {` from the dependency chain described above.
- Without L30: 682 tokens; removes `$x = $records[$a];` from the dependency chain described above.
- Without L31: 682 tokens; removes `$y = $records[$b];` from the dependency chain described above.
- Without L32: 608 tokens; removes `return ($y[6] <=> $x[6]) ?: (($y[4] - $y[5]) <=> ($x[4] - $x[5])) ?: ($y[4] <=> $x[4]) ?: strcmp($a, $b);` from the dependency chain described above.
- Without L33: 692 tokens; removes `});` from the dependency chain described above.
