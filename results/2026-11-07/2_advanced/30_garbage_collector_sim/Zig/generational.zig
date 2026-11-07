const std = @import("std");
const h = @import("heap.zig");
const mark = @import("mark_sweep.zig");
pub fn barrier(heap: *h.Heap, target: usize, value: usize) void {
    if (heap.get(target).address < heap.collector.young) return;
    heap.barriers += 1;
    if (value != 0 and heap.get(value).address < heap.collector.young and !heap.remembered[target - 1]) {
        heap.remembered[target - 1] = true;
        heap.remembers += 1;
    }
}
const Evacuation = struct {
    heap: *h.Heap,
    record: *h.Collection,
    pending: []bool,
    top: usize,
    tenure: bool,
    major: bool,
    queue: std.ArrayList(usize) = .empty,
    fn evacuate(self: *Evacuation, id: usize) bool {
        if (id == 0 or !self.pending[id - 1]) return true;
        self.pending[id - 1] = false;
        const object = self.heap.object(id);
        object.age += 1;
        object.moves += 1;
        if (self.tenure or object.age >= self.heap.collector.promotion_age) {
            const address = h.firstFit(self.heap, object.size(), self.heap.collector.young, self.heap.size) orelse return false;
            object.address = address;
            self.record.promoted.add(object.size());
        } else {
            object.address = self.top;
            self.top += object.size();
        }
        self.record.moved.add(object.size());
        if (!self.major) self.record.live.add(object.size());
        h.append(usize, &self.queue, id);
        return true;
    }
};
pub fn collect(heap: *h.Heap, record: *h.Collection) bool {
    const major = h.eq(record.kind, "major") or h.eq(record.kind, "full");
    const tenure = h.eq(record.kind, "tenure") or h.eq(record.kind, "full");
    if (major) {
        mark.mark(heap, record);
        mark.sweep(heap, record, true);
    }
    const pending = h.alloc(bool, heap.objects.items.len);
    for (heap.objects.items, pending) |object, *value| value.* = object.present and object.address < heap.collector.young;
    const destination = heap.collector.young / 2 - heap.base;
    var state: Evacuation = .{ .heap = heap, .record = record, .pending = pending, .top = destination,
         .major = major, .tenure = tenure };
    record.work += h.n(heap.roots.items.len);
    for (heap.roots.items) |root| if (!state.evacuate(root)) return false;
    for (h.addressOrder(heap)) |id| if (heap.remembered[id - 1]) {
        const object = heap.get(id);
        record.work += h.n(1 + object.p);
        for (object.fields) |value| if (!state.evacuate(value)) return false;
    };
    var front: usize = 0;
    while (front < state.queue.items.len) : (front += 1) {
        const object = heap.get(state.queue.items[front]);
        record.work += h.n(object.size() + object.p);
        for (object.fields) |value| if (!state.evacuate(value)) return false;
    }
    for (heap.objects.items, pending) |*object, remains| if (remains) {
        object.present = false;
        record.freed.add(object.size());
    };
    heap.base = destination;
    heap.top = state.top;
    @memset(&heap.remembered, false);
    for (heap.objects.items) |object| if (object.present and object.address >= heap.collector.young) {
        for (object.fields) |value| if (value != 0 and heap.get(value).address < heap.collector.young) {
            heap.remembered[object.id - 1] = true;
            break;
        };
    };
    return true;
}
