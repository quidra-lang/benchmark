const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const names = [_][]const u8{ "milk", "notebook", "bread", "apple", "detergent", "eggs" };
    const prices = [_]u32{ 198, 165, 248, 128, 437, 268 };
    const quantities = [_]u32{ 2, 3, 1, 4, 1, 1 };
    const food = [_]bool{ true, false, true, true, false, true };
    var totals = [_]u32{ 0, 0 };
    for (names, prices, quantities, food) |name, price, quantity, is_food| {
        const subtotal = price * quantity;
        totals[if (is_food) @as(usize, 0) else 1] += subtotal;
        try out.print("{s} {d} x {d} = {d}\n", .{ name, price, quantity, subtotal });
    }
    const food_tax = totals[0] * 8 / 100;
    const general_tax = totals[1] * 10 / 100;
    try out.print("food: {d} yen, tax {d} yen\ngeneral: {d} yen, tax {d} yen\ntotal: {d} yen\n", .{
        totals[0],
        food_tax,
        totals[1],
        general_tax,
        totals[0] + totals[1] + food_tax + general_tax,
    });
    try out.flush();
}
