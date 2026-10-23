const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Error = Allocator.Error || error{
    Invalid
};

var error_message: Text = "";

fn equal(a: Text, b: Text) bool {
    return std.mem.eql(u8, a, b);
}

fn starts(s: Text, p: Text) bool {
    return std.mem.startsWith(u8, s, p);
}

fn ends(s: Text, p: Text) bool {
    return std.mem.endsWith(u8, s, p);
}

fn before(a: Text, b: Text) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn trim(s: Text) Text {
    return std.mem.trim(u8, s, " ");
}

fn bad(gpa: Allocator, comptime pattern: Text, args: anytype) Error {
    error_message = std.fmt.allocPrint(gpa, pattern, args) catch return error.OutOfMemory;
    return error.Invalid;
}

const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, s: Text) Allocator.Error!void {
        try self.bytes.appendSlice(self.gpa, s);
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

const Cut = struct {
    left: Text,
    right: Text,
    found: bool
};

fn cut(s: Text, separator: u8) Cut {
    if (std.mem.findScalar(u8, s, separator)) |p| return .{
        .left = s[0..p],
        .right = s[p + 1..],
        .found = true
    };
    return .{
        .left = s,
        .right = "",
        .found = false
    };
}

fn split(gpa: Allocator, s: Text, separator: u8) Allocator.Error![]Text {
    var out: std.ArrayList(Text) = .empty;
    var parts = std.mem.splitScalar(u8, s, separator);
    while (parts.next()) |p| try out.append(gpa, p);
    return out.items;
}

fn join(gpa: Allocator, parts: []const Text, separator: Text) Allocator.Error!Text {
    var out: Builder = .{
        .gpa = gpa
    };
    for (parts, 0..) |p,
    i | {
        if (i > 0) try out.add(separator);
        try out.add(p);
    }
    return out.result();
}

fn lower(gpa: Allocator, s: Text) Allocator.Error!Text {
    const out = try gpa.dupe(u8, s);
    for (out) |*c| c.* = std.ascii.toLower(c.*);
    return out;
}

fn digits(s: Text) bool {
    if (s.len == 0) return false;
    for (s) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

fn number(s: Text) usize {
    return std.fmt.parseInt(usize, s, 10) catch unreachable;
}

fn decimalIn(s: Text, minimum: usize, maximum: usize) bool {
    if (!digits(s) or (s.len > 1 and s[0] == '0')) return false;
    const n = std.fmt.parseInt(usize, s, 10) catch return false;
    return n >= minimum and n <= maximum;
}

fn name(s: Text) bool {
    if (s.len == 0 or s.len > 20 or s[0] < 'a' or s[0] > 'z') return false;
    for (s) |c| if (!(c >= 'a' and c <= 'z') and !std.ascii.isDigit(c) and c != '_') return false;
    return true;
}

fn role(s: Text) bool {
    if (s.len == 0 or s.len > 16) return false;
    for (s) |c| if (c < 'a' or c > 'z') return false;
    return true;
}

fn unreserved(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '.' or c == '_' or c == '~';
}

fn segment(s: Text) bool {
    if (s.len == 0 or equal(s, ".") or equal(s, "..")) return false;
    for (s) |c| if (!unreserved(c)) return false;
    return true;
}

fn canonical(s: Text) bool {
    if (equal(s, "/")) return true;
    if (!starts(s, "/")) return false;
    var parts = std.mem.splitScalar(u8, s[1..], '/');
    while (parts.next()) |p| if (!segment(p)) return false;
    return true;
}

fn mediaPart(s: Text) bool {
    if (s.len == 0) return false;
    for (s) |c| if (!(c >= 'a' and c <= 'z') and !std.ascii.isDigit(c) and c != '.' and c != '+' and c != '-') return false;
    return true;
}

fn media(s: Text) bool {
    const parts = cut(s, '/');
    return parts.found and mediaPart(parts.left) and mediaPart(parts.right);
}

fn intValue(s: Text) bool {
    return s.len <= 9 and digits(s);
}

fn slug(s: Text) bool {
    if (s.len == 0) return false;
    for (s) |c| if (!(c >= 'a' and c <= 'z') and !std.ascii.isDigit(c) and c != '-') return false;
    return true;
}

fn hex(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    return null;
}

fn encode(gpa: Allocator, s: Text) Allocator.Error!Text {
    var out: Builder = .{
        .gpa = gpa
    };
    const alphabet = "0123456789ABCDEF";
    for (s) |c| {
        if (unreserved(c)) try out.byte(c) else {
            try out.byte('%');
            try out.byte(alphabet[c >> 4]);
            try out.byte(alphabet[c & 15]);
        }
    }
    return out.result();
}

fn decode(gpa: Allocator, s: Text) Allocator.Error!Text {
    var out: Builder = .{
        .gpa = gpa
    };
    var at: usize = 0;
    while (at < s.len): (at += 1) {
        if (s[at] == '%') {
            try out.byte(hex(s[at + 1]).?*16 + hex(s[at + 2]).?);
            at += 2;
        } else try out.byte(s[at]);
    }
    return out.result();
}

fn escapeCheck(s: Text) bool {
    var at: usize = 0;
    while (at < s.len): (at += 1) if (s[at] == '%') {
        if (at + 2 >= s.len) return false;
        const a = hex(s[at + 1]) orelse return false;
        const b = hex(s[at + 2]) orelse return false;
        const c = a * 16 + b;
        if (c < 32 or c > 126) return false;
        at += 2;
    };
    return true;
}

fn normalize(gpa: Allocator, path: Text) Allocator.Error!Text {
    var out: Builder = .{
        .gpa = gpa
    };
    var at: usize = 0;
    while (at < path.len): (at += 1) {
        if (path[at] == '%') {
            const c = hex(path[at + 1]).?*16 + hex(path[at + 2]).?;
            if (unreserved(c)) try out.byte(c) else {
                try out.byte('%');
                try out.byte(std.ascii.toUpper(path[at + 1]));
                try out.byte(std.ascii.toUpper(path[at + 2]));
            }
            at += 2;
        } else try out.byte(path[at]);
    }
    var parts: std.ArrayList(Text) = .empty;
    var words = std.mem.splitScalar(u8, out.result()[1..], '/');
    while (words.next()) |p| {
        if (equal(p, "..")) {
            if (parts.items.len > 0) parts.items.len -= 1;
        } else if (p.len > 0 and !equal(p, ".")) try parts.append(gpa, p);
    }
    return std.fmt.allocPrint(gpa, "/{s}", .{
        try join(gpa, parts.items, "/")
    });
}

const RulePath = struct {
    base: Text,
    wildcard: bool
};

fn rulePath(s: Text) ?RulePath {
    if (ends(s, "/*")) {
        const base = s[0..s.len - 2];
        if (equal(base, "/") or !canonical(base)) return null;
        return .{
            .base = base,
            .wildcard = true
        };
    }
    return if (canonical(s)).{
        .base = s,
        .wildcard = false
    } else null;
}

const PieceKind = enum {
    literal,
    param,
    integer,
    slug,
    wild
};

const Piece = struct {
    kind: PieceKind,
    name: Text
};

fn parsePattern(gpa: Allocator, pattern: Text) Allocator.Error!?[]Piece {
    if (equal(pattern, "/")) return try gpa.alloc(Piece, 0);
    if (!starts(pattern, "/")) return null;
    const parts = try split(gpa, pattern[1..], '/');
    var out: std.ArrayList(Piece) = .empty;
    var names: std.StringHashMapUnmanaged(void) = .empty;
    for (parts, 0..) |p,
    i | {
        var piece: Piece = .{
            .kind = .literal,
            .name = p
        };
        if (!segment(p)) {
            if (p.len < 3 or p[0] != '{' or p[p.len - 1] != '}') return null;
            const inside = p[1..p.len - 1];
            piece = .{
                .kind = .param,
                .name = inside
            };
            if (starts(inside, "*")) {
                piece.kind = .wild;
                piece.name = inside[1..];
                if (i + 1 != parts.len) return null;
            } else {
                const typed = cut(inside, ':');
                if (typed.found) {
                    piece.name = typed.left;
                    if (equal(typed.right, "int")) piece.kind = .integer else if (equal(typed.right, "slug")) piece.kind = .slug else return null;
                }
            }
            if (!name(piece.name) or names.contains(piece.name)) return null;
            try names.put(gpa, piece.name, { });
        }
        try out.append(gpa, piece);
    }
    return out.items;
}

const method_names = [_]Text {
    "DELETE",
    "GET",
    "HEAD",
    "OPTIONS",
    "PATCH",
    "POST",
    "PUT"
};

fn methodBit(s: Text) ?u16 {
    for (method_names, 0..) |m,
    i | if (equal(m, s)) return @as(u16, 1) << @as(u4, @intCast(i));
    return null;
}

fn methodList(gpa: Allocator, methods: u16, options: bool, separator: Text) Allocator.Error!Text {
    var mask = methods;
    if (mask & methodBit("GET").?!= 0) mask |= methodBit("HEAD").?;
    if (options) mask |= methodBit("OPTIONS").?;
    var parts: std.ArrayList(Text) = .empty;
    for (method_names) |m| if (mask & methodBit(m).?!= 0) {
        try parts.append(gpa, m);
    };
    return join(gpa, parts.items, separator);
}

const Route = struct {
    name: Text,
    pattern: Text,
    role: Text,
    methods: u16,
    pieces: []Piece,
    types: ?[]Text = null,
    number: usize,
    literals: usize = 0,
    typed: usize = 0,
    wild: bool = false,
    selections: usize = 0,
};

fn higher(_: void, a: *Route, b: *Route) bool {
    if (a.literals != b.literals) return a.literals > b.literals;
    if (a.typed != b.typed) return a.typed > b.typed;
    if (a.wild != b.wild) return !a.wild;
    return a.number < b.number;
}

const Redirect = struct {
    from: Text,
    to: Text,
    wildcard: bool,
    code: usize
};

const Client = struct {
    level: usize,
    last: usize,
    allowed: usize = 0,
    limited: usize = 0
};

const Pair = struct {
    name: Text,
    value: Text
};

fn pairBefore(_: void, a: Pair, b: Pair) bool {
    return before(a.name, b.name);
}

fn matches(gpa: Allocator, r: *Route, segments: []const Text) Allocator.Error!?[]Pair {
    const m = r.pieces.len - @intFromBool(r.wild);
    if ((!r.wild and segments.len != m) or (r.wild and segments.len < m)) return null;
    var params: std.ArrayList(Pair) = .empty;
    for (r.pieces, 0..) |p,
    j | {
        if (p.kind == .wild) {
            var values: std.ArrayList(Text) = .empty;
            for (segments[j..]) |x| try values.append(gpa, try decode(gpa, x));
            try params.append(gpa, .{
                .name = p.name,
                .value = try join(gpa, values.items, "/")
            });
            break;
        }
        const x = segments[j];
        switch (p.kind) {
            .literal => if (!equal(p.name, x)) return null,
            .param => try params.append(gpa, .{
                .name = p.name,
                .value = try decode(gpa, x)
            }),
            .integer => {
                if (!intValue(x)) return null;
                try params.append(gpa, .{
                    .name = p.name,
                    .value = try std.fmt.allocPrint(gpa, "{d}", .{
                        number(x)
                    })
                });
            },
            .slug => {
                if (!slug(x)) return null;
                try params.append(gpa, .{
                    .name = p.name,
                    .value = x
                });
            },
            .wild => unreachable,
        }
    }
    std.mem.sort(Pair, params.items, { }, pairBefore);
    return params.items;
}

fn qWeight(s: Text) ?usize {
    const p = cut(s, '.');
    if (!equal(p.left, "0") and !equal(p.left, "1")) return null;
    if (p.found and (p.right.len > 3 or (p.right.len > 0 and !digits(p.right)))) return null;
    if (equal(p.left, "1")) {
        for (p.right) |c| if (c != '0') return null;
        return 1000;
    }
    var weight: usize = 0;
    for (p.right) |c| weight = weight * 10 + c - '0';
    var length = p.right.len;
    while (length < 3): (length += 1) weight *= 10;
    return weight;
}

const AcceptElement = struct {
    range: Text,
    specificity: usize,
    weight: usize
};

fn negotiate(gpa: Allocator, types: []Text, accept: ?Text) Allocator.Error!?Text {
    const header = accept orelse return types[0];
    var elements: std.ArrayList(AcceptElement) = .empty;
    var words = std.mem.splitScalar(u8, header, ',');
    while (words.next()) |text| {
        var fields = std.mem.splitScalar(u8, text, ';');
        const range = try lower(gpa, trim(fields.next().?));
        var specificity: usize = 3;
        if (equal(range, "*/*")) specificity = 1 else if (ends(range, "/*") and mediaPart(range[0..range.len - 2])) specificity = 2 else if (!media(range)) continue;
        var weight: ?usize = 1000;
        while (fields.next()) |field| {
            const p = cut(trim(field), '=');
            if (p.found and equal(try lower(gpa, trim(p.left)), "q")) {
                weight = qWeight(trim(p.right));
                break;
            }
        }
        if (weight) |w| try elements.append(gpa, .{
            .range = range,
            .specificity = specificity,
            .weight = w
        });
    }
    var selected: ?Text = null;
    var best: usize = 0;
    for (types) |t| {
        var specificity: usize = 0;
        var weight: usize = 0;
        const main = cut(t, '/').left;
        for (elements.items) |e| {
            const fits = equal(e.range, "*/*") or equal(e.range, t) or (ends(e.range, "/*") and equal(e.range[0..e.range.len - 2], main));
            if (fits and e.specificity > specificity) {
                specificity = e.specificity;
                weight = e.weight;
            }
        }
        if (weight > best) {
            best = weight;
            selected = t;
        }
    }
    return selected;
}

fn quoted(gpa: Allocator, s: Text) Allocator.Error!Text {
    var out: Builder = .{
        .gpa = gpa
    };
    try out.byte('"');
    for (s) |c| {
        if (c == '\\' or c == '"') try out.byte('\\');
        try out.byte(c);
    }
    try out.byte('"');
    return out.result();
}

fn html(gpa: Allocator, s: Text) Allocator.Error!Text {
    var out: Builder = .{
        .gpa = gpa
    };
    for (s) |c| switch (c) {
        '&' => try out.add("&amp;"),
        '<' => try out.add("&lt;"),
        '>' => try out.add("&gt;"),
        '"' => try out.add("&quot;"),
        else => try out.byte(c)
    };
    return out.result();
}

fn jsonObject(gpa: Allocator, pairs: []const Pair) Allocator.Error!Text {
    var out: Builder = .{
        .gpa = gpa
    };
    try out.byte('{');
    for (pairs, 0..) |p,
    i | {
        if (i > 0) try out.byte(',');
        try out.print("{s}:{s}", .{
            try quoted(gpa, p.name),
            try quoted(gpa, p.value)
        });
    }
    try out.byte('}');
    return out.result();
}

fn encodedPairs(gpa: Allocator, pairs: []const Pair) Allocator.Error!Text {
    if (pairs.len == 0) return "-";
    var out: Builder = .{
        .gpa = gpa
    };
    for (pairs, 0..) |p,
    i | {
        if (i > 0) try out.byte('&');
        try out.print("{s}={s}", .{
            try encode(gpa, p.name),
            try encode(gpa, p.value)
        });
    }
    return out.result();
}

fn queryDecode(gpa: Allocator, s: Text) Allocator.Error!Text {
    const bytes = try gpa.dupe(u8, s);
    for (bytes) |*c| if (c.* == '+') {
        c.* = ' ';
    };
    return decode(gpa, bytes);
}

fn bodyFor(gpa: Allocator, r: *Route, params: []Pair, query: Text, headers: std.StringHashMapUnmanaged(Text), selected: Text) Allocator.Error!Text {
    var queries: std.ArrayList(Pair) = .empty;
    var cookies: std.ArrayList(Pair) = .empty;
    var parts = std.mem.splitScalar(u8, query, '&');
    while (parts.next()) |text| {
        if (text.len == 0) continue;
        const p = cut(text, '=');
        try queries.append(gpa, .{
            .name = try queryDecode(gpa, p.left),
            .value = try queryDecode(gpa, p.right)
        });
    }
    if (headers.get("cookie")) |cookie| {
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        var words = std.mem.splitScalar(u8, cookie, ';');
        while (words.next()) |text| {
            const p = cut(trim(text), '=');
            if (p.found and p.left.len > 0 and !seen.contains(p.left)) {
                try seen.put(gpa, p.left, { });
                try cookies.append(gpa, .{
                    .name = p.left,
                    .value = p.right
                });
            }
        }
    }
    std.mem.sort(Pair, cookies.items, { }, pairBefore);
    var out: Builder = .{
        .gpa = gpa
    };
    if (equal(selected, "application/json")) {
        try out.add("{\"route\":");
        try out.add(try quoted(gpa, r.name));
        try out.add(",\"params\":");
        try out.add(try jsonObject(gpa, params));
        try out.add(",\"query\":[");
        for (queries.items, 0..) |p,
        i | {
            if (i > 0) try out.byte(',');
            try out.print("[{s},{s}]", .{
                try quoted(gpa, p.name),
                try quoted(gpa, p.value)
            });
        }
        try out.add("],\"cookies\":");
        try out.add(try jsonObject(gpa, cookies.items));
        try out.byte('}');
    } else if (equal(selected, "text/html")) {
        try out.print("<dl><dt>route</dt><dd>{s}</dd>", .{
            try html(gpa, r.name)
        });
        const lists = [_][]const Pair {
            params,
            queries.items,
            cookies.items
        };
        const labels = [_]Text {
            "param",
            "query",
            "cookie"
        };
        for (lists, labels) |pairs,
        label | for (pairs) |p| {
            try out.print("<dt>{s} {s}</dt><dd>{s}</dd>", .{
                label,
                try html(gpa, p.name),
                try html(gpa, p.value)
            });
        };
        try out.add("</dl>");
    } else try out.print("route={s} params={s} query={s} cookies={s}", .{
        r.name,
        try encodedPairs(gpa, params),
        try encodedPairs(gpa, queries.items),
        try encodedPairs(gpa, cookies.items)
    });
    return out.result();
}

fn etag(gpa: Allocator, body: Text) Allocator.Error!Text {
    var a: u32 = 1;
    var b: u32 = 0;
    for (body) |c| {
        a = (a + c) % 65521;
        b = (b + a) % 65521;
    }
    return std.fmt.allocPrint(gpa, "\"{x:0>4}{x:0>4}\"", .{
        b,
        a
    });
}

const header_names = [_]Text {
    "Location",
    "Allow",
    "Retry-After",
    "WWW-Authenticate",
    "Access-Control-Allow-Origin",
    "Access-Control-Allow-Methods",
    "Vary",
    "ETag",
    "Content-Type",
    "Content-Length"
};

const Response = struct {
    status: usize,
    body: Text,
    headers: [10]?Text = @splat(null),
    content_type: Text = "text/plain",
    head: bool = false
};

fn reply(status: usize, body: Text) Response {
    return .{
        .status = status,
        .body = body
    };
}

fn phrase(status: usize) Text {
    return switch (status) {
        200 => "OK",
        204 => "No Content",
        301 => "Moved Permanently",
        302 => "Found",
        304 => "Not Modified",
        307 => "Temporary Redirect",
        308 => "Permanent Redirect",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        406 => "Not Acceptable",
        412 => "Precondition Failed",
        429 => "Too Many Requests",
        501 => "Not Implemented",
        else => unreachable
    };
}

const Router = struct {
    gpa: Allocator,
    out: Builder,
    routes: std.ArrayList(*Route) = .empty,
    priority: []* Route = &.{ },
    by_name: std.StringHashMapUnmanaged(*Route) = .empty,
    tokens: std.StringHashMapUnmanaged(Text) = .empty,
    redirects: std.ArrayList(Redirect) = .empty,
    origins: std.StringHashMapUnmanaged(void) = .empty,
    clients: std.StringHashMapUnmanaged(*Client) = .empty,
    statuses: [502]usize = @splat(0),
    capacity: usize = 0,
    period: usize = 0,
    errors: usize = 0,
    requests: usize = 0,
    url_ok: usize = 0,
    url_error: usize = 0,
    fn config(self: *Router, w: []Text) Error!void {
        const cmd = w[0];
        const n = w.len - 1;
        const gpa = self.gpa;
        const known = equal(cmd, "ROUTE") or equal(cmd, "TOKEN") or equal(cmd, "REDIRECT") or equal(cmd, "ORIGIN") or equal(cmd, "LIMIT") or equal(cmd, "TYPES");
        if (!known) return bad(gpa, "unknown command {s}", .{
            cmd
        });
        const count_ok = (equal(cmd, "ROUTE") and (n == 3 or n == 5)) or ((equal(cmd, "TOKEN") or equal(cmd, "LIMIT")) and n == 2) or (equal(cmd, "REDIRECT") and n == 3) or (equal(cmd, "ORIGIN") and n == 1) or (equal(cmd, "TYPES") and n >= 2);
        if (!count_ok) return bad(gpa, "wrong number of arguments", .{ });
        if (equal(cmd, "ROUTE")) {
            if (!name(w[1])) return bad(gpa, "bad route name {s}", .{
                w[1]
            });
            if (self.by_name.contains(w[1])) return bad(gpa, "duplicate route {s}", .{
                w[1]
            });
            var methods: u16 = 0;
            var words = std.mem.splitScalar(u8, w[2], ',');
            while (words.next()) |m| {
                const bit = methodBit(m) orelse return bad(gpa, "bad methods {s}", .{
                    w[2]
                });
                if (equal(m, "HEAD") or equal(m, "OPTIONS") or methods & bit != 0) return bad(gpa, "bad methods {s}", .{
                    w[2]
                });
                methods |= bit;
            }
            const pieces = (try parsePattern(gpa, w[3])) orelse return bad(gpa, "bad pattern {s}", .{
                w[3]
            });
            var route_role: Text = "";
            if (n == 5) {
                if (!equal(w[4], "ROLE")) return bad(gpa, "unknown option {s}", .{
                    w[4]
                });
                if (!role(w[5])) return bad(gpa, "bad role {s}", .{
                    w[5]
                });
                route_role = if (equal(w[5], "none")) "" else w[5];
            }
            const r = try gpa.create(Route);
            r.* = .{
                .name = w[1],
                .pattern = w[3],
                .role = route_role,
                .methods = methods,
                .pieces = pieces,
                .number = self.routes.items.len
            };
            for (pieces) |p| switch (p.kind) {
                .literal => r.literals += 1,
                .integer,
                .slug => r.typed += 1,
                .wild => r.wild = true,
                else => { }
            };
            try self.routes.append(gpa, r);
            try self.by_name.put(gpa, r.name, r);
        } else if (equal(cmd, "TOKEN")) {
            var valid = w[1].len >= 1 and w[1].len <= 32;
            for (w[1]) |c| if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '_' and c != '-') {
                valid = false;
            };
            if (!valid) return bad(gpa, "bad token {s}", .{
                w[1]
            });
            if (self.tokens.contains(w[1])) return bad(gpa, "duplicate token {s}", .{
                w[1]
            });
            if (!role(w[2])) return bad(gpa, "bad role {s}", .{
                w[2]
            });
            try self.tokens.put(gpa, w[1], w[2]);
        } else if (equal(cmd, "REDIRECT")) {
            const from = rulePath(w[1]) orelse return bad(gpa, "bad path {s}", .{
                w[1]
            });
            const to = rulePath(w[2]) orelse return bad(gpa, "bad path {s}", .{
                w[2]
            });
            if (from.wildcard != to.wildcard) return bad(gpa, "wildcard mismatch", .{ });
            if (!equal(w[3], "301") and !equal(w[3], "302") and !equal(w[3], "307") and !equal(w[3], "308")) return bad(gpa, "bad redirect code {s}", .{
                w[3]
            });
            for (self.redirects.items) |r| if (equal(r.from, from.base) and r.wildcard == from.wildcard) return bad(gpa, "duplicate redirect {s}", .{
                w[1]
            });
            try self.redirects.append(gpa, .{
                .from = from.base,
                .to = to.base,
                .wildcard = from.wildcard,
                .code = number(w[3])
            });
        } else if (equal(cmd, "ORIGIN")) {
            const origin = w[1];
            var host: Text = "";
            if (starts(origin, "http://")) host = origin[7..] else if (starts(origin, "https://")) host = origin[8..];
            var valid = host.len > 0;
            for (host) |c| if (!(c >= 'a' and c <= 'z') and !std.ascii.isDigit(c) and c != '.' and c != '-' and c != ':') {
                valid = false;
            };
            if (!valid) return bad(gpa, "bad origin {s}", .{
                origin
            });
            if (self.origins.contains(origin)) return bad(gpa, "duplicate origin {s}", .{
                origin
            });
            try self.origins.put(gpa, origin, { });
        } else if (equal(cmd, "LIMIT")) {
            if (!decimalIn(w[1], 1, 100) or !decimalIn(w[2], 1, 3600)) return bad(gpa, "bad limit", .{ });
            if (self.capacity > 0) return bad(gpa, "duplicate limit", .{ });
            self.capacity = number(w[1]);
            self.period = number(w[2]);
        } else if (equal(cmd, "TYPES")) {
            const r = self.by_name.get(w[1]) orelse return bad(gpa, "unknown route {s}", .{
                w[1]
            });
            if (r.types != null) return bad(gpa, "duplicate types {s}", .{
                w[1]
            });
            var seen: std.StringHashMapUnmanaged(void) = .empty;
            for (w[2..]) |t| {
                if (!media(t)) return bad(gpa, "bad media type {s}", .{
                    t
                });
                if (seen.contains(t)) return bad(gpa, "duplicate media type {s}", .{
                    t
                });
                try seen.put(gpa, t, { });
            }
            r.types = try gpa.dupe(Text, w[2..]);
        }
    }
    fn table(self: *Router) Error!void {
        const limit = if (self.capacity > 0) try std.fmt.allocPrint(self.gpa, "{d}/{d}", .{
            self.capacity,
            self.period
        }) else "none";
        try self.out.line("CONFIG routes={d} tokens={d} redirects={d} origins={d} limit={s} errors={d}", .{
            self.routes.items.len,
            self.tokens.count(),
            self.redirects.items.len,
            self.origins.count(),
            limit,
            self.errors
        });
        self.priority = try self.gpa.dupe(*Route, self.routes.items);
        std.mem.sort(*Route, self.priority, { }, higher);
        for (self.priority, 0..) |r,
        i | {
            if (r.types == null) {
                const types = try self.gpa.alloc(Text, 1);
                types[0] = "application/json";
                r.types = types;
            }
            try self.out.line("TABLE {d} {s} {s} {s} role={s} types={s}", .{
                i + 1,
                r.name,
                try methodList(self.gpa, r.methods, false, ","),
                r.pattern,
                if (r.role.len == 0) "-" else r.role,
                try join(self.gpa, r.types.?, ",")
            });
        }
    }
    fn dispatch(self: *Router, method: Text, target: Text, h: std.StringHashMapUnmanaged(Text)) Error!Response {
        const gpa = self.gpa;
        if (methodBit(method) == null) return reply(501, try std.fmt.allocPrint(gpa, "not implemented: {s}", .{
            method
        }));
        const host = h.get("host") orelse "";
        if (host.len == 0) return reply(400, "bad request: missing host");
        var effective = method;
        if (h.get("x-http-method-override")) |override| {
            if (equal(method, "POST") and (equal(override, "PUT") or equal(override, "PATCH") or equal(override, "DELETE"))) effective = override else return reply(400, "bad request: method override");
        }
        if (h.get("x-client")) |c| if (c.len > 0) {
            const t = number(h.get("x-time").?);
            var record: *Client = undefined;
            if (self.clients.get(c)) |existing| record = existing else {
                record = try gpa.create(Client);
                record.* = .{
                    .level = self.capacity * self.period,
                    .last = t
                };
                try self.clients.put(gpa, c, record);
            }
            if (self.capacity > 0) {
                record.level = @min(self.capacity * self.period, record.level + (t - record.last) * self.capacity);
                record.last = t;
                if (record.level < self.period) {
                    record.limited += 1;
                    const wait = (self.period - record.level + self.capacity - 1) / self.capacity;
                    var response = reply(429, try std.fmt.allocPrint(gpa, "too many requests: client {s}", .{
                        c
                    }));
                    response.headers[2] = try std.fmt.allocPrint(gpa, "{d}", .{
                        wait
                    });
                    return response;
                }
                record.level -= self.period;
            }
            record.allowed += 1;
        };
        const p = cut(target, '?');
        const path = p.left;
        const query = p.right;
        const suffix = if (p.found) try std.fmt.allocPrint(gpa, "?{s}", .{
            query
        }) else "";
        const normalized = try normalize(gpa, path);
        if (!equal(normalized, path)) {
            const location = try std.fmt.allocPrint(gpa, "{s}{s}", .{
                normalized,
                suffix
            });
            var response = reply(308, try std.fmt.allocPrint(gpa, "redirect to {s}", .{
                location
            }));
            response.headers[0] = location;
            return response;
        }
        for (self.redirects.items) |r| {
            const prefix = try std.fmt.allocPrint(gpa, "{s}/", .{
                r.from
            });
            if (equal(path, r.from) or (r.wildcard and starts(path, prefix))) {
                const location = try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{
                    r.to,
                    path[r.from.len..],
                    suffix
                });
                var response = reply(r.code, try std.fmt.allocPrint(gpa, "redirect to {s}", .{
                    location
                }));
                response.headers[0] = location;
                return response;
            }
        }
        const segments = if (equal(path, "/")) try gpa.alloc(Text, 0) else try split(gpa, path[1..], '/');
        const Match = struct {
            route: *Route,
            params: []Pair
        };
        var matching: std.ArrayList(Match) = .empty;
        var allowed: u16 = 0;
        for (self.priority) |r| if (try matches(gpa, r, segments)) |params| {
            try matching.append(gpa, .{
                .route = r,
                .params = params
            });
            allowed |= r.methods;
        };
        if (matching.items.len == 0) return reply(404, try std.fmt.allocPrint(gpa, "not found: {s}", .{
            path
        }));
        const allow = try methodList(gpa, allowed, true, ", ");
        if (equal(effective, "OPTIONS")) {
            var response = reply(204, "");
            response.headers[1] = allow;
            return response;
        }
        const lookup = if (equal(effective, "HEAD")) "GET" else effective;
        var selected: ?Match = null;
        for (matching.items) |m| if (m.route.methods & methodBit(lookup).?!= 0) {
            selected = m;
            break;
        };
        const selected_match = selected orelse {
            var response = reply(405, try std.fmt.allocPrint(gpa, "method not allowed: {s}", .{
                effective
            }));
            response.headers[1] = allow;
            return response;
        };
        const r = selected_match.route;
        r.selections += 1;
        if (r.role.len > 0) {
            const authorization = h.get("authorization") orelse {
                var response = reply(401, "unauthorized: missing token");
                response.headers[3] = "Bearer realm=\"api\"";
                return response;
            };
            const auth = cut(authorization, ' ');
            const token_role = self.tokens.get(auth.right);
            if (!equal(try lower(gpa, auth.left), "bearer") or token_role == null) {
                var response = reply(401, "unauthorized: invalid token");
                response.headers[3] = "Bearer realm=\"api\", error=\"invalid_token\"";
                return response;
            }
            if (!equal(token_role.?, r.role) and !equal(token_role.?, "admin")) return reply(403, try std.fmt.allocPrint(gpa, "forbidden: requires role {s}", .{
                r.role
            }));
        }
        const selected_type = try negotiate(gpa, r.types.?, h.get("accept"));
        var response: Response = undefined;
        if (selected_type) |t| {
            const body = try bodyFor(gpa, r, selected_match.params, query, h, t);
            const tag = try etag(gpa, body);
            var conditional = false;
            if (h.get("if-none-match")) |condition| {
                var values = std.mem.splitScalar(u8, condition, ',');
                while (values.next()) |text| {
                    var item = trim(text);
                    if (starts(item, "W/")) item = item[2..];
                    if (equal(item, "*") or equal(item, tag)) {
                        conditional = true;
                        break;
                    }
                }
            }
            if (conditional) {
                if (equal(lookup, "GET")) {
                    response = reply(304, "");
                    response.headers[7] = tag;
                } else response = reply(412, try std.fmt.allocPrint(gpa, "precondition failed: {s}", .{
                    tag
                }));
            } else {
                response = reply(200, body);
                response.content_type = t;
                response.headers[7] = tag;
            }
        } else response = reply(406, try std.fmt.allocPrint(gpa, "not acceptable: {s}", .{
            try join(gpa, r.types.?, ", ")
        }));
        if (r.types.?.len > 1) response.headers[6] = "Accept";
        return response;
    }
    fn early(head: bool, body: Text) Response {
        var response = reply(400, body);
        response.head = head;
        return response;
    }
    fn request(self: *Router, line: Text, header_lines: []Text) Error!Response {
        const parts = try split(self.gpa, line, ' ');
        var valid_method = parts.len == 3;
        if (valid_method) {
            valid_method = parts[0].len >= 1 and parts[0].len <= 16;
            for (parts[0]) |c| if (c < 'A' or c > 'Z') {
                valid_method = false;
            };
        }
        if (parts.len != 3 or !valid_method or !starts(parts[1], "/") or std.mem.findScalar(u8, parts[1], '#') != null or !equal(parts[2], "HTTP/1.1")) return reply(400, "bad request: request line");
        const head = equal(parts[0], "HEAD");
        if (!escapeCheck(parts[1])) return early(head, "bad request: percent escape");
        var h: std.StringHashMapUnmanaged(Text) = .empty;
        for (header_lines, 0..) |text,
        i | {
            const p = cut(text, ':');
            var valid = p.found and p.left.len > 0;
            for (p.left) |c| if (!std.ascii.isAlphanumeric(c) and c != '-') {
                valid = false;
            };
            if (!valid) return early(head, try std.fmt.allocPrint(self.gpa, "bad request: header line {d}", .{
                i + 1
            }));
            const header_name = try lower(self.gpa, p.left);
            if (h.contains(header_name)) return early(head, try std.fmt.allocPrint(self.gpa, "bad request: duplicate header {s}", .{
                header_name
            }));
            try h.put(self.gpa, header_name, trim(p.right));
        }
        var response = try self.dispatch(parts[0], parts[1], h);
        response.head = head;
        if (h.get("origin")) |origin| if (self.origins.contains(origin)) {
            response.headers[4] = origin;
            if (response.status == 204 and h.contains("access-control-request-method")) response.headers[5] = response.headers[1];
        };
        return response;
    }
    fn printResponse(self: *Router, original: Response) Error!void {
        var response = original;
        self.requests += 1;
        self.statuses[response.status] += 1;
        if (response.status != 204 and response.status != 304) {
            response.headers[8] = if (response.status == 200) response.content_type else "text/plain";
            response.headers[9] = try std.fmt.allocPrint(self.gpa, "{d}", .{
                response.body.len
            });
        }
        try self.out.line("REQUEST {d}", .{
            self.requests
        });
        try self.out.line("HTTP/1.1 {d} {s}", .{
            response.status,
            phrase(response.status)
        });
        for (header_names, response.headers) |header_name,
        v | if (v) |text| {
            try self.out.line("{s}: {s}", .{
                header_name,
                text
            });
        };
        if (response.status != 204 and response.status != 304 and !response.head) try self.out.line("{s}", .{
            response.body
        });
    }
    fn urlfor(self: *Router, w: []Text) Error!Text {
        const gpa = self.gpa;
        const route_name = w[1];
        const r = self.by_name.get(route_name) orelse return bad(gpa, "unknown route {s}", .{
            route_name
        });
        var parameters: std.StringHashMapUnmanaged(void) = .empty;
        for (r.pieces) |p| if (p.kind != .literal) {
            try parameters.put(gpa, p.name, { });
        };
        var values: std.StringHashMapUnmanaged(Text) = .empty;
        var query: std.ArrayList(Pair) = .empty;
        for (w[2..]) |arg| {
            const p = cut(arg, '=');
            if (!p.found or p.left.len == 0) return bad(gpa, "bad argument {s}", .{
                arg
            });
            if (parameters.contains(p.left)) {
                if (values.contains(p.left)) return bad(gpa, "duplicate parameter {s}", .{
                    p.left
                });
                try values.put(gpa, p.left, p.right);
            } else try query.append(gpa, .{
                .name = p.left,
                .value = p.right
            });
        }
        var path: std.ArrayList(Text) = .empty;
        for (r.pieces) |p| {
            if (p.kind == .literal) {
                try path.append(gpa, p.name);
                continue;
            }
            const argument = values.get(p.name);
            if (p.kind != .wild and argument == null) return bad(gpa, "missing parameter {s}", .{
                p.name
            });
            const v = argument orelse "";
            var valid = true;
            switch (p.kind) {
                .param => valid = v.len > 0 and !equal(v, ".") and !equal(v, ".."),
                .integer => valid = intValue(v),
                .slug => valid = slug(v),
                .wild => if (v.len > 0) {
                    var segments = std.mem.splitScalar(u8, v, '/');
                    while (segments.next()) |part| if (part.len == 0 or equal(part, ".") or equal(part, "..")) {
                        valid = false;
                        break;
                    };
                },
                .literal => unreachable,
            }
            if (!valid) return bad(gpa, "bad value for {s}", .{
                p.name
            });
            if (p.kind == .wild) {
                if (v.len > 0) {
                    var segments = std.mem.splitScalar(u8, v, '/');
                    while (segments.next()) |part| try path.append(gpa, try encode(gpa, part));
                }
            } else try path.append(gpa, try encode(gpa, v));
        }
        var url: Builder = .{
            .gpa = gpa
        };
        try url.byte('/');
        try url.add(try join(gpa, path.items, "/"));
        if (query.items.len > 0) {
            try url.byte('?');
            try url.add(try encodedPairs(gpa, query.items));
        }
        return std.fmt.allocPrint(gpa, "URLFOR {s} {s}", .{
            route_name,
            url.result()
        });
    }
    fn summary(self: *Router) Error!void {
        try self.out.line("SUMMARY requests={d} urlfor_ok={d} urlfor_error={d}", .{
            self.requests,
            self.url_ok,
            self.url_error
        });
        for (self.statuses, 0..) |count,
        code | if (count > 0) {
            try self.out.line("STATUS {d} {d}", .{
                code,
                count
            });
        };
        for (self.routes.items) |r| try self.out.line("ROUTE {s} {d}", .{
            r.name,
            r.selections
        });
        var names: std.ArrayList(Text) = .empty;
        var it = self.clients.keyIterator();
        while (it.next()) |key| try names.append(self.gpa, key.*);
        std.mem.sort(Text, names.items, { }, struct {
            fn less(_: void, a: Text, b: Text) bool {
                return before(a, b);
            }
        }.less);
        for (names.items) |c| {
            const record = self.clients.get(c).?;
            try self.out.line("CLIENT {s} allowed={d} limited={d}", .{
                c,
                record.allowed,
                record.limited
            });
        }
    }
    fn run(self: *Router, lines: []Text) Error!void {
        var at: usize = 0;
        while (!equal(lines[at], "REQUESTS")): (at += 1) {
            self.config(try split(self.gpa, lines[at], ' ')) catch | err | {
                if (err != error.Invalid) return err;
                self.errors += 1;
                try self.out.line("CONFIG ERROR {d}: {s}", .{
                    at + 1,
                    error_message
                });
            };
        }
        at += 1;
        try self.table();
        while (!equal(lines[at], "END")) {
            const line = lines[at];
            at += 1;
            if (starts(line, "URLFOR ")) {
                const result = self.urlfor(try split(self.gpa, line, ' ')) catch | err | {
                    if (err != error.Invalid) return err;
                    self.url_error += 1;
                    try self.out.line("URLFOR ERROR {s}", .{
                        error_message
                    });
                    continue;
                };
                self.url_ok += 1;
                try self.out.line("{s}", .{
                    result
                });
            } else {
                const start = at;
                while (lines[at].len > 0): (at += 1) { }
                const headers = lines[start..at];
                at += 1;
                try self.printResponse(try self.request(line, headers));
            }
        }
        try self.summary();
    }
};

pub fn main(init: std.process.Init)!void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    const gpa = storage.allocator();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, & input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, & output_buffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var router: Router = .{
        .gpa = gpa,
        .out = .{
            .gpa = gpa
        }
    };
    try router.run(try split(gpa, text, '\n'));
    try output.interface.writeAll(router.out.result());
    try output.interface.flush();
}
