# Task B selection: 94_league_standings / Quidra

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.qui`. Selected original locations: L1,L2,L3,L4,L7,L8,L9,L10,L11,L12,L13,L14,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61,L62,L63,L64.

- L1: `int index_of(string name, string[] names)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    for 0 <= int i < int(len(names))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `        if names[i] == name` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `            return i` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `bool better(int a, int b, int[] points, int[] goals_for, int[] goals_against)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    if points[a] != points[b]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `        return points[a] > points[b]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    int first = goals_for[a] - goals_against[a]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    int second = goals_for[b] - goals_against[b]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    if first != second` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        return first > second` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    return goals_for[a] > goals_for[b]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `string[] names = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `names = names.sorted()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `string[] matches = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    "Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    "Wolves 2-1 Eagles", "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    "Sharks 2-2 Wolves", "Bears 3-1 Wolves", "Lions 2-0 Sharks", "Tigers 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `int[] played = array(6, fill = 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `int[] wins = array(6, fill = 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `int[] draws = array(6, fill = 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `int[] losses = array(6, fill = 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `int[] goals_for = array(6, fill = 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `int[] goals_against = array(6, fill = 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `int[] points = array(6, fill = 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `for string match_text = matches[]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    string[] fields = match_text.split(" ")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    int home = index_of(fields[0], names)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    int away = index_of(fields[2], names)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    string[] score = fields[1].split("-")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    int first = int.parse(score[0])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    int second = int.parse(score[1])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    played[home] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    played[away] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    goals_for[home] += first` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    goals_against[home] += second` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    goals_for[away] += second` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `    goals_against[away] += first` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    if first == second` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `        draws[home] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `        draws[away] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `        points[home] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        points[away] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    elif first > second` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `        wins[home] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `        losses[away] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `        points[home] += 3` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `    else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L54: `        wins[away] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `        losses[home] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `        points[away] += 3` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `bool[] used = array(6, fill = false)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `for 1 <= int position <= 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `    int best = -1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `    for 0 <= int i < 6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `        if not used[i]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `            if best == -1 or better(i, best, points, goals_for, goals_against)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `                best = i` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `    used[best] = true` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **1022 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 1011 tokens. The contiguous original span L1–L64 costs 1030 tokens; the complete original source costs 1183 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 1005 tokens; removes `int index_of(string name, string[] names)` from the dependency chain described above.
- Without L2: 1001 tokens; removes `for 0 <= int i < int(len(names))` from the dependency chain described above.
- Without L3: 1009 tokens; removes `if names[i] == name` from the dependency chain described above.
- Without L4: 1015 tokens; removes `return i` from the dependency chain described above.
- Without L7: 986 tokens; removes `bool better(int a, int b, int[] points, int[] goals_for, int[] goals_against)` from the dependency chain described above.
- Without L8: 1007 tokens; removes `if points[a] != points[b]` from the dependency chain described above.
- Without L9: 1006 tokens; removes `return points[a] > points[b]` from the dependency chain described above.
- Without L10: 999 tokens; removes `int first = goals_for[a] - goals_against[a]` from the dependency chain described above.
- Without L11: 999 tokens; removes `int second = goals_for[b] - goals_against[b]` from the dependency chain described above.
- Without L12: 1013 tokens; removes `if first != second` from the dependency chain described above.
- Without L13: 1012 tokens; removes `return first > second` from the dependency chain described above.
- Without L14: 1003 tokens; removes `return goals_for[a] > goals_for[b]` from the dependency chain described above.
- Without L16: 984 tokens; removes `string[] names = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]` from the dependency chain described above.
- Without L17: 1012 tokens; removes `names = names.sorted()` from the dependency chain described above.
- Without L18: 1013 tokens; removes `string[] matches = [` from the dependency chain described above.
- Without L19: 977 tokens; removes `"Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks",` from the dependency chain described above.
- Without L20: 977 tokens; removes `"Wolves 2-1 Eagles", "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions",` from the dependency chain described above.
- Without L21: 977 tokens; removes `"Sharks 2-2 Wolves", "Bears 3-1 Wolves", "Lions 2-0 Sharks", "Tigers 2-1 Eagles",` from the dependency chain described above.
- Without L22: 988 tokens; removes `"Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions",` from the dependency chain described above.
- Without L23: 1020 tokens; removes `]` from the dependency chain described above.
- Without L24: 1003 tokens; removes `int[] played = array(6, fill = 0)` from the dependency chain described above.
- Without L25: 1003 tokens; removes `int[] wins = array(6, fill = 0)` from the dependency chain described above.
- Without L26: 1003 tokens; removes `int[] draws = array(6, fill = 0)` from the dependency chain described above.
- Without L27: 1003 tokens; removes `int[] losses = array(6, fill = 0)` from the dependency chain described above.
- Without L28: 1001 tokens; removes `int[] goals_for = array(6, fill = 0)` from the dependency chain described above.
- Without L29: 1001 tokens; removes `int[] goals_against = array(6, fill = 0)` from the dependency chain described above.
- Without L30: 1003 tokens; removes `int[] points = array(6, fill = 0)` from the dependency chain described above.
- Without L31: 1009 tokens; removes `for string match_text = matches[]` from the dependency chain described above.
- Without L32: 1003 tokens; removes `string[] fields = match_text.split(" ")` from the dependency chain described above.
- Without L33: 1002 tokens; removes `int home = index_of(fields[0], names)` from the dependency chain described above.
- Without L34: 1002 tokens; removes `int away = index_of(fields[2], names)` from the dependency chain described above.
- Without L35: 1003 tokens; removes `string[] score = fields[1].split("-")` from the dependency chain described above.
- Without L36: 1005 tokens; removes `int first = int.parse(score[0])` from the dependency chain described above.
- Without L37: 1005 tokens; removes `int second = int.parse(score[1])` from the dependency chain described above.
- Without L38: 1012 tokens; removes `played[home] += 1` from the dependency chain described above.
- Without L39: 1012 tokens; removes `played[away] += 1` from the dependency chain described above.
- Without L40: 1010 tokens; removes `goals_for[home] += first` from the dependency chain described above.
- Without L41: 1010 tokens; removes `goals_against[home] += second` from the dependency chain described above.
- Without L42: 1010 tokens; removes `goals_for[away] += second` from the dependency chain described above.
- Without L43: 1010 tokens; removes `goals_against[away] += first` from the dependency chain described above.
- Without L44: 1013 tokens; removes `if first == second` from the dependency chain described above.
- Without L45: 1011 tokens; removes `draws[home] += 1` from the dependency chain described above.
- Without L46: 1011 tokens; removes `draws[away] += 1` from the dependency chain described above.
- Without L47: 1011 tokens; removes `points[home] += 1` from the dependency chain described above.
- Without L48: 1011 tokens; removes `points[away] += 1` from the dependency chain described above.
- Without L49: 1013 tokens; removes `elif first > second` from the dependency chain described above.
- Without L50: 1011 tokens; removes `wins[home] += 1` from the dependency chain described above.
- Without L51: 1011 tokens; removes `losses[away] += 1` from the dependency chain described above.
- Without L52: 1011 tokens; removes `points[home] += 3` from the dependency chain described above.
- Without L53: 1019 tokens; removes `else` from the dependency chain described above.
- Without L54: 1011 tokens; removes `wins[away] += 1` from the dependency chain described above.
- Without L55: 1011 tokens; removes `losses[home] += 1` from the dependency chain described above.
- Without L56: 1011 tokens; removes `points[away] += 3` from the dependency chain described above.
- Without L57: 1003 tokens; removes `bool[] used = array(6, fill = false)` from the dependency chain described above.
- Without L58: 1008 tokens; removes `for 1 <= int position <= 6` from the dependency chain described above.
- Without L59: 1012 tokens; removes `int best = -1` from the dependency chain described above.
- Without L60: 1007 tokens; removes `for 0 <= int i < 6` from the dependency chain described above.
- Without L61: 1011 tokens; removes `if not used[i]` from the dependency chain described above.
- Without L62: 987 tokens; removes `if best == -1 or better(i, best, points, goals_for, goals_against)` from the dependency chain described above.
- Without L63: 1012 tokens; removes `best = i` from the dependency chain described above.
- Without L64: 1012 tokens; removes `used[best] = true` from the dependency chain described above.
