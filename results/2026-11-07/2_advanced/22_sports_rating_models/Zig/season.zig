const std = @import("std");
const r = @import("report.zig");

pub const Team = struct { code: []const u8, name: []const u8 };
pub const Match = struct {
    round: usize, order: usize, home: usize, away: usize, home_score: i64, away_score: i64, margin: i64, y2: i64,
    pub fn result(self: Match) f64 { return r.f(self.y2) / 2; }
};
pub const Settings = struct {
    win_points: i64, draw_points: i64, form_length: usize, close_margin: i64, exponent: f64,
    elo_k: i64, elo_home: i64, elo_initial: i64, grid_k: []i64, grid_home: []i64,
    bt_iterations: usize, od_iterations: usize, link_iterations: usize, holdout_round: usize,
    upsets: usize, calibration_bins: usize, simulations: usize, seed: i64, top_positions: usize, bottom_positions: usize,
};
pub const Season = struct {
    teams: []Team, matches: []Match, rounds: usize, settings: Settings,
    pub fn before(self: Season, round: usize) usize {
        var count: usize = 0;
        while (count < self.matches.len and self.matches[count].round < round) count += 1;
        return count;
    }
};

fn teamIndex(teams: []const Team, code: []const u8) usize {
    for (teams, 0..) |team, i| if (r.eq(team.code, code)) return i;
    unreachable;
}
fn integers(fields: []const []const u8) []i64 {
    const result = r.alloc(i64, fields.len - 1);
    for (fields[1..], result) |text, *value| value.* = r.number(text);
    return result;
}
fn matchLessThan(_: void, first: Match, second: Match) bool {
    return if (first.round != second.round) first.round < second.round else first.order < second.order;
}

pub fn load(io: std.Io) !Season {
    const team_data = try std.Io.Dir.cwd().readFileAlloc(io, "input/teams.csv", r.allocator, .unlimited);
    const team_lines = r.lines(team_data);
    const teams = r.alloc(Team, team_lines.len - 1);
    for (team_lines[1..], teams) |line, *team| {
        const fields = r.split(line, ',');
        team.* = .{ .code = fields[0], .name = fields[1] };
    }
    const match_data = try std.Io.Dir.cwd().readFileAlloc(io, "input/matches.csv", r.allocator, .unlimited);
    const match_lines = r.lines(match_data);
    const matches = r.alloc(Match, match_lines.len - 1);
    for (match_lines[1..], matches, 0..) |line, *match, i| {
        const fields = r.split(line, ',');
        const home_score = r.number(fields[3]);
        const away_score = r.number(fields[4]);
        const margin = home_score - away_score;
        match.* = .{ .round = r.u(r.number(fields[0])), .order = i, .home = teamIndex(teams, fields[1]), .away = teamIndex(teams, fields[2]), .home_score = home_score, .away_score = away_score, .margin = margin, .y2 = if (margin > 0) 2 else if (margin == 0) 1 else 0 };
    }
    std.mem.sort(Match, matches, {}, matchLessThan);
    const parameter_data = try std.Io.Dir.cwd().readFileAlloc(io, "input/params.txt", r.allocator, .unlimited);
    const parameter_lines = r.lines(parameter_data);
    var fields: [20][]const []const u8 = undefined;
    for (parameter_lines, 0..) |line, i| fields[i] = r.split(line, ' ');
    const settings: Settings = .{
        .win_points = r.number(fields[0][1]), .draw_points = r.number(fields[1][1]), .form_length = r.u(r.number(fields[2][1])),
        .close_margin = r.number(fields[3][1]), .exponent = std.fmt.parseFloat(f64, fields[4][1]) catch unreachable,
        .elo_k = r.number(fields[5][1]), .elo_home = r.number(fields[6][1]), .elo_initial = r.number(fields[7][1]),
        .grid_k = integers(fields[8]), .grid_home = integers(fields[9]), .bt_iterations = r.u(r.number(fields[10][1])),
        .od_iterations = r.u(r.number(fields[11][1])), .link_iterations = r.u(r.number(fields[12][1])), .holdout_round = r.u(r.number(fields[13][1])),
        .upsets = r.u(r.number(fields[14][1])), .calibration_bins = r.u(r.number(fields[15][1])), .simulations = r.u(r.number(fields[16][1])),
        .seed = r.number(fields[17][1]), .top_positions = r.u(r.number(fields[18][1])), .bottom_positions = r.u(r.number(fields[19][1])),
    };
    return .{ .teams = teams, .matches = matches, .rounds = matches[matches.len - 1].round, .settings = settings };
}
