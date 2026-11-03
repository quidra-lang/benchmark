# Task B selection: 94_league_standings / Rust

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.rs`. Selected original locations: L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L29,L30,L31,L32,L33,L34,L35,L36,L38,L41,L42,L43,L45,L46,L48,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61,L62,L63,L64,L65,L66.

- L1: `#[derive(Default)]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `struct Team {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    name: String,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    played: i32,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    wins: i32,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    draws: i32,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    losses: i32,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    gf: i32,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    ga: i32,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    points: i32,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L13: `fn record(t: &mut Team, gf: i32, ga: i32) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    t.played += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    t.gf += gf;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `    t.ga += ga;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    if gf > ga {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `        t.wins += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        t.points += 3;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    } else if gf == ga {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `        t.draws += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `        t.points += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        t.losses += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L26: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L29: `    let mut teams: Vec<Team> = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        .iter()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        .map(|&name| Team {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `            name: name.to_string(),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `            ..Team::default()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        })` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `        .collect();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    for game in [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `        "Tigers 2-2 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `        "Wolves 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `        "Lions 0-1 Tigers",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `        "Tigers 3-3 Bears",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `        "Sharks 2-2 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `        "Bears 3-1 Wolves",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        "Tigers 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `        "Sharks 2-0 Tigers",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `        "Wolves 2-1 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `    ] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        let parts: Vec<&str> = game.split(' ').collect();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `        let goals: Vec<i32> = parts[1].split('-').map(|n| n.parse().unwrap()).collect();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `        let x = teams.iter().position(|t| t.name == parts[0]).unwrap();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `        let y = teams.iter().position(|t| t.name == parts[2]).unwrap();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `        record(&mut teams[x], goals[0], goals[1]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `        record(&mut teams[y], goals[1], goals[0]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L60: `    teams.sort_by(|a, b| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `        b.points` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `            .cmp(&a.points)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `            .then((b.gf - b.ga).cmp(&(a.gf - a.ga)))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `            .then(b.gf.cmp(&a.gf))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L65: `            .then(a.name.cmp(&b.name))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `    });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **773 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 739 tokens. The contiguous original span L1–L66 costs 861 tokens; the complete original source costs 1082 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 766 tokens; removes `#[derive(Default)]` from the dependency chain described above.
- Without L2: 767 tokens; removes `struct Team {` from the dependency chain described above.
- Without L3: 766 tokens; removes `name: String,` from the dependency chain described above.
- Without L4: 766 tokens; removes `played: i32,` from the dependency chain described above.
- Without L5: 766 tokens; removes `wins: i32,` from the dependency chain described above.
- Without L6: 766 tokens; removes `draws: i32,` from the dependency chain described above.
- Without L7: 766 tokens; removes `losses: i32,` from the dependency chain described above.
- Without L8: 766 tokens; removes `gf: i32,` from the dependency chain described above.
- Without L9: 766 tokens; removes `ga: i32,` from the dependency chain described above.
- Without L10: 766 tokens; removes `points: i32,` from the dependency chain described above.
- Without L11: 771 tokens; removes `}` from the dependency chain described above.
- Without L13: 747 tokens; removes `fn record(t: &mut Team, gf: i32, ga: i32) {` from the dependency chain described above.
- Without L14: 763 tokens; removes `t.played += 1;` from the dependency chain described above.
- Without L15: 763 tokens; removes `t.gf += gf;` from the dependency chain described above.
- Without L16: 763 tokens; removes `t.ga += ga;` from the dependency chain described above.
- Without L17: 762 tokens; removes `if gf > ga {` from the dependency chain described above.
- Without L18: 762 tokens; removes `t.wins += 1;` from the dependency chain described above.
- Without L19: 762 tokens; removes `t.points += 3;` from the dependency chain described above.
- Without L20: 758 tokens; removes `} else if gf == ga {` from the dependency chain described above.
- Without L21: 762 tokens; removes `t.draws += 1;` from the dependency chain described above.
- Without L22: 762 tokens; removes `t.points += 1;` from the dependency chain described above.
- Without L23: 766 tokens; removes `} else {` from the dependency chain described above.
- Without L24: 762 tokens; removes `t.losses += 1;` from the dependency chain described above.
- Without L25: 770 tokens; removes `}` from the dependency chain described above.
- Without L26: 771 tokens; removes `}` from the dependency chain described above.
- Without L29: 727 tokens; removes `let mut teams: Vec<Team> = ["Lions", "Tigers", "Eagles", "Sharks", "Wolves", "Bears"]` from the dependency chain described above.
- Without L30: 766 tokens; removes `.iter()` from the dependency chain described above.
- Without L31: 759 tokens; removes `.map(|&name| Team {` from the dependency chain described above.
- Without L32: 758 tokens; removes `name: name.to_string(),` from the dependency chain described above.
- Without L33: 763 tokens; removes `..Team::default()` from the dependency chain described above.
- Without L34: 768 tokens; removes `})` from the dependency chain described above.
- Without L35: 765 tokens; removes `.collect();` from the dependency chain described above.
- Without L36: 764 tokens; removes `for game in [` from the dependency chain described above.
- Without L38: 760 tokens; removes `"Tigers 2-2 Wolves",` from the dependency chain described above.
- Without L41: 760 tokens; removes `"Wolves 2-1 Eagles",` from the dependency chain described above.
- Without L42: 760 tokens; removes `"Lions 0-1 Tigers",` from the dependency chain described above.
- Without L43: 760 tokens; removes `"Tigers 3-3 Bears",` from the dependency chain described above.
- Without L45: 760 tokens; removes `"Sharks 2-2 Wolves",` from the dependency chain described above.
- Without L46: 760 tokens; removes `"Bears 3-1 Wolves",` from the dependency chain described above.
- Without L48: 760 tokens; removes `"Tigers 2-1 Eagles",` from the dependency chain described above.
- Without L50: 760 tokens; removes `"Sharks 2-0 Tigers",` from the dependency chain described above.
- Without L51: 760 tokens; removes `"Wolves 2-1 Lions",` from the dependency chain described above.
- Without L52: 768 tokens; removes `] {` from the dependency chain described above.
- Without L53: 744 tokens; removes `let parts: Vec<&str> = game.split(' ').collect();` from the dependency chain described above.
- Without L54: 726 tokens; removes `let goals: Vec<i32> = parts[1].split('-').map(|n| n.parse().unwrap()).collect();` from the dependency chain described above.
- Without L55: 736 tokens; removes `let x = teams.iter().position(|t| t.name == parts[0]).unwrap();` from the dependency chain described above.
- Without L56: 736 tokens; removes `let y = teams.iter().position(|t| t.name == parts[2]).unwrap();` from the dependency chain described above.
- Without L57: 747 tokens; removes `record(&mut teams[x], goals[0], goals[1]);` from the dependency chain described above.
- Without L58: 747 tokens; removes `record(&mut teams[y], goals[1], goals[0]);` from the dependency chain described above.
- Without L59: 770 tokens; removes `}` from the dependency chain described above.
- Without L60: 757 tokens; removes `teams.sort_by(|a, b| {` from the dependency chain described above.
- Without L61: 767 tokens; removes `b.points` from the dependency chain described above.
- Without L62: 761 tokens; removes `.cmp(&a.points)` from the dependency chain described above.
- Without L63: 738 tokens; removes `.then((b.gf - b.ga).cmp(&(a.gf - a.ga)))` from the dependency chain described above.
- Without L64: 754 tokens; removes `.then(b.gf.cmp(&a.gf))` from the dependency chain described above.
- Without L65: 754 tokens; removes `.then(a.name.cmp(&b.name))` from the dependency chain described above.
- Without L66: 768 tokens; removes `});` from the dependency chain described above.
