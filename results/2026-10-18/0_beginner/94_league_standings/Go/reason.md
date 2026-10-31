# Task B selection: 94_league_standings / Go

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.go`. Selected original locations: L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61,L62,L63,L64.

- L13: `func record(t *Team, gf, ga int) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `	t.played++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `	t.gf += gf` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `	t.ga += ga` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `	if gf > ga {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `		t.wins++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `		t.points += 3` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `	} else if gf == ga {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `		t.draws++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `		t.points++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `	} else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `		t.losses++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L30: `	for _, name := range []string{"Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"} {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `		teams = append(teams, Team{name: name})` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L33: `	matches := []string{` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `		"Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `		"Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `		"Lions 2-0 Sharks", "Tigers 2-1 Eagles", "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L38: `	for _, game := range matches {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `		var home, away string` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `		var h, a int` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `		fmt.Sscanf(game, "%s %d-%d %s", &home, &h, &a, &away)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `		x, y := 0, 0` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `		for teams[x].name != home {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `			x++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L46: `		for teams[y].name != away {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `			y++` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L49: `		record(&teams[x], h, a)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `		record(&teams[y], a, h)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `	}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L52: `	sort.Slice(teams, func(i, j int) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `		a, b := teams[i], teams[j]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `		if a.points != b.points {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `			return a.points > b.points` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L57: `		if a.gf-a.ga != b.gf-b.ga {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `			return a.gf-a.ga > b.gf-b.ga` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L60: `		if a.gf != b.gf {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `			return a.gf > b.gf` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `		}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L63: `		return a.name < b.name` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `	})` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **732 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 685 tokens. The contiguous original span L13–L64 costs 751 tokens; the complete original source costs 1015 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L13: 712 tokens; removes `func record(t *Team, gf, ga int) {` from the dependency chain described above.
- Without L14: 726 tokens; removes `t.played++` from the dependency chain described above.
- Without L15: 723 tokens; removes `t.gf += gf` from the dependency chain described above.
- Without L16: 723 tokens; removes `t.ga += ga` from the dependency chain described above.
- Without L17: 721 tokens; removes `if gf > ga {` from the dependency chain described above.
- Without L18: 725 tokens; removes `t.wins++` from the dependency chain described above.
- Without L19: 722 tokens; removes `t.points += 3` from the dependency chain described above.
- Without L20: 717 tokens; removes `} else if gf == ga {` from the dependency chain described above.
- Without L21: 725 tokens; removes `t.draws++` from the dependency chain described above.
- Without L22: 725 tokens; removes `t.points++` from the dependency chain described above.
- Without L23: 725 tokens; removes `} else {` from the dependency chain described above.
- Without L24: 725 tokens; removes `t.losses++` from the dependency chain described above.
- Without L25: 729 tokens; removes `}` from the dependency chain described above.
- Without L26: 730 tokens; removes `}` from the dependency chain described above.
- Without L30: 685 tokens; removes `for _, name := range []string{"Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"} {` from the dependency chain described above.
- Without L31: 712 tokens; removes `teams = append(teams, Team{name: name})` from the dependency chain described above.
- Without L32: 729 tokens; removes `}` from the dependency chain described above.
- Without L33: 723 tokens; removes `matches := []string{` from the dependency chain described above.
- Without L34: 675 tokens; removes `"Lions 0-3 Bears", "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks", "Wolves 2-1 Eagles",` from the dependency chain described above.
- Without L35: 675 tokens; removes `"Lions 0-1 Tigers", "Tigers 3-3 Bears", "Eagles 2-2 Lions", "Sharks 2-2 Wolves", "Bears 3-1 Wolves",` from the dependency chain described above.
- Without L36: 675 tokens; removes `"Lions 2-0 Sharks", "Tigers 2-1 Eagles", "Eagles 1-0 Bears", "Sharks 2-0 Tigers", "Wolves 2-1 Lions",` from the dependency chain described above.
- Without L37: 729 tokens; removes `}` from the dependency chain described above.
- Without L38: 716 tokens; removes `for _, game := range matches {` from the dependency chain described above.
- Without L39: 721 tokens; removes `var home, away string` from the dependency chain described above.
- Without L40: 721 tokens; removes `var h, a int` from the dependency chain described above.
- Without L41: 695 tokens; removes `fmt.Sscanf(game, "%s %d-%d %s", &home, &h, &a, &away)` from the dependency chain described above.
- Without L42: 718 tokens; removes `x, y := 0, 0` from the dependency chain described above.
- Without L43: 716 tokens; removes `for teams[x].name != home {` from the dependency chain described above.
- Without L44: 726 tokens; removes `x++` from the dependency chain described above.
- Without L45: 728 tokens; removes `}` from the dependency chain described above.
- Without L46: 716 tokens; removes `for teams[y].name != away {` from the dependency chain described above.
- Without L47: 726 tokens; removes `y++` from the dependency chain described above.
- Without L48: 728 tokens; removes `}` from the dependency chain described above.
- Without L49: 715 tokens; removes `record(&teams[x], h, a)` from the dependency chain described above.
- Without L50: 715 tokens; removes `record(&teams[y], a, h)` from the dependency chain described above.
- Without L51: 729 tokens; removes `}` from the dependency chain described above.
- Without L52: 710 tokens; removes `sort.Slice(teams, func(i, j int) bool {` from the dependency chain described above.
- Without L53: 712 tokens; removes `a, b := teams[i], teams[j]` from the dependency chain described above.
- Without L54: 716 tokens; removes `if a.points != b.points {` from the dependency chain described above.
- Without L55: 717 tokens; removes `return a.points > b.points` from the dependency chain described above.
- Without L56: 728 tokens; removes `}` from the dependency chain described above.
- Without L57: 708 tokens; removes `if a.gf-a.ga != b.gf-b.ga {` from the dependency chain described above.
- Without L58: 709 tokens; removes `return a.gf-a.ga > b.gf-b.ga` from the dependency chain described above.
- Without L59: 728 tokens; removes `}` from the dependency chain described above.
- Without L60: 716 tokens; removes `if a.gf != b.gf {` from the dependency chain described above.
- Without L61: 717 tokens; removes `return a.gf > b.gf` from the dependency chain described above.
- Without L62: 728 tokens; removes `}` from the dependency chain described above.
- Without L63: 718 tokens; removes `return a.name < b.name` from the dependency chain described above.
- Without L64: 728 tokens; removes `})` from the dependency chain described above.
