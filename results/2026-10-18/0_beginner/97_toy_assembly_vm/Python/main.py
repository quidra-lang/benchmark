program = [
    "SET A 1",
    "SET B 1",
    "SET D 8",
    "MUL A B",
    "PRINT A",
    "ADD B 1",
    "SUB D 1",
    "JNZ D -4",
    "SET A 1071",
    "SET B 462",
    "SET C A",
    "MOD C B",
    "SET A B",
    "SET B C",
    "JNZ B -4",
    "PRINT A",
    "HALT",
]
registers = dict.fromkeys("ABCD", 0)


def value(token):
    return registers[token] if token in registers else int(token)


pc = executed = 0
while 0 <= pc < len(program):
    parts = program[pc].split()
    operation = parts[0]
    executed += 1
    if operation == "HALT":
        break
    if operation == "JNZ":
        pc += int(parts[2]) if value(parts[1]) != 0 else 1
        continue
    if operation == "PRINT":
        print(value(parts[1]))
    else:
        register, operand = parts[1], value(parts[2])
        if operation == "SET":
            registers[register] = operand
        elif operation == "ADD":
            registers[register] += operand
        elif operation == "SUB":
            registers[register] -= operand
        elif operation == "MUL":
            registers[register] *= operand
        elif operation == "MOD":
            registers[register] %= operand
    pc += 1
print(f"executed: {executed}")
