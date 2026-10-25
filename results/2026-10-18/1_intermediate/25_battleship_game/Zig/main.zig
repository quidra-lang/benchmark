const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = error{BadCommand} || Allocator.Error || Writer.Error;
const ship_names = [_][]const u8{ "CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER" };
const ship_lengths = [_]usize{ 5, 4, 3, 3, 2 };
const ship_symbols = "CBRSD";
const Phase = enum { setup, battle, over };
const Strategy = enum { HUNT, PROB, RANDOM };
const ViewKind = enum { reef, unattacked, miss, hit, sunk };
const LogMode = enum { normal, match, silent };
const Command = enum {
    NEW, PLACE, REMOVE, AUTOPLACE, LAYOUT, REEF, SALVO, CHAIN, TOUCH,
    FIRE, AI, TORPEDO, SONAR, RESIGN, CONTROL, SEED,
    HINT, DENSITY, SHOW, RADAR, EXPORT, FLEET, STATUS, STATS, MATCH, SERIES, TOURNEY,
    fn setupOnly(command: Command) bool {
        return switch (command) { .PLACE, .REMOVE, .AUTOPLACE, .LAYOUT, .REEF, .SALVO, .CHAIN, .TOUCH => true, else => false };
    }
    fn isTurn(command: Command) bool {
        return switch (command) { .FIRE, .AI, .TORPEDO, .SONAR => true, else => false };
    }
};

fn number(text: []const u8) u64 { return std.fmt.parseInt(u64, text, 10) catch unreachable; }
fn playerIndex(text: []const u8) usize { return @intCast(number(text) - 1); }
fn advance(state: u64) u64 { return 48271 * state % 2147483647; }
fn strategy(text: []const u8) Strategy { return std.meta.stringToEnum(Strategy, text).?; }
fn shipIndex(text: []const u8) usize {
    for (ship_names, 0..) |name, ship| if (std.mem.eql(u8, name, text)) return ship;
    unreachable;
}
fn switchName(enabled: bool) []const u8 { return if (enabled) "ON" else "OFF"; }
fn rowName(row: usize) u8 { return 'A' + @as(u8, @intCast(row)); }
fn parseCell(text: []const u8) usize { return @as(usize, text[0] - 'A') * 10 + @as(usize, @intCast(number(text[1..]))) - 1; }
fn step(cell: usize, dr: i32, dc: i32) ?usize {
    const row = @as(i32, @intCast(cell / 10)) + dr;
    const column = @as(i32, @intCast(cell % 10)) + dc;
    if (row < 0 or row >= 10 or column < 0 or column >= 10) return null;
    return @intCast(row * 10 + column);
}
fn touching(a: usize, b: usize) bool {
    return @max(a / 10, b / 10) - @min(a / 10, b / 10) <= 1 and @max(a % 10, b % 10) - @min(a % 10, b % 10) <= 1;
}
fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void { try out.print(fmt ++ "\n", args); }

const Position = struct {
    cell: usize,
    pub fn format(value: Position, out: *Writer) Writer.Error!void { try out.print("{c}{d}", .{ rowName(value.cell / 10), value.cell % 10 + 1 }); }
};
fn coordinate(cell: usize) Position { return .{ .cell = cell }; }
const Range = struct {
    first: usize,
    last: usize,
    pub fn format(value: Range, out: *Writer) Writer.Error!void { try out.print("{f}-{f}", .{ coordinate(value.first), coordinate(value.last) }); }
};
const OptionalNumber = struct {
    value: ?u64,
    pub fn format(value: OptionalNumber, out: *Writer) Writer.Error!void {
        if (value.value) |n| try out.print("{d}", .{n}) else try out.writeAll("-");
    }
};
const Placement = struct {
    cells: [5]usize = @splat(0),
    len: usize = 0,
    fn range(placement: Placement) Range { return .{ .first = placement.cells[0], .last = placement.cells[placement.len - 1] }; }
};
fn positions(start: usize, horizontal: bool, length: usize) ?Placement {
    if ((if (horizontal) start % 10 else start / 10) + length > 10) return null;
    var result: Placement = .{ .len = length };
    for (0..length) |i| result.cells[i] = start + i * (if (horizontal) @as(usize, 1) else 10);
    return result;
}
const Nearby = struct { cells: [8]usize = @splat(0), len: usize = 0 };
fn surroundings(cell: usize) Nearby {
    var result: Nearby = .{};
    for (0..3) |r| for (0..3) |c| {
        if (r == 1 and c == 1) continue;
        if (step(cell, @as(i32, @intCast(r)) - 1, @as(i32, @intCast(c)) - 1)) |neighbor| {
            result.cells[result.len] = neighbor;
            result.len += 1;
        }
    };
    return result;
}
const PlacementProblem = union(enum) {
    bounds,
    reef,
    overlap: usize,
    touch: usize,
    pub fn format(problem: PlacementProblem, out: *Writer) Writer.Error!void {
        switch (problem) {
            .bounds => try out.writeAll("out of bounds"),
            .reef => try out.writeAll("on reef"),
            .overlap => |ship| try out.print("overlaps {s}", .{ship_names[ship]}),
            .touch => |ship| try out.print("touches {s}", .{ship_names[ship]}),
        }
    }
};
const LayoutProblem = union(enum) {
    count: struct { ship: usize, count: usize },
    straight: usize,
    reef: usize,
    touch: struct { first: usize, second: usize },
    pub fn format(problem: LayoutProblem, out: *Writer) Writer.Error!void {
        switch (problem) {
            .count => |value| try out.print("{s} has {d} cells", .{ ship_names[value.ship], value.count }),
            .straight => |ship| try out.print("{s} not straight", .{ship_names[ship]}),
            .reef => |ship| try out.print("{s} on reef", .{ship_names[ship]}),
            .touch => |pair| try out.print("{s} touches {s}", .{ ship_names[pair.first], ship_names[pair.second] }),
        }
    }
};
const Shot = union(enum) {
    already,
    miss,
    hit,
    sunk: usize,
    fn isHit(shot: Shot) bool { return switch (shot) { .hit, .sunk => true, else => false }; }
    pub fn format(shot: Shot, out: *Writer) Writer.Error!void {
        switch (shot) {
            .already => try out.writeAll("ALREADY"),
            .miss => try out.writeAll("MISS"),
            .hit => try out.writeAll("HIT"),
            .sunk => |ship| try out.print("SUNK {s}", .{ship_names[ship]}),
        }
    }
};
const ChoiceInfo = union(enum) {
    line,
    stack,
    parity,
    number: usize,
    pub fn format(info: ChoiceInfo, out: *Writer) Writer.Error!void {
        switch (info) {
            .line => try out.writeAll("LINE"),
            .stack => try out.writeAll("STACK"),
            .parity => try out.writeAll("PARITY"),
            .number => |n| try out.print("{d}", .{n}),
        }
    }
};
const Choice = struct { cell: usize, info: ChoiceInfo };

const Player = struct {
    ships: [5]Placement = @splat(.{}),
    owner: [100]?usize = @splat(null),
    attacked: [100]bool = @splat(false),
    candidates: [68]usize = @splat(0),
    candidate_count: usize = 0,
    random: u64,
    controller: ?Strategy = null,
    torpedo_used: bool = false,
    sonar_used: bool = false,
    shots: u64 = 0,
    hits: u64 = 0,
    sinks: u64 = 0,
    turns: u64 = 0,
    streak: u64 = 0,
    best_streak: u64 = 0,
    wins: u64 = 0,
    fn sunk(player: *const Player, ship: usize) bool {
        const placement = &player.ships[ship];
        if (placement.len == 0) return false;
        for (placement.cells[0..placement.len]) |cell| if (!player.attacked[cell]) return false;
        return true;
    }
    fn placed(player: *const Player) usize {
        var count: usize = 0;
        for (player.ships) |ship| if (ship.len > 0) { count += 1; };
        return count;
    }
    fn afloat(player: *const Player) usize {
        var count: usize = 0;
        for (player.ships, 0..) |ship, i| if (ship.len > 0 and !player.sunk(i)) { count += 1; };
        return count;
    }
    fn setShip(player: *Player, ship: usize, placement: Placement) void {
        const old = player.ships[ship];
        for (old.cells[0..old.len]) |cell| player.owner[cell] = null;
        player.ships[ship] = placement;
        for (placement.cells[0..placement.len]) |cell| player.owner[cell] = ship;
    }
    fn clearFleet(player: *Player) void {
        player.ships = @splat(.{});
        player.owner = @splat(null);
    }
    fn record(player: *Player, shot: Shot) void {
        player.shots += 1;
        if (shot.isHit()) {
            player.hits += 1;
            player.streak += 1;
            player.best_streak = @max(player.best_streak, player.streak);
        } else player.streak = 0;
        switch (shot) { .sunk => player.sinks += 1, else => {} }
    }
};
const View = struct {
    cells: [100]ViewKind,
    excluded: [100]bool = @splat(false),
    remaining: [5]bool,
    fn candidate(view: *const View, cell: ?usize) bool {
        if (cell) |index| return view.cells[index] == .unattacked and !view.excluded[index];
        return false;
    }
    fn scores(view: *const View) [100]usize {
        var result: [100]usize = @splat(0);
        for (view.remaining, 0..) |remaining, ship| {
            if (!remaining) continue;
            for (0..100) |start| for ([_]bool{ true, false }) |horizontal| {
                const placement = positions(start, horizontal, ship_lengths[ship]) orelse continue;
                var possible = true;
                var hits: usize = 0;
                for (placement.cells[0..placement.len]) |cell| {
                    if (view.excluded[cell] or (view.cells[cell] != .unattacked and view.cells[cell] != .hit)) possible = false;
                    if (view.cells[cell] == .hit) hits += 1;
                }
                if (possible) for (placement.cells[0..placement.len]) |cell| { result[cell] += 1 + 10 * hits; };
            };
        }
        return result;
    }
    fn best(view: *const View, distribution: *const [100]usize) usize {
        var chosen: ?usize = null;
        for (view.cells, 0..) |kind, cell| if (kind == .unattacked and (chosen == null or distribution[cell] > distribution[chosen.?])) { chosen = cell; };
        return chosen.?;
    }
};

const Game = struct {
    players: [2]Player = .{ .{ .random = 1 }, .{ .random = 2 } },
    reefs: [100]bool = @splat(false),
    salvo: bool = false,
    chain: bool = false,
    touch: bool = false,
    phase: Phase = .setup,
    current: usize = 0,
    winner: usize = 0,
    fn allowance(game: *const Game, player: usize) usize { return if (game.salvo) game.players[player].afloat() else 1; }
    fn placementProblem(game: *const Game, player: usize, maybe_cells: ?Placement) ?PlacementProblem {
        const placement = maybe_cells orelse return .bounds;
        const cells = placement.cells[0..placement.len];
        for (cells) |cell| if (game.reefs[cell]) return .reef;
        var first: usize = 5;
        for (cells) |cell| if (game.players[player].owner[cell]) |ship| { first = @min(first, ship); };
        if (first < 5) return .{ .overlap = first };
        if (!game.touch) {
            for (cells) |cell| {
                const nearby = surroundings(cell);
                for (nearby.cells[0..nearby.len]) |neighbor| if (game.players[player].owner[neighbor]) |ship| { first = @min(first, ship); };
            }
            if (first < 5) return .{ .touch = first };
        }
        return null;
    }
    fn autoPlace(game: *Game, player: usize, seed: u64) u64 {
        const owner = &game.players[player];
        owner.random = seed;
        owner.clearFleet();
        var attempts: u64 = 0;
        for (ship_lengths, 0..) |length, ship| while (owner.ships[ship].len == 0) {
            attempts += 1;
            owner.random = advance(owner.random);
            const horizontal = owner.random % 2 == 0;
            owner.random = advance(owner.random);
            const k: usize = @intCast(owner.random % (10 * (11 - length)));
            const start = if (horizontal) k / (11 - length) * 10 + k % (11 - length) else k;
            const placement = positions(start, horizontal, length).?;
            if (game.placementProblem(player, placement) == null) owner.setShip(ship, placement);
        };
        return attempts;
    }
    fn layout(game: *Game, player: usize, text: []const u8) ?LayoutProblem {
        var placements: [5]Placement = @splat(.{});
        for (ship_symbols, 0..) |symbol, ship| {
            var count: usize = 0;
            var cell: usize = 0;
            for (text) |ch| {
                if (ch == '/') continue;
                if (ch == symbol) {
                    if (count < 5) placements[ship].cells[count] = cell;
                    count += 1;
                }
                cell += 1;
            }
            if (count != ship_lengths[ship]) return .{ .count = .{ .ship = ship, .count = count } };
            placements[ship].len = count;
            const cells = placements[ship].cells[0..count];
            var horizontal = true;
            var vertical = true;
            for (cells, 0..) |at, i| {
                horizontal = horizontal and at == cells[0] + i and at / 10 == cells[0] / 10;
                vertical = vertical and at == cells[0] + 10 * i;
            }
            if (!horizontal and !vertical) return .{ .straight = ship };
            for (cells) |at| if (game.reefs[at]) return .{ .reef = ship };
        }
        if (!game.touch) for (0..5) |first| {
            for (first + 1..5) |second| {
                for (placements[first].cells[0..placements[first].len]) |a| {
                    for (placements[second].cells[0..placements[second].len]) |b| if (touching(a, b)) return .{ .touch = .{ .first = first, .second = second } };
                }
            }
        };
        game.players[player].clearFleet();
        for (placements, 0..) |placement, ship| game.players[player].setShip(ship, placement);
        return null;
    }
    fn placedLines(game: *const Game, player: usize, out: *Writer) Writer.Error!void {
        for (game.players[player].ships, 0..) |ship, i| try line(out, "PLACED {d} {s} {f}", .{ player + 1, ship_names[i], ship.range() });
    }
    fn view(game: *const Game, player: usize) View {
        const opponent = &game.players[1 - player];
        var result: View = .{ .cells = undefined, .remaining = undefined };
        for (0..5) |ship| result.remaining[ship] = !opponent.sunk(ship);
        for (0..100) |cell| {
            result.cells[cell] = if (game.reefs[cell]) .reef else if (!opponent.attacked[cell]) .unattacked else if (opponent.owner[cell]) |ship|
                (if (result.remaining[ship]) .hit else .sunk) else .miss;
        }
        if (!game.touch) for (result.cells, 0..) |kind, cell| {
            if (kind != .sunk) continue;
            const nearby = surroundings(cell);
            for (nearby.cells[0..nearby.len]) |neighbor| result.excluded[neighbor] = true;
        };
        return result;
    }
    fn choose(game: *Game, player: usize, ai: Strategy, mutate: bool) Choice {
        const current_view = game.view(player);
        if (ai == .PROB) {
            const scores = current_view.scores();
            const cell = current_view.best(&scores);
            return .{ .cell = cell, .info = .{ .number = scores[cell] } };
        }
        if (ai == .RANDOM) {
            var candidates: [100]usize = undefined;
            var count: usize = 0;
            for (0..100) |cell| if (current_view.candidate(cell)) { candidates[count] = cell; count += 1; };
            const random = advance(game.players[player].random);
            if (mutate) game.players[player].random = random;
            return .{ .cell = candidates[@intCast(random % count)], .info = .{ .number = count } };
        }
        for (current_view.cells, 0..) |kind, cell| {
            if (kind != .hit) continue;
            for ([_][2]i32{ .{ 0, 1 }, .{ 1, 0 } }) |direction| {
                var front = step(cell, direction[0], direction[1]);
                if (front == null or current_view.cells[front.?] != .hit) continue;
                while (front != null and current_view.cells[front.?] == .hit) front = step(front.?, direction[0], direction[1]);
                const back = step(cell, -direction[0], -direction[1]);
                if (current_view.candidate(front)) return .{ .cell = front.?, .info = .line };
                if (current_view.candidate(back)) return .{ .cell = back.?, .info = .line };
            }
        }
        const owner = &game.players[player];
        var i = owner.candidate_count;
        while (i > 0) {
            i -= 1;
            if (current_view.candidate(owner.candidates[i])) return .{ .cell = owner.candidates[i], .info = .stack };
        }
        var shortest: usize = 5;
        for (current_view.remaining, ship_lengths) |remaining, length| if (remaining) { shortest = @min(shortest, length); };
        for (0..100) |cell| if (current_view.candidate(cell) and (cell / 10 + cell % 10) % shortest == 0) return .{ .cell = cell, .info = .parity };
        unreachable;
    }
    fn shoot(game: *Game, player: usize, cell: usize) Shot {
        const owner = &game.players[player];
        const opponent = &game.players[1 - player];
        var result: Shot = .already;
        if (!opponent.attacked[cell]) {
            opponent.attacked[cell] = true;
            if (opponent.owner[cell]) |ship| {
                result = if (opponent.sunk(ship)) .{ .sunk = ship } else .hit;
                if (result == .hit) for ([_][2]i32{ .{ 0, -1 }, .{ 1, 0 }, .{ 0, 1 }, .{ -1, 0 } }) |direction| {
                    if (step(cell, direction[0], direction[1])) |neighbor| {
                        owner.candidates[owner.candidate_count] = neighbor;
                        owner.candidate_count += 1;
                    }
                };
            } else result = .miss;
        }
        owner.record(result);
        return result;
    }
    fn finishTurn(game: *Game, player: usize, hit: bool, mode: LogMode, out: ?*Writer) Writer.Error!void {
        game.players[player].turns += 1;
        if (game.players[1 - player].afloat() == 0) {
            game.phase = .over;
            game.winner = player;
            game.players[player].wins += 1;
            if (mode == .normal) try line(out.?, "WINNER {d}", .{player + 1});
        } else game.current = if (game.chain and hit) player else 1 - player;
    }
    fn shootingTurn(game: *Game, player: usize, ai: ?Strategy, targets: []const usize, mode: LogMode, out: ?*Writer) Writer.Error!void {
        const count = game.allowance(player);
        game.phase = .battle;
        var hit = false;
        for (0..count) |i| {
            const cell = if (ai) |choice| game.choose(player, choice, true).cell else targets[i];
            const result = game.shoot(player, cell);
            hit = hit or result.isHit();
            if (mode == .normal) try line(out.?, "SHOT {d} {f} {f}", .{ player + 1, coordinate(cell), result });
            if (mode == .match) switch (result) {
                .sunk => |ship| try line(out.?, "SINK {d} {s} {d}", .{ player + 1, ship_names[ship], game.players[player].shots }),
                else => {},
            };
            if (game.players[1 - player].afloat() == 0) break;
        }
        try game.finishTurn(player, hit, mode, out);
    }
    fn torpedo(game: *Game, player: usize, row: usize, west: bool, out: *Writer) Writer.Error!void {
        game.phase = .battle;
        game.players[player].torpedo_used = true;
        const opponent = &game.players[1 - player];
        var shot: ?Shot = null;
        var target: usize = 0;
        var reef: ?usize = null;
        for (0..10) |i| {
            const cell = row * 10 + (if (west) i else 9 - i);
            if (game.reefs[cell]) { reef = cell; break; }
            if (opponent.owner[cell] != null) {
                target = cell;
                shot = game.shoot(player, cell);
                break;
            }
            opponent.attacked[cell] = true;
        }
        if (shot == null) game.players[player].record(.miss);
        try out.print("TORPEDO {d} {c} {s} ", .{ player + 1, rowName(row), if (west) "W" else "E" });
        if (shot) |result| try line(out, "{f} {f}", .{ result, coordinate(target) })
        else if (reef) |cell| try line(out, "REEF {f}", .{coordinate(cell)})
        else try out.writeAll("MISS\n");
        try game.finishTurn(player, if (shot) |result| result.isHit() else false, .normal, out);
    }
    fn sonar(game: *Game, player: usize, cell: usize, out: *Writer) Writer.Error!void {
        game.phase = .battle;
        game.players[player].sonar_used = true;
        const opponent = &game.players[1 - player];
        const nearby = surroundings(cell);
        var count: usize = @intFromBool(opponent.owner[cell] != null and !opponent.attacked[cell]);
        for (nearby.cells[0..nearby.len]) |at| if (opponent.owner[at] != null and !opponent.attacked[at]) { count += 1; };
        try line(out, "SONAR {d} {f} {d}", .{ player + 1, coordinate(cell), count });
        try game.finishTurn(player, false, .normal, out);
    }
    fn automatic(game: *Game, out: *Writer) Writer.Error!void {
        while (game.phase == .battle) {
            const player = game.current;
            const ai = game.players[player].controller orelse break;
            try game.shootingTurn(player, ai, &.{}, .normal, out);
        }
    }
    fn show(game: *const Game, player: usize, radar: bool, out: *Writer) Writer.Error!void {
        try line(out, "{s} {d}", .{ if (radar) "RADAR" else "BOARD", player + 1 });
        try out.writeAll("  1 2 3 4 5 6 7 8 9 10\n");
        const current_view = game.view(player);
        const owner = &game.players[player];
        for (0..10) |row| {
            try out.writeByte(rowName(row));
            for (0..10) |column| {
                const cell = row * 10 + column;
                const symbol: u8 = if (radar) switch (current_view.cells[cell]) { .reef => '~', .unattacked => '.', .miss => 'o', .hit => 'x', .sunk => '#' }
                    else if (game.reefs[cell]) '~' else if (owner.owner[cell]) |ship|
                    (if (owner.attacked[cell]) std.ascii.toLower(ship_symbols[ship]) else ship_symbols[ship]) else if (owner.attacked[cell]) 'o' else '.';
                try out.print(" {c}", .{symbol});
            }
            try out.writeByte('\n');
        }
    }
    fn density(game: *const Game, player: usize, out: *Writer) Writer.Error!void {
        const current_view = game.view(player);
        const scores = current_view.scores();
        try line(out, "DENSITY {d}", .{player + 1});
        try out.writeByte(' ');
        for (1..11) |column| try out.print("{d: >5}", .{column});
        try out.writeByte('\n');
        for (0..10) |row| {
            try out.writeByte(rowName(row));
            for (0..10) |column| {
                const cell = row * 10 + column;
                if (current_view.cells[cell] == .unattacked) try out.print("{d: >5}", .{scores[cell]})
                else try out.writeAll(if (current_view.cells[cell] == .reef) "    ~" else "    -");
            }
            try out.writeByte('\n');
        }
        const cell = current_view.best(&scores);
        try line(out, "BEST {f} {d}", .{ coordinate(cell), scores[cell] });
    }
    fn exportFleet(game: *const Game, player: usize, out: *Writer) Writer.Error!void {
        try out.print("EXPORT {d} ", .{player + 1});
        for (0..100) |cell| {
            if (cell > 0 and cell % 10 == 0) try out.writeByte('/');
            try out.writeByte(if (game.players[player].owner[cell]) |ship| ship_symbols[ship] else '.');
        }
        try out.writeByte('\n');
    }
    fn fleet(game: *const Game, player: usize, out: *Writer) Writer.Error!void {
        const owner = &game.players[player];
        try line(out, "FLEET {d} afloat {d}", .{ player + 1, owner.afloat() });
        for (owner.ships, 0..) |ship, i| {
            if (ship.len == 0) try line(out, "{s} unplaced", .{ship_names[i]}) else {
                var count: usize = 0;
                for (ship.cells[0..ship.len]) |cell| if (owner.attacked[cell]) { count += 1; };
                try line(out, "{s} {f} {d}/{d} {s}", .{ ship_names[i], ship.range(), count, ship_lengths[i], if (owner.sunk(i)) "SUNK" else "AFLOAT" });
            }
        }
    }
    fn status(game: *const Game, out: *Writer) Writer.Error!void {
        var reef_count: usize = 0;
        for (game.reefs) |reef| if (reef) { reef_count += 1; };
        const phase_name: []const u8 = switch (game.phase) { .setup => "SETUP", .battle => "BATTLE", .over => "OVER" };
        try out.print("STATUS {s} salvo {s} chain {s} touch {s} reefs {d}", .{ phase_name, switchName(game.salvo), switchName(game.chain), switchName(game.touch), reef_count });
        if (game.phase == .setup) try line(out, " placed {d} {d}", .{ game.players[0].placed(), game.players[1].placed() }) else {
            if (game.phase == .battle) try out.print(" turn {d} shots {d}", .{ game.current + 1, game.allowance(game.current) })
            else try out.print(" winner {d}", .{game.winner + 1});
            try line(out, " afloat {d} {d}", .{ game.players[0].afloat(), game.players[1].afloat() });
        }
    }
    fn stats(game: *const Game, out: *Writer) Writer.Error!void {
        for (game.players, 0..) |player, i| {
            try out.print("STATS {d} shots {d} hits {d} sunk {d} turns {d} streak {d} accuracy ", .{ i + 1, player.shots, player.hits, player.sinks, player.turns, player.best_streak });
            if (player.shots == 0) try out.writeAll("-") else try out.print("{d}%", .{player.hits * 100 / player.shots});
            try line(out, " wins {d}", .{player.wins});
        }
    }
    fn match(game: *const Game, first_seed: u64, second_seed: u64, first: Strategy, second: Strategy, sinks: ?*Writer) Writer.Error!Game {
        var result: Game = .{ .salvo = game.salvo, .chain = game.chain, .touch = game.touch, .reefs = game.reefs };
        _ = result.autoPlace(0, first_seed);
        _ = result.autoPlace(1, second_seed);
        result.phase = .battle;
        const strategies = [_]Strategy{ first, second };
        while (result.phase == .battle) try result.shootingTurn(result.current, strategies[result.current], &.{}, if (sinks == null) .silent else .match, sinks);
        return result;
    }
};

const Program = struct {
    game: Game = .{},
    scratch: Allocator,
    out: *Writer,
    error_message: []const u8 = "",
    fn fail(program: *Program, comptime fmt: []const u8, args: anytype) Error {
        program.error_message = std.fmt.allocPrint(program.scratch, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn execute(program: *Program, words: []const []const u8) Error!void {
        const command = std.meta.stringToEnum(Command, words[0]).?;
        const game = &program.game;
        const out = program.out;
        if (command == .NEW) {
            const wins = [_]u64{ game.players[0].wins, game.players[1].wins };
            game.* = .{};
            for (wins, 0..) |count, i| game.players[i].wins = count;
            return out.writeAll("NEW\n");
        }
        if (command.setupOnly()) {
            if (game.phase != .setup) return program.fail("setup closed", .{});
            if (command == .SALVO or command == .CHAIN or command == .TOUCH) {
                const enabled = std.mem.eql(u8, words[1], "ON");
                switch (command) { .SALVO => game.salvo = enabled, .CHAIN => game.chain = enabled, .TOUCH => game.touch = enabled, else => unreachable }
                return line(out, "{s} {s}", .{ words[0], switchName(enabled) });
            }
            if (command == .REEF) {
                const cell = parseCell(words[1]);
                if (game.reefs[cell]) return program.fail("reef exists at {f}", .{coordinate(cell)});
                for (game.players, 0..) |owner, player| if (owner.owner[cell]) |ship| return program.fail("{f} occupied by {d} {s}", .{ coordinate(cell), player + 1, ship_names[ship] });
                game.reefs[cell] = true;
                return line(out, "REEF {f}", .{coordinate(cell)});
            }
            const player = playerIndex(words[1]);
            if (command == .PLACE or command == .REMOVE) {
                const ship = shipIndex(words[2]);
                const owner = &game.players[player];
                if (command == .REMOVE) {
                    if (owner.ships[ship].len == 0) return program.fail("{s} not placed", .{ship_names[ship]});
                    owner.setShip(ship, .{});
                    return line(out, "REMOVED {d} {s}", .{ player + 1, ship_names[ship] });
                }
                if (owner.ships[ship].len > 0) return program.fail("{s} already placed", .{ship_names[ship]});
                const placement = positions(parseCell(words[3]), std.mem.eql(u8, words[4], "H"), ship_lengths[ship]);
                if (game.placementProblem(player, placement)) |problem| return program.fail("{f}", .{problem});
                owner.setShip(ship, placement.?);
                return line(out, "PLACED {d} {s} {f}", .{ player + 1, ship_names[ship], placement.?.range() });
            }
            if (command == .AUTOPLACE) {
                const attempts = game.autoPlace(player, number(words[2]));
                try line(out, "AUTOPLACE {d} attempts {d}", .{ player + 1, attempts });
            } else {
                if (game.layout(player, words[2])) |problem| return program.fail("{f}", .{problem});
                try line(out, "LAYOUT {d}", .{player + 1});
            }
            return game.placedLines(player, out);
        }
        if (command.isTurn()) {
            const player = playerIndex(words[1]);
            if (game.phase == .over) return program.fail("game over", .{});
            if (game.phase == .setup and (game.players[0].placed() != 5 or game.players[1].placed() != 5)) return program.fail("fleets not ready", .{});
            if (player != game.current) return program.fail("not your turn", .{});
            switch (command) {
                .FIRE => {
                    const count = words.len - 2;
                    if (count != game.allowance(player)) return program.fail("expected {d} shots", .{game.allowance(player)});
                    var targets: [5]usize = undefined;
                    for (words[2..], 0..) |word, i| {
                        const cell = parseCell(word);
                        if (game.reefs[cell]) return program.fail("reef at {f}", .{coordinate(cell)});
                        targets[i] = cell;
                    }
                    try game.shootingTurn(player, null, targets[0..count], .normal, out);
                },
                .AI => try game.shootingTurn(player, strategy(words[2]), &.{}, .normal, out),
                .TORPEDO => {
                    if (game.players[player].torpedo_used) return program.fail("torpedo used", .{});
                    try game.torpedo(player, words[2][0] - 'A', std.mem.eql(u8, words[3], "W"), out);
                },
                .SONAR => {
                    if (game.players[player].sonar_used) return program.fail("sonar used", .{});
                    try game.sonar(player, parseCell(words[2]), out);
                },
                else => unreachable,
            }
            return game.automatic(out);
        }
        switch (command) {
            .STATUS => return game.status(out),
            .STATS => return game.stats(out),
            .MATCH, .SERIES, .TOURNEY => return program.simulation(command, words),
            else => {},
        }
        const player = playerIndex(words[1]);
        switch (command) {
            .CONTROL => {
                game.players[player].controller = if (std.mem.eql(u8, words[2], "HUMAN")) null else strategy(words[2]);
                try line(out, "CONTROL {d} {s}", .{ player + 1, words[2] });
            },
            .SEED => {
                game.players[player].random = number(words[2]);
                try line(out, "SEED {d} {d}", .{ player + 1, game.players[player].random });
            },
            .RESIGN => {
                if (game.phase != .battle) return program.fail("not in battle", .{});
                game.phase = .over;
                game.winner = 1 - player;
                game.players[1 - player].wins += 1;
                try line(out, "RESIGN {d}\nWINNER {d}", .{ player + 1, 2 - player });
            },
            .HINT => {
                if (game.phase == .over) return program.fail("game over", .{});
                const choice = game.choose(player, strategy(words[2]), false);
                try line(out, "HINT {d} {s} {f} {f}", .{ player + 1, words[2], coordinate(choice.cell), choice.info });
            },
            .DENSITY => {
                if (game.phase == .over) return program.fail("game over", .{});
                try game.density(player, out);
            },
            .SHOW, .RADAR => try game.show(player, command == .RADAR, out),
            .EXPORT => try game.exportFleet(player, out),
            .FLEET => try game.fleet(player, out),
            else => unreachable,
        }
    }
    fn simulation(program: *Program, command: Command, words: []const []const u8) Error!void {
        const game = &program.game;
        const out = program.out;
        if (command == .MATCH) {
            try line(out, "MATCH 1 {s} 2 {s}", .{ words[3], words[4] });
            const result = try game.match(number(words[1]), number(words[2]), strategy(words[3]), strategy(words[4]), out);
            return line(out, "RESULT winner {d} shots {d} {d} hits {d} {d}", .{ result.winner + 1, result.players[0].shots, result.players[1].shots, result.players[0].hits, result.players[1].hits });
        }
        const count: usize = @intCast(number(words[1]));
        var random = number(words[2]);
        if (command == .SERIES) {
            var wins: [2]u64 = @splat(0);
            var shots: [2]u64 = @splat(0);
            var fastest: [2]?u64 = @splat(null);
            for (0..count) |_| {
                random = advance(random);
                const first = random;
                random = advance(random);
                const result = try game.match(first, random, strategy(words[3]), strategy(words[4]), null);
                wins[result.winner] += 1;
                for (0..2) |player| shots[player] += result.players[player].shots;
                const winning_shots = result.players[result.winner].shots;
                fastest[result.winner] = @min(fastest[result.winner] orelse winning_shots, winning_shots);
            }
            return line(out, "SERIES {d} wins {d} {d} shots {d} {d} fastest {f} {f}", .{ count, wins[0], wins[1], shots[0], shots[1], OptionalNumber{ .value = fastest[0] }, OptionalNumber{ .value = fastest[1] } });
        }
        var totals = [_]Total{ .{ .ai = .HUNT }, .{ .ai = .PROB }, .{ .ai = .RANDOM } };
        for (0..3) |first| for (0..3) |second| {
            if (first == second) continue;
            for (0..count) |_| {
                random = advance(random);
                const first_seed = random;
                random = advance(random);
                const result = try game.match(first_seed, random, @enumFromInt(first), @enumFromInt(second), null);
                totals[if (result.winner == 0) first else second].wins += 1;
                totals[first].shots += result.players[0].shots;
                totals[second].shots += result.players[1].shots;
            }
        };
        std.mem.sort(Total, &totals, {}, Total.before);
        try line(out, "TOURNEY {d}", .{count});
        for (totals, 1..) |total, rank| try line(out, "{d} {s} wins {d} shots {d}", .{ rank, @tagName(total.ai), total.wins, total.shots });
    }
};
const Total = struct {
    ai: Strategy,
    wins: u64 = 0,
    shots: u64 = 0,
    fn before(_: void, a: Total, b: Total) bool {
        if (a.wins != b.wins) return a.wins > b.wins;
        if (a.shots != b.shots) return a.shots < b.shots;
        return @intFromEnum(a.ai) < @intFromEnum(b.ai);
    }
};

fn readWords(gpa: Allocator, input: *std.Io.Reader) ![]const []const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    var words: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.tokenizeAny(u8, text, " \r");
    while (parts.next()) |word| try words.append(gpa, word);
    return try words.toOwnedSlice(gpa);
}

pub fn main(init: std.process.Init) !void {
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var program: Program = .{ .scratch = scratch.allocator(), .out = &output.interface };
    const count: usize = @intCast(number((try readWords(scratch.allocator(), &input.interface))[0]));
    for (0..count) |_| {
        _ = scratch.reset(.retain_capacity);
        const words = try readWords(scratch.allocator(), &input.interface);
        var response: Writer.Allocating = .init(scratch.allocator());
        defer response.deinit();
        program.out = &response.writer;
        program.execute(words) catch |err| {
            if (err != error.BadCommand) return err;
            try output.interface.print("ERROR {s}\n", .{program.error_message});
            continue;
        };
        try output.interface.writeAll(response.written());
    }
    try output.interface.flush();
}
