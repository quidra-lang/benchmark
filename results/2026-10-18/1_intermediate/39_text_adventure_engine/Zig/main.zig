const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const PlaceKind = enum { nowhere, room, player, inside };
const Place = struct {
    kind: PlaceKind = .nowhere,
    index: usize = 0,
    fn equal(a: Place, b: Place) bool {
        return a.kind == b.kind and a.index == b.index;
    }
};
const player: Place = .{ .kind = .player };
const ContainerState = enum { open, closed, locked };
const EndStatus = enum { none, won, dead };
const Direction = enum { north, south, east, west, up, down };
const directions = [_][]const u8{ "north", "south", "east", "west", "up", "down" };
const Verb = enum { go, look, examine, take, drop, put, inventory, open, close, unlock, lock, use, light, extinguish, wait, score, save, restore, verbose, brief };
const synonyms = [_][]const u8{
    "go walk run",     "look l",                 "examine x inspect read", "take get grab", "drop discard", "put insert place",
    "inventory inv i", "open",                   "close shut",             "unlock",        "lock",         "use apply",
    "light ignite",    "extinguish douse snuff", "wait z",                 "score",         "save",         "restore load",
    "verbose",         "brief",
};
const Exit = struct { destination: usize, key: ?usize = null, locked: bool = false };
const Effect = union(enum) {
    message: []const u8,
    open: struct { room: usize, direction: Direction, destination: usize },
    move: struct { item: usize, place: Place },
    flag: struct { index: usize, on: bool },
    points: i32,
};
const Rule = struct { flag: ?usize, when_on: bool, effect: Effect };
const UseRule = struct { first: usize, second: usize, rule: Rule };
const Room = struct {
    id: []const u8,
    name: []const u8 = "",
    dark: bool = false,
    descriptions: std.ArrayList([]const u8) = .empty,
    enter: std.ArrayList(Rule) = .empty,
};
const Item = struct {
    id: []const u8,
    name: []const u8 = "",
    weight: i32 = 0,
    treasure: ?i32 = null,
    capacity: ?i32 = null,
    key: ?usize = null,
    light: bool = false,
    fixed: bool = false,
    nouns: std.ArrayList([]const u8) = .empty,
    name_words: []const []const u8 = &.{},
    details: std.ArrayList([]const u8) = .empty,
};
const GameState = struct {
    room: usize = 0,
    bonus: i32 = 0,
    moves: i32 = 0,
    darkness: i32 = 0,
    end: EndStatus = .none,
    places: [200]Place = @splat(.{}),
    containers: [200]ContainerState = @splat(.open),
    fuel: [200]i32 = @splat(0),
    lit: [200]bool = @splat(false),
    visited: [200]bool = @splat(false),
    exits: [200][6]?Exit = @splat(@splat(null)),
    flags: [400]bool = @splat(false),
};
const Selection = struct {
    data: [200]usize = undefined,
    len: usize = 0,
    fn add(selection: *Selection, item: usize) void {
        selection.data[selection.len] = item;
        selection.len += 1;
    }
    fn slice(selection: *const Selection) []const usize {
        return selection.data[0..selection.len];
    }
};
const TreasureScore = struct { points: i32 = 0, stored: usize = 0, total: usize = 0 };

fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn contains(words: []const []const u8, word: []const u8) bool {
    for (words) |value| if (equal(word, value)) return true;
    return false;
}
fn integer(text: []const u8) i32 {
    return std.fmt.parseInt(i32, text, 10) catch unreachable;
}
fn directionOf(word: []const u8) ?Direction {
    for (directions, 0..) |name, index| if (equal(word, name) or equal(word, name[0..1])) return @fromBackingInt(@intCast(index));
    return null;
}
fn verbOf(word: []const u8) ?Verb {
    for (synonyms, 0..) |group, index| {
        var tokens = std.mem.tokenizeScalar(u8, group, ' ');
        while (tokens.next()) |alias| if (equal(alias, word)) return @fromBackingInt(@intCast(index));
    }
    return null;
}
fn all(phrase: []const []const u8) bool {
    return phrase.len == 1 and equal(phrase[0], "all");
}
fn line(out: *Writer, comptime format: []const u8, args: anytype) Writer.Error!void {
    try out.print(format ++ "\n", args);
}
fn splitWords(gpa: Allocator, text: []const u8) Allocator.Error![]const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var tokens = std.mem.tokenizeScalar(u8, text, ' ');
    while (tokens.next()) |word| try result.append(gpa, word);
    return result.toOwnedSlice(gpa);
}
fn normalized(gpa: Allocator, text: []const u8) Allocator.Error![]const []const u8 {
    const lower = try gpa.dupe(u8, text);
    for (lower) |*character| if (character.* >= 'A' and character.* <= 'Z') {
        character.* += 'a' - 'A';
    };
    var result: std.ArrayList([]const u8) = .empty;
    var tokens = std.mem.tokenizeScalar(u8, lower, ' ');
    while (tokens.next()) |word| {
        if (!equal(word, "the") and !equal(word, "a") and !equal(word, "an")) try result.append(gpa, word);
    }
    return result.toOwnedSlice(gpa);
}
fn joined(gpa: Allocator, words: []const []const u8) Error![]const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    for (words, 0..) |word, index| {
        if (index > 0) try buffer.writer.writeByte(' ');
        try buffer.writer.writeAll(word);
    }
    return buffer.toOwnedSlice();
}

const Adventure = struct {
    gpa: Allocator,
    rooms: std.ArrayList(Room) = .empty,
    items: std.ArrayList(Item) = .empty,
    flags: std.ArrayList([]const u8) = .empty,
    use_rules: std.ArrayList(UseRule) = .empty,
    trophy: usize = 0,
    max_weight: i32 = 0,
    state: GameState = .{},
    saved: ?GameState = null,
    pronoun: ?usize = null,
    previous: ?[]const u8 = null,
    verbose: bool = false,

    fn roomId(game: *const Adventure, id: []const u8) usize {
        for (game.rooms.items, 0..) |room, index| if (equal(room.id, id)) return index;
        unreachable;
    }
    fn itemId(game: *const Adventure, id: []const u8) usize {
        for (game.items.items, 0..) |item, index| if (equal(item.id, id)) return index;
        unreachable;
    }
    fn flagId(game: *Adventure, id: []const u8) Allocator.Error!usize {
        for (game.flags.items, 0..) |flag, index| if (equal(flag, id)) return index;
        const index = game.flags.items.len;
        try game.flags.append(game.gpa, id);
        return index;
    }
    fn parseRule(game: *Adventure, words: []const []const u8, start: usize) Error!Rule {
        var index = start;
        var flag: ?usize = null;
        var when_on = true;
        if (equal(words[index], "IF") or equal(words[index], "UNLESS")) {
            when_on = equal(words[index], "IF");
            flag = try game.flagId(words[index + 1]);
            index += 2;
        }
        const effect: Effect = if (equal(words[index], "MESSAGE"))
            .{ .message = try joined(game.gpa, words[index + 1 ..]) }
        else if (equal(words[index], "OPEN"))
            .{ .open = .{ .room = game.roomId(words[index + 1]), .direction = directionOf(words[index + 2]).?, .destination = game.roomId(words[index + 3]) } }
        else if (equal(words[index], "REMOVE"))
            .{ .move = .{ .item = game.itemId(words[index + 1]), .place = .{} } }
        else if (equal(words[index], "ADD"))
            .{ .move = .{ .item = game.itemId(words[index + 1]), .place = .{ .kind = .room, .index = game.roomId(words[index + 2]) } } }
        else if (equal(words[index], "SET") or equal(words[index], "CLEAR"))
            .{ .flag = .{ .index = try game.flagId(words[index + 1]), .on = equal(words[index], "SET") } }
        else
            .{ .points = integer(words[index + 1]) };
        return .{ .flag = flag, .when_on = when_on, .effect = effect };
    }
    fn lessItem(_: void, a: Item, b: Item) bool {
        return std.mem.order(u8, a.id, b.id) == .lt;
    }
    fn create(gpa: Allocator, definitions: []const []const u8) Error!*Adventure {
        const game = try gpa.create(Adventure);
        game.* = .{ .gpa = gpa };
        for (definitions) |text| {
            const words = try splitWords(gpa, text);
            if (equal(words[0], "ROOM")) try game.rooms.append(gpa, .{ .id = words[1] });
            if (equal(words[0], "ITEM")) try game.items.append(gpa, .{ .id = words[1] });
        }
        std.sort.heap(Item, game.items.items, {}, lessItem);
        for (definitions) |text| {
            const words = try splitWords(gpa, text);
            const kind = words[0];
            if (equal(kind, "ROOM")) {
                const room = &game.rooms.items[game.roomId(words[1])];
                room.dark = equal(words[2], "DARK");
                const start: usize = if (room.dark) 3 else 2;
                room.name = try joined(gpa, words[start..]);
            } else if (equal(kind, "DESC")) {
                try game.rooms.items[game.roomId(words[1])].descriptions.append(gpa, try joined(gpa, words[2..]));
            } else if (equal(kind, "EXIT")) {
                game.state.exits[game.roomId(words[1])][@backingInt(directionOf(words[2]).?)] = .{
                    .destination = game.roomId(words[3]),
                    .key = if (words.len > 4) game.itemId(words[5]) else null,
                    .locked = words.len > 4,
                };
            } else if (equal(kind, "ITEM")) {
                const x = game.itemId(words[1]);
                const item = &game.items.items[x];
                game.state.places[x] = if (equal(words[2], "PLAYER")) player else if (equal(words[2], "NOWHERE")) .{} else .{ .kind = .room, .index = game.roomId(words[2]) };
                item.weight = integer(words[3]);
                try item.nouns.append(gpa, words[1]);
                var index: usize = 4;
                if (equal(words[index], "TREASURE")) {
                    item.treasure = integer(words[index + 1]);
                    index += 2;
                }
                if (equal(words[index], "LIGHT")) {
                    item.light = true;
                    game.state.fuel[x] = integer(words[index + 1]);
                    index += 2;
                }
                if (equal(words[index], "CONTAINER")) {
                    item.capacity = integer(words[index + 1]);
                    index += 2;
                    if (equal(words[index], "CLOSED")) {
                        game.state.containers[x] = .closed;
                        index += 1;
                    }
                    if (equal(words[index], "LOCKED")) {
                        item.key = game.itemId(words[index + 1]);
                        game.state.containers[x] = .locked;
                        index += 2;
                    }
                }
                if (equal(words[index], "FIXED")) {
                    item.fixed = true;
                    index += 1;
                }
                item.name = try joined(gpa, words[index..]);
                item.name_words = words[index..];
            } else if (equal(kind, "INSIDE")) {
                game.state.places[game.itemId(words[1])] = .{ .kind = .inside, .index = game.itemId(words[2]) };
            } else if (equal(kind, "ALIAS")) {
                try game.items.items[game.itemId(words[1])].nouns.append(gpa, words[2]);
            } else if (equal(kind, "DETAIL")) {
                try game.items.items[game.itemId(words[1])].details.append(gpa, try joined(gpa, words[2..]));
            } else if (equal(kind, "RULE")) {
                try game.use_rules.append(gpa, .{ .first = game.itemId(words[1]), .second = game.itemId(words[2]), .rule = try game.parseRule(words, 3) });
            } else if (equal(kind, "ENTER")) {
                try game.rooms.items[game.roomId(words[1])].enter.append(gpa, try game.parseRule(words, 2));
            } else if (equal(kind, "TROPHY")) game.trophy = game.roomId(words[1]) else if (equal(kind, "START")) game.state.room = game.roomId(words[1]) else if (equal(kind, "MAXWEIGHT")) game.max_weight = integer(words[1]);
        }
        game.state.visited[game.state.room] = true;
        return game;
    }
    fn floor(game: *const Adventure) Place {
        return .{ .kind = .room, .index = game.state.room };
    }
    fn direct(game: *const Adventure, place: Place) Selection {
        var result: Selection = .{};
        for (0..game.items.items.len) |x| if (game.state.places[x].equal(place)) {
            result.add(x);
        };
        return result;
    }
    fn reachable(game: *const Adventure, x: usize, root: Place) bool {
        var place = game.state.places[x];
        while (true) {
            if (place.equal(root)) return true;
            if (place.kind != .inside or game.state.containers[place.index] != .open) return false;
            place = game.state.places[place.index];
        }
    }
    fn carried(game: *const Adventure, x: usize) bool {
        return game.reachable(x, player);
    }
    fn isLit(game: *const Adventure) bool {
        if (!game.rooms.items[game.state.room].dark) return true;
        for (0..game.items.items.len) |x| if (game.state.lit[x] and (game.carried(x) or game.reachable(x, game.floor()))) return true;
        return false;
    }
    fn visible(game: *const Adventure, x: usize, lit: bool) bool {
        return game.carried(x) or (lit and game.reachable(x, game.floor()));
    }
    fn contentWeight(game: *const Adventure, container: usize) i32 {
        var result: i32 = 0;
        for (0..game.items.items.len) |x| if (game.state.places[x].equal(.{ .kind = .inside, .index = container })) {
            result += game.totalWeight(x);
        };
        return result;
    }
    fn totalWeight(game: *const Adventure, x: usize) i32 {
        return game.items.items[x].weight + game.contentWeight(x);
    }
    fn carriedWeight(game: *const Adventure) i32 {
        var result: i32 = 0;
        for (0..game.items.items.len) |x| if (game.state.places[x].equal(player)) {
            result += game.totalWeight(x);
        };
        return result;
    }
    fn within(game: *const Adventure, item: usize, container: usize) bool {
        var place = game.state.places[item];
        while (place.kind == .inside) {
            if (place.index == container) return true;
            place = game.state.places[place.index];
        }
        return false;
    }
    fn treasures(game: *const Adventure) TreasureScore {
        var result: TreasureScore = .{};
        for (game.items.items, 0..) |item, x| if (item.treasure) |points| {
            result.total += 1;
            var place = game.state.places[x];
            while (place.kind == .inside) place = game.state.places[place.index];
            if (place.equal(.{ .kind = .room, .index = game.trophy })) {
                result.stored += 1;
                result.points += points;
            }
        };
        return result;
    }
    fn knownWord(game: *const Adventure, word: []const u8) bool {
        for (game.items.items) |item| if (contains(item.nouns.items, word) or contains(item.name_words, word)) return true;
        return false;
    }
};

const Names = struct {
    game: *const Adventure,
    selected: Selection,
    pub fn format(names: Names, out: *Writer) Writer.Error!void {
        for (names.selected.slice(), 0..) |x, index| {
            if (index > 0) try out.writeAll(", ");
            try out.writeAll(names.game.items.items[x].name);
        }
    }
};
const DisplayName = struct {
    game: *const Adventure,
    index: usize,
    pub fn format(display: DisplayName, out: *Writer) Writer.Error!void {
        const game = display.game;
        const x = display.index;
        try out.writeAll(game.items.items[x].name);
        const container = game.items.items[x].capacity != null;
        const lit = game.state.lit[x];
        if (container or lit) {
            try out.writeAll(" (");
            if (container) try out.writeAll(@tagName(game.state.containers[x]));
            if (lit) try out.writeAll(if (container) ", lit" else "lit");
            try out.writeByte(')');
        }
    }
};

const Session = struct {
    game: *Adventure,
    gpa: Allocator,
    out: *Writer,
    problem: []const u8 = "",

    fn fail(session: *Session, comptime format: []const u8, args: anytype) Error {
        session.problem = try std.fmt.allocPrint(session.gpa, format, args);
        return error.Invalid;
    }
    fn say(session: *Session, comptime format: []const u8, args: anytype) Error!void {
        try line(session.out, format, args);
    }
    fn itemTree(session: *Session, place: Place, depth: usize) Error!void {
        const game = session.game;
        const children = game.direct(place);
        for (children.slice()) |x| {
            try session.out.splatByteAll(' ', depth * 2);
            try session.say("{f}", .{DisplayName{ .game = game, .index = x }});
            if (game.items.items[x].capacity != null and game.state.containers[x] == .open)
                try session.itemTree(.{ .kind = .inside, .index = x }, depth + 1);
        }
    }
    fn describe(session: *Session, full: bool) Error!void {
        const game = session.game;
        if (!game.isLit()) return session.say("It is pitch dark.", .{});
        const room = &game.rooms.items[game.state.room];
        try session.say("{s}", .{room.name});
        if (full) for (room.descriptions.items) |text| {
            try session.say("{s}", .{text});
        };
        try session.out.writeAll("Exits: ");
        var first = true;
        for (game.state.exits[game.state.room], 0..) |possible, d| if (possible) |exit| {
            if (!first) try session.out.writeAll(", ");
            first = false;
            try session.out.writeAll(directions[d]);
            if (exit.locked) try session.out.writeAll(" (locked)");
        };
        if (first) try session.out.writeAll("none");
        try session.out.writeByte('\n');
        if (game.direct(game.floor()).len > 0) {
            try session.say("You see:", .{});
            try session.itemTree(game.floor(), 1);
        }
    }
    fn resolve(session: *Session, phrase: []const []const u8) Error!usize {
        const game = session.game;
        const lit = game.isLit();
        if (phrase.len == 1 and equal(phrase[0], "it")) {
            const x = game.pronoun orelse return session.fail("I don't know what \"it\" refers to.", .{});
            if (!game.visible(x, lit)) return session.fail("You can't see any such thing.", .{});
            return x;
        }
        for (phrase) |word| if (!game.knownWord(word)) return session.fail("I don't know the word \"{s}\".", .{word});
        var matches: Selection = .{};
        for (game.items.items, 0..) |item, x| {
            if (!game.visible(x, lit) or !contains(item.nouns.items, phrase[phrase.len - 1])) continue;
            var match = true;
            for (phrase[0 .. phrase.len - 1]) |word| if (!contains(item.name_words, word)) {
                match = false;
                break;
            };
            if (match) matches.add(x);
        }
        if (matches.len == 0) return session.fail("You can't see any such thing.", .{});
        if (matches.len > 1) return session.fail("Which do you mean: {f}?", .{Names{ .game = game, .selected = matches }});
        game.pronoun = matches.data[0];
        return matches.data[0];
    }
    fn examine(session: *Session, x: usize) Error!void {
        const game = session.game;
        const item = &game.items.items[x];
        if (item.details.items.len == 0) try session.say("You see nothing special about the {s}.", .{item.name}) else for (item.details.items) |text| {
            try session.say("{s}", .{text});
        }
        if (item.light) try session.say("It is {s} (fuel {d}).", .{ if (game.state.lit[x]) "lit" else "unlit", game.state.fuel[x] });
        if (item.capacity != null) switch (game.state.containers[x]) {
            .locked => try session.say("It is locked.", .{}),
            .closed => try session.say("It is closed.", .{}),
            .open => {
                const place: Place = .{ .kind = .inside, .index = x };
                if (game.direct(place).len == 0) try session.say("It is empty.", .{}) else {
                    try session.say("It contains:", .{});
                    try session.itemTree(place, 1);
                }
            },
        };
        if (item.treasure) |points| try session.say("It is a treasure worth {d} points.", .{points});
        try session.say("It weighs {d}.", .{game.totalWeight(x)});
    }
    fn requireContainer(session: *Session, x: usize) Error!void {
        if (session.game.items.items[x].capacity == null) return session.fail("The {s} is not a container.", .{session.game.items.items[x].name});
        if (session.game.state.containers[x] != .open) return session.fail("The {s} is closed.", .{session.game.items.items[x].name});
    }
    fn take(session: *Session, target: []const []const u8, from: ?[]const []const u8) Error!bool {
        const game = session.game;
        if (!game.isLit()) return session.fail("It is pitch dark.", .{});
        var container: ?usize = null;
        var source = game.floor();
        if (from) |phrase| {
            const c = try session.resolve(phrase);
            try session.requireContainer(c);
            container = c;
            source = .{ .kind = .inside, .index = c };
        }
        if (all(target)) {
            var candidates: Selection = .{};
            const direct = game.direct(source);
            for (direct.slice()) |x| if (!game.items.items[x].fixed) {
                candidates.add(x);
            };
            if (candidates.len == 0) {
                if (container) |c| return session.fail("There is nothing in the {s} to take.", .{game.items.items[c].name});
                return session.fail("There is nothing here to take.", .{});
            }
            var taken = false;
            for (candidates.slice()) |x| {
                if (!game.carried(x) and game.carriedWeight() + game.totalWeight(x) > game.max_weight)
                    try session.say("{s}: You can't carry any more.", .{game.items.items[x].name})
                else {
                    game.state.places[x] = player;
                    taken = true;
                    try session.say("{s}: Taken.", .{game.items.items[x].name});
                }
            }
            return taken;
        }
        const x = try session.resolve(target);
        if (container) |c| if (!game.state.places[x].equal(source)) {
            return session.fail("The {s} is not in the {s}.", .{ game.items.items[x].name, game.items.items[c].name });
        };
        if (game.state.places[x].equal(player)) return session.fail("You already have the {s}.", .{game.items.items[x].name});
        if (game.items.items[x].fixed) return session.fail("The {s} is fixed in place.", .{game.items.items[x].name});
        if (!game.carried(x) and game.carriedWeight() + game.totalWeight(x) > game.max_weight) return session.fail("You can't carry any more.", .{});
        game.state.places[x] = player;
        try session.say("Taken.", .{});
        return true;
    }
    fn drop(session: *Session, target: []const []const u8) Error!void {
        const game = session.game;
        if (all(target)) {
            const direct = game.direct(player);
            if (direct.len == 0) return session.fail("You are empty-handed.", .{});
            for (direct.slice()) |x| {
                game.state.places[x] = game.floor();
                try session.say("{s}: Dropped.", .{game.items.items[x].name});
            }
            return;
        }
        const x = try session.resolve(target);
        if (!game.carried(x)) return session.fail("You aren't carrying the {s}.", .{game.items.items[x].name});
        game.state.places[x] = game.floor();
        try session.say("Dropped.", .{});
    }
    fn putItem(session: *Session, x: usize, y: usize) Error!?[]const u8 {
        const game = session.game;
        const xn = game.items.items[x].name;
        const yn = game.items.items[y].name;
        if (game.within(y, x)) return try std.fmt.allocPrint(session.gpa, "The {s} is inside the {s}.", .{ yn, xn });
        if (game.state.places[x].equal(.{ .kind = .inside, .index = y })) return try std.fmt.allocPrint(session.gpa, "The {s} is already in the {s}.", .{ xn, yn });
        const weight = game.contentWeight(y) + (if (game.within(x, y)) @as(i32, 0) else game.totalWeight(x));
        if (weight > game.items.items[y].capacity.?) return try std.fmt.allocPrint(session.gpa, "The {s} doesn't fit in the {s}.", .{ xn, yn });
        game.state.places[x] = .{ .kind = .inside, .index = y };
        return null;
    }
    fn put(session: *Session, first: []const []const u8, second: []const []const u8) Error!bool {
        const game = session.game;
        if (all(first)) {
            const y = try session.resolve(second);
            try session.requireContainer(y);
            const direct = game.direct(player);
            var candidates: Selection = .{};
            for (direct.slice()) |x| if (x != y) {
                candidates.add(x);
            };
            if (candidates.len == 0) return session.fail("You have nothing to put in the {s}.", .{game.items.items[y].name});
            var moved = false;
            for (candidates.slice()) |x| {
                const reason = try session.putItem(x, y);
                if (reason == null) moved = true;
                try session.say("{s}: {s}", .{ game.items.items[x].name, reason orelse "Done." });
            }
            return moved;
        }
        const x = try session.resolve(first);
        const y = try session.resolve(second);
        if (!game.carried(x)) return session.fail("You aren't carrying the {s}.", .{game.items.items[x].name});
        if (x == y) return session.fail("You can't put the {s} inside itself.", .{game.items.items[x].name});
        try session.requireContainer(y);
        if (try session.putItem(x, y)) |reason| return session.fail("{s}", .{reason});
        try session.say("You put the {s} in the {s}.", .{ game.items.items[x].name, game.items.items[y].name });
        return true;
    }
    fn open(session: *Session, x: usize) Error!void {
        const game = session.game;
        const name = game.items.items[x].name;
        if (game.items.items[x].capacity == null) return session.fail("You can't open the {s}.", .{name});
        if (game.state.containers[x] == .open) return session.fail("The {s} is already open.", .{name});
        if (game.state.containers[x] == .locked) return session.fail("The {s} is locked.", .{name});
        game.state.containers[x] = .open;
        const children = game.direct(.{ .kind = .inside, .index = x });
        if (children.len == 0) try session.say("Opened.", .{}) else try session.say("Opening the {s} reveals {f}.", .{ name, Names{ .game = game, .selected = children } });
    }
    fn close(session: *Session, x: usize) Error!void {
        const game = session.game;
        if (game.items.items[x].capacity == null) return session.fail("You can't close the {s}.", .{game.items.items[x].name});
        if (game.state.containers[x] != .open) return session.fail("The {s} is already closed.", .{game.items.items[x].name});
        game.state.containers[x] = .closed;
        try session.say("Closed.", .{});
    }
    fn checkKey(session: *Session, key: usize, phrase: ?[]const []const u8) Error!void {
        const game = session.game;
        if (phrase) |words| {
            const x = try session.resolve(words);
            if (!game.carried(x)) return session.fail("You aren't carrying the {s}.", .{game.items.items[x].name});
            if (x != key) return session.fail("The {s} doesn't fit.", .{game.items.items[x].name});
        } else {
            if (!game.carried(key)) return session.fail("You don't have the right key.", .{});
            try session.say("(with the {s})", .{game.items.items[key].name});
        }
    }
    fn lock(session: *Session, target: []const []const u8, key_phrase: ?[]const []const u8, locking: bool) Error!void {
        const game = session.game;
        const direction: ?Direction = if (target.len == 1) directionOf(target[0]) else null;
        if (direction) |d| {
            const index = @backingInt(d);
            const exit = game.state.exits[game.state.room][index] orelse return session.fail("There is no exit {s}.", .{@tagName(d)});
            const key = exit.key orelse return session.fail("The way {s} has no lock.", .{@tagName(d)});
            if (exit.locked == locking) return session.fail("The way {s} is {s}.", .{ @tagName(d), if (locking) "already locked" else "not locked" });
            try session.checkKey(key, key_phrase);
            game.state.exits[game.state.room][index].?.locked = locking;
            if (game.state.exits[exit.destination][index ^ 1]) |back| {
                if (back.destination == game.state.room and back.key == exit.key) game.state.exits[exit.destination][index ^ 1].?.locked = locking;
            }
        } else {
            const x = try session.resolve(target);
            const item = &game.items.items[x];
            if (item.capacity == null or item.key == null) return session.fail("The {s} has no lock.", .{item.name});
            if ((game.state.containers[x] == .locked) == locking) return session.fail("The {s} is {s}.", .{ item.name, if (locking) "already locked" else "not locked" });
            if (locking and game.state.containers[x] == .open) return session.fail("You must close the {s} first.", .{item.name});
            try session.checkKey(item.key.?, key_phrase);
            game.state.containers[x] = if (locking) .locked else .closed;
        }
        try session.say("{s}", .{if (locking) "Locked." else "Unlocked."});
    }
    fn runRule(session: *Session, rule: Rule) Error!?bool {
        const game = session.game;
        if (rule.flag) |flag| if (game.state.flags[flag] != rule.when_on) return null;
        switch (rule.effect) {
            .message => |text| {
                try session.say("{s}", .{text});
                return true;
            },
            .open => |effect| game.state.exits[effect.room][@backingInt(effect.direction)] = .{ .destination = effect.destination },
            .move => |effect| game.state.places[effect.item] = effect.place,
            .flag => |effect| game.state.flags[effect.index] = effect.on,
            .points => |amount| game.state.bonus += amount,
        }
        return false;
    }
    fn use(session: *Session, first: []const []const u8, second: []const []const u8) Error!void {
        const game = session.game;
        const x = try session.resolve(first);
        const y = try session.resolve(second);
        if (!game.carried(x)) return session.fail("You aren't carrying the {s}.", .{game.items.items[x].name});
        var executed: usize = 0;
        var message = false;
        for (game.use_rules.items) |entry| if (entry.first == x and entry.second == y) {
            if (try session.runRule(entry.rule)) |printed| {
                executed += 1;
                message = message or printed;
            }
        };
        if (executed == 0) return session.fail("Nothing happens.", .{});
        if (!message) try session.say("Done.", .{});
    }
    fn light(session: *Session, x: usize, lighting: bool) Error!void {
        const game = session.game;
        const name = game.items.items[x].name;
        if (!game.items.items[x].light) return session.fail("You can't {s} the {s}.", .{ if (lighting) "light" else "extinguish", name });
        if (game.state.lit[x] == lighting) return session.fail("The {s} is {s}.", .{ name, if (lighting) "already lit" else "not lit" });
        if (lighting and game.state.fuel[x] == 0) return session.fail("The {s} has no fuel.", .{name});
        game.state.lit[x] = lighting;
        try session.say("The {s} is now {s}.", .{ name, if (lighting) "lit" else "out" });
    }
    fn move(session: *Session, direction: Direction) Error!bool {
        const game = session.game;
        const exit = game.state.exits[game.state.room][@backingInt(direction)] orelse return session.fail("You can't go that way.", .{});
        if (exit.locked) return session.fail("The way {s} is locked.", .{@tagName(direction)});
        game.state.room = exit.destination;
        const baseline = game.isLit();
        try session.describe(game.verbose or !game.state.visited[game.state.room]);
        game.state.visited[game.state.room] = true;
        for (game.rooms.items[game.state.room].enter.items) |rule| _ = try session.runRule(rule);
        return baseline;
    }
    fn turn(session: *Session, baseline: bool) Error!void {
        const game = session.game;
        game.state.moves += 1;
        var reachable: [200]bool = @splat(false);
        for (0..game.items.items.len) |x| reachable[x] = game.carried(x) or game.reachable(x, game.floor());
        for (0..game.items.items.len) |x| if (game.state.lit[x]) {
            game.state.fuel[x] -= 1;
            if (game.state.fuel[x] == 0) {
                game.state.lit[x] = false;
                if (reachable[x]) try session.say("The {s} goes out.", .{game.items.items[x].name});
            }
        };
        const lit = game.isLit();
        if (baseline and !lit) try session.say("It is now pitch dark.", .{}) else if (!baseline and lit) try session.describe(true);
        game.state.darkness = if (lit) 0 else game.state.darkness + 1;
        if (game.state.darkness == 2) try session.say("You hear something moving in the dark.", .{});
        if (game.state.darkness == 3) game.state.end = .dead;
        const treasure = game.treasures();
        if (game.state.end == .none and treasure.total > 0 and treasure.stored == treasure.total) game.state.end = .won;
        if (game.state.end != .none) {
            try session.say("{s}", .{if (game.state.end == .dead) "*** You have died ***" else "*** You have won ***"});
            try session.say("You scored {d} points in {d} moves.", .{ treasure.points + game.state.bonus, game.state.moves });
        }
    }
    fn run(session: *Session, verb: Verb, first: []const []const u8, second: ?[]const []const u8) Error!void {
        const game = session.game;
        var baseline = game.isLit();
        var success = true;
        switch (verb) {
            .go => baseline = try session.move(directionOf(first[0]).?),
            .look => try session.describe(true),
            .examine => try session.examine(try session.resolve(first)),
            .take => success = try session.take(first, second),
            .drop => try session.drop(first),
            .put => success = try session.put(first, second.?),
            .open => try session.open(try session.resolve(first)),
            .close => try session.close(try session.resolve(first)),
            .unlock => try session.lock(first, second, false),
            .lock => try session.lock(first, second, true),
            .use => try session.use(first, second.?),
            .light => try session.light(try session.resolve(first), true),
            .extinguish => try session.light(try session.resolve(first), false),
            .wait => try session.say("Time passes.", .{}),
            .inventory => {
                if (game.direct(player).len == 0) try session.say("You are empty-handed.", .{}) else {
                    try session.say("You are carrying:", .{});
                    try session.itemTree(player, 1);
                    try session.say("Total weight: {d}/{d}", .{ game.carriedWeight(), game.max_weight });
                }
            },
            .score => {
                const treasure = game.treasures();
                try session.say("You have scored {d} points (treasure {d}, bonus {d}) in {d} moves.", .{
                    treasure.points + game.state.bonus, treasure.points, game.state.bonus, game.state.moves,
                });
                try session.say("Treasures stored: {d} of {d}.", .{ treasure.stored, treasure.total });
            },
            .save => {
                game.saved = game.state;
                try session.say("Game saved.", .{});
            },
            .restore => {
                game.state = game.saved orelse return session.fail("There is no saved game.", .{});
                try session.say("Game restored.", .{});
                try session.describe(true);
            },
            .verbose => {
                game.verbose = true;
                try session.say("Verbose mode.", .{});
            },
            .brief => {
                game.verbose = false;
                try session.say("Brief mode.", .{});
            },
        }
        const action = switch (verb) {
            .go, .take, .drop, .put, .open, .close, .unlock, .lock, .use, .light, .extinguish, .wait => true,
            else => false,
        };
        if (success and action) try session.turn(baseline);
    }
    fn interpret(session: *Session, words: []const []const u8) Error!void {
        if (words.len == 0) return session.fail("I beg your pardon?", .{});
        var rest = words[1..];
        var verb: Verb = undefined;
        if (directionOf(words[0]) != null) {
            verb = .go;
            rest = words;
        } else verb = verbOf(words[0]) orelse return session.fail("I don't know the verb \"{s}\".", .{words[0]});
        if (session.game.state.end != .none and verb != .restore) return session.fail("The game is over.", .{});
        if (verb == .look and rest.len > 0) {
            if (!equal(rest[0], "at")) return session.fail("I don't understand that.", .{});
            verb = .examine;
            rest = rest[1..];
        }
        const no_objects = switch (verb) {
            .look, .inventory, .wait, .score, .save, .restore, .verbose, .brief => true,
            else => false,
        };
        if (no_objects) {
            if (rest.len != 0) return session.fail("I don't understand that.", .{});
            return session.run(verb, rest, null);
        }
        if (rest.len == 0) {
            if (verb == .go) return session.fail("Which way do you want to go?", .{});
            return session.fail("What do you want to {s}?", .{@tagName(verb)});
        }
        if (verb == .go) {
            if (rest.len != 1 or directionOf(rest[0]) == null) return session.fail("I don't understand that.", .{});
            return session.run(verb, rest, null);
        }
        const prepositions: []const []const u8 = switch (verb) {
            .put => &.{ "in", "into" },
            .use => &.{ "on", "with" },
            .lock, .unlock => if (contains(rest, "with")) &.{"with"} else &.{},
            .take => if (contains(rest, "from")) &.{"from"} else &.{},
            else => &.{},
        };
        if (prepositions.len == 0) return session.run(verb, rest, null);
        var at: usize = 0;
        while (at < rest.len and !contains(prepositions, rest[at])) : (at += 1) {}
        if (at == 0 or at >= rest.len - 1) return session.fail("I don't understand that.", .{});
        try session.run(verb, rest[0..at], rest[at + 1 ..]);
    }
    fn process(session: *Session, text: []const u8) Error!void {
        try session.say("> {s}", .{text});
        var words = try normalized(session.gpa, text);
        if (words.len > 0 and (equal(words[0], "again") or equal(words[0], "g"))) {
            if (words.len != 1) return session.fail("I don't understand that.", .{});
            const previous = session.game.previous orelse return session.fail("There is nothing to repeat.", .{});
            words = try normalized(session.gpa, previous);
        } else session.game.previous = try session.game.gpa.dupe(u8, text);
        try session.interpret(words);
    }
};

fn readLine(gpa: Allocator, input: *std.Io.Reader) ![]const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    return if (text.len > 0 and text[text.len - 1] == '\r') text[0 .. text.len - 1] else text;
}
pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [1024]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var definitions: std.ArrayList([]const u8) = .empty;
    while (true) {
        const text = try readLine(gpa, &input.interface);
        if (equal(text, "BEGIN")) break;
        try definitions.append(gpa, text);
    }
    const game = try Adventure.create(gpa, definitions.items);
    var initial: Session = .{ .game = game, .gpa = gpa, .out = &output.interface };
    try initial.describe(true);
    try output.interface.flush();
    while (true) {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const temporary = scratch.allocator();
        const text = try readLine(temporary, &input.interface);
        if (equal(text, "QUIT")) break;
        var response: Writer.Allocating = .init(temporary);
        defer response.deinit();
        var session: Session = .{ .game = game, .gpa = temporary, .out = &response.writer };
        session.process(text) catch |err| {
            if (err != error.Invalid) return err;
            try line(&response.writer, "{s}", .{session.problem});
        };
        try output.interface.writeAll(response.written());
        try output.interface.flush();
    }
    const treasure = game.treasures();
    try line(&output.interface, "Final score: {d} points in {d} moves.", .{ treasure.points + game.state.bonus, game.state.moves });
    try output.interface.flush();
}
