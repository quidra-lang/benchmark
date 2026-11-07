#include "simulator.hpp"
Sources dependencies(const std::vector<Instruction> &instructions) {
    std::array<int, 32> last;
    last.fill(-1);
    Sources out;
    for (int i = 0; i < int(instructions.size()); ++i) {
        const Instruction &instruction = instructions[i];
        out.push_back({instruction.rs1 > 0 ? last[instruction.rs1] : -1,
                       instruction.rs2 > 0 ? last[instruction.rs2] : -1});
        if (instruction.rd > 0)
            last[instruction.rd] = i;
    }
    return out;
}
bool id_resolved(const Instruction &instruction, const Variant &variant) {
    return (instruction.kind == jump && instruction.rs1 < 0) ||
           (instruction.control() && variant.id);
}
int ready_cycle(const Instruction &consumer, const Instruction &producer, const Timing &time,
                const Variant &variant) {
    if (!variant.forwarding)
        return time.w + 1;
    return (producer.kind == load ? time.w : time.m) + int(id_resolved(consumer, variant));
}
int forwarding_path(const Instruction &consumer, const Timing *producer, const Timing &time,
                    const Variant &variant) {
    if (!producer || !variant.forwarding)
        return 0;
    const bool early = id_resolved(consumer, variant);
    const int use = time.x - int(early);
    if (producer->m == use)
        return 1;
    if (!early && producer->w == use)
        return 2;
    return 0;
}
