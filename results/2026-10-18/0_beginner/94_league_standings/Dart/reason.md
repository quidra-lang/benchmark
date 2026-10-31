# Task B selection: 94_league_standings / Dart

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.dart`. Selected original locations: L1,L2,L3,L4,L5,L6,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L22,L25,L26,L27,L29,L30,L32,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61,L62,L63,L64,L65,L66,L67,L68,L69,L70,L71,L72,L73.

- L1: `class Team {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `  final String name;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `  int played = 0, wins = 0, draws = 0, losses = 0, gf = 0, ga = 0, points = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `  Team(this.name);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `  int get gd => gf - ga;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `  final teams = {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    for (final name in [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `      'Lions',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `      'Tigers',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `      'Eagles',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `      'Sharks',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `      'Wolves',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `      'Bears',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `    ])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `      name: Team(name),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `  };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `  const matches = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    'Tigers 2-2 Wolves',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    'Wolves 2-1 Eagles',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    'Lions 0-1 Tigers',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    'Tigers 3-3 Bears',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    'Sharks 2-2 Wolves',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    'Bears 3-1 Wolves',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    'Tigers 2-1 Eagles',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    'Sharks 2-0 Tigers',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `    'Wolves 2-1 Lions',` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `  ];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L37: `  for (final match in matches) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    final f = match.split(' ');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `    final goals = f[1].split('-');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    final h = int.parse(goals[0]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    final a = int.parse(goals[1]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    final home = teams[f[0]]!;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `    final away = teams[f[2]]!;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    home.played++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    away.played++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `    home.gf += h;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `    home.ga += a;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `    away.gf += a;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    away.ga += h;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `    if (h > a) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `      home.wins++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `      away.losses++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `      home.points += 3;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `    } else if (h < a) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `      away.wins++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `      home.losses++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `      away.points += 3;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `      home.draws++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `      away.draws++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `      home.points++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `      away.points++;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L64: `  }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L65: `  final order = teams.values.toList()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `    ..sort((a, b) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L67: `      var c = b.points.compareTo(a.points);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `      if (c != 0) return c;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L69: `      c = b.gd.compareTo(a.gd);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L70: `      if (c != 0) return c;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L71: `      c = b.gf.compareTo(a.gf);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L72: `      return c != 0 ? c : a.name.compareTo(b.name);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L73: `    });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **754 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 701 tokens. The contiguous original span L1–L73 costs 835 tokens; the complete original source costs 1003 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 748 tokens; removes `class Team {` from the dependency chain described above.
- Without L2: 746 tokens; removes `final String name;` from the dependency chain described above.
- Without L3: 702 tokens; removes `int played = 0, wins = 0, draws = 0, losses = 0, gf = 0, ga = 0, points = 0;` from the dependency chain described above.
- Without L4: 745 tokens; removes `Team(this.name);` from the dependency chain described above.
- Without L5: 738 tokens; removes `int get gd => gf - ga;` from the dependency chain described above.
- Without L6: 752 tokens; removes `}` from the dependency chain described above.
- Without L9: 745 tokens; removes `final teams = {` from the dependency chain described above.
- Without L10: 742 tokens; removes `for (final name in [` from the dependency chain described above.
- Without L11: 747 tokens; removes `'Lions',` from the dependency chain described above.
- Without L12: 747 tokens; removes `'Tigers',` from the dependency chain described above.
- Without L13: 747 tokens; removes `'Eagles',` from the dependency chain described above.
- Without L14: 747 tokens; removes `'Sharks',` from the dependency chain described above.
- Without L15: 747 tokens; removes `'Wolves',` from the dependency chain described above.
- Without L16: 747 tokens; removes `'Bears',` from the dependency chain described above.
- Without L17: 750 tokens; removes `])` from the dependency chain described above.
- Without L18: 743 tokens; removes `name: Team(name),` from the dependency chain described above.
- Without L19: 750 tokens; removes `};` from the dependency chain described above.
- Without L20: 745 tokens; removes `const matches = [` from the dependency chain described above.
- Without L22: 742 tokens; removes `'Tigers 2-2 Wolves',` from the dependency chain described above.
- Without L25: 742 tokens; removes `'Wolves 2-1 Eagles',` from the dependency chain described above.
- Without L26: 742 tokens; removes `'Lions 0-1 Tigers',` from the dependency chain described above.
- Without L27: 742 tokens; removes `'Tigers 3-3 Bears',` from the dependency chain described above.
- Without L29: 742 tokens; removes `'Sharks 2-2 Wolves',` from the dependency chain described above.
- Without L30: 742 tokens; removes `'Bears 3-1 Wolves',` from the dependency chain described above.
- Without L32: 742 tokens; removes `'Tigers 2-1 Eagles',` from the dependency chain described above.
- Without L34: 742 tokens; removes `'Sharks 2-0 Tigers',` from the dependency chain described above.
- Without L35: 742 tokens; removes `'Wolves 2-1 Lions',` from the dependency chain described above.
- Without L36: 750 tokens; removes `];` from the dependency chain described above.
- Without L37: 739 tokens; removes `for (final match in matches) {` from the dependency chain described above.
- Without L38: 737 tokens; removes `final f = match.split(' ');` from the dependency chain described above.
- Without L39: 735 tokens; removes `final goals = f[1].split('-');` from the dependency chain described above.
- Without L40: 736 tokens; removes `final h = int.parse(goals[0]);` from the dependency chain described above.
- Without L41: 736 tokens; removes `final a = int.parse(goals[1]);` from the dependency chain described above.
- Without L42: 738 tokens; removes `final home = teams[f[0]]!;` from the dependency chain described above.
- Without L43: 738 tokens; removes `final away = teams[f[2]]!;` from the dependency chain described above.
- Without L44: 747 tokens; removes `home.played++;` from the dependency chain described above.
- Without L45: 747 tokens; removes `away.played++;` from the dependency chain described above.
- Without L46: 744 tokens; removes `home.gf += h;` from the dependency chain described above.
- Without L47: 744 tokens; removes `home.ga += a;` from the dependency chain described above.
- Without L48: 744 tokens; removes `away.gf += a;` from the dependency chain described above.
- Without L49: 744 tokens; removes `away.ga += h;` from the dependency chain described above.
- Without L50: 741 tokens; removes `if (h > a) {` from the dependency chain described above.
- Without L51: 746 tokens; removes `home.wins++;` from the dependency chain described above.
- Without L52: 746 tokens; removes `away.losses++;` from the dependency chain described above.
- Without L53: 743 tokens; removes `home.points += 3;` from the dependency chain described above.
- Without L54: 737 tokens; removes `} else if (h < a) {` from the dependency chain described above.
- Without L55: 746 tokens; removes `away.wins++;` from the dependency chain described above.
- Without L56: 746 tokens; removes `home.losses++;` from the dependency chain described above.
- Without L57: 743 tokens; removes `away.points += 3;` from the dependency chain described above.
- Without L58: 747 tokens; removes `} else {` from the dependency chain described above.
- Without L59: 746 tokens; removes `home.draws++;` from the dependency chain described above.
- Without L60: 746 tokens; removes `away.draws++;` from the dependency chain described above.
- Without L61: 746 tokens; removes `home.points++;` from the dependency chain described above.
- Without L62: 746 tokens; removes `away.points++;` from the dependency chain described above.
- Without L63: 751 tokens; removes `}` from the dependency chain described above.
- Without L64: 751 tokens; removes `}` from the dependency chain described above.
- Without L65: 738 tokens; removes `final order = teams.values.toList()` from the dependency chain described above.
- Without L66: 741 tokens; removes `..sort((a, b) {` from the dependency chain described above.
- Without L67: 733 tokens; removes `var c = b.points.compareTo(a.points);` from the dependency chain described above.
- Without L68: 737 tokens; removes `if (c != 0) return c;` from the dependency chain described above.
- Without L69: 735 tokens; removes `c = b.gd.compareTo(a.gd);` from the dependency chain described above.
- Without L70: 737 tokens; removes `if (c != 0) return c;` from the dependency chain described above.
- Without L71: 735 tokens; removes `c = b.gf.compareTo(a.gf);` from the dependency chain described above.
- Without L72: 725 tokens; removes `return c != 0 ? c : a.name.compareTo(b.name);` from the dependency chain described above.
- Without L73: 749 tokens; removes `});` from the dependency chain described above.
