const g = @import("grid.zig");
const slots = @import("slots.zig");
const words = @import("word_index.zig");
pub const State = struct {
    letters: [225]u8 = [_]u8{0} ** 225,
    words: [150]?usize = [_]?usize{null} ** 150,
    used: [2000]bool = [_]bool{false} ** 2000,
    pub fn init(layout: *const slots.Layout) State {
        var state: State = .{};
        @memcpy(state.letters[0..layout.grid.cells.len], layout.grid.cells);
        return state;
    }
    pub fn pattern(self: *const State, slot: slots.Slot, buffer: *[15]u8) []const u8 {
        for (slot.cells, 0..) |cell, i| buffer[i] = self.letters[cell];
        return buffer[0..slot.cells.len];
    }
    pub fn assign(self: *State, slot: slots.Slot, index: *const words.Index, word: usize, slot_number: usize) void {
        for (slot.cells, index.words[word].text) |cell, letter| self.letters[cell] = letter;
        self.used[word] = true;
        self.words[slot_number] = word;
    }
};
pub const Outcome = enum { filled, unfillable, budget };
pub const Attempt = struct {
    layout: *const slots.Layout, index: *const words.Index,
    state: State, best: State, min_score: usize, budget: usize,
    nodes: usize = 0, backtracks: usize = 0, prunes: usize = 0, dead_ends: usize = 0, max_depth: usize = 0,
    sequence: [150]usize = undefined, depth: usize = 0,
    failures: [150]usize = [_]usize{0} ** 150,
    trace: [10][]const u8 = undefined, trace_count: usize = 0,
    outcome: Outcome = .unfillable,
    pub fn init(layout: *const slots.Layout, index: *const words.Index, initial: State, min_score: usize, budget: usize) Attempt {
        return .{ .layout = layout, .index = index, .state = initial, .best = initial, .min_score = min_score, .budget = budget };
    }
    pub fn run(self: *Attempt) void { self.outcome = self.search(); }
    pub fn finalState(self: *Attempt) *State { return if (self.outcome == .filled) &self.state else &self.best; }
    fn search(self: *Attempt) Outcome {
        var chosen: ?usize = null;
        var smallest: usize = 2001;
        var buffer: [15]u8 = undefined;
        for (self.layout.slots, 0..) |slot, i| {
            if (self.state.words[i] != null) continue;
            const count = self.index.candidates(self.state.pattern(slot, &buffer), self.min_score, &self.state.used, null);
            if (count < smallest) { chosen = i; smallest = count; }
        }
        const selected = chosen orelse return .filled;
        if (smallest == 0) { self.dead_ends += 1; self.failures[selected] += 1; return .unfillable; }
        const slot = self.layout.slots[selected];
        var choices: [2000]usize = undefined;
        const count = self.index.candidates(self.state.pattern(slot, &buffer), self.min_score, &self.state.used, &choices);
        for (choices[0..count]) |word| {
            if (self.nodes == self.budget) return .budget;
            self.nodes += 1;
            var cleared: [15]usize = undefined;
            var clear_count: usize = 0;
            for (slot.cells) |cell| if (self.state.letters[cell] == '.') { cleared[clear_count] = cell; clear_count += 1; };
            self.state.assign(slot, self.index, word, selected);
            self.sequence[self.depth] = selected;
            self.depth += 1;
            var wiped: ?usize = null;
            for (slot.crossings) |other| {
                if (self.state.words[other] == null and self.index.candidates(self.state.pattern(self.layout.slots[other], &buffer), self.min_score, &self.state.used, null) == 0) { wiped = other; break; }
            }
            if (self.nodes <= 10) {
                self.trace[self.trace_count] = g.fmt("{s}={s}{s}", .{ slot.label, self.index.words[word].text, if (wiped != null) "!" else "" });
                self.trace_count += 1;
            }
            var result: Outcome = undefined;
            if (wiped) |other| { self.prunes += 1; self.failures[other] += 1; result = .unfillable; } else {
                if (self.depth > self.max_depth) { self.max_depth = self.depth; self.best = self.state; }
                result = self.search();
            }
            if (result != .unfillable) return result;
            for (cleared[0..clear_count]) |cell| self.state.letters[cell] = '.';
            self.state.words[selected] = null;
            self.state.used[word] = false;
            self.depth -= 1;
            self.backtracks += 1;
        }
        return .unfillable;
    }
};
