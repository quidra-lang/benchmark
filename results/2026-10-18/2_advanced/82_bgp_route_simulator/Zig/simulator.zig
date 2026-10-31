const std = @import("std");
const t = @import("topology.zig");
const d = @import("decision.zig");
pub var work_allocator: std.mem.Allocator = undefined;
pub const Message = struct { serial: i64, sender: usize, receiver: usize, link: usize, prefix: usize,
     content: ?*const d.Attribute, arrival: i64 };
fn less(_: void, a: Message, b: Message) bool {
    if (a.arrival != b.arrival) return a.arrival < b.arrival;
    if (a.receiver != b.receiver) return a.receiver < b.receiver;
    if (a.sender != b.sender) return a.sender < b.sender;
    return a.serial < b.serial;
}
pub const MessageQueue = struct {
    heap: std.ArrayList(Message) = .empty,
    serial: i64 = 0,
    fn push(self: *MessageQueue, message: Message) void {
        t.append(Message, &self.heap, message);
        var index = self.heap.items.len - 1;
        while (index > 0) {
            const parent = (index - 1) / 2;
            if (!less({}, self.heap.items[index], self.heap.items[parent])) break;
            std.mem.swap(Message, &self.heap.items[index], &self.heap.items[parent]);
            index = parent;
        }
    }
    pub fn send(self: *MessageQueue, time: i64, sender: usize, receiver: usize, index: usize,
         prefix: usize, content: ?*const d.Attribute, network: *const t.Topology) Message {
        self.serial += 1;
        const message: Message = .{ .serial = self.serial, .sender = sender, .receiver = receiver,
             .link = index, .prefix = prefix, .content = content, .arrival = time + network.links[index].delay };
        self.push(message);
        return message;
    }
    pub fn nextTime(self: *const MessageQueue) ?i64 {
        return if (self.heap.items.len == 0) null else self.heap.items[0].arrival;
    }
    pub fn take(self: *MessageQueue) Message {
        const result = self.heap.items[0];
        const last = self.heap.pop().?;
        if (self.heap.items.len == 0) return result;
        self.heap.items[0] = last;
        var index: usize = 0;
        while (2 * index + 1 < self.heap.items.len) {
            var child = 2 * index + 1;
            if (child + 1 < self.heap.items.len and less({}, self.heap.items[child + 1], self.heap.items[child])) child += 1;
            if (!less({}, self.heap.items[child], self.heap.items[index])) break;
            std.mem.swap(Message, &self.heap.items[child], &self.heap.items[index]);
            index = child;
        }
        return result;
    }
    pub fn ordered(self: *const MessageQueue) []Message {
        const out = work_allocator.dupe(Message, self.heap.items) catch @panic("allocation failed");
        std.mem.sort(Message, out, {}, less);
        return out;
    }
    pub fn removeLink(self: *MessageQueue, index: usize) []Message {
        const ordered_messages = self.ordered();
        defer work_allocator.free(ordered_messages);
        var removed: std.ArrayList(Message) = .empty;
        self.heap.clearRetainingCapacity();
        for (ordered_messages) |message| if (message.link == index) {
            removed.append(work_allocator, message) catch @panic("allocation failed");
        } else self.push(message);
        return removed.toOwnedSlice(work_allocator) catch @panic("allocation failed");
    }
};
pub const Event = struct { time: i64, text: []const u8, fields: t.Names, kind: []const u8 };
pub fn readEvents(io: std.Io) ![]const Event {
    var out: std.ArrayList(Event) = .empty;
    t.append(Event, &out, .{ .time = 0, .text = "INITIAL", .fields = &.{"INITIAL"}, .kind = "INITIAL" });
    for (try t.readLines(io, "input/events.txt")) |line| {
        const separator = std.mem.indexOfScalar(u8, line, ' ') orelse unreachable;
        const text = line[separator + 1 ..];
        const fields = t.words(text);
        const kind = if (t.eq(fields[0], "LINK") or t.eq(fields[0], "POLICY")) t.fmt("{s}_{s}",
             .{ fields[0], fields[1] }) else fields[0];
        t.append(Event, &out, .{ .time = t.number(line[0..separator]), .text = text, .fields = fields, .kind = kind });
    }
    return out.items;
}
pub const Trace = struct { source: usize, address: []const u8, value: u64 };
pub const Params = struct { defaults: [3]i64, stepcap: i64, traces: []const Trace };
pub fn readParams(io: std.Io, network: *const t.Topology) !Params {
    const lines = try t.readLines(io, "input/params.txt");
    const defaults = t.words(lines[0]);
    var traces: std.ArrayList(Trace) = .empty;
    for (lines[2..]) |line| {
        const f = t.words(line);
        t.append(Trace, &traces, .{ .source = network.asIndex(t.number(f[1])), .address = f[2],
             .value = t.addressValue(f[2]) });
    }
    return .{ .defaults = .{ t.number(defaults[1]), t.number(defaults[2]), t.number(defaults[3]) },
         .stepcap = t.number(t.words(lines[1])[1]), .traces = traces.items };
}
