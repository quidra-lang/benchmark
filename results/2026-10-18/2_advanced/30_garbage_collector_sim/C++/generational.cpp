#include "collector.hpp"
void barrier(Heap &heap, int target, int value) {
    if (heap.object(target).address < heap.collector.young)
        return;
    ++heap.barriers;
    if (value && heap.object(value).address < heap.collector.young && heap.remembered.insert(target).second)
        ++heap.remembers;
}
bool collect_generational(Heap &heap, Collection &record) {
    const bool major = record.kind == "major" || record.kind == "full",
               tenure = record.kind == "tenure" || record.kind == "full";
    if (major) {
        marking(heap, record);
        sweeping(heap, record, true);
    }
    std::set<int> evacuation;
    for (const Object &object : heap.objects)
        if (object.present && object.address < heap.collector.young)
            evacuation.insert(object.id);
    const int destination = heap.collector.young / 2 - heap.base;
    int top = destination;
    std::vector<int> queue;
    auto evacuate = [&](int id) {
        if (!id || !evacuation.erase(id))
            return true;
        Object &object = heap.object(id);
        ++object.age;
        ++object.moves;
        if (tenure || object.age >= heap.collector.promotion_age) {
            const int address = first_fit(heap, object.size(), heap.collector.young, heap.size);
            if (address < 0)
                return false;
            object.address = address;
            record.promoted.add(object.size());
        } else {
            object.address = top;
            top += object.size();
        }
        record.moved.add(object.size());
        if (!major)
            record.live.add(object.size());
        queue.push_back(id);
        return true;
    };
    record.work += heap.roots.size();
    for (int root : heap.roots)
        if (!evacuate(root))
            return false;
    std::vector<int> remembered(heap.remembered.begin(), heap.remembered.end());
    std::sort(remembered.begin(), remembered.end(),
              [&](int a, int b) { return heap.object(a).address < heap.object(b).address; });
    for (int id : remembered) {
        const Object &object = heap.object(id);
        record.work += 1 + object.p;
        for (int value : object.fields)
            if (!evacuate(value))
                return false;
    }
    for (std::size_t front = 0; front < queue.size(); ++front) {
        const Object &object = heap.object(queue[front]);
        record.work += object.size() + object.p;
        for (int value : object.fields)
            if (!evacuate(value))
                return false;
    }
    for (int id : evacuation) {
        Object &object = heap.object(id);
        object.present = false;
        record.freed.add(object.size());
    }
    heap.base = destination;
    heap.top = top;
    heap.remembered.clear();
    for (const Object &object : heap.objects)
        if (object.present && object.address >= heap.collector.young)
            for (int value : object.fields)
                if (value && heap.object(value).address < heap.collector.young) {
                    heap.remembered.insert(object.id);
                    break;
                }
    return true;
}
