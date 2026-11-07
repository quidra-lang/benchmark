const master = @import("items.zig");
fn multiple(amount: i64, factor: i64) i64 { return @divFloor(amount + factor - 1, factor) * factor; }
pub fn quantity(item: master.Item, week: usize, projected: i64, receipts: []const i64, gross: []const i64, horizon: usize) i64 {
    const net = item.safety - projected;
    switch (item.rule) {
        .LFL => return net,
        .FOQ => return multiple(net, item.first),
        .MIN => return multiple(@max(net, item.first), item.second),
        .POQ => {
            var result = net;
            var balance = projected;
            const last = @min(week + @as(usize, @intCast(item.first)) - 1, horizon);
            for (week + 1..last + 1) |later| { balance += receipts[later] - gross[later]; result = @max(result, item.safety - balance); }
            return result;
        },
    }
}
