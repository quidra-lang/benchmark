const std = @import("std");
const mime = @import("mime.zig");
pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, arguments: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, arguments) catch @panic("allocation failed"); }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn u(value: i64) usize { return @intCast(value); }
pub fn number(source: []const u8) i64 { return std.fmt.parseInt(i64, source, 10) catch unreachable; }
pub fn whitespace(character: u8) bool { return character == ' ' or character == '\t'; }
pub fn lowerCharacter(character: u8) u8 { return if (character >= 'A' and character <= 'Z') character + 'a' - 'A' else character; }
pub fn lowercase(source: []const u8) []const u8 {
    const result = alloc(u8, source.len);
    for (source, result) |character, *target| target.* = lowerCharacter(character);
    return result;
}
pub fn equalCase(first: []const u8, second: []const u8) bool {
    if (first.len != second.len) return false;
    for (first, second) |a, b| if (lowerCharacter(a) != lowerCharacter(b)) return false;
    return true;
}
pub fn split(source: []const u8, separator: u8) Strings {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, source, separator);
    while (iterator.next()) |part| append([]const u8, &result, part);
    return result.items;
}
pub fn lines(source: []const u8) Strings { const result = split(source, '\n'); return result[0 .. result.len - 1]; }
pub fn splitWords(source: []const u8) Strings {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.tokenizeAny(u8, source, " \t");
    while (iterator.next()) |word| append([]const u8, &result, word);
    return result.items;
}
pub fn join(source: Strings, separator: []const u8) []const u8 {
    var text: Text = .{};
    for (source, 0..) |item, i| { if (i > 0) text.write(separator); text.write(item); }
    return text.value();
}
pub fn collapseWhitespace(source: []const u8) []const u8 { return join(splitWords(source), " "); }
pub fn strip(source: []const u8) []const u8 { return std.mem.trim(u8, source, " \t"); }
pub fn rstrip(source: []const u8) []const u8 { return std.mem.trimEnd(u8, source, " \t"); }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, source: []const u8) void { self.data.appendSlice(allocator, source) catch @panic("allocation failed"); }
    pub fn add(self: *Text, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, source: []const u8) void { append([]const u8, &self.data, source); }
    pub fn add(self: *Lines, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn paragraph(self: *Lines, other: Lines) void {
        if (self.data.items.len > 0) self.write("");
        self.data.appendSlice(allocator, other.data.items) catch @panic("allocation failed");
    }
};
pub const SourceLine = struct { number: usize, text: []const u8 };
pub const Field = struct { name: []const u8, value: []const u8 };
pub const Header = struct {
    fields: []Field, invalid: []usize,
    pub fn value(self: Header, name: []const u8) ?[]const u8 {
        for (self.fields) |field| if (equalCase(field.name, name)) return field.value;
        return null;
    }
    pub fn count(self: Header, name: []const u8) usize {
        var result: usize = 0;
        for (self.fields) |field| result += @intFromBool(equalCase(field.name, name));
        return result;
    }
};
pub fn parseFields(source: []const SourceLine) Header {
    var fields: std.ArrayList(Field) = .empty;
    var invalid: std.ArrayList(usize) = .empty;
    var in_field = false;
    for (source) |line| {
        if (whitespace(line.text[0])) {
            if (in_field) {
                const field = &fields.items[fields.items.len - 1];
                field.value = fmt("{s}{s}", .{ field.value, line.text });
            } else append(usize, &invalid, line.number);
            continue;
        }
        const colon = std.mem.indexOfScalar(u8, line.text, ':');
        in_field = colon != null and colon.? > 0;
        if (in_field) for (line.text[0..colon.?]) |character| if (character < 33 or character > 126) { in_field = false; };
        if (in_field) append(Field, &fields, .{ .name = lowercase(line.text[0..colon.?]), .value = line.text[colon.? + 1 ..] }) else append(usize, &invalid, line.number);
    }
    for (fields.items) |*field| field.value = strip(field.value);
    return .{ .fields = fields.items, .invalid = invalid.items };
}
pub fn removeComments(source: []const u8) ?[]const u8 {
    var output: Text = .{};
    var depth: usize = 0;
    var position: usize = 0;
    while (position < source.len) : (position += 1) {
        const character = source[position];
        if (depth == 0) {
            if (character == '(') { depth = 1; output.write(" "); } else output.add("{c}", .{character});
        } else if (character == '\\') { if (position + 1 < source.len) position += 1; } else if (character == '(') depth += 1 else if (character == ')') depth -= 1;
    }
    return if (depth == 0) output.value() else null;
}
pub const word_kind: u16 = 256;
pub const quoted_kind: u16 = 257;
pub const Token = struct { kind: u16, text: []const u8, spaced: bool };
fn wordCharacter(character: u8, mime_mode: bool) bool {
    if (mime_mode) return character >= 33 and character <= 126 and std.mem.indexOfScalar(u8, "()<>@,;:\\\"/[]?=", character) == null;
    return (character >= 'A' and character <= 'Z') or (character >= 'a' and character <= 'z') or (character >= '0' and character <= '9') or std.mem.indexOfScalar(u8, "!#$%&'*+-/=?^_`{|}~", character) != null;
}
pub fn tokenize(source: []const u8, mime_mode: bool) ?[]Token {
    var tokens: std.ArrayList(Token) = .empty;
    const specials = if (mime_mode) "/;=" else "<>:;@,.";
    var position: usize = 0;
    var spaced = false;
    while (position < source.len) {
        const character = source[position];
        if (whitespace(character)) { spaced = true; position += 1; continue; }
        if (character == '(') {
            var depth: usize = 1;
            position += 1;
            while (position < source.len and depth > 0) {
                if (source[position] == '\\') position = @min(position + 2, source.len) else {
                    if (source[position] == '(') depth += 1 else if (source[position] == ')') depth -= 1;
                    position += 1;
                }
            }
            if (depth != 0) return null;
            spaced = true;
            continue;
        }
        var token: Token = .{ .kind = 0, .text = "", .spaced = spaced };
        if (character == '"') {
            var quoted: Text = .{};
            position += 1;
            while (position < source.len and source[position] != '"') : (position += 1) {
                if (source[position] == '\\') { position += 1; if (position == source.len) return null; }
                quoted.add("{c}", .{source[position]});
            }
            if (position == source.len) return null;
            position += 1;
            token.kind = quoted_kind;
            token.text = quoted.value();
        } else if (std.mem.indexOfScalar(u8, specials, character) != null) {
            token.kind = character;
            token.text = source[position .. position + 1];
            position += 1;
        } else if (wordCharacter(character, mime_mode)) {
            const start = position;
            while (position < source.len and wordCharacter(source[position], mime_mode)) position += 1;
            token.kind = word_kind;
            token.text = source[start..position];
        } else return null;
        append(Token, &tokens, token);
        spaced = false;
    }
    return tokens.items;
}
pub const DecodedWord = struct { text: []const u8, decoded: bool = false, failed: bool = false };
pub fn decodeWord(word: []const u8) DecodedWord {
    const original: DecodedWord = .{ .text = word };
    if (word.len < 4 or !std.mem.startsWith(u8, word, "=?") or !std.mem.endsWith(u8, word, "?=")) return original;
    const pieces = split(word[2 .. word.len - 2], '?');
    if (pieces.len != 3 or pieces[0].len == 0 or pieces[1].len == 0 or pieces[2].len == 0) return original;
    const failure: DecodedWord = .{ .text = word, .failed = true };
    if (!equalCase(pieces[0], "us-ascii")) return failure;
    var data: []const u8 = undefined;
    if (eq(pieces[1], "Q") or eq(pieces[1], "q")) {
        var output: Text = .{};
        var i: usize = 0;
        const encoded = pieces[2];
        while (i < encoded.len) {
            var value = encoded[i];
            if (value == '_') { value = ' '; i += 1; } else if (value == '=') {
                if (i + 2 >= encoded.len) return failure;
                const first = mime.hexValue(encoded[i + 1]) orelse return failure;
                const second = mime.hexValue(encoded[i + 2]) orelse return failure;
                value = 16 * first + second;
                i += 3;
            } else i += 1;
            output.add("{c}", .{value});
        }
        data = output.value();
    } else if (eq(pieces[1], "B") or eq(pieces[1], "b")) data = mime.strictBase64(allocator, pieces[2]) orelse return failure else return failure;
    for (data) |value| if (value < 32 or value > 126) return failure;
    return .{ .text = data, .decoded = true };
}
pub const Decoded = struct { text: []const u8, failed: bool };
pub fn decodeUnstructured(source: []const u8) Decoded {
    var output: Text = .{};
    var previous = false;
    var failed = false;
    for (splitWords(source), 0..) |word, i| {
        const decoded = decodeWord(word);
        if (i > 0 and !(previous and decoded.decoded)) output.write(" ");
        output.write(decoded.text);
        previous = decoded.decoded;
        failed = failed or decoded.failed;
    }
    return .{ .text = collapseWhitespace(output.value()), .failed = failed };
}
pub const Parameter = struct { name: []const u8, value: []const u8 };
pub const Parameters = struct {
    main_type: []const u8 = "", subtype: []const u8 = "", values: []Parameter = &.{},
    pub fn get(self: Parameters, name: []const u8) ?[]const u8 {
        for (self.values) |value| if (eq(value.name, name)) return value.value;
        return null;
    }
};
pub fn parseParameters(source: []const u8, with_subtype: bool) ?Parameters {
    const tokens = tokenize(source, true) orelse return null;
    if (tokens.len == 0 or tokens[0].kind != word_kind) return null;
    var result: Parameters = .{ .main_type = lowercase(tokens[0].text) };
    var position: usize = 1;
    if (with_subtype) {
        if (tokens.len < 3 or tokens[1].kind != '/' or tokens[2].kind != word_kind) return null;
        result.subtype = lowercase(tokens[2].text);
        position = 3;
    }
    var parameters: std.ArrayList(Parameter) = .empty;
    while (position < tokens.len) : (position += 4) {
        if (position + 3 >= tokens.len or tokens[position].kind != ';' or tokens[position + 1].kind != word_kind or tokens[position + 2].kind != '=' or (tokens[position + 3].kind != word_kind and tokens[position + 3].kind != quoted_kind)) return null;
        const name = lowercase(tokens[position + 1].text);
        var present = false;
        for (parameters.items) |parameter| if (eq(parameter.name, name)) { present = true; break; };
        if (!present) append(Parameter, &parameters, .{ .name = name, .value = tokens[position + 3].text });
    }
    result.values = parameters.items;
    return result;
}
pub const Entity = struct {
    number: []const u8, main_type: []const u8 = "text", subtype: []const u8 = "plain", parameters: Parameters = .{},
    disposition: ?[]const u8 = null, filename: ?[]const u8 = null, content: []const u8 = "", split: bool = false, children: []*Entity = &.{},
};
