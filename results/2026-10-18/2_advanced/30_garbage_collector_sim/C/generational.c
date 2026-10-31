#include "collector.h"
void barrier(Heap *heap, int target, int value) {
    if (heap->objects[target - 1].address < heap->collector.young)
        return;
    ++heap->barriers;
    if (value && heap->objects[value - 1].address < heap->collector.young && !heap->remembered[target - 1]) {
        heap->remembered[target - 1] = true;
        ++heap->remembers;
    }
}
static bool evacuate(Heap *heap, Collection *record, int id, bool *evacuation, int *top, bool tenure,
                     bool major, int *queue, int *end) {
    if (!id || !evacuation[id - 1])
        return true;
    evacuation[id - 1] = false;
    Object *object = &heap->objects[id - 1];
    ++object->age;
    ++object->moves;
    if (tenure || object->age >= heap->collector.promotion_age) {
        int address = first_fit(heap, object_size(*object), heap->collector.young, heap->size);
        if (address < 0)
            return false;
        object->address = address;
        add_object(&record->promoted, object_size(*object));
    } else {
        object->address = *top;
        *top += object_size(*object);
    }
    add_object(&record->moved, object_size(*object));
    if (!major)
        add_object(&record->live, object_size(*object));
    queue[(*end)++] = id;
    return true;
}
bool collect_generational(Heap *heap, Collection *record) {
    bool major = !strcmp(record->kind, "major") || !strcmp(record->kind, "full"),
         tenure = !strcmp(record->kind, "tenure") || !strcmp(record->kind, "full");
    if (major) {
        marking(heap, record);
        sweeping(heap, record, true);
    }
    bool evacuation[5000] = {0};
    for (int i = 0; i < heap->count; ++i)
        evacuation[i] = heap->objects[i].present && heap->objects[i].address < heap->collector.young;
    int destination = heap->collector.young / 2 - heap->base, top = destination, queue[5000], end = 0;
    record->work += heap->root_count;
    for (int i = 0; i < heap->root_count; ++i)
        if (!evacuate(heap, record, heap->roots[i], evacuation, &top, tenure, major, queue, &end))
            return false;
    Indices remembered = address_order(heap);
    for (int i = 0; i < remembered.count; ++i) {
        int id = remembered.values[i];
        if (!heap->remembered[id - 1])
            continue;
        Object *object = &heap->objects[id - 1];
        record->work += 1 + object->p;
        for (int f = 0; f < object->p; ++f)
            if (!evacuate(heap, record, object->fields[f], evacuation, &top, tenure, major, queue, &end))
                return false;
    }
    for (int front = 0; front < end; ++front) {
        Object *object = &heap->objects[queue[front] - 1];
        record->work += object_size(*object) + object->p;
        for (int f = 0; f < object->p; ++f)
            if (!evacuate(heap, record, object->fields[f], evacuation, &top, tenure, major, queue, &end))
                return false;
    }
    for (int i = 0; i < heap->count; ++i)
        if (evacuation[i]) {
            heap->objects[i].present = false;
            add_object(&record->freed, object_size(heap->objects[i]));
        }
    heap->base = destination;
    heap->top = top;
    memset(heap->remembered, 0, sizeof heap->remembered);
    for (int i = 0; i < heap->count; ++i) {
        Object *object = &heap->objects[i];
        if (!object->present || object->address < heap->collector.young)
            continue;
        for (int f = 0; f < object->p; ++f)
            if (object->fields[f] && heap->objects[object->fields[f] - 1].address < heap->collector.young) {
                heap->remembered[i] = true;
                break;
            }
    }
    return true;
}
