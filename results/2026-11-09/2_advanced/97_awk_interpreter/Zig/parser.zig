const std = @import("std");
const lex = @import("lexer.zig");
const values = @import("values_fields.zig");
pub const Node = struct {
    kind: values.Text, token: lex.Token, name: values.Text = "", op: values.Text = "", args: []*Node = &.{}, params: []*Node = &.{},
    x: ?*Node = null, y: ?*Node = null, z: ?*Node = null, w: ?*Node = null, flag: bool = false, delta: i64 = 0, binding: ?usize = null, redir: ?lex.Token = null,
    pub fn is(n: *const Node, kind: values.Text) bool { return values.eq(n.kind, kind); }
    pub fn lvalue(n: *const Node) bool { return n.is("name") or n.is("array") or n.is("field"); }
};
pub const Parser = struct {
    a: std.mem.Allocator, tokens: []const lex.Token, p: usize = 0, issue: lex.Position = .{}, in_function: bool = false, phase: values.Text = "", loops: usize = 0,
    fn peek(p: *Parser) lex.Token { return p.tokens[p.p]; }
    fn at(p: *Parser, s: values.Text) bool { return values.eq(p.peek().spelling, s); }
    fn take(p: *Parser) lex.Token { const t = p.peek(); p.p += 1; return t; }
    fn fail(p: *Parser, pos: lex.Position) error{Syntax} { p.issue = pos; return error.Syntax; }
    fn expect(p: *Parser, s: values.Text) !lex.Token { if (!p.at(s)) return p.fail(p.peek().position); return p.take(); }
    fn accept(p: *Parser, s: values.Text) bool { if (p.at(s)) { p.p += 1; return true; } return false; }
    fn newlines(p: *Parser) void { while (p.accept("\n")) {} }
    fn node(p: *Parser, kind: values.Text, token: lex.Token) !*Node { const n = try p.a.create(Node); n.* = .{ .kind = kind, .token = token }; return n; }
    fn name(p: *Parser) !*Node { if (p.peek().kind != .name) return p.fail(p.peek().position); const t = p.take(); const n = try p.node("name", t); n.name = t.spelling; return n; }
    fn binary(p: *Parser, t: lex.Token, op: values.Text, left: *Node, right: *Node) !*Node { const n = try p.node("binary", t); n.op = op; n.x = left; n.y = right; return n; }
    pub fn parse(p: *Parser) ![]*Node {
        var items: std.ArrayList(*Node) = .empty;
        while (p.peek().kind != .eof) {
            if (p.accept("\n") or p.accept(";")) continue; const t = p.peek();
            if (p.accept("function")) {
                if (p.peek().kind != .name and p.peek().kind != .function_name) return p.fail(p.peek().position); const name_token = p.take(); const n = try p.node("function", name_token); n.name = name_token.spelling; _ = try p.expect("("); var params: std.ArrayList(*Node) = .empty;
                if (!p.at(")")) while (true) { const param = try p.name(); param.kind = "parameter"; try params.append(p.a, param); if (!p.accept(",")) break; p.newlines(); };
                _ = try p.expect(")"); p.newlines(); p.in_function = true; n.x = try p.block(); p.in_function = false; n.params = params.items; try items.append(p.a, n); continue;
            }
            const n = try p.node("rule", t); var patterns: std.ArrayList(*Node) = .empty;
            if (p.at("BEGIN") or p.at("END")) n.op = p.take().spelling
            else if (p.at("{")) n.op = "all"
            else { try patterns.append(p.a, try p.expression(true)); if (p.accept(",")) { p.newlines(); try patterns.append(p.a, try p.expression(true)); } n.op = if (patterns.items.len == 2) "range" else "pattern"; }
            n.args = patterns.items; p.phase = n.op;
            if (lex.member(n.op, "BEGIN END all") or p.at("{")) n.x = try p.block() else if (!p.at("\n") and !p.at(";") and p.peek().kind != .eof) return p.fail(p.peek().position);
            p.phase = ""; try items.append(p.a, n);
        }
        return items.items;
    }
    fn block(p: *Parser) anyerror!*Node {
        const n = try p.node("block", try p.expect("{")); var list: std.ArrayList(*Node) = .empty;
        while (!p.at("}")) { if (p.peek().kind == .eof) return p.fail(p.peek().position); if (p.accept("\n") or p.accept(";")) continue; try list.append(p.a, try p.statement()); }
        _ = p.take(); n.args = list.items; return n;
    }
    fn condition(p: *Parser) !*Node { _ = try p.expect("("); const n = try p.expression(true); _ = try p.expect(")"); return n; }
    fn body(p: *Parser) !*Node { p.newlines(); p.loops += 1; const n = try p.statement(); p.loops -= 1; return n; }
    fn terminator(p: *Parser) !void { if (!p.accept(";") and !p.accept("\n") and !p.at("}")) return p.fail(p.peek().position); }
    fn statement(p: *Parser) anyerror!*Node {
        if (p.at("{")) return p.block(); const t = p.take(); const word = t.spelling;
        if (values.eq(word, ";")) return p.node("empty", t);
        if (values.eq(word, "if")) { const n = try p.node("if", t); n.x = try p.condition(); p.newlines(); n.y = try p.statement(); p.newlines(); if (p.accept("else")) { p.newlines(); n.z = try p.statement(); } return n; }
        if (values.eq(word, "while")) { const n = try p.node("while", t); n.x = try p.condition(); n.y = try p.body(); return n; }
        if (values.eq(word, "do")) { const n = try p.node("do", t); n.y = try p.body(); p.newlines(); _ = try p.expect("while"); n.x = try p.condition(); try p.terminator(); return n; }
        if (values.eq(word, "for")) {
            _ = try p.expect("(");
            if (p.p + 3 < p.tokens.len and p.peek().kind == .name and values.eq(p.tokens[p.p + 1].spelling, "in") and p.tokens[p.p + 2].kind == .name and values.eq(p.tokens[p.p + 3].spelling, ")")) { const n = try p.node("for_in", t); n.x = try p.name(); _ = try p.expect("in"); n.y = try p.name(); _ = try p.expect(")"); n.z = try p.body(); return n; }
            const n = try p.node("for", t); if (!p.at(";")) n.x = try p.expression(true); _ = try p.expect(";"); p.newlines(); if (!p.at(";")) n.y = try p.expression(true); _ = try p.expect(";"); p.newlines(); if (!p.at(")")) n.z = try p.expression(true); _ = try p.expect(")"); n.w = try p.body(); return n;
        }
        var n: *Node = undefined;
        if (values.eq(word, "print") or values.eq(word, "printf")) n = try p.output(t)
        else if (values.eq(word, "delete")) { n = try p.node("delete", t); n.x = try p.name(); if (p.accept("[")) { n.flag = true; n.args = try p.expressionList(true); _ = try p.expect("]"); } }
        else if (lex.member(word, "next break continue exit return")) {
            if ((values.eq(word, "next") and !p.in_function and lex.member(p.phase, "BEGIN END")) or (values.eq(word, "return") and !p.in_function) or (lex.member(word, "break continue") and p.loops == 0)) return p.fail(t.position);
            n = try p.node(word, t); if (lex.member(word, "exit return") and !p.at(";") and !p.at("\n") and !p.at("}")) n.x = try p.expression(true);
        } else { p.p -= 1; n = try p.node("expression_statement", t); n.x = try p.expression(true); }
        try p.terminator(); return n;
    }
    fn output(p: *Parser, t: lex.Token) !*Node {
        const n = try p.node(t.spelling, t); var paren = false;
        if (p.at("(")) { var depth: usize = 0; var i = p.p; while (i < p.tokens.len) : (i += 1) { if (values.eq(p.tokens[i].spelling, "(")) depth += 1 else if (values.eq(p.tokens[i].spelling, ")")) { depth -= 1; if (depth == 0) { const next = p.tokens[i + 1]; paren = next.kind == .eof or lex.member(next.spelling, "; \n } > >>"); break; } } } }
        if (paren) { _ = p.take(); n.args = try p.expressionList(true); _ = try p.expect(")"); }
        else if (!p.at(";") and !p.at("\n") and !p.at("}") and !p.at(">") and !p.at(">>")) n.args = try p.expressionList(false);
        if (values.eq(t.spelling, "printf") and n.args.len == 0) return p.fail(p.peek().position);
        if (p.at(">") or p.at(">>")) { n.redir = p.take(); n.x = try p.concat(); } return n;
    }
    fn expressionList(p: *Parser, greater: bool) ![]*Node { var list: std.ArrayList(*Node) = .empty; try list.append(p.a, try p.expression(greater)); while (p.accept(",")) { p.newlines(); try list.append(p.a, try p.expression(greater)); } return list.items; }
    fn expression(p: *Parser, greater: bool) anyerror!*Node {
        const left = try p.conditional(greater); if (left.lvalue() and lex.member(p.peek().spelling, "= += -= *= /= %= ^=")) { const op = p.take(); const n = try p.node("assignment", op); n.op = op.spelling; n.x = left; n.y = try p.expression(greater); return n; } return left;
    }
    fn conditional(p: *Parser, greater: bool) anyerror!*Node { const left = try p.logical(0, greater); if (!p.at("?")) return left; const n = try p.node("conditional", p.take()); n.x = left; n.y = try p.conditional(greater); _ = try p.expect(":"); n.z = try p.conditional(greater); return n; }
    fn logical(p: *Parser, level: usize, greater: bool) anyerror!*Node {
        if (level == 2) { var left = try p.comparison(greater); while (p.at("in")) { const n = try p.node("membership", p.take()); n.args = try p.a.dupe(*Node, &.{left}); n.x = try p.name(); left = n; } return left; }
        var left = try p.logical(level + 1, greater); const word = if (level == 0) "||" else "&&"; while (p.at(word)) { const t = p.take(); p.newlines(); left = try p.binary(t, word, left, try p.logical(level + 1, greater)); } return left;
    }
    fn comparison(p: *Parser, greater: bool) anyerror!*Node { var left = try p.concat(); while (lex.member(p.peek().spelling, "< <= == != >= >") and (greater or !p.at(">"))) { const op = p.take(); left = try p.binary(op, op.spelling, left, try p.concat()); } return left; }
    fn concat(p: *Parser) anyerror!*Node { var left = try p.additive(); while (true) { const t = p.peek(); if (t.kind != .number and t.kind != .string and t.kind != .name and t.kind != .function_name and t.kind != .builtin and !lex.member(t.spelling, "$ ( ++ --")) break; left = try p.binary(t, "concat", left, try p.additive()); } return left; }
    fn additive(p: *Parser) anyerror!*Node { var left = try p.multiplicative(); while (p.at("+") or p.at("-")) { const op = p.take(); left = try p.binary(op, op.spelling, left, try p.multiplicative()); } return left; }
    fn multiplicative(p: *Parser) anyerror!*Node { var left = try p.unary(); while (p.at("*") or p.at("/") or p.at("%")) { const op = p.take(); left = try p.binary(op, op.spelling, left, try p.unary()); } return left; }
    fn unary(p: *Parser) anyerror!*Node { if (lex.member(p.peek().spelling, "! - +")) { const t = p.take(); const n = try p.node("unary", t); n.op = t.spelling; n.x = try p.unary(); return n; } var left = try p.postfix(); if (p.at("^")) { const op = p.take(); left = try p.binary(op, "^", left, try p.unary()); } return left; }
    fn prefix(p: *Parser) anyerror!*Node { const t = p.take(); const n = try p.node("increment", t); n.flag = true; n.delta = if (values.eq(t.spelling, "++")) 1 else -1; n.x = try p.lvalue(); return n; }
    fn postfix(p: *Parser) anyerror!*Node { if (p.at("++") or p.at("--")) return p.prefix(); const left = try p.atom(); if (left.lvalue() and (p.at("++") or p.at("--"))) { const t = p.take(); const n = try p.node("increment", t); n.delta = if (values.eq(t.spelling, "++")) 1 else -1; n.x = left; return n; } return left; }
    fn lvalue(p: *Parser) anyerror!*Node {
        if (p.peek().kind == .name) { const n = try p.name(); if (p.accept("[")) { n.kind = "array"; n.args = try p.expressionList(true); _ = try p.expect("]"); } return n; }
        if (p.at("$")) { const n = try p.node("field", p.take()); n.x = if (p.at("++") or p.at("--")) try p.prefix() else try p.atom(); return n; } return p.fail(p.peek().position);
    }
    fn atom(p: *Parser) anyerror!*Node {
        const t = p.peek(); if (t.kind == .number or t.kind == .string) { _ = p.take(); return p.node(if (t.kind == .number) "number" else "string", t); }
        if (t.kind == .name or p.at("$")) return p.lvalue();
        if (p.accept("(")) { const expressions = try p.expressionList(true); _ = try p.expect(")"); if (expressions.len == 1) { const n = try p.node("paren", t); n.x = expressions[0]; return n; } _ = try p.expect("in"); const n = try p.node("membership", t); n.args = expressions; n.x = try p.name(); return n; }
        if (t.kind == .function_name or t.kind == .builtin) {
            _ = p.take(); const n = try p.node(if (t.kind == .builtin) "builtin" else "call", t); n.name = t.spelling;
            if (p.accept("(")) { if (!p.at(")")) n.args = try p.expressionList(true); _ = try p.expect(")"); } else if (t.kind == .function_name or !values.eq(n.name, "length")) return p.fail(p.peek().position);
            if (t.kind == .builtin) { const count = n.args.len; const valid = if (values.eq(n.name, "length")) count <= 1 else if (lex.member(n.name, "substr split")) count == 2 or count == 3 else if (values.eq(n.name, "index")) count == 2 else if (values.eq(n.name, "sprintf")) count >= 1 else count == 1; if (!valid or (values.eq(n.name, "split") and !n.args[1].is("name"))) return p.fail(t.position); }
            return n;
        }
        if (p.accept("getline")) { const n = try p.node("getline", t); if (p.peek().kind == .name or p.at("$")) n.x = try p.lvalue(); if (p.accept("<")) n.y = try p.atom(); return n; }
        return p.fail(t.position);
    }
};
