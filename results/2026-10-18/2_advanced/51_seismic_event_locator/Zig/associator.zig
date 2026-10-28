const std = @import("std");
const c = @import("waveform_io.zig");
pub const Candidate = struct { picks: []usize, first: usize };
pub fn associate(picks: []c.Pick, p: c.Params) []Candidate {
    var candidates: std.ArrayList(Candidate) = .empty;
    for (picks, 0..) |first, i| {
        if (picks[i].assigned) continue;
        var selected: std.ArrayList(usize) = .empty;
        var seen = [_]bool{false} ** 12;
        var j = i;
        while (j < picks.len and picks[j].sample <= first.sample + p.window) : (j += 1) {
            if (!picks[j].assigned and !seen[picks[j].station]) {
                seen[picks[j].station] = true;
                c.append(usize, &selected, j);
            }
        }
        if (selected.items.len < c.u(p.minimum)) continue;
        for (selected.items) |id| picks[id].assigned = true;
        c.append(Candidate, &candidates, .{ .picks = selected.items, .first = i });
    }
    return candidates.items;
}
