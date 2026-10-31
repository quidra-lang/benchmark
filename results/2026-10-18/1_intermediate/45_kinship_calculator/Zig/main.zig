const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Text = []const u8;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Sex = enum { M, F, X };
const Status = enum { current, divorced, widowed };
const Verb = enum {
    PERSON,
    DEATH,
    REMOVE,
    PARENT,
    UNPARENT,
    SPOUSE,
    DIVORCE,
    UNDO,
    INFO,
    RELATION,
    RELATIVES,
    WHO,
    PATH,
    COMMON,
    ANCESTORS,
    DESCENDANTS,
    COUSINS,
    SIBLINGS,
    GENERATIONS,
    TREE,
    PEDIGREE,
    TIMELINE,
    CENSUS,
    KINSHIP,
    FIND,
    TERM,
    STATS,
    AUDIT,
};
const Step = enum { parent, father, mother, child, son, daughter, sibling, brother, sister, spouse, husband, wife };

fn IndexList(comptime capacity: usize) type {
    return struct {
        data: [capacity]usize = undefined,
        len: usize = 0,
        const Self = @This();

        fn add(list: *Self, value: usize) void {
            list.data[list.len] = value;
            list.len += 1;
        }
        fn slice(list: *const Self) []const usize {
            return list.data[0..list.len];
        }
        fn contains(list: *const Self, value: usize) bool {
            for (list.slice()) |item| if (item == value) return true;
            return false;
        }
        fn remove(list: *Self, value: usize) void {
            for (list.slice(), 0..) |item, i| if (item == value) {
                for (i + 1..list.len) |j| list.data[j - 1] = list.data[j];
                list.len -= 1;
                return;
            };
        }
    };
}
const Selection = IndexList(200);
const Parents = IndexList(2);
const Person = struct {
    active: bool = false,
    id: Text = "",
    name: Text = "",
    sex: Sex = .X,
    birth: i32 = 0,
    death: ?i32 = null,
    parents: Parents = .{},
};
const Marriage = struct {
    first: usize,
    second: usize,
    start: i32,
    end: ?i32 = null,
    status: Status = .current,
    died: ?usize = null,

    fn contains(marriage: Marriage, id: usize) bool {
        return marriage.first == id or marriage.second == id;
    }
    fn other(marriage: Marriage, id: usize) usize {
        return if (marriage.first == id) marriage.second else marriage.first;
    }
};
const Family = struct {
    people: [200]Person = @splat(.{}),
    marriages: [1000]Marriage = undefined,
    marriage_count: usize = 0,

    fn lookup(family: *const Family, id: Text) ?usize {
        for (family.people, 0..) |person, i| if (person.active and equal(person.id, id)) return i;
        return null;
    }
    fn idLess(family: *const Family, a: usize, b: usize) bool {
        return std.mem.order(u8, family.people[a].id, family.people[b].id) == .lt;
    }
    fn ageLess(family: *const Family, a: usize, b: usize) bool {
        const first = family.people[a];
        const second = family.people[b];
        return if (first.birth != second.birth) first.birth < second.birth else family.idLess(a, b);
    }
    fn ordered(family: *const Family, input: Selection, age: bool) Selection {
        var result = input;
        if (age) std.sort.heap(usize, result.data[0..result.len], family, ageLess) else std.sort.heap(usize, result.data[0..result.len], family, idLess);
        return result;
    }
};
const Snapshot = struct { source: Text, family: *const Family };
const Calculator = struct {
    storage: Allocator,
    family: Family = .{},
    history: std.ArrayList(Snapshot) = .empty,

    fn remember(calculator: *Calculator, source: Text) Allocator.Error!void {
        const saved = try calculator.storage.create(Family);
        saved.* = calculator.family;
        try calculator.history.append(calculator.storage, .{
            .source = try calculator.storage.dupe(u8, source),
            .family = saved,
        });
    }
};
const Fraction = struct {
    numerator: u64 = 0,
    power: u6 = 0,

    fn make(numerator: u64, power: u6) Fraction {
        if (numerator == 0) return .{};
        var n = numerator;
        var p = power;
        while (p > 0 and n % 2 == 0) {
            n /= 2;
            p -= 1;
        }
        return .{ .numerator = n, .power = p };
    }
    fn add(a: Fraction, b: Fraction) Fraction {
        const p = @max(a.power, b.power);
        return make((a.numerator << (p - a.power)) + (b.numerator << (p - b.power)), p);
    }
    fn half(value: Fraction) Fraction {
        return make(value.numerator, value.power + 1);
    }
    pub fn format(value: Fraction, writer: *Writer) Writer.Error!void {
        try writer.print("{d}/{d}", .{ value.numerator, @as(u64, 1) << value.power });
    }
};
const Apex = struct { id: usize, a: i16, b: i16, share: usize = 0 };

fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn integer(text: Text) i32 {
    return std.fmt.parseInt(i32, text, 10) catch unreachable;
}
fn line(out: *Writer, comptime format: Text, args: anytype) Writer.Error!void {
    try out.print(format ++ "\n", args);
}
fn gender(sex: Sex, male: Text, female: Text, neutral: Text) Text {
    return switch (sex) {
        .M => male,
        .F => female,
        .X => neutral,
    };
}
fn grand(out: *Writer, generation: i32) Writer.Error!void {
    if (generation == 1) return;
    for (0..@intCast(generation - 2)) |_| try out.writeAll("great-");
    try out.writeAll("grand");
}
fn ordinal(out: *Writer, value: i32) Writer.Error!void {
    const first = [_]Text{ "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth" };
    if (value <= 10) return out.writeAll(first[@intCast(value - 1)]);
    const suffix: Text = if (@mod(value, 100) >= 11 and @mod(value, 100) <= 13) "th" else switch (@mod(value, 10)) {
        1 => "st",
        2 => "nd",
        3 => "rd",
        else => "th",
    };
    try out.print("{d}{s}", .{ value, suffix });
}
fn writeTerm(out: *Writer, a: i32, b: i32, sex: Sex) Writer.Error!void {
    if (a == 0 and b == 0) return out.writeAll("self");
    if (a == 0) {
        try grand(out, b);
        return out.writeAll(gender(sex, "father", "mother", "parent"));
    }
    if (b == 0) {
        try grand(out, a);
        return out.writeAll(gender(sex, "son", "daughter", "child"));
    }
    if (a == 1 and b == 1) return out.writeAll(gender(sex, "brother", "sister", "sibling"));
    if (a == 1) {
        try grand(out, b - 1);
        return out.writeAll(gender(sex, "uncle", "aunt", "pibling"));
    }
    if (b == 1) {
        try grand(out, a - 1);
        return out.writeAll(gender(sex, "nephew", "niece", "nibling"));
    }
    try ordinal(out, @min(a, b) - 1);
    try out.writeAll(" cousin");
    const removal = @abs(a - b);
    switch (removal) {
        0 => {},
        1 => try out.writeAll(" once removed"),
        2 => try out.writeAll(" twice removed"),
        else => try out.print(" {d} times removed", .{removal}),
    }
}
fn writeLife(out: *Writer, person: Person) Writer.Error!void {
    try out.print("{d}-", .{person.birth});
    if (person.death) |year| try out.print("{d}", .{year});
}

const Analysis = struct {
    family: *const Family,
    ids: Selection = .{},
    children: [200]Selection = @splat(.{}),
    upward: [200][200]i16 = undefined,
    downward: [200][200]i16 = undefined,
    up_ready: [200]bool = @splat(false),
    down_ready: [200]bool = @splat(false),
    latest: [200][200]i16 = @splat(@splat(-1)),
    currents: [200]?usize = @splat(null),
    coefficients: [200][200]?Fraction = @splat(@splat(null)),

    fn create(gpa: Allocator, family: *const Family) Allocator.Error!*Analysis {
        const graph = try gpa.create(Analysis);
        graph.* = .{ .family = family };
        for (family.people, 0..) |entry, i| if (entry.active) graph.ids.add(i);
        graph.ids = family.ordered(graph.ids, false);
        for (graph.ids.slice()) |id| {
            for (family.people[id].parents.slice()) |parent| graph.children[parent].add(id);
        }
        for (family.marriages[0..family.marriage_count], 0..) |marriage, i| {
            graph.latest[marriage.first][marriage.second] = @intCast(i);
            graph.latest[marriage.second][marriage.first] = @intCast(i);
            if (marriage.status == .current) {
                graph.currents[marriage.first] = i;
                graph.currents[marriage.second] = i;
            }
        }
        return graph;
    }
    fn person(graph: *const Analysis, id: usize) *const Person {
        return &graph.family.people[id];
    }
    fn parents(graph: *const Analysis, id: usize) []const usize {
        return graph.person(id).parents.slice();
    }
    fn current(graph: *const Analysis, id: usize) ?Marriage {
        const index = graph.currents[id] orelse return null;
        return graph.family.marriages[index];
    }
    fn spouse(graph: *const Analysis, id: usize) ?usize {
        return if (graph.current(id)) |marriage| marriage.other(id) else null;
    }
    fn last(graph: *const Analysis, a: usize, b: usize) ?Marriage {
        const index = graph.latest[a][b];
        return if (index < 0) null else graph.family.marriages[@intCast(index)];
    }
    fn partner(graph: *const Analysis, a: usize, b: usize) bool {
        const marriage = graph.last(a, b) orelse return false;
        return marriage.status != .divorced;
    }
    fn sharedParents(graph: *const Analysis, a: usize, b: usize) usize {
        var count: usize = 0;
        for (graph.parents(a)) |parent| if (graph.person(b).parents.contains(parent)) {
            count += 1;
        };
        return count;
    }
    fn siblings(graph: *const Analysis, a: usize, b: usize) bool {
        return a != b and graph.sharedParents(a, b) > 0;
    }
    fn stepSiblings(graph: *const Analysis, a: usize, b: usize) bool {
        if (graph.sharedParents(a, b) != 0) return false;
        for (graph.parents(a)) |p| {
            for (graph.parents(b)) |q| if (graph.partner(p, q)) return true;
        }
        return false;
    }
    fn distances(graph: *Analysis, start: usize, up: bool) *const [200]i16 {
        const ready = if (up) &graph.up_ready[start] else &graph.down_ready[start];
        const result = if (up) &graph.upward[start] else &graph.downward[start];
        if (ready.*) return result;
        @memset(result, -1);
        result[start] = 0;
        var pending: Selection = .{};
        pending.add(start);
        var at: usize = 0;
        while (at < pending.len) : (at += 1) {
            const id = pending.data[at];
            const adjacent = if (up) graph.parents(id) else graph.children[id].slice();
            for (adjacent) |next| if (result[next] == -1) {
                result[next] = result[id] + 1;
                pending.add(next);
            };
        }
        ready.* = true;
        return result;
    }
    fn ancestor(graph: *Analysis, a: usize, b: usize) bool {
        return a != b and graph.distances(b, true)[a] >= 0;
    }
    fn apex(graph: *Analysis, a: usize, b: usize) ?Apex {
        const first = graph.distances(a, true);
        const second = graph.distances(b, true);
        if (second[a] >= 0) return .{ .id = a, .a = 0, .b = second[a] };
        if (first[b] >= 0) return .{ .id = b, .a = first[b], .b = 0 };
        var best: ?Apex = null;
        for (graph.ids.slice()) |id| {
            if (first[id] < 0 or second[id] < 0) continue;
            if (best == null or first[id] + second[id] < best.?.a + best.?.b or
                (first[id] + second[id] == best.?.a + best.?.b and first[id] < best.?.a))
                best = .{ .id = id, .a = first[id], .b = second[id] };
        }
        if (best) |*chosen| {
            for (graph.ids.slice()) |id| if (first[id] == chosen.a and second[id] == chosen.b) {
                chosen.share += 1;
            };
        }
        return best;
    }
    fn phi(graph: *Analysis, a: usize, b: usize) Fraction {
        if (graph.coefficients[a][b]) |cached| return cached;
        var value: Fraction = .{};
        if (a == b) {
            value = (Fraction{ .numerator = 1 }).add(graph.inbreeding(a)).half();
        } else {
            const x = if (graph.person(a).birth >= graph.person(b).birth) a else b;
            const y = if (x == a) b else a;
            for (graph.parents(x)) |parent| value = value.add(graph.phi(parent, y));
            value = value.half();
        }
        graph.coefficients[a][b] = value;
        graph.coefficients[b][a] = value;
        return value;
    }
    fn inbreeding(graph: *Analysis, id: usize) Fraction {
        const values = graph.parents(id);
        return if (values.len == 2) graph.phi(values[0], values[1]) else .{};
    }
};

const Session = struct {
    calculator: *Calculator,
    graph: *Analysis,
    gpa: Allocator,
    out: *Writer,
    problem: Text = "",

    fn fail(session: *Session, comptime format: Text, args: anytype) Error {
        session.problem = std.fmt.allocPrint(session.gpa, format, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn check(session: *Session, name: Text) Error!usize {
        return session.calculator.family.lookup(name) orelse return session.fail("UNKNOWN PERSON {s}", .{name});
    }
    fn blood(session: *Session, apex: Apex, sex: Sex) Error!Text {
        var text: Writer.Allocating = .init(session.gpa);
        defer text.deinit();
        if (apex.a > 0 and apex.b > 0) {
            if (apex.share == 1) try text.writer.writeAll("half-") else if (apex.share >= 4) try text.writer.writeAll("double ");
        }
        try writeTerm(&text.writer, apex.a, apex.b, sex);
        return text.toOwnedSlice();
    }
    fn relations(session: *Session, a: usize, b: usize, sex: Sex) Error![]const Text {
        var result: std.ArrayList(Text) = .empty;
        if (a == b) {
            try result.append(session.gpa, "self");
            return result.toOwnedSlice(session.gpa);
        }
        const graph = session.graph;
        if (graph.apex(a, b)) |apex| try result.append(session.gpa, try session.blood(apex, sex));
        if (graph.last(a, b)) |marriage| {
            try result.append(session.gpa, switch (marriage.status) {
                .current => gender(sex, "husband", "wife", "spouse"),
                .divorced => gender(sex, "ex-husband", "ex-wife", "ex-spouse"),
                .widowed => if (marriage.died == a) gender(sex, "late husband", "late wife", "late spouse") else gender(sex, "widower", "widow", "surviving spouse"),
            });
        } else {
            for (graph.children[a].slice()) |child| if (graph.person(child).parents.contains(b)) {
                try result.append(session.gpa, "co-parent");
                break;
            };
        }
        if (!graph.person(b).parents.contains(a)) {
            for (graph.parents(b)) |parent| if (graph.partner(a, parent)) {
                try result.append(session.gpa, gender(sex, "stepfather", "stepmother", "stepparent"));
                break;
            };
        }
        if (!graph.person(a).parents.contains(b)) {
            for (graph.parents(a)) |parent| if (graph.partner(b, parent)) {
                try result.append(session.gpa, gender(sex, "stepson", "stepdaughter", "stepchild"));
                break;
            };
        }
        if (graph.stepSiblings(a, b)) try result.append(session.gpa, gender(sex, "stepbrother", "stepsister", "stepsibling"));
        if (!graph.ancestor(a, b)) {
            const distances = graph.distances(b, true);
            for (graph.ids.slice()) |parent| if (distances[parent] == 2 and graph.partner(a, parent)) {
                try result.append(session.gpa, gender(sex, "stepgrandfather", "stepgrandmother", "stepgrandparent"));
                break;
            };
        }
        if (!graph.ancestor(b, a)) {
            const distances = graph.distances(a, true);
            for (graph.ids.slice()) |parent| if (distances[parent] == 2 and graph.partner(b, parent)) {
                try result.append(session.gpa, gender(sex, "stepgrandson", "stepgranddaughter", "stepgrandchild"));
                break;
            };
        }
        for (graph.ids.slice()) |partner| if (graph.partner(b, partner) and graph.person(partner).parents.contains(a)) {
            try result.append(session.gpa, gender(sex, "father-in-law", "mother-in-law", "parent-in-law"));
            break;
        };
        for (graph.ids.slice()) |partner| if (graph.partner(a, partner) and graph.person(partner).parents.contains(b)) {
            try result.append(session.gpa, gender(sex, "son-in-law", "daughter-in-law", "child-in-law"));
            break;
        };
        for (graph.ids.slice()) |partner| {
            if ((graph.partner(b, partner) and graph.siblings(a, partner)) or
                (graph.partner(a, partner) and graph.siblings(partner, b)))
            {
                try result.append(session.gpa, gender(sex, "brother-in-law", "sister-in-law", "sibling-in-law"));
                break;
            }
        }
        return result.toOwnedSlice(session.gpa);
    }
    fn relation(session: *Session, a: usize, b: usize) Error!Text {
        const terms = try session.relations(a, b, session.graph.person(a).sex);
        if (terms.len == 0) return "no relation";
        return std.mem.join(session.gpa, ", ", terms);
    }
    fn personList(session: *Session, input: []const usize) Error!void {
        var selected: Selection = .{};
        for (input) |id| selected.add(id);
        selected = session.graph.family.ordered(selected, true);
        if (selected.len == 0) return session.out.writeAll("-");
        for (selected.slice(), 0..) |id, i| {
            if (i > 0) try session.out.writeByte(' ');
            try session.out.writeAll(session.graph.person(id).id);
        }
    }
    fn modify(session: *Session, source: Text, verb: Verb, args: []const Text) Error!void {
        const calculator = session.calculator;
        const family = &calculator.family;
        const graph = session.graph;
        if (verb == .PERSON) {
            if (family.lookup(args[1]) != null) return session.fail("DUPLICATE PERSON {s}", .{args[1]});
            try calculator.remember(source);
            for (&family.people) |*person| if (!person.active) {
                person.* = .{
                    .active = true,
                    .id = try calculator.storage.dupe(u8, args[1]),
                    .name = try calculator.storage.dupe(u8, args[4]),
                    .sex = std.meta.stringToEnum(Sex, args[2]).?,
                    .birth = integer(args[3]),
                };
                return line(session.out, "ADDED {s} {s} {s} {d}", .{ person.id, person.name, @tagName(person.sex), person.birth });
            };
            unreachable;
        }
        const a = try session.check(args[1]);
        const first = &family.people[a];
        if (verb == .REMOVE) {
            try calculator.remember(source);
            first.active = false;
            for (&family.people) |*person| if (person.active) person.parents.remove(a);
            var count: usize = 0;
            for (family.marriages[0..family.marriage_count]) |marriage| {
                if (marriage.contains(a)) continue;
                family.marriages[count] = marriage;
                count += 1;
            }
            family.marriage_count = count;
            return line(session.out, "REMOVED {s}", .{args[1]});
        }
        if (verb == .DEATH) {
            const year = integer(args[2]);
            if (first.death != null) return session.fail("ALREADY DECEASED {s}", .{first.id});
            if (year < first.birth) return session.fail("BAD YEAR {s}", .{first.id});
            for (family.marriages[0..family.marriage_count]) |marriage| {
                if (marriage.contains(a) and (marriage.start > year or (marriage.end orelse year) > year))
                    return session.fail("BAD YEAR {s}", .{first.id});
            }
            for (graph.children[a].slice()) |child| if (graph.person(child).birth > year + 1)
                return session.fail("AFTER DEATH {s} {s}", .{ graph.person(child).id, first.id });
            const current = graph.currents[a];
            try calculator.remember(source);
            first.death = year;
            try session.out.print("DIED {s} {d}", .{ first.id, year });
            if (current) |index| {
                const marriage = &family.marriages[index];
                marriage.end = year;
                marriage.status = .widowed;
                marriage.died = a;
                try session.out.print(" spouse={s}", .{graph.person(marriage.other(a)).id});
            }
            return session.out.writeByte('\n');
        }
        const b = try session.check(args[2]);
        const second = &family.people[b];
        if (verb == .PARENT) {
            if (a == b) return session.fail("SAME PERSON {s}", .{first.id});
            if (first.parents.contains(b)) return session.fail("ALREADY PARENT {s} {s}", .{ first.id, second.id });
            if (first.parents.len == 2) return session.fail("TOO MANY PARENTS {s}", .{first.id});
            if (graph.ancestor(a, b)) return session.fail("CYCLE {s} {s}", .{ first.id, second.id });
            if (second.birth + 12 > first.birth) return session.fail("AGE GAP {s} {s}", .{ first.id, second.id });
            if (second.death) |year| if (year + 1 < first.birth)
                return session.fail("AFTER DEATH {s} {s}", .{ first.id, second.id });
            try calculator.remember(source);
            first.parents.add(b);
            return line(session.out, "LINKED {s} {s} {s}", .{ first.id, second.id, gender(second.sex, "father", "mother", "parent") });
        }
        if (verb == .UNPARENT) {
            if (!first.parents.contains(b)) return session.fail("NOT PARENT {s} {s}", .{ first.id, second.id });
            try calculator.remember(source);
            first.parents.remove(b);
            return line(session.out, "UNLINKED {s} {s}", .{ first.id, second.id });
        }
        const year = integer(args[3]);
        if (verb == .SPOUSE) {
            if (a == b) return session.fail("SAME PERSON {s}", .{first.id});
            for ([_]usize{ a, b }) |id| if (graph.person(id).death != null)
                return session.fail("DECEASED {s}", .{graph.person(id).id});
            for ([_]usize{ a, b }) |id| if (graph.currents[id] != null)
                return session.fail("ALREADY MARRIED {s}", .{graph.person(id).id});
            if (graph.ancestor(a, b) or graph.ancestor(b, a) or graph.siblings(a, b))
                return session.fail("CLOSE KIN {s} {s}", .{ first.id, second.id });
            for ([_]usize{ a, b }) |id| if (year < graph.person(id).birth + 16)
                return session.fail("TOO YOUNG {s}", .{graph.person(id).id});
            for ([_]usize{ a, b }) |id| {
                for (family.marriages[0..family.marriage_count]) |marriage| {
                    if (marriage.contains(id) and (marriage.end orelse (year - 1)) >= year)
                        return session.fail("BAD YEAR {s}", .{graph.person(id).id});
                }
            }
            try calculator.remember(source);
            family.marriages[family.marriage_count] = .{ .first = a, .second = b, .start = year };
            family.marriage_count += 1;
            return line(session.out, "MARRIED {s} {s} {d}", .{ first.id, second.id, year });
        }
        const index = graph.currents[a] orelse return session.fail("NOT MARRIED {s} {s}", .{ first.id, second.id });
        const marriage = &family.marriages[index];
        if (marriage.other(a) != b) return session.fail("NOT MARRIED {s} {s}", .{ first.id, second.id });
        if (year <= marriage.start) return session.fail("BAD YEAR {s}", .{first.id});
        try calculator.remember(source);
        marriage.end = year;
        marriage.status = .divorced;
        return line(session.out, "DIVORCED {s} {s} {d}", .{ first.id, second.id, year });
    }
    fn info(session: *Session, id: usize) Error!void {
        const graph = session.graph;
        const person = graph.person(id);
        try session.out.print("INFO {s} {s} {s} ", .{ person.id, person.name, @tagName(person.sex) });
        try writeLife(session.out, person.*);
        try session.out.writeAll("\n  parents: ");
        try session.personList(graph.parents(id));
        try session.out.writeByte('\n');
        for (graph.family.marriages[0..graph.family.marriage_count]) |marriage| if (marriage.contains(id)) {
            try session.out.print("  marriage: {s} {d}-", .{ graph.person(marriage.other(id)).id, marriage.start });
            if (marriage.end) |year| try session.out.print("{d}", .{year});
            try line(session.out, " {s}", .{@tagName(marriage.status)});
        };
        try session.out.writeAll("  children: ");
        try session.personList(graph.children[id].slice());
        try session.out.writeAll("\n  siblings: ");
        var siblings: Selection = .{};
        for (graph.ids.slice()) |other| if (graph.siblings(id, other)) siblings.add(other);
        try session.personList(siblings.slice());
        try line(session.out, "\n  inbreeding: {f}", .{graph.inbreeding(id)});
    }
    fn upwardPath(session: *Session, start: usize, apex: usize) Selection {
        const graph = session.graph;
        const distance = graph.distances(apex, false);
        var result: Selection = .{};
        var current = start;
        result.add(current);
        while (current != apex) {
            var next: ?usize = null;
            for (graph.parents(current)) |parent| {
                if (distance[parent] == distance[current] - 1 and
                    (next == null or graph.family.idLess(parent, next.?))) next = parent;
            }
            current = next.?;
            result.add(current);
        }
        return result;
    }
    fn path(session: *Session, a: usize, b: usize) Error!void {
        const graph = session.graph;
        const apex = graph.apex(a, b) orelse return line(session.out, "PATH {s} {s} none", .{ graph.person(a).id, graph.person(b).id });
        var first = session.upwardPath(a, apex.id);
        const second = session.upwardPath(b, apex.id);
        var i = second.len - 1;
        while (i > 0) {
            i -= 1;
            first.add(second.data[i]);
        }
        try session.out.print("PATH {s} {s} {d}:", .{ graph.person(a).id, graph.person(b).id, apex.a + apex.b });
        for (first.slice()) |id| try session.out.print(" {s}", .{graph.person(id).id});
        try session.out.writeByte('\n');
    }
    fn common(session: *Session, a: usize, b: usize) Error!void {
        const graph = session.graph;
        const first = graph.distances(a, true);
        const second = graph.distances(b, true);
        var nearest: Selection = .{};
        for (graph.ids.slice()) |id| {
            if (first[id] < 0 or second[id] < 0) continue;
            var child_common = false;
            for (graph.children[id].slice()) |child| {
                if (first[child] >= 0 and second[child] >= 0) child_common = true;
            }
            if (!child_common) nearest.add(id);
        }
        const Context = struct {
            family: *const Family,
            first: *const [200]i16,
            second: *const [200]i16,
            fn less(context: @This(), x: usize, y: usize) bool {
                const a_sum = context.first[x] + context.second[x];
                const b_sum = context.first[y] + context.second[y];
                return if (a_sum != b_sum) a_sum < b_sum else context.family.idLess(x, y);
            }
        };
        std.sort.heap(usize, nearest.data[0..nearest.len], Context{ .family = graph.family, .first = first, .second = second }, Context.less);
        try line(session.out, "COMMON {s} {s} {d}", .{ graph.person(a).id, graph.person(b).id, nearest.len });
        for (nearest.slice()) |id| try line(session.out, "  {s} {d} {d}", .{ graph.person(id).id, first[id], second[id] });
    }
    fn visitTree(session: *Session, id: usize, depth: usize, seen: *[200]bool) Error!void {
        const graph = session.graph;
        try session.out.splatByteAll(' ', 2 * (depth + 1));
        if (seen[id]) return line(session.out, "{s} (see above)", .{graph.person(id).id});
        seen[id] = true;
        const person = graph.person(id);
        try session.out.print("{s} {s} ", .{ person.id, person.name });
        try writeLife(session.out, person.*);
        if (graph.spouse(id)) |spouse| try session.out.print(" = {s}", .{graph.person(spouse).id});
        try session.out.writeByte('\n');
        const children = graph.family.ordered(graph.children[id], true);
        for (children.slice()) |child| try session.visitTree(child, depth + 1, seen);
    }
    fn enterPedigree(session: *Session, out: *Writer, id: usize, depth: usize, number: usize, generation: usize, seen: *[200]bool, entries: *usize) Error!void {
        const graph = session.graph;
        const person = graph.person(id);
        entries.* += 1;
        seen[id] = true;
        try out.splatByteAll(' ', 2 * (generation + 1));
        try out.print("{d} {s} {s} ", .{ number, person.id, person.name });
        try writeLife(out, person.*);
        try out.writeByte('\n');
        if (generation >= depth) return;
        var parents = person.parents;
        std.sort.heap(usize, parents.data[0..parents.len], graph.family, struct {
            fn less(family: *const Family, a: usize, b: usize) bool {
                const first = family.people[a].sex;
                const second = family.people[b].sex;
                return if (first != second) @backingInt(first) < @backingInt(second) else family.idLess(a, b);
            }
        }.less);
        for (parents.slice(), 0..) |parent, i| try session.enterPedigree(out, parent, depth, 2 * number + i, generation + 1, seen, entries);
    }
    const Event = struct { year: i32, rank: u8, other: Text = "", text: Text };
    fn lost(session: *Session, events: *std.ArrayList(Event), id: usize, relatives: []const usize, kind: Text) Error!void {
        const person = session.graph.person(id);
        for (relatives) |other| {
            const relative = session.graph.person(other);
            if (relative.death) |year| {
                if (year >= person.birth and year <= (person.death orelse year)) {
                    try events.append(session.gpa, .{
                        .year = year,
                        .rank = 5,
                        .other = relative.id,
                        .text = try std.fmt.allocPrint(session.gpa, "lost {s} {s}", .{ kind, relative.id }),
                    });
                }
            }
        }
    }
    fn timeline(session: *Session, id: usize) Error!void {
        const graph = session.graph;
        const person = graph.person(id);
        var events: std.ArrayList(Event) = .empty;
        try events.append(session.gpa, .{ .year = person.birth, .rank = 0, .text = "born" });
        for (graph.family.marriages[0..graph.family.marriage_count]) |marriage| if (marriage.contains(id)) {
            const other = graph.person(marriage.other(id)).id;
            try events.append(session.gpa, .{ .year = marriage.start, .rank = 1, .other = other, .text = try std.fmt.allocPrint(session.gpa, "married {s}", .{other}) });
            if (marriage.status == .divorced) {
                try events.append(session.gpa, .{ .year = marriage.end.?, .rank = 3, .other = other, .text = try std.fmt.allocPrint(session.gpa, "divorced {s}", .{other}) });
            } else if (marriage.status == .widowed and marriage.died == marriage.other(id)) {
                try events.append(session.gpa, .{ .year = marriage.end.?, .rank = 4, .other = other, .text = try std.fmt.allocPrint(session.gpa, "widowed {s}", .{other}) });
            }
        };
        for (graph.children[id].slice()) |child| {
            const other = graph.person(child);
            try events.append(session.gpa, .{ .year = other.birth, .rank = 2, .other = other.id, .text = try std.fmt.allocPrint(session.gpa, "child {s}", .{other.id}) });
        }
        try session.lost(&events, id, graph.parents(id), "parent");
        try session.lost(&events, id, graph.children[id].slice(), "child");
        if (person.death) |year| try events.append(session.gpa, .{ .year = year, .rank = 6, .text = "died" });
        std.sort.heap(Event, events.items, {}, struct {
            fn less(_: void, a: Event, b: Event) bool {
                if (a.year != b.year) return a.year < b.year;
                if (a.rank != b.rank) return a.rank < b.rank;
                return std.mem.order(u8, a.other, b.other) == .lt;
            }
        }.less);
        try line(session.out, "TIMELINE {s} {d}", .{ person.id, events.items.len });
        for (events.items) |event| try line(session.out, "  {d} {s}", .{ event.year, event.text });
    }
    fn census(session: *Session, year: i32) Error!void {
        const graph = session.graph;
        var residents: Selection = .{};
        for (graph.ids.slice()) |id| {
            const person = graph.person(id);
            if (person.birth <= year and (person.death orelse (year + 1)) > year) residents.add(id);
        }
        residents = graph.family.ordered(residents, true);
        try line(session.out, "CENSUS {d} {d}", .{ year, residents.len });
        for (residents.slice()) |id| {
            var latest: ?Marriage = null;
            for (graph.family.marriages[0..graph.family.marriage_count]) |marriage| {
                if (marriage.contains(id) and marriage.start <= year) latest = marriage;
            }
            try session.out.print("  {s} {d} ", .{ graph.person(id).id, year - graph.person(id).birth });
            if (latest) |marriage| {
                if ((marriage.end orelse (year + 1)) > year)
                    try session.out.print("married {s}", .{graph.person(marriage.other(id)).id})
                else
                    try session.out.writeAll(@tagName(marriage.status));
            } else try session.out.writeAll("single");
            try session.out.writeByte('\n');
        }
    }
    fn find(session: *Session, id: usize, route: Text) Error!void {
        const graph = session.graph;
        var found: Selection = .{};
        found.add(id);
        var steps = std.mem.splitScalar(u8, route, '.');
        while (steps.next()) |word| {
            const step = std.meta.stringToEnum(Step, word).?;
            const sex: ?Sex = switch (step) {
                .father, .son, .brother, .husband => .M,
                .mother, .daughter, .sister, .wife => .F,
                else => null,
            };
            var next: [200]bool = @splat(false);
            for (found.slice()) |current| {
                for (graph.ids.slice()) |other| {
                    if (sex) |required| if (graph.person(other).sex != required) continue;
                    const reachable = switch (step) {
                        .parent, .father, .mother => graph.person(current).parents.contains(other),
                        .child, .son, .daughter => graph.person(other).parents.contains(current),
                        .sibling, .brother, .sister => graph.siblings(current, other),
                        .spouse, .husband, .wife => graph.spouse(current) == other,
                    };
                    if (reachable) next[other] = true;
                }
            }
            found.len = 0;
            for (graph.ids.slice()) |other| if (next[other]) found.add(other);
        }
        found.remove(id);
        try line(session.out, "FIND {s} {s} {d}", .{ graph.person(id).id, route, found.len });
        for (found.slice()) |other| try line(session.out, "  {s}: {s}", .{ graph.person(other).id, try session.relation(other, id) });
    }
    fn execute(session: *Session, source: Text) Error!void {
        var words: [8]Text = undefined;
        var word_count: usize = 0;
        var tokens = std.mem.tokenizeScalar(u8, source, ' ');
        while (tokens.next()) |word| {
            words[word_count] = word;
            word_count += 1;
        }
        const args = words[0..word_count];
        const verb = std.meta.stringToEnum(Verb, args[0]).?;
        const graph = session.graph;
        const calculator = session.calculator;
        const family = &calculator.family;
        switch (verb) {
            .PERSON, .DEATH, .REMOVE, .PARENT, .UNPARENT, .SPOUSE, .DIVORCE => return session.modify(source, verb, args),
            .UNDO => {
                const saved = calculator.history.pop() orelse return session.fail("NOTHING TO UNDO", .{});
                family.* = saved.family.*;
                return line(session.out, "UNDONE {s}", .{saved.source});
            },
            .TERM => {
                try session.out.print("{s} ", .{source});
                try writeTerm(session.out, integer(args[1]), integer(args[2]), std.meta.stringToEnum(Sex, args[3]).?);
                return session.out.writeByte('\n');
            },
            .CENSUS => return session.census(integer(args[1])),
            .STATS => {
                const ordered = family.ordered(graph.ids, true);
                var lengths: [200]usize = @splat(0);
                var longest: usize = 0;
                var living: usize = 0;
                var links: usize = 0;
                var founders: usize = 0;
                var couples: usize = 0;
                for (ordered.slice()) |id| {
                    const person = graph.person(id);
                    var length: usize = 1;
                    for (person.parents.slice()) |parent| length = @max(length, lengths[parent] + 1);
                    lengths[id] = length;
                    longest = @max(longest, length);
                    links += person.parents.len;
                    if (person.parents.len == 0) founders += 1;
                    if (person.death == null) living += 1;
                }
                for (family.marriages[0..family.marriage_count]) |marriage| if (marriage.status == .current) {
                    couples += 1;
                };
                return line(session.out, "STATS persons={d} living={d} links={d} couples={d} founders={d} generations={d}", .{ graph.ids.len, living, links, couples, founders, longest });
            },
            .AUDIT => {
                var rows: std.ArrayList(Text) = .empty;
                for (family.marriages[0..family.marriage_count]) |marriage| {
                    if (graph.apex(marriage.first, marriage.second)) |apex| {
                        try rows.append(session.gpa, try std.fmt.allocPrint(session.gpa, "  marriage {s} {s} {s}", .{
                            graph.person(marriage.first).id,                           graph.person(marriage.second).id,
                            try session.blood(apex, graph.person(marriage.first).sex),
                        }));
                    }
                }
                for (graph.ids.slice()) |id| {
                    const value = graph.inbreeding(id);
                    if (value.numerator != 0) try rows.append(session.gpa, try std.fmt.allocPrint(session.gpa, "  inbred {s} {f}", .{ graph.person(id).id, value }));
                }
                try line(session.out, "AUDIT {d}", .{rows.items.len});
                for (rows.items) |row| try line(session.out, "{s}", .{row});
                return;
            },
            else => {},
        }
        const id = try session.check(args[1]);
        switch (verb) {
            .RELATION, .PATH, .COMMON, .KINSHIP => {
                const other = try session.check(args[2]);
                return switch (verb) {
                    .RELATION => line(session.out, "RELATION {s} {s}: {s}", .{ args[1], args[2], try session.relation(id, other) }),
                    .PATH => session.path(id, other),
                    .COMMON => session.common(id, other),
                    .KINSHIP => line(session.out, "KINSHIP {s} {s} {f}", .{ args[1], args[2], graph.phi(id, other) }),
                    else => unreachable,
                };
            },
            .INFO => return session.info(id),
            .TIMELINE => return session.timeline(id),
            .FIND => return session.find(id, args[2]),
            .TREE => {
                const distances = graph.distances(id, false);
                var count: usize = 0;
                for (graph.ids.slice()) |other| if (other != id and distances[other] >= 0) {
                    count += 1;
                };
                try line(session.out, "TREE {s} {d}", .{ args[1], count });
                var seen: [200]bool = @splat(false);
                return session.visitTree(id, 0, &seen);
            },
            .PEDIGREE => {
                var body: Writer.Allocating = .init(session.gpa);
                defer body.deinit();
                var seen: [200]bool = @splat(false);
                var entries: usize = 0;
                try session.enterPedigree(&body.writer, id, @intCast(integer(args[2])), 1, 0, &seen, &entries);
                var distinct: usize = 0;
                for (seen) |entered| if (entered) {
                    distinct += 1;
                };
                try line(session.out, "PEDIGREE {s} {s} entries={d} distinct={d}", .{ args[1], args[2], entries, distinct });
                return session.out.writeAll(body.written());
            },
            .RELATIVES, .WHO => {
                const query = if (verb == .WHO) try std.mem.join(session.gpa, " ", args[2..]) else "";
                var rows: std.ArrayList(Text) = .empty;
                for (graph.ids.slice()) |other| {
                    if (other == id) continue;
                    const actual = try session.relations(other, id, graph.person(other).sex);
                    var matched: ?Text = null;
                    if (verb == .RELATIVES) {
                        if (actual.len > 0) matched = try std.mem.join(session.gpa, ", ", actual);
                    } else {
                        const neutral = try session.relations(other, id, .X);
                        for (actual, neutral) |word, alternative| {
                            if (equal(word, query) or equal(alternative, query)) {
                                matched = word;
                                break;
                            }
                        }
                    }
                    if (matched) |word| try rows.append(session.gpa, try std.fmt.allocPrint(session.gpa, "  {s}: {s}", .{ graph.person(other).id, word }));
                }
                if (verb == .WHO) try line(session.out, "WHO {s} {s} {d}", .{ args[1], query, rows.items.len }) else try line(session.out, "RELATIVES {s} {d}", .{ args[1], rows.items.len });
                for (rows.items) |row| try line(session.out, "{s}", .{row});
                return;
            },
            .ANCESTORS, .DESCENDANTS => {
                const upward = verb == .ANCESTORS;
                const distances = graph.distances(id, upward);
                var selected: Selection = .{};
                for (graph.ids.slice()) |other| if (other != id and distances[other] >= 0) selected.add(other);
                const Context = struct {
                    family: *const Family,
                    distances: *const [200]i16,
                    fn less(context: @This(), a: usize, b: usize) bool {
                        return if (context.distances[a] != context.distances[b]) context.distances[a] < context.distances[b] else context.family.idLess(a, b);
                    }
                };
                std.sort.heap(usize, selected.data[0..selected.len], Context{ .family = family, .distances = distances }, Context.less);
                try line(session.out, "{s} {s} {d}", .{ @tagName(verb), args[1], selected.len });
                for (selected.slice()) |other| {
                    const generation = distances[other];
                    try session.out.print("  {d} {s} ", .{ generation, graph.person(other).id });
                    try writeTerm(session.out, if (upward) 0 else generation, if (upward) generation else 0, graph.person(other).sex);
                    try session.out.writeByte('\n');
                }
                return;
            },
            .COUSINS => {
                const Cousin = struct { id: usize, apex: Apex };
                var candidates: [200]Cousin = undefined;
                var count: usize = 0;
                const degree = integer(args[2]);
                for (graph.ids.slice()) |other| {
                    if (other == id) continue;
                    if (graph.apex(other, id)) |apex| {
                        if (apex.a >= 2 and apex.b >= 2 and @min(apex.a, apex.b) - 1 == degree) {
                            candidates[count] = .{ .id = other, .apex = apex };
                            count += 1;
                        }
                    }
                }
                std.sort.heap(Cousin, candidates[0..count], @as(*const Family, family), struct {
                    fn less(f: *const Family, a: Cousin, b: Cousin) bool {
                        const first = @abs(a.apex.a - a.apex.b);
                        const second = @abs(b.apex.a - b.apex.b);
                        return if (first != second) first < second else f.idLess(a.id, b.id);
                    }
                }.less);
                try line(session.out, "COUSINS {s} {d} {d}", .{ args[1], degree, count });
                for (candidates[0..count]) |cousin| try line(session.out, "  {s} {s}", .{
                    graph.person(cousin.id).id, try session.blood(cousin.apex, graph.person(cousin.id).sex),
                });
                return;
            },
            .GENERATIONS => {
                const Group = struct { count: usize = 0, living: usize = 0, minimum: i32 = 2026, maximum: i32 = 0 };
                var groups: [200]Group = @splat(.{});
                var count: usize = 0;
                const distances = graph.distances(id, false);
                for (graph.ids.slice()) |other| {
                    if (distances[other] <= 0) continue;
                    const group = &groups[@intCast(distances[other])];
                    const person = graph.person(other);
                    if (group.count == 0) count += 1;
                    group.count += 1;
                    if (person.death == null) group.living += 1;
                    group.minimum = @min(group.minimum, person.birth);
                    group.maximum = @max(group.maximum, person.birth);
                }
                try line(session.out, "GENERATIONS {s} {d}", .{ args[1], count });
                for (groups, 0..) |group, generation| if (group.count > 0)
                    try line(session.out, "  {d} {d} {d} {d}-{d}", .{ generation, group.count, group.living, group.minimum, group.maximum });
                return;
            },
            .SIBLINGS => {
                var rows: std.ArrayList(Text) = .empty;
                var order: usize = 1;
                const ordered = family.ordered(graph.ids, true);
                for (ordered.slice()) |other| {
                    if (other == id) continue;
                    const shared = graph.sharedParents(id, other);
                    const kind: Text = if (shared == 2) "full" else if (shared == 1) "half" else if (graph.stepSiblings(id, other)) "step" else continue;
                    if (shared > 0 and family.ageLess(other, id)) order += 1;
                    try rows.append(session.gpa, try std.fmt.allocPrint(session.gpa, "  {s} {s} {d}", .{ graph.person(other).id, kind, graph.person(other).birth }));
                }
                try line(session.out, "SIBLINGS {s} {d} order={d}", .{ args[1], rows.items.len, order });
                for (rows.items) |row| try line(session.out, "{s}", .{row});
                return;
            },
            else => unreachable,
        }
    }
};

fn readLine(reader: *std.Io.Reader, gpa: Allocator) !?Text {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = reader.streamDelimiterEnding(&buffer.writer, '\n') catch |err| switch (err) {
        error.EndOfStream => {
            if (buffer.written().len == 0) return null;
            return try buffer.toOwnedSlice();
        },
        else => return err,
    };
    reader.toss(1);
    return try buffer.toOwnedSlice();
}
pub fn main(init: std.process.Init) !void {
    var storage: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer storage.deinit();
    const persistent = storage.allocator();
    var calculator: Calculator = .{ .storage = persistent };
    var input_buffer: [4096]u8 = undefined;
    var output_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const first = std.mem.trim(u8, (try readLine(&input.interface, persistent)).?, "\r");
    const count = try std.fmt.parseInt(usize, first, 10);
    for (0..count) |_| {
        var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source = std.mem.trim(u8, (try readLine(&input.interface, gpa)).?, "\r");
        var response: Writer.Allocating = .init(gpa);
        defer response.deinit();
        var session: Session = .{
            .calculator = &calculator,
            .graph = try Analysis.create(gpa, &calculator.family),
            .gpa = gpa,
            .out = &response.writer,
        };
        session.execute(source) catch |err| switch (err) {
            error.Invalid => {
                try line(&output.interface, "ERROR {s}", .{session.problem});
                try output.interface.flush();
                continue;
            },
            else => return err,
        };
        try output.interface.writeAll(response.written());
        try output.interface.flush();
    }
}
