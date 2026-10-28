#include "collector.h"
static void push_mark(Heap *heap, Collection *record, int id, int *stack, int *depth) {
    if (!id || heap->objects[id - 1].marked)
        return;
    heap->objects[id - 1].marked = true;
    stack[(*depth)++] = id;
    if (*depth > record->stack)
        record->stack = *depth;
}
void marking(Heap *heap, Collection *record) {
    for (int i = 0; i < heap->count; ++i)
        heap->objects[i].marked = false;
    record->work += heap->root_count;
    int stack[5000], depth = 0;
    for (int i = 0; i < heap->root_count; ++i) {
        push_mark(heap, record, heap->roots[i], stack, &depth);
        while (depth) {
            Object *object = &heap->objects[stack[--depth] - 1];
            add_object(&record->live, object_size(*object));
            record->work += 1 + object->p;
            for (int f = 0; f < object->p; ++f)
                push_mark(heap, record, object->fields[f], stack, &depth);
        }
    }
}
void sweeping(Heap *heap, Collection *record, bool old_only) {
    for (int i = 0; i < heap->count; ++i) {
        Object *object = heap->objects + i;
        if (!object->present || (old_only && object->address < heap->collector.young))
            continue;
        ++record->work;
        if (!object->marked) {
            add_object(&record->freed, object_size(*object));
            object->present = false;
            heap->remembered[i] = false;
        }
    }
}
void collect_sweep(Heap *heap, Collection *record) {
    marking(heap, record);
    sweeping(heap, record, false);
}
void collect_compact(Heap *heap, Collection *record) {
    marking(heap, record);
    Indices ids = address_order(heap);
    record->work += ids.count + heap->root_count;
    int destination = 0;
    for (int i = 0; i < ids.count; ++i) {
        Object *object = &heap->objects[ids.values[i] - 1];
        if (!object->marked) {
            object->present = false;
            add_object(&record->freed, object_size(*object));
            continue;
        }
        record->work += object->p;
        if (object->address != destination) {
            add_object(&record->moved, object_size(*object));
            record->work += object_size(*object);
            object->address = destination;
            ++object->moves;
        }
        destination += object_size(*object);
    }
    heap->top = destination;
}
