const std = @import("std");

const Entry = struct {
    name: []const u8,
    value: u32
};

fn add(entries: *[12]Entry, len: *usize, name: []const u8, value: u32) void {
    for (entries[0..len.*]) | * e| {
        if (std.mem.eql(u8, e.name, name)) {
            e.value += value;
            return;
        }
    }
    entries[len.*] = .{ .name = name, .value = value };
    len.* += 1;
}

fn nameLess(_: void, a: Entry, b: Entry) bool {
    return std.mem.order(u8, a.name, b.name) == .lt;
}

fn salesLess(_: void, a: Entry, b: Entry) bool {
    return if (a.value != b.value) a.value > b.value else nameLess({}, a, b);
}

pub fn main(init: std.process.Init) !void {
    var output_buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &writer.interface;
    const lines = [_][]const u8{
        "date,region,product,quantity,unit_price",
        "2026-04-01,north,notebook,10,200",
        "2026-04-01,east,marker,6,150",
        "2026-04-01,south,eraser,25,80",
        "2026-04-02,west,stapler,4,600",
        "2026-04-02,north,marker,8,150",
        "2026-04-02,east,notebook,9,200",
        "2026-04-03,south,stapler,3,600",
        "2026-04-03,west,eraser,15,80",
        "2026-04-03,north,eraser,20,80",
        "2026-04-04,east,stapler,5,600",
        "2026-04-04,south,notebook,6,200",
        "2026-04-04,west,marker,8,150"
    };
    var regions: [12]Entry = undefined;
    var products: [12]Entry = undefined;
    var dates: [12]Entry = undefined;
    var rlen: usize = 0;
    var plen: usize = 0;
    var dlen: usize = 0;
    var total: u32 = 0;
    for (lines[1..]) |line| {
        var fields = std.mem.splitScalar(u8, line, ',');
        const date = fields.next().?;
        const region = fields.next().?;
        const product = fields.next().?;
        const quantity = try std.fmt.parseInt(u32, fields.next().?, 10);
        const price = try std.fmt.parseInt(u32, fields.next().?, 10);
        const sales = quantity * price;
        total += sales;
        add(&regions, &rlen, region, sales);
        add(&products, &plen, product, quantity);
        add(&dates, &dlen, date, sales);
    }
    std.mem.sort(Entry, regions[0..rlen], {}, salesLess);
    std.mem.sort(Entry, products[0..plen], {}, nameLess);
    std.mem.sort(Entry, dates[0..dlen], {}, nameLess);
    try out.print("total: {d}\n", .{ total });
    for (regions[0..rlen]) |e|
        try out.print("{s}: {d}\n", .{ e.name, e.value });
    for (products[0..plen]) |e|
        try out.print("{s}: {d}\n", .{ e.name, e.value });
    var best = dates[0];
    for (dates[1..dlen]) |e| {
        if (e.value > best.value)
            best = e;
    }
    try out.print("best day: {s} ({d})\n", .{ best.name, best.value });
    try out.flush();
}
