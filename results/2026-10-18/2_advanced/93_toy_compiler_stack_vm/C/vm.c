#include "compiler.h"
ExecutableList flatten(UnitList units) {
    ExecutableList result = {0};
    for (int i = 0; i < units.count; ++i)
        for (int j = 0; j < units.items[i]->code.count; ++j) {
            Instruction instruction = units.items[i]->code.items[j];
            if (jump(instruction.op))
                instruction.a += units.items[i]->start;
            Executable executable = {instruction, i};
            PUSH(result, executable);
        }
    return result;
}
typedef struct {
    NumberList locals;
    int return_address;
} Frame;
static RunResult *fault(RunResult *result, const char *message, int pc, Frame *frames, int depth) {
    result->error = message;
    result->fault_pc = pc;
    for (int i = 0; i < depth; ++i)
        PUSH(result->returns, frames[i].return_address);
    return result;
}
RunResult *execute(UnitList units, int cells, NumberList input) {
    ExecutableList code = flatten(units);
    RunResult *result = ml_alloc(sizeof(*result));
    result->fault_pc = -1;
    result->counts = ml_alloc((size_t)code.count * sizeof(int));
    result->calls = ml_alloc((size_t)units.count * sizeof(int));
    int64_t *globals = ml_alloc((size_t)cells * sizeof(*globals));
    NumberList stack = {0};
    Frame *frames = ml_alloc(100 * sizeof(*frames));
    int depth = 0, pc = 0, read = 0;
    while (true) {
        Executable current = code.items[pc];
        Instruction instruction = current.instruction;
        const char *op = instruction.op;
        if (result->executed == 100000)
            return fault(result, "instruction limit exceeded", pc, frames, depth);
        ++result->executed;
        ++result->counts[pc];
        int next = pc + 1;
        if (equal(op, "PUSH"))
            PUSH(stack, instruction.a);
        else if (equal(op, "POP"))
            --stack.count;
        else if (equal(op, "LOADG"))
            PUSH(stack, globals[instruction.a]);
        else if (equal(op, "STOREG"))
            globals[instruction.a] = stack.items[--stack.count];
        else if (equal(op, "LOADL"))
            PUSH(stack, frames[depth - 1].locals.items[instruction.a]);
        else if (equal(op, "STOREL"))
            frames[depth - 1].locals.items[instruction.a] = stack.items[--stack.count];
        else if (equal(op, "LOADA") || equal(op, "STOREA")) {
            int64_t value = equal(op, "STOREA") ? stack.items[--stack.count] : 0;
            int64_t index = stack.items[--stack.count];
            if (index < 0 || index >= instruction.b)
                return fault(result,
                             ml_format("index %lld out of bounds for array of size %lld",
                                       (long long)index, (long long)instruction.b),
                             pc, frames, depth);
            if (equal(op, "LOADA"))
                PUSH(stack, globals[instruction.a + index]);
            else
                globals[instruction.a + index] = value;
        } else if (word_in("ADD SUB MUL DIV MOD", op)) {
            int64_t b = stack.items[--stack.count];
            int64_t a = stack.items[--stack.count];
            int64_t value = 0;
            if (equal(op, "ADD"))
                value = a + b;
            else if (equal(op, "SUB"))
                value = a - b;
            else if (equal(op, "MUL"))
                value = a * b;
            else {
                if (!b)
                    return fault(result, "division by zero", pc, frames, depth);
                int64_t quotient = a / b;
                value = equal(op, "DIV") ? quotient : a - quotient * b;
            }
            if (value < -2147483648LL || value > 2147483647LL)
                return fault(result, "integer overflow", pc, frames, depth);
            PUSH(stack, value);
        } else if (equal(op, "NEG")) {
            int64_t value = -stack.items[--stack.count];
            if (value < -2147483648LL || value > 2147483647LL)
                return fault(result, "integer overflow", pc, frames, depth);
            PUSH(stack, value);
        } else if (equal(op, "NOT")) {
            int64_t value = stack.items[--stack.count];
            PUSH(stack, value == 0);
        } else if (word_in("LT LE GT GE EQ NE", op)) {
            int64_t b = stack.items[--stack.count];
            int64_t a = stack.items[--stack.count];
            bool answer = equal(op, "LT")   ? a < b
                          : equal(op, "LE") ? a <= b
                          : equal(op, "GT") ? a > b
                          : equal(op, "GE") ? a >= b
                          : equal(op, "EQ") ? a == b
                                            : a != b;
            PUSH(stack, answer);
        } else if (equal(op, "JUMP"))
            next = (int)instruction.a;
        else if (conditional(op)) {
            int64_t value = stack.items[--stack.count];
            if ((equal(op, "JUMPF") && value == 0) || (equal(op, "JUMPT") && value != 0))
                next = (int)instruction.a;
        } else if (equal(op, "CALL")) {
            if (depth == 100)
                return fault(result, "call depth limit exceeded", pc, frames, depth);
            Frame *frame = &frames[depth];
            frame->locals.count = 0;
            int count = (int)instruction.b;
            for (int i = stack.count - count; i < stack.count; ++i)
                PUSH(frame->locals, stack.items[i]);
            stack.count -= count;
            frame->return_address = pc + 1;
            ++depth;
            next = (int)instruction.a;
            int called = 0;
            while (units.items[called]->start != next)
                ++called;
            ++result->calls[called];
            int pair = 0;
            while (pair < result->pairs.count && (result->pairs.items[pair].from != current.unit ||
                                                  result->pairs.items[pair].to != called))
                ++pair;
            if (pair == result->pairs.count) {
                CallPair entry = {current.unit, called, 0};
                PUSH(result->pairs, entry);
            }
            ++result->pairs.items[pair].count;
        } else if (equal(op, "ENTER")) {
            Frame *frame = &frames[depth - 1];
            while (frame->locals.count < (int)instruction.a)
                PUSH(frame->locals, 0);
        } else if (equal(op, "RET") || equal(op, "RETV"))
            next = frames[--depth].return_address;
        else if (equal(op, "READ")) {
            if (read == input.count)
                return fault(result, "read past end of input", pc, frames, depth);
            int64_t value = input.items[read++];
            PUSH(stack, value);
        } else if (equal(op, "PRINT")) {
            int count = (int)instruction.a;
            Text line = {0};
            for (int i = stack.count - count; i < stack.count; ++i) {
                if (i > stack.count - count)
                    text_char(&line, ' ');
                text_add(&line, ml_format("%lld", (long long)stack.items[i]));
            }
            stack.count -= count;
            char *output = text_value(&line);
            PUSH(result->output, output);
        }
        if (stack.count > result->maximum_stack)
            result->maximum_stack = stack.count;
        if (depth > result->maximum_depth)
            result->maximum_depth = depth;
        if (equal(op, "HALT"))
            return result;
        pc = next;
    }
}
