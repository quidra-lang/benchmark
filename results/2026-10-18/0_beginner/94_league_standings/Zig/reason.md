# Task B selection: 94_league_standings / Zig

## Common answer requirements

Trace Tigers/Wolves five matches to played/wins/draws/losses/GF/GA/points; identify first separating criterion after points and GD ties; establish full standings order.

## Answer and source dependencies

Tigers results are 2-2 Wolves, 1-0 Lions, 3-3 Bears, 2-1 Eagles, 0-2 Sharks: five played, two wins, two draws, one loss, GF 8, GA 8, GD 0, points 8. Wolves results are 2-2 Tigers, 2-1 Eagles, 2-2 Sharks, 1-3 Bears, 2-1 Lions: likewise P5 W2 D2 L1 and eight points, but GF9 GA9 GD0. Home/away goal assignment swaps the two score components correctly; every match adds both GF and GA, and wins/draws contribute three/one points. Comparison first tries points descending (tie 8), then GD descending (tie 0), then GF descending: Wolves 9 beats Tigers 8. Ascending team name is the final fallback only if all numeric keys tie. Stable ordering after alphabetizing names supplies that fallback in implementations without an explicit name comparison.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing association between the literal match rows and matches input, and missing record/condition/match-loop boundaries before ranking. The repair retains that declaration association and the actual lexical boundaries. Dart additionally retains Team(this.name) and field declarations, establishing name/record mapping; Go retains lookup and points/GD/GF comparator condition boundaries. Tigers trace is D2-2Wolves, W1-0Lions, D3-3Bears, W2-1Eagles, L0-2Sharks: P5W2D2L1GF8GA8GD0Pts8. Wolves trace is D2-2Tigers,W2-1Eagles,D2-2Sharks,L1-3Bears,W2-1Lions: P5W2D2L1GF9GA9GD0Pts8. Points8 and GD0 tie; GF9>8 first separates Wolves ahead of Tigers. Source ordering then uses ASCII name ascending for complete ties.

Source: `main.zig`. Selected original locations: L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L14,L15,L16,L17,L18,L20,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61,L62,L63,L64,L65,L66,L67,L68,L69,L70,L71,L72,L73,L74,L75,L76.

- L3: `const Team = struct {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    name: []const u8,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `    played: u32 = 0,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    wins: u32 = 0,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `    draws: u32 = 0,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    losses: u32 = 0,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    gf: i32 = 0,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    ga: i32 = 0,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    points: u32 = 0,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `};` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L14: `fn find(teams: *const [6]Team, name: []const u8) usize {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `    for (teams, 0..) |t, i| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        if (std.mem.eql(u8, t.name, name))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `            return i;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L20: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `fn less(_: void, a: Team, b: Team) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    if (a.points != b.points)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `        return a.points > b.points;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    const ag = a.gf - a.ga;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    const bg = b.gf - b.ga;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    if (ag != bg)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        return ag > bg;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `    if (a.gf != b.gf)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `        return a.gf > b.gf;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `    return std.mem.order(u8, a.name, b.name) == .lt;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L38: `    var teams = [_]Team{` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L39: `        .{ .name = "Lions" },  .{ .name = "Tigers" }, .{ .name = "Eagles" }, .{ .name = "Sharks" },` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `        .{ .name = "Wolves" }, .{ .name = "Bears" },` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L42: `    const matches = [_][]const u8{` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `        "Lions 0-3 Bears",   "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `        "Wolves 2-1 Eagles", "Lions 0-1 Tigers",  "Tigers 3-3 Bears",  "Eagles 2-2 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `        "Sharks 2-2 Wolves", "Bears 3-1 Wolves",  "Lions 2-0 Sharks",  "Tigers 2-1 Eagles",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `        "Eagles 1-0 Bears",  "Sharks 2-0 Tigers", "Wolves 2-1 Lions",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `    };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L48: `    for (matches) |match| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        var fields = std.mem.splitScalar(u8, match, ' ');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `        const home = find(&teams, fields.next().?);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `        var goals = std.mem.splitScalar(u8, fields.next().?, '-');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `        const h = try std.fmt.parseInt(i32, goals.next().?, 10);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `        const a = try std.fmt.parseInt(i32, goals.next().?, 10);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `        const away = find(&teams, fields.next().?);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L55: `        teams[home].played += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L56: `        teams[away].played += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `        teams[home].gf += h;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L58: `        teams[home].ga += a;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L59: `        teams[away].gf += a;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `        teams[away].ga += h;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L61: `        if (h > a) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `            teams[home].wins += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `            teams[away].losses += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `            teams[home].points += 3;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L65: `        } else if (h < a) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `            teams[away].wins += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L67: `            teams[home].losses += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `            teams[away].points += 3;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L69: `        } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L70: `            teams[home].draws += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L71: `            teams[away].draws += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L72: `            teams[home].points += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L73: `            teams[away].points += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L74: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L75: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L76: `    std.mem.sort(Team, &teams, {}, less);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **1133 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 1108 tokens. The contiguous original span L3–L76 costs 1227 tokens; the complete original source costs 1483 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 1123 tokens; removes `const Team = struct {` from the dependency chain described above.
- Without L4: 1123 tokens; removes `name: []const u8,` from the dependency chain described above.
- Without L5: 1122 tokens; removes `played: u32 = 0,` from the dependency chain described above.
- Without L6: 1122 tokens; removes `wins: u32 = 0,` from the dependency chain described above.
- Without L7: 1122 tokens; removes `draws: u32 = 0,` from the dependency chain described above.
- Without L8: 1122 tokens; removes `losses: u32 = 0,` from the dependency chain described above.
- Without L9: 1122 tokens; removes `gf: i32 = 0,` from the dependency chain described above.
- Without L10: 1122 tokens; removes `ga: i32 = 0,` from the dependency chain described above.
- Without L11: 1122 tokens; removes `points: u32 = 0,` from the dependency chain described above.
- Without L12: 1130 tokens; removes `};` from the dependency chain described above.
- Without L14: 1104 tokens; removes `fn find(teams: *const [6]Team, name: []const u8) usize {` from the dependency chain described above.
- Without L15: 1113 tokens; removes `for (teams, 0..) |t, i| {` from the dependency chain described above.
- Without L16: 1110 tokens; removes `if (std.mem.eql(u8, t.name, name))` from the dependency chain described above.
- Without L17: 1125 tokens; removes `return i;` from the dependency chain described above.
- Without L18: 1130 tokens; removes `}` from the dependency chain described above.
- Without L20: 1131 tokens; removes `}` from the dependency chain described above.
- Without L22: 1109 tokens; removes `fn less(_: void, a: Team, b: Team) bool {` from the dependency chain described above.
- Without L23: 1118 tokens; removes `if (a.points != b.points)` from the dependency chain described above.
- Without L24: 1118 tokens; removes `return a.points > b.points;` from the dependency chain described above.
- Without L25: 1115 tokens; removes `const ag = a.gf - a.ga;` from the dependency chain described above.
- Without L26: 1115 tokens; removes `const bg = b.gf - b.ga;` from the dependency chain described above.
- Without L27: 1122 tokens; removes `if (ag != bg)` from the dependency chain described above.
- Without L28: 1122 tokens; removes `return ag > bg;` from the dependency chain described above.
- Without L29: 1118 tokens; removes `if (a.gf != b.gf)` from the dependency chain described above.
- Without L30: 1118 tokens; removes `return a.gf > b.gf;` from the dependency chain described above.
- Without L31: 1105 tokens; removes `return std.mem.order(u8, a.name, b.name) == .lt;` from the dependency chain described above.
- Without L32: 1131 tokens; removes `}` from the dependency chain described above.
- Without L38: 1120 tokens; removes `var teams = [_]Team{` from the dependency chain described above.
- Without L39: 1071 tokens; removes `.{ .name = "Lions" },  .{ .name = "Tigers" }, .{ .name = "Eagles" }, .{ .name = "Sharks" },` from the dependency chain described above.
- Without L40: 1101 tokens; removes `.{ .name = "Wolves" }, .{ .name = "Bears" },` from the dependency chain described above.
- Without L41: 1129 tokens; removes `};` from the dependency chain described above.
- Without L42: 1117 tokens; removes `const matches = [_][]const u8{` from the dependency chain described above.
- Without L43: 1086 tokens; removes `"Lions 0-3 Bears",   "Tigers 2-2 Wolves", "Eagles 4-0 Sharks", "Bears 0-1 Sharks",` from the dependency chain described above.
- Without L44: 1087 tokens; removes `"Wolves 2-1 Eagles", "Lions 0-1 Tigers",  "Tigers 3-3 Bears",  "Eagles 2-2 Lions",` from the dependency chain described above.
- Without L45: 1087 tokens; removes `"Sharks 2-2 Wolves", "Bears 3-1 Wolves",  "Lions 2-0 Sharks",  "Tigers 2-1 Eagles",` from the dependency chain described above.
- Without L46: 1098 tokens; removes `"Eagles 1-0 Bears",  "Sharks 2-0 Tigers", "Wolves 2-1 Lions",` from the dependency chain described above.
- Without L47: 1129 tokens; removes `};` from the dependency chain described above.
- Without L48: 1120 tokens; removes `for (matches) |match| {` from the dependency chain described above.
- Without L49: 1106 tokens; removes `var fields = std.mem.splitScalar(u8, match, ' ');` from the dependency chain described above.
- Without L50: 1110 tokens; removes `const home = find(&teams, fields.next().?);` from the dependency chain described above.
- Without L51: 1101 tokens; removes `var goals = std.mem.splitScalar(u8, fields.next().?, '-');` from the dependency chain described above.
- Without L52: 1100 tokens; removes `const h = try std.fmt.parseInt(i32, goals.next().?, 10);` from the dependency chain described above.
- Without L53: 1100 tokens; removes `const a = try std.fmt.parseInt(i32, goals.next().?, 10);` from the dependency chain described above.
- Without L54: 1110 tokens; removes `const away = find(&teams, fields.next().?);` from the dependency chain described above.
- Without L55: 1120 tokens; removes `teams[home].played += 1;` from the dependency chain described above.
- Without L56: 1120 tokens; removes `teams[away].played += 1;` from the dependency chain described above.
- Without L57: 1120 tokens; removes `teams[home].gf += h;` from the dependency chain described above.
- Without L58: 1120 tokens; removes `teams[home].ga += a;` from the dependency chain described above.
- Without L59: 1120 tokens; removes `teams[away].gf += a;` from the dependency chain described above.
- Without L60: 1120 tokens; removes `teams[away].ga += h;` from the dependency chain described above.
- Without L61: 1119 tokens; removes `if (h > a) {` from the dependency chain described above.
- Without L62: 1119 tokens; removes `teams[home].wins += 1;` from the dependency chain described above.
- Without L63: 1119 tokens; removes `teams[away].losses += 1;` from the dependency chain described above.
- Without L64: 1119 tokens; removes `teams[home].points += 3;` from the dependency chain described above.
- Without L65: 1115 tokens; removes `} else if (h < a) {` from the dependency chain described above.
- Without L66: 1119 tokens; removes `teams[away].wins += 1;` from the dependency chain described above.
- Without L67: 1119 tokens; removes `teams[home].losses += 1;` from the dependency chain described above.
- Without L68: 1119 tokens; removes `teams[away].points += 3;` from the dependency chain described above.
- Without L69: 1125 tokens; removes `} else {` from the dependency chain described above.
- Without L70: 1119 tokens; removes `teams[home].draws += 1;` from the dependency chain described above.
- Without L71: 1119 tokens; removes `teams[away].draws += 1;` from the dependency chain described above.
- Without L72: 1119 tokens; removes `teams[home].points += 1;` from the dependency chain described above.
- Without L73: 1119 tokens; removes `teams[away].points += 1;` from the dependency chain described above.
- Without L74: 1129 tokens; removes `}` from the dependency chain described above.
- Without L75: 1130 tokens; removes `}` from the dependency chain described above.
- Without L76: 1111 tokens; removes `std.mem.sort(Team, &teams, {}, less);` from the dependency chain described above.
