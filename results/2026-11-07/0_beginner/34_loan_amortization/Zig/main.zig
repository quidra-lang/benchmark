const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    var balance: u32 = 1000000;
    var month: u32 = 0;
    var total_interest: u32 = 0;
    var total_paid: u32 = 0;
    while (balance > 0) {
        month += 1;
        const interest = balance / 100;
        const payment = @min(50000, balance + interest);
        const principal = payment - interest;
        balance -= principal;
        total_interest += interest;
        total_paid += payment;
        try out.print("month {d}: interest={d} principal={d} balance={d}\n", .{ month, interest, principal, balance });
    }
    try out.print("total interest: {d}\ntotal paid: {d}\n", .{ total_interest, total_paid });
    try out.flush();
}
