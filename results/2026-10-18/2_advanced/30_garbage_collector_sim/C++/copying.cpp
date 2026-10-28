#include "collector.hpp"
void collect_copy(Heap &heap, Collection &record) {
    heap.base = heap.size / 2 - heap.base;
    heap.top = heap.base;
    std::set<int> copied;
    std::vector<int> queue;
    auto copy = [&](int id) {
        if (!id || copied.count(id))
            return;
        Object &object = heap.object(id);
        copied.insert(id);
        object.address = heap.top;
        heap.top += object.size();
        ++object.moves;
        record.live.add(object.size());
        record.moved.add(object.size());
        queue.push_back(id);
    };
    record.work += heap.roots.size();
    for (int root : heap.roots)
        copy(root);
    for (std::size_t front = 0; front < queue.size(); ++front) {
        const Object &object = heap.object(queue[front]);
        record.work += object.size() + object.p;
        for (int reference : object.fields)
            copy(reference);
    }
    for (Object &object : heap.objects)
        if (object.present && !copied.count(object.id)) {
            object.present = false;
            record.freed.add(object.size());
        }
}
