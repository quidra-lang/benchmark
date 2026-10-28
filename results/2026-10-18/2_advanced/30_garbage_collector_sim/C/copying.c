#include "collector.h"
static void copy_object(Heap *heap, Collection *record, int id, bool *copied, int *queue, int *end) {
    if (!id || copied[id - 1])
        return;
    Object *object = &heap->objects[id - 1];
    copied[id - 1] = true;
    object->address = heap->top;
    heap->top += object_size(*object);
    ++object->moves;
    add_object(&record->live, object_size(*object));
    add_object(&record->moved, object_size(*object));
    queue[(*end)++] = id;
}
void collect_copy(Heap *heap, Collection *record) {
    heap->base = heap->size / 2 - heap->base;
    heap->top = heap->base;
    bool copied[5000] = {0};
    int queue[5000], end = 0;
    record->work += heap->root_count;
    for (int i = 0; i < heap->root_count; ++i)
        copy_object(heap, record, heap->roots[i], copied, queue, &end);
    for (int front = 0; front < end; ++front) {
        Object *object = &heap->objects[queue[front] - 1];
        record->work += object_size(*object) + object->p;
        for (int f = 0; f < object->p; ++f)
            copy_object(heap, record, object->fields[f], copied, queue, &end);
    }
    for (int i = 0; i < heap->count; ++i)
        if (heap->objects[i].present && !copied[i]) {
            heap->objects[i].present = false;
            add_object(&record->freed, object_size(heap->objects[i]));
        }
}
