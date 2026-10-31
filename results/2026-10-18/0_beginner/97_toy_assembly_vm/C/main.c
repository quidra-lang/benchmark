#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int value(const char *token, const int *registers) {
    return token[0] >= 'A' && token[0] <= 'D' ? registers[token[0] - 'A'] : atoi(token);
}

int main(void) {
    const char *program[] = {"SET A 1", "SET B 1", "SET D 8", "MUL A B", "PRINT A", "ADD B 1", "SUB D 1",
        "JNZ D -4", "SET A 1071", "SET B 462", "SET C A", "MOD C B", "SET A B", "SET B C", "JNZ B -4", "PRINT A",
        "HALT"};
    int registers[4] = {0}, pc = 0, executed = 0;
    while (pc >= 0 && pc < 17) {
        char op[16], a[16] = "", b[16] = "";
        sscanf(program[pc], "%15s %15s %15s", op, a, b);
        executed++;
        if (strcmp(op, "HALT") == 0)
            break;
        if (strcmp(op, "JNZ") == 0) {
            pc += value(a, registers) != 0 ? atoi(b) : 1;
            continue;
        }
        if (strcmp(op, "PRINT") == 0) {
            printf("%d\n", value(a, registers));
        } else {
            int r = a[0] - 'A', x = value(b, registers);
            if (strcmp(op, "SET") == 0)
                registers[r] = x;
            else if (strcmp(op, "ADD") == 0)
                registers[r] += x;
            else if (strcmp(op, "SUB") == 0)
                registers[r] -= x;
            else if (strcmp(op, "MUL") == 0)
                registers[r] *= x;
            else if (strcmp(op, "MOD") == 0)
                registers[r] %= x;
        }
        pc++;
    }
    printf("executed: %d\n", executed);
    return 0;
}
