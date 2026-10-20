'use strict';

function attachSources(instructions) {
    const lastWriter = Array(32).fill(null);
    instructions.forEach((instruction, i) => {
        instruction.sources = [];
        for (const slot of ['rs1', 'rs2']) {
            const register = instruction[slot];
            if (register !== null && register !== 0) {
                instruction.sources.push({slot, register, producer: lastWriter[register]});
            }
        }
        if (instruction.rd !== null && instruction.rd !== 0) lastWriter[instruction.rd] = i;
    });
}

function idResolved(instruction, variant) {
    if (instruction.className === 'JUMP') return instruction.rs1 === null || variant.resolution === 'ID';
    return instruction.className === 'BRANCH' && variant.resolution === 'ID';
}

function readyCycle(source, consumer, variant, instructions, times) {
    if (source.producer === null) return null;
    const producer = instructions[source.producer];
    const time = times[source.producer];
    if (!variant.forwarding) return time.W + 1;
    return (producer.className === 'LOAD' ? time.W : time.M) + (idResolved(consumer, variant) ? 1 : 0);
}

function forwardingPath(source, consumerIndex, variant, instructions, times) {
    if (!variant.forwarding || source.producer === null) return 'regfile';
    const early = idResolved(instructions[consumerIndex], variant);
    const usedAt = times[consumerIndex].X - (early ? 1 : 0);
    const producer = times[source.producer];
    if (producer.M === usedAt) return 'ex_mem';
    if (!early && producer.W === usedAt) return 'mem_wb';
    return 'regfile';
}

module.exports = {attachSources, idResolved, readyCycle, forwardingPath};
