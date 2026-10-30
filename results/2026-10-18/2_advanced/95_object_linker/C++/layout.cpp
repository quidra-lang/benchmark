#include "linker.hpp"
int64_t aligned(int64_t value, int64_t alignment) {
    return (value + alignment - 1) / alignment * alignment;
}
OutputSection *output_for(Section *section, const std::vector<OutputSection *> &outputs) {
    for (OutputSection *output : outputs)
        if (belongs(section->name, output->name))
            return output;
    return nullptr;
}
void place_segment(Segment &segment) {
    int64_t cursor = segment.base;
    segment.file_size = 0;
    for (const auto &pointer : segment.sections) {
        OutputSection &output = *pointer;
        int64_t alignment = 1;
        for (const auto &component : output.components)
            alignment = std::max(alignment, component->alignment);
        cursor = aligned(cursor, alignment);
        output.address = cursor;
        output.alignment = alignment;
        for (const auto &component : output.components) {
            cursor = aligned(cursor, component->alignment);
            component->address = cursor;
            if (component->kind == "section")
                component->section->address = cursor;
            else if (component->kind == "common")
                component->common->address = cursor;
            cursor += component->size;
        }
        output.size = cursor - output.address;
        if (!belongs(output.name, ".bss"))
            segment.file_size = cursor - segment.base;
    }
    segment.memory_size = cursor - segment.base;
}
