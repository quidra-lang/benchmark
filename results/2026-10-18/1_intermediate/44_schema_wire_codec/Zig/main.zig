const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Text = []const u8;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Kind = enum { unsigned32, unsigned64, signed32, signed64, boolean, fixed32, sfixed32, fixed64, string, bytes, enumeration, message };
const EnumMember = struct { name: Text, number: i64 };
const SchemaType = struct {
    name: Text,
    kind: Kind,
    fields: std.ArrayList(*Field) = .empty,
    members: std.ArrayList(EnumMember) = .empty,

    fn wire(schema: *const SchemaType) u3 {
        return switch (schema.kind) {
            .fixed64 => 1,
            .string, .bytes, .message => 2,
            .fixed32, .sfixed32 => 5,
            else => 0,
        };
    }
    fn byName(schema: *const SchemaType, name: Text) ?*const Field {
        for (schema.fields.items) |field| if (equal(field.name, name)) return field;
        return null;
    }
    fn byNumber(schema: *const SchemaType, number: u64) ?*const Field {
        for (schema.fields.items) |field| if (field.number == number) return field;
        return null;
    }
    fn enumName(schema: *const SchemaType, number: i64) ?Text {
        for (schema.members.items) |member| if (member.number == number) return member.name;
        return null;
    }
    fn enumNumber(schema: *const SchemaType, name: Text) ?i64 {
        for (schema.members.items) |member| if (equal(member.name, name)) return member.number;
        return null;
    }
};
const Field = struct {
    number: u64,
    type_name: Text,
    name: Text,
    required: bool,
    repeated: bool,
    is_packed: bool,
    group: ?Text,
    value_type: *const SchemaType = undefined,
    index: usize = 0,
};
const Schema = struct {
    gpa: Allocator,
    types: std.ArrayList(*SchemaType) = .empty,

    fn lookup(schema: *const Schema, name: Text) ?*SchemaType {
        for (schema.types.items) |value_type| if (equal(value_type.name, name)) return value_type;
        return null;
    }
    fn add(schema: *Schema, name: Text, kind: Kind) Allocator.Error!*SchemaType {
        const value_type = try schema.gpa.create(SchemaType);
        value_type.* = .{ .name = name, .kind = kind };
        try schema.types.append(schema.gpa, value_type);
        return value_type;
    }
    fn load(schema: *Schema, reader: *std.Io.Reader) !void {
        const names = [_]Text{ "uint32", "uint64", "sint32", "sint64", "bool", "fixed32", "sfixed32", "fixed64", "string", "bytes" };
        for (names, 0..) |name, i| _ = try schema.add(name, @fromBackingInt(@intCast(i)));
        var current: *SchemaType = undefined;
        while (true) {
            const source = std.mem.trim(u8, (try readLine(reader, schema.gpa)).?, "\r");
            if (equal(source, "END SCHEMA")) break;
            const words = try splitWords(schema.gpa, source);
            if (equal(words[0], "ENUM") or equal(words[0], "MESSAGE")) {
                current = try schema.add(words[1], if (equal(words[0], "ENUM")) .enumeration else .message);
            } else if (equal(words[0], "VALUE")) {
                try current.members.append(schema.gpa, .{ .name = words[1], .number = try std.fmt.parseInt(i64, words[2], 10) });
            } else if (equal(words[0], "FIELD")) {
                const mode = if (words.len > 4) words[4] else "";
                const field = try schema.gpa.create(Field);
                field.* = .{
                    .number = try std.fmt.parseInt(u64, words[1], 10),
                    .type_name = words[2],
                    .name = words[3],
                    .required = equal(mode, "REQUIRED"),
                    .repeated = equal(mode, "REPEATED"),
                    .is_packed = words.len > 5 and equal(words[5], "PACKED"),
                    .group = if (equal(mode, "ONEOF")) words[5] else null,
                };
                try current.fields.append(schema.gpa, field);
            }
        }
        for (schema.types.items) |value_type| {
            std.sort.heap(*Field, value_type.fields.items, {}, struct {
                fn less(_: void, a: *Field, b: *Field) bool {
                    return a.number < b.number;
                }
            }.less);
            std.sort.heap(EnumMember, value_type.members.items, {}, struct {
                fn less(_: void, a: EnumMember, b: EnumMember) bool {
                    return a.number < b.number;
                }
            }.less);
            for (value_type.fields.items, 0..) |field, i| {
                field.index = i;
                field.value_type = schema.lookup(field.type_name).?;
            }
        }
    }
};

const Value = union(enum) { number: i64, boolean: bool, binary: Text, message: *Message };
const Unknown = struct { number: u64, wire: u3, integer: u64, bytes: Text };
const Message = struct {
    value_type: *const SchemaType,
    fields: []std.ArrayList(Value),
    unknown: std.ArrayList(Unknown) = .empty,

    fn create(gpa: Allocator, value_type: *const SchemaType) Allocator.Error!*Message {
        const message = try gpa.create(Message);
        const fields = try gpa.alloc(std.ArrayList(Value), value_type.fields.items.len);
        for (fields) |*field_values| field_values.* = .empty;
        message.* = .{ .value_type = value_type, .fields = fields };
        return message;
    }
    fn values(message: *const Message, field: *const Field) []const Value {
        return message.fields[field.index].items;
    }
    fn choose(message: *Message, field: *const Field) void {
        const group = field.group orelse return;
        for (message.value_type.fields.items) |other| {
            if (other == field) continue;
            if (other.group) |name| if (equal(name, group)) {
                message.fields[other.index].clearRetainingCapacity();
            };
        }
    }
    fn apply(message: *Message, gpa: Allocator, field: *const Field, incoming: []const Value) Allocator.Error!void {
        if (incoming.len == 0) return;
        message.choose(field);
        const stored = &message.fields[field.index];
        if (field.repeated) {
            try stored.appendSlice(gpa, incoming);
        } else if (field.value_type.kind == .message and stored.items.len > 0) {
            try stored.items[0].message.merge(gpa, incoming[0].message);
        } else {
            stored.clearRetainingCapacity();
            try stored.appendSlice(gpa, incoming);
        }
    }
    fn merge(message: *Message, gpa: Allocator, source: *const Message) Allocator.Error!void {
        for (message.value_type.fields.items) |field| try message.apply(gpa, field, source.values(field));
        try message.unknown.appendSlice(gpa, source.unknown.items);
    }
};

fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}
fn digit(c: u8) bool {
    return c >= '0' and c <= '9';
}
fn letter(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}
fn hexDigit(c: u8) ?u8 {
    return if (digit(c)) c - '0' else if (c >= 'a' and c <= 'f') c - 'a' + 10 else null;
}
fn integerText(source: Text) bool {
    const digits = if (source.len > 0 and source[0] == '-') source[1..] else source;
    if (digits.len == 0 or digits.len > 18) return false;
    for (digits) |c| if (!digit(c)) return false;
    return true;
}
fn validHex(source: Text) bool {
    if (source.len % 2 != 0) return false;
    for (source) |c| if (hexDigit(c) == null) return false;
    return true;
}
fn hexBytes(gpa: Allocator, source: Text) Allocator.Error!Text {
    const bytes = try gpa.alloc(u8, source.len / 2);
    for (bytes, 0..) |*byte, i| byte.* = hexDigit(source[2 * i]).? * 16 + hexDigit(source[2 * i + 1]).?;
    return bytes;
}
fn splitWords(gpa: Allocator, source: Text) Allocator.Error![]const Text {
    var parts: std.ArrayList(Text) = .empty;
    var iterator = std.mem.splitScalar(u8, source, ' ');
    while (iterator.next()) |part| try parts.append(gpa, part);
    return parts.toOwnedSlice(gpa);
}
fn rest(source: Text, separators: usize) Text {
    var count: usize = 0;
    for (source, 0..) |c, i| if (c == ' ') {
        count += 1;
        if (count == separators) return source[i + 1 ..];
    };
    unreachable;
}
fn line(out: *Writer, comptime format: Text, args: anytype) Writer.Error!void {
    try out.print(format ++ "\n", args);
}
fn wireName(wire: u3) Text {
    return switch (wire) {
        0 => "varint",
        1 => "i64",
        2 => "len",
        5 => "i32",
        else => unreachable,
    };
}
fn writeHex(out: *Writer, bytes: Text, empty_dash: bool) Writer.Error!void {
    if (bytes.len == 0 and empty_dash) return out.writeByte('-');
    const alphabet = "0123456789abcdef";
    for (bytes) |byte| {
        try out.writeByte(alphabet[byte / 16]);
        try out.writeByte(alphabet[byte % 16]);
    }
}
fn writeBytes(out: *Writer, bytes: Text) Writer.Error!void {
    try out.writeByte('<');
    try writeHex(out, bytes, false);
    try out.writeByte('>');
}
fn writeRaw(out: *Writer, value: Unknown) Writer.Error!void {
    if (value.wire == 0) try out.print("{d}", .{value.integer}) else try writeBytes(out, value.bytes);
}
fn writeQuote(out: *Writer, bytes: Text, json: bool) Writer.Error!void {
    try out.writeByte('"');
    for (bytes) |byte| switch (byte) {
        '"' => try out.writeAll("\\\""),
        '\\' => try out.writeAll("\\\\"),
        '\n' => try out.writeAll("\\n"),
        '\t' => try out.writeAll("\\t"),
        32...33, 35...91, 93...126 => try out.writeByte(byte),
        else => {
            try out.writeAll(if (json) "\\u00" else "\\x");
            try writeHex(out, &.{byte}, false);
        },
    };
    try out.writeByte('"');
}
fn writeBase64(out: *Writer, bytes: Text) Writer.Error!void {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var at: usize = 0;
    while (at < bytes.len) : (at += 3) {
        const n: u32 = @as(u32, bytes[at]) * 65536 +
            (if (at + 1 < bytes.len) @as(u32, bytes[at + 1]) * 256 else 0) +
            (if (at + 2 < bytes.len) @as(u32, bytes[at + 2]) else 0);
        try out.writeByte(alphabet[n / 262144]);
        try out.writeByte(alphabet[n / 4096 % 64]);
        try out.writeByte(if (at + 1 < bytes.len) alphabet[n / 64 % 64] else '=');
        try out.writeByte(if (at + 2 < bytes.len) alphabet[n % 64] else '=');
    }
}
fn writeValue(out: *Writer, value_type: *const SchemaType, value: Value, json: bool) Writer.Error!void {
    switch (value) {
        .number => |number| {
            if (value_type.kind == .enumeration) {
                if (json) try out.writeByte('"');
                try out.writeAll(value_type.enumName(number).?);
                if (json) try out.writeByte('"');
            } else {
                const quoted = json and (value_type.kind == .unsigned64 or value_type.kind == .signed64 or value_type.kind == .fixed64);
                if (quoted) try out.writeByte('"');
                try out.print("{d}", .{number});
                if (quoted) try out.writeByte('"');
            }
        },
        .boolean => |state| try out.writeAll(if (state) "true" else "false"),
        .binary => |bytes| {
            if (value_type.kind == .string) try writeQuote(out, bytes, json) else if (json) {
                try out.writeByte('"');
                try writeBase64(out, bytes);
                try out.writeByte('"');
            } else try writeBytes(out, bytes);
        },
        .message => |message| try writeMessage(out, message, json),
    }
}
fn writeSequence(out: *Writer, value_type: *const SchemaType, values: []const Value, json: bool) Writer.Error!void {
    try out.writeByte('[');
    for (values, 0..) |value, i| {
        if (i > 0) try out.writeAll(if (json) "," else ", ");
        try writeValue(out, value_type, value, json);
    }
    try out.writeByte(']');
}
fn writeMessage(out: *Writer, message: *const Message, json: bool) Writer.Error!void {
    try out.writeByte('{');
    var first = true;
    for (message.value_type.fields.items) |field| {
        const values = message.values(field);
        if (values.len == 0) continue;
        if (!first) try out.writeAll(if (json) "," else ", ");
        first = false;
        if (json) {
            try out.writeByte('"');
            var capitalize = false;
            for (field.name) |c| {
                if (c == '_') {
                    capitalize = true;
                } else {
                    try out.writeByte(if (capitalize and c >= 'a' and c <= 'z') c - 'a' + 'A' else c);
                    capitalize = false;
                }
            }
            try out.writeAll("\":");
        } else try out.print("{s}: ", .{field.name});
        if (field.repeated) try writeSequence(out, field.value_type, values, json) else try writeValue(out, field.value_type, values[0], json);
    }
    try out.writeByte('}');
}
fn writeContents(out: *Writer, message: *const Message, depth: usize) Writer.Error!void {
    for (message.value_type.fields.items) |field| for (message.values(field)) |value| {
        try out.splatByteAll(' ', depth * 2);
        if (value == .message) {
            try line(out, "{s} {{", .{field.name});
            try writeContents(out, value.message, depth + 1);
            try out.splatByteAll(' ', depth * 2);
            try out.writeAll("}\n");
        } else {
            try out.print("{s}: ", .{field.name});
            try writeValue(out, field.value_type, value, false);
            try out.writeByte('\n');
        }
    };
    for (message.unknown.items) |unknown| {
        try out.splatByteAll(' ', depth * 2);
        try out.print("{d}: {s} ", .{ unknown.number, wireName(unknown.wire) });
        try writeRaw(out, unknown);
        try out.writeByte('\n');
    }
}
fn writeText(out: *Writer, message: *const Message) Writer.Error!void {
    try line(out, "{s} {{", .{message.value_type.name});
    try writeContents(out, message, 1);
    try out.writeAll("}\n");
}

const max_unsigned = 9007199254740991;
fn zigzag(value: i64) u64 {
    return @intCast(if (value >= 0) 2 * value else -2 * value - 1);
}
fn unzigzag(value: u64) i64 {
    const half: i64 = @intCast(value / 2);
    return if (value % 2 == 0) half else -1 - half;
}
fn inRange(value_type: *const SchemaType, value: i64) bool {
    return switch (value_type.kind) {
        .unsigned32, .fixed32 => value >= 0 and value <= 4294967295,
        .unsigned64, .fixed64 => value >= 0 and value <= max_unsigned,
        .signed32, .sfixed32 => value >= -2147483648 and value <= 2147483647,
        .signed64 => value >= -4503599627370496 and value <= 4503599627370495,
        else => true,
    };
}
fn writeVarint(out: *Writer, input: u64) Writer.Error!void {
    var value = input;
    while (value >= 128) : (value /= 128) try out.writeByte(@intCast(value % 128 + 128));
    try out.writeByte(@intCast(value));
}
fn writeElement(gpa: Allocator, out: *Writer, value_type: *const SchemaType, value: Value) Error!void {
    if (value == .message or value == .binary) {
        const payload = if (value == .message) try encode(gpa, value.message) else value.binary;
        try writeVarint(out, payload.len);
        try out.writeAll(payload);
        return;
    }
    const signed = if (value == .boolean) @as(i64, if (value.boolean) 1 else 0) else value.number;
    var number: u64 = if (value_type.kind == .signed32 or value_type.kind == .signed64) zigzag(signed) else @intCast(if (value_type.kind == .sfixed32 and signed < 0) signed + 4294967296 else signed);
    if (value_type.wire() == 0) {
        try writeVarint(out, number);
    } else {
        const count: usize = if (value_type.wire() == 1) 8 else 4;
        for (0..count) |_| {
            try out.writeByte(@intCast(number % 256));
            number /= 256;
        }
    }
}
fn writeField(gpa: Allocator, out: *Writer, field: *const Field, values: []const Value) Error!void {
    if (values.len == 0) return;
    if (field.is_packed) {
        var payload: Writer.Allocating = .init(gpa);
        defer payload.deinit();
        for (values) |value| try writeElement(gpa, &payload.writer, field.value_type, value);
        try writeVarint(out, field.number * 8 + 2);
        try writeVarint(out, payload.written().len);
        try out.writeAll(payload.written());
    } else for (values) |value| {
        try writeVarint(out, field.number * 8 + field.value_type.wire());
        try writeElement(gpa, out, field.value_type, value);
    }
}
fn encode(gpa: Allocator, message: *const Message) Error!Text {
    var output: Writer.Allocating = .init(gpa);
    defer output.deinit();
    for (message.value_type.fields.items) |field| try writeField(gpa, &output.writer, field, message.values(field));
    for (message.unknown.items) |unknown| {
        try writeVarint(&output.writer, unknown.number * 8 + unknown.wire);
        if (unknown.wire == 0) try writeVarint(&output.writer, unknown.integer) else {
            if (unknown.wire == 2) try writeVarint(&output.writer, unknown.bytes.len);
            try output.writer.writeAll(unknown.bytes);
        }
    }
    return output.toOwnedSlice();
}

const Raw = struct { number: u64, bytes: Text, position: usize, payload: usize };
const Reader = struct {
    session: *Session,
    data: Text,
    position: usize,
    end: usize,

    fn varint(reader: *Reader) Error!u64 {
        const start = reader.position;
        var value: u64 = 0;
        for (0..8) |i| {
            if (reader.position >= reader.end) return reader.session.byteError("truncated varint", start);
            const byte = reader.data[reader.position];
            reader.position += 1;
            value += @as(u64, byte & 127) << @intCast(7 * i);
            if (byte < 128) {
                if (value > max_unsigned) return reader.session.byteError("varint too large", start);
                return value;
            }
        }
        return reader.session.byteError("varint too long", start);
    }
    fn read(reader: *Reader, wire: u3) Error!Raw {
        const start = reader.position;
        if (wire == 0) return .{ .number = try reader.varint(), .bytes = "", .position = start, .payload = start };
        const length: u64 = if (wire == 2) try reader.varint() else if (wire == 1) 8 else 4;
        if (length > reader.end - reader.position)
            return reader.session.byteError(if (wire == 2) "length past end" else if (wire == 1) "truncated i64" else "truncated i32", start);
        const payload = reader.position;
        reader.position += @intCast(length);
        return .{ .number = 0, .bytes = reader.data[payload..reader.position], .position = start, .payload = payload };
    }
};

const Shape = enum { none, message, list, integer, boolean, name, string, bytes };
const TokenData = union(enum) { symbol: u8, integer: i64, name: Text, string: Text, bytes: Text, end: void };
const Token = struct {
    data: TokenData,
    column: usize,
    fn shape(token: Token) Shape {
        return switch (token.data) {
            .integer => .integer,
            .name => |name| if (equal(name, "true") or equal(name, "false")) .boolean else .name,
            .string => .string,
            .bytes => .bytes,
            .symbol => |c| if (c == '{') .message else if (c == '[') .list else .none,
            .end => .none,
        };
    }
};
const Literal = struct {
    session: *Session,
    tokens: []const Token,
    position: usize = 0,

    fn init(session: *Session, source: Text) Error!Literal {
        var tokens: std.ArrayList(Token) = .empty;
        var at: usize = 0;
        while (at < source.len) {
            const c = source[at];
            if (c == ' ') {
                at += 1;
                continue;
            }
            const start = at;
            at += 1;
            var token: Token = .{ .data = .{ .symbol = c }, .column = start + 1 };
            if (std.mem.findScalar(u8, "{}[]:,", c) != null) {
                try tokens.append(session.gpa, token);
                continue;
            }
            if (c == '"') {
                var bytes: std.ArrayList(u8) = .empty;
                var closed = false;
                while (at < source.len) {
                    const current = source[at];
                    at += 1;
                    if (current == '"') {
                        closed = true;
                        break;
                    }
                    if (current != '\\') {
                        try bytes.append(session.gpa, current);
                        continue;
                    }
                    if (at == source.len) return session.columnError("syntax error", token.column);
                    const escaped = source[at];
                    at += 1;
                    switch (escaped) {
                        '"', '\\' => try bytes.append(session.gpa, escaped),
                        'n' => try bytes.append(session.gpa, 10),
                        't' => try bytes.append(session.gpa, 9),
                        'x' => {
                            if (at + 2 > source.len) return session.columnError("syntax error", token.column);
                            const high = hexDigit(source[at]) orelse return session.columnError("syntax error", token.column);
                            const low = hexDigit(source[at + 1]) orelse return session.columnError("syntax error", token.column);
                            if (high > 7) return session.columnError("syntax error", token.column);
                            try bytes.append(session.gpa, high * 16 + low);
                            at += 2;
                        },
                        else => return session.columnError("syntax error", token.column),
                    }
                }
                if (!closed) return session.columnError("syntax error", token.column);
                token.data = .{ .string = try bytes.toOwnedSlice(session.gpa) };
            } else if (c == '<') {
                const relative = std.mem.findScalar(u8, source[at..], '>') orelse return session.columnError("syntax error", token.column);
                const finish = at + relative;
                if (!validHex(source[at..finish])) return session.columnError("syntax error", token.column);
                token.data = .{ .bytes = try hexBytes(session.gpa, source[at..finish]) };
                at = finish + 1;
            } else if (c == '-' or digit(c)) {
                if (c == '-' and (at == source.len or !digit(source[at]))) return session.columnError("syntax error", token.column);
                while (at < source.len and digit(source[at])) : (at += 1) {}
                token.data = .{ .integer = std.fmt.parseInt(i64, source[start..at], 10) catch unreachable };
            } else if (letter(c) or c == '_') {
                while (at < source.len and (letter(source[at]) or digit(source[at]) or source[at] == '_')) : (at += 1) {}
                token.data = .{ .name = source[start..at] };
            } else return session.columnError("syntax error", token.column);
            try tokens.append(session.gpa, token);
        }
        try tokens.append(session.gpa, .{ .data = .{ .end = {} }, .column = source.len + 1 });
        return .{ .session = session, .tokens = try tokens.toOwnedSlice(session.gpa) };
    }
    fn peek(literal: *const Literal) Token {
        return literal.tokens[literal.position];
    }
    fn symbol(literal: *const Literal, c: u8) bool {
        const token = literal.peek();
        return token.data == .symbol and token.data.symbol == c;
    }
    fn expect(literal: *Literal, c: u8) Error!void {
        if (!literal.symbol(c)) return literal.session.columnError("syntax error", literal.peek().column);
        literal.position += 1;
    }
    fn expectEnd(literal: *const Literal) Error!void {
        if (literal.peek().data != .end) return literal.session.columnError("syntax error", literal.peek().column);
    }
    fn require(literal: *const Literal, shape: Shape) Error!void {
        const token = literal.peek();
        if (token.shape() == .none) return literal.session.columnError("syntax error", token.column);
        if (token.shape() != shape) return literal.session.columnError("type mismatch", token.column);
    }
    fn readMessage(literal: *Literal, value_type: *const SchemaType) Error!*Message {
        try literal.expect('{');
        const message = try Message.create(literal.session.gpa, value_type);
        const seen = try literal.session.gpa.alloc(bool, value_type.fields.items.len);
        @memset(seen, false);
        if (!literal.symbol('}')) while (true) {
            const token = literal.peek();
            if (token.data != .name) return literal.session.columnError("syntax error", token.column);
            const field = value_type.byName(token.data.name) orelse return literal.session.columnError("unknown field", token.column);
            if (seen[field.index]) return literal.session.columnError("duplicate field", token.column);
            if (field.group) |group| for (value_type.fields.items) |other| {
                if (!seen[other.index]) continue;
                if (other.group) |other_group| if (equal(group, other_group))
                    return literal.session.columnError("oneof conflict", token.column);
            };
            seen[field.index] = true;
            literal.position += 1;
            try literal.expect(':');
            const values = try literal.fieldValue(field);
            try message.fields[field.index].appendSlice(literal.session.gpa, values);
            if (!literal.symbol(',')) break;
            literal.position += 1;
        };
        const closing = literal.peek();
        try literal.expect('}');
        for (value_type.fields.items) |field| if (field.required and !seen[field.index]) {
            const reason = try std.fmt.allocPrint(literal.session.gpa, "missing required field {s}", .{field.name});
            return literal.session.columnError(reason, closing.column);
        };
        return message;
    }
    fn fieldValue(literal: *Literal, field: *const Field) Error![]const Value {
        var values: std.ArrayList(Value) = .empty;
        if (!field.repeated) {
            try values.append(literal.session.gpa, try literal.element(field.value_type));
        } else {
            try literal.require(.list);
            try literal.expect('[');
            if (!literal.symbol(']')) {
                try values.append(literal.session.gpa, try literal.element(field.value_type));
                while (literal.symbol(',')) {
                    literal.position += 1;
                    try values.append(literal.session.gpa, try literal.element(field.value_type));
                }
            }
            try literal.expect(']');
        }
        return values.toOwnedSlice(literal.session.gpa);
    }
    fn element(literal: *Literal, value_type: *const SchemaType) Error!Value {
        const shape: Shape = switch (value_type.kind) {
            .boolean => .boolean,
            .string => .string,
            .bytes => .bytes,
            .enumeration => .name,
            .message => .message,
            else => .integer,
        };
        try literal.require(shape);
        const token = literal.peek();
        if (shape == .message) return .{ .message = try literal.readMessage(value_type) };
        literal.position += 1;
        return switch (shape) {
            .integer => blk: {
                const number = token.data.integer;
                if (!inRange(value_type, number)) return literal.session.columnError("out of range", token.column);
                break :blk .{ .number = number };
            },
            .boolean => .{ .boolean = equal(token.data.name, "true") },
            .name => .{ .number = value_type.enumNumber(token.data.name) orelse return literal.session.columnError("unknown enum value", token.column) },
            .string => .{ .binary = token.data.string },
            .bytes => .{ .binary = token.data.bytes },
            else => unreachable,
        };
    }
};

const Segment = struct {
    field: *const Field,
    index: ?usize,
    fn wholeList(segment: Segment) bool {
        return segment.field.repeated and segment.index == null;
    }
};
const Verb = enum { VARINT, ZIGZAG, SCHEMA, ENCODE, SIZE, DECODE, LITERAL, JSON, CANON, EXPLAIN, GET, PATCH, CLEAR, MERGE, DIFF };
const Session = struct {
    schema: *const Schema,
    gpa: Allocator,
    out: *Writer,
    problem: Text = "",

    fn fail(session: *Session, reason: Text) error{Invalid} {
        session.problem = reason;
        return error.Invalid;
    }
    fn byteError(session: *Session, reason: Text, offset: usize) Error {
        const message = std.fmt.allocPrint(session.gpa, "{s} at byte {d}", .{ reason, offset }) catch |err| return err;
        return session.fail(message);
    }
    fn columnError(session: *Session, reason: Text, column: usize) Error {
        const message = std.fmt.allocPrint(session.gpa, "{s} at column {d}", .{ reason, column }) catch |err| return err;
        return session.fail(message);
    }
    fn checkRequired(session: *Session, message: *const Message, prefix: Text) Error!void {
        for (message.value_type.fields.items) |field| {
            const values = message.values(field);
            const path = try std.fmt.allocPrint(session.gpa, "{s}{s}", .{ prefix, field.name });
            if (field.required and values.len == 0)
                return session.fail(try std.fmt.allocPrint(session.gpa, "missing required field {s}", .{path}));
            if (field.value_type.kind == .message) for (values, 0..) |value, i| {
                const next = if (field.repeated) try std.fmt.allocPrint(session.gpa, "{s}[{d}].", .{ path, i }) else try std.fmt.allocPrint(session.gpa, "{s}.", .{path});
                try session.checkRequired(value.message, next);
            };
        }
    }
    fn convertValue(session: *Session, value_type: *const SchemaType, raw: Raw) Error!Value {
        if (value_type.kind == .string) {
            for (raw.bytes, 0..) |byte, i| if (byte >= 128) return session.byteError("invalid string", raw.payload + i);
            return .{ .binary = raw.bytes };
        }
        if (value_type.kind == .bytes) return .{ .binary = raw.bytes };
        var unsigned = raw.number;
        if (value_type.wire() == 1 or value_type.wire() == 5) {
            if (value_type.kind == .fixed64 and (raw.bytes[7] != 0 or raw.bytes[6] >= 32))
                return session.byteError("value out of range", raw.position);
            unsigned = 0;
            var i = raw.bytes.len;
            while (i > 0) {
                i -= 1;
                unsigned = unsigned * 256 + raw.bytes[i];
            }
        }
        var number: i64 = if (value_type.kind == .signed32 or value_type.kind == .signed64) unzigzag(unsigned) else @intCast(unsigned);
        if (value_type.kind == .sfixed32 and number >= 2147483648) number -= 4294967296;
        if (!inRange(value_type, number)) return session.byteError("value out of range", raw.position);
        if (value_type.kind == .boolean) {
            if (number > 1) return session.byteError("value out of range", raw.position);
            return .{ .boolean = number == 1 };
        }
        if (value_type.kind == .enumeration and value_type.enumName(number) == null)
            return session.byteError("unknown enum number", raw.position);
        return .{ .number = number };
    }
    fn readMessage(session: *Session, value_type: *const SchemaType, data: Text, start: usize, end: usize, depth: usize, explain: bool) Error!*Message {
        const message = try Message.create(session.gpa, value_type);
        var reader: Reader = .{ .session = session, .data = data, .position = start, .end = end };
        while (reader.position < end) {
            const offset = reader.position;
            const tag = try reader.varint();
            const number = tag / 8;
            const wire: u3 = @intCast(tag % 8);
            if (number == 0) return session.byteError("invalid field number", offset);
            if (wire != 0 and wire != 1 and wire != 2 and wire != 5) return session.byteError("invalid wire type", offset);
            const field = value_type.byNumber(number);
            const is_packed = if (field) |candidate| candidate.repeated and candidate.value_type.wire() != 2 and wire == 2 else false;
            if (field) |candidate| if (wire != candidate.value_type.wire() and !is_packed) return session.byteError("wire type mismatch", offset);
            const raw = try reader.read(wire);
            if (explain) {
                try session.out.splatByteAll(' ', depth * 2);
                try session.out.print("{d} {d} {s} {s}", .{ offset, number, if (field) |candidate| candidate.name else "?", wireName(wire) });
                if (wire == 2) try session.out.print(" {d}", .{raw.bytes.len});
            }
            const known = field orelse {
                const unknown: Unknown = .{ .number = number, .wire = wire, .integer = raw.number, .bytes = raw.bytes };
                if (explain) {
                    try session.out.writeByte(' ');
                    try writeRaw(session.out, unknown);
                    try session.out.writeByte('\n');
                } else try message.unknown.append(session.gpa, unknown);
                continue;
            };
            var values: std.ArrayList(Value) = .empty;
            if (known.value_type.kind == .message) {
                if (explain) try session.out.writeByte('\n');
                const child = try session.readMessage(known.value_type, data, raw.payload, raw.payload + raw.bytes.len, depth + 1, explain);
                try values.append(session.gpa, .{ .message = child });
            } else if (is_packed) {
                var elements: Reader = .{ .session = session, .data = data, .position = raw.payload, .end = raw.payload + raw.bytes.len };
                if (explain) try session.out.writeAll(" packed");
                while (elements.position < elements.end) {
                    const value = try session.convertValue(known.value_type, try elements.read(known.value_type.wire()));
                    try values.append(session.gpa, value);
                    if (explain) {
                        try session.out.writeByte(' ');
                        try writeValue(session.out, known.value_type, value, false);
                    }
                }
                if (explain) try session.out.writeByte('\n');
            } else {
                const value = try session.convertValue(known.value_type, raw);
                try values.append(session.gpa, value);
                if (explain) {
                    try session.out.writeByte(' ');
                    try writeValue(session.out, known.value_type, value, false);
                    try session.out.writeByte('\n');
                }
            }
            if (!explain) try message.apply(session.gpa, known, values.items);
        }
        return message;
    }
    fn decode(session: *Session, value_type: *const SchemaType, data: Text, explain: bool) Error!*Message {
        const message = try session.readMessage(value_type, data, 0, data.len, 0, explain);
        if (explain) {
            if (data.len == 0) try session.out.writeAll("(empty)\n");
        } else try session.checkRequired(message, "");
        return message;
    }
    fn decodeSuffix(session: *Session, value_type: *const SchemaType, data: Text, suffix: Text) Error!*Message {
        return session.decode(value_type, data, false) catch |err| {
            if (err == error.Invalid)
                return session.fail(try std.fmt.allocPrint(session.gpa, "{s}{s}", .{ session.problem, suffix }));
            return err;
        };
    }
    fn parsePath(session: *Session, root: *const SchemaType, source: Text) Error![]const Segment {
        var segments: std.ArrayList(Segment) = .empty;
        var iterator = std.mem.splitScalar(u8, source, '.');
        var value_type = root;
        while (iterator.next()) |part| {
            var name = part;
            var index: ?usize = null;
            if (std.mem.findScalar(u8, part, '[')) |open| {
                if (part.len == 0 or part[part.len - 1] != ']') return session.fail("invalid path");
                const digits = part[open + 1 .. part.len - 1];
                if (digits.len == 0 or digits.len > 6) return session.fail("invalid path");
                for (digits) |c| if (!digit(c)) return session.fail("invalid path");
                index = std.fmt.parseInt(usize, digits, 10) catch unreachable;
                name = part[0..open];
            }
            const field = value_type.byName(name) orelse return session.fail("invalid path");
            if (index != null and !field.repeated) return session.fail("invalid path");
            if (iterator.peek() != null and (field.value_type.kind != .message or (field.repeated and index == null)))
                return session.fail("invalid path");
            try segments.append(session.gpa, .{ .field = field, .index = index });
            value_type = field.value_type;
        }
        return segments.toOwnedSlice(session.gpa);
    }
    fn getPath(session: *Session, message: *Message, path: []const Segment) Error!void {
        var current: ?*Message = message;
        for (path, 0..) |segment, step| {
            const values: []const Value = if (current) |node| node.values(segment.field) else &.{};
            const index = segment.index orelse 0;
            if (step + 1 == path.len) {
                if (segment.wholeList()) {
                    try writeSequence(session.out, segment.field.value_type, values, false);
                } else if (index < values.len) {
                    try writeValue(session.out, segment.field.value_type, values[index], false);
                } else try session.out.writeAll("(none)");
                try session.out.writeByte('\n');
                return;
            }
            current = if (index < values.len) values[index].message else null;
        }
        unreachable;
    }
    fn editPath(session: *Session, message: *Message, path: []const Segment, replacement: ?[]const Value) Error!void {
        var current = message;
        for (path[0 .. path.len - 1]) |segment| {
            const stored = &current.fields[segment.field.index];
            const index = segment.index orelse 0;
            if (index >= stored.items.len) {
                if (replacement == null) return;
                if (segment.index != null) return session.fail("index out of range");
                current.choose(segment.field);
                const child = try Message.create(session.gpa, segment.field.value_type);
                try stored.append(session.gpa, .{ .message = child });
            }
            current = stored.items[index].message;
        }
        const last = path[path.len - 1];
        const stored = &current.fields[last.field.index];
        if (last.index) |index| {
            if (index >= stored.items.len) {
                if (replacement != null) return session.fail("index out of range");
            } else if (replacement) |values| {
                stored.items[index] = values[0];
            } else _ = stored.orderedRemove(index);
        } else {
            if (replacement != null) current.choose(last.field);
            stored.clearRetainingCapacity();
            if (replacement) |values| try stored.appendSlice(session.gpa, values);
        }
    }
    fn differences(session: *Session, a: *const Message, b: *const Message, prefix: Text, count: *usize) Error!void {
        for (a.value_type.fields.items) |field| {
            const x = a.values(field);
            const y = b.values(field);
            for (0..@max(x.len, y.len)) |i| {
                const path = if (field.repeated) try std.fmt.allocPrint(session.gpa, "{s}{s}[{d}]", .{ prefix, field.name, i }) else try std.fmt.allocPrint(session.gpa, "{s}{s}", .{ prefix, field.name });
                if (i < x.len and i < y.len and field.value_type.kind == .message) {
                    try session.differences(x[i].message, y[i].message, try std.fmt.allocPrint(session.gpa, "{s}.", .{path}), count);
                } else if (i >= x.len or i >= y.len or !valueEqual(x[i], y[i])) {
                    count.* += 1;
                    try session.out.print("{s}: ", .{path});
                    if (i < x.len) try writeValue(session.out, field.value_type, x[i], false) else try session.out.writeAll("(none)");
                    try session.out.writeAll(" -> ");
                    if (i < y.len) try writeValue(session.out, field.value_type, y[i], false) else try session.out.writeAll("(none)");
                    try session.out.writeByte('\n');
                }
            }
        }
    }
    fn schemaFields(session: *Session, value_type: *const SchemaType, chain: *[40]*const SchemaType, depth: usize) Error!void {
        for (value_type.fields.items) |field| {
            try session.out.splatByteAll(' ', depth * 2);
            try session.out.print("{d} {s}: ", .{ field.number, field.name });
            if (field.required) try session.out.writeAll("required ") else if (field.is_packed) {
                try session.out.writeAll("repeated packed ");
            } else if (field.repeated) try session.out.writeAll("repeated ") else if (field.group) |group| {
                try session.out.print("oneof {s} ", .{group});
            }
            try session.out.writeAll(field.value_type.name);
            if (field.value_type.kind == .enumeration) {
                try session.out.writeAll(" (");
                for (field.value_type.members.items, 0..) |member, i| {
                    if (i > 0) try session.out.writeAll(", ");
                    try session.out.print("{s}={d}", .{ member.name, member.number });
                }
                try session.out.writeByte(')');
            }
            var recursive = false;
            if (field.value_type.kind == .message) for (chain[0..depth]) |ancestor| {
                if (ancestor == field.value_type) recursive = true;
            };
            if (recursive) try session.out.writeAll(" (recursive)");
            try session.out.writeByte('\n');
            if (field.value_type.kind == .message and !recursive) {
                chain[depth] = field.value_type;
                try session.schemaFields(field.value_type, chain, depth + 1);
            }
        }
    }
    fn parseHex(session: *Session, source: Text) Error!Text {
        if (equal(source, "-")) return "";
        if (source.len == 0 or !validHex(source)) return session.fail("invalid hex");
        return hexBytes(session.gpa, source);
    }
    fn execute(session: *Session, source: Text) Error!void {
        const words = try splitWords(session.gpa, source);
        const verb = std.meta.stringToEnum(Verb, words[0]) orelse return session.fail("unknown command");
        const minimum: usize = switch (verb) {
            .VARINT, .ZIGZAG, .SCHEMA => 2,
            .ENCODE, .SIZE, .DECODE, .LITERAL, .JSON, .CANON, .EXPLAIN => 3,
            .GET, .CLEAR, .MERGE, .DIFF => 4,
            .PATCH => 5,
        };
        const flexible = verb == .ENCODE or verb == .SIZE or verb == .PATCH;
        if (words.len < minimum or (!flexible and words.len != minimum)) return session.fail("wrong number of arguments");
        if (verb == .VARINT or verb == .ZIGZAG) {
            if (!integerText(words[1])) return session.fail("invalid number");
            const number = std.fmt.parseInt(i64, words[1], 10) catch unreachable;
            const valid = if (verb == .VARINT) number >= 0 and number <= max_unsigned else number >= -4503599627370496 and number <= 4503599627370495;
            if (!valid) return session.fail("invalid number");
            const value: u64 = if (verb == .ZIGZAG) zigzag(number) else @intCast(number);
            var bytes: Writer.Allocating = .init(session.gpa);
            defer bytes.deinit();
            try writeVarint(&bytes.writer, value);
            if (verb == .ZIGZAG) try session.out.print("{d} ", .{value});
            try writeHex(session.out, bytes.written(), true);
            try session.out.writeByte('\n');
            return;
        }
        const value_type = session.schema.lookup(words[1]) orelse return session.fail("unknown message type");
        if (value_type.kind != .message) return session.fail("unknown message type");
        const data = if (verb == .SCHEMA or verb == .ENCODE or verb == .SIZE) "" else try session.parseHex(words[2]);
        const second = if (verb == .MERGE or verb == .DIFF) try session.parseHex(words[3]) else "";
        const path: []const Segment = if (verb == .GET or verb == .PATCH or verb == .CLEAR) try session.parsePath(value_type, words[3]) else &.{};
        if (verb == .SCHEMA) {
            try line(session.out, "{s}", .{value_type.name});
            var chain: [40]*const SchemaType = undefined;
            chain[0] = value_type;
            try session.schemaFields(value_type, &chain, 1);
            return;
        }
        if (verb == .ENCODE or verb == .SIZE) {
            var literal = try Literal.init(session, rest(source, 2));
            const message = try literal.readMessage(value_type);
            try literal.expectEnd();
            const encoded = try encode(session.gpa, message);
            if (verb == .ENCODE) {
                try writeHex(session.out, encoded, true);
            } else {
                try session.out.print("{d}", .{encoded.len});
                for (value_type.fields.items) |field| {
                    const values = message.values(field);
                    if (values.len == 0) continue;
                    var bytes: Writer.Allocating = .init(session.gpa);
                    defer bytes.deinit();
                    try writeField(session.gpa, &bytes.writer, field, values);
                    try session.out.print(" {s}={d}", .{ field.name, bytes.written().len });
                }
            }
            try session.out.writeByte('\n');
            return;
        }
        if (verb == .EXPLAIN) {
            _ = try session.decode(value_type, data, true);
            return;
        }
        if (verb == .MERGE) {
            const joined = try std.mem.concat(session.gpa, u8, &.{ data, second });
            try writeText(session.out, try session.decode(value_type, joined, false));
            return;
        }
        if (verb == .DIFF) {
            const a = try session.decodeSuffix(value_type, data, " in first");
            const b = try session.decodeSuffix(value_type, second, " in second");
            var count: usize = 0;
            try session.differences(a, b, "", &count);
            if (count == 0) try session.out.writeAll("SAME\n");
            return;
        }
        const message = try session.decode(value_type, data, false);
        switch (verb) {
            .DECODE => return writeText(session.out, message),
            .LITERAL, .JSON => {
                try writeMessage(session.out, message, verb == .JSON);
                try session.out.writeByte('\n');
                return;
            },
            .GET => return session.getPath(message, path),
            .PATCH => {
                var literal = try Literal.init(session, rest(source, 4));
                const last = path[path.len - 1];
                const replacement = if (last.wholeList()) try literal.fieldValue(last.field) else blk: {
                    const values = try session.gpa.alloc(Value, 1);
                    values[0] = try literal.element(last.field.value_type);
                    break :blk values;
                };
                try literal.expectEnd();
                try session.editPath(message, path, replacement);
                try session.checkRequired(message, "");
            },
            .CLEAR => {
                try session.editPath(message, path, null);
                try session.checkRequired(message, "");
            },
            .CANON => {},
            else => unreachable,
        }
        try writeHex(session.out, try encode(session.gpa, message), true);
        try session.out.writeByte('\n');
    }
};

fn valueEqual(a: Value, b: Value) bool {
    return switch (a) {
        .number => |number| number == b.number,
        .boolean => |state| state == b.boolean,
        .binary => |bytes| equal(bytes, b.binary),
        .message => unreachable,
    };
}
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
    var input_buffer: [4096]u8 = undefined;
    var output_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var schema: Schema = .{ .gpa = persistent };
    try schema.load(&input.interface);
    const first = std.mem.trim(u8, (try readLine(&input.interface, persistent)).?, "\r");
    const count = try std.fmt.parseInt(usize, first, 10);
    for (0..count) |_| {
        var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
        defer arena.deinit();
        const gpa = arena.allocator();
        const source = std.mem.trim(u8, (try readLine(&input.interface, gpa)).?, "\r");
        var response: Writer.Allocating = .init(gpa);
        defer response.deinit();
        var session: Session = .{ .schema = &schema, .gpa = gpa, .out = &response.writer };
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
