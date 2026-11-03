# Task B selection: 96_poker_hand_rank / Zig

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.zig`. Selected original locations: L3,L5,L6,L7,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L53,L54,L62,L63,L64,L66,L67,L68,L69,L70,L71,L72,L73,L74,L78,L79,L80,L81,L82,L83,L85,L86,L87,L88,L89,L90,L91,L92,L93,L98,L99,L100.

- L3: `const Hand = struct { original: []const u8, category: u8, sequence: [5]u8, len: usize };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `fn rankLess(counts: *const [15]u8, a: u8, b: u8) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L6: `    return if (counts[a] != counts[b]) counts[a] > counts[b] else a > b;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L7: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L9: `fn evaluate(original: []const u8) Hand {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    var counts: [15]u8 = @splat(0);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    var flush = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    var suit: u8 = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `    var tokens = std.mem.splitScalar(u8, original, ' ');` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `    while (tokens.next()) |card| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        const rank = std.mem.findScalar(u8, "23456789TJQKA", card[0]).? + 2;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `        counts[rank] += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        if (suit == 0)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L18: `            suit = card[1];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L19: `        if (card[1] != suit)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `            flush = false;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L22: `    var sequence: [5]u8 = undefined;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    var len: usize = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    var pairs: u8 = 0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `    var triple = false;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    var four = false;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `    for (2..15) |r| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `        if (counts[r] > 0) {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `            sequence[len] = @intCast(r);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `            len += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L32: `        if (counts[r] == 2)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `            pairs += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `        if (counts[r] == 3)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L35: `            triple = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `        if (counts[r] == 4)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L37: `            four = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L39: `    const wheel = len == 5 and counts[14] == 1 and` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `        counts[2] == 1 and counts[3] == 1 and counts[4] == 1 and counts[5] == 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L41: `    const straight = len == 5 and (wheel or sequence[4] - sequence[0] == 4);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    std.mem.sort(u8, sequence[0..len], @as(*const [15]u8, &counts), rankLess);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L43: `    if (wheel)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `        sequence = .{ 5, 4, 3, 2, 1 };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `    const category: u8 = if (straight and flush)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `        8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L47: `    else if (four)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `    else if (triple and pairs == 1)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `        6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `    else if (flush)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L52: `        5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L53: `    else if (straight)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L54: `        4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L62: `        0;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L63: `    return .{ .original = original, .category = category, .sequence = sequence, .len = len };` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L66: `fn less(_: void, a: Hand, b: Hand) bool {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L67: `    if (a.category != b.category)` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `        return a.category > b.category;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L69: `    for (0..a.len) |i| {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L70: `        if (a.sequence[i] != b.sequence[i])` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L71: `            return a.sequence[i] > b.sequence[i];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L72: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L73: `    return false;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L74: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L78: `    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L79: `    const out = &writer.interface;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L80: `    const originals = [_][]const u8{` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L81: `        "9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L82: `        "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L83: `    };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L85: `    for (originals, 0..) |s, i|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L86: `        hands[i] = evaluate(s);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L87: `    std.mem.sort(Hand, &hands, {}, less);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L88: `    const categories = [_][]const u8{` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L89: `        "high card",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L90: `        "one pair",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L91: `        "two pair",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L92: `        "three of a kind",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L93: `        "straight",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L98: `    };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L99: `    for (hands, 0..) |hand, i|` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L100: `        try out.print("{d}. {s}: {s}\n", .{ i + 1, hand.original, categories[hand.category] });` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.

## Minimization and language semantics

The final selected excerpt measures **1366 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 1225 tokens. The contiguous original span L3–L100 costs 1516 tokens; the complete original source costs 1544 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L3: 1324 tokens; removes `const Hand = struct { original: []const u8, category: u8, sequence: [5]u8, len: usize };` from the dependency chain described above.
- Without L5: 1334 tokens; removes `fn rankLess(counts: *const [15]u8, a: u8, b: u8) bool {` from the dependency chain described above.
- Without L6: 1326 tokens; removes `return if (counts[a] != counts[b]) counts[a] > counts[b] else a > b;` from the dependency chain described above.
- Without L7: 1364 tokens; removes `}` from the dependency chain described above.
- Without L9: 1349 tokens; removes `fn evaluate(original: []const u8) Hand {` from the dependency chain described above.
- Without L10: 1345 tokens; removes `var counts: [15]u8 = @splat(0);` from the dependency chain described above.
- Without L11: 1356 tokens; removes `var flush = true;` from the dependency chain described above.
- Without L12: 1353 tokens; removes `var suit: u8 = 0;` from the dependency chain described above.
- Without L13: 1340 tokens; removes `var tokens = std.mem.splitScalar(u8, original, ' ');` from the dependency chain described above.
- Without L14: 1349 tokens; removes `while (tokens.next()) |card| {` from the dependency chain described above.
- Without L15: 1323 tokens; removes `const rank = std.mem.findScalar(u8, "23456789TJQKA", card[0]).? + 2;` from the dependency chain described above.
- Without L16: 1354 tokens; removes `counts[rank] += 1;` from the dependency chain described above.
- Without L17: 1354 tokens; removes `if (suit == 0)` from the dependency chain described above.
- Without L18: 1353 tokens; removes `suit = card[1];` from the dependency chain described above.
- Without L19: 1351 tokens; removes `if (card[1] != suit)` from the dependency chain described above.
- Without L20: 1356 tokens; removes `flush = false;` from the dependency chain described above.
- Without L21: 1363 tokens; removes `}` from the dependency chain described above.
- Without L22: 1350 tokens; removes `var sequence: [5]u8 = undefined;` from the dependency chain described above.
- Without L23: 1353 tokens; removes `var len: usize = 0;` from the dependency chain described above.
- Without L24: 1353 tokens; removes `var pairs: u8 = 0;` from the dependency chain described above.
- Without L25: 1356 tokens; removes `var triple = false;` from the dependency chain described above.
- Without L26: 1356 tokens; removes `var four = false;` from the dependency chain described above.
- Without L27: 1350 tokens; removes `for (2..15) |r| {` from the dependency chain described above.
- Without L28: 1349 tokens; removes `if (counts[r] > 0) {` from the dependency chain described above.
- Without L29: 1348 tokens; removes `sequence[len] = @intCast(r);` from the dependency chain described above.
- Without L30: 1356 tokens; removes `len += 1;` from the dependency chain described above.
- Without L31: 1362 tokens; removes `}` from the dependency chain described above.
- Without L32: 1351 tokens; removes `if (counts[r] == 2)` from the dependency chain described above.
- Without L33: 1356 tokens; removes `pairs += 1;` from the dependency chain described above.
- Without L34: 1351 tokens; removes `if (counts[r] == 3)` from the dependency chain described above.
- Without L35: 1356 tokens; removes `triple = true;` from the dependency chain described above.
- Without L36: 1351 tokens; removes `if (counts[r] == 4)` from the dependency chain described above.
- Without L37: 1356 tokens; removes `four = true;` from the dependency chain described above.
- Without L38: 1363 tokens; removes `}` from the dependency chain described above.
- Without L39: 1339 tokens; removes `const wheel = len == 5 and counts[14] == 1 and` from the dependency chain described above.
- Without L40: 1321 tokens; removes `counts[2] == 1 and counts[3] == 1 and counts[4] == 1 and counts[5] == 1;` from the dependency chain described above.
- Without L41: 1328 tokens; removes `const straight = len == 5 and (wheel or sequence[4] - sequence[0] == 4);` from the dependency chain described above.
- Without L42: 1325 tokens; removes `std.mem.sort(u8, sequence[0..len], @as(*const [15]u8, &counts), rankLess);` from the dependency chain described above.
- Without L43: 1359 tokens; removes `if (wheel)` from the dependency chain described above.
- Without L44: 1340 tokens; removes `sequence = .{ 5, 4, 3, 2, 1 };` from the dependency chain described above.
- Without L45: 1346 tokens; removes `const category: u8 = if (straight and flush)` from the dependency chain described above.
- Without L46: 1362 tokens; removes `8` from the dependency chain described above.
- Without L47: 1357 tokens; removes `else if (four)` from the dependency chain described above.
- Without L48: 1362 tokens; removes `7` from the dependency chain described above.
- Without L49: 1349 tokens; removes `else if (triple and pairs == 1)` from the dependency chain described above.
- Without L50: 1362 tokens; removes `6` from the dependency chain described above.
- Without L51: 1357 tokens; removes `else if (flush)` from the dependency chain described above.
- Without L52: 1362 tokens; removes `5` from the dependency chain described above.
- Without L53: 1357 tokens; removes `else if (straight)` from the dependency chain described above.
- Without L54: 1362 tokens; removes `4` from the dependency chain described above.
- Without L62: 1361 tokens; removes `0;` from the dependency chain described above.
- Without L63: 1326 tokens; removes `return .{ .original = original, .category = category, .sequence = sequence, .len = len };` from the dependency chain described above.
- Without L64: 1364 tokens; removes `}` from the dependency chain described above.
- Without L66: 1342 tokens; removes `fn less(_: void, a: Hand, b: Hand) bool {` from the dependency chain described above.
- Without L67: 1351 tokens; removes `if (a.category != b.category)` from the dependency chain described above.
- Without L68: 1351 tokens; removes `return a.category > b.category;` from the dependency chain described above.
- Without L69: 1349 tokens; removes `for (0..a.len) |i| {` from the dependency chain described above.
- Without L70: 1344 tokens; removes `if (a.sequence[i] != b.sequence[i])` from the dependency chain described above.
- Without L71: 1344 tokens; removes `return a.sequence[i] > b.sequence[i];` from the dependency chain described above.
- Without L72: 1363 tokens; removes `}` from the dependency chain described above.
- Without L73: 1360 tokens; removes `return false;` from the dependency chain described above.
- Without L74: 1364 tokens; removes `}` from the dependency chain described above.
- Without L78: 1334 tokens; removes `var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);` from the dependency chain described above.
- Without L79: 1353 tokens; removes `const out = &writer.interface;` from the dependency chain described above.
- Without L80: 1350 tokens; removes `const originals = [_][]const u8{` from the dependency chain described above.
- Without L81: 1298 tokens; removes `"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",` from the dependency chain described above.
- Without L82: 1298 tokens; removes `"3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D",` from the dependency chain described above.
- Without L83: 1362 tokens; removes `};` from the dependency chain described above.
- Without L85: 1348 tokens; removes `for (originals, 0..) |s, i|` from the dependency chain described above.
- Without L86: 1351 tokens; removes `hands[i] = evaluate(s);` from the dependency chain described above.
- Without L87: 1344 tokens; removes `std.mem.sort(Hand, &hands, {}, less);` from the dependency chain described above.
- Without L88: 1350 tokens; removes `const categories = [_][]const u8{` from the dependency chain described above.
- Without L89: 1357 tokens; removes `"high card",` from the dependency chain described above.
- Without L90: 1357 tokens; removes `"one pair",` from the dependency chain described above.
- Without L91: 1357 tokens; removes `"two pair",` from the dependency chain described above.
- Without L92: 1353 tokens; removes `"three of a kind",` from the dependency chain described above.
- Without L93: 1359 tokens; removes `"straight",` from the dependency chain described above.
- Without L98: 1362 tokens; removes `};` from the dependency chain described above.
- Without L99: 1348 tokens; removes `for (hands, 0..) |hand, i|` from the dependency chain described above.
- Without L100: 1315 tokens; removes `try out.print("{d}. {s}: {s}\n", .{ i + 1, hand.original, categories[hand.category] });` from the dependency chain described above.
