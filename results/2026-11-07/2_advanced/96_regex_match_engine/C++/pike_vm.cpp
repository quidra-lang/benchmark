#include "regex.hpp"
void PikeVM::add(ThreadList &list, int p, const Captures &captures, int q) {
    if (list.marks[static_cast<size_t>(p)])
        return;
    list.marks.set(static_cast<size_t>(p));
    ++steps;
    const Instruction &instruction = pattern.program[static_cast<size_t>(p)];
    if (instruction.op == "JMP")
        add(list, instruction.x, captures, q);
    else if (instruction.op == "SPLIT") {
        add(list, instruction.x, captures, q);
        add(list, instruction.y, captures, q);
    } else if (instruction.op == "SAVE") {
        Captures c = captures;
        c[static_cast<size_t>(instruction.number)] = q;
        add(list, p + 1, c, q);
    } else if (instruction.op == "ASSERT") {
        if (assertion(instruction.kind, text, q, pattern.flags))
            add(list, p + 1, captures, q);
    } else
        list.threads.push_back({p, captures});
}
std::optional<Captures> PikeVM::search(int start) {
    std::optional<Captures> match;
    ThreadList list;
    for (int q = start;; ++q) {
        if (!match && (!full || q == start))
            add(list, 0, unset_captures(pattern.groups), q);
        ThreadList next;
        for (const PikeThread &thread : list.threads) {
            ++steps;
            const Instruction &instruction = pattern.program[static_cast<size_t>(thread.pc)];
            if (instruction.op == "MATCH") {
                if (!full || q == static_cast<int>(text.size())) {
                    match = thread.captures;
                    break;
                }
            } else if (consumes(instruction, text, q, pattern.flags))
                add(next, thread.pc + 1, thread.captures, q + 1);
        }
        if (q == static_cast<int>(text.size()) || (next.threads.empty() && (match || full)))
            return match;
        list = std::move(next);
    }
}
