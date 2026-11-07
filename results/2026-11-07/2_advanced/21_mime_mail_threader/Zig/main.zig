const std = @import("std");
const h = @import("headers.zig");
const addresses = @import("addresses.zig");
const dates = @import("dates.zig");
const mime = @import("mime.zig");
const threader = @import("threader.zig");
const Message = threader.Message;
const Container = threader.Container;

fn readMailbox(source: h.Strings) [][]const h.SourceLine {
    var messages: std.ArrayList(std.ArrayList(h.SourceLine)) = .empty;
    for (source, 0..) |raw, i| {
        if (std.mem.startsWith(u8, raw, "From ")) {
            h.append(std.ArrayList(h.SourceLine), &messages, .empty);
            continue;
        }
        var arrows: usize = 0;
        while (arrows < raw.len and raw[arrows] == '>') arrows += 1;
        const line = if (arrows > 0 and std.mem.startsWith(u8, raw[arrows..], "From ")) raw[1..] else raw;
        h.append(h.SourceLine, &messages.items[messages.items.len - 1], .{ .number = i + 1, .text = line });
    }
    const result = h.alloc([]const h.SourceLine, messages.items.len);
    for (messages.items, result) |*message, *target| {
        if (message.items.len > 0 and message.items[message.items.len - 1].text.len == 0) message.items.len -= 1;
        target.* = message.items;
    }
    return result;
}

const Sections = struct { head: []const h.SourceLine, body: []const h.SourceLine };

fn splitSections(source: []const h.SourceLine) Sections {
    for (source, 0..) |line, i| if (line.text.len == 0) return .{ .head = source[0..i], .body = source[i + 1 ..] };
    return .{ .head = source, .body = &.{} };
}

fn isMessageId(source: []const u8) bool {
    if (source.len < 3 or source[0] != '<' or source[source.len - 1] != '>') return false;
    const inside = source[1 .. source.len - 1];
    if (inside[0] == '@' or inside[inside.len - 1] == '@') return false;
    var ats: usize = 0;
    for (inside) |character| {
        if (character < 33 or character > 126 or std.mem.indexOfScalar(u8, "<>()\"\\", character) != null) return false;
        ats += @intFromBool(character == '@');
    }
    return ats == 1;
}

fn extractIds(source: []const u8) std.ArrayList([]const u8) {
    var result: std.ArrayList([]const u8) = .empty;
    var position: usize = 0;
    while (std.mem.indexOfScalarPos(u8, source, position, '<')) |start| {
        const end = std.mem.indexOfScalarPos(u8, source, start + 1, '>') orelse break;
        const id = source[start .. end + 1];
        if (isMessageId(id)) h.append([]const u8, &result, id);
        position = end + 1;
    }
    return result;
}

fn parseEntity(message: *Message, number: []const u8, header: h.Header, source: []const h.SourceLine, enabled: bool) *h.Entity {
    const entity = &h.alloc(h.Entity, 1)[0];
    entity.* = .{ .number = number };
    if (enabled) {
        if (header.value("Content-Type")) |value| {
            if (h.parseParameters(value, true)) |parsed| {
                entity.main_type = parsed.main_type;
                entity.subtype = parsed.subtype;
                entity.parameters = parsed;
            } else message.problems.add("bad Content-Type in part {s}", .{number});
        }
        if (header.value("Content-Disposition")) |value| {
            if (h.parseParameters(value, false)) |parsed| {
                entity.disposition = parsed.main_type;
                entity.filename = parsed.get("filename");
            } else message.problems.add("bad Content-Disposition in part {s}", .{number});
        }
    }
    if (entity.filename == null or entity.filename.?.len == 0) entity.filename = entity.parameters.get("name");
    if (h.eq(entity.main_type, "text")) {
        if (entity.parameters.get("charset")) |charset| {
            if (!h.equalCase(charset, "us-ascii")) message.problems.add("unsupported charset \"{s}\" in part {s}", .{ h.lowercase(charset), number });
        }
    }
    if (enabled and h.eq(entity.main_type, "multipart")) {
        const boundary = entity.parameters.get("boundary") orelse "";
        if (boundary.len == 0) {
            message.problems.add("missing boundary in part {s}", .{number});
        } else {
            entity.split = true;
            const opening = h.fmt("--{s}", .{boundary});
            const closing = h.fmt("--{s}--", .{boundary});
            var parts: std.ArrayList([]const h.SourceLine) = .empty;
            var start: ?usize = null;
            var closed = false;
            for (source, 0..) |line, i| {
                const text = h.rstrip(line.text);
                if (h.eq(text, closing)) {
                    if (start) |value| h.append([]const h.SourceLine, &parts, source[value..i]);
                    closed = true;
                    start = null;
                    break;
                }
                if (h.eq(text, opening)) {
                    if (start) |value| h.append([]const h.SourceLine, &parts, source[value..i]);
                    start = i + 1;
                }
            }
            if (start) |value| h.append([]const h.SourceLine, &parts, source[value..]);
            if (parts.items.len == 0) message.problems.add("no parts in part {s}", .{number}) else if (!closed) message.problems.add("unterminated multipart in part {s}", .{number});
            var children: std.ArrayList(*h.Entity) = .empty;
            for (parts.items, 0..) |part, i| {
                const sections = splitSections(part);
                const child_header = h.parseFields(sections.head);
                for (child_header.invalid) |line_number| message.problems.add("bad header line {d}", .{line_number});
                h.append(*h.Entity, &children, parseEntity(message, h.fmt("{s}.{d}", .{ number, i + 1 }), child_header, sections.body, true));
            }
            entity.children = children.items;
            return entity;
        }
    }
    const body = h.alloc([]const u8, source.len);
    for (source, body) |line, *text| text.* = line.text;
    const original = h.join(body, "\n");
    const encoding = if (enabled) h.lowercase(header.value("Content-Transfer-Encoding") orelse "7bit") else "7bit";
    if (h.eq(encoding, "base64")) {
        if (mime.decodeBase64Body(h.allocator, original)) |content| entity.content = content else {
            message.problems.add("bad base64 in part {s}", .{number});
        }
    } else if (h.eq(encoding, "quoted-printable")) {
        const decoded = mime.decodeQuotedPrintable(h.allocator, original);
        entity.content = decoded.text;
        if (decoded.failed) message.problems.add("bad quoted-printable in part {s}", .{number});
    } else {
        entity.content = original;
        if (!h.eq(encoding, "7bit") and !h.eq(encoding, "8bit") and !h.eq(encoding, "binary")) message.problems.add("unknown encoding \"{s}\" in part {s}", .{ encoding, number });
    }
    return entity;
}

fn readRecipients(message: *Message, header: h.Header, name: []const u8) h.Strings {
    const value = header.value(name) orelse return &.{};
    const parsed = addresses.parse(value) orelse {
        message.problems.add("bad {s}", .{name});
        return &.{};
    };
    var result: std.ArrayList([]const u8) = .empty;
    for (parsed.items) |address| {
        if (address.group) {
            for (address.members) |member| h.append([]const u8, &result, member.address);
        } else h.append([]const u8, &result, address.mailbox.?.address);
    }
    if (parsed.encoding_error) message.problems.add("bad encoded word in {s}", .{name});
    return result.items;
}

fn processMessage(message: *Message, source: []const h.SourceLine, earlier: []const Message) void {
    const checked = [_][]const u8{ "From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References", "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition" };
    const sections = splitSections(source);
    const header = h.parseFields(sections.head);
    for (header.invalid) |line_number| message.problems.add("bad header line {d}", .{line_number});
    for (checked) |name| if (header.count(name) > 1) message.problems.add("duplicate {s}", .{name});
    if (header.value("From")) |value| {
        if (addresses.parse(value)) |parsed| {
            if (parsed.items.len == 1 and !parsed.items[0].group) {
                message.sender = parsed.items[0].mailbox;
                if (parsed.encoding_error) message.problems.write("bad encoded word in From");
            } else message.problems.write("bad From");
        } else message.problems.write("bad From");
    } else message.problems.write("missing From");
    message.to = readRecipients(message, header, "To");
    message.cc = readRecipients(message, header, "Cc");
    const subject = h.decodeUnstructured(header.value("Subject") orelse "");
    message.subject = subject.text;
    if (subject.failed) message.problems.write("bad encoded word in Subject");
    message.base_subject = subject.text;
    while (message.base_subject.len >= 3 and h.equalCase(message.base_subject[0..3], "re:")) {
        message.base_subject = std.mem.trimStart(u8, message.base_subject[3..], " ");
        message.reply = true;
    }
    if (header.value("Date")) |value| {
        const parsed = dates.parse(value);
        message.date = parsed.seconds;
        if (parsed.error_text) |error_text| message.problems.write(error_text);
    } else message.problems.write("missing Date");
    if (header.value("Message-ID")) |value| {
        if (!isMessageId(value)) {
            message.problems.write("bad Message-ID");
        } else {
            var duplicate: ?usize = null;
            for (earlier) |previous| {
                if (h.eq(previous.id, value)) { duplicate = previous.number; break; }
            }
            if (duplicate) |number| message.problems.add("Message-ID already used by message {d}", .{number}) else message.id = value;
        }
    } else message.problems.write("missing Message-ID");
    var references = extractIds(header.value("References") orelse "");
    const replies = extractIds(header.value("In-Reply-To") orelse "");
    if (replies.items.len > 0 and (references.items.len == 0 or !h.eq(references.items[references.items.len - 1], replies.items[0]))) h.append([]const u8, &references, replies.items[0]);
    message.references = references.items;
    var enabled = false;
    if (header.value("MIME-Version")) |value| {
        if (h.removeComments(value)) |clean| {
            var compact: h.Text = .{};
            for (clean) |character| if (!h.whitespace(character)) compact.add("{c}", .{character});
            enabled = h.eq(compact.value(), "1.0");
        }
        if (!enabled) message.problems.write("bad MIME-Version");
    }
    message.body = parseEntity(message, "1", header, sections.body, enabled);
}

const LogicalLine = struct { depth: usize, text: []const u8, flowing: bool = false };

fn quotePrefix(depth: usize) []const u8 {
    if (depth == 0) return "";
    const result = h.alloc(u8, depth + 1);
    @memset(result[0..depth], '>');
    result[depth] = ' ';
    return result;
}

fn wrap(text: []const u8, prefix: []const u8, result: *h.Lines) void {
    var current: []const u8 = "";
    for (h.splitWords(text)) |word| {
        if (current.len > 0 and current.len + 1 + word.len > 72) {
            result.add("{s}{s}", .{ prefix, current });
            current = word;
        } else current = if (current.len > 0) h.fmt("{s} {s}", .{ current, word }) else word;
    }
    result.add("{s}{s}", .{ prefix, current });
}

fn flowedLines(content: []const u8, delete_space: bool) h.Lines {
    var result: h.Lines = .{};
    if (content.len == 0) return result;
    var logical: std.ArrayList(LogicalLine) = .empty;
    for (h.split(content, '\n')) |line| {
        var depth: usize = 0;
        while (depth < line.len and line[depth] == '>') depth += 1;
        var text = line[depth..];
        if (text.len > 0 and text[0] == ' ') text = text[1..];
        const flowing = text.len > 0 and text[text.len - 1] == ' ' and !h.eq(text, "-- ");
        const previous = if (logical.items.len > 0) &logical.items[logical.items.len - 1] else null;
        if (previous != null and previous.?.flowing and previous.?.depth == depth) {
            const left = if (delete_space) previous.?.text[0 .. previous.?.text.len - 1] else previous.?.text;
            previous.?.text = h.fmt("{s}{s}", .{ left, text });
            previous.?.flowing = flowing;
        } else h.append(LogicalLine, &logical, .{ .depth = depth, .text = text, .flowing = flowing });
    }
    for (logical.items) |line| wrap(line.text, quotePrefix(line.depth), &result);
    return result;
}

fn referenceValue(name: []const u8) ?u8 {
    const names = [_][]const u8{ "amp", "lt", "gt", "quot", "apos", "nbsp" };
    const values = [_]u8{ '&', '<', '>', '"', '\'', ' ' };
    for (names, values) |candidate, value| if (h.eq(name, candidate)) return value;
    if (name.len >= 2 and name.len <= 4 and name[0] == '#') {
        for (name[1..]) |character| if (character < '0' or character > '9') return null;
        const value = h.number(name[1..]);
        if (value >= 32 and value <= 126) return @intCast(value);
    }
    return null;
}

fn replaceReferences(text: []const u8) []const u8 {
    var result: h.Text = .{};
    var position: usize = 0;
    while (position < text.len) {
        if (text[position] == '&') {
            if (std.mem.indexOfScalarPos(u8, text, position + 1, ';')) |end| {
                if (referenceValue(text[position + 1 .. end])) |replacement| {
                    result.add("{c}", .{replacement});
                    position = end + 1;
                    continue;
                }
            }
        }
        result.add("{c}", .{text[position]});
        position += 1;
    }
    return result.value();
}

fn tagCharacter(character: u8) bool {
    return (character >= 'A' and character <= 'Z') or (character >= 'a' and character <= 'z') or (character >= '0' and character <= '9');
}

fn paragraphTag(name: []const u8) bool {
    const names = [_][]const u8{ "p", "div", "ul", "ol", "table", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6" };
    for (names) |candidate| if (h.eq(name, candidate)) return true;
    return false;
}

fn htmlBlocks(content: []const u8) []LogicalLine {
    var blocks: std.ArrayList(LogicalLine) = .empty;
    var depth: usize = 0;
    var text: h.Text = .{};
    var hide: ?[]const u8 = null;
    var position: usize = 0;
    while (position < content.len) {
        const closing = if (content[position] == '<') std.mem.indexOfScalarPos(u8, content, position + 1, '>') else null;
        if (closing == null) {
            if (hide == null) text.add("{c}", .{content[position]});
            position += 1;
            continue;
        }
        const inside = content[position + 1 .. closing.?];
        position = closing.? + 1;
        const end_tag = inside.len > 0 and inside[0] == '/';
        const start = inside[@intFromBool(end_tag)..];
        var size: usize = 0;
        while (size < start.len and tagCharacter(start[size])) size += 1;
        const name = h.lowercase(start[0..size]);
        if (hide) |hidden| {
            if (end_tag and h.eq(name, hidden)) hide = null;
        } else if (!end_tag and (h.eq(name, "head") or h.eq(name, "style") or h.eq(name, "script"))) {
            hide = name;
        } else if (h.eq(name, "br") or (h.eq(name, "li") and !end_tag)) {
            h.append(LogicalLine, &blocks, .{ .depth = depth, .text = text.value() });
            text = .{};
            if (h.eq(name, "li")) text.write("* ");
        } else if (paragraphTag(name)) {
            h.append(LogicalLine, &blocks, .{ .depth = depth, .text = text.value() });
            h.append(LogicalLine, &blocks, .{ .depth = depth, .text = "" });
            text = .{};
            if (h.eq(name, "blockquote")) {
                if (!end_tag) depth += 1 else if (depth > 0) depth -= 1;
            }
        }
    }
    h.append(LogicalLine, &blocks, .{ .depth = depth, .text = text.value() });
    return blocks.items;
}

fn htmlLines(content: []const u8) h.Lines {
    var result: h.Lines = .{};
    for (htmlBlocks(content)) |block| {
        const replaced = h.alloc(u8, block.text.len);
        for (block.text, replaced) |character, *target| target.* = if (character == '\n') ' ' else character;
        const text = std.mem.trim(u8, replaceReferences(h.collapseWhitespace(replaced)), " ");
        if (text.len > 0) wrap(text, quotePrefix(block.depth), &result) else {
            if (result.data.items.len > 0 and result.data.items[result.data.items.len - 1].len > 0) result.write("");
        }
    }
    while (result.data.items.len > 0 and result.data.items[result.data.items.len - 1].len == 0) result.data.items.len -= 1;
    return result;
}

fn collectTextParts(entity: *h.Entity, allow_html: bool) []*h.Entity {
    var result: std.ArrayList(*h.Entity) = .empty;
    if (!entity.split) {
        if (!h.eq(entity.main_type, "text") or (entity.disposition != null and h.eq(entity.disposition.?, "attachment"))) return result.items;
        if (h.eq(entity.subtype, "plain") or (allow_html and h.eq(entity.subtype, "html"))) h.append(*h.Entity, &result, entity);
        return result.items;
    }
    if (h.eq(entity.subtype, "alternative")) {
        for ([_]bool{ false, true }) |html| {
            for (entity.children) |child| {
                const parts = collectTextParts(child, html);
                if (parts.len > 0) return parts;
            }
        }
        return result.items;
    }
    for (entity.children) |child| {
        for (collectTextParts(child, allow_html)) |part| h.append(*h.Entity, &result, part);
    }
    return result.items;
}

const Display = struct { format: []const u8, lines: h.Lines };

fn displayLines(entity: *h.Entity) Display {
    if (h.eq(entity.subtype, "html")) return .{ .format = "html", .lines = htmlLines(entity.content) };
    const format = entity.parameters.get("format") orelse "";
    if (h.equalCase(format, "flowed")) {
        const delete_space = h.equalCase(entity.parameters.get("delsp") orelse "", "yes");
        return .{ .format = "flowed", .lines = flowedLines(entity.content, delete_space) };
    }
    var result: h.Lines = .{};
    if (entity.content.len > 0) for (h.split(entity.content, '\n')) |line| result.write(line);
    return .{ .format = "plain", .lines = result };
}

fn subjectNotation(subject: []const u8) []const u8 {
    return if (subject.len > 0) subject else "(no subject)";
}

fn dateNotation(date: ?i64) []const u8 {
    return if (date) |seconds| dates.formatUtc(seconds) else "invalid";
}

const ThreadStats = struct {
    messages: usize = 0,
    depth: usize = 0,
    senders: std.ArrayList([]const u8) = .empty,
    rows: h.Lines = .{},
    first: ?i64 = null,
    last: ?i64 = null,
};

fn walkThread(container: *Container, number: usize, depth: usize, prefix: []const u8, stem: []const u8, stats: *ThreadStats) void {
    stats.depth = @max(stats.depth, depth);
    if (container.message) |message| {
        stats.messages += 1;
        message.thread = number;
        message.depth = depth;
        message.parent = if (container.parent) |parent| parent.message else null;
        if (message.sender) |sender| {
            var present = false;
            for (stats.senders.items) |address| if (h.eq(address, sender.address)) { present = true; };
            if (!present) h.append([]const u8, &stats.senders, sender.address);
        }
        if (message.date) |seconds| {
            if (stats.first == null or seconds < stats.first.?) stats.first = seconds;
            if (stats.last == null or seconds > stats.last.?) stats.last = seconds;
        }
        stats.rows.add("{s}[{d}] {s} {s} {s}", .{ prefix, message.number, dateNotation(message.date), if (message.sender) |sender| sender.address else "-", subjectNotation(message.subject) });
    } else if (container.subject) |subject| {
        stats.rows.add("{s}[subject] {s}", .{ prefix, subject });
    } else stats.rows.add("{s}[missing] {s}", .{ prefix, container.id });
    for (container.children.items, 0..) |child, i| {
        const last = i + 1 == container.children.items.len;
        walkThread(child, number, depth + 1, h.fmt("{s}{s}", .{ stem, if (last) "`- " else "+- " }), h.fmt("{s}{s}", .{ stem, if (last) "   " else "|  " }), stats);
    }
}

fn threadReport(root: *Container, number: usize) h.Lines {
    var stats: ThreadStats = .{};
    walkThread(root, number, 0, "", "", &stats);
    var result: h.Lines = .{};
    result.add("thread {d} messages {d} depth {d} senders {d}", .{ number, stats.messages, stats.depth, stats.senders.items.len });
    if (stats.first) |first| result.add("span {s} .. {s}", .{ dates.formatUtc(first), dates.formatUtc(stats.last.?) }) else result.write("span -");
    result.add("subject {s}", .{subjectNotation(root.subject orelse threader.rootSubject(root))});
    for (stats.rows.data.items) |line| result.write(line);
    return result;
}

fn entityLines(entity: *h.Entity, result: *h.Lines) void {
    var line: h.Text = .{};
    line.add("part {s} {s}/{s}", .{ entity.number, entity.main_type, entity.subtype });
    if (!entity.split) {
        line.add(" {d}", .{entity.content.len});
        if (entity.disposition) |disposition| line.add(" {s}", .{disposition});
        if (entity.filename) |filename| if (filename.len > 0) line.add(" \"{s}\"", .{filename});
    }
    result.write(line.value());
    if (entity.split) for (entity.children) |child| entityLines(child, result);
}

fn messageReport(message: *Message) h.Lines {
    var result: h.Lines = .{};
    result.add("message {d}", .{message.number});
    result.add("id {s}", .{if (message.id.len > 0) message.id else "-"});
    result.add("date {s}", .{dateNotation(message.date)});
    const sender_text = if (message.sender) |sender| (if (sender.name.len > 0) h.fmt("{s} <{s}>", .{ sender.name, sender.address }) else sender.address) else "-";
    result.add("from {s}", .{sender_text});
    result.add("to {s}", .{if (message.to.len > 0) h.join(message.to, ", ") else "-"});
    result.add("cc {s}", .{if (message.cc.len > 0) h.join(message.cc, ", ") else "-"});
    result.add("subject {s}", .{subjectNotation(message.subject)});
    result.add("refs {s}", .{if (message.references.len > 0) h.join(message.references, " ") else "-"});
    result.add("thread {d} depth {d} parent {s}", .{ message.thread, message.depth, if (message.parent) |parent| h.fmt("{d}", .{parent.number}) else "-" });
    entityLines(message.body, &result);
    return result;
}

fn bodyReport(request: []const u8, messages: []Message) h.Lines {
    var result: h.Lines = .{};
    result.add("request {s}", .{request});
    var found: ?*Message = null;
    for (messages) |*message| {
        if (message.id.len > 0 and h.eq(message.id, request)) { found = message; break; }
    }
    if (found == null) {
        result.write("not found");
        return result;
    }
    const parts = collectTextParts(found.?.body, true);
    result.add("message {d} text parts {d}", .{ found.?.number, parts.len });
    for (parts) |part| {
        const display = displayLines(part);
        var quoted: usize = 0;
        var signature: usize = 0;
        for (display.lines.data.items, 0..) |*line, i| {
            line.* = h.rstrip(line.*);
            if (line.*.len > 0 and line.*[0] == '>') quoted += 1;
            if (h.eq(line.*, "--")) signature = display.lines.data.items.len - i - 1;
        }
        result.add("part {s} {s} lines {d} quoted {d} signature {d}", .{ part.number, display.format, display.lines.data.items.len, quoted, signature });
        for (display.lines.data.items) |line| result.add("{s}{s}", .{ if (line.len > 0) "| " else "|", line });
    }
    return result;
}

const SenderStats = struct {
    address: []const u8,
    name: []const u8 = "",
    count: usize = 0,
    threads: std.ArrayList(usize) = .empty,
    first: ?i64 = null,
    last: ?i64 = null,
};

fn senderLessThan(_: void, first: SenderStats, second: SenderStats) bool {
    if (first.count != second.count) return first.count > second.count;
    return std.mem.order(u8, first.address, second.address) == .lt;
}

fn csvField(source: []const u8) []const u8 {
    if (std.mem.indexOfAny(u8, source, ",\"") == null) return source;
    var result: h.Text = .{};
    result.write("\"");
    for (source) |character| {
        if (character == '"') result.write("\"\"") else result.add("{c}", .{character});
    }
    result.write("\"");
    return result.value();
}

fn sendersReport(messages: []Message) h.Lines {
    var stats: std.ArrayList(SenderStats) = .empty;
    for (messages) |message| {
        const sender = message.sender orelse continue;
        var index: usize = 0;
        while (index < stats.items.len and !h.eq(stats.items[index].address, sender.address)) index += 1;
        if (index == stats.items.len) h.append(SenderStats, &stats, .{ .address = sender.address });
        const entry = &stats.items[index];
        entry.count += 1;
        var present = false;
        for (entry.threads.items) |number| if (number == message.thread) { present = true; };
        if (!present) h.append(usize, &entry.threads, message.thread);
        if (message.date) |seconds| {
            if (entry.first == null or seconds < entry.first.?) entry.first = seconds;
            if (entry.last == null or seconds > entry.last.?) entry.last = seconds;
        }
        if (sender.name.len > 0) entry.name = sender.name;
    }
    std.mem.sort(SenderStats, stats.items, {}, senderLessThan);
    var result: h.Lines = .{};
    result.write("address,name,messages,threads,first,last");
    for (stats.items) |entry| {
        result.add("{s},{s},{d},{d},{s},{s}", .{ entry.address, csvField(entry.name), entry.count, entry.threads.items.len, if (entry.first) |seconds| dates.formatUtc(seconds) else "-", if (entry.last) |seconds| dates.formatUtc(seconds) else "-" });
    }
    return result;
}

fn malformedReport(messages: []Message) h.Lines {
    var malformed: usize = 0;
    var problems: usize = 0;
    for (messages) |message| {
        malformed += @intFromBool(message.problems.data.items.len > 0);
        problems += message.problems.data.items.len;
    }
    var result: h.Lines = .{};
    result.add("messages {d} malformed {d} problems {d}", .{ messages.len, malformed, problems });
    for (messages) |message| {
        for (message.problems.data.items) |problem| result.add("message {d}: {s}", .{ message.number, problem });
    }
    return result;
}

fn writeLines(io: std.Io, name: []const u8, source: h.Lines) !void {
    var text: h.Text = .{};
    for (source.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = h.fmt("output/{s}", .{name}), .data = text.value() });
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    h.allocator = arena.allocator();
    const raw = try std.Io.Dir.cwd().readFileAlloc(init.io, "input/mailbox.mbox", h.allocator, .unlimited);
    const source = readMailbox(h.lines(raw));
    const messages = h.alloc(Message, source.len);
    for (source, 0..) |lines, i| {
        messages[i] = .{ .number = i + 1 };
        processMessage(&messages[i], lines, messages[0..i]);
    }
    const roots = threader.build(messages);
    var threads: h.Lines = .{};
    var message_lines: h.Lines = .{};
    var bodies: h.Lines = .{};
    for (roots, 0..) |root, i| threads.paragraph(threadReport(root, i + 1));
    for (messages) |*message| {
        if (message.parent) |parent| {
            if (message.date != null and parent.date != null and message.date.? < parent.date.?) message.problems.add("dated before parent message {d}", .{parent.number});
        }
        message_lines.paragraph(messageReport(message));
    }
    const requests = try std.Io.Dir.cwd().readFileAlloc(init.io, "input/requests.txt", h.allocator, .unlimited);
    for (h.lines(requests)) |request| bodies.paragraph(bodyReport(request, messages));
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    try writeLines(init.io, "threads.txt", threads);
    try writeLines(init.io, "messages.txt", message_lines);
    try writeLines(init.io, "bodies.txt", bodies);
    try writeLines(init.io, "senders.csv", sendersReport(messages));
    try writeLines(init.io, "malformed.txt", malformedReport(messages));
}
