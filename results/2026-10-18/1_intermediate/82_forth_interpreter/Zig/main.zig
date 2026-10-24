const std = @import("std");
const Allocator = std.mem.Allocator;
const Text = []const u8;
const Int = i64;
const Error = Allocator.Error || error{Invalid};
const Failure = struct { word: Text, reason: Text, code: ?Int = null };
var failure: Failure = undefined;
var reasonBuffer: [256]u8 = undefined;
fn equal(a: Text, b: Text) bool { return std.mem.eql(u8, a, b); }
fn sameName(a: Text, b: Text) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (std.ascii.toUpper(x) != std.ascii.toUpper(y)) return false;
    return true;
}
fn member(text: Text, list: []const Text) bool { for (list) |item| if (equal(text, item)) return true; return false; }
fn uppercase(gpa: Allocator, text: Text) Allocator.Error!Text {
    const result = try gpa.dupe(u8, text);
    for (result) |*c| c.* = std.ascii.toUpper(c.*);
    return result;
}
fn issue(raw: Text, reason: Text, code: ?Int) Error { failure = .{ .word = raw, .reason = reason, .code = code }; return error.Invalid; }
fn flag(value: bool) Int { return if (value) -1 else 0; }
fn u(value: Int) usize { return @intCast(value); }
fn si(value: usize) Int { return @intCast(value); }
const compileOnly = [_]Text{ "IF", "ELSE", "THEN", "DO", "?DO", "LOOP", "+LOOP", "LEAVE", "UNLOOP", "I", "J", "BEGIN", "UNTIL", "WHILE", "REPEAT", "AGAIN", "CASE", "OF", "ENDOF", "ENDCASE", "EXIT", "RECURSE", "DOES>", ";", ">R", "R>", "R@", "ABORT\"", "[']", "{:" };
const interpretOnly = [_]Text{ ":", ":NONAME", "FORGET" };
const bothModes = [_]Text{ ".\"", "(", "\\", "TO", "IS" };
const builtinNames = "+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS";
const Builder = struct {
    gpa: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(self: *Builder, text: Text) Allocator.Error!void { try self.bytes.appendSlice(self.gpa, text); }
    fn print(self: *Builder, comptime format: Text, args: anytype) Allocator.Error!void {
        const text = try std.fmt.allocPrint(self.gpa, format, args);
        defer self.gpa.free(text);
        try self.add(text);
    }
    fn line(self: *Builder, comptime format: Text, args: anytype) Allocator.Error!void { try self.print(format ++ "\n", args); }
};
const Action = struct { kind: Text, raw: Text, text: Text = "", value: Int = 0, word: ?*Word = null, target: usize = 0, slots: []const usize = &.{} };
const WordKind = enum { builtin, colon, create, variable, constant, value, deferred };
const Word = struct {
    name: Text,
    rawName: Text = "",
    kind: WordKind,
    here: usize = 0,
    address: usize = 0,
    value: Int = 0,
    token: Int = 0,
    actions: std.ArrayList(Action) = .empty,
    localNames: std.StringHashMapUnmanaged(usize) = .empty,
    localCount: usize = 0,
    does: ?*Word = null,
    doesStart: usize = 0,
};
const Control = struct { kind: Text, index: usize = 0, start: usize = 0, leaves: std.ArrayList(usize) = .empty, ends: std.ArrayList(usize) = .empty };
const Machine = struct {
    gpa: Allocator,
    out: *Builder,
    pending: std.ArrayList(u8) = .empty,
    data: std.ArrayList(Int) = .empty,
    returns: std.ArrayList(Int) = .empty,
    memory: std.ArrayList(Int) = .empty,
    dictionary: std.ArrayList(*Word) = .empty,
    builtins: std.ArrayList(*Word) = .empty,
    tokens: std.ArrayList(*Word) = .empty,
    tokenNumbers: std.AutoHashMapUnmanaged(*Word, Int) = .empty,
    compiling: ?*Word = null,
    controls: std.ArrayList(Control) = .empty,
    source: Text = "",
    position: usize = 0,
    depth: usize = 0,

    fn initialize(self: *Machine) Error!void {
        try self.memory.append(self.gpa, 10);
        var iterator = std.mem.tokenizeScalar(u8, builtinNames, ' ');
        while (iterator.next()) |name| {
            const word = try self.gpa.create(Word);
            word.* = .{ .name = name, .kind = .builtin };
            try self.builtins.append(self.gpa, word);
        }
    }
    fn read(self: *Machine) ?Text {
        while (self.position < self.source.len and self.source[self.position] == ' ') self.position += 1;
        const start = self.position;
        while (self.position < self.source.len and self.source[self.position] != ' ') self.position += 1;
        return if (start == self.position) null else self.source[start..self.position];
    }
    fn readName(self: *Machine, raw: Text) Error!Text { return self.read() orelse return issue(raw, "missing name", -16); }
    fn lookup(self: *Machine, name: Text) ?*Word {
        var i = self.dictionary.items.len;
        while (i > 0) { i -= 1; if (sameName(self.dictionary.items[i].name, name)) return self.dictionary.items[i]; }
        for (self.builtins.items) |word| if (sameName(word.name, name)) return word;
        return null;
    }
    fn numeric(raw: Text, rawBase: Int) Error!?Int {
        if (raw.len == 3 and raw[0] == '\'' and raw[2] == '\'') return @as(Int, raw[1]);
        var text = raw;
        var base = rawBase;
        if (raw.len > 0) switch (raw[0]) {
            '$' => { base = 16; text = raw[1..]; },
            '#' => { base = 10; text = raw[1..]; },
            '%' => { base = 2; text = raw[1..]; },
            else => if (base < 2 or base > 36) return issue(raw, "invalid base", -40),
        };
        const negative = std.mem.startsWith(u8, text, "-");
        if (negative) text = text[1..];
        if (text.len == 0) return null;
        for (text) |character| {
            const c = std.ascii.toUpper(character);
            const digit: Int = if (std.ascii.isDigit(c)) c - '0' else if (c >= 'A' and c <= 'Z') c - 'A' + 10 else -1;
            if (digit < 0 or digit >= base) return null;
        }
        var value: Int = 0;
        for (text) |character| {
            const c = std.ascii.toUpper(character);
            const digit: Int = if (std.ascii.isDigit(c)) c - '0' else c - 'A' + 10;
            value = value * base + digit;
        }
        return if (negative) -value else value;
    }
    fn checkName(self: *Machine, raw: Text) Error!void {
        _ = self;
        for (compileOnly) |name| if (sameName(raw, name)) return issue(raw, "invalid name", -19);
        for (interpretOnly) |name| if (sameName(raw, name)) return issue(raw, "invalid name", -19);
        for (bothModes) |name| if (sameName(raw, name)) return issue(raw, "invalid name", -19);
        if (try numeric(raw, 10) != null) return issue(raw, "invalid name", -19);
    }
    fn take(self: *Machine, count: usize, raw: Text) Error![4]Int {
        if (self.data.items.len < count) return issue(raw, "stack underflow", -4);
        var values: [4]Int = .{ 0, 0, 0, 0 };
        const start = self.data.items.len - count;
        @memcpy(values[0..count], self.data.items[start..]);
        self.data.shrinkRetainingCapacity(start);
        return values;
    }
    fn push(self: *Machine, value: Int, raw: Text) Error!void {
        try self.data.append(self.gpa, value);
        if (self.data.items.len > 1000) return issue(raw, "stack overflow", -3);
    }
    fn pushAll(self: *Machine, values: []const Int, raw: Text) Error!void { for (values) |value| try self.push(value, raw); }
    fn returnNeed(self: *Machine, count: usize, raw: Text) Error!void { if (self.returns.items.len < count) return issue(raw, "return stack underflow", -6); }
    fn returnPush(self: *Machine, value: Int, raw: Text) Error!void {
        try self.returns.append(self.gpa, value);
        if (self.returns.items.len > 1000) return issue(raw, "return stack overflow", -5);
    }
    fn address(self: *Machine, value: Int, raw: Text) Error!usize {
        if (value < 0 or @rem(value, 8) != 0 or value >= si(self.memory.items.len) * 8) return issue(raw, "invalid address", -9);
        return u(@divTrunc(value, 8));
    }
    fn formatNumber(self: *Machine, value: Int, raw: Text, buffer: *[64]u8) Error!Text {
        const base = self.memory.items[0];
        if (base < 2 or base > 36) return issue(raw, "invalid base", -40);
        const digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        var absolute = if (value < 0) -value else value;
        var start: usize = buffer.len;
        while (true) {
            start -= 1;
            buffer[start] = digits[u(@mod(absolute, base))];
            absolute = @divTrunc(absolute, base);
            if (absolute == 0) break;
        }
        if (value < 0) { start -= 1; buffer[start] = '-'; }
        return buffer[start..];
    }
    fn write(self: *Machine, text: Text) Error!void { try self.pending.appendSlice(self.gpa, text); }
    fn flush(self: *Machine) Error!void { try self.out.line("{s}", .{std.mem.trimEnd(u8, self.pending.items, " ")}); self.pending.clearRetainingCapacity(); }
    fn executionToken(self: *Machine, word: *Word) Error!Int {
        if (self.tokenNumbers.get(word)) |token| return token;
        try self.tokens.append(self.gpa, word);
        const token = si(self.tokens.items.len);
        try self.tokenNumbers.put(self.gpa, word, token);
        return token;
    }
    fn validToken(self: *Machine, value: Int, raw: Text) Error!*Word {
        if (value < 1 or value > si(self.tokens.items.len)) return issue(raw, "invalid argument", -24);
        return self.tokens.items[u(value - 1)];
    }
    fn executeToken(self: *Machine, value: Int, raw: Text) Error!void { const word = try self.validToken(value, raw); try self.execute(word, word.name); }
    fn addAction(self: *Machine, action: Action) Error!usize {
        const index = self.compiling.?.actions.items.len;
        try self.compiling.?.actions.append(self.gpa, action);
        return index;
    }
    fn topControl(self: *Machine, raw: Text, kinds: []const Text) Error!*Control {
        if (self.controls.items.len == 0 or !member(self.controls.items[self.controls.items.len - 1].kind, kinds)) return issue(raw, "control structure mismatch", null);
        return &self.controls.items[self.controls.items.len - 1];
    }
    fn compileControl(self: *Machine, raw: Text, name: Text) Error!bool {
        if (equal(name, "IF")) {
            try self.controls.append(self.gpa, .{ .kind = "IF", .index = try self.addAction(.{ .kind = "zero", .raw = raw }) });
        } else if (equal(name, "ELSE")) {
            const top = try self.topControl(raw, &.{"IF"});
            const index = try self.addAction(.{ .kind = "jump", .raw = raw });
            self.compiling.?.actions.items[top.index].target = self.compiling.?.actions.items.len;
            top.kind = "ELSE";
            top.index = index;
        } else if (equal(name, "THEN")) {
            const top = try self.topControl(raw, &.{ "IF", "ELSE" });
            self.compiling.?.actions.items[top.index].target = self.compiling.?.actions.items.len;
            _ = self.controls.pop();
        } else if (equal(name, "BEGIN")) {
            try self.controls.append(self.gpa, .{ .kind = "BEGIN", .start = self.compiling.?.actions.items.len });
        } else if (member(name, &.{ "UNTIL", "AGAIN" })) {
            const top = try self.topControl(raw, &.{"BEGIN"});
            _ = try self.addAction(.{ .kind = if (equal(name, "UNTIL")) "zero" else "jump", .raw = raw, .target = top.start });
            _ = self.controls.pop();
        } else if (equal(name, "WHILE")) {
            const top = try self.topControl(raw, &.{"BEGIN"});
            top.kind = "WHILE";
            top.index = try self.addAction(.{ .kind = "zero", .raw = raw });
        } else if (equal(name, "REPEAT")) {
            const top = try self.topControl(raw, &.{"WHILE"});
            _ = try self.addAction(.{ .kind = "jump", .raw = raw, .target = top.start });
            self.compiling.?.actions.items[top.index].target = self.compiling.?.actions.items.len;
            _ = self.controls.pop();
        } else if (member(name, &.{ "DO", "?DO" })) {
            const index = try self.addAction(.{ .kind = name, .raw = raw });
            try self.controls.append(self.gpa, .{ .kind = name, .index = index, .start = index + 1 });
        } else if (member(name, &.{ "LOOP", "+LOOP" })) {
            const top = try self.topControl(raw, &.{ "DO", "?DO" });
            _ = try self.addAction(.{ .kind = name, .raw = raw, .target = top.start });
            const finish = self.compiling.?.actions.items.len;
            self.compiling.?.actions.items[top.index].target = finish;
            for (top.leaves.items) |index| self.compiling.?.actions.items[index].target = finish;
            _ = self.controls.pop();
        } else if (equal(name, "LEAVE")) {
            var found: ?usize = null;
            var i = self.controls.items.len;
            while (i > 0) { i -= 1; if (member(self.controls.items[i].kind, &.{ "DO", "?DO" })) { found = i; break; } }
            const index = found orelse return issue(raw, "control structure mismatch", null);
            const actionIndex = try self.addAction(.{ .kind = "LEAVE", .raw = raw });
            try self.controls.items[index].leaves.append(self.gpa, actionIndex);
        } else if (equal(name, "CASE")) {
            try self.controls.append(self.gpa, .{ .kind = "CASE" });
        } else if (equal(name, "OF")) {
            _ = try self.topControl(raw, &.{"CASE"});
            try self.controls.append(self.gpa, .{ .kind = "OF", .index = try self.addAction(.{ .kind = "OF", .raw = raw }) });
        } else if (equal(name, "ENDOF")) {
            const top = try self.topControl(raw, &.{"OF"});
            const index = try self.addAction(.{ .kind = "jump", .raw = raw });
            self.compiling.?.actions.items[top.index].target = self.compiling.?.actions.items.len;
            _ = self.controls.pop();
            const parent = try self.topControl(raw, &.{"CASE"});
            try parent.ends.append(self.gpa, index);
        } else if (equal(name, "ENDCASE")) {
            const top = try self.topControl(raw, &.{"CASE"});
            _ = try self.addAction(.{ .kind = "ENDCASE", .raw = raw });
            for (top.ends.items) |index| self.compiling.?.actions.items[index].target = self.compiling.?.actions.items.len;
            _ = self.controls.pop();
        } else return false;
        return true;
    }
    fn readString(self: *Machine, raw: Text) Error!Text {
        if (self.position == self.source.len) return issue(raw, "unterminated string", null);
        const start = self.position + 1;
        const end = std.mem.findScalar(u8, self.source[start..], '"') orelse return issue(raw, "unterminated string", null);
        self.position = start + end + 1;
        return self.source[start .. start + end];
    }
    fn declareLocals(self: *Machine, raw: Text) Error!void {
        var names: std.ArrayList(Text) = .empty;
        var ignored = false;
        var closed = false;
        while (self.read()) |name| {
            if (sameName(name, ":}")) { closed = true; break; }
            if (equal(name, "--")) ignored = true;
            if (!ignored) try names.append(self.gpa, name);
        }
        if (!closed) return issue(raw, "unterminated locals", null);
        var slots: std.ArrayList(usize) = .empty;
        for (names.items) |name| {
            try self.checkName(name);
            const slot = self.compiling.?.localCount;
            self.compiling.?.localCount += 1;
            try self.compiling.?.localNames.put(self.gpa, try uppercase(self.gpa, name), slot);
            try slots.append(self.gpa, slot);
        }
        _ = try self.addAction(.{ .kind = "locals", .raw = raw, .slots = slots.items });
    }
    fn localSlot(self: *Machine, name: Text) ?usize {
        var iterator = self.compiling.?.localNames.iterator();
        while (iterator.next()) |entry| if (sameName(name, entry.key_ptr.*)) return entry.value_ptr.*;
        return null;
    }
    fn assign(self: *Machine, raw: Text, name: Text) Error!void {
        const targetName = try self.readName(raw);
        if (equal(name, "TO") and self.compiling != null) {
            if (self.localSlot(targetName)) |slot| { _ = try self.addAction(.{ .kind = "localSet", .raw = raw, .target = slot }); return; }
        }
        const target = self.lookup(targetName) orelse return issue(targetName, "undefined word", -13);
        const required: WordKind = if (equal(name, "TO")) .value else .deferred;
        if (target.kind != required) return issue(targetName, if (equal(name, "TO")) "not a value" else "not deferred", null);
        const action: Action = .{ .kind = name, .raw = raw, .word = target };
        if (self.compiling != null) { _ = try self.addAction(action); } else try self.runtimeAction(action, &.{});
    }
    fn process(self: *Machine, raw: Text) Error!void {
        const name = try uppercase(self.gpa, raw);
        if (equal(name, "\\")) { self.position = self.source.len; return; }
        if (equal(name, "(")) {
            const end = std.mem.findScalar(u8, self.source[self.position..], ')') orelse return issue(raw, "unterminated comment", null);
            self.position += end + 1;
            return;
        }
        if (self.compiling == null and member(name, &compileOnly)) return issue(raw, "compile only", null);
        if (self.compiling != null and member(name, &interpretOnly)) return issue(raw, "interpret only", null);
        if (member(name, &.{ ".\"", "ABORT\"" })) {
            const text = try self.readString(raw);
            if (self.compiling == null) { try self.write(text); } else { _ = try self.addAction(.{ .kind = name, .raw = raw, .text = text }); }
            return;
        }
        if (member(name, &.{ "TO", "IS" })) return self.assign(raw, name);
        if (member(name, &.{ ":", ":NONAME" })) {
            const rawName = if (equal(name, ":")) try self.readName(raw) else raw;
            if (equal(name, ":")) try self.checkName(rawName);
            const word = try self.gpa.create(Word);
            word.* = .{ .name = if (equal(name, ":NONAME")) ":NONAME" else try uppercase(self.gpa, rawName), .rawName = rawName, .kind = .colon, .here = self.memory.items.len };
            self.compiling = word;
            self.controls.clearRetainingCapacity();
            return;
        }
        if (equal(name, "FORGET")) {
            const targetName = try self.readName(raw);
            var found: ?usize = null;
            var i = self.dictionary.items.len;
            while (i > 0) { i -= 1; if (sameName(self.dictionary.items[i].name, targetName)) { found = i; break; } }
            const index = found orelse return issue(targetName, "undefined word", -13);
            self.memory.shrinkRetainingCapacity(self.dictionary.items[index].here);
            self.dictionary.shrinkRetainingCapacity(index);
            return;
        }
        if (self.compiling) |word| {
            if (try self.compileControl(raw, name)) return;
            if (equal(name, ";")) {
                if (self.controls.items.len > 0) {
                    const top = self.controls.items[self.controls.items.len - 1].kind;
                    const kind = if (equal(top, "ELSE")) "IF" else if (equal(top, "WHILE")) "BEGIN" else top;
                    return issue(raw, std.fmt.bufPrint(&reasonBuffer, "unclosed {s}", .{kind}) catch unreachable, null);
                }
                self.compiling = null;
                if (equal(word.name, ":NONAME")) { try self.push(try self.executionToken(word), raw); } else try self.dictionary.append(self.gpa, word);
                return;
            }
            if (equal(name, "DOES>")) {
                if (self.controls.items.len != 0) return issue(raw, "control structure mismatch", null);
                _ = try self.addAction(.{ .kind = "DOES>", .raw = raw, .word = word });
                return;
            }
            if (equal(name, "EXIT")) { _ = try self.addAction(.{ .kind = "EXIT", .raw = raw }); return; }
            if (equal(name, "RECURSE")) { _ = try self.addAction(.{ .kind = "call", .raw = raw, .word = word }); return; }
            if (equal(name, "[']")) {
                const targetName = try self.readName(raw);
                const target = self.lookup(targetName) orelse return issue(targetName, "undefined word", -13);
                _ = try self.addAction(.{ .kind = "push", .raw = raw, .value = try self.executionToken(target) });
                return;
            }
            if (equal(name, "{:")) return self.declareLocals(raw);
            if (member(name, &.{ ">R", "R>", "R@", "I", "J", "UNLOOP" })) { _ = try self.addAction(.{ .kind = name, .raw = raw }); return; }
            if (self.localSlot(name)) |slot| { _ = try self.addAction(.{ .kind = "localGet", .raw = raw, .target = slot }); return; }
            if (self.lookup(raw)) |target| { _ = try self.addAction(.{ .kind = "call", .raw = raw, .word = target }); return; }
            if (try numeric(raw, self.memory.items[0])) |value| { _ = try self.addAction(.{ .kind = "push", .raw = raw, .value = value }); return; }
            return issue(raw, "undefined word", -13);
        }
        if (self.lookup(raw)) |target| return self.execute(target, raw);
        if (try numeric(raw, self.memory.items[0])) |value| return self.push(value, raw);
        return issue(raw, "undefined word", -13);
    }
    fn runtimeAction(self: *Machine, action: Action, locals: []Int) Error!void {
        const raw = action.raw;
        if (equal(action.kind, "push")) { try self.push(action.value, raw); }
        else if (equal(action.kind, "call")) { try self.execute(action.word.?, raw); }
        else if (equal(action.kind, ".\"")) { try self.write(action.text); }
        else if (equal(action.kind, "ABORT\"")) { if ((try self.take(1, raw))[0] != 0) return issue(raw, action.text, -2); }
        else if (equal(action.kind, "localGet")) { try self.push(locals[action.target], raw); }
        else if (equal(action.kind, "localSet")) { locals[action.target] = (try self.take(1, raw))[0]; }
        else if (equal(action.kind, "locals")) {
            if (self.data.items.len < action.slots.len) return issue(raw, "stack underflow", -4);
            const start = self.data.items.len - action.slots.len;
            for (action.slots, self.data.items[start..]) |slot, value| locals[slot] = value;
            self.data.shrinkRetainingCapacity(start);
        } else if (equal(action.kind, "TO")) { self.memory.items[action.word.?.address] = (try self.take(1, raw))[0]; }
        else if (equal(action.kind, "IS")) { const value = (try self.take(1, raw))[0]; _ = try self.validToken(value, raw); action.word.?.token = value; }
        else if (equal(action.kind, ">R")) { try self.returnPush((try self.take(1, raw))[0], raw); }
        else if (equal(action.kind, "R>")) { try self.returnNeed(1, raw); const value = self.returns.pop().?; try self.push(value, raw); }
        else if (member(action.kind, &.{ "R@", "I", "J" })) { const count: usize = if (equal(action.kind, "J")) 3 else 1; try self.returnNeed(count, raw); try self.push(self.returns.items[self.returns.items.len - count], raw); }
        else if (equal(action.kind, "UNLOOP")) { try self.returnNeed(2, raw); self.returns.shrinkRetainingCapacity(self.returns.items.len - 2); }
    }
    fn definition(self: *Machine, word: *Word, start: usize, raw: Text) Error!void {
        if (self.depth == 100) return issue(raw, "nesting too deep", -7);
        self.depth += 1;
        const saved = self.returns.items.len;
        const locals = try std.heap.page_allocator.alloc(Int, word.localCount);
        defer std.heap.page_allocator.free(locals);
        @memset(locals, 0);
        var pc = start;
        while (pc < word.actions.items.len) {
            const action = word.actions.items[pc];
            pc += 1;
            if (equal(action.kind, "EXIT")) break;
            if (equal(action.kind, "DOES>")) {
                if (self.dictionary.items.len == 0 or self.dictionary.items[self.dictionary.items.len - 1].kind != .create) return issue(action.raw, "no CREATE word", -31);
                const newest = self.dictionary.items[self.dictionary.items.len - 1];
                newest.does = action.word;
                newest.doesStart = pc;
                break;
            }
            if (equal(action.kind, "jump")) { pc = action.target; }
            else if (equal(action.kind, "zero")) { if ((try self.take(1, action.raw))[0] == 0) pc = action.target; }
            else if (member(action.kind, &.{ "DO", "?DO" })) {
                const values = try self.take(2, action.raw);
                if (equal(action.kind, "?DO") and values[0] == values[1]) { pc = action.target; } else { try self.returnPush(values[0], action.raw); try self.returnPush(values[1], action.raw); }
            } else if (member(action.kind, &.{ "LOOP", "+LOOP" })) {
                const step: Int = if (equal(action.kind, "+LOOP")) (try self.take(1, action.raw))[0] else 1;
                try self.returnNeed(2, action.raw);
                const index = self.returns.items[self.returns.items.len - 1];
                const limit = self.returns.items[self.returns.items.len - 2];
                const next = index + step;
                if ((index - limit < 0) != (next - limit < 0)) { self.returns.shrinkRetainingCapacity(self.returns.items.len - 2); } else { self.returns.items[self.returns.items.len - 1] = next; pc = action.target; }
            } else if (equal(action.kind, "LEAVE")) {
                try self.returnNeed(2, action.raw);
                self.returns.shrinkRetainingCapacity(self.returns.items.len - 2);
                pc = action.target;
            } else if (equal(action.kind, "OF")) {
                const values = try self.take(2, action.raw);
                if (values[0] != values[1]) { try self.push(values[0], action.raw); pc = action.target; }
            } else if (equal(action.kind, "ENDCASE")) { _ = try self.take(1, action.raw); }
            else try self.runtimeAction(action, locals);
        }
        if (self.returns.items.len > saved) self.returns.shrinkRetainingCapacity(saved);
        self.depth -= 1;
    }
    fn execute(self: *Machine, initialWord: *Word, initialRaw: Text) Error!void {
        var word = initialWord;
        var raw = initialRaw;
        while (word.kind == .deferred) {
            if (word.token == 0) return issue(raw, "deferred word not set", -21);
            word = try self.validToken(word.token, raw);
            raw = word.name;
        }
        switch (word.kind) {
            .colon => try self.definition(word, 0, raw),
            .create => { try self.push(si(word.address) * 8, raw); if (word.does) |part| try self.definition(part, word.doesStart, raw); },
            .variable => try self.push(si(word.address) * 8, raw),
            .constant => try self.push(word.value, raw),
            .value => try self.push(self.memory.items[word.address], raw),
            .deferred => unreachable,
            .builtin => try self.builtin(word.name, raw),
        }
    }
    fn builtin(self: *Machine, name: Text, raw: Text) Error!void {
        if (member(name, &.{ "CREATE", "VARIABLE", "CONSTANT", "VALUE", "DEFER" })) {
            const rawName = try self.readName(raw);
            try self.checkName(rawName);
            const value: Int = if (member(name, &.{ "CONSTANT", "VALUE" })) (try self.take(1, raw))[0] else 0;
            const word = try self.gpa.create(Word);
            word.* = .{ .name = try uppercase(self.gpa, rawName), .rawName = rawName, .kind = if (equal(name, "CREATE")) .create else if (equal(name, "VARIABLE")) .variable else if (equal(name, "CONSTANT")) .constant else if (equal(name, "VALUE")) .value else .deferred, .here = self.memory.items.len, .address = self.memory.items.len, .value = value };
            try self.dictionary.append(self.gpa, word);
            if (member(name, &.{ "VARIABLE", "VALUE" })) try self.memory.append(self.gpa, value);
            return;
        }
        if (equal(name, "'")) {
            const targetName = try self.readName(raw);
            const target = self.lookup(targetName) orelse return issue(targetName, "undefined word", -13);
            try self.push(try self.executionToken(target), raw);
            return;
        }
        if (equal(name, "EXECUTE")) return self.executeToken((try self.take(1, raw))[0], raw);
        if (equal(name, "CATCH")) {
            const token = (try self.take(1, raw))[0];
            const target = try self.validToken(token, raw);
            const saved = try std.heap.page_allocator.dupe(Int, self.data.items);
            defer std.heap.page_allocator.free(saved);
            const returnSize = self.returns.items.len;
            const depth = self.depth;
            var code: Int = 0;
            self.execute(target, target.name) catch |err| {
                if (err != error.Invalid or failure.code == null) return err;
                self.data.clearRetainingCapacity();
                try self.data.appendSlice(self.gpa, saved);
                if (self.returns.items.len > returnSize) self.returns.shrinkRetainingCapacity(returnSize);
                self.depth = depth;
                code = failure.code.?;
            };
            try self.push(code, raw);
            return;
        }
        if (equal(name, "THROW")) { const code = (try self.take(1, raw))[0]; if (code != 0) return issue(raw, std.fmt.bufPrint(&reasonBuffer, "exception {d}", .{code}) catch unreachable, code); return; }
        if (equal(name, "ABORT")) return issue(raw, "aborted", -1);
        if (equal(name, "WORDS")) { var i = self.dictionary.items.len; while (i > 0) { i -= 1; try self.write(self.dictionary.items[i].name); try self.write(" "); } return; }
        if (equal(name, "CR")) return self.flush();
        if (equal(name, "SPACE")) return self.write(" ");
        if (equal(name, ".S")) {
            var buffer: [64]u8 = undefined;
            const count = try self.formatNumber(si(self.data.items.len), raw, &buffer);
            try self.write("<"); try self.write(count); try self.write("> ");
            for (self.data.items) |value| { try self.write(try self.formatNumber(value, raw, &buffer)); try self.write(" "); }
            return;
        }
        if (equal(name, "TRUE")) return self.push(-1, raw);
        if (equal(name, "FALSE")) return self.push(0, raw);
        if (equal(name, "BL")) return self.push(32, raw);
        if (equal(name, "BASE")) return self.push(0, raw);
        if (equal(name, "HERE")) return self.push(si(self.memory.items.len) * 8, raw);
        if (equal(name, "DEPTH")) return self.push(si(self.data.items.len), raw);
        if (equal(name, "HEX")) { self.memory.items[0] = 16; return; }
        if (equal(name, "DECIMAL")) { self.memory.items[0] = 10; return; }
        var count: usize = 1;
        if (member(name, &.{ "+", "-", "*", "/", "MOD", "/MOD", "MIN", "MAX", "=", "<>", "<", ">", "AND", "OR", "XOR", "SWAP", "OVER", "NIP", "TUCK", "2DUP", "2DROP", ".R", "!", "+!" })) count = 2;
        if (member(name, &.{ "*/", "*/MOD", "WITHIN", "ROT", "-ROT" })) count = 3;
        if (member(name, &.{ "2SWAP", "2OVER" })) count = 4;
        const values = try self.take(count, raw);
        var a = values[0];
        const b = values[1];
        if (equal(name, "+")) { try self.push(a + b, raw); }
        else if (equal(name, "-")) { try self.push(a - b, raw); }
        else if (equal(name, "*")) { try self.push(a * b, raw); }
        else if (member(name, &.{ "/", "MOD", "/MOD", "*/", "*/MOD" })) {
            const dividend = if (count == 3) a * b else a;
            const divisor = if (count == 3) values[2] else b;
            if (divisor == 0) return issue(raw, "division by zero", -10);
            const q = @divFloor(dividend, divisor);
            const r = dividend - divisor * q;
            if (equal(name, "MOD")) { try self.push(r, raw); } else if (member(name, &.{ "/MOD", "*/MOD" })) { try self.pushAll(&.{ r, q }, raw); } else try self.push(q, raw);
        } else if (equal(name, "NEGATE")) { try self.push(-a, raw); }
        else if (equal(name, "ABS")) { try self.push(if (a < 0) -a else a, raw); }
        else if (equal(name, "MIN")) { try self.push(@min(a, b), raw); }
        else if (equal(name, "MAX")) { try self.push(@max(a, b), raw); }
        else if (equal(name, "1+")) { try self.push(a + 1, raw); }
        else if (equal(name, "1-")) { try self.push(a - 1, raw); }
        else if (equal(name, "2*")) { try self.push(2 * a, raw); }
        else if (equal(name, "2/")) { try self.push(@divFloor(a, 2), raw); }
        else if (equal(name, "=")) { try self.push(flag(a == b), raw); }
        else if (equal(name, "<>")) { try self.push(flag(a != b), raw); }
        else if (equal(name, "<")) { try self.push(flag(a < b), raw); }
        else if (equal(name, ">")) { try self.push(flag(a > b), raw); }
        else if (equal(name, "0=")) { try self.push(flag(a == 0), raw); }
        else if (equal(name, "0<>")) { try self.push(flag(a != 0), raw); }
        else if (equal(name, "0<")) { try self.push(flag(a < 0), raw); }
        else if (equal(name, "0>")) { try self.push(flag(a > 0), raw); }
        else if (equal(name, "WITHIN")) { try self.push(flag(b <= a and a < values[2]), raw); }
        else if (equal(name, "AND")) { try self.push(a & b, raw); }
        else if (equal(name, "OR")) { try self.push(a | b, raw); }
        else if (equal(name, "XOR")) { try self.push(a ^ b, raw); }
        else if (equal(name, "INVERT")) { try self.push(~a, raw); }
        else if (equal(name, "DUP")) { try self.pushAll(&.{ a, a }, raw); }
        else if (equal(name, "?DUP")) { try self.push(a, raw); if (a != 0) try self.push(a, raw); }
        else if (member(name, &.{ "DROP", "2DROP" })) {}
        else if (equal(name, "SWAP")) { try self.pushAll(&.{ b, a }, raw); }
        else if (equal(name, "OVER")) { try self.pushAll(&.{ a, b, a }, raw); }
        else if (equal(name, "ROT")) { try self.pushAll(&.{ b, values[2], a }, raw); }
        else if (equal(name, "-ROT")) { try self.pushAll(&.{ values[2], a, b }, raw); }
        else if (equal(name, "NIP")) { try self.push(b, raw); }
        else if (equal(name, "TUCK")) { try self.pushAll(&.{ b, a, b }, raw); }
        else if (equal(name, "2DUP")) { try self.pushAll(&.{ a, b, a, b }, raw); }
        else if (equal(name, "2SWAP")) { try self.pushAll(&.{ values[2], values[3], a, b }, raw); }
        else if (equal(name, "2OVER")) { try self.pushAll(&.{ a, b, values[2], values[3], a, b }, raw); }
        else if (member(name, &.{ "PICK", "ROLL" })) {
            if (a < 0) return issue(raw, "invalid argument", -24);
            if (a >= si(self.data.items.len)) return issue(raw, "stack underflow", -4);
            const index = self.data.items.len - 1 - u(a);
            const value = self.data.items[index];
            if (equal(name, "ROLL")) _ = self.data.orderedRemove(index);
            try self.push(value, raw);
        } else if (equal(name, ".")) { var buffer: [64]u8 = undefined; try self.write(try self.formatNumber(a, raw, &buffer)); try self.write(" "); }
        else if (equal(name, ".R")) {
            var buffer: [64]u8 = undefined;
            const text = try self.formatNumber(a, raw, &buffer);
            var padding = b - si(text.len);
            while (padding > 0) : (padding -= 1) try self.write(" ");
            try self.write(text);
        } else if (equal(name, "?")) {
            const cell = try self.address(a, raw);
            var buffer: [64]u8 = undefined;
            try self.write(try self.formatNumber(self.memory.items[cell], raw, &buffer)); try self.write(" ");
        } else if (equal(name, "EMIT")) { if (a < 32 or a > 126) return issue(raw, "invalid argument", -24); try self.pending.append(self.gpa, @intCast(a)); }
        else if (equal(name, "SPACES")) { while (a > 0) : (a -= 1) try self.write(" "); }
        else if (equal(name, "!")) { const cell = try self.address(b, raw); self.memory.items[cell] = a; }
        else if (equal(name, "@")) { try self.push(self.memory.items[try self.address(a, raw)], raw); }
        else if (equal(name, "+!")) { const cell = try self.address(b, raw); self.memory.items[cell] += a; }
        else if (equal(name, ",")) { try self.memory.append(self.gpa, a); }
        else if (equal(name, "ALLOT")) {
            if (a < 0 or @rem(a, 8) != 0) return issue(raw, "invalid argument", -24);
            const start = self.memory.items.len;
            try self.memory.resize(self.gpa, start + u(@divTrunc(a, 8)));
            @memset(self.memory.items[start..], 0);
        } else if (equal(name, "CELLS")) { try self.push(8 * a, raw); }
        else if (equal(name, "CELL+")) { try self.push(a + 8, raw); }
    }
    fn processLine(self: *Machine, line: Text) Error!void {
        self.source = line;
        self.position = 0;
        while (self.read()) |raw| {
            self.process(raw) catch |err| {
                if (err != error.Invalid) return err;
                if (self.pending.items.len > 0) try self.flush();
                try self.out.line("ERROR {s}: {s}", .{ failure.word, failure.reason });
                self.data.clearRetainingCapacity();
                self.returns.clearRetainingCapacity();
                self.compiling = null;
                self.controls.clearRetainingCapacity();
                self.depth = 0;
                return;
            };
        }
        if (self.pending.items.len > 0) try self.flush();
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var inputBuffer: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &inputBuffer);
    const text = try input.interface.allocRemaining(gpa, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var out: Builder = .{ .gpa = gpa };
    var machine: Machine = .{ .gpa = gpa, .out = &out };
    try machine.initialize();
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (equal(line, "BYE")) {
            if (machine.compiling) |word| try out.line("ERROR {s}: unterminated definition", .{word.rawName});
            break;
        }
        try machine.processLine(line);
    }
    var outputBuffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &outputBuffer);
    try output.interface.writeAll(out.bytes.items);
    try output.interface.flush();
}
