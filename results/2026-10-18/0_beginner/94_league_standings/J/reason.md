# Task B selection: 94_league_standings / J

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.ijs`. Selected original locations: L1,L2,L3,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40.

- L1: `split =: 4 : 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  <;._1 x,y` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `)` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L6: `  names =. /:~;:'Lions Tigers Eagles Sharks Wolves Bears'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `  matches =. 'Lions 0-3 Bears';'Tigers 2-2 Wolves';'Eagles 4-0 Sharks';'Bears 0-1 Sharks';'Wolves 2-1 Eagles';'Lions 0-1 Tigers';'Tigers 3-3 Bears';'Eagles 2-2 Lions';'Sharks 2-2 Wolves';'Bears 3-1 Wolves';'Lions 2-0 Sharks';'Tigers 2-1 Eagles';'Eagles 1-0 Bears';'Sharks 2-0 Tigers';'Wolves 2-1 Lions'` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `  played =. wins =. draws =. losses =. goalsfor =. goalsagainst =. points =. 6$0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `  for_box. matches do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    fields =. ' ' split >box` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    home =. names i.0{fields` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    away =. names i.2{fields` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    score =. '-' split >1{fields` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    first =. 0".>0{score` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    second =. 0".>1{score` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    played =. (>:home{played) home}played` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    played =. (>:away{played) away}played` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    goalsfor =. ((home{goalsfor)+first) home}goalsfor` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `    goalsagainst =. ((home{goalsagainst)+second) home}goalsagainst` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    goalsfor =. ((away{goalsfor)+second) away}goalsfor` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    goalsagainst =. ((away{goalsagainst)+first) away}goalsagainst` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    if. first=second do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `      draws =. (>:home{draws) home}draws` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `      draws =. (>:away{draws) away}draws` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `      points =. (>:home{points) home}points` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `      points =. (>:away{points) away}points` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    else.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `      winner =. home` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `      loser =. away` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `      if. second>first do.` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        winner =. away` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `        loser =. home` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `      end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L34: `      wins =. (>:winner{wins) winner}wins` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `      losses =. (>:loser{losses) loser}losses` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `      points =. (3+winner{points) winner}points` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `    end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L38: `  end.` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `  difference =. goalsfor-goalsagainst` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `  order =. \:points,.difference,.goalsfor` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **633 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 621 tokens. The contiguous original span L1–L40 costs 644 tokens; the complete original source costs 844 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 623 tokens; removes `split =: 4 : 0` from the dependency chain described above.
- Without L2: 623 tokens; removes `<;._1 x,y` from the dependency chain described above.
- Without L3: 631 tokens; removes `)` from the dependency chain described above.
- Without L6: 611 tokens; removes `names =. /:~;:'Lions Tigers Eagles Sharks Wolves Bears'` from the dependency chain described above.
- Without L7: 478 tokens; removes `matches =. 'Lions 0-3 Bears';'Tigers 2-2 Wolves';'Eagles 4-0 Sharks';'Bears 0-1 Sharks';'Wolves 2-1 Eagles';'Lions 0-1 Tigers';'Tigers 3-3 Bears';'Eagles 2-2 Lions';'Sharks 2-2 Wolves';'Bears 3-1 Wolves';'Lions 2-0 Sharks';'Tigers 2-1 Eagles';'Eagles 1-0 Bears';'Sharks 2-0 Tigers';'Wolves 2-1 Lions'` from the dependency chain described above.
- Without L8: 600 tokens; removes `played =. wins =. draws =. losses =. goalsfor =. goalsagainst =. points =. 6$0` from the dependency chain described above.
- Without L9: 623 tokens; removes `for_box. matches do.` from the dependency chain described above.
- Without L10: 619 tokens; removes `fields =. ' ' split >box` from the dependency chain described above.
- Without L11: 621 tokens; removes `home =. names i.0{fields` from the dependency chain described above.
- Without L12: 621 tokens; removes `away =. names i.2{fields` from the dependency chain described above.
- Without L13: 617 tokens; removes `score =. '-' split >1{fields` from the dependency chain described above.
- Without L14: 621 tokens; removes `first =. 0".>0{score` from the dependency chain described above.
- Without L15: 621 tokens; removes `second =. 0".>1{score` from the dependency chain described above.
- Without L16: 617 tokens; removes `played =. (>:home{played) home}played` from the dependency chain described above.
- Without L17: 617 tokens; removes `played =. (>:away{played) away}played` from the dependency chain described above.
- Without L18: 614 tokens; removes `goalsfor =. ((home{goalsfor)+first) home}goalsfor` from the dependency chain described above.
- Without L19: 614 tokens; removes `goalsagainst =. ((home{goalsagainst)+second) home}goalsagainst` from the dependency chain described above.
- Without L20: 614 tokens; removes `goalsfor =. ((away{goalsfor)+second) away}goalsfor` from the dependency chain described above.
- Without L21: 614 tokens; removes `goalsagainst =. ((away{goalsagainst)+first) away}goalsagainst` from the dependency chain described above.
- Without L22: 624 tokens; removes `if. first=second do.` from the dependency chain described above.
- Without L23: 616 tokens; removes `draws =. (>:home{draws) home}draws` from the dependency chain described above.
- Without L24: 616 tokens; removes `draws =. (>:away{draws) away}draws` from the dependency chain described above.
- Without L25: 616 tokens; removes `points =. (>:home{points) home}points` from the dependency chain described above.
- Without L26: 616 tokens; removes `points =. (>:away{points) away}points` from the dependency chain described above.
- Without L27: 630 tokens; removes `else.` from the dependency chain described above.
- Without L28: 625 tokens; removes `winner =. home` from the dependency chain described above.
- Without L29: 625 tokens; removes `loser =. away` from the dependency chain described above.
- Without L30: 623 tokens; removes `if. second>first do.` from the dependency chain described above.
- Without L31: 625 tokens; removes `winner =. away` from the dependency chain described above.
- Without L32: 625 tokens; removes `loser =. home` from the dependency chain described above.
- Without L33: 629 tokens; removes `end.` from the dependency chain described above.
- Without L34: 616 tokens; removes `wins =. (>:winner{wins) winner}wins` from the dependency chain described above.
- Without L35: 616 tokens; removes `losses =. (>:loser{losses) loser}losses` from the dependency chain described above.
- Without L36: 615 tokens; removes `points =. (3+winner{points) winner}points` from the dependency chain described above.
- Without L37: 630 tokens; removes `end.` from the dependency chain described above.
- Without L38: 630 tokens; removes `end.` from the dependency chain described above.
- Without L39: 624 tokens; removes `difference =. goalsfor-goalsagainst` from the dependency chain described above.
- Without L40: 621 tokens; removes `order =. \:points,.difference,.goalsfor` from the dependency chain described above.
