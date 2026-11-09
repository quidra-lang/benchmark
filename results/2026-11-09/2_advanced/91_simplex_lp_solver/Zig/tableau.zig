const r = @import("rational.zig");
pub const Tableau = struct {
    a: [][]r.Q, beta: []r.Q, basis: []usize, rows: []const []const u8, columns: []const []const u8,
    pub fn basic(self: Tableau, k: usize) bool { for (self.basis) |b| if (b == k) return true; return false; }
    pub fn reduced(self: Tableau, costs: []const r.Q) []r.Q {
        const out = r.copy(r.Q, costs);
        for (self.a, self.basis) |row, b| for (row, 0..) |v, k| { out[k] = out[k].minus(costs[b].mul(v)); };
        return out;
    }
    pub fn value(self: Tableau, costs: []const r.Q) r.Q { var z: r.Q = .{}; for (self.beta, self.basis) |v, b| z = z.plus(v.mul(costs[b])); return z; }
    pub fn pivot(self: *Tableau, p: usize, q: usize) void {
        const divisor = self.a[p][q]; for (self.a[p]) |*v| v.* = v.div(divisor); self.beta[p] = self.beta[p].div(divisor);
        for (self.a, 0..) |row, i| { if (i == p) continue; const factor = row[q]; for (row, 0..) |*v, k| v.* = v.minus(factor.mul(self.a[p][k])); self.beta[i] = self.beta[i].minus(factor.mul(self.beta[p])); }
        self.basis[p] = q;
    }
    pub fn solution(self: Tableau) []r.Q { const x = r.zero(self.columns.len); for (self.beta, self.basis) |v, b| x[b] = v; return x; }
    pub fn display(self: Tableau, log: *r.Text, heading: []const u8, costs: []const r.Q, offset: r.Q, sign: r.Q) void {
        log.line("TABLEAU {s}", .{heading}); log.put("COLUMNS", .{}); for (self.columns) |n| log.put(" {s}", .{n}); log.put("\n", .{});
        for (self.a, 0..) |row, i| { log.put("ROW {s} {s}", .{self.rows[i], self.columns[self.basis[i]]}); for (row) |v| log.put(" {s}", .{v.str()}); log.line(" | {s}", .{self.beta[i].str()}); }
        log.put("COST", .{}); for (self.reduced(costs)) |v| log.put(" {s}", .{v.str()}); log.line(" | {s}", .{offset.plus(sign.mul(self.value(costs))).str()});
    }
};
