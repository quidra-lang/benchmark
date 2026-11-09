const std = @import("std");
const h = @import("heap.zig");
fn copy(heap: *h.Heap, record: *h.Collection, copied: []bool, queue: *std.ArrayList(usize), id: usize) void {
    if (id == 0 or copied[id - 1]) return;
    const object = heap.object(id);
    copied[id - 1] = true;
    object.address = heap.top;
    heap.top += object.size();
    object.moves += 1;
    record.live.add(object.size());
    record.moved.add(object.size());
    h.append(usize, queue, id);
}
pub fn collect(heap: *h.Heap, record: *h.Collection) void {
    heap.base = heap.size / 2 - heap.base;
    heap.top = heap.base;
    const copied = h.alloc(bool, heap.objects.items.len);
    @memset(copied, false);
    var queue: std.ArrayList(usize) = .empty;
    record.work += h.n(heap.roots.items.len);
    for (heap.roots.items) |root| copy(heap, record, copied, &queue, root);
    var front: usize = 0;
    while (front < queue.items.len) : (front += 1) {
        const object = heap.get(queue.items[front]);
        record.work += h.n(object.size() + object.p);
        for (object.fields) |value| copy(heap, record, copied, &queue, value);
    }
    for (heap.objects.items, copied) |*object, done| if (object.present and !done) {
        object.present = false;
        record.freed.add(object.size());
    };
}
