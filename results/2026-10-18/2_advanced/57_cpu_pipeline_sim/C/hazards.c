#include "simulator.h"
bool control(Instruction instruction) {
    return instruction.kind == BRANCH || instruction.kind == JUMP;
}
Sources *dependencies(const Instruction *instructions, int count) {
    Sources *out = allocate((size_t)count, sizeof(*out));
    int last[32];
    for (int i = 0; i < 32; ++i)
        last[i] = -1;
    for (int i = 0; i < count; ++i) {
        const Instruction instruction = instructions[i];
        out[i].producer[0] = instruction.rs1 > 0 ? last[instruction.rs1] : -1;
        out[i].producer[1] = instruction.rs2 > 0 ? last[instruction.rs2] : -1;
        if (instruction.rd > 0)
            last[instruction.rd] = i;
    }
    return out;
}
bool id_resolved(Instruction instruction, Variant variant) {
    return (instruction.kind == JUMP && instruction.rs1 < 0) ||
           (control(instruction) && variant.id);
}
int ready_cycle(Instruction consumer, Instruction producer, Timing time, Variant variant) {
    return !variant.forwarding
               ? time.w + 1
               : (producer.kind == LOAD ? time.w : time.m) + id_resolved(consumer, variant);
}
int forwarding_path(Instruction consumer, const Timing *producer, Timing time, Variant variant) {
    if (!producer || !variant.forwarding)
        return 0;
    bool early = id_resolved(consumer, variant);
    int use = time.x - early;
    if (producer->m == use)
        return 1;
    if (!early && producer->w == use)
        return 2;
    return 0;
}
