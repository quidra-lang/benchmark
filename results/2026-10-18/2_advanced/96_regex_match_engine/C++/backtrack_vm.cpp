#include "regex.hpp"
Captures unset_captures(int groups) { return Captures(static_cast<size_t>(2 * groups + 2), -1); }
struct BacktrackState {
    int pc, position;
    Captures captures;
    std::bitset<300> visited;
};
std::optional<BacktrackResult> BacktrackVM::execute(int pc, int position, Captures captures,
                                                    bool partial) {
    std::vector<BacktrackState> stack;
    stack.push_back({pc, position, std::move(captures), {}});
    while (!stack.empty()) {
        BacktrackState state = std::move(stack.back());
        stack.pop_back();
        int p = state.pc, q = state.position;
        Captures c = std::move(state.captures);
        std::bitset<300> visited = state.visited;
        bool running = true;
        while (running) {
            if (++steps > 200000) {
                aborted = true;
                throw TooManySteps{};
            }
            const Instruction &instruction = pattern.program[static_cast<size_t>(p)];
            if (instruction.op == "CHAR" || instruction.op == "ANY" || instruction.op == "CLASS") {
                if (!consumes(instruction, text, q, pattern.flags))
                    break;
                ++p;
                ++q;
                visited.reset();
            } else if (instruction.op == "SPLIT") {
                if (visited[static_cast<size_t>(p)])
                    break;
                visited.set(static_cast<size_t>(p));
                stack.push_back({instruction.y, q, c, visited});
                p = instruction.x;
            } else if (instruction.op == "JMP")
                p = instruction.x;
            else if (instruction.op == "SAVE") {
                c[static_cast<size_t>(instruction.number)] = q;
                ++p;
            } else if (instruction.op == "ASSERT") {
                if (!assertion(instruction.kind, text, q, pattern.flags))
                    break;
                ++p;
            } else if (instruction.op == "BACKREF") {
                int a = c[static_cast<size_t>(2 * instruction.number)],
                    b = c[static_cast<size_t>(2 * instruction.number + 1)];
                if (a < 0 || b < 0 || a > b || q + b - a > static_cast<int>(text.size()))
                    break;
                bool matches = true;
                for (int j = 0; j < b - a; ++j)
                    if (!char_matches(static_cast<unsigned char>(text[static_cast<size_t>(q + j)]),
                                      static_cast<unsigned char>(text[static_cast<size_t>(a + j)]),
                                      pattern.flags)) {
                        matches = false;
                        break;
                    }
                if (!matches)
                    break;
                if (b > a)
                    visited.reset();
                q += b - a;
                ++p;
            } else if (instruction.op == "LOOK") {
                std::optional<BacktrackResult> result = execute(p + 1, q, c, true);
                if (instruction.kind == "NOT") {
                    if (result)
                        break;
                    p = instruction.x;
                } else {
                    if (!result)
                        break;
                    c = std::move(result->captures);
                    if (instruction.kind == "ATOMIC") {
                        if (result->position > q)
                            visited.reset();
                        q = result->position;
                    }
                    p = instruction.x;
                }
            } else if (instruction.op == "MATCH") {
                if (partial || !full || q == static_cast<int>(text.size()))
                    return BacktrackResult{std::move(c), q};
                running = false;
            }
        }
    }
    return std::nullopt;
}
std::optional<Captures> BacktrackVM::search(int start) {
    int last = static_cast<int>(text.size());
    if (full)
        start = last = 0;
    for (int b = start; b <= last; ++b) {
        std::optional<BacktrackResult> result =
            execute(0, b, unset_captures(pattern.groups), false);
        if (result)
            return std::move(result->captures);
    }
    return std::nullopt;
}
