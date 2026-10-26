const std = @import("std");
const g = @import("grid.zig");
const slots = @import("slots.zig");
const words = @import("word_index.zig");
const filler = @import("filler.zig");
const render = @import("render.zig");
const letter_points = [_]usize{ 1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10 };
const Settings = struct { node_budget: usize, min_score: usize, symmetry: []const u8, relax_step: usize, weak_score: usize };
const WordList = struct { index: words.Index, lines: usize, invalid: g.Lines, duplicates: g.Lines };
const Clue = struct { word: usize, number: usize, text: []const u8, uses: usize = 0 };
const ClueBook = struct {
    clues: []Clue, entries: usize, invalid: g.Lines, unknown: g.Lines,
    fn choose(self: *ClueBook, index: *const words.Index, word: usize) ?[]const u8 {
        const ids = index.words[word].clues.items;
        if (ids.len == 0) return null;
        var chosen = ids[0];
        for (ids[1..]) |id| if (self.clues[id].uses < self.clues[chosen].uses) { chosen = id; };
        self.clues[chosen].uses += 1;
        return self.clues[chosen].text;
    }
};
const Template = struct {
    name: []const u8,
    options: std.ArrayList([]const u8) = .empty,
    rows: std.ArrayList([]const u8) = .empty,
    budget: usize, min_score: usize, symmetry: []const u8,
    error_text: ?[]const u8 = null,
    themes: std.ArrayList([]const u8) = .empty,
    layout: slots.Layout = undefined,
    initial: filler.State = undefined,
    theme_slots: [150]bool = [_]bool{false} ** 150,
    attempts: std.ArrayList(*filler.Attempt) = .empty,
    final_attempt: *filler.Attempt = undefined,
    state: *filler.State = undefined,
    chosen: [150]?[]const u8 = [_]?[]const u8{null} ** 150,

    fn readOptions(self: *Template) ?usize {
        var budget = false;
        var minimum = false;
        var symmetry = false;
        for (self.options.items, 1..) |line, number| {
            const space = std.mem.indexOfScalar(u8, line, ' ').?;
            const key = line[0..space];
            const value = line[space + 1 ..];
            if (g.eq(key, "theme")) {
                if (!words.validWord(value)) return number;
                for (self.themes.items) |earlier| if (g.eq(earlier, value)) return number;
                g.append([]const u8, &self.themes, value);
            } else if (g.eq(key, "node_budget") and !budget and words.validInteger(value, 1, 100000)) {
                self.budget = g.number(value);
                budget = true;
            } else if (g.eq(key, "min_score") and !minimum and words.validInteger(value, 1, 100)) {
                self.min_score = g.number(value);
                minimum = true;
            } else if (g.eq(key, "symmetry") and !symmetry and validSymmetry(value)) {
                self.symmetry = value;
                symmetry = true;
            } else return number;
        }
        return null;
    }

    fn check(self: *Template, earlier: []const Template, index: *const words.Index) ?[]const u8 {
        if (!validName(self.name)) return "bad name";
        for (earlier) |template| if (g.eq(template.name, self.name)) return "duplicate name";
        if (self.readOptions()) |number| return g.fmt("bad option {d}", .{number});
        if (self.rows.items.len < 3 or self.rows.items.len > 15) return "bad height";
        const width = self.rows.items[0].len;
        for (self.rows.items, 1..) |row, number| {
            var valid = row.len == width and width >= 3 and width <= 15;
            for (row) |symbol| if (symbol != '.' and symbol != '#' and (symbol < 'A' or symbol > 'Z')) { valid = false; };
            if (!valid) return g.fmt("bad row {d}", .{number});
        }
        const grid = g.Grid.init(self.rows.items);
        if (!g.eq(self.symmetry, "none")) {
            if (grid.asymmetricCell(self.symmetry)) |cell| return g.fmt("asymmetric at {s}", .{grid.cellText(cell)});
        }
        const components = grid.componentCount();
        if (components != 1) return g.fmt("disconnected components={d}", .{components});
        if (slots.shortRun(grid)) |run| return g.fmt("short slot at {s} {s}", .{ grid.cellText(run.cell), if (run.across) "across" else "down" });
        self.layout = slots.Layout.init(grid);
        for (grid.cells, 0..) |symbol, cell| {
            if (symbol != '#' and self.layout.ownerCount(cell) == 0) return g.fmt("orphan cell {s}", .{grid.cellText(cell)});
        }
        self.initial = filler.State.init(&self.layout);
        for (self.themes.items, 1..) |theme, number| {
            const word = index.find(theme) orelse return g.fmt("unknown theme {d}", .{number});
            var chosen: ?usize = null;
            var buffer: [15]u8 = undefined;
            for (self.layout.slots, 0..) |slot, i| {
                if (self.initial.words[i] != null or theme.len != slot.cells.len) continue;
                if (words.wordMatches(theme, self.initial.pattern(slot, &buffer))) { chosen = i; break; }
            }
            const selected = chosen orelse return g.fmt("theme {d} does not fit", .{number});
            self.initial.assign(self.layout.slots[selected], index, word, selected);
            self.theme_slots[selected] = true;
        }
        return null;
    }

    fn process(self: *Template, index: *const words.Index, book: *ClueBook, relax_step: usize) void {
        var minimum = self.min_score;
        while (true) {
            const attempt = &g.alloc(filler.Attempt, 1)[0];
            attempt.* = filler.Attempt.init(&self.layout, index, self.initial, minimum, self.budget);
            attempt.run();
            g.append(*filler.Attempt, &self.attempts, attempt);
            self.final_attempt = attempt;
            if (attempt.outcome == .filled or relax_step == 0 or minimum == 1) break;
            minimum = if (minimum > relax_step) minimum - relax_step else 1;
        }
        self.state = self.final_attempt.finalState();
        for (0..2) |direction| {
            for (self.layout.slots, 0..) |slot, i| {
                if (slot.across != (direction == 0)) continue;
                if (self.state.words[i]) |word| self.chosen[i] = book.choose(index, word);
            }
        }
    }

    fn entry(self: *const Template, index: *const words.Index, slot: usize) []const u8 {
        const word = index.words[self.state.words[slot].?];
        return g.fmt("{s}:{s}:{d}", .{ self.layout.slots[slot].label, word.text, word.score });
    }

    fn totalScore(self: *const Template, index: *const words.Index) usize {
        var total: usize = 0;
        for (self.state.words[0..self.layout.slots.len]) |word| total += index.words[word.?].score;
        return total;
    }

    fn gridParagraph(self: *const Template) g.Lines {
        var lines: g.Lines = .{};
        lines.add("TEMPLATE {s}", .{self.name});
        if (self.error_text) |reason| { lines.add("error {s}", .{reason}); return lines; }
        lines.add("outcome={s} attempts={d} min_score={d}", .{ @tagName(self.final_attempt.outcome), self.attempts.items.len, self.final_attempt.min_score });
        render.gridLines(self.layout.grid, self.state, &lines);
        lines.write("numbers");
        render.numberLines(&self.layout, &lines);
        return lines;
    }

    fn clueParagraph(self: *const Template, index: *const words.Index) g.Lines {
        var lines: g.Lines = .{};
        lines.add("TEMPLATE {s}", .{self.name});
        var clued: usize = 0;
        var missing: usize = 0;
        var unfilled: usize = 0;
        for (0..2) |direction| {
            var heading = false;
            for (self.layout.slots, 0..) |slot, i| {
                if (slot.across != (direction == 0)) continue;
                if (!heading) { lines.write(if (direction == 0) "ACROSS" else "DOWN"); heading = true; }
                if (self.state.words[i]) |word| {
                    var clue: []const u8 = "(no clue)";
                    if (self.chosen[i]) |chosen| { clued += 1; clue = chosen; } else missing += 1;
                    lines.write(render.listLine(slot, clue, index.words[word].text, g.fmt("{d}", .{index.words[word].score}), self.theme_slots[i]));
                } else {
                    unfilled += 1;
                    var buffer: [15]u8 = undefined;
                    lines.write(render.listLine(slot, "(unfilled)", self.state.pattern(slot, &buffer), "-", false));
                }
            }
        }
        lines.add("clued={d} missing={d} unfilled={d}", .{ clued, missing, unfilled });
        return lines;
    }

    fn qualityLines(self: *const Template, index: *const words.Index, weak_score: usize, lines: *g.Lines) void {
        var weakest: usize = 0;
        var weak: g.Text = .{};
        for (self.layout.slots, 0..) |_, i| {
            const score = index.words[self.state.words[i].?].score;
            if (score < index.words[self.state.words[weakest].?].score) weakest = i;
            if (score < weak_score) {
                if (weak.value().len > 0) weak.write(",");
                weak.write(self.entry(index, i));
            }
        }
        const total = self.totalScore(index);
        lines.add("quality total={d} average={s} weakest={s} weak={s}", .{ total, render.decimal(total, self.layout.slots.len, 2), self.entry(index, weakest), if (weak.value().len > 0) weak.value() else "-" });
        var used = [_]bool{false} ** 26;
        var whites: usize = 0;
        var points: usize = 0;
        var worst: ?usize = null;
        var worst_sum: usize = 0;
        for (self.layout.grid.cells, 0..) |symbol, cell| {
            if (symbol == '#') continue;
            whites += 1;
            const letter = self.state.letters[cell] - 'A';
            used[letter] = true;
            points += letter_points[letter];
            if (self.layout.ownerCount(cell) == 2) {
                const across = self.layout.across[cell].?;
                const down = self.layout.down[cell].?;
                const score = index.words[self.state.words[across].?].score + index.words[self.state.words[down].?].score;
                if (worst == null or score < worst_sum) { worst = cell; worst_sum = score; }
            }
        }
        var missing: g.Text = .{};
        var distinct: usize = 0;
        for (used, 0..) |present, i| {
            if (present) distinct += 1 else missing.add("{c}", .{@as(u8, @intCast('A' + i))});
        }
        var crossing: []const u8 = "-";
        if (worst) |cell| {
            const across = self.layout.across[cell].?;
            const down = self.layout.down[cell].?;
            crossing = g.fmt("{s} {s}:{s}+{s}:{s}={d}", .{
                self.layout.grid.cellText(cell), self.layout.slots[across].label, index.words[self.state.words[across].?].text,
                self.layout.slots[down].label, index.words[self.state.words[down].?].text, worst_sum,
            });
        }
        lines.add("letters distinct={d} pangram={s} missing={s} scrabble={s} worst_crossing={s}", .{
            distinct, if (missing.value().len > 0) "no" else "yes", if (missing.value().len > 0) missing.value() else "-", render.decimal(points, whites, 2), crossing,
        });
    }

    fn statsParagraph(self: *const Template, index: *const words.Index, weak_score: usize) g.Lines {
        var lines: g.Lines = .{};
        const grid = self.layout.grid;
        lines.add("TEMPLATE {s}", .{self.name});
        var whites: usize = 0;
        var givens: usize = 0;
        var unchecked: usize = 0;
        for (grid.cells, 0..) |symbol, cell| {
            if (symbol == '#') continue;
            whites += 1;
            givens += @intFromBool(symbol != '.');
            unchecked += @intFromBool(self.layout.ownerCount(cell) == 1);
        }
        const black = grid.cells.len - whites;
        const rot = grid.asymmetricCell("rot180") == null;
        const mirror = grid.asymmetricCell("mirror") == null;
        const symmetries = if (rot) (if (mirror) "rot180,mirror" else "rot180") else (if (mirror) "mirror" else "none");
        lines.add("grid size={d}x{d} blocks={d} white={d} density={s} givens={d} required={s} symmetry={s}", .{
            grid.width, grid.height, black, whites, render.decimal(100 * black, grid.cells.len, 1), givens, self.symmetry, symmetries,
        });
        var lengths = [_]usize{0} ** 16;
        var across: usize = 0;
        var longest: usize = 0;
        var length_sum: usize = 0;
        var themes: g.Text = .{};
        for (self.layout.slots, 0..) |slot, i| {
            lengths[slot.cells.len] += 1;
            across += @intFromBool(slot.across);
            longest = @max(longest, slot.cells.len);
            length_sum += slot.cells.len;
            if (self.theme_slots[i]) {
                if (themes.value().len > 0) themes.write(" ");
                themes.write(self.entry(index, i));
            }
        }
        var distribution: g.Text = .{};
        var coverage: g.Text = .{};
        for (3..16) |length| {
            if (lengths[length] == 0) continue;
            if (distribution.value().len > 0) distribution.write(",");
            distribution.add("{d}:{d}", .{ length, lengths[length] });
            var supply: usize = 0;
            for (index.length[length]) |word| supply += @intFromBool(index.words[word].score >= self.min_score);
            if (coverage.value().len > 0) coverage.write(" ");
            coverage.add("{d}:{d}", .{ length, supply });
        }
        lines.add("slots across={d} down={d} total={d} lengths={s} avg_length={s} longest={d} unchecked={d}", .{
            across, self.layout.slots.len - across, self.layout.slots.len, distribution.value(), render.decimal(length_sum, self.layout.slots.len, 2), longest, unchecked,
        });
        if (themes.value().len > 0) lines.add("themes {s}", .{themes.value()});
        lines.add("coverage {s}", .{coverage.value()});
        var counts: [150]usize = undefined;
        var tight: [150]usize = undefined;
        var tight_count: usize = 0;
        var buffer: [15]u8 = undefined;
        for (self.layout.slots, 0..) |slot, i| {
            if (self.theme_slots[i]) continue;
            counts[i] = index.candidates(self.initial.pattern(slot, &buffer), self.min_score, &self.initial.used, null);
            var position = tight_count;
            tight_count += 1;
            while (position > 0 and counts[i] < counts[tight[position - 1]]) : (position -= 1) tight[position] = tight[position - 1];
            tight[position] = i;
        }
        var tightest: g.Text = .{};
        for (tight[0..@min(tight_count, 3)], 0..) |i, position| {
            if (position > 0) tightest.write(" ");
            tightest.add("{s}:{d}", .{ self.layout.slots[i].label, counts[i] });
        }
        lines.add("tightest {s}", .{if (tightest.value().len > 0) tightest.value() else "-"});
        for (self.attempts.items, 1..) |attempt, number| lines.add("attempt {d} min_score={d} budget={d} outcome={s} nodes={d} backtracks={d} prunes={d} dead_ends={d} max_depth={d}", .{
            number, attempt.min_score, attempt.budget, @tagName(attempt.outcome), attempt.nodes, attempt.backtracks, attempt.prunes, attempt.dead_ends, attempt.max_depth,
        });
        var trace: g.Text = .{};
        for (self.final_attempt.trace[0..self.final_attempt.trace_count], 0..) |item, i| { if (i > 0) trace.write(" "); trace.write(item); }
        lines.add("trace {s}", .{if (trace.value().len > 0) trace.value() else "-"});
        var hot: [150]usize = undefined;
        var hot_count: usize = 0;
        for (0..self.layout.slots.len) |i| {
            if (self.final_attempt.failures[i] == 0) continue;
            var position = hot_count;
            hot_count += 1;
            while (position > 0 and self.final_attempt.failures[i] > self.final_attempt.failures[hot[position - 1]]) : (position -= 1) hot[position] = hot[position - 1];
            hot[position] = i;
        }
        var hotspots: g.Text = .{};
        for (hot[0..@min(hot_count, 3)], 0..) |i, position| {
            if (position > 0) hotspots.write(" ");
            hotspots.add("{s}:{d}", .{ self.layout.slots[i].label, self.final_attempt.failures[i] });
        }
        lines.add("hotspots {s}", .{if (hotspots.value().len > 0) hotspots.value() else "-"});
        if (self.final_attempt.outcome == .filled) {
            var order: g.Text = .{};
            for (self.final_attempt.sequence[0..self.final_attempt.depth], 0..) |i, position| { if (position > 0) order.write(" "); order.write(self.layout.slots[i].label); }
            lines.add("order {s}", .{if (order.value().len > 0) order.value() else "-"});
            self.qualityLines(index, weak_score, &lines);
        } else {
            var assigned: usize = 0;
            var lettered: usize = 0;
            var blocked: g.Text = .{};
            for (self.layout.slots, 0..) |slot, i| {
                if (self.state.words[i] != null) assigned += 1 else if (index.candidates(self.state.pattern(slot, &buffer), self.final_attempt.min_score, &self.state.used, null) == 0) {
                    if (blocked.value().len > 0) blocked.write(",");
                    blocked.write(slot.label);
                }
            }
            for (grid.cells, 0..) |symbol, cell| if (symbol != '#' and self.state.letters[cell] != '.') { lettered += 1; };
            lines.add("partial assigned={d}/{d} letters={d}/{d} blocked={s}", .{ assigned, self.layout.slots.len, lettered, whites, if (blocked.value().len > 0) blocked.value() else "-" });
        }
        return lines;
    }
};

fn readLines(io: std.Io, name: []const u8) !g.Strings {
    return g.lines(try std.Io.Dir.cwd().readFileAlloc(io, g.fmt("input/{s}", .{name}), g.allocator, .unlimited));
}
fn ignored(line: []const u8) bool { return line.len == 0 or line[0] == '#'; }
fn validName(name: []const u8) bool {
    if (name.len < 1 or name.len > 20) return false;
    for (name) |character| if (!((character >= 'a' and character <= 'z') or (character >= '0' and character <= '9') or character == '_')) return false;
    return true;
}
fn validSymmetry(name: []const u8) bool { return g.eq(name, "rot180") or g.eq(name, "mirror") or g.eq(name, "none"); }

fn readSettings(io: std.Io) !Settings {
    var result: Settings = undefined;
    for (try readLines(io, "params.txt")) |line| {
        if (ignored(line)) continue;
        const parts = g.split(line, ' ');
        if (g.eq(parts[0], "node_budget")) result.node_budget = g.number(parts[1]) else if (g.eq(parts[0], "min_score")) result.min_score = g.number(parts[1]) else if (g.eq(parts[0], "relax_step")) result.relax_step = g.number(parts[1]) else if (g.eq(parts[0], "weak_score")) result.weak_score = g.number(parts[1]) else result.symmetry = parts[1];
    }
    return result;
}

fn readWords(io: std.Io) !WordList {
    const source = try readLines(io, "words.txt");
    var accepted: std.ArrayList(words.Word) = .empty;
    var invalid: g.Lines = .{};
    var duplicates: g.Lines = .{};
    for (source, 1..) |line, number| {
        if (words.wordLineError(line)) |reason| { invalid.add("invalid {d} {s}", .{ number, reason }); continue; }
        const parts = g.split(line, ' ');
        var existing: ?usize = null;
        for (accepted.items, 0..) |word, i| if (g.eq(word.text, parts[0])) { existing = i; break; };
        if (existing) |i| duplicates.add("duplicate {d} {s} first={d}", .{ number, parts[0], accepted.items[i].first }) else g.append(words.Word, &accepted, .{ .text = parts[0], .score = g.number(parts[1]), .first = number });
    }
    return .{ .index = words.Index.init(accepted.items), .lines = source.len, .invalid = invalid, .duplicates = duplicates };
}

fn readClues(io: std.Io, index: *words.Index) !ClueBook {
    var clues: std.ArrayList(Clue) = .empty;
    var entries: usize = 0;
    var invalid: g.Lines = .{};
    var unknown: g.Lines = .{};
    for (try readLines(io, "clues.txt"), 1..) |line, number| {
        if (ignored(line)) continue;
        entries += 1;
        if (words.clueLineError(line)) |reason| { invalid.add("clue_invalid {d} {s}", .{ number, reason }); continue; }
        const parts = g.split(line, '|');
        const word = index.find(parts[0]) orelse { unknown.add("clue_unknown {d} {s}", .{ number, parts[0] }); continue; };
        const ids = &index.words[word].clues;
        g.append(usize, ids, clues.items.len);
        g.append(Clue, &clues, .{ .word = word, .number = ids.items.len, .text = parts[1] });
    }
    return .{ .clues = clues.items, .entries = entries, .invalid = invalid, .unknown = unknown };
}

fn readTemplates(io: std.Io, settings: Settings) ![]Template {
    var templates: std.ArrayList(Template) = .empty;
    var current: ?usize = null;
    for (try readLines(io, "templates.txt")) |line| {
        if (current) |i| {
            if (g.eq(line, "END")) current = null else if (std.mem.indexOfScalar(u8, line, ' ') != null) g.append([]const u8, &templates.items[i].options, line) else g.append([]const u8, &templates.items[i].rows, line);
        } else if (std.mem.startsWith(u8, line, "TEMPLATE ")) {
            current = templates.items.len;
            g.append(Template, &templates, .{ .name = line[9..], .budget = settings.node_budget, .min_score = settings.min_score, .symmetry = settings.symmetry });
        }
    }
    return templates.items;
}

fn totals(templates: []const Template, index: *const words.Index, lines: *g.Lines) void {
    var filled: [30]usize = undefined;
    var filled_count: usize = 0;
    var invalid: usize = 0;
    var outcomes = [_]usize{0} ** 3;
    var attempts: usize = 0;
    var nodes: usize = 0;
    const appearances = g.alloc(usize, index.words.len);
    @memset(appearances, 0);
    const names = g.alloc(g.Text, index.words.len);
    @memset(names, .{});
    for (templates, 0..) |*template, i| {
        if (template.error_text != null) { invalid += 1; continue; }
        outcomes[@intFromEnum(template.final_attempt.outcome)] += 1;
        attempts += template.attempts.items.len;
        for (template.attempts.items) |attempt| nodes += attempt.nodes;
        if (template.final_attempt.outcome != .filled) continue;
        var position = filled_count;
        filled_count += 1;
        const total = template.totalScore(index);
        while (position > 0) {
            const previous = &templates[filled[position - 1]];
            const left = total * previous.layout.slots.len;
            const right = previous.totalScore(index) * template.layout.slots.len;
            if (left < right or (left == right and std.mem.order(u8, template.name, previous.name) != .lt)) break;
            filled[position] = filled[position - 1];
            position -= 1;
        }
        filled[position] = i;
        for (template.state.words[0..template.layout.slots.len]) |value| {
            const word = value.?;
            if (appearances[word] > 0) names[word].write(",");
            names[word].write(template.name);
            appearances[word] += 1;
        }
    }
    var ranking: g.Lines = .{};
    ranking.write("RANKING");
    for (filled[0..filled_count], 1..) |i, rank| {
        const template = &templates[i];
        const total = template.totalScore(index);
        ranking.add("rank {d} {s} average={s} total={d} entries={d}", .{ rank, template.name, render.decimal(total, template.layout.slots.len, 2), total, template.layout.slots.len });
    }
    lines.paragraph(ranking);
    var reused: [2000]usize = undefined;
    var reuse_count: usize = 0;
    for (index.words, 0..) |word, i| {
        if (appearances[i] < 2) continue;
        var position = reuse_count;
        reuse_count += 1;
        while (position > 0) {
            const previous = reused[position - 1];
            if (appearances[i] < appearances[previous] or (appearances[i] == appearances[previous] and std.mem.order(u8, word.text, index.words[previous].text) != .lt)) break;
            reused[position] = previous;
            position -= 1;
        }
        reused[position] = i;
    }
    var reuse: g.Lines = .{};
    reuse.write("REUSE");
    for (reused[0..reuse_count]) |word| reuse.add("reused {s} {d} {s}", .{ index.words[word].text, appearances[word], names[word].value() });
    lines.paragraph(reuse);
    var summary: g.Lines = .{};
    summary.add("SUMMARY templates={d} invalid={d} filled={d} unfillable={d} budget={d} attempts={d} nodes={d}", .{
        templates.len, invalid, outcomes[@intFromEnum(filler.Outcome.filled)], outcomes[@intFromEnum(filler.Outcome.unfillable)], outcomes[@intFromEnum(filler.Outcome.budget)], attempts, nodes,
    });
    lines.paragraph(summary);
}

fn wordlistLines(list: *const WordList, book: ClueBook) g.Lines {
    const index = &list.index;
    var lines: g.Lines = .{};
    lines.add("WORDLIST lines={d} valid={d} invalid={d} duplicates={d}", .{ list.lines, index.words.len, list.invalid.data.items.len, list.duplicates.data.items.len });
    for (list.invalid.data.items) |line| lines.write(line);
    for (list.duplicates.data.items) |line| lines.write(line);
    for (3..16) |length| {
        const pool = index.length[length];
        if (pool.len == 0) continue;
        var total: usize = 0;
        for (pool) |word| total += index.words[word].score;
        const best = index.words[pool[0]];
        lines.add("length {d} words={d} average={s} best={s}:{d}", .{ length, pool.len, render.decimal(total, pool.len, 2), best.text, best.score });
    }
    var bands = [_]usize{0} ** 5;
    var letters = [_]usize{0} ** 26;
    for (index.words) |word| {
        bands[(word.score - 1) / 20] += 1;
        var seen = [_]bool{false} ** 26;
        for (word.text) |letter| seen[letter - 'A'] = true;
        for (seen, 0..) |present, letter| letters[letter] += @intFromBool(present);
    }
    lines.add("bands 1-20={d} 21-40={d} 41-60={d} 61-80={d} 81-100={d}", .{ bands[0], bands[1], bands[2], bands[3], bands[4] });
    var top: g.Text = .{};
    top.write("top");
    for (index.words[0..@min(index.words.len, 5)]) |word| top.add(" {s}:{d}", .{ word.text, word.score });
    lines.write(top.value());
    var rare: [26]usize = undefined;
    for (0..26) |letter| {
        var position = letter;
        while (position > 0 and letters[letter] < letters[rare[position - 1]]) : (position -= 1) rare[position] = rare[position - 1];
        rare[position] = letter;
    }
    var rare_text: g.Text = .{};
    rare_text.write("rare_letters");
    for (rare[0..5]) |letter| rare_text.add(" {c}:{d}", .{ @as(u8, @intCast('A' + letter)), letters[letter] });
    lines.write(rare_text.value());
    var clued_words: usize = 0;
    var used: usize = 0;
    var repeated: usize = 0;
    for (index.words) |word| clued_words += @intFromBool(word.clues.items.len > 0);
    for (book.clues) |clue| { used += @intFromBool(clue.uses >= 1); repeated += @intFromBool(clue.uses >= 2); }
    lines.add("CLUES entries={d} valid={d} invalid={d} unknown={d} words={d}", .{ book.entries, book.clues.len, book.invalid.data.items.len, book.unknown.data.items.len, clued_words });
    for (book.invalid.data.items) |line| lines.write(line);
    for (book.unknown.data.items) |line| lines.write(line);
    lines.add("CLUE_USE used={d} unused={d} repeated={d}", .{ used, book.clues.len - used, repeated });
    var alphabetical: [2000]usize = undefined;
    for (index.words, 0..) |word, i| {
        var position = i;
        while (position > 0 and std.mem.order(u8, word.text, index.words[alphabetical[position - 1]].text) == .lt) : (position -= 1) alphabetical[position] = alphabetical[position - 1];
        alphabetical[position] = i;
    }
    for (alphabetical[0..index.words.len]) |word| {
        for (index.words[word].clues.items) |id| {
            const clue = book.clues[id];
            if (clue.uses >= 2) lines.add("repeated {s} clue={d} uses={d}", .{ index.words[word].text, clue.number, clue.uses });
        }
    }
    return lines;
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    g.allocator = arena.allocator();
    const settings = try readSettings(init.io);
    var word_list = try readWords(init.io);
    const index = &word_list.index;
    var book = try readClues(init.io, index);
    const templates = try readTemplates(init.io, settings);
    var grid: g.Lines = .{};
    var clues: g.Lines = .{};
    var stats: g.Lines = .{};
    for (templates, 0..) |*template, i| {
        template.error_text = template.check(templates[0..i], index);
        if (template.error_text == null) {
            template.process(index, &book, settings.relax_step);
            clues.paragraph(template.clueParagraph(index));
            stats.paragraph(template.statsParagraph(index, settings.weak_score));
        }
        grid.paragraph(template.gridParagraph());
    }
    totals(templates, index, &stats);
    try render.writeLines(init.io, "grid.txt", grid);
    try render.writeLines(init.io, "clues.txt", clues);
    try render.writeLines(init.io, "search_stats.txt", stats);
    try render.writeLines(init.io, "wordlist.txt", wordlistLines(&word_list, book));
}
