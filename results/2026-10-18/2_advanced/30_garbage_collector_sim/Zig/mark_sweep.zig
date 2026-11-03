const std = @import("std");
const h = @import("heap.zig");
fn push(heap: *h.Heap, record: *h.Collection, stack: *std.ArrayList(usize), id: usize) void {
    if (id == 0 or heap.object(id).marked) return;
    heap.object(id).marked = true;
    h.append(usize, stack, id);
    record.stack = @max(record.stack, stack.items.len);
}
pub fn mark(heap: *h.Heap, record: *h.Collection) void {
    for (heap.objects.items) |*object| object.marked = false;
    record.work += h.n(heap.roots.items.len);
    var stack: std.ArrayList(usize) = .empty;
    for (heap.roots.items) |root| {
        push(heap, record, &stack, root);
        while (stack.items.len > 0) {
            const id = stack.items[stack.items.len - 1];
            stack.items.len -= 1;
            const object = heap.get(id);
            record.live.add(object.size());
            record.work += h.n(1 + object.p);
            for (object.fields) |value| push(heap, record, &stack, value);
        }
    }
}
pub fn sweep(heap: *h.Heap, record: *h.Collection, old_only: bool) void {
    for (heap.objects.items) |*object| if (object.present and (!old_only or object.address >= heap.collector.young)) {
        record.work += 1;
        if (!object.marked) {
            record.freed.add(object.size());
            object.present = false;
            heap.remembered[object.id - 1] = false;
        }
    };
}
pub fn collectSweep(heap: *h.Heap, record: *h.Collection) void {
    mark(heap, record);
    sweep(heap, record, false);
}
pub fn collectCompact(heap: *h.Heap, record: *h.Collection) void {
    mark(heap, record);
    const ids = h.addressOrder(heap);
    record.work += h.n(ids.len + heap.roots.items.len);
    var destination: usize = 0;
    for (ids) |id| {
        const object = heap.object(id);
        if (!object.marked) {
            object.present = false;
            record.freed.add(object.size());
            continue;
        }
        record.work += h.n(object.p);
        if (object.address != destination) {
            record.moved.add(object.size());
            record.work += h.n(object.size());
            object.address = destination;
            object.moves += 1;
        }
        destination += object.size();
    }
    heap.top = destination;
}
