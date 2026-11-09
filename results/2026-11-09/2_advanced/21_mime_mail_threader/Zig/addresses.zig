const std = @import("std");
const h = @import("headers.zig");

pub const Mailbox = struct { name: []const u8, address: []const u8 };
pub const Address = struct { group: bool = false, mailbox: ?Mailbox = null, members: []Mailbox = &.{} };
pub const Addresses = struct { items: []Address, encoding_error: bool };

fn dotAtom(tokens: []const h.Token) bool {
    if (tokens.len == 0 or tokens.len % 2 == 0) return false;
    for (tokens, 0..) |token, i| if (token.kind != (if (i % 2 == 0) h.word_kind else '.')) return false;
    return true;
}

fn addressString(local: []const h.Token, domain: []const h.Token) ?[]const u8 {
    if (!dotAtom(local) or !dotAtom(domain)) return null;
    var text: h.Text = .{};
    for (local) |token| text.write(token.text);
    text.write("@");
    for (domain) |token| text.write(token.text);
    return h.lowercase(text.value());
}

const Parser = struct {
    tokens: []const h.Token,
    position: usize = 0,
    encoding_error: bool = false,

    fn peek(self: Parser) u16 {
        return if (self.position < self.tokens.len) self.tokens[self.position].kind else 0;
    }

    fn expect(self: *Parser, kind: u16) bool {
        if (self.peek() != kind) return false;
        self.position += 1;
        return true;
    }

    fn displayName(self: *Parser, phrase: []const h.Token) []const u8 {
        var text: h.Text = .{};
        var previous = false;
        for (phrase, 0..) |token, i| {
            const word = if (token.kind == h.word_kind) h.decodeWord(token.text) else h.DecodedWord{ .text = token.text };
            if (i > 0 and token.spaced and !(word.decoded and previous)) text.write(" ");
            text.write(word.text);
            previous = word.decoded;
            self.encoding_error = self.encoding_error or word.failed;
        }
        return h.collapseWhitespace(text.value());
    }

    fn parseAddress(self: *Parser, in_group: bool) ?Address {
        const phrase_start = self.position;
        while (self.peek() == h.word_kind or self.peek() == h.quoted_kind or self.peek() == '.') self.position += 1;
        const phrase = self.tokens[phrase_start..self.position];
        if (self.peek() == '<') {
            self.position += 1;
            const local_start = self.position;
            while (self.peek() == h.word_kind or self.peek() == '.') self.position += 1;
            const local = self.tokens[local_start..self.position];
            if (!self.expect('@')) return null;
            const domain_start = self.position;
            while (self.peek() == h.word_kind or self.peek() == '.') self.position += 1;
            const domain = self.tokens[domain_start..self.position];
            if (!self.expect('>')) return null;
            const address = addressString(local, domain) orelse return null;
            return .{ .mailbox = .{ .name = self.displayName(phrase), .address = address } };
        }
        if (self.peek() == '@') {
            self.position += 1;
            const domain_start = self.position;
            while (self.peek() == h.word_kind or self.peek() == '.') self.position += 1;
            const address = addressString(phrase, self.tokens[domain_start..self.position]) orelse return null;
            return .{ .mailbox = .{ .name = "", .address = address } };
        }
        if (self.peek() == ':' and phrase.len > 0 and !in_group) {
            self.position += 1;
            var members: std.ArrayList(Mailbox) = .empty;
            if (self.peek() != ';') {
                while (true) {
                    const member = self.parseAddress(true) orelse return null;
                    h.append(Mailbox, &members, member.mailbox.?);
                    if (self.peek() != ',') break;
                    self.position += 1;
                }
            }
            if (!self.expect(';')) return null;
            return .{ .group = true, .members = members.items };
        }
        return null;
    }
};

pub fn parse(source: []const u8) ?Addresses {
    const tokens = h.tokenize(source, false) orelse return null;
    if (tokens.len == 0) return null;
    var parser: Parser = .{ .tokens = tokens };
    var items: std.ArrayList(Address) = .empty;
    while (true) {
        h.append(Address, &items, parser.parseAddress(false) orelse return null);
        if (parser.peek() != ',') break;
        parser.position += 1;
    }
    if (parser.position != tokens.len) return null;
    return .{ .items = items.items, .encoding_error = parser.encoding_error };
}
