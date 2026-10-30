#include "compiler.hpp"
std::vector<Executable> flatten(const std::vector<Unit> &units) {
    std::vector<Executable> result;
    for (size_t i = 0; i < units.size(); ++i)
        for (Instruction instruction : units[i].code) {
            if (jump(instruction.op))
                instruction.a += units[i].start;
            result.push_back({instruction, static_cast<int>(i)});
        }
    return result;
}
RunResult execute(const std::vector<Unit> &units, int cells, const std::vector<int64_t> &input) {
    std::vector<Executable> code = flatten(units);
    RunResult result;
    result.counts.resize(code.size());
    std::vector<int64_t> globals(cells), stack;
    std::vector<Frame> frames;
    std::map<int, int> starts;
    for (size_t i = 0; i < units.size(); ++i)
        starts[units[i].start] = static_cast<int>(i);
    int pc = 0;
    size_t read = 0;
    auto pop = [&]() {
        int64_t value = stack.back();
        stack.pop_back();
        return value;
    };
    auto fault = [&](const std::string &message) {
        result.error = message;
        result.fault_pc = pc;
        result.frames = frames;
        return result;
    };
    while (true) {
        const Executable &current = code[pc];
        const Instruction &instruction = current.instruction;
        const std::string &op = instruction.op;
        if (result.executed == 100000)
            return fault("instruction limit exceeded");
        ++result.executed;
        ++result.counts[pc];
        int next = pc + 1;
        if (op == "PUSH")
            stack.push_back(instruction.a);
        else if (op == "POP")
            pop();
        else if (op == "LOADG")
            stack.push_back(globals[instruction.a]);
        else if (op == "STOREG")
            globals[instruction.a] = pop();
        else if (op == "LOADL")
            stack.push_back(frames.back().locals[instruction.a]);
        else if (op == "STOREL")
            frames.back().locals[instruction.a] = pop();
        else if (op == "LOADA" || op == "STOREA") {
            int64_t value = op == "STOREA" ? pop() : 0;
            int64_t index = pop();
            if (index < 0 || index >= instruction.b)
                return fault("index " + std::to_string(index) +
                             " out of bounds for array of size " + std::to_string(instruction.b));
            if (op == "LOADA")
                stack.push_back(globals[instruction.a + index]);
            else
                globals[instruction.a + index] = value;
        } else if (word_in("ADD SUB MUL DIV MOD", op)) {
            int64_t b = pop();
            int64_t a = pop();
            int64_t value = 0;
            if (op == "ADD")
                value = a + b;
            else if (op == "SUB")
                value = a - b;
            else if (op == "MUL")
                value = a * b;
            else {
                if (b == 0)
                    return fault("division by zero");
                int64_t quotient = a / b;
                value = op == "DIV" ? quotient : a - quotient * b;
            }
            if (value < -2147483648LL || value > 2147483647LL)
                return fault("integer overflow");
            stack.push_back(value);
        } else if (op == "NEG") {
            int64_t value = -pop();
            if (value < -2147483648LL || value > 2147483647LL)
                return fault("integer overflow");
            stack.push_back(value);
        } else if (op == "NOT") {
            int64_t value = pop();
            stack.push_back(value == 0);
        } else if (word_in("LT LE GT GE EQ NE", op)) {
            int64_t b = pop();
            int64_t a = pop();
            bool answer = op == "LT"   ? a < b
                          : op == "LE" ? a <= b
                          : op == "GT" ? a > b
                          : op == "GE" ? a >= b
                          : op == "EQ" ? a == b
                                       : a != b;
            stack.push_back(answer);
        } else if (op == "JUMP")
            next = static_cast<int>(instruction.a);
        else if (conditional(op)) {
            int64_t value = pop();
            if ((op == "JUMPF" && value == 0) || (op == "JUMPT" && value != 0))
                next = static_cast<int>(instruction.a);
        } else if (op == "CALL") {
            if (frames.size() == 100)
                return fault("call depth limit exceeded");
            size_t count = static_cast<size_t>(instruction.b);
            Frame frame;
            frame.locals.assign(stack.end() - count, stack.end());
            stack.resize(stack.size() - count);
            frame.return_address = pc + 1;
            frames.push_back(std::move(frame));
            next = static_cast<int>(instruction.a);
            const std::string &called = units[starts.at(next)].name;
            ++result.calls[called];
            ++result.pairs[{units[current.unit].name, called}];
        } else if (op == "ENTER")
            frames.back().locals.resize(static_cast<size_t>(instruction.a), 0);
        else if (op == "RET" || op == "RETV") {
            next = frames.back().return_address;
            frames.pop_back();
        } else if (op == "READ") {
            if (read == input.size())
                return fault("read past end of input");
            stack.push_back(input[read++]);
        } else if (op == "PRINT") {
            size_t count = static_cast<size_t>(instruction.a);
            std::string line;
            for (size_t i = stack.size() - count; i < stack.size(); ++i) {
                if (i > stack.size() - count)
                    line += " ";
                line += std::to_string(stack[i]);
            }
            stack.resize(stack.size() - count);
            result.output.push_back(std::move(line));
        }
        result.maximum_stack = std::max(result.maximum_stack, static_cast<int>(stack.size()));
        result.maximum_depth = std::max(result.maximum_depth, static_cast<int>(frames.size()));
        if (op == "HALT")
            return result;
        pc = next;
    }
}
