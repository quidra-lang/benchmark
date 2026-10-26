const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{Invalid};
const faces = "URFDLB";
const colors = "WRGYOB";
const letters = "RLMrlxUDEudyFBSfbz";
const State = [54]u8;
const Permutation = [54]u8;
const Vector = [3]i8;
const Move = struct { letter: u8, amount: u8 };
const Place = struct { cubie: Vector, normal: Vector };
const Turn = struct { axis: usize, count: usize, layers: []const i8 };
const Group = struct { names: []const Text, stickers: []const []const usize };
const Piece = struct { id: ?usize = null, orientation: usize = 0 };
const Pieces = struct { count: usize, values: [12]Piece = undefined };
const Rotation = struct { moves: []const Move, effect: Permutation };
const Normalized = struct { cube: State, rotation: usize };
const Saved = struct { cube: State, history: []const Move };
const Macros = std.StringHashMapUnmanaged([]const Move);
const corner_group: Group = .{
    .names = &.{ "URF", "UFL", "ULB", "UBR", "DFR", "DLF", "DBL", "DRB" },
    .stickers = &.{ &.{ 8, 9, 20 }, &.{ 6, 18, 38 }, &.{ 0, 36, 47 }, &.{ 2, 45, 11 }, &.{ 29, 26, 15 }, &.{ 27, 44, 24 }, &.{ 33, 53, 42 }, &.{ 35, 17, 51 } },
};
const edge_group: Group = .{
    .names = &.{ "UR", "UF", "UL", "UB", "DR", "DF", "DL", "DB", "FR", "FL", "BL", "BR" },
    .stickers = &.{ &.{ 5, 10 }, &.{ 7, 19 }, &.{ 3, 37 }, &.{ 1, 46 }, &.{ 32, 16 }, &.{ 28, 25 }, &.{ 30, 43 }, &.{ 34, 52 }, &.{ 23, 12 }, &.{ 21, 41 }, &.{ 50, 39 }, &.{ 48, 14 } },
};
const center_group: Group = .{
    .names = &.{ "U", "R", "F", "D", "L", "B" },
    .stickers = &.{ &.{4}, &.{13}, &.{22}, &.{31}, &.{40}, &.{49} },
};
var reason: Text = "";
fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn bad(gpa: Allocator, comptime pattern: Text, args: anytype) Error {
    reason = std.fmt.allocPrint(gpa, pattern, args) catch return error.OutOfMemory;
    return error.Invalid;
}
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Allocator.Error!void {
        try self.bytes.appendSlice(self.gpa, text);
    }
    fn byte(self: *Builder, c: u8) Allocator.Error!void {
        try self.bytes.append(self.gpa, c);
    }
    fn print(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.add(try std.fmt.allocPrint(self.gpa, pattern, args));
    }
    fn line(self: *Builder, comptime pattern: Text, args: anytype) Allocator.Error!void {
        try self.print(pattern ++ "\n", args);
    }
    fn result(self: *const Builder) Text {
        return self.bytes.items;
    }
};
fn split(gpa: Allocator, text: Text, separator: u8) Allocator.Error![]Text {
    var result: std.ArrayList(Text) = .empty;
    var start: usize = 0;
    for (text, 0..) |c, i| if (c == separator) {
        try result.append(gpa, text[start..i]);
        start = i + 1;
    };
    try result.append(gpa, text[start..]);
    return result.items;
}
fn join(gpa: Allocator, parts: []const Text, separator: Text) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (parts, 0..) |part, i| {
        if (i > 0) try out.add(separator);
        try out.add(part);
    }
    return out.result();
}
fn identity() Permutation {
    var p: Permutation = undefined;
    for (&p, 0..) |*v, i| v.* = @intCast(i);
    return p;
}
fn compose(a: Permutation, b: Permutation) Permutation {
    var p: Permutation = undefined;
    for (&p, 0..) |*v, i| v.* = a[b[i]];
    return p;
}
fn inversePermutation(p: Permutation) Permutation {
    var result: Permutation = undefined;
    for (p, 0..) |source, i| result[source] = @intCast(i);
    return result;
}
fn permute(cube: State, p: Permutation) State {
    var result: State = undefined;
    for (&result, 0..) |*v, i| v.* = cube[p[i]];
    return result;
}
fn inverse(gpa: Allocator, moves: []const Move) Allocator.Error![]Move {
    const result = try gpa.alloc(Move, moves.len);
    for (moves, 0..) |move, i| result[moves.len - 1 - i] = .{ .letter = move.letter, .amount = 4 - move.amount };
    return result;
}
fn quarter(vector: Vector, axis: usize) Vector {
    var result = vector;
    const a = (axis + 1) % 3;
    const b = (axis + 2) % 3;
    result[a] = vector[b];
    result[b] = -vector[a];
    return result;
}
fn turn(letter: u8) Turn {
    return switch (letter) {
        'R' => .{ .axis = 0, .count = 1, .layers = &.{1} },
        'L' => .{ .axis = 0, .count = 3, .layers = &.{-1} },
        'M' => .{ .axis = 0, .count = 3, .layers = &.{0} },
        'r' => .{ .axis = 0, .count = 1, .layers = &.{ 0, 1 } },
        'l' => .{ .axis = 0, .count = 3, .layers = &.{ -1, 0 } },
        'x' => .{ .axis = 0, .count = 1, .layers = &.{ -1, 0, 1 } },
        'U' => .{ .axis = 1, .count = 1, .layers = &.{1} },
        'D' => .{ .axis = 1, .count = 3, .layers = &.{-1} },
        'E' => .{ .axis = 1, .count = 3, .layers = &.{0} },
        'u' => .{ .axis = 1, .count = 1, .layers = &.{ 0, 1 } },
        'd' => .{ .axis = 1, .count = 3, .layers = &.{ -1, 0 } },
        'y' => .{ .axis = 1, .count = 1, .layers = &.{ -1, 0, 1 } },
        'F' => .{ .axis = 2, .count = 1, .layers = &.{1} },
        'B' => .{ .axis = 2, .count = 3, .layers = &.{-1} },
        'S' => .{ .axis = 2, .count = 1, .layers = &.{0} },
        'f' => .{ .axis = 2, .count = 1, .layers = &.{ 0, 1 } },
        'b' => .{ .axis = 2, .count = 3, .layers = &.{ -1, 0 } },
        'z' => .{ .axis = 2, .count = 1, .layers = &.{ -1, 0, 1 } },
        else => unreachable,
    };
}
fn literalMoves(gpa: Allocator, text: Text) Allocator.Error![]Move {
    var result: std.ArrayList(Move) = .empty;
    for (try split(gpa, text, ' ')) |word| {
        if (word.len == 0) continue;
        try result.append(gpa, .{ .letter = word[0], .amount = if (word.len == 1) 1 else if (word[1] == '2') 2 else 3 });
    }
    return result.items;
}
fn moveText(gpa: Allocator, move: Move) Allocator.Error!Text {
    return std.fmt.allocPrint(gpa, "{c}{s}", .{ move.letter, if (move.amount == 2) "2" else if (move.amount == 3) "'" else "" });
}
fn movesText(gpa: Allocator, moves: []const Move) Allocator.Error!Text {
    var out: Builder = .{ .gpa = gpa };
    for (moves, 0..) |move, i| {
        if (i > 0) try out.byte(' ');
        try out.add(try moveText(gpa, move));
    }
    return out.result();
}
fn sequenceText(gpa: Allocator, moves: []const Move) Allocator.Error!Text {
    return std.fmt.allocPrint(gpa, "{d}{s}{s}", .{ moves.len, if (moves.len == 0) "" else " ", try movesText(gpa, moves) });
}
fn contains(words: []const Text, word: Text) bool {
    for (words) |item| if (equal(item, word)) return true;
    return false;
}
fn misplaced(cube: State) usize {
    var count: usize = 0;
    for (cube, 0..) |color, i| if (color != cube[i / 9 * 9 + 4]) {
        count += 1;
    };
    return count;
}
fn identify(cube: State, group: Group) Pieces {
    var result: Pieces = .{ .count = group.names.len };
    for (group.stickers, 0..) |stickers, position| {
        result.values[position] = .{};
        find: for (group.names, 0..) |name, id| {
            for (0..stickers.len) |orientation| {
                var same = true;
                for (stickers, 0..) |_, i| {
                    const face = std.mem.findScalar(u8, faces, name[i]).?;
                    if (cube[stickers[(orientation + i) % stickers.len]] != colors[face]) {
                        same = false;
                        break;
                    }
                }
                if (same) {
                    result.values[position] = .{ .id = id, .orientation = orientation };
                    break :find;
                }
            }
        }
    }
    return result;
}
fn cycles(gpa: Allocator, cube: State, group: Group) Error!Text {
    const identified = identify(cube, group);
    var where: [12]usize = undefined;
    var orientations: [12]usize = undefined;
    var seen: [12]bool = @splat(false);
    for (identified.values[0..identified.count], 0..) |piece, position| {
        where[piece.id.?] = position;
        orientations[piece.id.?] = piece.orientation;
    }
    var written: std.ArrayList(Text) = .empty;
    for (0..group.names.len) |first| {
        if (seen[first]) continue;
        var names: std.ArrayList(Text) = .empty;
        var sum: usize = 0;
        var at = first;
        while (!seen[at]) {
            seen[at] = true;
            try names.append(gpa, group.names[at]);
            sum += orientations[at];
            at = where[at];
        }
        const width = group.stickers[0].len;
        const mark: Text = if (width == 1 or sum % width == 0) "" else if (sum % width == 1) "+" else "-";
        if (names.items.len > 1 or mark.len != 0) try written.append(gpa, try std.fmt.allocPrint(gpa, "({s}){s}", .{ try join(gpa, names.items, " "), mark }));
    }
    return if (written.items.len == 0) "none" else join(gpa, written.items, " ");
}
fn parity(pieces: Pieces) u1 {
    var result: u1 = 0;
    for (pieces.values[0..pieces.count], 0..) |a, i| {
        for (pieces.values[i + 1 .. pieces.count]) |b| if (a.id.? > b.id.?) {
            result ^= 1;
        };
    }
    return result;
}
fn sameMoves(a: []const Move, b: []const Move) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (x.letter != y.letter or x.amount != y.amount) return false;
    return true;
}
fn simplify(gpa: Allocator, sequence: []const Move) Error![]const Move {
    var current = sequence;
    while (true) {
        var result: std.ArrayList(Move) = .empty;
        var start: usize = 0;
        while (start < current.len) {
            var end = start + 1;
            while (end < current.len and turn(current[end].letter).axis == turn(current[start].letter).axis) end += 1;
            var letter_order: std.ArrayList(u8) = .empty;
            var amounts: [256]usize = @splat(0);
            var seen: [256]bool = @splat(false);
            for (current[start..end]) |move| {
                if (!seen[move.letter]) {
                    seen[move.letter] = true;
                    try letter_order.append(gpa, move.letter);
                }
                amounts[move.letter] += move.amount;
            }
            for (letter_order.items) |letter| if (amounts[letter] % 4 != 0) {
                try result.append(gpa, .{ .letter = letter, .amount = @intCast(amounts[letter] % 4) });
            };
            start = end;
        }
        if (sameMoves(current, result.items)) return result.items;
        current = result.items;
    }
}
fn gcd(first: u64, second: u64) u64 {
    var a = first;
    var b = second;
    while (b != 0) {
        const remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}
fn order(p: Permutation) u64 {
    var seen: [54]bool = @splat(false);
    var result: u64 = 1;
    for (0..54) |first| {
        if (seen[first]) continue;
        var length: u64 = 0;
        var at = first;
        while (!seen[at]) {
            seen[at] = true;
            length += 1;
            at = p[at];
        }
        result = result / gcd(result, length) * length;
    }
    return result;
}
const Model = struct {
    gpa: Allocator,
    tables: [18][3]Permutation = undefined,
    rotations: [24]Rotation = undefined,
    solved: State = undefined,
    fn table(self: *const Model, move: Move) Permutation {
        return self.tables[std.mem.findScalar(u8, letters, move.letter).?][move.amount - 1];
    }
    fn effect(self: *const Model, moves: []const Move) Permutation {
        var result = identity();
        for (moves) |move| result = compose(result, self.table(move));
        return result;
    }
    fn apply(self: *const Model, cube: State, moves: []const Move) State {
        var result = cube;
        for (moves) |move| result = permute(result, self.table(move));
        return result;
    }
    fn findMove(self: *const Model, p: Permutation) Move {
        for (letters, 0..) |letter, i| for (self.tables[i], 0..) |candidate, j| {
            if (std.mem.eql(u8, &p, &candidate)) return .{ .letter = letter, .amount = @intCast(j + 1) };
        };
        unreachable;
    }
    fn conjugate(self: *const Model, rotation: Permutation, move: Move) Move {
        return self.findMove(compose(compose(rotation, self.table(move)), inversePermutation(rotation)));
    }
    fn init(self: *Model) Error!void {
        const frames = [6][3]Vector{
            .{ .{ 0, 1, 0 }, .{ 1, 0, 0 }, .{ 0, 0, 1 } },
            .{ .{ 1, 0, 0 }, .{ 0, 0, -1 }, .{ 0, -1, 0 } },
            .{ .{ 0, 0, 1 }, .{ 1, 0, 0 }, .{ 0, -1, 0 } },
            .{ .{ 0, -1, 0 }, .{ 1, 0, 0 }, .{ 0, 0, -1 } },
            .{ .{ -1, 0, 0 }, .{ 0, 0, 1 }, .{ 0, -1, 0 } },
            .{ .{ 0, 0, -1 }, .{ -1, 0, 0 }, .{ 0, -1, 0 } },
        };
        var places: [54]Place = undefined;
        var next: usize = 0;
        for (frames) |frame| {
            for (0..3) |row| for (0..3) |column| {
                var cubie = frame[0];
                for (0..3) |axis| cubie[axis] += (@as(i8, @intCast(column)) - 1) * frame[1][axis] + (@as(i8, @intCast(row)) - 1) * frame[2][axis];
                places[next] = .{ .cubie = cubie, .normal = frame[0] };
                next += 1;
            };
        }
        for (letters, 0..) |letter, i| {
            const t = turn(letter);
            var p = identity();
            for (places, 0..) |original, source| {
                if (std.mem.findScalar(i8, t.layers, original.cubie[t.axis]) == null) continue;
                var destination = original;
                for (0..t.count) |_| {
                    destination.cubie = quarter(destination.cubie, t.axis);
                    destination.normal = quarter(destination.normal, t.axis);
                }
                for (places, 0..) |candidate, j| {
                    if (std.mem.eql(i8, &destination.cubie, &candidate.cubie) and std.mem.eql(i8, &destination.normal, &candidate.normal)) {
                        p[j] = @intCast(source);
                        break;
                    }
                }
            }
            var current = identity();
            for (0..3) |amount| {
                current = compose(current, p);
                self.tables[i][amount] = current;
            }
        }
        next = 0;
        for ([_]Text{ "", "x", "x2", "x'", "z", "z'" }) |first| {
            for ([_]Text{ "", "y", "y2", "y'" }) |second| {
                const moves = try literalMoves(self.gpa, try std.fmt.allocPrint(self.gpa, "{s} {s}", .{ first, second }));
                self.rotations[next] = .{ .moves = moves, .effect = self.effect(moves) };
                next += 1;
            }
        }
        for (&self.solved, 0..) |*color, i| color.* = colors[i / 9];
    }
    fn normalize(self: *const Model, cube: State) ?Normalized {
        for (self.rotations, 0..) |rotation, i| {
            const candidate = permute(cube, rotation.effect);
            var good = true;
            for (0..6) |face| if (candidate[face * 9 + 4] != colors[face]) {
                good = false;
                break;
            };
            if (good) return .{ .cube = candidate, .rotation = i };
        }
        return null;
    }
    fn check(self: *const Model, word: Text) Error!?Text {
        const gpa = self.gpa;
        if (word.len != 54) return try std.fmt.allocPrint(gpa, "length {d}", .{word.len});
        var counts: [6]usize = @splat(0);
        for (word, 0..) |color, i| {
            const at = std.mem.findScalar(u8, colors, color) orelse return try std.fmt.allocPrint(gpa, "char {d}", .{i + 1});
            counts[at] += 1;
        }
        for (counts, 0..) |count, i| if (count != 9) return try std.fmt.allocPrint(gpa, "count {c} {d}", .{ colors[i], count });
        var cube: State = undefined;
        @memcpy(&cube, word);
        const normalized = self.normalize(cube) orelse return "centers";
        var c = identify(cube, corner_group);
        var e = identify(cube, edge_group);
        for (c.values[0..c.count], 0..) |piece, i| if (piece.id == null) return try std.fmt.allocPrint(gpa, "corner {s}", .{corner_group.names[i]});
        for (e.values[0..e.count], 0..) |piece, i| if (piece.id == null) return try std.fmt.allocPrint(gpa, "edge {s}", .{edge_group.names[i]});
        for ([_]Group{ corner_group, edge_group }, [_]Pieces{ c, e }) |group, pieces| {
            for (group.names, 0..) |name, id| {
                var found = false;
                for (pieces.values[0..pieces.count]) |piece| if (piece.id.? == id) {
                    found = true;
                    break;
                };
                if (!found) return try std.fmt.allocPrint(gpa, "missing {s}", .{name});
            }
        }
        c = identify(normalized.cube, corner_group);
        e = identify(normalized.cube, edge_group);
        var twist: usize = 0;
        var flip: usize = 0;
        for (c.values[0..c.count]) |piece| twist += piece.orientation;
        for (e.values[0..e.count]) |piece| flip += piece.orientation;
        if (twist % 3 != 0) return "twist";
        if (flip % 2 != 0) return "flip";
        if (parity(c) != parity(e)) return "parity";
        return null;
    }
    fn unrotate(self: *const Model, moves: []const Move) Error![]Move {
        var result: std.ArrayList(Move) = .empty;
        var rotation = identity();
        for (moves) |move| {
            const replacement: ?Text = switch (move.letter) {
                'M' => "R L' x'",
                'E' => "U D' y'",
                'S' => "F' B z",
                'r' => "L x",
                'l' => "R x'",
                'u' => "D y",
                'd' => "U y'",
                'f' => "B z",
                'b' => "F z'",
                else => null,
            };
            var expanded: []const Move = undefined;
            if (replacement) |text| {
                const parts = try literalMoves(self.gpa, text);
                for (parts) |*part| part.amount = part.amount * move.amount % 4;
                expanded = parts;
            } else {
                const single = try self.gpa.alloc(Move, 1);
                single[0] = move;
                expanded = single;
            }
            for (expanded) |part| {
                if (std.mem.findScalar(u8, "xyz", part.letter) != null) rotation = compose(rotation, self.table(part)) else try result.append(self.gpa, self.conjugate(rotation, part));
            }
        }
        for (self.rotations) |candidate| {
            if (std.mem.eql(u8, &rotation, &candidate.effect)) {
                try result.appendSlice(self.gpa, candidate.moves);
                return result.items;
            }
        }
        unreachable;
    }
    fn search(self: *const Model, cube: State, depth: usize, previous: u8) Error!?[]Move {
        if (depth == 0) return if (misplaced(cube) == 0) try self.gpa.alloc(Move, 0) else null;
        for (faces) |face| {
            if (face == previous or (previous == 'D' and face == 'U') or (previous == 'L' and face == 'R') or (previous == 'B' and face == 'F')) continue;
            for (1..4) |amount| {
                const move: Move = .{ .letter = face, .amount = @intCast(amount) };
                if (try self.search(permute(cube, self.table(move)), depth - 1, face)) |rest| {
                    const result = try self.gpa.alloc(Move, rest.len + 1);
                    result[0] = move;
                    @memcpy(result[1..], rest);
                    return result;
                }
            }
        }
        return null;
    }
};
const Parser = struct {
    gpa: Allocator,
    line: Text,
    pos: usize,
    macros: *const Macros,
    fn peek(self: *const Parser) u8 {
        return if (self.pos < self.line.len) self.line[self.pos] else 0;
    }
    fn skip(self: *Parser) void {
        while (self.peek() == ' ') self.pos += 1;
    }
    fn syntax(self: *const Parser) Error {
        return bad(self.gpa, "syntax at {d}", .{@min(self.pos + 1, self.line.len + 1)});
    }
    fn power(self: *Parser, moves: []const Move) Error![]Move {
        var count: usize = 1;
        if (self.peek() >= '1' and self.peek() <= '9') {
            count = self.peek() - '0';
            self.pos += 1;
            if (self.peek() >= '0' and self.peek() <= '9') {
                count = count * 10 + self.peek() - '0';
                self.pos += 1;
            }
        }
        const invert = self.peek() == '\'';
        if (invert) self.pos += 1;
        var result: std.ArrayList(Move) = .empty;
        for (0..count) |_| try result.appendSlice(self.gpa, moves);
        return if (invert) inverse(self.gpa, result.items) else result.items;
    }
    fn sequence(self: *Parser) Error![]Move {
        var result: std.ArrayList(Move) = .empty;
        while (true) {
            self.skip();
            const current = self.peek();
            var part: []const Move = undefined;
            if (std.mem.findScalar(u8, letters, current) != null) {
                self.pos += 1;
                var amount: u8 = 1;
                if (self.peek() == '2') {
                    amount = 2;
                    self.pos += 1;
                } else if (self.peek() == '\'') {
                    amount = 3;
                    self.pos += 1;
                }
                const single = try self.gpa.alloc(Move, 1);
                single[0] = .{ .letter = current, .amount = amount };
                part = single;
            } else if (current == '(') {
                self.pos += 1;
                const nested = try self.sequence();
                self.skip();
                if (self.peek() != ')') return self.syntax();
                self.pos += 1;
                part = try self.power(nested);
            } else if (current == '[') {
                self.pos += 1;
                const a = try self.sequence();
                self.skip();
                const separator = self.peek();
                if (separator != ',' and separator != ':') return self.syntax();
                self.pos += 1;
                const b = try self.sequence();
                self.skip();
                if (self.peek() != ']') return self.syntax();
                self.pos += 1;
                var nested: std.ArrayList(Move) = .empty;
                try nested.appendSlice(self.gpa, a);
                try nested.appendSlice(self.gpa, b);
                try nested.appendSlice(self.gpa, try inverse(self.gpa, a));
                if (separator == ',') try nested.appendSlice(self.gpa, try inverse(self.gpa, b));
                part = try self.power(nested.items);
            } else if (current == '{') {
                self.pos += 1;
                const start = self.pos;
                while (self.peek() >= 'a' and self.peek() <= 'z') self.pos += 1;
                const name = self.line[start..self.pos];
                if (name.len == 0 or self.peek() != '}') return self.syntax();
                const nested = self.macros.get(name) orelse return bad(self.gpa, "undefined {s}", .{name});
                self.pos += 1;
                part = try self.power(nested);
            } else return result.items;
            try result.appendSlice(self.gpa, part);
        }
    }
    fn whole(self: *Parser) Error![]Move {
        const result = try self.sequence();
        self.skip();
        if (self.peek() != 0) return self.syntax();
        if (result.len > 500) return bad(self.gpa, "too long", .{});
        return result;
    }
};
fn nameWord(word: Text) bool {
    if (word.len == 0 or word.len > 8) return false;
    for (word) |c| if (c < 'a' or c > 'z') return false;
    return true;
}
fn numberWord(word: Text) bool {
    if (word.len == 0 or word.len > 10 or (word.len > 1 and word[0] == '0')) return false;
    for (word) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}
fn number(word: Text) u64 {
    return std.fmt.parseInt(u64, word, 10) catch unreachable;
}
const command_names = [_]Text{ "RESET", "SHOW", "STATE", "ISSOLVED", "HISTORY", "SOLUTION", "ANALYZE", "STAGE", "MACROS", "CHECK", "LOAD", "UNDO", "REDO", "SEARCH", "WHERE", "SAVE", "RESTORE", "SCRAMBLE", "APPLY", "INVERT", "SIMPLIFY", "METRICS", "ORDER", "CYCLES", "UNROTATE", "UNTIL", "DEFINE", "MIRROR", "ROTATE" };
const Command = enum { reset, show, state, issolved, history, solution, analyze, stage, macros, check, load, undo, redo, search, where, save, restore, scramble, apply, invert, simplify, metrics, order, cycles, unrotate, until, define, mirror, rotate };
const Simulator = struct {
    gpa: Allocator,
    model: *const Model,
    cube: State,
    out: Builder,
    history: std.ArrayList(Move) = .empty,
    redo: std.ArrayList(Move) = .empty,
    macros: Macros = .empty,
    saves: std.StringHashMapUnmanaged(Saved) = .empty,
    fn record(self: *Simulator, moves: []const Move) Error!void {
        self.cube = self.model.apply(self.cube, moves);
        try self.history.appendSlice(self.gpa, moves);
        self.redo = .empty;
    }
    fn command(self: *Simulator, line: Text) Error!void {
        const gpa = self.gpa;
        const at = std.mem.findScalar(u8, line, ' ');
        const name = if (at) |i| line[0..i] else line;
        const arguments = if (at) |i| line[i + 1 ..] else "";
        var found: ?Command = null;
        for (command_names, 0..) |candidate, i| if (equal(candidate, name)) {
            found = @fromBackingInt(@intCast(i));
            break;
        };
        const cmd = found orelse return bad(gpa, "unknown command {s}", .{name});
        const no_arguments = @backingInt(cmd) <= @backingInt(Command.macros);
        const word_command = @backingInt(cmd) >= @backingInt(Command.check) and @backingInt(cmd) <= @backingInt(Command.scramble);
        const sequence_command = @backingInt(cmd) >= @backingInt(Command.apply) and @backingInt(cmd) <= @backingInt(Command.until);
        const head_command = @backingInt(cmd) >= @backingInt(Command.define);
        const words: []const Text = if (arguments.len == 0) &.{} else try split(gpa, arguments, ' ');
        const count: usize = if (cmd == .scramble) 2 else 1;
        var invalid = (no_arguments and at != null) or (word_command and words.len != count) or (head_command and at == null);
        if (!invalid and word_command) {
            if (cmd == .undo or cmd == .redo or cmd == .search or cmd == .scramble) {
                for (words) |word| if (!numberWord(word)) {
                    invalid = true;
                };
            }
            if ((cmd == .save or cmd == .restore) and !nameWord(words[0])) invalid = true;
        }
        var head: Text = "";
        var seq_start = name.len + 1;
        if (!invalid and head_command) {
            head = words[0];
            seq_start = name.len + head.len + 2;
            invalid = switch (cmd) {
                .define => !nameWord(head),
                .mirror => !contains(&.{ "LR", "UD", "FB" }, head),
                .rotate => !contains(&.{ "x", "x2", "x'", "y", "y2", "y'", "z", "z2", "z'" }, head),
                else => unreachable,
            };
        }
        if (invalid) return bad(gpa, "bad arguments", .{});
        var moves: []const Move = &.{};
        if (sequence_command or head_command) {
            var parser: Parser = .{ .gpa = gpa, .line = line, .pos = seq_start, .macros = &self.macros };
            moves = try parser.whole();
        }
        if (((cmd == .undo or cmd == .redo) and number(words[0]) < 1) or (cmd == .search and number(words[0]) > 4) or (cmd == .scramble and (number(words[0]) < 1 or number(words[0]) > 50 or number(words[1]) < 1 or number(words[1]) > 2147483646))) return bad(gpa, "bad value", .{});
        if (cmd == .where and !contains(corner_group.names, words[0]) and !contains(edge_group.names, words[0])) return bad(gpa, "unknown piece {s}", .{words[0]});
        switch (cmd) {
            .reset => {
                self.cube = self.model.solved;
                self.history = .empty;
                self.redo = .empty;
                try self.out.add("reset\n");
            },
            .show => {
                for (0..9) |row| {
                    var cells: Builder = .{ .gpa = gpa };
                    var first = true;
                    if (row < 3 or row >= 6) {
                        try cells.add("      ");
                        const face: usize = if (row < 3) 0 else 3;
                        const r = if (row < 3) row else row - 6;
                        for (0..3) |column| {
                            if (!first) try cells.byte(' ');
                            first = false;
                            try cells.byte(self.cube[face * 9 + r * 3 + column]);
                        }
                    } else {
                        for ([_]usize{ 4, 2, 1, 5 }) |face| for (0..3) |column| {
                            if (!first) try cells.byte(' ');
                            first = false;
                            try cells.byte(self.cube[face * 9 + (row - 3) * 3 + column]);
                        };
                    }
                    try self.out.line("{s}", .{cells.result()});
                }
            },
            .state => try self.out.line("state {s}", .{&self.cube}),
            .issolved => {
                const n = misplaced(self.cube);
                if (n == 0) try self.out.add("solved\n") else try self.out.line("unsolved {d}", .{n});
            },
            .history => try self.out.line("history {s}", .{try sequenceText(gpa, self.history.items)}),
            .solution => try self.out.line("solution {s}", .{try sequenceText(gpa, try simplify(gpa, try inverse(gpa, self.history.items)))}),
            .analyze, .stage, .where => {
                const normalized = self.model.normalize(self.cube).?;
                const cube = normalized.cube;
                if (cmd == .analyze) {
                    const rotation = self.model.rotations[normalized.rotation].moves;
                    try self.out.line("rotation {s}", .{if (rotation.len == 0) "none" else try movesText(gpa, rotation)});
                    try self.out.line("corners {s}", .{try cycles(gpa, cube, corner_group)});
                    try self.out.line("edges {s}", .{try cycles(gpa, cube, edge_group)});
                } else if (cmd == .where) {
                    const group = if (contains(corner_group.names, words[0])) corner_group else edge_group;
                    const pieces = identify(cube, group);
                    for (pieces.values[0..pieces.count], 0..) |piece, position| {
                        if (equal(group.names[piece.id.?], words[0])) {
                            try self.out.line("{s} at {s} {s} {d}", .{ words[0], group.names[position], if (group.names.len == 8) "twist" else "flip", piece.orientation });
                            break;
                        }
                    }
                } else {
                    const c = identify(cube, corner_group);
                    const e = identify(cube, edge_group);
                    var cross: usize = 0;
                    var slots: usize = 0;
                    var top: usize = 0;
                    for (4..8) |i| {
                        if (e.values[i].id.? == i and e.values[i].orientation == 0) cross += 1;
                        if (c.values[i].id.? == i and c.values[i].orientation == 0 and e.values[i + 4].id.? == i + 4 and e.values[i + 4].orientation == 0) slots += 1;
                    }
                    for (cube[0..9]) |color| if (color == 'W') {
                        top += 1;
                    };
                    const stage: Text = if (misplaced(cube) == 0) "solved" else if (cross == 4 and slots == 4 and top == 9) "oll" else if (cross == 4 and slots == 4) "f2l" else if (cross == 4) "cross" else "none";
                    try self.out.line("stage {s} cross {d} slots {d} top {d}", .{ stage, cross, slots, top });
                }
            },
            .macros => {
                var names: std.ArrayList(Text) = .empty;
                var iterator = self.macros.keyIterator();
                while (iterator.next()) |name_ptr| try names.append(gpa, name_ptr.*);
                std.mem.sort(Text, names.items, {}, textLess);
                try self.out.line("macros {d}", .{names.items.len});
                for (names.items) |macro_name| try self.out.line("macro {s} {s}", .{ macro_name, try sequenceText(gpa, self.macros.get(macro_name).?) });
            },
            .check, .load => {
                const invalidity = try self.model.check(words[0]);
                if (cmd == .check) {
                    if (invalidity) |text| try self.out.line("invalid {s}", .{text}) else try self.out.add("valid\n");
                } else {
                    if (invalidity) |text| return bad(gpa, "invalid {s}", .{text});
                    @memcpy(&self.cube, words[0]);
                    self.history = .empty;
                    self.redo = .empty;
                    try self.out.add("loaded\n");
                }
            },
            .undo, .redo => {
                const source = if (cmd == .undo) &self.history else &self.redo;
                if (source.items.len == 0) return bad(gpa, "nothing to {s}", .{if (cmd == .undo) "undo" else "redo"});
                const n: usize = @intCast(@min(number(words[0]), source.items.len));
                for (0..n) |_| {
                    const move = source.items[source.items.len - 1];
                    source.items.len -= 1;
                    if (cmd == .undo) {
                        self.cube = permute(self.cube, self.model.table(.{ .letter = move.letter, .amount = 4 - move.amount }));
                        try self.redo.append(gpa, move);
                    } else {
                        self.cube = permute(self.cube, self.model.table(move));
                        try self.history.append(gpa, move);
                    }
                }
                try self.out.line("{s} {d}", .{ if (cmd == .undo) "undone" else "redone", n });
            },
            .search => {
                const limit: usize = @intCast(number(words[0]));
                for (0..limit + 1) |depth| {
                    if (try self.model.search(self.cube, depth, 0)) |solution| {
                        try self.out.line("found {s}", .{try sequenceText(gpa, solution)});
                        return;
                    }
                }
                try self.out.add("not found\n");
            },
            .save => {
                try self.saves.put(gpa, words[0], .{ .cube = self.cube, .history = try gpa.dupe(Move, self.history.items) });
                try self.out.line("saved {s}", .{words[0]});
            },
            .restore => {
                const save = self.saves.get(words[0]) orelse return bad(gpa, "no save {s}", .{words[0]});
                self.cube = save.cube;
                self.history = .empty;
                try self.history.appendSlice(gpa, save.history);
                self.redo = .empty;
                try self.out.line("restored {s}", .{words[0]});
            },
            .scramble => {
                var scramble: std.ArrayList(Move) = .empty;
                var seed = number(words[1]);
                const n: usize = @intCast(number(words[0]));
                for (0..n) |i| {
                    var usable: std.ArrayList(u8) = .empty;
                    for (faces) |face| {
                        if (i > 0 and face == scramble.items[i - 1].letter) continue;
                        if (i > 1 and turn(scramble.items[i - 1].letter).axis == turn(scramble.items[i - 2].letter).axis and turn(face).axis == turn(scramble.items[i - 1].letter).axis) continue;
                        try usable.append(gpa, face);
                    }
                    seed = 48271 * seed % 2147483647;
                    const face = usable.items[@intCast(seed % usable.items.len)];
                    seed = 48271 * seed % 2147483647;
                    const amounts = [_]u8{ 1, 3, 2 };
                    try scramble.append(gpa, .{ .letter = face, .amount = amounts[@intCast(seed % 3)] });
                }
                try self.record(scramble.items);
                try self.out.line("scramble {s}", .{try movesText(gpa, scramble.items)});
            },
            .apply => {
                try self.record(moves);
                try self.out.line("applied {d}", .{moves.len});
            },
            .invert => try self.out.line("inverse {s}", .{try sequenceText(gpa, try inverse(gpa, moves))}),
            .simplify => try self.out.line("simplified {s}", .{try sequenceText(gpa, try simplify(gpa, moves))}),
            .metrics => {
                var htm: usize = 0;
                var qtm: usize = 0;
                var stm: usize = 0;
                for (moves) |move| {
                    if (std.mem.findScalar(u8, "xyz", move.letter) != null) continue;
                    const h: usize = if (std.mem.findScalar(u8, "MES", move.letter) != null) 2 else 1;
                    const q: usize = if (move.amount == 2) 2 else 1;
                    htm += h;
                    qtm += h * q;
                    stm += 1;
                }
                try self.out.line("metrics htm {d} qtm {d} stm {d} etm {d}", .{ htm, qtm, stm, moves.len });
            },
            .order => try self.out.line("order {d}", .{order(self.model.effect(moves))}),
            .cycles => {
                const cube = self.model.apply(self.model.solved, moves);
                try self.out.line("corners {s}", .{try cycles(gpa, cube, corner_group)});
                try self.out.line("edges {s}", .{try cycles(gpa, cube, edge_group)});
                try self.out.line("centers {s}", .{try cycles(gpa, cube, center_group)});
            },
            .unrotate => try self.out.line("unrotated {s}", .{try sequenceText(gpa, try self.model.unrotate(moves))}),
            .until => {
                const p = self.model.effect(moves);
                const limit = order(p);
                var cube = self.cube;
                var k: u64 = 1;
                while (k <= limit) : (k += 1) {
                    cube = permute(cube, p);
                    if (misplaced(cube) == 0) {
                        try self.out.line("until {d}", .{k});
                        return;
                    }
                }
                try self.out.add("until never\n");
            },
            .define => {
                try self.macros.put(gpa, head, try gpa.dupe(Move, moves));
                try self.out.line("defined {s} {d}", .{ head, moves.len });
            },
            .mirror => {
                const axis: usize = if (equal(head, "LR")) 0 else if (equal(head, "UD")) 1 else 2;
                const mirrored = try gpa.dupe(Move, moves);
                for (mirrored) |*move| {
                    const opposite: ?u8 = switch (move.letter) {
                        'R' => 'L',
                        'L' => 'R',
                        'U' => 'D',
                        'D' => 'U',
                        'F' => 'B',
                        'B' => 'F',
                        'r' => 'l',
                        'l' => 'r',
                        'u' => 'd',
                        'd' => 'u',
                        'f' => 'b',
                        'b' => 'f',
                        else => null,
                    };
                    if (turn(move.letter).axis != axis) move.amount = 4 - move.amount else if (opposite) |letter| {
                        move.letter = letter;
                        move.amount = 4 - move.amount;
                    }
                }
                try self.out.line("mirror {s}", .{try sequenceText(gpa, mirrored)});
            },
            .rotate => {
                const rotation = self.model.effect(try literalMoves(gpa, head));
                const rotated = try gpa.alloc(Move, moves.len);
                for (moves, 0..) |move, i| rotated[i] = self.model.conjugate(rotation, move);
                try self.out.line("rotated {s}", .{try sequenceText(gpa, rotated)});
            },
        }
    }
};
fn textLess(_: void, a: Text, b: Text) bool {
    return std.mem.order(u8, a, b) == .lt;
}
pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    const lines = try split(gpa, text, '\n');
    var model: Model = .{ .gpa = gpa };
    try model.init();
    var simulator: Simulator = .{ .gpa = gpa, .model = &model, .cube = model.solved, .out = .{ .gpa = gpa } };
    const count = std.fmt.parseInt(usize, lines[0], 10) catch unreachable;
    for (lines[1 .. count + 1]) |line| {
        simulator.command(line) catch |err| {
            if (err != error.Invalid) return err;
            try simulator.out.line("error: {s}", .{reason});
        };
    }
    try output.interface.writeAll(simulator.out.result());
    try output.interface.flush();
}
