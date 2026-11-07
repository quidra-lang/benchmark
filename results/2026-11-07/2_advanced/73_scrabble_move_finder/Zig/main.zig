const std = @import("std");
const b = @import("board.zig");
const dictionary = @import("dictionary_trie.zig");
const generator = @import("move_generator.zig");
const scoring = @import("scoring.zig");
const game = @import("game.zig");
const n = b.n;
const u = b.u;
const Job = []const []const u8;
const Strategy = enum { score, tiles, equity };
const Evaluated = struct { move: b.Move, result: scoring.Scored, leave: b.Word, value: i64 };
const TopnTotals = struct { jobs: usize = 0, errors: usize = 0, moves: usize = 0, bingos: usize = 0 };
const ValidationTotals = struct { jobs: usize = 0, errors: usize = 0, moves: usize = 0, valid: usize = 0,
     invalid: usize = 0, loss: i64 = 0 };
const GameTotals = struct { games: usize = 0, duplicates: usize = 0, errors: usize = 0, turns: usize = 0,
     rounds: usize = 0, plays: usize = 0, exchanges: usize = 0, passes: usize = 0, bingos: usize = 0 };
fn validName(value: []const u8) bool {
    if (value.len < 1 or value.len > 20) return false;
    for (value) |letter| if (!b.lower(letter) and !(letter >= '0' and letter <= '9') and letter != '_') return false;
    return true;
}
fn validNumber(value: []const u8, minimum: i64, maximum: i64) bool {
    if (value.len == 0 or (value.len > 1 and value[0] == '0')) return false;
    var number: i64 = 0;
    for (value) |digit| {
        if (digit < '0' or digit > '9') return false;
        number = number * 10 + digit - '0';
        if (number > maximum) return false;
    }
    return number >= minimum;
}
fn validRack(value: []const u8) bool {
    if (value.len < 1 or value.len > 7) return false;
    for (value) |letter| if (!b.upper(letter) and letter != '?') return false;
    return true;
}
fn strategy(value: []const u8) ?Strategy {
    return if (b.eq(value, "score")) .score else if (b.eq(value, "tiles")) .tiles else if (b.eq(value,
         "equity")) .equity else null;
}
fn charLess(_: void, left: u8, right: u8) bool {
    return left < right;
}
fn collection(value: []const u8) []const u8 {
    if (value.len == 0) return "-";
    const out = b.dupe(u8, value);
    std.mem.sort(u8, out, {}, charLess);
    return out;
}
fn removeTiles(rack: []const u8, removed: []const u8) b.Word {
    var counts = [_]i64{0} ** 128;
    for (rack) |tile| counts[tile] += 1;
    for (removed) |tile| counts[tile] -= 1;
    var out: b.Word = .{};
    for (counts, 0..) |count, tile| {
        var i: i64 = 0;
        while (i < count) : (i += 1) out.add(@intCast(tile));
    }
    return out;
}
fn joined(values: []const []const u8, separator: []const u8) []const u8 {
    var out: b.Text = .{};
    for (values, 0..) |value, i| {
        if (i > 0) out.add("{s}", .{separator});
        out.add("{s}", .{value});
    }
    return out.value();
}
fn notation(move: Evaluated) []const u8 {
    return b.fmt("{s} {s}", .{ b.position(move.move), move.move.word.text() });
}
fn wordList(move: Evaluated) []const u8 {
    var out: b.Text = .{};
    for (move.result.words[0..move.result.count], 0..) |word, i| {
        if (i > 0) out.add(",", .{});
        out.add("{s}:{d}", .{ word.word.word.text(), word.score });
    }
    return out.value();
}
fn standardBefore(left: Evaluated, right: Evaluated) bool {
    if (left.result.score != right.result.score) return left.result.score > right.result.score;
    if (left.move.row != right.move.row) return left.move.row < right.move.row;
    if (left.move.column != right.move.column) return left.move.column < right.move.column;
    if (left.move.direction != right.move.direction) return left.move.direction < right.move.direction;
    return std.mem.lessThan(u8, left.move.word.text(), right.move.word.text());
}
fn strategyBefore(order: Strategy, left: Evaluated, right: Evaluated) bool {
    if (order == .tiles and left.result.tiles.count != right.result.tiles.count) return left.result.tiles.count > right.result.tiles.count;
    if (order == .equity and left.result.score + left.value != right.result.score + right.value) return left.result.score + left.value > right.result.score + right.value;
    return standardBefore(left, right);
}
fn choose(moves: []const Evaluated, order: Strategy) Evaluated {
    var best = moves[0];
    for (moves[1..]) |move| if (strategyBefore(order, move, best)) {
        best = move;
    };
    return best;
}
fn samePlacement(left: b.Placement, right: b.Placement) bool {
    if (left.count != right.count) return false;
    for (left.items[0..left.count]) |tile| {
        var found = false;
        for (right.items[0..right.count]) |other| if (tile.row == other.row and tile.column == other.column and tile.letter == other.letter) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    return true;
}
const Program = struct {
    work: std.mem.Allocator,
    values: b.Counts = [_]i64{0} ** 27,
    counts: b.Counts = [_]i64{0} ** 27,
    weights: b.Counts = [_]i64{0} ** 27,
    trie: dictionary.Trie,
    jobs: []const Job = &.{},
    dictionary_lines: b.Lines = .{},
    topn_totals: TopnTotals = .{},
    validation_totals: ValidationTotals = .{},
    game_totals: GameTotals = .{},
    fn readInputs(self: *Program, io: std.Io) !void {
        for (try b.readLines(io, "input/tiles.txt")) |line| {
            if (line.len == 0 or line[0] == '#') continue;
            const row = b.words(line);
            const tile = b.tileIndex(row[0][0]);
            self.values[tile] = b.number(row[1]);
            self.counts[tile] = b.number(row[2]);
            self.weights[tile] = b.number(row[3]);
        }
        var candidates: usize = 0;
        var skipped: usize = 0;
        var duplicates: usize = 0;
        var lengths = [_]usize{0} ** 16;
        for (try b.readLines(io, "input/dictionary.txt")) |line| {
            if (line.len == 0 or line[0] == '#') continue;
            candidates += 1;
            var valid = line.len >= 2 and line.len <= 15;
            for (line) |letter| if (!b.upper(letter)) {
                valid = false;
            };
            if (!valid) skipped += 1 else if (self.trie.add(line)) lengths[line.len] += 1 else duplicates += 1;
        }
        self.dictionary_lines.add("DICTIONARY lines={d} words={d} skipped={d} duplicates={d} nodes={d}",
             .{ candidates, self.trie.words, skipped, duplicates, self.trie.nodes.items.len });
        var description: b.Text = .{};
        description.add("lengths", .{});
        for (2..16) |length| if (lengths[length] > 0) description.add(" {d}={d}", .{ length, lengths[length] });
        self.dictionary_lines.add("{s}", .{description.value()});
        var jobs: std.ArrayList(Job) = .empty;
        var current: std.ArrayList([]const u8) = .empty;
        for (try b.readLines(io, "input/jobs.txt")) |line| {
            if (current.items.len == 0) {
                if (line.len > 0 and line[0] != '#') b.append([]const u8, &current, line);
            } else if (b.eq(line, "END")) {
                b.append(Job, &jobs, current.items);
                current = .empty;
            } else b.append([]const u8, &current, line);
        }
        self.jobs = jobs.items;
    }
    fn initialRows(_: *const Program, job: Job) []const []const u8 {
        const header = b.words(job[0]);
        const start: usize = if (b.eq(header[0], "TOPN")) 3 else 2;
        var last = start;
        while (last < job.len and !std.mem.startsWith(u8, job[last], "MOVE")) : (last += 1) {}
        return job[start..last];
    }
    fn fromRows(_: *const Program, rows: []const []const u8) b.Board {
        var out: b.Board = undefined;
        for (0..15) |row| @memcpy(&out[row], rows[row]);
        return out;
    }
    fn usedTiles(_: *const Program, board: *const b.Board) b.Counts {
        var out = [_]i64{0} ** 27;
        const tiles = b.boardTiles(board);
        for (tiles.items[0..tiles.count]) |tile| out[b.tileIndex(tile.letter)] += 1;
        return out;
    }
    fn tileError(self: *const Program, board: *const b.Board, rack: []const u8) ?[]const u8 {
        var used = self.usedTiles(board);
        for (rack) |tile| used[b.tileIndex(tile)] += 1;
        for (self.counts, used, 0..) |count, total, tile| if (total > count) return b.fmt("too many {c}",
             .{b.tile_order[tile]});
        return null;
    }
    fn unseen(self: *const Program, board: *const b.Board, rack: []const u8) []const u8 {
        var used = self.usedTiles(board);
        for (rack) |tile| used[b.tileIndex(tile)] += 1;
        var out: b.Text = .{};
        for (self.counts, used, 0..) |count, total, tile| for (0..u(count - total)) |_| out.add("{c}",
             .{b.tile_order[tile]});
        return out.value();
    }
    fn boardError(self: *const Program, rows: []const []const u8, rack: []const u8) ?[]const u8 {
        if (rows.len != 15) return b.fmt("board rows {d}", .{rows.len});
        for (rows, 1..) |row, i| {
            var bad = row.len != 15;
            for (row) |letter| if (letter != '.' and !b.upper(letter) and !b.lower(letter)) {
                bad = true;
            };
            if (bad) return b.fmt("bad board row {d}", .{i});
        }
        const board = self.fromRows(rows);
        if (self.tileError(&board, rack)) |reason| return reason;
        if (b.boardTiles(&board).count > 0 and board[7][7] == '.') return "center empty";
        if (!b.connected(&board)) return "disconnected";
        const words = b.boardWords(&board);
        for (words.items[0..words.count]) |word| {
            var capital = word.word;
            for (capital.data[0..capital.len]) |*letter| letter.* = b.capital(letter.*);
            if (!self.trie.contains(capital.text())) return b.fmt("unknown word {s} at {s}",
                 .{ word.word.text(), b.position(word) });
        }
        return null;
    }
    fn jobError(self: *const Program, job: Job, seen: *const std.StringHashMapUnmanaged(void)) ?[]const u8 {
        const header = b.words(job[0]);
        const kind = header[0];
        const name = header[1];
        if (!validName(name)) return "bad name";
        if (seen.contains(name)) return "duplicate name";
        if (b.eq(kind, "TOPN")) {
            if (!validNumber(header[2], 1, 99)) return "bad count";
            if (strategy(header[3]) == null) return "bad order";
            const rack = b.words(job[1])[1];
            if (!validRack(rack)) return "bad rack";
            return self.boardError(self.initialRows(job), rack);
        }
        if (b.eq(kind, "VALIDATE")) return self.boardError(self.initialRows(job), "");
        if (!validNumber(header[2], 1, 2147483646)) return "bad seed";
        if (job.len - 1 < 2 or job.len - 1 > 4) return b.fmt("bad player count {d}", .{job.len - 1});
        var names: [4][]const u8 = undefined;
        for (job[1..], 1..) |line, i| {
            const row = b.words(line);
            if (!validName(row[1]) or strategy(row[2]) == null or (b.eq(kind, "GAME") and !validNumber(row[3],
                 0, 99))) return b.fmt("bad player {d}", .{i});
            for (names[0 .. i - 1]) |old| if (b.eq(old, row[1])) return b.fmt("duplicate player {d}", .{i});
            names[i - 1] = row[1];
        }
        return null;
    }
    fn leaveValue(self: *const Program, rack: []const u8) i64 {
        var counts = [_]i64{0} ** 27;
        var total: i64 = 0;
        var vowels: i64 = 0;
        var consonants: i64 = 0;
        var duplicates: i64 = 0;
        for (rack) |tile| {
            const index = b.tileIndex(tile);
            counts[index] += 1;
            total += self.weights[index];
            if (tile != '?') {
                if (std.mem.indexOfScalar(u8, "AEIOU", tile) != null) vowels += 1 else consonants += 1;
            }
        }
        for (counts[0..26]) |count| duplicates += @max(0, count - 1);
        return total - 4 * duplicates - 3 * @max(0, n(@abs(vowels - consonants)) - 1);
    }
    fn bestLeave(self: *const Program, rack: []const u8) b.Word {
        var best: b.Word = .{};
        var maximum: i64 = 0;
        for (0..(@as(usize, 1) << @intCast(rack.len)) - 1) |mask| {
            var candidate: b.Word = .{};
            for (rack, 0..) |tile, i| if (mask & (@as(usize, 1) << @intCast(i)) != 0) candidate.add(tile);
            std.mem.sort(u8, candidate.data[0..candidate.len], {}, charLess);
            const value = self.leaveValue(candidate.text());
            if (value > maximum or (value == maximum and (candidate.len > best.len or (candidate.len == best.len and std.mem.lessThan(u8,
                 candidate.text(), best.text()))))) {
                best = candidate;
                maximum = value;
            }
        }
        return best;
    }
    fn evaluate(self: *const Program, board: *const b.Board, rack: []const u8, move: b.Move) Evaluated {
        const result = scoring.scoreMove(board, move, self.values);
        var removed: b.Word = .{};
        for (result.tiles.items[0..result.tiles.count]) |tile| removed.add(if (b.upper(tile.letter)) tile.letter else '?');
        const leave = removeTiles(rack, removed.text());
        return .{ .move = move, .result = result, .leave = leave, .value = self.leaveValue(leave.text()) };
    }
    fn legalMoves(self: *const Program, allocator: std.mem.Allocator, board: *const b.Board,
         rack: []const u8) []Evaluated {
        const generated = generator.generate(allocator, board, rack, &self.trie);
        const out = allocator.alloc(Evaluated, generated.len) catch @panic("allocation failed");
        for (generated, out) |move, *value| value.* = self.evaluate(board, rack, move);
        const Context = struct {
            fn less(_: void, left: Evaluated, right: Evaluated) bool {
                return standardBefore(left, right);
            }
        };
        std.mem.sort(Evaluated, out, {}, Context.less);
        return out;
    }
    fn appendBoard(_: *const Program, out: *b.Lines, board: *const b.Board) void {
        const words = b.boardWords(board);
        const tiles = b.boardTiles(board);
        var longest: b.Word = b.Word.init("-");
        var length: usize = 0;
        var blanks: usize = 0;
        var used = [_]usize{0} ** 128;
        for (words.items[0..words.count]) |word| if (word.word.len > length) {
            longest = word.word;
            length = word.word.len;
        };
        for (tiles.items[0..tiles.count]) |tile| {
            blanks += @intFromBool(b.lower(tile.letter));
            used[b.premiums[tile.row][tile.column]] += 1;
        }
        out.add("position tiles={d} words={d} longest={s} blanks={d} premiums=TW:{d},DW:{d},TL:{d},DL:{d}",
             .{ tiles.count, words.count, longest.text(), blanks, used['#'], used['*'], used['^'],
             used['+'] });
        out.extend(b.display(board));
    }
    fn topn(self: *Program, job: Job) b.Lines {
        var arena = std.heap.ArenaAllocator.init(self.work);
        defer arena.deinit();
        const allocator = arena.allocator();
        const header = b.words(job[0]);
        const count = u(b.number(header[2]));
        const order = strategy(header[3]).?;
        const rack = b.words(job[1])[1];
        const board = self.fromRows(self.initialRows(job));
        const moves = self.legalMoves(allocator, &board, rack);
        const shown_all = allocator.dupe(Evaluated, moves) catch @panic("allocation failed");
        const Context = struct {
            fn less(context: Strategy, left: Evaluated, right: Evaluated) bool {
                return strategyBefore(context, left, right);
            }
        };
        std.mem.sort(Evaluated, shown_all, order, Context.less);
        const shown = shown_all[0..@min(count, shown_all.len)];
        const unknown = self.unseen(&board, rack);
        const anchor_squares = generator.anchors(&board);
        const swapped = b.transpose(&board);
        const checks = [_]generator.Checks{ generator.crossChecks(&board, &self.trie), generator.crossChecks(&swapped,
             &self.trie) };
        var check_counts = [_][3]usize{[_]usize{0} ** 3} ** 2;
        for (0..2) |direction| for (0..15) |row| for (0..15) |column| {
            if (checks[direction].checked[row][column]) {
                const mask = checks[direction].masks[row][column];
                check_counts[direction][0] += 1;
                check_counts[direction][1] += @intFromBool(mask == 0);
                check_counts[direction][2] += @popCount(mask);
            }
        };
        var vowels: usize = 0;
        var consonants: usize = 0;
        var blanks: usize = 0;
        for (rack) |tile| {
            if (tile == '?') blanks += 1 else if (std.mem.indexOfScalar(u8, "AEIOU", tile) != null) vowels += 1 else consonants += 1;
        }
        var across: usize = 0;
        var bingos: usize = 0;
        var blank_moves: usize = 0;
        var best_scores = [_]?i64{null} ** 8;
        for (moves) |move| {
            across += @intFromBool(move.move.direction == 0);
            bingos += @intFromBool(move.result.tiles.count == 7);
            var blank = false;
            for (move.result.tiles.items[0..move.result.tiles.count]) |tile| if (b.lower(tile.letter)) {
                blank = true;
            };
            blank_moves += @intFromBool(blank);
            const best = &best_scores[move.result.tiles.count];
            if (best.* == null or move.result.score > best.*.?) best.* = move.result.score;
        }
        var out: b.Lines = .{};
        out.add("TOPN {s} n={d} order={s} rack={s}", .{ header[1], count, header[3], collection(rack) });
        out.add("board tiles={d} anchors={d}", .{ b.boardTiles(&board).count, anchor_squares.count });
        out.add("unseen count={d} tiles={s}", .{ unknown.len, collection(unknown) });
        out.add("rack vowels={d} consonants={d} blanks={d} value={d}", .{ vowels, consonants,
             blanks, game.points(rack, self.values) });
        out.add("checks across={d},{d},{d} down={d},{d},{d}", .{ check_counts[0][0], check_counts[0][1],
             check_counts[0][2], check_counts[1][0], check_counts[1][1], check_counts[1][2] });
        out.add("moves total={d} across={d} down={d} bingos={d} blanks={d}", .{ moves.len,
             across, moves.len - across, bingos, blank_moves });
        var scores: b.Text = .{};
        scores.add("best_by_tiles", .{});
        for (1..8) |tiles| {
            if (best_scores[tiles]) |value| scores.add(" {d}={d}", .{ tiles, value }) else scores.add(" {d}=-",
                 .{tiles});
        }
        out.add("{s}", .{scores.value()});
        const keep = self.bestLeave(rack);
        out.add("exchange keep={s} value={d}", .{ collection(keep.text()), self.leaveValue(keep.text()) });
        const anagrams = self.trie.anagrams(allocator, rack);
        const Anagrams = struct {
            fn less(_: void, left: b.Word, right: b.Word) bool {
                return if (left.len != right.len) left.len > right.len else std.mem.lessThan(u8,
                     left.text(), right.text());
            }
        };
        std.mem.sort(b.Word, anagrams, {}, Anagrams.less);
        var anagram_text: b.Text = .{};
        for (anagrams[0..@min(10, anagrams.len)], 0..) |word, i| {
            if (i > 0) anagram_text.add(",", .{});
            anagram_text.add("{s}", .{word.text()});
        }
        out.add("anagrams total={d} top={s}", .{ anagrams.len, if (anagrams.len == 0) "-" else anagram_text.value() });
        const words = b.boardWords(&board);
        for (words.items[0..words.count]) |word| {
            if (word.word.len < 3) continue;
            var capital = word.word;
            for (capital.data[0..capital.len]) |*letter| letter.* = b.capital(letter.*);
            var front: b.Text = .{};
            var back: b.Text = .{};
            for (0..26) |letter| {
                var candidate: [17]u8 = undefined;
                candidate[0] = @as(u8, @intCast(letter)) + 'A';
                @memcpy(candidate[1 .. capital.len + 1], capital.text());
                if (self.trie.contains(candidate[0 .. capital.len + 1])) front.add("{c}", .{candidate[0]});
                @memcpy(candidate[0..capital.len], capital.text());
                candidate[capital.len] = @as(u8, @intCast(letter)) + 'A';
                if (self.trie.contains(candidate[0 .. capital.len + 1])) back.add("{c}", .{candidate[capital.len]});
            }
            if (front.value().len > 0 or back.value().len > 0) out.add("hook {s} {s} front={s} back={s}",
                 .{ b.position(word), word.word.text(), if (front.value().len == 0) "-" else front.value(),
                 if (back.value().len == 0) "-" else back.value() });
        }
        const endgame = unknown.len >= 1 and unknown.len <= 7 and shown.len > 0;
        var nets: [99]i64 = undefined;
        if (endgame) {
            var best: usize = 0;
            for (shown, 0..) |move, i| {
                var reply_arena = std.heap.ArenaAllocator.init(self.work);
                defer reply_arena.deinit();
                const after = scoring.apply(&board, move.result.tiles);
                const replies = self.legalMoves(reply_arena.allocator(), &after, unknown);
                nets[i] = move.result.score - (if (replies.len == 0) @as(i64, 0) else replies[0].result.score);
                if (i > 0 and nets[i] > nets[best]) best = i;
            }
            out.add("endgame opponent={s} best={d} net={d}", .{ collection(unknown), best + 1, nets[best] });
        }
        for (shown, 0..) |move, i| {
            var text: b.Text = .{};
            text.add("{d} {s} score={d} tiles={d} leave={s} value={d}", .{ i + 1, notation(move),
                 move.result.score, move.result.tiles.count, collection(move.leave.text()),
                 move.value });
            if (endgame) text.add(" net={d}", .{nets[i]});
            text.add(" words={s}", .{wordList(move)});
            out.add("{s}", .{text.value()});
        }
        self.topn_totals.moves += moves.len;
        self.topn_totals.bingos += bingos;
        return out;
    }
    const RecordCheck = struct { reason: ?[]const u8 = null, move: ?b.Move = null };
    fn recordError(self: *const Program, board: *const b.Board, player: []const u8, rack: []const u8,
         action: []const []const u8) RecordCheck {
        if (!validName(player)) return .{ .reason = "bad player" };
        if (!validRack(rack)) return .{ .reason = "bad rack" };
        if (self.tileError(board, rack)) |reason| return .{ .reason = reason };
        if (action.len == 1 and b.eq(action[0], "PASS")) return .{};
        if (b.eq(action[0], "EXCHANGE")) {
            const returned = action[1];
            if (!validRack(returned)) return .{ .reason = "bad exchange" };
            var available = [_]i64{0} ** 27;
            var requested = [_]i64{0} ** 27;
            for (rack) |tile| available[b.tileIndex(tile)] += 1;
            for (returned) |tile| requested[b.tileIndex(tile)] += 1;
            for (returned) |tile| if (requested[b.tileIndex(tile)] > available[b.tileIndex(tile)]) return .{ .reason = b.fmt("rack lacks {c}",
                 .{tile}) };
            return .{};
        }
        var move = b.parsePosition(action[0]) orelse return .{ .reason = "bad position" };
        const word = action[1];
        var bad = word.len < 2 or word.len > 15;
        for (word) |letter| if (!b.upper(letter) and !b.lower(letter)) {
            bad = true;
        };
        if (bad) return .{ .reason = "bad word" };
        move.word = b.Word.init(word);
        const cells = scoring.squares(move);
        for (cells.items[0..cells.count]) |tile| if (!b.inside(n(tile.row), n(tile.column))) return .{ .reason = "off board" };
        for (cells.items[0..cells.count]) |tile| if (board[tile.row][tile.column] != '.' and board[tile.row][tile.column] != tile.letter) return .{ .reason = b.fmt("mismatch at {s}",
             .{b.squareName(tile.row, tile.column)}) };
        const dr = n(move.direction);
        const dc = 1 - dr;
        const boundary = [_][2]i64{ .{ n(move.row) - dr, n(move.column) - dc }, .{ n(move.row) + dr * n(word.len),
             n(move.column) + dc * n(word.len) } };
        for (boundary) |point| if (b.inside(point[0], point[1]) and board[u(point[0])][u(point[1])] != '.') return .{ .reason = "not whole word" };
        const tiles = scoring.placement(board, move);
        if (tiles.count == 0) return .{ .reason = "no new tiles" };
        var available = [_]i64{0} ** 27;
        for (rack) |tile| available[b.tileIndex(tile)] += 1;
        for (tiles.items[0..tiles.count]) |tile| {
            const index = b.tileIndex(tile.letter);
            if (available[index] == 0) return .{ .reason = b.fmt("rack lacks {c}", .{b.tile_order[index]}) };
            available[index] -= 1;
        }
        if (b.boardTiles(board).count == 0) {
            var center = false;
            for (tiles.items[0..tiles.count]) |tile| if (tile.row == 7 and tile.column == 7) {
                center = true;
            };
            if (!center) return .{ .reason = "center not covered" };
        } else {
            var touches = false;
            for (tiles.items[0..tiles.count]) |tile| {
                const adjacent = b.neighbors(tile.row, tile.column);
                for (adjacent.items[0..adjacent.count]) |point| if (board[point[0]][point[1]] != '.') {
                    touches = true;
                };
            }
            if (!touches) return .{ .reason = "not connected" };
        }
        const crosses = scoring.crossWords(board, move);
        for (0..crosses.count + 1) |i| {
            const formed = if (i == 0) move else crosses.items[i - 1];
            var capital = formed.word;
            for (capital.data[0..capital.len]) |*letter| letter.* = b.capital(letter.*);
            if (!self.trie.contains(capital.text())) return .{ .reason = b.fmt("unknown word {s} at {s}",
                 .{ formed.word.text(), b.position(formed) }) };
        }
        return .{ .move = move };
    }
    fn validate(self: *Program, job: Job) b.Lines {
        var out: b.Lines = .{};
        out.add("VALIDATE {s}", .{b.words(job[0])[1]});
        var board = self.fromRows(self.initialRows(job));
        const Player = struct { name: []const u8, moves: usize = 0, valid: usize = 0, score: i64 = 0, loss: i64 = 0 };
        var players: std.ArrayList(Player) = .empty;
        var valid: usize = 0;
        var invalid: usize = 0;
        var score: i64 = 0;
        var best_total: i64 = 0;
        var loss: i64 = 0;
        for (job[17..], 1..) |line, i| {
            const row = b.words(line);
            const player = row[1];
            const rack = row[2];
            const action = row[3..];
            const checked = self.recordError(&board, player, rack, action);
            var player_index: usize = 0;
            if (checked.reason == null or !b.eq(checked.reason.?, "bad player")) {
                while (player_index < players.items.len and !b.eq(players.items[player_index].name,
                     player)) : (player_index += 1) {}
                if (player_index == players.items.len) b.append(Player, &players, .{ .name = player });
                players.items[player_index].moves += 1;
            }
            var text: b.Text = .{};
            text.add("move {d} {s} {s}", .{ i, player, joined(action, " ") });
            if (checked.reason) |reason| {
                text.add(" invalid {s}", .{reason});
                out.add("{s}", .{text.value()});
                invalid += 1;
                continue;
            }
            var arena = std.heap.ArenaAllocator.init(self.work);
            defer arena.deinit();
            const legal = self.legalMoves(arena.allocator(), &board, rack);
            const best = if (legal.len == 0) @as(i64, 0) else legal[0].result.score;
            var earned: i64 = 0;
            var rank: usize = 0;
            var played: ?Evaluated = null;
            if (checked.move) |move| {
                played = self.evaluate(&board, rack, move);
                earned = played.?.result.score;
                for (legal, 1..) |candidate, j| if (samePlacement(candidate.result.tiles, played.?.result.tiles)) {
                    rank = j;
                    break;
                };
            }
            const statistics = &players.items[player_index];
            statistics.valid += 1;
            statistics.score += earned;
            statistics.loss += best - earned;
            valid += 1;
            score += earned;
            best_total += best;
            loss += best - earned;
            if (played) |move| {
                text.add(" score={d} total={d} tiles={d} rank={d}/{d} best={d} words={s}",
                     .{ earned, statistics.score, move.result.tiles.count, rank, legal.len,
                     best, wordList(move) });
                board = scoring.apply(&board, move.result.tiles);
            } else text.add(" score=0 total={d} moves={d} best={d}", .{ statistics.score, legal.len, best });
            out.add("{s}", .{text.value()});
        }
        for (players.items) |player| out.add("player {s} moves={d} valid={d} score={d} loss={d}",
             .{ player.name, player.moves, player.valid, player.score, player.loss });
        out.add("total valid={d} invalid={d} score={d} best={d} loss={d}", .{ valid, invalid,
             score, best_total, loss });
        self.appendBoard(&out, &board);
        self.validation_totals.moves += job.len - 17;
        self.validation_totals.valid += valid;
        self.validation_totals.invalid += invalid;
        self.validation_totals.loss += loss;
        return out;
    }
    const GamePlayer = struct { name: []const u8, strategy_name: []const u8, order: Strategy,
         threshold: i64 = 0, rack: b.Word = .{}, score: i64 = 0, plays: usize = 0, bingos: usize = 0,
         exchanges: usize = 0, passes: usize = 0, top: i64 = 0, loss: i64 = 0 };
    fn ordinaryGame(self: *Program, job: Job) b.Lines {
        const header = b.words(job[0]);
        var random: game.Minstd = .{ .state = b.number(header[2]) };
        var bag = game.makeBag(self.counts, &random);
        var board = b.emptyBoard();
        const players = b.alloc(GamePlayer, job.len - 1);
        var out: b.Lines = .{};
        out.add("GAME {s} seed={d} players={d}", .{ header[1], b.number(header[2]), players.len });
        for (job[1..], players, 1..) |line, *player, i| {
            const row = b.words(line);
            player.* = .{ .name = row[1], .strategy_name = row[2], .order = strategy(row[2]).?,
                 .threshold = b.number(row[3]), .rack = game.draw(&bag, 7) };
            out.add("player {d} {s} strategy={s} threshold={d}", .{ i, player.name, player.strategy_name,
                 player.threshold });
        }
        const Highlight = struct { turn: usize, player: usize, move: Evaluated };
        var highlight: ?Highlight = null;
        var outgoing: ?usize = null;
        var turn: usize = 0;
        var consecutive: usize = 0;
        while (true) {
            const index = turn % players.len;
            const player = &players[index];
            turn += 1;
            const rack = player.rack;
            var arena = std.heap.ArenaAllocator.init(self.work);
            defer arena.deinit();
            const legal = self.legalMoves(arena.allocator(), &board, rack.text());
            const candidate: ?Evaluated = if (legal.len == 0) null else choose(legal, player.order);
            var text: b.Text = .{};
            text.add("turn {d} {s} rack={s} moves={d}", .{ turn, player.name, collection(rack.text()), legal.len });
            if (candidate != null and !(candidate.?.result.score < player.threshold and bag.count >= 7)) {
                const move = candidate.?;
                board = scoring.apply(&board, move.result.tiles);
                player.score += move.result.score;
                const drawn = game.draw(&bag, 7 - move.leave.len);
                player.rack = move.leave;
                for (drawn.text()) |tile| player.rack.add(tile);
                player.plays += 1;
                player.bingos += @intFromBool(move.result.tiles.count == 7);
                player.top = @max(player.top, move.result.score);
                player.loss += legal[0].result.score - move.result.score;
                consecutive = 0;
                if (highlight == null or move.result.score > highlight.?.move.result.score) highlight = .{ .turn = turn,
                     .player = index, .move = move };
                text.add(" best={d} play {s} score={d} total={d} draw={s} bag={d}", .{ legal[0].result.score,
                     notation(move), move.result.score, player.score, collection(drawn.text()),
                     bag.count });
                out.add("{s}", .{text.value()});
                if (player.rack.len == 0 and bag.count == 0) {
                    outgoing = index;
                    break;
                }
            } else if (bag.count >= 7) {
                const keep = self.bestLeave(rack.text());
                const returned = removeTiles(rack.text(), keep.text());
                const drawn = game.exchange(&bag, returned.text(), &random);
                player.rack = keep;
                for (drawn.text()) |tile| player.rack.add(tile);
                player.exchanges += 1;
                consecutive += 1;
                text.add(" exchange keep={s} draw={s} bag={d}", .{ collection(keep.text()),
                     collection(drawn.text()), bag.count });
                out.add("{s}", .{text.value()});
            } else {
                player.passes += 1;
                consecutive += 1;
                text.add(" pass bag={d}", .{bag.count});
                out.add("{s}", .{text.value()});
            }
            if (consecutive == 6) break;
        }
        if (outgoing) |player| out.add("end reason=out player={s} turns={d}", .{ players[player].name,
             turn }) else out.add("end reason=scoreless turns={d}", .{turn});
        const adjustments = b.alloc(i64, players.len);
        const final_scores = b.alloc(i64, players.len);
        for (players, adjustments) |player, *adjustment| adjustment.* = -game.points(player.rack.text(), self.values);
        if (outgoing) |player| {
            adjustments[player] = 0;
            for (players, 0..) |other, i| if (i != player) {
                adjustments[player] += game.points(other.rack.text(), self.values);
            };
        }
        for (players, adjustments, final_scores) |player, adjustment, *total| {
            total.* = player.score + adjustment;
            out.add("final {s} score={d} rack={s} adjust={s}{d} total={d}", .{ player.name,
                 player.score, collection(player.rack.text()), if (adjustment > 0) "+" else "",
                 adjustment, total.* });
        }
        const standings = b.alloc(usize, players.len);
        for (standings, 0..) |*player, i| player.* = i;
        const Context = struct {
            fn less(scores: []const i64, left: usize, right: usize) bool {
                return scores[left] > scores[right] or (scores[left] == scores[right] and left < right);
            }
        };
        std.mem.sort(usize, standings, @as([]const i64, final_scores), Context.less);
        for (standings, 1..) |index, i| {
            const player = players[index];
            out.add("standing {d} {s} total={d} plays={d} bingos={d} exchanges={d} passes={d} top={d} loss={d}",
                 .{ i, player.name, final_scores[index], player.plays, player.bingos, player.exchanges,
                 player.passes, player.top, player.loss });
        }
        var winners: std.ArrayList([]const u8) = .empty;
        for (players, final_scores) |player, total| if (total == final_scores[standings[0]]) b.append([]const u8,
             &winners, player.name);
        out.add("winner {s}", .{joined(winners.items, ",")});
        if (highlight) |item| out.add("highlight turn={d} player={s} play {s} score={d}", .{ item.turn,
             players[item.player].name, notation(item.move), item.move.result.score });
        self.appendBoard(&out, &board);
        self.game_totals.turns += turn;
        for (players) |player| {
            self.game_totals.plays += player.plays;
            self.game_totals.exchanges += player.exchanges;
            self.game_totals.passes += player.passes;
            self.game_totals.bingos += player.bingos;
        }
        return out;
    }
    fn duplicateGame(self: *Program, job: Job) b.Lines {
        const header = b.words(job[0]);
        var random: game.Minstd = .{ .state = b.number(header[2]) };
        var bag = game.makeBag(self.counts, &random);
        var rack = game.draw(&bag, 7);
        var board = b.emptyBoard();
        const players = b.alloc(GamePlayer, job.len - 1);
        var out: b.Lines = .{};
        out.add("DUPLICATE {s} seed={d} players={d}", .{ header[1], b.number(header[2]), players.len });
        for (job[1..], players, 1..) |line, *player, i| {
            const row = b.words(line);
            player.* = .{ .name = row[1], .strategy_name = row[2], .order = strategy(row[2]).? };
            out.add("player {d} {s} strategy={s}", .{ i, player.name, player.strategy_name });
        }
        var round: usize = 0;
        var master_total: i64 = 0;
        var went_out = false;
        while (true) {
            var arena = std.heap.ArenaAllocator.init(self.work);
            defer arena.deinit();
            const legal = self.legalMoves(arena.allocator(), &board, rack.text());
            if (legal.len == 0) break;
            round += 1;
            const master = legal[0];
            var picks: b.Text = .{};
            for (players, 0..) |*player, i| {
                const score = choose(legal, player.order).result.score;
                player.score += score;
                if (i > 0) picks.add(",", .{});
                picks.add("{d}", .{score});
            }
            master_total += master.result.score;
            out.add("round {d} rack={s} moves={d} master {s} score={d} picks={s}", .{ round,
                 collection(rack.text()), legal.len, notation(master), master.result.score,
                 picks.value() });
            board = scoring.apply(&board, master.result.tiles);
            const drawn = game.draw(&bag, 7 - master.leave.len);
            rack = master.leave;
            for (drawn.text()) |tile| rack.add(tile);
            if (rack.len == 0) {
                went_out = true;
                break;
            }
        }
        if (went_out) out.add("end reason=out rounds={d}", .{round}) else out.add("end reason=stuck rounds={d} rack={s}",
             .{ round, collection(rack.text()) });
        out.add("master total={d}", .{master_total});
        var maximum = players[0].score;
        for (players) |player| maximum = @max(maximum, player.score);
        var winners: std.ArrayList([]const u8) = .empty;
        for (players) |player| {
            const percent = if (master_total >= 1) @divFloor(100 * player.score, master_total) else 0;
            out.add("final {s} total={d} percent={d}", .{ player.name, player.score, percent });
            if (player.score == maximum) b.append([]const u8, &winners, player.name);
        }
        out.add("winner {s}", .{joined(winners.items, ",")});
        self.appendBoard(&out, &board);
        self.game_totals.rounds += round;
        return out;
    }
    fn writeBlocks(_: *const Program, io: std.Io, name: []const u8, blocks: []const b.Lines) !void {
        var text: b.Text = .{};
        for (blocks, 0..) |block, i| {
            if (i > 0) text.add("\n", .{});
            for (block.data.items) |line| text.add("{s}\n", .{line});
        }
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = b.fmt("output/{s}", .{name}), .data = text.value() });
    }
    fn run(self: *Program, io: std.Io) !void {
        try self.readInputs(io);
        var reports = [_]std.ArrayList(b.Lines){.empty} ** 3;
        b.append(b.Lines, &reports[0], self.dictionary_lines);
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        for (self.jobs) |job| {
            const header = b.words(job[0]);
            const kind = header[0];
            const name = header[1];
            var destination: usize = 2;
            if (b.eq(kind, "TOPN")) {
                destination = 0;
                self.topn_totals.jobs += 1;
            } else if (b.eq(kind, "VALIDATE")) {
                destination = 1;
                self.validation_totals.jobs += 1;
            } else if (b.eq(kind, "GAME")) self.game_totals.games += 1 else self.game_totals.duplicates += 1;
            const reason = self.jobError(job, &seen);
            seen.put(b.allocator, name, {}) catch @panic("allocation failed");
            var result: b.Lines = .{};
            if (reason) |why| {
                result.add("{s} {s}", .{ kind, name });
                result.add("error {s}", .{why});
                if (destination == 0) self.topn_totals.errors += 1 else if (destination == 1) self.validation_totals.errors += 1 else self.game_totals.errors += 1;
            } else if (destination == 0) result = self.topn(job) else if (destination == 1) result = self.validate(job) else if (b.eq(kind,
                 "GAME")) result = self.ordinaryGame(job) else result = self.duplicateGame(job);
            b.append(b.Lines, &reports[destination], result);
        }
        var summary: b.Lines = .{};
        summary.add("SUMMARY jobs={d} errors={d} moves={d} bingos={d}", .{ self.topn_totals.jobs,
             self.topn_totals.errors, self.topn_totals.moves, self.topn_totals.bingos });
        b.append(b.Lines, &reports[0], summary);
        summary = .{};
        summary.add("SUMMARY jobs={d} errors={d} moves={d} valid={d} invalid={d} loss={d}",
             .{ self.validation_totals.jobs, self.validation_totals.errors, self.validation_totals.moves,
             self.validation_totals.valid, self.validation_totals.invalid, self.validation_totals.loss });
        b.append(b.Lines, &reports[1], summary);
        summary = .{};
        summary.add("SUMMARY games={d} duplicates={d} errors={d} turns={d} rounds={d} plays={d} exchanges={d} passes={d} bingos={d}",
             .{ self.game_totals.games, self.game_totals.duplicates, self.game_totals.errors,
             self.game_totals.turns, self.game_totals.rounds, self.game_totals.plays, self.game_totals.exchanges,
             self.game_totals.passes, self.game_totals.bingos });
        b.append(b.Lines, &reports[2], summary);
        try std.Io.Dir.cwd().createDirPath(io, "output");
        const names = [_][]const u8{ "moves.txt", "validation.txt", "game.txt" };
        for (names, reports) |name, blocks| try self.writeBlocks(io, name, blocks.items);
    }
};
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    b.allocator = arena.allocator();
    var program: Program = .{ .work = init.gpa, .trie = dictionary.Trie.init() };
    try program.run(init.io);
}
