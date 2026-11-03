# Task B selection: 94_league_standings / Lua

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.lua`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37.

- L1: `local teams = {"Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `local records = {}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `for _, team in ipairs(teams) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    records[team] = {played = 0, wins = 0, draws = 0, losses = 0, gf = 0, ga = 0, points = 0}` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L6: `local matches = {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    "Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    "Wolves 2-1 Eagles", "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    "Sharks 2-2 Wolves", "Bears 3-1 Wolves", "Lions 2-0 Sharks", "Tigers 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L12: `for _, match in ipairs(matches) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    local home, h, a, away = match:match("(%a+) (%d+)%-(%d+) (%a+)")` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    h, a = tonumber(h), tonumber(a)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    for _, side in ipairs({{home, h, a}, {away, a, h}}) do` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        local record = records[side[1]]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        local gf, ga = side[2], side[3]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        record.played = record.played + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        record.gf, record.ga = record.gf + gf, record.ga + ga` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `        if gf > ga then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `            record.wins = record.wins + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `            record.points = record.points + 3` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `        elseif gf == ga then` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `            record.draws = record.draws + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `            record.points = record.points + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `        else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `            record.losses = record.losses + 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L31: `table.sort(teams, function(a, b)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    local x, y = records[a], records[b]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `    if x.points ~= y.points then return x.points > y.points end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    if x.gf - x.ga ~= y.gf - y.ga then return x.gf - x.ga > y.gf - y.ga end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    if x.gf ~= y.gf then return x.gf > y.gf end` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    return a < b` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `end)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **782 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 758 tokens. The contiguous original span L1–L37 costs 782 tokens; the complete original source costs 966 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 745 tokens; removes `local teams = {"Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"}` from the dependency chain described above.
- Without L2: 773 tokens; removes `local records = {}` from the dependency chain described above.
- Without L3: 766 tokens; removes `for _, team in ipairs(teams) do` from the dependency chain described above.
- Without L4: 724 tokens; removes `records[team] = {played = 0, wins = 0, draws = 0, losses = 0, gf = 0, ga = 0, points = 0}` from the dependency chain described above.
- Without L5: 780 tokens; removes `end` from the dependency chain described above.
- Without L6: 774 tokens; removes `local matches = {` from the dependency chain described above.
- Without L7: 737 tokens; removes `"Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks",` from the dependency chain described above.
- Without L8: 737 tokens; removes `"Wolves 2-1 Eagles", "Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions",` from the dependency chain described above.
- Without L9: 737 tokens; removes `"Sharks 2-2 Wolves", "Bears 3-1 Wolves", "Lions 2-0 Sharks", "Tigers 2-1 Eagles",` from the dependency chain described above.
- Without L10: 748 tokens; removes `"Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions",` from the dependency chain described above.
- Without L11: 780 tokens; removes `}` from the dependency chain described above.
- Without L12: 766 tokens; removes `for _, match in ipairs(matches) do` from the dependency chain described above.
- Without L13: 738 tokens; removes `local home, h, a, away = match:match("(%a+) (%d+)%-(%d+) (%a+)")` from the dependency chain described above.
- Without L14: 763 tokens; removes `h, a = tonumber(h), tonumber(a)` from the dependency chain described above.
- Without L15: 744 tokens; removes `for _, side in ipairs({{home, h, a}, {away, a, h}}) do` from the dependency chain described above.
- Without L16: 767 tokens; removes `local record = records[side[1]]` from the dependency chain described above.
- Without L17: 760 tokens; removes `local gf, ga = side[2], side[3]` from the dependency chain described above.
- Without L18: 766 tokens; removes `record.played = record.played + 1` from the dependency chain described above.
- Without L19: 752 tokens; removes `record.gf, record.ga = record.gf + gf, record.ga + ga` from the dependency chain described above.
- Without L20: 770 tokens; removes `if gf > ga then` from the dependency chain described above.
- Without L21: 765 tokens; removes `record.wins = record.wins + 1` from the dependency chain described above.
- Without L22: 765 tokens; removes `record.points = record.points + 3` from the dependency chain described above.
- Without L23: 770 tokens; removes `elseif gf == ga then` from the dependency chain described above.
- Without L24: 765 tokens; removes `record.draws = record.draws + 1` from the dependency chain described above.
- Without L25: 765 tokens; removes `record.points = record.points + 1` from the dependency chain described above.
- Without L26: 778 tokens; removes `else` from the dependency chain described above.
- Without L27: 765 tokens; removes `record.losses = record.losses + 1` from the dependency chain described above.
- Without L28: 778 tokens; removes `end` from the dependency chain described above.
- Without L29: 779 tokens; removes `end` from the dependency chain described above.
- Without L30: 780 tokens; removes `end` from the dependency chain described above.
- Without L31: 767 tokens; removes `table.sort(teams, function(a, b)` from the dependency chain described above.
- Without L32: 761 tokens; removes `local x, y = records[a], records[b]` from the dependency chain described above.
- Without L33: 753 tokens; removes `if x.points ~= y.points then return x.points > y.points end` from the dependency chain described above.
- Without L34: 729 tokens; removes `if x.gf - x.ga ~= y.gf - y.ga then return x.gf - x.ga > y.gf - y.ga end` from the dependency chain described above.
- Without L35: 753 tokens; removes `if x.gf ~= y.gf then return x.gf > y.gf end` from the dependency chain described above.
- Without L36: 773 tokens; removes `return a < b` from the dependency chain described above.
- Without L37: 779 tokens; removes `end)` from the dependency chain described above.
