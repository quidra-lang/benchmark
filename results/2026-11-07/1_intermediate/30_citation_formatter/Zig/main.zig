const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Style = enum { APA, IEEE, CHICAGO, MLA };
const Kind = enum { article, book, inproceedings, incollection, techreport, phdthesis, misc };
const Command = enum { FORMAT, BIBLIOGRAPHY, CITE, KEYGEN, CHECK, SEARCH, EXPORT, STATS };
const Placeholder = enum {
    author,
    editor,
    title,
    journal,
    booktitle,
    edition,
    volume,
    number,
    pages,
    publisher,
    institution,
    school,
    address,
    howpublished,
    month,
    year,
    doi,
    note,
    pp,
    eds,
    mon,
};
const known_fields = [_][]const u8{
    "author",    "editor",      "title",  "journal", "booktitle",    "edition", "volume", "number", "pages",
    "publisher", "institution", "school", "address", "howpublished", "month",   "year",   "doi",    "note",
};
const small_words = [_][]const u8{
    "a",  "an", "and",  "as",  "at", "but", "by", "for", "from", "in",   "into", "nor", "of",
    "on", "or", "over", "per", "so", "the", "to", "up",  "via",  "with", "yet",
};
const months = [_][]const u8{
    "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December",
};
const month_short = [_][]const u8{ "Jan.", "Feb.", "Mar.", "Apr.", "May", "June", "July", "Aug.", "Sep.", "Oct.", "Nov.", "Dec." };

fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn less(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}
fn contains(values: []const []const u8, value: []const u8) bool {
    for (values) |item| if (equal(item, value)) return true;
    return false;
}
fn letter(c: u8) bool {
    return c >= 'A' and c <= 'Z' or c >= 'a' and c <= 'z';
}
fn digit(c: u8) bool {
    return c >= '0' and c <= '9';
}
fn lowercase(c: u8) bool {
    return c >= 'a' and c <= 'z';
}
fn uppercase(c: u8) bool {
    return c >= 'A' and c <= 'Z';
}
fn lowerByte(c: u8) u8 {
    return if (uppercase(c)) c + 32 else c;
}
fn upperByte(c: u8) u8 {
    return if (lowercase(c)) c - 32 else c;
}
fn digits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!digit(c)) return false;
    return true;
}
fn integer(text: []const u8) usize {
    return std.fmt.parseInt(usize, text, 10) catch unreachable;
}
fn join(gpa: Allocator, separator: []const u8, parts: []const []const u8) Allocator.Error![]const u8 {
    return std.mem.join(gpa, separator, parts);
}
fn format(gpa: Allocator, comptime pattern: []const u8, args: anytype) Allocator.Error![]const u8 {
    return std.fmt.allocPrint(gpa, pattern, args);
}
fn line(out: *Writer, comptime pattern: []const u8, args: anytype) Writer.Error!void {
    try out.print(pattern ++ "\n", args);
}

const Text = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,

    fn add(text: *Text, value: []const u8) Allocator.Error!void {
        try text.bytes.appendSlice(text.gpa, value);
    }
    fn byte(text: *Text, value: u8) Allocator.Error!void {
        try text.bytes.append(text.gpa, value);
    }
    fn result(text: Text) []const u8 {
        return text.bytes.items;
    }
};

fn lower(gpa: Allocator, text: []const u8) Allocator.Error![]const u8 {
    const result = try gpa.dupe(u8, text);
    for (result) |*c| c.* = lowerByte(c.*);
    return result;
}
fn plain(gpa: Allocator, text: []const u8) Allocator.Error![]const u8 {
    var result: Text = .{ .gpa = gpa };
    for (text) |c| if (c != '{' and c != '}') try result.byte(c);
    return result.result();
}
fn letters(gpa: Allocator, text: []const u8) Allocator.Error![]const u8 {
    var result: Text = .{ .gpa = gpa };
    for (text) |c| if (letter(c)) try result.byte(lowerByte(c));
    return result.result();
}
fn splitTop(gpa: Allocator, text: []const u8, separator: []const u8) Allocator.Error![][]const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    var depth: i32 = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        if (depth == 0 and std.mem.startsWith(u8, text[i..], separator)) {
            try parts.append(gpa, text[start..i]);
            i += separator.len;
            start = i;
            continue;
        }
        if (text[i] == '{') depth += 1;
        if (text[i] == '}') depth -= 1;
        i += 1;
    }
    try parts.append(gpa, text[start..]);
    return parts.items;
}
const Accent = struct { value: u8, length: usize };
fn accent(text: []const u8, i: usize) ?Accent {
    if (i + 1 >= text.len or text[i] != '\\') return null;
    const command = text[i + 1];
    if (command == '&') return .{ .value = '&', .length = 2 };
    const symbol = std.mem.findScalar(u8, "'\"`^~=.", command) != null;
    if (i + 4 < text.len and (symbol or std.mem.findScalar(u8, "cuvH", command) != null) and
        text[i + 2] == '{' and letter(text[i + 3]) and text[i + 4] == '}')
    {
        return .{ .value = text[i + 3], .length = 5 };
    }
    if (symbol and i + 2 < text.len and letter(text[i + 2])) return .{ .value = text[i + 2], .length = 3 };
    return null;
}
fn normalize(gpa: Allocator, text: []const u8) Allocator.Error![]const u8 {
    var result: Text = .{ .gpa = gpa };
    var pending_space = false;
    var i: usize = 0;
    while (i < text.len) {
        var value = text[i];
        var length: usize = 1;
        const wrapped = if (text[i] == '{') accent(text, i + 1) else null;
        if (wrapped != null and i + wrapped.?.length + 1 < text.len and text[i + wrapped.?.length + 1] == '}') {
            value = wrapped.?.value;
            length = wrapped.?.length + 2;
        } else if (accent(text, i)) |direct| {
            value = direct.value;
            length = direct.length;
        }
        i += length;
        if (value == '~' or value == ' ') {
            pending_space = result.result().len != 0;
        } else {
            if (pending_space) try result.byte(' ');
            pending_space = false;
            try result.byte(value);
        }
    }
    return result.result();
}
fn titleCase(gpa: Allocator, text: []const u8, style: Style) Allocator.Error![]const u8 {
    if (style == .IEEE) return text;
    if (style == .APA) {
        const result = try gpa.dupe(u8, text);
        var depth: i32 = 0;
        for (result, 0..) |*c, i| {
            if (c.* == '{') {
                depth += 1;
            } else if (c.* == '}') {
                depth -= 1;
            } else if (depth == 0 and letter(c.*)) {
                c.* = if (i == 0 or i >= 2 and text[i - 2] == ':' and text[i - 1] == ' ') upperByte(c.*) else lowerByte(c.*);
            }
        }
        return result;
    }
    const words = try splitTop(gpa, text, " ");
    for (words, 0..) |word, i| {
        if (word[0] == '{') continue;
        const make_lower = i > 0 and i + 1 < words.len and !std.mem.endsWith(u8, words[i - 1], ":") and
            contains(&small_words, try letters(gpa, word));
        const changed = try gpa.dupe(u8, word);
        var depth: i32 = 0;
        for (changed) |*c| {
            if (c.* == '{') {
                depth += 1;
            } else if (c.* == '}') {
                depth -= 1;
            } else if (letter(c.*)) {
                if (make_lower) {
                    if (depth == 0) c.* = lowerByte(c.*);
                } else {
                    if (depth == 0) c.* = upperByte(c.*);
                    break;
                }
            }
        }
        words[i] = changed;
    }
    return join(gpa, " ", words);
}
fn listNames(gpa: Allocator, names: []const []const u8, conjunction: []const u8, list_b: bool) Allocator.Error![]const u8 {
    if (names.len == 1) return names[0];
    if (list_b and names.len == 2) return join(gpa, " ", &.{ names[0], conjunction, names[1] });
    return format(gpa, "{s}, {s} {s}", .{ try join(gpa, ", ", names[0 .. names.len - 1]), conjunction, names[names.len - 1] });
}

const Person = struct {
    first: []const u8,
    von: []const u8,
    last: []const u8,
    jr: []const u8,

    fn parse(gpa: Allocator, text: []const u8) Allocator.Error!Person {
        const parts = try splitTop(gpa, text, ",");
        for (parts) |*part| part.* = std.mem.trim(u8, part.*, " ");
        const words = try splitTop(gpa, parts[0], " ");
        var first_lower: ?usize = null;
        var after_lower: usize = 0;
        for (words[0 .. words.len - 1], 0..) |word, i| {
            if (lowercase(word[0])) {
                if (first_lower == null) first_lower = i;
                after_lower = i + 1;
            }
        }
        if (parts.len == 1) {
            if (first_lower) |first| return .{
                .first = try join(gpa, " ", words[0..first]),
                .von = try join(gpa, " ", words[first..after_lower]),
                .last = try join(gpa, " ", words[after_lower..]),
                .jr = "",
            };
            return .{ .first = try join(gpa, " ", words[0 .. words.len - 1]), .von = "", .last = words[words.len - 1], .jr = "" };
        }
        return .{
            .first = parts[parts.len - 1],
            .von = try join(gpa, " ", words[0..after_lower]),
            .last = try join(gpa, " ", words[after_lower..]),
            .jr = if (parts.len == 3) parts[1] else "",
        };
    }
    fn same(a: Person, b: Person) bool {
        return equal(a.first, b.first) and equal(a.von, b.von) and equal(a.last, b.last) and equal(a.jr, b.jr);
    }
    fn surname(person: Person, gpa: Allocator) Allocator.Error![]const u8 {
        return plain(gpa, if (person.von.len == 0) person.last else try join(gpa, " ", &.{ person.von, person.last }));
    }
    fn initials(person: Person, gpa: Allocator) Allocator.Error![]const u8 {
        var result: Text = .{ .gpa = gpa };
        var words = std.mem.tokenizeScalar(u8, try plain(gpa, person.first), ' ');
        while (words.next()) |word| {
            if (result.result().len > 0) try result.byte(' ');
            var pieces = std.mem.splitScalar(u8, word, '-');
            var first = true;
            while (pieces.next()) |piece| {
                if (!first) try result.byte('-');
                first = false;
                for (piece) |c| {
                    if (letter(c)) {
                        try result.byte(upperByte(c));
                        try result.byte('.');
                        break;
                    }
                }
            }
        }
        return result.result();
    }
    fn notation(person: Person, gpa: Allocator, inverted: bool, use_initials: bool) Allocator.Error![]const u8 {
        const given = if (use_initials) try person.initials(gpa) else try plain(gpa, person.first);
        var result = try person.surname(gpa);
        if (person.first.len != 0) result = if (inverted)
            try join(gpa, ", ", &.{ result, given })
        else
            try join(gpa, " ", &.{ given, result });
        if (person.jr.len != 0) result = try join(gpa, ", ", &.{ result, try plain(gpa, person.jr) });
        return result;
    }
};
const NameList = struct {
    names: []const Person,
    et_al: bool,

    fn parse(gpa: Allocator, text: []const u8) Allocator.Error!NameList {
        const parts = try splitTop(gpa, text, " and ");
        const et_al = equal(parts[parts.len - 1], "others");
        const names = try gpa.alloc(Person, parts.len - @intFromBool(et_al));
        for (names, parts[0..names.len]) |*name, part| name.* = try Person.parse(gpa, part);
        return .{ .names = names, .et_al = et_al };
    }
    fn single(list: NameList) bool {
        return list.names.len == 1 and !list.et_al;
    }
    fn same(a: NameList, b: NameList) bool {
        if (a.et_al != b.et_al or a.names.len != b.names.len) return false;
        for (a.names, b.names) |left, right| if (!left.same(right)) return false;
        return true;
    }
    fn authors(list: NameList, gpa: Allocator, style: Style) Allocator.Error![]const u8 {
        const values = try gpa.alloc([]const u8, list.names.len);
        for (list.names, 0..) |name, i| values[i] = try name.notation(gpa, style == .APA or style != .IEEE and i == 0, style == .APA or style == .IEEE);
        return switch (style) {
            .APA => if (list.et_al) format(gpa, "{s}, et al.", .{try join(gpa, ", ", values)}) else if (values.len > 20) format(gpa, "{s}, . . . {s}", .{ try join(gpa, ", ", values[0..19]), values[values.len - 1] }) else listNames(gpa, values, "&", false),
            .IEEE => if (list.et_al or values.len >= 7) format(gpa, "{s} et al.", .{values[0]}) else listNames(gpa, values, "and", true),
            .CHICAGO => if (list.et_al or values.len >= 11) format(gpa, "{s}, et al.", .{try join(gpa, ", ", values[0..@min(7, values.len)])}) else listNames(gpa, values, "and", false),
            .MLA => if (list.et_al or values.len >= 3) format(gpa, "{s}, et al.", .{values[0]}) else listNames(gpa, values, "and", false),
        };
    }
    fn editors(list: NameList, gpa: Allocator, style: Style) Allocator.Error![]const u8 {
        const values = try gpa.alloc([]const u8, list.names.len);
        for (list.names, 0..) |name, i| values[i] = try name.notation(gpa, false, style == .APA or style == .IEEE);
        return if (list.et_al) format(gpa, "{s} et al.", .{values[0]}) else listNames(gpa, values, if (style == .APA) "&" else "and", true);
    }
};

const Field = struct { name: []const u8, raw: []const u8, value: []const u8 };
fn findField(fields: []const Field, name: []const u8) ?Field {
    for (fields) |field| if (equal(field.name, name)) return field;
    return null;
}
const Entry = struct {
    key: []const u8,
    kind: Kind,
    fields: []const Field,
    authors: ?NameList,
    editors: ?NameList,
    sort_last: []const u8,
    sort_title: []const u8,
    suffix: u8 = 0,

    fn primary(entry: Entry) NameList {
        return entry.authors orelse entry.editors.?;
    }
    fn has(entry: Entry, name: []const u8) bool {
        return findField(entry.fields, name) != null;
    }
    fn raw(entry: Entry, name: []const u8) []const u8 {
        return if (findField(entry.fields, name)) |field| field.raw else "";
    }
    fn value(entry: Entry, name: []const u8) []const u8 {
        return if (findField(entry.fields, name)) |field| field.value else "";
    }
    fn year(entry: Entry, gpa: Allocator, style: Style) Allocator.Error![]const u8 {
        return if ((style == .APA or style == .CHICAGO) and entry.suffix != 0)
            format(gpa, "{s}{c}", .{ entry.value("year"), entry.suffix })
        else
            entry.value("year");
    }
    fn keyLess(_: void, a: *Entry, b: *Entry) bool {
        return less({}, a.key, b.key);
    }
    fn titleLess(_: void, a: *Entry, b: *Entry) bool {
        const order = std.mem.order(u8, a.sort_title, b.sort_title);
        return if (order == .eq) keyLess({}, a, b) else order == .lt;
    }
    fn bibLess(_: void, a: *Entry, b: *Entry) bool {
        const left = [_][]const u8{ a.sort_last, a.value("year"), a.sort_title, a.key };
        const right = [_][]const u8{ b.sort_last, b.value("year"), b.sort_title, b.key };
        for (left, right) |x, y| {
            const order = std.mem.order(u8, x, y);
            if (order != .eq) return order == .lt;
        }
        return false;
    }
};
fn requiredFields(kind: Kind) []const []const u8 {
    return switch (kind) {
        .article => &.{ "author", "title", "journal", "year" },
        .book => &.{ "author", "title", "publisher", "year" },
        .inproceedings => &.{ "author", "title", "booktitle", "year" },
        .incollection => &.{ "author", "title", "booktitle", "publisher", "year" },
        .techreport => &.{ "author", "title", "institution", "year" },
        .phdthesis => &.{ "author", "title", "school", "year" },
        .misc => &.{ "author", "title", "year" },
    };
}
const Database = struct {
    gpa: Allocator,
    macros: std.StringHashMapUnmanaged([]const u8) = .empty,
    entries: std.ArrayList(*Entry) = .empty,
    by_key: std.StringHashMapUnmanaged(*Entry) = .empty,
    error_line: usize = 0,
    problem: []const u8 = "",

    fn fail(db: *Database, comptime pattern: []const u8, args: anytype) Error {
        db.problem = format(db.gpa, pattern, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn evaluate(db: *Database, expression: []const u8) Error![]const u8 {
        var depth: i32 = 0;
        for (expression) |c| {
            if (c == '{') depth += 1;
            if (c == '}') depth -= 1;
            if (depth < 0) return db.fail("unbalanced braces", .{});
        }
        if (depth != 0) return db.fail("unbalanced braces", .{});
        var result: Text = .{ .gpa = db.gpa };
        var terms = std.mem.splitSequence(u8, expression, " # ");
        while (terms.next()) |term| {
            if (term[0] == '{' or term[0] == '"') {
                try result.add(term[1 .. term.len - 1]);
            } else if (digit(term[0])) {
                try result.add(term);
            } else {
                try result.add(db.macros.get(term) orelse return db.fail("unknown macro '{s}'", .{term}));
            }
        }
        return result.result();
    }
    fn readMacro(db: *Database, text: []const u8, separator: usize, name: []const u8) Error!void {
        const value = try db.evaluate(text[separator + 3 .. text.len - 1]);
        if (db.macros.contains(name)) return db.fail("duplicate macro", .{});
        try db.macros.put(db.gpa, name, value);
    }
    fn readEntry(db: *Database, lines: []const []const u8, start: usize, end: usize, kind_text: []const u8, key: []const u8) Error!void {
        db.error_line = start + 1;
        const kind = std.meta.stringToEnum(Kind, kind_text) orelse return db.fail("unknown type '{s}'", .{kind_text});
        if (db.by_key.contains(key)) return db.fail("duplicate key", .{});
        var fields: std.ArrayList(Field) = .empty;
        for (start + 1..end) |i| {
            db.error_line = i + 1;
            const separator = std.mem.find(u8, lines[i], " = ").?;
            const name = lines[i][2..separator];
            var expression = lines[i][separator + 3 ..];
            if (std.mem.endsWith(u8, expression, ",")) expression = expression[0 .. expression.len - 1];
            const evaluated = try db.evaluate(expression);
            if (findField(fields.items, name) != null) return db.fail("duplicate field '{s}'", .{name});
            const normalized = try normalize(db.gpa, evaluated);
            try fields.append(db.gpa, .{ .name = name, .raw = normalized, .value = try plain(db.gpa, normalized) });
        }
        db.error_line = end + 1;
        for (requiredFields(kind)) |name| {
            if (findField(fields.items, name) == null and
                !(kind == .book and equal(name, "author") and findField(fields.items, "editor") != null))
                return db.fail("missing field '{s}'", .{name});
        }
        const authors: ?NameList = if (findField(fields.items, "author")) |field| try NameList.parse(db.gpa, field.raw) else null;
        const editors: ?NameList = if (findField(fields.items, "editor")) |field| try NameList.parse(db.gpa, field.raw) else null;
        const primary = authors orelse editors.?;
        var sort_title = try lower(db.gpa, findField(fields.items, "title").?.value);
        for ([_][]const u8{ "a ", "an ", "the " }) |prefix| {
            if (std.mem.startsWith(u8, sort_title, prefix)) {
                sort_title = sort_title[prefix.len..];
                break;
            }
        }
        const entry = try db.gpa.create(Entry);
        entry.* = .{
            .key = key,
            .kind = kind,
            .fields = fields.items,
            .authors = authors,
            .editors = editors,
            .sort_last = try lower(db.gpa, try plain(db.gpa, primary.names[0].last)),
            .sort_title = sort_title,
        };
        try db.entries.append(db.gpa, entry);
        try db.by_key.put(db.gpa, key, entry);
    }
    fn load(db: *Database, lines: []const []const u8, out: *Writer) Error!void {
        const month_keys = [_][]const u8{ "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" };
        for (month_keys, months) |key, value| try db.macros.put(db.gpa, key, value);
        var errors: usize = 0;
        var i: usize = 0;
        while (i < lines.len) : (i += 1) {
            const text = lines[i];
            if (text.len == 0 or text[0] == '%') continue;
            if (std.mem.startsWith(u8, text, "@string{")) {
                db.error_line = i + 1;
                const separator = std.mem.find(u8, text, " = ").?;
                const name = text[8..separator];
                db.readMacro(text, separator, name) catch |err| {
                    if (err != error.Invalid) return err;
                    errors += 1;
                    try line(out, "ERROR line {d}: {s}: {s}", .{ db.error_line, name, db.problem });
                };
            } else {
                var end = i + 1;
                while (!equal(lines[end], "}")) end += 1;
                const brace = std.mem.findScalar(u8, text, '{').?;
                const key = text[brace + 1 .. text.len - 1];
                db.readEntry(lines, i, end, text[1..brace], key) catch |err| {
                    if (err != error.Invalid) return err;
                    errors += 1;
                    try line(out, "ERROR line {d}: {s}: {s}", .{ db.error_line, key, db.problem });
                };
                i = end;
            }
        }
        try db.assignSuffixes();
        try line(out, "LOADED entries={d} macros={d} errors={d}", .{ db.entries.items.len, db.macros.count() - 12, errors });
    }
    fn assignSuffixes(db: *Database) Allocator.Error!void {
        for (db.entries.items) |entry| {
            if (entry.suffix != 0) continue;
            var group: std.ArrayList(*Entry) = .empty;
            for (db.entries.items) |other| {
                if (entry.primary().same(other.primary()) and equal(entry.raw("year"), other.raw("year"))) try group.append(db.gpa, other);
            }
            if (group.items.len < 2) continue;
            std.sort.heap(*Entry, group.items, {}, Entry.titleLess);
            for (group.items, 0..) |other, index| other.suffix = 'a' + @as(u8, @intCast(index));
        }
    }
};

const templates = [4][6][]const u8{
    .{
        "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
        "{author}. ({year}). {title}< ({edition})>. {publisher}.",
        "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
        "{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
        "{author}. ({year}). {title} [Doctoral dissertation, {school}].",
        "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>",
    },
    .{
        "{author}, \"{title},\" {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.",
        "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
        "{author}, \"{title},\" in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.",
        "{author}, \"{title},\" {institution}<, {address}>, Tech. Rep.< {number}>, {year}.",
        "{author}, \"{title},\" Ph.D. dissertation, {school}<, {address}>, {year}.",
        "{author}, \"{title},\"< {howpublished},> <{mon} >{year}.< {note}.>",
    },
    .{
        "{author}. {year}. \"{title}.\" {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>",
        "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
        "{author}. {year}. \"{title}.\" In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>",
        "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
        "{author}. {year}. \"{title}.\" PhD diss., {school}.",
        "{author}. {year}. {title}.< {howpublished}.>< {note}.>",
    },
    .{
        "{author}. \"{title}.\" {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>",
        "{author}. {title}.< {edition},> {publisher}, {year}.",
        "{author}. \"{title}.\" {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.",
        "{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
        "{author}. {title}. {year}. {school}, PhD dissertation.",
        "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>",
    },
};
const Part = union(enum) { literal: u8, field: Placeholder, optional: []const Part };
const Values = struct {
    items: [21][]const u8 = @splat(""),
    fn set(values: *Values, name: Placeholder, text: []const u8) void {
        values.items[@backingInt(name)] = text;
    }
    fn get(values: Values, name: Placeholder) []const u8 {
        return values.items[@backingInt(name)];
    }
};
const ReferenceFormatter = struct {
    parsed: [4][6][]const Part,

    fn init(gpa: Allocator) Allocator.Error!ReferenceFormatter {
        var result: ReferenceFormatter = undefined;
        for (templates, 0..) |style, i| {
            for (style, 0..) |template, j| {
                var position: usize = 0;
                result.parsed[i][j] = try parse(gpa, template, &position);
            }
        }
        return result;
    }
    fn parse(gpa: Allocator, text: []const u8, i: *usize) Allocator.Error![]const Part {
        var parts: std.ArrayList(Part) = .empty;
        while (i.* < text.len and text[i.*] != '>') {
            switch (text[i.*]) {
                '{' => {
                    const end = i.* + std.mem.findScalar(u8, text[i.*..], '}').?;
                    const name = std.meta.stringToEnum(Placeholder, text[i.* + 1 .. end]).?;
                    try parts.append(gpa, .{ .field = name });
                    i.* = end + 1;
                },
                '<' => {
                    i.* += 1;
                    try parts.append(gpa, .{ .optional = try parse(gpa, text, i) });
                    i.* += 1;
                },
                else => {
                    try parts.append(gpa, .{ .literal = text[i.*] });
                    i.* += 1;
                },
            }
        }
        return parts.items;
    }
    fn editorSuffix(entry: Entry, style: Style) []const u8 {
        if (entry.authors != null) return "";
        const single = entry.primary().single();
        return switch (style) {
            .APA => if (single) " (Ed.)" else " (Eds.)",
            .IEEE => if (single) ", Ed." else ", Eds.",
            .CHICAGO => if (single) ", ed." else ", eds.",
            .MLA => if (single) ", editor" else ", editors",
        };
    }
    fn edition(gpa: Allocator, text: []const u8) Allocator.Error![]const u8 {
        if (!digits(text)) return format(gpa, "{s} ed.", .{text});
        const number = integer(text);
        const suffix: []const u8 = if (number % 100 >= 11 and number % 100 <= 13) "th" else switch (number % 10) {
            1 => "st",
            2 => "nd",
            3 => "rd",
            else => "th",
        };
        return format(gpa, "{s}{s} ed.", .{ text, suffix });
    }
    fn values(gpa: Allocator, entry: Entry, style: Style, repeated: bool) Allocator.Error!Values {
        var result: Values = .{};
        for (known_fields) |name| result.set(std.meta.stringToEnum(Placeholder, name).?, entry.value(name));
        result.set(.author, try join(gpa, "", &.{ if (repeated) "---" else try entry.primary().authors(gpa, style), editorSuffix(entry, style) }));
        result.set(.editor, if (entry.editors) |names| try names.editors(gpa, style) else "");
        result.set(.eds, if (entry.editors) |names| if (names.single()) "Ed." else "Eds." else "");
        result.set(.title, try plain(gpa, try titleCase(gpa, entry.raw("title"), style)));
        result.set(.year, try entry.year(gpa, style));
        if (entry.has("pages")) {
            var pages: Text = .{ .gpa = gpa };
            const text = entry.value("pages");
            var i: usize = 0;
            while (i < text.len) {
                try pages.byte(text[i]);
                i += if (std.mem.startsWith(u8, text[i..], "--")) @as(usize, 2) else 1;
            }
            result.set(.pages, pages.result());
            result.set(.pp, try format(gpa, "{s} {s}", .{
                @as([]const u8, if (std.mem.findScalar(u8, pages.result(), '-') != null) "pp." else "p."), pages.result(),
            }));
        }
        if (entry.has("edition")) result.set(.edition, try edition(gpa, entry.value("edition")));
        const month = entry.value("month");
        result.set(.mon, month);
        for (months, month_short) |full, short| {
            if (equal(month, full)) {
                result.set(.mon, short);
                break;
            }
        }
        return result;
    }
    fn render(text: *Text, parts: []const Part, fields: Values) Allocator.Error!void {
        for (parts) |part| {
            switch (part) {
                .field => |name| try text.add(fields.get(name)),
                .optional => |children| {
                    var visible = true;
                    for (children) |child| {
                        const empty = switch (child) {
                            .field => |name| fields.get(name).len == 0,
                            else => false,
                        };
                        if (empty) {
                            visible = false;
                            break;
                        }
                    }
                    if (visible) try render(text, children, fields);
                },
                .literal => |c| {
                    const current = text.result();
                    if (c != '.' or current.len == 0 or std.mem.findScalar(u8, ".?!", current[current.len - 1]) == null) try text.byte(c);
                },
            }
        }
    }
    fn reference(formatter: ReferenceFormatter, gpa: Allocator, entry: Entry, style: Style, number: usize, repeated: bool) Allocator.Error![]const u8 {
        var result: Text = .{ .gpa = gpa };
        if (style == .IEEE) try result.add(try format(gpa, "[{d}] ", .{number}));
        const kind: usize = switch (entry.kind) {
            .article => 0,
            .book => 1,
            .inproceedings, .incollection => 2,
            .techreport => 3,
            .phdthesis => 4,
            .misc => 5,
        };
        try render(&result, formatter.parsed[@backingInt(style)][kind], try values(gpa, entry, style, repeated));
        return result.result();
    }
};

const CitationKind = enum { cite, citep, citet, citeauthor, citeyear };
const Citation = struct { start: usize, end: usize, kind: CitationKind, entries: []*Entry };
const Manager = struct {
    db: *Database,
    formatter: ReferenceFormatter,
    record: std.ArrayList(*Entry) = .empty,

    fn recorded(manager: Manager, entry: *Entry) bool {
        for (manager.record.items) |other| if (other == entry) return true;
        return false;
    }
    fn ieeeOrder(manager: Manager, gpa: Allocator) Allocator.Error![]*Entry {
        var order: std.ArrayList(*Entry) = .empty;
        try order.appendSlice(gpa, manager.record.items);
        for (manager.db.entries.items) |entry| if (!manager.recorded(entry)) try order.append(gpa, entry);
        std.sort.heap(*Entry, order.items[manager.record.items.len..], {}, Entry.keyLess);
        return order.items;
    }
};
fn ieeeNumber(order: []const *Entry, entry: *Entry) usize {
    for (order, 0..) |other, i| if (other == entry) return i + 1;
    unreachable;
}
fn shortName(gpa: Allocator, entry: Entry, style: Style, parenthetical: bool) Allocator.Error![]const u8 {
    const primary = entry.primary();
    const first = try primary.names[0].surname(gpa);
    if (primary.et_al or primary.names.len >= @as(usize, if (style == .CHICAGO) 4 else 3)) return format(gpa, "{s} et al.", .{first});
    return switch (primary.names.len) {
        1 => first,
        2 => join(gpa, " ", &.{ first, if (style == .APA and parenthetical) "&" else "and", try primary.names[1].surname(gpa) }),
        3 => format(gpa, "{s}, {s}, and {s}", .{ first, try primary.names[1].surname(gpa), try primary.names[2].surname(gpa) }),
        else => unreachable,
    };
}
fn numberLess(_: void, a: usize, b: usize) bool {
    return a < b;
}
fn numberRanges(gpa: Allocator, numbers: []usize) Allocator.Error![]const u8 {
    std.sort.heap(usize, numbers, {}, numberLess);
    var parts: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < numbers.len) {
        var end = i;
        while (end + 1 < numbers.len and numbers[end + 1] == numbers[end] + 1) end += 1;
        if (end - i >= 2) {
            try parts.append(gpa, try format(gpa, "[{d}]-[{d}]", .{ numbers[i], numbers[end] }));
        } else {
            for (numbers[i .. end + 1]) |number| try parts.append(gpa, try format(gpa, "[{d}]", .{number}));
        }
        i = end + 1;
    }
    return join(gpa, ", ", parts.items);
}
fn citationText(gpa: Allocator, citation: Citation, style: Style, order: []const *Entry) Allocator.Error![]const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    if (citation.kind == .citeauthor or citation.kind == .citeyear) {
        for (citation.entries) |entry| try parts.append(gpa, if (citation.kind == .citeauthor)
            try shortName(gpa, entry.*, style, false)
        else
            try entry.year(gpa, style));
        return join(gpa, if (citation.kind == .citeauthor) "; " else ", ", parts.items);
    }
    const parenthetical = citation.kind != .citet;
    if (style == .IEEE) {
        if (parenthetical) {
            const numbers = try gpa.alloc(usize, citation.entries.len);
            for (citation.entries, 0..) |entry, i| numbers[i] = ieeeNumber(order, entry);
            return numberRanges(gpa, numbers);
        }
        for (citation.entries) |entry| try parts.append(gpa, try format(gpa, "{s} [{d}]", .{
            try shortName(gpa, entry.*, style, false), ieeeNumber(order, entry),
        }));
        return join(gpa, "; ", parts.items);
    }
    if (style == .MLA) {
        for (citation.entries) |entry| try parts.append(gpa, try shortName(gpa, entry.*, style, parenthetical));
        const text = try join(gpa, "; ", parts.items);
        return if (parenthetical) format(gpa, "({s})", .{text}) else text;
    }
    const entries = try gpa.dupe(*Entry, citation.entries);
    if (parenthetical) std.sort.heap(*Entry, entries, {}, Entry.bibLess);
    var i: usize = 0;
    while (i < entries.len) {
        const name = try shortName(gpa, entries[i].*, style, parenthetical);
        var end = i + 1;
        while (end < entries.len and equal(name, try shortName(gpa, entries[end].*, style, parenthetical))) end += 1;
        var years: std.ArrayList([]const u8) = .empty;
        for (entries[i..end]) |entry| try years.append(gpa, try entry.year(gpa, style));
        const year_text = try join(gpa, ", ", years.items);
        try parts.append(gpa, if (parenthetical)
            try format(gpa, "{s}{s}{s}", .{ name, @as([]const u8, if (style == .APA) ", " else " "), year_text })
        else
            try format(gpa, "{s} ({s})", .{ name, year_text }));
        i = end;
    }
    const text = try join(gpa, "; ", parts.items);
    return if (parenthetical) format(gpa, "({s})", .{text}) else text;
}

fn unknownFields(gpa: Allocator, entry: Entry) Allocator.Error![][]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (entry.fields) |field| if (!contains(&known_fields, field.name)) try names.append(gpa, field.name);
    std.sort.heap([]const u8, names.items, {}, less);
    return names.items;
}
fn baseKey(gpa: Allocator, entry: Entry) Allocator.Error![]const u8 {
    var result: Text = .{ .gpa = gpa };
    try result.add(try letters(gpa, try plain(gpa, entry.primary().names[0].last)));
    for (entry.raw("year")) |c| if (digit(c)) try result.byte(c);
    var words = std.mem.splitScalar(u8, entry.value("title"), ' ');
    while (words.next()) |word| {
        const candidate = try letters(gpa, word);
        if (candidate.len != 0 and !contains(&small_words, candidate)) {
            try result.add(candidate);
            break;
        }
    }
    return result.result();
}
const Counts = std.StringHashMapUnmanaged(usize);
fn countValue(gpa: Allocator, counts: *Counts, key: []const u8) Allocator.Error!void {
    try counts.put(gpa, key, (counts.get(key) orelse 0) + 1);
}
fn printCounts(gpa: Allocator, out: *Writer, label: []const u8, counts: Counts) Error!void {
    var keys: std.ArrayList([]const u8) = .empty;
    var iterator = counts.keyIterator();
    while (iterator.next()) |key| try keys.append(gpa, key.*);
    std.sort.heap([]const u8, keys.items, {}, less);
    for (keys.items) |key| try line(out, "{s} {s} {d}", .{ label, key, counts.get(key).? });
}
const Session = struct {
    gpa: Allocator,
    manager: *Manager,
    out: *Writer,
    problem: []const u8 = "",
    warning_count: usize = 0,

    fn fail(session: *Session, comptime pattern: []const u8, args: anytype) Error {
        session.problem = format(session.gpa, pattern, args) catch return error.OutOfMemory;
        return error.Invalid;
    }
    fn lookup(session: *Session, key: []const u8) Error!*Entry {
        return session.manager.db.by_key.get(key) orelse return session.fail("unknown key '{s}'", .{key});
    }
    fn cite(session: *Session, text: []const u8, style: Style) Error!void {
        var citations: std.ArrayList(Citation) = .empty;
        var position: usize = 0;
        while (std.mem.findScalar(u8, text[position..], '\\')) |offset| {
            const start = position + offset;
            const brace = start + std.mem.findScalar(u8, text[start..], '{').?;
            const end = brace + std.mem.findScalar(u8, text[brace..], '}').?;
            var entries: std.ArrayList(*Entry) = .empty;
            var keys = std.mem.splitScalar(u8, text[brace + 1 .. end], ',');
            while (keys.next()) |key| {
                const entry = try session.lookup(key);
                var seen = false;
                for (entries.items) |other| {
                    if (other == entry) {
                        seen = true;
                        break;
                    }
                }
                if (!seen) try entries.append(session.gpa, entry);
            }
            try citations.append(session.gpa, .{
                .start = start,
                .end = end + 1,
                .kind = std.meta.stringToEnum(CitationKind, text[start + 1 .. brace]).?,
                .entries = entries.items,
            });
            position = end + 1;
        }
        for (citations.items) |citation| {
            for (citation.entries) |entry| {
                if (!session.manager.recorded(entry)) try session.manager.record.append(session.manager.db.gpa, entry);
            }
        }
        const order = try session.manager.ieeeOrder(session.gpa);
        position = 0;
        for (citations.items) |citation| {
            try session.out.writeAll(text[position..citation.start]);
            try session.out.writeAll(try citationText(session.gpa, citation, style, order));
            position = citation.end;
        }
        try line(session.out, "{s}", .{text[position..]});
    }
    fn keygen(session: *Session) Error!void {
        const entries = session.manager.db.entries.items;
        const bases = try session.gpa.alloc([]const u8, entries.len);
        for (entries, 0..) |entry, i| bases[i] = try baseKey(session.gpa, entry.*);
        for (entries, 0..) |entry, i| {
            var count: usize = 0;
            var ordinal: usize = 0;
            for (bases, 0..) |base, j| {
                if (equal(base, bases[i])) {
                    count += 1;
                    if (j < i) ordinal += 1;
                }
            }
            try session.out.print("{s} -> {s}", .{ entry.key, bases[i] });
            if (count > 1) try session.out.writeByte('a' + @as(u8, @intCast(ordinal)));
            try session.out.writeByte('\n');
        }
    }
    fn warn(session: *Session, key: []const u8, comptime pattern: []const u8, args: anytype) Writer.Error!void {
        session.warning_count += 1;
        try session.out.print("WARN {s}: ", .{key});
        try line(session.out, pattern, args);
    }
    fn check(session: *Session) Error!void {
        var titles: std.StringHashMapUnmanaged([]const u8) = .empty;
        for (session.manager.db.entries.items) |entry| {
            if (entry.has("pages")) {
                const pages = entry.value("pages");
                if (std.mem.findScalar(u8, pages, '-') != null and std.mem.find(u8, pages, "--") == null)
                    try session.warn(entry.key, "pages use a single hyphen", .{});
                var parts: std.ArrayList([]const u8) = .empty;
                var tokens = std.mem.tokenizeScalar(u8, pages, '-');
                while (tokens.next()) |part| try parts.append(session.gpa, part);
                if (parts.items.len == 2 and digits(parts.items[0]) and digits(parts.items[1]) and integer(parts.items[0]) > integer(parts.items[1]))
                    try session.warn(entry.key, "pages are reversed", .{});
            }
            const year = entry.value("year");
            if (year.len != 4 or !digits(year)) try session.warn(entry.key, "year is not 4 digits", .{});
            const title = entry.value("title");
            var has_lower = false;
            var upper_count: usize = 0;
            for (title) |c| {
                if (lowercase(c)) has_lower = true;
                if (uppercase(c)) upper_count += 1;
            }
            if (!has_lower and upper_count >= 2) try session.warn(entry.key, "title is all caps", .{});
            if (entry.kind == .article and !entry.has("doi")) try session.warn(entry.key, "article has no doi", .{});
            const lowered = try lower(session.gpa, title);
            if (titles.get(lowered)) |first| {
                try session.warn(entry.key, "same title as {s}", .{first});
            } else {
                try titles.put(session.gpa, lowered, entry.key);
            }
            for (try unknownFields(session.gpa, entry.*)) |name| try session.warn(entry.key, "unknown field '{s}'", .{name});
        }
        try line(session.out, "CHECK warnings={d}", .{session.warning_count});
    }
    fn exportEntry(session: *Session, entry: Entry) Error!void {
        var names: std.ArrayList([]const u8) = .empty;
        for (known_fields) |name| if (entry.has(name)) try names.append(session.gpa, name);
        try names.appendSlice(session.gpa, try unknownFields(session.gpa, entry));
        try line(session.out, "@{s}{{{s},", .{ @tagName(entry.kind), entry.key });
        for (names.items, 0..) |name, i| try line(session.out, "  {s} = {{{s}}}{s}", .{
            name, entry.raw(name), @as([]const u8, if (i + 1 < names.items.len) "," else ""),
        });
        try line(session.out, "}}", .{});
    }
    fn stats(session: *Session) Error!void {
        const Pair = struct { first: usize, second: usize };
        var types: Counts = .empty;
        var years: Counts = .empty;
        var authors: Counts = .empty;
        var author_names: std.ArrayList([]const u8) = .empty;
        var pairs: std.AutoHashMapUnmanaged(Pair, usize) = .empty;
        for (session.manager.db.entries.items) |entry| {
            try countValue(session.gpa, &types, @tagName(entry.kind));
            try countValue(session.gpa, &years, entry.value("year"));
            const list = entry.authors orelse continue;
            const names = try session.gpa.alloc([]const u8, list.names.len);
            for (list.names, 0..) |name, i| names[i] = try name.notation(session.gpa, false, false);
            std.sort.heap([]const u8, names, {}, less);
            var unique: std.ArrayList(usize) = .empty;
            for (names, 0..) |name, i| {
                if (i > 0 and equal(names[i - 1], name)) continue;
                const id = authors.get(name) orelse blk: {
                    const next = author_names.items.len;
                    try authors.put(session.gpa, name, next);
                    try author_names.append(session.gpa, name);
                    break :blk next;
                };
                try unique.append(session.gpa, id);
            }
            for (unique.items, 0..) |a, i| {
                for (unique.items[i + 1 ..]) |b| {
                    const pair: Pair = .{ .first = a, .second = b };
                    try pairs.put(session.gpa, pair, (pairs.get(pair) orelse 0) + 1);
                }
            }
        }
        try line(session.out, "ENTRIES {d}", .{session.manager.db.entries.items.len});
        try printCounts(session.gpa, session.out, "TYPE", types);
        try printCounts(session.gpa, session.out, "YEAR", years);
        try line(session.out, "AUTHORS {d}", .{author_names.items.len});
        var best: ?Pair = null;
        var best_count: usize = 0;
        var iterator = pairs.iterator();
        while (iterator.next()) |item| {
            const pair = item.key_ptr.*;
            const count = item.value_ptr.*;
            var take = count > best_count;
            if (count == best_count and best != null) {
                const first_order = std.mem.order(u8, author_names.items[pair.first], author_names.items[best.?.first]);
                take = first_order == .lt or first_order == .eq and less({}, author_names.items[pair.second], author_names.items[best.?.second]);
            }
            if (take) {
                best = pair;
                best_count = count;
            }
        }
        if (best) |pair| {
            try line(session.out, "PAIR {s} & {s} {d}", .{ author_names.items[pair.first], author_names.items[pair.second], best_count });
        } else {
            try line(session.out, "PAIR none", .{});
        }
    }
    fn execute(session: *Session, text: []const u8) Error!void {
        const first_space = std.mem.findScalar(u8, text, ' ');
        const command_text = text[0 .. first_space orelse text.len];
        const command = std.meta.stringToEnum(Command, command_text) orelse return session.fail("unknown command '{s}'", .{command_text});
        var words: std.ArrayList([]const u8) = .empty;
        if ((command == .CITE or command == .SEARCH) and first_space != null) {
            const first = first_space.?;
            try words.append(session.gpa, command_text);
            if (std.mem.findScalar(u8, text[first + 1 ..], ' ')) |offset| {
                const second = first + 1 + offset;
                try words.append(session.gpa, text[first + 1 .. second]);
                try words.append(session.gpa, text[second + 1 ..]);
            } else {
                try words.append(session.gpa, text[first + 1 ..]);
            }
        } else {
            var tokens = std.mem.splitScalar(u8, text, ' ');
            while (tokens.next()) |word| try words.append(session.gpa, word);
        }
        const expected: usize = switch (command) {
            .FORMAT, .CITE, .SEARCH => 2,
            .BIBLIOGRAPHY, .EXPORT => 1,
            .KEYGEN, .CHECK, .STATS => 0,
        };
        const arguments = words.items[1..];
        if (if (command == .FORMAT) arguments.len < expected else arguments.len != expected)
            return session.fail("wrong number of arguments", .{});
        var style: Style = .APA;
        if (command == .FORMAT or command == .BIBLIOGRAPHY or command == .CITE)
            style = std.meta.stringToEnum(Style, arguments[0]) orelse return session.fail("unknown style '{s}'", .{arguments[0]});
        const manager = session.manager;
        switch (command) {
            .FORMAT => {
                const order = try manager.ieeeOrder(session.gpa);
                for (arguments[1..]) |key| {
                    if (manager.db.by_key.get(key)) |entry| {
                        try line(session.out, "{s}", .{try manager.formatter.reference(session.gpa, entry.*, style, ieeeNumber(order, entry), false)});
                    } else {
                        try line(session.out, "ERROR unknown key '{s}'", .{key});
                    }
                }
            },
            .BIBLIOGRAPHY => {
                try line(session.out, "{s}", .{@as([]const u8, if (style == .MLA) "Works Cited" else "References")});
                const ieee_order = try manager.ieeeOrder(session.gpa);
                const order = try session.gpa.dupe(*Entry, ieee_order);
                if (style != .IEEE) std.sort.heap(*Entry, order, {}, Entry.bibLess);
                var previous: ?NameList = null;
                for (order) |entry| {
                    const repeated = (style == .CHICAGO or style == .MLA) and previous != null and previous.?.same(entry.primary());
                    try line(session.out, "{s}", .{try manager.formatter.reference(session.gpa, entry.*, style, ieeeNumber(ieee_order, entry), repeated)});
                    previous = entry.primary();
                }
            },
            .CITE => try session.cite(arguments[1], style),
            .KEYGEN => try session.keygen(),
            .CHECK => try session.check(),
            .SEARCH => {
                const needle = try lower(session.gpa, arguments[1]);
                var matches: std.ArrayList([]const u8) = .empty;
                for (manager.db.entries.items) |entry| {
                    if (entry.has(arguments[0]) and std.mem.find(u8, try lower(session.gpa, entry.value(arguments[0])), needle) != null)
                        try matches.append(session.gpa, entry.key);
                }
                if (matches.items.len == 0) {
                    try line(session.out, "MATCHES 0", .{});
                } else {
                    try line(session.out, "MATCHES {d}: {s}", .{ matches.items.len, try join(session.gpa, " ", matches.items) });
                }
            },
            .EXPORT => try session.exportEntry((try session.lookup(arguments[0])).*),
            .STATS => try session.stats(),
        }
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
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var database_lines: std.ArrayList([]const u8) = .empty;
    while (true) {
        const text = try readLine(gpa, &input.interface);
        if (equal(text, "%%")) break;
        try database_lines.append(gpa, text);
    }
    var database: Database = .{ .gpa = gpa };
    try database.load(database_lines.items, &output.interface);
    var manager: Manager = .{ .db = &database, .formatter = try ReferenceFormatter.init(gpa) };
    const count = integer(try readLine(gpa, &input.interface));
    for (0..count) |_| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const command_gpa = scratch.allocator();
        const text = try readLine(command_gpa, &input.interface);
        var response: Writer.Allocating = .init(command_gpa);
        defer response.deinit();
        var session: Session = .{ .gpa = command_gpa, .manager = &manager, .out = &response.writer };
        session.execute(text) catch |err| {
            if (err != error.Invalid) return err;
            try line(&output.interface, "ERROR {s}", .{session.problem});
            continue;
        };
        try output.interface.writeAll(response.written());
    }
    try output.interface.flush();
}
