#include <iostream>
#include <string>
#include <array>
#include <sstream>

int value(const std::string &token, const std::array<int, 4> &registers) {
    return token[0] >= 'A' && token[0] <= 'D' ? registers[token[0] - 'A'] : std::stoi(token);
}

int main() {
    std::array<std::string, 17> program = {"SET A 1", "SET B 1", "SET D 8", "MUL A B", "PRINT A",
        "ADD B 1", "SUB D 1", "JNZ D -4", "SET A 1071", "SET B 462", "SET C A", "MOD C B", "SET A B", "SET B C",
        "JNZ B -4", "PRINT A", "HALT"};
    std::array<int, 4> registers{};
    int pc = 0, executed = 0;
    while (pc >= 0 && pc < 17) {
        std::istringstream input(program[pc]);
        std::string op, a, b;
        input >> op >> a >> b;
        ++executed;
        if (op == "HALT")
            break;
        if (op == "JNZ") {
            pc += value(a, registers) != 0 ? std::stoi(b) : 1;
            continue;
        }
        if (op == "PRINT") {
            std::cout << value(a, registers) << '\n';
        } else {
            int r = a[0] - 'A', x = value(b, registers);
            if (op == "SET")
                registers[r] = x;
            else if (op == "ADD")
                registers[r] += x;
            else if (op == "SUB")
                registers[r] -= x;
            else if (op == "MUL")
                registers[r] *= x;
            else if (op == "MOD")
                registers[r] %= x;
        }
        ++pc;
    }
    std::cout << "executed: " << executed << '\n';
}
