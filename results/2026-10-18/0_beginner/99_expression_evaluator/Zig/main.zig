const std = @import("std");

const EvalError = error{ DivisionByZero, UndefinedVariable };
const Table = struct {
    names: [16][]const u8 = undefined,
    values: [16]i64 = undefined,
    len: usize = 0,

    fn set(self: *Table, name: []const u8, v: i64) void {
        for (self.names[0..self.len], 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) {
                self.values[i] = v;
                return;
            }
        }
        self.names[self.len] = name;
        self.values[self.len] = v;
        self.len += 1;
    }
};

const Parser = struct {
    tokens: []const []const u8,
    position: usize = 0,
    variables: *Table,
    missing: []const u8 = "",

    fn at(self: *Parser, s: []const u8) bool {
        return self.position < self.tokens.len and std.mem.eql(u8, self.tokens[self.position], s);
    }

    fn expression(self: *Parser) EvalError!i64 {
        var result = try self.term();
        while (self.at("+") or self.at("-")) {
            const op = self.tokens[self.position][0];
            self.position += 1;
            const right = try self.term();
            result = if (op == '+') result + right else result - right;
        }
        return result;
    }

    fn term(self: *Parser) EvalError!i64 {
        var result = try self.unary();
        while (self.at("*") or self.at("/")) {
            const op = self.tokens[self.position][0];
            self.position += 1;
            const right = try self.unary();
            if (op == '/' and right == 0)
                return error.DivisionByZero;
            result = if (op == '*') result * right else @divTrunc(result, right);
        }
        return result;
    }

    fn unary(self: *Parser) EvalError!i64 {
        if (self.at("-")) {
            self.position += 1;
            return -(try self.unary());
        }
        return self.primary();
    }

    fn primary(self: *Parser) EvalError!i64 {
        if (self.at("(")) {
            self.position += 1;
            const result = try self.expression();
            self.position += 1;
            return result;
        }
        const token = self.tokens[self.position];
        self.position += 1;
        if (token[0] >= '0' and token[0] <= '9')
            return std.fmt.parseInt(i64, token, 10) catch unreachable;
        for (self.variables.names[0..self.variables.len], 0..) |name, i| {
            if (std.mem.eql(u8, name, token))
                return self.variables.values[i];
        }
        self.missing = token;
        return error.UndefinedVariable;
    }
};

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const lines = [_][]const u8{
        "width = 12",
        "height = width - 5",
        "area = width * height",
        "(area + 6) / 4",
        "shift = -area / 8 + 3",
        "height = 100 / (height - 7) + bonus",
        "volume = area * depth",
        "width = (width+3)*-(2-4)",
        "width * shift - height"
    };
    var variables = Table{};
    for (lines) |line| {
        var tokens: [128][]const u8 = undefined;
        var len: usize = 0;
        var i: usize = 0;
        while (i < line.len) {
            if (line[i] == ' ') {
                i += 1;
                continue;
            }
            const start = i;
            const digit = line[i] >= '0' and line[i] <= '9';
            const letter = line[i] >= 'a' and line[i] <= 'z';
            i += 1;
            if (digit) {
                while (i < line.len and line[i] >= '0' and line[i] <= '9')
                    i += 1;
            } else if (letter) {
                while (i < line.len and line[i] >= 'a' and line[i] <= 'z')
                    i += 1;
            }
            tokens[len] = line[start..i];
            len += 1;
        }
        const assignment = len > 1 and std.mem.eql(u8, tokens[1], "=");
        var parser = Parser{
            .tokens = tokens[0..len],
            .position = if (assignment) 2 else 0,
            .variables = &variables
        };
        const result = parser.expression() catch |err| {
            switch (err) {
                error.DivisionByZero => try out.writeAll("error: division by zero\n"),
                error.UndefinedVariable => try out.print("error: undefined variable {s}\n", .{ parser.missing })
            }
            continue;
        };
        if (assignment) {
            variables.set(tokens[0], result);
            try out.print("{s} = {d}\n", .{ tokens[0], result });
        } else {
            try out.print("{d}\n", .{ result });
        }
    }
    try out.flush();
}
