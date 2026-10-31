const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const CommandError = error{
    MissingDelimiter,
    BadAddress,
    UnknownCommand,
    InvalidSuffix,
    InvalidMark,
    InvalidDestination,
    InvalidGlobalCommand,
    InvalidFileName,
    UnexpectedAddress,
    TooManyAddresses,
    AddressOutOfRange,
    InvalidRange,
    NoMatch,
    NoPreviousPattern,
    NoPreviousSubstitution,
    MarkNotSet,
    NothingToUndo,
    NothingToRedo,
    NothingToPut,
    NoSuchFile,
    LineTooLong,
    BadLine,
    BufferFull,
};
const ParseError = CommandError || Allocator.Error;
const Error = ParseError || Writer.Error;
const ElementKind = enum { number, offset, current, last, mark, forward, backward, separator, all };
const Kind = enum {
    empty,
    append,
    insert,
    change,
    print,
    numbered,
    listed,
    number,
    count,
    yank,
    marks,
    history,
    files,
    delete,
    put,
    join,
    join_spaced,
    window,
    indent,
    unindent,
    undo,
    redo,
    change_case,
    read,
    write,
    write_append,
    edit,
    write_print,
    mark,
    move,
    copy,
    sort,
    substitute,
    global,
    inverse_global,

    fn noAddress(kind: Kind) bool {
        return switch (kind) {
            .undo, .redo, .history, .marks, .files, .edit => true,
            else => false,
        };
    }
    fn oneAddress(kind: Kind) bool {
        return switch (kind) {
            .append, .insert, .put, .number, .read, .mark, .window => true,
            else => false,
        };
    }
};
const Element = struct { kind: ElementKind, value: i64 = 0, symbol: u8 = 0, text: []const u8 = "" };
const Address = struct {
    left: []const Element,
    right: ?[]const Element = null,
    separator: u8 = 0,
    fn count(address: Address) usize {
        return if (address.right != null) 2 else if (address.left.len == 0) 0 else 1;
    }
};
const Delimited = struct { text: []const u8, replacement: []const ?u8, raw: []const u8 };
const Command = struct {
    kind: Kind,
    count: usize = 0,
    suffix: u8 = 0,
    case_mode: u8 = 0,
    name: []const u8 = "",
    pattern: []const u8 = "",
    replacement: ?[]const ?u8 = null,
    all: bool = false,
    options: []const u8 = "",
    destination: []const Element = &.{},
    subcommand: ?*const Command = null,
    fn modifies(command: Command) bool {
        return switch (command.kind) {
            .append, .insert, .change, .delete, .put, .join, .join_spaced, .move, .copy, .substitute, .indent, .unindent, .change_case, .sort, .read, .edit => true,
            .global, .inverse_global => command.subcommand.?.modifies(),
            else => false,
        };
    }
};

fn equal(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn digit(c: u8) bool {
    return c >= '0' and c <= '9';
}
fn digits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!digit(c)) return false;
    return true;
}
fn number(text: []const u8) usize {
    return std.fmt.parseInt(usize, text, 10) catch unreachable;
}
fn printSuffix(c: u8) bool {
    return c == 'p' or c == 'n' or c == 'l';
}
fn sortForm(text: []const u8) bool {
    return equal(text, "sort") or std.mem.startsWith(u8, text, "sort ");
}
fn line(out: *Writer, comptime format: []const u8, args: anytype) Writer.Error!void {
    try out.print(format ++ "\n", args);
}

const Parser = struct {
    gpa: Allocator,
    text: []const u8,
    position: usize = 0,

    fn delimited(parser: *Parser, delimiter: u8) ParseError!Delimited {
        const start = parser.position;
        var text: std.ArrayList(u8) = .empty;
        var replacement: std.ArrayList(?u8) = .empty;
        while (parser.position < parser.text.len) {
            var c = parser.text[parser.position];
            parser.position += 1;
            if (c == delimiter) return .{
                .text = try text.toOwnedSlice(parser.gpa),
                .replacement = try replacement.toOwnedSlice(parser.gpa),
                .raw = parser.text[start .. parser.position - 1],
            };
            const escaped = c == '\\';
            if (escaped) {
                if (parser.position == parser.text.len) break;
                c = parser.text[parser.position];
                parser.position += 1;
            }
            try text.append(parser.gpa, c);
            try replacement.append(parser.gpa, if (c == '&' and !escaped) null else c);
        }
        return error.MissingDelimiter;
    }

    fn scan(parser: *Parser) ParseError![]const Element {
        var elements: std.ArrayList(Element) = .empty;
        while (parser.position < parser.text.len) {
            const c = parser.text[parser.position];
            var element: Element = undefined;
            if (digit(c)) {
                const start = parser.position;
                while (parser.position < parser.text.len and digit(parser.text[parser.position])) parser.position += 1;
                element = .{ .kind = .number, .value = @intCast(number(parser.text[start..parser.position])) };
            } else if (c == '+' or c == '-') {
                parser.position += 1;
                const start = parser.position;
                while (parser.position < parser.text.len and digit(parser.text[parser.position])) parser.position += 1;
                const value: i64 = if (start == parser.position) 1 else @intCast(number(parser.text[start..parser.position]));
                element = .{ .kind = .offset, .value = if (c == '+') value else -value };
            } else if (c == '\'') {
                parser.position += 1;
                const name: u8 = if (parser.position == parser.text.len) 0 else parser.text[parser.position];
                if (parser.position < parser.text.len) parser.position += 1;
                element = .{ .kind = .mark, .symbol = name };
            } else if (c == '/' or c == '?') {
                parser.position += 1;
                element = .{ .kind = if (c == '/') .forward else .backward, .text = (try parser.delimited(c)).text };
            } else {
                const kind: ElementKind = switch (c) {
                    '.' => .current,
                    '$' => .last,
                    ',', ';' => .separator,
                    '%' => .all,
                    else => break,
                };
                element = .{ .kind = kind, .symbol = c };
                parser.position += 1;
            }
            try elements.append(parser.gpa, element);
        }
        return try elements.toOwnedSlice(parser.gpa);
    }
};

fn expression(elements: []const Element) bool {
    for (elements, 0..) |element, i| {
        if (element.kind == .offset) continue;
        if (i != 0 or element.kind == .separator or element.kind == .all) return false;
    }
    return true;
}

fn addressForm(elements: []const Element) CommandError!Address {
    if (elements.len == 1 and elements[0].kind == .all)
        return .{ .left = &.{.{ .kind = .number, .value = 1 }}, .right = &.{.{ .kind = .last }}, .separator = ',' };
    var separator: ?usize = null;
    for (elements, 0..) |element, i| if (element.kind == .separator) {
        if (separator != null) return error.BadAddress;
        separator = i;
    };
    if (separator) |position| {
        const left = elements[0..position];
        const right = elements[position + 1 ..];
        if (!expression(left) or !expression(right)) return error.BadAddress;
        return .{ .left = left, .right = right, .separator = elements[position].symbol };
    }
    if (!expression(elements)) return error.BadAddress;
    return .{ .left = elements };
}

fn optionalCount(argument: []const u8) CommandError!usize {
    if (argument.len == 0) return 0;
    if (!digits(argument) or number(argument) == 0) return error.InvalidSuffix;
    return number(argument);
}
fn suffix(argument: []const u8) CommandError!u8 {
    if (argument.len == 0) return 0;
    if (argument.len != 1 or !printSuffix(argument[0])) return error.InvalidSuffix;
    return argument[0];
}
fn fileName(argument: []const u8) CommandError![]const u8 {
    if (argument.len < 2 or argument.len > 9 or argument[0] != ' ') return error.InvalidFileName;
    for (argument[1..]) |c| if (!(c >= 'a' and c <= 'z') and !digit(c)) return error.InvalidFileName;
    return argument[1..];
}

fn substitution(gpa: Allocator, argument: []const u8) ParseError!Command {
    var command: Command = .{ .kind = .substitute, .count = 1 };
    var repeated = true;
    for (argument) |c| if (c != 'g' and !printSuffix(c) and !digit(c)) {
        repeated = false;
        break;
    };
    var flags = argument;
    if (!repeated) {
        const delimiter = argument[0];
        if (delimiter == ' ' or delimiter == '\\') return error.MissingDelimiter;
        var parser: Parser = .{ .gpa = gpa, .text = argument, .position = 1 };
        command.pattern = (try parser.delimited(delimiter)).text;
        const replacement = try parser.delimited(delimiter);
        if (!equal(replacement.raw, "%")) command.replacement = replacement.replacement;
        flags = argument[parser.position..];
    }
    var has_count = false;
    var position: usize = 0;
    while (position < flags.len) {
        const c = flags[position];
        position += 1;
        if (c == 'g' and !command.all) command.all = true else if (printSuffix(c) and command.suffix == 0) {
            command.suffix = c;
        } else if (digit(c) and !has_count) {
            const start = position - 1;
            while (position < flags.len and digit(flags[position])) position += 1;
            command.count = number(flags[start..position]);
            if (command.count == 0) return error.InvalidSuffix;
            has_count = true;
        } else return error.InvalidSuffix;
    }
    return command;
}

fn parseCommand(gpa: Allocator, text: []const u8) ParseError!Command {
    if (sortForm(text)) {
        const options = if (text.len == 4) "" else text[5..];
        if (text.len > 4 and options.len == 0) return error.InvalidSuffix;
        var used: [256]bool = @splat(false);
        for (options) |c| {
            if (std.mem.findScalar(u8, "ruin", c) == null or used[c]) return error.InvalidSuffix;
            used[c] = true;
        }
        if (used['i'] and used['n']) return error.InvalidSuffix;
        return .{ .kind = .sort, .options = options };
    }
    const first: u8 = if (text.len == 0) 0 else text[0];
    const argument = if (text.len == 0) "" else text[1..];
    const plain: ?Kind = switch (first) {
        0 => .empty,
        'a' => .append,
        'i' => .insert,
        'c' => .change,
        'p' => .print,
        'n' => .numbered,
        'l' => .listed,
        '=' => .number,
        '#' => .count,
        'y' => .yank,
        'K' => .marks,
        'h' => .history,
        'f' => .files,
        else => null,
    };
    if (plain) |kind| {
        if (argument.len != 0) return error.InvalidSuffix;
        return .{ .kind = kind };
    }
    switch (first) {
        'd', 'x', 'j', 'J' => return .{
            .kind = switch (first) {
                'd' => .delete,
                'x' => .put,
                'j' => .join,
                else => .join_spaced,
            },
            .suffix = try suffix(argument),
        },
        'z', '>', '<', 'u' => return .{
            .kind = switch (first) {
                'z' => .window,
                '>' => .indent,
                '<' => .unindent,
                else => .undo,
            },
            .count = try optionalCount(argument),
        },
        '~' => {
            if (argument.len != 0 and !equal(argument, "u") and !equal(argument, "l")) return error.InvalidSuffix;
            return .{ .kind = .change_case, .case_mode = if (argument.len == 0) 0 else argument[0] };
        },
        'r' => return if (argument.len == 0 or digits(argument)) .{ .kind = .redo, .count = try optionalCount(argument) } else .{ .kind = .read, .name = try fileName(argument) },
        'w' => return if (argument.len == 0) .{ .kind = .write_print } else .{ .kind = .write, .name = try fileName(argument) },
        'W', 'e' => return .{ .kind = if (first == 'W') .write_append else .edit, .name = try fileName(argument) },
        'k' => {
            if (argument.len != 1 or argument[0] < 'a' or argument[0] > 'z') return error.InvalidMark;
            return .{ .kind = .mark, .name = argument };
        },
        'm', 't' => {
            var parser: Parser = .{ .gpa = gpa, .text = argument };
            const destination = try parser.scan();
            if (destination.len == 0 or !expression(destination)) return error.InvalidDestination;
            return .{ .kind = if (first == 'm') .move else .copy, .destination = destination, .suffix = try suffix(argument[parser.position..]) };
        },
        's' => return substitution(gpa, argument),
        'g', 'v' => {
            if (argument.len == 0 or argument[0] == ' ' or argument[0] == '\\') return error.MissingDelimiter;
            var parser: Parser = .{ .gpa = gpa, .text = argument, .position = 1 };
            const pattern = (try parser.delimited(argument[0])).text;
            const subtext = if (parser.position == argument.len) "p" else argument[parser.position..];
            if (std.mem.findScalar(u8, "pnldmtjJs><~aicx", subtext[0]) == null or sortForm(subtext)) return error.InvalidGlobalCommand;
            const subcommand = try gpa.create(Command);
            subcommand.* = try parseCommand(gpa, subtext);
            return .{ .kind = if (first == 'g') .global else .inverse_global, .pattern = pattern, .subcommand = subcommand };
        },
        else => return error.UnknownCommand,
    }
}

fn textCommand(text: []const u8) bool {
    return equal(text, "a") or equal(text, "i") or equal(text, "c");
}
fn hasText(gpa: Allocator, text: []const u8) ParseError!bool {
    var parser: Parser = .{ .gpa = gpa, .text = text };
    _ = parser.scan() catch |err| {
        if (err == error.MissingDelimiter) return false;
        return err;
    };
    const command = text[parser.position..];
    if (textCommand(command)) return true;
    if (command.len < 2 or (command[0] != 'g' and command[0] != 'v') or command[1] == ' ' or command[1] == '\\') return false;
    parser = .{ .gpa = gpa, .text = command, .position = 2 };
    _ = parser.delimited(command[1]) catch |err| {
        if (err == error.MissingDelimiter) return false;
        return err;
    };
    return textCommand(command[parser.position..]);
}

const Line = struct { id: usize, text: []const u8 };
const HistoryRecord = struct { command: []const u8, lines: []const Line, current: usize };
const FileData = struct {
    previous: ?*const FileData,
    lines: []const []const u8,
    count: usize,
    bytes: usize,
};
const File = struct {
    name: []const u8,
    data: *const FileData,
    fn lessThan(_: void, a: File, b: File) bool {
        return std.mem.order(u8, a.name, b.name) == .lt;
    }
};
const State = struct {
    lines: []const Line = &.{},
    current: usize = 0,
    display_count: usize = 5,
    next_id: usize = 1,
    marks: [26]?usize = @splat(null),
    cut: []const []const u8 = &.{},
    pattern: ?[]const u8 = null,
    replacement: ?[]const ?u8 = null,
    undo: std.ArrayList(HistoryRecord) = .empty,
    redo: std.ArrayList(HistoryRecord) = .empty,
    files: std.ArrayList(File) = .empty,

    fn copy(state: State, gpa: Allocator) Allocator.Error!State {
        var result = state;
        result.undo = try state.undo.clone(gpa);
        result.redo = try state.redo.clone(gpa);
        result.files = try state.files.clone(gpa);
        return result;
    }
    fn fileIndex(state: *const State, name: []const u8) ?usize {
        for (state.files.items, 0..) |file, i| if (equal(file.name, name)) return i;
        return null;
    }
};

fn leadingInteger(text: []const u8) i64 {
    var position: usize = if (text[0] == '-') 1 else 0;
    const start = position;
    while (position < text.len and digit(text[position])) position += 1;
    return if (position == start) 0 else std.fmt.parseInt(i64, text[0..position], 10) catch unreachable;
}
const SortContext = struct {
    numeric: bool,
    insensitive: bool,
    reverse: bool,
    fn compare(context: SortContext, a: Line, b: Line) std.math.Order {
        if (context.numeric) return std.math.order(leadingInteger(a.text), leadingInteger(b.text));
        for (0..@min(a.text.len, b.text.len)) |i| {
            const left = if (context.insensitive) std.ascii.toLower(a.text[i]) else a.text[i];
            const right = if (context.insensitive) std.ascii.toLower(b.text[i]) else b.text[i];
            if (left != right) return std.math.order(left, right);
        }
        return std.math.order(a.text.len, b.text.len);
    }
    fn lessThan(context: SortContext, a: Line, b: Line) bool {
        return context.compare(a, b) == (if (context.reverse) std.math.Order.gt else .lt);
    }
};

const Values = struct { items: [2]i64 = undefined, count: usize = 0 };
const Range = struct { first: usize, last: usize };
const Editor = struct {
    gpa: Allocator,
    storage: Allocator,
    state: *State,
    buffer: std.ArrayList(Line) = .empty,
    stable: []const Line,
    out: *Writer,

    fn pattern(editor: *Editor, search: []const u8) CommandError![]const u8 {
        if (search.len != 0) editor.state.pattern = search;
        return editor.state.pattern orelse error.NoPreviousPattern;
    }

    fn locate(editor: *const Editor, id: usize) ?usize {
        for (editor.buffer.items, 0..) |item, i| if (item.id == id) return i;
        return null;
    }

    fn evaluate(editor: *Editor, elements: []const Element) CommandError!i64 {
        var value: i64 = @intCast(editor.state.current);
        for (elements) |element| switch (element.kind) {
            .offset => value += element.value,
            .number => value = element.value,
            .current => value = @intCast(editor.state.current),
            .last => value = @intCast(editor.buffer.items.len),
            .mark => {
                if (element.symbol < 'a' or element.symbol > 'z') return error.InvalidMark;
                const id = editor.state.marks[element.symbol - 'a'] orelse return error.MarkNotSet;
                const position = editor.locate(id) orelse return error.MarkNotSet;
                value = @intCast(position + 1);
            },
            .forward, .backward => {
                const search = try editor.pattern(element.text);
                const size: i64 = @intCast(editor.buffer.items.len);
                const forward = element.kind == .forward;
                var index: i64 = @intCast(editor.state.current);
                if (!forward) index -= 2;
                value = 0;
                for (0..editor.buffer.items.len) |_| {
                    if (index >= size) index = 0;
                    if (index < 0) index = size - 1;
                    if (std.mem.find(u8, editor.buffer.items[@intCast(index)].text, search) != null) {
                        value = index + 1;
                        break;
                    }
                    index += if (forward) @as(i64, 1) else -1;
                }
                if (value == 0) return error.NoMatch;
            },
            .separator, .all => unreachable,
        };
        return value;
    }

    fn evaluateAddress(editor: *Editor, address: Address) CommandError!Values {
        if (address.count() == 0) return .{};
        const left = if (address.left.len != 0) try editor.evaluate(address.left) else if (address.separator == ',') @as(i64, 1) else @as(i64, @intCast(editor.state.current));
        if (address.count() == 1) return .{ .items = .{ left, left }, .count = 1 };
        if (address.separator == ';') {
            if (left < 0 or left > editor.buffer.items.len) return error.AddressOutOfRange;
            editor.state.current = @intCast(left);
        }
        const right = if (address.right.?.len == 0) @as(i64, @intCast(editor.buffer.items.len)) else try editor.evaluate(address.right.?);
        return .{ .items = .{ left, right }, .count = 2 };
    }

    fn range(editor: *const Editor, command: Command, addresses: Values) CommandError!Range {
        const kind = command.kind;
        const size: i64 = @intCast(editor.buffer.items.len);
        const current: i64 = @intCast(editor.state.current);
        if (kind.noAddress()) return .{ .first = 0, .last = 0 };
        if (kind.oneAddress()) {
            const a = if (addresses.count != 0) addresses.items[0] else switch (kind) {
                .number, .read => size,
                .window => current + 1,
                else => current,
            };
            const minimum: i64 = if (kind == .mark or kind == .window) 1 else 0;
            if (a < minimum or a > size) return error.AddressOutOfRange;
            return .{ .first = @intCast(a), .last = @intCast(a) };
        }
        var a: i64 = undefined;
        var b: i64 = undefined;
        if (addresses.count != 0) {
            a = addresses.items[0];
            b = addresses.items[addresses.count - 1];
        } else switch (kind) {
            .write_print, .write, .write_append, .count => return .{ .first = 1, .last = editor.buffer.items.len },
            .global, .inverse_global, .sort => {
                a = 1;
                b = size;
            },
            .join, .join_spaced => {
                a = current;
                b = current + 1;
            },
            else => {
                a = current;
                b = current;
            },
        }
        if (a < 1 or b < 1 or a > size or b > size) return error.AddressOutOfRange;
        if (a > b or a == b and (kind == .join or kind == .join_spaced)) return error.InvalidRange;
        return .{ .first = @intCast(a), .last = @intCast(b) };
    }

    fn process(editor: *Editor, text: []const u8, inserted: []const []const u8, before: State) Error!void {
        var parser: Parser = .{ .gpa = editor.storage, .text = text };
        const address = try addressForm(try parser.scan());
        const command = try parseCommand(editor.storage, text[parser.position..]);
        if (command.kind.noAddress() and address.count() != 0) return error.UnexpectedAddress;
        if (command.kind.oneAddress() and address.count() == 2) return error.TooManyAddresses;
        const bounds = try editor.range(command, try editor.evaluateAddress(address));
        _ = try editor.execute(command, bounds, inserted, false);
        if (editor.buffer.items.len > 200) return error.BufferFull;
        if (command.modifies()) {
            try editor.state.undo.append(editor.gpa, .{ .command = text, .lines = before.lines, .current = before.current });
            editor.state.redo.clearRetainingCapacity();
            editor.state.lines = try editor.storage.dupe(Line, editor.buffer.items);
        } else editor.state.lines = editor.stable;
    }

    fn printLine(editor: *Editor, index: usize, form: u8) Writer.Error!void {
        const text = editor.buffer.items[index - 1].text;
        if (form == 'n') return line(editor.out, "{d:3} {s}", .{ index, text });
        if (form != 'l') return line(editor.out, "{s}", .{text});
        var escaped: [161]u8 = undefined;
        var length: usize = 0;
        for (text) |c| {
            escaped[length] = c;
            length += 1;
            if (c == '\\') {
                escaped[length] = c;
                length += 1;
            }
        }
        escaped[length] = '$';
        length += 1;
        var position: usize = 0;
        while (length - position > 40) : (position += 39)
            try line(editor.out, "{s}\\", .{escaped[position .. position + 39]});
        try line(editor.out, "{s}", .{escaped[position..length]});
    }

    fn contents(editor: *const Editor, allocator: Allocator, bounds: Range) Allocator.Error![]const []const u8 {
        const selected = editor.buffer.items[bounds.first - 1 .. bounds.last];
        const result = try allocator.alloc([]const u8, selected.len);
        for (selected, result) |item, *destination| destination.* = item.text;
        return result;
    }

    fn insert(editor: *Editor, position: usize, text: []const []const u8) Allocator.Error!void {
        const inserted = try editor.gpa.alloc(Line, text.len);
        for (text, inserted) |value, *item| {
            item.* = .{ .id = editor.state.next_id, .text = value };
            editor.state.next_id += 1;
        }
        try editor.buffer.insertSlice(editor.gpa, position, inserted);
        editor.state.current = position + inserted.len;
    }

    fn history(editor: *Editor, undo: bool, count: usize) ParseError!void {
        const source = if (undo) &editor.state.undo else &editor.state.redo;
        const target = if (undo) &editor.state.redo else &editor.state.undo;
        if (source.items.len < count) return if (undo) error.NothingToUndo else error.NothingToRedo;
        for (0..count) |_| {
            const record = source.pop().?;
            try target.append(editor.gpa, .{ .command = record.command, .lines = editor.stable, .current = editor.state.current });
            editor.stable = record.lines;
            editor.buffer.clearRetainingCapacity();
            try editor.buffer.appendSlice(editor.gpa, record.lines);
            editor.state.current = record.current;
        }
    }

    fn sort(editor: *Editor, command: Command, bounds: Range) Allocator.Error!void {
        const context: SortContext = .{
            .numeric = std.mem.findScalar(u8, command.options, 'n') != null,
            .insensitive = std.mem.findScalar(u8, command.options, 'i') != null,
            .reverse = std.mem.findScalar(u8, command.options, 'r') != null,
        };
        const sorted = try editor.gpa.dupe(Line, editor.buffer.items[bounds.first - 1 .. bounds.last]);
        std.sort.insertion(Line, sorted, context, SortContext.lessThan);
        const unique = std.mem.findScalar(u8, command.options, 'u') != null;
        var count: usize = 0;
        for (sorted) |item| {
            if (unique and count != 0 and context.compare(sorted[count - 1], item) == .eq) continue;
            sorted[count] = item;
            count += 1;
        }
        try editor.buffer.replaceRange(editor.gpa, bounds.first - 1, bounds.last - bounds.first + 1, sorted[0..count]);
        editor.state.current = bounds.first + count - 1;
    }

    fn substitute(editor: *Editor, command: Command, bounds: Range, global: bool) Error!usize {
        const search = try editor.pattern(command.pattern);
        const replacement = command.replacement orelse editor.state.replacement orelse return error.NoPreviousSubstitution;
        editor.state.replacement = replacement;
        var expanded: Writer.Allocating = .init(editor.gpa);
        for (replacement) |part| {
            if (part) |c| try expanded.writer.writeByte(c) else try expanded.writer.writeAll(search);
        }
        var substituted: usize = 0;
        for (bounds.first - 1..bounds.last) |index| {
            const original = editor.buffer.items[index].text;
            var result: Writer.Allocating = .init(editor.gpa);
            var position: usize = 0;
            var occurrences: usize = 0;
            while (std.mem.findPos(u8, original, position, search)) |match| {
                try result.writer.writeAll(original[position..match]);
                occurrences += 1;
                try result.writer.writeAll(if (occurrences == command.count or command.all and occurrences >= command.count)
                    expanded.written()
                else
                    search);
                position = match + search.len;
            }
            if (occurrences < command.count) continue;
            try result.writer.writeAll(original[position..]);
            const changed = result.written();
            if (changed.len > 80) return error.LineTooLong;
            if (changed.len == 0 or changed[changed.len - 1] == ' ') return error.BadLine;
            editor.buffer.items[index].text = try editor.storage.dupe(u8, changed);
            editor.state.current = index + 1;
            substituted += 1;
        }
        if (substituted == 0 and !global) return error.NoMatch;
        if (substituted != 0 and command.suffix != 0) try editor.printLine(editor.state.current, command.suffix);
        return substituted;
    }

    fn fileCommand(editor: *Editor, command: Command, bounds: Range) Error!void {
        const index = editor.state.fileIndex(command.name);
        var data: *const FileData = undefined;
        if (command.kind == .write or command.kind == .write_append) {
            const text = try editor.contents(editor.storage, bounds);
            const previous: ?*const FileData = if (command.kind == .write_append and index != null)
                editor.state.files.items[index.?].data
            else
                null;
            const created = try editor.storage.create(FileData);
            created.* = .{
                .previous = previous,
                .lines = text,
                .count = text.len + (if (previous) |old| old.count else 0),
                .bytes = bytes(text) + (if (previous) |old| old.bytes else 0),
            };
            data = created;
            if (index) |i| editor.state.files.items[i].data = data else try editor.state.files.append(editor.gpa, .{ .name = command.name, .data = data });
        } else {
            data = editor.state.files.items[index orelse return error.NoSuchFile].data;
            var chunks: std.ArrayList(*const FileData) = .empty;
            var current: ?*const FileData = data;
            while (current) |chunk| {
                try chunks.append(editor.gpa, chunk);
                current = chunk.previous;
            }
            const text = try editor.gpa.alloc([]const u8, data.count);
            var position: usize = 0;
            var remaining = chunks.items.len;
            while (remaining != 0) {
                remaining -= 1;
                const chunk = chunks.items[remaining];
                @memcpy(text[position..][0..chunk.lines.len], chunk.lines);
                position += chunk.lines.len;
            }
            if (command.kind == .edit) editor.buffer.clearRetainingCapacity();
            try editor.insert(if (command.kind == .edit) 0 else bounds.first, text);
        }
        try line(editor.out, "file {s} lines={d} bytes={d}", .{ command.name, data.count, data.bytes });
    }

    fn execute(editor: *Editor, command: Command, bounds: Range, text: []const []const u8, global: bool) Error!usize {
        const a = bounds.first;
        const b = bounds.last;
        const kind = command.kind;
        const state = editor.state;
        const out = editor.out;
        switch (kind) {
            .empty => {
                try editor.printLine(b, 'p');
                state.current = b;
            },
            .print, .numbered, .listed => {
                const form: u8 = if (kind == .print) 'p' else if (kind == .numbered) 'n' else 'l';
                for (a..b + 1) |i| try editor.printLine(i, form);
                state.current = b;
            },
            .window => {
                if (command.count != 0) state.display_count = command.count;
                const end = @min(editor.buffer.items.len, a + state.display_count - 1);
                for (a..end + 1) |i| try editor.printLine(i, 'p');
                state.current = end;
            },
            .number => try line(out, "{d}", .{a}),
            .count => {
                var words: usize = 0;
                var chars: usize = 0;
                const selected = editor.buffer.items[a - 1 .. b];
                for (selected) |item| {
                    chars += item.text.len;
                    var in_word = false;
                    for (item.text) |c| {
                        if (c != ' ' and !in_word) words += 1;
                        in_word = c != ' ';
                    }
                }
                try line(out, "count lines={d} words={d} chars={d}", .{ selected.len, words, chars });
            },
            .write_print => {
                for (a..b + 1) |i| try editor.printLine(i, 'p');
                try line(out, "lines={d} bytes={d}", .{ b + 1 - a, bytes(try editor.contents(editor.gpa, bounds)) });
            },
            .append => try editor.insert(a, text),
            .insert => try editor.insert(@max(a, 1) - 1, text),
            .change, .delete => {
                state.cut = try editor.contents(editor.storage, bounds);
                try editor.buffer.replaceRange(editor.gpa, a - 1, b - a + 1, &.{});
                if (kind == .change and text.len != 0) try editor.insert(a - 1, text) else state.current = @min(a, editor.buffer.items.len);
            },
            .yank => state.cut = try editor.contents(editor.storage, bounds),
            .put => {
                if (state.cut.len == 0) return error.NothingToPut;
                try editor.insert(a, state.cut);
            },
            .move, .copy => {
                const destination = try editor.evaluate(command.destination);
                if (destination < 0 or destination > editor.buffer.items.len) return error.AddressOutOfRange;
                const d: usize = @intCast(destination);
                if (kind == .copy) try editor.insert(d, try editor.contents(editor.gpa, bounds)) else {
                    if (a <= d and d < b) return error.InvalidDestination;
                    const moved = try editor.gpa.dupe(Line, editor.buffer.items[a - 1 .. b]);
                    try editor.buffer.replaceRange(editor.gpa, a - 1, moved.len, &.{});
                    const position = if (d < a) d else d - moved.len;
                    try editor.buffer.insertSlice(editor.gpa, position, moved);
                    state.current = position + moved.len;
                }
            },
            .join, .join_spaced => {
                var joined: Writer.Allocating = .init(editor.gpa);
                for (editor.buffer.items[a - 1 .. b], 0..) |item, i| {
                    if (kind == .join_spaced and i != 0) try joined.writer.writeByte(' ');
                    try joined.writer.writeAll(if (kind == .join_spaced and i != 0) std.mem.trimStart(u8, item.text, " ") else item.text);
                }
                if (joined.written().len > 80) return error.LineTooLong;
                editor.buffer.items[a - 1].text = try editor.storage.dupe(u8, joined.written());
                try editor.buffer.replaceRange(editor.gpa, a, b - a, &.{});
                state.current = a;
            },
            .indent, .unindent, .change_case => {
                const width = if (command.count == 0) 4 else command.count;
                for (editor.buffer.items[a - 1 .. b]) |*item| {
                    if (kind == .indent) {
                        if (item.text.len + width > 80) return error.LineTooLong;
                        const changed = try editor.storage.alloc(u8, item.text.len + width);
                        @memset(changed[0..width], ' ');
                        @memcpy(changed[width..], item.text);
                        item.text = changed;
                    } else if (kind == .unindent) {
                        var removed: usize = 0;
                        while (removed < width and removed < item.text.len and item.text[removed] == ' ') removed += 1;
                        item.text = item.text[removed..];
                    } else {
                        const changed = try editor.storage.dupe(u8, item.text);
                        for (changed) |*c| c.* = if (command.case_mode == 'u') std.ascii.toUpper(c.*) else if (command.case_mode == 'l') std.ascii.toLower(c.*) else if (c.* >= 'A' and c.* <= 'Z') c.* + 32 else if (c.* >= 'a' and c.* <= 'z') c.* - 32 else c.*;
                        item.text = changed;
                    }
                }
                state.current = b;
            },
            .sort => try editor.sort(command, bounds),
            .substitute => return editor.substitute(command, bounds, global),
            .mark => state.marks[command.name[0] - 'a'] = editor.buffer.items[a - 1].id,
            .marks => {
                try out.writeAll("marks");
                var count: usize = 0;
                for (state.marks, 0..) |mark, i| if (mark) |id| {
                    if (editor.locate(id)) |position| {
                        try out.print(" {c}={d}", .{ @as(u8, @intCast('a' + i)), position + 1 });
                        count += 1;
                    }
                };
                try out.writeAll(if (count == 0) " none\n" else "\n");
            },
            .undo, .redo => try editor.history(kind == .undo, if (command.count == 0) 1 else command.count),
            .history => {
                try line(out, "history undo={d} redo={d}", .{ state.undo.items.len, state.redo.items.len });
                for (0..state.undo.items.len) |i| try line(out, "undo {d}: {s}", .{ i + 1, state.undo.items[state.undo.items.len - i - 1].command });
                for (0..state.redo.items.len) |i| try line(out, "redo {d}: {s}", .{ i + 1, state.redo.items[state.redo.items.len - i - 1].command });
            },
            .global, .inverse_global => {
                const search = try editor.pattern(command.pattern);
                var selected: std.ArrayList(usize) = .empty;
                for (editor.buffer.items[a - 1 .. b]) |item| {
                    if ((std.mem.find(u8, item.text, search) != null) == (kind == .global)) try selected.append(editor.gpa, item.id);
                }
                if (selected.items.len == 0) return error.NoMatch;
                const subcommand = command.subcommand.?.*;
                var substituted: usize = 0;
                for (selected.items) |id| {
                    const position = editor.locate(id) orelse continue;
                    state.current = position + 1;
                    substituted += try editor.execute(subcommand, try editor.range(subcommand, .{}), text, true);
                }
                if (subcommand.kind == .substitute and substituted == 0) return error.NoMatch;
            },
            .write, .write_append, .read, .edit => try editor.fileCommand(command, bounds),
            .files => {
                const files = try editor.gpa.dupe(File, state.files.items);
                std.sort.heap(File, files, {}, File.lessThan);
                try out.writeAll("files");
                for (files) |file| try out.print(" {s}={d}", .{ file.name, file.data.count });
                try out.writeAll(if (files.len == 0) " none\n" else "\n");
            },
        }
        if (command.suffix != 0 and state.current >= 1) try editor.printLine(state.current, command.suffix);
        return 0;
    }
};

fn bytes(text: []const []const u8) usize {
    var result: usize = 0;
    for (text) |item| result += item.len + 1;
    return result;
}

fn errorReason(err: anyerror) ?[]const u8 {
    return switch (err) {
        error.MissingDelimiter => "missing delimiter",
        error.BadAddress => "bad address",
        error.UnknownCommand => "unknown command",
        error.InvalidSuffix => "invalid suffix",
        error.InvalidMark => "invalid mark",
        error.InvalidDestination => "invalid destination",
        error.InvalidGlobalCommand => "invalid global command",
        error.InvalidFileName => "invalid file name",
        error.UnexpectedAddress => "unexpected address",
        error.TooManyAddresses => "too many addresses",
        error.AddressOutOfRange => "address out of range",
        error.InvalidRange => "invalid range",
        error.NoMatch => "no match",
        error.NoPreviousPattern => "no previous pattern",
        error.NoPreviousSubstitution => "no previous substitution",
        error.MarkNotSet => "mark not set",
        error.NothingToUndo => "nothing to undo",
        error.NothingToRedo => "nothing to redo",
        error.NothingToPut => "nothing to put",
        error.NoSuchFile => "no such file",
        error.LineTooLong => "line too long",
        error.BadLine => "bad line",
        error.BufferFull => "buffer full",
        else => null,
    };
}

fn readLine(gpa: Allocator, input: *std.Io.Reader) ![]const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    return if (text.len != 0 and text[text.len - 1] == '\r') text[0 .. text.len - 1] else text;
}

pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    var state_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer state_arena.deinit();
    var state: State = .{};
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    while (true) {
        const command = try readLine(storage.allocator(), &input.interface);
        if (equal(command, "Q")) break;
        var text: std.ArrayList([]const u8) = .empty;
        if (try hasText(storage.allocator(), command)) {
            while (true) {
                const value = try readLine(storage.allocator(), &input.interface);
                if (equal(value, ".")) break;
                try text.append(storage.allocator(), value);
            }
        }
        var candidate_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var committed = false;
        defer if (!committed) candidate_arena.deinit();
        const gpa = candidate_arena.allocator();
        var next = try state.copy(gpa);
        var response: Writer.Allocating = .init(gpa);
        var editor: Editor = .{
            .gpa = gpa,
            .storage = storage.allocator(),
            .state = &next,
            .stable = state.lines,
            .out = &response.writer,
        };
        try editor.buffer.appendSlice(gpa, state.lines);
        editor.process(command, text.items, state) catch |err| {
            const reason = errorReason(err) orelse return err;
            try line(&output.interface, "? {s}", .{reason});
            continue;
        };
        try output.interface.writeAll(response.written());
        state_arena.deinit();
        state_arena = candidate_arena;
        state = next;
        committed = true;
    }
    try output.interface.flush();
}
