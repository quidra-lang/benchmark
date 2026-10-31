#include "linker.h"
int64_t aligned(int64_t value, int64_t alignment) {
    return (value + alignment - 1) / alignment * alignment;
}
OutputSection *output_for(Section *section, OutputList outputs) {
    for (int i = 0; i < outputs.count; ++i)
        if (belongs(section->name, outputs.items[i]->name))
            return outputs.items[i];
    return NULL;
}
void place_segment(Segment *segment) {
    int64_t cursor = segment->base;
    segment->file_size = 0;
    for (int i = 0; i < segment->sections.count; ++i) {
        OutputSection *output = segment->sections.items[i];
        int64_t alignment = 1;
        for (int j = 0; j < output->components.count; ++j)
            if (output->components.items[j]->alignment > alignment)
                alignment = output->components.items[j]->alignment;
        cursor = aligned(cursor, alignment);
        output->address = cursor;
        output->alignment = alignment;
        for (int j = 0; j < output->components.count; ++j) {
            Component *component = output->components.items[j];
            cursor = aligned(cursor, component->alignment);
            component->address = cursor;
            if (equal(component->kind, "section"))
                component->section->address = cursor;
            else if (equal(component->kind, "common"))
                component->common->address = cursor;
            cursor += component->size;
        }
        output->size = cursor - output->address;
        if (!belongs(output->name, ".bss"))
            segment->file_size = cursor - segment->base;
    }
    segment->memory_size = cursor - segment->base;
}
