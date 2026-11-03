# Task B selection: 94_league_standings / Ruby

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.rb`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31.

- L1: `teams = %w[Lions Tigers Eagles Sharks Wolves Bears]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `matches = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  'Lions 0-3 Bears', 'Tigers 2-2 Wolves', 'Eagles 4-0 Sharks', 'Bears 0-1 Sharks',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  'Wolves 2-1 Eagles', 'Lions 0-1 Tigers', 'Tigers 3-3 Bears', 'Eagles 2-2 Lions',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  'Sharks 2-2 Wolves', 'Bears 3-1 Wolves', 'Lions 2-0 Sharks', 'Tigers 2-1 Eagles',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `  'Eagles 1-0 Bears', 'Sharks 2-0 Tigers', 'Wolves 2-1 Lions'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L8: `stats = teams.to_h { |name| [name, {played: 0, wins: 0, draws: 0, losses: 0, gf: 0, ga: 0, points: 0}] }` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `matches.each do |match|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `  home, score, away = match.split` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `  h, a = score.split('-').map(&:to_i)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `  [[home, h, a], [away, a, h]].each do |name, goals, conceded|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    s = stats[name]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    s[:played] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    s[:gf] += goals` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    s[:ga] += conceded` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    if goals > conceded` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `      s[:wins] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `      s[:points] += 3` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    elsif goals == conceded` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `      s[:draws] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `      s[:points] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    else` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L24: `      s[:losses] += 1` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `  end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L27: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L28: `ordered = teams.sort_by do |name|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `  s = stats[name]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `  [-s[:points], s[:ga] - s[:gf], -s[:gf], name]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `end` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **531 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 513 tokens. The contiguous original span L1–L31 costs 531 tokens; the complete original source costs 701 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 512 tokens; removes `teams = %w[Lions Tigers Eagles Sharks Wolves Bears]` from the dependency chain described above.
- Without L2: 525 tokens; removes `matches = [` from the dependency chain described above.
- Without L3: 486 tokens; removes `'Lions 0-3 Bears', 'Tigers 2-2 Wolves', 'Eagles 4-0 Sharks', 'Bears 0-1 Sharks',` from the dependency chain described above.
- Without L4: 486 tokens; removes `'Wolves 2-1 Eagles', 'Lions 0-1 Tigers', 'Tigers 3-3 Bears', 'Eagles 2-2 Lions',` from the dependency chain described above.
- Without L5: 486 tokens; removes `'Sharks 2-2 Wolves', 'Bears 3-1 Wolves', 'Lions 2-0 Sharks', 'Tigers 2-1 Eagles',` from the dependency chain described above.
- Without L6: 498 tokens; removes `'Eagles 1-0 Bears', 'Sharks 2-0 Tigers', 'Wolves 2-1 Lions'` from the dependency chain described above.
- Without L7: 529 tokens; removes `]` from the dependency chain described above.
- Without L8: 465 tokens; removes `stats = teams.to_h { |name| [name, {played: 0, wins: 0, draws: 0, losses: 0, gf: 0, ga: 0, points: 0}] }` from the dependency chain described above.
- Without L9: 521 tokens; removes `matches.each do |match|` from the dependency chain described above.
- Without L10: 516 tokens; removes `home, score, away = match.split` from the dependency chain described above.
- Without L11: 506 tokens; removes `h, a = score.split('-').map(&:to_i)` from the dependency chain described above.
- Without L12: 495 tokens; removes `[[home, h, a], [away, a, h]].each do |name, goals, conceded|` from the dependency chain described above.
- Without L13: 521 tokens; removes `s = stats[name]` from the dependency chain described above.
- Without L14: 521 tokens; removes `s[:played] += 1` from the dependency chain described above.
- Without L15: 521 tokens; removes `s[:gf] += goals` from the dependency chain described above.
- Without L16: 521 tokens; removes `s[:ga] += conceded` from the dependency chain described above.
- Without L17: 522 tokens; removes `if goals > conceded` from the dependency chain described above.
- Without L18: 520 tokens; removes `s[:wins] += 1` from the dependency chain described above.
- Without L19: 520 tokens; removes `s[:points] += 3` from the dependency chain described above.
- Without L20: 522 tokens; removes `elsif goals == conceded` from the dependency chain described above.
- Without L21: 520 tokens; removes `s[:draws] += 1` from the dependency chain described above.
- Without L22: 520 tokens; removes `s[:points] += 1` from the dependency chain described above.
- Without L23: 528 tokens; removes `else` from the dependency chain described above.
- Without L24: 520 tokens; removes `s[:losses] += 1` from the dependency chain described above.
- Without L25: 528 tokens; removes `end` from the dependency chain described above.
- Without L26: 528 tokens; removes `end` from the dependency chain described above.
- Without L27: 529 tokens; removes `end` from the dependency chain described above.
- Without L28: 515 tokens; removes `ordered = teams.sort_by do |name|` from the dependency chain described above.
- Without L29: 521 tokens; removes `s = stats[name]` from the dependency chain described above.
- Without L30: 499 tokens; removes `[-s[:points], s[:ga] - s[:gf], -s[:gf], name]` from the dependency chain described above.
- Without L31: 529 tokens; removes `end` from the dependency chain described above.
