const b = @import("board.zig");
pub const rack_size = 7;
pub const bingo_bonus = 50;
pub fn squares(move: b.Move) b.Placement {
    var out: b.Placement = .{};
    for (move.word.text(), 0..) |letter, i| out.add(.{ .row = move.row + move.direction * i,
         .column = move.column + (1 - move.direction) * i, .letter = letter });
    return out;
}
pub fn placement(board: *const b.Board, move: b.Move) b.Placement {
    var out: b.Placement = .{};
    const cells = squares(move);
    for (cells.items[0..cells.count]) |tile| if (board[tile.row][tile.column] == '.') out.add(tile);
    return out;
}
pub fn apply(board: *const b.Board, tiles: b.Placement) b.Board {
    var out = board.*;
    for (tiles.items[0..tiles.count]) |tile| out[tile.row][tile.column] = tile.letter;
    return out;
}
pub fn crossWords(board: *const b.Board, move: b.Move) b.Words {
    const tiles = placement(board, move);
    const after = apply(board, tiles);
    var out: b.Words = .{};
    for (tiles.items[0..tiles.count]) |tile| {
        const word = b.runAt(&after, tile.row, tile.column, 1 - move.direction);
        if (word.word.len >= 2) out.add(word);
    }
    return out;
}
pub fn wordScore(board: *const b.Board, word: b.Move, values: b.Counts) i64 {
    const cells = squares(word);
    var score: i64 = 0;
    var multiplier: i64 = 1;
    for (cells.items[0..cells.count]) |tile| {
        var value = if (b.upper(tile.letter)) values[tile.letter - 'A'] else @as(i64, 0);
        if (board[tile.row][tile.column] == '.') {
            const premium = b.premiums[tile.row][tile.column];
            value *= if (premium == '+') @as(i64, 2) else if (premium == '^') 3 else 1;
            multiplier *= if (premium == '*') @as(i64, 2) else if (premium == '#') 3 else 1;
        }
        score += value;
    }
    return score * multiplier;
}
pub const WordScore = struct { word: b.Move, score: i64 };
pub const Scored = struct { score: i64 = 0, tiles: b.Placement, words: [16]WordScore = undefined, count: usize = 0 };
pub fn scoreMove(board: *const b.Board, move: b.Move, values: b.Counts) Scored {
    var out: Scored = .{ .tiles = placement(board, move) };
    out.words[0] = .{ .word = move, .score = wordScore(board, move, values) };
    out.count = 1;
    const crosses = crossWords(board, move);
    for (crosses.items[0..crosses.count]) |word| {
        out.words[out.count] = .{ .word = word, .score = wordScore(board, word, values) };
        out.count += 1;
    }
    for (out.words[0..out.count]) |word| out.score += word.score;
    if (out.tiles.count == rack_size) out.score += bingo_bonus;
    return out;
}
