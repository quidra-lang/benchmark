const d = @import("song_parser.zig");
pub const Next = struct { position: usize, row: usize, stop: bool = false };
pub fn samplesPerTick(song: *const d.Song, tempo: i64) usize {
    return d.u(@divTrunc(song.rate * 5, tempo * 2));
}
pub fn nextRow(song: *const d.Song, position: usize, row: usize) Next {
    const cells = song.patterns[song.order[position]].?[row];
    var jump: ?usize = null;
    var break_: ?usize = null;
    var stop = false;
    for (cells) |cell| {
        const effect = cell.effect;
        if (d.eq(effect.name, "F") and effect.argument == 0) stop = true else if (d.eq(effect.name,
             "B")) jump = d.u(effect.argument) else if (d.eq(effect.name, "D")) break_ = d.u(effect.argument);
    }
    if (jump != null or break_ != null) return .{ .position = jump orelse position + 1, .row = if (break_ != null and break_.? < 64) break_.? else 0,
         .stop = stop };
    return if (row < 63) .{ .position = position, .row = row + 1, .stop = stop } else .{ .position = position + 1,
         .row = 0, .stop = stop };
}
pub fn reachable(song: *const d.Song) [][64]bool {
    const reached = d.alloc([64]bool, song.order.len);
    @memset(reached, @splat(false));
    var position: usize = 0;
    var row: usize = 0;
    while (position < song.order.len and !reached[position][row]) {
        reached[position][row] = true;
        const next = nextRow(song, position, row);
        if (next.stop) break;
        position = next.position;
        row = next.row;
    }
    return reached;
}
