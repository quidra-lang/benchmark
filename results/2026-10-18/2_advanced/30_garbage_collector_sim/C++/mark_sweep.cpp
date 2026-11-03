#include "collector.hpp"
void marking(Heap &heap, Collection &record) {
    for (Object &object : heap.objects)
        object.marked = false;
    record.work += heap.roots.size();
    std::vector<int> stack;
    auto push = [&](int id) {
        if (!id || heap.object(id).marked)
            return;
        heap.object(id).marked = true;
        stack.push_back(id);
        record.stack = std::max(record.stack, Integer(stack.size()));
    };
    for (int root : heap.roots) {
        push(root);
        while (!stack.empty()) {
            const int id = stack.back();
            stack.pop_back();
            const Object &object = heap.object(id);
            record.live.add(object.size());
            record.work += 1 + object.p;
            for (int reference : object.fields)
                push(reference);
        }
    }
}
void sweeping(Heap &heap, Collection &record, bool old_only) {
    for (Object &object : heap.objects)
        if (object.present && (!old_only || object.address >= heap.collector.young)) {
            ++record.work;
            if (!object.marked) {
                record.freed.add(object.size());
                object.present = false;
                heap.remembered.erase(object.id);
            }
        }
}
void collect_sweep(Heap &heap, Collection &record) {
    marking(heap, record);
    sweeping(heap, record);
}
void collect_compact(Heap &heap, Collection &record) {
    marking(heap, record);
    const std::vector<int> ids = address_order(heap);
    record.work += Integer(ids.size() + heap.roots.size());
    int destination = 0;
    for (int id : ids) {
        Object &object = heap.object(id);
        if (!object.marked) {
            object.present = false;
            record.freed.add(object.size());
            continue;
        }
        record.work += object.p;
        if (object.address != destination) {
            record.moved.add(object.size());
            record.work += object.size();
            object.address = destination;
            ++object.moves;
        }
        destination += object.size();
    }
    heap.top = destination;
}
