const D = @import("transactions.zig");
const K = @import("kmeans.zig");
pub const names = [_][]const u8{ "recency", "frequency", "monetary", "basket", "categories", "tenure" };
pub const Customer = struct { file_number: usize, id: []const u8, spend: i64, orders: []const *const D.Order, category_spend: []i64, category_present: []bool, raw: K.Point, transformed: K.Point, point: K.Point = undefined };
pub const Scaling = struct { mean: K.Point, sd: K.Point, raw_mean: K.Point, raw_sd: K.Point };
pub const Moments = struct { mean: f64, sd: f64 };
pub fn eligibleCustomers(data: *const D.Transactions, orders: []const D.Order, day: i64) []Customer {
    var counts = [_]usize{0} ** 400;
    var count: usize = 0;
    for (orders) |order| { if (order.net > 0) counts[order.customer] += 1; }
    for (counts[0..data.ids.len]) |size| { if (size > 0) count += 1; }
    const result = D.alloc(Customer, count);
    var position: usize = 0;
    for (data.ids, 0..) |id, file_number| {
        if (counts[file_number] == 0) continue;
        const purchases = D.alloc(*const D.Order, counts[file_number]);
        const amounts = D.alloc(i64, data.categories.len);
        const present = D.alloc(bool, data.categories.len);
        @memset(amounts, 0);
        @memset(present, false);
        var first = day;
        var last: i64 = 0;
        var spend: i64 = 0;
        var order_number: usize = 0;
        for (orders) |*order| {
            if (order.customer != file_number or order.net <= 0) continue;
            purchases[order_number] = order;
            order_number += 1;
            spend += order.net;
            first = @min(first, order.day);
            last = @max(last, order.day);
            for (order.rows) |row| { amounts[row.category] += row.amount; present[row.category] = true; }
        }
        var categories: usize = 0;
        for (amounts) |value| { if (value > 0) categories += 1; }
        const monetary = D.real(spend) / 100;
        const raw: K.Point = .{ D.real(day - last), D.real(purchases.len), monetary, monetary / D.real(purchases.len), D.real(categories), D.real(day - first) };
        var transformed = raw;
        for (1..4) |f| transformed[f] = @sqrt(raw[f]);
        result[position] = .{ .file_number = file_number, .id = id, .spend = spend, .orders = purchases, .category_spend = amounts, .category_present = present, .raw = raw, .transformed = transformed };
        position += 1;
    }
    return result;
}
pub fn orderedSum(values: []const f64) f64 { var result: f64 = 0; for (values) |value| result += value; return result; }
pub fn meanSd(values: []const f64) Moments {
    const mean = orderedSum(values) / D.real(values.len);
    var squares: f64 = 0;
    for (values) |value| { const difference = value - mean; squares += difference * difference; }
    return .{ .mean = mean, .sd = if (values.len == 1) 0 else @sqrt(squares / D.real(values.len - 1)) };
}
pub fn fitScaling(customers: []const Customer) Scaling {
    var result: Scaling = undefined;
    for (0..6) |f| {
        var raw: [400]f64 = undefined;
        var transformed: [400]f64 = undefined;
        for (customers, 0..) |customer, i| { raw[i] = customer.raw[f]; transformed[i] = customer.transformed[f]; }
        const first = meanSd(raw[0..customers.len]);
        const second = meanSd(transformed[0..customers.len]);
        result.raw_mean[f] = first.mean;
        result.raw_sd[f] = first.sd;
        result.mean[f] = second.mean;
        result.sd[f] = second.sd;
    }
    return result;
}
pub fn standardize(customers: []Customer, scaling: Scaling) void {
    for (customers) |*customer| { for (0..6) |f| customer.point[f] = if (scaling.sd[f] == 0) 0 else (customer.transformed[f] - scaling.mean[f]) / scaling.sd[f]; }
}
pub fn correlation(points: K.Points, first: usize, second: usize) f64 {
    var total: f64 = 0;
    for (points.values) |point| total += point[first] * point[second];
    return total / D.real(points.values.len - 1);
}
